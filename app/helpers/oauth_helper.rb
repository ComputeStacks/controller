module OauthHelper

  def oauth_application_owner(app)
    owner = User.find_by(id: app.owner_id)
    return nil if owner.nil?
    link_to owner.full_name, admin_user_path(owner)
  end

  def oauth_available_scopes
    if current_user.is_admin
      [
        ['Admin (read)', 'admin_read'],
        ['Admin (write)', 'admin_write'],
        ['Profile (read)', 'profile_read'],
        ['Profile (update)', 'profile_update'],
        ['Projects (read)', 'project_read'],
        ['Projects (write)', 'project_write'],
        ['Container Images (read)', 'images_read'],
        ['Container Images (write)', 'images_write'],
        ['Orders (read)', 'order_read'],
        ['Orders (write)', 'order_write'],
        ['DNS (read)', 'dns_read'],
        ['DNS (write)', 'dns_write'],
        ['Public', 'public'],
        ['Register', 'register']
      ]
    else
      [
        ['Profile (read)', 'profile_read'],
        ['Profile (update)', 'profile_update'],
        ['Projects (read)', 'project_read'],
        ['Projects (write)', 'project_write'],
        ['Container Images (read)', 'images_read'],
        ['Container Images (write)', 'images_write'],
        ['Orders (read)', 'order_read'],
        ['Orders (write)', 'order_write'],
        ['DNS (read)', 'dns_read'],
        ['DNS (write)', 'dns_write'],
        ['Public', 'public']
      ]
    end
  end

end