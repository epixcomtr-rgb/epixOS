#!/usr/bin/env bash
# epixOS — isteğe bağlı ağır geliştirici araçları
# Kullanım: sudo ./scripts/install-devtools.sh [--all] [--rust] [--node] [--docker] [--go] [--java] [--vscode]
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "sudo ile çalıştır: sudo $0 $*" >&2; exit 1; }
as_user="${SUDO_USER:-live}"
ALL=0; PICK=()

for a in "$@"; do
  case "$a" in
    --all) ALL=1 ;;
    --rust|--node|--docker|--go|--java|--vscode) PICK+=("$a") ;;
    *) echo "bilinmeyen seçenek: $a" >&2; exit 1 ;;
  esac
done

want() { [[ $ALL -eq 1 ]] || [[ " ${PICK[*]:-} " == *" $1 "* ]]; }

apt_base() {
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates gnupg lsb-release
}

run_as_user() { sudo -u "$as_user" -H bash -lc "$*"; }

if want --docker; then
  echo "==> Docker + Compose"
  apt_base
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  usermod -aG docker "$as_user" || true
fi

if want --node; then
  echo "==> Node.js (nvm)"
  apt_base
  run_as_user 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash'
  run_as_user 'export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"; nvm install --lts'
fi

if want --rust; then
  echo "==> Rust (rustup)"
  apt_base
  apt-get install -y --no-install-recommends build-essential pkg-config libssl-dev
  run_as_user 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path'
fi

if want --go; then
  echo "==> Go"
  apt_base
  apt-get install -y --no-install-recommends golang-go
fi

if want --java; then
  echo "==> OpenJDK 21"
  apt_base
  apt-get install -y --no-install-recommends openjdk-21-jdk
fi

if want --vscode; then
  echo "==> VS Code (deb)"
  apt_base
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
    > /etc/apt/sources.list.d/vscode.list
  apt-get update
  apt-get install -y code
fi

echo "==> Tamam. Yeni gruplar için oturumu kapat/aç."
