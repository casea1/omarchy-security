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

**The widget needs nothing installed.** It is unprivileged QML that runs the
two collector scripts itself, as you, on a timer. Opening the panel cannot
produce an authentication prompt, because there is nothing to authenticate.

That works because almost nothing here actually needs privilege:

- `ufw status` refuses to run as anyone but root, but every file it reads is
  world-readable, and the `### tuple ###` lines in `/etc/ufw/user.rules` are a
  *better* source than its output — application profiles arrive already
  expanded into concrete ports, which the human-facing table leaves ambiguous.
- The advisory database is a public JSON document, and `vercmp` ships with
  pacman, so the CVE check is a join anyone can compute.
- Listening sockets, routes, DNS, Wi-Fi, Secure Boot, LUKS and kernel state
  are all readable by an ordinary user.

```
default                                     optional (system/install.sh)
───────────────────────────────────         ──────────────────────────────────
Panel.qml runs the collectors as you        systemd timers run them as root
  ↓                                           ↓
$XDG_RUNTIME_DIR/omarchy-security/          /run/omarchy-security/
  ↓                                           ↓
        Service.qml reads whichever snapshot is newer
```

### What root actually buys

Two things, both marked in the panel rather than silently missing:

1. **Process attribution.** `ss` will not name a socket owned by another
   user, so system daemons show as `—` until the collector runs as root.
2. **A complete file-integrity sweep.** An ordinary user cannot read every
   packaged file; those are counted as *unreadable*, never as *unchanged*.

The optional installer also pulls in `arch-audit`. The built-in fallback was
cross-checked against it and reports the identical package set, so this is a
convenience rather than a requirement.

### Design rules

A check that could not run reports `unknown`, which is deliberately not
`ok` — a security widget that shows green because it failed to look is worse
than no widget. Stale data degrades the shield to `unknown` rather than
leaving the last known-good state on screen.

Severity tracks what you can *act on*. An advisory with a published fix you
have not installed is a failure. An advisory upstream has not fixed yet is a
warning, because turning the icon red for something nobody can install helps
no one.

The two collectors are split because they cost wildly different amounts:
`arch-audit` makes a network call and `pacman -Qkk` checksums every packaged
file, so neither belongs on a 60-second loop. Separate output files mean they
never race on a read-modify-write, and the panel reports each one's age.

## Install

Nothing to do. Add it to the bar in `~/.config/omarchy/shell.json`:

```json
{ "id": "io.github.casea1.security" }
```

For the optional extras, click **Enable full checks** in the panel (it asks
for your password once via pkexec), or run it yourself:

```bash
sudo ~/.config/omarchy/plugins/io.github.casea1.security/system/install.sh
```

It is safe to re-run, and re-running is how you pick up updates to the
collector scripts. To remove just the privileged half:
`sudo .../system/uninstall.sh`.

## Remove

```bash
omarchy plugin remove io.github.casea1.security
```

That removes the widget and its bar entry. If you never clicked **Enable full
checks**, nothing else was ever installed and you are done.

If you did, the privileged half lives outside the plugin directory and
`omarchy plugin remove` cannot reach it. Remove it *before* removing the
plugin, while the script is still on disk:

```bash
sudo ~/.config/omarchy/plugins/io.github.casea1.security/system/uninstall.sh
```

It stops and deletes both timers, both units, `/usr/local/bin/omarchy-security-*`,
the polkit rule, `/run/omarchy-security` and `/var/lib/omarchy-security`. If you
have already deleted the plugin directory, the same thing by hand:

```bash
sudo systemctl disable --now omarchy-security-collect.timer omarchy-security-audit.timer
sudo rm -f /etc/systemd/system/omarchy-security-{collect,audit}.{service,timer} \
           /usr/local/bin/omarchy-security-{collect,audit} \
           /etc/polkit-1/rules.d/49-omarchy-security.rules
sudo systemctl daemon-reload
sudo rm -rf /run/omarchy-security /var/lib/omarchy-security
```

`arch-audit`, if the installer added it, is left alone — drop it with
`omarchy pkg drop arch-audit` if nothing else needs it.

## What this plugin does to your system

Stated plainly, because a security widget asking for a password deserves it.

**Without the optional installer** it writes one JSON snapshot into your own
runtime directory and reads files. It runs `ufw`-adjacent *reads* only, never
`ufw` itself. It makes one network request, to `security.archlinux.org`, for
the public advisory database, cached for six hours. That is all.

**With the installer**, run once via `pkexec`, it adds:

| Path | What |
|---|---|
| `/usr/local/bin/omarchy-security-{collect,audit}` | the two collector scripts |
| `/etc/systemd/system/omarchy-security-*.{service,timer}` | two timers |
| `/etc/polkit-1/rules.d/49-omarchy-security.rules` | lets `wheel` **start** those two units, nothing else |
| `arch-audit` | if not already installed |

The polkit rule is deliberately narrow: it grants `start` on two named
oneshot units to members of `wheel`, and grants nothing else. The collectors
only read; the single file each writes is a JSON snapshot.

Action buttons run commands in a terminal, where you can see them. Those
commands are composed inside the collector from a fixed vocabulary — never
assembled from panel state — and any package name interpolated into one is
filtered to `[A-Za-z0-9@._+-]` first.

## Reading the panel

The panel shows **problems, not inventory**. Each section prints the checks
that need attention and folds the rest into one line — `4 checks passed` —
which you can click to see them. Facts that are not findings (rule counts,
socket totals, the resolver in use) live in the section summary on the right
rather than taking a row each.

The exposure table follows the same rule: collapsed, it lists only sockets
something can actually reach. Expand the section for the full picture.

A check that does not apply is not rendered at all. There is no "Wi-Fi
encryption: not on Wi-Fi" row, because that is not reassurance, it is noise.

## Actions

Findings carry buttons that do the thing rather than telling you what to
type. Anything that runs opens in a terminal, so `sudo` can prompt and the
output stays on screen; the window holds open until you press a key, so a
command that fails is still readable. Buttons marked `↗` open a browser.

| Finding | Buttons |
|---|---|
| Known vulnerabilities | List affected · Advisory details ↗ · Update system |
| Packaged file integrity | Show what changed · Reinstall packages |
| Secure Boot disabled | How to enable ↗ · Show boot state |
| ufw off / incoming allowed | Enable firewall · Deny incoming |
| Something reachable | Show ufw rules · Show listeners |
| SSH server enabled | Disable SSH server · Show SSH config |
| Gateway MAC changed | Accept new gateway · Show ARP table |
| Kernel replaced on disk | Reboot now (asks first) |

Commands are composed in the collector, from a fixed vocabulary — never
assembled in the QML from panel state. Package names interpolated into a
command are filtered to `[A-Za-z0-9@._+-]` first, so nothing that did not
come from pacman reaches a command line.

## Interactions

| Input | Action |
|---|---|
| left click | open/close the panel |
| right / middle click | re-run the collectors now |
| click a section header | expand or collapse it |
| `e` | expand or collapse everything |
| `r` | re-run the collectors now |
| `esc` | close |

## Settings

Set these inline on the widget's entry in `shell.json`.

| Key | Default | Meaning |
|---|---|---|
| `showBadge` | `true` | Show a count of warnings beside the shield |
| `staleAfterSec` | `300` | Age past which the snapshot is treated as stale |
| `warnColor` | `""` | Override the amber used for warnings |
| `showLocalListeners` | `false` | Include loopback-only sockets when the exposure section is expanded |

## Licence

MIT
