# Change Log

## v9.7.9

- [FEATURE] **A project's SSH password can now be replaced on demand.** A new "Rotate" link sits next to the password on the project's SFTP connection panel, shown while password login is enabled, and on the SFTP container's admin page, where it is always available. Either one generates a new password and rebuilds the SSH container, because the password is only applied when that container is created. The rebuild disconnects any open SSH, SFTP and cloud shell sessions — the link asks before going ahead — and the new password takes effect once the rebuild completes. Host keys are kept, so clients do not see a changed-key warning.

    **The existing API endpoint, `POST /api/projects/{project-id}/bastions/{id}/reset_password`, now works.** It previously returned a server error whenever the rebuild could not be started, and it saved the new password before knowing whether it would run, so it could hand back a password the container never received. Project collaborators could not use it at all. It now checks first and leaves the password unchanged when the node is offline or another action is in progress on the container, returning the reason instead. It requires the `project_write` scope and returns the bastion with its new password.

- [FIX] **A failed order no longer strips a running project of its private network.** An order placed against a project that already exists does not create a network — it uses the one the project has. If that order then failed for any reason, the failure handling released the project's network anyway. The containers carried on running, but the controller no longer had any record that the project had a network: anything that needed to know, such as adding a container or re-provisioning file access, saw none, and the routine cleanup began considering a live customer's network for deletion every ten minutes. The failure path now releases a network only when the same order created it.

## v9.7.8

- [CHANGE] **The local development environment setup has been rebuilt.** It previously referenced a Vagrant box that was removed some time ago, and following it could no longer produce a working setup. Two scripts now do the work — one for a developer's own workstation, one for the separate VM that acts as the container node — and both can be re-run safely to pick up changes. `doc/development.md` replaces the old instructions and walks through the whole process, including the one-time loop where the node is installed before the controller exists to enroll it against.

- [FIX] **An availability zone no longer runs out of usable address ranges for new projects.** Each project gets a private network, drawn from a pool of address ranges belonging to its availability zone. When a project goes away its range is returned to the pool and handed to the next project, which renames it — and the name is the only thing tying the controller's record of a range to the network the node actually has. If the node could not be reached at the moment the range was returned, the network stayed on the node while the record moved on, and the two could never be matched up again. The abandoned network went on holding the address range, so every later project given that range failed to provision: the node refused to create a second network over the same addresses, and reported it in a way that read as an unrelated permissions error.

    Any interruption in talking to a node could cause it, and one was enough to lose that address range permanently. A node restarting for a routine package upgrade is the likely cause of the ones seen so far.

    **An address range is now only returned to the pool once its network is confirmed gone from every node in the zone.** Anything that cannot be confirmed stays where it is and is retried by the ten-minute cleanup, which is a delay rather than a loss. Separately, creating a project network now recognises an abandoned copy of itself on the node and clears it out of the way first, so a range stranded before this release is reclaimed the next time it comes up rather than failing again. A copy that anything is still using is never removed — including by containers that are merely stopped, which hold no connection and would otherwise look unused — and the operator is told what is holding the range.

- [FIX] **An order that cannot build its private network now fails instead of building containers that will not start.** The result of setting up the network was not being checked, so an order whose network never reached the node carried on regardless. Every container was then created and every one of them failed to start, reporting a missing network, and the order left them behind. It now stops at the point of failure with a single clear message, and the address range is released rather than being left attached to the failed project.

- [FEATURE] **A new maintenance task reports networks on the nodes that no longer match the records, and the records that are missing from their node.** Run `rake networks:audit_orphans` on the controller. It reports abandoned networks holding a live address range, networks whose record has been deleted, networks belonging to no project, and — the reverse case — projects whose network is absent from the node, which is why their containers cannot start. Networks the controller did not create are listed but never touched.

    It reports and changes nothing by default. `REMOVE=1` additionally deletes the abandoned networks that **nothing is using**, and it is deliberately hard to satisfy: a network counts as in use if the node reports anything connected to it, if any container on that node is configured to use it **even while stopped**, or if the controller has handed out addresses on it. Anything the task could not establish — a node whose container list will not read, a network that disappeared mid-run — counts as in use as well. The distinction matters because a stopped container holds no connection, so a check against connections alone would report a network as unused moments after a node reboot and delete it, leaving those containers unable to start. Database records are not modified either way — the existing cleanup reconciles them once the node is clear.

## v9.7.7

- [FIX] **Placing an order, and several admin pages, no longer time out.** Every database query the controller ran was carrying a hidden delay, and any page that ran a lot of them went past the proxy's patience and returned a gateway error. Ordering was the worst affected: choosing an application and pressing next returned an error rather than the settings page, and orders placed through the API hung and then failed with nothing recorded against them in the event log, because the failure happened before the job that creates the event was ever started.

    The cause was a new default in a third-party dependency rather than a change in this application. The error-reporting library began, in its latest major version, to send a log record to the error-reporting service for **every SQL query**. Those records are collected in batches of a hundred and each batch is delivered over the network before the query that filled it is allowed to return. Where the error-reporting service is not in the same datacentre as the controller, that delivery is a round trip across the internet — measured here at 435ms, two thirds of it spent setting up a fresh encrypted connection, because the connection is not held open between batches. Averaged over every query it worked out at roughly 4.3ms each, which is more than ten times the cost of running the query and returning the answer.

    Sending a log record per query is now switched off, which is how this behaved before. **Error reporting itself is unchanged** — exceptions, breadcrumbs and performance tracing are separate features and none of them fire per query, so nothing you were relying on has been turned off.

- [FIX] **An unreachable metrics server no longer stops orders being placed.** Before putting a container on a node, the controller checked that the node physically has enough CPU and memory for it — and it asked the metrics server that question live, every time, for every node it was considering. When the metrics server could not be reached, or was slow enough to time out, the answer came back as zero rather than as "unknown", so every node in the fleet looked as though it had no CPU at all and no order could be placed anywhere. A single unreachable metrics server was enough to stop new orders entirely, and the failure was reported to the customer as though no node had room.

    **A node's CPU and memory are now recorded on the node itself.** They are read from the node's own container service once a minute by the existing health check and stored, so placing a container reads a stored figure instead of asking a remote server four times per node. These are facts about the hardware that change only when a machine is resized, so asking for them repeatedly was never necessary. Both figures are shown on the node in the admin area, along with when they were last confirmed.

    **Where the figure genuinely is not known, the checks that depend on it now stand aside instead of refusing.** A node that has just been added, and has not yet been health-checked, is allowed to accept containers rather than being treated as empty. That applies to both checks that need to know the node's size: whether it is big enough at all, and — on the installations that do not allow overcommitting — how much of it is already committed. The checks that do not depend on it are unaffected: whether the node is being drained, and whether it has reached its container limit. Note that on an installation with overcommitting switched off, an availability zone whose nodes all have unknown capacity is still passed over when choosing where to place an order; only the choice of node within a zone stands aside. Placing a container also stops asking for these figures at all where the answer cannot change the outcome.

- [FIX] **Provisioning SFTP access can no longer destroy the SFTP container a project already has.** When the controller could not find a node for a project's SFTP container, it carried on with an empty placeholder in its list. Every safeguard that followed was written to notice an empty list and stop, and none of them recognised the placeholder — so the run removed the project's existing SFTP container on the grounds that it was no longer needed, and then failed with an internal error before creating the replacement. Nothing retried it. The most likely way to hit it was moving a project's storage to another availability zone, which schedules exactly this work a few minutes later.

    A zone that cannot be placed into is now reported and skipped rather than failing the run, existing containers are left alone, and the reason is recorded for the operator. The customer is told which zone was skipped without being shown the internals, which can read as "this node has no CPUs" when the real problem is that the metrics server is unreachable.

