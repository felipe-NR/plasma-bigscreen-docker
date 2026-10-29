-- plasma-bigscreen-docker: keep the nested Plasma Bigscreen session fullscreen
-- on the TV. KWin's nested window sets no app id, so the rule matches its
-- title in English and in Portuguese.

local tv_output = "HDMI-A-1"
-- Above 10, so the Omarchy bar workspace selector and SUPER+number leave it out.
local tv_workspace = "11"

hl.workspace_rule({ workspace = tv_workspace, monitor = tv_output })

-- Once the TV is the only display on tv_output, swap the rule above for this
-- one so the TV shows the Bigscreen workspace as soon as it is connected.
-- hl.workspace_rule({ workspace = tv_workspace, monitor = tv_output, default = true })

o.window(
  { title = "^(KDE Wayland Compositor|Compositor KDE Wayland).*" },
  { workspace = tv_workspace .. " silent", fullscreen = true, idle_inhibit = "fullscreen" }
)

-- Stremio hands streams to mpv when its external player is on, and the image
-- starts that mpv on this compositor with the app id bigscreen-mpv. The nested
-- KWin only renders SDR, while a fullscreen client of Hyprland playing HDR
-- switches the TV to HDR (render.cm_auto_hdr). mpv gets a workspace of its own
-- so the Bigscreen window keeps its fullscreen state, and the Bigscreen comes
-- back when mpv closes.
local player_workspace = "12"

hl.workspace_rule({ workspace = player_workspace, monitor = tv_output })

o.window({ class = "^bigscreen-mpv$" }, { workspace = player_workspace, fullscreen = true })

hl.on("window.close", function(window)
  if window.class == "bigscreen-mpv" then
    hl.dispatch(hl.dsp.focus({ workspace = tv_workspace }))
  end
end)
