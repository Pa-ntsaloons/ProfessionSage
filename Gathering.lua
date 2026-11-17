local _, ns = ...

--------------------------------------------------------------------------------
-- Gathering guide: where to go at each skill and what you'll find there.
--
-- Written for this addon from the classic leveling brackets, which WoW Forever
-- kept for gathering. Every item ID and zone name was checked against the
-- client's own data (build 1.60.1.70938).
--
-- zones: { name, faction }  faction "A" = Alliance, "H" = Horde, nil = both
-- items: { item, skill needed } (for Skinning the skill depends on the beast)
--------------------------------------------------------------------------------

local A, H = "A", "H"

ns.GATHERING = {
  [182] = {
    noun = "Herbs",
    brackets = {
      { from = 1, to = 70,
        zones = { { "Elwynn Forest", A }, { "Dun Morogh", A }, { "Teldrassil", A },
                  { "Durotar", H }, { "Mulgore", H }, { "Tirisfal Glades", H } },
        items = { { 2447, 1 }, { 765, 1 }, { 2449, 15 } } },
      { from = 70, to = 115,
        zones = { { "Westfall", A }, { "Loch Modan", A }, { "Darkshore", A }, { "Redridge Mountains", A },
                  { "The Barrens", H }, { "Silverpine Forest", H } },
        items = { { 785, 50 }, { 2450, 70 }, { 3820, 85 }, { 2453, 100 } } },
      { from = 115, to = 170,
        zones = { { "Wetlands", A }, { "Duskwood", A }, { "Stonetalon Mountains", H }, { "Ashenvale", H },
                  { "Hillsbrad Foothills" }, { "Desolace" } },
        items = { { 3355, 115 }, { 3369, 120 }, { 3356, 125 }, { 3357, 150 } } },
      { from = 170, to = 205,
        zones = { { "Arathi Highlands" }, { "Stranglethorn Vale" }, { "Swamp of Sorrows" },
                  { "Dustwallow Marsh" }, { "Alterac Mountains" } },
        items = { { 3818, 160 }, { 3821, 170 }, { 3358, 185 }, { 3819, 195 } } },
      { from = 205, to = 230,
        zones = { { "Tanaris" }, { "Feralas" }, { "The Hinterlands" }, { "Searing Gorge" }, { "Azshara" } },
        items = { { 4625, 205 }, { 8831, 210 }, { 8836, 220 } } },
      { from = 230, to = 270,
        zones = { { "Felwood" }, { "Un'Goro Crater" }, { "Azshara" }, { "Feralas" },
                  { "The Hinterlands" }, { "Blasted Lands" } },
        items = { { 8838, 230 }, { 8839, 235 }, { 8845, 245 }, { 8846, 250 }, { 13464, 260 } } },
      { from = 270, to = 300,
        zones = { { "Un'Goro Crater" }, { "Eastern Plaguelands" }, { "Western Plaguelands" },
                  { "Winterspring" }, { "Silithus" }, { "Felwood" }, { "Burning Steppes" } },
        items = { { 13463, 270 }, { 13465, 280 }, { 13466, 285 }, { 13467, 290 }, { 13468, 300 } } },
    },
  },

  [186] = {
    noun = "Ore",
    brackets = {
      { from = 1, to = 65,
        zones = { { "Elwynn Forest", A }, { "Dun Morogh", A }, { "Darkshore", A },
                  { "Durotar", H }, { "Mulgore", H }, { "Tirisfal Glades", H } },
        items = { { 2770, 1 }, { 2835, 1 } } },
      { from = 65, to = 125,
        zones = { { "Westfall", A }, { "Redridge Mountains", A }, { "Loch Modan", A },
                  { "The Barrens", H }, { "Silverpine Forest", H }, { "Stonetalon Mountains", H },
                  { "Hillsbrad Foothills" } },
        items = { { 2771, 65 }, { 2836, 65 }, { 2775, 75 } } },
      { from = 125, to = 175,
        zones = { { "Arathi Highlands" }, { "Desolace" }, { "Thousand Needles" },
                  { "Stranglethorn Vale" }, { "Alterac Mountains" }, { "Badlands" } },
        items = { { 2772, 125 }, { 2838, 125 }, { 2776, 155 } } },
      { from = 175, to = 245,
        zones = { { "Badlands" }, { "Searing Gorge" }, { "Tanaris" }, { "The Hinterlands" },
                  { "Felwood" }, { "Azshara" } },
        items = { { 3858, 175 }, { 7912, 175 }, { 7911, 230 }, { 11370, 230 } } },
      { from = 245, to = 300,
        zones = { { "Un'Goro Crater" }, { "Burning Steppes" }, { "Western Plaguelands" },
                  { "Eastern Plaguelands" }, { "Winterspring" }, { "Silithus" }, { "Azshara" } },
        items = { { 10620, 245 }, { 12365, 245 } } },
    },
    note = "Rich Thorium Veins need 275. Dark Iron Ore is only in Searing Gorge, Burning Steppes and Blackrock Depths.",
  },

  [393] = {
    noun = "Leather",
    brackets = {
      { from = 1, to = 75,
        zones = { { "Elwynn Forest", A }, { "Dun Morogh", A }, { "Teldrassil", A }, { "Westfall", A },
                  { "Durotar", H }, { "Mulgore", H }, { "Tirisfal Glades", H }, { "The Barrens", H } },
        items = { { 2934, 1 }, { 2318, 1 }, { 783, 1 } } },
      { from = 75, to = 150,
        zones = { { "Loch Modan", A }, { "Redridge Mountains", A }, { "Darkshore", A }, { "Wetlands", A },
                  { "The Barrens", H }, { "Stonetalon Mountains", H }, { "Silverpine Forest", H },
                  { "Hillsbrad Foothills" } },
        items = { { 2318, 75 }, { 2319, 100 }, { 4232, 100 } } },
      { from = 150, to = 200,
        zones = { { "Arathi Highlands" }, { "Thousand Needles" }, { "Stranglethorn Vale" },
                  { "Desolace" }, { "Duskwood", A }, { "Ashenvale", H } },
        items = { { 2319, 150 }, { 4234, 150 }, { 4235, 175 } } },
      { from = 200, to = 250,
        zones = { { "Stranglethorn Vale" }, { "Badlands" }, { "Dustwallow Marsh" },
                  { "Swamp of Sorrows" }, { "Desolace" } },
        items = { { 4234, 200 }, { 4304, 225 } } },
      { from = 250, to = 300,
        zones = { { "Tanaris" }, { "Feralas" }, { "The Hinterlands" }, { "Un'Goro Crater" },
                  { "Felwood" }, { "Winterspring" }, { "Burning Steppes" } },
        items = { { 4304, 250 }, { 8169, 250 }, { 8170, 275 }, { 8171, 275 } } },
    },
    note = "Skill needed depends on the beast: level x 5 up to level 20, then (level - 10) x 10. At 300 you can skin up to level 40, plus higher beasts as your skill allows.",
  },

  [356] = {
    noun = "Fish",
    brackets = {
      { from = 1, to = 75,
        zones = { { "Elwynn Forest", A }, { "Dun Morogh", A }, { "Teldrassil", A }, { "Westfall", A },
                  { "Durotar", H }, { "Mulgore", H }, { "Tirisfal Glades", H } },
        items = { { 6291, 1 }, { 6303, 1 }, { 6289, 1 }, { 6361, 1 } } },
      { from = 75, to = 150,
        zones = { { "Loch Modan", A }, { "Westfall", A }, { "Darkshore", A }, { "Redridge Mountains", A },
                  { "Wetlands", A }, { "The Barrens", H }, { "Silverpine Forest", H }, { "Hillsbrad Foothills" } },
        items = { { 6308, 75 }, { 6317, 75 }, { 6358, 75 }, { 6359, 75 }, { 6522, 75 } } },
      { from = 150, to = 225,
        zones = { { "Stranglethorn Vale" }, { "Arathi Highlands" }, { "Desolace" },
                  { "Dustwallow Marsh" }, { "Swamp of Sorrows" }, { "Thousand Needles" } },
        items = { { 8365, 150 }, { 6362, 150 }, { 4603, 150 }, { 21071, 150 } } },
      { from = 225, to = 300,
        zones = { { "Tanaris" }, { "Feralas" }, { "Azshara" }, { "The Hinterlands" }, { "Un'Goro Crater" },
                  { "Winterspring" }, { "Western Plaguelands" }, { "Eastern Plaguelands" }, { "Silithus" } },
        items = { { 13759, 225 }, { 13760, 225 }, { 13889, 225 }, { 13758, 225 }, { 13422, 225 },
                  { 13893, 225 }, { 13756, 225 }, { 13754, 225 }, { 13888, 225 } } },
    },
    note = "Expert Fishing (to 225) is a book from Old Man Heming in Booty Bay; Artisan (to 300) is a quest from Nat Pagle in Dustwallow Marsh.",
  },
}

