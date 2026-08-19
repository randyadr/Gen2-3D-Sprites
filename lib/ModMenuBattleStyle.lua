-- Stadium 2 battle-style skin for Gen1Recomp's Mod Manager and for simple
-- list-like menus opened by other mods from Gold's START / pause menu.
--
-- Goals:
--   * MODS is a real matching submenu over the voxel world.
--   * Selecting a mod opens a matching detail submenu; OPTIONS opens another
--     matching submenu for that mod's options_schema rows.
--   * Every mod that uses the engine Mod Manager/options_schema automatically
--     gets the same presentation, not just STADIUM2_OVERWORLD_MODELS.
--   * A third-party START-menu row that pushes a conventional list-like state
--     is opportunistically skinned too.  Its update/action logic is untouched.
--     Unknown/custom-rendered states are left native rather than guessed at.
--
-- Presentation only: no enable/disable, option persistence, dependency,
-- restart, profile, permission, or third-party menu actions are reimplemented.
local V = ...
local mod = V and V.mod

local M = {
  installed = false,
  managerDraws = 0,
  genericDraws = 0,
  managerTaggedFromPause = 0,
  genericTagged = 0,
  genericSkipped = 0,
  genericModal = 0,
  lastError = nil,
}

local StartMenuClass
local ManagerClass
local activeGame
local fonts = {}

local function customUIEnabled()
  local options = mod and mod.options
  if not (options and type(options.get) == "function") then return true end
  local ok, value = pcall(options.get, options, "customUI")
  if not ok or value == nil then return true end
  return value ~= false
end

local function font(size)
  size = math.max(5, math.floor((tonumber(size) or 10) + 0.5))
  if fonts[size] ~= nil then return fonts[size] or nil end
  local G = love and love.graphics
  if not (G and type(G.newFont) == "function") then
    fonts[size] = false
    return nil
  end
  local ok, f = pcall(G.newFont, size)
  fonts[size] = ok and f or false
  return fonts[size] or nil
end

local function cleanText(text)
  text = tostring(text or "")
  text = text:gsub("<PO><KE>", "POKé")
  text = text:gsub("<PK><MN>", "POKéMON")
  text = text:gsub("<POKE>", "POKé")
  text = text:gsub("<LV>", "LV ")
  text = text:gsub("<NEXT>", " ")
  text = text:gsub("[\v\f\r]", " ")
  text = text:gsub("\n", "  ")
  text = text:gsub("%s+", " ")
  return text
end

local function clipped(text, f, maxW)
  text = cleanText(text)
  if not f or type(f.getWidth) ~= "function" or f:getWidth(text) <= maxW then
    return text
  end
  local suffix = "..."
  while #text > 0 and f:getWidth(text .. suffix) > maxW do
    text = text:sub(1, -2)
  end
  return text .. suffix
end

local function roundRect(mode, x, y, w, h, r)
  love.graphics.rectangle(mode, x, y, w, h, r, r)
end

local function uiScaleFor(ww, wh)
  return math.max(0.18, math.min(1, math.min(ww / 800, wh / 600)))
end

local function panel(x, y, w, h, r, alpha, s)
  local G = love.graphics
  G.setColor(0.018, 0.026, 0.045, alpha or 0.82)
  roundRect("fill", x, y, w, h, r)
  G.setColor(1, 1, 1, 0.20)
  G.setLineWidth(math.max(1, 2 * (s or 1)))
  roundRect("line", x, y, w, h, r)
end

local function targetDimensions(fallbackW, fallbackH)
  if fallbackW and fallbackH and fallbackW > 0 and fallbackH > 0 then
    return fallbackW, fallbackH
  end
  local G = love and love.graphics
  if not G then return nil, nil end
  if type(G.getCanvas) == "function" then
    local ok, canvas = pcall(G.getCanvas)
    if ok and canvas and type(canvas.getDimensions) == "function" then
      local w, h = canvas:getDimensions()
      if w and h and w > 0 and h > 0 then return w, h end
    end
  end
  if type(G.getDimensions) == "function" then return G.getDimensions() end
  return nil, nil
end

