# Bootstrap Manifest (`schema_version: 1`)

The bootstrap manifest is a **pure-data YAML document** describing the desired state of a
ComputeStacks controller installation. It is rendered by the provisioner and applied with:

```
rake bootstrap:apply[/var/lib/computestacks/manifest.yml]
DRY_RUN=1 rake bootstrap:apply[/var/lib/computestacks/manifest.yml]   # diff only, writes nothing
UPDATE_ADDRESSES=1 rake bootstrap:apply[…]                            # also converge infra addresses
```

`DRY_RUN` and `UPDATE_ADDRESSES` are independent and combine: setting both previews the address
changes without writing them.

It replaces the generated `bootstrap.rake` template, which embedded Ruby in a Jinja template and
silently drifted from the controller's models across releases. **This document is the contract.**
Every field below was derived from `db/schema.rb` and the model validations/callbacks in this
repository, not from any external sketch. Where the two disagree, this document wins.

The manifest carries secrets (admin password, DNS API keys, the load balancer private key). Render
it `root:root 0600` and delete it after a successful apply.

---

## Contents

- [Apply semantics](#apply-semantics)
  - [Exemptions from bootstrap-only](#exemptions-from-bootstrap-only)
    - [Credential rotation](#credential-rotation)
    - [Address updates](#address-updates)
  - [Drift warnings](#drift-warnings)
- [Ordering](#ordering)
- [Write semantics — plaintext vs encrypted](#write-semantics--plaintext-vs-encrypted)
- [Top level](#top-level)
- [`settings`](#settings)
- [`metric_clients` / `log_clients`](#metric_clients--log_clients)
- [`dns`](#dns)
- [`locations`](#locations)
  - [`locations[].regions`](#locationsregions)
  - [`…regions[].nodes`](#regionsnodes)
  - [`…regions[].networks`](#regionsnetworks)
  - [`…regions[].load_balancer`](#regionsload_balancer)
- [`products`](#products)
- [`catalog`](#catalog)
- [`user_group`](#user_group)
- [`features`](#features)
- [`admin_user`](#admin_user)
- [Full example — greenfield](#full-example--greenfield)
- [Full example — attach a second region](#full-example--attach-a-second-region)
- [Fields deliberately NOT in the manifest](#fields-deliberately-not-in-the-manifest)

---

## Apply semantics

**This bootstraps a controller. It does not converge one.**

A controller is edited by humans, through the admin UI, for years after it is installed. A
manifest the provisioner rendered months ago is not a statement of desired state — it is a
starting point that has since been overtaken. So the rule is:

> **If it already exists in the database, the manifest does not touch it.** The database wins, and
> the difference is *reported* so the operator knows their inventory has gone stale.

Without that rule, deploying one new node next year would silently roll back every
shared-infrastructure change made since the controller was installed.

**Every section is optional.** A section that is absent is not touched at all. An *attach*
manifest (adding a region to a live controller) carries only `locations` — and, if the new region
needs its own Prometheus/Loki, `metric_clients` / `log_clients`. It never touches settings, DNS,
products or the admin user.

- **Entities: create-if-absent only.** `Location`, `Region`, `Node`, `Network`, `LoadBalancer`,
  `MetricClient`, `LogClient`, the DNS `ProvisionDriver`, `Dns::Zone`, the default `UserGroup` and
  the admin `User` are created when their natural key finds nothing. When it finds a row, **not one
  attribute is assigned**: the row is reported as `[skip] … (exists, skipped)` and the apply moves
  on. The exceptions are enumerated in [Exemptions from bootstrap-only](#exemptions-from-bootstrap-only)
  below — six paired credentials that always converge, and three infrastructure addresses that
  converge only under `UPDATE_ADDRESSES=1`. Nothing else.
- **Additive operations still run on a live controller,** because they create rather than rewrite:
  a new node or network inside an existing region, the default user group's link to a new region,
  and the [billing price extension](#billing-price-extension) below.
- **`settings` and `features`: seed the unconfigured only.** Their rows are not create-if-absent —
  `Setting.setup!` and `Feature.setup!` create every one of them at install time, so "skip it if it
  exists" would mean the manifest could never seed anything at all. See [`settings`](#settings) and
  [`features`](#features) for the exact test.
- **Never destroy.** The apply service never calls `destroy`, `delete`, `destroy_all`, or a
  `collection=` assignment that would orphan rows. This is enforced structurally: a SQL subscriber
  is active for the whole apply and raises if any `DELETE` is issued against a manifest-managed
  table (`locations`, `regions`, `nodes`, `networks`, `load_balancers`, `provision_drivers`,
  `product_modules`, `metric_clients`, `log_clients`, `settings`, `dns_zones`, `users`,
  `user_groups`, `billing_*`). This matters most for `ProvisionDriver`, which is
  `has_many :regions, dependent: :destroy` — a "recreate the DNS driver" path would cascade-delete
  every region on the controller.
  *(`features` is excluded from the guard: `Feature.setup!` is the application's own routine and
  prunes flags that no longer exist in the code. It is only run when the `features` section asks
  for it.)*
- **Atomic.** The whole apply runs in one transaction; each section is a savepoint. Any validation
  error aborts with a message naming the section and the key path (e.g.
  `locations[0].regions[0].nodes[1].primary_ip`) and a non-zero exit status. Nothing is left
  half-applied.
- **`DRY_RUN=1`** prints the creates it would perform, the credential rotations, the address
  updates (when `UPDATE_ADDRESSES=1` is also set), and the drift warnings, then rolls back. Nothing
  is written and no `after_commit` callback fires.

### Exemptions from bootstrap-only

There are exactly two, and both are enumerated field lists rather than rules about rows:

| Exemption | Fields | When |
| --- | --- | --- |
| [Credential rotation](#credential-rotation) | six, across four models | **always** |
| [Address updates](#address-updates) | three, across three models | **only with `UPDATE_ADDRESSES=1`** |

Everything else on those same rows — and every field on every other row — still follows
bootstrap-only: compared, reported as [drift](#drift-warnings), not written.

#### Credential rotation

Six fields, on four models, are **not** covered by the rule above. On a row that already exists
they are compared against the manifest and, when they differ, **written**:

| Model | Fields |
| --- | --- |
| `MetricClient` (`metric_clients`) | `username`, `password` |
| `LogClient` (`log_clients`) | `username`, `password` |
| `ProvisionDriver` (`dns.driver`) | `api_key`, `api_secret` |
| `LoadBalancer` (`regions[].load_balancer`) | `shared_certificate`, `stats_password` |

**That list is exhaustive.** Every other field on those same rows — a client's `endpoint`, the
driver's `username` or `settings`, the load balancer's `domain`, `ext_ip` or `le` — still follows
bootstrap-only: compared, reported as [drift](#drift-warnings), not written. Nothing outside these
four models rotates anything; `Region#guac_key`, the admin user's password and every `settings`
value are unaffected. (The DNS driver's `endpoint` is not a credential; it is an
[address](#address-updates), and it moves only under the flag.)

They are exempt because they are **machine-paired values the provisioner owns on both ends**. The
same vaulted variable that renders into the manifest also renders the other half of the pair, and
the provisioner converges that half on every run:

- the htpasswd file Prometheus and Loki authenticate against;
- PowerDNS's `api-key` in its own configuration;
- the wildcard certificate deployed to the load balancer;
- the haproxy stats password in the generated haproxy configuration.

There is no human decision here to protect: nobody rotates these in the admin UI in a way the
manifest could roll back. Leaving the controller's copy stale is the failure mode — the server side
moves, the controller keeps the old value, and metrics, log queries, DNS or the stats page break
while the playbook run reports success. As the repo owner put it: *if the credential changed on the
shared infrastructure, then we should also update it.*

Each rotated field is reported on its own line, and the value is never printed in either direction:

```
  [skip  ] MetricClient http://10.100.1.5:9090 (exists, skipped)
  [rotate] MetricClient http://10.100.1.5:9090 — password updated (credential rotation)
```

Rotations count in the summary's `rotated` total, and under `DRY_RUN=1` they are previewed exactly
like a create — the lines are printed and the transaction is rolled back, so an attach can be
inspected before it is run.

A field the manifest omits is never rotated (an omitted key is not "set it to blank"), and a value
that has not actually changed is not rewritten: the encrypted fields are compared through their
decrypted reader, so a re-run reports `0 rotated`.

#### Address updates

**These are written only when the apply is run with `UPDATE_ADDRESSES=1`.** Without the flag the
behaviour is exactly the bootstrap-only rule above: compared, reported as
[drift](#drift-warnings), not written. There is no default-on behaviour here and nothing about an
ordinary run changes.

| Model | Field | Manifest key |
| --- | --- | --- |
| `Region` | `acme_server` | `locations[].regions[].acme_server` |
| `Node` | `agent_host` | `locations[].regions[].nodes[].agent_host` |
| `ProvisionDriver` (DNS) | `endpoint` | `dns.driver.endpoint` — only when the `dns` section is present, as ever |

That list is exhaustive. The flag exempts **those three fields**, not the rows they live on: a
region's `pid_limit`, a node's `public_ip` and the driver's `username` still only warn, with the
flag set or not.

They are exempt because they name an address the provisioner *derives* rather than one an operator
*chooses*, and because a deliberate topology change has to be expressible. Rolling Tailscale onto a
region that is already live is the case this exists for: the addresses move together, on every node
and on the ACME helper and the PowerDNS API at once, and doing that by hand in the admin UI on a
live fleet is exactly the kind of change an operator asks the manifest to make. It is opt-in rather
than automatic because the same write on a routine "add a node" run would silently undo an address
somebody moved in the UI — which is the whole reason the bootstrap-only rule exists.

**`agent_host` clears.** Under the flag, a node entry whose `agent_host` key is **absent or null**
sets the column back to `NULL`. This is the one place in the manifest where an omitted key is not
"leave it alone", and it is deliberate: the provisioner derives `agent_host` *pairwise* and omits
the key entirely when that node and the controller are not both on the tailnet, so "no key" is the
only way a rollback off the tailnet can be expressed. A cleared node behaves exactly as it did
before the column was ever set — `Node#agent_address` falls back to `primary_ip`. Without the flag
an absent key is ignored, as everywhere else. `acme_server` and the driver's `endpoint` do **not**
clear: an absent key for those is still ignored, flag or no flag.

> **Runs using this flag must be full runs.** The addresses above are derived from inventory and
> from gathered facts — `agent_host` in particular is a pairwise derivation over the node and the
> controller. A run that renders the manifest against partial data (an `--limit`ed play, or one
> with a cold fact cache) can render an address as absent when it is simply unknown, and under this
> flag "absent" is a write. Use `UPDATE_ADDRESSES=1` only on a full run, or one with a warm fact
> cache covering every node in the manifest.

Each changed field is reported on its own line, and — unlike a credential rotation — **both values
are printed**. An address is not a secret, and an operator who asked for a readdress needs to see
what moved where:

```
  [skip  ] Node node1001 (exists, skipped)
  [readdress] Region ams-005 — acme_server: "10.100.1.10:3000" -> "100.64.0.10:3000"
  [readdress] Node node1001 — agent_host: nil -> "node1001.tail1234.ts.net"
  [readdress] Node node1002 — agent_host: "node1002.tail1234.ts.net" -> (cleared)
```

Address updates count in the summary's **`rotated`** total — they are writes of the same kind, and
that total is the number the provisioner's `changed_when` reads. Under `DRY_RUN=1` they are
previewed and rolled back like everything else. A value that has not changed is not rewritten, so
re-applying an in-sync manifest with the flag still reports `0 rotated`.

### Drift warnings

When a row already exists and the manifest carries values that do not match it, the apply prints
an informational warning naming each field:

```
  [skip  ] Region ams-005 (exists, skipped)
  [warn  ] Region ams-005 — manifest differs from database, database wins — update your inventory or change it in the UI
             pid_limit: database 300, manifest 500
             acme_server: database "10.100.1.10:3000", manifest "10.100.9.9:3000"
```

Nothing is written either way, in a real apply or under `DRY_RUN=1`. The warning is the whole
point: it tells the operator that the provisioner's inventory and the controller have diverged,
without the apply picking a winner on their behalf. Fix it by correcting the inventory, or by
making the change in the admin UI — whichever is actually right.

Redaction is the same as for a create: a value prints as `«redacted»` when the column is encrypted,
or when the setting's name looks like a credential (see [`settings`](#settings)). That covers the
*database's* value as well as the manifest's. The admin user's password is never compared at all.

### Idempotence

Re-applying an unchanged manifest performs zero writes and reports
`0 created, 0 seeded, 0 rotated, 0 linked` with no warnings — with `UPDATE_ADDRESSES=1` as well as
without it. The comparisons that decide whether to warn take the same care the old update
path did — otherwise a healthy install would print permanent false drift:

- Encrypted columns are compared through their *decrypted* reader, because `Secret.encrypt!`
  produces a different ciphertext every call.
- `hostname` is normalised the way `Setting#set_value` normalises it (leading scheme stripped).
- A network's `subnet` is read back through `Network#to_net`, which is the manifest's own notation.

### The failures that remain, even on a row that already exists

Both are about *identity* rather than attributes. Leaving the row alone would not make them safe,
because the manifest is describing something that lives somewhere else, and the apply would go on
to attach this region's configuration to it:

- A `Region` whose name already exists **under a different location**.
- A `Node` whose hostname already exists **in a different region**, or whose `primary_ip` already
  belongs to a different node.

## Ordering

The apply order is fixed and is **not** the order of keys in the file:

1. `settings` (`Setting.setup!` first when `defaults: true`, then the values)
2. `metric_clients`, `log_clients`
3. `dns`
4. `locations` → regions → nodes → networks → load balancer
5. `products`
6. `catalog`
7. `user_group` (+ region links)
8. **billing price extension** — not gated on a section; runs whenever the apply created a region
9. `features`
10. `admin_user`

Two constraints make this order mandatory:

- **Products must come after regions.** `load_products` creates `BillingResourcePrice` rows with
  `regions: Region.all`, and `BillingResourcePrice` validates that at least one region is selected.
  On a greenfield database with no regions yet this raises `RecordInvalid` and the whole bootstrap
  dies.
- **The default user group must come after products.** `UserGroup belongs_to :billing_plan` is
  required; without a plan the group cannot be created.

The apply service never runs `rake install`. That task creates a spurious `demo` Location and a
`DM01` Region that then have to be cleaned up by hand.

### Billing price extension

When a manifest adds a region to a controller that already had regions, existing prices do not
cover it and every product would price at `0.0` there. After `products`, the apply extends prices
to each newly-created region under this rule:

> A `BillingResourcePrice` is extended to a new region **only if it already covers every region
> that existed before this apply**. A price that covers only some pre-existing regions is
> deliberately region-specific and is left alone.

Before linking, the apply checks explicitly that no *other* price in the same `billing_phase` with
the same `currency` and the same `max_qty` already covers the new region — the HABTM
`price.regions << region` path bypasses the parent's `ensure_unique_max_qty` validation, so
duplicate coverage would otherwise be created silently. A price that fails this check is skipped
and reported; it is not an error, because it means an operator has hand-built pricing for that
region.

This survives the bootstrap-not-override rule because it is a **create**: adding a region to a
price's `regions` HABTM makes a link that did not exist. No price row is edited, no existing link
is removed, and no price a human tailored is widened.

## Write semantics — plaintext vs encrypted

Three different write paths exist. Getting one wrong writes a value that decrypts to `nil` at read
time and fails silently in production, so each field below is tagged. For an entity these apply on
**create**, on the six [rotated credentials](#credential-rotation), and on the three
[updated addresses](#address-updates); on a row that already exists the same reader is used to
compare, so the drift warning tells the truth about an encrypted column instead of reporting it as
always-different.

| Tag | Meaning |
| --- | --- |
| **plaintext** | Ordinary column. Manifest value is written as-is. |
| **`Secret.encrypt!`** | The column stores ciphertext and the model reads it back with `Secret.decrypt!`. The manifest carries the **plaintext**; the apply encrypts. |
| **encrypting setter** | The model has a virtual setter that encrypts (`LoadBalancer#shared_certificate=`, `Region#guac_key=`, `Node#agent_token=`). The manifest carries the **plaintext**; the apply assigns through the setter. |
| **model-encrypted** | `Setting#value` — the model's `before_save` encrypts when the row's `encrypted` flag is set. The manifest always carries plaintext and never sets `encrypted`. |

`Secret` derives its key from `SECRET_KEY_BASE`, which must be at least 128 characters and must be
**the same value the controller runs with**. Applying a manifest under a different
`SECRET_KEY_BASE` writes secrets the running app cannot decrypt.

---

## Top level

```yaml
schema_version: 1
```

| Key | Required | Notes |
| --- | --- | --- |
| `schema_version` | **yes** | Must be `1`. Any other value aborts before anything is read. |
| `settings` | no | Hash. |
| `metric_clients` | no | List. |
| `log_clients` | no | List. |
| `dns` | no | Hash. |
| `locations` | no | List. |
| `products` | no | Hash. |
| `catalog` | no | Hash. |
| `user_group` | no | Hash. |
| `features` | no | Hash. |
| `admin_user` | no | Hash. |

An unknown top-level key is an error, not a warning — it is almost always a typo in the
provisioner template.

---

## `settings`

Maps to the `settings` table (`Setting`). One row per named setting; `name` is unique.

```yaml
settings:
  defaults: true
  values:
    hostname: portal.example.com
    registry_node: 10.100.1.20
    registry_base_url: cr.example.com
    registry_ssh_port: "22"
    cr_le: cr.example.com
    company_name: Example Hosting
    app_name: Example Hosting
    general_support: support@example.com
    acme_directory: https://acme-v02.api.letsencrypt.org/directory
    acme_email: ops@example.com
```

| Key | Required | Maps to | Semantics |
| --- | --- | --- | --- |
| `defaults` | no (default `true`) | — | Runs `Setting.setup!`, which creates every setting the app knows about with its default value. Idempotent; creates only what is missing. |
| `values` | no | `settings.value` | Hash of `name` → value. Written **only when nobody has configured that setting** — see below. |

**The apply never creates a `Setting`.** It looks the row up by `name` and **aborts** if it does
not exist, because a row created without the right `category` is invisible in the admin UI and a
mistyped name would otherwise be accepted silently. Leave `defaults: true` (the default) so
`Setting.setup!` has created the row first.

**A value is written only when nobody has configured it.** Create-if-absent is meaningless here:
after `Setting.setup!` every row exists, so skipping existing rows would mean the manifest could
never seed a single setting. The test the apply uses instead is:

> Write the manifest's value if the setting's current value is **blank**, or if the row still
> **looks like nobody has configured it**. Otherwise skip it and report the difference as
> [drift](#drift-warnings). A short list of names is never written at all.

"Nobody has configured it" is decided mainly by the row's own provenance: `Setting.setup!` creates
a row with its default, so a row whose `updated_at` is still its `created_at` has not been written
since it was seeded and therefore still holds the `setup!` default for its name. That consults the
defaults the setup actually used, per row, rather than keeping a second copy of the defaults table
in the bootstrap code — and it stays correct when a later release changes a default.

**The timestamp is evidence, not proof, and it is wrong in both directions.** Two named exceptions
patch the cases that are known to matter; both are small tables in
`app/services/bootstrap/apply_service.rb`, and both are there because a *machine* wrote the row.

*Timestamp moved with no human involved (would refuse a legitimate seed).*
`db/migrate/20250609233415_update_settings.rb` rewrites the `le` and `le_auto` **descriptions** and
re-points `acme_email` off its setup sentinel, all with `update`. On any controller that was
migrated rather than schema-loaded, those three rows have `updated_at != created_at` and would be
unseedable for ever. So:

- `SETTING_SENTINEL_VALUES` — a row holding a known placeholder counts as unconfigured whatever the
  timestamp says. Currently `acme_email` => `noreply@example.acme`,
  `acme-noreply@computestacks.com`.
- `SETTING_SETUP_DEFAULTS` — for the two rows where only the description moved, the `setup!`
  creation default is recorded so a row still holding it counts as unconfigured. Currently `le` and
  `le_auto`, both `true`. This is deliberately a two-entry table of known cases, not a mirror of the
  whole defaults table — a full mirror would go stale the first time a release changed a default,
  which is precisely what the timestamp rule avoids. **A setting outside these two tables whose
  timestamp some future migration moves will silently stop being seedable**; if that happens, add
  it here.

*Value moved with no timestamp change (would allow a seed that overrides a machine).*
`Setting.billing_module` forces `signup_form` to false with `update_column` when the billing module
is WHMCS, and `update_column` does not move `updated_at` — so the row still looks untouched. A
manifest carrying `signup_form: true` would re-open public registration on a controller whose
signups are supposed to come from WHMCS. So:

- `NEVER_SEED_SETTINGS` — names the apply refuses outright, whatever the row looks like. Currently
  `signup_form`. A manifest carrying one is skipped and warned, naming the reason; set it in the
  admin UI instead.

The practical consequences:

- On a greenfield install every value in the manifest lands, because `Setting.setup!` has just
  created every row.
- On a live controller the manifest can still seed a setting nobody ever filled in — an empty
  `google_analytics_id`, or an `smtp_server` still reading `smtp.postmarkapp.com`.
- A setting an operator changed in the admin UI is never rewritten, in either direction, no matter
  what the manifest says.
- Once the bootstrap itself has written a setting, that setting counts as configured; a later
  manifest with a different value reports drift rather than overwriting it.
- A name in `NEVER_SEED_SETTINGS` is never written, not even on a greenfield install.

**A boolean setting may be written either way.** `Setting` stores a boolean in its text column as
`"t"` / `"f"`, and the manifest's value is compared to the stored one as a string — so the apply
normalises YAML `true`/`false` (and the `"true"`/`"false"` spellings) to `"t"`/`"f"` before
comparing, exactly as it normalises `hostname` into the form the model saves. Without that, a
boolean seeded as YAML `false` would be reported as drift on every subsequent run
(`value: database "f", manifest false`) for ever. Applies to every boolean setting: `le`,
`le_auto`, `registry_selinux`, `belco`, `dixa`, `google_analytics`, `monarx_active`.

Encryption is handled by the model: `Setting#set_value` encrypts on save when the row's `encrypted`
flag is true (`acme_kid`, `acme_hmac_key`, `smtp_password`, `belco_shared_secret`, the `monarx_*`
keys, `marketplace_password`). **model-encrypted** — always put plaintext in the manifest. Both the
"is it blank" test and the drift comparison read `Setting#decrypted_value`, never the stored
ciphertext.

Settings the provisioner is expected to set:

| Name | Category | Notes |
| --- | --- | --- |
| `hostname` | `general` | The portal domain. The model strips a leading `http://` / `https://` and trims — write it bare (`portal.example.com`), not as a URL. Nodes fetch `https://<hostname>`, so this must resolve from the node network. |
| `registry_node` | `container_registry` | Registry server IP the controller SSHes to. |
| `registry_base_url` | `container_registry` | Registry hostname, e.g. `cr.example.com`. |
| `registry_ssh_port` | `container_registry` | String. Default `"22"`. |
| `cr_le` | `container_registry` | Domain to use for the registry's ACME certificate. Blank disables it. Note the row may still be sitting under the legacy `computestacks` category on an old install; `Setting.computestacks_cr_le` migrates it, and `Setting.setup!` calls that — another reason to leave `defaults: true`. |
| `app_name`, `company_name`, `general_support` | branding/general | Optional. |
| `acme_directory`, `acme_email` | `acme` | Optional; `acme_kid` / `acme_hmac_key` are encrypted (EAB). |
| `smtp_server`, `smtp_port`, `smtp_username`, `smtp_password`, `smtp_from` | `mail` | Optional. `smtp_password` is encrypted. |

---

## `metric_clients` / `log_clients`

Map to `metric_clients` (Prometheus, `MetricClient`) and `log_clients` (Loki, `LogClient`). Both
tables have the same shape and the same rules.

```yaml
metric_clients:
  - endpoint: http://10.100.1.5:9090
    create: true
    username: prometheus
    password: "…"

log_clients:
  - endpoint: http://10.100.1.5:3100
    create: true
    username: loki
    password: "…"
```

| Key | Required | Maps to | Write semantics |
| --- | --- | --- | --- |
| `endpoint` | **yes** | `.endpoint` | plaintext. **Natural key, matched exactly.** |
| `create` | no (default `false`) | — | Whether the apply may create the row when no exact match exists. |
| `username` | no | `.username` | plaintext. **[Rotated](#credential-rotation).** |
| `password` | no | `.password` | **plaintext, [rotated](#credential-rotation).** These two columns are *not* encrypted — `MetricClient#endpoint_with_auth` and `LogClient#call` read them directly. Do not wrap them in `Secret.encrypt!`. |

**The endpoint match is exact and a miss is fatal** unless `create: true`. A trailing slash, a
changed port, or `http` vs `https` counts as a different client. Without this rule a drifted
endpoint would quietly create a *second* client with the same credentials, leave the regions
pointing at the old one, and zero out the placement metrics the scheduler relies on. If you must
change an endpoint, change it in the admin UI (or by hand) — the manifest cannot rename one.

An existing client's `username` / `password` **are** rewritten when the manifest differs — they are
paired with the htpasswd file the provisioner writes on the Prometheus/Loki host from the same
variables, so a rotation has to land on both halves. See
[Credential rotation](#credential-rotation). Nothing else about the row is touched, and the value
is not printed.

Regions reference these by endpoint; see `metric_client_endpoint` / `log_client_endpoint` below.

> `MetricClient` and `LogClient` are lists, not single objects, so that a second region can bring
> its own Prometheus/Loki. A single-region install writes a one-element list.

---

## `dns`

Maps to `provision_drivers`, `product_modules` and `dns_zones`.

```yaml
dns:
  driver:
    module_name: Pdns
    endpoint: http://10.100.1.9:8081/api/v1/servers/localhost
    auth_type: static
    username: admin
    api_key: "…"
    api_secret: "…"
    settings:
      config:
        zone_type: master
        masters: []
        nameservers:
          - ns1.example.com.
          - ns2.example.com.
        server: localhost
  zones:
    - name: example.com
      provider_ref: example.com.
```

### `dns.driver` → `ProvisionDriver`

**Natural key:** the driver referenced by `ProductModule.find_by(name: "dns").primary`. If that is
absent, `provision_drivers.endpoint`. If neither matches, a driver is created and a `dns`
`ProductModule` is created/pointed at it (`primary` plus the HABTM link, exactly as the app's own
admin UI does). Keying on the product module rather than on the endpoint means **a driver whose
API address was moved in the admin UI is still recognised as the same driver** — critical, because
`ProvisionDriver has_many :regions, dependent: :destroy` and a second driver row would be a
cascade-delete waiting to happen.

**An existing driver is never reconfigured, apart from its API credentials.** A manifest whose
`endpoint`, `username` or `settings` differ from the driver on the controller reports
[drift](#drift-warnings) and changes nothing — move PowerDNS in the admin UI, then update the
inventory to match. `api_key` and `api_secret` are the exception: they are the same values the
provisioner renders into PowerDNS's own configuration, so a rotation is applied here too. See
[Credential rotation](#credential-rotation). `endpoint` is a second, narrower exception: it is
written on an existing driver **only** under `UPDATE_ADDRESSES=1` — see
[Address updates](#address-updates).

The `dns` `ProductModule` itself is plumbing rather than operator data — it is how the rest of the
application finds the driver — so it is created when missing, and its `primary_id` is filled in
when it is empty **or when it points at a `ProvisionDriver` that no longer exists**. A dangling
pointer overrides no human choice: the driver it named is gone, so DNS is already dead, and leaving
it would mean the driver this apply just created stays unwired with no error anywhere. A
`primary_id` pointing at a *different, existing* driver is the operator's choice and is only
reported.

| Key | Required | Maps to | Write semantics |
| --- | --- | --- | --- |
| `module_name` | **yes** | `provision_drivers.module_name` | plaintext. `Pdns` for PowerDNS, `Autodns` for AutoDNS. The value is `eval`'d into a class name by the model, so it must be an existing driver module. |
| `endpoint` | **yes** | `.endpoint` | plaintext. For PowerDNS the full API server path, e.g. `http://host:8081/api/v1/servers/localhost`. **[Updated](#address-updates) on an existing driver under `UPDATE_ADDRESSES=1`**, and only then. |
| `auth_type` | no (default `static`) | `.auth_type` | plaintext |
| `username` | no | `.username` | plaintext |
| `api_key` | no | `.api_key` | **`Secret.encrypt!`** — the manifest carries plaintext. `ProvisionDriver#cloud_auth` calls `Secret.decrypt!` on this column; a raw write decrypts to `nil` and DNS silently stops working with no error anywhere. **[Rotated](#credential-rotation).** |
| `api_secret` | no | `.api_secret` | **`Secret.encrypt!`** — same as above, and also **[rotated](#credential-rotation)**. |
| `settings` | no | `.settings` | plaintext JSON (the column is a `string` with `serialize :settings, coder: JSON`). Written only when the driver is created; on an existing driver a differing hash is reported, never merged. |

`settings.config` is passed to `<module_name>.configure` before any zone call. For PowerDNS:

| `settings.config` key | Notes |
| --- | --- |
| `zone_type` | `master` or `native`. |
| `masters` | List of master FQDNs **with the trailing dot** — required when `zone_type: slave`; empty list otherwise. |
| `nameservers` | List of NS FQDNs **with the trailing dot**. Used as the zone's NS records. |
| `server` | PowerDNS server id in the API path. Effectively always `localhost`. |

For AutoDNS the config keys are `soa_email`, `nameservers`, `master_ns`, and the driver additionally
takes `dns: true` and `auth_type: master` at the top of `settings`.

### `dns.zones` → `Dns::Zone`

**Natural key:** `name` (the model validates uniqueness on it).

| Key | Required | Maps to | Notes |
| --- | --- | --- | --- |
| `name` | **yes** | `dns_zones.name` | Must satisfy `Dns::Zone.valid_domain?` — lowercase labels, a 2–15 character TLD. `.local` is rejected in production. |
| `provider_ref` | no (default `"<name>."`) | `.provider_ref` | The zone's id on the remote provider. PowerDNS uses the FQDN **with a trailing dot**. |

The apply always sets `provision_driver` explicitly and leaves `run_module_create` unset, so the
zone row is created locally and **no zone is created on the remote nameserver**. The provisioner's
PowerDNS role owns the actual zone. If `dns.driver` is omitted, zones are created with no driver.

---

## `locations`

Maps to `locations` (`Location`). **Natural key:** `name`.

```yaml
locations:
  - name: ams005
    active: true
    fill_strategy: least
    fill_by_qty: true
    overcommit_cpu: true
    overcommit_memory: true
    regions: [ … ]
```

| Key | Required | Maps to | Notes |
| --- | --- | --- | --- |
| `name` | **yes** | `.name` | Validated `length: 2..50`. This is the provisioner's `region` inventory var. |
| `active` | no (default `true`) | `.active` | Column default `true`. |
| `fill_strategy` | no (default `least`) | `.fill_strategy` | `least` or `full`. Not validated by the model; anything else silently disables placement (`Location#next_region` falls through its `case`). |
| `fill_by_qty` | no (default `true`) | `.fill_by_qty` | |
| `overcommit_cpu` | no (default `true`) | `.overcommit_cpu` | |
| `overcommit_memory` | no (default `true`) | `.overcommit_memory` | |
| `regions` | no | — | List, below. |

### `locations[].regions`

Maps to `regions` (`Region`). **Natural key:** `name`, scoped to the parent location. The apply
**aborts** if a region with that name already exists under a *different* location — the name would
otherwise be ambiguous and the wrong region's nodes and networks would be extended.

A region that already exists is [skipped](#apply-semantics): none of the fields below is assigned,
and a difference is reported as a warning. Its `nodes`, `networks` and `load_balancer` are still
walked, because a node or network the region does not have yet is a *create* and is exactly how a
zone is grown.

```yaml
regions:
  - name: ams-005
    active: true
    network_driver: bridge
    p_net_size: 27
    volume_backend: local
    pid_limit: 300
    ulimit_nofile_soft: 2500
    ulimit_nofile_hard: 3000
    acme_server: 10.100.1.10:3000
    loki_endpoint: http://10.100.1.10:3100
    metric_client_endpoint: http://10.100.1.5:9090
    log_client_endpoint: http://10.100.1.5:3100
    nodes: [ … ]
    networks: [ … ]
    load_balancer: { … }
```

| Key | Required | Maps to | Write semantics / notes |
| --- | --- | --- | --- |
| `name` | **yes** | `regions.name` | plaintext, `presence` validated. The provisioner's `az` inventory var. |
| `active` | no (default `true`) | `.active` | plaintext. Column default `true`. |
| `network_driver` | no (default `bridge`) | `.network_driver` | plaintext. Validated `in: %w[calico_docker bridge]`. **`bridge` for all new installs**; `calico_docker` exists only for legacy clusters. |
| `p_net_size` | no (default `27`) | `.p_net_size` | plaintext integer. Validated `> 23` and `< 30`, i.e. **24–29 only**. Prefix length of each project's private network carved out of the region's shared subnet. |
| `volume_backend` | no (default `local`) | `.volume_backend` | plaintext. Validated `in: %w[local nfs]`. |
| `nfs_remote_host` | no | `.nfs_remote_host` | plaintext. Only meaningful with `volume_backend: nfs`. |
| `nfs_remote_path` | no (default `/var/nfsshare/volumes`) | `.nfs_remote_path` | plaintext. No trailing slash — the volume name is appended. |
| `nfs_controller_ip` | no | `.nfs_controller_ip` | plaintext. NFS address as reached *from the controller*. |
| `pid_limit` | no (default `0`) | `.pid_limit` | plaintext integer, `>= 0`. `0` = unlimited. The v1 template used `300`. **Column name is `pid_limit`, singular** — the admin API's `pids_limit` parameter name is a bug in that controller and is not the column. |
| `ulimit_nofile_soft` | no (default `0`) | `.ulimit_nofile_soft` | plaintext integer, `>= 0`. v1 used `2500`. |
| `ulimit_nofile_hard` | no (default `0`) | `.ulimit_nofile_hard` | plaintext integer, `>= 0`. v1 used `3000`. Must be `>=` soft or docker rejects every container start; **the model does not check this**, so the provisioner must. |
| `acme_server` | no (default `127.0.0.1:3000`) | `.acme_server` | plaintext, `host:port` with **no scheme**. The in-region ACME helper the nodes talk to. **[Updated](#address-updates) on an existing region under `UPDATE_ADDRESSES=1`**, and only then. An absent key never clears it. |
| `loki_endpoint` | no (default `http://localhost:3100`) | `.loki_endpoint` | plaintext. This is the endpoint **containers** ship logs to (node-facing). It is *not* the controller's `log_clients` endpoint, which is used for reading logs back. On a single-host install the two are usually different addresses for the same Loki. |
| `loki_retries` | no (default `"5"`) | `.loki_retries` | plaintext **string** (the column is a `string`). |
| `loki_batch_size` | no (default `"400"`) | `.loki_batch_size` | plaintext **string**. |
| `metric_client_endpoint` | no | `.metric_client_id` | Reference by **exact endpoint** into `metric_clients`. Unknown endpoint aborts. |
| `log_client_endpoint` | no | `.log_client_id` | Reference by **exact endpoint** into `log_clients`. Unknown endpoint aborts. |
| `fill_to` | no (default `500`) | `.fill_to` | plaintext integer, `>= 1`. |
| `offline_window` | no (default `60`) | `.offline_window` | plaintext integer, seconds. |
| `failure_count` | no (default `2`) | `.failure_count` | plaintext integer. |
| `disable_oom` | no (default `false`) | `.disable_oom` | plaintext boolean. |
| `ipv6_egress` | no (default `false`) | `.features["ipv6_egress"]` | Written through `Region#ipv6_egress=`; there is **no column**. Requires working upstream IPv6 on the node — see the v9.7.4 changelog entry before enabling. |
| `guac_url` | no | `.guac_url` | plaintext. No trailing slash, e.g. `https://guac.example.com/guacamole`. |
| `guac_key` | no | `.guac_key_enc` | **encrypting setter** `Region#guac_key=`. Manifest carries plaintext. A blank value is ignored (the setter refuses to store blanks), it does not clear an existing key. |
| `settings` | no | `.settings` | plaintext JSON hash. Written only when the region is created; on an existing region a differing hash is reported, never merged. Reserved for driver-specific data; leave it out. |
| `nodes` / `networks` / `load_balancer` | no | — | Below. |

> **`consul_token` is gone.** The column still exists but nothing in the application reads it —
> Consul/Diplomat was retired in the v3 agent cutover. The v1 template set it. Do **not** carry it
> in the manifest.

### `regions[].nodes`

Maps to `nodes` (`Node`). **Natural key:** `hostname` (globally, not per region). The apply also
aborts if a *different* node already holds the same `primary_ip` — that is inventory drift and
silently splitting a node in two is much worse than failing.

```yaml
nodes:
  - label: node1001
    hostname: node1001
    primary_ip: 10.100.1.10
    public_ip: 203.0.113.10
    active: true
    ssh_port: 22
    agent_host: node1001.tail1234.ts.net
```

| Key | Required | Maps to | Write semantics / notes |
| --- | --- | --- | --- |
| `hostname` | **yes** | `nodes.hostname` | plaintext, `presence` validated. Natural key. |
| `label` | no (defaults to `hostname`) | `.label` | plaintext, `presence` validated — so it must never end up blank. |
| `primary_ip` | **yes** | `.primary_ip` | plaintext. Validated **IPv4 dotted-quad only**. The address the controller and the fleet reach this node on. |
| `public_ip` | **yes** | `.public_ip` | plaintext. Validated **IPv4 dotted-quad only**. |
| `active` | no (**apply defaults it to `true`**) | `.active` | plaintext boolean. **The column default is `false`.** `Node.available` filters `active: true`, so a node left at the column default accepts no orders and every order fails with "no capacity" and no other symptom. The apply therefore defaults this to `true` rather than to the column default; set `active: false` explicitly if that is what you want. |
| `ssh_port` | no (default `22`) | `.ssh_port` | plaintext integer. |
| `agent_host` | no | `.agent_host` | plaintext. **Optional override** for the address the controller dials cs-agent on; blank (stored as `NULL`) falls back to `primary_ip`. Validated as an RFC-1123 hostname, which also accepts a dotted-quad — so a Tailscale name (`node1.tailnet.ts.net`) or a raw address both work. **IPv6 is rejected**: the value is interpolated into a URL unbracketed. **[Updated](#address-updates) on an existing node under `UPDATE_ADDRESSES=1`**, and only then — and under that flag an **absent or null key clears the column**, which is how a node coming off the tailnet is expressed. Without the flag an absent key is ignored like every other. |
| `port_begin` | no (default `10000`) | `.port_begin` | plaintext integer. Must match the port range the node's firewall opens. |
| `port_end` | no (default `50000`) | `.port_end` | plaintext integer. |
| `volume_device` | no | `.volume_device` | plaintext, e.g. `/dev/sda`. Required for the block I/O limits below to have any effect. |
| `block_read_bps` / `block_write_bps` | no (default `0`) | `.block_*_bps` | plaintext integer, `>= 0`. `0` = unlimited. |
| `block_read_iops` / `block_write_iops` | no (default `0`) | `.block_*_iops` | plaintext integer, `>= 0`. |
| `maintenance` | no (default `false`) | `.maintenance` | plaintext boolean. |

**`agent_token` is not a manifest field.** `Node` mints one in a `before_save` when the column is
blank, and only its SHA-256 (`Node#agent_token_hash`) ever leaves the controller. The provisioner
reads that hash back through the enrolment path; it must never be set from a manifest.

### `regions[].networks`

Maps to `networks` (`Network`). **Natural key:** `name`, scoped to the region.

```yaml
networks:
  - name: ams005
    label: ams-005 shared
    subnet: 10.100.4.0/22
    is_shared: true
    active: true
    network_driver: bridge
```

| Key | Required | Maps to | Write semantics / notes |
| --- | --- | --- | --- |
| `name` | **yes** | `networks.name` | plaintext. `presence` + uniqueness per region. **The model rewrites it**: `before_validation` strips whitespace, downcases, and removes every non-alphanumeric character — `ams-005 net` is stored as `ams005net`. Write the already-normalized form so the diff is readable; the apply normalizes before matching regardless. |
| `label` | **yes** | `.label` | plaintext, `presence` validated. Free text; this is what the admin UI shows. |
| `subnet` | **yes** | `.subnet` | plaintext CIDR, `presence` + uniqueness per region. Validated: **IPv4 only**, at least a `/28` (the check is "16 or more addresses"), and inside RFC-1918 (`10/8`, `172.16/12`, `192.168/16`). Overlap with any existing network is rejected. |
| `is_shared` | no (default `true`) | `.is_shared` | plaintext boolean. The region's shared network is `true`. |
| `active` | no (default `true`) | `.active` | plaintext boolean. |
| `network_driver` | no (default `bridge`) | `.network_driver` | plaintext, `in: %w[calico_docker bridge]`. Should match the region's. |

**The subnet of an existing network is not updated.** `Network` refuses subnet changes while
addresses are in use, and an unused change would still need every node's docker network rebuilt.
A mismatch is reported as [drift](#drift-warnings), compared through `Network#to_net` so the
notation matches the manifest's. Creating a *second* network whose subnet is already taken in that
region is still an error — the model would reject the overlap anyway, and the message names the
network that holds it.

### `regions[].load_balancer`

Maps to `load_balancers` (`LoadBalancer`). **Natural key:** the region — `Region has_one
:load_balancer`, so there is at most one and it is found through the association.

```yaml
load_balancer:
  label: ams-005 lb
  domain: app.example.com
  public_ip: 203.0.113.10
  ext_ip: [10.100.1.10]
  internal_ip: [10.100.1.10]
  direct_connect: false
  le: false
  stats_bind: "*:81"
  stats_password: "…"
  shared_certificate: |
    -----BEGIN CERTIFICATE-----
    …
    -----END CERTIFICATE-----
    -----BEGIN PRIVATE KEY-----
    …
    -----END PRIVATE KEY-----
```

| Key | Required | Maps to | Write semantics / notes |
| --- | --- | --- | --- |
| `domain` | **yes** | `load_balancers.domain` | plaintext, **`presence` validated**. The shared wildcard domain tenant containers are published under (`<container>.app.example.com`). Changing it enqueues `ValidateDomainWorker`. |
| `public_ip` | **yes** | `.public_ip` | plaintext, **`presence` validated**. The floating/public address of the haproxy host. |
| `ext_ip` | **yes** | `.ext_ip` | plaintext JSON array, **`presence` validated — an empty list fails**, because `[].blank?` is true. The addresses haproxy itself binds/answers on: the `primary_ip` of every node in the region's LB cluster. |
| `internal_ip` | no (defaults to `ext_ip`) | `.internal_ip` | plaintext JSON array. |
| `label` | no | `.label` | plaintext. **Not** presence-validated in the model, but leaving it out means the app names the LB after a random generated word, so always set it. |
| `name` | — | `.name` | **Not settable.** `before_create :set_defaults` overwrites `name` with a generated word on every create. Do not put it in the manifest. |
| `shared_certificate` | no | `.cert_encrypted` | **encrypting setter** `LoadBalancer#shared_certificate=`. Manifest carries the **plaintext PEM bundle — certificate, chain and private key concatenated**. The model parses it with `OpenSSL::X509::Certificate` and rejects anything that is not a valid certificate. **[Rotated](#credential-rotation)** — a renewed certificate in the manifest is written to an existing load balancer. The comparison reads the decrypted value, so a stable certificate is not rewritten on every run. |
| `stats_bind` | no (column default `*:81`) | `.stats_bind` | plaintext, haproxy `bind` spec. **This drives the haproxy stats listener, and it is `*:81` by default — not 8404.** The provisioner's Prometheus scrape config and its firewall rule must use the same value; one variable should render all three. |
| `stats_password` | no (column has a hard-coded default) | `.stats_password` | **plaintext column, not encrypted.** `NOT NULL` with a shipped default — leaving it unset means every install shares the same published stats password. Always set it. **[Rotated](#credential-rotation)** — the provisioner writes the same value into the generated haproxy configuration. |
| `direct_connect` | no (column default `true`) | `.direct_connect` | plaintext boolean. `false` restricts the LB to containers on its own node. The v1 template set `false`. |
| `le` | no (default `false`) | `.le` | plaintext boolean. `true` makes the controller order a wildcard ACME certificate for `domain` **on save** (`LoadBalancerServices::LetsEncryptService` runs synchronously in an `after_save`). Leave `false` when you are supplying `shared_certificate`. |
| `proxy_cloudflare` / `proxy_bunny` | no (default `true`) | `.proxy_*` | plaintext boolean. |
| `cpus` | no (default `1`) | `.cpus` | plaintext integer. |
| `maxconn` / `maxconn_c` / `ssl_cache` / `max_queue` | no | as named | plaintext integers. |
| `g_timeout_connect` / `g_timeout_client` / `g_timeout_server` | no | as named | plaintext haproxy duration strings (`5s`, `150s`). |
| `proto_alpn` / `proto_11` / `proto_20` / `proto_23` | no | as named | plaintext booleans. |

Saving a load balancer has two side effects the manifest cannot suppress: a `ValidateDomainWorker`
job is enqueued when `domain` changes, and `LetsEncryptService` runs when `le` changes. Both are
correct behaviour on a real bootstrap (Sidekiq and Redis are up); under `DRY_RUN=1` neither runs,
because nothing is saved. A [credential rotation](#credential-rotation) saves an existing load
balancer, but assigns neither `domain` nor `le`, so both callbacks see no change and do nothing.

---

## `products`

```yaml
products:
  seed: true
```

| Key | Required | Notes |
| --- | --- | --- |
| `seed` | no (default `true`) | Runs the repository's own `load_products` task, which creates the default `BillingPlan` and the sample container/storage/bandwidth/backup products with USD hourly prices. |

`load_products` is **self-guarding: it does nothing at all if any `BillingPlan` already exists.**
That is what makes it safe to leave in an attach manifest, though an attach manifest should simply
omit the section. Prices are created with `regions: Region.all` as of that moment — which is why
this section runs after `locations`, and why the price-extension rule above exists for later
regions.

The currency comes from the controller's `CURRENCY` environment variable, not from the manifest.

All three seed tasks the apply can run (`load_products`, `default_settings`, `load_containers`) are
create-if-absent throughout, so none of them can override an operator's work. `load_products` does
everything inside `if BillingPlan.first.nil?` and the apply will not call it at all once a plan
exists; its one `UserGroup#update` is unreachable on a live controller, since `UserGroup
belongs_to :billing_plan` is required and no group can exist while there is no plan.

---

## `catalog`

```yaml
catalog:
  system_content: true
  container_images: true
```

| Key | Required | Notes |
| --- | --- | --- |
| `system_content` | no (default `false`) | Runs `default_settings`: the collaboration/confirmation `Block` content and the DockerHub / Quay / GCR / GHCR `ContainerImageProvider` rows. Also re-runs `Setting.setup!` and `Feature.setup!` (both idempotent). **Must run after `products`** — it creates the default `UserGroup`, which needs a `BillingPlan`. |
| `container_images` | no (default `false`) | Runs `load_containers`, seeding the container image catalog from the `containers:*` tasks. Slow; a greenfield install wants it, an attach manifest does not. |

---

## `user_group`

Maps to `user_groups` (`UserGroup`) and the `regions_user_groups` join.

```yaml
user_group:
  name: default
  link_regions: all
```

| Key | Required | Maps to | Notes |
| --- | --- | --- | --- |
| `name` | no (default `default`) | `.name` | plaintext. Validated `length: 2..50`. Only used when creating; a differing name on an existing group is reported, not applied. |
| `link_regions` | no (default `all`) | `regions_user_groups` | `all` links the default group to every region; `none` links nothing. Links are **added only, never removed**, so this keeps working on a live controller — it is how a newly attached region becomes orderable. |

**Natural key:** `is_default: true`. If no default group exists one is created with
`is_default: true` and the default `BillingPlan` (`belongs_to :billing_plan` is required, so
`products` must have run). An existing default group's attributes are **not** overwritten —
quotas and billing flags are operator-owned.

Without a region link, users in the default group see no availability zone and cannot order
anything, which is why this defaults to `all`.

---

## `features`

Maps to `features` (`Feature`).

```yaml
features:
  defaults: true
  values:
    updated_cr_cert: true
```

| Key | Required | Notes |
| --- | --- | --- |
| `defaults` | no (default `true`) | Runs `Feature.setup!`, which creates every known flag at its shipped default **and destroys flags no longer known to the code**. This is the application's own routine; it is the one place the apply is allowed to delete rows, and it only runs when this section is present. Which flags *exist* is controller-owned structure, not operator data, so this is unchanged by the bootstrap-not-override rule. |
| `values` | no | Hash of feature name → `true`/`false` (sets `active`). An unknown name aborts. Applied **only while the flag is still at its `Feature.setup!` default** — see below. |

**A flag a human has toggled is never flipped back.** As with [`settings`](#settings), the row's
own provenance answers the question: `Feature.setup!` creates a flag at its shipped default, so a
flag whose `updated_at` is still its `created_at` has not been written since and is still at that
default, and the manifest may set it. Once anybody has toggled it — in the admin UI, or by an
earlier bootstrap — the manifest's value is reported as [drift](#drift-warnings) and the flag is
left as it is.

`features` needs none of the [named exceptions `settings` carries](#settings): nothing in the
application writes a `Feature` outside `Feature.setup!` and the admin UI, so nothing moves a flag's
timestamp — or its value — behind the rule's back. A migration that starts rewriting flag rows
would break this the same way one already broke it for settings.

`updated_cr_cert` now ships with `default => true` in `Feature.setup!`, so a greenfield install
gets it without the manifest saying anything. The v1 template's dance — remember whether the flag
existed, run `Feature.setup!`, then force it active for new installs only — is obsolete. Listing
it explicitly under `values` is still correct and harmless, and is the documented way to be
certain.

---

## `admin_user`

Maps to `users` (`User`).

```yaml
admin_user:
  email: admin@example.com
  password: "…"
  fname: Admin
  lname: Admin
  currency: USD
  bypass_billing: true
```

| Key | Required | Maps to | Notes |
| --- | --- | --- | --- |
| `email` | **yes** | `users.email` | plaintext. `presence` + uniqueness. **Natural key.** |
| `password` | **yes** | `.encrypted_password` | Devise hashes it. The manifest carries plaintext. |
| `fname` | no (default `Admin`) | `.fname` | plaintext, `presence` validated. |
| `lname` | no (default `Admin`) | `.lname` | plaintext, `presence` validated. |
| `currency` | no (defaults to the controller's `CURRENCY`) | `.currency` | plaintext. Validated against the `money` gem's ISO list. |
| `bypass_billing` | no (default `true`) | `.bypass_billing` | plaintext boolean. |
| `is_admin` | — | `.is_admin` | Always `true`. Not settable. |

**Create-if-absent only. An existing user with this email is never modified** — the apply will not
reset a password, re-grant admin, or reactivate a disabled account, because a manifest re-run must
never be a way to take over an account. If the row exists the section reports `[skip]`, plus a
[drift warning](#drift-warnings) for `fname` / `lname` / `currency` / `bypass_billing` if they
differ. **The password is never compared**, so it can never appear in the output.

The user is created with `skip_confirmation!` and is attached to the default `UserGroup`
(`User before_validation :set_user_group` finds it), so `user_group` must have run. Note that
`User#user_address` consults `Setting.billing_address` / `Setting.billing_phone` at validation
time — if either has been turned on, a manifest-created admin needs address fields too. The
defaults are off.

---

## Full example — greenfield

```yaml
schema_version: 1

settings:
  defaults: true
  values:
    hostname: portal.example.com
    app_name: Example Hosting
    company_name: Example Hosting
    general_support: support@example.com
    registry_node: 10.100.1.20
    registry_base_url: cr.example.com
    registry_ssh_port: "22"
    cr_le: cr.example.com

metric_clients:
  - endpoint: http://10.100.1.5:9090
    create: true
    username: prometheus
    password: "s3cr3t-prom"

log_clients:
  - endpoint: http://10.100.1.5:3100
    create: true
    username: loki
    password: "s3cr3t-loki"

dns:
  driver:
    module_name: Pdns
    endpoint: http://10.100.1.9:8081/api/v1/servers/localhost
    auth_type: static
    username: admin
    api_key: "pdns-api-key"
    api_secret: "pdns-api-secret"
    settings:
      config:
        zone_type: master
        masters: []
        nameservers:
          - ns1.example.com.
          - ns2.example.com.
        server: localhost
  zones:
    - name: app.example.com
      provider_ref: app.example.com.

locations:
  - name: ams005
    active: true
    fill_strategy: least
    fill_by_qty: true
    regions:
      - name: ams-005
        active: true
        network_driver: bridge
        p_net_size: 27
        volume_backend: local
        pid_limit: 300
        ulimit_nofile_soft: 2500
        ulimit_nofile_hard: 3000
        acme_server: 10.100.1.10:3000
        loki_endpoint: http://10.100.1.10:3100
        metric_client_endpoint: http://10.100.1.5:9090
        log_client_endpoint: http://10.100.1.5:3100
        nodes:
          - label: node1001
            hostname: node1001
            primary_ip: 10.100.1.10
            public_ip: 203.0.113.10
            active: true
            ssh_port: 22
        networks:
          - name: ams005
            label: ams-005 shared
            subnet: 10.100.4.0/22
            is_shared: true
            active: true
            network_driver: bridge
        load_balancer:
          label: ams-005 lb
          domain: app.example.com
          public_ip: 203.0.113.10
          ext_ip: [10.100.1.10]
          internal_ip: [10.100.1.10]
          direct_connect: false
          le: false
          stats_bind: "*:81"
          stats_password: "s3cr3t-stats"
          shared_certificate: |
            -----BEGIN CERTIFICATE-----
            …
            -----END CERTIFICATE-----
            -----BEGIN PRIVATE KEY-----
            …
            -----END PRIVATE KEY-----

products:
  seed: true

catalog:
  system_content: true
  container_images: true

user_group:
  name: default
  link_regions: all

features:
  defaults: true
  values:
    updated_cr_cert: true

admin_user:
  email: admin@example.com
  password: "s3cr3t-admin"
  fname: Admin
  lname: Admin
  bypass_billing: true
```

## Full example — attach a second region

Only the topology. No `settings`, no `dns`, no `products`, no `catalog`, no `admin_user`. The
`user_group` section is present purely so the new region is linked to the default group; the
billing price extension is **not** gated on any section and runs automatically whenever the apply
created a region.

```yaml
schema_version: 1

metric_clients:
  - endpoint: http://10.100.1.5:9090

log_clients:
  - endpoint: http://10.100.1.5:3100

locations:
  - name: fra002
    regions:
      - name: fra-002
        network_driver: bridge
        p_net_size: 27
        volume_backend: local
        pid_limit: 300
        ulimit_nofile_soft: 2500
        ulimit_nofile_hard: 3000
        acme_server: 10.100.2.10:3000
        loki_endpoint: http://10.100.2.10:3100
        metric_client_endpoint: http://10.100.1.5:9090
        log_client_endpoint: http://10.100.1.5:3100
        nodes:
          - label: node2001
            hostname: node2001
            primary_ip: 10.100.2.10
            public_ip: 203.0.113.20
            active: true
        networks:
          - name: fra002
            label: fra-002 shared
            subnet: 10.100.8.0/22
        load_balancer:
          label: fra-002 lb
          domain: app-fra.example.com
          public_ip: 203.0.113.20
          ext_ip: [10.100.2.10]
          direct_connect: false
          stats_bind: "*:81"
          stats_password: "s3cr3t-stats"

user_group:
  link_regions: all
```

Note the two client sections carry **no `create: true`**. They are references: if the endpoints do
not match a `MetricClient` / `LogClient` already on the controller, exactly and character for
character, the apply aborts rather than creating a duplicate client that would silently split the
placement metrics.

---

## Fields deliberately NOT in the manifest

| Field | Why |
| --- | --- |
| `regions.consul_token` | Dead column. Nothing reads it since the v3 agent cutover retired Consul. |
| `nodes.agent_token` / `agent_token_encrypted` | Minted by the model; only the SHA-256 leaves the controller, through enrolment. |
| `load_balancers.name` | Overwritten by `before_create :set_defaults` on every create. Use `label`. |
| `users.is_admin` | Always true for `admin_user`; the manifest has no other user path. |
| `settings` rows not created by `Setting.setup!` | The apply never creates a setting; a row created without the right `category` is invisible in the admin UI. |
| `settings.values.signup_form` | Machine-managed — `Setting.billing_module` forces it off for external billing with `update_column`, invisibly to the provenance rule. See [`settings`](#settings). |
| Any `destroy` | See the never-destroy rule above. |
| Any change to a row that already exists, other than the two [exemptions](#exemptions-from-bootstrap-only) | See [Apply semantics](#apply-semantics). The manifest bootstraps; it does not override. |
