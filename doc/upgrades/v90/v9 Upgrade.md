# v9.0 Upgrade Notes

## Update Consul

The path for the consul image has changed. Please update the following file `/etc/systemd/system/consul.service` and change the docker image to: `hashicorp/consul:1.16`

Be sure to run:

```bash
docker pull hashicorp/consul:1.16 \
  && systemctl daemon-reload \
  && systemctl restart consul
```

## Update Node Agent

Newer installations now include a script to update the agent. Please install that script and run it:

```bash
cat << 'EOF' > /usr/local/bin/update-agent
#!/bin/bash

set -e

AGENT_TAR=$(mktemp)
curl -sSL --fail -o $AGENT_TAR https://f.cscdn.cc/file/cstackscdn/packages/cs-agent/cs-agent.tar.gz
tar -xzvf $AGENT_TAR --directory .
gpg --verify cs-agent.sig cs-agent || exit_code=$?
if [[ ${exit_code} -ne 0 ]]; then exit ${exit_code}; fi
systemctl stop cs-agent
mv cs-agent /usr/local/bin/
chown root:root /usr/local/bin/cs-agent && chmod +x /usr/local/bin/cs-agent
rm $AGENT_TAR
rm cs-agent.sig
systemctl start cs-agent
EOF
chmod +x /usr/local/bin/update-agent
```

---


## Support for local networking

In v9.0 we introduced support for single-node installations that utilize linux bridges per project. To migrate an existing calico-based environment to this platform, you will need to perform a number of steps.

> For this to work, all containers within a project need to be on the same node. Please manually migrate containers before proceeding.

### Configure the Node

The first step is to define what your new network range will be and what size of network each project will get. In this example, we will define a network of `10.134.0.0/21` for all projects on this node, and tell ComputeStacks to give a `/28` to each project. This will give `14` IPs per project.

Add the following to `/usr/local/bin/cs-recover_iptables`:

```
iptables -N container-inbound
iptables -A FORWARD -j container-inbound
iptables -A INPUT -s 10.134.0.0/21 -j ACCEPT
```

_WHERE `10.134.0.0/21` IS THE SUBNET YOU'RE USING_.

Be sure to also manually run those iptable commands to apply them now.

> You must also ensure that this network does not overlap in your existing environment.


### Configure ComputeStacks

#### Setup the Network
Create a new network, with a subnet of `10.134.0.0/21`. Check the `Shared Network` box, assign it to the correct availability zone, and click save.

#### Setup the Availability Zone
Edit the availability zone and change the network driver to `Bridge`, and set the correct project network size (`28`).

### Perform the Migration
Once that's done, you may navigate to the Availability zone and click `Migrate Network Driver`.

> If you don't see the 'Migrate Network Driver' button on the availability zone, it means that you have not changed the availability zone's network driver, or you have more than 1 node in that AZ.

