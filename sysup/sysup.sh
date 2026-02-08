#!/bin/bash
# usage : 
#   sudo chmod 755 /usr/local/bin/sysup.sh
#   manual
#     sudo /usr/local/bin/sysup.sh
#   cron (root)
#     0 3 * * 0 /usr/local/bin/sysup.sh 2>&1 | logger -t "SYSUP"

set -euo pipefail

# - function
log_info() {
    echo "SYSUP $(date '+%Y-%m-%d %H:%M:%S') - INFO  $*"
}

log_error() {
    echo "SYSUP $(date '+%Y-%m-%d %H:%M:%S') - ERROR $*" >&2
}

check_exist() {
    local checkfile="$1"

    if [ -z "$checkfile" ]; then
        log_error "check_exist: empty param"
        exit 1
    fi

    if ! command -v "$checkfile" >/dev/null 2>&1; then
        log_error "$checkfile not found"
        exit 1
    fi
}

wait_lock() {
    local lockfile="$1"
    local max_retries=30
    local count=0
    local wait_time=10

    if [ ! -e "$lockfile" ]; then
        return
    fi

    if command -v fuser >/dev/null 2>&1; then
        while fuser "$lockfile" >/dev/null 2>&1; do
            count=$((count + 1))
            if [ "$count" -ge "$max_retries" ]; then
                log_error "lock timeout after $((max_retries * wait_time)) seconds for $lockfile"
                exit 1
            fi
            sleep "$wait_time"
        done
    else
        log_error "fuser command not found, skipping lock check"
    fi
}

handle_error() {
    local rc=$1
    local lineno=$2
    log_error "Trap rc=$rc at line $lineno"
    exit "$rc"
}

trap 'handle_error $? $LINENO' ERR

# - main
log_info "start"

if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# dist detection
if grep -qiE "debian|ubuntu|mint|pop" /etc/os-release || [ -f /etc/debian_version ]; then
    OS="debian"
elif grep -qiE "rhel|centos|rocky|almalinux|fedora" /etc/os-release; then
    OS="rhel"
elif grep -qiE "opensuse|suse" /etc/os-release; then
    OS="suse"
else
    log_error "Unsupported OS"
    exit 1
fi

log_info "Detected OS: $OS"

## DEBIAN
if [ "$OS" = "debian" ]; then
    check_exist "apt-get"

    # update
    wait_lock "/var/lib/dpkg/lock"
    wait_lock "/var/lib/dpkg/lock-frontend"
    wait_lock "/var/lib/apt/lists/lock"

    export DEBIAN_FRONTEND=noninteractive
    apt-get -y update
    apt-get -y dist-upgrade
    apt-get -y autoremove
    #apt-get -y autoclean

    if [ -f /var/run/reboot-required ]; then
        log_info "Reboot required"
    fi
fi

## RHEL/FEDORA
if [ "$OS" = "rhel" ]; then
    check_exist "dnf"

    # update
    wait_lock "/var/cache/dnf/metadata_lock.pid"

    dnf -y upgrade --refresh
    dnf -y autoremove
    #dnf -y clean all

    if command -v needs-restarting >/dev/null 2>&1 && ! needs-restarting -r >/dev/null 2>&1; then
        log_info "Reboot required"
    fi
fi

## SUSE
if [ "$OS" = "suse" ]; then
    check_exist "zypper"

    # update
    wait_lock "/var/run/zypp.pid"

    zypper --non-interactive refresh

    if grep -qi "tumbleweed" /etc/os-release || grep -qi "slowroll" /etc/os-release; then
        zypper --non-interactive dup
    else
        zypper --non-interactive update
    fi

    if command -v needs-restarting >/dev/null 2>&1 && ! needs-restarting -r >/dev/null 2>&1; then
        log_info "Reboot required"
    fi

fi

log_info "end"

exit 0
