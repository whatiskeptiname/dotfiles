#!/usr/bin/env python3
"""Small pomodoro panel, opened by right-clicking custom/pomodoro on the bar.

Shows the current timer with start/pause, skip and reset, plus the durations,
which it saves to ~/.config/waybar-pomodoro.conf. All timer logic stays in
pomodoro.sh; this only calls it (`info`, `toggle`, `skip`, `stop`).

Running it while it's already open closes it, so right-click toggles it.
It also closes on Escape or on any click outside it: the window is a
transparent layer covering the whole output (bar included), with the panel
drawn in it, so a click anywhere else lands on the window and closes it right
away, like a popup menu. (Focus loss can't be used: sway hands an on-demand
layer surface focus when it maps and takes it straight back.)
"""

import json
import os
import re
import signal
import subprocess
import sys
from ctypes import CDLL
from pathlib import Path

# gtk4-layer-shell has to be loaded before libwayland-client, i.e. before Gtk.
CDLL("libgtk4-layer-shell.so.0")

import gi  # noqa: E402

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, GLib, Gtk, Gtk4LayerShell as LayerShell  # noqa: E402

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "pomodoro.sh"
COLORS = HERE.parent / "colors" / "colors.dark.css"
RUNTIME_CONFIG = Path("/tmp/waybar-runtime.jsonc")  # written by burn-in.sh
RUNTIME_CSS = Path("/tmp/waybar-runtime.css")
CONF = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "waybar-pomodoro.conf"
PIDFILE = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "waybar-pomodoro-panel.pid"

# (key in pomodoro.sh / info, label, min, max, unit)
SETTINGS = [
    ("work", "Work", 1, 180, "min"),
    ("short", "Short break", 1, 60, "min"),
    ("long", "Long break", 1, 120, "min"),
    ("long_every", "Long break every", 2, 12, "sessions"),
]
SWITCHES = [
    ("sound", "Sound"),
    ("autostart", "Start work after a break"),
]


def toggle_existing():
    """If a panel is already open, close it and report True."""
    try:
        pid = int(PIDFILE.read_text())
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes()
    except (OSError, ValueError):
        return False
    if b"pomodoro-panel" not in cmdline:
        return False
    os.kill(pid, signal.SIGTERM)
    return True


def sh(*args):
    out = subprocess.run([str(SCRIPT), *args], capture_output=True, text=True)
    return out.stdout


def palette():
    colors = {"fg": "#acb0d0", "bg": "rgba(8, 8, 11, 0.95)", "inactive": "#787c99",
              "red": "#f7768e", "green": "#41a6b5", "yellow": "#e0af68", "blue": "#7aa2f7"}
    try:
        for name, value in re.findall(r"@define-color\s+([\w-]+)\s+([^;@]+);", COLORS.read_text()):
            colors[name] = value.strip()
    except OSError:
        pass
    colors["accent"] = colors["blue"]
    try:  # burn-in.sh's per-boot accent, so the panel matches the clock
        found = re.findall(r"#custom-pomodoro\s*\{\s*color:\s*(#[0-9a-fA-F]{6})", RUNTIME_CSS.read_text())
        if found:
            colors["accent"] = found[-1]
    except OSError:
        pass
    return colors


def bar_geometry():
    """(at_bottom, height) of the bar, from the config burn-in.sh generated."""
    try:
        text = RUNTIME_CONFIG.read_text()
    except OSError:
        return False, 30
    height = re.search(r'"height":\s*(\d+)', text)
    return '"position": "bottom"' in text, int(height.group(1)) if height else 30


