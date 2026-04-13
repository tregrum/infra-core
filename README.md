# Infra-Core Ansible Repo

This repository contains an opinionated “common baseline” role for RHEL-compatible hosts. It manages OS packages, repositories, storage, local accounts, cron jobs, and other day-two settings through a single inventory-driven interface.

## Repository Layout

- `defaults/main.yml` – baseline variables
- `tasks/` – modular task sets (services, storage, accounts, etc.)
- `files/` & `templates/` – assets copied to managed hosts

## Key Capabilities

- System baseline controls for MOTD, SELinux, timezone, networking, and update posture
- Package lifecycle management (`packages_installed_common`, `packages_installed_bespoke`, `packages_uninstalled_common`, `packages_uninstalled_bespoke`) plus ad-hoc RPM staging via `packages_rpm`
- Yum/DNF repository enablement supporting release RPMs, `.repo` downloads, or inline definitions
- Automated updates via `dnf-automatic` with optional reboot scheduling
- Local groups/accounts, sudoers entries, and service/firewall controls
- LVM provisioning, remote mounts, NFS exports, filesystem paths, and ACLs
- Artifact-driven deployment for files, templates, trees, links, sync, and archives
- User profile customization and cron job enforcement through inventory-driven vars

## Usage

### System Baseline

Use the baseline variables for shared host identity and behavior such as `timezone`, `selinux_config`, `dns_domain_search`, `sudoers_group`, `mail_relay`, and MOTD/profile defaults.

### Packages, Repositories, and Updates

Define entries under `repos_enabled` using whichever combination fits:

- Provide `gpg_key` (string or list) to trust a key URL/file
- Supply `repo_packages` to install release RPMs (e.g., Remi)
- Set `repo_file_url` (and optional `repo_filename`) to fetch a `.repo` file
- Use `baseurl`, `name`, and `description` for inline `yum_repository` definitions

The role normalizes these options so you can mix approaches per repository.

Use `packages_installed_common` for the baseline package set and `packages_installed_bespoke` for env-, role-, or host-specific additions. The merged `packages_installed` list is what the role actually installs. The same layering pattern applies to `packages_uninstalled_common` and `packages_uninstalled_bespoke`.

#### Installing Standalone RPMs

Define `packages_rpm` entries when software is not available via enabled repositories. Every item supports the usual `state`, `disable_gpg_check`, and `validate_certs` toggles, plus these source types:

- `url`: installs directly via `dnf` from HTTP/HTTPS without staging. TLS verification follows `validate_certs`.
- `artifact`: points at an RPM stored under `{{ artifacts_root }}/rpms` (override `packages_rpm_artifact_src`). The role copies it into `packages_rpm_remote_cache` (default `/var/cache/infra-core/rpms`) or the optional `remote_path`, then installs locally. `filename`, `mode`, and `checksum` still apply.
- `file`: reuses a file shipped with this role under `files/`, following the same copy-and-install flow as artifacts.
- `path`: references an RPM that already exists on the managed host.

Drop files into whichever layer fits (inventory artifacts, per-role files, or an existing path) and mix URL installs alongside them in the same list.

#### Automated Updates

When enabling `dnf-automatic`, set `dnf_automatic.reboot` to the native config value you want written into `automatic.conf`:

```yaml
dnf_automatic:
  install: true
  schedule: "*-*-16 04:30"
  # or every 3rd Sunday: schedule: "Sun-*-15..21 04:30"
  reboot: "when-needed" # never, when-changed, when-needed
  # excludepkgs:
  #   - "legacy-runtime*"
  #   - "compat-library*"
```
`dnf_conf_excludepkgs` is the global always-on exclude rule defined in `/etc/dnf/dnf.conf`. `dnf_automatic.excludepkgs` is found in the `[base]` section of `/etc/dnf/automatic.conf`. Its effectively additive to `dnf_conf_excludepkgs`, but only applies to os updates executed by dnf-automatic timer.  Use them when you need a core DNF policy that blocks a small set of packages everywhere, and optionally a narrower automatic-update policy that skips a few more packages during the unattended run.

### Accounts and Access

Local users and groups are driven through `local_groups`, `group_members`, and `local_accounts`. `sudoers_group` can be used for a simple shared administrative sudo rule.

### Storage, Filesystems, Paths, and ACLs

