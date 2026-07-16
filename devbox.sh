#!/usr/bin/env bash

set -e

###############################################
#                ASCII BANNER
###############################################

cat << "EOF"

   ___             ___          
  / _ \___ _  __  / _ )___ __ __
 / // / -_) |/ / / _  / _ \\ \ /
/____/\__/|___/ /____/\___/_\_\ 
                Idea by Narendran

EOF

###############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

short_usage() {
cat << EOF

Usage:
  $0 install <container-name>
  $0 start   <container-name>
  $0 stop    <container-name>
  $0 remove  <container-name>
  $0 status  <container-name>
  $0 ls
  $0 help

Run '$0 help' for full details.

EOF
exit 0
}

full_usage() {
cat << EOF

Usage:
  $0 install <container-name>
  $0 start   <container-name>
  $0 stop    <container-name>
  $0 remove  <container-name>
  $0 status  <container-name>
  $0 ls
  $0 help


Description:
  install   Create container, install Git & SSH,
            configure Git, generate SSH key, and set
            the GitHub remote (origin) for the repo.

  start     Start the container (if needed) and open
            a shell directly in /workspace.

  stop      Stop the container.

  remove    Remove the container completely.

  status    Show the status of the container, including
            Git configuration and SSH key.

  ls        List all stored credentials/config for every
            container (from config.json).

EOF

cat << "EOF"
============================================================
              GitHub Authentication Setup
============================================================

1. Copy the "SSH Public Key" from the container.

   GitHub:
     Profile
       └── Settings
             └── Developer Settings
                   └── SSH and GPG keys
                         └── SSH keys
                               └── New SSH key

   URL: https://github.com/settings/keys

------------------------------------------------------------

2. Create a "Personal Access Token (Classic)".

   GitHub:
     Profile
       └── Settings
             └── Developer Settings
                   └── Personal access tokens
                         └── Tokens (classic)
                               └── Generate new token
                                     └── Generate new token (classic)

   URL: https://github.com/settings/tokens

============================================================
EOF

exit 0
}

###############################################
# CONFIG.JSON HELPERS (require jq)
###############################################

ensure_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "[+] jq not found. Installing jq..."
        sudo apt update
        sudo apt install -y jq
    fi
}

ensure_config_file() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "{}" > "$CONFIG_FILE"
    fi
}

# save_config <container> <git_username> <git_email> <repo_name> <ssh_pub_key>
save_config() {
    local name="$1" user="$2" email="$3" repo="$4" pubkey="$5"

    ensure_jq
    ensure_config_file

    tmp="$(mktemp)"

    jq \
        --arg name "$name" \
        --arg user "$user" \
        --arg email "$email" \
        --arg repo "$repo" \
        --arg pubkey "$pubkey" \
        '.[$name] = {
            "container_name": $name,
            "git_username": $user,
            "git_email": $email,
            "repo_name": $repo,
            "ssh_public_key": $pubkey
        }' "$CONFIG_FILE" > "$tmp"

    mv "$tmp" "$CONFIG_FILE"
}

# get_config_field <container> <field>
get_config_field() {
    local name="$1" field="$2"
    ensure_jq
    ensure_config_file
    jq -r --arg name "$name" --arg field "$field" \
        '.[$name][$field] // empty' "$CONFIG_FILE"
}

config_exists() {
    local name="$1"
    ensure_jq
    ensure_config_file
    [ "$(jq -r --arg name "$name" 'has($name)' "$CONFIG_FILE")" = "true" ]
}

###############################################
# INSTALL
###############################################

