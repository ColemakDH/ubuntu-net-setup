#!/usr/bin/env bash
set -euo pipefail

# Ubuntu 22.04 left/right network configuration
# Usage:
#   sudo ./setup.sh
#
# Configures:
#   /etc/hosts
#   /etc/hostname
#   /etc/netplan/50-cloud-init.yaml
#   /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
#
# Then reboots the system.

# ------------------------------------------------------------
# Require root
# ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script as root."
    echo "Example: sudo $0"
    exit 1
fi

# ------------------------------------------------------------
# Ask which machine this is
# ------------------------------------------------------------

echo
echo "======================================"
echo " Ubuntu Left/Right Network Setup"
echo "======================================"
echo
echo "1) left  - 192.168.100.1"
echo "2) right - 192.168.100.2"
echo

while true; do
    read -rp "Is this the LEFT or RIGHT machine? [left/right]: " SIDE
    SIDE="${SIDE,,}"

    case "$SIDE" in
        left)
            IP="192.168.100.1"
            break
            ;;
        right)
            IP="192.168.100.2"
            break
            ;;
        *)
            echo "Please enter 'left' or 'right'."
            ;;
    esac
done

HOSTNAME="$SIDE"

echo
echo "Configuration:"
echo "  Hostname : $HOSTNAME"
echo "  ens34 IP : $IP/24"
echo

read -rp "Continue? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# ------------------------------------------------------------
# Backup existing configuration
# ------------------------------------------------------------

BACKUP_DIR="/root/network-setup-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo
echo "Creating backups in:"
echo "  $BACKUP_DIR"

cp -a /etc/hosts "$BACKUP_DIR/hosts"
cp -a /etc/hostname "$BACKUP_DIR/hostname"

if [[ -f /etc/netplan/50-cloud-init.yaml ]]; then
    cp -a /etc/netplan/50-cloud-init.yaml \
        "$BACKUP_DIR/50-cloud-init.yaml"
fi

if [[ -f /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg ]]; then
    cp -a /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg \
        "$BACKUP_DIR/99-disable-network-config.cfg"
fi

# ------------------------------------------------------------
# /etc/hostname
# ------------------------------------------------------------

echo "Setting hostname to $HOSTNAME..."

printf '%s\n' "$HOSTNAME" > /etc/hostname

# ------------------------------------------------------------
# /etc/hosts
# ------------------------------------------------------------

echo "Updating /etc/hosts..."

# Remove old left/right entries if they exist.
sed -i \
    -e '/[[:space:]]left$/d' \
    -e '/[[:space:]]right$/d' \
    /etc/hosts

# Add this machine.
printf '%s\t%s\n' "$IP" "$HOSTNAME" >> /etc/hosts

# Make sure localhost entries remain present.
if ! grep -qE '^127\.0\.0\.1[[:space:]]+localhost([[:space:]]|$)' /etc/hosts; then
    sed -i '1i127.0.0.1\tlocalhost' /etc/hosts
fi

# ------------------------------------------------------------
# Disable cloud-init network configuration
# ------------------------------------------------------------

echo "Disabling cloud-init network configuration..."

mkdir -p /etc/cloud/cloud.cfg.d

cat > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg <<'EOF'
network: {config: disabled}
EOF

# ------------------------------------------------------------
# Netplan
# ------------------------------------------------------------

NETPLAN_FILE="/etc/netplan/50-cloud-init.yaml"

echo "Configuring ens34 in $NETPLAN_FILE..."

# Create the file if it doesn't exist.
touch "$NETPLAN_FILE"

# Remove an existing ens34 block if one exists.
# This handles the common simple netplan structure.
python3 - "$NETPLAN_FILE" "$IP" <<'PY'
import sys

filename = sys.argv[1]
ip = sys.argv[2]

with open(filename, "r") as f:
    lines = f.readlines()

output = []
skip = False
indent = None

for line in lines:
    # Detect an existing ens34 interface.
    if line.startswith("    ens34:"):
        skip = True
        indent = len(line) - len(line.lstrip())
        continue

    if skip:
        current_indent = len(line) - len(line.lstrip())

        # Stop skipping when we reach another interface at the
        # same indentation level.
        if line.strip() and current_indent <= indent:
            skip = False
            output.append(line)

        # Otherwise this belongs to ens34 and is discarded.
        continue

    output.append(line)

# Remove trailing blank lines.
while output and not output[-1].strip():
    output.pop()

# Make sure the file has the required network structure.
if not any(line.startswith("network:") for line in output):
    output = [
        "network:\n",
        "  version: 2\n",
        "  ethernets:\n",
    ]
else:
    # Add ethernets section if necessary.
    if not any(line.strip() == "ethernets:" for line in output):
        output.append("  ethernets:\n")

# Add ens34.
output.extend([
    "    ens34:\n",
    "      dhcp4: false\n",
    f"      addresses:\n",
    f"        - {ip}/24\n",
])

with open(filename, "w") as f:
    f.writelines(output)
PY

# ------------------------------------------------------------
# Validate netplan
# ------------------------------------------------------------

echo
echo "Validating netplan..."

if ! netplan generate; then
    echo
    echo "ERROR: netplan configuration is invalid."
    echo "Your original configuration is backed up at:"
    echo "  $BACKUP_DIR"
    exit 1
fi

# ------------------------------------------------------------
# Apply hostname immediately
# ------------------------------------------------------------

hostnamectl set-hostname "$HOSTNAME"

# ------------------------------------------------------------
# Show resulting configuration
# ------------------------------------------------------------

echo
echo "======================================"
echo " Configuration complete"
echo "======================================"
echo
echo "/etc/hostname:"
cat /etc/hostname

echo
echo "/etc/hosts:"
cat /etc/hosts

echo
echo "/etc/netplan/50-cloud-init.yaml:"
cat /etc/netplan/50-cloud-init.yaml

echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo

read -rp "Reboot now? [y/N]: " REBOOT

if [[ "$REBOOT" =~ ^[Yy]$ ]]; then
    echo "Rebooting..."
    reboot
else
    echo
    echo "Not rebooting."
    echo "Run 'sudo reboot' when ready."
fi

