local _, ns = ...

--------------------------------------------------------------------------------
-- Where to get a recipe item: vendors, drops, objects and quests.
--
-- Two sources, neither copied into this addon:
--  * Questie's database (LibQuestieDB), read at runtime when Questie is installed.
--  * Vendors you've visited yourself, remembered account-wide.
--------------------------------------------------------------------------------

local Sources = {}
ns.Sources = Sources

local WORLD_DROP_CREATURES = 8  -- more droppers than this reads as "world drop"
local SHOW_EACH = 3              -- how many vendors / creatures to name

local cache = {}

local function questieDB()
  local lib = _G.LibQuestieDB
  if type(lib) == "table" and lib.Item and lib.Npc and type(lib.Item.Get) == "function" then
    return lib
  end
end

function Sources.HasQuestie()
  return questieDB() ~= nil
end

local function zoneName(areaID)
  if type(areaID) ~= "number" or areaID == 0 then
    return nil
  end
  if C_Map and C_Map.GetAreaInfo then
    return C_Map.GetAreaInfo(areaID)
  end
end

local playerFaction
local function friendlyToMe(friendly)
  -- Questie: "A", "H", "AH" (or nil when anyone can use them).
  if type(friendly) ~= "string" or friendly == "" or friendly == "AH" then
    return true
  end
  playerFaction = playerFaction or UnitFactionGroup("player")
  return (friendly == "A" and playerFaction == "Alliance") or (friendly == "H" and playerFaction == "Horde")
end

local function npcInfo(lib, npc)
  local ok, name = pcall(lib.Npc.Get, npc, "name")
  if not ok or not name then
    return nil
  end
  local _, zone = pcall(lib.Npc.Get, npc, "zoneID")
  local _, friendly = pcall(lib.Npc.Get, npc, "friendlyToFaction")
  return { name = name, zone = zoneName(zone), friendly = friendly }
end

local function fromQuestie(item, result)
  local lib = questieDB()
  if not lib then
    return
  end
  local function field(key)
    local ok, value = pcall(lib.Item.Get, item, key)
    return ok and type(value) == "table" and value or nil
  end

  for _, npc in ipairs(field("vendors") or {}) do
    local info = npcInfo(lib, npc)
    if info and friendlyToMe(info.friendly) then
      table.insert(result.vendors, info)
    end
  end

  local drops = field("npcDrops") or {}
  if #drops > WORLD_DROP_CREATURES then
    result.worldDrop = true
  end
  for _, npc in ipairs(drops) do
    local info = npcInfo(lib, npc)
    if info then
      table.insert(result.drops, info)
    end
    if #result.drops >= SHOW_EACH then
      break
    end
  end
  result.dropCount = #drops

  if lib.Object and type(lib.Object.Get) == "function" then
    for _, object in ipairs(field("objectDrops") or {}) do
      local ok, name = pcall(lib.Object.Get, object, "name")
      if ok and name then
        table.insert(result.objects, name)
      end
    end
  end

  if lib.Quest and type(lib.Quest.Get) == "function" then
    for _, quest in ipairs(field("questRewards") or {}) do
      local ok, name = pcall(lib.Quest.Get, quest, "name")
      if ok and name then
        table.insert(result.quests, name)
      end
    end
  end
end

local function fromVisits(item, result)
  local seen = ns.db and ns.db.recipeVendors[item]
  if not seen then
    return
  end
  for name, zone in pairs(seen) do
    local duplicate = false
    for _, vendor in ipairs(result.vendors) do
      if vendor.name == name then
        duplicate = true
      end
    end
    if not duplicate then
      table.insert(result.vendors, 1, { name = name, zone = zone ~= "" and zone or nil, visited = true })
    end
  end
end

-- { vendors = { {name, zone}... }, drops = {...}, dropCount, worldDrop,
--   objects = { name... }, quests = { name... } }
function Sources.Get(item)
  if not item then
    return nil
  end
  local result = cache[item]
  if result then
    return result
  end
  result = { vendors = {}, drops = {}, dropCount = 0, objects = {}, quests = {} }
  fromQuestie(item, result)
  fromVisits(item, result)
  cache[item] = result
  return result
end

function Sources.IsVendorSold(item)
  local result = Sources.Get(item)
  return result ~= nil and #result.vendors > 0
end

-- One word for a list row: "Vendor", "Drop", "Quest", ...
function Sources.Kind(item)
  local s = Sources.Get(item)
  if not s then
    return nil
  end
  if #s.vendors > 0 then
    return "Vendor"
  elseif s.worldDrop then
    return "World drop"
  elseif s.dropCount > 0 then
    return "Drop"
  elseif #s.quests > 0 then
    return "Quest"
  elseif #s.objects > 0 then
    return "Container"
  end
