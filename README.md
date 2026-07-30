# dotfiles

Sway + Waybar setup on Fedora (Wayland). Includes legacy i3 + polybar config.

![Sway Screenshot](./images/sway_kittys.png)


---

## Apps & Tools

### Core
| App | Purpose |
|-----|---------|
| `sway` | Wayland tiling window manager |
| `waybar` | Status bar |
| `swaylock` | Lock screen |
| `swayidle` | Idle management (auto-lock + display off) |
| `rofi` | App launcher, window switcher, power menu |
| `kitty` | Terminal emulator |

### Apps
| App | Purpose |
|-----|---------|
| `google-chrome` | Browser (Mod+c) |
| `code` | VS Code (Mod+p) |
| `thunar` | File manager (Mod+o) |

### Media & System
| App | Purpose |
|-----|---------|
| `wireplumber` / `wpctl` | Audio control (PipeWire) |
| `brightnessctl` | Brightness control |
| `swayosd` | On-screen display for volume/brightness/mic |
| `swaync` | Notification center daemon |

### Screenshot
| App | Purpose |
|-----|---------|
| `grim` | Wayland screen capture |
| `slurp` | Region selection |
| `swappy` | Screenshot annotation & save |
| `gthumb` | Simple photo viewer & editor (crop, resize, color adjust) |

### Tray
| App | Purpose |
|-----|---------|
| `copyq` | Clipboard manager |
| `nm-applet` | WiFi tray icon |
| `blueman-applet` | Bluetooth tray icon |

### Fonts
- **CaskaydiaCove Nerd Font** — UI font (bar, borders, icons)
- Nepali TTF fonts in `fonts/` — optional, for Nepali language support

---

## Installation

### 1. Install dependencies

```bash
sudo dnf install sway waybar swaylock swayidle rofi kitty thunar \
  wireplumber brightnessctl grim slurp swappy \
  copyq network-manager-applet blueman \
  xdg-desktop-portal-wlr xdg-desktop-portal-gtk
```

Install swayosd (Wayland OSD for volume/brightness):
```bash
sudo dnf copr enable mochaa/swayosd
sudo dnf install swayosd
```

Install swaync (notification center):
```bash
sudo dnf install swaynotificationcenter
```

Install Google Chrome and VS Code via their official `.rpm` repos.

### 2. Clone the repo

```bash
git clone https://github.com/whatiskeptiname/dotfiles.git ~/Documents/self/dotfiles
```

### 3. Create config directories

```bash
mkdir -p ~/.config/sway/scripts
mkdir -p ~/.config/waybar/scripts
mkdir -p ~/.config/waybar/colors
```

### 4. Symlink sway configs

```bash
ln -s ~/Documents/self/dotfiles/sway/config                    ~/.config/sway/config
ln -s ~/Documents/self/dotfiles/sway/environment               ~/.config/sway/environment
ln -s ~/Documents/self/dotfiles/sway/scripts/burn-in.sh          ~/.config/sway/scripts/burn-in.sh
ln -s ~/Documents/self/dotfiles/sway/scripts/lock.sh             ~/.config/sway/scripts/lock.sh
ln -s ~/Documents/self/dotfiles/sway/scripts/powermenu.sh        ~/.config/sway/scripts/powermenu.sh
ln -s ~/Documents/self/dotfiles/sway/scripts/notify-osd.sh       ~/.config/sway/scripts/notify-osd.sh
ln -s ~/Documents/self/dotfiles/sway/scripts/waybar.sh           ~/.config/sway/scripts/waybar.sh
ln -s ~/Documents/self/dotfiles/sway/scripts/window-switcher.sh  ~/.config/sway/scripts/window-switcher.sh
chmod +x ~/Documents/self/dotfiles/sway/scripts/*.sh
```

### 5. Symlink waybar configs

```bash
ln -s ~/Documents/self/dotfiles/waybar/config.jsonc                 ~/.config/waybar/config.jsonc
ln -s ~/Documents/self/dotfiles/waybar/style.css                    ~/.config/waybar/style.css
ln -s ~/Documents/self/dotfiles/waybar/colors/colors.dark.css       ~/.config/waybar/colors/colors.dark.css
ln -s ~/Documents/self/dotfiles/waybar/scripts/gpu.sh               ~/.config/waybar/scripts/gpu.sh
ln -s ~/Documents/self/dotfiles/waybar/scripts/mic-vol.sh           ~/.config/waybar/scripts/mic-vol.sh
```

