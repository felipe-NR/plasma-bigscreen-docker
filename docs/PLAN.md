# Plan

Goal: run Plasma Bigscreen on a TV connected to this host over HDMI, with
Docker playing the part of an HTPC that uses the TV as its display.

## Decisions

- **Window mode.** The container runs the Bigscreen session as a nested
  Wayland client of the host compositor (Hyprland). A window rule keeps that
  window fullscreen on the TV output, and the host desktop keeps running on
  the other monitor. No `--privileged`.
- **Arch Linux base image.** Plasma Bigscreen is part of the Plasma release
  cycle again (v6.8.x) and ships in Arch `extra`, so the image installs it
  from packages and follows the same Mesa and Plasma line as the host.
- **Native packages, no Flatpak.** bubblewrap needs user namespaces, which the
  default Docker seccomp profile blocks. Kodi, mpv and Firefox come from the
  Arch repositories.
- **Phone remotes, CEC later.** Unified Remote is the main remote and KDE
  Connect the fallback, both on the phone. An 8BitDo Ultimate 2C worked
  through the Bigscreen inputhandler, but controller support needs
  `/dev/input` in the container, which also exposes the host keyboard, so it
  was dropped. The AMD iGPU on the test host exposes no `/dev/cec*` on HDMI,
  so the TV remote needs a USB-CEC adapter.

## Sources and what was kept

| Source | Kept | Caveat |
|-|-|-|
| [Diolinux article](https://diolinux.com.br/noticias/plasma-bigscreen-para-tvs.html) | Tested apps, known gaps (virtual keyboard, CEC) | Predates the return to the Plasma release cycle |
| [KDE/plasma-bigscreen](https://github.com/KDE/plasma-bigscreen) | Session environment, inputhandler, CEC settings | The README launch script is older than the 6.8 session script |
| [Alibaba buying guide](https://electronics.alibaba.com/buyingguides/plasma-bigscreen-tv-os-guide-linux-for-smart-tvs) | Input and audio checklist | Marketing text, unsourced numbers |
| [nuntius-dev/KDEPlasmaDesktopinDocker](https://github.com/nuntius-dev/KDEPlasmaDesktopinDocker/) | Non-root user pattern | VNC only, no GPU or audio; useful for debugging at most |
| [kdeneon/plasma](https://hub.docker.com/r/kdeneon/plasma) | Nothing | Not updated in over three years, Plasma 5 on X11 |

## Phases

### 0. Repository

Public repository `felipe-NR/plasma-bigscreen-docker`, MIT license.

### 1. Host and hardware

1. Connect the TV to HDMI and move the current monitor to DP or USB4.
2. Check that `hyprctl monitors` lists the TV at its native mode and that its
   HDMI audio shows up as a PipeWire sink.
3. `/dev/uinput` access is not needed. The 6.8 inputhandler injects keys
   through the XDG RemoteDesktop portal of the nested session, and controller
   navigation works without it (checked on 2026-10-28).

### 2. Image

Arch base, `plasma-bigscreen`, `plasma-keyboard`, `xdg-desktop-portal-kde`,
Mesa with VA-API and Vulkan, Xwayland, fonts, Kodi, mpv and Firefox. A user
whose UID matches the host user, so the mounted sockets work.

### 3. Window mode (MVP)

Mount the host Wayland, PipeWire and PulseAudio sockets and `/dev/dri`, and
keep `/home/htpc` in a named volume. Add the Hyprland window rule for the TV
output.

Done when the Bigscreen home screen fills the TV, Kodi plays a 4K file with
VA-API decoding, sound comes out of the TV and the phone remote moves through
the menus.

Checked on 2026-10-28: `startplasma-wayland` falls back to its non-systemd
startup, the nested output follows the window size (1920x1080 fullscreen),
and controller input reaches Bigscreen through the portal. `kwin_wayland`
needs `SYS_NICE` in the container bounding set because of its file
capability. Still open: focus behaviour once the TV is a second monitor.

### 4. Input

1. Unified Remote server in the container on its X11 backend, so its input
   goes through Xwayland and libei into the nested KWin (ports 9511 and
   9512).
2. KDE Connect on the phone as fallback remote and keyboard (ports 1716 and
   1739 to 1764). Paired on 2026-10-28. Its RemoteDesktop permission is
   granted at session start.
   Both touchpads move the Bigscreen pointer since KWin draws its own cursor
   (`KWIN_FORCE_SW_CURSOR=1`) and keeps overlays off (`KWIN_USE_OVERLAYS=0`).
3. The container keeps its own network namespace and publishes those ports on
   the LAN address. With host networking, the abstract X11 socket of the
   session's Xwayland took over `DISPLAY=:0` for X11 apps on the host. Phones
   add the server by IP, since broadcasts do not reach the container.
4. Host keyboard and mouse through the Bigscreen window.
5. TV remote over CEC through a Pulse-Eight USB-CEC adapter passed to the
   container. Optional purchase.
6. On-screen text input through `plasma-keyboard`.

### 5. Dedicated HTPC mode (optional)

KWin on its DRM backend with seatd on a free VT, Hyprland stopped. Needs
`/dev/dri`, `/dev/input`, `/dev/tty*` and `/run/udev`, and a systemd unit or a
login menu entry to start it.

### 6. Operations

Read-only media library mount, `restart: unless-stopped`, updates by
rebuilding the image, pinning an Arch Archive date if a Plasma release
regresses. Optional GitHub Actions build pushed to GHCR.
