module NodeServices
  ##
  # The ONLY writer of `Node#customer_notice`: the message customers see (portal banner,
  # API `node_status.message`) while a node is in maintenance or offline. Separate from
  # the internal `maintenance_reason`, which customers never see.
  #
  #   NodeServices::CustomerNoticeService.new(node, notice: "Kernel upgrade", actor: user, remote_ip: ip).perform
  #
  # A blank notice clears it, which is always allowed. Setting one is refused while the
  # node is online: the notice is cleared automatically when the node returns to online
  # (Node#clear_customer_notice_if_online!), so it can never outlive its incident.
  #
  # Every change is audited with the actor and IP.
  class CustomerNoticeService
    attr_reader :node, :notice, :actor, :remote_ip, :errors

    def initialize(node, notice:, actor: nil, remote_ip: nil)
      @node = node
      @notice = notice.to_s.strip.presence
      @actor = actor
      @remote_ip = remote_ip.presence || "127.0.0.1"
      @errors = []
    end

    # @return [Boolean]
    def perform
      Node.transaction do
        # Row lock: the auto-clear on return to online waits for this, so a notice
        # cannot be set on a node that has just come back.
        locked = Node.lock.find(node.id)
        if notice && Nodes::CustomerStatusPresenter.state_for(locked) == "online"
          errors << "A customer notice can only be set while the node is in maintenance or offline."
          raise ActiveRecord::Rollback
        end
        next if locked.customer_notice == notice

        previous = locked.customer_notice
        locked.update_column :customer_notice, notice
        audit = Audit.create_from_object!(node, "updated", remote_ip, actor)
        # What customers were shown, so a published notice can be reconstructed later.
        audit.update_attribute :raw_data, {"customer_notice" => {"from" => previous, "to" => notice}}
      end
      node.reload
      errors.empty?
    rescue ActiveRecord::ActiveRecordError => e
      errors << e.message
      false
    end
  end
end
