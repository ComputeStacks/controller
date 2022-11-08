module ContainerServices
  module ServiceResizeHelper

    # Generate a resize button for a given service
    # and ensure we have packages available.
    def service_resize_btn(service)

      if service.available_packages.count < 2
        link_to "#{icon('fa-solid', 'sliders')} #{t('container_services.actions.resize')}".html_safe, "#{container_service_path(@service)}", class: 'btn btn-sm btn-default', disabled: 'disabled', title: "No packages available"
      else
        link_to "#{icon('fa-solid', 'sliders')} #{t('container_services.actions.resize')}".html_safe, "#{container_service_path(@service)}/resize_service", class: 'btn btn-sm btn-primary'
      end

    end

  end
end
