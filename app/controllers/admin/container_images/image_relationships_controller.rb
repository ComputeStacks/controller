class Admin::ContainerImages::ImageRelationshipsController < Admin::ContainerImages::BaseController

  def new
    if @container.user.nil?
      @containers = ContainerImage.where(user: nil).order(:name)
    else
      @containers = ContainerImage.where('user_id is null OR user_id = ?', @container.user.id).order(:name)
    end
    @container_dependencies = @container.dependencies
    @container_roles = @container.dependencies.pluck(:role)
    render template: 'container_images/image_relationships/new'
  end

  def edit
    redirect_to helpers.container_image_path(@container), alert: "Not allowed. Delete and re-add the relationship."
  end

  def create
    c = ContainerImage.find_by(id: params[:container])
    if @container.dependencies.include?(c)
      redirect_to helpers.container_image_path(@container), alert: "Container already added."
      return false
    end
    @container.dependency_parents.create!(
      requires_container_id: c.id,
      current_user: current_user
    )
    redirect_to helpers.container_image_path(@container), notice: "Container added"
  end

  def update
    redirect_to helpers.container_image_path(@container), alert: "Not allowed. Delete and re-add the relationship."
  end

  def destroy
    c = @container.dependencies.find_by(id: params[:id])
    if c.nil?
      redirect_to helpers.container_image_path(@container), alert: "Unknown dependent container."
      return false
    end
    @container.dependencies.delete(c)
    redirect_to helpers.container_image_path(@container), notice: "Removed container."
  end

end