- [FIX] **Placing an order no longer asks the database a thousand questions per availability zone.** Working out how much of a zone was already committed asked the database about every application in it, then about each one's subscription, then twice more about that subscription's package — over a thousand queries to produce two numbers, repeated for every zone the order might go to. The equivalent figure for a node walked its containers the same way. Both are now a single sum of two columns. This also removes a way one customer's order could fail with a server error while another customer's containers were mid-creation.

- [CHANGE] **A zone's committed-resources figure now counts containers that are not billed.** A project's load balancer, and any application ordered with the free option, never gets a subscription — so the zone figure ignored them entirely, while the equivalent check made later, when the container is actually placed on a node, counted them. The two disagreed, and a zone could accept an order that the node then refused. They now agree, and the zone figure is correspondingly larger. This figure is used only to choose between availability zones when placing an order; it is not displayed anywhere, so nothing in the admin interface changes. On a location that fills by container count — the default — it is not consulted at all.

- [CHANGE] **SFTP containers now count toward committed resources, at the size the node actually gives them.** A project's SFTP container occupies a node like any other container, but was left out of the figures used to choose where new containers go — while still counting toward the container limit that caps a zone. It is now included. The size used is the one the node enforces, one core and 1 GB. Three different figures for this existed in different parts of the system: the node enforced one core and 1 GB, the capacity shown in the admin API assumed half a core and 512 MB, and the code that picks a node for a new SFTP container assumed one core and 512 MB. They are now one value. **The admin capacity figures for a location and its zones will rise accordingly** — the previous numbers understated SFTP by half. The SFTP container counts shown alongside them may fall slightly: they now count the containers actually running on that location's nodes, where before they counted every SFTP container belonging to a project with anything in the location, including ones already awaiting deletion.

- [CHANGE] **A zone's committed resources are no longer calculated when nothing will read them.** A location set to fill the emptiest zone first, measured by container count, with overcommit enabled on both CPU and memory, ranks zones by how many containers each holds and never consults the resource figures — but they were gathered anyway on every order, including two requests to the zone's metrics server for every node. Where they cannot affect the outcome they are now skipped. Every other configuration still calculates them and is unaffected: filling zones to capacity always ranks by resources whatever else is set, as does filling the emptiest zone when measured by resources rather than by count, and either overcommit setting switched off brings back the capacity check that reads them.

- [FIX] **Ordering into a location with no usable availability zone returns an error message instead of a server error.** The check that produced "There are no availability zones available" went on to use the missing zone anyway, so the customer saw a 500.

- [CHANGE] **Six more gems are pinned to a version range.** `tzinfo-data`, `net-smtp`, `pry`, `pry-rails`, `puma` and `csv` were the only libraries reaching a running controller with no version constraint at all, so each build was free to pick a newer one. They now carry ranges, as the rest already did. No version in use changes.

- [CHANGE] **The error-reporting gems are now pinned to a specific version.** This project does not keep a resolved dependency list under version control, so every image build picks the newest version of anything unpinned. That is how the default described above arrived in a release whose own source contained no relevant change, and it made a dependency's major version upgrade indistinguishable from a normal build. The three related gems are pinned together and must be moved together.

## v9.7.6

- [FEATURE] **A controller can now be seeded from a manifest: `rake bootstrap:apply[/path/to/manifest.yml]`.** The installer previously generated a `bootstrap.rake` file from a template and ran it inside the container, which meant the seeding code lived in the installer rather than here and drifted out of step with the models on every release — a renamed column or a new validation was only discovered on somebody's fresh install. The manifest is pure data (its schema is documented in `doc/bootstrap_manifest.md` and versioned as `schema_version: 1`) and the code that applies it lives in this repository and is tested here.

    **It bootstraps a controller; it does not converge one.** A location, availability zone, node, network, load balancer, metrics/log client, DNS driver, DNS zone, default user group or admin user that already exists is left exactly as it is — not one attribute is assigned to it. The controller is edited by humans through the admin UI for years after it is installed, and a manifest rendered months earlier would otherwise roll that work back the next time a node is deployed. Where the manifest and the database disagree the database wins, and the apply prints a warning naming each field, so the operator finds out their inventory has gone stale instead of losing a change to it.

    There are exactly two exceptions, and both are enumerated field lists. **The first is six credential fields the installer owns on *both* ends** — a metrics/log client's `username` and `password`, the DNS driver's `api_key` and `api_secret`, and the load balancer's `shared_certificate` and `stats_password` — which are updated on a row that already exists when the manifest carries a different value. The same variable renders the other half of each pair (the htpasswd file Prometheus and Loki authenticate against, PowerDNS's own `api-key`, the wildcard certificate, the haproxy stats password) and the installer converges that half on every run, so leaving the controller's copy behind would break metrics, log queries, DNS or the stats page at the next rotation while the run reported success. Nothing else on those rows is written; a changed client endpoint or load balancer domain still only warns, and each rotation is logged by field name with the value never printed.

    **The second is off unless you ask for it.** `UPDATE_ADDRESSES=1` also converges the three infrastructure addresses the installer derives rather than an operator chooses — an availability zone's `acme_server`, a node's `agent_host` and the DNS driver's `endpoint` — on rows that already exist. It is there for deliberate topology changes, such as rolling Tailscale onto a zone that is already live, where those addresses all move at once across every node and doing it by hand in the admin UI is not realistic; without the flag the three fields behave like everything else and only warn, so an ordinary run is completely unchanged. Under the flag a node entry with **no** `agent_host` clears the column, because the installer derives that address pairwise and omits it when the node and the controller are not both on the tailnet — "no key" is therefore the only way a rollback can be expressed, and a cleared node falls back to its `primary_ip` exactly as it did before the column existed. Addresses are not secrets, so each one is logged with both the old and the new value. Because the flag turns an absent address into a write, only run it against a manifest rendered from complete inventory and fact data — a full run, not a limited one.

    Settings and feature flags follow the same principle in the only form that fits them: every one of their rows exists after `Setting.setup!` / `Feature.setup!`, so a value is written only while it is still blank or still exactly as the setup seeded it, and a setting somebody configured or a flag somebody toggled is never overwritten. Everything additive keeps working on a live controller — a new zone, a node or network added to an existing zone, the default group's link to a new zone, and the billing price extension below.

    The apply **never destroys or recreates a row**, enforced by a guard that watches the SQL it issues: `ProvisionDriver has_many :regions, dependent: :destroy` means a naive "recreate the DNS driver" would cascade-delete every availability zone on the controller. Every section is optional, so the same task attaches a new zone to a live controller without touching settings, DNS, products or the admin user. `DRY_RUN=1` prints the creates, the credential rotations, any address updates and the drift warnings and writes nothing; secrets are redacted in both the database's value and the manifest's, and the admin password is never compared at all. Anything that fails to validate aborts the whole apply with a non-zero exit and a message naming the manifest section and key; nothing is left half-applied.

