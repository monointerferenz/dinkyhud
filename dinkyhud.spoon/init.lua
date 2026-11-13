--- === dinkyhud ===
---
--- A compact floating HUD for the dinky tiling window manager
---
--- The HUD shows every workspace that has windows (plus the focused one),
--- renders a sketchybar-app-font icon for each app running in it, and appends
--- a badge for the current layout/mode. It refreshes on a timer and
--- immediately when Spaces change or applications launch/quit.
---
--- Requirements:
---  * `dinky` installed (default path `/opt/homebrew/bin/dinky`, override with `dinkyhud.dinkyBin`)
---  * `sketchybar-app-font` installed for the app icons
---
--- Usage:
---
---     hs.loadSpoon("dinkyhud")
---     spoon.dinkyhud.position = "top" -- optional, before start()
---     spoon.dinkyhud:start()

local obj = {}
obj.__index = obj

-- Metadata
obj.name    = "dinkyhud"
obj.version = "0.1"
obj.author  = "monointerferenz <operator@monointerferenz.de>",
obj.license = "CC0 1.0"

--- dinkyhud.dinkyBin
--- Variable
--- Absolute path to the `dinky` executable
obj.dinkyBin = "/opt/homebrew/bin/dinky"

--- dinkyhud.appFont
--- Variable
--- Font used for the app icons (requires the sketchybar-app-font glyphs)
obj.appFont = "sketchybar-app-font"

--- dinkyhud.position
--- Variable
--- Vertical placement: "bottom" (above the Dock) or "top" (just below the menu bar)
obj.position = "bottom"

--- dinkyhud.refreshInterval
--- Variable
--- Seconds between automatic refreshes
obj.refreshInterval = 2

--- dinkyhud.iconMapPath
--- Variable
--- Path to the sketchybar app icon map; defaults to the `icon_map.sh` bundled with this Spoon
obj.iconMapPath = nil

--- dinkyhud.layoutLabels
--- Variable
--- Short label shown for each layout (keys: `dwindle`, `master`, `scrolling`)
obj.layoutLabels = {
    dwindle   = "   dwi",
    master    = "   mst",
    scrolling = "   scr",
}

--- dinkyhud.modeColors
--- Variable
--- Badge colours keyed by dinky mode name; `default` is used for unknown modes
obj.modeColors = {
    main    = { red = 0.50, green = 0.62, blue = 0.75, alpha = 1.0 }, -- Soft sky blue
    service = { red = 0.78, green = 0.63, blue = 0.36, alpha = 1.0 }, -- Warm orange/amber
    default = { red = 0.61, green = 0.51, blue = 0.61, alpha = 1.0 }, -- Lavender fallback
}

-- Map exact macOS %{app-name} strings to sketchybar-app-font ligatures.
-- Any app not listed here automatically falls back to `:lowercase_name:`
-- (or `:default:` if the font has no such glyph).

local function loadSketchybarIconMap(path)
    local map, valid = {}, {}
    local file = io.open(path, "r")
    if not file then return map, valid end

    local pendingApps = {}
    for line in file:lines() do
        for app in line:gmatch('"([^"]+)"') do
            if not app:match("^:.*:$") then
                table.insert(pendingApps, app)
            end
        end

        local ligature = line:match('icon_result="(:[^"]+:)"')
        if ligature then
            valid[ligature] = true -- Track every real glyph in the font
            for _, app in ipairs(pendingApps) do
                map[app] = ligature
            end
            pendingApps = {}
        end
    end

    file:close()
    return map, valid
end

local function layoutBadgeColor(mode, colors)
    if not mode or mode == "" then
        return colors.main
    end
    return colors[mode] or colors.default
end

function obj:_loadIconMap()
    local path = self.iconMapPath or hs.spoons.resourcePath("icon_map.sh")
    self._appLigatures, self._validLigatures = loadSketchybarIconMap(path)
end

function obj:_appLigature(app)
    -- 1. Direct match from the icon map
    local map = self._appLigatures or {}
    if map[app] then
        return map[app]
    end

    -- 2. Try a normalized guess, but only if that ligature really exists in the font
    local valid = self._validLigatures or {}
    local normalized = ":" .. app:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "") .. ":"
    if valid[normalized] then
        return normalized
    end

    -- 3. Safe fallback to the generic app icon
    return ":default:"
end