install_container() {

    if ! command -v podman >/dev/null 2>&1; then
        echo "[+] Podman not found."
        echo "[+] Installing Podman..."
        sudo apt update
        sudo apt install -y podman
    else
        echo "[✓] Podman already installed."
    fi

    ensure_jq
    ensure_config_file

    if podman container exists "$CONTAINER_NAME"; then
        echo
        echo "[✓] Container '$CONTAINER_NAME' already exists."
        exit 0
    fi

    echo
    read -rp "Git Username     : " GIT_USERNAME
    read -rp "Git Email        : " GIT_EMAIL
    read -rp "GitHub Repo Name : " REPO_NAME

    echo
    echo "[+] Creating container..."

    podman run -dit \
        --name "$CONTAINER_NAME" \
        -v "$(pwd)":/workspace:Z \
        docker.io/library/ubuntu \
        bash

    echo "[+] Installing packages..."

    podman exec "$CONTAINER_NAME" bash -c "
        apt update &&
        DEBIAN_FRONTEND=noninteractive apt install -y \
            git \
            openssh-client \
            nano
    "

    echo "[+] Configuring Git..."

    podman exec "$CONTAINER_NAME" git config --global user.name "$GIT_USERNAME"
    podman exec "$CONTAINER_NAME" git config --global user.email "$GIT_EMAIL"

    echo "[+] Creating SSH directory..."

    podman exec "$CONTAINER_NAME" bash -c "
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
    "

    echo "[+] Generating SSH key..."

    podman exec "$CONTAINER_NAME" bash -c "
        if [ ! -f ~/.ssh/id_ed25519 ]; then
            ssh-keygen \
                -t ed25519 \
                -C '$GIT_EMAIL' \
                -f ~/.ssh/id_ed25519 \
                -N ''
        fi
    "

    echo "[+] Setting Git remote 'origin'..."

    podman exec "$CONTAINER_NAME" bash -c "
        cd /workspace &&
        if [ -d .git ]; then
            if git remote | grep -q '^origin\$'; then
                git remote set-url origin 'git@github.com:${GIT_USERNAME}/${REPO_NAME}.git'
            else
                git remote add origin 'git@github.com:${GIT_USERNAME}/${REPO_NAME}.git'
            fi
        else
            echo '[!] /workspace is not a git repo yet — skipping remote setup.'
            echo '    (run: git init && git remote add origin git@github.com:${GIT_USERNAME}/${REPO_NAME}.git)'
        fi
    "

    SSH_PUBKEY="$(podman exec "$CONTAINER_NAME" bash -c "cat /root/.ssh/id_ed25519.pub")"

    echo "[+] Saving credentials to config.json..."

    save_config "$CONTAINER_NAME" "$GIT_USERNAME" "$GIT_EMAIL" "$REPO_NAME" "$SSH_PUBKEY"

    echo
    echo "=========================================="
    echo "Git Configuration"
    echo "=========================================="

    podman exec "$CONTAINER_NAME" git config --list

    echo
    echo "=========================================="
    echo "SSH Fingerprint"
    echo "=========================================="

    podman exec "$CONTAINER_NAME" bash -c "ssh-keygen -lf /root/.ssh/id_ed25519"

    echo
    echo "=========================================="
    echo "Public SSH Key"
    echo "=========================================="

    echo "$SSH_PUBKEY"

    echo
    echo "=========================================="
    echo "Git Remote"
    echo "=========================================="
    echo "origin -> git@github.com:${GIT_USERNAME}/${REPO_NAME}.git"

    echo
    echo "=========================================="
    echo "Container Created Successfully!"
    echo "=========================================="

    echo
    echo "Start container with:"
    echo "  $0 start $CONTAINER_NAME"
}

###############################################
# START
###############################################

