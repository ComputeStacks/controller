class Dns::RecordsController < Dns::BaseController

  def new
   @record = Dns::ZoneRecord.new(nil, @zone, params[:t].upcase).client
   if @record.nil?
     redirect_to "/dns", alert: I18n.t('dns.server_error')
     return false
   end
   @record.type = params[:t].upcase
   @record.ttl = 86400
  end

  def show
    redirect_to "/dns/#{@zone.id}/records/#{@record.id}-#{@record.name.parameterize}/edit"
  end

  def edit
    if params[:id] =~ /-/
      @record = Dns::ZoneRecord.new(params[:id].to_i, @zone, params[:id].split('-').last).client
      @record_id = params[:id]
    else
      @record = Dns::ZoneRecord.new(params[:id], @zone).client
      @record_id = @record.id
    end
  end

  def create
    @record = Dns::ZoneRecord.new(nil, @zone)
    response = @record.create!(params)
    if response['success']
      flash[:notice] = I18n.t('crud.created', resource: 'Record')
    else
      flash[:alert] = "Error! #{response['message']}"
    end
    redirect_to "/dns/#{@zone.id}-#{@zone.name.parameterize}"
  end

  def update
    @record = Dns::ZoneRecord.new(params[:id].to_i, @zone, params[:type])
    response = @record.update!(params)
    if response['success']
      redirect_to "/dns/#{@zone.id}-#{@zone.name.parameterize}", notice: I18n.t('crud.updated', resource: 'Record')
    else
      redirect_to "/dns/#{@zone.id}/records/#{@record.id}-#{@zone.name.parameterize}/edit", alert: "Error! #{response['message']}"
    end
  end

  def destroy
    if params[:id] =~ /-/
      @record = Dns::ZoneRecord.new(params[:id].to_i, @zone, params[:id].split('-').last)
    else
      @record = Dns::ZoneRecord.new(params[:id], @zone)
    end
    response = @record.destroy
    if response['success']
      flash[:notice] = I18n.t('crud.deleted', resource: 'Record')
    else
      flash[:alert] = "Error! #{response['message']}"
    end
    redirect_to "/dns/#{@zone.id}-#{@zone.name.parameterize}"
  end

end
