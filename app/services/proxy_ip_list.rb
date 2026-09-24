require "fileutils"
require "ipaddr"
require "securerandom"

# Single source of truth for the account-**global** CDN proxy IP lists
# (Cloudflare, Bunny). These lists are identical for every load balancer, so we
# store them once as newline files in the exact format HAProxy `src -f` expects
# instead of duplicating them as per-LB `load_balancer_addr` rows.
#
# - `refresh!(provider)` fetches, diffs, and atomically writes the file. It never
#   overwrites a good list with an empty/failed fetch (last-good wins) and alerts
#   on failure.
# - `read(provider)` returns an array of IPAddr for the HAProxy config renderer.
#
# The files live under DIR (default `lib/proxy_ips`, mirroring the `lib/ssh`
# convention). In dev the controller runs directly on the VM, so the app dir is
# writable; in the container, cstacks.sh mounts the persisted host directory
# /var/lib/computestacks/proxy_ips onto /usr/src/app/lib/proxy_ips.
module ProxyIpList
  extend self

  DIR = ENV.fetch("PROXY_IP_DIR") { Rails.root.join("lib", "proxy_ips").to_s }

  PROVIDERS = {
    cloudflare: {
      urls: %w[https://www.cloudflare.com/ips-v4 https://www.cloudflare.com/ips-v6],
      parser: :lines,
      file: "cloudflare.lst"
    },
    # NOTE: verify these endpoints stay current — Bunny is migrating to api.bunny.net.
    bunny: {
      urls: %w[https://bunnycdn.com/api/system/edgeserverlist https://bunnycdn.com/api/system/edgeserverlist/IPv6],
      parser: :json,
      file: "bunny.lst"
    }
  }.freeze

  # @return [String] absolute path to the provider's list file
  def path(provider)
    File.join(DIR, PROVIDERS.fetch(provider).fetch(:file))
  end

  # @return [Boolean] the file exists and is non-empty
  def file_present?(provider)
    File.exist?(path(provider)) && !File.zero?(path(provider))
  end

  # @return [Boolean] any provider list file is missing (used by the boot seeder)
  def any_missing?
    PROVIDERS.keys.any? { |p| !File.exist?(path(p)) }
  end

  # Read the stored list. Skips blank lines and rescues a missing/unreadable file
  # to [] so HAProxy config rendering never blows up.
  # @return [Array<IPAddr>]
  def read(provider)
    File.readlines(path(provider), chomp: true).filter_map do |line|
      line = line.strip
      next if line.empty?
      begin
        IPAddr.new(line)
      rescue IPAddr::Error
        nil
      end
    end
  rescue SystemCallError
    []
  end

  # Fetch, parse, diff, and atomically write the provider list.
  # @return [Boolean] true if the on-disk list changed
  def refresh!(provider)
    cfg = PROVIDERS.fetch(provider)
    ips = fetch(cfg)
    if ips.blank?
      alert(provider, "fetch returned no addresses; keeping last-good list")
      return false
    end
    content = normalize(ips)
    return false if content == current_content(provider) # unchanged — no redeploy
    write_atomic(provider, content)
    true
  rescue => e
    ExceptionAlertService.new(e, "3f2a9c1b7e4d6058").perform if defined?(ExceptionAlertService)
    alert(provider, e.message)
    false
  end

  private

  def fetch(cfg)
    cfg[:urls].flat_map { |url| parse(cfg[:parser], http_get(url)) }
  end

  def http_get(url)
    resp = HTTP.timeout(connect: 5, read: 15).headers(accept: "application/json").get(url)
    resp.status.success? ? resp.to_s : nil
  end

  def parse(parser, body)
    return [] if body.blank?
    case parser
    when :lines then body.split("\n").map(&:strip).reject(&:blank?)
    when :json  then Array(Oj.load(body, strict: true))
    else []
    end
  end

  # Sorted + de-duped so the diff is stable across fetches.
  def normalize(ips)
    ips.map { |i| i.to_s.strip }.reject(&:blank?).uniq.sort.join("\n") + "\n"
  end

  def current_content(provider)
    File.read(path(provider))
  rescue SystemCallError
    nil
  end

  def write_atomic(provider, content)
    FileUtils.mkdir_p(DIR)
    # Unique per call so concurrent Sidekiq threads in the same process never
    # write the same tmp path (which would truncate/garble the file).
    tmp = "#{path(provider)}.#{SecureRandom.hex(8)}.tmp"
    File.write(tmp, content)
    File.rename(tmp, path(provider))
  end

  def alert(provider, message)
    SystemEvent.create!(
      message: "Proxy IP list refresh failed for #{provider}: #{message}",
      log_level: "warn",
      data: {"provider" => provider.to_s},
      event_code: "8c5e1a2b9d3f4706"
    )
  rescue => _e
    Rails.logger.warn("ProxyIpList: #{provider} refresh failed: #{message}")
  end
end
