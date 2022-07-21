module Orders
  module StateManager
    extend ActiveSupport::Concern

    included do
      scope :pending, -> { where( Arel.sql( %Q(status IN ('#{pending_statuses.join("','")}')) )) }
      scope :pending_projects, -> { where Arel.sql(%Q(deployment_id IS NULL AND status IN ('#{(pending_statuses + ['processing']).join("','")}'))) }
    end

    class_methods do

      def pending_statuses
        %w(
          awaiting_payment
          open
          pending
        )
      end

      def allowed_statuses
        %w(
          open
          pending
          awaiting_payment
          processing
          cancelled
          completed
          failed
        )
      end

    end

    ##
    # State Questions

    def pending?
      Order.pending_statuses.include? status
    end

    def processing?
      status == 'processing'
    end

    def can_process?
      pending? && !need_payment?
    end

    def done?
      !success? && !failed? && !cancelled?
    end

    def need_payment?
      status == 'awaiting_payment'
    end

    def cancelled?
      status == 'cancelled'
    end

    def success?
      status == 'completed'
    end

    def failed?
      status == 'failed'
    end

    ##
    # Update State

    def processing!
      update_attribute :status, 'processing'
    end

    def open!
      update_attribute :status, 'open'
    end

    def pending!
      update_attribute :status, 'pending'
    end

    def need_payment!
      update_attribute :status, 'awaiting_payment'
    end

    def fail!
      update_attribute :status, 'failed'
    end

    def cancel!
      update_attribute :status, 'cancelled'
    end

    def done!
      update_attribute :status, 'completed'
    end

  end
end
