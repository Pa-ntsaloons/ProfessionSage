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

local function friendlyToMe(friendly)
  -- Questie: "A", "H", "AH" (or nil when anyone can use them).
  if type(friendly) ~= "string" or friendly == "" or friendly == "AH" then
    return true
  end
  local faction = ns.PlayerFaction()
  return (friendly == "A" and faction == "Alliance") or (friendly == "H" and faction == "Horde")
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
  ns.TooltipHeading(tooltip, "Where to get it")
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
local ALL_RANKS  -- set below

-- Words in a trainer's title for each profession.
local TRAINER_WORDS = {
  [171] = { "Alchem" }, [164] = { "Blacksmith", "Armorsmith", "Weaponsmith" }, [333] = { "Enchant" },
  [202] = { "Engineer" }, [165] = { "Leatherwork" }, [197] = { "Tailor" }, [185] = { "Cook", "Chef" },
  [129] = { "First Aid", "Surgeon", "Physician" }, [186] = { "Mining", "Miner" }, [182] = { "Herbalis" },
  [393] = { "Skinn" }, [356] = { "Fishing", "Fisherman" },
}

-- Rank names to numbers (Apprentice counts as the first, like Journeyman).
local RANK_ORDER = { Apprentice = 1 }
for _, step in ipairs(ns.RANK_STEPS) do
  RANK_ORDER[step.name] = step.rank
end

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

-- A trainer's title names one rank above the highest they teach:
-- "Journeyman X" teaches Apprentice (0), "Expert X" up to Journeyman (1),
-- "Artisan X" up to Expert (2), "Master X" up to Artisan (3).
local function rankOf(title)
  if title:find("Master") then
    return 3
  elseif title:find("Artisan") then
    return 2
  elseif title:find("Journeyman") then
    return 0
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
  local curated = Sources.RankTrainers(skillLine, minRank)
  if curated then
    return curated
  end
  local here = GetRealZoneText and GetRealZoneText()
  local result = {}
  local anyRank = ALL_RANKS[skillLine]
  for _, trainer in ipairs(allTrainers(skillLine)) do
    if anyRank or trainer.rank >= (minRank or 1) then
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

-- The trainer rank a recipe or training step needs (0 Apprentice ... 3 Artisan).
function Sources.RankForSkill(skill)
  local rank = 0
  for _, step in ipairs(ns.RANK_STEPS) do
    if skill >= step.at then
      rank = step.rank
    end
  end
  return rank
end

function Sources.RankNumber(rankName)
  return RANK_ORDER[rankName] or 1
end

--------------------------------------------------------------------------------
-- Who teaches each rank. Questie's titles are a guide for Apprentice and
-- Journeyman, but Expert and Artisan are only taught by a few NPCs, listed
-- here (WoW Forever, checked against warcrafttavern.com and
-- wow-professions.com). Positions are uiMapID and x, y in percent, for
-- waypoints; no map means no fixed spot.
--------------------------------------------------------------------------------

local STORMWIND, ORGRIMMAR, IRONFORGE, THUNDER_BLUFF, DARNASSUS, UNDERCITY = 1453, 1454, 1455, 1456, 1457, 1458
local ELWYNN, STONETALON, FERALAS, SWAMP, STRANGLETHORN, TANARIS = 1429, 1442, 1444, 1435, 1434, 1446
local HINTERLANDS, DUSTWALLOW, HILLSBRAD, ARATHI, ASHENVALE, DESOLACE = 1425, 1445, 1424, 1417, 1440, 1443

-- Mining, Herbalism and Skinning trainers teach every rank.
ALL_RANKS = { [186] = true, [182] = true, [393] = true }

local function npc(name, placeText, faction, map, x, y)
  return { name = name, place = placeText, faction = faction, map = map, x = x, y = y }
end

