# WSL / ネイティブLinux 設定分離 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Debian系（WSL / ネイティブLinux）のAnsibleタスクを「Linux共通 / WSL専用 / ネイティブ専用」の3バケツに分離し、`is_wsl` 判定で正しく振り分ける。あわせて現状の誤ゲート（`wsl.conf`・`wslu` が非WSLでも実行される）を修正する。

**Architecture:** `group_vars/all.yaml` に計算変数 `is_wsl` / `is_linux_native` を追加。`os_base` / `packages` / `scheduler` の各 `Debian.yaml` を「共通処理 + 末尾で `wsl.yaml` / `linux_native.yaml` を `when:` dispatch」の統一形へ組み替える。WSL専用処理は `wsl.yaml` に集約し、ネイティブ専用は空プレースホルダ `linux_native.yaml` を用意する。

**Tech Stack:** Ansible（community.general 含む）、Docker Compose（`dev`/`mock` コンテナ）、GNU Make。

## Global Constraints

- WSL判定は既存踏襲で **`'microsoft' in ansible_facts.kernel | lower`**（WSL2カーネルは版名に `microsoft` を含む）。新規の判定方式は導入しない。
- WSL実機の**実効挙動は不変**。挙動が変わってよいのは「非WSL（ネイティブ/mock）で `wsl.conf`・`wslu` を実行しなくなる」点のみ。
- 変数上書きは **JSON形式**（`--extra-vars '{"is_wsl": true}'`）。`key=value` 形式は文字列 `"false"` が truthy になる罠があるため使わない。
- lint 3種（ansible-lint / yamllint / shellcheck）を **`make check`** で通す。設定は `ansible/.ansible-lint`。
- `tools` ロールと macOS(`Darwin`) パスは**対象外**（触らない）。
- 対象OSのネイティブは Ubuntu/Debian系（`ansible_os_family == "Debian"`）。
- 参照スペック: `docs/superpowers/specs/2026-07-08-wsl-native-separation-design.md`

## 前提 / 検証環境の準備

lint と mock 実行には Docker が必要。実装開始前に一度だけ：

```bash
make up          # dev + mock コンテナ起動
make install     # dev コンテナへ galaxy collection 導入（ansible-lint の解決に必要）
```

- 各タスクの lint ゲートは `make check`（`docker compose exec dev` 経由）。
- 挙動検証（Task 7）は mock コンテナで実施。mock 用 extra_vars は Task 7 内で用意する。

## File Structure

| ファイル | 責務 | 操作 |
|---|---|---|
| `ansible/inventories/group_vars/all.yaml` | `is_wsl`/`is_linux_native` 判定変数 | Modify |
| `ansible/roles/os_base/tasks/Debian.yaml` | Linux共通os_base + dispatch | Modify |
| `ansible/roles/os_base/tasks/wsl.yaml` | WSL専用os_base（wslu/wsl.conf/resolv.conf） | Create（`wsl_configuration.yaml` を rename+集約） |
| `ansible/roles/os_base/tasks/wsl_configuration.yaml` | 旧WSL設定 | Delete（rename元） |
| `ansible/roles/os_base/tasks/dns_resolver_configuration.yaml` | 共通DNSブロック（symlinkを除去） | Modify |
| `ansible/roles/os_base/tasks/linux_native.yaml` | ネイティブ専用os_base（placeholder） | Create |
| `ansible/roles/packages/tasks/Debian.yaml` | Linux共通packages + dispatch | Modify |
| `ansible/roles/packages/tasks/wsl.yaml` | WSL専用packages（placeholder） | Create |
| `ansible/roles/packages/tasks/linux_native.yaml` | ネイティブ専用packages（placeholder） | Create |
| `ansible/roles/scheduler/tasks/Debian.yaml` | Linux共通scheduler + dispatch | Modify |
| `ansible/roles/scheduler/tasks/wsl.yaml` | WSL専用scheduler（placeholder） | Create |
| `ansible/roles/scheduler/tasks/linux_native.yaml` | ネイティブ専用scheduler（placeholder） | Create |
| `Makefile` | `play-wsl` ターゲット | Modify |
| `ansible/playbook.yaml` | play 名の更新 | Modify |
| `README.md` | 三分割構成の反映 | Modify |

---

### Task 1: 判定変数 `is_wsl` / `is_linux_native` を追加

**Files:**
- Modify: `ansible/inventories/group_vars/all.yaml`

**Interfaces:**
- Produces: グローバル変数 `is_wsl`（bool）, `is_linux_native`（bool）。以降の全タスクの `when:` で参照される。

