require "open3"
require "json"

module LetsEncryptServices
  # Runs the external `cert-issuer` CLI as a subprocess and normalizes its result.
  # See the cert-issuer contract: stdout JSON is authoritative, exit code is only recorded.
  class CertIssuerRunner
    ERROR_TYPES = %w[config validation_failed rate_limited transient internal].freeze
    PASSTHROUGH_ENV = %w[HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy SSL_CERT_FILE SSL_CERT_DIR].freeze
    STDERR_TAIL_BYTES = 4096

    Result = Struct.new(:error_type, :payload, :exit_status, :stderr_tail, keyword_init: true) do
      def ok? = error_type.nil?

      # payload["error"] or {} -- always a Hash
      def error = (payload.is_a?(Hash) && payload["error"].is_a?(Hash)) ? payload["error"] : {}
    end

    # Where lib/dev/install-cert-issuer.sh puts the binary on a workstation.
    DEV_BINARY = File.expand_path("../../../lib/dev/bin/cert-issuer", __dir__)

    # CERT_ISSUER_BIN, else (outside production) the workstation copy, else PATH.
    def self.default_binary
      env = ENV["CERT_ISSUER_BIN"].presence
      return env if env
      return DEV_BINARY if !Rails.env.production? && File.executable?(DEV_BINARY)
      "cert-issuer"
    end

    # @return [String, nil] absolute path of the binary, if it can be run
    def self.resolve_binary(bin = default_binary)
      return (File.executable?(bin) ? bin : nil) if bin.include?(File::SEPARATOR)
      ENV["PATH"].to_s.split(File::PATH_SEPARATOR).map { |d| File.join(d, bin) }.find { |f| File.executable?(f) }
    end

    def initialize(binary: self.class.default_binary, term_grace: 35)
      @binary = binary
      @term_grace = term_grace
    end

    # request: Hash (serialized to JSON on stdin; never logged, it holds private keys)
    # env: Hash{String=>String} provider variables
    # timeout: Integer seconds, hard limit for the whole subprocess
    def run(request:, env:, timeout:)
      stdin = stdout = stderr = wait_thr = nil
      begin
        stdin, stdout, stderr, wait_thr = Open3.popen3(child_env(env), @binary, "issue", unsetenv_others: true)
      rescue Errno::ENOENT, Errno::EACCES
        return internal_result("cert-issuer binary not found: #{@binary}")
      end

      out_buf = +""
      err_tail = +""
      readers = [
        Thread.new { read_all(stdout) { |c| out_buf << c } },
        Thread.new { read_all(stderr) { |c| err_tail << c; err_tail = err_tail.byteslice(-STDERR_TAIL_BYTES, STDERR_TAIL_BYTES) if err_tail.bytesize > STDERR_TAIL_BYTES } }
      ]
      readers.each { |t| t.report_on_exception = false }

      begin
        begin
          stdin.write(request.to_json)
        rescue Errno::EPIPE, IOError
          # child exited early; its stdout still decides the outcome
        ensure
          stdin.close unless stdin.closed?
        end

        timed_out = false
        if wait_thr.join(timeout).nil?
          timed_out = true
          terminate(wait_thr)
        end
        # A grandchild may keep the pipes open after the child exits; don't wait long for EOF.
        reader_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
        readers.each { |t| t.join([reader_deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max) }
      rescue Exception # rubocop:disable Lint/RescueException -- includes Sidekiq::Shutdown / Thread kill
        signal(wait_thr, "TERM") if wait_thr&.alive?
        raise
      ensure
        readers&.each { |t| t.kill if t.alive? }
        [stdin, stdout, stderr].each { |io| io.close if io && !io.closed? }
      end

      status = wait_thr.value
      exit_status = status.exitstatus
      tail = err_tail.dup.force_encoding("UTF-8").scrub
      if timed_out
        r = internal_result("cert-issuer timed out after #{timeout} seconds")
        r.exit_status = exit_status
        r.stderr_tail = tail
        return r
      end
      parse(out_buf, exit_status, tail)
    end

    private

    def child_env(env)
      base = {"PATH" => ENV["PATH"]}.compact
      PASSTHROUGH_ENV.each { |k| base[k] = ENV[k] if ENV[k] }
      base.merge(env.to_h { |k, v| [k.to_s, v.to_s] })
    end

    def read_all(io)
      while (chunk = io.readpartial(16_384))
        yield chunk
      end
    rescue EOFError, IOError
      nil
    end

    def terminate(wait_thr)
      signal(wait_thr, "TERM")
      return if wait_thr.join(@term_grace)
      signal(wait_thr, "KILL")
      wait_thr.join
    end

    def signal(wait_thr, sig)
      Process.kill(sig, wait_thr.pid)
    rescue Errno::ESRCH
      nil
    end

    def parse(out, exit_status, tail)
      doc = begin
        JSON.parse(out)
      rescue JSON::ParserError
        nil
      end
      if doc.is_a?(Hash) && doc["version"] == 1
        if doc["status"] == "ok"
          return Result.new(error_type: nil, payload: doc, exit_status: exit_status, stderr_tail: tail)
        elsif doc["status"] == "error" && doc["error"].is_a?(Hash) && ERROR_TYPES.include?(doc["error"]["type"])
          return Result.new(error_type: doc["error"]["type"], payload: doc, exit_status: exit_status, stderr_tail: tail)
        end
      end
      msg = doc.nil? ? "no JSON result from cert-issuer (exit #{exit_status.inspect})" : "unrecognized result from cert-issuer (exit #{exit_status.inspect})"
      internal_result(msg, exit_status: exit_status, stderr_tail: tail)
    end

    def internal_result(message, exit_status: nil, stderr_tail: "")
      Result.new(
        error_type: "internal",
        payload: {"version" => 1, "status" => "error", "error" => {"type" => "internal", "message" => message}},
        exit_status: exit_status,
        stderr_tail: stderr_tail
      )
    end
  end
end