-- [skill line][rank] = list of trainers (faction nil = both).
local RANK_TRAINERS = {
  [171] = { -- Alchemy
    [2] = { npc("Ainethil", "Craftsmen's Terrace, Darnassus", "Alliance", DARNASSUS, 55.5, 23.1),
            npc("Doctor Herbert Halsey", "The Apothecarium, Undercity", "Horde", UNDERCITY, 48.3, 72.3) },
    [3] = { npc("Kylanna Windwhisper", "Feathermoon Stronghold, Feralas", "Alliance", FERALAS, 32.6, 43.7),
            npc("Rogvar", "Stonard, Swamp of Sorrows", "Horde", SWAMP, 48.3, 55.5) },
  },
  [164] = { -- Blacksmithing
    [2] = { npc("Bengus Deepforge", "The Great Forge, Ironforge", "Alliance", IRONFORGE, 51.6, 42.4),
            npc("Saru Steelfury", "Valley of Honor, Orgrimmar", "Horde", ORGRIMMAR, 82.4, 23.5) },
    [3] = { npc("Brikk Keencraft", "Booty Bay, Stranglethorn Vale", nil, STRANGLETHORN, 29.0, 75.5) },
  },
  [333] = { -- Enchanting
    [2] = { npc("Kitta Firewind", "Tower of Azora, Elwynn Forest", "Alliance", ELWYNN, 64.9, 70.7),
            npc("Hgarth", "Sun Rock Retreat, Stonetalon Mountains", "Horde", STONETALON, 49.2, 57.2) },
    [3] = { npc("Annora", "inside Uldaman, Badlands", nil) },
  },
  [202] = { -- Engineering
    [2] = { npc("Springspindle Fizzlegear", "Tinker Town, Ironforge", "Alliance", IRONFORGE, 68.8, 45.2),
            npc("Roxxik", "Valley of Honor, Orgrimmar", "Horde", ORGRIMMAR, 76.0, 25.0) },
    [3] = { npc("Buzzek Bracketswing", "Gadgetzan, Tanaris", nil, TANARIS, 52.2, 27.6) },
  },
  [165] = { -- Leatherworking
    [2] = { npc("Telonis", "Craftsmen's Terrace, Darnassus", "Alliance", DARNASSUS, 64.6, 21.5),
            npc("Una", "Middle Rise, Thunder Bluff", "Horde", THUNDER_BLUFF, 41.7, 42.7) },
    [3] = { npc("Drakk Stonehand", "Aerie Peak, The Hinterlands", "Alliance", HINTERLANDS, 13.4, 43.4),
            npc("Hahrana Ironhide", "Camp Mojache, Feralas", "Horde", FERALAS, 74.4, 43.1) },
  },
  [197] = { -- Tailoring
    [2] = { npc("Georgio Bolero", "Mage Quarter, Stormwind", "Alliance", STORMWIND, 53.3, 81.7),
            npc("Josef Gregorian", "Magic Quarter, Undercity", "Horde", UNDERCITY, 70.8, 30.6) },
    [3] = { npc("Timothy Worthington", "Theramore Isle, Dustwallow Marsh", "Alliance", DUSTWALLOW, 66.2, 51.6),
            npc("Daryl Stack", "Tarren Mill, Hillsbrad Foothills", "Horde", HILLSBRAD, 63.6, 20.8) },
  },
}

