class CollaborationMailer < ApplicationMailer

  ##
  # Notify user of invite to join Dns::Zone
  #
  # @param [Dns::Zone] zone
  # @param [User] user
  def dns_invite(zone, user)
    block = Block.find_by(content_key: 'collaborate.invite.domain')
    return if block.nil?
    content = block.find_content_by_locale(user.locale.blank? ? 'en' : user.locale)
    return if content.nil?
    @body = content.parsed_body(zone).gsub("h4","h1")
    mail to: user.email, subject: I18n.t("collaborators.mailer.subject.dns", locale: user.locale_sym, app: Setting.app_name, zone: zone.name)
  end

  ##
  # Notify user of invite to join ContainerImage
  #
  # @param [ContainerImage] image
  # @param [User] user
  def image_invite(image, user)
    block = Block.find_by(content_key: 'collaborate.invite.image')
    return if block.nil?
    content = block.find_content_by_locale(user.locale.blank? ? 'en' : user.locale)
    return if content.nil?
    @body = content.parsed_body(image).gsub("h4","h1")
    mail to: user.email, subject: "[#{Setting.app_name}] Image Collaboration Invitation: #{image.label}"
  end

  ##
  # Notify user of invite to join Deployment
  #
  # @param [Deployment] project
  # @param [User] user
  def project_invite(project, user)
    block = Block.find_by(content_key: 'collaborate.invite.project')
    return if block.nil?
    content = block.find_content_by_locale(user.locale.blank? ? 'en' : user.locale)
    return if content.nil?
    @body = content.parsed_body(project).gsub("h4","h1")
    mail to: user.email, subject: I18n.t("collaborators.mailer.subject.project", locale: user.locale_sym, app: Setting.app_name, project: project.name)
  end

  ##
  # Notify user of invite to join Container Registry
  #
  # @param [ContainerRegistry] registry
  # @param [User] user
  def registry_invite(registry, user)
    block = Block.find_by(content_key: 'collaborate.invite.registry')
    return if block.nil?
    content = block.find_content_by_locale(user.locale.blank? ? 'en' : user.locale)
    return if content.nil?
    @body = content.parsed_body(registry).gsub("h4","h1")
    mail to: user.email, subject: I18n.t("collaborators.mailer.subject.registry", locale: user.locale_sym, app: Setting.app_name, registry: registry.label)
  end

end
