# Node maintenance

A node in maintenance takes no new containers. The controller stops recovering, restarting
or health-checking its containers, and the node's agent (cs-agent 3.4+) pauses backups and
other background work. Containers are **not** moved, except in an AZ with clustered storage,
where entering maintenance from the admin UI also evacuates the node.

## Two holds

A node is in maintenance (`nodes.maintenance`) when **either** hold is present:

| Hold | Placed by | Stored as | Released by |
| --- | --- | --- | --- |
| **controller** | the admin UI, the admin API, or `NodeServices::MaintenanceRequestService` | `nodes.maintenance_requested`, with `maintenance_reason` | the same paths |
| **node** (local) | `cs-agent maintenance on` on the node itself | `nodes.maintenance_holds["local"]`, as the agent last reported it | `cs-agent maintenance off` on the node, or the override |

`nodes.maintenance` is a stored generated column: `maintenance_requested` OR a local hold.
It cannot be written. Rails drops writes to it without an error, so set the controller hold
through the service, and `reload` a node before reading the derived value.

**Releasing the controller hold does not take a node-held node out of maintenance.** The
provisioner's playbook uses the node hold (`cs-agent maintenance on --wait`) around a Docker
or kernel upgrade, and releases it when it finishes.

The controller pushes its hold to the agent, and the agent reports both holds back through
its changelog. A drift pass every 2 minutes re-reads every node's status and corrects a
controller hold the agent missed. Agents older than 3.4 return 404; the controller then
treats maintenance as the controller hold alone, and the hold is not enforced on the node.

## Override: release all holds

When a node is stuck in maintenance under a local hold that nobody is around to release,
the **override** releases both holds at once. It is audited and raises a warning-level
system event.

- Admin UI: node edit page, **Override: Release All Holds**. The button only appears while
  a local hold exists.
- Admin API: `POST /api/admin/locations/{location_id}/regions/{region_id}/nodes/{id}/maintenance/release_all`
  with `confirm=true`. It returns `422` without the confirmation.

Until the agent applies it, the node's status carries the `override_pending` warning.

The override only ever releases a local hold placed no later than the override itself.
A hold placed afterwards, for example by a playbook that started a Docker upgrade while
the override was still waiting to reach the agent, is left alone. The agent enforces this
when it applies the release, so the override retires with an informational system event
instead.

## From a Rails runner

`NodeServices::MaintenanceRequestService` is the only writer of the controller hold. Use it
for scripted or bulk changes:

```ruby
node = Node.find_by(hostname: "node1001")

# place the controller hold
NodeServices::MaintenanceRequestService.new(node, on: true, reason: "kernel 6.12").perform

# release the controller hold
NodeServices::MaintenanceRequestService.new(node, on: false).perform

# release BOTH holds (the override)
NodeServices::MaintenanceRequestService.new(node, on: false, override_all: true).perform
```

Pass `actor:` (a `User`) and `remote_ip:` when you have them; they go into the audit
record. A call that changes nothing is safe to repeat: it doesn't bump the generation, and it
still re-sends the hold to the agent.

## Seeing it

