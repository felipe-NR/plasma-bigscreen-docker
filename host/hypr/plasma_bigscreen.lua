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