-- First Aid and Cooking don't train Expert and Artisan: Expert is a book you
-- buy and read, Artisan is a quest. `at` is who to visit, by faction or `any`.
local SPECIAL_RANKS = {
  [129] = {
    [2] = { book = 16084, name = "Expert First Aid - Under Wraps", needs = 125, cost = 10000, at = {
      Alliance = npc("Deneb Walker", "Stromgarde Keep, Arathi Highlands", nil, ARATHI, 27.0, 58.8),
      Horde = npc("Balai Lok'Wein", "Brackenwall Village, Dustwallow Marsh", nil, DUSTWALLOW, 36.5, 30.5) } },
    [3] = { quest = "Triage", needs = 225, level = 35, at = {
      Alliance = npc("Doctor Gustaf VanHowzen", "Theramore Isle, Dustwallow Marsh", nil, DUSTWALLOW, 67.5, 48.8),
      Horde = npc("Doctor Gregory Victor", "Hammerfall, Arathi Highlands", nil, ARATHI, 73.5, 36.9) },
      note = "Bandage the wounded soldiers in the doctor's triage area before they die." },
  },
  [185] = {
    [2] = { book = 16072, name = "Expert Cookbook", needs = 125, cost = 10000, at = {
      Alliance = npc("Shandrina", "Silverwind Refuge, Ashenvale", nil, ASHENVALE, 49.5, 67.0),
      Horde = npc("Wulan", "Shadowprey Village, Desolace", nil, DESOLACE, 26.1, 69.7) } },
    [3] = { quest = "Clamlette Surprise", needs = 225, level = 35, at = {
      any = npc("Dirge Quikcleave", "Gadgetzan, Tanaris", nil, TANARIS, 52.6, 27.9) },
      note = "Bring 12 Giant Egg, 10 Zesty Clam Meat and 20 Alterac Swiss." },
  },
  [356] = {
    [2] = { book = 16083, name = "Expert Fishing - The Bass and You", needs = 125, level = 20, cost = 10000, at = {
      any = npc("Old Man Heming", "Booty Bay, Stranglethorn Vale", nil, STRANGLETHORN, 27.6, 77.4) } },
    [3] = { quest = "Nat Pagle, Angler Extreme", needs = 225, at = {
      any = npc("Nat Pagle", "Dustwallow Marsh", nil, DUSTWALLOW, 58.4, 60.0) },
      note = "Nat Pagle asks for rare fish caught around Azeroth." },
  },
}

-- What a trainer rank needs: skill, character level, cost in copper.
local RANK_NEEDS = {
  [1] = { skill = 50, level = 10, cost = 500 },
  [2] = { skill = 125, level = 20, cost = 5000 },
  [3] = { skill = 200, level = 35, cost = 50000 },
}

-- The listed Expert/Artisan trainers for your faction, or nil when this rank
-- isn't in the list (Questie's trainers are used then).
function Sources.RankTrainers(skillLine, rank)
  local list = RANK_TRAINERS[skillLine] and RANK_TRAINERS[skillLine][rank]
  if not list then
    return nil
  end
  local result = {}
  for _, entry in ipairs(list) do
    if not entry.faction or entry.faction == ns.PlayerFaction() then
      table.insert(result, { name = entry.name, zone = entry.place, spot = entry })
    end
  end
  return result
end

-- How to reach a rank (2 Expert, 3 Artisan) when it isn't a trainer, or nil.
function Sources.SpecialRank(skillLine, rank)
  local ranks = SPECIAL_RANKS[skillLine]
  return ranks and ranks[rank]
end

-- Who to visit for it, for your faction.
function Sources.SpecialRankNPC(special)
  return special.at[ns.PlayerFaction()] or special.at.any
end

-- Where a waypoint for learning this rank should go, or nil.
function Sources.RankSpot(skillLine, rank)
  local special = Sources.SpecialRank(skillLine, rank)
  if special then
    local spot = Sources.SpecialRankNPC(special)
    return spot and spot.map and spot or nil
  end
  for _, trainer in ipairs(Sources.RankTrainers(skillLine, rank) or {}) do
    if trainer.spot.map then
      return trainer.spot
    end
  end
end

-- Puts a waypoint on someone: the map pin (and TomTom's arrow when installed).
-- Returns true when one was set.
function Sources.SetWaypoint(spot)
  if not spot or not spot.map then
    return false
  end
  local x, y = spot.x / 100, spot.y / 100
  local set = false
  if TomTom and type(TomTom.AddWaypoint) == "function" then
    set = pcall(TomTom.AddWaypoint, TomTom, spot.map, x, y, { title = spot.name, from = ns.TITLE, persistent = false }) or set
  end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates
    and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(spot.map)) then
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(spot.map, x, y))
    if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
      pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    set = ok or set
  end
  if set then
    ns.Print(string.format("Waypoint set: %s, %s (%.1f, %.1f).", spot.name, spot.place, spot.x, spot.y))
  end
  return set
