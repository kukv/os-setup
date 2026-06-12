VM_NAME      := os-setup-test
IMAGE        := ghcr.io/cirruslabs/macos-tahoe-base:latest
SSH_USER     := admin
SSH_PASS     := admin
SSH_OPTS     := -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR -o PubkeyAuthentication=no -o PreferredAuthentications=password
PROJECT_ROOT := $(shell cd $(CURDIR)/.. && pwd)
DISK_SIZE    := 100
TAGS         ?=

.PHONY: help check-deps create start start-gui provision test teardown ssh status

help: ## ヘルプを表示
	@echo "Tart VM テスト環境"
	@echo ""
	@echo "前提条件:"
	@echo "  brew install cirruslabs/cli/tart hudochenkov/sshpass/sshpass"
	@echo ""
	@echo "使い方:"
	@echo "  make test            - VM作成 → プロビジョニング → 停止 (フルテスト)"
	@echo "  make test TAGS=packages - 特定タグのみテスト"
	@echo ""
	@echo "ターゲット:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

check-deps: ## 依存ツールの確認
	@missing=""; \
	command -v tart >/dev/null 2>&1 || missing="$$missing tart"; \
	command -v sshpass >/dev/null 2>&1 || missing="$$missing sshpass"; \
	if [ -n "$$missing" ]; then \
		echo "Error: 以下のツールがインストールされていません:$$missing"; \
		echo ""; \
		echo "  brew install cirruslabs/cli/tart hudochenkov/sshpass/sshpass"; \
		exit 1; \
	fi; \
	echo "==> 依存ツール OK"

create: check-deps ## VM を作成 (初回はイメージダウンロードに時間がかかる)
	@if tart list | grep -q '$(VM_NAME)'; then \
		echo "==> VM '$(VM_NAME)' は既に存在します (再作成: make teardown && make create)"; \
	else \
		echo "==> macOS イメージをクローン中..."; \
		tart clone $(IMAGE) $(VM_NAME); \
		tart set $(VM_NAME) --disk-size $(DISK_SIZE); \
		echo "==> VM '$(VM_NAME)' を作成しました (disk: $(DISK_SIZE)GB)"; \
	fi

start: create ## VM をヘッドレスモードで起動 (ターミナルをブロック)
	@echo "==> VM '$(VM_NAME)' をヘッドレスで起動中..."
	@echo "    停止: Ctrl+C または別ターミナルから make teardown"
	@tart run $(VM_NAME) --no-graphics

start-gui: create ## VM を GUI 付きで起動 (macOS デスクトップを表示)
	@echo "==> VM '$(VM_NAME)' を GUI で起動中..."
	@echo "    停止: ウィンドウを閉じるか、別ターミナルから make teardown"
	@tart run $(VM_NAME)

provision: ## 起動中の VM にプロジェクトを同期して playbook を実行
	@echo "==> VM の IP を取得中..."
	@VM_IP=""; \
	for i in $$(seq 1 60); do \
		VM_IP=$$(tart ip $(VM_NAME) 2>/dev/null); \
		if [ -n "$$VM_IP" ]; then break; fi; \
		printf "."; sleep 2; \
	done; echo ""; \
	if [ -z "$$VM_IP" ]; then \
		echo "Error: VM が起動していません。先に 'make start' を実行してください"; \
		exit 1; \
	fi; \
	echo "==> VM IP: $$VM_IP"; \
	echo "==> SSH 接続を待機中..."; \
	for i in $$(seq 1 30); do \
		if sshpass -p '$(SSH_PASS)' ssh $(SSH_OPTS) $(SSH_USER)@$$VM_IP true 2>/dev/null; then \
			break; \
		fi; \
		printf "."; sleep 2; \
	done; echo ""; \
	echo "==> プロジェクトファイルを同期中..."; \
	sshpass -p '$(SSH_PASS)' rsync -az \
		--exclude='.git' --exclude='.idea' --exclude='.DS_Store' \
		-e "ssh $(SSH_OPTS)" \
		$(PROJECT_ROOT)/ $(SSH_USER)@$$VM_IP:~/os-setup/; \
	echo "==> テスト用 extra_vars を配置中..."; \
	sshpass -p '$(SSH_PASS)' ssh $(SSH_OPTS) $(SSH_USER)@$$VM_IP \
		"mkdir -p ~/.local/etc && cp ~/os-setup/test/extra_vars.test.yaml ~/.local/etc/extra_vars.yaml"; \
	echo "==> Playbook を実行中$(if $(TAGS), (tags: $(TAGS)),)..."; \
	sshpass -p '$(SSH_PASS)' ssh $(SSH_OPTS) $(SSH_USER)@$$VM_IP \
		"cd ~/os-setup && zsh test/run-in-vm.sh '$(TAGS)'"

test: create ## フルテスト: VM起動 → プロビジョニング → 停止
	@echo "==> VM をバックグラウンドで起動中..."
	@tart run $(VM_NAME) --no-graphics & \
	VM_PID=$$!; \
	trap "echo '==> VM を停止中...'; tart stop $(VM_NAME) 2>/dev/null || true; wait $$VM_PID 2>/dev/null || true" EXIT; \
	sleep 5; \
	$(MAKE) provision TAGS="$(TAGS)"; \
	echo "==> テスト完了!"

teardown: ## VM を停止・削除
	@-tart stop $(VM_NAME) 2>/dev/null
	@-tart delete $(VM_NAME) 2>/dev/null
	@echo "==> VM '$(VM_NAME)' を削除しました"

ssh: ## 起動中の VM に SSH 接続
	@VM_IP=$$(tart ip $(VM_NAME) 2>/dev/null); \
	if [ -z "$$VM_IP" ]; then echo "Error: VM が起動していません"; exit 1; fi; \
	sshpass -p '$(SSH_PASS)' ssh $(SSH_OPTS) $(SSH_USER)@$$VM_IP

status: ## VM の状態を表示
	@echo "==> VM Status:"
	@tart list 2>/dev/null | grep -E '(Name|$(VM_NAME))' || echo "  VM '$(VM_NAME)' が見つかりません"
	@VM_IP=$$(tart ip $(VM_NAME) 2>/dev/null); \
	if [ -n "$$VM_IP" ]; then echo "  Running (IP: $$VM_IP)"; else echo "  Not running"; fi
