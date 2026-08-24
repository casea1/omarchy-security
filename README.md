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
{ "id": "io.github.caseaustin12.security" }
```

For the optional extras, click **Enable full checks** in the panel (it asks
for your password once via pkexec), or run it yourself:

```bash
sudo ~/.config/omarchy/plugins/io.github.caseaustin12.security/system/install.sh
```

It is safe to re-run, and re-running is how you pick up updates to the
collector scripts. To remove just the privileged half:
`sudo .../system/uninstall.sh`.

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
