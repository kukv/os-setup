# os-setup

Unified provisioning for **WSL2 (Ubuntu)** and **macOS** with a single Ansible
codebase. One playbook runs four concern-scoped roles, each branching internally
on `ansible_os_family` (`Debian` / `Darwin`).

## Responsibility split

`os-setup` handles **OS provisioning + tool bootstrap + orchestration + scheduling**.
Actual dotfiles (zsh, git, neovim, mise config, …) live in
[`kukv/dotfiles`](https://github.com/kukv/dotfiles) and are applied by **chezmoi**.

| Role        | Debian (WSL)                                   | Darwin (macOS)                                |
| ----------- | ---------------------------------------------- | --------------------------------------------- |
| `os_base`   | apt base pkgs, wsl.conf, locale, NTP, DNS, default shell, Homebrew bootstrap | Homebrew update/upgrade |
| `packages`  | mise + chezmoi (brew), ruby build deps, ARM toolchain | mise + chezmoi, brew formulae/casks, Claude Code CLI |
| `tools`     | chezmoi apply → mise install → go/corepack (shared) | same shared orchestration |
| `scheduler` | systemd timer (`os-setup.timer`)               | launchd LaunchAgent (`com.kukv.os-setup`)     |

The `tools` role is the core: it seeds chezmoi data (git identity), runs
`chezmoi init --apply kukv/dotfiles` (which lays down the mise config), then
`mise install`, then default Go packages and `corepack enable`.

## Usage

### WSL2 (Ubuntu)

```bash
# <user> must already exist
sudo bash init.sh -u <user> [-b <branch>]
```

`init.sh` configures passwordless sudo, installs ansible/git via apt, then runs
`ansible-pull` as `<user>`. Provide secrets/vars in `/etc/ansible/extra_vars.yaml`
(see `extra_vars.yaml.example`).

### macOS

```bash
# Xcode Command Line Tools required first: xcode-select --install
zsh init.sh [-b <branch>]
```

`init.sh` installs Homebrew + ansible if needed, then runs `ansible-pull`.
- Git identity / non-secret vars → `~/.local/etc/extra_vars.yaml`
- Secret tokens → `~/.local/etc/os-setup.env` (mode `0600`, see `os-setup.env.example`)

## Variables

See `extra_vars.yaml.example`. Git identity uses the nested form
`git.user.{name,email,signing_key}` (flows into chezmoi data → `~/.gitconfig`).
`signing_key` is macOS-only (1Password SSH agent); leave empty on WSL.

## Scheduling

Both platforms re-run `os-setup` periodically via `ansible-pull`:
- **WSL**: `os-setup.timer` (systemd), schedule via `provisioning_schedule` (default `weekly`).
- **macOS**: `com.kukv.os-setup` LaunchAgent (weekly), plus a log-rotation agent.

## Testing

- **WSL / Debian path**: `docker compose run --rm dev ansible-lint` (lint) and
  `docker compose run --rm mock` (full run in a mock container).
- **macOS / Darwin path**: `test/run-in-vm.sh` (tart VM).