end

local function addSpecialRankLines(tooltip, special)
  local where = Sources.SpecialRankNPC(special)
  local whereText = where and string.format("%s |cffa0a0a0(%s)|r", where.name, where.place)
  local levelText = special.level and string.format(" and character level %d", special.level) or ""
  if special.book then
    tooltip:AddLine(string.format("Buy and read the book %s (%s, readable from skill %d%s). It isn't taught by trainers.",
      special.name, ns.Money(special.cost), special.needs, levelText), 1, 1, 1, true)
    ns.TooltipHeading(tooltip, "Where to get it")
    if whereText then
      tooltip:AddLine("Sold by " .. whereText, 1, 1, 1, true)
    end
    local auction = ns.Prices.Auction(special.book)
    if auction then
      tooltip:AddLine("On the auction house for " .. ns.Money(auction), 1, 1, 1)
    end
  else
    tooltip:AddLine(string.format("Complete the quest \"%s\" (needs skill %d%s). It isn't taught by trainers.",
      special.quest, special.needs, levelText), 1, 1, 1, true)
    if whereText then
      ns.TooltipHeading(tooltip, "Quest from")
      tooltip:AddLine(whereText, 1, 1, 1, true)
    end
    if special.note then
      tooltip:AddLine(special.note, 0.8, 0.8, 0.8, true)
    end
  end
end

-- Tooltip for a "learn the next rank" step: rank 1 Journeyman, 2 Expert,
-- 3 Artisan; `at` is the skill the route stops at.
function Sources.AddRankTooltip(tooltip, skillLine, rank, rankName, at)
  tooltip:SetText(string.format("%s %s", rankName, ns.PROFESSION_NAMES[skillLine] or ""))
  Sources.AddRankLines(tooltip, skillLine, rank, rankName, at)
end

-- The body of a rank tooltip (what it takes and where), for any tooltip.
function Sources.AddRankLines(tooltip, skillLine, rank, rankName, at)
  tooltip:AddLine(string.format("Your skill stops at %d until you learn %s.", at, rankName), 1, 1, 1, true)
  local special = Sources.SpecialRank(skillLine, rank)
  if special then
    addSpecialRankLines(tooltip, special)
  else
    local needs = RANK_NEEDS[rank]
    if needs then
      local level = (needs.level and not ALL_RANKS[skillLine] and not SPECIAL_RANKS[skillLine]) and string.format(", character level %d", needs.level) or ""
      tooltip:AddLine(string.format("Needs skill %d%s. Costs %s.", needs.skill, level, ns.Money(needs.cost)),
        0.8, 0.8, 0.8, true)
    end
    Sources.AddTrainerTooltip(tooltip, skillLine, rank)
  end
  local spot = Sources.RankSpot(skillLine, rank)
  if spot then
    tooltip:AddLine(" ")
    tooltip:AddLine(string.format("Click to set a waypoint to %s.", spot.name), 0.4, 0.8, 1, true)
  end
end

function Sources.AddTrainerTooltip(tooltip, skillLine, minRank)
  local trainers = Sources.Trainers(skillLine, minRank)
  ns.TooltipHeading(tooltip, "Trainers")
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
  local skillLine = ns.SkillLineByName(GetTrainerServiceSkillReq(1))
  if not skillLine then
    return
  end
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

ns.On("TRAINER_SHOW", ns.Debounce(rememberTrainer, 0.3))

--------------------------------------------------------------------------------
-- Remember vendors you visit that sell recipes.
--------------------------------------------------------------------------------

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
    if item and ns.Recipes.IsRecipeItem(item) then
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