### 6. Make scripts executable

```bash
chmod +x ~/Documents/self/dotfiles/sway/scripts/*.sh
chmod +x ~/Documents/self/dotfiles/waybar/scripts/*.sh
```

### 7. Install Nepali fonts (optional)

```bash
cp ~/Documents/self/dotfiles/fonts/*.TTF ~/.local/share/fonts/
cp ~/Documents/self/dotfiles/fonts/*.ttf ~/.local/share/fonts/
fc-cache -f
```

### 8. Fix wallpaper path

Edit `sway/config` and update to your username:
```
output * bg /home/<user>/Documents/self/dotfiles/wallpapers/purple.jpg fill
```

### 9. Disable dunst (if installed)

swaync handles all notifications. If dunst is running it will conflict:
```bash
pkill dunst
# Check it's not in autostart:
ls ~/.config/autostart/
```

### 10. Start sway

Log out and select **Sway** from your display manager, or run `sway` from a TTY.

---

## Keybindings

| Key | Action |
|-----|--------|
| `Mod+Return` | Terminal (kitty) |
| `Mod+d` | App launcher (rofi) |
| `Mod+Tab` | Window switcher (rofi) |
| `Mod+c` | Google Chrome |
| `Mod+p` | VS Code |
| `Mod+o` | File manager (Thunar) |
| `Mod+n` | Toggle notification center (swaync) |
| `Mod+Shift+n` | Toggle focus mode (mute all notifications / DND) |
| `Mod+Shift+s` | Screenshot — select region → annotate (grim+slurp+swappy) |
| `Mod+Shift+Delete` | Power menu (rofi) |
| `Mod+Shift+c` | Reload sway config |
| `Mod+Shift+q` | Close window |
| `Mod+Shift+e` | Exit sway (with confirmation) |
| `XF86AudioRaiseVolume` | Volume up 5% (swayosd) |
| `XF86AudioLowerVolume` | Volume down 5% (swayosd) |
| `XF86AudioMute` | Toggle mute (swayosd) |
| `XF86AudioMicMute` | Toggle mic mute (swayosd) |
| `XF86MonBrightnessUp` | Brightness up 5% (swayosd) |
| `XF86MonBrightnessDown` | Brightness down 5% (swayosd) |

### Power menu (`Mod+Shift+Delete`)
Lock · Shutdown · Reboot · Suspend · Hibernate · Exit Sway

---

## Features

### OLED Burn-in Prevention (`sway/scripts/burn-in.sh`)
Runs on every sway start/reload and randomizes:
- **Wallpaper** — picks randomly from `wallpapers/`
- **Waybar position** — top-left, top-right, bottom-left, bottom-right
- **Module order** — shuffles vitals modules each boot
- **Accent colors** — 12-color pool, all unique per module underline, cycles before repeating
- **Window border color** — matches the accent color

### Notifications
- **swayosd** — pill-style OSD overlay for volume/brightness/mic
- **swaync** — full notification daemon + panel (`Mod+n`)
- **Focus mode / DND** — `Mod+Shift+n` or right-click the waybar bell icon toggles Do Not Disturb; the icon switches to a crossed-out bell while muted

### Idle & Lock
- Display powers off after **1 minute** of inactivity, back on when activity resumes
- Screen locks after **3 minutes** of inactivity
- Locks before sleep and via power menu (`Mod+Shift+Delete → Lock`)

Lock screen (`sway/scripts/lock.sh`):
- Shows the current random wallpaper as background (falls back to solid black)
- Ring color randomized each lock from the 12-color burn-in palette
- Ring position randomized each lock (both axes)
- Ring always visible (`--indicator-idle-visible`) — clearly indicates locked state
- Tokyo Night colors for verify / wrong-password states

### Dark Mode
- GTK4, GTK3, and Qt apps all use dark theme via gsettings + `QT_QPA_PLATFORMTHEME=gtk3`

### Urgent Windows
- 3px bright red border box on urgent windows
- Blinking workspace indicator in waybar

---

## Screen Sharing (Wayland / PipeWire)

