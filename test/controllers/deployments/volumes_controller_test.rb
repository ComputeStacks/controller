require "test_helper"

##
# The customer-facing surface of an async volume clone.
#
# Restores now outlive the order, so the project page has to say so on its own — the order
# page is gone within one 6.5s poll (OrdersController#show redirects to the project). Both
# the banner region and the volume list are driven off VolumeCloneJob, never off the umbrella
# EventLog, because a reaper can terminate that event out from under a live job.
class Deployments::VolumesControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers
  include CloneTestHelpers

  setup do
    sign_in users(:admin)
    @deployment = volumes(:wordpress_web).deployment
  end

  def clone_job(state:, finished_at: nil)
    VolumeCloneJob.create!(
      volume: volumes(:wordpress_web),
      source_volume: volumes(:mysql),
      deployment: @deployment,
      state: state,
      finished_at: finished_at,
      next_poll_at: Time.now
    )
  end

  test "the banner is empty when nothing is cloning" do
    get "/deployments/#{@deployment.token}/volume_clones", xhr: true
    assert_response :success
    assert_equal "", response.body.strip
  end

  test "an in-flight clone names the step it is on" do
    clone_job state: VolumeCloneJob::STATE_AWAITING_BACKUP

    get "/deployments/#{@deployment.token}/volume_clones", xhr: true
    assert_response :success
    assert_includes response.body, "Restoring data into 1 volume."
    assert_includes response.body, "Snapshotting the source volume"
    # Reassurance matters here: the services are already running.
    assert_includes response.body, "already running"
  end

  test "a recent failure is surfaced and an old one is not" do
    job = clone_job state: VolumeCloneJob::STATE_FAILED, finished_at: 1.hour.ago

    get "/deployments/#{@deployment.token}/volume_clones", xhr: true
    assert_includes response.body, "did not finish restoring"

    # Terminal rows outlive the clone for the snapshot reaper and for post-mortems, so
    # without a window the customer would still be looking at this banner months later.
    job.update! finished_at: (VolumeCloneJob::UI_FAILURE_WINDOW + 1.hour).ago
    get "/deployments/#{@deployment.token}/volume_clones", xhr: true
    assert_equal "", response.body.strip
  end

  test "a completed clone says nothing at all" do
    clone_job state: VolumeCloneJob::STATE_COMPLETED, finished_at: Time.now

    get "/deployments/#{@deployment.token}/volume_clones", xhr: true
    assert_equal "", response.body.strip
  end

  test "the volume list marks the cloning row and leaves the others alone" do
    clone_job state: VolumeCloneJob::STATE_AWAITING_RESTORE

    get "/deployments/#{@deployment.token}/volumes", xhr: true
    assert_response :success
    assert_includes response.body, "Copying data"
    # One label, not one per row.
    assert_equal 1, response.body.scan("Copying data").count
  end

  test "the volume list resolves every repository in one query" do
    @deployment.volumes.each { |v| seed_archives v, [archive_name("one"), archive_name("two")] }

    queries = 0
    counter = lambda { |*, payload| queries += 1 if payload[:sql]&.include?("agent_repositories") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get "/deployments/#{@deployment.token}/volumes", xhr: true
    end

    assert_response :success
    assert_includes response.body, "2"
    # `repo_info` looks its row up by NAME, so `includes` cannot preload it — without
    # Volume.prime_repo_info! this is one query per volume.
    assert_equal 1, queries, "expected a single agent_repositories query, saw #{queries}"
  end
end
