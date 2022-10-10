# v8.0 Upgrade Notes

## Update Controller

New image should pull from: `cscr.cc/cs-public/platform/controller:v8.0`

```
sed -i 's/cmptstks\/controller/cscr.cc\/cs-public\/platform\/controller/g' /etc/default/computestacks
```

Change `cstacks` to use updated container:

```
sed -i 's/portal ash/portal bash/g' /usr/local/bin/cstacks
sed -i 's/$CS_REG ash/$CS_REG bash/g' /usr/local/bin/cstacks
```

## Update cs-agent

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

`systemctl daemon-reload`

### Download and update the agent binary

```bash
cd /tmp && wget https://f.cscdn.cc/file/cstackscdn/packages/cs-agent/cs-agent.tar.gz
tar -xzvf cs-agent.tar.gz
rm -f /usr/local/bin/cs-agent
mv cs-agent /usr/local/bin/
chown root:root /usr/local/bin/cs-agent && chmod +x /usr/local/bin/cs-agent
rm -rf /tmp/cs-agent*
```

## Update Consul


```
# /etc/systemd/system/consul.service
[Service]
LimitNOFILE=infinity
```

`systemctl daemon-reload && systemctl restart consul`
