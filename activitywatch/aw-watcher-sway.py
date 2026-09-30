#!/usr/bin/env python3
"""ActivityWatch watcher for sway.

Feeds three buckets on the local aw-server:
  aw-watcher-window_<host>      focused window {app, title}  (stock bucket, so
                                the web UI's Activity view works unchanged)
  aw-watcher-afk_<host>         {status: afk|not-afk} — no input for IDLE_TIMEOUT,
                                unless the focused app is playing media
  aw-watcher-sway-media_<host>  media playing in a window you're NOT focused on
                                (e.g. a video on the second monitor), or from an
                                app with no visible window (music in the background)

Unfocused windows that aren't playing anything count as nothing, the same as
every mainstream tracker. See the "Usage Tracking" section of the README.
"""

import json
import os
import re
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

import i3ipc

AW_URL = os.environ.get("AW_URL", "http://localhost:5600/api/0")
HOST = socket.gethostname()
CLIENT = "aw-watcher-sway"
IDLE_TIMEOUT = 180   # seconds without input before AFK (ActivityWatch's default)
WINDOW_POLL = 1      # focused-window heartbeat interval
MEDIA_POLL = 5       # afk/media heartbeat interval (spawns pactl/playerctl)

BUCKET_WINDOW = f"aw-watcher-window_{HOST}"
BUCKET_AFK = f"aw-watcher-afk_{HOST}"
BUCKET_MEDIA = f"aw-watcher-sway-media_{HOST}"


