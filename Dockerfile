# Builds the AUR packages the image needs. makepkg refuses to run as root, so
# dependencies go in as root and the build runs as an unprivileged user.
FROM archlinux:latest AS aur

ARG STREMIO_AUR_COMMIT=aca31f7ca5a28772926d3b74f7d99a4de7ee2dd8

SHELL ["/bin/bash", "-c"]
RUN pacman -Syu --noconfirm --needed base-devel git \
 && useradd -m builder
USER builder
WORKDIR /home/builder
RUN git clone https://aur.archlinux.org/stremio-linux-shell.git \
 && git -C stremio-linux-shell checkout --quiet "$STREMIO_AUR_COMMIT"
USER root
RUN . stremio-linux-shell/PKGBUILD \
 && pacman -S --noconfirm --needed "${depends[@]}" "${makedepends[@]}"
USER builder
RUN cd stremio-linux-shell && makepkg --noconfirm

FROM archlinux:latest

ARG HTPC_UID=1000
ARG HTPC_GID=1000
ARG LOCALES="en_US.UTF-8 pt_BR.UTF-8"

# The base image skips translations, locale sources and X11 compose tables
# when it installs packages. Plasma translations, locale-gen and dead keys
# need them, so drop the filter and reinstall the packages that were trimmed.
COPY --from=aur /home/builder/stremio-linux-shell/*.pkg.tar.zst /tmp/aur/
RUN sed -i '/^NoExtract/d' /etc/pacman.conf \
 && pacman -Syu --noconfirm \
 && pacman -S --noconfirm glibc \
 && pacman -S --noconfirm --needed \
      plasma-bigscreen plasma-keyboard plasma-integration \
      xdg-desktop-portal-kde breeze breeze-icons \
      mesa vulkan-radeon libva-utils xorg-xwayland \
      noto-fonts noto-fonts-emoji \
      kodi mpv firefox \
 && pacman -U --noconfirm /tmp/aur/*.pkg.tar.zst \
 && rm -rf /tmp/aur /var/cache/pacman/pkg/*

RUN for locale in $LOCALES; do \
      sed -i "s/^#\(${locale} UTF-8\)/\1/" /etc/locale.gen; \
    done \
 && locale-gen

# Hide launchers that come in as dependencies and make no sense on a TV. The
# swap-session entry switches the display manager session, which does not
# exist inside the container.
RUN install -d /usr/local/share/applications \
 && for app in assistant designer linguist lstopo qdbusviewer qv4l2 qvidcap \
               org.kde.kdeconnect.nonplasma org.kde.kdeconnect.sms \
               plasma-bigscreen-swap-session; do \
      sed '/^\[Desktop Entry\]/a NoDisplay=true' "/usr/share/applications/$app.desktop" \
        > "/usr/local/share/applications/$app.desktop"; \
    done

RUN groupadd -g "$HTPC_GID" htpc \
 && useradd -m -u "$HTPC_UID" -g "$HTPC_GID" -s /bin/bash htpc

COPY container/start-bigscreen /usr/local/bin/start-bigscreen

ENV XDG_RUNTIME_DIR=/run/user/${HTPC_UID} \
    WAYLAND_DISPLAY=wayland-host \
    PULSE_SERVER=unix:/run/user/${HTPC_UID}/pulse/native \
    QTWEBENGINE_DISABLE_SANDBOX=1 \
    WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 \
    LANG=en_US.UTF-8

USER htpc
WORKDIR /home/htpc
CMD ["/usr/local/bin/start-bigscreen"]
