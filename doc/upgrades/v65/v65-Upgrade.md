# Upgrade to v6.5

```bash
docker pull cmptstks/ssh:v2
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

### Generate token for cs-agent
_NOTE: COMPLETELY OPTIONAL_  It may be easier to just use the root token.

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


## Final

* Re-apply all project calico policies
* Rebuild all sftp containers
* Update `consul/config.json` and set default policy to deny
