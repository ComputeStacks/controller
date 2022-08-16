module OrdersHelper

  # Generate order confirmation image
  def order_confirmation_image(order)
    "#{CS_CDN_URL}/images/icons/stacks/docker.png"
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
      container_image = ContainerImage.find_by(id: i['container_id'])
      image_name = container_image.nil? ? 'Unknown' : container_image.label
      product = Product.find_by(id: i.dig('resources', 'product_id'))
      result << tag.div(class: 'order_wrapper') do
        tag.div(class: "order-item #{k > 0 ? 'order-wrap-border' : ''}") do
          concat(
            tag.div(class: 'pull-right text-right hidden-xs') do
              concat tag.small(t('obj.deployment').upcase)
              concat tag.div(order.deployment.name, class: 'order-item-description')
            end
          ) if order.deployment
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
                        concat(
                            tag.td(class: 'text-right') do
                              product.nil? ? I18n.t('common.free') : formatted_product_price(region, product)
                            end
                        )
                      end
                  )
                  i['volume_config'].each do |vol|
                    concat(
                      tag.tr do
                        case vol['action']
                        when 'clone', 'mount'
                          concat(
                            tag.td("-> #{vol['action'].capitalize} Volume #{vol['source']} at #{vol['mount_path']} #{vol['mount_ro'] ? '(RO)' : '' }", class: 'order-child-table-item', colspan: '2', style: 'text-indent: 10px;')
                          )
                        when 'create'
                          concat(
                            tag.td("-> Create Volume #{vol['label']} at #{vol['mount_path']}", class: 'order-child-table-item', colspan: '2', style: 'text-indent: 10px;')
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
                              tag.td('CPU', class: 'order-child-table-item')
                          )
                          concat(
                              tag.td("#{product.package.cpu} #{product.package.cpu.to_f > 1 ? 'CORES' : 'CORE'}", class: 'text-right')
                          )
                        end
                    )
                    concat(
                        tag.tr do
                          concat(
                              tag.td(I18n.t('attributes.mem'), class: 'order-child-table-item')
                          )
                          concat(
                              tag.td("#{product.package.memory.to_f / 1024.0} GB", class: 'text-right')
                          )
                        end
                    )
                    concat(
                        tag.tr do
                          concat(
                              tag.td(I18n.t('attributes.disk'), class: 'order-child-table-item')
                          )
                          concat(
                              tag.td("#{product.package.storage} GB", class: 'text-right')
                          )
                        end
                    )
                    concat(
                      tag.tr do
                        concat(
                          tag.td(I18n.t('attributes.local_disk'), class: 'order-child-table-item')
                        )
                        concat(
                          tag.td("#{product.package.local_disk} GB", class: 'text-right')
                        )
                      end
                    )
                    concat(
                        tag.tr do
                          concat(
                              tag.td(I18n.t('attributes.transfer'), class: 'order-child-table-item')
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
