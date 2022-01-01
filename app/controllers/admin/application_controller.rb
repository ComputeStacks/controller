class Admin::ApplicationController < AuthController

  include AdminAuthable  

  layout 'admin/layouts/application'

end
