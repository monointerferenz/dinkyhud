--- === dinkyhud ===

local DINKY_BIN = "/opt/homebrew/bin/dinky" -- Verify path with `which dinky`
local APP_FONT  = "sketchybar-app-font"

-- Position: "top" (just below the menu bar) or "bottom" (above the Dock)
local POSITION  = "bottom"

local LAYOUT_LABELS = {
    dwindle   = "   dwi",
    master    = "   mst",
    scrolling = "   scr"
}

local MODE_COLORS = {
    main    = { red = 0.50, green = 0.62, blue = 0.75, alpha = 1.0 }, -- Soft sky blue
    service = { red = 0.78, green = 0.63, blue = 0.36, alpha = 1.0 }, -- Warm orange/amber
    default = { red = 0.61, green = 0.51, blue = 0.61, alpha = 1.0 }  -- Lavender fallback for other modes
}

local function getLayoutBadgeColor(mode)
    if not mode or mode == "" then
        return MODE_COLORS.main
    end
    return MODE_COLORS[mode] or MODE_COLORS.default
end

-- Map exact macOS %{app-name} strings to sketchybar-app-font ligatures.
-- Any app not listed here automatically falls back to `:lowercase_name:` (or `:default:` if unknown).
local VALID_LIGATURES = {}

local function loadSketchybarIconMap(path)
    local map = {}
    local file = io.open(path, "r")
    if not file then return map end

    local pendingApps = {}
    for line in file:lines() do
        for app in line:gmatch('"([^"]+)"') do
            if not app:match("^:.*:$") then
                table.insert(pendingApps, app)
            end
        end

        local ligature = line:match('icon_result="(:[^"]+:)"')
        if ligature then
            VALID_LIGATURES[ligature] = true -- Track every real glyph in the font
            for _, app in ipairs(pendingApps) do
                map[app] = ligature
            end
            pendingApps = {}
        end
    end

    file:close()
    return map
end

local APP_LIGATURES = loadSketchybarIconMap(hs.configdir .. "/icon_map.sh")


-- Global canvas reference & click target map
if dinkyHud then dinkyHud:delete() end
dinkyHud = hs.canvas.new({ x = 0, y = 0, w = 200, h = 32 })
dinkyHud:level(hs.canvas.windowLevels.floating)
dinkyHud:behavior(
    hs.canvas.windowBehaviors.canJoinAllSpaces +
    hs.canvas.windowBehaviors.stationary +
    hs.canvas.windowBehaviors.ignoresCycle
    )

local clickZones = {}

local function runDinky(args, callback)
    local task = hs.task.new(DINKY_BIN, function(exitCode, stdOut)
        if callback then
            local cleanOut = (exitCode == 0 and stdOut) and stdOut:gsub("%s+$", "") or nil
            callback(cleanOut)
        end
    end, args)
    if task then task:start() end
end

local function getAppLigature(app)
    -- 1. Direct match from icon_map.sh
    if APP_LIGATURES[app] then
        return APP_LIGATURES[app]
    end

    -- 2. Try normalized guess ONLY if that ligature actually exists in the font
    local normalized = ":" .. app:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "") .. ":"
    if VALID_LIGATURES[normalized] then
        return normalized
    end

    -- 3. Safe fallback to the generic app icon
    return ":default:"
end

-- Build styled text for one Space segment and measure its exact pixel width
local function makeSpaceStyledText(wsNum, icons, isFocused)
    local numColor  = isFocused and { red = 0.91, green = 0.86, blue = 0.71, alpha = 1.0 } or { red = 0.83, green = 0.76, blue = 0.63, alpha = 0.7 }
    local iconColor = isFocused and { red = 0.91, green = 0.86, blue = 0.71, alpha = 0.95 } or { red = 0.83, green = 0.76, blue = 0.63, alpha = 0.55 }

    local numStyle  = { font = { name = ".AppleSystemUIFontBold", size = 12 }, color = numColor, baselineOffset = -1.5 }
    local iconStyle = { font = { name = APP_FONT, size = 12 }, color = iconColor, baselineOffset = -3.0 }

    local st = hs.styledtext.new(wsNum, numStyle)
    if icons and #icons > 0 then
        st = st .. hs.styledtext.new(" " .. table.concat(icons, " "), iconStyle)
    end
    return st
