##
# Narrows an EventLog relation from the admin event log filter params.
#
#   EventLog::AdminFilter.new(params).apply(EventLog.all)
#
class EventLog::AdminFilter
  PERIODS = {
    "1h" => ["Last hour", 1.hour],
    "24h" => ["Last 24 hours", 1.day],
    "7d" => ["Last 7 days", 7.days],
    "30d" => ["Last 30 days", 30.days]
  }.freeze

  STATUSES = {
    "active" => "All Active",
    "pending" => "Pending",
    "running" => "Running",
    "completed" => "Completed",
    "cancelled" => "Cancelled",
    "failed" => "Failed"
  }.freeze

  PERFORMER_OPTIONS = {"system" => "System", "user" => "Any user"}.freeze

  # Kinds listed under a family other than their locale prefix, so every backup flow
  # (including the ones cs-agent runs) sits in one group.
  REGROUPED = {
    "volume.backup" => "backup",
    "volume.download" => "backup",
    "volume.restore" => "backup"
  }.freeze

  # Matches the event code on the log itself, on any of its details, or on a system event
  # raised under the same audit. Each branch is backed by an event_code index.
  CODE_MATCH_SQL = <<~SQL.squish
    event_logs.id IN (
      SELECT id FROM event_logs WHERE event_code = :code
      UNION SELECT event_log_id FROM event_log_data WHERE event_code = :code
      UNION SELECT el.id FROM event_logs el
        INNER JOIN system_events se ON se.audit_id = el.audit_id
        WHERE se.event_code = :code
    )
  SQL

  attr_reader :params

  # @param [ActionController::Parameters, Hash] params
  def initialize(params)
    @params = params
  end

  # Every known event kind, grouped by family: `{"node" => [["node.offline", "Node … is offline"], ...]}`
  #
  # @return [Hash<String, Array<Array(String, String)>>]
  def self.kind_groups
    @kind_groups ||= flatten_messages(I18n.t("events.messages", locale: :en))
      .map { |key, msg| [key, msg.to_s.gsub(/%\{\w+\}/, "…")] }
      .sort
      .group_by { |key, _| REGROUPED[key] || key.split(".").first }
  end

  def self.flatten_messages(hash, prefix = nil)
    hash.flat_map do |k, v|
      key = [prefix, k].compact.join(".")
      v.is_a?(Hash) ? flatten_messages(v, key) : [[key, v]]
    end
  end
  private_class_method :flatten_messages

  # @param [ActiveRecord::Relation] scope
  # @return [ActiveRecord::Relation]
  def apply(scope)
    scope = by_status(scope)
    scope = by_kind(scope)
    scope = by_period(scope)
    scope = by_range(scope)
    scope = by_performer(scope)
    scope = scope.where("EXISTS (SELECT 1 FROM event_log_data d WHERE d.event_log_id = event_logs.id)") if flag?(:with_details)
    scope = scope.where("EXISTS (SELECT 1 FROM system_events se WHERE se.audit_id = event_logs.audit_id)") if flag?(:with_system_events)
    scope = scope.where(CODE_MATCH_SQL, code: code) if code.present?
    scope
  end

  # @return [Array<String>] selected kinds; a family is written as `node.*`
  def kinds
    Array(params[:kind]).map(&:to_s).compact_blank
  end

  # Selected kinds missing from the catalog (e.g. from a hand-edited URL), kept so the
  # form can still show them as selected.
  #
  # @return [Array<String>]
  def unknown_kinds
    known = self.class.kind_groups.flat_map { |family, ks| ["#{family}.*", *ks.map(&:first)] }
    kinds - known
  end

  def status = params[:status].to_s

  def period = params[:period].to_s

  def timerange = params[:timerange].to_s.strip

  def performed_by = params[:performed_by].to_s

  # What the "Performed by" input shows for the current value; blank means anyone.
  #
  # @return [String]
  def performed_by_label
    return PERFORMER_OPTIONS[performed_by] if PERFORMER_OPTIONS.key?(performed_by)
    user = User.find_by(id: performed_by.to_i) if performed_by.present?
    user ? user.full_name_with_email : ""
  end

  def code = params[:code].to_s.strip

  def flag?(name) = ActiveModel::Type::Boolean.new.cast(params[name]) || false

  # The custom date range was given but could not be parsed, so it was ignored.
  def invalid_range?
    timerange.present? && date_range.nil?
  end

  private

  def by_status(scope)
    case status
    when "active" then scope.active
    when "failed" then scope.failed
    when *STATUSES.keys then scope.where(status: status)
    else scope
    end
  end

  def by_kind(scope)
    return scope if kinds.empty?
    families, exact = kinds.partition { |k| k.end_with?(".*") }
    locale = EventLog.arel_table[:locale]
    # A family also matches a bare key of the same name (e.g. `unknown`).
    # Kinds regrouped into a family match it; those regrouped out of it do not.
    clauses = families.map do |f|
      family = f.delete_suffix(".*")
      clause = locale.eq(family).or(locale.matches("#{EventLog.sanitize_sql_like(family)}.%", nil, true))
      moved_out = REGROUPED.keys.select { |k| k.start_with?("#{family}.") && REGROUPED[k] != family }
      clause = clause.and(locale.not_in(moved_out)) if moved_out.any?
      moved_in = REGROUPED.select { |_, g| g == family }.keys
      moved_in.any? ? clause.or(locale.in(moved_in)) : clause
    end
    clauses << locale.in(exact) if exact.any?
    scope.where(clauses.reduce(:or))
  end

  # A valid custom range takes precedence over the preset.
  def by_period(scope)
    return scope if date_range
    duration = PERIODS.dig(period, 1)
    duration ? scope.where(event_logs: {created_at: duration.ago..}) : scope
  end

  # `timerange` comes from the easepick range picker: "YYYY-MM-DD - YYYY-MM-DD", in UTC.
  def by_range(scope)
    range = date_range
    range ? scope.where(event_logs: {created_at: range}) : scope
  end

  def date_range
    return @date_range if defined?(@date_range)
    @date_range = begin
      first, last = timerange.split(" - ", 2).map { |d| Date.iso8601(d.strip) }
      last ||= first
      first, last = last, first if last < first
      first.beginning_of_day...last.next_day.beginning_of_day
    rescue ArgumentError, NoMethodError
      nil
    end
  end

  def by_performer(scope)
    by_user = "EXISTS (SELECT 1 FROM audits a WHERE a.id = event_logs.audit_id AND a.user_id IS NOT NULL)"
    case performed_by
    when "" then scope
    when "system" then scope.where("NOT #{by_user}")
    when "user" then scope.where(by_user)
    else
      scope.where("EXISTS (SELECT 1 FROM audits a WHERE a.id = event_logs.audit_id AND a.user_id = ?)", performed_by.to_i)
    end
  end
end
