# WSL / ネイティブLinux 設定分離 設計

- 日付: 2026-07-08
- ステータス: Approved（実装計画待ち）
- 対象リポジトリ: `jp.kukv/os-setup`

## 背景

現状このリポジトリは `ansible_os_family == "Debian"` を暗黙に **WSL** と等価に扱っており、
ネイティブLinux（非WSLのUbuntu/Debian）との区別がほとんど付けられていない。
近くネイティブLinux機を導入予定のため、設定を

1. **WSL専用**（ネイティブでは不要／有害）
2. **Linux共通**（WSL・ネイティブ兼用）
3. **ネイティブLinux専用**（現状ゼロ、将来追加）

の3バケツに分けて管理できる構造へ組み替える。

### 現状のWSL固有処理（棚卸し結果）

| 設定 | 場所 | 現状のゲート | 判定 |
|---|---|---|---|
| `wslu` インストール | `os_base/tasks/wsl_configuration.yaml` | バージョンのみ (`< 26.04`)。WSL判定なし | WSL専用（誤ゲート） |
| `/etc/wsl.conf` 作成 | `os_base/tasks/wsl_configuration.yaml` + `templates/wsl.conf.j2` | **ゲートなし**（Debianなら常時） | WSL専用（誤ゲート） |
| `/etc/resolv.conf` を uplink へ貼り替え | `os_base/tasks/dns_resolver_configuration.yaml` | `'microsoft' in kernel` で正しくゲート済み | WSL専用 |

## 目的 / ゴール

- WSL専用処理を `is_wsl` で正しくゲートし、ネイティブLinux機で同じ playbook を流したとき
  WSL固有設定（`wsl.conf`, `wslu`）が**実行されない**状態を今のうちに作る。
- 各ロールに WSL／ネイティブ専用処理の**明示的な置き場所**を用意し、将来の追加を容易にする。
- WSL実機の実効挙動は変えない（元々WSL前提のため）。

## 決定事項（確定済み）

1. **目的**: 構造分離 ＋ 現状の誤ゲート修正。
2. **ネイティブOS**: Ubuntu/Debian系（`os_family == "Debian"`）。よってWSLとネイティブは
   `Debian.yaml` の中で `is_wsl` により分岐する。
3. **粒度**: 案B-2 = Debian系の全ロール（`os_base` / `packages` / `scheduler`）を
   一律で「共通 + `wsl.yaml` + `linux_native.yaml`」の三点セットに統一。
4. **ネイティブ専用ファイル名**: `linux_native.yaml`。
5. **WSL経路のテスト**: `Makefile` に `make play-wsl`（`is_wsl` を強制上書き）を追加。

## スコープ

**対象**: `ansible/roles/{os_base,packages,scheduler}` の Debian パス、`group_vars/all.yaml`、
`Makefile`、`README.md`。

**対象外**:
- `tools` ロール — `Debian.yaml` を持たず、`brew_bin_dir` でOS差を吸収する完全共通処理。分岐不要。
- macOS (`Darwin.yaml`) パス全般。
- ネイティブ専用タスクの中身の実装（本設計ではプレースホルダのみ用意。実機導入時に別途）。

## 設計詳細

### 1. 判定変数（`group_vars/all.yaml`）

既存の `brew_bin_dir`（`os_family` で分岐する計算変数）と同じ流儀で追加する。

```yaml
# WSL vs native-Linux detection. WSL2 kernels carry "microsoft" in the release
# string; native Ubuntu/Debian does not. Override via extra_vars (JSON form,
# e.g. '{"is_wsl": true}') to force a path in tests.
is_wsl: "{{ 'microsoft' in ansible_facts.kernel | lower }}"
is_linux_native: "{{ ansible_facts.os_family == 'Debian' and not is_wsl }}"
```

- `is_wsl` / `is_linux_native` は排他。`when: is_wsl` / `when: is_linux_native` で対称に振り分ける。
- extra_vars は最優先のため、テスト時に `is_wsl` を強制できる。
- 既存の `dns_resolver_configuration.yaml` にあったインライン判定
  `'microsoft' in ansible_facts.kernel | lower` はこの変数へ集約する。

### 2. ディレクトリ構造（三分割）

各Debian系ロールで **`Debian.yaml`（Linux共通のオーケストレータ）** の末尾に
`is_wsl` / `is_linux_native` の dispatch を置き、`wsl.yaml` / `linux_native.yaml` へ委譲する。

