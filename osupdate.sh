#!/bin/bash

set -euo pipefail

# - function
function log_info() {
    echo "OS-UPDATE [INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

function log_error() {
    echo "OS-UPDATE [ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
}

function check_exist() {
    local checkfile="$1"

    if [ -z "$checkfile" ]; then
        log_error "check_exist: empty param"
        exit 1
    fi

    if ! command -v "$checkfile" &>/dev/null; then
        log_error "$checkfile not found"
        exit 1
    fi
}

function wait_lock() {
    local lockfile="$1"
    local max_retries=10
    local count=0

    check_exist "fuser"

    while fuser "$lockfile" >/dev/null 2>&1; do
        ((count++))
        if [ "$count" -ge "$max_retries" ]; then
            log_error "error: lock time over"
            exit 1
        fi
        sleep 5
    done
}

function handle_error() {
    local rc=$1
    lineno=$2
    log_error "error: rc=$rc at line $lineno"
    exit $rc
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
    log_error "update end error: Unsupported OS"
    exit 1
fi

log_info "Detected OS: $OS"

## DEBIAN
if [ "$OS" = "debian" ]; then
    check_exist "apt-get"

    # update
    wait_lock "/var/lib/dpkg/lock"

    export DEBIAN_FRONTEND=noninteractive
    apt-get -y update
    apt-get -y upgrade # safety
    apt-get -y dist-upgrade
    apt-get -y autoremove
fi

## FEDORA
if [ "$OS" = "rhel" ]; then
    check_exist "dnf"

    # update
    wait_lock "/var/lib/rpm/.rpm.lock"
    wait_lock "/var/cache/dnf/metadata_lock.pid"

    dnf -y check-update
    dnf -y upgrade 
    dnf -y upgrade --refresh
    dnf -y autoremove
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
    ## please check format : zypper packages --unneeded
    zypper --non-interactive packages --unneeded | awk '/^i/{print $3}' | xargs -r zypper --non-interactive remove
fi

log_info "end"

exit 0
