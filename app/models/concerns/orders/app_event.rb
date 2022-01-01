module Orders
  module AppEvent
    extend ActiveSupport::Concern

    def app_event_subject(alert_name)
      case alert_name
      when 'NewOrder'
        "New Order"
      else
        ""
      end
    end

    def app_event_description(alert_name)
      case alert_name
      when 'NewOrder'
        "#{user.full_name} created a new Order."
      else
        ""
      end
    end

    def app_event_labels
      data = order_data['raw_order']
      result = [ { 'key' => 'link', 'value' => %Q(https://#{Setting.hostname}/admin/orders/#{id}) } ]
      result << { 'key' => 'Project', 'value' => deployment.name } if deployment
      data.each_with_index do |i, k|
        container_image = ContainerImage.find_by(id: i['container_id'])
        image_name = container_image.nil? ? 'Unknown' : container_image.label
        product = Product.find_by(id: i.dig('resources', 'product_id'))
        product_name = product ? product.label : "Unknown Package"
        result << {
          'key' => image_name,
          'value' => product_name
        }
      end
      result
    end

  end
end
