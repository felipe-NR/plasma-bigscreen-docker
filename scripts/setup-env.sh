#!/usr/bin/env bash
# Writes .env with the host values compose.yaml needs: user ids, device
# groups and the sockets of the running Wayland session.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${XDG_RUNTIME_DIR:?run this from your graphical session}"
: "${WAYLAND_DISPLAY:?run this from your graphical session}"

gid() { getent group "$1" | cut -d: -f3; }

for socket in "$WAYLAND_DISPLAY" pulse/native pipewire-0; do
    if [ ! -S "$XDG_RUNTIME_DIR/$socket" ]; then
        echo "Missing socket: $XDG_RUNTIME_DIR/$socket" >&2
        exit 1
    fi
done

media_dir=${MEDIA_DIR:-$HOME/Videos}
timezone=$(timedatectl show -p Timezone --value 2>/dev/null || echo UTC)
# Address of the interface that holds the default route, where phones reach us.
lan_ip=$(ip -4 route get 1.1.1.1 | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}')

cat > .env <<EOF
HTPC_UID=$(id -u)
HTPC_GID=$(id -g)
VIDEO_GID=$(gid video)
RENDER_GID=$(gid render)
HOST_RUNTIME_DIR=$XDG_RUNTIME_DIR
HOST_WAYLAND_DISPLAY=$WAYLAND_DISPLAY
MEDIA_DIR=$media_dir
HTPC_LANG=${HTPC_LANG:-pt_BR.UTF-8}
HTPC_TZ=${HTPC_TZ:-$timezone}
HTPC_HOSTNAME=${HTPC_HOSTNAME:-$(hostname)}
LAN_IP=${LAN_IP:-$lan_ip}
EOF

echo "Wrote .env:"
cat .env
