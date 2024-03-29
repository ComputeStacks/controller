module ContainerImageHelper

  def container_images_path
    if request.path =~ /admin/ && current_user.is_admin?
      "/admin/container_images"
    else
      "/container_images"
    end
  end

  # @param [ContainerImage] image
  def container_image_path(image)
    return "/container_images" if image.nil?
    if request.path =~ /admin/ && current_user.is_admin?
      "/admin/container_images/#{image.id}-#{image.name.parameterize}"
    else
      "/container_images/#{image.id}-#{image.name.parameterize}"
    end
  end

  def new_container_image_path
    "#{container_images_path}/new"
  end

  # @param [ContainerImage] image
  def edit_container_image_path(image)
    "#{container_image_path(image)}/edit"
  end

  # @param [ContainerImage] image
  # @param [String] size must be small, medium.
  def container_image_img_icon_tag(image, size)
    style = case size
            when 'small'
              'width:20px;height:20px;'
            else
              # default (medium)
              'width:25px;height:25px;'
            end
    %Q(<img src="#{image_path image.icon_url}" style="#{style}" title="#{image.label}" alt="#{image.label}" />).html_safe
  end

  def image_content_general(image)
    unless image.general_block.nil? || image.general_block.block_contents.find_by(locale: I18n.locale).nil?
      content = image.general_block.block_contents.find_by(locale: I18n.locale)
      content.nil? ? nil : "#{content.body.html_safe}<br><hr>".html_safe
    end
  end

  def image_content_ssh(service)
    image = service.container_image
    content_key = service.volumes.sftp_enabled.empty? ? 'container_image.ssh_bastion' : 'container_image.ssh'
    if image.ssh_block.nil? || image.ssh_block.block_contents.find_by(locale: I18n.locale).nil?
      content = Block.find_by(content_key: content_key)&.block_contents&.find_by(locale: I18n.locale)
      content = Block.find_by(content_key: content_key)&.block_contents&.find_by(locale: I18n.default_locale) if content.nil?
    else
      content = image.ssh_block.block_contents.find_by(locale: I18n.locale)
      content = image.ssh_block.block_contents.find_by(locale: I18n.default_locale) if content.nil?
    end
    content.nil? ? nil : content.body.html_safe
  end

  def image_content_remote(service)
    image = service.container_image
    if image.remote_block.nil? || image.remote_block.block_contents.find_by(locale: I18n.locale).nil?
      content = Block.find_by(content_key: 'container_image.ports')&.block_contents&.find_by(locale: I18n.locale)
      content = Block.find_by(content_key: 'container_image.ports')&.block_contents&.find_by(locale: I18n.default_locale) if content.nil?
    else
      content = image.remote_block.block_contents.find_by(locale: I18n.locale)
      content = image.remote_block.block_contents.find_by(locale: I18n.default_locale) if content.nil?
    end
    content.nil? ? nil : content.parsed_body(service).html_safe
  end

  def image_content_domain(image)
    if image.domains_block.nil? || image.domains_block.block_contents.find_by(locale: I18n.locale).nil?
      content = Block.find_by(content_key: 'container_image.domain')&.block_contents&.find_by(locale: I18n.locale)
      content = Block.find_by(content_key: 'container_image.domain')&.block_contents&.find_by(locale: I18n.default_locale) if content.nil?
    else
      content = image.domains_block.block_contents.find_by(locale: I18n.locale)
      content = image.domains_block.block_contents.find_by(locale: I18n.default_locale) if content.nil?
    end
    content.nil? ? nil : content.body.html_safe
  end

  def available_image_providers
    if current_user.is_admin && request.path =~ /admin/
      ContainerImageProvider.all
    else
      ContainerImageProvider.where("container_registry_id is null OR container_registry_id IN (?)", ContainerRegistry.find_all_for(current_user).pluck(:id))
    end
  end

  def image_minimums(image)
    d = []
    d << "#{image.min_cpu} CPU" if image.min_cpu > 0
    d << "#{image.min_memory} MB" if image.min_memory > 0
    d.join(' / ')
  end

  def image_table_buttons(image)
    btns = [
      link_to("#{icon('fa-solid', 'copy')} #{t('container_images.clone')}".html_safe, "#{request.path =~ /admin/ ? '/admin' : ''}/container_images/new?container_image[parent_image_id]=#{image.id}", class: 'btn btn-sm btn-default'),
      link_to(icon('fa-solid', 'gear'), "#{request.path =~ /admin/ ? '/admin' : ''}/container_images/#{image.id}", class: 'btn btn-sm btn-default')
    ]
    if image.can_administer?(current_user)
      btns << link_to(icon('fa-solid', 'trash'), "#{request.path =~ /admin/ ? '/admin' : ''}/container_images/#{image.id}", method: :delete, data: {confirm: t('confirm_prompt')}, class: 'btn btn-sm btn-danger')
    else
      btns << link_to(icon('fa-solid', 'trash'), "/container_images/#{image.id}", disabled: 'disabled', title: 'only owners can delete', class: 'btn btn-sm btn-danger')
    end
    %Q(
      <div class="text-right" style="vertical-align: middle;">
        <div class="btn-group">
          #{btns.join("\n")}
        </div>
      </div>
    )
  end

end
