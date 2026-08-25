#!/usr/bin/env bash
# OPTIONAL. The widget works without any of this.
#
# Everything that matters is already readable without privilege: ufw keeps
# its ruleset in world-readable files, and the advisory database is a public
# document. The widget runs the collectors itself, as you, on a timer.
#
# What this adds:
#   * names for listening sockets owned by other users (ss needs root)
#   * a complete file-integrity sweep (a user cannot read every packaged file)
#   * arch-audit, the reference advisory checker
#   * collection on a system timer, so data is fresh before you open the panel
#
# Safe to re-run; it overwrites in place and is how you pick up updates.
#
# Run with sudo:  sudo ./install.sh   (the widget's button does this via pkexec)

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

# A root timer has no idea whose desktop it serves, so the widget's own
# settings would be invisible to it. Record the installing user's shell.json
# so `checkAdvisories` governs the privileged collector too.
INVOKER=${PKEXEC_UID:+$(getent passwd "$PKEXEC_UID" | cut -d: -f1)}
INVOKER=${INVOKER:-${SUDO_USER:-}}
if [ -n "$INVOKER" ]; then
  INVOKER_HOME=$(getent passwd "$INVOKER" | cut -d: -f6)
  if [ -n "$INVOKER_HOME" ]; then
    echo "==> Pointing the audit timer at $INVOKER's settings"
    mkdir -p "$UNIT_DIR/omarchy-security-audit.service.d"
    cat > "$UNIT_DIR/omarchy-security-audit.service.d/config.conf" <<CONF
[Service]
Environment=OMARCHY_SECURITY_CONFIG=$INVOKER_HOME/.config/omarchy/shell.json
CONF
  fi
fi

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
echo "The widget will prefer this snapshot and stop collecting on its own."
echo "Snapshot: /run/omarchy-security/status.json"
if [ -r /run/omarchy-security/status.json ]; then
  echo
  jq -r '.sections | to_entries[] | "  \(.key): \(.value.status) — \(.value.summary)"' \
    /run/omarchy-security/status.json 2>/dev/null || true
fi
