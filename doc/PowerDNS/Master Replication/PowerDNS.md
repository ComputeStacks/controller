# PowerDNS

### Requirements

  - Ubuntu 16.04 Fresh Installation
  - Static IP Address with Hostnames already configured

### Installation Notes & Defaults

For this installation guide, we will be using the follow defaults -- please change to suite your environment:

  - Master IP Address: 10.10.0.10
  - Slave IP Address: 10.20.0.10
  - Master Hostname: ns1.computestacks.net
  - Slave Hostname: ns2.computestacks.net


  - Replication uses standard Master Slave DNS replication, and not PG replication.
  - API KEY will be set to: CHANGEME
  - Webserver Password will be set to: CHANGEMENOW
  - The CloudPortal IP Address, which will access this DNS Server, is: 10.10.0.25
  - Postgres password for the pdns user will be: POSTGRES_PDNS_PASSWORD

### Requirements for ComputeStacks

When your PowerDNS setup is completed, you will need to send the following details to us:

  - The IP Address and hostnames of all nodes
  - The IP and hostname of your master Server
  - The API Key, and Webserver password

### Prepare the system and install PowerDNS

_Make sure NTP is running, and the system timezone is correct._

Configure PowerDNS Repo

Create the file `/etc/apt/sources.list.d/pdns.list` with the contents:

```
deb [arch=amd64] http://repo.powerdns.com/ubuntu xenial-auth-40 main
```

Create the file `/etc/apt/preferences.d/pdns` with the content:

```
Package: pdns-*
Pin: origin repo.powerdns.com
Pin-Priority: 600
```

Install PowerDNS' repository key with: `curl https://repo.powerdns.com/FD380FBB-pub.asc | sudo apt-key add`

Install latest updates: `apt update && apt upgrade`

Install Basic Packages: `apt install build-essential postgresql-9.5 pdns-server pdns-backend-pgsql`


### Configure PostgreSQL

**Create User & Database:**

```
su postgres
psql
create user pdns with password 'POSTGRES_PDNS_PASSWORD';
create database pdns owner pdns;
alter user pdns with superuser;
\c pdns
```

While still connected to psql, copy and paste the contents of the 'Default Schema' section listed here: https://doc.powerdns.com/md/authoritative/backend-generic-postgresql/#default-schema

Once finished, type `\q` to exit the psql terminal. Type `exit` to exit the `postgres` user and return to `root`.


Create file `/etc/powerdns/pdns.d/pdns.local.gpgsql.conf` with the content:

```
gpgsql-host=localhost
gpgsql-port=
gpgsql-dbname=pdns
gpgsql-user=pdns
gpgsql-password=POSTGRES_PDNS_PASSWORD
gpgsql-dnssec=yes
```

### Configure PowerDNS

These steps should be repeated on all PowerDNS Servers in the cluster.

Remove the following files:

```
rm /etc/powerdns/bindbackend.conf
rm /etc/powerdns/pdns.d/pdns.simplebind.conf
```

### Configure The Master DNS Server

Edit `/etc/powerdns/pdns.conf` to look like:

_For production, remove 0.0.0.0/0 from webserver-allow-from_

```
master=yes
api=yes
api-key=CHANGEME
webserver=yes
webserver-address=0.0.0.0
webserver-port=8081
webserver-allow-from=0.0.0.0/0,10.10.0.25/32
webserver-password=CHANGEMENOW
allow-recursion=127.0.0.1/32
local-port=53
local-address=0.0.0.0
recursor=no
setgid=pdns
setuid=pdns
security-poll-suffix=
include-dir=/etc/powerdns/pdns.d
launch=gpgsql
config-dir=/etc/powerdns
default-soa-name=ns1.computestacks.net
allow-axfr-ips=10.20.0.10/32
```

Restart the server with:

```
service pdns restart
```

### Configure Slaves

_This should be repeated for all slaves_

Identify master server as the 'SuperMaster'. This will cause slave's to automatically provision new zone records.

_Connect to postgresql:_

```
su postgres
psql
```


_Once in the postgres terminal, run:_

```
\c pdns
insert into supermasters values ('10.10.0.10', 'ns2.computestacks.net', 'admin');
\q
exit
```

Edit `/etc/powerdns/pdns.conf` to look like:

```
master=no
slave=yes
slave-cycle-interval=60
recursor=no
allow-recursion=127.0.0.1/32
local-port=53
local-address=0.0.0.0
setgid=pdns
setuid=pdns
security-poll-suffix=
include-dir=/etc/powerdns/pdns.d
launch=gpgsql
config-dir=/etc/powerdns
```


Restart the server with:

```
service pdns restart
```
