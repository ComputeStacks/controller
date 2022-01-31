# PowerDNS

Using Postgres Streaming Replication. [ [source](https://www.cybertec-postgresql.com/en/setting-up-postgresql-streaming-replication/) ]

## Firewall

Use `ufw`.

```bash
ufw allow from {{ CONTROLLER-IP }}
ufw allow from {{ SLAVE-IP }}
ufw allow 53/udp
ufw allow 53/tcp
```

## Ensure The Following

```bash
echo "Configure TimeZone"
echo "UTC" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata
service cron restart
echo "Configure vim"
echo "syntax on" >> /etc/vim/vimrc
```

Remove NTP if installed and replace with `chrony`: `apt -y install chrony`


## Master

### PostgreSQL Setup

```
CREATE USER repuser REPLICATION;
```

Edit `/etc/postgresql/13/main/pg_hba.conf` and add: `host replication repuser {{SLAVE-IP}}/32 trust` where the ip is the slave.

restart postgres.

### PowerDNS Configuration

`/etc/powerdns/pdns.conf`
```
api=yes
api-key={{CHANGEME}} # pwgen -s 32 1
webserver=yes
webserver-address=10.0.0.14 # ip used by controller to connect
webserver-port=8081
webserver-allow-from=10.0.0.10/32 # controller
webserver-password={{CHANGEME}} # pwgen -s 32 1
local-port=53
local-address=0.0.0.0, ::
include-dir=/etc/powerdns/pdns.d
launch=gpgsql
config-dir=/etc/powerdns
default-soa-edit=inception-increment
default-ttl=14400
default-soa-content=ns-1.dockr.net hostmaster.@ 0 10800 3600 604800 3600
query-cache-ttl=20
```

`/etc/powerdns/pdns.d/pdns.local.gpgsql.conf`
```
gpgsql-host=localhost
gpgsql-port=
gpgsql-dbname=pdns
gpgsql-user=pdns
gpgsql-password={{PG_PASS}}
gpgsql-dnssec=yes
```

## Slave

### PostgreSQL Setup

1. Stop postgres
2. wipe out existing data directory: `rm -rf /var/lib/postgresql/13/main/*`
3. Seed slave database: `pg_basebackup -h {{MASTER-IP}} -U repuser --checkpoint=fast -D /var/lib/postgresql/13/main/ -R --slot=ns2 -C`
4. Verify with: `cat /var/lib/postgresql/13/main/postgresql.auto.conf`
5. Start postgresql

Verify by running the following _on the master_:

```
\x
SELECT * FROM pg_stat_replication;
```

### PowerDNS Setup

`/etc/powerdns/pdns.conf`
```
local-port=53
local-address=0.0.0.0, ::
include-dir=/etc/powerdns/pdns.d
launch=gpgsql
config-dir=/etc/powerdns
negquery-cache-ttl=20
```

Update `/etc/powerdns/pdns.d/pdns.local.gpgsql.conf` and ensure password is the same as the master!

## ComputeStacks

When configuring the provision driver for CS, the settings hash should look something like:

```ruby
s = {
  "config" => {
    "zone_type" => "Native",
    "masters" => [],
    "nameservers" => ["ns1.example.net.", "ns2.example.net."],
    "server" => "localhost"
  }
}
```
