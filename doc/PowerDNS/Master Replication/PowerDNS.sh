#! /bin/bash
#
set -e

export DEBIAN_FRONTEND=noninteractive
export DEBUG_OUTPUT=/tmp/base_installation.log

function installnoninteractive
{
   bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -q -y $* >> $DEBUG_OUTPUT"
}

function update_datetime
{
  echo "Configure TimeZone"
  echo "UTC" > /etc/timezone
  dpkg-reconfigure -f noninteractive tzdata
  service cron restart
}

function install_base
{
  echo "PowerDNS Installation..."
  echo "...Installing Base Packages..."
  installnoninteractive ntp \
                        build-essential \
                        software-properties-common \
                        vim \
                        libevent1-dev \
                        libncurses5-dev \
                        python-software-properties \
                        unzip \
                        zip \
                        pwgen \
                        sysstat \
                        wget \
                        curl \
                        apt-transport-https \
                        ca-certificates

  echo "Configure Sysstat"
  sed -i "s/^ENABLED=.*/ENABLED='true'/g" /etc/default/sysstat
  service sysstat restart
  echo "Configure vim"
  echo "syntax on" >> /etc/vim/vimrc
  service ntp restart
}

function install_tmux
{
  if ! type "tmux" > /dev/null; then
    echo "Installing tmux"
    cd /usr/src
    wget https://github.com/tmux/tmux/releases/download/2.3/tmux-2.3.tar.gz
    tar -xzvf tmux*gz
    cd tmux*
    ./configure && make
    sudo make install
  fi
  echo "Install tmux config"
  curl https://storage.googleapis.com/cstacks/provision_assets/tmux.conf > /root/.tmux.conf
}

function base_setup
{
  apt-get update && apt-get -y upgrade
  echo "Setup DateTime"
  update_datetime
  install_base
  install_tmux
}

function pdns_repo
{
  cat<<EOF
deb [arch=amd64] http://repo.powerdns.com/ubuntu xenial-auth-40 main
EOF
}

function pdns_pri
{
  cat<<EOF
Package: pdns-*
Pin: origin repo.powerdns.com
Pin-Priority: 600
EOF
}

function install_pdns
{
  pdns_repo > /etc/apt/sources.list.d/pdns.list
  pdns_pri > /etc/apt/preferences.d/pdns
  curl https://repo.powerdns.com/FD380FBB-pub.asc | sudo apt-key add
  apt-get update
  installnoninteractive build-essential postgresql-9.5 pdns-server pdns-backend-pgsql
  rm /etc/powerdns/bindbackend.conf
  rm /etc/powerdns/pdns.d/pdns.simplebind.conf
  service pdns stop
}

function ssh_config_dns
{
  cat<<EOF

UseDNS no
EOF
}

function configure_ssh
{
  echo "Configure SSH"
  sed -i "s/^X11Forwarding .*/X11Forwarding no/g" /etc/ssh/sshd_config
  sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
  sed -i 's/#PasswordAuthentication .*/PasswordAuthentication no/g' /etc/ssh/sshd_config
  ssh_config_dns >> /etc/ssh/sshd_config
  service ssh restart
}

function cleanup
{
  echo "Complete PowerDNS Configuration as listed here: https://cs.codebasehq.com/projects/os/notebook/PowerDNS%20Installation.md"
  cat /dev/null > /root/.bash_history
}

base_setup
install_pdns
configure_ssh
cleanup
exit 0
