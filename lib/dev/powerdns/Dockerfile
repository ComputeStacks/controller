FROM ghcr.io/kwatson/docker-powerdns:main

ADD pdns.conf /etc/pdns/pdns.conf

RUN apk add sqlite \
      && mkdir -p /etc/pdns/sqlite-db \
      && sqlite3 /etc/pdns/sqlite-db/pdns.db < /usr/local/share/doc/pdns/schema.sqlite3.sql \
      && chown pdns:pdns -R /etc/pdns \
      && rm -rf /var/cache/apk/* \
      ; \
      pdnsutil create-zone cstacks.local ns1.cstacks.local \
        && pdnsutil add-record cstacks.local ns1 A 127.0.0.1 \
        && pdnsutil add-record cstacks.local @ A 127.0.0.1 \
        && pdnsutil add-record cstacks.local controller A 127.0.0.1 \
        && pdnsutil add-record cstacks.local registry A 127.0.0.1 \
        && pdnsutil add-record cstacks.local a A 127.0.0.1 \
        && pdnsutil add-record cstacks.local *.a CNAME a.cstacks.local \
        && pdnsutil add-record cstacks.local @ CAA "0 issue \"letsencrypt.org\"" \
        && pdnsutil create-zone csdevserver.local ns1.cstacks.local \
        && pdnsutil add-record csdevserver.local @ A 127.0.0.1 \
        && pdnsutil add-record csdevserver.local @ CAA "0 issue \"letsencrypt.org\"" \
        && pdnsutil create-zone usrcloud.local ns1.cstacks.local \
        && pdnsutil add-record usrcloud.local @ A 127.0.0.1 \
        && pdnsutil add-record usrcloud.local www CNAME usrcloud.local \
        && pdnsutil create-zone usrca.local ns1.cstacks.local \
        && pdnsutil add-record usrca.local @ A 127.0.0.1 \
        && pdnsutil add-record usrca.local www CNAME usrca.local \
        && pdnsutil add-record usrca.local @ CAA "0 issue \"letsencrypt.org\"" \
        && pdnsutil create-zone cstacksorg.local ns1.cstacks.local \
        && pdnsutil add-record cstacksorg.local @ A 127.0.0.1 \
        && pdnsutil create-zone csnet.local ns1.cstacks.local \
        && pdnsutil add-record csnet.local @ A 127.0.0.1 \
        && pdnsutil add-record csnet.local @ CAA "0 issue \"digicert.com\"" \
        && pdnsutil create-zone cstacksus.local ns1.cstacks.local \
        && pdnsutil add-record cstacksus.local test A 127.0.0.1 \
        && pdnsutil add-record cstacksus.local @ CAA "0 issue \"letsencrypt.org\"" \
        && pdnsutil add-record cstacksus.local test CAA "0 issue \"digicert.com\"" \
        && pdnsutil create-zone cstackscc.local ns1.cstacks.local \
        && pdnsutil add-record cstackscc.local test A 127.0.0.1 \
        && pdnsutil add-record cstackscc.local @ CAA "0 issue \"digicert.com\"" \
        && pdnsutil add-record cstackscc.local test CAA "0 issue \"letsencrypt.org\"" \
        && pdnsutil create-zone myshared.local ns1.cstacks.local \
        && pdnsutil add-record myshared.local app A 127.0.0.1 \
        && pdnsutil add-record myshared.local *.app CNAME app.myshared.local \
        && pdnsutil add-record myshared.local @ CAA "0 issue \"letsencrypt.org\"" \
        && pdnsutil add-record myshared.local @ CAA "0 issuewild \"letsencrypt.org\"" \
        && pdnsutil create-zone mysharedus.local ns1.cstacks.local \
        && pdnsutil add-record mysharedus.local app A 192.168.10.10 \
        && pdnsutil add-record mysharedus.local *.app CNAME app.mysharedus.local \
        && pdnsutil add-record mysharedus.local @ CAA "0 issue \"letsencrypt.org\"" \
        && pdnsutil add-record mysharedus.local @ CAA "0 issuewild \"letsencrypt.org\"" \
        && pdnsutil create-zone mysharednet.local ns1.cstacks.local \
        && pdnsutil add-record mysharednet.local app A 127.0.0.1 \
        && pdnsutil add-record mysharednet.local *.app CNAME app.mysharedus.local \
        && pdnsutil add-record mysharednet.local @ CAA "0 issue \"digicert.com\"" \
        && pdnsutil add-record mysharednet.local @ CAA "0 issuewild \"digicert.com\"" \
        && pdnsutil create-zone mysharedorg.local ns1.cstacks.local \
        && pdnsutil add-record mysharedorg.local app A 127.0.0.1 \
        && pdnsutil add-record mysharedorg.local *.app CNAME app.mysharedorg.local \
        && pdnsutil create-zone mysharedapp.local ns1.cstacks.local \
        && pdnsutil add-record mysharedapp.local app A 127.0.0.1 \
        && pdnsutil add-record mysharedapp.local *.app CNAME app.mysharedapp.local \
        && pdnsutil add-record mysharedapp.local @ CAA "0 issue \"letsencrypt.org\""

