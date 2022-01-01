class Admin::Users::BypassSecurityController < Admin::Users::ApplicationController


  def create
    @user.disable_2fa!
    redirect_to @basepath, notice: "Second Factor is bypassed until next login."
  end

  def destroy
    @user.enable_2fa!
    redirect_to @basepath, notice: "Second Factor restored."
  end
 
end
