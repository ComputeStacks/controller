module Admin::UsersHelper

  def admin_user_path(user)
    "/admin/users/#{user.id}-#{user.full_name.parameterize}"
  end

end
