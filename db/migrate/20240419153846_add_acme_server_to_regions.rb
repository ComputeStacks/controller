class AddAcmeServerToRegions < ActiveRecord::Migration[7.1]
  def change
    add_column :regions, :acme_server, :string, default: '127.0.0.1:3000', null: false

    existing_le_server = Setting.find_by(name: 'le_validation_server', category: 'lets_encrypt')
    return if existing_le_server.nil?

    Region.all.each do |i|
      i.update acme_server: existing_le_server.value
    end

    existing_le_server.destroy

  end
end
