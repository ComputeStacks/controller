class DocumentationController < ApplicationController

  def api
    redirect_to "https://docs.computestacks.com/user_api/", allow_other_host: true
  end

end
