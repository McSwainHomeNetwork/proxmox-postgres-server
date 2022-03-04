#cloud-config

%{if length(ssh_authorized_keys) > 0 }
ssh_authorized_keys:
%{for line in ssh_authorized_keys}
- ${line}
%{endfor}
%{endif}

package_update: true
package_upgrade: true

packages:
- nfs-client
- postgresql
- qemu-guest-agent
- apt-transport-https
- software-properties-common

write_files:
- path: /etc/postgresql/12/main/conf.d/custom.conf
  content: |-
    listen_addresses = '0.0.0.0'
    superuser_reserved_connections = 3
    password_encryption = scram-sha-256
    ssl = off
    data_directory = '/data/postgres'
  owner: 'postgres:postgres'
  permissions: '0755'
  defer: true
- path: /etc/postgresql/12/main/pg_hba.conf
  content: |-
    host    all             all             0.0.0.0/0               scram-sha-256
    host    all             all             ::0/0                   scram-sha-256
  append: true
  defer: true
- path: /var/spool/cron/crontabs/postgres
  defer: true
  content: "*/30 * * * * sh -c 'pg_dumpall -c --if-exists | gzip -9 > /backup/pg-$(date +\"\\%Y_\\%m_\\%d_\\%I_\\%M_\\%p\").sql.gz'\n"
  owner: 'postgres:crontab'
  permissions: '0600'
- path: /etc/systemd/system/prometheus.service
  defer: true
  content: |-
    [Unit]
    Description=Prometheus
    Wants=network-online.target
    After=network-online.target
    [Service]
    User=prometheus
    Group=prometheus
    Type=simple
    ExecStart=/usr/bin/prometheus \
        --config.file /etc/prometheus/prometheus.yml \
        --storage.tsdb.path /data/prometheus/ \
        --web.console.templates=/etc/prometheus/consoles \
        --web.console.libraries=/etc/prometheus/console_libraries
    [Install]
    WantedBy=multi-user.target
- path: /etc/prometheus/prometheus.yml
  defer: true
  owner: 'prometheus:prometheus'
  content: |-
    global:
      scrape_interval: 5s
    scrape_configs:
    - job_name: kubernetes
      honor_labels: true
      metrics_path: '/federate'
      params:
        'match[]':
        - '{job="prometheus"}'
        - '{__name__=~"job:.*"}'
      static_configs:
      - targets:
        - 'https://k8s.prometheus.mcswain.dev'
      basic_auth:
        username: 'prometheus'
        password: '${prometheus_federation_password}'
- path: /etc/grafana/provisioning/datasources/prometheus.yml
  defer: true
  owner: 'grafana'
  content: |-
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      access: direct
      url: http://localhost:9090
      isDefault: true
      version: 1
      editable: false

mounts:
- [ UUID=59bd7786-1525-4ce2-b618-a804ca9d4741, /data, "xfs", "defaults", "1", "0" ]
- [ 192.168.1.135:/mnt/data/backups/Homelab/pgdump, /backup, "nfs", "nfsvers=4.1,noatime", "0", "0" ]

runcmd:
  - 'mdadm --assemble /dev/md0 /dev/nvme0n1p1 /dev/nvme1n1p1'
  - [ systemctl, daemon-reload ]
  - [ systemctl, stop, postgresql.service ]
  - [ mkdir, -p, /data/postgres ]
  - [ chown, -R, postgres:postgres, /data ]
  - [ mkdir, -p, /backup ]
  - [ mount, /backup ]
  - [ systemctl, enable, --now, postgresql.service ]
  - [ sudo, -i, -u, postgres, --, psql, -c, "CREATE ROLE k3s ENCRYPTED PASSWORD '${postgres_k3s_password}' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT LOGIN;"]
  - [ sudo, -i, -u, postgres, --, psql, -c, "CREATE DATABASE kubernetes OWNER k3s;"]
  - [ sudo, -i, -u, postgres, --, psql, -c, "CREATE ROLE vaultwarden ENCRYPTED PASSWORD '${postgres_vaultwarden_password}' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT LOGIN;"]
  - [ sudo, -i, -u, postgres, --, psql, -c, "CREATE DATABASE vaultwarden OWNER vaultwarden;"]
  - [ sudo, -i, -u, postgres, --, psql, -c, "CREATE ROLE keycloak ENCRYPTED PASSWORD '${postgres_keycloak_password}' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT LOGIN;"]
  - [ sudo, -i, -u, postgres, --, psql, -c, "CREATE DATABASE keycloak OWNER keycloak;"]
  - [ sudo, -i, -u, postgres, --, psql, -c, "CREATE ROLE admin ENCRYPTED PASSWORD '${postgres_admin_password}' NOCREATEDB SUPERUSER INHERIT LOGIN;"]
  - [ systemctl, restart, postgresql.service ]
  - [ systemctl, enable, --now, qemu-guest-agent.service ]
  - useradd --no-create-home prometheus
  - mkdir -p /data/prometheus
  - mkdir -p /etc/prometheus
  - [ chown, -R, prometheus:prometheus, /data/prometheus ]
  - chown prometheus:prometheus /etc/prometheus.yml
  - wget -O /tmp/prometheus.tgz https://github.com/prometheus/prometheus/releases/download/v2.33.4/prometheus-2.33.4.linux-amd64.tar.gz
  - sh -c 'cd /tmp && tar xvfz prometheus.tgz'
  - sudo cp /tmp/prometheus-2.33.4.linux-amd64/prometheus /usr/bin
  - sudo cp /tmp/prometheus-2.33.4.linux-amd64/promtool /usr/bin/
  - sudo cp -r /tmp/prometheus-2.33.4.linux-amd64/consoles /etc/prometheus
  - sudo cp -r /tmp/prometheus-2.33.4.linux-amd64/console_libraries /etc/prometheus
  - rm -rf /tmp/prometheus-2.33.4.linux-amd64 /tmp/prometheus.tgz
  - [ chown, -R, prometheus:prometheus, /etc/prometheus ]
  - systemctl daemon-reload
  - systemctl enable --now prometheus
  - curl -fSsL https://packages.grafana.com/gpg.key | apt-key add -
  - echo "deb https://packages.grafana.com/oss/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list
  - apt-get update
  - apt-get install -y grafana
  - mkdir -p /data/grafana
  - systemctl enable --now grafana-server

bootcmd:
  - 'mdadm --assemble /dev/md0 /dev/nvme0n1p1 /dev/nvme1n1p1'
  - 'mount /backup'
