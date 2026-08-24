# Omarchy Security

A bar widget for [Omarchy](https://omarchy.org/) that answers one question at
a glance: *is anything about this machine's security posture worth my
attention right now?*

The shield in the bar takes the colour of the worst thing currently true.
Clicking it opens a panel that says what that thing is and what to do about
it.

## What it checks

**Firewall** — whether ufw is active, what the default incoming policy is,
and how many allow rules exist.

**Exposure** — every listening socket on the machine, correlated against the
ufw ruleset. This is the part that is hard to get from any single command: a
process listening on `0.0.0.0` is unremarkable, but a process listening on
`0.0.0.0` *that the firewall permits* is reachable by anyone on the network,
and that is what gets reported. Sockets bound to the tailnet, to a container
bridge, or to an address the machine no longer has are classified as such
rather than counted as exposure.

**Network** — the default route, Wi-Fi encryption (an open or WEP network is
a hard failure), the DNS resolver in use and whether DNS-over-TLS is on, and
whether the gateway's MAC address has changed since the last time this
machine was on that network.

**Integrity** — packages with published Arch security advisories via
`arch-audit`, packaged files that differ from their package, Secure Boot
state, root disk encryption, and whether the running kernel still exists on
disk (i.e. whether a reboot is needed to actually be running the patched
one).

## Architecture

The widget is unprivileged QML and never runs a privileged command. Opening
the panel cannot produce an authentication prompt, because there is nothing
to authenticate — the panel only reads a file.

```
root, on a systemd timer                     unprivileged, in omarchy-shell
──────────────────────────                   ──────────────────────────────
omarchy-security-collect  ──►  /run/omarchy-security/status.json     ──►  Panel.qml
  every 60s                                                               (reads only)
omarchy-security-audit    ──►  /run/omarchy-security/integrity.json  ──►
  hourly; file sweep once a day
```

The split exists because the two halves cost wildly different amounts.
`arch-audit` makes a network call and `pacman -Qkk` checksums every packaged
file on the system; neither belongs on a 60-second loop. Separate output
files mean the two collectors never race on a read-modify-write, and the
panel can honestly report each one's age.

A check that could not run reports `unknown`, which is deliberately not
`ok` — a security widget that shows green because it failed to look is worse
than no widget at all. Stale data also degrades the shield to `unknown`
rather than leaving the last known-good state on screen.

## Install

The plugin directory is the whole widget; the privileged collector needs
installing:

```bash
sudo ~/.config/omarchy/plugins/io.github.caseaustin12.security/system/install.sh
```

That installs two scripts to `/usr/local/bin`, four systemd units, a narrow
polkit rule (wheel members may `start` those two units, nothing else), and
`arch-audit` if it is missing.

Then add it to the bar in `~/.config/omarchy/shell.json`:

```json
{ "id": "io.github.caseaustin12.security" }
```

To remove the privileged half: `sudo .../system/uninstall.sh`.

## Interactions

| Input | Action |
|---|---|
| left click | open/close the panel |
| right / middle click | re-run both collectors now |
| `r` in the panel | re-run both collectors now |
| `esc` | close |

## Settings

Set these inline on the widget's entry in `shell.json`.

| Key | Default | Meaning |
|---|---|---|
| `showBadge` | `true` | Show a count of warnings beside the shield |
| `staleAfterSec` | `300` | Age past which the snapshot is treated as stale |
| `warnColor` | `""` | Override the amber used for warnings |
| `showLocalListeners` | `false` | Include loopback-only sockets in the exposure table |

## Licence

MIT
