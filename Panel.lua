local _, ns = ...

local Recipes, Prices, Planner = ns.Recipes, ns.Prices, ns.Planner

--------------------------------------------------------------------------------
-- Leveling guide: a panel beside Blizzard's profession window, opened from a
-- side tab under the profession tabs.
--------------------------------------------------------------------------------

local Panel = {}
ns.Panel = Panel

local PANEL_WIDTH = 350
local ROW_HEIGHT = 24
local TAB_GAP = 40  -- room for the profession side tabs between the frames

local ICON_LEARN = "Interface\\Icons\\INV_Scroll_03"
local ICON_TRAIN = "Interface\\Icons\\INV_Misc_Book_11"
local ICON_STUCK = "Interface\\Icons\\INV_Misc_QuestionMark"
local ICON_TAB = "Interface\\Icons\\INV_Misc_Book_09"
local MINING = 186

local frame, view, scrollBox, routeButton, shoppingButton
local header, skillText, targetSlider, onlyKnownCheck, useBagsCheck
local totalText, totalSub, sourceText, trackButton, auctionatorButton, tab
local targetLabel, targetBox, modeButton, routeModeControl
local gatherView = {}  -- [skill line] = "craft" when Mining shows its smelting route
local mode = "route"
local current  -- { skillLine, skill, maxRank, target, result }

local function chosenTarget(skillLine, skill, maxRank)
  local saved = ns.char.targets[skillLine]
  if saved and saved > skill then
    return math.min(saved, 300)
  end
  if maxRank and maxRank > skill then
    return maxRank
  end
  return math.min(300, skill + 25)
end

-- The route the guide would show for this profession, with its target, or nil
-- when there's nothing to plan. info is C_TradeSkillUI.GetBaseProfessionInfo().
function Panel.RouteFor(skillLine, info)
  local skill = info.skillLevel or 0
  local maxRank = info.maxSkillLevel or skill
  if skill >= 300 or not ns.RECIPES[skillLine] then
    return nil
  end
  local target = chosenTarget(skillLine, skill, maxRank)
  return Planner.Plan({
    skillLine = skillLine,
    from = skill,
    to = target,
    maxRank = maxRank,
    onlyKnown = ns.db.onlyKnown,
    mode = ns.db.routeMode or "cheap",
  }), target
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function craftTooltip(row, step)
  local recipe = step.recipe
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(Recipes.Name(recipe))
  GameTooltip:AddLine(string.format("Craft about %d time%s to go from %d to %d.",
    step.crafts, step.crafts == 1 and "" or "s", step.from, step.to), 1, 1, 1, true)
  local first = Recipes.Chance(recipe, step.from)
  local last = Recipes.Chance(recipe, math.max(step.from, step.to - 1))
  if first >= 1 and last >= 1 then
    GameTooltip:AddLine("Orange: every craft gives a skill-up.", 1, 0.5, 0.25, true)
  else
    GameTooltip:AddLine(string.format("Chance of a skill-up: %d%% at %d, falling to %d%% at %d. The craft count includes the ones that won't give a point.",
      math.floor(first * 100 + 0.5), step.from, math.floor(last * 100 + 0.5), step.to - 1), 0.8, 0.8, 0.8, true)
  end
  GameTooltip:AddLine(" ")
  for _, reagent in ipairs(recipe.reagents) do
    local name, icon = ns.ItemLabel(reagent.item)
    local price = Prices.Buy(reagent.item)
    GameTooltip:AddDoubleLine(string.format("|T%s:0|t %s x%d", icon or 134400, name, reagent.count * step.crafts),
      price and ns.Money(price * reagent.count * step.crafts) or "|cff808080no price|r", 1, 1, 1, 1, 1, 1)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("Materials", ns.Money(step.cost), 1, 0.82, 0, 1, 1, 1)
  if step.resale > 0 then
    local _, source = Prices.Sell(recipe.item)
    GameTooltip:AddDoubleLine(source == "vendor" and "Sell back (vendor)" or "Sell back (AH, after cut)",
      ns.Money(step.resale), 1, 0.82, 0, 1, 1, 1)
  end
  GameTooltip:AddDoubleLine(step.net >= 0 and "Net cost" or "Net profit", ns.Money(math.abs(step.net)), 1, 0.82, 0,
    step.net >= 0 and 1 or 0.25, 1, step.net >= 0 and 1 or 0.25)
  ns.AddRecipeTooltip(GameTooltip, recipe, step.crafts)
  if Recipes.IsKnown(recipe) then
    GameTooltip:AddLine("Click to show this recipe.", 0.4, 0.8, 1)
  end
  GameTooltip:Show()
