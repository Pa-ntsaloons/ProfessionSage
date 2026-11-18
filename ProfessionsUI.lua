local _, ns = ...

local Recipes, Prices, Planner = ns.Recipes, ns.Prices, ns.Planner

--------------------------------------------------------------------------------
-- Waiting for Blizzard's profession window (it loads on demand)
--------------------------------------------------------------------------------

local professionsLoaded = {}

-- Runs fn once Blizzard's Professions UI exists.
-- Needs both Blizzard's frame and our saved settings. Another addon (such as
-- Mastercraft) may load Blizzard's frame before this addon has its settings.
local function ready()
  return ns.db ~= nil and ProfessionsFrame ~= nil and ProfessionsFrame.CraftingPage ~= nil
end

local function runPending()
  if not ready() then
    return
  end
  local pending = professionsLoaded
  professionsLoaded = {}
  for _, entry in ipairs(pending) do
    ns.SafeCall(entry.label, entry.fn)
  end
end

function ns.OnProfessionsLoaded(fn, label)
  table.insert(professionsLoaded, { fn = fn, label = label or "setup" })
  runPending()
end

ns.On("ADDON_LOADED", function(name)
  if name == "Blizzard_Professions" then
    runPending()
  end
end)
ns.Listen("DB_READY", runPending)

--------------------------------------------------------------------------------
-- Recipe tooltip lines
--------------------------------------------------------------------------------

function ns.AddRecipeTooltip(tooltip, recipe, crafts)
  crafts = crafts or 1
  tooltip:AddLine(" ")
  tooltip:AddLine(ns.TITLE, 0.85, 0.7, 0.43)

  local cost, missing = Prices.CraftCost(recipe)
  local value, source = nil, nil
  if recipe.item then
    local each
    each, source = Prices.Sell(recipe.item)
    value = each and each * recipe.count
  end

  if value then
    local label = source == "vendor" and "Sells to vendor" or "Sells on AH"
    tooltip:AddDoubleLine(label, ns.Money(value * crafts), 1, 0.82, 0, 1, 1, 1)
  end
  if cost then
    tooltip:AddDoubleLine("Materials", ns.Money(cost * crafts), 1, 0.82, 0, 1, 1, 1)
  end
  if value and cost then
    tooltip:AddDoubleLine("Profit", ns.Profit((value - cost) * crafts), 1, 0.82, 0, 1, 1, 1)
  end
  if missing then
    local names = {}
    for _, item in ipairs(missing) do
      table.insert(names, ns.ItemName(item) or ("item " .. item))
    end
    tooltip:AddLine("No price for: " .. table.concat(names, ", "), 0.6, 0.6, 0.6, true)
  end

  local c = ns.DIFFICULTY_COLORS
  tooltip:AddLine(string.format("%s%d|r  %s%d|r  %s%d|r  %s%d|r",
    c.orange:GenerateHexColorMarkup(), recipe.learn,
    c.yellow:GenerateHexColorMarkup(), recipe.yellow,
    c.green:GenerateHexColorMarkup(), recipe.green,
    c.grey:GenerateHexColorMarkup(), recipe.grey), 1, 1, 1)
  if not Prices.HasAuctionator() then
    tooltip:AddLine("Install Auctionator for auction prices.", 0.6, 0.6, 0.6)
  end
end

--------------------------------------------------------------------------------
-- Profit next to every recipe in the list
--------------------------------------------------------------------------------

local routeCrafts = {}  -- [recipe spell] = crafts, while the route filter is on

local function decorateRow(button, node)
  local data = node and node.GetData and node:GetData()
  local info = data and data.recipeInfo
  local text = button.ProfessionSageProfit
  local recipe = info and Recipes.Get(info.recipeID)
  button.professionSageRecipe = recipe

  -- Route filter: how many to craft, in front of the name.
  local crafts = recipe and routeCrafts[recipe.spell]
  if crafts and button.Label and button.Label:GetText() ~= button.professionSageLabel then
    button.professionSageLabel = string.format("|cffffffff%dx|r %s", crafts, button.Label:GetText() or "")
    button.Label:SetText(button.professionSageLabel)
  end

  local profit = recipe and ns.db.showRowProfit and Prices.Profit(recipe)
  if not profit then
    if text then
      text:Hide()
    end
    return
  end

  if not text then
    text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("RIGHT", button, "RIGHT", -4, 0)
    text:SetJustifyH("RIGHT")
    button.ProfessionSageProfit = text
  end
  text:SetText(ns.Profit(profit.profit))
  text:Show()

  -- Keep the recipe name from running under the profit.
  if button.Label then
    local used = text:GetStringWidth() + 14
    if button.SkillUps and button.SkillUps:IsShown() then
      used = used + button.SkillUps:GetWidth()
    end
    if button.Count and button.Count:IsShown() then
      used = used + button.Count:GetStringWidth()
    end
    local available = math.max(40, button:GetWidth() - used)
    if button.Label:GetStringWidth() > available then
      button.Label:SetWidth(available)
    end
  end
end

