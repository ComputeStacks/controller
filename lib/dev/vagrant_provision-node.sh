#!/usr/bin/env bash

set -e

CURRENT_DISTRO=$(lsb_release -i | awk -F"\t" '{print $2}')

hostname csdev
echo "csdev" > /etc/hostname
echo "127.0.0.1 csdev" >> /etc/hosts
echo "export EDITOR=vim" >> /etc/profile
echo "export EDITOR=vim" >> /root/.profile
echo "export EDITOR=vim" >> /home/vagrant/.profile
echo "alias dconsole='docker exec -e COLUMNS=\"\`tput cols\`\" -e LINES=\"\`tput lines\`\" -it'" >> /root/.bashrc
echo "alias dconsole='docker exec -e COLUMNS=\"\`tput cols\`\" -e LINES=\"\`tput lines\`\" -it'" >> /home/vagrant/.bashrc
echo "Defaults:vagrant env_keep += \"EDITOR\"" >> /etc/sudoers.d/vagrant
echo "syntax on" >> /etc/vim/vimrc
apt-get -y remove ufw
apt-get update && apt-get -y upgrade
apt-get -y install apt-utils software-properties-common ca-certificates net-tools curl wget lsb-release iputils-ping vim openssl dnsutils gnupg2 pass traceroute tree iptables jq whois socat git rsync apt-transport-https gnupg-agent prometheus-node-exporter git tmux pwgen

# Distro specific
if [[ "${CURRENT_DISTRO}" == 'Ubuntu' ]]; then
  install -m 0755 -d /etc/apt/keyrings

  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  fi
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

  add-apt-repository -y ppa:vbernat/haproxy-2.8