# ── ActivityWatch REST ────────────────────────────────────────────────────
def _request(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{AW_URL}{path}", data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=5) as resp:
        return resp.read()


def ensure_bucket(bucket_id, event_type):
    try:
        _request("POST", f"/buckets/{bucket_id}",
                 {"client": CLIENT, "type": event_type, "hostname": HOST})
    except urllib.error.HTTPError as e:
        if e.code != 304:  # 304 = bucket already exists
            raise


def heartbeat(bucket_id, data, pulsetime):
    event = {"timestamp": datetime.now(timezone.utc).isoformat(),
             "duration": 0, "data": data}
    _request("POST", f"/buckets/{bucket_id}/heartbeat?pulsetime={pulsetime}", event)


# ── Input idle (ext-idle-notify via swayidle) ─────────────────────────────
class IdleMonitor:
    """Runs a private swayidle that just echoes state changes to us."""

    def __init__(self, timeout):
        self.idle = False
        self.proc = subprocess.Popen(
            ["swayidle", "-w", "timeout", str(timeout), "echo idle",
             "resume", "echo active"],
            stdout=subprocess.PIPE, text=True)
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.proc.stdout:
            self.idle = line.strip() == "idle"
        # swayidle died (sway gone?) — exit so systemd restarts us cleanly
        os._exit(1)


# ── Window / media discovery ──────────────────────────────────────────────
def norm(name):
    """'Google Chrome' / 'google-chrome' / 'Google-chrome' → 'googlechrome'."""
    return re.sub(r"[^a-z0-9]", "", (name or "").lower())


def app_of(con):
    return con.app_id or con.window_class or "unknown"  # window_class = XWayland


def windows(tree):
    """Yield (con, output_name) for every real window."""
    for output in tree.nodes:
        if output.name == "__i3":
            continue
        for con in output.descendants():
            if con.ipc_data.get("pid") and con.type in ("con", "floating_con"):
                yield con, output.name


def ancestors(pid):
    """pid and all its parent pids (audio often comes from a child process)."""
    seen = set()
    while pid and pid > 1 and pid not in seen:
        seen.add(pid)
        try:
            with open(f"/proc/{pid}/stat") as f:
                # comm may contain spaces/parens — ppid is 2nd field after ')'
                pid = int(f.read().rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            break
    return seen


def media_sources():
    """Currently-playing sources as [(pid or None, name)]."""
    sources = []
    try:
        out = subprocess.run(["pactl", "-f", "json", "list", "sink-inputs"],
                             capture_output=True, text=True, timeout=3).stdout
        for s in json.loads(out or "[]"):
            if s.get("corked"):
                continue
            props = s.get("properties", {})
            pid = props.get("application.process.id")
            sources.append((int(pid) if pid and pid.isdigit() else None,
                            props.get("application.name") or
                            props.get("application.process.binary")))
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        pass
    try:
        out = subprocess.run(["playerctl", "-a", "-f", "{{playerInstance}}\t{{status}}", "status"],
                             capture_output=True, text=True, timeout=3).stdout
        for line in out.splitlines():
            inst, _, status = line.partition("\t")
            if status != "Playing" or inst == "playerctld":
                continue
            name, _, suffix = inst.partition(".instance")  # chromium.instance10926
            sources.append((int(suffix) if suffix.isdigit() else None, name))
    except (OSError, subprocess.SubprocessError):
        pass
    return sources


def playing_windows(wins, sources):
    """Map each source to a window (by process ancestry, then by app name).
    Returns (set of playing window ids, list of unmatched source names)."""
    playing = {con.id for con, _ in wins if con.ipc_data.get("inhibit_idle")}
    unmatched = []
    for pid, name in sources:
        match = None
        if pid:
            chain = ancestors(pid)
            match = next((c for c, _ in wins if c.ipc_data["pid"] in chain), None)
        if match is None and name:
            key = norm(name)
            # prefer a visible window of that app
            cands = [c for c, _ in wins if key and (norm(app_of(c)) in key or key in norm(app_of(c)))]
            match = next((c for c in cands if c.ipc_data.get("visible")), cands[0] if cands else None)
        if match is not None:
            playing.add(match.id)
        elif name:
            unmatched.append(name)
    return playing, unmatched


def main():
    ensure_bucket(BUCKET_WINDOW, "currentwindow")
    ensure_bucket(BUCKET_AFK, "afkstatus")
    ensure_bucket(BUCKET_MEDIA, "app.media.playing")

    sway = i3ipc.Connection()
    idle = IdleMonitor(IDLE_TIMEOUT)
    last_media = 0.0

    while True:
        tree = sway.get_tree()
        wins = list(windows(tree))
        focused = next((c for c, _ in wins if c.focused), None)

        # Focused time (rule 1)
        if focused is not None:
            heartbeat(BUCKET_WINDOW, {"app": app_of(focused), "title": focused.name or ""},
                      pulsetime=WINDOW_POLL + 1)

        now = time.monotonic()
        if now - last_media >= MEDIA_POLL:
            last_media = now
            playing, unmatched = playing_windows(wins, media_sources())

            # AFK, with media overriding input idle (rules 2–3)
            watching_focused = focused is not None and focused.id in playing
            status = "afk" if idle.idle and not watching_focused else "not-afk"
            heartbeat(BUCKET_AFK, {"status": status}, pulsetime=MEDIA_POLL + 1)

            # Background watching/listening (rules 4–5). A bucket's heartbeats
            # only merge with its latest event, so report one source per tick:
            # a visible window beats a hidden one beats a windowless stream.
            bg = [(c, out) for c, out in wins
                  if c.id in playing and (focused is None or c.id != focused.id)]
            bg.sort(key=lambda w: not w[0].ipc_data.get("visible"))
            if bg:
                con, out = bg[0]
                heartbeat(BUCKET_MEDIA, {"app": app_of(con), "title": con.name or "",
                                         "output": out,
                                         "visible": bool(con.ipc_data.get("visible"))},
                          pulsetime=MEDIA_POLL + 1)
            elif unmatched:
                heartbeat(BUCKET_MEDIA, {"app": unmatched[0], "title": "",
                                         "output": "", "visible": False},
                          pulsetime=MEDIA_POLL + 1)

        time.sleep(WINDOW_POLL)


if __name__ == "__main__":
    main()
