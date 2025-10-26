#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<-EOF_USAGE
	Usage: $(basename "$0") <env-repo-name> [infra-core-path-or-url] [destination_dir]
	
	Creates a fresh environment repository skeleton wired up to the shared infra-core
	code via a git submodule. Specify a local path or Git URL for infra-core.
	EOF_USAGE
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi
DEFAULT_CORE_REPO='https://github.com/tregrum/infra-core'
ENV_REPO_NAME=$1
CORE_SOURCE=${2:-$DEFAULT_CORE_REPO}
DEST_ROOT=${3:-.}

if ! command -v git >/dev/null 2>&1; then
  echo "git is required" >&2
  exit 1
fi

if ! DEST_ROOT_ABS=$(realpath -m "$DEST_ROOT" 2>/dev/null); then
  echo "Unable to resolve destination path: $DEST_ROOT" >&2
  exit 1
fi

ENV_ROOT="$DEST_ROOT_ABS/$ENV_REPO_NAME"

if [[ -e "$ENV_ROOT" ]]; then
  echo "Destination already exists: $ENV_ROOT" >&2
  exit 1
fi

mkdir -p "$ENV_ROOT"
cd "$ENV_ROOT"

git init >/dev/null

mkdir -p inventory/group_vars inventory/host_vars inventory/artifacts/{files,templates} roles .logs

touch inventory/group_vars/.gitkeep inventory/host_vars/.gitkeep .logs/.gitkeep \
      inventory/artifacts/files/.gitkeep inventory/artifacts/templates/.gitkeep roles/.gitkeep

cat <<EOF_README > README.md
# ${ENV_REPO_NAME} Environment Repository

This repo wraps infra-core with inventory, vars, and artifacts specific to ${ENV_REPO_NAME} 
application/environment. Edit `inventory/all.inv`, populate `group_vars/` and
`host_vars/` if needed, then run the wrapper playbook.
EOF_README

cat <<'EOF_CFG' > ansible.cfg
[defaults]
nocows = true
roles = core:roles
interpreter_python = /usr/bin/python3
stdout_callback = yaml
inventory = inventory/all.inv
# user = root
# remote_user = root
retry_files_enabled = False
log_path=.logs/ansible.log
host_key_checking = False
pipelining = True
retries = 2

EOF_CFG

cat <<EOF_PLAY > playbook.yml
#!/usr/bin/env ansible-playbook
---
- name: Application Env Playbook Tasks
  hosts: all
  gather_facts: true
  become: true
  ignore_errors: "{{ ansible_check_mode | default(false) | bool }}"
  roles:
    - core
#   - transfer_agent
#   - additional roles
EOF_PLAY

chmod +x playbook.yml

# ---
# # Wrapper playbook for this environment. Adjust hosts/groups to match your
# # inventory and add additional roles/tasks as needed.
# - hosts: "all"
#   become: true
#   vars:
#     artifacts_root: "{{ inventory_dir }}/artifacts"
#     artifacts_merged: >-
#       {{
#         (artifacts_common | default([]))
#         + (artifacts_env   | default([]))
#         + (artifacts_role  | default([]))
#         + (artifacts_host  | default([]))
#       }}
#     artifact_allowed_ops:
#       - systemd_daemon_reload
#       - systemd_service_enable
#       - firewalld_enable_service
#       - restorecon
#   tasks:
#     - name: Run shared infra-core role
#       import_role:
#         name: core/main
#
#     # Example: append environment-only roles/tasks here
#     # - import_role:
#     #     name: roles/custom

cat <<EOF_INV > inventory/all.inv
# Example base inventory for this environment. Replace with your hosts/groups.
[web]
web1.example.com
EOF_INV

cat <<'EOF_GV' > inventory/group_vars/all.yml
# Shared vars for all hosts in this environment.
---
# Example group variable file illustrating supported configuration knobs

# Root volume fix-up toggle
# fix_root_pv: false

# Create a sudoers entry granting ALL to this group
# sudoers_group: "sudo_app_admins"

# Outbound mail relay host for postfix
# mail_relay: "mailrelay.example.com"

# Additional search domain to append to ifcfg files on VMware guests
# dns_domain_search: "example.com"

# Desired SELinux state: enforcing|permissive|disabled
# selinux_config: "permissive"

# System timezone identifier
# timezone: "America/Detroit"

# Drop a trusted CA bundle in /etc/pki/ca-trust/source/anchors
# ca_file: "orgca.pem"
# force_orgca: false

