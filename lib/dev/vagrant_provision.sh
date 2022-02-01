#!/bin/bash

hostname csdev
echo "csdev" > /etc/hostname
echo "127.0.0.1 csdev" >> /etc/hosts
echo "127.0.0.1 controller.cstacks.local" >> /etc/hosts
echo "127.0.0.1 ns1.cstacks.local" >> /etc/hosts
echo "export EDITOR=vim" >> /etc/profile
echo "export EDITOR=vim" >> /root/.profile
echo "export EDITOR=vim" >> /home/vagrant/.profile
echo "Defaults:vagrant env_keep += \"EDITOR\"" >> /etc/sudoers.d/vagrant
echo "syntax on" >> /etc/vim/vimrc
apt-get update && apt-get -y upgrade
apt-get -y install apt-utils build-essential software-properties-common ca-certificates curl wget lsb-release iputils-ping vim openssl dnsutils gnupg2 pass traceroute tree iptables jq whois socat git rsync apt-transport-https gnupg-agent etcd prometheus-node-exporter redis-server postgresql-13 postgresql-13-ip4r rbenv icu-devtools libicu-dev libreadline-dev libsqlite3-dev libssl-dev libxml2-dev libxslt1-dev git direnv libpq-dev nodejs tmux pwgen
curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

echo "deb [arch=amd64] http://repo.powerdns.com/debian bullseye-auth-46 main" > /etc/apt/sources.list.d/pdns.list

cat << 'EOF' > /etc/apt/preferences.d/pdns
Package: pdns-*
Pin: origin repo.powerdns.com
Pin-Priority: 600
EOF

curl https://repo.powerdns.com/FD380FBB-pub.asc | apt-key add -

curl https://haproxy.debian.net/bernat.debian.org.gpg \
      | gpg --dearmor > /usr/share/keyrings/haproxy.debian.net.gpg

echo deb "[signed-by=/usr/share/keyrings/haproxy.debian.net.gpg]" \
      http://haproxy.debian.net bullseye-backports-2.4 main \
      > /etc/apt/sources.list.d/haproxy.list

apt-get update && apt-get -y install consul docker-ce docker-ce-cli containerd.io haproxy=2.4.\* pdns-server pdns-backend-pgsql
touch /etc/consul.d/consul.env && chown consul:consul /etc/consul.d/consul.env
cat << 'EOF' > /etc/consul.d/consul.hcl
datacenter = "dev"
client_addr = "127.0.0.1"
ui_config{
  enabled = true
}
bind_addr = "127.0.0.1"
acl{
  enabled = true
  default_policy = "allow"
  enable_token_persistence = true
}
data_dir = "/opt/consul"
bootstrap_expect = 1
server = true
EOF
systemctl enable consul && systemctl start consul

systemctl stop pdns

echo "Setting up powerdns..."
export PDNS_API_KEY=$(pwgen -s 32 1)
export PDNS_WEB_KEY=$(pwgen -s 32 1)
export PDNS_DB_PASS=$(pwgen -s 32 1)

mkdir /home/vagrant/.pdns
echo $PDNS_API_KEY > /home/vagrant/.pdns/api_key
echo $PDNS_WEB_KEY > /home/vagrant/.pdns/web_auth_pass

sudo -u postgres psql -c "create role pdns with superuser login password '$PDNS_DB_PASS'"
sudo -u postgres psql -c 'create database pdns owner pdns'
sudo -u postgres psql -d pdns -f /usr/share/doc/pdns-backend-pgsql/schema.pgsql.sql
rm /etc/powerdns/named.conf
rm /etc/powerdns/pdns.d/bind.conf

cat << EOF > /etc/powerdns/pdns.d/pdns.local.gpgsql.conf
gpgsql-host=localhost
gpgsql-dbname=pdns
gpgsql-user=pdns
gpgsql-password=$PDNS_DB_PASS
gpgsql-dnssec=yes
EOF

