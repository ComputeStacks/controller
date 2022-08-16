# v7.0 Upgrade from v6.4

## Nodes

### Configure Consul

Bootstrap ACL System

```ruby
# Add to consul/config.json
{
  "addresses": {
    "http": "0.0.0.0",
    "https": "0.0.0.0"
  },
  "ports": {
    "http": "8500"
  },
  "acl": {
    "enabled": true,
    "default_policy": "allow", # just for bootstrapping
    "enable_token_persistence": true
  }
}
```

After restarting docker, grab the root token with: `docker exec -it consul consul acl bootstrap`

Example from dev:

```
AccessorID:       18137038-f3b2-fc3c-111b-cdd7d5826477
SecretID:         79b0863a-1068-3c8c-085f-96ef4a97bc08
Description:      Bootstrap Token (Global Management)
Local:            false
Create Time:      2021-11-25 22:16:54.813159252 +0000 UTC
Policies:
   00000000-0000-0000-0000-000000000001 - global-management
```

Add the following to the consul container:

```bash
-e CONSUL_HTTP_TOKEN=79b0863a-1068-3c8c-085f-96ef4a97bc08 \
```

### Update Agent

```bash
docker pull cmptstks/ssh:v2
systemctl stop cs-agent
cd /tmp && wget https://cdn.computestacks.net/packages/cs-agent/cs-agent.tar.gz
tar -xzvf cs-agent.tar.gz
rm -f /usr/local/bin/cs-agent
mv cs-agent /usr/local/bin/
chown root:root /usr/local/bin/cs-agent && chmod +x /usr/local/bin/cs-agent
rm -rf /tmp/cs-agent*
```

Edit `/etc/computestacks/agent.yml` (_may need to `chmod +w`_) and add:

```yaml
consul:
  token: "" # <-- the token created above
```

Start with: `systemctl start cs-agent`

### Finalize Consul

Update `consul/config.json` and set default policy to deny, and restart consul: `systemctl restart consul`

### Node IPTables

v7.0 has moved the metadata service from the controller, to consul running on each node. In order to make that work, you will need to update the iptables rule to allow containers on the container network access to the private IP of the node.

```bash
iptables -A INPUT -p all -s 10.100.0.0/21 -j ACCEPT
echo "iptables -A INPUT -p all -s 10.100.0.0/21 -j ACCEPT" >> /usr/local/bin/cs-recover_iptables
```

Where `10.100.0.0/21` is the container network. You can find this by looking in the controller admin, or running the following command on a node:

```bash
calicoctl get ipPool
```

## Controller

Add `SENTRY_DSN` to `/etc/default/computestacks` and `-e SENTRY_DSN=$SENTRY_DSN \` to `/usr/local/bin/cstacks`

Run the upgrade process (this will automatically create a database backup): `cstacks upgrade && cstacks run`

For the final steps, enter the console on the controller with: `cstacks console`

```ruby
Region.pluck(:id, :name)  # find the ID of the region
Region.find(id-from-previous-query).update consul_token: ''
```

### Update Policies & MetaData

```ruby
Deployment.all.each do |project|
  ProjectServices::StoreMetadata.new(project).perform
  ProjectServices::GenMetadataToken.new(project).perform
  ProjectServices::MetadataSshKeys.new(project).perform
  NetworkWorkers::ProjectPolicyWorker.perform_async project.to_global_id.to_s
  project.services.each do |service|
    NetworkWorkers::ServicePolicyWorker.perform_async service.id
  end
end; 0
Deployment::Sftp.all.each do |sftp|
  sftp.ssh_host_keys.create!(algo: 'rsa') unless sftp.ssh_host_keys.rsa.exists?
  sftp.ssh_host_keys.create!(algo: 'ed25519') unless sftp.ssh_host_keys.ed25519.exists?
  SftpServices::MetadataSshHostKeys.new(sftp).perform
  NetworkWorkers::SftpPolicyWorker.perform_async sftp.id
end; 0
```

### Rebuild SFTP Containers

```ruby
Deployment::Sftp.all.each do |sftp|
  audit = Audit.create_from_object! sftp, 'updated', '127.0.0.1'
  PowerCycleContainerService.new(sftp, 'rebuild', audit).perform
end; 0
```

### Rebuild phpMyAdmin Containers

```ruby
ContainerImage.find_by(role: 'pma').deployed_services.each do |service|
  service.containers.each do |i|
    audit = Audit.create_from_object! i, 'updated', '127.0.0.1'
    PowerCycleContainerService.new(i, 'rebuild', audit).perform
  end
end
```
