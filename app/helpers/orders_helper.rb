module OrdersHelper

  def order_image_dependency_map(image)
    image.dependencies.filter_map { |i| i.id }.join(', ')
  end

  def order_view_status(order)
    pending_msg = "Your order is being provisioned, please wait..."
    error_msg = "There appears to be a problem, please contact support."
    failed_provisioning = "There was a problem provisioning your order."

    is_ready = "Your project is ready"
    is_ready_cloned = "Your project is ready, however the cloning process may still need a few more minutes to finish. Please watch for the volume snapshot and restore process in your event log to ensure the clone was successful."

    event = order.provision_event

    return pending_msg if event.nil?

    return pending_msg if order.deployment.nil? && event.active?
    return error_msg if order.deployment.nil? && event.done?
    if order.is_clone?
      return is_ready_cloned if order.deployment && event.success?
    else
      return is_ready if order.deployment && event.success?
    end
    return failed_provisioning if order.deployment&.provisioning_failed?
    "Your project is being provisioned."
  end

  # Generate order confirmation table
  #
  # @param [Order] order
  # @type [User] current_user
  # @return [String]
  def order_confirmation(order)
    data = order.order_data['raw_order']
    result = []
    region = Region.find_by(id: order.order_data['region_id'])
    data.each_with_index do |i, k|
      image_variant = ContainerImage::ImageVariant.find_by(id: i['image_variant_id'])
      next if image_variant.nil?
      container_image = image_variant.container_image
      image_name = container_image.nil? ? 'Unknown' : image_variant.friendly_name
      image_product = container_image.product
      product = Product.find_by(id: i.dig('resources', 'product_id'))
      result << tag.div(class: 'order_wrapper') do
        tag.div(class: "order-item #{k > 0 ? 'order-wrap-border' : ''}") do
          concat(
            tag.div(class: 'pull-right text-right hidden-xs') do
              concat tag.small(t('obj.deployment').upcase)
              concat tag.div(order.deployment.name, class: 'order-item-description')
            end
          ) if order.deployment && order.pending?
          concat tag.small(i['product_type'].upcase.gsub("_", " "), style: 'font-weight:bold;')
          concat tag.div(i.dig('product', 'label'), class: 'order-item-description')
          concat(
              tag.div(class: 'order-children') do
                tag.table(class: 'order-child-table') do
                  concat(
                      tag.tr do
                        concat(
                            tag.td(image_name, class: 'order-child-table-item', style: 'font-weight:bold;')
                        )
                        if image_product
                          concat(
                              tag.td(class: 'text-right', style: 'font-weight:bold;') do
                                formatted_product_price(region, image_product)
                              end
                          )
                        end
                      end
                  )
                  i['volume_config'].each do |vol|
                    concat(
                      tag.tr do
                        case vol['action']
                        when 'clone', 'mount'
                          concat(
                            tag.td("#{icon('fa-solid', 'arrow-right-long')}  #{vol['action'].capitalize} Volume #{vol['source']} at #{vol['mount_path']} #{vol['mount_ro'] ? '(RO)' : '' }".html_safe, class: 'order-child-table-item', colspan: '2', style: 'text-indent: 10px;')
                          )
                        when 'create'
                          concat(
                            tag.td("#{icon('fa-solid', 'arrow-right-long')}  Create Volume #{vol['label']} at #{vol['mount_path']}".html_safe, class: 'order-child-table-item', colspan: '2', style: 'text-indent: 10px;')
                          )
                        else
                          next
                        end
                      end
                    )
                  end
                  if product&.package
                    concat(
                      tag.tr do
                        concat(
                          tag.td(product.label, class: 'order-child-table-item', style: 'font-weight:bold;')
                        )
                        concat(
                          tag.td(class: 'text-right', style: 'font-weight:bold;') do
                            product.nil? ? I18n.t('common.free') : formatted_product_price(region, product)
                          end
                        )
                      end
                    )
                    concat(
                        tag.tr do
                          concat(
                              tag.td("#{icon('fa-solid', 'arrow-right-long')} CPU".html_safe, class: 'order-child-table-item', style: 'text-indent: 10px;')
                          )
                          concat(
                              tag.td("#{product.package.cpu} #{product.package.cpu.to_f > 1 ? 'CORES' : 'CORE'}", class: 'text-right')
                          )
                        end
                    )
                    concat(
                        tag.tr do
                          concat(
                              tag.td("#{icon('fa-solid', 'arrow-right-long')} #{I18n.t('attributes.mem')}".html_safe, class: 'order-child-table-item', style: 'text-indent: 10px;')
                          )
                          concat(
                              tag.td("#{product.package.memory.to_f / 1024.0} GB", class: 'text-right')
                          )
                        end
                    )
                    concat(
                        tag.tr do
                          concat(
                              tag.td("#{icon('fa-solid', 'arrow-right-long')}  #{I18n.t('attributes.disk')}".html_safe, class: 'order-child-table-item', style: 'text-indent: 10px;')
                          )
                          concat(
                              tag.td("#{product.package.storage} GB", class: 'text-right')
                          )
                        end
                    )
                    concat(
                      tag.tr do
                        concat(
                          tag.td("#{icon('fa-solid', 'arrow-right-long')}  #{I18n.t('attributes.local_disk')}".html_safe, class: 'order-child-table-item', style: 'text-indent: 10px;')
                        )
                        concat(
                          tag.td("#{product.package.local_disk} GB", class: 'text-right')
                        )
                      end
                    )
                    concat(
                        tag.tr do
                          concat(
                              tag.td("#{icon('fa-solid', 'arrow-right-long')} #{I18n.t('attributes.transfer')}".html_safe, class: 'order-child-table-item', style: 'text-indent: 10px;')
                          )
                          concat(
                              tag.td("#{product.package.bandwidth} GB", class: 'text-right')
                          )
                        end
                    )
                  else
                    if i.dig('resources', 'memory') && !container_image&.is_free
                      concat(
                        tag.tr do
                          concat(
                            tag.td(I18n.t('attributes.mem'), class: 'order-child-table-item')
                          )
                          concat(
                            tag.td("#{i.dig('resources', 'memory')} MB", class: 'text-right')
                          )
                        end
                      )
                    end
                    if i.dig('resources', 'cpu') && !container_image&.is_free
                      concat(
                        tag.tr do
                          concat(
                            tag.td('CPU', class: 'order-child-table-item')
                          )
                          concat(
                            tag.td("#{i.dig('resources', 'cpu')} #{i.dig('resources', 'cpu').to_i > 1 ? 'CORES' : 'CORE'}", class: 'text-right')
                          )
                        end
                      )
                    end
                  end

                  if i.dig('resources', 'disk')
                    concat(
                        tag.tr do
                          concat(
                              tag.td(I18n.t('attributes.disk'), class: 'order-child-table-item')
                          )
                          concat(
                              tag.td("#{i.dig('resources', 'disk')} GB", class: 'text-right')
                          )
                        end
                    )
                  end
                  if i.dig('resources', 'local_disk')
                    concat(
                      tag.tr do
                        concat(
                          tag.td(I18n.t('attributes.local_disk'), class: 'order-child-table-item')
                        )
                        concat(
                          tag.td("#{i.dig('resources', 'local_disk')} GB", class: 'text-right')
                        )
                      end
                    )
                  end
                  unless i['addons'].nil? || i['addons'].empty?
                    concat(
                      tag.tr do
                        concat(
                          tag.td("Addons", class: 'order-child-table-item', style: 'font-weight:bold;')
                        )
                        concat( tag.td("") )
                      end
                    )
                    i['addons'].each do |addon_id|
                      addon = ContainerImagePlugin.find_by id: addon_id
                      next if addon.nil?
                      concat(
                        tag.tr do
                          concat(
                            tag.td("#{icon('fa-solid', 'arrow-right-long')}  #{addon.label}".html_safe, class: 'order-child-table-item', style: 'text-indent: 10px;')
                          )
                          concat(
                            tag.td(class: 'text-right') do
                              addon.product.nil? ? I18n.t('common.free') : formatted_product_price(region, addon.product)
                            end
                          )
                        end
                      )
                    end
                  end
                  if container_image && i['params']
                    i['params'].each do |k,v|
                      next if v['type'] == 'password'
                      concat(
                        tag.tr do
                          concat(
                            tag.th(container_image.setting_params.find_by(name: k)&.label, class: 'order-child-table-item')
                          )
                          concat(
                            tag.th(truncate(v['value'], length: 50), class: 'text-right')
                          )
                        end
                      )
                    end
                  end
                end
              end
          )
        end
      end
    end
    result.join('').html_safe
  end

end