cat << EOF > /etc/powerdns/pdns.conf
api=yes
api-key=$PDNS_API_KEY
webserver=yes
webserver-address=127.0.0.1
webserver-port=8081
webserver-allow-from=127.0.0.1/32
webserver-password=$PDNS_WEB_KEY
local-port=53
local-address=127.0.0.1
include-dir=/etc/powerdns/pdns.d
launch=gpgsql
config-dir=/etc/powerdns
default-soa-edit=inception-increment
default-ttl=14400
default-soa-content=ns1.cstacks.local hostmaster.@ 0 10800 3600 604800 3600
query-cache-ttl=20
EOF

systemctl enable pdns && systemctl start pdns

echo "Installing Overmind processor manager..."
cd /tmp
curl -s https://api.github.com/repos/DarthSim/overmind/releases/latest \
  | grep browser_download_url \
  | grep linux-amd64 \
  | cut -d '"' -f 4 \
  | wget -qi -

gunzip /tmp/overmind*.gz
rm /tmp/overmind*.gz.sha256sum
mv /tmp/overmind* /usr/local/bin/overmind && chmod +x /usr/local/bin/overmind
cd ~

echo "Setting up self-signed wildcard SSL..."
mkdir /home/vagrant/.ssl_wildcard

cat << 'EOF' > /home/vagrant/.ssl_wildcard/wildcard.conf
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = OR
L = Portland
O = CS Customer
OU = Deployment
CN = a.cstacks.local

[v3_req]
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = *.cstacks.local
EOF

openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -sha256 -keyout /home/vagrant/.ssl_wildcard/sharedcert.pem -out /home/vagrant/.ssl_wildcard/sharedcert.pem -config /home/vagrant/.ssl_wildcard/wildcard.conf -extensions 'v3_req'

curl https://gist.githubusercontent.com/kwatson/45a298891981e2323eed3e118a3d5da7/raw/ff7eb5ba7afbccb11df6470290ab6f520c2a128d/.tmux.conf > /home/vagrant/.tmux.conf
cp /home/vagrant/.tmux.conf /root/

chown -R vagrant:vagrant /home/vagrant/

mkdir -p /etc/haproxy/certs

cat << 'EOF' > /etc/haproxy/default.http
HTTP/1.0 503 Service Unavailable
Cache-Control: no-cache
Connection: close
Content-Type: text/html



<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="content-type" content="text/html;charset=UTF-8" />
    <title>Service Unavailable - 503</title>

    <style type="text/css">

      body {
        margin: 0;
        text-align: center;
        font: 1em/1.3em "Lucida Grande", Arial, Arial, sans-serif;
        background-color: #efefef ;
      }


      div.outer {
        font-size: 75%;
        position: absolute;
        left: 40%;
        top: 50%;
        width: 600px;
        height: 300px;
        margin-left: -200px;
        margin-top: -150px;
      }


      .dialog {
        padding: 0;
        background-color: white;
        border-top: 1px solid #ddd;
        border-right: 1px solid #ccc;
        border-left: 1px solid #ddd;
        border-bottom: 1px solid #ccc;
      }

      div.error {
        margin-left: 0px;
        padding-left: 3px;
        border-left: 2px solid #aaa;
        overflow: auto;
        background: #eee;
      }

      h1 {
        font-size: 100%;
        background: #000;
        color: white;
        margin: 0;
        padding: 5px 10px;
      }

      .block {
        text-align: center;
        width: 600px;
        margin: 0 auto;
        margin-top: 2em;
      }

      h1 span {
        float: right;
        font-size: 75%;
        color: #666;
      }
      .footer,
      .footer a {
        font-size: 9px;
        text-decoration: none;
        color: #333;
        font-weight: bold;
      }
      .footer a:hover,
      .footer a:active {
        text-decoration: underline;
      }
    </style>

</head>

<body>

<div class="outer">

    <div class="dialog" style="text-align: center;">
      <h1>Service Unavailable - 503</h1>


      <div class="block">
        <p>
          Either the service you're attempting to connect to is offline,<br />
          or you have entered an invalid URL.
        </p>
      </div>
   </div>
</div>
</body>
</html>
EOF

if systemctl status consul; then
  echo "Consul booted successfull"
