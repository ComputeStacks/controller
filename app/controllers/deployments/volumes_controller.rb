class Deployments::VolumesController < Deployments::BaseController
  def index
    @volumes = @deployment.volumes.sorted
    # `repo_info` looks its AgentRepository up by name rather than through an association, so
    # `includes` cannot reach it and the per-row `list_archives.count` below would otherwise
    # be one query per volume.
    Volume.prime_repo_info! @volumes
    @clone_jobs = surfaced_clone_jobs
    if request.xhr?
      render template: "deployments/volumes/index", layout: false
    end
  end

  # The clone banner as its own polled region, so it shows on every tab of the project page
  # and not just the volumes one. See app/views/deployments/volumes/_clone_banner.html.erb.
  def clone_status
    render partial: "deployments/volumes/clone_banner",
      locals: {jobs: surfaced_clone_jobs.values},
      layout: false
  end

  private

  # @return [Hash{Integer => VolumeCloneJob}] keyed by target volume id
  def surfaced_clone_jobs
    @deployment.volume_clone_jobs.surfaced.includes(:volume).index_by(&:volume_id)
  end
end
