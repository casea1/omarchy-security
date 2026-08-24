#!/usr/bin/env bash
# Installs the privileged half of the Omarchy security widget.
#
# The widget itself is unprivileged QML and needs no installation — it is
# already in ~/.config/omarchy/plugins. What this puts in place is the root
# collector that gives it something to read.
#
# Run with sudo:  sudo ./install.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR=/usr/local/bin
UNIT_DIR=/etc/systemd/system
RULE_DIR=/etc/polkit-1/rules.d

if [ "$(id -u)" -ne 0 ]; then
  echo "This installs system units and must run as root:  sudo $0" >&2
  exit 1
fi

echo "==> Installing collectors into $BIN_DIR"
install -Dm755 "$HERE/omarchy-security-collect" "$BIN_DIR/omarchy-security-collect"
install -Dm755 "$HERE/omarchy-security-audit"   "$BIN_DIR/omarchy-security-audit"

echo "==> Installing systemd units into $UNIT_DIR"
for unit in omarchy-security-collect.service omarchy-security-collect.timer \
            omarchy-security-audit.service   omarchy-security-audit.timer; do
  install -Dm644 "$HERE/$unit" "$UNIT_DIR/$unit"
done

echo "==> Installing polkit rule into $RULE_DIR"
install -Dm644 "$HERE/49-omarchy-security.rules" "$RULE_DIR/49-omarchy-security.rules"

if ! command -v arch-audit >/dev/null 2>&1; then
  echo "==> Installing arch-audit (maps installed packages to Arch advisories)"
  pacman -S --needed --noconfirm arch-audit || \
    echo "    could not install arch-audit; the CVE check will report 'unknown'"
fi

echo "==> Enabling timers"
systemctl daemon-reload
systemctl enable --now omarchy-security-collect.timer
systemctl enable --now omarchy-security-audit.timer

echo "==> Priming the first snapshot"
systemctl start omarchy-security-collect.service
# The audit sweep checksums every packaged file on a first run, so it is
# kicked off without blocking the installer on it.
systemctl start --no-block omarchy-security-audit.service

echo
echo "Done. The fast collector runs every 60s, the audit hourly."
echo "Snapshot: /run/omarchy-security/status.json"
if [ -r /run/omarchy-security/status.json ]; then
  echo
  jq -r '.sections | to_entries[] | "  \(.key): \(.value.status) — \(.value.summary)"' \
    /run/omarchy-security/status.json 2>/dev/null || true
fi
