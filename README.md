# Dreame Vacuum for Omarchy

Control your Dreame robot vacuum from the [Omarchy](https://omarchy.org) bar:
start, pause, dock, locate, suction level, room cleaning and the live map.
It runs without Home Assistant, using the device library from
[Tasshack/dreame-vacuum](https://github.com/Tasshack/dreame-vacuum) ([docs](https://dv.tasshack.com)).

## Features

- **One-click control:** Start/Pause, Stop, Dock and Locate. Middle-click the bar icon to start or pause.
- **Suction:** Quiet, Standard, Strong, Turbo.
- **Room cleaning:** pick rooms from your saved map, choose 1–3 passes, clean.
- **Live status:** battery, current room, cleaned area and time, and a live map image.
- **Maintenance:** main brush, side brush, filter (and mop/sensors when the robot has them).
- **Notifications** when a job finishes or the robot reports an error.
- Follows your Omarchy theme, fonts and language (English, Dutch; robot states in every language the library supports).

## How it works

```
Omarchy bar  ──►  dreame-vacuum (client)  ──►  dreame-vacuum serve (user service)  ──►  Dreamehome cloud  ──►  robot
                   Unix socket, JSON                Tasshack's dreame library
```

The service logs in once and keeps the connection open, so commands answer at once.
The plugin, your terminal and your keybindings all use the same `dreame-vacuum` command.

## Installation

```bash
omarchy plugin add https://github.com/opteon-sdc/omarchy-dreame-vacuum --enable
~/.config/omarchy/plugins/io.github.opteon-sdc.dreame/setup
```

`setup` creates a private Python environment in `~/.local/share/dreame-vacuum`,
downloads the dreame library v2.0.3 (checksum verified), installs `~/.local/bin/dreame-vacuum`,
starts the `dreame-vacuum` user service and asks you to log in.

To log in again later, or to switch robots:

```bash
dreame-vacuum login            # Dreamehome e-mail, password and region (eu, us, …)
systemctl --user restart dreame-vacuum
```

The panel's **Log in** button does the same in a terminal.

Your login is stored in `~/.config/dreame-vacuum/config.json` (mode 600), just as the
Home Assistant integration stores it. `dreame-vacuum logout` removes it.

## Command line

```bash
dreame-vacuum status
dreame-vacuum start | pause | toggle | stop | dock | locate
dreame-vacuum suction turbo
dreame-vacuum rooms
dreame-vacuum clean-rooms 1 3 --repeats 2
dreame-vacuum --output json watch     # state as JSON lines
```

## Keybindings

`omarchy-shell dreame <function>` works from Hyprland bindings. The functions are `toggle` (panel),
`start`, `pause`, `playPause`, `stop`, `dock` and `locate`. For example, in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + V", "Vacuum start/pause", "omarchy-shell dreame playPause")
```

In the panel: <kbd>Space</kbd> start/pause, <kbd>S</kbd> stop, <kbd>H</kbd> dock,
<kbd>L</kbd> locate, <kbd>1</kbd>–<kbd>4</kbd> suction level.

## Settings

| Setting | Default | |
|---|---|---|
| `barLabel` | `cleaning` | Battery next to the icon: `cleaning`, `always`, `never` |
| `notify` | `true` | Notify when a job finishes or on errors |
| `showMap` | `true` | Show the live map in the panel |
| `panelWidth` | `420` | Panel width |
| `cliPath` | `""` | Path to `dreame-vacuum`; empty uses PATH |

## Troubleshooting

```bash
systemctl --user status dreame-vacuum
journalctl --user -u dreame-vacuum -f
```

For a detailed log, run the service by hand: `systemctl --user stop dreame-vacuum; dreame-vacuum serve -v`.

## Development

`tests/check.sh` runs the static checks. `tests/fake-dreame-vacuum` is a demo robot:
set `cliPath` to it to try the panel without an account.

## Credits and license

MIT. The device protocol, map renderer and translations come from
[Tasshack/dreame-vacuum](https://github.com/Tasshack/dreame-vacuum) (MIT); setup downloads them, and this repository does not include them.
This project is not affiliated with Dreame Technology.
