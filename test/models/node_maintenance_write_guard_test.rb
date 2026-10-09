require "test_helper"

##
# Node#maintenance is a generated column. Rails drops writes to it SILENTLY (an
# `update(maintenance: true)` saves, returns true, and changes nothing), so a stray
# writer is a bug no other test is guaranteed to catch. Every writer must go through
# NodeServices::MaintenanceRequestService (maintenance_requested) or the agent
# projection (maintenance_holds).
#
# This is a textual guard over app/, lib/ and test/. If it trips on something that is
# not a Node write, add the line to ALLOWED with a reason.
class NodeMaintenanceWriteGuardTest < ActiveSupport::TestCase
  WRITE_METHODS = %w[
    update update! update_columns update_column update_attribute update_attribute!
    update_all assign_attributes write_attribute create create! new insert_all
    upsert_all find_or_create_by find_or_create_by! find_or_initialize_by
  ].join("|")

  PATTERNS = [
    # node.maintenance = true
    /\.maintenance\s*=(?![=~>])/,
    # node.update(maintenance: true), Node.create!("maintenance" => ...), update_column(:maintenance, ...)
    /\b(?:#{WRITE_METHODS})\b.*?(?:(?<![\w.])maintenance:\s|["']maintenance["']\s*=>|:maintenance\s*,)/,
    # node[:maintenance] = / self["maintenance"] =
    /\[\s*["':]maintenance["']?\s*\]\s*=(?!=)/,
    # Raw SQL: UPDATE nodes SET maintenance = ...
    /\bSET\b.*(?<![\w.])maintenance\s*=(?!=)/i
  ].freeze

  # [path, line regexp, why]
  ALLOWED = [
    [%r{\Aapp/models/}, /\bFeature\.create!?\(/, "Feature has its own, ordinary maintenance column"],
    [%r{\Atest/services/bootstrap/apply_service_test\.rb\z}, /\["nodes"\]\[\d+\]\["maintenance"\]\s*=/, "a manifest Hash key, mapped to maintenance_requested by the apply"],
    [%r{\Atest/models/node_maintenance_test\.rb\z}, //, "deliberately writes the generated column (and the legacy one in the migration test)"]
  ].freeze

  test "nothing writes the generated Node#maintenance column" do
    root = Rails.root
    offenders = []
    files = Dir.glob(root.join("{app,lib,test}/**/*.{rb,rake,erb,slim,rabl}").to_s)
    files.each do |abs|
      rel = abs.delete_prefix("#{root}/")
      next if rel == "test/models/node_maintenance_write_guard_test.rb"
      File.foreach(abs).with_index(1) do |line, no|
        code = line.strip
        next if code.start_with?("#")
        next unless PATTERNS.any? { |rx| rx.match?(code) }
        next if ALLOWED.any? { |path_rx, line_rx, _| path_rx.match?(rel) && line_rx.match?(code) }
        offenders << "#{rel}:#{no}: #{code}"
      end
    end
    assert offenders.empty?,
      "Writes to the generated Node#maintenance column (silently dropped by Rails). Use " \
      "NodeServices::MaintenanceRequestService, or write maintenance_requested / " \
      "maintenance_holds in tests:\n#{offenders.join("\n")}"
  end

  test "node fixtures do not set maintenance" do
    Dir.glob(Rails.root.join("test/fixtures/nodes*.yml").to_s).each do |f|
      refute_match(/^\s+maintenance:/, File.read(f), "#{f} sets the generated maintenance column")
    end
  end

  test "the guard catches the forms it is meant to" do
    [
      "node.maintenance = true",
      "@node.update(maintenance: true, maintenance_updated: Time.now)",
      "n.update_columns(maintenance: false)",
      "n.update_column(:maintenance, true)",
      'Node.create!(attrs.merge("maintenance" => true))',
      "node[:maintenance] = true",
      'execute "UPDATE nodes SET maintenance = true"'
    ].each do |sample|
      assert PATTERNS.any? { |rx| rx.match?(sample) }, "guard misses: #{sample}"
    end
    [
      "node.maintenance_requested = true",
      "n.update_columns(maintenance_requested: true)",
      'Node.where("disconnected = false OR maintenance = true")',
      "scope :online, -> { where(disconnected: false, maintenance: false) }",
      "return false if node.maintenance",
      "SET maintenance_requested = $1"
    ].each do |sample|
      refute PATTERNS.any? { |rx| rx.match?(sample) }, "guard false positive: #{sample}"
    end
  end
end