- [FEATURE] Adding a region to an existing controller now extends the billing prices to it. Prices are attached to the regions that exist at the moment `load_products` runs, so a region added later had no price for any product and everything in it billed at 0.0 with nothing to indicate anything was wrong. The apply extends a price to a new region only when that price already covers every region that existed before, so hand-built region-specific pricing is left alone, and it checks first that the phase does not already price that region at the same currency and quantity tier — the join insert bypasses the validation that would otherwise catch it.
- [CHANGE] `agent:datachannel_backfill` and `metadata:agent_backfill` now **exit non-zero when any node, volume or project failed**. Both printed `[fail]` lines and still exited 0, so an automated caller recorded a successful run while backup/restore dispatch stayed blocked for that node or a project's tenant was never provisioned. Skips are unchanged and are still not failures — they mean "re-run once the node is online". Both tasks also accept `NODE_ID=<id>` or `NODE=<hostname>` to limit the pass to one node (for `metadata:agent_backfill`, to the projects in that node's region); without it they cover the whole fleet exactly as before.
- [FIX] **The admin dashboard no longer returns a gateway timeout.** The "Invalid Billing Plans" check on it joined billing plans to their users without collapsing the result, so it built one copy of each plan for every user on that plan and then put three further questions to the database about each copy. The work therefore grew with the number of user accounts rather than with the number of billing plans, and a few thousand accounts is enough to take the page past a proxy's patience, so it returned an error instead of loading. The check now costs two queries whatever the user count, and answers the same thing. `/admin/billing_plans` was paying a smaller version of the same cost once per row and is quicker for the same reason.
- [FIX] **The CPU, memory and disk figures on the admin dashboard now arrive about three times faster for an availability zone that is far from the controller.** Each zone's row asks that zone's metrics server for three separate readings, and it asked for them strictly one after another — so the row cost three round trips to a machine that may be nowhere near the controller. Measured from a controller in Amsterdam, a zone in San Jose took 4.8 seconds to fill in one row, against 0.24 seconds for a zone in the same city. A node's three readings are now fetched at the same time, so the row costs about one round trip rather than three; a zone with several nodes still reads its nodes one after another, so the saving there is per node. The three readings remain three separate requests rather than one combined query on purpose: a slow or failing reading still leaves the other two showing real numbers instead of blanking all three.
- [CHANGE] Four smaller things behind the same page. The zone panel no longer issues a query per availability zone and another per load balancer to draw itself. An availability zone's own page no longer loads a list of nodes that nothing on it reads — which was also being loaded on every one of the dashboard's metrics requests. A dashboard partial that nothing rendered, and that could only have raised an error if it ever were, has been deleted. And a duplicate `sftp_containers` association on the availability zone model, which Rails was already silently ignoring in favour of the one declared after it, has been removed. One visible change comes with it: locations and the availability zones inside them are now listed by name. Neither was ordered before — the panel showed them in whatever order the database happened to return, which was stable in practice but never specified.
- [FIX] **The admin node pages no longer take tens of seconds to load.** Each node's panel shows five figures pulled from that zone's metrics server, and the page fetched them strictly one at a time — nine round trips per node, because the template asked for the disk figure four separate times and the uptime twice. All of it blocked the page, and the fleet-wide node list renders every node in one request, so the wait grew with both the number of nodes and the distance to their zones: against a zone on another continent it was roughly twelve seconds per node. Every figure for every node is now requested in one batch, twelve reads at a time, so the page costs one round trip per twelve reads instead of one per read — a two-node fleet goes from eighteen sequential round trips to one, and a twelve-node fleet from around a hundred to five. A zone's own node list benefits the same way. One small display change comes with it: a node whose metrics server cannot be reached now shows its disk row as unknown, where previously the row was left out altogether.
- [CHANGE] **An availability zone's node list no longer refreshes itself every 6.5 seconds.** It re-fetched every figure for every node on that timer, so a zone page left open put a standing load on the metrics server for as long as the tab stayed open — and each cycle was the full nine reads per node described above. It now loads once per page view, like the dashboard's zone rows. Be aware that the same panel also carries each node's status and its panel colour — online, offline, entering or already in maintenance mode, failed health-check counts — so those no longer update on their own either; reload the page to see a node's current state.

## v9.7.5

- [FIX] **OAuth scope restrictions on the API are now enforced.** They were not. Every scope check was written to be skipped for HTTP Basic requests, but the condition it used (`unless: :current_user`) is also true for an OAuth token, because the signed-in user is resolved from the token's resource owner. The result was that an application a customer authorised with nothing but the default `public` scope could call anything that customer could call — including the admin API, if the customer is an admin. Independently, 40 of those checks asked for scope names that do not exist (`projects_read` / `projects_write`; the configured names are singular), so they could never have been satisfied even if they had run. Both are fixed together: neither fix does anything on its own.
- [CHANGE] **An OAuth application may need its scopes widened before you upgrade.** Now that the checks run, a token is refused with `403` unless it carries the scope the endpoint asks for. Any application authorised with only `public` will lose access to everything except `/api/version` and the public container image catalog. The scope each endpoint requires is documented with that endpoint. **HTTP Basic API credentials are unaffected by the scope gate** — they carry no scopes and never did, so billing integrations, the provisioner and anything else authenticating that way keep working exactly as they do now. One small related change: an `Authorization` header whose scheme is written in lower case (`basic …`) is now recognised as Basic authentication, where before it was not attempted at all and the request was rejected. Both the authentication path and the scope gate read the header through the same test, so the two cannot disagree about what a Basic request is.
- [FIX] Three API endpoints had no scope check at all, because they were left out of the list of actions each controller's check applied to: an ingress rule's domain list, the ingress rule "toggle NAT" call, and `GET /api/containers`. They are now gated like everything else — read scope for the first and last, write scope for the NAT toggle.
- [CHANGE] Scope requirements are now declared per action on each controller, and **an action with no declaration is refused rather than allowed**. This replaces the previous arrangement, where a check listed the actions it covered and anything unlisted was silently ungated — which is how the three endpoints above came to have no check. A test now walks every route in the API and fails if any action has no declaration, so the same gap cannot reappear. An OAuth request for an action that somehow has none receives `403` and the condition is reported to Sentry; a Basic request is deliberately still allowed through, so a mistake here cannot take down an integration that never used scopes in the first place.
- [CHANGE] On the admin API, a caller without the required scope now receives `403` from the scope check rather than `401` from the admin check, because the scope check runs first. Nothing about who is allowed in has changed.
- [CHANGE] A request with the wrong scope now receives `403` before the record it named is looked up, where a handful of endpoints previously looked the record up first and answered `404`. This is the correct order — it stops a caller without permission learning whether an id exists — but the status code for that combination has changed.
- [FIX] The scope names published in the per-endpoint API documentation have been corrected. 102 of them — 80 in the controller and 22 in the WordPress plugin — named the nonexistent plural `projects_read` / `projects_write`. Four more named the wrong family entirely: the container registry collaborator endpoints documented a project scope where they require an image one. The admin image collection endpoints documented `images_write` where the admin API requires `admin_write`, and the load balancer endpoints documented `profile_read` where they require `project_read`.
- [CHANGE] `POST /api/projects/{id}/metrics` now requires read access rather than write. It reads and returns metrics and has always been documented as a read; it was only a `POST` because the request carries a list of metric kinds, and it inherited the write requirement from the controller it sits under.

**This is an ordinary upgrade** — `cstacks upgrade`, no migrations and no node-side changes. Two notes: check the scopes on any OAuth application you have registered before upgrading (see above), and if you run the WordPress plugin, the controller image must be rebuilt and published **before** the plugin image is rebuilt, since the plugin now declares its scopes using something this release adds.

## v9.7.4

