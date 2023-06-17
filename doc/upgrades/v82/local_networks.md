# Support for local networking

In v8.2 we introduced support for single-node installations that utilize linux bridges per project. To migrate an existing calico-based environment to this platform, you will need to perform a number of steps.

> For this to work, all containers within a project need to be on the same node. Please manually migrate containers before proceeding.


---


## Configure the Node

The first step is to define what your new network range will be and what size of network each project will get. In this example, we will define a network of `10.134.0.0/21` for all projects on this node, and tell ComputeStacks to give a `/28` to each project. This will give `14` IPs per project.

On the node, allow access via iptables from that subnet: `iptables -A INPUT -s 10.134.0.0/21 -j ACCEPT`. _Be sure to also add that to `/usr/local/bin/cs-recover_iptables`._

> You must also ensure that this network does not overlap in your existing environment.


## Configure ComputeStacks

### Setup the Network
Create a new network, with a subnet of `10.134.0.0/21`. Check the `Shared Network` box, assign it to the correct availability zone, and click save.

### Setup the Availability Zone
Edit the availability zone and change the network driver to `Bridge`, and set the correct project network size (`28`).

## Perform the Migration
Once that's done, you may navigate to the Availability zone and click `Migrate Network Driver`.

> If you don't see the 'Migrate Network Driver' button on the availability zone, it means that you have not changed the availability zone's network driver, or you have more than 1 node in that AZ.

