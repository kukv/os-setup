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
`mise install` が未認証 GitHub API のレート制限（403）で失敗する。token があれば回避できる。

- 実機実行前に `~/.local/etc/os-setup.env` に `github_token`（`GITHUB_TOKEN`）を用意する。
  既存の `~/.local/etc/mac-setup.env` の値を流用してよい。

---

## 移行手順

```bash
# 0) 事前対応
#    - Finding #1: os-setup は修正済み（最新 main を使う）
#    - Finding #2: ~/.local/etc/os-setup.env に github_token を用意

# 1) バックアップ（保険）
mkdir -p ~/migrate-backup
cp -a ~/.zshrc ~/.zprofile ~/.zshenv ~/.gitconfig ~/.ssh/config \
      ~/.config/mise/config.toml ~/migrate-backup/ 2>/dev/null

# 2) 旧 mac-setup スケジューラを先に止める（dotfiles 奪い合いの防止）
UID_N=$(id -u)
launchctl bootout gui/$UID_N/com.kukv.mac-setup 2>/dev/null
launchctl bootout gui/$UID_N/com.kukv.mac-setup-log-rotation 2>/dev/null
rm -f ~/Library/LaunchAgents/com.kukv.mac-setup*.plist

# 3) os-setup を適用
curl -sf https://raw.githubusercontent.com/kukv/os-setup/refs/heads/main/init.sh | zsh

# 4) 検証
launchctl list | grep kukv          # os-setup の 2 本だけになっているか
mise --version && chezmoi --version
git config --get gpg.ssh.program     # 1Password 署名が効くか

# 5) 残置物の掃除
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