- [ ] **Step 1: `group_vars/all.yaml` を編集**

ファイル全体を以下にする（既存の `tmp_dir` / `brew_bin_dir` / `brew_bin` は残し、末尾に2変数を追記）：

```yaml
---
tmp_dir: "/tmp"
# Homebrew bin dir (OS-specific; referenced by tools/packages roles)
brew_bin_dir: "{{ '/opt/homebrew/bin' if ansible_facts.os_family == 'Darwin' else '/home/linuxbrew/.linuxbrew/bin' }}"
brew_bin: "{{ brew_bin_dir }}/brew"

# WSL vs native-Linux detection. WSL2 kernels carry "microsoft" in the release
# string; native Ubuntu/Debian does not. Override via extra_vars (JSON form,
# e.g. '{"is_wsl": true}') to force a path in tests.
is_wsl: "{{ 'microsoft' in ansible_facts.kernel | lower }}"
is_linux_native: "{{ ansible_facts.os_family == 'Debian' and not is_wsl }}"
```

- [ ] **Step 2: lint 実行**

Run: `make check`
Expected: PASS（ansible-lint / yamllint / shellcheck すべてエラーなし）

- [ ] **Step 3: 変数が評価できることを確認**

Run:
```bash
docker compose exec mock ansible localhost \
  -i /ansible/inventories/hosts.yaml -c local \
  -m debug -a "msg={{ is_wsl }} / {{ is_linux_native }}"
```
Expected: 実行成功し `ok:` で真偽値2つが表示される（mock は非WSLなので `False / True`）。テンプレートエラーが出ないことが要点。

- [ ] **Step 4: Commit**

```bash
git add ansible/inventories/group_vars/all.yaml
git commit -m "feat: add is_wsl / is_linux_native detection variables"
```

---

### Task 2: os_base を三分割（誤ゲート修正込み）

**Files:**
- Create: `ansible/roles/os_base/tasks/wsl.yaml`（`wsl_configuration.yaml` を rename + resolv.conf symlink を集約）
- Delete: `ansible/roles/os_base/tasks/wsl_configuration.yaml`
- Create: `ansible/roles/os_base/tasks/linux_native.yaml`
- Modify: `ansible/roles/os_base/tasks/dns_resolver_configuration.yaml`（symlink タスクを除去）
- Modify: `ansible/roles/os_base/tasks/Debian.yaml`（WSL include を末尾 dispatch へ）

**Interfaces:**
- Consumes: `is_wsl`, `is_linux_native`（Task 1）。
- Produces: `os_base/tasks/wsl.yaml`, `os_base/tasks/linux_native.yaml`（他ロールと同じ命名規約の起点）。

- [ ] **Step 1: `wsl_configuration.yaml` を `wsl.yaml` へ rename**

```bash
git mv ansible/roles/os_base/tasks/wsl_configuration.yaml ansible/roles/os_base/tasks/wsl.yaml
```

- [ ] **Step 2: `wsl.yaml` を編集（resolv.conf symlink を集約）**

`ansible/roles/os_base/tasks/wsl.yaml` の全内容を以下にする：

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

- [ ] **Step 3: `dns_resolver_configuration.yaml` から symlink タスクを除去**

`ansible/roles/os_base/tasks/dns_resolver_configuration.yaml` の全内容を以下にする（DNSブロックと `flush_handlers` のみ残す）：

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

- [ ] **Step 4: `linux_native.yaml`（placeholder）を作成**

`ansible/roles/os_base/tasks/linux_native.yaml` を新規作成：

```yaml
---
# Native-Linux-only (non-WSL Debian/Ubuntu) base configuration.
# No native-only tasks yet — placeholder for future additions
# (e.g. NetworkManager/netplan DNS, firmware, desktop packages).
- name: "No native-Linux-specific base configuration yet"
  ansible.builtin.meta: "noop"
```

- [ ] **Step 5: `Debian.yaml` を dispatch 形へ書き換え**

`ansible/roles/os_base/tasks/Debian.yaml` の全内容を以下にする（`Configure WSL` include を削除し、共通処理の後＝DNS設定後に dispatch を追加）：

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

- [ ] **Step 6: lint 実行**

Run: `make check`
Expected: PASS。`meta: noop` が ansible-lint に弾かれた場合のみ、`linux_native.yaml` の noop タスクを次へ置換して再実行：
```yaml
- name: "No native-Linux-specific base configuration yet"
  ansible.builtin.debug:
    msg: "No native-Linux-specific base configuration yet"
```

- [ ] **Step 7: 旧ファイル参照が残っていないか確認**

