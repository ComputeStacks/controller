# v9.6 — Load Balancer Real Client IP & File-Based CDN Proxy IPs

The load balancer now sets an authoritative real client IP and manages the
Cloudflare/Bunny proxy IP lists as files instead of per-load-balancer database
rows. This upgrade adds **one new persistent mount** on a containerized
controller — without it the CDN IP lists are lost on every container restart
(and any `restrict_cf`/`restrict_bunny` enforcement lapses; see §2).

## What changed

- **Real client IP.** The generated HAProxy config now sets **both** `X-Real-IP`
  and `X-Forwarded-For` to the true client on every request — the CDN-attested
  address when the connection comes from a trusted proxy (Cloudflare / Bunny /
  edge), and the connecting IP otherwise (overwrites any client-supplied value,
  so it is non-spoofable). `X-Forwarded-Proto` is preserved. Backends that read
  *either* header now get the visitor IP.
- **CDN proxy IP lists are now global files.** Cloudflare and Bunny ranges are
  fetched into `lib/proxy_ips/{cloudflare,bunny}.lst` (previously one
  `load_balancer_addr` row per IP, per load balancer), diffed, and refreshed
  daily by `UpdateProxyServiceWorker` (Clockwork). Bunny is refreshed on the
  schedule now too (previously Cloudflare only). A failed/empty fetch keeps the
  last-good file and raises a `warn` SystemEvent.
- **`restrict_bunny`.** Ingress rules can now restrict access to Bunny CDN only,
  the same way `restrict_cf` restricts to Cloudflare. The two are mutually
  exclusive per rule (validated).
- **Migration.** `db:migrate` (run by `cstacks upgrade`) deletes the old
  `label='Cloudflare'` `load_balancer_addr` rows and their taggings. All other
  addresses (Bunny, `public`/`internal`/`connect` roles, manually-added proxy
  IPs) are left untouched.

## 1. Add the persistent proxy-IP mount (containerized controller)

The lists live at `lib/proxy_ips` inside the container; that path must be a
persisted host directory or the lists vanish on restart.

```bash
# host directory that survives container recreation (mirrors sshkeys/rake/branding)
mkdir -p /var/lib/computestacks/proxy_ips

# env var — the env file uses bare KEY=value (no quotes)
echo 'CS_PROXY_IPS_PATH=/var/lib/computestacks/proxy_ips' >> /etc/default/computestacks

# mount it into the long-lived `run -d` container (the only cstacks subcommand
# that serves traffic and runs the daily refresh)
sed -i '/docker run -d --name portal/a\        -v $CS_PROXY_IPS_PATH:/usr/src/app/lib/proxy_ips \\' /usr/local/bin/cstacks
grep -c 'lib/proxy_ips' /usr/local/bin/cstacks   # expect: 1 (re-running the sed duplicates it)

# pull v9.6.0, run migrations (deletes old Cloudflare addr rows), restart with the mount
cstacks upgrade && cstacks run
```

On first boot the lists are empty until the daily refresh runs. Populate them
immediately with:

```bash
docker exec portal bundle exec rails runner 'LoadBalancerWorkers::UpdateProxyServiceWorker.new.perform'
```

> The mounted directory must be writable by the container's runtime user — the
> app **writes** the `.lst` files here (unlike `lib/ssh`, which it only reads).

> Provisioner (tracked separately — **not** done by this upgrade), so fresh
> provisions include the mount:
> - `roles/controller/defaults/main.yml`: `proxy_ips_directory: "{{ data_directory }}/proxy_ips"`
> - `roles/controller/tasks/install.yml`: add `- "{{ proxy_ips_directory }}"` to the **setup directories** loop
> - `roles/controller/templates/default-computestacks.j2`: `CS_PROXY_IPS_PATH={{ proxy_ips_directory }}`
> - `roles/controller/files/cstacks.sh`: add `-v $CS_PROXY_IPS_PATH:/usr/src/app/lib/proxy_ips \` to the `run()` block

## 2. Fail-open behavior (restrict_cf / restrict_bunny)

If a `restrict_*` rule is active but its IP list is empty — before the first
refresh, or if the CDN's IP endpoint is unreachable — enforcement **fails open**:
the restricted endpoint stays reachable rather than being denied. This matches
the pre-9.6 behavior. Each affected deploy emits a `warn` SystemEvent:

```
Ingress restriction active but <provider> IP list is empty on Load Balancer: <label> — restricted endpoints are open (fail-open).
```

Watch system events after upgrading if you rely on the restrict feature, and
populate the lists (§1) **before** enabling restrict rules on a fresh install.

## 3. Verify

```bash
# lists populated inside the container
docker exec portal ls -l /usr/src/app/lib/proxy_ips        # cloudflare.lst + bunny.lst, non-empty

# real IP reaches a backend: from a header-echo container behind the LB, both
# X-Real-IP and X-Forwarded-For should be the visitor IP — via a CDN and direct.

# restrict: toggle restrict_bunny on an ingress rule → a non-Bunny source is
# rejected while a Bunny source passes.
#   (haproxy -c only *warns* on mode-tcp rules, so eyeball the TCP/TLS frontends
#    to confirm the `tcp-request content reject` lines rendered.)
```