end

local function place(entry)
  if entry.zone then
    return string.format("%s |cffa0a0a0(%s)|r", entry.name, entry.zone)
  end
  return entry.name
end

-- Adds "where to get it" lines to a tooltip.
function Sources.AddTooltip(tooltip, item)
  local s = Sources.Get(item)
  tooltip:AddLine(" ")
  tooltip:AddLine("Where to get it", 0.85, 0.7, 0.43)
  local any = false

  for index, vendor in ipairs(s.vendors) do
    if index > SHOW_EACH then
      tooltip:AddLine(string.format("  ...and %d more vendors", #s.vendors - SHOW_EACH), 0.7, 0.7, 0.7)
      break
    end
    tooltip:AddLine("Sold by " .. place(vendor), 1, 1, 1)
    any = true
  end

  if s.worldDrop then
    tooltip:AddLine(string.format("World drop |cffa0a0a0(%d creatures)|r", s.dropCount), 1, 1, 1)
    any = true
  elseif s.dropCount > 0 then
    for _, npc in ipairs(s.drops) do
      tooltip:AddLine("Drops from " .. place(npc), 1, 1, 1)
    end
    if s.dropCount > #s.drops then
      tooltip:AddLine(string.format("  ...and %d more creatures", s.dropCount - #s.drops), 0.7, 0.7, 0.7)
    end
    any = true
  end

  for _, quest in ipairs(s.quests) do
    tooltip:AddLine("Quest reward: " .. quest, 1, 1, 1)
    any = true
  end
  for _, object in ipairs(s.objects) do
    tooltip:AddLine("Found in " .. object, 1, 1, 1)
    any = true
  end

  local auction = ns.Prices.Auction(item)
  if auction then
    tooltip:AddLine("On the auction house for " .. ns.Money(auction), 1, 1, 1)
    any = true
  end

  if not any then
    if Sources.HasQuestie() then
      tooltip:AddLine("Not in Questie's database.", 0.6, 0.6, 0.6, true)
    else
      tooltip:AddLine("Unknown. Install Questie to see vendors and drops, or visit a vendor that sells it.", 0.6, 0.6, 0.6, true)
    end
  end
end

--------------------------------------------------------------------------------
-- Trainers: from Questie's NPCs (trainer flag + a title like "Artisan
-- Alchemist") and from trainers you've visited.
--------------------------------------------------------------------------------

local NPC_FLAG_TRAINER = 16

-- Words in a trainer's title for each profession.
local TRAINER_WORDS = {
  [171] = { "Alchem" }, [164] = { "Blacksmith", "Armorsmith", "Weaponsmith" }, [333] = { "Enchant" },
  [202] = { "Engineer" }, [165] = { "Leatherwork" }, [197] = { "Tailor" }, [185] = { "Cook", "Chef" },
  [129] = { "First Aid", "Surgeon", "Physician" }, [186] = { "Mining", "Miner" }, [182] = { "Herbalis" },
  [393] = { "Skinn" }, [356] = { "Fishing", "Fisherman" },
}

local RANK_ORDER = { Apprentice = 1, Journeyman = 1, Expert = 2, Artisan = 3 }

local trainerCache = {}

local function titleMatches(title, skillLine)
  if type(title) ~= "string" or title:find("Suppl") or title:find("Vendor") then
    return false
  end
  for _, word in ipairs(TRAINER_WORDS[skillLine] or {}) do
    if title:find(word) then
      return true
    end
  end
  return false
end

local function rankOf(title)
  if title:find("Artisan") or title:find("Master") then
    return 3
  elseif title:find("Expert") then
    return 2
  end
  return 1
end

-- All trainers of a profession for your faction: { name, zone, title, rank }.
local function allTrainers(skillLine)
  if trainerCache[skillLine] then
    return trainerCache[skillLine]
  end
  local list, seen = {}, {}
  local lib = questieDB()
  if lib and type(lib.Npc.GetAllIds) == "function" then
    local ok, ids = pcall(lib.Npc.GetAllIds)
    for _, npc in ipairs(ok and ids or {}) do
      local okFlags, flags = pcall(lib.Npc.Get, npc, "npcFlags")
      if okFlags and type(flags) == "number" and bit.band(flags, NPC_FLAG_TRAINER) ~= 0 then
        local _, title = pcall(lib.Npc.Get, npc, "subName")
        if titleMatches(title, skillLine) then
          local info = npcInfo(lib, npc)
          if info and friendlyToMe(info.friendly) and not seen[info.name] then
            seen[info.name] = true
            table.insert(list, { name = info.name, zone = info.zone, title = title, rank = rankOf(title) })
          end
        end
      end
    end
  end
  for name, visit in pairs(ns.db and ns.db.trainers[skillLine] or {}) do
    if not seen[name] then
      seen[name] = true
      table.insert(list, { name = name, zone = visit.zone, title = visit.title, rank = rankOf(visit.title or "") })
    end
  end
  trainerCache[skillLine] = list
  return list
end

-- Trainers who can teach at least `minRank` (1 any, 2 Expert, 3 Artisan),
-- the ones in your current zone first.
function Sources.Trainers(skillLine, minRank)
  local here = GetRealZoneText and GetRealZoneText()
  local result = {}
  for _, trainer in ipairs(allTrainers(skillLine)) do
    if trainer.rank >= (minRank or 1) then
      table.insert(result, trainer)
    end
  end
  table.sort(result, function(a, b)
    local aHere, bHere = a.zone == here, b.zone == here
    if aHere ~= bHere then
      return aHere
    end
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    return (a.zone or "") < (b.zone or "")
  end)
  return result
end

-- The trainer rank a recipe or training step needs.
function Sources.RankForSkill(skill)
  if skill >= 225 then
    return 3
  elseif skill >= 150 then
    return 2
  end
  return 1
end

function Sources.RankNumber(rankName)
  return RANK_ORDER[rankName] or 1
end

function Sources.AddTrainerTooltip(tooltip, skillLine, minRank)
  local trainers = Sources.Trainers(skillLine, minRank)
  tooltip:AddLine(" ")
  tooltip:AddLine("Trainers", 0.85, 0.7, 0.43)
  if #trainers == 0 then
    tooltip:AddLine(Sources.HasQuestie() and "None found in Questie's database." or
      "Install Questie to see trainers here, or visit one and it will be remembered.", 0.6, 0.6, 0.6, true)
    return
  end
  local here = GetRealZoneText and GetRealZoneText()
  for index, trainer in ipairs(trainers) do
    if index > 5 then
      tooltip:AddLine(string.format("  ...and %d more", #trainers - 5), 0.7, 0.7, 0.7)
      break
    end
    local label = place(trainer)
    if trainer.title and trainer.title ~= "" then
      label = label .. " |cff808080<" .. trainer.title .. ">|r"
    end
    tooltip:AddLine(label, trainer.zone == here and 0.4 or 1, 1, trainer.zone == here and 0.4 or 1)
  end
end

local function rememberTrainer()
  if not ns.db or not GetTrainerServiceSkillReq or not GetNumTrainerServices then
    return
  end
  local name = UnitName("npc")
  if not name or GetNumTrainerServices() == 0 then
    return
  end
  local skillName = GetTrainerServiceSkillReq(1)
  for skillLine, professionName in pairs(ns.PROFESSION_NAMES) do
    if professionName == skillName then
      ns.db.trainers[skillLine] = ns.db.trainers[skillLine] or {}
      local title = ""
      if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local data = C_TooltipInfo.GetUnit("npc")
        local line = data and data.lines and data.lines[2]
        title = line and line.leftText or ""
      end
      ns.db.trainers[skillLine][name] = { zone = GetRealZoneText and GetRealZoneText() or "", title = title }
      trainerCache[skillLine] = nil
    end
  end
end

ns.On("TRAINER_SHOW", ns.Debounce(rememberTrainer, 0.3))

--------------------------------------------------------------------------------
-- Remember vendors you visit that sell recipes.
--------------------------------------------------------------------------------

local recipeItems
local function isRecipeItem(item)
  if not recipeItems then
    recipeItems = {}
    for _, rows in pairs(ns.RECIPES) do
      for _, row in ipairs(rows) do
        if row[8] ~= 0 then
          recipeItems[row[8]] = true
        end
      end
    end
  end
  return recipeItems[item]
end

local function rememberVendor()
  if not ns.db or not GetMerchantNumItems or not GetMerchantItemID then
    return
  end
  local vendor = UnitName("npc")
  if not vendor then
    return
  end
  local zone = (GetRealZoneText and GetRealZoneText()) or ""
  local learned = false
  for index = 1, GetMerchantNumItems() do
    local item = GetMerchantItemID(index)
    if item and isRecipeItem(item) then
      ns.db.recipeVendors[item] = ns.db.recipeVendors[item] or {}
      if ns.db.recipeVendors[item][vendor] ~= zone then
        ns.db.recipeVendors[item][vendor] = zone
        cache[item] = nil
        learned = true
      end
    end
  end
  if learned then
    ns.Fire("KNOWN_CHANGED")
  end
end

local queueRemember = ns.Debounce(rememberVendor, 0.5)
ns.On("MERCHANT_SHOW", queueRemember)
ns.On("MERCHANT_UPDATE", queueRemember)
