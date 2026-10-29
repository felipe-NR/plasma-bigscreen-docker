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

local function is_bigscreen(window)
  return window.title:find("^KDE Wayland Compositor") ~= nil
    or window.title:find("^Compositor KDE Wayland") ~= nil
end

-- KWin hides the host cursor over its window only once the pointer enters
-- the window. When the window shows up under a pointer that does not move,
-- as after mpv closes or the container restarts, the host keeps drawing its
-- own cursor next to KWin's. Moving the pointer into the window hands it
-- over; the one-pixel step makes sure Hyprland sees a motion.
local function hand_pointer_to_bigscreen()
  for _, window in ipairs(hl.get_windows()) do
    if is_bigscreen(window) and window.workspace and window.workspace.active then
      local x = window.at.x + math.floor(window.size.x / 2)
      local y = window.at.y + math.floor(window.size.y / 2)
      hl.dispatch(hl.dsp.cursor.move({ x = x + 1, y = y }))
      hl.dispatch(hl.dsp.cursor.move({ x = x, y = y }))
      return
    end
  end
end

hl.on("window.close", function(window)
  if window.class == "bigscreen-mpv" then
    hl.dispatch(hl.dsp.focus({ workspace = tv_workspace }))
    hl.timer(hand_pointer_to_bigscreen, { timeout = 300, type = "oneshot" })
  end
end)

hl.on("window.open", function(window)
  if is_bigscreen(window) then
    hl.timer(hand_pointer_to_bigscreen, { timeout = 1000, type = "oneshot" })
  end
end)