else
  echo "Consul failed to start"
  exit 1
fi

systemctl enable etcd && systemctl start etcd

if systemctl status etcd; then
  echo "etcd booted successfull"
else
  echo "etcd failed to start"
  exit 1
fi

systemctl enable prometheus-node-exporter && systemctl start prometheus-node-exporter

cat << 'EOF' > /etc/redis.conf
bind 127.0.0.1
protected-mode yes
port 6379
tcp-backlog 511
timeout 0
tcp-keepalive 300
daemonize yes
supervised no
pidfile /var/run/redis/redis-server.pid
loglevel notice
logfile /var/log/redis/redis-server.log
databases 16
always-show-logo yes
save ""
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /var/lib/redis
replica-serve-stale-data yes
replica-read-only yes
repl-diskless-sync no
repl-diskless-sync-delay 5
repl-disable-tcp-nodelay no
replica-priority 100
lazyfree-lazy-eviction no
lazyfree-lazy-expire no
lazyfree-lazy-server-del no
replica-lazy-flush no
appendonly no
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-use-rdb-preamble yes
lua-time-limit 5000
slowlog-log-slower-than 10000
slowlog-max-len 128
latency-monitor-threshold 0
notify-keyspace-events ""
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
stream-node-max-bytes 4096
stream-node-max-entries 100
activerehashing yes
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
hz 10
dynamic-hz yes
aof-rewrite-incremental-fsync yes
rdb-save-incremental-fsync yes
EOF

systemctl restart redis-server

wget -O /tmp/cs-agent.tar.gz https://cdn.computestacks.net/packages/cs-agent/cs-agent.tar.gz
tar -xzvf /tmp/cs-agent.tar.gz -C /tmp
mv /tmp/cs-agent /usr/local/bin/ && chmod +x /usr/local/bin/cs-agent

cat << 'EOF' > /etc/systemd/system/cs-agent.service
[Unit]
Description="ComputeStacks Agent"
Documentation=https://computestacks.com
Requires=docker.service
After=docker.service
Requires=consul.service
After=consul.service
ConditionFileNotEmpty=/etc/computestacks/agent.yml

[Service]
User=root
Group=root
ExecStart=/usr/local/bin/cs-agent
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

mkdir /etc/systemd/system/docker.service.d
cat << 'EOF' > /etc/systemd/system/docker.service.d/startup.conf
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H unix:// -H tcp://0.0.0.0:2376 --ipv6=false --icc=false --userland-proxy=false --cluster-store=etcd://127.0.0.1:2379
TasksMax=infinity
EOF

systemctl daemon-reload && systemctl enable docker && systemctl restart docker

echo "Allow vagrant user to access docker..."
usermod -aG docker vagrant

mkdir /etc/calico
mkdir /var/log/calico
mkdir /var/run/calico

wget -O /usr/local/bin/calicoctl https://cdn.computestacks.net/packages/calico/calicoctl-v1.6.5
wget -O /usr/local/bin/calico-libnetwork https://cdn.computestacks.net/packages/calico/libnetwork-plugin-v1.1.3
chmod +x /usr/local/bin/calicoctl
chmod +x /usr/local/bin/calico-libnetwork

cat << 'EOF' > /etc/calico/calico-ipam.env
IP=127.0.0.1
ETCD_ENDPOINTS=http://127.0.0.1:2379
NODENAME=csdev
CALICO_NETWORKING_BACKEND=bird
CALICO_LIBNETWORK_LABEL_ENDPOINTS=true
EOF

cat << 'EOF' > /etc/calico/calicoctl.cfg
apiVersion: v1
kind: calicoApiConfig
metadata:
spec:
  datastoreType: "etcdv2"
  etcdEndpoints: http://127.0.0.1:2379
EOF

cat << 'EOF' > /etc/systemd/system/calico-ipam.service
[Unit]
Description=calico-ipam
Before=docker.service

