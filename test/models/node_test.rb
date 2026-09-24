require "test_helper"

class NodeTest < ActiveSupport::TestCase
  test "agent_token round-trips through encryption and is not stored in plaintext" do
    node = nodes(:testone)
    node.update!(agent_token: "super-secret-bearer")
    assert_equal "super-secret-bearer", node.reload.agent_token
    refute_equal "super-secret-bearer", node.agent_token_encrypted
  end

  test "agent_token_hash is nil when unset and lowercase sha256 hex when set" do
    node = nodes(:testone)
    node.update_columns(agent_token_encrypted: nil)
    assert_nil node.agent_token_hash

    node.update!(agent_token: "abc")
    assert_equal Digest::SHA256.hexdigest("abc"), node.agent_token_hash
  end

  test "mints an agent_token on create and does not re-mint on later save" do
    node = Node.create!(
      region: regions(:regionone),
      label: "mint-test",
      hostname: "mint-test-host",
      primary_ip: "10.99.0.9",
      public_ip: "10.99.0.9"
    )
    assert node.agent_token.present?, "expected a token minted on create"
    minted = node.agent_token

    node.update!(label: "mint-test-renamed")
    assert_equal minted, node.reload.agent_token, "token must not be re-minted on later saves"
  end

  # --- agent_host / agent_address -------------------------------------------------

  test "agent_address falls back to primary_ip when agent_host is unset" do
    node = nodes(:testone)
    assert_nil node.agent_host
    assert_equal node.primary_ip, node.agent_address
  end

  test "agent_address returns agent_host when set" do
    node = nodes(:testone)
    was = node.primary_ip
    node.update!(agent_host: "100.64.79.114")
    assert_equal "100.64.79.114", node.agent_address
    assert_equal was, node.reload.primary_ip, "primary_ip must be untouched"
    assert_not_equal node.primary_ip, node.agent_address
  end

  test "a blank agent_host is stored as NULL and falls back" do
    node = nodes(:testone)
    node.update!(agent_host: "   ")
    assert_nil node.reload.agent_host
    assert_equal node.primary_ip, node.agent_address
  end

  test "surrounding whitespace is stripped rather than failing validation" do
    node = nodes(:testone)
    node.update!(agent_host: "  100.64.79.114\t")
    assert_equal "100.64.79.114", node.reload.agent_host
  end

  test "agent_host accepts an IPv4 literal or a DNS name and rejects junk" do
    node = nodes(:testone)

    %w[100.64.79.114 node1.tailnet-abcd.ts.net cs-node-1].each do |good|
      node.agent_host = good
      assert node.valid?, "expected #{good.inspect} to be accepted: #{node.errors.full_messages.join(", ")}"
    end

    # IPv6 is rejected: agent_address is interpolated into a URL without brackets.
    ["fd7a:115c:a1e0::1", "100.64.79.114:8500", "http://100.64.79.114", "has space", "-leading.dash"].each do |bad|
      node.agent_host = bad
      assert_not node.valid?, "expected #{bad.inspect} to be rejected"
    end
  end
end
