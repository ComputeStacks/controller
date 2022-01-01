class Admin::Subscriptions::SubscriptionUsageController < Admin::Subscriptions::BaseController

  # before_action :find_usage_item, only: %w(show edit update create destroy)

  def index
    usages = @subscription.billing_usages.order(period_start: :desc)
    usages = case params[:state]
             when 'processed'
               usages.where(processed: true)
             when 'unprocessed'
               usages.where(processed: false)
             else
               usages
             end
    usages = case params[:product].to_i
             when 0
               usages
             else
               p = Product.find_by(id: params[:product])
               p.nil? ? usages : usages.where(products: {id: p.id}).joins(:product)
             end
    unless params[:timerange].blank?
      stime = params[:timerange].split("-").first.strip
      etime = params[:timerange].split("-").last.strip
      usages = usages.where("period_start >= ? AND period_end <= ?", Time.parse(stime).utc, Time.parse(etime).utc)
    end
    unless params[:p_timerange].blank?
      pstime = params[:p_timerange].split("-").first.strip
      petime = params[:p_timerange].split("-").last.strip
      usages = usages.where("processed_on >= ? AND processed_on <= ?", Time.parse(pstime).utc, Time.parse(petime).utc)
    end
    @billing_usages = usages.paginate page: params[:page], per_page: 30
  rescue
    redirect_to "/admin/subscriptions/#{@subscription.id}", alert: "Invalid data entry."
  end

  def destroy
    usage_ids = []
    usage_ids << params[:id] if params[:id]
    usage_ids << usage_ids + params[:billing_usage_ids] if params[:billing_usage_ids].is_a?(Array)
    usage_ids.flatten!
    if usage_ids.empty?
      redirect_to "/admin/subscriptions/#{@subscription.id}/subscription_usage"
      return false
    end
    errors = []
    count = 0
    usage_ids.each do |i|
      usage = BillingUsage.find_by(id: i)
      next if usage.nil?
      audit = Audit.create!(
          user: current_user,
          event: 'deleted',
          ip_addr: request.remote_ip,
          rel_model: 'BillingUsage',
          raw_data: {
              subscription: {
                  id: usage.subscription&.id
              },
              usage: usage.serializable_hash
          }
      )
      if usage.destroy
        count += 1
      else
        audit.destroy
        errors << "Error deleting usage item #{i}: #{usage.errors.full_messages.join(' ')}"
      end
    end
    if errors.empty?
      flash[:notice] = "#{count} #{count == 1 ? 'usage item' : 'usage items'} deleted."
    else
      flash[:alert] = errors.join(' ')
    end
    redirect_to "/admin/subscriptions/#{@subscription.id}/subscription_usage"
  end

end
