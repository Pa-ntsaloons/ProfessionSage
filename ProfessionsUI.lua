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
  ns.TooltipHeading(tooltip, ns.TITLE)

  local cost, missing = Prices.CraftCost(recipe)
  local value, source = nil, nil
  if recipe.item then
    local each
    each, source = Prices.Sell(recipe.item)
    value = each and each * recipe.count
  end

  if value then
    ns.TooltipPair(tooltip, source == "vendor" and "Sells to vendor" or "Sells on AH", ns.Money(value * crafts))
  end
  if cost then
    ns.TooltipPair(tooltip, "Materials", ns.Money(cost * crafts))
  end
  if value and cost then
    ns.TooltipPair(tooltip, "Profit", ns.Profit((value - cost) * crafts))
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
-- Our list is built once per route and reused, so it can go back up the moment
-- Blizzard rebuilds its own (otherwise the unfiltered list flashes).
local routeProvider, routeKey, routeSkillLine

local function recipeList()
  return ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RecipeList
end

-- Our list for the open profession, or nil to keep Blizzard's.
local function buildRouteProvider()
  local skillLine, info = ns.GetOpenProfession()
  routeSkillLine = skillLine
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

  local order, crafts = {}, {}
  for _, step in ipairs(result.steps) do
    if step.kind == "craft" then
      local spell = step.recipe.spell
      if not crafts[spell] then
        crafts[spell] = 0
        table.insert(order, spell)
      end
      crafts[spell] = crafts[spell] + step.crafts
    end
  end
  if #order == 0 then
    return nil
  end

  -- Same route as last time: keep the list we have, so it doesn't redraw.
  local parts = { skillLine, target, ns.db.routeMode or "cheap" }
  for _, spell in ipairs(order) do
    local recipeInfo = C_TradeSkillUI.GetRecipeInfo(spell)
    table.insert(parts, string.format("%d:%d:%s", spell, crafts[spell], recipeInfo and tostring(recipeInfo.learned) or "-"))
  end
  local key = table.concat(parts, ",")
  if routeProvider and key == routeKey then
    return routeProvider
  end
  routeKey = key
  wipe(routeCrafts)
  for spell, count in pairs(crafts) do
    routeCrafts[spell] = count
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

-- rebuild: plan the route again (it may have changed); otherwise reuse the
-- list we have unless the profession changed.
local function applyRouteFilter(rebuild)
  local list = recipeList()
  if not list or not list.ScrollBox or not ns.db then
    return
  end
  local provider
  if ns.db.routeFilter then
    if rebuild or not routeProvider or routeSkillLine ~= ns.GetOpenProfession() then
      routeProvider = buildRouteProvider()
      if not routeProvider then
        routeKey = nil
      end
    end
    provider = routeProvider
  end
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
local queueRouteRebuild = ns.Debounce(function() applyRouteFilter(true) end, 0.2)

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
      -- Straight away, so Blizzard's list never shows.
      ns.SafeCall("route filter", applyRouteFilter, false)
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
          applyRouteFilter(true)
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
    queueRouteRebuild()
  end
end, "route filter")

local function onRouteInputsChanged()
  if ns.db and ns.db.routeFilter then
    queueRouteRebuild()
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

-- Materials for `crafts` of a recipe, with what you have: list of
-- { item, count, bags, bank }, plus how many items your bags are short of, how
-- many are short even counting the bank, and how many of those your other
-- characters (Syndicator) could cover.
local function materialsFor(recipe, crafts)
  local list, shortInBags, short, altsCover = {}, 0, 0, 0
  for _, entry in ipairs(Planner.Materials(recipe, crafts)) do
    local bags = ns.GetItemCount(entry.item, false) or 0
    local total = ns.GetItemCount(entry.item, true) or 0
    local alts = ns.AltCounts(entry.item)
    table.insert(list, { item = entry.item, count = entry.count, bags = bags, bank = math.max(0, total - bags) })
    if bags < entry.count then
      shortInBags = shortInBags + 1
    end
    if total < entry.count then
      short = short + 1
      if total + alts >= entry.count then
        altsCover = altsCover + 1
      end
    end
  end
  return list, shortInBags, short, altsCover
end

-- Hovering the status: each material with what's in your bags and bank.
local function materialsTooltip(owner)
  local recipe = selectedRecipe()
  if not recipe or not plan.box then
    return
  end
  local crafts = plan.box:GetValue()
  GameTooltip:SetOwner(owner, "ANCHOR_TOP")
  GameTooltip:SetText(string.format("Materials for %d", crafts))
  for index, entry in ipairs((materialsFor(recipe, crafts))) do
    if index > 1 then
      GameTooltip:AddLine(" ")
    end
    ns.AddMaterialLines(GameTooltip, entry.item, entry.count, entry.bags, entry.bank)
  end
  GameTooltip:Show()
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

  -- Keep the status clear of Blizzard's "Track Recipe" checkbox.
  local track = form.TrackRecipeCheckbox
  self.status:ClearAllPoints()
  self.status:SetPoint("LEFT", self.box, "RIGHT", self.statusGap, 0)
  if track and track:IsShown() then
    self.status:SetPoint("RIGHT", track, "LEFT", -4, 0)
  end

  local crafts = self.box:GetValue()
  local _, shortInBags, short, altsCover = materialsFor(recipe, crafts)
  if short > 0 and altsCover == short then
    self.status:SetText("|cffffd100Some on alts|r")
  elseif short > 0 then
    self.status:SetText(string.format("|cffff6060%d item%s short|r", short, short == 1 and "" or "s"))
  elseif shortInBags > 0 then
    self.status:SetText("|cffffd100Some in bank|r")
  else
    self.status:SetText("|cff40c040All in bags|r")
  end

  local title = trackerTitle(recipe, crafts)
  if fromUser and ns.db.planPopup then
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

  -- Whether being short opens the materials popup.
  local popupCheck = CreateFrame("CheckButton", nil, holder, "UICheckButtonTemplate")
  popupCheck:SetSize(22, 22)
  popupCheck:SetPoint("LEFT", -4, 0)
  popupCheck:SetChecked(ns.db.planPopup)
  popupCheck:SetScript("OnClick", function(self)
    ns.db.planPopup = self:GetChecked() and true or false
    local recipe = selectedRecipe()
    if not ns.db.planPopup and recipe and ns.Tracker:IsTracking() and ns.char.shopping.recipe == recipe.spell then
      ns.Tracker:Clear()
    end
    plan:Update(true)
  end)
  popupCheck:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Materials popup")
    GameTooltip:AddLine("On: if you're short of materials for the amount you plan to make, a list of what you still need pops up at the side of your screen.", 1, 1, 1, true)
    GameTooltip:AddLine("Off: only the status next to the amount shows what you're short of.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  popupCheck:SetScript("OnLeave", GameTooltip_Hide)
  plan.popupCheck = popupCheck

  local label = holder:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  label:SetPoint("LEFT", popupCheck, "RIGHT", 0, 0)
  label:SetText("Plan")

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
  plan.statusGap = ok and 28 or 10
  status:SetPoint("LEFT", box, "RIGHT", plan.statusGap, 0)
  status:SetJustifyH("LEFT")
  status:SetWordWrap(false)
  plan.status = status

  local statusHover = CreateFrame("Frame", nil, holder)
  statusHover:SetAllPoints(status)
  statusHover:SetScript("OnEnter", materialsTooltip)
  statusHover:SetScript("OnLeave", GameTooltip_Hide)

  local help = CreateFrame("Frame", nil, holder)
  help:SetAllPoints(label)
  help:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Plan")
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
