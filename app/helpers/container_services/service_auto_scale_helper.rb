module ContainerServices
  module ServiceAutoScaleHelper

    def service_auto_scale_status(service)
      if service.auto_scale
        tag.span t('container_services.auto_scale.enabled'), class: 'text-success'
      else
        tag.span t('container_services.auto_scale.disabled'), style: 'color:#666;'
      end
    end

    def service_auto_scale_btn(service)
      if service.auto_scale
        link_to "#{tag.i(nil, class: 'fa-solid fa-chart-line')} #{t('container_services.auto_scale.enabled')}".html_safe, container_service_auto_scale_path(service), class: 'btn btn-sm btn-success'
      else
        link_to "#{tag.i(nil, class: 'fa-solid fa-chart-line')} #{t('container_services.auto_scale.disabled')}".html_safe, container_service_auto_scale_path(service), class: 'btn btn-sm btn-default'
      end
    end

  end
end
