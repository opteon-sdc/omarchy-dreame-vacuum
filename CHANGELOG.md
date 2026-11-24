# Changelog

## 1.1.0 — 2026-11-24

- Routines: named presets of rooms with their own cleaning mode (vacuum, mop,
  both, mop after vacuuming), suction and passes, kept in
  `~/.config/dreame-vacuum/routines.json`. Run them from the panel (keys 1–9),
  with `dreame-vacuum routine <id>` or with `omarchy-shell dreame routine <id>`.
- Command errors show at the top of the panel in your language.
- Robot warnings (such as "clean the mop pad washboard") show as a quiet notice; only real errors turn the panel and bar icon red.
- Room cleaning lets you pick the mode and suction (`clean-rooms --mode … --suction …`); it refuses to start while a job is running, like routines.
- Tabs for status, routines, rooms, map and maintenance instead of one long panel; the suction picker left the panel (set it per routine or with the CLI).
- Status tab: progress of the current job room by room, dock activity (washing, drying, charging) and all-time totals.
- Zoomable map: scroll, pinch, double-click or +/− to zoom, drag to pan; the view stays put while the map updates.
- Notifications come from the service, once: "cleaning completed" only when the
  job is really done (not when the robot docks mid-job to wash its mop pads or
  recharge), errors only when a new one appears, and no duplicates with several monitors.
- The battery label on the bar keeps the bar's spacing; the icon is only coloured for errors.
- The map no longer blinks when it updates.

## 1.0.0 — 2026-11-24

- First release: bar widget and panel for Dreame robot vacuums.
- Start, pause, resume, stop, dock and locate; suction level; room cleaning with 1–3 passes.
- Live map, maintenance levels, error banner and notifications.
- `dreame-vacuum` CLI and user service built on Tasshack's dreame-vacuum library v2.0.3.
- English and Dutch.
