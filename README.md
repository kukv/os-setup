# os-setup

WSL2 (Ubuntu) と macOS を **単一の Ansible コードベース**でプロビジョニングするリポジトリです。
1 つの playbook が 4 つの role を実行し、各 role が `ansible_os_family`（`Debian` / `Darwin`）で OS 分岐します。

`~/` 配下の設定ファイル実体（zsh / git / neovim / mise など）は
[`kukv/dotfiles`](https://github.com/kukv/dotfiles) が **chezmoi** で管理します。
os-setup は **OS 設定 + ツール導入 + オーケストレーション + 定期実行** に専念します。

---

## インストール・設定される機能

- **OS 基盤**
  - WSL: 日本語 locale、`wsl.conf`、NTP（JST）、DNS、デフォルトシェル zsh、Homebrew 導入
  - macOS: Homebrew の更新
- **開発ツール**
  - `mise`（言語・CLI ツール一式）/ `chezmoi`（dotfiles 適用）
  - WSL: Ruby ビルド依存、ARM クロスコンパイル toolchain
  - macOS: Homebrew formulae / casks（GUI アプリ含む）、Mac App Store アプリ（`mas`）、Claude Code CLI
- **dotfiles 適用** — `chezmoi` で `kukv/dotfiles` を展開（mise の設定・zsh・git・Claude/Codex 設定 等）
- **定期プロビジョニング** — `ansible-pull` を WSL は systemd timer、macOS は launchd で定期実行

> **手動管理（自動化対象外）のアプリ**: LocalStack Desktop は Homebrew cask / Mac App Store のいずれでも配布されていないため、必要に応じて手動でインストールする。

---

## 事前準備：変数ファイル

git identity などを extra_vars に置きます。配置場所は OS で異なります。

- **WSL**: `/etc/ansible/extra_vars.yaml`
- **macOS**: `~/.local/etc/extra_vars.yaml`（秘密 token は別途 `~/.local/etc/os-setup.env`, `0600`）

```yaml
---
# mise の GitHub API rate limit 緩和（任意。空でも動作するがレート制限あり）
# ※ macOS では os-setup.env 側に置く（os-setup.env.example 参照）
github_token: ""

# 定期プロビジョニングの間隔（systemd-timer の OnCalendar 書式 / WSL）
provisioning_schedule: "weekly"

# git identity（chezmoi data 経由で ~/.gitconfig に反映）
git:
  user:
    name: "Your Name"
    email: "you@example.com"
    signing_key: ""   # macOS のみ（1Password の SSH 公開鍵）。WSL は空で可
```

サンプル: [`extra_vars.yaml.example`](extra_vars.yaml.example) / [`os-setup.env.example`](os-setup.env.example)

---

## 使い方

`init.sh` は自身が `ansible-pull` でこのリポジトリを取得して実行します。事前 clone は不要です。

### WSL2 (Ubuntu)

`<user>` は事前に作成済みのプロビジョニング用ユーザー。**root で実行**します。

```bash
curl -sf https://raw.githubusercontent.com/kukv/os-setup/refs/heads/main/init.sh | bash -s -- --user <user>
```

実行後、**WSL2 を再起動**してください（PowerShell で `wsl --shutdown` → 再度開く。`wsl.conf` の systemd 設定反映のため）。

### macOS

事前に Xcode Command Line Tools が必要です（`xcode-select --install`）。

```bash
curl -sf https://raw.githubusercontent.com/kukv/os-setup/refs/heads/main/init.sh | zsh
```

### `init.sh` のオプション

| オプション | 説明 |
| --- | --- |
| `-u`, `--user <user>` | （WSL 必須）プロビジョニング用ユーザー |
| `-b`, `--branch <branch>` | 使用する git ブランチ（既定: `main`） |
| `-h`, `--help` | ヘルプ表示 |

---

## dotfiles との責務分担

| | 担当 |
| --- | --- |
| **os-setup**（このリポ） | OS 設定、Homebrew / mise / chezmoi 導入、`chezmoi apply` と `mise install` の順序保証、定期実行 |
| [**kukv/dotfiles**](https://github.com/kukv/dotfiles) | `~/` 配下の設定（zsh / git / neovim / mise config / oh-my-zsh など）を chezmoi で管理 |

`tools` role が両者を繋ぐ中核で、git identity を chezmoi data に注入 →
`chezmoi init --apply kukv/dotfiles` → `mise install` の順を保証します。

---

## 定期プロビジョニング

両 OS とも `ansible-pull` でこのリポジトリを定期的に再適用します。

- **WSL**: systemd timer `os-setup.timer`（間隔は `provisioning_schedule`、既定 `weekly`）
  - ログ: `/var/log/ansible/ansible-pull.log`
- **macOS**: launchd `com.kukv.os-setup`（週次）+ ログローテーション用エージェント
  - ログ: `~/.local/log/ansible/`

---

## 開発・テスト

- **WSL / Debian パス**
  - lint: `docker compose run --rm dev ansible-lint`
  - フル実行（mock コンテナ）: `docker compose up -d --build mock` → `make play`
- **macOS / Darwin パス**: `test/run-in-vm.sh`（tart VM、`test/Makefile` 参照）
- CI: PR で shellcheck / yamllint / ansible-lint が走ります。

---

## アーキテクチャ（開発者向け）

単一 playbook が `gather_facts` 後に 4 role を順に実行します。各 role は `main.yaml` で
`include_tasks: "{{ ansible_os_family }}.yaml"` により OS 分岐します。

| Role | Debian (WSL) | Darwin (macOS) |
| --- | --- | --- |
| `os_base` | apt 基盤、`wsl.conf`、locale、NTP、DNS、デフォルトシェル、Homebrew 導入 | Homebrew 更新 |
| `packages` | mise + chezmoi（brew）、Ruby ビルド依存、ARM toolchain | mise + chezmoi、brew formulae/casks、Claude Code CLI |
| `tools` | chezmoi apply → mise install → go/corepack（共通） | 同じ共通オーケストレーション |
| `scheduler` | systemd timer (`os-setup.timer`) | launchd LaunchAgent (`com.kukv.os-setup`) |

```
ansible/
├── playbook.yaml              # 単一エントリ（4 role）
├── inventories/               # hosts / group_vars
├── tasks/                     # galaxy collection 導入
└── roles/
    ├── os_base/   {Debian,Darwin}.yaml + templates(wsl.conf 等)
    ├── packages/  {Debian,Darwin}.yaml
    ├── tools/     main.yaml + templates/chezmoi.toml.j2
    └── scheduler/ {Debian,Darwin}.yaml + templates(systemd/launchd)
```