```
os_base/tasks/
  main.yaml                        # 変更なし: include {{ os_family }}.yaml
  Darwin.yaml                      # 変更なし
  Debian.yaml                      # 共通 + 末尾で wsl/native を dispatch
  wsl.yaml                         # WSL専用（旧 wsl_configuration.yaml を改名・集約）
  linux_native.yaml                # ネイティブ専用（プレースホルダ）
  lang_locale_configuration.yaml   # 共通（据え置き）
  time_locale_configuration.yaml   # 共通（据え置き）
  dns_resolver_configuration.yaml  # 共通DNSブロックのみ（symlink を wsl.yaml へ移動）
  change_default_terminal.yaml     # 共通（据え置き）
  homebrew_bootstrap.yaml          # 共通（据え置き）
  templates/wsl.conf.j2            # 変更なし

packages/tasks/
  main.yaml                        # 変更なし
  Darwin.yaml                      # 変更なし
  claude.yaml                      # 変更なし
  Debian.yaml                      # 共通(Ruby/ARM) + 末尾で dispatch
  wsl.yaml                         # 空プレースホルダ
  linux_native.yaml                # 空プレースホルダ

scheduler/tasks/
  main.yaml                        # 変更なし
  Darwin.yaml / darwin_*.yaml      # 変更なし
  debian_setup_log.yaml            # 変更なし（共通）
  Debian.yaml                      # 共通(systemd log/unit/timer) + 末尾で dispatch
  wsl.yaml                         # 空プレースホルダ
  linux_native.yaml                # 空プレースホルダ
```

### 3. dispatch パターン

各 `Debian.yaml` の末尾（共通処理の後）に統一形で追加する。os_base / scheduler は
`become: true` ブロック内に置き、委譲先が特権前提でも動くようにする。

```yaml
- name: "Run WSL-specific <role> configuration"
  ansible.builtin.include_tasks: "wsl.yaml"
  when: is_wsl

- name: "Run native-Linux-specific <role> configuration"
  ansible.builtin.include_tasks: "linux_native.yaml"
  when: is_linux_native
```

### 4. os_base の振り分け（誤ゲート修正込み）

**`os_base/tasks/Debian.yaml`（変更後）** — WSL include を末尾の dispatch に置き換え、
共通処理（特に DNS 設定 + `flush_handlers`）を実行し切った後に WSL 処理を走らせる。

```yaml
---
- name: "Configure OS base (privileged)"
  become: true
  block:
    - name: "Install requirement system packages"
      ansible.builtin.apt:
        name: "{{ requirement_packages }}"
        state: "present"

    - name: "Configure language locale"
      ansible.builtin.include_tasks: "lang_locale_configuration.yaml"

    - name: "Configure time locale"
      ansible.builtin.include_tasks: "time_locale_configuration.yaml"

    - name: "Configure DNS resolver"
      ansible.builtin.include_tasks: "dns_resolver_configuration.yaml"

    - name: "Change default terminal to zsh"
      ansible.builtin.include_tasks: "change_default_terminal.yaml"

    - name: "Run WSL-specific base configuration"
      ansible.builtin.include_tasks: "wsl.yaml"
      when: is_wsl

    - name: "Run native-Linux-specific base configuration"
      ansible.builtin.include_tasks: "linux_native.yaml"
      when: is_linux_native

- name: "Install Homebrew (Linux)"
  ansible.builtin.include_tasks: "homebrew_bootstrap.yaml"
```

**`os_base/tasks/wsl.yaml`（新規 = 旧 `wsl_configuration.yaml` を改名・集約）**
`wsl.conf` は `is_wsl` 配下に入ることで正しくゲートされる。`wslu` は
「WSL かつ `< 26.04`」となる。`dns_resolver_configuration.yaml` にあった
resolv.conf 貼り替えをここへ移動（ファイル自体が `is_wsl` 下なのでインライン判定は不要）。

```yaml
---
- name: "Install WSL utility packages"
  ansible.builtin.apt:
    name:
      - "wslu"
    state: "present"
  when: "ansible_facts.distribution_version is version('26.04', '<')"

- name: "Create /etc/wsl.conf"
  ansible.builtin.template:
    src: "wsl.conf.j2"
    dest: "/etc/wsl.conf"
    owner: "root"
    group: "root"
    mode: "0644"

# On WSL the systemd-resolved stub (127.0.0.53) is taken over by the WSL DNS
# proxy, which breaks name resolution. Bypass the stub by pointing resolv.conf
# at the uplink file that lists the upstream DNS servers directly.
- name: "Point /etc/resolv.conf to systemd-resolved uplink servers"
  ansible.builtin.file:
    src: "../run/systemd/resolve/resolv.conf"
    dest: "/etc/resolv.conf"
    state: "link"
    force: true
    follow: false
```

**`os_base/tasks/dns_resolver_configuration.yaml`（変更後 = 共通DNSブロックのみ）**
symlink タスクを wsl.yaml へ移した残り。`flush_handlers` はここに残し、
共通DNS設定 → systemd-resolved 再起動 → （後続の wsl.yaml で）resolv.conf 貼り替え、の順を保証する。

```yaml
---
- name: "Setup DNS resolver"
  ansible.builtin.blockinfile:
    path: "/etc/systemd/resolved.conf"
    block: |
      DNS=8.8.8.8 1.1.1.1
      FallbackDNS=8.8.4.4 1.0.0.1
    marker: "# {mark} DNS SETUP"
    create: true
    prepend_newline: true
    mode: "0644"
  notify: "Restart systemd-resolved"

- name: "Apply DNS resolver changes before dependent tasks"
  ansible.builtin.meta: "flush_handlers"
```

