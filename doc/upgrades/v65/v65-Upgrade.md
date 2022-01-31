# Upgrade to v6.5

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

## Configure Consul

Bootstrap ACL System

```ruby
# Add to consul/config.json
{
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
CONSUL_HTTP_TOKEN=79b0863a-1068-3c8c-085f-96ef4a97bc08
```

### (Optionally) Generate token for cs-agent

```bash
cat << 'EOF' > 'agent-policy.hcl'
node "node101" {
  policy = "write"
}
EOF
consul acl policy create -name node101-agent -rules @agent-policy.hcl
consul acl token create -description "cs-agent token for node101" -policy-name node101-agent
```

You'll get a response like:

```
AccessorID:       d3a139d8-f479-4534-aff4-ad2d123924ec
SecretID:         c12cdf1b-ddfa-94df-fe23-7bb2e440d25f
Description:      cs-agent token for node101
Local:            false
Create Time:      2021-11-25 22:34:07.315410179 +0000 UTC
Policies:
   20766aa4-6e33-03fc-c5c4-04e15a8af12c - node101-agent
```


## Update Agent

Edit `/etc/computestacks/agent.yml` (_may need to `chmod +w`_) and add:

```yaml
consul:
  token: "" # <-- the token created above
```

Start with: `systemctl start cs-agent`

## Finalize Consul

Update `consul/config.json` and set default policy to deny, and restart consul: `systemctl restart consul`

## Update Policies & MetaData

```ruby
Deployment.all.each do |project|
  NetworkWorkers::ProjectPolicyWorker.perform_async project.to_global_id.uri
end; 0
Deployment::Sftp.all.each do |sftp|
  SftpServices::MetadataSshHostKeys.new(sftp).perform
end; 0
```

## Rebuild SFTP Containers

```ruby
Deployment::Sftp.all.each do |sftp|
  audit = Audit.create_from_object! sftp, 'updated', '127.0.0.1'
  PowerCycleContainerService.new(sftp, 'rebuild', audit).perform
end; 0
```

