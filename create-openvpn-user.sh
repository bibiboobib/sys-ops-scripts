#!/bin/sh
# POSIX-compliant user creation script for Linux and Unix systems
# Creates users with home directory, shell, and password
# Supports Linux (Debian, Ubuntu, CentOS, Fedora, Arch) and FreeBSD

# Exit on error
set -e

# Check if running as root
is_root() {
    if [ "$(id -u)" -ne 0 ]; then
        return 1
    fi
}

# Detect operating system
check_os() {
    OS=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu|raspbian|centos|fedora|arch|rocky|almalinux|ol|amzn)
                OS="linux"
                ;;
            *)
                OS="unknown"
                ;;
        esac
    elif uname -s | grep -q FreeBSD; then
        OS="freebsd"
    else
        echo "Unsupported OS. Supported: Linux, FreeBSD."
        exit 1
    fi
}

# Check if user exists
user_exists() {
    USERNAME="$1"
    if [ "$OS" = "freebsd" ]; then
        pw usershow "$USERNAME" >/dev/null 2>&1
    else
        id "$USERNAME" >/dev/null 2>&1
    fi
}

# Create user
create_user() {
    USERNAME="$1"
    HOMEDIR="/home/$USERNAME"
    SHELL="/bin/sh"
    LOGFILE="/var/log/user_create.log"

    # Check if user exists
    if user_exists "$USERNAME"; then
        echo "User $USERNAME already exists."
        exit 1
    fi

    # Use bash if available
    if [ -x /bin/bash ]; then
        SHELL="/bin/bash"
    fi

    # Create user
    echo "Creating user $USERNAME..."
    if [ "$OS" = "freebsd" ]; then
        pw useradd -n "$USERNAME" -m -s "$SHELL" -c "OpenVPN user"
        echo "$(date): Created user $USERNAME on FreeBSD" >> "$LOGFILE"
    else
        useradd -m -s "$SHELL" -c "OpenVPN user" "$USERNAME"
        echo "$(date): Created user $USERNAME on Linux" >> "$LOGFILE"
    fi

    # Set password
    echo "Enter password for $USERNAME:"
    if [ "$OS" = "freebsd" ]; then
        pw usermod "$USERNAME" -h 0
    else
        passwd "$USERNAME"
    fi

    echo "User $USERNAME created with home directory $HOMEDIR and shell $SHELL."
    echo "Log: $LOGFILE"
}

# Main
if ! is_root; then
    echo "This script must be run as root."
    exit 1
fi

check_os

echo "Enter username (alphanumeric, underscore, dash): "
read USERNAME
if ! echo "$USERNAME" | grep -E '^[a-zA-Z0-9_-]+$'; then
    echo "Invalid username."
    exit 1
fi

create_user "$USERNAME"
