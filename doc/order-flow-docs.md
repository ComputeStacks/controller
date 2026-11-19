# Order Flow

Documenting flow of models, workers, and services used when an order event is triggered.

## New Order
* Deployments::OrderController
  - BuildOrderService
    + ProcessOrderWorker
      * ProcessOrderService
        - NetworkServices::GenerateProjectNetworkService
          - NetworkServices::CreateBridgeNetworkService
        - OrderServices::ContainerServiceOrderService
          + ProvisionServices::ContainerServiceProvisioner
        - ProvisionServices::SftpProvisioner
        - DeployServices::DeployProjectService
          + NetworkWorkers::ProjectPolicyWorker
          + PowerCycleContainerService
          + LoadBalancerServices::DeployConfigService
          + ProjectServices::StoreMetadata
          + VolumeServices::EnqueueCloneService  (see Volume Clone)

### Provisioning order and failures

* **Dependencies first.** `OrderServices::ProductDependencySorter` puts a product whose image is a
  dependency of another product's image ahead of it, matched by image id or role the same way
  `ContainerServices::ServiceConfig#init_link!` links services (so MariaDB is built before the
  WordPress that needs it). Unrelated products, and products in a dependency cycle, keep their
  original order.
* **Each pass walks the pending products in that order.** A product whose volumes are not ready
  yet (`ready_to_provision?`) is skipped and retried on the next pass, two seconds later; that is
  not a failure. The whole loop gives up after three minutes.
* **Fail fast.** The first product that fails stops the order: nothing after it is started, in
  this pass or any later one, and the order fails.
* **A failed order is reported, never rolled back.** Products built before the failure stay.
  `ProcessOrderService#fail_process!` always writes the "ProcessOrderService error output" event
  detail, and stores the reason on the order itself as `order_data["failure_reason"]`: the
  specific errors (or the fail message when there are none), plus the exception on a crash,
  truncated to 1,000 characters. The order is the durable record -- it outlives the project's
  events.
* **Projects left behind by failed orders are swept.** `ProjectWorkers::FailedOrderSweepWorker`
  (`lib/clock.rb`, hourly) deletes a project its failed order created once every order for it has
  failed, and it has been empty and quiet for 24 hours: no services, containers, SFTP containers,
  volumes, collaborators, SSH keys or notifiers, an owner, and no event in that time. Each project
  is checked again right before it is deleted, at most 10 a run, through the admin Delete path
  acting as the owner. Its orders get `order_data["deleted_project"]` (and a backfilled
  `failure_reason` for orders that failed before it was recorded), and each deleting run writes
  its own SystemEvent. It never deletes anything else; it reports, in SystemEvents updated in
  place, projects left by failed orders that are not empty, orders stuck processing or pending
  for over an hour, and failed orders of the last 7 days whose provisioning event's services
  still exist.

## Volume Clone

Ordering a volume with `action: "clone"` copies another volume's data into the new one. The
copy does **not** block the order: `EnqueueCloneService` writes one `volume_clone_jobs` row per
target volume and returns, so the order completes as soon as the containers are built and the
project is usable while its data is still landing. Everything after that is driven by the row.

* VolumeServices::EnqueueCloneService — one VolumeCloneJob per target volume, one Audit each
  - VolumeWorkers::CloneSweepWorker — `lib/clock.rb`, every 15s. The **only** enqueuer.
    + VolumeWorkers::CloneStepWorker — one tick of one job
      * VolumeServices::CloneStepService
        - Volume#create_backup! → cs-agent `volume.backup` task
        - Agent::ChangelogProjector / Agent::TaskReconciler — task status + archive list
        - Volume#restore_backup! → cs-agent `volume.restore` task
    + VolumeWorkers::TrashCloneSnapshotWorker — reaps the temporary archive we created

The state machine walks `pending → awaiting_container → resolving_source →
dispatching_backup → awaiting_backup → discovering_archive → dispatching_restore →
awaiting_restore → completed`, and can enter `failed`/`cancelled` from anywhere.

Three fast paths skip the backup entirely and re-enter at `dispatching_restore` with
`owns_snapshot = false` (so cleanup never trashes an archive we did not create): a
caller-supplied `snapshot`, an existing archive on the source newer than 10 minutes, and
**adoption** — a sibling job cloning the same source already produced an archive, so one
backup serves N clones.

Notes for anyone changing this:

* **The row is the only durable state.** The workers hold nothing and never re-enqueue
  themselves; liveness is a pure DB property, so a `SIGKILL` (production `supervisord` uses
  `stopsignal=KILL`) or a Redis flush costs at most one sweep interval. Mutual exclusion is a
  Postgres row lock, not a Sidekiq lock.
* **The EventLogs are presentational.** Two reapers mutate EventLogs on a schedule owned by
  another concern; if one terminates a clone's event, the machine keeps going.
* **A clone failure must never fail the order.** `ProcessOrderService#fail_process!` detaches
  the project's private network, which would destroy a live project over a failed data copy.
* Each clone gets its **own** Audit, never the order's — `PowerCycleContainerService` keys on
  the order audit having exactly one EventLog.

## Resize Service
* ContainerServiceWorkers::ResizeServiceWorker
  - ProvisionServices::ContainerResizeProvisioner
  - ProjectServices::StoreMetadata

## Scale Service
* ContainerServiceWorkers::ScaleServiceWorker
  - ProvisionServices::ScaleServiceProvisioner
    + ProvisionServices::ContainerProvisioner
    + ContainerWorkers::ProvisionWorker
    + ContainerServices::TrashContainer
    + ProjectServices::StoreMetadata

## Delete ContainerService
* ContainerServiceWorkers::TrashServiceWorker
  - ContainerServices::TrashService
  - ProjectWorkers::SftpInitWorker
  - ProjectServices::StoreMetadata
