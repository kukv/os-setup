# macOS 実機を mac-setup → os-setup へ移行する runbook

WSL で先行運用していた os-setup を、macOS 実機でも [`kukv/mac-setup`](https://github.com/kukv/mac-setup) から置き換えるための手順。
tart VM（macOS 26.5）でクリーン導入と「mac-setup 適用済みからの移行」を検証した結果に基づく（検証日: 2026-07-14）。

---

## 前提理解：何が衝突するか

os-setup と mac-setup は責務が重なり、同じパス・同じ launchd ラベル体系を使う。VM で実測した衝突は以下。

### os-setup が綺麗に乗っ取る（`chezmoi apply --force` が既存ファイルをエラーなく上書き）

`~/.zshrc` / `~/.zprofile` / `~/.gitconfig` / `~/.ssh/config` / `~/.ssh/allowed_signers` / `~/.config/mise/config.toml`

→ mac-setup が直書きしていたこれらは chezmoi 版に置換される。**dotfiles の手動削除は不要。**

### os-setup が掃除しない＝手動撤去が必要な残置

| 残置物 | 影響 |
| --- | --- |
| **launchd `com.kukv.mac-setup` / `com.kukv.mac-setup-log-rotation`** | os-setup は旧 agent を消さない。放置すると週次で mac-setup を ansible-pull し直し、dotfiles を chezmoi から奪い返す。**最優先で撤去。** |
| `~/.zshenv`（+ `~/.zshenv.generated` / `~/.zshenv.user`） | chezmoi 管理外で残置し、古い env を source し続ける。 |
| `~/.local/bin/mac-setup-pull.sh` / `mac-setup-log-rotation.sh` | 孤立スクリプト。 |
| `~/.oh-my-zsh` | mac-setup が clone。dotfiles 側も一部 vendor するため中途半端に重複。 |
| `~/Library/Application Support/iTerm2/DynamicProfiles/default_profile.json` | 孤立プロファイル。 |
| `~/.local/etc/mac-setup.env` | token 移行後は不要。 |

---

## 事前対応（os-setup 側・実機実行前に済ませる）

VM 検証で見つかった、実機でも踏みうる 2 件。

### Finding #1（os-setup 側は修正済み）: Homebrew tap-trust で tart 導入が失敗
`packages` role が `cirruslabs/cli/tart` を導入する際、依存 `softnet` が現行 Homebrew の tap-trust により untrusted tap として拒否され、**`packages` role ごと失敗＝playbook 全体が中断**する。

- **os-setup:** `packages/tasks/Darwin.yaml` に「Trust the cirruslabs/cli tap」タスク（`brew trust cirruslabs/cli`）を追加済み。最新の main を使えば対応不要（VM で untrusted 状態から green を確認）。
- **mac-setup（ロールバック時）:** mac-setup main は未修正のため、切り戻す場合は事前に手動で `brew trust cirruslabs/cli` が必要。

### Finding #2: mise install が GitHub API レート制限で失敗
`mise install` が未認証 GitHub API のレート制限（403）で失敗する。GitHub token があれば回避できる（scope なしの PAT で十分）。token は `~/.local/etc/os-setup.env` に置く（下記「設定ファイル」参照。既存 `~/.local/etc/mac-setup.env` の値を流用してよい）。

**注意（初回実行の落とし穴）**: macOS の `init.sh` は `--extra-vars @extra_vars.yaml` を渡すだけで **`os-setup.env` を source しない**（source するのは定期実行の `os-setup-pull.sh` のみ）。そのため **初回の `init.sh` 実行前に手動で os-setup.env を source** しないと、この初回 run で mise がレート制限に当たる。手順は下記「移行手順」step 4 参照。

### Finding #3（os-setup 側で対応済み）: pkg/sudo 形式の cask は自動対象外
`zoom` / `microsoft-office` / `onedrive` / `cloudflare-warp` / `logi-options+` は pkg/installer 形式で導入に `sudo` が必要。非対話の `ansible-pull` では `sudo` がパスワードを聞けず（`sudo: a terminal is required`）失敗するため、**cask 管理リストから外した**（手動導入。README「手動管理アプリ」参照）。

### 既存アプリの adopt に注意（App Management）
手動導入済みのアプリ（例: Docker）を os-setup の cask が引き継ぐ（adopt）際、macOS の **App Management 保護**により root でも `/Applications/*.app` の改変が拒否され失敗することがある（`xattr ... Operation not permitted`）。対処: System Settings → Privacy & Security → **App Management**（＋ Full Disk Access）に実行中のターミナルを追加し、対象アプリを終了してから `brew install --cask <name> --adopt`。

---

## 設定ファイル（macOS）

移行手順の前に 2 ファイルを用意する。

### `~/.local/etc/extra_vars.yaml`

```yaml
---
git:
  user:
    name: "あなたの実名"
    email: "you@example.com"
  use_1password: true   # 1Password で SSH認証・コミット署名する実機は true。
                        # ローカルSSH鍵で署名するなら false（必要なら signing_key_file: も指定）
```

- 必須は `git.user.name` / `git.user.email`（playbook が assert）。
- `github_token` はここに書かない（macOS は os-setup.env 側）。`provisioning_schedule` は WSL 専用で不要。

### `~/.local/etc/os-setup.env`（`chmod 0600`）

```bash
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
HOMEBREW_GITHUB_API_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
MISE_GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

- 3 つとも同じ token で可。mise / Homebrew の API レート制限緩和用なので scope なし PAT で十分。

---

## 移行手順

```bash
# 0) 事前対応
#    - Finding #1: os-setup は修正済み（最新 main を使う）
#    - Finding #2: step 1 で os-setup.env を用意し、step 4 で source する

# 1) 設定ファイルを用意（上記「設定ファイル」節参照）
mkdir -p ~/.local/etc
$EDITOR ~/.local/etc/extra_vars.yaml     # git identity + use_1password
$EDITOR ~/.local/etc/os-setup.env        # GITHUB_TOKEN 等
chmod 0600 ~/.local/etc/os-setup.env

# 2) バックアップ（保険）
mkdir -p ~/migrate-backup
cp -a ~/.zshrc ~/.zprofile ~/.zshenv ~/.gitconfig ~/.ssh/config \
      ~/.config/mise/config.toml ~/migrate-backup/ 2>/dev/null

# 3) 旧 mac-setup スケジューラを先に止める（dotfiles 奪い合いの防止）
UID_N=$(id -u)
launchctl bootout gui/$UID_N/com.kukv.mac-setup 2>/dev/null
launchctl bootout gui/$UID_N/com.kukv.mac-setup-log-rotation 2>/dev/null
rm -f ~/Library/LaunchAgents/com.kukv.mac-setup*.plist

# 4) os-setup を適用
#    ★ 初回は os-setup.env を先に source する（init.sh は自動で読まない → mise のレート制限回避）
set -a; source ~/.local/etc/os-setup.env; set +a
curl -sf https://raw.githubusercontent.com/kukv/os-setup/refs/heads/main/init.sh | zsh

# 5) 検証
launchctl list | grep kukv          # os-setup の 2 本だけになっているか
mise --version && chezmoi --version
git config --get gpg.ssh.program     # 1Password 署名が効くか

# 6) 残置物の掃除
rm -f ~/.zshenv ~/.zshenv.generated ~/.zshenv.user     # chezmoi 版 .zshrc/.zprofile に一本化
rm -f ~/.local/bin/mac-setup-pull.sh ~/.local/bin/mac-setup-log-rotation.sh
rm -f ~/Library/Application\ Support/iTerm2/DynamicProfiles/default_profile.json
rm -f ~/.local/etc/mac-setup.env     # token を os-setup.env に移した後
# ~/.oh-my-zsh は dotfiles の zsh 構成を確認してから判断（不要なら rm -rf）
```

---

## ロールバック

問題が起きた場合:

1. os-setup の launchd を撤去: `launchctl bootout gui/$(id -u)/com.kukv.os-setup{,-log-rotation}` → `rm ~/Library/LaunchAgents/com.kukv.os-setup*.plist`
2. `~/migrate-backup/` から dotfiles を戻す。
3. mac-setup を再適用: `curl -sf https://raw.githubusercontent.com/kukv/mac-setup/main/init.sh | zsh`
   （※ Finding #1 の tart tap-trust は mac-setup 側にも影響するため、`brew trust cirruslabs/cli` が必要）

---

## 検証の詳細（参考）

tart VM での検証手順は `test/`（`test/Makefile`, `test/run-in-vm.sh`）参照。

- **Phase 1（クリーン導入）**: os_base / packages機構 / chezmoi / launchd すべて green を確認。
  `chezmoi apply` は `use_1password: true` でも（VM に 1Password 不在でも）成功。
- **Phase 2（移行）**: mac-setup main を適用して footprint を作り、その上に os-setup を適用。
  上記の「乗っ取り」と「残置」を sha256 比較・`launchctl list` で実測確認。