end

local function setupRow(row, entry)
  if not row.icon then
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 4, 0)
    row.right = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", -6, 0)
    row.right:SetJustifyH("RIGHT")
    row.left = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.left:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.left:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.left:SetJustifyH("LEFT")
    row.left:SetWordWrap(false)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnLeave", GameTooltip_Hide)
  end

  row.icon:SetDesaturated(false)
  row:SetScript("OnClick", nil)
  row:SetScript("OnEnter", nil)

  if entry.kind == "craft" then
    local recipe = entry.recipe
    local color = ns.DIFFICULTY_COLORS[entry.difficulty] or ns.DIFFICULTY_COLORS.yellow
    row.icon:SetTexture(Recipes.Icon(recipe) or 134400)
    -- Share of crafts that give a point on this step (orange is always 100%).
    local rate = (entry.to - entry.from) / math.max(1, entry.crafts)
    local rateText = rate < 0.995 and string.format(" |cffa0a0a0%d%%|r", math.floor(rate * 100 + 0.5)) or ""
    row.left:SetText(string.format("|cffffffff%dx|r ", entry.crafts) .. color:WrapTextInColorCode(Recipes.Name(recipe)) .. rateText)
    local net = entry.net >= 0 and ns.Money(entry.net) or ("|cff40c040+|r" .. ns.Money(-entry.net))
    row.right:SetText(string.format("|cffa0a0a0%d-%d|r  %s", entry.from, entry.to, net))
    row:SetScript("OnEnter", function(self) craftTooltip(self, entry) end)
    row:SetScript("OnClick", function()
      if Recipes.IsKnown(recipe) and C_TradeSkillUI.OpenRecipe then
        C_TradeSkillUI.OpenRecipe(recipe.spell)
      end
    end)
  elseif entry.kind == "learn" then
    local recipe = entry.recipe
    row.icon:SetTexture(ICON_LEARN)
    row.left:SetText("|cff66bbffLearn:|r " .. Recipes.Name(recipe))
    if entry.how == "trainer" then
      row.right:SetText("|cffa0a0a0Trainer|r")
    else
      local kind = entry.how == "vendor" and "Vendor" or "AH"
      row.right:SetText(string.format("|cffa0a0a0%s|r  %s", kind, ns.Money(entry.cost)))
    end
    row:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if entry.how == "trainer" then
        GameTooltip:SetText("Learn " .. Recipes.Name(recipe))
        GameTooltip:AddLine(string.format("Taught by %s trainers from skill %d%s.",
          ns.PROFESSION_NAMES[recipe.skillLine] or "profession", recipe.learn,
          recipe.learnExact and "" or " (about; exact once you've seen it at a trainer)"), 1, 1, 1, true)
        ns.Sources.AddTrainerTooltip(GameTooltip, recipe.skillLine, ns.Sources.RankForSkill(recipe.learn))
      else
        GameTooltip:SetItemByID(recipe.recipeItem)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(entry.how == "vendor" and "Vendor price" or "Auction price",
          ns.Coins(entry.cost), 1, 0.82, 0, 1, 1, 1)
        ns.Sources.AddTooltip(GameTooltip, recipe.recipeItem)
      end
      GameTooltip:Show()
    end)
  elseif entry.kind == "train" then
    row.icon:SetTexture(ICON_TRAIN)
    row.left:SetText(string.format("|cffffd100Train %s|r", entry.rank))
    row.right:SetText(string.format("|cffa0a0a0at %d|r", entry.at))
    row:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Train " .. entry.rank)
      GameTooltip:AddLine(string.format("Your skill stops at %d until you learn the next rank from a trainer.", entry.at), 1, 1, 1, true)
      if current and current.skillLine then
        ns.Sources.AddTrainerTooltip(GameTooltip, current.skillLine, ns.Sources.RankNumber(entry.rank))
      end
      GameTooltip:Show()
    end)
  elseif entry.kind == "stuck" then
    row.icon:SetTexture(ICON_STUCK)
    row.icon:SetDesaturated(true)
    row.left:SetText(string.format("|cff909090No priced recipe from skill %d|r", entry.at))
    row.right:SetText("")
    local mining = current and current.skillLine == MINING
    if mining then
      row.left:SetText(string.format("|cff909090Mine ore from skill %d|r", entry.at))
    end
    row:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Route stops here")
      if mining then
        GameTooltip:AddLine("Smelting can't take you further at this skill. Mine ore nodes to keep leveling; smelting picks up again at higher skill.", 1, 1, 1, true)
      else
        GameTooltip:AddLine("None of the recipes that still give skill-ups here have prices for all their materials. Scan the auction house with Auctionator, or turn off \"Only recipes I know\".", 1, 1, 1, true)
      end
      GameTooltip:Show()
    end)
  elseif entry.kind == "bracket" then
    row.icon:SetTexture(nil)
    row.left:SetText(string.format("|cffffd100Skill %d - %d|r%s", entry.from, entry.to,
      entry.current and "  |cff40c040(you are here)|r" or ""))
    row.right:SetText("")
  elseif entry.kind == "zones" then
    row.icon:SetTexture(nil)
    local names = {}
    for _, zone in ipairs(entry.zones) do
      table.insert(names, zone.nodes > 0 and string.format("%s |cff40c040(%d)|r", zone.name, zone.nodes) or zone.name)
    end
    row.left:SetText("|cffc8c8c8" .. table.concat(names, ", ") .. "|r")
    row.right:SetText("")
    row:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(string.format("Where to go at %d - %d", entry.from, entry.to))
      for _, zone in ipairs(entry.zones) do
        if zone.nodes > 0 then
          GameTooltip:AddDoubleLine(zone.name, string.format("%d nodes found", zone.nodes), 1, 1, 1, 0.25, 0.75, 0.25)
        else
          GameTooltip:AddLine(zone.name, 1, 1, 1)
        end
      end
      GameTooltip:AddLine(" ")
      if entry.hasCounts then
        GameTooltip:AddLine("Sorted by the nodes for this bracket you've found there (GatherMate2).", 0.7, 0.7, 0.7, true)
      elseif ns.HasGatherMate() then
        GameTooltip:AddLine("Zones will sort by the nodes you find as GatherMate2 records them.", 0.7, 0.7, 0.7, true)
      else
        GameTooltip:AddLine("Install GatherMate2 to sort zones by the nodes you've found.", 0.7, 0.7, 0.7, true)
      end
      GameTooltip:Show()
    end)
  elseif entry.kind == "gather" then
    local name, icon = ns.ItemLabel(entry.item)
    row.icon:SetTexture(icon or 134400)
    local locked = entry.skill and entry.need > entry.skill
    row.icon:SetDesaturated(locked)
    row.left:SetText(name .. (locked and string.format(" |cff808080(needs %d)|r", entry.need) or ""))
    local price, source = Prices.Sell(entry.item)
    row.right:SetText(price and (ns.Money(price) .. (source == "vendor" and " |cffa0a0a0v|r" or "")) or "|cff808080-|r")
    row:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(entry.item)
      GameTooltip:AddLine(" ")
      GameTooltip:AddDoubleLine("Skill needed", tostring(entry.need), 1, 0.82, 0, 1, 1, 1)
      local auction = Prices.Auction(entry.item)
      if auction then
        GameTooltip:AddDoubleLine("Auction price", ns.Coins(auction), 1, 0.82, 0, 1, 1, 1)
      end
      local vendor = select(11, ns.GetItemInfo(entry.item))
      if vendor and vendor > 0 then
        GameTooltip:AddDoubleLine("Vendor price", ns.Coins(vendor), 1, 0.82, 0, 1, 1, 1)
      end
      GameTooltip:Show()
    end)
  elseif entry.kind == "note" then
    row.icon:SetTexture(ICON_STUCK)
    row.icon:SetDesaturated(true)
    row.left:SetText("|cff909090" .. entry.text .. "|r")
    row.right:SetText("")
    row:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Good to know")
      GameTooltip:AddLine(entry.text, 1, 1, 1, true)
      GameTooltip:Show()
    end)
  elseif entry.kind == "item" then
    local name, icon = ns.ItemLabel(entry.item)
    local have = ns.HaveCount(entry.item)
    local missing = math.max(0, entry.count - have)
    row.icon:SetTexture(icon or 134400)
    row.left:SetText(name)
    local countText = missing == 0 and string.format("|cff40c040%d/%d|r", entry.count, entry.count)
      or (have > 0 and string.format("%d |cffa0a0a0(have %d)|r", missing, have) or tostring(missing))
    local price = Prices.Buy(entry.item)
    row.right:SetText(countText .. "  " .. (missing > 0 and (price and ns.Money(price * missing) or "|cff808080?|r") or ""))
    row:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(entry.item)
      local buy, source = Prices.Buy(entry.item)
      if buy then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(source == "vendor" and "Vendor price" or "Auction price", ns.Coins(buy), 1, 0.82, 0, 1, 1, 1)
      end
      GameTooltip:Show()
    end)
  end
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

