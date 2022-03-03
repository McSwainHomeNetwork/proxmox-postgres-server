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

mounts:
- [ UUID=48a3f88e-0d33-41cb-84b9-66fc6db9897b, /data, "xfs", "defaults", "1", "0" ]

runcmd:
  - 'mdadm --assemble /dev/md0 /dev/nvme0n1 /dev/nvme1n1'
  - [ systemctl, daemon-reload ]
  - [ systemctl, stop, postgresql.service ]
  - [ mkdir, -p, /data/postgres ]
  - [ chown, -R, postgres:postgres, /data ]
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

bootcmd:
  - 'mdadm --assemble /dev/md0 /dev/nvme0n1 /dev/nvme1n1'
