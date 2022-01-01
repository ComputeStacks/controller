class Api::Admin::Users::BaseController < Api::Admin::ApplicationController
  include ApiAdminFindUser

  before_action :locate_user


end
