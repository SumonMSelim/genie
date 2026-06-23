#!/bin/bash

# Test runner for server/outline/install-outline-server.sh
#
# Installs Docker inside the container (Docker-in-Docker not required — uses
# the host Docker socket mounted by the caller), then runs the outline script.
#
# Usage (from project root, inside a genie test container):
#   bash tests/test-outline-server.sh
#
# Or via the shared harness:
#   ./tests/run.sh ubuntu24 tests/test-outline-server.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTLINE_SCRIPT="${PROJECT_ROOT}/server/outline/install-outline-server.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect OS for package manager
detect_pkg_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    else
        error "Unsupported package manager. This test supports Ubuntu and Debian."
        exit 1
    fi
}

install_docker() {
    if command -v docker >/dev/null 2>&1; then
        info "Docker already installed: $(docker --version)"
        return 0
    fi

    info "Installing Docker..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release

    # shellcheck source=/dev/null
    . /etc/os-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${ID}/gpg" \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin

    success "Docker installed: $(docker --version)"
}

install_openssl() {
    if command -v openssl >/dev/null 2>&1; then
        return 0
    fi
    info "Installing openssl..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq openssl
}

start_docker_daemon() {
    if docker info >/dev/null 2>&1; then
        info "Docker daemon already running."
        return 0
    fi
    info "Starting Docker daemon..."
    # Use vfs snapshotter to avoid overlay-on-overlay failures in DinD
    dockerd --storage-driver=vfs &>/tmp/dockerd.log &
    local max=30
    while (( max > 0 )); do
        if docker info >/dev/null 2>&1; then
            success "Docker daemon ready."
            return 0
        fi
        sleep 1
        (( max-- )) || true
    done
    error "Docker daemon failed to start. Logs:"
    cat /tmp/dockerd.log
    exit 1
}

run_outline_script() {
    info "Running outline install script with --hostname test.local..."
    bash "${OUTLINE_SCRIPT}" --hostname test.local --api-port 8081 --keys-port 8082
}

main() {
    if [[ ${EUID} -ne 0 ]]; then
        error "Run as root or with sudo."
        exit 1
    fi

    detect_pkg_manager
    install_docker
    install_openssl
    start_docker_daemon
    run_outline_script
}

main "$@"