start_container() {

    if ! podman container exists "$CONTAINER_NAME"; then
        echo "[!] Container '$CONTAINER_NAME' not found."
        exit 1
    fi

    if [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" != "true" ]; then
        echo "[+] Starting container..."
        podman start "$CONTAINER_NAME" >/dev/null
    else
        echo "[✓] Container already running."
    fi

    echo
    echo "[+] Opening shell..."
    echo

    exec podman exec \
        -it \
        -w /workspace \
        "$CONTAINER_NAME" \
        bash
}

###############################################
# STOP
###############################################

stop_container() {

    if ! podman container exists "$CONTAINER_NAME"; then
        echo "[!] Container '$CONTAINER_NAME' not found."
        exit 1
    fi

    if [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" = "true" ]; then
        podman stop "$CONTAINER_NAME" >/dev/null
        echo "[✓] Container stopped."
    else
        echo "[✓] Container already stopped."
    fi
}

###############################################
# REMOVE
###############################################

remove_container() {

    if ! podman container exists "$CONTAINER_NAME"; then
        echo "[!] Container '$CONTAINER_NAME' not found."
        exit 1
    fi

    if [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" = "true" ]; then
        podman stop "$CONTAINER_NAME" >/dev/null
    fi

    podman rm "$CONTAINER_NAME" >/dev/null

    echo "[✓] Container removed."

    if config_exists "$CONTAINER_NAME"; then
        ensure_jq
        tmp="$(mktemp)"
        jq --arg name "$CONTAINER_NAME" 'del(.[$name])' "$CONFIG_FILE" > "$tmp"
        mv "$tmp" "$CONFIG_FILE"
        echo "[✓] Removed credentials from config.json."
    fi
}

# ==========================================
#         Container Status
# ==========================================
status_container() {

    if ! podman container exists "$CONTAINER_NAME"; then
        echo "[✗] Container does not exist."
        exit 1
    fi

    echo "=========================================="
    echo "Container Status"
    echo "=========================================="

    if [ "$(podman inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" = "true" ]; then
        echo "[✓] Container is running."
    else
        echo "[!] Container is stopped."
        echo
        echo "Run:"
        echo "./devbox.sh start $CONTAINER_NAME"
        exit 0
    fi

    echo

    podman exec "$CONTAINER_NAME" bash -c '

        command -v git >/dev/null &&
        echo "[✓] Git installed" ||
        echo "[✗] Git not installed"

        command -v ssh >/dev/null &&
        echo "[✓] OpenSSH installed" ||
        echo "[✗] OpenSSH not installed"

        echo

        echo "Git Username : $(git config --global user.name)"
        echo "Git Email    : $(git config --global user.email)"

        echo

        if [ -f ~/.ssh/id_ed25519 ]; then
            echo "[✓] SSH key exists."
        else
            echo "[✗] SSH key missing."
        fi

        echo
        echo "Checking GitHub authentication..."
        echo

        ssh -o StrictHostKeyChecking=no \
            -T git@github.com 2>&1 || true

        echo

        if ssh -o BatchMode=yes \
            -o ConnectTimeout=5 \
            -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
            echo "[✓] GitHub SSH configured."
        else
            echo "[✗] GitHub SSH NOT configured."
            echo
            echo "Public key:"
            cat ~/.ssh/id_ed25519.pub
        fi

'

    echo
    echo "=========================================="
    echo "Git Remote (origin)"
    echo "=========================================="
    podman exec "$CONTAINER_NAME" bash -c "cd /workspace && git remote -v 2>/dev/null || echo 'No git remote configured.'"
}

###############################################
# LS  (list all stored credentials)
###############################################

list_config() {
    ensure_jq
    ensure_config_file

    COUNT="$(jq 'length' "$CONFIG_FILE")"

    if [ "$COUNT" -eq 0 ]; then
        echo "[!] No containers found in config.json."
        exit 0
    fi

    echo "=========================================="
    echo "Stored Credentials (config.json)"
    echo "=========================================="
    echo

    jq -r '
        to_entries[] |
        "Container Name : \(.value.container_name)\n" +
        "Git Username   : \(.value.git_username)\n" +
        "Git Email      : \(.value.git_email)\n" +
        "Repo Name      : \(.value.repo_name)\n" +
        "SSH Public Key : \(.value.ssh_public_key)\n" +
        "------------------------------------------"
    ' "$CONFIG_FILE"
}

###############################################
# MAIN
###############################################

ACTION="$1"
CONTAINER_NAME="$2"

# No argument at all -> short usage only
[[ -z "$ACTION" ]] && short_usage

# help / -h / --help -> full usage including GitHub auth guide
[[ "$ACTION" == "help" || "$ACTION" == "-h" || "$ACTION" == "--help" ]] && full_usage

# ls -> list stored credentials (no container name required)
[[ "$ACTION" == "ls" ]] && { list_config; exit 0; }

# All other actions require a container name
[[ -z "$CONTAINER_NAME" ]] && short_usage

case "$ACTION" in
    install)
        install_container
        ;;
    start)
        start_container
        ;;
    stop)
        stop_container
        ;;
    remove)
        remove_container
        ;;
    status)
        status_container
        ;;
    *)
        short_usage
        ;;
esac