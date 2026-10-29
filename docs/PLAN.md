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
- **Phone remotes, no CEC.** Unified Remote is the main remote and KDE
  Connect the fallback, both on the phone. An 8BitDo Ultimate 2C worked
  through the Bigscreen inputhandler, but controller support needs
  `/dev/input` in the container, which also exposes the host keyboard, so it
  was dropped. The AMD iGPU on the test host exposes no `/dev/cec*` on HDMI,
  and a USB-CEC adapter is out of scope, so the TV remote does not drive
  Bigscreen.
- **Stremio in 4K HDR through mpv.** Playback means Stremio. Its built-in
  player draws libmpv into the GTK window and has no HDR output
  (stremio-linux-shell issues #16 and #32), so HDR streams go through
  Stremio's external player option, which hands an M3U playlist to mpv
  through the OpenURI portal. Kodi stays in the image without a 4K test.

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

1. Connect the TV to HDMI and move the current monitor to DP or USB4. Until
   there is an adapter for the monitor, the TV takes its place on the HDMI
   port and is the only display.
2. Check that `hyprctl monitors` lists the TV at its native mode, that its
   EDID announces HDR, and that its HDMI audio shows up as a PipeWire sink.
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

Done when the Bigscreen home screen fills the TV, Stremio plays a 4K HDR
stream with VA-API decoding (phase 5), sound comes out of the TV and the
phone remote moves through the menus.

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
5. On-screen text input through `plasma-keyboard`.

### 5. Stremio in 4K HDR

The chain from stream to TV, each link with what was checked on 2026-10-28:

1. mpv decodes on the GPU: zero-copy VA-API with a 4K HEVC Main10 HDR10
   test file, and 106 fps with `vaapi-copy` against the 24 fps it needs.
2. The nested KWin cannot carry HDR. It asks Hyprland for the preferred
   color only after a `preferred_changed` event, and Hyprland sends that
   event only to surfaces on exactly one output, which needs the client to
   bind `wl_output`. KWin's Wayland backend does not, so with the TV in HDR
   (`cm = "hdr"`, `bitdepth = 10`) KWin still offered mpv gamma 2.2, BT.709
   and 80 nits, and labelled its own frames the same way (Wayland protocol
   log).
3. mpv on the host compositor gets HDR. Started with `WAYLAND_DISPLAY` set
   to the host socket, mpv receives PQ, BT.2020 and 203 nits reference and
   picks an HDR10 ST2084 swapchain. With
   `target-colorspace-hint-mode=source`, the TV in SDR and
   `render:cm_auto_hdr` on, the TV switched to its "HDR Theater" picture
   mode while mpv played fullscreen, and back when it closed.
4. `container/mpv-tv` and the image's `mpv.desktop` start every mpv that a
   launcher or the OpenURI portal opens that way, with the app id
   `bigscreen-mpv`. The Hyprland rule puts it on workspace 12 on the TV and
   a `window.close` hook goes back to workspace 11, so the Bigscreen window
   keeps its fullscreen state. Launching `mpv.desktop` from inside the
   session put mpv on workspace 12, and closing it over MPRIS went back.
5. Stremio hands the stream to mpv through its external player option
   ("M3U Playlist"). The portal first showed its app chooser: GIO found no
   handler because the image's `mpv.desktop` sat in a folder without
   `mimeinfo.cache`. With the cache, a 4K HDR BDRemux from Stremio played
   in HDR with VA-API at about 5% of one core.
6. Stremio's subtitles do not reach the external player, which gets only
   the URL. `container/stremio-subtitles.lua` finds the title in Stremio's
   local storage (the `streams` entry, in the WAL of WebKit's
   `localstorage.sqlite3`) and loads the OpenSubtitles v3 subtitles Stremio
   would show. Timing and track changes go through KDE Connect run
   commands.

Stremio's built-in player stays SDR on the host as well: it shows an
"HDR10" badge for the file, but the TV did not switch while it played.

The TV needs its enhanced HDMI format on the HDMI 2.1 input: in standard
mode it announced 300 MHz TMDS, enough for 4K30 at 8 bits only. In enhanced
mode it announces 600 MHz. amdgpu on Linux has no HDMI 2.1 FRL, so the link
stays on TMDS, where 4K60 at 10 bits RGB does not fit; the bit depth the
driver picks needs root to read from debugfs and was not measured. The
nested output is 3840x2160 at scale 1.

### 6. Dedicated HTPC mode (optional)

KWin on its DRM backend with seatd on a free VT, Hyprland stopped. Needs
`/dev/dri`, `/dev/input`, `/dev/tty*` and `/run/udev`, and a systemd unit or a
login menu entry to start it.

### 7. Operations

Read-only media library mount, `restart: unless-stopped`, updates by
rebuilding the image, pinning an Arch Archive date if a Plasma release
regresses. Optional GitHub Actions build pushed to GHCR.
