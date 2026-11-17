local _, ns = ...

local Recipes = {}
ns.Recipes = Recipes

--------------------------------------------------------------------------------
-- Recipe data (Data.lua), unpacked on first use
--------------------------------------------------------------------------------

local byProfession = {}
local bySpell = {}

local function playerRaceBit()
  local raceID = select(3, UnitRace("player"))
  return raceID and 2 ^ (raceID - 1) or 0
end

local function parseReagents(text)
  local reagents = {}
  for item, count in text:gmatch("(%d+):(%d+)") do
    table.insert(reagents, { item = tonumber(item), count = tonumber(count) })
  end
  return reagents
end

-- Recipes of one profession this character's race can learn, lowest first.
function Recipes.For(skillLine)
  local list = byProfession[skillLine]
  if list then
    return list
  end
  list = {}
  local raceBit = playerRaceBit()
  for _, row in ipairs(ns.RECIPES[skillLine] or {}) do
    local spell, learn, yellow, grey, item, count, mats, source, race, ups, exact, recipeCost = unpack(row)
    if race == 0 or raceBit == 0 or bit.band(race, raceBit) ~= 0 then
      local fromTrainer = ns.db and ns.db.learnAt[spell]
      local recipe = {
        spell = spell,
        skillLine = skillLine,
        learn = fromTrainer or learn,
        learnExact = fromTrainer ~= nil or exact == 1,
        yellow = yellow,
        green = math.floor((yellow + grey) / 2),
        grey = grey,
        item = item ~= 0 and item or nil,
        count = count > 0 and count or 1,
        reagents = parseReagents(mats),
        recipeItem = source ~= 0 and source or nil,
        recipeVendorPrice = recipeCost and recipeCost > 0 and recipeCost or nil,
        skillUps = ups or 1,
      }
      table.insert(list, recipe)
      bySpell[spell] = recipe
    end
  end
  byProfession[skillLine] = list
  return list
end

function Recipes.Get(spell)
  if not bySpell[spell] then
    for skillLine in pairs(ns.RECIPES) do
      if not byProfession[skillLine] then
        Recipes.For(skillLine)
        if bySpell[spell] then
          break
        end
      end
    end
  end
  return bySpell[spell]
end

function Recipes.Name(recipe)
  local name = ns.GetSpellName(recipe.spell)
  if name and name ~= "" then
    return name
  end
  return recipe.item and ns.ItemName(recipe.item) or ("Recipe " .. recipe.spell)
end

function Recipes.Icon(recipe)
  if recipe.item then
    return ns.GetItemIcon(recipe.item)
  end
  return ns.GetSpellIcon(recipe.spell)
end

--------------------------------------------------------------------------------
-- Skill-ups
--------------------------------------------------------------------------------

ns.DIFFICULTY_COLORS = {
  orange = CreateColor(1, 0.5, 0.25),
  yellow = CreateColor(1, 1, 0),
  green = CreateColor(0.25, 0.75, 0.25),
  grey = CreateColor(0.5, 0.5, 0.5),
}

function Recipes.Difficulty(recipe, skill)
  if skill < recipe.yellow then
    return "orange"
  elseif skill < recipe.green then
    return "yellow"
  elseif skill < recipe.grey then
    return "green"
  end
  return "grey"
end

-- Whether you could have this recipe at this skill: you know it, or your skill
-- is high enough to learn it.
function Recipes.Usable(recipe, skill)
  return Recipes.IsKnown(recipe) or skill >= recipe.learn
end

-- Chance that one craft gives a skill-up at this skill: certain while orange,
-- then falling evenly to nothing at grey (the classic formula).
function Recipes.Chance(recipe, skill)
  if skill >= recipe.grey or not Recipes.Usable(recipe, skill) then
    return 0
  end
  if skill < recipe.yellow then
    return 1
  end
  return (recipe.grey - skill) / (recipe.grey - recipe.yellow)
end

-- Points a successful craft gives (some recipes give more while orange).
function Recipes.Gain(recipe, skill)
  if skill < recipe.yellow then
    return recipe.skillUps
  end
  return 1
end

--------------------------------------------------------------------------------
-- What you know (read from Blizzard's profession window, kept per character)
--------------------------------------------------------------------------------

function Recipes.IsKnown(recipe)
  local known = ns.char and ns.char.known[recipe.skillLine]
  return known ~= nil and known[recipe.spell] == true
end

function Recipes.HasScanned(skillLine)
  return ns.char ~= nil and ns.char.known[skillLine] ~= nil
end

local function scanOpenProfession()
  local skillLine = ns.GetOpenProfession()
  if not skillLine or not C_TradeSkillUI.GetRecipeInfo then
    return
  end
  -- Another player's linked profession isn't yours.
  if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then
    return
  end
  if C_TradeSkillUI.IsNPCCrafting and C_TradeSkillUI.IsNPCCrafting() then
    return
  end
  local known = {}
  for _, recipe in ipairs(Recipes.For(skillLine)) do
    local info = C_TradeSkillUI.GetRecipeInfo(recipe.spell)
    if info and info.learned then
      known[recipe.spell] = true
    end
  end
  ns.char.known[skillLine] = known
  ns.Fire("KNOWN_CHANGED", skillLine)
end

local queueScan = ns.Debounce(scanOpenProfession, 0.3)
ns.On("TRADE_SKILL_SHOW", queueScan)
ns.On("TRADE_SKILL_LIST_UPDATE", queueScan)
ns.On("NEW_RECIPE_LEARNED", queueScan)

--------------------------------------------------------------------------------
-- Exact learn levels from trainers (the client data only has estimates for
-- trainer recipes). Kept account-wide: they're the same for every character.
--------------------------------------------------------------------------------

local function scanTrainer()
  if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceSkillReq) or not ns.db then
    return
  end
  local byName = {}
  local learned = 0
  for index = 1, GetNumTrainerServices() do
    local serviceName = GetTrainerServiceInfo(index)
    local skillName, skillRank = GetTrainerServiceSkillReq(index)
    if serviceName and skillName and skillRank then
      for skillLine, professionName in pairs(ns.PROFESSION_NAMES) do
        if professionName == skillName then
          if not byName[skillLine] then
            byName[skillLine] = {}
            for _, recipe in ipairs(Recipes.For(skillLine)) do
              byName[skillLine][Recipes.Name(recipe)] = recipe
            end
          end
          local recipe = byName[skillLine][serviceName]
          if recipe and ns.db.learnAt[recipe.spell] ~= skillRank then
            ns.db.learnAt[recipe.spell] = skillRank
            recipe.learn, recipe.learnExact = skillRank, true
            learned = learned + 1
          end
        end
      end
    end
  end
  if learned > 0 then
    ns.Fire("KNOWN_CHANGED")
  end
end

local queueTrainer = ns.Debounce(scanTrainer, 0.3)
ns.On("TRAINER_SHOW", queueTrainer)
ns.On("TRAINER_UPDATE", queueTrainer)

local skillChanged = ns.Debounce(function() ns.Fire("SKILL_CHANGED") end, 0.3)
ns.On("SKILL_LINES_CHANGED", skillChanged)
ns.On("TRADE_SKILL_LIST_UPDATE", skillChanged)