local function missingShopping(result)
  local list = {}
  for _, entry in ipairs(result.shopping) do
    local missing = entry.count - ns.HaveCount(entry.item)
    if missing > 0 then
      table.insert(list, { item = entry.item, count = missing })
    end
  end
  return list
end

local function updateTabs()
  routeButton:SetEnabled(mode ~= "route")
  shoppingButton:SetEnabled(mode ~= "shopping")
end

function Panel:Refresh()
  ns.SafeCall("guide", self.RefreshNow, self)
end

local function setTotals(main, sub)
  totalText:SetText(main)
  totalSub:SetText(sub)
end

local function setCraftingControlsShown(shown)
  for _, control in ipairs({ targetLabel, targetSlider, targetBox, onlyKnownCheck, useBagsCheck,
                             routeButton, shoppingButton, trackButton, auctionatorButton, routeModeControl }) do
    control:SetShown(shown)
  end
end

function Panel:ShowGatheringGuide(skillLine, skill)
  local brackets, guide, hasCounts = ns.GatheringGuide(skillLine, skill)
  local entries = {}
  for _, bracket in ipairs(brackets) do
    table.insert(entries, { kind = "bracket", from = bracket.from, to = bracket.to, current = bracket.current })
    table.insert(entries, { kind = "zones", from = bracket.from, to = bracket.to, zones = bracket.zones,
                            hasCounts = hasCounts })
    for _, item in ipairs(bracket.items) do
      table.insert(entries, { kind = "gather", item = item.item, need = item.need, skill = skill })
    end
  end
  if guide.note then
    table.insert(entries, { kind = "note", text = guide.note })
  end
  scrollBox:SetDataProvider(CreateDataProvider(entries))
  setTotals(string.format("|cffffd100%s|r for your skill and where to find them", guide.noun),
    "Prices: the better of AH (after cut) and vendor")
  sourceText:SetText("Zones shown for your faction. Hover a zone line for the full list.")