Run: `git grep -n "wsl_configuration"`
Expected: 出力なし（`Debian.yaml` からの参照が消えている）。

- [ ] **Step 8: Commit**

```bash
git add ansible/roles/os_base/tasks/
git commit -m "refactor: split os_base into shared / wsl / native, gate wsl.conf+wslu on is_wsl"
```

---

### Task 3: packages を三分割

**Files:**
- Modify: `ansible/roles/packages/tasks/Debian.yaml`（末尾に dispatch 追加）
- Create: `ansible/roles/packages/tasks/wsl.yaml`（placeholder）
- Create: `ansible/roles/packages/tasks/linux_native.yaml`（placeholder）

**Interfaces:**
- Consumes: `is_wsl`, `is_linux_native`（Task 1）。

- [ ] **Step 1: `packages/tasks/wsl.yaml`（placeholder）を作成**

```yaml
---
# WSL-only package installation for the packages role.
# No WSL-only packages yet — placeholder for future additions.
- name: "No WSL-specific package tasks yet"
  ansible.builtin.meta: "noop"
```

- [ ] **Step 2: `packages/tasks/linux_native.yaml`（placeholder）を作成**

```yaml
---
# Native-Linux-only package installation for the packages role.
# No native-only packages yet — placeholder for future additions.
- name: "No native-Linux-specific package tasks yet"
  ansible.builtin.meta: "noop"
```

- [ ] **Step 3: `packages/tasks/Debian.yaml` に dispatch を追加**

全内容を以下にする（既存の Ruby/ARM 導入は残し、末尾に dispatch）：

```yaml
---
- name: "Install Ruby build prerequisites"
  become: true
  ansible.builtin.apt:
    name: "{{ ruby_build_packages }}"
    state: "present"

- name: "Install ARM cross-compile toolchain"
  become: true
  ansible.builtin.apt:
    name: "{{ arm_cross_packages }}"
    state: "present"

- name: "Run WSL-specific package installation"
  ansible.builtin.include_tasks: "wsl.yaml"
  when: is_wsl

- name: "Run native-Linux-specific package installation"
  ansible.builtin.include_tasks: "linux_native.yaml"
  when: is_linux_native
```

- [ ] **Step 4: lint 実行**

Run: `make check`
Expected: PASS（noop が弾かれた場合は Task 2 Step 6 と同じ debug 置換）。

- [ ] **Step 5: Commit**

```bash
git add ansible/roles/packages/tasks/
git commit -m "refactor: add wsl/native dispatch to packages role"
```

---

### Task 4: scheduler を三分割

**Files:**
- Modify: `ansible/roles/scheduler/tasks/Debian.yaml`（become ブロック内末尾に dispatch）
- Create: `ansible/roles/scheduler/tasks/wsl.yaml`（placeholder）
- Create: `ansible/roles/scheduler/tasks/linux_native.yaml`（placeholder）

**Interfaces:**
- Consumes: `is_wsl`, `is_linux_native`（Task 1）。

- [ ] **Step 1: `scheduler/tasks/wsl.yaml`（placeholder）を作成**

```yaml
---
# WSL-only provisioning-scheduler configuration.
# No WSL-only scheduler tasks yet — placeholder for future additions.
- name: "No WSL-specific scheduler tasks yet"
  ansible.builtin.meta: "noop"
```

- [ ] **Step 2: `scheduler/tasks/linux_native.yaml`（placeholder）を作成**

```yaml
---
# Native-Linux-only provisioning-scheduler configuration.
# No native-only scheduler tasks yet — placeholder for future additions.
- name: "No native-Linux-specific scheduler tasks yet"
  ansible.builtin.meta: "noop"
```

- [ ] **Step 3: `scheduler/tasks/Debian.yaml` に dispatch を追加**

全内容を以下にする（既存の become ブロックの末尾に dispatch を追加）：

```yaml
---
- name: "Configure provisioning scheduler (privileged)"
  become: true
  block:
    - name: "Setup ansible log"
      ansible.builtin.include_tasks: "debian_setup_log.yaml"

    - name: "Create systemd unit files"
      ansible.builtin.template:
        src: "{{ item }}.j2"
        dest: "/etc/systemd/system/{{ item }}"
        owner: "root"
        group: "root"
        mode: "0644"
      with_items:
        - "os-setup.service"
        - "os-setup.timer"
      notify: "Reload systemd"

    - name: "Enable and start provisioning timer"
      ansible.builtin.systemd:
        name: "os-setup.timer"
        enabled: true
        state: "started"

    - name: "Run WSL-specific scheduler configuration"
      ansible.builtin.include_tasks: "wsl.yaml"
      when: is_wsl

    - name: "Run native-Linux-specific scheduler configuration"
      ansible.builtin.include_tasks: "linux_native.yaml"
      when: is_linux_native
```