# Packages to install/absent via dnf
# packages_installed:
#   - "nginx"
# packages_installed_extra:
#   - "jq"
# packages_uninstalled:
#   - "firewalld"

# Standalone RPM artifacts to install (outside configured repos)
# packages_rpm:
#   - name: "corp-agent"
#     url: "https://packages.example.com/corp-agent-1.2.3.el9.x86_64.rpm"
#     checksum: "sha256:..."
#   - name: "bundled-tool"
#     file: "bundled-tool-0.4.1.el9.x86_64.rpm"
#   - name: "prestage-driver"
#     path: "/opt/rpms/driver.rpm"
#     disable_gpg_check: false
# packages_rpm_staging_dir: "/var/tmp/ansible-rpms"

# Services to toggle via systemd
# services_enabled:
#   - "postfix"
# services_disabled:
#   - "firewalld"

# Firewalld ports to open permanently
# firewall_allow_ports:
#   - "443/tcp"

# Global bash snippets to install into /etc/profile.d
# global_profiles:
#   - "corp_env.sh"

# Manage selinux disabled/enabled toggles per service above

# OS update automation
# updates:
#   install: true
#   schedule: "*-*-16 04:30"
#   reboot: false

# Repository definitions support multiple methods. Example:
# repos_enabled:
#   epel:
#     name: "epel"
#     description: "Extra Packages for Enterprise Linux"
#     baseurl: "https://download.fedoraproject.org/pub/epel/$releasever/Everything/$basearch/"
#     gpg_key:
#       - "https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-{{ ansible_distribution_major_version }}"
#   remi:
#     repo_packages: "https://rpms.remirepo.net/enterprise/remi-release-9.rpm"
#   docker:
#     repo_file_url: "https://download.docker.com/linux/centos/docker-ce.repo"
#     repo_filename: "docker-ce"
#     gpg_key: "https://download.docker.com/linux/centos/gpg"

# LVM data definitions for new volume groups/logical volumes
# volume_groups:
#   data:
#     name: "data"
#     size_gb: 100
# local_mounts:
#   data01:
#     vg: "data"
#     lv: "lvdata01"
#     size: 50    # in GB
#     path: "/mnt/data01"
#     fs: "xfs"
#     fsopts: "noatime"

# Local Unix groups + accounts
# local_groups:
#   appteam:
#     name: "appteam"
#     gid: 2001
# group_members:
#   appteam:
#     - "svc-appdeploy"
# local_accounts:
#   svc-appdeploy:
#     name: "svc-appdeploy"
#     uid: 60010
#     group: "appteam"
#     create_home: false
#     comment: "App deployment account"
#     generate_ssh_key: false

# Local filesystem paths to manage
# local_paths:
#   data_logs:
#     path: "/var/log/app"
#     state: "directory"
#     owner: "root"
#     group: "root"
#     mode: "0750"

# Cron entries to drop in /etc/cron.d
# crontab_entries:
#   nmon:
#     root 0 * * * /usr/bin/nmon -ft > /dev/null 2>&1

# Extra cron files to remove
# crontabs_removed:
#   - "/etc/cron.d/unwanted"
EOF_GV


cat <<'EOF_HV' > inventory/host_vars/.gitkeep
EOF_HV

cat <<'EOF_GITIG' > .gitignore
# Ignore logs, env files, swap files, pycache, and retry files
*.retry
roles/*/
*.swp
.env
.vagrant
*.log
logs/*.log
autoinventory
__pycache__/
*.py[cod]
.ansible
EOF_GITIG

cat <<'EOF_REQ' > roles/requirements.yml
# Example role requirements file. Add additional roles as needed.
---
# - src: git@github.com/transferco/transfer_agent.git
#   scm: git
EOF_REQ


if [[ -d "$CORE_SOURCE" ]]; then
  CORE_ARG=$(realpath "$CORE_SOURCE")
else
  CORE_ARG="$CORE_SOURCE"
fi

git submodule add "$CORE_ARG" core >/dev/null

echo "Created environment repo skeleton at $ENV_ROOT"
echo "Next steps:"
echo "  cd $ENV_ROOT"
echo "  git add ."
echo "  git commit -m 'Initial environment scaffold'"
echo "Install any extra roles:"
echo "  ansible-galaxy role install -r roles/requirements.yml -p roles/"
echo "Check inventory:"
echo "   ansible-inventory --list "
echo "Check playbook target inventory:"
echo "  ./playbook.yml -Cv --list-hosts "
echo "Check task list:"
echo "  ./playbook.yml -Cv --list-tasks "