- [FEATURE] An availability zone has a new **IPv6 Egress** setting, off in every zone and unchanged until someone ticks it. With it on, project networks created in that zone are built dual-stack, so containers can reach IPv6-only destinations on the internet. It is egress only: nothing becomes reachable inbound over IPv6 and published ports stay IPv4 only. It applies to project networks **created after** it is enabled — existing projects keep IPv4 only until their network is rebuilt, and *Rebuild Container Networks* on the zone converts every project in it, restarting their containers. **The node must have working upstream IPv6 before you enable this.** Without it containers still receive an IPv6 address and default route, and any workload that does not implement Happy Eyeballs — apt, and many language HTTP clients — will hang on every dual-stack hostname it looks up, which is worse than IPv4 only. Unticking the box does not undo anything: a network that already has IPv6 keeps it until that project's network is rebuilt.
- [FIX] Containers using the fluentd log driver now start even when fluentd is briefly unreachable. Docker's fluentd driver refuses to start a container it cannot connect to, and fluentd runs on each node as a systemd-supervised `docker run` with `RestartSec=30`, so it is down for roughly thirty seconds after every docker daemon restart or node reboot. Container recovery landing in that window failed, and enough consecutive failures tripped the auto-recovery limit, which marks the container inactive and takes it out of recovery permanently — a reboot could therefore leave containers down and needing to be started by hand, one at a time. The driver now runs in async mode: logs are buffered while fluentd is away and can be dropped if that buffer overflows, but the container always starts. Only affects containers created or rebuilt after upgrading, since the log driver is fixed into a container's configuration when it is created.

## v9.7.3

- [FEATURE] A service setting can now be created as a **password** in the UI, not only as static text. Password settings are stored encrypted and their value is never rendered back into the page — the list shows a *Show* action instead, and the edit form takes a new value only if you type one, leaving the stored value alone when you submit it blank. Previously the type could only be set when an image template generated the setting, so any credential added to a service by hand had to be stored as readable text.
- [FIX] Deleting a service setting now republishes the project's metadata. It never did, so a node kept serving a setting that no longer existed until something else happened to touch that project — which, on a project that is simply running, may be never. Anything that reads a setting inside a container was therefore working from a value the controller had already discarded.
- [FIX] Service setting and environment parameter values are no longer written to the application log or sent to Sentry. They are ordinary form fields named `value` (and `static_value` / `env_value`), so they were never filtered, while the payload they carry is routinely a database password or an API key.
- [CHANGE] A service setting's `param_type` is now validated against `static` and `password`, matching the image-template setting it is copied from, and cannot be changed once the setting exists — switching it would leave the stored value encoded for the wrong type.

**This is an ordinary upgrade** — `cstacks upgrade` with no migrations, no node-side changes, and no coordinated window.

## v9.7.2

- [FIX] **"Create this volume on existing deployed services?"** on an image volume now works. It never did: on the admin path the checkbox was ignored and the cascade ran on *every* volume added (a hidden `"0"` is truthy in Ruby), while on the non-admin path the checkbox was discarded entirely; the job that ran then crashed on the most ordinary case — a mount path nested inside an existing one — leaving an orphan volume row behind on each of its 25 retries, and reported nothing anywhere an admin would see. The rebuilt cascade creates the volume, its mount and the real docker volume for each deployed service, skips services that already have one (per service, with the reason recorded), fans out one job per service so a single failure cannot starve the rest, and rolls a service back completely if the node cannot provision the volume. It is admin-only, and now also available retroactively as **Apply to existing services** on each image volume — safe to re-run, and the supported way to recover a service that failed.
- [CHANGE] A volume added to an already-deployed service **does not restart or rebuild anything**. Containers pick the mount up at their next natural rebuild. Until that happens the volume is marked pending: the node agent is told not to back it up (otherwise borg builds a healthy-looking archive series of an empty volume), it is not exposed over SFTP, not offered as a clone source, and manual backups and restores are refused. The project's volume list shows the pending state and says when it will land. Note that anything already stored at that path inside the container becomes hidden once the empty volume mounts.
- [FIX] Volumes created for a deployed service no longer register briefly as *detached*, which minted a spurious "Detached Volume" billing subscription for a volume that was attached the whole time.
- [FEATURE] `rake volumes:audit_mounts` reports template volumes whose mount never reached a container — including any left behind by the old broken cascade, which the node agent may have been backing up while empty — plus orphan volumes, duplicate mounts, and volumes whose state could not be determined because a node was unreachable. Read-only; `FIX=1` marks the affected volumes pending so the agent stops archiving nothing. Run it after upgrading — the column it needs ships in the first of this release's two migrations.
- [FIX] The nightly volume sync now finishes recording a volume it discovers on a node. When it found a volume the controller did not know about — typically one Docker created by itself because the image declares a `VOLUME` that was never declared in ComputeStacks, such as a `/tmp` or `/run` scratch path — it recorded the volume but never attached it to the service, so the volume showed as unattached forever and quietly accrued a "Detached Volume" billing subscription it should never have had. Such a volume is now attached to the service that mounts it (still with backups off, as before), which also means Docker reuses it on the next rebuild instead of abandoning it and creating another. A volume that cannot be attached — because the service already mounts something at that path, or the path sits inside an existing mount — is now reported and skipped rather than failing the run, and a fault on one volume can no longer end the sweep before it reaches the remaining volumes and nodes.
- [FIX] Two mounts can no longer be created at the same path on one service. A pair of them made the service impossible to rebuild (Docker refuses duplicate mount destinations) and left cleanup to direct database work. A database constraint now prevents it; `rake volumes:audit_mounts` reports any pair that already exists, and the upgrade stops with that list rather than applying the constraint over broken data.

**This is an ordinary upgrade** — `cstacks upgrade` (database backup + `db:migrate`) with no node-side changes and no coordinated window. Nothing is rebuilt or restarted, and no container's mounts change until it is next rebuilt for its own reasons.

There are two migrations. The first adds a column and always applies. The second adds the duplicate-mount constraint and **will refuse to run if your database already contains two mounts at the same path on one service**, printing the offending pairs. That is deliberate: applying a unique index over broken data is worse than stopping. The application runs correctly without that second migration — the constraint prevents a new occurrence, it is not something the code depends on — so an upgrade that stops there is safe to leave until you can resolve the duplicates and re-run `db:migrate`.

**Run `rake volumes:audit_mounts` after upgrading.** It is read-only by default. It reports volumes whose mount never reached a container — including any left behind by the previously broken cascade, which the node agent may have been backing up while they sat empty, producing a plausible archive series containing none of the customer's data. It also reports the duplicate mounts above, orphaned volumes, and volumes whose state it could not determine because a node was unreachable (an unreachable node is treated as "no data", never as "not mounted"). If it finds volumes in the first category, `FIX=1` marks them pending, which tells the agent to stop backing them up until a container genuinely mounts them; everything else it reports is left for you to decide.

## v9.7.1

- [FEATURE] Nodes have an optional **Agent Host** setting: the address or hostname the controller uses to reach that node's cs-agent on port 8500. Left blank (the default, and the state of every existing node) it uses the node's Primary IP exactly as before. Setting it moves only the controller→agent channel — the one control-plane transport still on plain HTTP — onto a separate path such as a private/VPN address, while Docker, SSH, load balancer backends, and the container metadata service continue to use the Primary IP. Takes effect on the next poll with no restart, and can be applied or reverted one node at a time. The agent must keep listening on the Primary IP regardless, since containers reach `metadata.internal` there.
- [FIX] A per-node firewall (NAT) rule push that the node's cs-agent did not accept is now recorded as a warn system event (deduplicated per node every 15 minutes) naming the node and the address dialed. Previously both an unreachable agent and an agent that rejected the push were discarded silently, leaving that node's published-port rules stale with nothing to indicate it and no scheduled reconcile to correct it. Rule-building failures, which already alerted, are unchanged.
- [FIX] A transport failure while pulling a node's cs-agent changelog now also raises a warn system event instead of only reporting to Sentry, so a node whose agent has become unreachable is visible in the admin UI. This condition does not mark the node offline (the health check reaches the node over a different path and correctly reports it up), but it stalls task and backup status projection for that node.
- [CHANGE] `rake test_connection:nodes` now also checks each node's cs-agent, and every check prints the address it dialed — the node's transports no longer necessarily share one address. A new `rake test_connection:agent` runs only that check, distinguishing an address nothing answers on from an agent that answers and rejects the controller's admin token. Neither writes to the event log.

