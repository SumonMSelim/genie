#!/bin/bash

# Usage: ./run.sh <os_target> <script_path>
# Example: ./run.sh ubuntu22 server/bootstrap-server.sh

OS_TARGET=$1
SCRIPT_PATH=$2

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FULL_SCRIPT_PATH="$PROJECT_ROOT/$SCRIPT_PATH"
COMPOSE_FILE="$PROJECT_ROOT/tests/environments/compose.yml"

ask_confirm() {
    local prompt="$1"
    local default="${2:-Y}"
    local choice

    if [[ "$default" == "Y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -rp "$prompt" choice
    choice="${choice:-$default}"

    [[ "$choice" =~ ^[Yy]$ ]]
}

# Check arguments
if [ -z "$OS_TARGET" ] || [ -z "$SCRIPT_PATH" ]; then
    echo -e "\033[0;31mError: Missing arguments.\033[0m"
    echo "Usage: ./run.sh <os_target> <script_path>"
    echo "Targets: ubuntu24, ubuntu22, ubuntu20, debian12, debian11"
    exit 1
fi

# Check if script exists locally
if [ ! -f "$FULL_SCRIPT_PATH" ]; then
    echo -e "\033[0;31mError: Script '$FULL_SCRIPT_PATH' not found.\033[0m"
    exit 1
fi

echo -e "\033[0;34m[INFO]\033[0m Starting environment: $OS_TARGET"
echo -e "\033[0;34m[INFO]\033[0m Script path from project root: $FULL_SCRIPT_PATH"

# Force a fresh container each run (prevents old state from leaking)
docker compose -f "$COMPOSE_FILE" up -d --force-recreate --renew-anon-volumes "$OS_TARGET"

echo -e "\033[0;34m[INFO]\033[0m Executing script: $SCRIPT_PATH"
# Repo is mounted read-only at /genie, so run via bash without chmod.
docker exec -it "genie-$OS_TARGET" bash -lc "cd /genie && bash \"$SCRIPT_PATH\""

if ask_confirm "Stop environment '$OS_TARGET' now?"; then
    echo -e "\033[0;34m[INFO]\033[0m Stopping environment..."
    docker compose -f "$COMPOSE_FILE" stop "$OS_TARGET"

    # Default cleanup: remove container + volumes so the next run is clean.
    echo -e "\033[0;34m[INFO]\033[0m Removing container + volumes..."
    docker compose -f "$COMPOSE_FILE" rm -fsv "$OS_TARGET"
else
    echo -e "\033[0;33m[WARNING]\033[0m Leaving environment running."
    echo -e "\033[0;33m[WARNING]\033[0m Stop later with: docker compose -f \"$COMPOSE_FILE\" stop \"$OS_TARGET\""
fi

echo -e "\033[0;32m[SUCCESS]\033[0m Test session for $SCRIPT_PATH on $OS_TARGET completed."
