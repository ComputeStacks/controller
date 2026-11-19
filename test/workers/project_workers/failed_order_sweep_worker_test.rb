require "test_helper"
require "minitest/mock"

class ProjectWorkers::FailedOrderSweepWorkerTest < ActiveSupport::TestCase
  W = ProjectWorkers::FailedOrderSweepWorker

  setup do
    SystemEvent.where(event_code: [
      W::DELETED_EVENT_CODE, W::NOT_EMPTY_EVENT_CODE, W::STUCK_ORDER_EVENT_CODE, W::PARTIAL_FAILURE_EVENT_CODE,
      W::STUCK_DELETION_EVENT_CODE
    ]).delete_all
    Sidekiq::Worker.clear_all
    @owner = users(:user)
    @project, @order = orphan
  end

  # A project its failed order created, with nothing in it, everything three days old.
  def orphan(name: "orphan", age: 3.days, reason: "mariadb broke")
    project = Deployment.create!(name: name, user: @owner)
    data = {"project" => {"id" => nil, "name" => name, "skip_ssh" => false}, "raw_order" => []}
    data["failure_reason"] = reason if reason
    order = Order.create!(user: @owner, deployment: project, status: "failed", order_data: data)
    project.update_columns(created_at: age.ago, updated_at: age.ago)
    order.update_columns(created_at: age.ago, updated_at: age.ago)
    [project, order]
  end

  # The provisioning event ProcessOrderWorker records for an order, linked the same way.
  def provision_event(order, age: 3.days)
    audit = Audit.create!(event: "updated", rel_model: "Order", rel_uuid: order.id, user: order.user, ip_addr: "127.0.0.1")
    event = EventLog.create!(locale: "order.provision", event_code: W::PROVISION_EVENT_CODE, audit: audit, status: "failed")
    event.deployments << order.deployment if order.deployment
    event.update_columns(created_at: age.ago, updated_at: age.ago)
    event
  end

  def deleted?(project)
    project.reload.status == "deleting"
  end

  def not_empty_items
    SystemEvent.find_by!(event_code: W::NOT_EMPTY_EVENT_CODE).data[:items].join("\n")
  end

  # --- deleting ---------------------------------------------------------------------------

  test "deletes an empty project its failed order left behind, the way the admin Delete button does" do
    W.new.perform

    assert deleted?(@project)
    job = ProjectWorkers::TrashProjectWorker.jobs.last
    refute_nil job
    assert_equal @project.global_id.to_s, job["args"][0]

    event = GlobalID::Locator.locate(job["args"][1])
    assert_equal "deployment.trash", event.locale
    assert_equal "20cd984da4da8963", event.event_code
    assert_includes event.deployments, @project
    assert_equal @owner, event.audit.user
    assert_equal "deleted", event.audit.event
    assert_equal "failed-order cleanup", event.audit.raw_data[:by]
    assert_equal [@order.id], event.audit.raw_data[:order_ids]
    detail = event.event_details.find_by!(event_code: W::TRASH_DETAIL_EVENT_CODE)
    assert_match "failed-order cleanup", detail.data
    assert_match "Order #{@order.id}: mariadb broke", detail.data

    deleted = @order.reload.order_data["deleted_project"]
    assert_equal @project.id, deleted["id"]
    assert_equal "orphan", deleted["name"]
    assert_equal @owner.id, deleted["owner_id"]
    assert_equal "failed-order cleanup", deleted["by"]
    refute_nil deleted["deleted_at"]
    assert_equal "mariadb broke", @order.order_data["failure_reason"]
    assert_operator @order.updated_at, :<, 1.day.ago, "the order keeps the time it failed"

    se = SystemEvent.find_by!(event_code: W::DELETED_EVENT_CODE)
    assert_equal "info", se.log_level
    assert_equal [@project.id], se.data[:projects].map { |p| p[:id] }
    assert_equal @order.id, se.data[:projects].first[:orders].first[:id]
  end

  test "leaves the fixture projects, which have no failed orders, alone" do
    W.new.perform

    refute deleted?(deployments(:project_test))
    refute deleted?(deployments(:user_project_test))
  end

  test "backfills the failure reason of an order that failed before it was recorded" do
    project, order = orphan(name: "old", reason: nil)
    event = provision_event(order)
    event.event_details.create!(event_code: "1adee2a19e284b32", data: "ProcessOrderService error output:\n\nimage is gone\nno capacity")
    event.update_columns(state_reason: "Failed to provision all resources")

    W.new.perform

    assert deleted?(project)
    assert_equal "image is gone; no capacity", order.reload.order_data["failure_reason"]
    assert_equal project.id, order.order_data["deleted_project"]["id"]
  end

  test "backfills from the event's state reason when there is no error output" do
    project, order = orphan(name: "old", reason: nil)
    provision_event(order).update_columns(state_reason: "Over quota")

    W.new.perform

    assert deleted?(project)
    assert_equal "Over quota", order.reload.order_data["failure_reason"]
  end

  test "writes the deleted project onto every order of the project" do
    addon = Order.create!(user: @owner, deployment: @project, status: "failed",
      order_data: {"project" => {"id" => @project.id}, "raw_order" => [], "failure_reason" => "redis broke"})
    addon.update_columns(created_at: 2.days.ago, updated_at: 2.days.ago)

    W.new.perform

    assert deleted?(@project)
    assert_equal @project.id, addon.reload.order_data["deleted_project"]["id"]
    assert_equal @project.id, @order.reload.order_data["deleted_project"]["id"]
  end

  test "deletes at most ten projects a run" do
    11.times { |i| orphan(name: "orphan #{i}") } # 12 with the one from setup

    W.new.perform

    assert_equal 10, ProjectWorkers::TrashProjectWorker.jobs.size
    assert_equal 10, Deployment.where(status: "deleting").count
    assert_equal 10, SystemEvent.find_by!(event_code: W::DELETED_EVENT_CODE).data[:projects].length

    W.new.perform

    assert_equal 12, Deployment.where(status: "deleting").count
  end

  test "a project that keeps raising does not hold a slot" do
    10.times { |i| orphan(name: "orphan #{i}") } # 11 with the one from setup; setup's is oldest by id
    worker = W.new
    real = worker.method(:delete_orphan)
    worker.stub(:delete_orphan, ->(id) { raise "boom" if id == @project.id; real.call(id) }) do
      ExceptionAlertService.stub(:new, ->(*) { Struct.new(:perform).new(nil) }) do
        worker.perform
      end
    end

    assert_equal 10, Deployment.where(status: "deleting").count
    refute deleted?(@project)
  end

  test "reports a project it deleted that still exists an hour later" do
    W.new.perform
    assert deleted?(@project)
    @order.reload
    data = @order.order_data
    data["deleted_project"]["deleted_at"] = 2.hours.ago.iso8601
    @order.update_columns(order_data: data)

    W.new.perform

    se = SystemEvent.find_by!(event_code: W::STUCK_DELETION_EVENT_CODE)
    assert_equal 1, se.data[:total]
    assert_match "(#{@project.id}), status deleting", se.data[:items].join("\n")
  end

  test "writes a new SystemEvent for every run that deleted something, and none otherwise" do
    W.new.perform
    W.new.perform # nothing left
    orphan(name: "second")
    W.new.perform

    assert_equal 2, SystemEvent.where(event_code: W::DELETED_EVENT_CODE).count
  end

  test "checks each project again right before deleting it" do
    # Something arrives after the list of candidates was built: the first look is stale.
    deployment_container_services(:user_nginx).update_columns(deployment_id: @project.id)
    worker = W.new
    original = worker.method(:blockers)
    calls = 0
    worker.stub(:blockers, ->(ids) { (calls += 1) == 1 ? {} : original.call(ids) }) do
      worker.perform
    end

    assert_operator calls, :>=, 2
    refute deleted?(@project)
    assert_empty ProjectWorkers::TrashProjectWorker.jobs
    assert_nil SystemEvent.find_by(event_code: W::DELETED_EVENT_CODE)
  end

  # --- each condition on its own keeps the project ------------------------------------------

  test "keeps a project created less than 24 hours ago" do
    @project.update_columns(created_at: 23.hours.ago)

    W.new.perform

    refute deleted?(@project)
  end

  test "keeps a project whose newest order was updated less than 24 hours ago" do
    newer = Order.create!(user: @owner, deployment: @project, status: "failed",
      order_data: {"project" => {"id" => @project.id}, "raw_order" => []})
    newer.update_columns(updated_at: 2.hours.ago)

    W.new.perform

    refute deleted?(@project)
  end

  test "keeps a project with any order that did not fail" do
    %w[completed processing pending open awaiting_payment cancelled].each do |status|
      other = Order.create!(user: @owner, deployment: @project, status: status,
        order_data: {"project" => {"id" => @project.id}, "raw_order" => []})
      other.update_columns(created_at: 3.days.ago, updated_at: 3.days.ago)

      W.new.perform

      refute deleted?(@project), "deleted with a #{status} order"
      other.delete
    end
  end

  test "keeps a project a failed order did not create" do
    @order.update_columns(order_data: @order.order_data.merge("project" => {"id" => @project.id}))

    W.new.perform

    refute deleted?(@project)
  end

  test "keeps a project with a service, and reports it" do
    deployment_container_services(:user_nginx).update_columns(deployment_id: @project.id)

    W.new.perform

    refute deleted?(@project)
    se = SystemEvent.find_by!(event_code: W::NOT_EMPTY_EVENT_CODE)
    assert_equal "warn", se.log_level
    assert_equal 1, se.data[:total]
    assert_match "Project orphan (#{@project.id}), owner #{@owner.id}: services", not_empty_items
  end

  test "keeps a project with a container, and reports it" do
    service = deployment_container_services(:user_nginx)
    refute_empty service.containers
    service.update_columns(deployment_id: @project.id)

    W.new.perform

    refute deleted?(@project)
    assert_match "containers", not_empty_items
  end

  test "keeps a project with an SFTP container, and reports it" do
    deployment_sftp(:user_project_test_testone).update_columns(deployment_id: @project.id)

    W.new.perform

    refute deleted?(@project)
    assert_match "SFTP containers", not_empty_items
  end

  test "keeps a project with a volume, even one being trashed, and reports it" do
    volumes(:user_nginx_web).update_columns(deployment_id: @project.id, to_trash: true)

    W.new.perform

    refute deleted?(@project)
    assert_match "volumes", not_empty_items
  end

  test "keeps a project with a collaborator, and reports it" do
    DeploymentCollaborator.insert!({deployment_id: @project.id, user_id: users(:admin).id, active: false})

    W.new.perform

    refute deleted?(@project)
    assert_match "collaborators", not_empty_items
  end

  test "keeps a project with an SSH key, and reports it" do
    Deployment::SshKey.insert!({deployment_id: @project.id, label: "laptop", pubkey: "ssh-ed25519 AAAAC3Nz test"})

    W.new.perform

    refute deleted?(@project)
    assert_match "SSH keys", not_empty_items
  end

  test "keeps a project with a notifier, and reports it" do
    project_notifications(:one).update_columns(deployment_id: @project.id)

    W.new.perform

    refute deleted?(@project)
    assert_match "notifiers", not_empty_items
  end

  test "keeps a project whose owner is gone, and reports it" do
    @project.update_columns(user_id: User.maximum(:id) + 100)

    W.new.perform

    refute deleted?(@project)
    assert_match "no owner", not_empty_items
  end

  test "keeps a project with an event from the last 24 hours, without reporting it" do
    event = EventLog.create!(locale: "service.trash", status: "completed")
    event.deployments << @project

    W.new.perform

    refute deleted?(@project)
    assert_nil SystemEvent.find_by(event_code: W::NOT_EMPTY_EVENT_CODE)
  end

  test "keeps a project with an older event that is still running, and reports it" do
    event = EventLog.create!(locale: "service.trash", status: "running")
    event.deployments << @project
    event.update_columns(created_at: 2.days.ago, updated_at: 2.days.ago)

    W.new.perform

    refute deleted?(@project)
    assert_match "running or pending events", not_empty_items
  end

  test "keeps a project that is already being deleted" do
    @project.update_columns(status: "deleting")

    W.new.perform

    assert_empty ProjectWorkers::TrashProjectWorker.jobs
  end

  # --- reports ----------------------------------------------------------------------------

  test "a report is updated in place on the next run" do
    deployment_container_services(:user_nginx).update_columns(deployment_id: @project.id)

    W.new.perform
    W.new.perform

    assert_equal 1, SystemEvent.where(event_code: W::NOT_EMPTY_EVENT_CODE).count
    se = SystemEvent.find_by!(event_code: W::NOT_EMPTY_EVENT_CODE)
    assert_equal 2, se.data[:count]
    refute_nil se.data[:first_seen]
    refute_nil se.data[:last_seen]
  end

  test "reports orders stuck in processing or pending for over an hour" do
    stuck = Order.create!(user: @owner, status: "processing", order_data: {"project" => {"id" => nil}, "raw_order" => []})
    stuck.update_columns(updated_at: 3.hours.ago)
    waiting = Order.create!(user: @owner, status: "pending", order_data: {"project" => {"id" => nil}, "raw_order" => []})
    waiting.update_columns(updated_at: 2.hours.ago)
    fresh = Order.create!(user: @owner, status: "processing", order_data: {"project" => {"id" => nil}, "raw_order" => []})
    fresh.update_columns(updated_at: 10.minutes.ago)

    W.new.perform

    se = SystemEvent.find_by!(event_code: W::STUCK_ORDER_EVENT_CODE)
    assert_equal "warn", se.log_level
    assert_equal 2, se.data[:total]
    items = se.data[:items].join("\n")
    assert_match "Order #{stuck.id} (processing)", items
    assert_match "3 hour(s)", items
    assert_match "Order #{waiting.id} (pending)", items
    refute_match fresh.id, items
  end

  test "reports a failed order whose services are still there, and not one that built nothing" do
    project = deployments(:project_test)
    service = deployment_container_services(:pma)
    partial = Order.create!(user: users(:admin), deployment: project, status: "failed",
      order_data: {"project" => {"id" => nil}, "raw_order" => [], "failure_reason" => "mariadb broke"})
    provision_event(partial, age: 1.day).container_services << service

    addon = Order.create!(user: users(:admin), deployment: project, status: "failed",
      order_data: {"project" => {"id" => project.id}, "raw_order" => [], "failure_reason" => "no capacity"})
    provision_event(addon, age: 1.day)

    old = Order.create!(user: users(:admin), deployment: project, status: "failed",
      order_data: {"project" => {"id" => nil}, "raw_order" => [], "failure_reason" => "long ago"})
    provision_event(old, age: 10.days).container_services << service
    old.update_columns(updated_at: 10.days.ago)

    W.new.perform

    se = SystemEvent.find_by!(event_code: W::PARTIAL_FAILURE_EVENT_CODE)
    assert_equal 1, se.data[:total]
    item = se.data[:items].join("\n")
    assert_match "Order #{partial.id}, project #{project.id}, owner #{project.user_id}", item
    assert_match "#{service.label} (#{service.id})", item
    assert_match "mariadb broke", item
    refute_match addon.id, item
    refute_match old.id, item
  end

  test "a failed order whose services were all removed is not a partial failure" do
    service = deployment_container_services(:pma)
    partial = Order.create!(user: users(:admin), deployment: deployments(:project_test), status: "failed",
      order_data: {"project" => {"id" => nil}, "raw_order" => []})
    provision_event(partial, age: 1.day).container_services << service
    Deployment::ContainerService.where(id: service.id).delete_all

    W.new.perform

    assert_nil SystemEvent.find_by(event_code: W::PARTIAL_FAILURE_EVENT_CODE)
  end

  test "an error in one part does not stop the others" do
    stuck = Order.create!(user: @owner, status: "processing", order_data: {"project" => {"id" => nil}, "raw_order" => []})
    stuck.update_columns(updated_at: 3.hours.ago)
    worker = W.new

    worker.stub(:empty_orphan_ids, -> { raise "boom" }) do
      worker.perform
    end

    refute deleted?(@project)
    refute_nil SystemEvent.find_by(event_code: W::STUCK_ORDER_EVENT_CODE)
  end
end
