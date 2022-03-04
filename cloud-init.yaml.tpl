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
- crudini

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
- path: /etc/systemd/system/node_exporter.service
  defer: true
  content: |-
    [Unit]
    Description=Prometheus Node Exporter
    Wants=network-online.target
    After=network-online.target
    [Service]
    User=root
    Group=root
    Type=simple
    ExecStart=/usr/bin/node_exporter
    [Install]
    WantedBy=multi-user.target
- path: /etc/systemd/system/postgres_exporter.service
  defer: true
  content: |-
    [Unit]
    Description=Prometheus Postgres Exporter
    Wants=network-online.target
    After=network-online.target
    [Service]
    User=postgres
    Group=postgres
    Type=simple
    Environment="DATA_SOURCE_NAME=user=postgres host=/var/run/postgresql/ sslmode=disable"
    ExecStart=/usr/bin/postgres_exporter --auto-discover-databases
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
        - 'k8s.prometheus.mcswain.dev:443'
      scheme: https
      basic_auth:
        username: 'prometheus'
        password: '${prometheus_federation_password}'
    - job_name: grafana
      static_configs:
      - targets:
        - 'localhost:3000'
      scheme: https
    - job_name: node
      static_configs:
      - targets:
        - 'localhost:9100'
    - job_name: postgres
      static_configs:
      - targets:
        - 'localhost:9187'
- path: /etc/grafana-prometheus.yaml
  content: |-
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      access: proxy
      url: http://localhost:9090
      isDefault: true
      version: 1
      editable: false
      jsonData:
        timeInterval: 5s

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
  - [ sudo, -i, -u, postgres, --, psql, -c, "CREATE ROLE grafana ENCRYPTED PASSWORD '${postgres_grafana_password}' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT LOGIN;"]
  - [ sudo, -i, -u, postgres, --, psql, -c, "CREATE DATABASE grafana OWNER grafana;"]
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
  - cp /tmp/prometheus-2.33.4.linux-amd64/prometheus /usr/bin
  - cp /tmp/prometheus-2.33.4.linux-amd64/promtool /usr/bin/
  - cp -r /tmp/prometheus-2.33.4.linux-amd64/consoles /etc/prometheus
  - cp -r /tmp/prometheus-2.33.4.linux-amd64/console_libraries /etc/prometheus
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
  - systemctl stop grafana-server
  - mv /etc/grafana-prometheus.yaml /etc/grafana/provisioning/datasources/prometheus.yaml
  - chown grafana:grafana /etc/grafana/provisioning/datasources/prometheus.yaml
  - crudini --set /etc/grafana/grafana.ini paths data /data/grafana
  - crudini --set /etc/grafana/grafana.ini security secret_key '${grafana_secret_key}'
  - crudini --set /etc/grafana/grafana.ini security cookie_secure true
  - crudini --set /etc/grafana/grafana.ini security cookie_samesite strict
  - crudini --set /etc/grafana/grafana.ini users allow_sign_up false
  - crudini --set /etc/grafana/grafana.ini users allow_org_create false
  - crudini --set /etc/grafana/grafana.ini auth disable_login_form true
  - crudini --set /etc/grafana/grafana.ini auth disable_signout_menu true
  - crudini --set /etc/grafana/grafana.ini 'auth.anonymous' enabled true
  - crudini --set /etc/grafana/grafana.ini 'auth.anonymous' org_role Admin
  - crudini --set /etc/grafana/grafana.ini 'auth.basic' enabled false
  - crudini --set /etc/grafana/grafana.ini 'auth.jwt' enabled false
  - crudini --set /etc/grafana/grafana.ini smtp enabled true
  - crudini --set /etc/grafana/grafana.ini smtp host email.mcswain.dev:465
  - crudini --set /etc/grafana/grafana.ini smtp user grafana
  - crudini --set /etc/grafana/grafana.ini smtp password '${grafana_smtp_password}'
  - crudini --set /etc/grafana/grafana.ini smtp from_address 'grafana@mcswain.dev'
  - crudini --set /etc/grafana/grafana.ini smtp from_name Grafana
  - crudini --set /etc/grafana/grafana.ini smtp startTLS_policy NoStartTLS
  - crudini --set /etc/grafana/grafana.ini database type postgres
  - crudini --set /etc/grafana/grafana.ini database host localhost:5432
  - crudini --set /etc/grafana/grafana.ini database name grafana
  - crudini --set /etc/grafana/grafana.ini database user grafana
  - crudini --set /etc/grafana/grafana.ini database password '${postgres_grafana_password}'
  - chown -R grafana:grafana /data/grafana
  - systemctl start grafana-server
  - wget -O /tmp/node_exporter.tgz https://github.com/prometheus/node_exporter/releases/download/v1.3.1/node_exporter-1.3.1.linux-amd64.tar.gz
  - sh -c 'cd /tmp && tar xvfz node_exporter.tgz'
  - cp /tmp/node_exporter-1.3.1.linux-amd64/node_exporter /usr/bin/node_exporter
  - rm -rf /tmp/node_exporter-1.3.1.linux-amd64 /tmp/node_exporter.tgz
  - systemctl enable --now node_exporter
  - wget -O /tmp/postgres_exporter.tgz https://github.com/prometheus-community/postgres_exporter/releases/download/v0.10.1/postgres_exporter-0.10.1.linux-amd64.tar.gz
  - sh -c 'cd /tmp && tar xvfz postgres_exporter.tgz'
  - cp /tmp/postgres_exporter-0.10.1.linux-amd64/postgres_exporter /usr/bin/postgres_exporter
  - rm -rf /tmp/postgres_exporter-0.10.1.linux-amd64 /tmp/postgres_exporter.tgz
  - systemctl enable --now postgres_exporter

bootcmd:
  - 'mdadm --assemble /dev/md0 /dev/nvme0n1p1 /dev/nvme1n1p1'
  - 'mount /backup'