-- Build styled text for one Space segment
function obj:_spaceStyledText(wsNum, icons, isFocused)
    local numColor  = isFocused and { red = 0.91, green = 0.86, blue = 0.71, alpha = 1.0 } or { red = 0.83, green = 0.76, blue = 0.63, alpha = 0.7 }
    local iconColor = isFocused and { red = 0.91, green = 0.86, blue = 0.71, alpha = 0.95 } or { red = 0.83, green = 0.76, blue = 0.63, alpha = 0.55 }

    local numStyle  = { font = { name = ".AppleSystemUIFontBold", size = 12 }, color = numColor, baselineOffset = -1.5 }
    local iconStyle = { font = { name = self.appFont, size = 12 }, color = iconColor, baselineOffset = -3.0 }

    local st = hs.styledtext.new(wsNum, numStyle)
    if icons and #icons > 0 then
        st = st .. hs.styledtext.new(" " .. table.concat(icons, " "), iconStyle)
    end
    return st
end

function obj:_runDinky(args, callback)
    local task = hs.task.new(self.dinkyBin, function(exitCode, stdOut)
        if callback then
            local cleanOut = (exitCode == 0 and stdOut) and stdOut:gsub("%s+$", "") or nil
            callback(cleanOut)
        end
    end, args)
    if task then task:start() end
end

--- dinkyhud:init()
--- Method
--- Create the HUD canvas
---
--- Called automatically by `hs.loadSpoon`. Calling it again replaces any
--- canvas created by a previous call.
---
--- Returns:
---  * The dinkyhud object
function obj:init()
    if self.canvas then self.canvas:delete() end
    self.canvas = hs.canvas.new({ x = 0, y = 0, w = 200, h = 32 })
    self.canvas:level(hs.canvas.windowLevels.floating)
    self.canvas:behavior(
        hs.canvas.windowBehaviors.canJoinAllSpaces +
        hs.canvas.windowBehaviors.stationary +
        hs.canvas.windowBehaviors.ignoresCycle
    )
    return self
end

--- dinkyhud:start()
--- Method
--- Start the HUD
---
--- Loads the icon map, performs an immediate refresh, starts the refresh
--- timer and the Spaces/application watchers. A previous run is stopped
--- first, so calling this twice is safe.
---
--- Returns:
---  * The dinkyhud object
function obj:start()
    self:stop()
    if not self.canvas then self:init() end
    self:_loadIconMap()
    self:update()

    self.timer = hs.timer.doEvery(self.refreshInterval, function()
        self:update()
    end)

    self.spaceWatcher = hs.spaces.watcher.new(function()
        hs.timer.doAfter(0.15, function() self:update() end)
    end):start()

    self.appWatcher = hs.application.watcher.new(function(_, event)
        if event == hs.application.watcher.launched or event == hs.application.watcher.terminated then
            hs.timer.doAfter(0.2, function() self:update() end)
        end
    end):start()

    return self
end

--- dinkyhud:stop()
--- Method
--- Stop the HUD
---
--- Stops the refresh timer and both watchers, and hides the canvas. The HUD
--- can be started again with `start()`.
---
--- Returns:
---  * The dinkyhud object
function obj:stop()
    if self.timer then self.timer:stop(); self.timer = nil end
    if self.spaceWatcher then self.spaceWatcher:stop(); self.spaceWatcher = nil end
    if self.appWatcher then self.appWatcher:stop(); self.appWatcher = nil end
    if self.canvas then self.canvas:hide() end
    return self
end

