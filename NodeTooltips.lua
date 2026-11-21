local _, ns = ...

--------------------------------------------------------------------------------
-- Gathering tooltips: the skill a herb, ore node or skinnable creature needs,
-- colored like recipes (red: can't yet, then orange, yellow, green, grey for
-- how likely it is to give a skill-up).
--
-- Herbs and ore come from the gathering guide's data (Gathering.lua), so the
-- two always agree. Fishing pools have no skill of their own (the zone sets
-- it), so they get nothing.
--------------------------------------------------------------------------------

local HERBALISM, MINING, SKINNING = 182, 186, 393

-- Gathering gives a skill-up less often the further you're past a node:
-- orange for 25 points, yellow to 50, green to 100, then grey.
local SKILL_UP_COLORS = {
  { below = 25, color = "orange" },
  { below = 50, color = "yellow" },
  { below = 100, color = "green" },
}

-- Ore nodes whose skill isn't their ore's: "Rich Thorium Vein" needs more
-- than "Small Thorium Vein", and "Dark Iron Deposit" isn't iron.
local NODE_OVERRIDES = {
  ["Rich Thorium Vein"] = 275,
  ["Ooze Covered Rich Thorium Vein"] = 275,
  ["Hakkari Thorium Vein"] = 275,
  ["Dark Iron Deposit"] = 230,
}

-- [skill line] = { [node name] = skill }, and for ore { word, skill } pairs
-- ("Copper" for Copper Ore) matched against vein and deposit names. Built from
-- item names, which load as the client sees them, so it's rebuilt until all
-- are known.
local nodeSkills = {}
local oreWords
local complete = {}

local function buildTables()
  for _, skillLine in ipairs({ HERBALISM, MINING }) do
    if not complete[skillLine] then
      local guide = ns.GATHERING[skillLine]
      local names, words, allKnown = {}, {}, true
      for _, bracket in ipairs(guide and guide.brackets or {}) do
        for _, entry in ipairs(bracket.items) do
          local item, need = entry[1], entry[2]
          local name = ns.ItemName(item)
          if not name then
            ns.RequestItem(item)
            allKnown = false
          elseif skillLine == HERBALISM then
            names[name] = names[name] or need
          elseif name:find(" Ore$") then
            table.insert(words, { word = name:gsub(" Ore$", ""), need = need })
          end
        end
      end
      nodeSkills[skillLine] = names
      if skillLine == MINING then
        oreWords = words
      end
      complete[skillLine] = allKnown
    end
  end
end