end

local function updateHud()
    runDinky({
        "list-workspaces",
        "--all",
        "--format",
        "%{workspace}|%{workspace-is-focused}|%{workspace-layout}"
    }, function(wsOut)
        if not wsOut or wsOut == "" then
            dinkyHud:hide()
            return
        end

        runDinky({
            "list-windows",
            "--all",
            "--format",
            "%{workspace}|%{app-name}"
        }, function(winOut)
            runDinky({ "list-modes", "--current" }, function(modeOut)
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
                                table.insert(appsByWs[ws], getAppLigature(app))
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
                            local st = makeSpaceStyledText(ws, icons, focused)
                            local size = dinkyHud:minimumTextSize(st)
                            table.insert(segments, {
                                ws = ws,
                                focused = focused,
                                text = st,
                                width = math.ceil(size.w) + 16
                            })
                        end
                    end
                end

                -- Apply dynamic color based on `dinky list-modes --current`
                local layoutColor = getLayoutBadgeColor(currentMode)
                local layoutText = hs.styledtext.new(
                    LAYOUT_LABELS[activeLayout] or activeLayout,
                    { font = { name = ".AppleSystemUIFont", size = 12 }, color = layoutColor }
                )
                local layoutWidth = math.ceil(dinkyHud:minimumTextSize(layoutText).w) + 18

                local outerPad = 6
                local gap = 4
                local height = 30
                local totalWidth = outerPad * 2 + layoutWidth + gap

                for _, seg in ipairs(segments) do
                    totalWidth = totalWidth + seg.width + gap
                end

                local screenFrame = hs.screen.primaryScreen():frame()
                local x = math.floor(screenFrame.x + (screenFrame.w - totalWidth) / 2)
                local y = (POSITION == "bottom")
                    and (screenFrame.y + screenFrame.h - height - 8)
                    or  (screenFrame.y + 6)

                dinkyHud:frame({ x = x, y = y, w = totalWidth, h = height })

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

                clickZones = {}
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

                    table.insert(clickZones, {
                        x1 = cursorX,
                        x2 = cursorX + seg.width,
                        action = function()
                            runDinky({ "workspace", seg.ws }, updateHud)
                        end
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

                table.insert(clickZones, {
                    x1 = cursorX,
                    x2 = totalWidth,
                    action = function()
                        runDinky({ "workspace-layout", "dwindle", "master", "scrolling" }, updateHud)
                    end
                })

                dinkyHud:replaceElements(elements)
                dinkyHud:show()
            end)
        end)
    end)
end

-- Handle clicks on Space segments or the layout badge
-- dinkyHud:mouseCallback(function(_, event, _, x, _)
--     if event == "mouseUp" then
--         for _, zone in ipairs(clickZones) do
--             if x >= zone.x1 and x <= zone.x2 then
--                 zone.action()
--                 break
--             end
--         end
--     end
-- end)
dinkyHud:canvasMouseEvents(true, true, false, false)
updateHud()
-- Refresh every 2 seconds and immediately on Space changes or app launches/quits
dinkyTimer = hs.timer.doEvery(2, updateHud)
dinkySpaceWatcher = hs.spaces.watcher.new(function()
    hs.timer.doAfter(0.15, updateHud)
end):start()
dinkyAppWatcher = hs.application.watcher.new(function(_, event)
    if event == hs.application.watcher.launched or event == hs.application.watcher.terminated then
        hs.timer.doAfter(0.2, updateHud)
    end
end):start()