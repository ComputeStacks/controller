class Admin::Dns::RecordsController < Admin::Dns::BaseController

  def new
   @record = Dns::ZoneRecord.new(nil, @zone, params[:t].upcase).client
   if @record.nil?
     redirect_to "/admin/dns", alert: "Unable to connect to DNS server"
     return false
   end
   @record.type = params[:t].upcase
   @record.ttl = 86400
  end

  def show
    redirect_to "/admin/dns/#{@zone.id}/records/#{@record.id}-#{@record.name.parameterize}/edit"
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
      flash[:notice] = "Record added."
    else
      flash[:alert] = "Error! #{response['message']}"
    end
    redirect_to "/admin/dns/#{@zone.id}-#{@zone.name.parameterize}"
  end

  def update
    @record = Dns::ZoneRecord.new(params[:id].to_i, @zone, params[:type])
    response = @record.update!(params)
    if response['success']
      redirect_to "/admin/dns/#{@zone.id}-#{@zone.name.parameterize}", notice: "Record Updated."
    else
      redirect_to "/admin/dns/#{@zone.id}/records/#{@record.id}-#{@zone.name.parameterize}/edit", alert: "Error! #{response['message']}"
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
      flash[:notice] = "Record Deleted."
    else
      flash[:alert] = "Error! #{response['message']}"
    end
    redirect_to "/admin/dns/#{@zone.id}-#{@zone.name.parameterize}"
  end

end
