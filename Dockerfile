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
      kodi mpv mpv-mpris firefox \
 && pacman -U --noconfirm /tmp/aur/*.pkg.tar.zst \
 && rm -rf /tmp/aur /var/cache/pacman/pkg/*

# Stremio's streaming server runs on node. On 2026-10-28 Arch shipped nodejs
# 26.12.1-2 linked against libsimdjson.so.34 next to simdjson 5.0.8, which
# provides libsimdjson.so.35, so node did not start. When node fails, install
# the last simdjson with that soname from the Arch Linux Archive; once nodejs
# is rebuilt this step does nothing. The build stops if node still fails.
ARG SIMDJSON_FALLBACK=5.0.5-1
ARG SIMDJSON_FALLBACK_SHA256=39c50dc6d0f9c54c12cf494fcb1e8435156ecd192f86cf6134e9ff3f8d1832d5
RUN if ! node --version >/dev/null 2>&1; then \
      curl -fsSLo /tmp/simdjson.pkg.tar.zst \
        "https://archive.archlinux.org/packages/s/simdjson/simdjson-1%3A${SIMDJSON_FALLBACK}-x86_64.pkg.tar.zst" \
   && echo "${SIMDJSON_FALLBACK_SHA256}  /tmp/simdjson.pkg.tar.zst" | sha256sum -c - \
   && pacman -U --noconfirm /tmp/simdjson.pkg.tar.zst \
   && rm /tmp/simdjson.pkg.tar.zst; \
    fi \
 && node --version

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

# Unified Remote server for the phone remote, from the vendor build checked
# against a pinned hash.
ARG URSERVER_VERSION=3.14.0.2574
ARG URSERVER_SHA256=e3003654f6f940ddf44d66bbda95154d87efb319464cef159e087bc031d78431
RUN curl -fsSLo /tmp/urserver.tar.gz \
      "https://www.unifiedremote.com/static/builds/server/linux-x64/${URSERVER_VERSION##*.}/urserver-${URSERVER_VERSION}.tar.gz" \
 && echo "${URSERVER_SHA256}  /tmp/urserver.tar.gz" | sha256sum -c - \
 && install -d /opt/urserver \
 && tar -xzf /tmp/urserver.tar.gz -C /opt/urserver --strip-components=1 \
 && rm /tmp/urserver.tar.gz

# Let X11 clients such as Unified Remote send input through Xwayland without
# the KWin permission prompt, which nobody can answer from the couch.
RUN printf '[Xwayland]\nXwaylandEisNoPrompt=true\n' >> /etc/xdg/kwinrc

COPY container/start-bigscreen container/start-remotes container/mpv-tv /usr/local/bin/
COPY container/remotes.desktop /etc/xdg/autostart/remotes.desktop
COPY container/mpv.conf /etc/mpv/mpv.conf

# Launchers and Stremio's external player open mpv through mpv.desktop, so
# this copy, which shadows the packaged one, sends them to mpv-tv.
RUN sed -e 's/^TryExec=mpv$/TryExec=mpv-tv/' \
        -e 's/^Exec=mpv /Exec=mpv-tv /' \
        /usr/share/applications/mpv.desktop > /usr/local/share/applications/mpv.desktop \
 && grep -q '^Exec=mpv-tv ' /usr/local/share/applications/mpv.desktop

ENV XDG_RUNTIME_DIR=/run/user/${HTPC_UID} \
    WAYLAND_DISPLAY=wayland-host \
    PULSE_SERVER=unix:/run/user/${HTPC_UID}/pulse/native \
    QTWEBENGINE_DISABLE_SANDBOX=1 \
    WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 \
    LANG=en_US.UTF-8

USER htpc
WORKDIR /home/htpc
CMD ["/usr/local/bin/start-bigscreen"]
