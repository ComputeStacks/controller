require "test_helper"
require "tmpdir"

class LetsEncryptServices::CertIssuerRunnerTest < ActiveSupport::TestCase
  setup { @dir = Dir.mktmpdir("cert-issuer-test") }
  teardown { FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir) }

  def script(body, shebang: "#!/bin/sh")
    path = File.join(@dir, "fake-#{SecureRandom.hex(4)}")
    File.write(path, "#{shebang}\n#{body}\n")
    File.chmod(0o755, path)
    path
  end

  def runner(body, shebang: "#!/bin/sh", **opts)
    LetsEncryptServices::CertIssuerRunner.new(binary: script(body, shebang: shebang), **opts)
  end

  def run_it(r, request: {"a" => 1}, env: {}, timeout: 10)
    r.run(request: request, env: env, timeout: timeout)
  end

  def error_doc(type, extra = "")
    %({"version":1,"status":"error","error":{"type":"#{type}","message":"boom"#{extra}}})
  end

  test "ok document" do
    res = run_it(runner(%(cat >/dev/null; echo '{"version":1,"status":"ok","names":["a.example"]}')))
    assert res.ok?
    assert_nil res.error_type
    assert_equal ["a.example"], res.payload["names"]
    assert_equal 0, res.exit_status
    assert_equal({}, res.error)
  end

  %w[config validation_failed rate_limited transient internal].each do |type|
    test "error type #{type}" do
      res = run_it(runner(%(cat >/dev/null; echo '#{error_doc(type)}'; exit 10)))
      assert_not res.ok?
      assert_equal type, res.error_type
      assert_equal "boom", res.error["message"]
      assert_equal 10, res.exit_status
    end
  end

  test "garbage stdout is internal" do
    res = run_it(runner("cat >/dev/null; echo not-json"))
    assert_equal "internal", res.error_type
    assert_match(/no JSON result/, res.error["message"])
    assert_equal 1, res.payload["version"]
  end

  test "no output and non-zero exit is internal" do
    res = run_it(runner("cat >/dev/null; exit 3"))
    assert_equal "internal", res.error_type
    assert_equal 3, res.exit_status
    assert_match(/exit 3/, res.error["message"])
  end

  test "ok json with non-zero exit still wins" do
    res = run_it(runner(%(cat >/dev/null; echo '{"version":1,"status":"ok"}'; exit 1)))
    assert res.ok?
    assert_equal 1, res.exit_status
  end

  test "wrong version is internal" do
    res = run_it(runner(%(cat >/dev/null; echo '{"version":2,"status":"ok"}')))
    assert_equal "internal", res.error_type
  end

  test "unknown error type is internal" do
    res = run_it(runner(%(cat >/dev/null; echo '#{error_doc("weird")}')))
    assert_equal "internal", res.error_type
    assert_equal "internal", res.error["type"]
  end

  test "non-hash json is internal" do
    res = run_it(runner(%(cat >/dev/null; echo '[1,2]')))
    assert_equal "internal", res.error_type
  end

  test "stdin is received" do
    body = <<~'SH'
      req=$(cat)
      printf '{"version":1,"status":"ok","echo":%s}\n' "$req"
    SH
    res = run_it(runner(body), request: {"hello" => "world", "n" => 2})
    assert res.ok?
    assert_equal({"hello" => "world", "n" => 2}, res.payload["echo"])
  end

  test "env is isolated" do
    body = <<~'SH'
      cat >/dev/null
      keys=$(env | cut -d= -f1 | sort | sed 's/.*/"&"/' | paste -sd, -)
      printf '{"version":1,"status":"ok","keys":[%s]}\n' "$keys"
    SH
    res = nil
    with_env("SECRET_KEY_BASE" => "shh", "HTTPS_PROXY" => "http://proxy.invalid:3128", "SSL_CERT_FILE" => nil) do
      res = run_it(runner(body), env: {"FOO_TOKEN" => "x"})
    end
    assert res.ok?, res.payload.inspect
    keys = res.payload["keys"] - %w[PWD SHLVL _ OLDPWD]
    assert_includes keys, "FOO_TOKEN"
    assert_includes keys, "PATH"
    assert_includes keys, "HTTPS_PROXY"
    assert_not_includes keys, "SECRET_KEY_BASE"
    allowed = %w[FOO_TOKEN PATH] + LetsEncryptServices::CertIssuerRunner::PASSTHROUGH_ENV
    assert_empty keys - allowed
  end

  test "argv is exactly issue" do
    body = <<~'SH'
      cat >/dev/null
      printf '{"version":1,"status":"ok","argv":["%s"],"argc":%s}\n' "$1" "$#"
    SH
    res = run_it(runner(body))
    assert_equal ["issue"], res.payload["argv"]
    assert_equal 1, res.payload["argc"]
  end

  test "missing binary is internal" do
    r = LetsEncryptServices::CertIssuerRunner.new(binary: File.join(@dir, "nope"))
    res = run_it(r)
    assert_equal "internal", res.error_type
    assert_equal "cert-issuer binary not found: #{File.join(@dir, "nope")}", res.error["message"]
  end

  test "timeout terminates the child" do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    res = run_it(runner("sleep 30", term_grace: 1), timeout: 1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    assert_equal "internal", res.error_type
    assert_equal "cert-issuer timed out after 1 seconds", res.error["message"]
    assert_operator elapsed, :<, 5
  end

  test "child that ignores TERM is killed after the grace period" do
    body = <<~'SH'
      trap '' TERM
      while true; do sleep 1; done
    SH
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    res = run_it(runner(body, term_grace: 1), timeout: 1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    assert_equal "internal", res.error_type
    assert_match(/timed out/, res.error["message"])
    assert_operator elapsed, :>=, 1.9
    assert_operator elapsed, :<, 8
  end

  test "large stderr does not deadlock and is truncated to a tail" do
    body = <<~'SH'
      cat >/dev/null
      i=0
      while [ $i -lt 2000 ]; do
        echo "line-$i xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" >&2
        i=$((i+1))
      done
      echo '{"version":1,"status":"ok"}'
    SH
    res = run_it(runner(body), timeout: 20)
    assert res.ok?
    assert_operator res.stderr_tail.bytesize, :<=, 4096
    assert_match(/line-1999/, res.stderr_tail)
  end

  private

  def with_env(vars)
    old = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
