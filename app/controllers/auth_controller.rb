class AuthController < ApplicationController
  
  before_action :authenticate_user!
  before_action :second_factor!

end