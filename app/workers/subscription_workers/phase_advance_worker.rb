module SubscriptionWorkers
  class PhaseAdvanceWorker
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform
      SubscriptionProduct.where.not(phase_type: 'final').each do |sb|
        handle_phase_migration sb
      end
    rescue => e
      ExceptionAlertService.new(e, '00024f5a8612b12f').perform
    end

    private

    ##
    # Handle phase migration for a given subscription product
    #
    #
    # @param [SubscriptionProduct] sb
    # @return [void]
    def handle_phase_migration(sb)
      billing_plan = sb.user.billing_plan
      if billing_plan.nil? || sb.phase_type.nil?
        sb.update_attribute :phase_type, 'final'
        return
      end
      expected_phase = sb.billing_resource.determine_phase(sb)
      current_phase = sb.phase_type
      return if expected_phase == current_phase
      sb.update_attribute :phase_type, expected_phase
      audit = Audit.create_from_object!(sb, 'updated', '127.0.0.1')
      sb.billing_events.create!(
          subscription: sb.subscription,
          from_phase: current_phase,
          to_phase: expected_phase,
          audit: audit
      )
    rescue => e
      ExceptionAlertService.new(e, '68ad19bd3a3ad02d').perform
    end

  end
end
