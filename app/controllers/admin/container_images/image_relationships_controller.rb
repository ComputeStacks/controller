class Admin::ContainerImages::ImageRelationshipsController < Admin::ContainerImages::BaseController
  def new
    @containers = if @container.user.nil?
      ContainerImage.where(user: nil).order(:name)
    else
      ContainerImage.where("user_id is null OR user_id = ?", @container.user.id).order(:name)
    end
    @container_dependencies = @container.dependencies
    @container_roles = @container.dependencies.pluck(:role)
    render template: "container_images/image_relationships/new"
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
    c = @container.dependency_parents.find_by(id: params[:id])
    if c.nil?
      redirect_to helpers.container_image_path(@container), alert: "Unknown dependent container."
      return false
    end
    if c.destroy
      flash[:notice] = "Removed container"
    else
      flash[:alert] = "Error removing dependency: #{c.errors.full_messages.to_sentence}"
    end
    redirect_to helpers.container_image_path(@container)
  end
end
