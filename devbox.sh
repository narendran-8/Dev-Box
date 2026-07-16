

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

usage() {
cat << EOF

Usage:
  $0 install <container-name>
  $0 start   <container-name>
  $0 stop    <container-name>
  $0 remove  <container-name>
  $0 status <container-name>
  $0 help


Description:
  install   Create container, install Git & SSH,
            configure Git and generate SSH key.

  start     Start the container (if needed) and open
            a shell directly in /workspace.

  stop      Stop the container.

  remove    Remove the container completely.

  status    Show the status of the container, including
            Git configuration and SSH key.

EOF
exit 0
}

###############################################

ACTION="$1"
CONTAINER_NAME="$2"

[[ "$ACTION" == "help" || "$ACTION" == "-h" || "$ACTION" == "--help" ]] && usage

[[ -z "$ACTION" || -z "$CONTAINER_NAME" ]] && usage

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

    if podman container exists "$CONTAINER_NAME"; then
        echo
        echo "[✓] Container '$CONTAINER_NAME' already exists."
        exit 0
    fi

    echo
    read -rp "Git Username : " GIT_USERNAME
    read -rp "Git Email    : " GIT_EMAIL

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

    podman exec "$CONTAINER_NAME" bash -c "cat /root/.ssh/id_ed25519.pub"

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
}

###############################################
# MAIN
###############################################

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
    help|-h|--help)
        usage
        ;;
    *)
        usage
        ;;
esac