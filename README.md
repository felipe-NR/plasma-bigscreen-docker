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

Working:

- Bigscreen home screen in a nested KWin window, with the host locale and
  timezone.
- VA-API decoding of H.264, HEVC Main10 and AV1 on the host GPU (`vainfo`).
- Audio through the host PipeWire server.
- Stremio opens from the Bigscreen app list.
- KDE Connect pairs with the phone, and the pairing survives container
  restarts.
- The Unified Remote server starts with the session on its X11 backend, and
  XTest key presses move the Bigscreen selection (checked with `xdotool`).
- Host keyboard and mouse inside the Bigscreen window.

Not tested yet: the TV itself (the test host has one monitor for now), Kodi
4K playback, Unified Remote from the phone and CEC.

## Apps

From the Arch repositories: Kodi, mpv and Firefox. From the AUR:
[Stremio](https://github.com/Stremio/stremio-linux-shell)
(`stremio-linux-shell`), built in a separate Docker stage from a pinned AUR
commit (`STREMIO_AUR_COMMIT` in the Dockerfile).

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
- KDE Connect runs inside the session as the second phone remote. Its
  remote input plugin is not tested yet.

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
taking focus, and binds that workspace to the TV. Workspace 11 is outside the
range the Omarchy bar selector and the `SUPER+number` bindings use, so the
desktop workspaces stay as they were. To look at it on a single monitor:

```sh
hyprctl dispatch 'hl.dsp.focus({ workspace = "11" })'
```

### Omarchy bar button

`host/omarchy/Workspaces.qml` is the Omarchy workspaces widget with one
addition: a "TV" button after the numbered workspaces that shows while
workspace 11 has a window and jumps to it when pressed. Clone the built-in
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

The server runs with its X11 backend. Its key presses go to the session's
Xwayland, which hands them to KWin through libei, so they reach Bigscreen
whatever window has focus on the host. With its Wayland backend the server
would create a `/dev/uinput` device, and the host compositor would deliver
those keys to the focused host window instead.

Compose publishes 9512/tcp and 9511 to 9512/udp on `LAN_IP`. The web
manager listens on port 9510 inside the container and is not published.

### KDE Connect

KDE Connect is the second phone remote. Compose publishes 1716/tcp and
1716/udp for the connection and 1739 to 1764/tcp for file transfers, on
`LAN_IP`. As with Unified Remote, the phone does not find the container by
broadcast: in the KDE Connect app, add the device by IP with `LAN_IP`.

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
- AMD GPUs expose no HDMI-CEC on Linux, so the TV remote needs a USB-CEC
  adapter such as the Pulse-Eight. Not tested yet.
- Warnings about the document portal (`fuse`) and `systemd1` in the logs are
  expected: the container has no FUSE and no systemd user session.

## Plan

See [docs/PLAN.md](docs/PLAN.md).

## License

[MIT](LICENSE)
