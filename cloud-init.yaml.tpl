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
- postgresql
- qemu-guest-agent

write_files:
- path: /etc/postgresql/12/main/conf.d/custom.conf
  content: |-
    listen_addresses = '0.0.0.0'
    superuser_reserved_connections = 3
    password_encryption = scram-sha-256
    ssl = off
  owner: 'postgres:postgres'
  permissions: '0755'
  defer: true
- path: /etc/postgresql/12/main/pg_hba.conf
  content: |-
    host    all             all             0.0.0.0/0               scram-sha-256
    host    all             all             ::0/0                   scram-sha-256
  append: true
  defer: true

fs_setup:
  - device: /dev/vdb
    partition: 1
    filesystem: ext4

disk_setup:
  /dev/vdb:
    table_type: gpt
    layout: True
    overwrite: True

mounts:
- [ /dev/vdb, /data, "auto", "defaults", "0", "0" ]

runcmd:
  - [ mkdir, /data ]
  - [ chown, postgres:postgres, /data ]
  - [ chmod, 755, /data ]
  - [ sudo, -i, -u, postgres, --, psql, -c, "CREATE ROLE k3s ENCRYPTED PASSWORD '${postgres_k3s_password}' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT LOGIN;"]
  - [ sudo, -i, -u, postgres, --, psql, -c, "CREATE DATABASE kubernetes OWNER k3s;"]
  - [ sudo, -i, -u, postgres, --, psql, -c, "CREATE ROLE admin ENCRYPTED PASSWORD '${postgres_admin_password}' NOCREATEDB SUPERUSER INHERIT LOGIN;"]
  - [ systemctl, daemon-reload ]
  - [ systemctl, enable, --now, qemu-guest-agent.service ]
  - [ systemctl, enable, postgresql.service ]
  - [ systemctl, stop, postgresql.service ]
  - [ systemctl, restart, postgresql.service ]