- [ ] **Step 4: lint 実行**

Run: `make check`
Expected: PASS（noop が弾かれた場合は Task 2 Step 6 と同じ debug 置換）。

- [ ] **Step 5: Commit**

```bash
git add ansible/roles/scheduler/tasks/
git commit -m "refactor: add wsl/native dispatch to scheduler role"
```

---

### Task 5: `make play-wsl` ターゲットを追加

**Files:**
- Modify: `Makefile`（`play` の直後に `play-wsl` を追加）

**Interfaces:**
- Produces: `make play-wsl` — mock で `is_wsl=true` を強制して WSL 経路をテストするターゲット。Task 7 が使用。

- [ ] **Step 1: `Makefile` に `play-wsl` を追加**

既存の `play:` ターゲット定義の直後（`play/%:` の前）に以下を挿入（インデントは**タブ**）：

```makefile
play-wsl:
	$(MOCK_RUN_CONTEXT) \
		sudo -u "$(ANSIBLE_USER)" \
		bash -c "ansible-playbook -i inventories/hosts.yaml playbook.yaml --extra-vars '@/etc/ansible/extra_vars.yaml' --extra-vars 'ansible_user=$(ANSIBLE_USER)' --extra-vars '{\"is_wsl\": true}'"
```

- [ ] **Step 2: Makefile がパースできることを確認**

Run: `make -n play-wsl`
Expected: 実行はせず、展開後のコマンド1行が表示される（`--extra-vars '{"is_wsl": true}'` を含む）。エラーが出ないこと。

- [ ] **Step 3: shellcheck/yaml lint 実行**

Run: `make check`
Expected: PASS（Makefile 変更は lint 対象外だが回帰確認）。

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "test: add make play-wsl target to exercise the WSL path in mock"
```

---

### Task 6: ドキュメント & play 名の更新

**Files:**
- Modify: `ansible/playbook.yaml:2`（play 名）
- Modify: `README.md`（機能一覧・アーキテクチャ表・テスト節）

**Interfaces:**
- Consumes: なし（ドキュメント整合）。

- [ ] **Step 1: playbook 名を更新**

`ansible/playbook.yaml` の2行目を置換：
- 変更前: `- name: "Unified WSL/macOS setup"`
- 変更後: `- name: "Unified Linux (WSL/native) / macOS setup"`

- [ ] **Step 2: README 機能一覧を更新**

`README.md` の「OS 基盤」箇所（現在 15 行目付近）を置換：
- 変更前: `  - WSL: 日本語 locale、`wsl.conf`、NTP（JST）、DNS、デフォルトシェル zsh、Homebrew 導入`
- 変更後（2行）:
```markdown
  - Linux 共通: 日本語 locale、NTP（JST）、DNS、デフォルトシェル zsh、Homebrew 導入
  - WSL のみ: `wsl.conf`、`wslu`（<26.04）、resolv.conf の uplink 貼り替え
```

- [ ] **Step 3: README アーキテクチャ表の os_base 行を更新**

`README.md` のアーキテクチャ表（`| Role | Debian (WSL) | Darwin (macOS) |` の表）の `os_base` 行を置換：
- 変更前: `| `os_base` | apt 基盤、`wsl.conf`、locale、NTP、DNS、デフォルトシェル、Homebrew 導入 | Homebrew 更新 |`
- 変更後: `| `os_base` | apt 基盤、locale、NTP、DNS、シェル、Homebrew（共通）＋ `wsl.conf`/`wslu`/resolv.conf（WSL のみ、`is_wsl` 判定） | Homebrew 更新 |`

- [ ] **Step 4: README にディレクトリツリーの補足を追加**

`README.md` 末尾のディレクトリツリー説明（`os_base/   {Debian,Darwin}.yaml ...` の行付近）の直後に、`is_wsl` による三分割の一文を追記：
```markdown

Debian（Linux）パスは各 role の `Debian.yaml` が共通処理を行い、末尾で
`is_wsl` / `is_linux_native` により `wsl.yaml` / `linux_native.yaml` に分岐します。
`linux_native.yaml` は現状プレースホルダ（ネイティブ Linux 機導入時に追記）。
```

- [ ] **Step 5: README 開発・テスト節に play-wsl を追記**

`README.md` の「開発・テスト」→「WSL / Debian パス」箇所を置換：
- 変更前: `  - フル実行（mock コンテナ）: `docker compose up -d --build mock` → `make play``
- 変更後（2行）:
```markdown
  - フル実行（ネイティブ Linux 経路 / mock 既定）: `docker compose up -d --build mock` → `make play`
  - フル実行（WSL 経路）: `make play-wsl`（`is_wsl=true` を強制。mock はカーネル判定では非 WSL のため）
