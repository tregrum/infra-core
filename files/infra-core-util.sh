#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_CORE_REPO_FALLBACK='https://github.com/tregrum/infra-core'

usage() {
  cat <<EOF_USAGE
Usage:
  $(basename "$0") create <env-repo-name> [infra-core-path-or-url] [destination_dir] [ref]
  $(basename "$0") update <ref> [env_repo_dir]
  $(basename "$0") version [env_repo_dir]
  $(basename "$0") help

Commands:
  create   Create a fresh environment repository scaffold with infra-core as a submodule.
  update   Fetch and checkout a requested ref inside the existing core submodule.
  version  Show the current core submodule commit and nearest tag/ref context.
  help     Show this help text.

Notes:
  - create defaults infra-core source to this repo's origin fetch URL when available
  - create fallback core source is: ${DEFAULT_CORE_REPO_FALLBACK}
  - update and version operate on the current directory unless env_repo_dir is provided
  - update never commits changes; it prints suggested next steps instead
EOF_USAGE
}

require_git() {
  if ! command -v git >/dev/null 2>&1; then
    echo "git is required" >&2
    exit 1
  fi
}

default_core_repo() {
  local script_repo_root
  script_repo_root=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)

  if [[ -n "$script_repo_root" ]]; then
    git -C "$script_repo_root" remote get-url origin 2>/dev/null || echo "$DEFAULT_CORE_REPO_FALLBACK"
  else
    echo "$DEFAULT_CORE_REPO_FALLBACK"
  fi
}

resolve_path() {
  local path_arg=$1
  if ! realpath -m "$path_arg" 2>/dev/null; then
    echo "Unable to resolve path: $path_arg" >&2
    exit 1
  fi
}

ensure_env_repo() {
  local env_dir=$1
  if [[ ! -d "$env_dir/.git" ]]; then
    echo "Not a git repository: $env_dir" >&2
    exit 1
  fi
  if [[ ! -d "$env_dir/core/.git" && ! -f "$env_dir/core/.git" ]]; then
    echo "No core submodule found under: $env_dir/core" >&2
    exit 1
  fi
}

core_describe() {
  local env_dir=$1
  git -C "$env_dir/core" describe --tags --always --dirty 2>/dev/null \
    || git -C "$env_dir/core" rev-parse --short HEAD
}

