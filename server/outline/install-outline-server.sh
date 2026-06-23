#!/bin/bash

# Outline Server VPN — Install, configure and run via Docker Compose
#
# COMPATIBILITY:
# - Ubuntu: 20.04 LTS (Focal), 22.04 LTS (Jammy), 24.04 LTS (Noble), or newer
# - Debian: 11 (Bullseye), 12 (Bookworm), 13 (Trixie), or newer
#
# REQUIREMENTS: Docker, Docker Compose (v2 plugin), root or sudo.
#
# Author: Muhammad Sumon Molla Selim
# GitHub: https://github.com/SumonMSelim/genie

set -euo pipefail

readonly SCRIPT_NAME="${0##*/}"
readonly OUTLINE_IMAGE="${SB_IMAGE:-quay.io/outline/shadowbox:stable}"
readonly CONTAINER_NAME="${CONTAINER_NAME:-shadowbox}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output helpers
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Install, configure and run Outline Server VPN with Docker Compose on Ubuntu or Debian.

Requirements: Docker, Docker Compose (v2 plugin), root or sudo.

Options:
  --hostname HOST    Public hostname or IP (required)
  --api-port PORT    Management API port (default: random)
  --keys-port PORT   Port for new access keys (default: server-assigned)
  --install-dir DIR  State directory (default: /opt/outline)
  -h, --help         Show this help

Example:
  sudo $SCRIPT_NAME --hostname my.server.com --api-port 8081
EOF
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        error "This script must be run as root or with sudo."
        exit 1
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS_ID="${ID:-}"
        VERSION_ID="${VERSION_ID:-}"
        VERSION_CODENAME="${VERSION_CODENAME:-}"
        return 0
    fi
    error "Cannot detect OS. /etc/os-release not found."
    exit 1
}

check_os_supported() {
    local supported=false
    case "${OS_ID}" in
        ubuntu)
            if [[ -n "${VERSION_ID:-}" ]] && [[ "${VERSION_ID}" =~ ^[0-9][0-9]\.[0-9][0-9]$ ]]; then
                supported=true
            fi
            ;;
        debian)
            if [[ -n "${VERSION_ID:-}" ]] && [[ "${VERSION_ID}" =~ ^[0-9]+$ ]] && (( VERSION_ID >= 11 )); then
                supported=true
            fi
            ;;
    esac
    if [[ "${supported}" != "true" ]]; then
        error "Unsupported OS. This script supports Ubuntu (20.04+) and Debian (11+). Detected: ${OS_ID} ${VERSION_ID:-unknown}"
        exit 1
    fi
}

get_random_port() {
    local num=0
    while (( num < 1024 || num >= 65536 )); do
        num=$(( RANDOM + (RANDOM % 2) * 32768 ))
    done
    echo "$num"
}

is_valid_port() {
    local p="$1"
    [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= 65535 ))
}

safe_base64() {
    base64 -w 0 - | tr '/+' '_-' | tr -d '='
}

fetch() {
    curl --silent --show-error --fail --ipv4 "$@"
}

create_persisted_state() {
    readonly STATE_DIR="${OUTLINE_DIR}/persisted-state"
    mkdir -p "${STATE_DIR}"
    chmod u+rwx,g+rws,o-rwx "${STATE_DIR}"
    readonly ACCESS_CONFIG="${OUTLINE_DIR}/access.txt"
}

generate_api_prefix() {
    SB_API_PREFIX=$(head -c 16 /dev/urandom | safe_base64)
    readonly SB_API_PREFIX
}

generate_certificate() {
    local cert_name="${STATE_DIR}/shadowbox-selfsigned"
    readonly SB_CERTIFICATE_FILE="${cert_name}.crt"
    readonly SB_PRIVATE_KEY_FILE="${cert_name}.key"
    openssl req -x509 -nodes -days 36500 -newkey rsa:4096 \
        -subj "/CN=${PUBLIC_HOSTNAME}" \
        -keyout "${SB_PRIVATE_KEY_FILE}" \
        -out "${SB_CERTIFICATE_FILE}" \
        >/dev/null 2>&1
}

cert_fingerprint_hex() {
    local fp
    fp=$(openssl x509 -in "${SB_CERTIFICATE_FILE}" -noout -sha256 -fingerprint)
    echo "${fp#*=}" | tr -d ':'
}

write_server_config() {
    local json="{\"hostname\": \"${PUBLIC_HOSTNAME}\", \"name\": \"Outline Server\""
    if (( FLAGS_KEYS_PORT > 0 )); then
        json="${json}, \"portForNewAccessKeys\": ${FLAGS_KEYS_PORT}"
    fi
    echo "${json}}" > "${STATE_DIR}/shadowbox_server_config.json"
}

write_compose_file() {
    local compose_file="${OUTLINE_DIR}/compose.yml"
    cat > "${compose_file}" << EOF
services:
  ${CONTAINER_NAME}:
    image: ${OUTLINE_IMAGE}
    container_name: ${CONTAINER_NAME}
    restart: always
    network_mode: host
    volumes:
      - ${STATE_DIR}:${STATE_DIR}
    environment:
      - SB_STATE_DIR=${STATE_DIR}
      - SB_API_PORT=${API_PORT}
      - SB_API_PREFIX=${SB_API_PREFIX}
      - SB_CERTIFICATE_FILE=${SB_CERTIFICATE_FILE}
      - SB_PRIVATE_KEY_FILE=${SB_PRIVATE_KEY_FILE}
      - SB_METRICS_URL=
EOF
    echo "${compose_file}"
}

