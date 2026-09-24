require "test_helper"

class Api::System::AgentTokensControllerTest < ActionDispatch::IntegrationTest
  PATH = "/api/system/nodes/agent_token_hash"

  setup do
    @node = nodes(:testone)
    @node.update!(agent_token: "node-admin-bearer")
    @prev = ENV["NODE_ENROLLMENT_TOKEN"]
    ENV["NODE_ENROLLMENT_TOKEN"] = "enrollment-secret"
  end

  teardown { ENV["NODE_ENROLLMENT_TOKEN"] = @prev }

  # The node is identified by source IP; tests run in `test` env (not the dev
  # Node.first fallback), so set REMOTE_ADDR to the node's IP.
  def get_hash(bearer:, ip: @node.primary_ip)
    get PATH, headers: {"Authorization" => "Bearer #{bearer}", "REMOTE_ADDR" => ip}
  end

  test "returns the node's agent_token_hash for a request from the node's IP" do
    get_hash(bearer: "enrollment-secret")
    assert_response :success
    assert_equal @node.agent_token_hash, JSON.parse(response.body)["agent_token_hash"]
  end

  test "401 with a wrong Bearer" do
    get_hash(bearer: "wrong")
    assert_response :unauthorized
  end

  test "401 when NODE_ENROLLMENT_TOKEN is unset (even with a matching empty Bearer)" do
    ENV["NODE_ENROLLMENT_TOKEN"] = ""
    get PATH, headers: {"Authorization" => "Bearer ", "REMOTE_ADDR" => @node.primary_ip}
    assert_response :unauthorized
  end

  test "404 when the source IP matches no node" do
    get_hash(bearer: "enrollment-secret", ip: "203.0.113.255")
    assert_response :not_found
  end
end