end

function Panel:RefreshNow()
  if not frame or not frame:IsShown() or not scrollBox then
    return
  end

  local skillLine, info = ns.GetOpenProfession()
  if not skillLine then
    header:SetText(ns.TITLE)
    skillText:SetText("|cff909090Open a crafting profession to plan a route.|r")
    scrollBox:SetDataProvider(CreateDataProvider({}))
    setTotals("", "")
    current = nil
    return
  end

  local skill = info.skillLevel or 0
  local maxRank = info.maxSkillLevel or skill
  local name = ns.PROFESSION_NAMES[skillLine] or info.professionName or ""
  header:SetText(name)
  if frame.SetPortraitToAsset then
    local _, _, profession = ns.GetProfessionSkill(skillLine)
    pcall(frame.SetPortraitToAsset, frame, profession and profession.icon or ICON_TAB)
  end
  skillText:SetText(string.format("Skill |cffffffff%d|r / %d", skill, maxRank))

  -- Gathering professions get the where-to-go guide (Mining can switch to its
  -- smelting route).
  local gathering = ns.GATHERING[skillLine] ~= nil
  local showGuide = gathering and (not ns.RECIPES[skillLine] or gatherView[skillLine] ~= "craft")
  modeButton:SetShown(gathering and ns.RECIPES[skillLine] ~= nil)
  modeButton:SetText(showGuide and "Smelting route" or "Gathering guide")
  setCraftingControlsShown(not showGuide)
  if showGuide then
    self:ShowGatheringGuide(skillLine, skill)
    current = { skillLine = skillLine, skill = skill, gathering = true }
    return
  end

  if skill >= 300 then
    current = { skillLine = skillLine, skill = skill }
    scrollBox:SetDataProvider(CreateDataProvider({}))
    setTotals("|cff40c040Maxed out. Well done!|r", "")
    targetSlider:Hide()
    targetBox:Hide()
    return
  end
  targetSlider:Show()
  targetBox:Show()

  local target = chosenTarget(skillLine, skill, maxRank)
  if not current or current.skillLine ~= skillLine or current.skill ~= skill or current.gathering then
    targetSlider.updating = true
    targetSlider:Init(target, math.min(skill + 1, 299), 300, math.max(1, 300 - skill - 1), targetSlider.formatters)
    targetSlider.updating = false
  end
  if not targetBox:HasFocus() then
    targetBox:SetText(tostring(target))
  end

  -- Plan all three styles so they can be compared; show the chosen one.
  local chosen = ns.db.routeMode or "cheap"
  local result
  local compare = {}
  for _, option in ipairs(Planner.MODES) do
    local plan = Planner.Plan({
      skillLine = skillLine,
      from = skill,
      to = target,
      maxRank = maxRank,
      onlyKnown = ns.db.onlyKnown,
      mode = option.key,
    })
    compare[option.key] = plan
    if option.key == chosen then
      result = plan
    end
  end
  result = result or compare.cheap
  current = { skillLine = skillLine, skill = skill, maxRank = maxRank, target = target, result = result, name = name,
              compare = compare }

  local entries = {}
  if mode == "route" then
    entries = result.steps
  else
    for _, entry in ipairs(result.shopping) do
      table.insert(entries, { kind = "item", item = entry.item, count = entry.count })
    end
  end
  scrollBox:SetDataProvider(CreateDataProvider(entries), ScrollBoxConstants.RetainScrollPosition)

  if #result.steps == 0 then
    setTotals("|cff909090Nothing to plan.|r", "")
  else
    local reached = result.reached < target and string.format(" |cffff6060(stops at %d)|r", result.reached) or ""
    local toBuy = 0
    for _, entry in ipairs(missingShopping(result)) do
      toBuy = toBuy + (Prices.Buy(entry.item) or 0) * entry.count
    end
    local net = result.total >= 0 and ("Net cost " .. ns.Coins(result.total))
      or ("|cff40c040Net profit|r " .. ns.Coins(-result.total))
    setTotals(string.format("To %d: %s, ~%d crafts%s", target, net, result.crafts, reached),
      string.format("Materials %s  |  Sell back %s  |  To buy %s",
        ns.Money(result.materials), ns.Money(result.resale), ns.Money(toBuy)))
  end

  if not Prices.HasAuctionator() then
    sourceText:SetText("Auctionator not found: only vendor prices are used.")
  else
    sourceText:SetText("Prices from Auctionator. Scan the AH for fresher numbers.")
  end
  auctionatorButton:SetEnabled(Prices.HasAuctionator())
  updateTabs()
  -- Target, route style or options may have changed: the recipe list's
  -- "Leveling route" filter follows the guide.
  ns.Fire("ROUTE_CHANGED")
