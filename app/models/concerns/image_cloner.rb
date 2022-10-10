module ImageCloner
  extend ActiveSupport::Concern

  included do
    attr_accessor :parent_image_id
    #after_create_commit :clone!, if: :parent_image_id
    after_create :clone!, if: :parent_image_id
    validate :can_clone?, on: [:create], if: :parent_image_id
  end

  private

  def can_clone?
    return nil if parent_image_id.blank?
    return errors.add(:base, "You do not have permission to clone that image.") if current_user.nil?
    unless ContainerImage.where("id = ? AND (user_id IS NULL OR user_id = ?)", parent_image_id, current_user.id).exists?
      errors.add(:base, "You do not have permission to clone that image.")
    end
  end

  def clone!
    parent_image = ContainerImage.find_by(id: parent_image_id)
    return false unless parent_image.is_a?(ContainerImage) && parent_image != self
    local_errors = []

    parent_image.image_variants.each do |i|
      next if image_variants.where(registry_image_tag: i.registry_image_tag).exists?
      new_variant = i.dup
      new_variant.current_user = current_user
      new_variant.container_image_id = self.id
      new_variant.save
    end

    parent_image.host_entries.each do |i|
      new_entry = i.dup
      new_entry.current_user = current_user
      new_entry.container_image_id = self.id
      new_entry.save
    end

    parent_image.dependency_parents.each do |i|
      new_param = i.dup
      new_param.current_user = current_user
      new_param.container_image_id = self.id
      unless new_param.save
        local_errors << {
          kind: 'dependeny_params',
          parant_param_id: i.id,
          errors: new_param.errors.full_messages
        }
      end
    end
    parent_image.setting_params.each do |i|
      new_param = i.dup
      new_param.container_image_id = self.id
      unless new_param.save
        local_errors << {
          kind: 'setting_param',
          parant_param_id: i.id,
          errors: new_param.errors.full_messages
        }
      end
    end
    parent_image.env_params.each do |i|
      new_param = i.dup
      new_param.static_value = new_param.value if new_param.param_type == 'static'
      new_param.env_value = new_param.value if new_param.param_type == 'variable'
      new_param.container_image_id = self.id
      unless new_param.save
        local_errors << {
          kind: 'env_param',
          parant_param_id: i.id,
          errors: new_param.errors.full_messages
        }
      end
    end
    parent_image.ingress_params.each do |i|
      new_param = i.dup
      new_param.container_image_id = self.id
      unless new_param.save
        local_errors << {
          kind: 'ingress_param',
          parant_param_id: i.id,
          errors: new_param.errors.full_messages
        }
      end
    end
    parent_image.volumes.each do |i|
      new_param = i.dup
      new_param.container_image_id = self.id
      unless new_param.save
        local_errors << {
          kind: 'volume_param',
          parant_param_id: i.id,
          errors: new_param.errors.full_messages
        }
      end
    end

    unless local_errors.empty?
      SystemEvent.create!(
        message: "Error Cloning Image: #{parent_image.name}",
        data: local_errors,
        event_code: "#{id}-2a88db8ed4539a18"
      )
    end

    true
  end

end
