#cloud-config

package_update: true
package_upgrade: true

packages:
- postgresql
- qemu-guest-agent

runcmd:
  - [ systemctl, daemon-reload ]
  - [ systemctl, enable, --now, qemu-guest-agent.service ]

%{if length(ssh_authorized_keys) > 0 }
ssh_authorized_keys:
%{for line in ssh_authorized_keys}
- ${line}
%{endfor}
%{endif}