local function beginDraw(ww, wh, opaque)
  local G = love and love.graphics
  if not (G and ww and wh and ww > 0 and wh > 0) then return false end
  G.push("all")
  G.origin()
  if type(G.setBlendMode) == "function" then G.setBlendMode("alpha") end
  if opaque then
    G.setColor(0.008, 0.012, 0.022, 1)
    G.rectangle("fill", 0, 0, ww, wh)
  end
  return true
end

local function endDraw(kind)
  love.graphics.pop()
  if kind == "manager" then M.managerDraws = M.managerDraws + 1
  else M.genericDraws = M.genericDraws + 1 end
end

local function header(title, subtitle, x, y, w, h, wh, s)
  local G = love.graphics
  local tf = font(math.max(18 * s, wh * 0.023))
  local mf = font(math.max(11 * s, wh * 0.013))
  if tf then G.setFont(tf) end
  G.setColor(1, 1, 1, 0.98)
  G.print(clipped(title, G.getFont(), w * 0.89), x + w * 0.055, y + h * 0.22)
  if subtitle and cleanText(subtitle) ~= "" then
    if mf then G.setFont(mf) end
    G.setColor(1, 1, 1, 0.58)
    G.print(clipped(subtitle, G.getFont(), w * 0.89), x + w * 0.055, y + h * 0.68)
  end
end

local function footer(text, x, y, w, h, gap, wh, s, warning)
  local G = love.graphics
  local f = font(math.max(10 * s, wh * 0.013))
  if f then G.setFont(f) end
  if warning and warning ~= "" then
    G.setColor(1, 0.86, 0.56, 0.96)
  else
    G.setColor(1, 1, 1, 0.58)
  end
  G.printf(cleanText(warning and warning ~= "" and warning or text),
    x + gap * 1.5, y + h - math.max(30 * s, wh * 0.037),
    w - gap * 3, "left")
end

local function geometry(ww, wh, requestedRows, opts)
  opts = opts or {}
  local s = uiScaleFor(ww, wh)
  local margin = math.max(18 * s, wh * 0.025)
  local w = math.min(ww * (opts.widthFrac or 0.46), (opts.maxW or 620) * s)
  local gap = math.max(7 * s, wh * 0.008)
  local headerH = math.max(48 * s, wh * 0.060)
  local footerH = math.max(42 * s, wh * 0.052)
  local baseRowH = math.max(48 * s, math.min(72 * s, wh * (opts.rowScale or 0.069)))
  local minRowH = math.max(31 * s, wh * 0.041)
  local available = math.max(1, wh - margin * 2)
  local rows = math.max(1, math.floor(tonumber(requestedRows) or 1))
  local function heightFor(n, rh)
    return headerH + rh * n + gap * (n + 1) + footerH
  end
  local rowH = baseRowH
  local h = heightFor(rows, rowH)
  if h > available then
    rowH = (available - headerH - footerH - gap * (rows + 1)) / rows
    if rowH < minRowH then
      rowH = minRowH
      rows = math.max(1, math.floor(
        (available - headerH - footerH - gap) / (rowH + gap)))
    end
    h = heightFor(rows, rowH)
  end
  local x = ww - w - margin
  local y = wh - h - margin
  local r = math.max(14 * s, wh * 0.022)
  return {
    x=x, y=y, w=w, h=h, rowH=rowH, gap=gap, headerH=headerH,
    footerH=footerH, rows=rows, r=r, s=s, margin=margin,
  }
end

local function windowFirst(count, visible, cursor, engineScroll)
  count = math.max(0, tonumber(count) or 0)
  visible = math.max(1, tonumber(visible) or 1)
  cursor = math.max(1, math.min(count > 0 and count or 1, tonumber(cursor) or 1))
  if count <= visible then return 1 end
  local first = math.max(1, (tonumber(engineScroll) or 0) + 1)
  if cursor < first then first = cursor end
  if cursor > first + visible - 1 then first = cursor - visible + 1 end
  if first + visible - 1 > count then first = math.max(1, count - visible + 1) end
  return first
end

