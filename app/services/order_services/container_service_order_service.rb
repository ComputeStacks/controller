module OrderServices
  class ContainerServiceOrderService

    attr_accessor :order,
                  :event,
                  :project,
                  :product, # In the `data` loop, these are the params
                  :errors

    def initialize(order, event, project, product)
      self.order = order
      self.event = event
      self.project = project
      self.product = product
      self.errors = []
    end

    def perform
      return false unless valid?
      product_id = if product.dig(:product, :id)
                     product.dig(:product, :id) # deprecated
                   elsif product.dig(:resources, :product_id)
                     product.dig(:resources, :product_id)
                   elsif product.dig(:resources, :package_id) # deprecated
                     product.dig(:resources, :package_id) # package_id is actually product_id!
                   else
                     nil
                   end
      job = ProvisionServices::ContainerServiceProvisioner.new(
        order.user,
        project,
        event,
        {
          qty: product[:qty].to_i.zero? ? 1 : product[:qty].to_i,
          label: product[:label],
          region_id: order.data[:region_id],
          image_id: product[:container_id],
          product_id: product_id,
          cpu: product.dig(:resources, :cpu).to_f,
          memory: product.dig(:resources, :memory).to_i,
          settings: product[:params],
          external_id: product[:remote_service_id]
        }
      )
      success = job.perform
      job.errors.each do |er|
        errors << er
      end
      success
    end

    private

    def valid?
      errors << "Missing project" unless project.is_a?(Deployment)
      errors << "Missing order" unless order.is_a?(Order)
      errors << "Missing event" unless event.is_a?(EventLog)
      errors.empty?
    end

  end
end
