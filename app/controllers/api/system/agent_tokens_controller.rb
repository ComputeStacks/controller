##
# Serves a node's admin-token *hash* to the provisioner, which installs it as
# the cs-agent's `admin.token_hash`. Gated by the shared NODE_ENROLLMENT_TOKEN
# (controller env + Ansible vault) — NOT the IP-trust the rest of the system API
# relies on, since this touches admin-credential material. IP-independent; only
# the non-reversible sha256 is ever returned (a leaked enrollment secret exposes
# hashes, never usable admin Bearers). The plaintext admin token never leaves
# the controller.
class Api::System::AgentTokensController < Api::System::BaseController
  before_action :require_enrollment_token

  # GET /api/system/nodes/agent_token_hash
  #
  # The node identifies itself by its SOURCE IP (the request originates on the
  # node, as in IngressRulesController) — matched against primary_ip/public_ip
  # since it may reach the controller over either. Auth is the enrollment token,
  # not the IP, so a stray caller can't read a hash without the secret.
  def show
    node = resolve_node
    # head/render directly (not api_obj_missing, which needs format negotiation) so
    # the response is format-independent, matching the JSON success path below.
    return head(:not_found) if node.nil?

    render json: {agent_token_hash: node.agent_token_hash}
  end

  private

  def resolve_node
    remote_ip = request.remote_ip.to_s.gsub("::ffff:", "")
    Node.find_by("primary_ip = :ip OR public_ip = :ip", ip: remote_ip)
  end

  def require_enrollment_token
    expected = ENV["NODE_ENROLLMENT_TOKEN"].to_s
    return head(:unauthorized) if expected.blank?

    presented = request.headers["Authorization"].to_s.sub(/\ABearer\s+/i, "")
    # Compare fixed-length SHA-256 digests: equal length (so no length leak) and
    # constant-time. (This is the same construction ActiveSupport's secure_compare
    # uses internally, made explicit per the review.)
    unless ActiveSupport::SecurityUtils.fixed_length_secure_compare(
      Digest::SHA256.digest(presented), Digest::SHA256.digest(expected)
    )
      head :unauthorized
    end
  end
end
