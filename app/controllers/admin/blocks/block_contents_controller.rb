class Admin::Blocks::BlockContentsController < Admin::ApplicationController

  before_action :find_block
  before_action :find_content, only: %w(show edit update destroy)

  def index
    @block_contents = @block.block_contents.order(:locale).paginate page: params[:page], per_page: 30
  end

  def show; end

  def new
    @block_content = @block.block_contents.build
    if params[:from]
      parent = @block.block_contents.find_by(id: params[:from])
      @block_content.body = parent.body if parent
    end
    @existing_locale = @block.block_contents.pluck(:locale)
  end

  def edit; end

  def create
    @block_content = @block.block_contents.build(block_content_params)
    if @block_content.save
      redirect_to "#{@base_url}/block_contents/#{@block_content.id}", notice: "Created successfully."
    else
      @existing_locale = @block.block_contents.pluck(:locale)
      render template: "admin/blocks/block_contents/new"
    end
  end

  def update
    if @block_content.update(block_content_params)
      redirect_to @section_url, notice: "Updated successfully."
    end
  end

  def destroy
    if @block_content.destroy
      redirect_to @base_url, notice: "Section deleted."
    else
      redirect_to @section_url, alert: "Error! #{@block_content.errors.full_messages.join(' ')}"
    end
  end

  private

  def block_content_params
    params.require(:block_content).permit(:locale, :body)
  end

  def find_block
    @block = Block.find_by(id: params[:block_id])
    return(redirect_to("/admin/blocks", alert: "Unknown Block")) if @block.nil?
    @base_url = "/admin/blocks/#{@block.id}"
  end

  def find_content
    @block_content = BlockContent.find_by(id: params[:id])
    return(redirect_to(@base_url, alert: "Unknown Content Block")) if @block_content.nil?
    @section_url = "#{@base_url}/block_contents/#{@block_content.id}"
    @existing_locale = @block.block_contents.where.not(id: @block_content.id).pluck(:locale)
  end


end