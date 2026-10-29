# plasma-bigscreen-docker

Run [Plasma Bigscreen](https://invent.kde.org/plasma/plasma-bigscreen), the
KDE shell for TVs, in Docker on a Linux desktop host. The container starts a
nested Bigscreen session as one window of the host Wayland compositor, and a
Hyprland rule keeps that window fullscreen on the TV connected over HDMI. The
host desktop keeps running on its other monitor.

## Status

Early work. Tested on 2026-10-28 with:

| Part | Version |
|-|-|
| Host | Omarchy 4.0.6, Hyprland 0.56.2, kernel 7.2.8 |
| GPU | AMD Radeon 780M (Phoenix1), Mesa 26.2.5 |
| Image | Arch Linux, Plasma Bigscreen 6.8.1 |
| Remotes | Unified Remote 3.14 and KDE Connect on an Android phone |
| TV | Hisense 4K with HDR10, HLG and Dolby Vision, on its HDMI 2.1 input |

Working:

- Bigscreen home screen in a nested KWin window, with the host locale and
  timezone.
- VA-API decoding of H.264, HEVC Main10 and AV1 on the host GPU (`vainfo`).
- Audio through the host PipeWire server.
- Stremio opens from the Bigscreen app list.
- KDE Connect pairs with the phone, and the pairing survives container
  restarts.
- Unified Remote buttons from the phone (the Stremio remote: arrows, OK,
  back) move the Bigscreen and Stremio selection.
- The Unified Remote and KDE Connect touchpads move the Bigscreen pointer,
  and taps click where it points.
- Host keyboard and mouse inside the Bigscreen window.
- The Bigscreen session on the TV at 3840x2160 and 60 Hz.
- A 4K HEVC Main10 HDR10 test file through mpv in HDR: the TV switches to
  its HDR picture mode while mpv plays and back to SDR when it closes.
- Pausing and closing mpv over MPRIS.
- A 4K HDR BDRemux from Stremio's external player in HDR, with sound in
  sync and mpv at about 5% of one core.
- The KDE Connect media controls during playback, and the return to the
  Bigscreen on stop with a single cursor.
- OpenSubtitles subtitles for that stream through the mpv script: four in
  Brazilian Portuguese and five in English, with the first Portuguese one
  selected.

Not tested yet: the KDE Connect run commands from the phone.

## Apps

From the Arch repositories: Kodi, mpv (with `mpv-mpris`) and Firefox. From the AUR:
[Stremio](https://github.com/Stremio/stremio-linux-shell)
(`stremio-linux-shell`), built in a separate Docker stage from a pinned AUR
commit (`STREMIO_AUR_COMMIT` in the Dockerfile).

### HDR playback

Stremio's built-in player has no HDR output
([#16](https://github.com/Stremio/stremio-linux-shell/issues/16),
[#32](https://github.com/Stremio/stremio-linux-shell/issues/32)), and the
nested KWin renders SDR only (see Known limits). HDR video takes another
route:

1. In Stremio's settings, set "Play in external player" to "M3U Playlist".
   Stremio then hands an M3U playlist to the OpenURI portal, which opens it
   with `mpv.desktop` without asking: the image builds `mimeinfo.cache` for
   its own launchers, and without it GIO found no handler and the portal
   showed its app chooser.
2. The image's `mpv.desktop` runs `container/mpv-tv`, which starts mpv on the
   host compositor, outside the nested KWin, with the app id
   `bigscreen-mpv`.
3. The Hyprland rule puts that window fullscreen on workspace 12, also on
   the TV, and goes back to workspace 11 when it closes.
4. mpv describes its output in the colorspace of the video
   (`target-colorspace-hint-mode=source` in `container/mpv.conf`). For an
   HDR video that is PQ, and Hyprland switches the TV to HDR while the
   window is fullscreen (`render:cm_auto_hdr`, on by default). SDR videos
   leave the TV in SDR.

mpv decodes through VA-API, and `mpv-mpris` exposes it on the session bus,
so the KDE Connect media controls can pause, seek and stop it.

Stremio passes only the video URL to the external player, so its subtitles
stay behind. `container/stremio-subtitles.lua`, an mpv script, brings them
back:

1. It looks the URL up in the streams Stremio keeps in its local storage
   (WebKit's `localstorage.sqlite3`, read through `sqlite3` and `iconv`),
   which gives the IMDb id and, for series, the season and episode.
2. It asks the OpenSubtitles v3 addon, the one Stremio uses, with the video
   hash from Stremio's streaming server when it answers.
3. It adds up to five tracks each in Brazilian Portuguese, Portuguese and
   English next to the embedded ones, and selects the first Portuguese one
   unless a Portuguese subtitle or Portuguese audio is already on.

The phone switches tracks and fixes the timing through KDE Connect's run
commands, which `container/start-bigscreen` writes for every paired phone
and `mpv-tv-command` sends to mpv's IPC socket: next and previous subtitle,
show or hide, 0.1 s and 1 s later or earlier, and next audio track.

## How it works

`startplasma-wayland` finds `WAYLAND_DISPLAY` pointing at the host socket and
runs KWin as a Wayland client, so the whole Bigscreen session lives in one
host window.

Input comes from three places, and none of them needs `/dev/input` or
`/dev/uinput` in the container:

- The host keyboard and mouse reach the window like any other Wayland
  client. Right Ctrl makes KWin capture pointer and keyboard, so host
  shortcuts such as `SUPER+2` do nothing until you press Right Ctrl again.
- Unified Remote sends XTest events to the session's Xwayland, which passes
  them to KWin through libei (see below).
- KDE Connect runs inside the session as the second phone remote and sends
  its input through the RemoteDesktop portal, which also ends in libei.

All three move one pointer, and the last one used wins. Two KWin variables
in `compose.yaml` keep that pointer where the phone left it:

- `KWIN_FORCE_SW_CURSOR=1` makes KWin draw the cursor in its own frames.
  Without it the host compositor draws the cursor at the host mouse
  position, and the phone moves a pointer nobody can see.
- `KWIN_USE_OVERLAYS=0` keeps KWin from putting parts of the scene on
  overlay planes, which a nested KWin creates as Wayland subsurfaces.
  Hyprland replays the host pointer position to the window whenever one of
  those subsurfaces unmaps, and every replay pulled the phone's pointer
  back to the host mouse, every 2 to 5 seconds in testing.

The container gets:

| Mount or setting | Purpose |
|-|-|
| Host Wayland socket | Show the session as a host window |
| PipeWire and PulseAudio sockets | Sound through the host audio server |
| `/dev/dri` | GPU rendering and video decoding |
| Ports on `LAN_IP` | KDE Connect and Unified Remote from the phone |
| `cap_add: SYS_NICE` | `kwin_wayland` ships with the `cap_sys_nice` file capability and the kernel refuses to run it without it |
| Volume `home` | Bigscreen and app settings |
| `MEDIA_DIR` (read-only) | Media library at `/media` |

## Requirements

- Linux host running a Wayland compositor. The window rule is for Hyprland.
- PipeWire with its PulseAudio server.
- Docker with Compose v2, and your user in the `docker` group.
- AMD GPU. The image installs the Mesa `radeonsi` and `radv` drivers; other
  GPUs need other packages.

## Quick start

```sh
git clone https://github.com/felipe-NR/plasma-bigscreen-docker.git
cd plasma-bigscreen-docker
scripts/setup-env.sh
docker compose up -d --build
```

Run `scripts/setup-env.sh` from your graphical session. It writes `.env` with
your user and group ids and the paths of the session sockets. The first build
took about two and a half minutes on the test host, and `docker image ls`
reports 5.2 GB for the image.

Stop it with `docker compose down`. Settings stay in the `home` volume.

### Hyprland rule

```sh
cp host/hypr/plasma_bigscreen.lua ~/.config/hypr/
echo 'require("hypr.plasma_bigscreen")' >> ~/.config/hypr/hyprland.lua
hyprctl reload && hyprctl configerrors
```

Set `tv_output` in that file to the TV output name from `hyprctl monitors`.
The rule sends the Bigscreen window to workspace 11, fullscreen, without
taking focus, and binds that workspace to the TV. It also gives the HDR
player its own workspace 12 on the TV (see HDR playback). Workspace 11 is outside the
range the Omarchy bar selector and the `SUPER+number` bindings use, so the
desktop workspaces stay as they were. To look at it on a single monitor:

```sh
hyprctl dispatch 'hl.dsp.focus({ workspace = "11" })'
```

### Omarchy bar button

`host/omarchy/Workspaces.qml` is the Omarchy workspaces widget with one
addition: a "TV" button after the numbered workspaces that shows while
workspace 11 has a window and jumps to it when pressed. Hyprland leaves the
pointer on the bar after that switch, and the host would keep drawing the
bar's hand cursor over the TV next to the KWin cursor, so the button also
moves the pointer to the middle of the Bigscreen window. Clone the built-in
widget and replace its file:

```sh
omarchy plugin clone omarchy.workspaces
cp host/omarchy/Workspaces.qml ~/.config/omarchy/plugins/$USER.workspaces/
omarchy restart shell
```

Edits to the clone did not hot-reload on the test host, so restart the shell
after copying.

### Phone remote: Unified Remote

The image ships the [Unified Remote](https://www.unifiedremote.com/) server
(`/opt/urserver`, version pinned with its sha256 in the Dockerfile), started
with the Bigscreen session. Install the Unified Remote app on the phone and
add the server by the host LAN address (`LAN_IP`, port 9512). Discovery by
broadcast does not reach the container network.

The server runs with its X11 backend. Its key presses and touchpad motion go
to the session's Xwayland, which hands them to KWin through libei, so they
reach Bigscreen whatever window has focus on the host. With its Wayland backend the server
would create a `/dev/uinput` device, and the host compositor would deliver
those keys to the focused host window instead.

Compose publishes 9512/tcp and 9511 to 9512/udp on `LAN_IP`. The web
manager listens on port 9510 inside the container and is not published.

### KDE Connect

KDE Connect is the second phone remote. Compose publishes 1716/tcp and
1716/udp for the connection and 1739 to 1764/tcp for file transfers, on
`LAN_IP`. As with Unified Remote, the phone does not find the container by
broadcast: in the KDE Connect app, add the device by IP with `LAN_IP`.

The remote input plugin needs the RemoteDesktop portal, which would ask for
permission on the TV. `container/start-remotes` grants it up front in the
portal permission store, the way the Bigscreen inputhandler does for itself.

### Network and firewall

The container has its own network namespace. KWin creates an abstract X11
socket for the session's Xwayland, and abstract sockets belong to the network
namespace: with `network_mode: host`, that socket answered `DISPLAY=:0` for
X11 apps on the host desktop, which then failed with "Authorization
required".

Docker publishes ports ahead of ufw, so no ufw rule is needed for them, and
ufw does not restrict them either. Binding them to `LAN_IP` keeps them off the
other interfaces.

## Settings

`scripts/setup-env.sh` reads these variables when they are set and falls back
to the defaults below.

| Variable | Default | Meaning |
|-|-|-|
| `HTPC_LANG` | `pt_BR.UTF-8` | Interface language (`en_US.UTF-8` and `pt_BR.UTF-8` are generated) |
| `HTPC_TZ` | Host timezone | Clock timezone |
| `MEDIA_DIR` | `~/Videos` | Folder mounted read-only at `/media` |
| `HTPC_HOSTNAME` | Host name | Name the phones see for KDE Connect and Unified Remote |
| `LAN_IP` | Address of the default route interface | Where the phone remote ports are published |

## Known limits

- No Flatpak. bubblewrap needs user namespaces, which the default Docker
  seccomp profile blocks, so apps come from Arch packages. For the same
  reason the QtWebEngine and WebKitGTK sandboxes are turned off.
- Hyprland sends no frame callbacks to windows on hidden workspaces, so the
  session barely moves while workspace 11 is out of view. Once the workspace
  is on screen it runs at full speed. On the TV it is always on screen.
- The host mouse and the phones share one pointer. While the host pointer
  sits over the Bigscreen window, touching the host mouse moves the
  Bigscreen pointer to it. On a single monitor the fullscreen window covers
  the whole screen, so leave the host mouse alone while using the phone. With
  the TV as a second output, keep the host pointer on the other monitor.
- No game controllers. The Bigscreen inputhandler reads them through SDL,
  which needs `/dev/input`, `/run/udev` and the host `input` group in the
  container. That access also exposes the host keyboard, so it was dropped.
  Commit 8536cf0 has the compose settings that worked with an 8BitDo
  Ultimate 2C.
- `/etc/xdg/kwinrc` sets `XwaylandEisNoPrompt=true`, so any X11 client in
  the session can send input without the KWin prompt. Only the session's own
  apps can reach its Xwayland.
- The container shares the host PipeWire server. Picking an audio output in
  Bigscreen changes the host default output too.
- The nested KWin renders SDR only. Its Wayland backend asks the host for
  the preferred color only after a `preferred_changed` event, and Hyprland
  sends that event only to surfaces on exactly one output. KWin does not
  bind the host `wl_output`, so its window never counts as being on one,
  and KWin renders and labels everything as SDR at 80 nits even with the TV
  in HDR (seen in the Wayland protocol log). HDR video goes through mpv on
  the host compositor instead.
- During HDR playback, mpv is a host window: phone input still goes to the
  Bigscreen session underneath, so mpv takes only the KDE Connect media
  controls and run commands. Stremio's own subtitle menu and timing controls
  do not apply there.
- Stremio's built-in player shows an "HDR10" badge for HDR streams but
  renders them in SDR, on the host as in the container: the badge describes
  the file, not the output.
- HDR needs the TV input in HDMI 2.0 mode. In its standard mode the
  Hisense input announced 300 MHz TMDS and no HDMI Forum block, which
  allows 4K30 at 8 bits only. With the TV's enhanced HDMI format on, its
  HDMI 2.1 input announces 600 MHz TMDS. amdgpu on Linux has no HDMI 2.1
  FRL, so the link stays on TMDS, where 4K60 at 10 bits RGB does not fit;
  the bit depth the driver picks was not measured.
- No TV remote. AMD GPUs expose no HDMI-CEC on Linux, and a USB-CEC
  adapter is out of scope for this project.
- Warnings about the document portal (`fuse`) and `systemd1` in the logs are
  expected: the container has no FUSE and no systemd user session.

## Plan

See [docs/PLAN.md](docs/PLAN.md).

## License

[MIT](LICENSE)
