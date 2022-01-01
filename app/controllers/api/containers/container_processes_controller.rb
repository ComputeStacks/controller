##
# Container Processes API
class Api::Containers::ContainerProcessesController < Api::Containers::BaseController

  ##
  # List Container Processes
  #
  # `GET /api/containers/{container-id}/container_processes`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # Returns an Array of Objects containing:
  #
  # * `UID`: String
  # * `PID`: Integer
  # * `PPID`: Integer
  # * `C`: Integer
  # * `STIME`: String
  # * `TTY`: String
  # * `TIME`: string
  # * `CMD`: String
  #
  def index
    processes = @container.top(false)
    respond_to do |format|
      format.json { render json: processes }
      format.xml { render xml: processes }
    end
  end

end
