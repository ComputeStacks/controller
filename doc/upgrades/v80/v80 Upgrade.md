# v8.0 Upgrade Notes

## Update Controller

ComputeStacks CE will no longer publish minor point releases, instead they will be a rolling release pinned to the major version. For example, previously we would release images for v7.0 and v7.1. Going forward, there will only be a v7.

Our enterprise release will have minor version releases, plus LTS options if you wish to stay on an older release.

**Compute Stacks CE**: Please update your configuration file with:

```bash
# /etc/default/computestacks
CS_REG=ghcr.io/computestacks/controller:8
```

We also have a full rolling-release tag: `ghcr.io/computestacks/controller:latest`

**Enterprise Repository**: If you choose not to have our team handle your upgrade, or your plan does not include managed upgrades, please contact support for your enterprise repository URL.

Additionally, we have changed out base image, which requires a change to our `cstacks` helper file:

```bash
sed -i 's/portal ash/portal bash/g' /usr/local/bin/cstacks
sed -i 's/$CS_REG ash/$CS_REG bash/g' /usr/local/bin/cstacks
```

## Update cs-agent

Ensure you have the latest version of our backup agents:

```bash
docker pull cmptstks/ssh:v2
docker pull cmptstks/borg:stable
docker pull cmptstks/mariadb-backup:10.1
docker pull cmptstks/mariadb-backup:10.2
docker pull cmptstks/mariadb-backup:10.3
docker pull cmptstks/mariadb-backup:10.4
docker pull cmptstks/mariadb-backup:10.5
docker pull cmptstks/mariadb-backup:10.6
docker pull cmptstks/mariadb-backup:10.7
docker pull cmptstks/mariadb-backup:10.8
docker pull cmptstks/mariadb-backup:10.9
docker pull cmptstks/xtrabackup:2.4
docker pull cmptstks/xtrabackup:8.0
```

### Add the following to the agent config

```
# /etc/computestacks/agent.yml
nfs_opts: ",async,noatime,rsize=32768,wsize=32768"
```

### Update Service Config

```
# /etc/systemd/system/cs-agent.service
[Service]
LimitNOFILE=infinity
```

### Download and update the agent binary

```bash
systemctl stop cs-agent
cd /tmp && wget https://f.cscdn.cc/file/cstackscdn/packages/cs-agent/cs-agent.tar.gz
tar -xzvf cs-agent.tar.gz
rm -f /usr/local/bin/cs-agent
mv cs-agent /usr/local/bin/
chown root:root /usr/local/bin/cs-agent && chmod +x /usr/local/bin/cs-agent
rm -rf /tmp/cs-agent*
systemctl daemon-reload && systemctl start cs-agent
```

## Update Consul


```
# /etc/systemd/system/consul.service
[Service]
LimitNOFILE=infinity
```

```bash
systemctl daemon-reload && systemctl restart consul
```


## Consider adjusting kernel parameters

Example:

```
sysctl fs.file-max=16777216
sysctl fs.inotify.max_queued_events=8388608
sysctl fs.inotify.max_user_instances=8388608
sysctl fs.inotify.max_user_watches=16777216
sysctl kernel.pid_max=4194304
sysctl fs.aio-max-nr=2097152
```

Be sure to persist the changes in: `/etc/sysctld.d/99-sysctl.conf`
