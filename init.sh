#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/kukv/os-setup.git"
BRANCH="main"
OP_USER=""

usage() {
  cat <<'EOF'
Usage:
  Linux/WSL:  sudo bash init.sh -u <user> [-b <branch>]
  macOS:      zsh init.sh [-b <branch>]

Options:
  -u, --user    <user>    (Linux only, required) provisioning user
  -b, --branch  <branch>  git branch (default: main)
  -h, --help              show help
EOF
}

# --- arg parsing (portable) ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--user)   OP_USER="$2"; shift 2 ;;
    -b|--branch) BRANCH="$2"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

OS="$(uname -s)"

if [[ "$OS" == "Darwin" ]]; then
  # ---- macOS flow (from mac-setup/init.sh) ----
  echo "==> Checking Xcode Command Line Tools..."
  if ! xcode-select -p &>/dev/null; then
    echo "Error: Xcode Command Line Tools required: xcode-select --install"
    exit 1
  fi
  echo "==> Checking Homebrew..."
  if ! command -v brew &>/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  echo "==> Checking Ansible..."
  command -v ansible &>/dev/null || brew install ansible < /dev/null

  EXTRA_VARS_FILE="${HOME}/.local/etc/extra_vars.yaml"
  EXTRA_VARS_OPTS=()
  [[ -f "${EXTRA_VARS_FILE}" ]] && EXTRA_VARS_OPTS=(--extra-vars "@${EXTRA_VARS_FILE}")

  echo "==> Running ansible-pull (branch: ${BRANCH})..."
  PYTHONUNBUFFERED=1 ansible-pull \
    --url "${REPO_URL}" --checkout "${BRANCH}" \
    --inventory ansible/inventories/hosts.yaml \
    "${EXTRA_VARS_OPTS[@]}" \
    ansible/playbook.yaml

else
  # ---- Linux/WSL flow (from wsl-setup/init.sh) ----
  if [[ -z "${OP_USER}" ]]; then
    echo "Error: -u <user> is required on Linux"; usage; exit 9
  fi

  # passwordless sudo
  sudoers_path="/etc/sudoers.d"
  mkdir -p "${sudoers_path}"
  if ! grep -qs "${OP_USER} ALL=(ALL) NOPASSWD: ALL" "${sudoers_path}/${OP_USER}" 2>/dev/null; then
    echo "${OP_USER} ALL=(ALL) NOPASSWD: ALL" | tee "${sudoers_path}/${OP_USER}" > /dev/null
    chmod 440 "${sudoers_path}/${OP_USER}"
  fi

  apt-add-repository ppa:ansible/ansible -y
  apt update && apt upgrade -y
  apt install -y ansible git
  apt autoremove -y

  sudo -u "${OP_USER}" bash -c \
    "/usr/bin/ansible-pull -U ${REPO_URL} -C ${BRANCH} -i ansible/inventories/hosts.yaml ansible/playbook.yaml --extra-vars '@/etc/ansible/extra_vars.yaml' --extra-vars 'ansible_user=${OP_USER}'"
fi