--------------------------------------------------------------------------------
-- Nodes you've found, from GatherMate2 (read at runtime when it's installed).
--------------------------------------------------------------------------------

local GATHERMATE_TYPES = { [182] = "Herb Gathering", [186] = "Mining", [356] = "Fishing" }
local GATHERMATE_DBS = { [182] = "GatherMate2HerbDB", [186] = "GatherMate2MineDB", [356] = "GatherMate2FishDB" }

local function gatherMate()
  local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
  return AceAddon and AceAddon:GetAddon("GatherMate2", true)
end

function ns.HasGatherMate()
  return gatherMate() ~= nil
end

-- What part of a node's name points at an item: "Peacebloom" for herbs,
-- "Copper" for Copper Ore (Copper Vein), "Oily Blackmouth" for the fish.
local function itemKeyword(skillLine, item)
  local name = ns.ItemName(item)
  if not name then
    return nil
  end
  if skillLine == 186 then
    if not name:find(" Ore$") then
      return nil  -- stones come from every vein
    end
    return (name:gsub(" Ore$", ""))
  elseif skillLine == 356 then
    return (name:gsub("^Raw ", ""):gsub("^Large ", ""))
  end
  return name
end

-- [zone name] = { [node name] = count } for one profession.
local function nodeCounts(skillLine)
  local gm, db = gatherMate(), _G[GATHERMATE_DBS[skillLine] or ""]
  if not gm or type(db) ~= "table" or not gm.GetNameForNode then
    return nil
  end
  local nodeType = GATHERMATE_TYPES[skillLine]
  local counts = {}
  for mapID, nodes in pairs(db) do
    local info = type(mapID) == "number" and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    if info and info.name and type(nodes) == "table" then
      local zone = counts[info.name] or {}
      counts[info.name] = zone
      for _, nodeID in pairs(nodes) do
        local ok, name = pcall(gm.GetNameForNode, gm, nodeType, nodeID)
        if ok and name then
          zone[name] = (zone[name] or 0) + 1
        end
      end
    end
  end
  return counts