-- Display row shape: { name, meta, value, disabled, header, warning }.
local function drawRows(ww, wh, title, subtitle, rows, cursor, engineScroll, opts)
  opts = opts or {}
  local G = love.graphics
  local geo = geometry(ww, wh, #rows, opts)
  panel(geo.x, geo.y, geo.w, geo.h, geo.r, opts.alpha or 0.84, geo.s)
  header(title, subtitle, geo.x, geo.y, geo.w, geo.headerH, wh, geo.s)
  local first = windowFirst(#rows, geo.rows, cursor, engineScroll)
  local nf = font(math.max(13 * geo.s, math.min(18 * geo.s, geo.rowH * 0.31)))
  local mf = font(math.max(9 * geo.s, math.min(12 * geo.s, geo.rowH * 0.22)))

  for slot = 1, geo.rows do
    local i = first + slot - 1
    local row = rows[i]
    if not row then break end
    local ry = geo.y + geo.headerH + geo.gap + (slot - 1) * (geo.rowH + geo.gap)
    local on = cursor and i == cursor and not row.header
    if row.header then
      if mf then G.setFont(mf) end
      G.setColor(1, 1, 1, 0.44)
      G.print(clipped(row.name or "", G.getFont(), geo.w - geo.gap * 4.4),
        geo.x + geo.gap * 2.2, ry + geo.rowH * 0.38)
    else
      G.setColor(1, 1, 1, on and 0.17 or 0.07)
      roundRect("fill", geo.x + geo.gap, ry, geo.w - geo.gap * 2,
        geo.rowH, geo.r * 0.55)
      if on then
        G.setColor(1, 1, 1, 0.72)
        G.setLineWidth(math.max(1, 2 * geo.s))
        roundRect("line", geo.x + geo.gap, ry, geo.w - geo.gap * 2,
          geo.rowH, geo.r * 0.55)
      end
      local lx = geo.x + geo.gap * 2.2
      local right = geo.x + geo.w - geo.gap * 2.2
      if nf then G.setFont(nf) end
      local value = cleanText(row.value)
      local valueW = value ~= "" and G.getFont():getWidth(value) or 0
      local hasMeta = cleanText(row.meta) ~= ""
      G.setColor(1, 1, 1, row.disabled and 0.38 or 0.98)
      G.print(clipped(row.name or "", G.getFont(),
        math.max(20, geo.w - geo.gap * 4.4 - valueW - geo.gap * 1.5)),
        lx, hasMeta and (ry + geo.rowH * 0.14) or (ry + geo.rowH * 0.31))
      if value ~= "" then
        G.setColor(1, 1, 1, row.warning and 0.94 or (row.disabled and 0.30 or 0.76))
        G.print(value, right - valueW,
          hasMeta and (ry + geo.rowH * 0.14) or (ry + geo.rowH * 0.31))
      end
      if hasMeta and geo.rowH >= 33 * geo.s then
        if mf then G.setFont(mf) end
        G.setColor(1, 1, 1, row.disabled and 0.28 or 0.58)
        G.print(clipped(row.meta, G.getFont(), geo.w - geo.gap * 4.4),
          lx, ry + geo.rowH * 0.60)
      end
    end
  end

  footer(opts.footer or
    "D-PAD / ARROWS SELECT    CROSS/A CONFIRM    CIRCLE/B BACK",
    geo.x, geo.y, geo.w, geo.h, geo.gap, wh, geo.s, opts.warning)
  return geo, first
end

local function drawMessage(ww, wh, rightX, title, text, opts)
  text = cleanText(text)
  if text == "" then return end
  opts = opts or {}
  local G = love.graphics
  local s = uiScaleFor(ww, wh)
  local margin = math.max(18 * s, wh * 0.025)
  local available = math.max(0, (rightX or ww) - margin * 2)
  if available < 78 * s then return end
  local w = math.min(ww * (opts.widthFrac or 0.52), 720 * s, available)
  local h = math.max(74 * s, math.min((opts.maxH or 126) * s, wh * (opts.heightFrac or 0.15)))
  local x, y = margin, wh - h - margin
  local r = math.max(14 * s, wh * 0.022)
  panel(x, y, w, h, r, opts.alpha or 0.78, s)
  local tf = font(math.max(15 * s, wh * 0.020))
  local bf = font(math.max(11 * s, wh * 0.014))
  if tf then G.setFont(tf) end
  G.setColor(1, 1, 1, 0.96)
  G.print(clipped(title or "", G.getFont(), w - h * 0.42),
    x + h * 0.20, y + h * 0.14)
  if bf then G.setFont(bf) end
  G.setColor(1, 1, 1, 0.64)
  G.printf(text, x + h * 0.20, y + h * 0.48, w - h * 0.40, "left")
end

local function drawChoice(ww, wh, title, subtitle, labels, cursor)
  local rows = {}
  for _, label in ipairs(labels) do rows[#rows + 1] = { name = cleanText(label) } end
  return drawRows(ww, wh, title, subtitle, rows, cursor, 0,
    { widthFrac=0.34, maxW=440, rowScale=0.061,
      footer="CROSS/A CONFIRM    CIRCLE/B BACK" })
end

local function safeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  return ok and value or nil
end

local function stackTop(game)
  local stack = game and game.stack
  if not (stack and type(stack.top) == "function") then return nil end
  return safeCall(stack.top, stack)
end

local function isStartMenu(state)
  return state and StartMenuClass and getmetatable(state) == StartMenuClass
end

local function openedFromPause(game)
  local top = stackTop(game)
  return isStartMenu(top) or (top and top._stadium2PauseSkinChain == true) or false
end

local function parentFor(state)
  local game = state and state.game or activeGame
  local stack = game and game.stack
  local states = stack and stack.states
  if type(states) ~= "table" then return nil end
  for i = #states, 1, -1 do
    if states[i] == state then return states[i - 1] end
  end
  return nil
end

local function rowTextValue(value)
  if type(value) == "function" then value = safeCall(value) end
  if value == nil then return "" end
  if type(value) == "boolean" then return value and "ON" or "OFF" end
  if type(value) == "table" then return "" end
  return cleanText(value)
end

local function managerStatus(m, manager)
  if not m then return "" end
  if manager and type(manager.isStaged) == "function" and safeCall(manager.isStaged, manager, m) then
    return "STAGED"
  end
  if m.error then return "ERROR" end
  if m.state == "blocked_dependency" then return "BLOCKED" end
  if m.state == "wrong_generation" then return "OTHER GAME" end
  return m.enabled and "ON" or "OFF"
end

local function managerDisplayRows(self)
  local source
  local scroll = tonumber(self.scroll) or 1
  if self.screen == "options" then
    source = self.optionRows or {}
    scroll = tonumber(self.scroll) or 0
  elseif type(self.rowsForScreen) == "function" then
    source = safeCall(self.rowsForScreen, self) or {}
    scroll = math.max(0, scroll - 1) -- ManagerState regular screens are 1-based.
  else
    source = {}
  end

  local rows = {}
  for _, row in ipairs(source) do
    local out = {
      name = cleanText(row.label or row.name or row.id or ""),
      header = row.header == true,
      disabled = row.inert == true,
    }
    if row.mod then
      local m = row.mod
      out.value = managerStatus(m, self)
      local pieces = {}
      if m.version then pieces[#pieces + 1] = "v" .. cleanText(m.version) end
      if m.category then pieces[#pieces + 1] = cleanText(m.category) end
      out.meta = table.concat(pieces, "    ")
      if out.value == "ERROR" or out.value == "BLOCKED" then out.warning = true end
    elseif self.screen == "options" then
      out.value = rowTextValue(row.value)
      out.meta = row.activate and not row.step and "OPEN SUBMENU" or nil
    elseif row.action and tostring(row.label or ""):find("..", 1, true) then
      out.value = ">"
      out.meta = "OPEN SUBMENU"
    elseif row.profile then
      out.meta = "MOD PROFILE"
      if self:optionsTable().activeProfile == row.profile.name then out.value = "ACTIVE" end
    elseif row.glyph and row.glyph ~= " " then
      out.value = cleanText(row.glyph)
    end
    if out.name == "" then out.name = "—" end
    rows[#rows + 1] = out
  end
  return rows, scroll
end

local function managerTitle(self)
  if self.screen == "list" then
    local tab = ({ "MODS", "PROFILES", "ERRORS" })[tonumber(self.tab) or 1] or "MODS"
    return "MOD MANAGER", tab
  elseif self.screen == "detail" then
    local m = self.currentMod
    return cleanText(m and (m.name or m.id) or "MOD"),
      cleanText((m and m.version and ("VERSION " .. m.version)) or "MOD DETAILS")
  elseif self.screen == "options" then
    local m = self.currentMod
    if self._stadium2OptionCategoryLabel then
      return cleanText(self._stadium2OptionCategoryLabel),
        cleanText(m and (m.name or m.id) or "MOD SETTINGS")
    end
    return "MOD OPTIONS", cleanText(m and (m.name or m.id) or "ADD-ON SETTINGS")
  elseif self.screen == "permissions" then
    return "MOD PERMISSIONS", cleanText(self.currentMod and (self.currentMod.name or self.currentMod.id) or "")
  elseif self.screen == "errors" then
    return "MOD ERRORS", cleanText(self.currentMod and (self.currentMod.name or self.currentMod.id) or "")
  elseif self.screen == "apply" then
    return "APPLY MOD CHANGES", "RESTART REQUIRED"
  end
  return "MOD MANAGER", cleanText(self.screen or "")
end

local function managerDescription(self)
  if self.notice then return cleanText(self.notice) end
  if self.banner then return cleanText(self.banner) end
  if self.screen == "detail" and self.currentMod then
    local m = self.currentMod
    local parts = {}
    if m.description then parts[#parts + 1] = cleanText(m.description) end
    if m.author then parts[#parts + 1] = "BY " .. cleanText(m.author) end
    if #parts == 0 then parts[1] = "Choose an action for this add-on." end
    return table.concat(parts, "    ")
  elseif self.screen == "options" then
    if self._stadium2OptionCategoryDescription then
      return cleanText(self._stadium2OptionCategoryDescription)
        .. "    Changes save immediately."
    end
    if self._stadium2CategorizedOptions then
      return "Choose a settings category. Every change inside a category saves immediately."
    end
    return "These are this add-on's own settings. Left/right or A changes values; rows that open editors keep the engine's native editor logic."
  elseif self.screen == "list" and tonumber(self.tab) == 1 then
    return "Select an installed add-on to open its submenu. From there you can enable/disable it, open its options, inspect permissions, or view errors."
  elseif self.screen == "list" and tonumber(self.tab) == 2 then
    return "Saved mod profiles. Left/right changes tabs; A applies the highlighted profile."
  elseif self.screen == "apply" then
    return "Apply staged mod changes and restart, or discard the staged changes."
  end
  return "Mod Manager"
end

local function drawManager(self, ww, wh)
  ww, wh = targetDimensions(ww, wh)
  if not (ww and wh) then return false end
  local pause = self._stadium2PauseSkinChain == true
  if not beginDraw(ww, wh, not pause) then return false end
  local title, subtitle = managerTitle(self)
  local rows, scroll = managerDisplayRows(self)
  if #rows == 0 then rows = { { name = "NO ENTRIES", disabled = true } } end
  local footerText
  if self.screen == "list" then
    footerText = "D-PAD SELECT    LEFT/RIGHT TAB    CROSS/A OPEN    SELECT QUICK TOGGLE    START APPLY    CIRCLE/B BACK"
  elseif self.screen == "options" then
    if self._stadium2CategorizedOptions and not self._stadium2OptionCategory then
      footerText = "D-PAD SELECT    CROSS/A OPEN CATEGORY    CIRCLE/B BACK"
    elseif self._stadium2OptionCategory then
      footerText = "D-PAD SELECT    LEFT/RIGHT CHANGE    CROSS/A CHANGE/OPEN    CIRCLE/B CATEGORIES"
    else
      footerText = "D-PAD SELECT    LEFT/RIGHT CHANGE    CROSS/A CHANGE/OPEN    CIRCLE/B DONE"
    end
  else
    footerText = "D-PAD SELECT    CROSS/A CONFIRM    CIRCLE/B BACK"
  end
  local geo = drawRows(ww, wh, title, subtitle, rows,
    tonumber(self.cursor) or 1, scroll,
    { widthFrac=0.48, maxW=650, rowScale=0.063, footer=footerText })
  drawMessage(ww, wh, geo.x, title, managerDescription(self),
    { heightFrac=0.17, maxH=145 })

  if self.overlay then
    local lines = {}
    for _, line in ipairs(self.overlay.lines or {}) do lines[#lines + 1] = cleanText(line) end
    local prompt = table.concat(lines, "  ")
    if self.overlay.kind == "confirm" then
      drawChoice(ww, wh, "CONFIRM", prompt, { "YES", "NO" }, tonumber(self.overlay.index) or 1)
    else
      drawChoice(ww, wh, "NOTICE", prompt, { "OK" }, 1)
    end
  end
  endDraw("manager")
  return true
end

local function genericLabel(row)
  if type(row) == "string" or type(row) == "number" then return cleanText(row) end
  if type(row) ~= "table" then return nil end
  local label = row.label or row.name or row.text or row.title
  if label == nil and row.value ~= nil and type(row.value) ~= "table" and type(row.value) ~= "function" then
    label = row.value
  end
  if label == nil then return nil end
  return cleanText(label)
end

local function genericRows(state)
  local source, cursor, scroll
  if type(state.list) == "table" and type(state.list.items) == "table" then
    source = state.list.items
    cursor = tonumber(state.list.index) or tonumber(state.index) or 1
    scroll = tonumber(state.list.scroll) or 0
  elseif type(state.menu) == "table" and type(state.menu.items) == "table" then
    source = state.menu.items
    cursor = tonumber(state.menu.index) or tonumber(state.index) or tonumber(state.cursor) or 1
    scroll = tonumber(state.menu.scroll) or tonumber(state.scroll) or 0
  elseif type(state.items) == "table" then
    source = state.items
    cursor = tonumber(state.index) or tonumber(state.cursor) or 1
    scroll = tonumber(state.scroll) or 0
  elseif type(state.entries) == "table" then
    source = state.entries
    cursor = tonumber(state.index) or tonumber(state.cursor) or 1
    scroll = tonumber(state.scroll) or 0
  elseif type(state.choices) == "table" then
    source = state.choices
    cursor = tonumber(state.index) or tonumber(state.cursor) or tonumber(state.choice) or 1
    scroll = tonumber(state.scroll) or 0
  elseif type(state.optionRows) == "table" then
    source = state.optionRows
    cursor = tonumber(state.cursor) or tonumber(state.index) or 1
    scroll = tonumber(state.scroll) or 0
  elseif type(state.rows) == "table" and (state.cursor ~= nil or state.index ~= nil) then
    source = state.rows
    cursor = tonumber(state.cursor) or tonumber(state.index) or 1
    scroll = tonumber(state.scroll) or 0
  else
    return nil
  end
  if #source == 0 then return nil end

  local rows, recognized = {}, 0
  for _, row in ipairs(source) do
    local label = genericLabel(row)
    local out = { name = label or "—" }
    if label then recognized = recognized + 1 end
    if type(row) == "table" then
      out.header = row.header == true
      out.disabled = row.disabled == true or row.inert == true
      if row.desc then
        if type(row.desc) == "table" then out.meta = table.concat(row.desc, " ")
        else out.meta = row.desc end
      elseif row.description then
        out.meta = row.description
      end
      if type(row.value) == "function" then out.value = rowTextValue(row.value)
      elseif row.value ~= nil and label ~= cleanText(row.value) then out.value = rowTextValue(row.value) end
    end
    rows[#rows + 1] = out
  end
  if recognized < math.max(1, math.ceil(#source * 0.60)) then return nil end
  return rows, math.max(1, math.min(#rows, cursor)), math.max(0, scroll)
end

local function genericTitle(state)
  local title = state.title or state.menuTitle or state.heading or state.name
  if type(title) ~= "string" or title == "" then
    local id = state.screenId or state.id
    if type(id) == "string" and id ~= "" then title = id end
  end
  return cleanText(title or "MOD MENU")
end

local function genericDescription(state, rows, cursor)
  local row = rows and rows[cursor]
  if row and cleanText(row.meta) ~= "" then return cleanText(row.meta) end
  return cleanText(state.description or state.help or state.subtitle or "Add-on menu")
end

-- A row-list skin can only stand in for a screen that is DRAWING its row list.
--
-- Several of Gold's menus keep a sub-screen INSIDE the same state object
-- rather than pushing a new one, and paint it from that state's own draw:
-- Gen2PcMenu's CHANGE BOX box picker (src/ui/gen2/PcMenu.lua drawPanel, on
-- self.picking) and its notice boxes (self.message) are the two this skin
-- meets, and the START menu's QUIT confirmation (self.phase == "confirm") is
-- the same shape.  The row list underneath does not change while one of them
-- is up, so skinning straight through it draws a menu the player is no longer
-- driving: CHANGE BOX looked like a dead row while A was really moving the
-- current box, unseen.
--
-- So the skin stands down for those frames and lets the screen's own renderer
-- draw, which is exactly what CUSTOM UI / MENUS = OFF does.  Every one of
-- these starts from a full-screen white fill (Chrome.clear, or the window
-- fill in drawWidescreen), so nothing underneath shows through in the one
-- frame before isOpaque is back to its native value -- StateStack:visibleBase
-- reads isOpaque before the draw that restores it.
local function genericModalUp(state)
  if type(state) ~= "table" then return false end
  if state.picking then return true end
  if state.message ~= nil then return true end
  if state.phase == "confirm" then return true end
  return false
end

local function drawGeneric(state, ww, wh)
  local rows, cursor, scroll = genericRows(state)
  if not rows then return false end
  ww, wh = targetDimensions(ww, wh)
  if not (ww and wh and beginDraw(ww, wh, false)) then return false end
  local title = genericTitle(state)
  local geo = drawRows(ww, wh, title, "ADD-ON SUBMENU", rows, cursor, scroll,
    { widthFrac=0.46, maxW=620, rowScale=0.064,
      footer="D-PAD / ARROWS SELECT    CROSS/A CONFIRM    CIRCLE/B BACK" })
  drawMessage(ww, wh, geo.x, title, genericDescription(state, rows, cursor))
  endDraw("generic")
  return true
end

local function wrapGenericState(state)
  if type(state) ~= "table" then return false end
  if not customUIEnabled() then return false end
  if state._stadium2PauseSkin or state._stadium2ManagerSkin then return false end
  if state._stadium2GenericModMenuWrapped then return true end
  local rows = genericRows(state)
  if not rows then
    state._stadium2PauseSkinChain = true
    state._stadium2PauseParentGame = state.game or activeGame
    M.genericSkipped = M.genericSkipped + 1
    return false
  end

  local nativeDraw = state.draw
  local nativeWide = state.drawWidescreen
  local nativeOpaque = state.isOpaque
  if type(nativeDraw) ~= "function" and type(nativeWide) ~= "function" then
    M.genericSkipped = M.genericSkipped + 1
    return false
  end

  state._stadium2PauseSkinChain = true
  state._stadium2PauseParentGame = state.game or activeGame
  state._stadium2GenericModMenuWrapped = true
  state.isOpaque = false
  M.genericTagged = M.genericTagged + 1

  if type(nativeDraw) == "function" then
    state.draw = function(self, ...)
      if not customUIEnabled() or genericModalUp(self) then
        self.isOpaque = nativeOpaque
        if customUIEnabled() then M.genericModal = M.genericModal + 1 end
        return nativeDraw(self, ...)
      end
      self.isOpaque = false
      local ok, handled = pcall(drawGeneric, self)
      if ok and handled then M.lastError = nil return end
      if not ok then M.lastError = "generic menu: " .. tostring(handled) end
      return nativeDraw(self, ...)
    end
  end
  if type(nativeWide) == "function" then
    state.drawWidescreen = function(self, ww, wh, ...)
      if not customUIEnabled() or genericModalUp(self) then
        self.isOpaque = nativeOpaque
        if customUIEnabled() then M.genericModal = M.genericModal + 1 end
        return nativeWide(self, ww, wh, ...)
      end
      self.isOpaque = false
      local ok, handled = pcall(drawGeneric, self, ww, wh)
      if ok and handled then M.lastError = nil return end
      if not ok then M.lastError = "generic wide menu: " .. tostring(handled) end
      return nativeWide(self, ww, wh, ...)
    end
  end
  return true
end

local function installManager()
  local ok, ManagerState = pcall(require, "src.mods.ManagerState")
  if not (ok and type(ManagerState) == "table" and type(ManagerState.new) == "function"
      and type(ManagerState.draw) == "function") then
    return false, "src.mods.ManagerState unavailable"
  end
  ManagerClass = ManagerState
  if ManagerState._stadium2AllModMenusPatched then return true end

  local nativeNew = ManagerState.new
  local nativeDraw = ManagerState.draw
  ManagerState.new = function(game, ...)
    local pause = openedFromPause(game)
    local instance = nativeNew(game, ...)
    if type(instance) == "table" and customUIEnabled() then
      instance._stadium2ManagerSkin = true
      if pause then
        activeGame = game or activeGame
        instance._stadium2PauseSkinChain = true
        instance.isOpaque = false
        M.managerTaggedFromPause = M.managerTaggedFromPause + 1
      end
    end
    return instance
  end
  ManagerState.draw = function(self, ...)
    if not customUIEnabled() then
      if self then self.isOpaque = true end
      return nativeDraw(self, ...)
    end
    if self and self._stadium2ManagerSkin ~= false then
      if self._stadium2PauseSkinChain then self.isOpaque = false end
      local okDraw, handled = pcall(drawManager, self)
      if okDraw and handled then M.lastError = nil return end
      if not okDraw then M.lastError = "ManagerState: " .. tostring(handled) end
    end
    return nativeDraw(self, ...)
  end
  ManagerState._stadium2AllModMenusPatched = true
  return true
end

local function installStartBridge()
  if not (StartMenuClass and type(StartMenuClass.choose) == "function") then
    -- Some tests/minimal hosts do not expose choose(); the screen.pushed seam
    -- still covers real Screens.push traffic.
    return true
  end
  if StartMenuClass._stadium2ModMenuBridgePatched then return true end
  local nativeChoose = StartMenuClass.choose
  StartMenuClass.choose = function(self, id, index, ...)
    activeGame = self and self.game or activeGame
    local before = stackTop(self and self.game)
    local result = nativeChoose(self, id, index, ...)
    local after = stackTop(self and self.game)
    if not customUIEnabled() then return result end
    if before == self and after and after ~= self then
      after._stadium2PauseSkinChain = true
      after._stadium2PauseParentGame = after.game or (self and self.game)
      if not (after._stadium2PauseSkin or after._stadium2ManagerSkin) then
        wrapGenericState(after)
      end
    end
    return result
  end
  StartMenuClass._stadium2ModMenuBridgePatched = true
  return true
end

local function installPushWatcher()
  if not (mod and mod.events and type(mod.events.on) == "function") then
    return false, "mod.events unavailable"
  end
  mod.events:on("screen.pushed", function(ev)
    if not customUIEnabled() then return end
    local state = ev and ev.state
    if type(state) ~= "table" then return end
    if state.game then activeGame = state.game end
    local parent = parentFor(state)
    if not (isStartMenu(parent) or (parent and parent._stadium2PauseSkinChain)) then return end
    -- Built-in Gold submenu skins and the specialized Manager renderer already
    -- own their presentation.  Keep their chain alive but do not double-wrap.
    if state._stadium2PauseSkin or state._stadium2ManagerSkin then
      state._stadium2PauseSkinChain = true
      return
    end
    wrapGenericState(state)
  end)
  return true
end

function M.install()
  if M.installed then return true end
  local okStart, Start = pcall(require, "src.ui.gen2.StartMenu")
  if not (okStart and type(Start) == "table") then
    return false, "src.ui.gen2.StartMenu unavailable"
  end
  StartMenuClass = Start
  local okManager, managerErr = installManager()
  if not okManager then return false, managerErr end
  local okBridge, bridgeErr = installStartBridge()
  if not okBridge then return false, bridgeErr end
  local okWatch, watchErr = installPushWatcher()
  if not okWatch then return false, watchErr end
  M.installed = true
  return true
end

function M.status()
  return {
    installed = M.installed,
    managerDraws = M.managerDraws,
    genericDraws = M.genericDraws,
    managerTaggedFromPause = M.managerTaggedFromPause,
    genericTagged = M.genericTagged,
    genericSkipped = M.genericSkipped,
    genericModal = M.genericModal,
    lastError = M.lastError,
  }
end

return M
