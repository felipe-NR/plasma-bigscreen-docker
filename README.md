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
| Controller | 8BitDo Ultimate 2C on its 2.4 GHz dongle |

Working:

- Bigscreen home screen in a nested KWin window, with the host locale and
  timezone.
- VA-API decoding of H.264, HEVC Main10 and AV1 on the host GPU (`vainfo`).
- Audio through the host PipeWire server.
- Controller navigation with the D-pad and the left stick, including a
  controller connected after the container started.

Not tested yet: the TV itself (the test host has one monitor for now), Kodi
4K playback, the controller over Bluetooth, KDE Connect and CEC.

## How it works

`startplasma-wayland` finds `WAYLAND_DISPLAY` pointing at the host socket and
runs KWin as a Wayland client, so the whole Bigscreen session lives in one
host window.

The Bigscreen inputhandler reads controllers through SDL and injects key
presses through the XDG RemoteDesktop portal of the nested session. Controller
input stays inside Bigscreen and never reaches the host desktop, and the
container needs no `/dev/uinput`.

The container gets:

| Mount or setting | Purpose |
|-|-|
| Host Wayland socket | Show the session as a host window |
| PipeWire and PulseAudio sockets | Sound through the host audio server |
| `/dev/dri` | GPU rendering and video decoding |
| `/dev/input`, `/run/udev`, host network | Controllers, including hotplug |
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
The rule sends the Bigscreen window to workspace 10, fullscreen, without
taking focus, and binds that workspace to the TV.

## Settings

`scripts/setup-env.sh` reads these variables when they are set and falls back
to the defaults below.

| Variable | Default | Meaning |
|-|-|-|
| `HTPC_LANG` | `pt_BR.UTF-8` | Interface language (`en_US.UTF-8` and `pt_BR.UTF-8` are generated) |
| `HTPC_TZ` | Host timezone | Clock timezone |
| `MEDIA_DIR` | `~/Videos` | Folder mounted read-only at `/media` |

## Known limits

- No Flatpak. bubblewrap needs user namespaces, which the default Docker
  seccomp profile blocks, so apps come from the Arch repositories (Kodi, mpv
  and Firefox are included).
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
