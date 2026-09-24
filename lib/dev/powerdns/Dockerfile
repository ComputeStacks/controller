# Pinned to the version we run in production. 4.8 is EOL; 5.0 is the last branch
# that changes nothing the controller's pdns gem touches. See infra-notes
# topology/powerdns-version-and-upgrade.md before bumping this.
FROM powerdns/pdns-auth-50:5.0.7

# The official image is Debian-based, ships no sqlite3 CLI, keeps config in
# /etc/powerdns (not /etc/pdns), and runs as uid 953. Build as root, drop back after.
USER root

ADD pdns.conf /etc/powerdns/pdns.conf

RUN apt-get update \
      && apt-get install -y --no-install-recommends sqlite3 \
      && rm -rf /var/lib/apt/lists/* \
      && mkdir -p /etc/powerdns/sqlite-db \
      && sqlite3 /etc/powerdns/sqlite-db/pdns.db < /usr/local/share/doc/pdns/schema.sqlite3.sql \
      ; \
      pdnsutil create-zone cstacks.local ns1.cstacks.local \
        && pdnsutil add-record cstacks.local ns1.cstacks.local A 127.0.0.1 \
        && pdnsutil add-record cstacks.local cstacks.local A 127.0.0.1 \
        && pdnsutil add-record cstacks.local controller.cstacks.local A 127.0.0.1 \
        && pdnsutil add-record cstacks.local registry.cstacks.local A 127.0.0.1 \
        && pdnsutil add-record cstacks.local a.cstacks.local A 127.0.0.1 \
        && pdnsutil add-record cstacks.local "*.a.cstacks.local" CNAME a.cstacks.local \
        && pdnsutil add-record cstacks.local cstacks.local CAA "0 issue \"letsencrypt.org\"" \
        && pdnsutil create-zone csdevserver.local ns1.cstacks.local \
        && pdnsutil add-record csdevserver.local csdevserver.local A 127.0.0.1 \
        && pdnsutil add-record csdevserver.local csdevserver.local CAA "0 issue \"letsencrypt.org\"" \
        && pdnsutil create-zone usrcloud.local ns1.cstacks.local \
        && pdnsutil add-record usrcloud.local usrcloud.local A 127.0.0.1 \
        && pdnsutil add-record usrcloud.local www.usrcloud.local CNAME usrcloud.local \
        && pdnsutil create-zone usrca.local ns1.cstacks.local \
        && pdnsutil add-record usrca.local usrca.local A 127.0.0.1 \
        && pdnsutil add-record usrca.local www.usrca.local CNAME usrca.local \
        && pdnsutil add-record usrca.local usrca.local CAA "0 issue \"letsencrypt.org\"" \
        && pdnsutil create-zone cstacksorg.local ns1.cstacks.local \
        && pdnsutil add-record cstacksorg.local cstacksorg.local A 127.0.0.1 \
        && pdnsutil create-zone csnet.local ns1.cstacks.local \
        && pdnsutil add-record csnet.local csnet.local A 127.0.0.1 \
        && pdnsutil add-record csnet.local csnet.local CAA "0 issue \"digicert.com\"" \
        && pdnsutil create-zone cstacksus.local ns1.cstacks.local \
        && pdnsutil add-record cstacksus.local test.cstacksus.local A 127.0.0.1 \
        && pdnsutil add-record cstacksus.local cstacksus.local CAA "0 issue \"letsencrypt.org\"" \
        && pdnsutil add-record cstacksus.local test.cstacksus.local CAA "0 issue \"digicert.com\"" \
        && pdnsutil create-zone cstackscc.local ns1.cstacks.local \
        && pdnsutil add-record cstackscc.local test.cstackscc.local A 127.0.0.1 \
        && pdnsutil add-record cstackscc.local cstackscc.local CAA "0 issue \"digicert.com\"" \
        && pdnsutil add-record cstackscc.local test.cstackscc.local CAA "0 issue \"letsencrypt.org\"" \
        && pdnsutil create-zone myshared.local ns1.cstacks.local \
        && pdnsutil add-record myshared.local app.myshared.local A 127.0.0.1 \
        && pdnsutil add-record myshared.local "*.app.myshared.local" CNAME app.myshared.local \
        && pdnsutil add-record myshared.local myshared.local CAA "0 issue \"letsencrypt.org\"" \
        && pdnsutil add-record myshared.local myshared.local CAA "0 issuewild \"letsencrypt.org\"" \
        && pdnsutil create-zone mysharedus.local ns1.cstacks.local \
        && pdnsutil add-record mysharedus.local app.mysharedus.local A 192.168.10.10 \
        && pdnsutil add-record mysharedus.local "*.app.mysharedus.local" CNAME app.mysharedus.local \
        && pdnsutil add-record mysharedus.local mysharedus.local CAA "0 issue \"letsencrypt.org\"" \
        && pdnsutil add-record mysharedus.local mysharedus.local CAA "0 issuewild \"letsencrypt.org\"" \
        && pdnsutil create-zone mysharednet.local ns1.cstacks.local \
        && pdnsutil add-record mysharednet.local app.mysharednet.local A 127.0.0.1 \
        && pdnsutil add-record mysharednet.local "*.app.mysharednet.local" CNAME app.mysharedus.local \
        && pdnsutil add-record mysharednet.local mysharednet.local CAA "0 issue \"digicert.com\"" \
        && pdnsutil add-record mysharednet.local mysharednet.local CAA "0 issuewild \"digicert.com\"" \
        && pdnsutil create-zone mysharedorg.local ns1.cstacks.local \
        && pdnsutil add-record mysharedorg.local app.mysharedorg.local A 127.0.0.1 \
        && pdnsutil add-record mysharedorg.local "*.app.mysharedorg.local" CNAME app.mysharedorg.local \
        && pdnsutil create-zone mysharedapp.local ns1.cstacks.local \
        && pdnsutil add-record mysharedapp.local app.mysharedapp.local A 127.0.0.1 \
        && pdnsutil add-record mysharedapp.local "*.app.mysharedapp.local" CNAME app.mysharedapp.local \
        && pdnsutil add-record mysharedapp.local mysharedapp.local CAA "0 issue \"letsencrypt.org\""

RUN chown pdns:pdns -R /etc/powerdns

USER pdns