Screen sharing in Chrome/Chromium on Sway requires `xdg-desktop-portal-wlr` properly wired into the systemd user session. **Sway 1.12+ supports native per-window capture** — no workarounds needed.

### What's configured

| File | Purpose |
| ---- | ------- |
| `~/.config/xdg-desktop-portal/portals.conf` | Routes screen-cast and screenshot requests to the wlr backend |
| `~/.config/xdg-desktop-portal-wlr/config` | Sets max framerate for screencasts |
| `~/.config/chromium-flags.conf` | Enables PipeWire capture + native Wayland mode in Chromium |

The sway config (`sway/config`) also starts `sway-session.target` and imports the Wayland env vars into the systemd user session so the portal services can start.

### Setup

#### 1. Install packages

```bash
sudo dnf install wlroots xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk pipewire pipewire-utils
```

Install Sway 1.12 (not yet in Fedora 44 stable — grab the fc45 RPM directly):

```bash
sudo rpm -Uvh https://dl.fedoraproject.org/pub/fedora/linux/development/rawhide/Everything/x86_64/os/Packages/s/sway-1.12-1.fc45.x86_64.rpm
```

#### 2. Create portal backend config

```bash
mkdir -p ~/.config/xdg-desktop-portal
cat > ~/.config/xdg-desktop-portal/portals.conf << 'EOF'
[preferred]
default=wlr;gtk
org.freedesktop.impl.portal.ScreenCast=wlr
org.freedesktop.impl.portal.Screenshot=wlr
EOF
```

#### 3. Configure xdg-desktop-portal-wlr

```bash
mkdir -p ~/.config/xdg-desktop-portal-wlr
cat > ~/.config/xdg-desktop-portal-wlr/config << 'EOF'
[screencast]
max_framerate=60
EOF
```

#### 4. Configure Chromium

```bash
cat > ~/.config/chromium-flags.conf << 'EOF'
--enable-features=WebRTCPipeWireCapturer
--ozone-platform=wayland
EOF
```

#### 5. Wire sway into the systemd user session

Add these lines to `sway/config` (already present in this repo):

```sh
exec systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP SWAYSOCK
exec systemctl --user start sway-session.target
```

This activates `graphical-session.target`, which the portal service requires.

#### 6. Reload

```bash
systemctl --user start xdg-desktop-portal-wlr.service xdg-desktop-portal.service
```

Then restart Chromium.

### Sharing a specific window

With Sway 1.12, the screen-share dialog in Chrome/Meet/Zoom/Discord shows individual windows natively — just click the window you want to share. No fullscreen workaround needed.

---

## Display Scaling

Default scale is `1.5` for HiDPI. Adjust in `sway/config`:
```
output eDP-1 scale 1.5
```

---

## Multi-Monitor (NVIDIA + AMD hybrid GPU)

Legion 5 and similar laptops have HDMI wired to the NVIDIA chip (card0) while
sway defaults to the AMD iGPU (card1). Proprietary NVIDIA drivers also block
sway with an error unless `--unsupported-gpu` is passed.

The Fedora `start-sway` launcher (used by GDM) sources `~/.config/sway/environment`
before starting sway. `sway/environment` sets the two required variables:

```
WLR_DRM_DEVICES=/dev/dri/card1:/dev/dri/card0
SWAY_EXTRA_ARGS=--unsupported-gpu
```

Symlink it (already in step 4 above) and the normal **Sway** session in GDM will
automatically pick up the external monitor — no custom session entry needed.

> **Do not** set `WLR_DRM_DEVICES` in `~/.config/environment.d/` — it applies
> to all user systemd services and will cause a login loop if sway fails to start.

### Output config (1080p external)

| Output | Resolution | Refresh | Position | Scale |
|--------|-----------|---------|----------|-------|
| `eDP-1` (laptop) | 2560×1600 | 165 Hz | 0,0 | 1.5 |
| `HDMI-A-1` (external) | 1920×1080 | 100 Hz | 1707,0 | 1 |

Adaptive sync (FreeSync) is not supported on the external panel.

### Workspace layout

Workspaces 1–5 are pinned to the laptop screen, 6–10 to the external monitor.
Adjust the `workspace N output` lines in `sway/config` to change the split.
