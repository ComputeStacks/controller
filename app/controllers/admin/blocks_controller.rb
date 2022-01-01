class Admin::BlocksController < Admin::ApplicationController

  before_action :load_block, only: %w(show edit update destroy)

  def index
    @blocks = Block.order(created_at: :desc).paginate page: params[:page], per_page: 30
  end

  def show
    redirect_to "/admin/blocks/#{@block.id}/block_contents"
  end

  def new
    @block = Block.new
  end

  def edit; end

  def update
    if @block.update(block_params)
      redirect_to "/admin/blocks/#{@block.id}", success: "Content Block updated"
    else
      render template: "admin/blocks/edit"
    end
  end

  def create
    @block = Block.new(block_params)
    if @block.save
      redirect_to "/admin/blocks/#{@block.id}/block_contents/new"
    else
      render template: "admin/blocks/new"
    end
  end

  def destroy
    if @block.destroy
      flash[:notice] = "Block deleted."
    else
      flash[:alert] = "Error: #{@block.errors.full_messages.join(' ')}"
    end
    redirect_to "/admin/blocks"
  end

  private

  def block_params
    params.require(:block).permit(:title)
  end

  def load_block
    @block = Block.find_by(id: params[:id])
    return(redirect_to("/admin/blocks", alert: "Unknown block.")) if @block.nil?
  end

end