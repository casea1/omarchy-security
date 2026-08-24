#!/usr/bin/env bash
# Removes the privileged half installed by install.sh. The plugin directory
# under ~/.config/omarchy/plugins is left alone; delete it yourself if you
# also want the widget gone.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root:  sudo $0" >&2
  exit 1
fi

systemctl disable --now omarchy-security-collect.timer omarchy-security-audit.timer 2>/dev/null || true
rm -f /etc/systemd/system/omarchy-security-{collect,audit}.{service,timer}
rm -f /usr/local/bin/omarchy-security-{collect,audit}
rm -f /etc/polkit-1/rules.d/49-omarchy-security.rules
systemctl daemon-reload
rm -rf /run/omarchy-security /var/lib/omarchy-security

echo "Removed. The plugin directory was left in place."
