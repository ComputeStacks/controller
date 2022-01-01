class Admin::LetsEncryptController < Admin::ApplicationController

  before_action :load_certificate, only: %w(show edit update destroy)

  def index
    @lets_encrypts = ::LetsEncrypt.all
  end

  def show
  end

  def edit
  end

  def update

  end

  def new
  end

  def create
  end

  def destroy
    
  end

  private

  def load_certificate
    @lets_encrypt = ::LetsEncrypt.find_by(id: params[:id])
    if @lets_encrypt.nil?
      redirect_to "/lets_encrypt", alert: "Unknown LetsEncrypt Certificate."
      return false
    end
  end

end
