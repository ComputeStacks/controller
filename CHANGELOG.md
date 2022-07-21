# Change Log

## v7.2.0-beta1

_July 20, 2022_

* [FEATURE] Clone Project.
* [FEATURE] Clone volumes.
* [FEATURE] Shared mountable volumes.
* [FEATURE] Support for custom `/etc/hosts` entries in both images and containers.
* [CHANGE] Both `tcp` and `udp` will share the same external NAT port.
* [CHANGE] Previously, even if over-commit memory/cpu was enabled, ComputeStacks would still prevent placing containers on a node that did not have enough cpu or memory available. This would cause orders to fail; this will now follow the over-commit setting as well.
* [FIX] Resolved issue that would randomly cause an ip address to be assigned to multiple containers at once, and cause a provision failure.
* [FIX] Annual snapshot retention was not visible in the UI.
* [FIX] Region allocation was overcounting SFTP containers.

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