create_env_repo() {
  local env_repo_name=${1:-}
  local core_source=${2:-$(default_core_repo)}
  local dest_root=${3:-.}
  local requested_ref=${4:-}
  local dest_root_abs env_root core_arg

  if [[ -z "$env_repo_name" ]]; then
    usage >&2
    exit 1
  fi

  dest_root_abs=$(resolve_path "$dest_root")
  env_root="$dest_root_abs/$env_repo_name"

  if [[ -e "$env_root" ]]; then
    echo "Destination already exists: $env_root" >&2
    exit 1
  fi

  mkdir -p "$env_root"
  cd "$env_root"

  git init >/dev/null

  mkdir -p inventory/group_vars inventory/host_vars inventory/artifacts/{files,templates} roles .logs

  touch inventory/group_vars/.gitkeep inventory/host_vars/.gitkeep .logs/.gitkeep \
        inventory/artifacts/files/.gitkeep inventory/artifacts/templates/.gitkeep roles/.gitkeep

  cat <<EOF_README > README.md
# ${env_repo_name} Environment Repository

This repo wraps infra-core with inventory, vars, and artifacts specific to ${env_repo_name}
application/environment. Edit \`inventory/all.inv\`, populate \`group_vars/\` and
\`host_vars/\` if needed, then run the wrapper playbook.
EOF_README

  cat <<'EOF_CFG' > ansible.cfg
[defaults]
nocows = true
roles = core:roles
interpreter_python = /usr/bin/python3
stdout_callback = default
callback_result_format = yaml
callback_format_pretty = true
callback_result_indentation = 4
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

# Artifact deployment examples
# artifacts_common:
#   - type: copy_set
#     name: "profile snippets"
#     src_dir: "etc_profile.d"
#     dest_dir: "/etc/profile.d"
#     owner: "root"
#     group: "root"
#     mode: "0644"
#     files:
#       - "corp_env.sh"
#       - "java_env.sh"
#       - "proxy.sh"
#   - type: copy_tree
#     name: "app seed"
#     src_dir: "app/abc"
#     dest_dir: "/var/app"
#     owner: "appuser"
#     group: "appgrp"
#     mode: "0640"
#     dir_mode: "0750"

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
#   reboot: "when-needed"   # never, when-changed, when-needed

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
# network_mounts:
#   shared_apps:
#     src: "nfs-server.example.com:/exports/apps"
#     path: "/srv/apps"
#     fs: "nfs"
#     fsopts: "defaults,_netdev,nofail"
# nfs_exports:
#   apps_export:
#     path: "/srv/apps"
#     clients:
#       - "10.10.0.0/16(rw,sync,no_root_squash)"
#       - "192.168.50.10(ro,sync)"
#
# Optional /etc/dnf/dnf.conf package excludes
# dnf_conf_excludepkgs:
#   - "kernel*"
#   - "kmod-*"

# Local Unix groups + accounts
# local_groups_enforce_gid: false
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
# local_path_sets:
#   app_logs:
#     owner: "root"
#     group: "root"
#     mode: "0750"
#     paths:
#       - "/var/log/app"
#       - "/var/log/app/archive"
#       - "/var/log/app/import"
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

  if [[ -d "$core_source" ]]; then
    core_arg=$(realpath "$core_source")
  else
    core_arg="$core_source"
  fi

  git submodule add "$core_arg" core >/dev/null

  if [[ -n "$requested_ref" ]]; then
    git -C core fetch --tags --all >/dev/null 2>&1 || git -C core fetch --tags >/dev/null 2>&1
    git -C core checkout "$requested_ref" >/dev/null
  fi

  echo "Created environment repo skeleton at $env_root"
  if [[ -n "$requested_ref" ]]; then
    echo "Checked out core ref: $requested_ref"
  fi
  echo "Next steps:"
  echo "  cd $env_root"
  echo "  git status"
  echo "  git add ."
  echo "  git commit -m 'Initial environment scaffold'"
  echo "Install any extra roles:"
  echo "  ansible-galaxy role install -r roles/requirements.yml -p roles/"
  echo "Check inventory:"
  echo "  ansible-inventory --list"
  echo "Check playbook target inventory:"
  echo "  ./playbook.yml -Cv --list-hosts"
  echo "Check task list:"
  echo "  ./playbook.yml -Cv --list-tasks"
}

show_version() {
  local env_dir=${1:-.}
  local env_dir_abs

  env_dir_abs=$(resolve_path "$env_dir")
  ensure_env_repo "$env_dir_abs"

  echo "Environment repo: $env_dir_abs"
  echo "core commit: $(git -C "$env_dir_abs/core" rev-parse --short HEAD)"
  echo "core version: $(core_describe "$env_dir_abs")"
  echo "parent status:"
  git -C "$env_dir_abs" status --short core || true
}

update_core() {
  local requested_ref=${1:-}
  local env_dir=${2:-.}
  local env_dir_abs before_ref after_ref

  if [[ -z "$requested_ref" ]]; then
    usage >&2
    exit 1
  fi

  env_dir_abs=$(resolve_path "$env_dir")
  ensure_env_repo "$env_dir_abs"

  before_ref=$(core_describe "$env_dir_abs")
  git -C "$env_dir_abs/core" fetch --tags --all >/dev/null 2>&1 || git -C "$env_dir_abs/core" fetch --tags >/dev/null 2>&1
  git -C "$env_dir_abs/core" checkout "$requested_ref" >/dev/null
  after_ref=$(core_describe "$env_dir_abs")

  echo "Updated core in: $env_dir_abs"
  echo "Previous core ref: $before_ref"
  echo "Current core ref:  $after_ref"
  echo "Suggested next steps:"
  echo "  cd $env_dir_abs"
  echo "  git status"
  echo "  git diff --submodule"
  echo "  git add core"
  echo "  git commit -m \"Update core to $after_ref\""
}

main() {
  local command=${1:-}

  require_git

  case "$command" in
    create)
      shift
      create_env_repo "${1:-}" "${2:-$(default_core_repo)}" "${3:-.}" "${4:-}"
      ;;
    update)
      shift
      update_core "${1:-}" "${2:-.}"
      ;;
    version)
      shift
      show_version "${1:-.}"
      ;;
    help|-h|--help)
      usage
      ;;
    "")
      usage
      echo
      if [[ -d ./core ]]; then
        show_version .
      fi
      ;;
    *)
      echo "Unknown command: $command" >&2
      echo >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
