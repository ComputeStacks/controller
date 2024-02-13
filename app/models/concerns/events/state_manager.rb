module Events
  module StateManager
    extend ActiveSupport::Concern

    included do
      scope :active, -> { where "status = 'pending' OR status = 'running'" }
      scope :running, -> { where status: 'running' }
      scope :pending, -> { where status: 'pending' }
      scope :failed, -> { where status: 'failed' }
    end

    # @return [Boolean]
    def pending?
      status == 'pending'
    end

    # @return [Boolean]
    def running?
      status == 'running'
    end

    # @return [Boolean]
    def cancelled?
      status == 'cancelled'
    end

    # @return [Boolean]
    def active?
      running? || pending?
    end

    # @return [Boolean]
    def done?
      !active?
    end

    # @return [Boolean]
    def success?
      status == 'completed'
    end

    # @return [Boolean]
    def failed?
      status == 'failed'
    end

    # @return [Boolean]
    def pending!
      return true if pending?
      update status: 'pending'
    end

    # @return [Boolean]
    def start!(msg = nil)
      return false if failed? || cancelled?
      msg.blank? ? update(status: 'running') : update(status: 'running', state_reason: msg)
    end

    # @return [Boolean]
    def done!(msg = nil)
      return false unless active?
      msg.blank? ? update(status: 'completed') : update(status: 'completed', state_reason: msg)
      perform_callback_reply!
    end

    # @return [Boolean]
    def cancel!(msg)
      return false unless active?
      update status: 'cancelled', state_reason: msg
      perform_callback_reply!
    end

    # @return [Boolean]
    def fail!(msg)
      return false unless active?
      update status: 'failed', state_reason: msg
      perform_callback_reply!
    end

    # Handle any callbacks added to this event
    def perform_callback_reply!
      return if labels.empty?
      return if labels['callback_url'].blank?

      d = {
        'timestamp' => Time.now.to_i,
        'event_id' => id,
        'callback' => {
          'authorization' => labels['callback_auth'],
          'url' => labels['callback_url']
        }
      }

      CallbackWorker.perform_async d
      true
    end

  end
end
