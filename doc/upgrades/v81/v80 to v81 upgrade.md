# v8.0 to v8.1 Upgrade Guide

## Upgrade Redis Server

We now require redis server 6.2+. Please upgrade your installation prior to upgrading the controller.

Previous installations used the redis-server distributed with debian. To get the latest version, add the redis apt repository, and allow it to upgrade your installation with:

_Install latest version_
```bash
curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list

apt update && apt upgrade
```

Optionally edit `/etc/redis/redis.conf` and uncomment `save ""` to disable saving snapshots locally.

## Puma replaced Passenger

With the switch to puma, we need to adjust some environmental variables in `/etc/default/computestacks` and `/usr/local/bin/cstacks` on the controller.

Replace the following:

```bash
PASSENGER_MAX_POOL_SIZE=15
PASSENGER_MIN_INSTANCES=15
```

with:

```bash
RAILS_MIN_THREADS=15
RAILS_MAX_THREADS=15
```

```bash
sed -i 's/PASSENGER_MAX_POOL_SIZE/RAILS_MAX_THREADS/g' /etc/default/computestacks
sed -i 's/PASSENGER_MIN_INSTANCES/RAILS_MIN_THREADS/g' /etc/default/computestacks
sed -i 's/PASSENGER_MAX_POOL_SIZE/RAILS_MAX_THREADS/g' /usr/local/bin/cstacks
sed -i 's/PASSENGER_MIN_INSTANCES/RAILS_MIN_THREADS/g' /usr/local/bin/cstacks
```

_Adjust values to meet your needs_


## Cloudflare

If you're using cloudflare in front of your controller, you will want to add the following script to `/etc/cron.daily/cloudflare_ips`:

```bash
#!/bin/bash

set -e

CLOUDFLARE_FILE_PATH=/etc/nginx/conf.d/cloudflare.conf

echo "#Cloudflare" > $CLOUDFLARE_FILE_PATH;
echo "" >> $CLOUDFLARE_FILE_PATH;

echo "# - IPv4" >> $CLOUDFLARE_FILE_PATH;
for i in `curl -s -L https://www.cloudflare.com/ips-v4`; do
    echo "set_real_ip_from $i;" >> $CLOUDFLARE_FILE_PATH;
done

echo "" >> $CLOUDFLARE_FILE_PATH;
echo "# - IPv6" >> $CLOUDFLARE_FILE_PATH;
for i in `curl -s -L https://www.cloudflare.com/ips-v6`; do
    echo "set_real_ip_from $i;" >> $CLOUDFLARE_FILE_PATH;
done

echo "" >> $CLOUDFLARE_FILE_PATH;
echo "real_ip_header CF-Connecting-IP;" >> $CLOUDFLARE_FILE_PATH;

systemctl reload nginx
```

This will ensure the real ip is pushed to the controller for logging.