- **Admin UI:**
  - The node card and the node's events page show who holds the node, the reason, since
    when, whether background work has quiesced, any skipped backups, and warnings.
  - The node edit page also has **Enter Maintenance**, **Release Controller Hold**, the
    override, and **Refresh from Agent** (a live read of the agent's status).
  - The AZ page shows a summary line and the count of agent writes waiting to be re-pushed.
- **Admin API:**
  - Each node carries a `maintenance_status` object: `effective`, `requested`, `reason`,
    `requested_at`, `gen`, `holds.controller`, `holds.local`, `paused_since`,
    `skipped_backups`, `sample` (quiesce state), `agent` (`supported`, `observed_at`,
    `instance_id`), `running`, `pending` and `warnings`.
  - Regions and locations carry a `maintenance_summary` rollup and `pending_agent_syncs`.
  - All of it is read from stored state; none of it calls the agent.
  - `POST` and `DELETE .../nodes/{id}/maintenance` place and release the controller hold.
    They return `202` with the same `maintenance_status` object.

Warnings:

| Warning | Meaning |
| --- | --- |
| `mismatch` | The agent's copy of the controller hold still disagrees with the controller after a correction attempt. |
| `stale_hold` | A hold has been in place for more than 12 hours. |
| `unsupported_agent` | The controller hold is requested, but the agent is older than 3.4 (or has no token), so the node doesn't enforce it. |
| `status_stale` | No status has been read from the agent in the last 10 minutes. |
| `override_pending` | An override hasn't reached the agent yet. |

Holds older than 12 hours also raise a system event, as do persistent mismatches.

## What customers see

Customers see a node's state, never its holds or the internal reason. The portal shows a
banner on project and service pages, and a label in the project list and on the container
page. The customer API carries the same `node_status` object on containers, container
services, bastions, projects, and each availability zone in `GET /api/locations` (one call
covers a whole fleet):

```json
"node_status": {
  "state": "maintenance",
  "since": "2026-10-08T12:00:00Z",
  "planned": true,
  "message": "Kernel upgrade; back within the hour.",
  "operations": {
    "power": "deferred", "backup": "refused", "restore": "refused", "export": "refused",
    "scale": "refused", "bastion_password_reset": "refused", "config_changes": "available"
  }
}
```

- `state` is `maintenance` while either hold is present (even when the node is also
  unreachable, as it is during a reboot), else `offline` when the node is disconnected, else
  `online`. There is no unknown state.
- Over several nodes (a project, a service, an availability zone) the worst state wins.
  An availability zone counts its enabled nodes plus any disabled node that still hosts
  containers or bastions (disabling only closes a node to new placements). A service or
  project that has no containers yet takes its availability zone's state.
- `message` is the **customer notice**, a node field separate from the internal reason. Set
  it with the maintenance request (admin UI "Message to customers", admin API
  `customer_message`) or on its own from the node edit page / admin API `customer_notice`
  for an unplanned outage. It can only be set while the node is in maintenance or offline,
  it clears itself when the node is back online, and every change is audited. Treat it as
  public: every API user can read it through `/api/locations`.

`operations`:

| Operation | online | maintenance | offline |
| --- | --- | --- | --- |
| `power` (start, stop, restart, rebuild) | available | deferred | refused |
| `backup`, `restore`, `export` (and backup delete) | available | refused | refused |
| `scale` (adding containers; removing them is always allowed) | available | refused | refused |
| `bastion_password_reset` | available | refused | refused |
| `config_changes` | available | available | deferred (re-sent once the node is back) |

### API responses

- A **deferred** power action returns `202` with `deferred: true`, `event_id`,
  `code: "node_maintenance"` and `node_status` (the service-level endpoint returns
  `event_ids` and a per-container `containers` list instead). The action runs when
  maintenance ends. **The latest request wins**: a later request for the same container
  cancels the waiting one ("Superseded"), and if that one carried a callback, the callback
  fires as a failure. The callback of the action that does run fires when it finishes.
  Only the service-level power endpoint takes a callback.
- A **refused** action returns `409` with `errors`, a stable `code` (`node_maintenance` or
  `node_offline`) and `node_status`. For backups, restores, backup deletion, downloads and
  power actions the event is still recorded and failed, so a supplied callback also fires
  as a failure. An SSH password reset or a scale request is refused before any event
  exists, so no callback fires.

### Callback payload

Every callback posts `timestamp`, `event_id`, `status` (`completed`, `failed` or
`cancelled`), `code`, `success` and `data` (the event's detail lines). `code` is a stable
reason for a cancel or failure that isn't the work itself going wrong, so receivers need not
match `data`: `superseded` (replaced by a later power request), `node_maintenance` or
`node_offline` (refused because of the node). It is `null` otherwise, including for an
ordinary failure and for a deferred action that later ran.
