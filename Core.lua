local ADDON, ns = ...

ns.ADDON = ADDON
ns.TITLE = "Profession Sage"
ns.CALLER = "ProfessionSage"  -- how Auctionator's API knows us

--------------------------------------------------------------------------------
-- Client API (WoW Forever runs on the modern client; fall back just in case)
--------------------------------------------------------------------------------

ns.GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
ns.GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount
ns.GetItemIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon
ns.RequestItem = C_Item and C_Item.RequestLoadItemDataByID or function() end
ns.GetSpellName = C_Spell and C_Spell.GetSpellName or function(id) return (GetSpellInfo(id)) end
ns.GetSpellIcon = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture

function ns.Print(...)
  print("|cffd8b26e" .. ns.TITLE .. ":|r", ...)
end

--------------------------------------------------------------------------------
-- Errors: runs fn protected. An error is printed once per session in chat and
-- the last few are kept in saved variables, so they can be reported even
-- without an error-catching addon.
--------------------------------------------------------------------------------

local reported = {}

local function onError(label, message)
  local stack = debugstack and debugstack(3, 12, 0) or ""
  if ns.db then
    ns.db.errors = ns.db.errors or {}
    -- A repeat only bumps its count, so it can't push the first error out.
    local existing
    for _, e in ipairs(ns.db.errors) do
      if e.where == label and e.message == tostring(message) then
        existing = e
      end
    end
    if existing then
      existing.count = (existing.count or 1) + 1
      existing.when = date and date("%Y-%m-%d %H:%M:%S") or existing.when
    else
      table.insert(ns.db.errors, 1, { when = date and date("%Y-%m-%d %H:%M:%S") or "", where = label,
                                      message = tostring(message), stack = stack, count = 1 })
      while #ns.db.errors > 10 do
        table.remove(ns.db.errors)
      end
    end
  end
  local key = label .. tostring(message)
  if not reported[key] then
    reported[key] = true
    print("|cffff4040" .. ns.TITLE .. " error (" .. label .. "):|r " .. tostring(message))
  end
  if geterrorhandler then
    pcall(geterrorhandler(), message)
  end
end

function ns.SafeCall(label, fn, ...)
  local args = { ... }
  local n = select("#", ...)
  return xpcall(function() return fn(unpack(args, 1, n)) end, function(message)
    onError(label, message)
    return message
  end)
end

-- Wraps fn so every call is protected.
function ns.Safe(label, fn)
  return function(...)
    return select(2, ns.SafeCall(label, fn, ...))
  end
end

--------------------------------------------------------------------------------
-- Events and internal messages
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

function ns.On(event, handler)
  if not eventHandlers[event] then
    if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
      return false
    end
    eventHandlers[event] = {}
  end
  table.insert(eventHandlers[event], handler)
  return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  for _, handler in ipairs(eventHandlers[event]) do
    ns.SafeCall(event, handler, ...)
  end
end)

local listeners = {}

function ns.Listen(message, handler)
  listeners[message] = listeners[message] or {}
  table.insert(listeners[message], handler)
end

function ns.Fire(message, ...)
  for _, handler in ipairs(listeners[message] or {}) do
    ns.SafeCall(message, handler, ...)
  end
end

-- Runs fn once on the next frame, however often it's asked for in between.
function ns.Debounce(fn, delay)
  local queued = false
  return function()
    if queued then
      return
    end
    queued = true
    C_Timer.After(delay or 0, function()
      queued = false
      ns.SafeCall("update", fn)
    end)
  end
end

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------

local ACCOUNT_DEFAULTS = {
  showRowProfit = true,
  ahCut = 5,              -- percent the auction house keeps when you sell
  onlyKnown = false,      -- leveling guide: only use recipes you already know
  routeMode = "cheap",    -- leveling guide: "cheap", "fast" or "balanced"
  useBags = true,         -- count what you already have
  routeFilter = false,    -- recipe list: show only the leveling route, in order
  vendorPrices = {},      -- [item] = copper, learned at merchants
  learnAt = {},           -- [recipe spell] = skill a trainer requires
  recipeVendors = {},     -- [recipe item] = { [vendor name] = zone }, from visits
  trainers = {},          -- [skill line] = { [trainer name] = { zone, title } }, from visits
  tracker = { point = "RIGHT", x = -60, y = 120 },
}

local CHARACTER_DEFAULTS = {
  known = {},     -- [skill line] = { [recipe spell] = true }
  targets = {},   -- [skill line] = target skill for the leveling guide
  shopping = nil, -- what the materials popup is tracking, if anything
}

