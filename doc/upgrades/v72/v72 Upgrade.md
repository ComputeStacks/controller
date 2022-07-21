# v7.2 Upgrade Notes

## Update cs-agent

```bash
cd /tmp && wget https://cdn.computestacks.net/packages/cs-agent/cs-agent.tar.gz
tar -xzvf cs-agent.tar.gz
rm -f /usr/local/bin/cs-agent
mv cs-agent /usr/local/bin/
chown root:root /usr/local/bin/cs-agent && chmod +x /usr/local/bin/cs-agent
rm -rf /tmp/cs-agent*
```
