require "test_helper"

class Api::Stacks::LoadBalancersControllerTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  test "authenticate and retrieve load balancer configuration" do
    node = Deployment::ContainerService.web_only.first.nodes.first
    assert_not_nil node

    lb = LoadBalancer.find_by_node node
    assert_not_nil lb
    auth = ClusterAuthService.new(lb)
    auth.node = node
    auth_token = auth.generate_auth_token!

    get "/api/stacks/load_balancers", headers: {
      "Accept" => "text/plain",
      "Authorization" => "Bearer #{auth_token}"
    }

    assert_response :success

    # Ensure all services are present
    node.container_services.web_only.each do |service|
      service.ingress_rules.each do |ingress|
        rule = Digest::MD5.hexdigest("#{service.name}#{ingress.id}")
        assert_match(/backend #{rule}/, response.body)
        assert_match(/use_backend S_#{rule}/, response.body)
        service.containers.each do |container|
          assert_match(/server #{container.name} #{container.ip_address.ipaddr}:#{ingress.port}/, response.body)
        end
      end
    end

    body = response.body

    # --- Edge hardening (Phase 1) ---

    # Baseline security response headers, injected only if the backend did not set its own.
    assert_match(%r{http-response set-header X-Content-Type-Options nosniff if !\{ res\.hdr\(X-Content-Type-Options\) -m found \}}, body)
    assert_match(%r{http-response set-header Referrer-Policy strict-origin-when-cross-origin if !\{ res\.hdr\(Referrer-Policy\) -m found \}}, body)
    assert_match(/http-response del-header Server/, body)

    # Forwarding-header hygiene is present, but the existing real-client-IP flooring is untouched.
    assert_match(/http-request del-header X-Client-IP/, body)
    assert_match(/http-request del-header X-Forwarded-Host if !proxied_conn/, body)
    assert_match(/http-request set-header X-Real-IP %\[src\]/, body)
    assert_match(/http-request set-header X-Forwarded-For %\[src\]/, body)
    refute_match(/del-header X-Real-IP/, body)
    refute_match(/del-header X-Forwarded-For\b/, body)

    # :443 host ACLs are now case-insensitive; the dead/typo'd HSTS dummy ACL is gone.
    assert_match(/acl host_rule_\d+ var\(txn\.host\) -m str -i /, body)
    refute_match(/hsts-dummy\.local/, body)

    # force_ssl domains get a same-host http->https Location rewrite...
    assert_match(%r{http-response replace-header Location \^http://}, body)

    # ...but the intentionally http-only tenant (force_ssl? false) does NOT, and instead
    # takes the http-frontend use_backend branch (previously uncovered).
    http_only = deployment_container_domains(:plain_http_only)
    refute_match(%r{replace-header Location \^http://#{Regexp.escape(http_only.domain)}}, body)
    http_only_rule = Digest::MD5.hexdigest("#{http_only.container_service.name}#{http_only.ingress_rule.id}")
    assert_match(/use_backend #{http_only_rule} if host_rule_\d+/, body)

    # --- Edge hardening (Phase 2): per-domain HSTS directives + X-Frame-Options ---
    # nginx_default opts into includeSubDomains + preload + X-Frame-Options.
    assert_match(%r{http-response set-header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" if host_rule_\d+}, body)
    assert_match(/http-response set-header X-Frame-Options SAMEORIGIN if host_rule_\d+/, body)
    # Domains without the sub-toggles emit only the base max-age (no directives)...
    assert_match(%r{http-response set-header Strict-Transport-Security "max-age=63072000" if host_rule_\d+}, body)
    # ...and the old always-on, preload-ineligible value is gone.
    refute_match(/max-age=63072000; preload;/, body)
  end
end
