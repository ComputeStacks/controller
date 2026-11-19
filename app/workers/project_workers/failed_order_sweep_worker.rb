module ProjectWorkers
  ##
  # Clean up after failed orders.
  #
  # A failed order is reported, never rolled back, so the project an order created stays behind
  # when the order fails. Found in production on 2026-10-21: 43 such projects on one account,
  # 40 of them completely empty.
  #
  # 1. DELETES a project only when ALL of these hold, checked again for that one project right
  #    before it is deleted:
  #    * a failed order created it (the order has `deployment_id` = the project and no
  #      `order_data.project.id` -- BuildOrderService records that id only for an existing project);
  #    * every order of the project failed, and none was updated in the last 24 hours;
  #    * the project is more than 24 hours old and is not already being deleted;
  #    * it has no services, containers, SFTP containers, volumes (any state, to_trash included),
  #      collaborators, SSH keys or notifiers, and still has its owner;
  #    * it has no running or pending event, and no event created or updated in the last 24 hours.
  #    At most MAX_DELETIONS per run. Deletion takes the same path as the admin Delete button,
  #    acting as the owner (TrashProject requires a user who can delete the project). Before that,
  #    every order of the project gets its `failure_reason` (backfilled from its provisioning
  #    event for orders that failed before it was recorded) and a `deleted_project` record: the
  #    order is the durable record, since the project's events are pruned once it is gone.
  #    One new SystemEvent per run that deleted anything.
  #
  # 2. REPORTS (never deletes), one SystemEvent per kind updated in place each run (same pattern as
  #    NetworkWorkers::ProjectNetworkIntegrityWorker; nothing is written while a kind is clean):
  #    * projects that would be deleted, but are not empty (or have no owner, or a running event);
  #    * orders stuck in processing or pending for over an hour;
  #    * partial failures: failed orders of the last 7 days whose provisioning event's services
  #      still exist.
  class FailedOrderSweepWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    # SystemEvent: the projects one run deleted (a new row for every run that deleted anything).
    DELETED_EVENT_CODE = "72dbd377406255d1"

    # Event detail on the project's trash event: removed by this cleanup, and why.
    TRASH_DETAIL_EVENT_CODE = "0e800b08255d5de5"

    # SystemEvent: projects left by failed orders that are not empty, so were not deleted.
    NOT_EMPTY_EVENT_CODE = "e73c46fea5ab1d93"

    # SystemEvent: orders stuck in processing or pending.
    STUCK_ORDER_EVENT_CODE = "5cdda6c79f14cdc4"

    # SystemEvent: failed orders that left services behind.
    PARTIAL_FAILURE_EVENT_CODE = "62989e6b60d0aa12"

    # SystemEvent: projects this sweep deleted that still exist (the trash did not finish).
    STUCK_DELETION_EVENT_CODE = "9d4e2b7f61c03a58"

    # Unexpected error (reported to the exception tracker).
    ERROR_EVENT_CODE = "2f0604eae9f39f49"

    # ProcessOrderWorker's event, and the details it records a failure with.
    PROVISION_EVENT_CODE = "0a3af01a3384fa10"
    ORDER_ERROR_DETAIL_CODE = "1adee2a19e284b32"
    ORDER_FATAL_DETAIL_CODE = "88b1a3af8b282f4f"

    # Admin::DeploymentsController#destroy's trash event.
    TRASH_EVENT_CODE = "20cd984da4da8963"

    # How long a project left by a failed order must have been quiet before it is deleted.
    GRACE = 24.hours

    # Deletions per run, so a logic error cannot delete much; the rest wait for the next run.
    MAX_DELETIONS = 10

    # How many findings to list on a report SystemEvent; the total is always recorded.
    MAX_LISTED = 100

    STUCK_AFTER = 1.hour
    PARTIAL_WINDOW = 7.days

    # The order created its project: BuildOrderService writes `project.id` only for an existing one.
    CREATED_PROJECT_SQL = "jsonb_typeof(orders.order_data::jsonb -> 'project') = 'object' " \
      "AND (orders.order_data::jsonb -> 'project' ->> 'id') IS NULL"

    def perform
      check { delete_empty_orphans }
      check { report_orphans_not_empty }
      check { report_stuck_orders }
      check { report_partial_failures }
      check { report_stuck_deletions }
    end

    private

    # Each part runs on its own, so one that raises does not stop the others.
    def check
      yield
    rescue => e
      ExceptionAlertService.new(e, ERROR_EVENT_CODE).perform
    end

    ##
    # Part 1: delete empty projects left by failed orders.

    def delete_empty_orphans
      deleted = []
      # Walk every candidate until the cap is reached, rather than only the first few: a project
      # that keeps raising must not hold a slot (and block the ones behind it) every run.
      empty_orphan_ids.each do |project_id|
        break if deleted.length >= MAX_DELETIONS
        begin
          entry = delete_orphan(project_id)
          deleted << entry if entry
        rescue => e
          ExceptionAlertService.new(e, ERROR_EVENT_CODE).perform
        end
      end
      record_deletions(deleted)
    end

    # @return [Array<Integer>] project ids that qualify for deletion, oldest first
    def empty_orphan_ids(projects = Deployment.all)
      cutoff = GRACE.ago
      ids = orphans(projects, cutoff).order(:id).pluck(:id)
      return [] if ids.empty?
      blocked = blockers(ids)
      quiet = ids - recently_active_ids(ids, cutoff)
      quiet.reject { |id| blocked.key?(id) }
    end

    ##
    # Projects a failed order created, where every order failed and has been settled for the
    # grace period, the project is older than that, and it is not already being deleted.
    # Says nothing about what the project holds (see #blockers).
    def orphans(projects, cutoff)
      orders = Order.unscoped.where.not(deployment_id: nil)
      projects
        .where(id: orders.where(status: "failed").where(CREATED_PROJECT_SQL).select(:deployment_id))
        .where.not(id: orders.where.not(status: "failed").select(:deployment_id))
        .where.not(id: orders.where(updated_at: cutoff..).select(:deployment_id))
        .where(created_at: ...cutoff)
        .where.not(status: "deleting")
    end

    ##
    # What stops each project from being deleted: anything a customer, or a build, put in it.
    #
    # @param project_ids [Array<Integer>]
    # @return [Hash{Integer => Array<String>}] only the projects that have something
    def blockers(project_ids)
      found = {}
      add = ->(reason, ids) { ids.each { |id| (found[id] ||= []) << reason } }
      add.call "services", Deployment::ContainerService.where(deployment_id: project_ids).distinct.pluck(:deployment_id)
      add.call "containers", Deployment::Container.joins(:service)
        .where(deployment_container_services: {deployment_id: project_ids})
        .distinct.pluck("deployment_container_services.deployment_id")
      add.call "SFTP containers", Deployment::Sftp.where(deployment_id: project_ids).distinct.pluck(:deployment_id)
      add.call "volumes", Volume.where(deployment_id: project_ids).distinct.pluck(:deployment_id)
      add.call "collaborators", DeploymentCollaborator.where(deployment_id: project_ids).distinct.pluck(:deployment_id)
      add.call "SSH keys", Deployment::SshKey.where(deployment_id: project_ids).distinct.pluck(:deployment_id)
      add.call "notifiers", ProjectNotification.where(deployment_id: project_ids).distinct.pluck(:deployment_id)
      add.call "no owner", Deployment.where(id: project_ids).where.missing(:user).pluck(:id)
      add.call "running or pending events", project_event_links(project_ids).merge(EventLog.active)
        .distinct.pluck("deployments_event_logs.deployment_id")
      found
    end

    # Projects with an event created or updated within the grace period: still in use, so left
    # alone until it is quiet (not reported).
    def recently_active_ids(project_ids, cutoff)
      project_event_links(project_ids)
        .where("event_logs.created_at >= :cutoff OR event_logs.updated_at >= :cutoff", cutoff: cutoff)
        .distinct.pluck("deployments_event_logs.deployment_id")
    end

    def project_event_links(project_ids)
      EventLog
        .joins("INNER JOIN deployments_event_logs ON deployments_event_logs.event_log_id = event_logs.id")
        .where(deployments_event_logs: {deployment_id: project_ids})
    end

    ##
    # Delete one project, if it still qualifies.
    #
    # @return [Hash, nil] what was deleted
    def delete_orphan(project_id)
      # Check again, for this project alone: an order or a change may have arrived since.
      return nil unless empty_orphan_ids(Deployment.where(id: project_id)) == [project_id]
      project = Deployment.find_by(id: project_id)
      owner = project&.user
      return nil if owner.nil?

      orders = Order.unscoped.where(deployment_id: project.id).order(:created_at).to_a
      return nil if orders.empty? || orders.any? { |o| o.status != "failed" }

      reasons = orders.to_h { |o| [o.id, failure_reason_for(o)] }
      deleted_at = Time.now.utc
      event = nil
      ActiveRecord::Base.transaction do
        # The orders keep the record: the project's events are pruned once it is gone.
        orders.each do |order|
          data = order.order_data.is_a?(Hash) ? order.order_data : {}
          # update_columns: updated_at stays the time the order failed.
          order.update_columns(order_data: data.merge(
            "failure_reason" => reasons[order.id],
            "deleted_project" => {
              "id" => project.id,
              "name" => project.name,
              "owner_id" => owner.id,
              "deleted_at" => deleted_at.iso8601,
              "by" => "failed-order cleanup"
            }
          ))
        end

        # The same path as Admin::DeploymentsController#destroy. The audit names this cleanup,
        # so the deletion does not read as the owner deleting their own project.
        audit = Audit.create!(
          event: "deleted",
          rel_id: project.id,
          rel_model: "Deployment",
          ip_addr: "127.0.0.1",
          user: owner,
          raw_data: {name: project.name, by: "failed-order cleanup", order_ids: orders.map(&:id)}
        )
        event = EventLog.create!(
          locale: "deployment.trash",
          locale_keys: {project: project.name},
          event_code: TRASH_EVENT_CODE,
          audit: audit,
          status: "pending"
        )
        event.event_details.create!(
          event_code: TRASH_DETAIL_EVENT_CODE,
          data: "Removed by the failed-order cleanup: this project was created by a failed order " \
            "and has been empty for #{GRACE.inspect}.\n\n" +
            reasons.map { |id, reason| "Order #{id}: #{reason}" }.join("\n")
        )
        raise ActiveRecord::RecordNotSaved, "Unable to mark project #{project.id} as trashed" unless project.mark_trashed!
        event.deployments << project
      end
      ProjectWorkers::TrashProjectWorker.perform_async project.global_id.to_s, event.global_id.to_s

      {
        id: project.id,
        name: project.name,
        owner_id: owner.id,
        event_id: event.id,
        orders: reasons.map { |id, reason| {id: id, failure_reason: reason} }
      }
    end

    ##
    # Why an order failed: what it recorded itself, else (orders that failed before it recorded
    # that) what its provisioning event says.
    #
    # @return [String]
    def failure_reason_for(order)
      recorded = order.order_data.is_a?(Hash) ? order.order_data["failure_reason"] : nil
      return recorded if recorded.present?

      event = EventLog
        .where(event_code: PROVISION_EVENT_CODE, audit_id: Audit.where(rel_model: "Order", rel_uuid: order.id).select(:id))
        .order(created_at: :desc)
        .first
      return "No failure reason was recorded" if event.nil?

      details = event.event_details.order(:created_at)
      reason = details.where(event_code: ORDER_ERROR_DETAIL_CODE).last&.data&.delete_prefix("ProcessOrderService error output:")
      reason = details.where(event_code: ORDER_FATAL_DETAIL_CODE).last&.data if reason.blank?
      reason = event.state_reason if reason.blank?
      return "No failure reason was recorded" if reason.blank?
      reason.split("\n").map(&:strip).reject(&:blank?).join("; ").truncate(1_000)
    end

    # A new SystemEvent for every run that deleted anything, so each run's record is kept.
    def record_deletions(deleted)
      return if deleted.empty?
      SystemEvent.create!(
        message: "Failed-order cleanup: deleted #{deleted.length} empty project(s) left behind by failed orders",
        log_level: "info",
        event_code: DELETED_EVENT_CODE,
        data: {projects: deleted}
      )
    end

    ##
    # Part 2: reports.

    def report_orphans_not_empty
      ids = orphans(Deployment.all, GRACE.ago).order(:id).pluck(:id)
      blocked = ids.empty? ? {} : blockers(ids)
      listed_ids = blocked.keys.sort.first(MAX_LISTED)
      projects = Deployment.where(id: listed_ids).order(:id).pluck(:id, :name, :user_id)
      report(
        NOT_EMPTY_EVENT_CODE,
        blocked.length,
        "project(s) left behind by failed orders are not empty, so were not deleted",
        projects.map { |id, name, owner_id|
          "Project #{name} (#{id}), owner #{owner_id.inspect}: #{blocked[id].join(", ")}"
        }
      )
    end

    def report_stuck_orders
      now = Time.current
      orders = Order.unscoped.where(status: %w[processing pending]).where(updated_at: ...STUCK_AFTER.ago)
      report(
        STUCK_ORDER_EVENT_CODE,
        orders.count,
        "order(s) have been processing or pending for over an hour",
        orders.order(:updated_at).limit(MAX_LISTED).pluck(:id, :status, :deployment_id, :user_id, :updated_at).map { |id, status, project_id, user_id, updated_at|
          "Order #{id} (#{status}), project #{project_id.inspect}, user #{user_id.inspect}, " \
            "#{((now - updated_at) / 1.hour).floor} hour(s)"
        }
      )
    end

    # A failed order is a partial failure when any service linked to its provisioning event
    # still exists. A failed add-on order that built nothing is not one.
    def report_partial_failures
      rows = Deployment::ContainerService
        .joins("INNER JOIN deployment_container_services_event_logs dcsel ON dcsel.deployment_container_service_id = deployment_container_services.id")
        .joins("INNER JOIN event_logs ON event_logs.id = dcsel.event_log_id")
        .joins("INNER JOIN audits ON audits.id = event_logs.audit_id")
        .joins("INNER JOIN orders ON orders.id = audits.rel_uuid")
        .joins(:deployment)
        .where(event_logs: {event_code: PROVISION_EVENT_CODE}, audits: {rel_model: "Order"})
        .where(orders: {status: "failed", updated_at: PARTIAL_WINDOW.ago..})
        .distinct
        .pluck("orders.id", "deployments.id", "deployments.user_id", "deployment_container_services.id", "deployment_container_services.label")

      by_order = rows.group_by(&:first)
      order_ids = by_order.keys.sort.first(MAX_LISTED)
      reasons = Order.unscoped.where(id: order_ids).to_h { |o| [o.id, o.data[:failure_reason].presence || "not recorded"] }
      report(
        PARTIAL_FAILURE_EVENT_CODE,
        by_order.length,
        "failed order(s) in the last #{PARTIAL_WINDOW.inspect} left services behind",
        order_ids.map { |order_id|
          _, project_id, owner_id, = by_order[order_id].first
          services = by_order[order_id].map { |row| "#{row[4]} (#{row[3]})" }.uniq
          "Order #{order_id}, project #{project_id}, owner #{owner_id.inspect}, " \
            "services #{services.join(", ")}: #{reasons[order_id]}"
        }
      )
    end

    # Projects this sweep marked for deletion that still exist an hour later. Their orders
    # already say they were deleted, and the project sits in `deleting`, which this sweep skips;
    # without this nobody would hear that the trash never finished.
    def report_stuck_deletions
      orders = Order.unscoped
        .where.not(deployment_id: nil)
        .where("(orders.order_data::jsonb -> 'deleted_project' ->> 'deleted_at')::timestamptz < ?", STUCK_AFTER.ago)
      project_ids = orders.distinct.pluck(:deployment_id)
      projects = Deployment.where(id: project_ids).order(:id).limit(MAX_LISTED).pluck(:id, :name, :status, :user_id)
      report(
        STUCK_DELETION_EVENT_CODE,
        Deployment.where(id: project_ids).count,
        "project(s) deleted by the failed-order cleanup still exist; their deletion did not finish",
        projects.map { |id, name, status, owner_id|
          "Project #{name} (#{id}), status #{status}, owner #{owner_id.inspect}"
        }
      )
    end

    ##
    # Find-or-create the one SystemEvent for this code and record the latest findings on it.
    # Nothing at all when there are no findings.
    def report(event_code, total, summary, items)
      return if total.zero?

      message = "Failed orders: #{total} #{summary}"
      se = SystemEvent.find_by(event_code: event_code)
      if se.nil?
        se = SystemEvent.create!(
          message: message,
          log_level: "warn",
          data: {count: 0, first_seen: Time.now.utc},
          event_code: event_code
        )
      end
      previous = se.data.is_a?(Hash) ? se.data : {}
      se.update!(
        message: message,
        data: previous.merge(
          count: previous[:count].to_i + 1,
          total: total,
          items: items,
          last_seen: Time.now.utc
        )
      )
    end
  end
end
