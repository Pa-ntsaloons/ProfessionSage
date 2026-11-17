local _, ns = ...

local Planner = {}
ns.Planner = Planner

local Recipes, Prices = ns.Recipes, ns.Prices

-- Skill caps of each training rank (Apprentice, Journeyman, Expert, Artisan).
local RANK_CAPS = { 75, 150, 225, 300 }
local RANK_NAMES = { [75] = "Journeyman", [150] = "Expert", [225] = "Artisan" }

-- Route styles: "cheap" (lowest net cost), "fast" (fewest crafts), "balanced".
Planner.MODES = {
  { key = "cheap", label = "Most profit", tip = "Spends the least (or earns the most) once you sell what you make, even if it takes more crafts." },
  { key = "fast", label = "Fewest crafts", tip = "The fewest crafts: orange recipes and recipes you already know, so less crafting and fewer trips to learn new ones." },
  { key = "balanced", label = "Balanced", tip = "Saves crafts where it costs little gold: each craft counts as worth a typical craft's cost on this route." },
}
local LEARN_TRIP_CRAFTS = 8            -- a trip to a trainer or vendor, in crafts' worth of time
local BALANCED_MIN_CRAFT_VALUE = 300   -- copper; a craft's time is worth at least this

local function nextCap(skill)
  for _, cap in ipairs(RANK_CAPS) do
    if skill < cap then
      return cap
    end
  end
  return RANK_CAPS[#RANK_CAPS]
end

-- What it costs to start using a recipe: 0 if known or from a trainer (trainer
-- fees aren't in the data), the recipe item's auction price, or nil when the
-- recipe can't be priced (a drop or vendor recipe that isn't on the AH).
local function acquireCost(recipe)
  if Recipes.IsKnown(recipe) then
    return 0, "known"
  end
  if not recipe.recipeItem then
    return 0, "trainer"
  end
  local auction = Prices.Auction(recipe.recipeItem)
  local vendor = recipe.recipeVendorPrice and ns.Sources.IsVendorSold(recipe.recipeItem) and recipe.recipeVendorPrice
  if vendor and (not auction or vendor <= auction) then
    return vendor, "vendor"
  end
  if auction then
    return auction, "auction"
  end
  return nil, "unpriced"
end

--[[
Plans the cheapest expected route from one skill level to another.

options: skillLine, from, to, maxRank (the cap you're trained for now),
         onlyKnown (only use recipes you already know)

Returns {
  steps = list of
    { kind = "craft", recipe, from, to, crafts, cost, each }
    { kind = "learn", recipe, cost, how = "trainer" / "auction" }
    { kind = "train", at, rank }
    { kind = "stuck", at }
  shopping = list of { item, count } (before subtracting what you have)
  total = expected copper, reached = skill the route gets to
}

At each point it picks the recipe with the lowest expected cost per skill-up
(material cost / chance of a skill-up). A recipe that still has to be bought
has its price spread over the points it could be used for.
]]
function Planner.Plan(options)
  local skillLine, skill, target = options.skillLine, options.from, options.to
  local cap = math.max(options.maxRank or skill, skill)

  local candidates = {}
  for _, recipe in ipairs(Recipes.For(skillLine)) do
    local known = Recipes.IsKnown(recipe)
    if recipe.grey > skill and (known or recipe.learn < target) then
      if known or not options.onlyKnown then
        local craftCost = Prices.CraftCost(recipe)
        local acquire, how = acquireCost(recipe)
        if craftCost and acquire then
          -- Net cost: materials minus what selling the result brings back.
          local resale = Prices.Resale(recipe)
          table.insert(candidates, { recipe = recipe, craft = craftCost, resale = resale,
                                     net = craftCost - resale, acquire = acquire, how = how })
        end
      end
    end
  end

  local steps, acquired = {}, {}
  local total, materials, resale, learning, craftCount = 0, 0, 0, 0, 0
  local current
  local mode = options.mode or "cheap"

  -- Balanced: what one craft's time is worth, taken as a typical craft's net
  -- cost on this route (at least a few silver), so saving crafts can beat a
  -- slightly cheaper recipe.
  local craftValue = 0
  if mode == "balanced" then
    local costs = {}
    for _, candidate in ipairs(candidates) do
      if candidate.net > 0 then
        table.insert(costs, candidate.net)
      end
    end
    table.sort(costs)
    craftValue = math.max(BALANCED_MIN_CRAFT_VALUE, costs[math.max(1, math.floor(#costs / 2))] or 0)
  end

  while skill < target do
    if skill >= cap then
      if cap >= RANK_CAPS[#RANK_CAPS] then
        break
      end
      table.insert(steps, { kind = "train", at = skill, rank = RANK_NAMES[cap] or "the next rank" })
      cap = nextCap(cap)
      current = nil
    end

    local best, bestScore
    for _, candidate in ipairs(candidates) do
      local recipe = candidate.recipe
      local chance = Recipes.Chance(recipe, skill)
      if chance > 0 then
        local gain = Recipes.Gain(recipe, skill)
        local usefulPoints = math.max(1, math.min(recipe.grey, target) - skill)
        local needsLearning = not acquired[recipe] and candidate.how ~= "known"

        -- Money per skill-up, with a recipe's price spread over its points.
        local money = candidate.net / chance / gain
        if needsLearning and candidate.acquire > 0 then
          money = money + candidate.acquire / usefulPoints
        end
        -- Crafts per skill-up, with a trip to learn a recipe counted as time.
        local crafts = 1 / (chance * gain)
        if needsLearning then
          crafts = crafts + LEARN_TRIP_CRAFTS / usefulPoints
        end

        local score
        if mode == "fast" then
          score = crafts + money * 1e-7  -- money only breaks ties
        elseif mode == "balanced" then
          score = money + crafts * craftValue
        else
          score = money + crafts * 1e-3  -- crafts only break ties
        end
        if not bestScore or score < bestScore then
          best, bestScore = candidate, score
        end
      end
    end

    if not best then
      table.insert(steps, { kind = "stuck", at = skill })
      break
    end

    local recipe = best.recipe
    if not acquired[recipe] then
      acquired[recipe] = true
      if best.how ~= "known" then
        table.insert(steps, { kind = "learn", recipe = recipe, cost = best.acquire, how = best.how })
        total = total + best.acquire
        learning = learning + best.acquire
      end
    end

    local chance = Recipes.Chance(recipe, skill)
    local gain = Recipes.Gain(recipe, skill)
    -- A new step when the recipe or its color changes, so failed crafts show:
    -- orange always gives a point, yellow and green less and less often.
    local difficulty = Recipes.Difficulty(recipe, skill)
    if not (current and current.recipe == recipe and current.difficulty == difficulty) then
      current = { kind = "craft", recipe = recipe, from = skill, to = skill, crafts = 0, each = best.craft,
                  resaleEach = best.resale,
                  difficulty = difficulty }
      table.insert(steps, current)
    end
    current.crafts = current.crafts + 1 / chance
    skill = math.min(target, skill + gain)
    current.to = skill
  end

  -- Whole crafts, costs and the shopping list.
  local needed = {}
  local order = {}
  for _, step in ipairs(steps) do
    if step.kind == "craft" then
      step.crafts = math.max(1, math.ceil(step.crafts - 0.05))
      step.cost = step.crafts * step.each
      step.resale = step.crafts * step.resaleEach
      step.net = step.cost - step.resale
      craftCount = craftCount + step.crafts
      materials = materials + step.cost
      resale = resale + step.resale
      total = total + step.net
      for _, reagent in ipairs(step.recipe.reagents) do
        if not needed[reagent.item] then
          needed[reagent.item] = 0
          table.insert(order, reagent.item)
        end
        needed[reagent.item] = needed[reagent.item] + reagent.count * step.crafts
      end
    end
  end
  local shopping = {}
  for _, item in ipairs(order) do
    table.insert(shopping, { item = item, count = needed[item] })
  end

  -- total = recipes + materials - money back from selling what you make.
  return { steps = steps, shopping = shopping, total = total, materials = materials, resale = resale,
           learning = learning, crafts = craftCount, reached = skill }
end

-- Materials for crafting a recipe some number of times: list of { item, count }.
function Planner.Materials(recipe, crafts)
  local list = {}
  for _, reagent in ipairs(recipe.reagents) do
    table.insert(list, { item = reagent.item, count = reagent.count * crafts })
  end
  return list
end