**This is an ordinary upgrade** — `cstacks upgrade` (database backup + `db:migrate`) with no node-side changes and no coordinated window. The new column is nullable and defaults to unset, so the agent channel keeps using each node's Primary IP until you change it.

To move a node's agent channel, set **Agent Host** on the node (Admin → Regions → node), then run `rake test_connection:agent` and confirm that node reports `HTTP 200 - admin bearer accepted`. Clearing the field reverts the node. The task reports nothing to the event log, so it is safe to re-run as often as you like during a cutover.

Two failures it distinguishes: *nothing answered at this address* means either the node's firewall does not accept the controller on that path, or the agent's `metadata.listen_addr` in `/etc/computestacks/agent.yml` is pinned to `<primary_ip>:8500` instead of the default `:8500`; *the agent rejected our admin token* means the address is fine but the node's `admin.token_hash` does not match. Do **not** narrow `listen_addr` to the new address — containers reach that same listener at `metadata.internal` (the Primary IP), so narrowing it breaks metadata for every container on the node.

## v9.7.0

- [CHANGE] Volume backup coordination, per-node firewall (NAT/ingress) rules, and backup/restore/export/delete jobs now run entirely through the per-node **cs-agent HTTP API** instead of Consul. The controller PUSHes desired-state (firewall rules, volume backup config, tasks) to the agent's `/v1/admin/*` endpoints and PULLs node-reported truth (task status + results, borg repository state) from each node's append-only changelog, projecting it into local tables. This completes the migration begun in v9.6.0 (customer metadata) and **removes Consul/Diplomat from the controller entirely** — the `diplomat` gem, the Consul initializer, tokens/policies, and the Consul cleanup tasks are gone.
- [CHANGE] Backup/restore/export/delete readiness is now gated on the cs-agent **task status carried in the changelog** rather than the agent POSTing to `/api/system/events`. The controller-side backup UX is unchanged — the EventLog is still driven to running/completed/failed and callbacks still fire, now by a changelog-driven reconciler — but the agent-facing `POST /api/system/events` ingest endpoint is retired (its `create` action and route are removed; read/update remain). A completed backup/export now records a summary of the agent's structured result (e.g. last-backup time) on the event; failures carry the captured borg output. The per-step borg progress that the old csevent stream showed is no longer carried on success (it remains in the agent logs).
- [CHANGE] Volume teardown (borg repository destroy) is now an idempotent agent task triggered by `DELETE /v1/admin/projects/{id}/volumes/{name}`; the controller re-issues (bounded) on a failed teardown. Physical volume deletion via the storage driver is unchanged. The customer metadata Bearer (formerly the Consul ACL token) is retained.
- [FEATURE] Containers can now request an action on their own project through the cs-agent. The controller polls each node's cs-agent changelog, projects requested actions into a local table, and dispatches them through a generic, engine-pluggable action registry — **core defines no actions of its own**; a plugin engine registers a handler per action type. Each action is authorized by its handler (only the owning engine's projects run it), deduplicated and rate-limited per project, and retried with backoff; delivery is idempotent. Pull-only over the existing per-node agent Bearer — no new node-facing surface. Inert unless a plugin engine registers a handler.
- [FEATURE] Per-domain **HSTS `includeSubDomains`** and **`preload`** toggles, plus a per-domain **`X-Frame-Options: SAMEORIGIN`** toggle, on the domain edit form and the public API. `preload` is only emitted when `includeSubDomains` is also enabled (the HSTS preload list requires it).
- [CHANGE] The load balancer no longer emits an always-on, preload-ineligible `Strict-Transport-Security: max-age=…; preload;`. HSTS now defaults to `max-age=63072000` and appends `includeSubDomains`/`preload` only when the domain opts in.
- [CHANGE] The load balancer now injects baseline security response headers (`X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`) when the backend did not set its own, strips the backend `Server` header, and — for force-SSL domains only — upgrades same-host `http://` redirect `Location` values to `https://`.
- [CHANGE] The load balancer strips client-supplied non-canonical forwarding headers (`X-Client-IP`, `X-Originating-IP`, `X-Remote-IP`, `X-Host`, `X-Forwarded-Server`, `X-HTTP-Host-Override`, and similar) on every request, and additionally strips `X-Forwarded-Host`/`Forwarded` from untrusted (non-CDN) requests, closing IP/host-spoofing vectors. The existing `X-Real-IP`/`X-Forwarded-For` real-client-IP handling and Cloudflare/Bunny trust are unchanged.
- [FIX] Cloning a project no longer stalls partway through. A clone would take its snapshot of the source volume successfully and then silently stop without ever starting the restore, leaving the new volume empty and the order stuck in `processing` with nothing in the logs — reliably, for any volume large enough that its snapshot took more than a few seconds. (The clone service read the source's backup list once, cached it, and then waited up to five minutes for a *new* snapshot to appear in that cached copy, where it never could.) A handful of other latent faults in the same path are fixed with it: a failed clone reporting the order as successful; two volumes cloning at once matching each other's progress events; a single manually-named backup on the source crashing the "reuse a recent snapshot" shortcut; and the temporary snapshot being left behind whenever a clone failed.
- [CHANGE] Volume data restores now run **in the background instead of holding the order open**. An order that clones volumes completes as soon as its containers are built, and the project is usable immediately while its data copies in; the project page shows per-volume restore progress and, if something goes wrong, a failure notice linking to the event. Volumes now restore **in parallel** rather than one after another, several volumes cloning from the same source share a single snapshot of it, and progress survives a controller restart mid-copy — a restore that used to be destroyed by a deploy now resumes on its own within seconds. A clone that fails can no longer fail the order (which previously tore down the project's private network). Cloning from a volume in another availability zone, or naming a snapshot that does not exist, is now rejected when the order is submitted instead of failing minutes later.
- [FIX] An order is no longer failed at the last step because the node agent was briefly unreachable. When the controller could not provision the project's metadata tenant on the agent — a condition that repairs itself on the next metadata write — it marked the whole order failed and detached the project's private network, even though every container, volume and subscription in the order had already been built successfully. The condition is now recorded on the order's event and the order completes.
- [FIX] Load balancer host-matching ACLs are now case-insensitive and consistent across the HTTP and HTTPS frontends. Previously a mixed-case `Host` header failed to match on the HTTPS frontend (returning 503 instead of routing); routing, the Cloudflare/Bunny access restriction, and per-domain response headers (`X-Frame-Options`, `X-Robots-Tag`) now handle mixed-case hosts uniformly on both frontends.

**The cs-agent Consul-retirement changes above require a coordinated, controller-off-first rollout — every node must be on the Consul-free cs-agent (v3.1.0) before the new controller starts, and the controller must backfill each node's desired-state on first boot.** Consul is not a runtime fallback in this release; rollback is the reverse cutover. (The other v9.7.0 changes above need no migration.)

1. **Pre-window.** Snapshot each node's cs-agent `control.db` (the rollback anchor) and leave Consul running (the other anchor). Drain in-flight backup/restore jobs **and any in-flight volume clones/restores**. Ensure the provisioner (Ansible) is ready to stop deploying Consul (Phase-3 prerequisite). Two things to note before you start: **no scheduled backups fire** from the moment the old agent stops until step 5 latches each node (the v3 agent's schedule table starts empty and is rebuilt only by the backfill's volume PUTs), so keep the window short or accept the gap; and the `control.db` snapshot is also the **state-loss boundary** — any ingress-rule, volume or backup-config change made after it is taken is lost if you roll back to it.
2. **Stop the current controller.** No more Consul writes; running containers are unaffected.
3. **Deploy cs-agent v3.1.0 to all nodes and start it, then stop Consul.** The agent migrates its `control.db` additively and leaves the live published-port nftables table and running workloads untouched through the gap (published ports stay as-is). One exception: the `DOCKER-USER` cross-project isolation rules **do** update at agent boot, so cross-project reachability of published ports begins here rather than at step 5.
4. **Deploy and start this controller** (`cstacks upgrade` backs up the database and runs `db:migrate`). It talks only to the agents (per-node admin Bearer on `Node#agent_token`); it has no Consul client.
5. **Backfill (mandatory):** run `bundle exec rake agent:datachannel_backfill`. It PUTs every online node's firewall rules and every volume's backup desired-state to the owning node's agent, then latches `nodes.datachannel_backfilled_at` **only for nodes whose full pass succeeded**. The controller **refuses to dispatch backup, restore, export and delete tasks to a node until its sentinel is latched** (recording a warn system event, deduplicated per node every 15 minutes), so this must run before normal operation. It is idempotent and resumable. Nodes that are **disconnected or in maintenance are excluded from the pass entirely** — the task ends with an explicit `[pending]` list of every node that is not yet backfilled, and the fleet is only ready when that list is empty. Re-run the task until it is. Also grep the output for `[skip] volume`: a volume with no online node is skipped without blocking its node from latching, and its backup schedule is not seeded until the next dispatch self-heals it.
6. **Verify per node:**
   - Firewall renders: `nft list table ip cs_agent` on the node (the table is family `ip`, not `inet`).
   - Volumes and their backup schedules are present: `sqlite3 /var/lib/cs-agent/control.db 'select count(*) from volumes; select count(*) from schedules;'` (schedule detail: `select volume_name, cron_expr, datetime(next_fire_at,"unixepoch") from schedules;`) — this is node-side only; no controller page shows it.
   - The firewall desired-state landed: `sqlite3 -header -column /var/lib/cs-agent/control.db 'select key, value from control_meta;'` — `firewall_populated` and `volumes_populated` must both be `1`. That sentinel, not the `firewall_rules` row, is what gates the render: until it latches the agent logs `firewall desired-state not yet populated; leaving live published-port table untouched` once a minute and leaves the live nftables table alone, so published ports keep working through the gap. The agent latches it in the same transaction as the desired-state write, and the log stops within one 60s reconcile tick. (`generation`/`applied_generation` on the DOWN tables are inert in this release — the writeback is not wired yet.)
   - A task round-trips: run a manual backup and watch the event log reach completed, or check its `agent_tasks` row in the controller database.
   - The per-node changelog cursor advances: `Node.find(id).changelog_cursor` from a Rails console (no admin page exposes it).
   - **Ack, not prune.** Confirm the ack watermark advances. Actual pruning of acked changelog entries only begins once entries pass the agent's 7-day retention floor, so it is *not* observable during the window — check it a week later.
7. **Decommission Consul** — the Consul processes and the provisioner's Consul role — once the fleet is confirmed healthy.

**Rollback (until step 7):** on every node restore the `control.db` snapshot **and** downgrade the agent to v2.0.0 — snapshot first, because an old binary refuses to boot against a migrated DB. Note the apt **package** version is a different numbering scheme from the agent's own version string (package `1.5.0` ships agent `2.0.0`), so record `dpkg-query -W -f='${Version}\n' cs-agent` before upgrading and downgrade to that exact string (`apt-get install --allow-downgrades cs-agent=<recorded-package-version>`). Then restart Consul and redeploy the previous controller. Four things this release adds to that:

- **Do not run `db:rollback`.** The v9.7.0 migrations are additive, and v9.6.2 runs correctly against the migrated schema (the new tables are simply ignored). Reversing them drops `volume_clone_jobs`, whose rows are the only pointers to temporary clone snapshots in source borg repositories — rolling it back leaks those archives permanently. Any clone or restore in flight at rollback is stranded and needs manual cleanup.
- **Re-push desired state changed during the window.** v9.7.0 writes desired state only to the agents, never to Consul, so restoring a `control.db` snapshot discards it while the controller database still believes it was applied. After rolling back, re-save any ingress rules and volume backup settings changed during the window so v9.6.2 writes them back to Consul — otherwise a volume created in the window silently never gets scheduled backups again.
- **Do not leave a v3.x agent running under a v9.6.2 controller.** The metadata API still answers, so the fleet looks alive while the entire coordination plane is dead: backups and restores never run and ingress changes never apply, both silently. The agent downgrade is not optional.
- **If you later retry the upgrade,** first reset the changelog cursor for every node whose `control.db` you restored or recreated: `Node.where(...).update_all(changelog_cursor: 0)`. The agent serves changelog entries with a sequence above the cursor the controller holds, and a restored database restarts that sequence at 1 — so a controller still holding the high cursor from the failed attempt polls above everything the agent will ever produce, receives an empty page indistinguishable from a healthy one, and silently never sees another task result, repository update or container action. Nothing alerts, and the undelivered entries are pruned after 7 days.

***

## v9.6.2

- [FEATURE] The shared-memory (`/dev/shm`) size of a container service can now be set from the service edit form (in MB) and via the public API (`shm_size`, in bytes) instead of only from the Rails console. The value is capped at the service's memory limit; `0` uses the image default (64MB). A container rebuild is required to apply the change.

***

## v9.6.1

- [FEATURE] Ingress rules can now restrict external access to **Bunny CDN** only (`restrict_bunny`), mirroring the existing Cloudflare restriction. The two are mutually exclusive per rule.
- [CHANGE] The load balancer now sets both `X-Real-IP` and `X-Forwarded-For` to the real client on every request — the CDN-attested address for trusted-proxy connections (Cloudflare/Bunny/edge) and the connecting IP otherwise (non-spoofable) — and preserves `X-Forwarded-Proto`, so backends reading either header get the visitor IP.
- [CHANGE] Cloudflare/Bunny proxy IP ranges are now stored as account-global files (`lib/proxy_ips/*.lst`), diffed and refreshed daily (Bunny is now refreshed on schedule too), replacing the per-load-balancer database rows. The migration removes the old Cloudflare `load_balancer_addr` rows.

**Requires a persistent mount** for the CDN IP lists on containerized controllers: a host directory mounted onto `/usr/src/app/lib/proxy_ips` (e.g. `/var/lib/computestacks/proxy_ips`). See `doc/upgrades/v96/v96 Load Balancer Real-IP and CDN Proxy IPs.md`.

***

## v9.6.0

- [CHANGE] Customer metadata (project metadata blob, SSH keys, SFTP host keys, and the writable `/db` space) now lives on the per-node **cs-agent** instead of Consul KV. The controller pushes/reads it via an authenticated agent API; the per-project Consul ACL token/policy is replaced by an agent-side tenant. The full metadata blob is unchanged — only the storage backend moves. Consul still backs the coordination plane (volumes, jobs, firewall) until a later phase.

**Migrating to this release is a coordinated, per-node rollout — do not upgrade the controller in isolation:**

1. **Nodes** must run the cs-agent build that serves the new metadata API, bound to `primary_ip:8500`. Consul's HTTP listener moves to `:8502` (provisioner change); gossip/RPC/DNS ports are unchanged. Verify every controller reaches Consul over **https/8501** (mTLS) — a controller still using **http/8500** will collide with the agent and must be repointed first.
2. **Set `NODE_ENROLLMENT_TOKEN`** in the controller environment and the Ansible vault (matching values). The provisioner (running on the node) uses it to fetch the node's admin-token hash from `GET /api/system/nodes/agent_token_hash` (the node is identified by its source IP); the controller mints the per-node admin Bearer and stores it encrypted (new nodes at creation; existing nodes are minted by the `metadata:agent_backfill` rake in step 3).
3. **After the agent is bound on `:8500`,** run `rake metadata:agent_backfill` to provision every project's tenant and seed its managed blobs on the agent (idempotent and resumable — re-run for any project whose node was offline).
4. **Rebuild the bastion images** — `docker-images/bastion` (the `/db` writers) and `cs-docker-images/cs-docker-bastion` (the SSH/host-key readers). They use `METADATA_SERVICE`-derived paths that the legacy shim does **not** cover, so they must be rebuilt; the exact per-image path changes are in `doc/upgrades/v96/v96 Controller Metadata Cutover.md`. (phpMyAdmin needs no change — it reads `METADATA_URL`, which now carries the new endpoint.)
5. **Per-project migration = rebuilding that project's bastion.** Containers that haven't recycled keep working: old monarx still reads node id via the legacy `/metadata?raw=true` shim the agent serves, so php/wordpress containers are not customer-impacted and migrate naturally as they recycle.

***

## v9.5.2

- [FIX] Scaling a service down no longer fails with "Network size can not accommodate the requested number of containers." The private-network capacity check was comparing the wrong quantity and ran even when removing containers; it now only applies when adding containers and checks the number of new addresses needed against those available.

***

## v9.5.1

- [FIX] Container image pulls that fail registry authentication (401/403) now record a system event for operators instead of flooding Sentry.
- [FIX] Catch `Oj::ParseError` (not only `JSON::ParserError`) when parsing writable project metadata, so malformed/partial data degrades gracefully instead of raising.

***

## v9.5.0

- [FEATURE] Download backup archives — generate a presigned, time-limited download URL for any backup snapshot from the volume backup list (end-user UI, admin UI, and API).

**Requires cs-agent v1.10 on all nodes**, and the borg container set to **v1.5** in each node's `agent.yml`. Exports run read-only with `borg export-tar --bypass-lock`; the host `cs-borg_compact` cron must be retired on every node sharing a backup server before enabling.

***

## v9.4.12

- [FIX] Update promql for metrics.

***

## v9.4.11

- [FIX] A few bug fixes related to adding free containers with the api on an existing project (i.e. phpMyAdmin).
- [FIX] Correctly include image_variants in `/api/container_images` endpoint.
- [CHANGE] Add `/api/image_variants/:id` endpoint to allow for locating a container image with just an image variant id.

***

## v9.4.10

- [FIX] Resolve broken docker client after recent update.

***

## v9.4.9

- [CHANGE] Support Bunny CDN and move haproxy ip lists to separate files.

This release lays the ground work to be able to restrict ingress rules to bunny, just like we have now for Cloudflare.

***

## v9.4.8

- [FIX] Resolve issue with callback when changing container variant.

***

## v9.4.7

- [FIX] Resolve issues with gitlab ci.
- [FIX] Cleanup sql.
- [FIX] Gracefully fail if a node is offline while attempting to create the bridged network.

***

## v9.4.6

- [FIX] Expose service variant migration via API.

***

## v9.4.5

- [FIX] prometheus dates should be converted to UTC.
- [FIX] Correctly map backup and restore events to their parents when initiated via API.
- [CHANGE] Bump local ruby version (production container unaffected).

***

## v9.4.4

- [FIX] Fix metrics api endpoint to account for containers without a package

***

## v9.4.3

- [FEATURE] (API) Added simple metrics endpoint for projects that aggregates a bunch of service metrics.
- [CHANGE] Updated prometheus queries.

***

## v9.4.2

- [CHANGE] Bump default sftp container up to 1 core and 1GB of ram.
- [FIX] Take into account cpu quota in cpu graphs.
- [CHANGE] Disable cpu usage alerts from AlertManager, as those are not taking into account the cpu limit of the container, and creating false positives.
- [CHANGE] Haproxy: Remove multi-processor support since it now automatically creates threads to match available cpu cores.
- [CHANGE] Haproxy: Enable connection re-use
- [CHANGE] Haproxy: Update logging to record all connections.

***

## v9.4.1

- [FIX] CloudShell API was not returning the URL in the correct format.
- [FIX] Change domain ownership was not correctly updating the certificate owner.
- [FIX] Usage collection was not gracefully handling products without a price.

***

## v9.4.0

- [FEATURE] Cloud Shell (Powered by Guacamole).
- [FEATURE] Support for ACME providers other than LetsEncrypt. Includes support for EAB.
- [CHANGE] Renamed Lets Encrypt to "Free SSL Certificate" or "ACME" in the interface.
- [CHANGE] Upgrade ruby from v3.3 to v3.4

***

## v9.3.6

- [FIX] Changing an account owner will wipe out the certificate.
- [FIX] Network and Load Balancer charts
- [FIX] various small bug fixes related to nil values.

***

## v9.3.5

- [CHANGE] Support for Docker v28+.
- [FEATURE] Added option in admin (Settings -> Regions -> Manage) to rebuild all container networks. This is required to update all networks to support Docker v28+.

***

## v9.3.4

- [FIX] Cleanup unlinked networks off of the node.

## v9.3.3

- [FIX] Resolve issue that prevented image dependencies from being removed.

***

## v9.3.2

- [CHANGE] Monarx API

***

## v9.3.1

- [CHANGE] Include `node_id` in metadata service.
- [FIX] Fix global search for long url's.
- [FIX] Resolve issues with monarx API.

***

## v9.3.0

- [FEATURE] Introducing Callbacks for the API. This allows you to receive a webhook from ComputeStacks when a api request is completed by a background worker.
- [FEATURE] Move acme validation IP to a database field on the region. This allows different IPs for different regions.

***

## v9.2.2

- [FEATURE] Added volume and backups api.

***

## v9.2.1

- [FEATURE] `on_latest_image` Boolean field added to container and bastion api calls. If false, there is a new image on the node and a rebuild will use the new image.

## v9.2.0

***

**YJIT and JEMALLOC for ComputeStacks Production Environments**

Please add the following to your `/etc/default/computestacks` file:

```
MALLOC_CONF=dirty_decay_ms:1000,narenas:2,background_thread:true,stats_print:false
RUBY_YJIT_ENABLE=1
```

And download the latest `cstacks` helper script onto the controller with this command:

```bash
wget -O /usr/local/bin/cstacks https://raw.githubusercontent.com/ComputeStacks/ansible-install/main/roles/controller/files/cstacks.sh \
  && chmod +x /usr/local/bin/cstacks
```

Please see[v92 Notes.md](./doc/v92 Notes.md) for more details.

**Major Changes to the development environment**

This release includes major changes to how our development environment is configured.

- The controller, postgres, and redis are now run by calling `docker compose up -d` locally on your development machine. This means you'll need to have docker installed locally.
- Our vagrant image is now much closer to a production compute node, in that it only runs the containers as a node and no longer runs any of the controller.
- The controller's gemfile no longer pulls the gem from Github, but just does a git clone. This removes the requirement of having a github account to build the controller.

See [DEV_SETUP.md](./doc/DEV_SETUP.md) for specific instructions.

***

* [CHANGE] Upgrade ruby to 3.3, and rails to 7.1, and fix deprecations and bugs introduced with this upgrade.
* [CHANGE] Remove Rails.secrets in favor of environmental variables.
* [CHANGE] Disable marketplace reporting. This project is on an indefinite hold.
* [FIX] Updated monarx integration to resolve api issues.

***

## v9.1.2

* [FIX] Don't attempt node evacuation with local networking.

## v9.1.1

* [CHANGE] Add `make_primary` to container domains api.
* [CHANGE] Add caching to container stats.
* [CHANGE] Fix haproxy ipv6 support.
* [CHANGE] Add `X-Robots-Tag: noindex, nofollow` header to all sites using the default load balancer domain.

***

## v9.1.0

* [FEATURE] Introduced a new writable metadata endpoint `/db/` to allow for custom images to pass data back to ComputeStack Engines.
* [FEATURE] Added `docker_init` to container images. See [docker run --init](https://docs.docker.com/engine/reference/run/#specify-an-init-process) for more details.
* [CHANGE] The container image used for the bastion container can now be set in the admin settings.
* [CHANGE] Add secure cookies to HAProxy for SSL frontends. (`SERVERID` used for session stick)

***

## v9.0.1

* [CHANGE] Allow customization of ShmSize (Admin only).
* [CHANGE] Better service display for containers without volumes, settings, or domains.
* [FIX] Containers without a volume would fail to deploy.
* [FIX] phpMyAdmin Containers would fail to provision.
* [FIX] Vagrant installer was not creating the volume.

***

## v9.0.0

Version 9 includes major changes related to networking and integrations.

* [FEATURE] Support for plugins via Rails Engines.
* [FEATURE] Support for using linux bridges instead of Calico for container network.
* [CHANGE] Use docker api to determine container state, rather than prometheus.

***

## v8.1.1

* [FIX] Bug fixes around admin management of volumes.

***

## v8.1.0

_Please see doc/upgrades/v81/ for upgrade notes._

* [CHANGE] Replace webpacker with importmaps.
* [CHANGE] Replace passenger with puma.

***

## v8.0.4

* [CHANGE] Update initial images on a fresh install.
* [FIX] Don't cache dns results when validating lets encrypt domains.
* [FIX] Custom load balancer images were failing to deploy properly.

***

## v8.0.3

* [FIX] If phpMyAdmin was selected during an order, an error would prevent the order from being successful.
* [FIX] Adding a domain without selecting a project would result in a 500 error.

***

## v8.0.2

_Mar 14, 2023_

* [CHANGE] Wordpress: Default to `wp-cli` within the sftp container, rather than the app container. This way WP functions will still work even with the container is offline.
* [CHANGE] Pin the borg backup container to a specific version, rather than the latest tag.
* [CHANGE] Ignore containers that have a service role label.

***

## v8.0.1

_Mar 8, 2023_

* [CHANGE] Provide additional feedback if ComputeStacks is unable to locate a node during an order.
* [CHANGE] Hide node disk IO limit settings due to poor overall system performance when enabled.
* [FIX] Editing variable environment variables for a service would not show all possible options, including the currently selected one.
* [FIX] Adding a new image variant and checking the default box would not uncheck the previous default variant.
* [FIX] non-admins were unable to deploy collections with hidden images.
* [FIX] Fixed broken icons.

***

## v8.0.0

_Mar 1, 2023_

* [FEATURE] Clone Project.
* [FEATURE] Clone volumes.
* [FEATURE] Shared mountable volumes.
* [FEATURE] Support for custom `/etc/hosts` entries in both images and containers.
* [FEATURE] Image Variants
* [FEATURE] Image Collections
* [FEATURE] Image categories. When editing an image, you can define a category; images will be grouped by category on the order page.
* [FEATURE] Specify default variant when linking images. Note: Currently only accessible via API and console.
* [FEATURE] Support for monthly (post-paid) billing plans. New subscriptions will be prorated to the first of the month.
* [FEATURE] Support for paid addons, with the ability to allow users to selectively activate or deactivate them.
* [FEATURE] Support for marketplace addons via plugins.
* [FEATURE] New order provisioning screen after an order is placed.
* [CHANGE] Both `tcp` and `udp` will share the same external NAT port.
* [CHANGE] Previously, even if over-commit memory/cpu was enabled, ComputeStacks would still prevent placing containers on a node that did not have enough cpu or memory available. This would cause orders to fail; this will now follow the over-commit setting as well.
* [FIX] Resolved issue that would randomly cause an ip address to be assigned to multiple containers at once, and cause a provision failure.
* [FIX] Annual snapshot retention was not visible in the UI.
* [FIX] Region allocation was over counting SFTP containers.
* [FIX] Resolve broken unsuspend user api.
* [FIX] Resolve issue that prevented billing event data from being included in web hooks.

***

## v7.1.8

_May 19, 2022_

* [FIX] Resolve issues with collaborator API.

***


## v7.1.7

_May 2, 2022_

* [FIX] Resolve issue that could prevent users from deleting projects.

***

## v7.1.6

_Apr 27, 2022_

* [CHANGE] Make lets encrypt dns validation waiting period configurable in the

***

## v7.1.5

_Apr 15, 2022_

* [CHANGE] Support for dns servers that are accessed in other locations. ComputeStacks will now check if a zone already exists before creating it. If a zone exists and you wish to manage it from ComputeStacks, you will need to first add it in the administrator and uncheck the Create Zone box.

***

## v7.1.4

_Apr 14, 2022_

* [FIX] Resolve a bug that would allow removing the final phase of a billing resource.

***

## v7.1.3

_Apr 13, 2022_

* [CHANGE] Support for generating single-domain LetsEncrypt certificates.
* [CHANGE] Move wordpress beta features behind a feature flag.
* [CHANGE] Configuration option to temporarily disable LE automatic generation & renewal.
* [CHANGE] Increase LetsEncrypt provisioning from every 15min, to every 8min.

***

## v7.1.2

_Apr 6, 2022_

* [CHANGE] Update container registry to include docker user agent. Resolves an issue that prevented CS from validating images hosted on container registries that were only allowing the docker user-agent to connect.

***

## v7.1.1

_Mar 29, 2022_

* [FIX] Resolve issue with orphaned collaboration records.

***

## v7.1.0

_Mar 21, 2022_

* [FEATURE] Wordpress Integration Beta

***

## v7.0.2

_Feb 16, 2022_

* [FEATURE] Allow default domain to be set via the API.
* [CHANGE] Remove last part of existing metdata api (phpMyAdmin moved to new metadata service).
* [FIX] Bug fixes with our vagrant image.

***

## v7.0.1

* [FEATURE] Brand new vagrant image to aid in development.
* [CHANGE] Allow containers within a project to be linked by role, rather than a specific version.
* [FIX] Rollback libravatar service to gravatar due to performance issues.

***

## v7.0.0

_Jan 1, 2022_

* [CHANGE] License changed to AGPL.
* [FEATURE] SSH Keys for SFTP Containers and configurable password authentication.
* [FEATURE] Download connection profiles for Filezilla and Transmit.
* [FEATURE] Switch from gravatar to libravatar.
* [FEATURE] Set a global motd for all sftp containers. (Admin)
* [FEATURE] Moved metadata service to distributed database within each availability zone.
* [FEATURE] Improvements to global search. (Admin)
* [CHANGE] Allow udp and tcp to share the same port
* [CHANGE] Provide feedback on how a user can change their profile pic
* [CHANGE] Show user profile pics in admin
