module Admin::LetsEncryptHelper

  def admin_lets_encrypt_path(lets_encrypt)
    "/admin/lets_encrypt/#{lets_encrypt.id}"
  end

  def admin_lets_encrypt_auth_path(lets_encrypt_auth)
    "/admin/lets_encrypt/#{lets_encrypt_auth.certificate.id}/lets_encrypt_auth/#{lets_encrypt_auth.id}"
  end

end
