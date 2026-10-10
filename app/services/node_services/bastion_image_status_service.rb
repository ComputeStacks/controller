module NodeServices
  ##
  # Refresh the stored `on_latest_image` flag for every bastion on a node.
  #
  # The bastion API reads this column instead of querying the node per request (a slow node
  # used to stall the request past client timeouts). Run daily by
  # NodeWorkers::UpdateImageWorker, right after it pulls the bastion image.
  #
  # Compares each bastion's running image against the *configured* bastion image
  # (Setting.computestacks_bastion_image -- what a rebuild would use), so after the setting
  # moves to a new tag, existing bastions report false until rebuilt.
  #
  # Anything we cannot determine leaves the stored values alone. Never raises.
  class BastionImageStatusService
    attr_accessor :node

    # @param [Node] node
    def initialize(node)
      self.node = node
    end

    # @return [Boolean] true if the node was checked
    def perform
      return false if node.nil? || !node.online?

      bastions = Deployment::Sftp.where(node_id: node.id).to_a
      return false if bastions.empty?

      client = node.client(1)
      current_image_id = Docker::Image.get(Setting.computestacks_bastion_image, {}, client).id

      # Not Node#list_all_containers: it rescues to [], which is indistinguishable from
      # "no containers" and would leave us unable to tell a failure from an empty node.
      running = Docker::Container.all({all: true}, client).each_with_object({}) do |container, map|
        image_id = container.info["ImageID"]
        Array(container.info["Names"]).each { |n| map[n.delete_prefix("/")] = image_id }
      end

      bastions.each do |bastion|
        next unless running.key?(bastion.name)

        latest = running[bastion.name] == current_image_id
        bastion.update_column(:on_latest_image, latest) unless bastion.on_latest_image == latest
      end
      true
    rescue
      # Routine connectivity failures (or a failed pull leaving the image absent) are
      # expected here; keep the previous values and try again tomorrow.
      false
    end
  end
end