[Service]
EnvironmentFile=/etc/calico/calico-ipam.env
ExecStart=/usr/local/bin/calico-libnetwork
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat << 'EOF' > /usr/local/bin/run_calico
docker run --net=host --privileged --name=calico-node -d --restart=always \
  -e ETCD_ENDPOINTS=http://127.0.0.1:2379 \
  -e CALICO_LIBNETWORK_LABEL_ENDPOINTS=true \
  -e CALICO_NETWORKING_BACKEND=bird \
  -e CALICO_LIBNETWORK_ENABLED=false \
  -e CALICO_LIBNETWORK_CREATE_PROFILES=false \
  -e NO_DEFAULT_POOLS=true \
  -e IP=127.0.0.1 \
  -e NODENAME=csdev \
  -v /var/log/calico:/var/log/calico \
  -v /var/run/calico:/var/run/calico \
  -v /lib/modules:/lib/modules \
  -v /run:/run \
  -v /run/docker/plugins:/run/docker/plugins \
  -v /var/run/docker.sock:/var/run/docker.sock \
  quay.io/calico/node:release-v2.6
EOF
chmod +x /usr/local/bin/run_calico

systemctl daemon-reload && systemctl enable calico-ipam && systemctl start calico-ipam

bash /usr/local/bin/run_calico

