# Corosync Configuration

Place holder page with general notes on managing Corosync / Pacemaker.


Create the interface with: `pcs resource create VIP ocf:heartbeat:IPaddr2 ip=185.63.155.17 cidr_netmask=24`


From another file, I have the following notes:

```bash
pcs property set stonith-enabled=false
pcs property set no-quorum-policy=ignore

pcs resource create VIP IPaddr2 ip=212.114.110.211 cidr_netmask=23

pcs resource create haproxy ocf:heartbeat:haproxy binpath=/usr/sbin/haproxy conffile=/etc/haproxy/haproxy.cfg op monitor interval=10s

pcs resource group add HAproxyGroup VIP haproxy

pcs constraint order VIP then haproxy
```