```

- [ ] **Step 6: lint 実行**

Run: `make check`
Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add ansible/playbook.yaml README.md
git commit -m "docs: reflect wsl/native three-way split in README and play name"
```

---

### Task 7: 統合検証（mock で両経路の冪等性・挙動）

**Files:**
- 変更なし（検証のみ）。必要なら `docker/mock/etc/ansible/extra_vars.yaml`（gitignore 対象）を作成。

**Interfaces:**
- Consumes: Task 1–6 の全成果。

- [ ] **Step 1: mock 用 extra_vars を用意**

```bash
cp docker/mock/etc/ansible/extra_vars.yaml.sample docker/mock/etc/ansible/extra_vars.yaml
```
（既に存在すればスキップ。中身はダミーで可。）

- [ ] **Step 2: mock を作り直して起動**

```bash
make reset       # mock を force-recreate（クリーンな状態から）
```
Expected: mock コンテナが起動する。

- [ ] **Step 3: ネイティブ経路 1回目**

Run: `make play`
Expected: 正常終了（`failed=0`）。`Run WSL-specific ...` 系タスクが `skipping`、`Run native-Linux-specific ...` 系が実行される。

- [ ] **Step 4: ネイティブ経路の挙動を確認（誤ゲート修正の証明）**

Run:
```bash
docker compose exec mock bash -c 'test ! -e /etc/wsl.conf && echo NO_WSL_CONF; dpkg -s wslu >/dev/null 2>&1 && echo WSLU_PRESENT || echo NO_WSLU'
```
Expected: `NO_WSL_CONF` と `NO_WSLU` の両方が出力される（＝非WSLで wsl.conf も wslu も作られない）。

- [ ] **Step 5: ネイティブ経路 2回目（冪等性）**

Run: `make play`
Expected: `changed=0`（PLAY RECAP の changed が 0）。

- [ ] **Step 6: WSL 経路 1回目**

Run: `make play-wsl`
Expected: 正常終了（`failed=0`）。`Run WSL-specific ...` 系が実行され、`Create /etc/wsl.conf` が changed、`Install WSL utility packages` が実行される。

- [ ] **Step 7: WSL 経路の挙動を確認**

Run:
```bash
docker compose exec mock bash -c 'test -e /etc/wsl.conf && echo WSL_CONF_OK; dpkg -s wslu >/dev/null 2>&1 && echo WSLU_OK; readlink /etc/resolv.conf'
```
Expected: `WSL_CONF_OK`、`WSLU_OK`、`/etc/resolv.conf` が `../run/systemd/resolve/resolv.conf` を指す（symlink 作成）。

- [ ] **Step 8: WSL 経路 2回目（冪等性）**

Run: `make play-wsl`
Expected: `changed=0`。

- [ ] **Step 9: 検証結果を記録（コミット不要）**

両経路で `failed=0` かつ 2回目 `changed=0`、挙動アサーションが期待どおりであることを確認。差異があれば該当 Task に戻って修正。

---

## Self-Review（作成後チェック）

**1. Spec coverage:**
- §1 判定変数 → Task 1 ✓
- §2 ディレクトリ構造（3ロール三分割）→ Task 2/3/4 ✓
- §3 dispatch パターン → Task 2/3/4 各 Step ✓
- §4 os_base 振り分け・誤ゲート修正（wsl.conf/wslu/resolv.conf 移動、DNS trim）→ Task 2 ✓
- §5 プレースホルダ（meta: noop + fallback）→ Task 2/3/4 + lint fallback ✓
- §6 packages/scheduler → Task 3/4 ✓
- §7 テスト戦略（play-wsl）・README・play 名 → Task 5/6 ✓
- 挙動の変化テーブル → Task 7 Step 4/7 で実証 ✓
- 検証計画（native/WSL 冪等性）→ Task 7 ✓

**2. Placeholder scan:** 「TBD/後で」等の未確定記述なし。`meta: noop` は仕様上のプレースホルダで、lint fallback を明示済み。✓

**3. Type/name consistency:** 変数名は全タスクで `is_wsl` / `is_linux_native` に統一。dispatch タスク名・ファイル名（`wsl.yaml` / `linux_native.yaml`）は3ロールで一致。`make play-wsl` は Task 5 で定義し Task 7 で使用。✓
