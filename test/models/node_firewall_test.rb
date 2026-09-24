require "test_helper"
require "minitest/mock"

##
# PR3: node firewall rules are pushed to the node's cs-agent (which reconciles nftables on
# the PUT), replacing the old Consul KV write + reload-job trigger.
class NodeFirewallTest < ActiveSupport::TestCase
  class FakeAgentClient
    attr_reader :calls

    def initialize
      @calls = []
    end

    def put_firewall_rules(host, rules)
      @calls << [host, rules]
      true
    end
  end

  # Mirrors Agent::Client#put_firewall_rules' contract on failure: it folds transport
  # errors AND non-2xx responses into a bare `false`, never an exception.
  class FailingAgentClient < FakeAgentClient
    def put_firewall_rules(host, rules)
      super
      false
    end
  end

  PUSH_FAILED = "6b0f2d4c9a71e835".freeze

  setup do
    @node = nodes(:testone)
    @fake = FakeAgentClient.new
  end

  test "update_iptable_config! PUTs the NatRules to the node's agent and returns true" do
    result = Agent::Client.stub(:for_node, @fake) { @node.update_iptable_config! }
    assert_equal true, result
    assert_equal 1, @fake.calls.size
    host, rules = @fake.calls.first
    assert_equal @node.hostname, host
    assert rules.key?(:rules), "body must be the already-shaped {rules:[...]} NatRules JSON"
  end

  test "update_iptable_config! no longer accepts a trigger_reload argument" do
    # The Consul reload trigger is gone (the agent reconciles on PUT); the method is arity 0.
    assert_equal 0, @node.method(:update_iptable_config!).arity
  end

  ##
  # A rule-build failure must never reach the agent as an empty ruleset. The agent reconciles
  # nftables to exactly what it receives, so PUTting {rules: []} would close every published
  # port on the node — and the cutover backfill would report [ok] and latch the sentinel while
  # doing it.
  test "update_iptable_config! reports failure instead of PUTting an empty ruleset when rule building raises" do
    @node.stub(:iptable_rules, -> { raise ActiveRecord::StatementInvalid, "boom" }) do
      ExceptionAlertService.stub(:new, ->(*) { Struct.new(:perform).new(nil) }) do
        result = Agent::Client.stub(:for_node, @fake) { @node.update_iptable_config! }
        assert_equal false, result, "a rule-build failure must report not-pushed"
      end
    end
    assert_empty @fake.calls, "nothing may be PUT to the agent when the ruleset could not be built"
  end

  ##
  # A rejected push leaves nftables stale with nothing else to correct it: put_firewall_rules
  # swallows transport errors into `false`, ReloadIptableWorker discards the return value and
  # is retry: false, and there is no periodic firewall reconcile in lib/clock.rb. A misconfigured
  # agent_host must therefore be loud here or it is invisible.
  test "a rejected push reports a SystemEvent and returns false" do
    # Configure an override so the recorded address is distinguishable from primary_ip —
    # otherwise the assertion below passes even if the reporter names the wrong attribute.
    @node.update!(agent_host: "100.64.79.114")
    assert_not_equal @node.primary_ip, @node.agent_address

    failing = FailingAgentClient.new
    result = nil
    assert_difference -> { SystemEvent.where(event_code: PUSH_FAILED).count }, 1 do
      result = Agent::Client.stub(:for_node, failing) { @node.update_iptable_config! }
    end
    assert_equal false, result
    assert_equal 1, failing.calls.size, "the push must still have been attempted"

    event = SystemEvent.where(event_code: PUSH_FAILED).last
    assert_equal "100.64.79.114", event.data["agent_address"],
      "the event must name the address that was actually dialed, not primary_ip"
    assert_includes event.message, "[node #{@node.id}]",
      "the dedupe key must be node-unique; labels are not"
  end

  test "repeated rejected pushes are deduped within the 15 minute window" do
    failing = FailingAgentClient.new
    assert_difference -> { SystemEvent.where(event_code: PUSH_FAILED).count }, 1 do
      Agent::Client.stub(:for_node, failing) do
        3.times { @node.update_iptable_config! }
      end
    end
  end

  test "a successful push reports nothing" do
    assert_no_difference -> { SystemEvent.where(event_code: PUSH_FAILED).count } do
      Agent::Client.stub(:for_node, @fake) { @node.update_iptable_config! }
    end
  end

  test "a rule-build failure does not also report a push failure" do
    @node.stub(:iptable_rules, -> { raise ActiveRecord::StatementInvalid, "boom" }) do
      ExceptionAlertService.stub(:new, ->(*) { Struct.new(:perform).new(nil) }) do
        assert_no_difference -> { SystemEvent.where(event_code: PUSH_FAILED).count } do
          Agent::Client.stub(:for_node, @fake) { @node.update_iptable_config! }
        end
      end
    end
  end

  test "a rule-build failure still raises an exception alert" do
    alerted = []
    fake_alert = Class.new do
      define_method(:initialize) { |e, code| alerted << [e.class, code] }
      define_method(:perform) { nil }
    end
    @node.stub(:iptable_rules, -> { raise ActiveRecord::StatementInvalid, "boom" }) do
      ExceptionAlertService.stub(:new, ->(e, code) { fake_alert.new(e, code) }) do
        Agent::Client.stub(:for_node, @fake) { @node.update_iptable_config! }
      end
    end
    assert_equal 1, alerted.size
    assert_equal "ea45d8edfbcc4c7b", alerted.first.last
  end
end
