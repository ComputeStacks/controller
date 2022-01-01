##
# Migrate a container off the current node.
#
# This will automatically pick a new node.
#
# @!attribute container
#   @return [Deployment::Container]
# @!attribute event
#   @return [EventLog]
# @!attribute new_node
#   @return [Node]
class ContainerMigratorService

  attr_accessor :container,
                :event,
                :new_node

  # @param [Deployment::Container] container
  # @param [EventLog] event
  def initialize(container, event)
    self.container = container
    self.new_node = nil
    self.event = event
  end

  # @return [Boolean]
  def perform
    return false unless can_migrate?
    container.set_is_migrating!
    event.start!
    kill_existing! unless container.node.disconnected
    migrate!
  ensure
    # Return containers back to their previous state
    container.update_attribute(:status, container.req_state) if container.status == 'migrating'
  end

  private

  # @return [Boolean]
  def migrate!
    existing_node = container.node
    unless container.update_attribute :node, new_node
      event.event_details.create!(
        event_code: '0c4acb9fc7bf05d0',
        data: "Failed to update node: #{container.errors.full_messages(' ')}"
      )
      event.fail! 'Failed to update container node'
      return false
    end
    container.update node: new_node

    # Force cleanup the network
    begin
      net_client = container.ip_address.network.docker_client new_node
      net_client.disconnect(container.name, {}, { 'Force' => true })
      Network::Cidr.release! new_node, container.ip_address.cidr.to_s
    rescue
      # Ignore and drop any errors
    end

    provisioner = PowerCycleContainerService.new(container, 'build', event.audit)

    if provisioner.perform
      event.event_details.create!(
        data: "Migrated from node #{existing_node.label} to #{new_node.label}.",
        event_code: '52724bcdd6721794'
      )
      event.done!
      true
    else
      event.event_details.create!(
        data: "Fatal error provisioning container #{container.name} on #{new_node.label}",
        event_code: 'e192b31640cb6d08'
      )
      event.fail! 'Fatal error during provisioning'
      false
    end
  end

  ##
  # Kill existing containers
  #
  # Not super critical what the result is, but
  # if we're evacuating an online node,
  # performing these steps on even a partial set will
  # dramatically improve the overall cluster stability.
  def kill_existing!
    c = container.docker_client
    return true if c.nil?
    c.stop
    sleep(2)
    c.delete
  rescue
    # if this fails, then ignore it and continue to build on new server.
    true
  end

  # @return [Boolean]
  def can_migrate?
    unless container.can_migrate?
      event.event_details.create!(
        event_code: '27bae2d7240d3b98',
        data: "Unable to migrate container due to volume constraint."
      )
      event.cancel! 'Volume blocking migration'
      return false
    end
    unless has_new_home?
      event.event_details.create!(
        event_code: '19ac5752519b691e',
        data: "Unable to migrate: there are no nodes available."
      )
      event.cancel! 'No online nodes'
      return false
    end
    true
  end

  def has_new_home?
    return true unless self.new_node.nil?
    self.new_node = container.region.find_node container.package_for_node, container.node
    !new_node.nil?
  end

end
