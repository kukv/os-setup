#!/bin/zsh
set -euo pipefail

# Tart VM 内で実行されるプロビジョニングスクリプト
# ホストから rsync されたプロジェクトを使ってローカルで playbook を実行する

PROJECT_DIR="${HOME}/os-setup"
EXTRA_VARS_FILE="${HOME}/.local/etc/extra_vars.yaml"
TAGS="${1:-}"

echo "==> Checking Xcode Command Line Tools..."
if ! xcode-select -p &>/dev/null; then
  echo "Error: Xcode Command Line Tools がインストールされていません"
  echo "  xcode-select --install"
  exit 1
fi

echo "==> Checking Homebrew..."
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "==> Checking Ansible..."
if ! command -v ansible-playbook &>/dev/null; then
  echo "Installing Ansible..."
  brew install ansible
fi

echo "==> Installing Ansible Galaxy collections..."
ansible-galaxy collection install -r "${PROJECT_DIR}/ansible/requirements.yaml"

PLAYBOOK_OPTS=(
  -i "${PROJECT_DIR}/ansible/inventories/hosts.yaml"
  --extra-vars "@${EXTRA_VARS_FILE}"
)

if [[ -n "${TAGS}" ]]; then
  PLAYBOOK_OPTS+=(--tags "${TAGS}")
fi

echo "==> Running playbook${TAGS:+ (tags: ${TAGS})}..."
ansible-playbook "${PLAYBOOK_OPTS[@]}" "${PROJECT_DIR}/ansible/playbook.yaml"

echo "==> Done!"