local function onRowEnter(button)
  local recipe = button.professionSageRecipe
  if not recipe then
    return
  end
  if GameTooltip:GetOwner() ~= button or not GameTooltip:IsShown() then
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(Recipes.Name(recipe))
  end
  ns.AddRecipeTooltip(GameTooltip, recipe)
  GameTooltip:Show()
end

local function refreshRows()
  local list = ProfessionsFrame and ProfessionsFrame.CraftingPage.RecipeList
  if list and list:IsVisible() then
    list.ScrollBox:ForEachFrame(decorateRow)
  end
end
ns.RefreshRows = refreshRows

ns.OnProfessionsLoaded(function()
  local scrollBox = ProfessionsFrame.CraftingPage.RecipeList.ScrollBox
  -- Blizzard sets each row's scripts every time it fills the row, which also
  -- drops our hook, so hook again each time.
  ScrollUtil.AddInitializedFrameCallback(scrollBox, function(_, button, node)
    decorateRow(button, node)
    button:HookScript("OnEnter", onRowEnter)
  end, ns, false)
  scrollBox:ForEachFrame(function(button, node)
    decorateRow(button, node)
    button:HookScript("OnEnter", onRowEnter)
  end)
end)

local queueRefreshRows = ns.Debounce(refreshRows, 0.2)
ns.Listen("PRICES_CHANGED", queueRefreshRows)
ns.Listen("ITEM_INFO", queueRefreshRows)

--------------------------------------------------------------------------------
-- "Leveling route" filter: the recipe list shows only what the leveling guide
-- says to craft, in route order, with how many of each.
--------------------------------------------------------------------------------

local blizzardProvider  -- the list Blizzard built, to put back when the filter is off
local applying = false

local function recipeList()
  return ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RecipeList
end

-- Our list for the open profession, or nil to keep Blizzard's.
local function buildRouteProvider()
  wipe(routeCrafts)
  local skillLine, info = ns.GetOpenProfession()
  if not skillLine or not ns.Panel or not ns.Panel.RouteFor then
    return nil
  end
  if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then
    return nil
  end
  local result, target = ns.Panel.RouteFor(skillLine, info)
  if not result then
    return nil
  end

  local order = {}
  for _, step in ipairs(result.steps) do
    if step.kind == "craft" then
      local spell = step.recipe.spell
      if not routeCrafts[spell] then
        routeCrafts[spell] = 0
        table.insert(order, spell)
      end
      routeCrafts[spell] = routeCrafts[spell] + step.crafts
    end
  end
  if #order == 0 then
    return nil
  end

  local styleLabel = ""
  for _, option in ipairs(Planner.MODES) do
    if option.key == (ns.db.routeMode or "cheap") then
      styleLabel = " - " .. option.label
    end
  end
  local provider = CreateTreeDataProvider()
  local category = provider:Insert({ categoryInfo = {
    name = string.format("Route to %d%s", target, styleLabel),
    categoryID = -1,
  } })
  category:Insert({ topPadding = true })
  for _, spell in ipairs(order) do
    local recipeInfo = C_TradeSkillUI.GetRecipeInfo(spell)
    if recipeInfo then
      category:Insert({ recipeInfo = recipeInfo })
    end
  end
  category:Insert({ bottomPadding = true })
  return provider
end

local function applyRouteFilter()
  local list = recipeList()
  if not list or not list.ScrollBox or not ns.db then
    return
  end
  local provider = ns.db.routeFilter and buildRouteProvider()
  if not provider then
    wipe(routeCrafts)
    provider = blizzardProvider
  end
  if not provider or provider == list.ScrollBox:GetDataProvider() then
    refreshRows()
    return
  end
  applying = true
  list.ScrollBox:SetDataProvider(provider, ScrollBoxConstants.RetainScrollPosition)
  applying = false
  -- Keep the recipe you had selected.
  local previous = list.GetPreviousRecipeID and list:GetPreviousRecipeID()
  if previous and list.SelectRecipe then
    pcall(list.SelectRecipe, list, { recipeID = previous }, false)
  end
end
local queueRouteFilter = ns.Debounce(applyRouteFilter, 0.2)

ns.OnProfessionsLoaded(function()
  local list = recipeList()
  -- Blizzard rebuilds the list often (filters, search, skill-ups): remember
  -- its list and swap ours in again while the filter is on.
  hooksecurefunc(list.ScrollBox, "SetDataProvider", function(_, provider)
    if applying then
      return
    end
    blizzardProvider = provider
    if ns.db.routeFilter then
      queueRouteFilter()
    end
  end)
  blizzardProvider = list.ScrollBox:GetDataProvider()

  if Menu and Menu.ModifyMenu then
    Menu.ModifyMenu("MENU_PROFESSIONS_FILTER", function(_, rootDescription)
      if not ns.GetOpenProfession() then
        return
      end
      rootDescription:CreateDivider()
      rootDescription:CreateTitle(ns.TITLE)
      local check = rootDescription:CreateCheckbox("Leveling route",
        function() return ns.db.routeFilter end,
        function()
          ns.db.routeFilter = not ns.db.routeFilter
          applyRouteFilter()
        end)
      if check.SetTooltip then
        check:SetTooltip(function(tooltip)
          GameTooltip_SetTitle(tooltip, "Leveling route")
          GameTooltip_AddNormalLine(tooltip, "Show only the recipes the leveling guide uses to reach your target skill, in the order to craft them, with how many of each. Set the target and route style in the guide.")
        end)
      end
    end)
  end
  if ns.db.routeFilter then
    queueRouteFilter()
  end
end, "route filter")

