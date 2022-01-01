# PowerDNS Test Container

Resources
* [Dockerfile Github](https://github.com/tcely/dockerhub-powerdns)

## Setup

### SQLite Database Setup

* Create SQL file with: `sqlite3 lib/dev/power_dns/caa-tester/sqlite-db/pdns.db`
* Copy paste [PowerDNS SQL Schema](https://doc.powerdns.com/authoritative/backends/generic-sqlite3.html#setting-up-the-database)
* Save with `.save` and `.exit`.

### PowerDNS

```bash
docker run --rm -it --name pdns \
           -v ${PWD}/lib/dev/power_dns/caa-tester/sqlite-db:/etc/pdns/sqlite-db \
           -v ${PWD}/lib/dev/power_dns/caa-tester/pdns.conf:/etc/pdns/pdns.conf \
           -p 53:53/udp \
           tcely/powerdns-server --daemon=no --guardian=no --loglevel=9
```

#### Create Records

Enter shell with: `docker exec -it pdns ash`

##### Zone with valid CAA

_should pass_

```bash
pdnsutil create-zone cmptstks.com ns1.dev.local
pdnsutil add-record cmptstks.com @ A 192.168.173.10
pdnsutil add-record cmptstks.com @ CAA "0 issue \"letsencrypt.org\""
```

##### Zone with CNAME and No CAA

When query a PowerDNS server with a CNAME record, but no CAA, it will return the CNAME when asking for CAA.

We need to ensure that will pass our test

_should pass_

```bash
pdnsutil create-zone usr.cloud ns1.dev.local
pdnsutil add-record usr.cloud @ A 192.168.173.10
pdnsutil add-record usr.cloud www CNAME usr.cloud
```

##### Zone with CNAME and CAA

_should pass_

```bash
pdnsutil create-zone usr.ca ns1.dev.local
pdnsutil add-record usr.ca @ A 192.168.173.10
pdnsutil add-record usr.ca www CNAME usr.ca
pdnsutil add-record usr.ca @ CAA "0 issue \"letsencrypt.org\""
```

##### Zone without CAA

_should pass_

```bash
pdnsutil create-zone cmptstks.org ns1.dev.local
pdnsutil add-record cmptstks.org @ A 192.168.173.10
```

##### Zone with invalid CAA

_should fail_

```bash
pdnsutil create-zone cmptstks.net ns1.dev.local
pdnsutil add-record cmptstks.net @ A 192.168.173.10
pdnsutil add-record cmptstks.net @ CAA "0 issue \"digicert.com\""
```

##### Zone with valid CAA on root, but invalid on subdomain

_should fail_

```bash
pdnsutil create-zone cmptstks.us ns1.dev.local
pdnsutil add-record cmptstks.us test A 192.168.173.10
pdnsutil add-record cmptstks.us @ CAA "0 issue \"letsencrypt.org\""
pdnsutil add-record cmptstks.us test CAA "0 issue \"digicert.com\""
```

##### Zone with valid CAA on subdomain, but invalid on root

_should pass_

```bash
pdnsutil create-zone cmptstks.cc ns1.dev.local
pdnsutil add-record cmptstks.cc test A 192.168.173.10
pdnsutil add-record cmptstks.cc @ CAA "0 issue \"digicert.com\""
pdnsutil add-record cmptstks.cc test CAA "0 issue \"letsencrypt.org\""
```

##### Load Balancer: Valid Zone

_should pass_

```bash
pdnsutil create-zone sharedurl.com ns1.dev.local
pdnsutil add-record sharedurl.com app A 192.168.173.10
pdnsutil add-record sharedurl.com *.app CNAME app.sharedurl.com
pdnsutil add-record sharedurl.com @ CAA "0 issue \"letsencrypt.org\""
pdnsutil add-record sharedurl.com @ CAA "0 issuewild \"letsencrypt.org\""
```

##### Load Balancer: Missing CNAME

_should pass_

```bash
pdnsutil create-zone sharedurl.com ns1.dev.local
pdnsutil add-record sharedurl.com app A 192.168.173.10
pdnsutil add-record sharedurl.com @ CAA "0 issue \"letsencrypt.org\""
pdnsutil add-record sharedurl.com @ CAA "0 issuewild \"letsencrypt.org\""
```

##### Load Balancer: Zone with Invalid A Record

_should fail_

```bash
pdnsutil create-zone sharedurl.us ns1.dev.local
pdnsutil add-record sharedurl.us app A 192.168.10.10
pdnsutil add-record sharedurl.us *.app CNAME app.sharedurl.us
pdnsutil add-record sharedurl.us @ CAA "0 issue \"letsencrypt.org\""
pdnsutil add-record sharedurl.us @ CAA "0 issuewild \"letsencrypt.org\""
```

##### Load Balancer: Zone with Invalid CAA Record & CNAME

_should fail_

```bash
pdnsutil create-zone sharedurl.net ns1.dev.local
pdnsutil add-record sharedurl.net app A 192.168.173.10
pdnsutil add-record sharedurl.net *.app CNAME app.sharedurl.us
pdnsutil add-record sharedurl.net @ CAA "0 issue \"digicert.com\""
pdnsutil add-record sharedurl.net @ CAA "0 issuewild \"digicert.com\""
```

##### Load Balancer: Valid Zone without CAA Record

_should pass_

```bash
pdnsutil create-zone sharedurl.org ns1.dev.local
pdnsutil add-record sharedurl.org app A 192.168.173.10
pdnsutil add-record sharedurl.org *.app CNAME app.sharedurl.org
```

##### Load Balancer: Zone without wildcard CAA

_should fail_

```bash
pdnsutil create-zone sharedurl.app ns1.dev.local
pdnsutil add-record sharedurl.app app A 192.168.173.10
pdnsutil add-record sharedurl.app *.app CNAME app.sharedurl.app
pdnsutil add-record sharedurl.app @ CAA "0 issue \"letsencrypt.org\""
```
