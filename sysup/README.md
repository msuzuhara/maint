# sysup - System Update Service

Automated system update service for Linux using systemd timer and service.

## Overview

`sysup` is a systemd-based service that performs periodic system updates across multiple Linux distributions:
- **Debian/Ubuntu/Mint/Pop**: `apt-get update` and `dist-upgrade`
- **RHEL/CentOS/Rocky/AlmaLinux/Fedora**: `dnf upgrade`
- **openSUSE/SUSE**: `zypper refresh` and `dup` (Tumbleweed) or `update` (Leap)

The service runs automatically at **3:00 AM daily** with a randomized delay (0-30 minutes) to avoid load spikes on package repositories.

## Features

- ✅ Multi-distribution support (Debian, RHEL, SUSE)
- ✅ Automatic package manager lock file handling
- ✅ Safe error logging to systemd journal
- ✅ Configurable scheduled execution via systemd timer
- ✅ Reboot detection notification
- ✅ Root privilege verification

## Installation

### 1. Place the script

```bash
sudo cp sysup.sh /usr/local/bin/sysup.sh
sudo chmod 755 /usr/local/bin/sysup.sh
```

### 2. Install systemd files

```bash
sudo cp sysup.service /etc/systemd/system/sysup.service
sudo cp sysup.timer /etc/systemd/system/sysup.timer
sudo systemctl daemon-reload
```

### 3. Enable and start the timer

```bash
sudo systemctl enable --now sysup.timer
```

## Configuration

### Change scheduled time

Edit `/etc/systemd/system/sysup.timer` and modify the `OnCalendar` setting:

```ini
[Timer]
OnCalendar=*-*-* 03:00:00   # Run at 3:00 AM daily
```

Other examples:
- `*-*-* 02:30:00` – 2:30 AM daily
- `Sun *-*-* 03:00:00` – Every Sunday at 3:00 AM
- `*-*-1 03:00:00` – First day of each month at 3:00 AM

After modifying, reload and restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart sysup.timer
```

### Adjust randomized delay

Edit the `RandomizedDelaySec` value in `/etc/systemd/system/sysup.timer`:

```ini
RandomizedDelaySec=30min    # Random delay 0–30 minutes
```

## Usage

### Manual execution

```bash
sudo /usr/local/bin/sysup.sh
```

### Check status

```bash
sudo systemctl status sysup.service
sudo systemctl status sysup.timer
```

### View logs

```bash
# Last 50 lines
sudo journalctl -u sysup.service -n 50

# Follow logs in real-time
sudo journalctl -u sysup.service -f

# Logs from the last hour
sudo journalctl -u sysup.service --since "1 hour ago"
```

### List recent timer runs

```bash
sudo systemctl list-timers sysup.timer
```

## Troubleshooting

### Timer is not running

Check if the timer is enabled:
```bash
sudo systemctl is-enabled sysup.timer
# Output: enabled
```

Enable and start:
```bash
sudo systemctl enable --now sysup.timer
```

### Service fails with "lock timeout"

The `fuser` command is required for lock file detection. Install it:

**Debian/Ubuntu:**
```bash
sudo apt-get install psmisc
```

**RHEL/Fedora:**
```bash
sudo dnf install psmisc
```

### Permission denied error

Ensure the script has execute permissions:
```bash
sudo chmod 755 /usr/local/bin/sysup.sh
```

### Service runs but doesn't update packages

Check if the script runs as root. The service must run as root to modify system packages:
```bash
sudo systemctl status sysup.service
```

Verify the script can find package managers:
```bash
sudo /usr/local/bin/sysup.sh
```

## Files

- `sysup.sh` – Main update script
- `sysup.service` – Systemd service unit
- `sysup.timer` – Systemd timer unit
- `LICENSE` – License information

## License

See [LICENSE](LICENSE) for details.