--- dinkyhud:update()
--- Method
--- Refresh the HUD immediately
---
--- Queries `dinky` for the current workspaces, windows and mode, then
--- redraws the canvas. Refreshes happen automatically while the HUD is
--- running; call this only when you want an on-demand redraw.
---
--- Returns:
---  * The dinkyhud object
function obj:update()
    if not self.canvas then return self end
    if not self._appLigatures then self:_loadIconMap() end

    local canvas = self.canvas

    self:_runDinky({
        "list-workspaces",
        "--all",
        "--format",
        "%{workspace}|%{workspace-is-focused}|%{workspace-layout}"
    }, function(wsOut)
        if not wsOut or wsOut == "" then
            canvas:hide()
            return
        end

        self:_runDinky({
            "list-windows",
            "--all",
            "--format",
            "%{workspace}|%{app-name}"
        }, function(winOut)
            self:_runDinky({ "list-modes", "--current" }, function(modeOut)
                local currentMode = modeOut or "main"
                local appsByWs, seenByWs = {}, {}

                if winOut and winOut ~= "" then
                    for line in winOut:gmatch("[^\r\n]+") do
                        local ws, app = line:match("^([^|]+)|(.*)$")
                        if ws and app and app ~= "" then
                            appsByWs[ws] = appsByWs[ws] or {}
                            seenByWs[ws] = seenByWs[ws] or {}
                            if not seenByWs[ws][app] then
                                seenByWs[ws][app] = true
                                table.insert(appsByWs[ws], self:_appLigature(app))
                            end
                        end
                    end
                end

                local segments = {}
                local activeLayout = "dwindle"

                for line in wsOut:gmatch("[^\r\n]+") do
                    local ws, isFocused, layout = line:match("^([^|]+)|([^|]+)|(.*)$")
                    if ws then
                        local focused = (isFocused == "true")
                        if focused and layout and layout ~= "" then
                            activeLayout = layout
                        end

                        local icons = appsByWs[ws]
                        if (icons and #icons > 0) or focused then
                            local st = self:_spaceStyledText(ws, icons, focused)
                            local size = canvas:minimumTextSize(st)
                            table.insert(segments, {
                                focused = focused,
                                text = st,
                                width = math.ceil(size.w) + 16
                            })
                        end
                    end
                end

                -- Apply dynamic color based on `dinky list-modes --current`
                local layoutColor = layoutBadgeColor(currentMode, self.modeColors)
                local layoutText = hs.styledtext.new(
                    self.layoutLabels[activeLayout] or activeLayout,
                    { font = { name = ".AppleSystemUIFont", size = 12 }, color = layoutColor }
                )
                local layoutWidth = math.ceil(canvas:minimumTextSize(layoutText).w) + 18

                local outerPad = 6
                local gap = 4
                local height = 30
                local totalWidth = outerPad * 2 + layoutWidth + gap

                for _, seg in ipairs(segments) do
                    totalWidth = totalWidth + seg.width + gap
                end

                local screenFrame = hs.screen.primaryScreen():frame()
                local x = math.floor(screenFrame.x + (screenFrame.w - totalWidth) / 2)
                local y = (self.position == "bottom")
                    and (screenFrame.y + screenFrame.h - height - 8)
                    or  (screenFrame.y + 6)

                canvas:frame({ x = x, y = y, w = totalWidth, h = height })

                local elements = {
                    {
                        type = "rectangle",
                        action = "fill",
                        roundedRectRadii = { xRadius = 10, yRadius = 10 },
                        fillColor = { red = 0.16, green = 0.16, blue = 0.16, alpha = 0.88 }
                    },
                    {
                        type = "rectangle",
                        action = "stroke",
                        strokeWidth = 1,
                        roundedRectRadii = { xRadius = 10, yRadius = 10 },
                        -- Optional: tint the outer HUD border orange when in service mode
                        strokeColor = (currentMode == "service")
                            and { red = 0.28, green = 0.26, blue = 0.23, alpha = 0.55 }
                            or  { white = 1.0, alpha = 0.14 }
                    }
                }

                local cursorX = outerPad

                for _, seg in ipairs(segments) do
                    if seg.focused then
                        table.insert(elements, {
                            type = "rectangle",
                            action = "fill",
                            frame = { x = cursorX, y = 4, w = seg.width, h = height - 8 },
                            roundedRectRadii = { xRadius = 7, yRadius = 7 },
                            fillColor = { white = 1.0, alpha = 0.16 }
                        })
                    end

                    table.insert(elements, {
                        type = "text",
                        frame = { x = cursorX + 8, y = 6, w = seg.width - 8, h = height - 6 },
                        text = seg.text
                    })

                    cursorX = cursorX + seg.width + gap
                end

                table.insert(elements, {
                    type = "rectangle",
                    action = "fill",
                    frame = { x = cursorX, y = 7, w = 1, h = height - 14 },
                    fillColor = { white = 1.0, alpha = 0.15 }
                })
                cursorX = cursorX + gap + 1

                table.insert(elements, {
                    type = "text",
                    frame = { x = cursorX + 6, y = 7, w = layoutWidth - 6, h = height - 7 },
                    text = layoutText
                })

                canvas:replaceElements(elements)
                canvas:show()
            end)
        end)
    end)

    return self
end

return obj
