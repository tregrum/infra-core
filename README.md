---

# Infra-Core Ansible Repo

This repository contains an opinionated “common baseline” role for RHEL-compatible hosts. It manages OS packages, repositories, storage, local accounts, cron jobs, and other day-two settings through a single inventory-driven interface.

## Repository Layout

- `defaults/main.yml` – baseline variables
- `tasks/` – modular task sets (services, storage, accounts, etc.)
- `files/` & `templates/` – assets copied to managed hosts

## Usage

## Key Capabilities

- Package lifecycle management (`packages_installed`, `packages_installed_extra`, `packages_uninstalled`) plus ad-hoc RPM staging via `packages_rpm`
- Service enable/disable and SELinux state toggling
- Yum/DNF repository enablement supporting release RPMs, `.repo` downloads, or inline definitions
- Automated updates via `dnf-automatic` with optional reboot scheduling
- `dnf.conf` tuning including optional `excludepkgs`
- LVM provisioning: volume groups, logical volumes, filesystem creation, and mounts
- Remote filesystem mounts via `network_mounts` (for example NFS)
- NFS server exports via `nfs_exports`
- Local groups/accounts, sudoers entries, and filesystem path management
- Cron job enforcement via `/etc/cron.d`
- System profile customization (MOTD, root dotfiles, profile snippets)

## Customizing Repositories

Define entries under `repos_enabled` using whichever combination fits:

- Provide `gpg_key` (string or list) to trust a key URL/file
- Supply `repo_packages` to install release RPMs (e.g., Remi)
- Set `repo_file_url` (and optional `repo_filename`) to fetch a `.repo` file
- Use `baseurl`, `name`, and `description` for inline `yum_repository` definitions

The role normalizes these options so you can mix approaches per repository.

### Installing Standalone RPMs

Define `packages_rpm` entries when software is not available via enabled repositories. Every item supports the usual `state`, `disable_gpg_check`, and `validate_certs` toggles, plus these source types:

- `url`: installs directly via `dnf` from HTTP/HTTPS without staging. TLS verification follows `validate_certs`.
- `artifact`: points at an RPM stored under `{{ artifacts_root }}/rpms` (override `packages_rpm_artifact_src`). The role copies it into `packages_rpm_remote_cache` (default `/var/cache/infra-core/rpms`) or the optional `remote_path`, then installs locally. `filename`, `mode`, and `checksum` still apply.
- `file`: reuses a file shipped with this role under `files/`, following the same copy-and-install flow as artifacts.
- `path`: references an RPM that already exists on the managed host.

Drop files into whichever layer fits (inventory artifacts, per-role files, or an existing path) and mix URL installs alongside them in the same list.

### Deploying Artifacts

Use the existing flat `copy`, `template`, `directory`, `link`, `sync`, and `archive` artifact entries for one-off items. When you have a small cluster of files that all share the same source directory, target directory, and ownership/mode, use `copy_set` to keep `group_vars` compact. When you need to copy a whole directory tree, use `copy_tree`.

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

### Storage Mounts

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

### Managing Local Paths

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

### Automated Updates

When enabling `dnf-automatic`, set `updates.reboot` to the native config value you want written into `automatic.conf`:

```yaml
updates:
  install: true
  schedule: "*-*-16 04:30"
  reboot: "when-needed" # never, when-changed, when-needed
```

### Customizing Profiles

`profile_managed_files` now merges `profile_managed_files_common` (baseline entries) with `profile_managed_files_bespoke`. Override either list—or replace the merged variable entirely—when you need host-, role-, or environment-specific shells and dotfiles. Templates continue to support both inline `content` and `src` pointers.

## Worfklow

### Bootstrap a new environment repo

Assumes you have ansible & git installed.

1. Copy `new-infra-env.sh` into a new folder
2. Optionally review and edit script env items
3. Run bootstrap script: `new-infra-env.sh infra-app-abc123`
4. Customize environment hostnames `inventory/all.inv`
5. Customize environment variable `inventory/group_vars/all.yml`
6. Run ansible playbook: `./playbook.yml`

### Updating infra-core

```bash
cd /path/to/infra-core
git add .
git commit -m'a new commit'
git push origin main
git tag v1.3.0
git push origin main --tags
```

### Updating infra-<abc123

```bash
cd /path/to/infra-<abc123>
cd core && git fetch && git checkout v1.3.0
cd .. && git add core && git commit -m "Update infra-core to v1.3.0"
```