end

local queueRefresh = ns.Debounce(function() Panel:Refresh() end, 0.15)
ns.Listen("PRICES_CHANGED", queueRefresh)
ns.Listen("KNOWN_CHANGED", queueRefresh)
ns.Listen("SKILL_CHANGED", queueRefresh)
ns.Listen("ITEM_INFO", queueRefresh)
ns.On("BAG_UPDATE_DELAYED", queueRefresh)
ns.On("TRADE_SKILL_SHOW", queueRefresh)

--------------------------------------------------------------------------------
-- Building the panel
--------------------------------------------------------------------------------

local function createCheck(parent, text, tooltip, get, set)
  local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  check:SetSize(24, 24)
  local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  label:SetPoint("LEFT", check, "RIGHT", 2, 0)
  label:SetText(text)
  check:SetHitRectInsets(0, -label:GetStringWidth() - 4, 0, 0)
  check:SetChecked(get())
  check:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    Panel:Refresh()
  end)
  check:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(text)
    GameTooltip:AddLine(tooltip, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  check:SetScript("OnLeave", GameTooltip_Hide)
  return check
end

local function createButton(parent, text, width, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(width, 22)
  button:SetText(text)
  button:SetScript("OnClick", onClick)
  return button
end

local function createPanel()
  local ok
  ok, frame = pcall(CreateFrame, "Frame", "ProfessionSagePanel", ProfessionsFrame, "PortraitFrameTemplate")
  if not ok then
    frame = CreateFrame("Frame", "ProfessionSagePanel", ProfessionsFrame, "BackdropTemplate")
    frame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
  -- Leave room for the profession side tabs between the two frames.
  local gap = (tab and tab:GetWidth() or TAB_GAP) + 2
  frame:SetWidth(PANEL_WIDTH)
  frame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", gap, 0)
  frame:SetPoint("BOTTOMLEFT", ProfessionsFrame, "BOTTOMRIGHT", gap, 0)
  frame:EnableMouse(true)
  frame:Hide()
  if frame.SetTitle then
    frame:SetTitle(ns.TITLE)
  end
  if frame.CloseButton then
    frame.CloseButton:SetScript("OnClick", function() Panel:SetShown(false) end)
  end

  -- Background like Blizzard's panels.
  local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
  bg:SetPoint("TOPLEFT", 2, -21)
  bg:SetPoint("BOTTOMRIGHT", -2, 2)
  bg:SetColorTexture(0.07, 0.06, 0.05, 0.96)

  header = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  header:SetPoint("TOPLEFT", 64, -32)
  skillText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  skillText:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)

  targetLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  targetLabel:SetPoint("TOPLEFT", 16, -74)
  targetLabel:SetText("Target skill")

  targetSlider = CreateFrame("Frame", nil, frame, "MinimalSliderWithSteppersTemplate")
  targetSlider:SetWidth(180)
  targetSlider:SetPoint("LEFT", targetLabel, "RIGHT", 12, 0)
  targetSlider.formatters = {}  -- the number is the typeable box beside it
  targetSlider:Init(150, 1, 300, 299, targetSlider.formatters)

  -- The target as a number you can type.
  targetBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  targetBox:SetSize(36, 20)
  targetBox:SetPoint("LEFT", targetSlider, "RIGHT", 12, 0)
  targetBox:SetAutoFocus(false)
  targetBox:SetNumeric(true)
  targetBox:SetMaxLetters(3)
  targetBox:SetJustifyH("CENTER")
  local function applyTypedTarget(self)
    local value = tonumber(self:GetText())
    if current and current.skill and value then
      value = math.max(current.skill + 1, math.min(300, value))
      ns.char.targets[current.skillLine] = value
      targetSlider.updating = true
      targetSlider:SetValue(value)
      targetSlider.updating = false
    end
    self:ClearFocus()
    queueRefresh()
  end
  targetBox:SetScript("OnEnterPressed", applyTypedTarget)
  targetBox:SetScript("OnEditFocusLost", function(self)
    if current and ns.char.targets[current.skillLine] then
      self:SetText(tostring(ns.char.targets[current.skillLine]))
    end
  end)
  targetBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  targetSlider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
    if targetSlider.updating or not current then
      return
    end
    value = math.floor(value + 0.5)
    ns.char.targets[current.skillLine] = value
    targetBox:SetText(tostring(value))
    queueRefresh()
  end, targetSlider)

  -- Mining only: switch between the gathering guide and the smelting route.
  modeButton = createButton(frame, "Smelting route", 120, function()
    if current then
      gatherView[current.skillLine] = gatherView[current.skillLine] ~= "craft" and "craft" or nil
      Panel:Refresh()
    end
  end)
  modeButton:SetPoint("TOPRIGHT", -14, -34)
  modeButton:Hide()

  onlyKnownCheck = createCheck(frame, "Only recipes I know",
    "Plan with recipes you already know. Off: also suggests recipes from trainers and recipes you can buy on the auction house.",
    function() return ns.db.onlyKnown end, function(v) ns.db.onlyKnown = v end)
  onlyKnownCheck:SetPoint("TOPLEFT", 12, -96)

  useBagsCheck = createCheck(frame, "Count what I have",
    "Subtract materials in your bags and bank from the shopping list, and keep the route using them: materials you already bought count as paid for, so the plan doesn't switch recipes after you level up.",
    function() return ns.db.useBags end, function(v) ns.db.useBags = v end)
  useBagsCheck:SetPoint("TOPLEFT", 186, -96)

  routeButton = createButton(frame, "Route", 90, function() mode = "route"; Panel:Refresh() end)
  routeButton:SetPoint("TOPLEFT", 14, -126)
  shoppingButton = createButton(frame, "Shopping list", 104, function() mode = "shopping"; Panel:Refresh() end)
  shoppingButton:SetPoint("LEFT", routeButton, "RIGHT", 4, 0)

  -- Cheapest / Fastest / Balanced.
  local function modeLabel(key)
    for _, option in ipairs(Planner.MODES) do
      if option.key == key then
        return option.label
      end
    end
    return Planner.MODES[1].label
  end
  local function setRouteMode(key)
    ns.db.routeMode = key
    Panel:Refresh()
  end
  local okDropdown, dropdown = false, nil
  if MenuUtil then
    okDropdown, dropdown = pcall(CreateFrame, "DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
  end
  if okDropdown and dropdown then
    dropdown:SetWidth(112)
    dropdown:SetupMenu(function(_, root)
      for _, option in ipairs(Planner.MODES) do
        local radio = root:CreateRadio(option.label,
          function() return (ns.db.routeMode or "cheap") == option.key end,
          function() setRouteMode(option.key) end)
        if radio.SetTooltip then
          radio:SetTooltip(function(tooltip)
            GameTooltip_SetTitle(tooltip, option.label)
            GameTooltip_AddNormalLine(tooltip, option.tip)
          end)
        end
      end
    end)
    routeModeControl = dropdown
  else
    routeModeControl = createButton(frame, modeLabel(ns.db.routeMode), 112, function(self)
      local index = 1
      for i, option in ipairs(Planner.MODES) do
        if option.key == (ns.db.routeMode or "cheap") then
          index = i
        end
      end
      local nextOption = Planner.MODES[index % #Planner.MODES + 1]
      self:SetText(nextOption.label)
      setRouteMode(nextOption.key)
    end)
  end
  routeModeControl:SetPoint("TOPRIGHT", -14, -126)
  routeModeControl:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Route style")
    for _, option in ipairs(Planner.MODES) do
      GameTooltip:AddLine("|cffffd100" .. option.label .. ":|r " .. option.tip, 1, 1, 1, true)
    end
    -- The three routes to your target side by side.
    if current and current.compare then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(string.format("To %d:", current.target), 0.85, 0.7, 0.43)
      for _, option in ipairs(Planner.MODES) do
        local plan = current.compare[option.key]
        if plan then
          local money = plan.total >= 0 and ("cost " .. ns.Money(plan.total)) or ("|cff40c040profit|r " .. ns.Money(-plan.total))
          GameTooltip:AddDoubleLine(option.label, string.format("%s, ~%d crafts", money, plan.crafts), 1, 1, 1, 1, 1, 1)
        end
      end
    end
    GameTooltip:Show()
  end)
  routeModeControl:HookScript("OnLeave", GameTooltip_Hide)

  local inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
  inset:SetPoint("TOPLEFT", 10, -152)
  inset:SetPoint("BOTTOMRIGHT", -10, 88)

  scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", 4, -4)
  scrollBox:SetPoint("BOTTOMRIGHT", -20, 4)
  local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

  view = CreateScrollBoxListLinearView()
  view:SetElementExtent(ROW_HEIGHT)
  view:SetElementInitializer("Button", setupRow)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

  totalText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  totalText:SetPoint("BOTTOMLEFT", 16, 66)
  totalText:SetPoint("RIGHT", -16, 0)
  totalText:SetJustifyH("LEFT")
  totalText:SetWordWrap(false)
  totalSub = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  totalSub:SetPoint("BOTTOMLEFT", 16, 48)
  totalSub:SetPoint("RIGHT", -16, 0)
  totalSub:SetJustifyH("LEFT")
  totalSub:SetWordWrap(false)
  totalSub:SetTextColor(0.7, 0.7, 0.7)

  trackButton = createButton(frame, "Track materials", 130, function()
    if not current or not current.result then
      return
    end
    local items = missingShopping(current.result)
    if #items == 0 then
      ns.Print("You already have everything for this route.")
      return
    end
    -- The popup counts toward totals, so track what you have plus what's missing.
    local totals = {}
    for _, entry in ipairs(items) do
      table.insert(totals, { item = entry.item, count = entry.count + ns.GetItemCount(entry.item, true) })
    end
    ns.Tracker:Track(string.format("%s to %d", current.name, current.target), totals, "For your leveling route:")
  end)
  trackButton:SetPoint("BOTTOMLEFT", 12, 20)
  trackButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Track materials")
    GameTooltip:AddLine("Shows what you still need in a small window at the side of your screen, and ticks items off as you get them.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  trackButton:SetScript("OnLeave", GameTooltip_Hide)

  auctionatorButton = createButton(frame, "Send to Auctionator", 150, function()
    if not current or not current.result then
      return
    end
    local ok2, err = Prices.SendShoppingList(ns.TITLE, missingShopping(current.result))
    ns.Print(ok2 and ("Shopping list \"" .. ns.TITLE .. "\" created in Auctionator.") or err)
  end)
  auctionatorButton:SetPoint("BOTTOMRIGHT", -12, 20)

  sourceText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  sourceText:SetPoint("BOTTOM", 0, 6)

  frame:SetScript("OnShow", function()
    if tab then
      tab:SetChecked(true)
    end
    Panel:Refresh()
  end)
  frame:SetScript("OnHide", function()
    if tab then
      tab:SetChecked(false)
    end
  end)
end

function Panel:SetShown(shown)
  if not frame then
    return
  end
  ns.db.panelShown = shown and true or false
  frame:SetShown(shown)
end

function Panel:Toggle()
  self:SetShown(not (frame and frame:IsShown()))
end

--------------------------------------------------------------------------------
-- Side tab under the profession tabs
--------------------------------------------------------------------------------

local function anchorTab()
  if not tab then
    return
  end
  local last = ProfessionsFrame.ProfessionsOverviewTab
  for _, professionTab in ipairs(ProfessionsFrame.rightProfessionTabs or {}) do
    if professionTab:IsShown() then
      last = professionTab
    end
  end
  tab:ClearAllPoints()
  if last then
    tab:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -12)
  else
    tab:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 0, -60)
  end
