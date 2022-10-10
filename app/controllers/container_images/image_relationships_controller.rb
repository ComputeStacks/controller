class ContainerImages::ImageRelationshipsController < ContainerImages::BaseController

  def new
    if current_user.is_admin
      the_user_id = @container.user.nil? ? current_user.id : @container.user.id
      @containers = ContainerImage.where('user_id is null OR user_id = ?', the_user_id).order(:name)
    else
      @containers = ContainerImage.where('user_id is null OR user_id = ?', current_user.id).order(:name)
    end
    @container_dependencies = @container.dependencies
    @container_roles = @container.dependencies.pluck(:role)
  end

  def edit
    redirect_to helpers.container_image_path(@container), alert: "Not allowed. Delete and re-add the relationship."
    return false
  end

  def create
    user = @container.user
    if user.nil?
      redirect_to helpers.container_image_path(@container), alert: I18n.t('crud.unknown', resource: I18n.t('obj.user'))
      return false
    end
    c = ContainerImage.find_by(id: params[:container])
    if c.nil?
      redirect_to helpers.container_image_path(@container), alert: I18n.t('crud.unknown', resource: I18n.t('obj.container'))
      return false
    end
    # Dont allow selection of other users containers.
    unless c.user.nil?
      if user != c.user
        redirect_to helpers.container_image_path(@container), alert: I18n.t('crud.unknown', resource: I18n.t('obj.container'))
        return false
      end
    end
    if @container.dependencies.include?(c)
      redirect_to helpers.container_image_path(@container), alert: I18n.t('crud.created', resource: I18n.t('obj.container'))
      return false
    end
    @container.dependency_parents.create!(
      requires_container_id: c.id,
      current_user: current_user
    )
    redirect_to helpers.container_image_path(@container), notice: I18n.t('crud.created', resource: I18n.t('obj.container'))
  end

  def update
    redirect_to helpers.container_image_path(@container), alert: "Not allowed. Delete and re-add the relationship."
  end

  def destroy
    c = @container.dependencies.find_by(id: params[:id])
    if c.nil?
      redirect_to helpers.container_image_path(@container), alert: I18n.t('crud.unknown', resource: 'dependent container')
      return false
    end
    @container.dependencies.delete(c)
    redirect_to helpers.container_image_path(@container), notice: I18n.t('crud.deleted', resource: I18n.t('obj.container'))
  end

end
