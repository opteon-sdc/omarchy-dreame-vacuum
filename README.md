# Dreame Vacuum for Omarchy

Control your Dreame robot vacuum from the [Omarchy](https://omarchy.org) bar:
start, pause, dock, locate, suction level, room cleaning and the live map.
It runs without Home Assistant, using the device library from
[Tasshack/dreame-vacuum](https://github.com/Tasshack/dreame-vacuum) ([docs](https://dv.tasshack.com)).

## Features

- **One-click control:** Start/Pause, Stop, Dock and Locate. Middle-click the bar icon to start or pause.
- **Suction:** set per routine, or with `dreame-vacuum suction quiet|standard|strong|turbo`.
- **Routines:** one click for your usual jobs, such as "living room: mop after vacuuming" or "bedrooms and hallway: vacuum only".
- **Room cleaning:** pick rooms from your saved map, then the mode (vacuum, mop, both, or mop after vacuuming), suction and 1–3 passes. Mode and suction start on what the robot is set to now.
- **Tabs** keep the panel short: Status, Routines, Rooms, Map and Maintenance under the controls.
- **Status tab:** the job in progress: task and progress, area, time, mode, which rooms are done, being cleaned, still to do or skipped, what the dock is doing (washing or drying the pads, charging), and all-time totals.
- **Live map** you can zoom (scroll, pinch, double-click or +/−) and drag around.
- **Live status:** battery, current room, cleaned area and time.
- **Maintenance:** main brush, side brush, filter (and mop/sensors when the robot has them).
- **Notifications** when a job is really finished (not when the robot docks mid-job to wash its mop pads or recharge) and when a new error appears.
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

## Routines

Routines live in `~/.config/dreame-vacuum/routines.json`. `setup` writes an
example the first time; edit it, and the panel picks up the changes within half a minute.

```json
{
  "routines": [
    { "id": "living", "name": "Living", "rooms": ["Living Room"], "mode": "mopping_after_sweeping" },
    {
      "id": "nachtzone",
      "name": "Slaapkamer, dressing, badkamer & gang",
      "rooms": ["Primary Bedroom", "Closet", "Bathroom", "Corridor"],
      "mode": "sweeping"
    }
  ]
}
```

| Field | | |
|---|---|---|
| `id` | required | Letters, digits, `-` and `_`; used by the CLI and keybindings |
| `name` | | Shown in the panel |
| `rooms` | required | Room names as `dreame-vacuum rooms` shows them (case does not matter), or room ids |
| `mode` | optional | `sweeping`, `mopping`, `sweeping_and_mopping` or `mopping_after_sweeping` |
| `suction` | optional | `quiet`, `standard`, `strong` or `turbo` |
| `repeats` | optional | 1–3 passes |

Leave out `mode` or `suction` to keep what the robot has set. The robot keeps the
routine's mode and suction after the job, just as when you change them in the app.
A routine's mode only applies when per-room settings ("customized cleaning") and
CleanGenius are off in the Dreame app; otherwise the panel tells you so.
If the robot is busy cleaning, the routine refuses to start; a paused job is stopped first.

## Command line

```bash
dreame-vacuum status
dreame-vacuum start | pause | toggle | stop | dock | locate
dreame-vacuum suction turbo
dreame-vacuum rooms
dreame-vacuum clean-rooms 1 3 --repeats 2 --mode sweeping --suction turbo
dreame-vacuum routines
dreame-vacuum routine living
dreame-vacuum --output json watch     # state as JSON lines
```

## Keybindings

`omarchy-shell dreame <function>` works from Hyprland bindings. The functions are `toggle` (panel),
`start`, `pause`, `playPause`, `stop`, `dock`, `locate` and `routine <id>`. For example, in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + V", "Vacuum start/pause", "omarchy-shell dreame playPause")
o.bind("SUPER + ALT + L", "Vacuum the living room", "omarchy-shell dreame routine living")
```

In the panel: <kbd>Space</kbd> start/pause, <kbd>S</kbd> stop, <kbd>H</kbd> dock,
<kbd>L</kbd> locate, <kbd>1</kbd>–<kbd>9</kbd> run a routine, <kbd>←</kbd>/<kbd>→</kbd> switch tabs;
on the map tab <kbd>+</kbd>/<kbd>−</kbd> zoom and <kbd>0</kbd> shows the whole map.

## Settings

| Setting | Default | |
|---|---|---|
| `barLabel` | `cleaning` | Battery next to the icon: `cleaning`, `always`, `never` |
| `notify` | `true` | Notify when a job finishes or on errors |
| `defaultTab` | `status` | Tab the panel opens on: `status`, `routines`, `rooms`, `map`, `care` |
| `showMap` | `true` | Show the map tab |
| `panelWidth` | `420` | Panel width |
| `cliPath` | `""` | Path to `dreame-vacuum`; empty uses PATH |

## Troubleshooting

Every notification the service sends is logged:
`journalctl --user -u dreame-vacuum | grep Notify`.

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