end

local function createTab()
  local ok
  ok, tab = pcall(CreateFrame, "Frame", nil, ProfessionsFrame, "LargeSideTabButtonTemplate")
  if not ok then
    tab = CreateFrame("Button", nil, ProfessionsFrame)
    tab:SetSize(40, 40)
    tab.Icon = tab:CreateTexture(nil, "ARTWORK")
    tab.Icon:SetAllPoints()
    tab:SetScript("OnClick", function() Panel:Toggle() end)
  else
    tab.customMouseUpHandler = function(_, button, upInside)
      if button == "LeftButton" and upInside ~= false then
        Panel:Toggle()
      end
    end
  end
  tab.Icon:SetTexture(ICON_TAB)
  tab.SetChecked = function(self, checked)
    if self.SelectedTexture then
      self.SelectedTexture:SetShown(checked)
    end
  end
  tab:SetChecked(false)
  tab:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.TITLE)
    GameTooltip:AddLine("Leveling guide and shopping list", 1, 1, 1)
    GameTooltip:Show()
  end)
  tab:HookScript("OnLeave", GameTooltip_Hide)

  anchorTab()
  if type(ProfessionsFrame.RefreshRightTabs) == "function" then
    hooksecurefunc(ProfessionsFrame, "RefreshRightTabs", anchorTab)
  end
  ProfessionsFrame:HookScript("OnShow", anchorTab)
end

ns.OnProfessionsLoaded(function()
  createTab()
  createPanel()
  -- Only beside the crafting page, not Blizzard's professions overview.
  local page = ProfessionsFrame.CraftingPage
  page:HookScript("OnShow", function()
    tab:Show()
    if ns.db.panelShown then frame:Show() end
  end)
  page:HookScript("OnHide", function()
    tab:Hide()
    frame:Hide()
  end)
  tab:SetShown(page:IsShown())
  if ns.db.panelShown and page:IsShown() then
    frame:Show()
  end
end)