end

-- Nodes in a zone that give any of these items.
local function matchingNodes(zoneCounts, skillLine, items)
  if not zoneCounts then
    return 0
  end
  local total = 0
  for nodeName, count in pairs(zoneCounts) do
    for _, entry in ipairs(items) do
      local keyword = itemKeyword(skillLine, entry[1])
      if keyword and nodeName:find(keyword, 1, true) then
        total = total + count
        break
      end
    end
  end
  return total
end

--------------------------------------------------------------------------------

local playerFaction

-- The brackets from your skill onward, with zones for your faction.
-- Zones with the most nodes you've found (GatherMate2) come first; items you
-- can gather now come first, most valuable at the top.
-- Returns list of { from, to, zones = { { name, nodes } }, items, current }, guide, hasCounts.
function ns.GatheringGuide(skillLine, skill)
  local guide = ns.GATHERING[skillLine]
  if not guide then
    return nil
  end
  playerFaction = playerFaction or (UnitFactionGroup("player") == "Horde" and H or A)
  local counts = nodeCounts(skillLine)
  local anyCounts = false

  local result = {}
  for _, bracket in ipairs(guide.brackets) do
    if bracket.to > skill or bracket.to == 300 then
      local zones = {}
      for index, zone in ipairs(bracket.zones) do
        if zone[2] == nil or zone[2] == playerFaction then
          local nodes = matchingNodes(counts and counts[zone[1]], skillLine, bracket.items)
          anyCounts = anyCounts or nodes > 0
          table.insert(zones, { name = zone[1], nodes = nodes, order = index })
        end
      end
      table.sort(zones, function(a, b)
        if a.nodes ~= b.nodes then
          return a.nodes > b.nodes
        end
        return a.order < b.order
      end)

      local items = {}
      for _, entry in ipairs(bracket.items) do
        table.insert(items, { item = entry[1], need = entry[2], value = ns.Prices.Sell(entry[1]) or 0 })
      end
      table.sort(items, function(a, b)
        local aReady, bReady = a.need <= skill, b.need <= skill
        if aReady ~= bReady then
          return aReady
        end
        if aReady and a.value ~= b.value then
          return a.value > b.value
        end
        return a.need < b.need
      end)

      table.insert(result, {
        from = bracket.from, to = bracket.to, zones = zones, items = items,
        current = skill >= bracket.from and skill < bracket.to,
      })
    end
  end
  return result, guide, anyCounts
end