Use `local_mounts` for LVM-backed filesystems managed by this role. Use `network_mounts` for remote filesystems that should be present in `fstab` and mounted, such as NFS exports from another host. Use `nfs_exports` when this host should serve one or more exports itself.

Example:

```yaml
network_mounts:
  shared_apps:
    src: "nfs-server.example.com:/exports/apps"
    path: "/srv/apps"
    fs: "nfs"
    fsopts: "defaults,_netdev,nofail"
    owner: "root"
    group: "root"
    mode: "0755"
```

Use `local_paths` for one-off filesystem paths with bespoke settings. When you need to create several directories with the same owner, group, and mode, use `local_path_sets` to keep the variable file compact.

Example:

```yaml
local_path_sets:
  app_logs:
    owner: "root"
    group: "root"
    mode: "0750"
    paths:
      - "/var/log/app"
      - "/var/log/app/archive"
      - "/var/log/app/import"
```

`local_path_sets` normalizes into ordinary `local_paths` entries during the role run.

For controlled file removals, use `paths_absent_bespoke`. It merges with a small built-in `paths_absent_common` baseline. Entries must be absolute paths, and the role rejects a small set of high-risk root directories. Existing directories are also rejected so this list stays file-oriented.

Example:

```yaml
paths_absent_bespoke:
  - "/etc/cron.d/oldjob"
  - "/etc/motd.d/custom-banner"
```

When you need ACLs beyond basic owner/group/mode, define them under `local_acls`. ACLs run after artifacts and path creation so they act as the final permission layer.

Example:

```yaml
local_acls:
  - path: "/srv/app"
    etype: "group"
    entity: "appops"
    permissions: "rwx"
    default: true
```

Example NFS server export:

```yaml
nfs_exports:
  apps_export:
    path: "/srv/apps"
    clients:
      - "10.10.0.0/16(rw,sync,no_root_squash)"
      - "192.168.50.10(ro,sync)"
    owner: "root"
    group: "root"
    mode: "0755"
```

### Profiles and MOTD

`profile_managed_files` now merges `profile_managed_files_common` (baseline entries) with `profile_managed_files_bespoke`. Override either list, or replace the merged variable entirely, when you need host-, role-, or environment-specific shells and dotfiles. Templates continue to support both inline `content` and `src` pointers.

### Artifacts and Deployed Files

Use the existing flat `copy`, `template`, `directory`, `link`, `sync`, and `archive` artifact entries for one-off items. When you have a small cluster of files that all share the same source directory, target directory, and ownership/mode, use `copy_set` to keep `group_vars` compact. When you need to copy a whole directory tree, use `copy_tree`.

Starter examples:

```yaml
artifacts_common:
  - type: copy
    name: "app config"
    src: "app/app.conf"
    dest: "/etc/app/app.conf"
    owner: "root"
    group: "root"
    mode: "0644"

  - type: template
    name: "app config template"
    src: "app/app.conf.j2"
    dest: "/etc/app/app.conf"
    owner: "root"
    group: "root"
    mode: "0644"

  - type: directory
    name: "app state dir"
    dest: "/var/lib/app"
    owner: "appuser"
    group: "appgrp"
    mode: "0750"

  - type: link
    name: "app shortcut"
    src: "/opt/app/current"
    dest: "/usr/local/bin/app"

  - type: sync
    name: "deploy app tree"
    src_dir: "app/tree"
    dest: "/srv/app"
    rsync_opts:
      - "--exclude=.git"

  - type: archive
    name: "seed archive"
    src: "app/seed.tar.gz"
    dest: "/srv/app"
    strip: 1
```

If a file is a prerequisite for later package or network operations, place it in `artifacts_pre` instead of the normal artifact layers. `artifacts_pre` runs earlier in the role and flushes handlers before package tasks continue.

Example:

```yaml
artifacts_pre:
  - type: copy
    src: "ca/orgca.pem"
    dest: "/etc/pki/ca-trust/source/anchors/orgca.pem"
    owner: "root"
    group: "root"
    mode: "0644"
    force: false
    notify:
      - update_ca_trust
```

For `copy` artifacts, `force: false` gives you seed-only behavior: the role creates the file if it is missing, but does not overwrite an existing destination. The same option is also available for `template` artifacts when you want to seed a rendered file without later overwriting local changes.

