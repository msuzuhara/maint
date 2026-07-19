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
    printf "SYSUP %s - INFO  %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

log_error() {
    printf "SYSUP %s - ERROR %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
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
        log_info "fuser command not found, skipping lock check"
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
reboot_check=0
reboot_exec=0

# single instance lock using flock when available
lock_file="/var/run/sysup.lock"
exec 200>"$lock_file" || { log_error "Unable to open lockfile $lock_file"; exit 1; }
if command -v flock >/dev/null 2>&1; then
    if ! flock -n 200; then
        log_info "Another instance is running, exiting"
        exit 0
    fi
else
    log_info "flock not available, skipping single-instance lock"
fi

if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
fi

# option parsing
while getopts "rs" OPT
do
    case $OPT in
        r)  reboot_exec=1
           ;;
        s)  reboot_check=1
           ;;
        \?) log_error "Invalid option: -$OPTARG"
            log_error "Usage: sysup.sh [-r] [-s]"
            exit 2
           ;;
    esac
done

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

    if [ -f /var/run/reboot-required ] || [ -f /var/run/reboot-required.necessary ]; then
        log_info "Reboot required"
        if [ "$reboot_check" -eq 1 ]; then
            reboot_exec=1
        fi
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

    if command -v needs-restarting >/dev/null 2>&1; then
        if needs-restarting -r >/dev/null 2>&1; then
            log_info "Reboot required"
            if [ "$reboot_check" -eq 1 ]; then
                reboot_exec=1
            fi
        fi
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

    if command -v needs-restarting >/dev/null 2>&1; then
        if needs-restarting -r >/dev/null 2>&1; then
            log_info "Reboot required"
            if [ "$reboot_check" -eq 1 ]; then
                reboot_exec=1
            fi
        fi
    fi

fi

log_info "end"

if [ "$reboot_exec" -eq 1 ]; then
    log_info "A reboot is required to complete the updates."
    if command -v systemctl >/dev/null 2>&1; then
        systemctl reboot
    elif command -v shutdown >/dev/null 2>&1; then
        shutdown -r now
    else
        log_error "No reboot command available (systemctl/shutdown)"
        exit 1
    fi
fi

exit 0
