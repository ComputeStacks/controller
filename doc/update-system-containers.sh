cat << 'EOF' > /root/update-images.sh
#!/bin/bash
docker pull cmptstks/borg:stable
docker pull cmptstks/mariadb-backup:10.2
docker pull cmptstks/mariadb-backup:10.3
docker pull cmptstks/mariadb-backup:10.4
docker pull cmptstks/mariadb-backup:10.5
docker pull cmptstks/mariadb-backup:10.6
docker pull cmptstks/xtrabackup:2.4
docker pull cmptstks/xtrabackup:8.0
EOF

bash /root/update-images.sh
