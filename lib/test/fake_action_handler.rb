# Test double for a ContainerActionRegistry handler: configurable #owns? / result
# and a class-level call counter, so the generic dispatch pipeline can be exercised
# in the core suite without the commercial engine. Dispatch/projector/sweep tests
# register it under a test action_type and read FakeActionHandler.calls.
class FakeActionHandler
  Result = Struct.new(:status, :reason, :http_status, keyword_init: true)

  class << self
    attr_accessor :owns, :result, :calls

    def reset!(owns: true, result: Result.new(status: :accepted))
      self.owns = owns
      self.result = result
      self.calls = 0
    end
  end
  reset!

  def owns?(_deployment)
    self.class.owns
  end

  def call(_req)
    self.class.calls += 1
    self.class.result
  end
end