### 5. プレースホルダの中身

`include_tasks` が空ファイルを引くのを避けるため、プレースホルダは `meta: noop` の
no-op タスク1つを置く（実行時にスキップされず、可視な no-op として残る）。

```yaml
---
# Native-Linux-only (non-WSL Debian/Ubuntu) configuration for the <role> role.
# No native-only tasks yet — placeholder for future additions
# (e.g. NetworkManager/netplan DNS, firmware, desktop packages).
- name: "No native-Linux-specific <role> tasks yet"
  ansible.builtin.meta: "noop"
```

packages / scheduler の `wsl.yaml` も同様の no-op プレースホルダ（現状WSL固有処理なし）。

> 実装時に `ansible-lint` が `meta: noop` を問題視した場合は、コメントのみの空 tasks ファイル、
> または `ansible.builtin.debug` の no-op へフォールバックする（`make check` 通過を優先）。

### 6. packages / scheduler

現状 WSL/ネイティブの分岐は存在しない。共通部（`packages`: Ruby build依存・ARM toolchain、
`scheduler`: systemd log/unit/timer）は各 `Debian.yaml` に残し、末尾に §3 の dispatch を追加。
`wsl.yaml` / `linux_native.yaml` は §5 の no-op プレースホルダ。

### 7. テスト戦略 & ドキュメント

**mock の既定挙動が変わる**: mock コンテナ（`ubuntu:24.04`）のカーネルはDockerホストのものでWSL判定に
かからないため、`is_wsl == false` → mock は**ネイティブLinux経路**をテストする。

- `make play` = ネイティブ経路（`wsl.conf` / `wslu` は実行されない）。
- WSL経路を試すため **`make play-wsl`** を追加：

```makefile
play-wsl:
	$(MOCK_RUN_CONTEXT) \
		sudo -u "$(ANSIBLE_USER)" \
		bash -c "ansible-playbook -i inventories/hosts.yaml playbook.yaml --extra-vars '@/etc/ansible/extra_vars.yaml' --extra-vars 'ansible_user=$(ANSIBLE_USER)' --extra-vars '{\"is_wsl\": true}'"
```

- `is_wsl` の上書きは **JSON形式** (`{"is_wsl": true}`) を使う。`key=value` 形式だと文字列
  `"true"` になり、`"false"` を渡した場合に非空文字列として truthy に評価される罠があるため。
- `play-wsl/%`（タグ指定版）は必要になったら追加。当面は無し（YAGNI）。

**README 更新**:
- 機能一覧／アーキテクチャ表を「WSL / Linux共通 / ネイティブ」の三分割構成に更新。
- 開発・テスト節に `make play-wsl`（WSL経路）を追記。
- playbook 名 `"Unified WSL/macOS setup"` を実態に合わせ更新（例: `"Unified Linux (WSL/native) / macOS setup"`）。

## 挙動の変化

| 環境 | 変更前 | 変更後 |
|---|---|---|
| WSL実機 (`is_wsl=true`) | wslu(<26.04)/wsl.conf/resolv.conf を実行 | **同一**（挙動不変） |
| ネイティブLinux / mock (`is_wsl=false`) | wsl.conf・wslu を**誤って作成/導入** | wsl.conf・wslu を**実行しない**（＝意図した修正）。locale/time/DNSブロック/zsh/Homebrew は共通で継続 |

resolv.conf 貼り替えは変更前からカーネル判定でネイティブ側はスキップ済みのため、実効差分なし。

## 検証計画

1. `make check`（ansible-lint / yamllint / shellcheck）通過。
2. **ネイティブ経路**（mock 既定）: `make play` を2回実行。
   - 2回目 `changed=0`（冪等）。
   - `/etc/wsl.conf` が**作られない**、`wslu` が**入らない**ことを確認。
3. **WSL経路**（強制）: `make play-wsl` を2回実行。
   - 2回目 `changed=0`（冪等）。
   - `/etc/wsl.conf` 作成、`wslu` 導入（24.04 は `<26.04`）、resolv.conf symlink 試行を確認。
   - 注: mock 内では symlink 先 `/run/systemd/resolve/resolv.conf` が無くても
     `state: link, force: true, follow: false` によりダングリングリンクとして作成され冪等。
4. WSL実機での回帰は導入済み環境で `init.sh` 再実行相当（`ansible-pull`）により確認（手動）。

## 非対象・将来課題

- ネイティブ専用タスクの中身（NetworkManager/netplan によるDNS、ファームウェア、
  デスクトップ環境等）は実機導入時に `linux_native.yaml` へ追加。
- `packages` の Ruby build依存 / ARM toolchain は現状「Linux共通」として扱う。
  将来ネイティブで不要と判断すれば `wsl.yaml` へ移す余地あり（本設計では移さない）。
- 共通DNSブロック（`8.8.8.8` 等のハードコード）はネイティブ実機でDHCP配布DNSを使いたい場合に
  再検討の余地あり。本設計では共通のまま維持。
