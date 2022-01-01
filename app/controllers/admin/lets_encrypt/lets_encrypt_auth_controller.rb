class Admin::LetsEncrypt::LetsEncryptAuthController < Admin::ApplicationController

  before_action :load_lets_encrypt
  before_action :load_auth

  def destroy
    @auth.destroy
    redirect_to "/admin/lets_encrypt/#{@lets_encrypt.id}"
  end

  private

  def load_lets_encrypt
    @lets_encrypt = ::LetsEncrypt.find_by(id: params[:lets_encrypt_id])
    if @lets_encrypt.nil?
      rediret_to "/admin/lets_encrypt", alert: "Unknown LetsEncrypt."
      return false
    end
  end

  def load_auth
    @auth = LetsEncryptAuth.find_by(id: params[:id])
    if @auth.nil?
      redirect_to "/admin/lets_encrypt/#{@lets_encrypt.id}", alert: "Unknown Auth"
      return false
    end
  end

end
