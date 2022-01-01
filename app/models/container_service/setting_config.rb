##
# ContainerService Setting Parameter
#
# Used to populate Environmental variables
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute name
#   @return [String]
#
# @!attribute param_type
#   @return [static,password]
#
# @!attribute value
#   @return [String]
#
# @!attribute container_service
#   @return [Deployment::ContainerService]
#
# @!attribute deployment
#   @return [Deployment]
#
# @!attribute parent_param
#   @return [ContainerImage::SettingParam]
#
class ContainerService::SettingConfig < ApplicationRecord

  scope :sorted, -> { order( Arel.sql('lower(name)') ) }

  belongs_to :container_service, class_name: "Deployment::ContainerService"
  belongs_to :parent_param, class_name: "ContainerImage::SettingParam", foreign_key: "container_image_setting_param_id", optional: true

  has_one :deployment, through: :container_service

  validates :name, presence: true

  before_save :set_label

  after_save :refresh_metadata, unless: Proc.new { |i| i.skip_metadata_refresh }

  before_destroy :clean_env, prepend: true, if: Proc.new { safe_delete }
  attr_accessor :safe_delete,
                :skip_metadata_refresh

  def decrypted_value
    self.param_type == 'password' ? Secret.decrypt!(self.value) : self.value
  end

  private

  def set_label
    self.label = name if label.blank?
  end

  def clean_env
    return unless container_service
    container_service.env_params.where(value: "build.settings.#{name}", param_type: 'variable').each do |i|
      unless i.update(param_type: 'static', static_value: decrypted_value)
        errors.add(:base, i.errors.full_messages.join(' '))
        throw :abort
      end
    end
    container_service.dependent_services.each do |s|
      s.env_params.where(value: "dep.#{container_service.container_image.role}.parameters.settings.#{name}", param_type: 'variable').each do |i|
        unless i.update(param_type: 'static', static_value: decrypted_value)
          errors.add(:base, i.errors.full_messages.join(' '))
          throw :abort
        end
      end
    end
  end

  def refresh_metadata
    return if deployment.nil?
    ProjectWorkers::RefreshMetadataWorker.perform_async deployment.id
  end

end