-- The skill a gathering node needs, or nil when we don't know it.
local function nodeSkill(skillLine, nodeName)
  buildTables()
  if skillLine == HERBALISM then
    return nodeSkills[HERBALISM][nodeName]
  end
  if skillLine == MINING then
    if NODE_OVERRIDES[nodeName] then
      return NODE_OVERRIDES[nodeName]
    end
    if nodeName:find("Vein") or nodeName:find("Deposit") then
      local best
      for _, ore in ipairs(oreWords or {}) do
        -- The longest matching word wins ("Truesilver" over "Silver").
        if nodeName:find(ore.word, 1, true) and (not best or #ore.word > #best.word) then
          best = ore
        end
      end
      return best and best.need
    end
  end
end

-- Skinning: level x 5 up to level 20, then (level - 10) x 10.
local function skinningSkill(level)
  if not level or level < 1 then
    return nil
  end
  if level <= 20 then
    return math.max(1, level * 5)
  end
  return (level - 10) * 10
end

-- "Herbalism 185 (you: 120)", colored for your skill when you have the profession.
local function requirementLine(skillLine, need)
  local name = ns.PROFESSION_NAMES[skillLine] or ""
  local skill = ns.GetProfessionSkill(skillLine)
  local text = string.format("%s %d", name, need)
  if not skill then
    return "|cffa0a0a0" .. text .. "|r"
  end
  local colorName = "grey"
  if skill < need then
    return string.format("|cffff4040%s|r |cffa0a0a0(you: %d)|r", text, skill)
  end
  for _, band in ipairs(SKILL_UP_COLORS) do
    if skill < need + band.below then
      colorName = band.color
      break
    end
  end
  return ns.DIFFICULTY_COLORS[colorName]:WrapTextInColorCode(text) .. string.format(" |cffa0a0a0(you: %d)|r", skill)
end

--------------------------------------------------------------------------------
-- Hooking the tooltip
--------------------------------------------------------------------------------

local added = false

-- Whether we may look at a value. The client marks some tooltip text as
-- secret (in combat, for some units); comparing it is an error.
local function readable(value)
  -- The secret check comes first: even comparing a secret to nil is an error.
  if issecretvalue and issecretvalue(value) then
    return false
  end
  if canaccessvalue and not canaccessvalue(value) then
    return false
  end
  return type(value) ~= "nil"
end

-- Whether the tooltip is about a unit (a creature or player), safely.
local function isUnitTooltip(tooltip)
  local name, unit = tooltip:GetUnit()
  return type(name) ~= "nil" or type(unit) ~= "nil"
end

-- A tooltip line's text, or nil when there's none or it's secret.
local function lineText(index)
  local line = _G["GameTooltipTextLeft" .. index]
  local text = line and line:GetText()
  return readable(text) and text or nil
end

-- World objects (herbs, ore): line 1 is the node, line 2 the profession.
local function addNodeLine(tooltip)
  if isUnitTooltip(tooltip) or (tooltip.GetItem and type((tooltip:GetItem())) ~= "nil") then
    return
  end
  local nodeName, profession = lineText(1), lineText(2)
  local skillLine = profession and ns.SkillLineByName(profession)
  if not nodeName or (skillLine ~= HERBALISM and skillLine ~= MINING) then
    return
  end
  local need = nodeSkill(skillLine, nodeName)
  if need then
    -- On the profession line itself: "Herbalism" becomes "Herbalism 185 (you: 120)".
    added = true
    _G.GameTooltipTextLeft2:SetText(requirementLine(skillLine, need))
    tooltip:Show()
  end
end

-- Creatures you can skin show "Skinnable" in their tooltip.
local function isSkinnable(tooltip)
  local marker = UNIT_SKINNABLE_LEATHER or "Skinnable"
  for index = 2, tooltip:NumLines() do
    if lineText(index) == marker then
      return true
    end
  end
  return false
end

local function addSkinningLine(tooltip)
  local _, unit = tooltip:GetUnit()
  if not readable(unit) or UnitIsPlayer(unit) or not isSkinnable(tooltip) then
    return
  end
  local level = UnitLevel(unit)
  if not readable(level) then
    return
  end
  local need = skinningSkill(level)
  if need then
    added = true
    tooltip:AddLine(requirementLine(SKINNING, need))
    tooltip:Show()
  end
end

local function onShow(tooltip)
  if added then
    return
  end
  ns.SafeCall("gathering tooltip", function()
    if isUnitTooltip(tooltip) then
      addSkinningLine(tooltip)
    else
      addNodeLine(tooltip)
    end
  end)
end

GameTooltip:HookScript("OnShow", onShow)
GameTooltip:HookScript("OnTooltipCleared", function() added = false end)
-- On the modern client, tooltips can be filled after OnShow: add the line
-- there too (whichever comes first wins).
local types = TooltipDataProcessor and Enum and Enum.TooltipDataType
if types then
  if types.Unit then
    TooltipDataProcessor.AddTooltipPostCall(types.Unit, function(tooltip)
      if tooltip == GameTooltip and not added then
        ns.SafeCall("gathering tooltip", addSkinningLine, tooltip)
      end
    end)
  end
  if types.Object then
    TooltipDataProcessor.AddTooltipPostCall(types.Object, function(tooltip)
      if tooltip == GameTooltip and not added then
        ns.SafeCall("gathering tooltip", addNodeLine, tooltip)
      end
    end)
  end
end