export CONSUL_HTTP_TOKEN=$(curl -X PUT http://127.0.0.1:8500/v1/acl/bootstrap | jq -r '.SecretID')
echo "export CONSUL_HTTP_TOKEN=$CONSUL_HTTP_TOKEN" >> /home/vagrant/.profile
echo "export CONSUL_HTTP_TOKEN=$CONSUL_HTTP_TOKEN" >> /root/.profile
echo "export SECRET_KEY_BASE=$(openssl rand -hex 64)" >> /home/vagrant/.profile
echo "export USER_AUTH_SECRET=$(openssl rand -hex 64)" >> /home/vagrant/.profile
echo "export REDIS_HOST=127.0.0.1" >> /home/vagrant/.profile
echo "eval \"\$(direnv hook bash)\"" >> /home/vagrant/.profile
echo $CONSUL_HTTP_TOKEN > /home/vagrant/consul.token && chown vagrant:vagrant /home/vagrant/consul.token

sed -i 's/allow/deny/g' /etc/consul.d/consul.hcl && systemctl restart consul

mkdir /etc/computestacks
cat << EOF > /etc/computestacks/agent.yml
computestacks:
  host: http://127.0.0.1:3005
consul:
  host: 127.0.0.1:8500
  tls: false
  token: $CONSUL_HTTP_TOKEN
backups:
  enabled: true
  check_freq: "*/2 * * * *"
  prune_freq: "15 1 * * *"
  key: "changme!"
  borg:
    compress: "zstd,3"
    image: "cmptstks/borg:stable"
    nfs: false
docker:
  version: "1.41"
EOF

systemctl start cs-agent && systemctl enable cs-agent

cat << 'EOF' > /etc/systemd/system/cadvisor.service
[Unit]
Description=cadvisor
Requires=docker.service
After=docker.service
DefaultDependencies=no

[Service]
Type=simple
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker kill cadvisor 2>/dev/null'
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker rm cadvisor 2>/dev/null'

ExecStart=/usr/bin/env docker run --rm --name cadvisor \
      --log-driver=none \
      --network=host \
      --privileged \
      -v /:/rootfs:ro \
      -v /var/run:/var/run:ro \
      -v /sys:/sys:ro \
      -v /var/lib/docker/:/var/lib/docker:ro \
      -v /dev/disk/:/dev/disk:ro \
      -v /etc/machine-id:/etc/machine-id:ro \
      --device=/dev/kmsg \
      gcr.io/cadvisor/cadvisor:v0.43.0

ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker kill cadvisor 2>/dev/null'
ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker rm cadvisor 2>/dev/null'
Restart=always
RestartSec=30
SyslogIdentifier=cadvisor

[Install]
WantedBy=multi-user.target
WantedBy=docker.service
EOF

systemctl daemon-reload && systemctl enable cadvisor && systemctl start cadvisor

mkdir /etc/prometheus
docker network create ops
docker volume create prometheus-data
docker volume create alertmanager-data

cat << 'EOF' > /etc/prometheus/alerts_node.yml
groups:
- name: NodeHealth
  rules:
  - alert: NodeUp
    expr: up{job="cadvisor"} == 0
    for: 1m
    labels:
      severity: warning
      service: container-node
    annotations:
      summary: "Node Offline (instance {{ $labels.instance }})"
      description: "Node is Offline\n  LABELS: {{ $labels }}"
      value: "{{ $value }}"
  - alert: HighCpuLoad
    expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
    for: 5m
    labels:
      severity: warning
      service: container-node
    annotations:
      summary: "High CPU load (instance {{ $labels.instance }})"
      description: "CPU load is > 80%\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
      value: "{{ $value }}"
  - alert: OutOfMemory
    expr: node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100 < 10
    for: 5m
    labels:
      severity: warning
      service: container-node
    annotations:
      summary: "Out of memory (instance {{ $labels.instance }})"
      description: "Node memory is filling up (< 10% left)\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
      value: "{{ $value }}"
  - alert: OutOfInodes
    expr: node_filesystem_files_free{mountpoint ="/rootfs"} / node_filesystem_files{mountpoint ="/rootfs"} * 100 < 10
    for: 5m
    labels:
      severity: warning
      service: container-node
    annotations:
      summary: "Out of inodes (instance {{ $labels.instance }})"
      description: "Disk is almost running out of available inodes (< 10% left)\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
      value: "{{ $value }}"
  - alert: UnusualDiskReadLatency
    expr: rate(node_disk_read_time_seconds_total[1m]) / rate(node_disk_reads_completed_total[1m]) > 100
    for: 5m
    labels:
      severity: warning
      service: container-node
    annotations:
      summary: "Unusual disk read latency (instance {{ $labels.instance }})"
      description: "Disk latency is growing (read operations > 100ms)\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
      value: "{{ $value }}"
  - alert: UnusualDiskWriteLatency
    expr: rate(node_disk_write_time_seconds_total[1m]) / rate(node_disk_writes_completed_total[1m]) > 100
    for: 5m
    labels:
      severity: warning
      service: container-node
    annotations:
      summary: "Unusual disk write latency (instance {{ $labels.instance }})"
      description: "Disk latency is growing (write operations > 100ms)\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
      value: "{{ $value }}"
  - alert: OutOfDiskSpace
    expr: (node_filesystem_avail_bytes{mountpoint="/rootfs"}  * 100) / node_filesystem_size_bytes{mountpoint="/rootfs"} < 10
    for: 5m
    labels:
      severity: warning
      service: container-node
    annotations:
      summary: "Out of disk space (instance {{ $labels.instance }})"
      description: "Disk is almost full (< 10% left)\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
      value: "{{ $value }}"
  - alert: DiskWillFillIn4Hours
    expr: predict_linear(node_filesystem_free_bytes{fstype!~"tmpfs"}[1h], 4 * 3600) < 0
    for: 5m
    labels:
      severity: warning
      service: container-node
    annotations:
      summary: "Disk will fill in 4 hours (instance {{ $labels.instance }})"
      description: "Disk will fill in 4 hours at current write rate\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
      value: "{{ $value }}"
EOF

cat << 'EOF' > /etc/prometheus/alerts_prometheus.yml
groups:
- name: PrometheusHealth
  rules:
  - alert: PrometheusConfigurationReload
    expr: prometheus_config_last_reload_successful != 1
    for: 5m
    labels:
      severity: error
      service: prometheus
    annotations:
      summary: "Prometheus configuration reload (instance {{ $labels.instance }})"
      description: "Prometheus configuration reload error\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
      value: "{{ $value }}"
  - alert: PrometheusNotConnectedToAlertmanager
    expr: prometheus_notifications_alertmanagers_discovered < 1
    for: 5m
    labels:
      severity: error
      service: prometheus
    annotations:
      summary: "Prometheus not connected to alertmanager (instance {{ $labels.instance }})"
      description: "Prometheus cannot connect the alertmanager\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
      value: "{{ $value }}"
  - alert: AlertmanagerConfigurationReload
    expr: alertmanager_config_last_reload_successful != 1
    for: 5m
    labels:
      severity: error
      service: prometheus
    annotations:
      summary: "AlertManager configuration reload (instance {{ $labels.instance }})"
      description: "AlertManager configuration reload error\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
      value: "{{ $value }}"
  - alert: ExporterDown
    expr: up == 0
    for: 5m
    labels:
      severity: warning
      service: prometheus
    annotations:
      summary: "Exporter down (instance {{ $labels.instance }})"
      description: "Prometheus exporter down\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
      value: "{{ $value }}"
EOF

cat << 'EOF' > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Requires=docker.service
After=docker.service
DefaultDependencies=no

[Service]
Type=simple
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker kill prometheus 2>/dev/null'
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker rm prometheus 2>/dev/null'

ExecStart=/usr/bin/env docker run --rm --name prometheus \
      --log-driver=none \
      --network=host \
      -v prometheus-data:/prometheus \
      -v /etc/prometheus:/etc/prometheus:z \
      prom/prometheus:latest

ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker kill prometheus 2>/dev/null'
ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker rm prometheus 2>/dev/null'
Restart=always
RestartSec=30
SyslogIdentifier=prometheus

[Install]
WantedBy=multi-user.target
WantedBy=docker.service
EOF

cat << 'EOF' > /etc/prometheus/alerts_containers.yml
groups:
- name: ContainerHealth
  rules:
    - alert: ContainerCpuUsage
      expr: (sum(rate(container_cpu_usage_seconds_total{name!~"alertmanager|consul|loki|loki-logs|cadvisor|portal|prometheus|grafana|calico-node|vault-bootstrap|nginx|haproxy|"}[3m])) BY (instance, name) * 100) > 95
      for: 1m
      labels:
        severity: warning
      annotations:
        summary: "Container CPU usage (instance {{ $labels.instance }})"
        description: "Container CPU usage is above 95%\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
        value: "{{ $value }}"
    - alert: ContainerMemoryUsage
      expr: (sum(container_memory_usage_bytes{name!~"alertmanager|consul|loki|loki-logs|cadvisor|portal|prometheus|grafana|calico-node|vault-bootstrap|nginx|haproxy|"}) BY (instance, name) / sum(container_spec_memory_limit_bytes{name!~"alertmanager|consul|loki|loki-logs|cadvisor|portal|prometheus|grafana|calico-node|vault-bootstrap|nginx|haproxy|"}) BY (instance, name) * 100) > 92
      for: 1m
      labels:
        severity: warning
      annotations:
        summary: "Container Memory usage (instance {{ $labels.instance }})"
        description: "Container Memory usage is above 92%\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
        value: "{{ $value }}"
EOF

cat << 'EOF' > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 10s
  evaluation_interval: 10s
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - '127.0.0.1:9093'
rule_files:
  - alerts_prom.yml
  - alerts_node.yml
  - alerts_containers.yml
scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets:
          - 'localhost:9090'
  - job_name: cadvisor
    static_configs:
      - targets:
          - '127.0.0.1:8080'
        labels:
          region: dev
          node: csdev
  - job_name: node-exporter
    static_configs:
      - targets:
          - '127.0.0.1:9100'
        labels:
          region: dev
          node: csdev
  - job_name: haproxy
    static_configs:
      - targets:
          - '127.0.0.1:81'
        labels:
          region: dev
          node: csdev

EOF

cat << 'EOF' > /etc/prometheus/alertmanager.yml
route:
  group_by: ['alertname', 'name', 'service', 'region', 'node']
  group_wait: 30s
  group_interval: 1m
  repeat_interval: 1h
  receiver: controller
receivers:
  - name: 'controller'
    webhook_configs:
      - send_resolved: true
        url: "http://127.0.0.1:3005/api/system/alert_notifications"
EOF

cat << 'EOF' > /etc/systemd/system/alertmanager.service
[Unit]
Description=Prometheus AlertManager
Requires=docker.service
After=docker.service
DefaultDependencies=no

[Service]
Type=simple
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker kill alertmanager 2>/dev/null'
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker rm alertmanager 2>/dev/null'

ExecStart=/usr/bin/env docker run --rm --name alertmanager \
      --log-driver=none \
      --network=host \
      -v alertmanager-data:/alertmanager \
      -v /etc/prometheus:/etc/alertmanager:z \
      prom/alertmanager:latest

ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker kill alertmanager 2>/dev/null'
ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker rm alertmanager 2>/dev/null'
Restart=always
RestartSec=30
SyslogIdentifier=alertmanager

[Install]
WantedBy=multi-user.target
WantedBy=docker.service
EOF

mkdir /etc/loki
mkdir /var/lib/loki

docker volume create loki-data

cat << 'EOF' > /etc/systemd/system/loki.service
[Unit]
Description=Loki
Requires=docker.service
After=docker.service
DefaultDependencies=no

[Service]
Type=simple
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker kill loki-logs 2>/dev/null'
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker rm loki-logs 2>/dev/null'

ExecStart=/usr/bin/env docker run --rm --name loki-logs \
      --log-driver=none \
      --network=host \
      -v loki-data:/loki \
      -v /etc/loki/loki-config.yml:/etc/loki/local-config.yaml:z \
      grafana/loki:2.4.2

ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker kill loki-logs 2>/dev/null'
ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker rm loki-logs 2>/dev/null'
Restart=always
RestartSec=30
SyslogIdentifier=loki

[Install]
WantedBy=multi-user.target
WantedBy=docker.service
EOF

cat << 'EOF' > /etc/loki/loki-config.yml
---
auth_enabled: false

server:
  http_listen_port: 3100
  http_server_read_timeout: 1000s
  http_server_write_timeout: 1000s
  http_server_idle_timeout: 1000s
  log_level: info

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_encoding: snappy
  chunk_idle_period: 1h
  chunk_target_size: 1048576
  chunk_retain_period: 30s
  max_transfer_retries: 0
  wal:
    dir: /loki/ruler-wal

schema_config:
  configs:
  - from: 2020-05-15
    store: boltdb
    object_store: filesystem
    schema: v11
    index:
      prefix: index_
      period: 168h

storage_config:
  boltdb:
    directory: /loki/index

  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  ingestion_rate_mb: 30
  ingestion_burst_size_mb: 60

chunk_store_config:
  max_look_back_period: 336h

# https://grafana.com/docs/loki/latest/operations/storage/retention/
table_manager:
  retention_deletes_enabled: true
  retention_period: 336h
  chunk_tables_provisioning:
    inactive_read_throughput: 10
    inactive_write_throughput: 10
    provisioned_read_throughput: 50
    provisioned_write_throughput: 20
  index_tables_provisioning:
    inactive_read_throughput: 10
    inactive_write_throughput: 10
    provisioned_read_throughput: 50
    provisioned_write_throughput: 20
EOF

mkdir /etc/fluentd

cat << 'EOF' > /etc/fluentd/fluent.conf
<source>
  @type  forward
  @id    input1
  @label @mainstream
  port   9432
</source>

<filter **>
  @type stdout
</filter>

<label @mainstream>
  <match **.**>
    @type loki
    url "#{ENV['LOKI_URL']}"
    remove_keys container_name, container_id, source
    extra_labels {"job":"fluentd"}
    flush_interval 10s
    flush_at_shutdown true
    buffer_chunk_limit 1m
    <label>
      container_name $.container_name
    </label>
    <label>
      project_id $['com.computestacks.deployment_id']
    </label>
    <label>
      service_id $['com.computestacks.service_id']
    </label>
  </match>
</label>
EOF

cat << 'EOF' > /etc/systemd/system/fluentd.service
[Unit]
Description=fluentd
Requires=docker.service
After=docker.service
DefaultDependencies=no

[Service]
Type=simple
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker kill fluentd 2>/dev/null'

ExecStart=/usr/bin/env docker run --rm --name fluentd \
      --log-driver none \
      --network=host \
      -e LOKI_URL=http://127.0.0.1:3100 \
      -v /etc/fluentd/fluent.conf:/fluentd/etc/fluent.conf:ro \
      grafana/fluent-plugin-loki:main

ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker stop fluentd 2>/dev/null'
Restart=always
RestartSec=30
SyslogIdentifier=fluentd

[Install]
WantedBy=multi-user.target
WantedBy=docker.service
EOF

systemctl daemon-reload \
  && systemctl start alertmanager prometheus loki fluentd \
  && systemctl enable alertmanager prometheus loki fluentd

sudo -u postgres psql -c 'create role vagrant with superuser login'
sudo -u postgres psql -c 'create database vagrant owner vagrant'

echo "Generating SSH Keys for vagrant user..."
sudo -u vagrant ssh-keygen -b 2048 -t rsa -f /home/vagrant/.ssh/id_rsa -q -C "vagrant" -N ""
sudo -u vagrant cat /home/vagrant/.ssh/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys

echo "...adding ssh key to authorized_keys..."
mkdir -p /root/.ssh && chmod 700 /root/.ssh
cat /home/vagrant/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

echo "Installing Ruby Version Manager..."
sudo -u vagrant mkdir -p /home/vagrant/.rbenv/plugins
sudo -u vagrant git clone https://github.com/rbenv/ruby-build.git /home/vagrant/.rbenv/plugins/ruby-build
echo "export PATH=/home/vagrant/.rbenv/shims:$PATH" >> /home/vagrant/.profile
echo "export OVERMIND_SOCKET=/home/vagrant/.overmind.sock" >> /home/vagrant/.profile

echo "Installing ruby 2.7 (This may take a few minutes)..."
su - vagrant -c "rbenv install 2.7.5"
su - vagrant -c "rbenv global 2.7.5"

echo "Performing GitHub authentication..."
cat << 'OUTER' > /home/vagrant/gh_auth.sh
#!/bin/bash

if [ -f /home/vagrant/controller/.envrc ]; then
  cd /home/vagrant/controller
  . /home/vagrant/controller/.envrc
  bundle config https://rubygems.pkg.github.com/computestacks $GITHUB_GEM_PULL_USER:$GITHUB_GEM_PULL_TOKEN
  cat << EOF > ~/.gemrc
gem: --no-document
:backtrace: false
:bulk_threshold: 1000
:sources:
- https://rubygems.org/
- https://$GITHUB_GEM_PULL_USER:$GITHUB_GEM_PULL_TOKEN@rubygems.pkg.github.com/computestacks/
:update_sources: true
:verbose: true
EOF
else
  echo "Missing controller .envrc file, skipping github authentication."
fi
OUTER

su - vagrant -c "bash /home/vagrant/gh_auth.sh" && rm /home/vagrant/gh_auth.sh

cat << 'EOF' > /root/calico_net.yml
apiVersion: v1
kind: ipPool
metadata:
  cidr: 10.167.186.0/24
spec:
  nat-outgoing: true
EOF

calicoctl apply -f /root/calico_net.yml

docker network create --driver calico --ipam-driver calico-ipam --subnet=10.167.186.0/24 dev

echo "Provisioning PowerDNS for ComputeStacks..."
pdnsutil create-zone cstacks.local ns1.cstacks.local
pdnsutil add-record cstacks.local @ A 127.0.0.1
pdnsutil add-record cstacks.local ns1 A 127.0.0.1
pdnsutil add-record cstacks.local controller A 127.0.0.1
pdnsutil add-record cstacks.local registry A 127.0.0.1
pdnsutil add-record cstacks.local a A 127.0.0.1
pdnsutil add-record cstacks.local *.a CNAME a.cstacks.local
pdnsutil add-record cstacks.local @ CAA "0 issue \"letsencrypt.org\""
pdnsutil add-record cstacks.local @ CAA "0 issuewild \"letsencrypt.org\""
echo "...loading test domains..."
mv /tmp/cs_pdns_up /usr/local/bin/ \
  && bash /usr/local/bin/cs_pdns_up >/dev/null
