#!/bin/bash
apt update && apt -y install gnupg2 ca-certificates curl vim
echo "export EDITOR=vim" >> /etc/profile
echo "export EDITOR=vim" >> /root/.bashrc
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
apt update && apt -y install postgresql-13

echo "deb [arch=amd64] http://repo.powerdns.com/debian bullseye-auth-46 main" > /etc/apt/sources.list.d/pdns.list

cat << 'EOF' > /etc/apt/preferences.d/pdns
Package: pdns-*
Pin: origin repo.powerdns.com
Pin-Priority: 600
EOF

curl https://repo.powerdns.com/FD380FBB-pub.asc | apt-key add -
apt update && apt -y install pdns-server pdns-backend-pgsql
