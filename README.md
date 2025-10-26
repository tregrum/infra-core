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
- LVM provisioning: volume groups, logical volumes, filesystem creation, and mounts
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

### Customizing Profiles

`profile_managed_files` now merges `profile_managed_files_common` (baseline entries) with `profile_managed_files_bespoke`. Override either list—or replace the merged variable entirely—when you need host-, role-, or environment-specific shells and dotfiles. Templates continue to support both inline `content` and `src` pointers.

## Worfklow

### Bootstrap a new appenv repo

1. Download the bootstrap script.

```bash
curl -SsO https://raw.githubusercontent.com/tregrum/infra-core/refs/heads/main/files/new-infra-env.sh
```

2. Review and customize any details for your environment.

3. Boostrap new infra-<appenv> repo

```bash
new-infra-env.sh infra-appenv-123
```

### Updating infra-core dev repo

```bash
cd /path/to/infra-core
git add .
git commit -m'a new commit'
git push origin main
git tag v1.2.0
git push origin main --tags
```

### Updating infra-<appenv> to newer infra-core version

```bash
cd /path/to/infra-appenv-123
cd core && git fetch && git checkout v1.2.0
cd .. && git add core && git commit -m "Update infra-core to v1.2.0"
```
