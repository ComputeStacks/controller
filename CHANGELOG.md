# Change Log

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