start_compose() {
    local compose_file="${OUTLINE_DIR}/compose.yml"
    docker compose -f "${compose_file}" --project-directory "${OUTLINE_DIR}" up -d
}

wait_for_api() {
    local url="https://localhost:${API_PORT}/${SB_API_PREFIX}/access-keys"
    info "Waiting for Outline API to be ready..."
    local max=60
    while (( max > 0 )); do
        if fetch --insecure --max-time 3 "${url}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        (( max-- )) || true
    done
    error "Outline API did not become ready in time."
    return 1
}

create_first_access_key() {
    local url="https://localhost:${API_PORT}/${SB_API_PREFIX}/access-keys"
    fetch --insecure --request POST "${url}" >/dev/null 2>&1
}

write_access_config() {
    { echo "apiUrl:https://${PUBLIC_HOSTNAME}:${API_PORT}/${SB_API_PREFIX}"; echo "certSha256:$(cert_fingerprint_hex)"; } >> "${ACCESS_CONFIG}"
}

print_firewall_reminder() {
    echo ""
    warn "Open firewall: Management API port ${API_PORT} (TCP), and the access-key port (TCP/UDP) shown in Outline Manager."
    echo "  e.g. sudo ufw allow ${API_PORT}/tcp && sudo ufw reload"
}

print_success() {
    success "Outline Server is running."
    echo ""
    info "Add this server to Outline Manager (https://getoutline.org/get-started/#step-2):"
    echo ""
    if [[ -f "${ACCESS_CONFIG}" ]]; then
        local cert_sha
        cert_sha=$(cert_fingerprint_hex)
        echo "  { \"apiUrl\": \"https://${PUBLIC_HOSTNAME}:${API_PORT}/${SB_API_PREFIX}\", \"certSha256\": \"${cert_sha}\" }"
        echo ""
        info "Or copy from: ${ACCESS_CONFIG}"
        cat "${ACCESS_CONFIG}"
    fi
    echo ""
    info "Compose project directory: ${OUTLINE_DIR}"
    info "To stop:  docker compose -f ${OUTLINE_DIR}/compose.yml --project-directory ${OUTLINE_DIR} down"
    info "To logs:  docker compose -f ${OUTLINE_DIR}/compose.yml --project-directory ${OUTLINE_DIR} logs -f"
    print_firewall_reminder
}

parse_args() {
    FLAGS_HOSTNAME=""
    FLAGS_API_PORT=0
    FLAGS_KEYS_PORT=0
    OUTLINE_DIR="/opt/outline"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --hostname)
                FLAGS_HOSTNAME="${2:?Missing value for --hostname}"
                shift 2
                ;;
            --api-port)
                FLAGS_API_PORT="${2:?Missing value for --api-port}"
                shift 2
                if ! is_valid_port "${FLAGS_API_PORT}"; then
                    error "Invalid --api-port: ${FLAGS_API_PORT}"
                    exit 1
                fi
                ;;
            --keys-port)
                FLAGS_KEYS_PORT="${2:?Missing value for --keys-port}"
                shift 2
                if ! is_valid_port "${FLAGS_KEYS_PORT}"; then
                    error "Invalid --keys-port: ${FLAGS_KEYS_PORT}"
                    exit 1
                fi
                ;;
            --install-dir)
                OUTLINE_DIR="${2:?Missing value for --install-dir}"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    if (( FLAGS_API_PORT != 0 && FLAGS_API_PORT == FLAGS_KEYS_PORT )); then
        error "--api-port and --keys-port must differ."
        exit 1
    fi

    readonly OUTLINE_DIR FLAGS_HOSTNAME FLAGS_API_PORT FLAGS_KEYS_PORT
}

main() {
    require_root
    detect_os
    check_os_supported
    parse_args "$@"

    echo ""
    info "Outline Server VPN — Install (${OS_ID} ${VERSION_ID:-}, Docker Compose)"
    info "Install directory: ${OUTLINE_DIR}"
    echo ""

    if [[ -z "${FLAGS_HOSTNAME:-}" ]]; then
        error "Missing required --hostname. See --help."
        exit 1
    fi
    readonly PUBLIC_HOSTNAME="${FLAGS_HOSTNAME}"
    success "Hostname: ${PUBLIC_HOSTNAME}"

    API_PORT="${FLAGS_API_PORT}"
    if (( API_PORT == 0 )); then
        API_PORT=$(get_random_port)
    fi
    readonly API_PORT
    info "Management API port: ${API_PORT}"

    mkdir -p "${OUTLINE_DIR}"
    chmod u+rwx,o-rwx "${OUTLINE_DIR}"
    create_persisted_state
    generate_api_prefix
    generate_certificate
    write_server_config

    # Backup existing access config if present
    if [[ -s "${ACCESS_CONFIG}" ]]; then
        cp "${ACCESS_CONFIG}" "${ACCESS_CONFIG}.bak"
        : > "${ACCESS_CONFIG}"
    fi

    write_compose_file >/dev/null
    start_compose
    wait_for_api
    create_first_access_key
    write_access_config

    print_success
}

main "$@"
