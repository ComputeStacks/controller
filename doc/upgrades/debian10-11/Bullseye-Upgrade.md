# Upgrade Debian 10 to Debian 11

```bash
apt-mark unhold docker-ce docker-ce-cli
apt update && apt -y upgrade && apt -y dist-upgrade && apt -y autoremove
if [ -f /etc/apt/sources.list.d/backports.list ]; then rm /etc/apt/sources.list.d/backports.list; fi
cp /etc/apt/sources.list /etc/apt/sources.list.buster
cat << 'EOF' > /etc/apt/sources.list
deb http://deb.debian.org/debian/ bullseye main
deb-src http://deb.debian.org/debian/ bullseye main

deb https://deb.debian.org/debian-security bullseye-security main contrib
deb-src https://deb.debian.org/debian-security bullseye-security main contrib

# bullseye-updates, previously known as 'volatile'
deb http://deb.debian.org/debian/ bullseye-updates main
deb-src http://deb.debian.org/debian/ bullseye-updates main
EOF
echo "deb [arch=amd64] https://download.docker.com/linux/debian bullseye stable" > /etc/apt/sources.list.d/docker.list
apt update && apt -y install tmux && curl https://gist.githubusercontent.com/kwatson/45a298891981e2323eed3e118a3d5da7/raw/ff7eb5ba7afbccb11df6470290ab6f520c2a128d/.tmux.conf > ~/.tmux.conf
```

_Ensure you're in a tmux session on all nodes._

## Controller & Metrics
```bash
docker stop portal
cstacks database-backup
echo "deb http://apt.postgresql.org/pub/repos/apt bullseye-pgdg main" > /etc/apt/sources.list.d/postgresql.list
```

## Node

```bash
docker stop $(docker ps -aq --filter="network=net100")
if [ -f /etc/apt/sources.list.d/haproxy.list ]; then echo "deb http://haproxy.debian.net bullseye-backports-2.4 main" > /etc/apt/sources.list.d/haproxy.list; fi
```

## Upgrade

```bash
apt update && apt dist-upgrade
```

## Cleanup

```bash
apt autoremove

# On nodes
docker start $(docker ps -aq)
```