Example:

```yaml
artifacts_common:
  - type: copy_set
    name: "profile snippets"
    src_dir: "etc_profile.d"
    dest_dir: "/etc/profile.d"
    owner: "root"
    group: "root"
    mode: "0644"
    files:
      - "corp_env.sh"
      - "java_env.sh"
      - "proxy.sh"
```

`copy_set` normalizes into ordinary `copy` operations during the role run. File names must be relative to `{{ artifacts_root }}/{{ src_dir }}`. For backward compatibility, the role also falls back to `{{ artifacts_root }}/files/{{ src_dir }}` if needed. `dest_dir` must be an absolute path on the managed host.

Example:

```yaml
artifacts_common:
  - type: copy_tree
    name: "app seed"
    src_dir: "app/abc"
    dest_dir: "/var/app"
    owner: "appuser"
    group: "appgrp"
    mode: "0640"
    dir_mode: "0750"
```

`copy_tree` copies the named source directory and its contents into `dest_dir`, so the example above results in `/var/app/abc/...`. Sources are resolved using the same `{{ artifacts_root }}` then `{{ artifacts_root }}/files` fallback pattern as `copy_set`. The copy is additive; it does not prune remote files.

For `template` artifacts, sources now follow the same flat layout convention: the role looks in `{{ artifacts_root }}/...` first and falls back to `{{ artifacts_root }}/templates/...` for backward compatibility. A `.j2` suffix is just a naming convention; `type: template` is what enables Jinja rendering.

Artifact items may also declare `notify` aliases to trigger supported handlers when a file changes:

```yaml
artifacts_common:
  - type: copy
    src: "ca/orgca.pem"
    dest: "/etc/pki/ca-trust/source/anchors/orgca.pem"
    owner: "root"
    group: "root"
    mode: "0644"
    notify:
      - update_ca_trust
```

Built-in aliases include common actions such as `update_ca_trust`, `systemd_daemon_reload`, `reload_firewalld`, `reload_nfs_exports`, `restart_networkmanager`, `restart_postfix`, `restart_rsyslog`, `restart_sssd`, `restart_httpd`, and `restart_nginx`.

Downstream repos can extend the built-in alias map by adding entries to `artifact_notify_map` and defining matching handlers in their own play or companion role:

```yaml
artifact_notify_map:
  restart_myapp: "Restart myapp"
```

### Services and Firewall

Use `services_enabled` and `services_disabled` for basic systemd state management.

For firewalld, `firewall_allow_ports` enables port rules such as `443/tcp`, while `firewall_enable_services` enables service profiles by name, including any custom service XML deployed through artifacts.

When a run deploys a custom firewalld service XML under `/etc/firewalld/services` or `/usr/lib/firewalld/services`, the role reloads firewalld before `firewall_enable_services` is evaluated so the new service can be enabled in the same run.

### Using Ansible Vault

This role does not need any special secret-handling logic. Keep the public variable structure readable in your normal `group_vars` files, and place only the actual secret leaf values in a vaulted file.

Example:

```yaml
# group_vars/all.yml
repo_auth:
  username: "svc_repo"
  password: "{{ vault_repo_auth_password }}"

ldap_bind:
  dn: "CN=svc-ldap,OU=Service Accounts,DC=example,DC=com"
  password: "{{ vault_ldap_bind_password }}"
```

```yaml
# group_vars/vault.yml
vault_repo_auth_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  ...

vault_ldap_bind_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  ...
```

That pattern keeps inventory data approachable for other operators while still protecting the values that actually need encryption.

## Workflow

### Updating infra-core

```bash
cd /path/to/infra-core
git add .
git commit -m "a new commit"
git push origin main
git tag v1.1.1
git push origin main --tags
```

### Updating infra-<my_env>

```bash
cd /path/to/infra-<my_env>
./core/files/infra-core-util.sh update v1.1.1 .
git status
git diff --submodule
git add core
git commit -m "Update infra-core to v1.1.1"
```

### Creating infra-<my_env>

```bash
/path/to/infra-core/files/infra-core-util.sh create infra-my-env [/path/to/infra-core or url] [/path/to/workdir] [v1.1.1]
cd /path/to/workdir/infra-my-env
git status
git add .
git commit -m "Initial environment scaffold"
```
