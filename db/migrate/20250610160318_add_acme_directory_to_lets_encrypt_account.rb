class AddAcmeDirectoryToLetsEncryptAccount < ActiveRecord::Migration[7.1]
  def change
    add_column :lets_encrypt_accounts, :acme_directory, :string, default: "https://acme-v02.api.letsencrypt.org/directory"
  end
end
