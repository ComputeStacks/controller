# Upgrade Postgresql

The new default Postgresql version is 15 for new ComputeStacks Installations.

Installations on version 13 or 14 should upgrade. Here are the steps.

## Install Postgresql 15

```bash
apt update && apt install postgresql-15 postgresql-server-dev-15
systemctl stop postgresql.service
```

## Migrate Data

```bash
sudo su - postgres
/usr/lib/postgresql/15/bin/pg_upgrade \
  --old-datadir=/var/lib/postgresql/13/main \
  --new-datadir=/var/lib/postgresql/15/main \
  --old-bindir=/usr/lib/postgresql/13/bin \
  --new-bindir=/usr/lib/postgresql/15/bin \
  --old-options '-c config_file=/etc/postgresql/13/main/postgresql.conf' \
  --new-options '-c config_file=/etc/postgresql/15/main/postgresql.conf' \
  --check
```

Ensure that succeeds, and then re-run the above command, but this time without the `--check` option.

Exit out of the postgres user with `exit`, and return to the root user.

## Start up postgres

Swap the ports for v13 and v15 by editing `/etc/postgresql/15/main/postgresql.conf` and `/etc/postgresql/13/main/postgresql.conf`.

So v16 will be on port `5432` and v13 will be on `5433`.

Also ensure that `/etc/postgresql/15/main/pg_hba.conf` has the following line:

```bash
host    all             all             127.0.0.1/32            md5
```

_You may just need to edit the existing default line and change the method to `md5`._

```bash
systemctl start postgresql.service
```

Now go back into the postgres user and run:

```bash
/usr/lib/postgresql/15/bin/vacuumdb --all --analyze-in-stages
```

exit back to the root user again with `exit`.

## (optional) Tune Postgresql

Use [PG-Tune](https://pgtune.leopard.in.ua/) to create an optimized postgresql configuration. Edit `postgresql.conf` as necessary.

## Cleanup

```bash
systemctl stop postgersql.service
apt remove postgresql-13
./var/lib/postgresql/delete_old_cluster.sh
rm -rf /etc/postgresql/13
systemctl start postgresql.service
systemctl reset-failed
```