CSS = """
window { background: transparent; }
.panel {
    background: {bg};
    color: {fg};
    border-radius: 14px;
    border-bottom: 2px solid {accent};
    padding: 14px 18px;
    font-family: 'CaskaydiaCove Nerd Font Propo';
    font-weight: 700;
}
.phase { font-size: 13px; color: {inactive}; }
.time { font-size: 40px; color: {accent}; }
.time.work { color: {red}; }
.time.break { color: {green}; }
.time.paused { color: {inactive}; }
.time.ready { color: {yellow}; }
.dots { font-size: 16px; letter-spacing: 4px; color: {accent}; }
button {
    background: rgba(255, 255, 255, 0.06);
    color: {fg};
    border: none;
    border-radius: 10px;
    padding: 4px 12px;
    box-shadow: none;
    font-weight: 700;
}
button:hover { background: rgba(255, 255, 255, 0.12); }
button.primary { background: {accent}; color: #08080b; }
.setting { font-size: 12px; }
.unit { font-size: 11px; color: {inactive}; }
.hint { font-size: 10px; color: {inactive}; }
spinbutton { background: rgba(255, 255, 255, 0.06); border: none; border-radius: 8px; color: {fg}; }
spinbutton button { padding: 0 6px; background: transparent; }
switch { background: rgba(255, 255, 255, 0.12); border: none; }
switch:checked { background: {accent}; }
switch slider { background: {fg}; }
separator { background: rgba(255, 255, 255, 0.08); margin: 4px 0; }
"""