local function onRouteInputsChanged()
  if ns.db and ns.db.routeFilter then
    queueRouteFilter()
  end
end
ns.Listen("ROUTE_CHANGED", onRouteInputsChanged)
ns.Listen("SKILL_CHANGED", onRouteInputsChanged)
ns.Listen("KNOWN_CHANGED", onRouteInputsChanged)
ns.Listen("PRICES_CHANGED", onRouteInputsChanged)

--------------------------------------------------------------------------------
-- "Plan" amount: how many you want to make, beyond what your bags allow.
-- Blizzard's own amount box stops at what you can craft right now.
--------------------------------------------------------------------------------

local plan = {}
ns.Plan = plan

local function selectedRecipe()
  local form = ProfessionsFrame and ProfessionsFrame.CraftingPage.SchematicForm
  local info = form and form.GetRecipeInfo and form:GetRecipeInfo()
  return info and Recipes.Get(info.recipeID), info
end

local function trackerTitle(recipe, crafts)
  return string.format("%s x%d", Recipes.Name(recipe), crafts)
end

-- Missing materials for `crafts` of a recipe: count of items short.
local function shortfall(recipe, crafts)
  local short = 0
  for _, entry in ipairs(Planner.Materials(recipe, crafts)) do
    if (ns.GetItemCount(entry.item, true) or 0) < entry.count then
      short = short + 1
    end
  end
  return short
end

function plan:Update(fromUser)
  local recipe = selectedRecipe()
  if not self.holder then
    return
  end
  self.holder:SetShown(recipe ~= nil and #recipe.reagents > 0)
  if not recipe or #recipe.reagents == 0 then
    return
  end

  -- Stay clear of Blizzard's quality checkbox when it's showing.
  local form = ProfessionsFrame.CraftingPage.SchematicForm
  local quality = form.AllocateBestQualityCheckbox
  self.holder:ClearAllPoints()
  self.holder:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 14, (quality and quality:IsShown()) and 46 or 10)

  local crafts = self.box:GetValue()
  local short = shortfall(recipe, crafts)
  if short > 0 then
    self.status:SetText(string.format("|cffff6060%d item%s short|r", short, short == 1 and "" or "s"))
  else
    self.status:SetText("|cff40c040You have everything|r")
  end

  local title = trackerTitle(recipe, crafts)
  if fromUser then
    if short > 0 then
      ns.Tracker:Track(title, Planner.Materials(recipe, crafts))
    elseif ns.Tracker:IsTracking() and ns.char.shopping.recipe == recipe.spell then
      ns.Tracker:Clear()
    end
    if ns.char.shopping and short > 0 then
      ns.char.shopping.recipe = recipe.spell
    end
  end
end

local function createPlanControls()
  local form = ProfessionsFrame.CraftingPage.SchematicForm

  local holder = CreateFrame("Frame", nil, form)
  holder:SetSize(300, 24)
  holder:SetFrameLevel(form:GetFrameLevel() + 10)
  plan.holder = holder

  local label = holder:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  label:SetPoint("LEFT")
  label:SetText("Plan to make")

  local ok, box = pcall(CreateFrame, "EditBox", nil, holder, "NumericInputSpinnerTemplate")
  if not ok then
    box = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
    box:SetNumeric(true)
    box:SetAutoFocus(false)
    box:SetSize(36, 20)
    box.GetValue = function(self) return math.max(1, self:GetNumber()) end
    box:SetScript("OnTextChanged", function(_, userInput)
      if userInput then
        plan:Update(true)
      end
    end)
  else
    box:SetMinMaxValues(1, 999)
    box:SetValue(1)
    box:SetOnValueChangedCallback(function()
      plan:Update(true)
    end)
  end
  box:SetPoint("LEFT", label, "RIGHT", ok and 26 or 10, 0)
  plan.box = box

  local status = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  status:SetPoint("LEFT", box, "RIGHT", ok and 28 or 10, 0)
  plan.status = status

  local help = CreateFrame("Frame", nil, holder)
  help:SetAllPoints(label)
  help:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Plan to make")
    GameTooltip:AddLine("Choose how many you want to make, even more than you have materials for. If you're short, a list of what you still need pops up at the side of your screen.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  help:SetScript("OnLeave", GameTooltip_Hide)

  if EventRegistry then
    EventRegistry:RegisterCallback("Professions.RecipeSelected", function()
      plan:Update(false)
    end, plan)
  end
  form:HookScript("OnShow", function() plan:Update(false) end)
  plan:Update(false)
end

ns.OnProfessionsLoaded(createPlanControls)

local queuePlanUpdate = ns.Debounce(function() plan:Update(false) end, 0.2)
ns.On("BAG_UPDATE_DELAYED", queuePlanUpdate)