else # Debian

  if [[ ! -f /usr/share/keyrings/docker-archive-keyring.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --batch --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  fi

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

  if [[ ! -f /usr/share/keyrings/haproxy.debian.net.gpg ]]; then
    curl https://haproxy.debian.net/bernat.debian.org.gpg | gpg --batch --dearmor > /usr/share/keyrings/haproxy.debian.net.gpg
  fi

  echo deb "[signed-by=/usr/share/keyrings/haproxy.debian.net.gpg]" http://haproxy.debian.net bookworm-backports-2.8 main > /etc/apt/sources.list.d/haproxy.list

fi

## End distro-specific

apt-get update
apt-get -y install docker-ce docker-ce-cli containerd.io haproxy=2.8.\*

mkdir -p /etc/systemd/system/docker.service.d
cat << 'EOF' > /etc/systemd/system/docker.service.d/startup.conf
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H unix:// -H tcp://0.0.0.0:2376 --icc=false --userland-proxy=false
TasksMax=infinity
EOF

systemctl daemon-reload && systemctl restart docker

docker volume create consul-data
mkdir -p /etc/consul
cat << 'EOF' > /etc/consul/config.hcl
datacenter = "dev"
client_addr = "0.0.0.0"
ui_config{
  enabled = true
}
bind_addr = "127.0.0.1"
acl{
  enabled = true
  default_policy = "allow"
  enable_token_persistence = true
}
data_dir = "/consul/data"
bootstrap_expect = 1
server = true
EOF

cat << 'EOF' > /etc/systemd/system/consul.service
[Unit]
Description=Consul
Requires=docker.service
After=docker.service
DefaultDependencies=no

[Service]
Type=simple
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker kill consul 2>/dev/null'
ExecStartPre=-/usr/bin/env sh -c '/usr/bin/env docker rm consul 2>/dev/null'

ExecStart=/usr/bin/env docker run --rm --name consul \
      --log-driver=none \
      --network=host \
      --label com.computestacks.role=system \
      -v consul-data:/consul/data \
      -v /etc/consul:/consul/config \
      hashicorp/consul:1.16 consul agent -config-file=/consul/config/config.hcl

ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker kill consul 2>/dev/null'
ExecStop=-/usr/bin/env sh -c '/usr/bin/env docker rm consul 2>/dev/null'
Restart=always
RestartSec=30
SyslogIdentifier=consul
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
WantedBy=docker.service
EOF

docker pull hashicorp/consul:1.16
systemctl daemon-reload \
  && systemctl enable consul \
  && systemctl start consul

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

echo "Setting up container registry ssl..."
mkdir -p /opt/container_registry/ssl
cat << 'EOF' > /opt/container_registry/ssl/cert.conf
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
C = US
ST = OR
L = Portland
O = CS Customer
OU = Deployment
CN = registry.cstacks.local
EOF
openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -sha256 -keyout /opt/container_registry/ssl/privkey.pem -out /opt/container_registry/ssl/fullchain.pem -config /opt/container_registry/ssl/cert.conf

echo "Setting up haproxy defaults..."
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

systemctl enable prometheus-node-exporter && systemctl start prometheus-node-exporter

wget -O /tmp/cs-agent.tar.gz https://f.cscdn.cc/file/cstackscdn/packages/cs-agent/cs-agent-$(dpkg --print-architecture).tar.gz
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

echo "Allow vagrant user to access docker..."
usermod -aG docker vagrant

CONSUL_HTTP_TOKEN=$(curl -X PUT http://127.0.0.1:8500/v1/acl/bootstrap | jq -r '.SecretID')
export CONSUL_HTTP_TOKEN

echo "export CONSUL_HTTP_TOKEN=$CONSUL_HTTP_TOKEN" >> /home/vagrant/.profile
echo "export CONSUL_HTTP_TOKEN=$CONSUL_HTTP_TOKEN" >> /root/.profile
echo "$CONSUL_HTTP_TOKEN" > /home/vagrant/consul.token && chown vagrant:vagrant /home/vagrant/consul.token

curl -X PUT -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" -H "Content-Type: application/json" --data "{\"Token\": \"$CONSUL_HTTP_TOKEN\"}" http://localhost:8500/v1/agent/token/default

sed -i 's/allow/deny/g' /etc/consul/config.hcl && systemctl restart consul

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
    image: "ghcr.io/computestacks/cs-docker-borg:latest"
    nfs: false
    ssh:
      enabled: false
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
      --label com.computestacks.role=system \
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
      --label com.computestacks.role=system \
      -v prometheus-data:/prometheus \
      -v /etc/prometheus:/etc/prometheus:z \
      prom/prometheus:latest --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=10d --storage.tsdb.wal-compression --web.console.templates=/usr/share/prometheus/consoles --web.console.libraries=/usr/share/prometheus/console_libraries --storage.tsdb.max-block-duration=1d12h

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
      expr: (sum(rate(container_cpu_usage_seconds_total{name!~"alertmanager|consul|loki|loki-logs|cadvisor|portal|prometheus|grafana|vault-bootstrap|nginx|haproxy|"}[3m])) BY (instance, name) * 100) > 95
      for: 1m
      labels:
        severity: warning
      annotations:
        summary: "Container CPU usage (instance {{ $labels.instance }})"
        description: "Container CPU usage is above 95%\n  VALUE = {{ $value }}\n  LABELS: {{ $labels }}"
        value: "{{ $value }}"
    - alert: ContainerMemoryUsage
      expr: (sum(container_memory_usage_bytes{name!~"alertmanager|consul|loki|loki-logs|cadvisor|portal|prometheus|grafana|vault-bootstrap|nginx|haproxy|"}) BY (instance, name) / sum(container_spec_memory_limit_bytes{name!~"alertmanager|consul|loki|loki-logs|cadvisor|portal|prometheus|grafana|vault-bootstrap|nginx|haproxy|"}) BY (instance, name) * 100) > 92
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
      --label com.computestacks.role=system \
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
      --label com.computestacks.role=system \
      -v loki-data:/loki \
      -v /etc/loki/loki-config.yml:/etc/loki/local-config.yaml:z \
      grafana/loki:2.7.3

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
      --label com.computestacks.role=system \
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

echo "Adding vagrant public key to root user"
mkdir -p /root/.ssh && chmod 700 /root/.ssh
cat /home/vagrant/.ssh/authorized_keys >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# IPTable Configuration
if [ -f /usr/local/bin/cs-recover_iptables ]; then
  echo "Existing iptable script is present, skipping iptables configuration."
else
  cat << 'EOF' > /etc/systemd/system/cs-iptables.service
[Unit]
Description=CS Persist IP Tables

[Service]
Type=oneshot
User=root
Group=root
ExecStart=/usr/local/bin/cs-recover_iptables

[Install]
WantedBy=multi-user.target

EOF

  cat << 'EOF' > /usr/local/bin/cs-recover_iptables
#!/usr/bin/env bash
iptables -t nat -N expose-ports
iptables -t nat -A OUTPUT -j expose-ports
iptables -t nat -A PREROUTING -j expose-ports
iptables -N container-inbound
iptables -A FORWARD -j container-inbound

iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT

# For dev, open up...
# ...SSH
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
# ...Docker API
iptables -A INPUT -p tcp --dport 2376 -j ACCEPT
# ...consul UI
iptables -A INPUT -p tcp --dport 8500 -j ACCEPT
# ...prometheus
iptables -A INPUT -p tcp --dport 9090 -j ACCEPT
# ...vagrant default ip range. Adjust as needed
iptables -A INPUT -s 192.168.121.0/24 -j ACCEPT

# Standard CS Ports
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 10000:50000 -j ACCEPT
iptables -A INPUT -p udp --dport 10000:50000 -j ACCEPT

iptables -P INPUT DROP
EOF

  systemctl daemon-reload && systemctl enable cs-iptables.service
  chmod +x /usr/local/bin/cs-recover_iptables && bash /usr/local/bin/cs-recover_iptables
fi

echo "Adding controller ssh key..."
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQo4kmGXgVQMOw7uKVc5mZowf0ZhAXMhqWleYBq1tJ7 controller@dev" >> /home/vagrant/.ssh/authorized_keys
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGQo4kmGXgVQMOw7uKVc5mZowf0ZhAXMhqWleYBq1tJ7 controller@dev" >> /root/.ssh/authorized_keys

echo "Pulling docker images..."
docker pull ghcr.io/computestacks/cs-docker-bastion:latest
docker pull ghcr.io/computestacks/cs-docker-borg:latest
docker pull ghcr.io/computestacks/cs-docker-xtrabackup:2.4
docker pull ghcr.io/computestacks/cs-docker-xtrabackup:8.0

if free | awk '/^Swap:/ {exit !$2}'; then
  echo "Disabling swap"
  swapoff -a
  sed -i '/swap/d' /etc/fstab
  systemctl daemon-reload
fi
