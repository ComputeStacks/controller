##
# =Shared Memory (/dev/shm) Size validation for a container service
#
# `shm_size` is stored in bytes (0 = use the container image default). When a value is set
# we cap it at the service's memory limit (bytes) — a /dev/shm larger than the container's
# memory is a foot-gun, and Docker counts the tmpfs against the memory cgroup anyway.
#
# Only enforced when `shm_size` is actually changing. `Deployment::ContainerService` is
# `.update(...)`-ed on unrelated attributes by sync paths that ignore the return value
# (e.g. Deployment::Container#update_service_resource during a resize); guarding on
# `shm_size_changed?` keeps those saves from silently failing for services that already
# carry a large (console-set) shm_size.
class ShmSizeValidator < ActiveModel::Validator
  def validate(record)
    return unless record.shm_size_changed?

    shm = record.shm_size
    return if shm.nil?

    if shm.negative?
      record.errors.add(:shm_size, "must be greater than or equal to 0")
      return
    end

    return if shm.zero? # 0 = use the image default; nothing to cap

    mem = record.memory
    return if mem.nil? || mem.zero? # no memory limit to enforce against

    mem_bytes = mem * 1_048_576
    if shm > mem_bytes
      record.errors.add(:shm_size, "cannot exceed the service's memory limit (#{mem} MB)")
    end
  end
end