class Panel(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Pomodoro")
        self.loading = False

        LayerShell.init_for_window(self)
        LayerShell.set_namespace(self, "pomodoro-panel")
        LayerShell.set_layer(self, LayerShell.Layer.OVERLAY)
        LayerShell.set_keyboard_mode(self, LayerShell.KeyboardMode.ON_DEMAND)
        # Cover the whole output, bar included (-1 ignores its exclusive
        # zone), so every click outside the panel reaches us. The panel sits
        # centered just past the bar, whichever edge burn-in.sh put it on.
        for e in (LayerShell.Edge.TOP, LayerShell.Edge.BOTTOM,
                  LayerShell.Edge.LEFT, LayerShell.Edge.RIGHT):
            LayerShell.set_anchor(self, e, True)
        LayerShell.set_exclusive_zone(self, -1)
        at_bottom, bar_height = bar_geometry()

        provider = Gtk.CssProvider()
        css = CSS
        for name, value in palette().items():
            css = css.replace("{" + name + "}", value)
        provider.load_from_string(css)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.add_css_class("panel")
        box.set_size_request(280, -1)
        box.set_halign(Gtk.Align.CENTER)
        if at_bottom:
            box.set_valign(Gtk.Align.END)
            box.set_margin_bottom(bar_height + 6)
        else:
            box.set_valign(Gtk.Align.START)
            box.set_margin_top(bar_height + 6)
        self.panel = box
        self.set_child(box)

        self.phase = Gtk.Label(css_classes=["phase"])
        self.time = Gtk.Label(css_classes=["time"])
        self.dots = Gtk.Label(css_classes=["dots"])
        for w in (self.phase, self.time, self.dots):
            box.append(w)

        buttons = Gtk.Box(spacing=6, halign=Gtk.Align.CENTER, margin_top=4)
        self.primary = Gtk.Button(css_classes=["primary"])
        self.primary.connect("clicked", lambda *_: self.act("toggle"))
        self.skip = Gtk.Button(label="󰒭 Skip", tooltip_text="End this phase now")
        self.skip.connect("clicked", lambda *_: self.act("skip"))
        self.reset = Gtk.Button(label="󰑓 Reset", tooltip_text="Stop and go back to the clock")
        self.reset.connect("clicked", lambda *_: self.act("stop"))
        for b in (self.primary, self.skip, self.reset):
            buttons.append(b)
        box.append(buttons)

        box.append(Gtk.Separator())

        grid = Gtk.Grid(column_spacing=8, row_spacing=6)
        self.spins = {}
        for row, (key, label, lo, hi, unit) in enumerate(SETTINGS):
            grid.attach(Gtk.Label(label=label, xalign=0, hexpand=True, css_classes=["setting"]), 0, row, 1, 1)
            spin = Gtk.SpinButton.new_with_range(lo, hi, 1)
            spin.connect("value-changed", self.save)
            grid.attach(spin, 1, row, 1, 1)
            grid.attach(Gtk.Label(label=unit, xalign=0, css_classes=["unit"]), 2, row, 1, 1)
            self.spins[key] = spin
        self.switches = {}
        for i, (key, label) in enumerate(SWITCHES, start=len(SETTINGS)):
            grid.attach(Gtk.Label(label=label, xalign=0, css_classes=["setting"]), 0, i, 2, 1)
            sw = Gtk.Switch(halign=Gtk.Align.END, valign=Gtk.Align.CENTER)
            sw.connect("notify::active", self.save)
            grid.attach(sw, 2, i, 1, 1)
            self.switches[key] = sw
        box.append(grid)
        box.append(Gtk.Label(label="New durations apply from the next phase",
                             css_classes=["hint"], margin_top=2))

        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self.on_key)
        self.add_controller(keys)
        clicks = Gtk.GestureClick(button=0)  # any button
        clicks.connect("pressed", self.on_press)
        self.add_controller(clicks)
        # The pointer leaving the window means it went to another monitor.
        motion = Gtk.EventControllerMotion()
        motion.connect("leave", lambda *_: self.close())
        self.add_controller(motion)
        self.connect("close-request", self.on_close)

        info = self.refresh()
        self.loading = True
        for key, spin in self.spins.items():
            spin.set_value(info.get(key, spin.get_value()))
        for key, sw in self.switches.items():
            sw.set_active(bool(info.get(key, 0)))
        self.loading = False
        GLib.timeout_add(1000, lambda: self.refresh() is not None)

    def refresh(self):
        try:
            info = json.loads(sh("info"))
        except json.JSONDecodeError:
            return {}
        phase, status = info["phase"], info["status"]
        secs = info["remaining"]
        self.time.set_text(f"{secs // 60:02d}:{secs % 60:02d}")

        names = {"work": f"Work session {info['count'] + 1}", "short": "Short break",
                 "long": "Long break", "idle": "Ready to focus"}
        text = names[phase]
        if status == "paused":
            text += " · paused"
        elif status == "ready":
            text = f"Break over · next: {names['work']}"
        self.phase.set_text(text)

        kind = {"running": "work" if phase == "work" else "break",
                "paused": "paused", "ready": "ready"}.get(status, "")
        self.time.set_css_classes(["time"] + ([kind] if kind else []))

        every = info["long_every"]
        filled = info["count"] % every
        if phase == "long":
            filled = every
        self.dots.set_text("●" * filled + "○" * (every - filled))

        self.primary.set_label({"running": "󰏤 Pause", "paused": "󰐊 Resume"}.get(status, "󰐊 Start"))
        self.skip.set_sensitive(phase != "idle")
        self.reset.set_sensitive(phase != "idle")
        return info

    def act(self, cmd):
        sh(cmd)
        self.refresh()

    def save(self, *_):
        if self.loading:
            return
        lines = [f"{k.upper()}={int(s.get_value())}" for k, s in self.spins.items()]
        lines += [f"{k.upper()}={int(s.get_active())}" for k, s in self.switches.items()]
        tmp = CONF.with_suffix(".tmp")
        tmp.write_text("# Written by waybar/scripts/pomodoro-panel.py\n" + "\n".join(lines) + "\n")
        tmp.replace(CONF)
        self.refresh()  # idle countdown shows the new work length
        subprocess.run(["pkill", "-RTMIN+9", "-x", "waybar"])

    def on_key(self, _ctl, keyval, *_):
        if keyval == Gdk.KEY_Escape:
            self.close()
            return True
        return False

    def on_press(self, _gesture, _n, x, y):
        hit = self.pick(x, y, Gtk.PickFlags.DEFAULT)
        if hit is None or not (hit == self.panel or hit.is_ancestor(self.panel)):
            self.close()

    def on_close(self, *_):
        for spin in self.spins.values():
            spin.update()  # commit a half-typed value before closing
        return False

def main():
    if toggle_existing():
        return 0
    PIDFILE.write_text(str(os.getpid()))
    app = Gtk.Application(application_id=None)
    app.connect("activate", lambda a: Panel(a).present())
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, lambda: app.quit() or False)
    try:
        return app.run([])
    finally:
        try:
            if PIDFILE.read_text() == str(os.getpid()):
                PIDFILE.unlink()
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