local function fillDefaults(target, defaults)
  for key, default in pairs(defaults) do
    if type(target[key]) ~= type(default) then
      target[key] = type(default) == "table" and CopyTable(default) or default
    end
  end
end

ns.On("ADDON_LOADED", function(loaded)
  if loaded ~= ADDON then
    return
  end
  if type(ProfessionSageDB) ~= "table" then
    ProfessionSageDB = {}
  end
  if type(ProfessionSageCharDB) ~= "table" then
    ProfessionSageCharDB = {}
  end
  ns.db = ProfessionSageDB
  ns.char = ProfessionSageCharDB
  fillDefaults(ns.db, ACCOUNT_DEFAULTS)
  fillDefaults(ns.char, CHARACTER_DEFAULTS)
  ns.Fire("DB_READY")
end)

ns.On("PLAYER_LOGIN", function()
  ns.Fire("LOGIN")
end)

--------------------------------------------------------------------------------
-- Money
--------------------------------------------------------------------------------

local GOLD, SILVER, COPPER = "|cffffd700", "|cffc7c7cf", "|cffeda55f"

-- Compact money text: "1g 20s", "45s 10c", "8c". Only the two largest units.
function ns.Money(copper)
  if not copper then
    return "?"
  end
  copper = math.floor(math.abs(copper) + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if g > 0 then
    return s > 0 and string.format("%d%sg|r %d%ss|r", g, GOLD, s, SILVER) or string.format("%d%sg|r", g, GOLD)
  elseif s > 0 then
    return c > 0 and string.format("%d%ss|r %d%sc|r", s, SILVER, c, COPPER) or string.format("%d%ss|r", s, SILVER)
  end
  return string.format("%d%sc|r", c, COPPER)
end

-- Money with Blizzard's coin icons, for totals.
function ns.Coins(copper)
  if not copper then
    return "?"
  end
  copper = math.floor(copper + 0.5)
  if GetCoinTextureString then
    return GetCoinTextureString(copper)
  end
  return ns.Money(copper)
end

-- "+1g 20s" in green or "-45s" in red.
function ns.Profit(copper)
  if not copper then
    return ""
  end
  if copper >= 0 then
    return "|cff40c040+|r" .. ns.Money(copper)
  end
  return "|cffff4040-|r" .. ns.Money(copper)
end

--------------------------------------------------------------------------------
-- Items
--------------------------------------------------------------------------------

-- Name (with quality color) and icon; asks the server for unknown items.
function ns.ItemLabel(item)
  local name, _, quality = ns.GetItemInfo(item)
  if not name then
    ns.RequestItem(item)
    return "item:" .. item, ns.GetItemIcon(item)
  end
  local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  if color and color.hex then
    name = color.hex .. name .. "|r"
  end
  return name, ns.GetItemIcon(item)
end

function ns.ItemName(item)
  return (ns.GetItemInfo(item))
end

-- How many you have: bags plus bank (when the setting is on).
function ns.HaveCount(item)
  if not ns.db.useBags then
    return 0
  end
  return ns.GetItemCount(item, true) or 0
end

local itemInfoChanged = ns.Debounce(function() ns.Fire("ITEM_INFO") end, 0.2)
ns.On("GET_ITEM_INFO_RECEIVED", itemInfoChanged)

--------------------------------------------------------------------------------
-- Your professions
--------------------------------------------------------------------------------

-- Skill lines with recipes in our data that this character has, with skill.
-- { skillLine, name, icon, rank, maxRank }
function ns.GetPlayerProfessions()
  local result = {}
  if not GetProfessions then
    return result
  end
  for _, index in pairs({ GetProfessions() }) do
    local name, icon, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
    if skillLine and (ns.RECIPES[skillLine] or (ns.GATHERING and ns.GATHERING[skillLine])) then
      table.insert(result, { skillLine = skillLine, name = name, icon = icon, rank = rank, maxRank = maxRank })
    end
  end
  return result
end

function ns.GetProfessionSkill(skillLine)
  for _, profession in ipairs(ns.GetPlayerProfessions()) do
    if profession.skillLine == skillLine then
      return profession.rank, profession.maxRank, profession
    end
  end
end

-- The profession open in Blizzard's window, as a skill line in our data.
function ns.GetOpenProfession()
  if not (C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo) then
    return nil
  end
  local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
  if not ok or type(info) ~= "table" then
    return nil
  end
  for _, id in ipairs({ info.professionID, info.parentProfessionID }) do
    if id and (ns.RECIPES[id] or (ns.GATHERING and ns.GATHERING[id])) then
      return id, info
    end
  end
end
