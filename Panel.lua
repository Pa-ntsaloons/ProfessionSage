local _, ns = ...

local Prices, Planner = ns.Prices, ns.Planner

--------------------------------------------------------------------------------
-- Leveling guide: a panel beside Blizzard's profession window, opened from the
-- guide button (GuideButton.lua). Rows are drawn by PanelRows.lua.
--------------------------------------------------------------------------------

local Panel = {}
ns.Panel = Panel

local PANEL_WIDTH = 350
local ROW_HEIGHT = 24
local TAB_GAP = 40  -- room for the profession side tabs between the frames
local ICON_TAB = "Interface\\Icons\\INV_Misc_Book_09"
local MINING = 186

local frame, scrollBox, routeButton, shoppingButton
local header, skillText, targetSlider, onlyKnownCheck, useBagsCheck
local totalText, totalSub, sourceText, trackButton, auctionatorButton
local targetLabel, targetBox, modeButton, routeModeControl
local gatherView = {}  -- [skill line] = "craft" when Mining shows its smelting route
local mode = "route"
local current  -- { skillLine, skill, maxRank, target, result, gathering }

local function chosenTarget(skillLine, skill, maxRank)
  local saved = ns.char.targets[skillLine]
  if saved and saved > skill then
    return math.min(saved, ns.MAX_SKILL)
  end
  if maxRank and maxRank > skill then
    return maxRank
  end
  return math.min(ns.MAX_SKILL, skill + 25)
end

-- The route the guide would show for this profession, with its target, or nil
-- when there's nothing to plan. info is C_TradeSkillUI.GetBaseProfessionInfo().
function Panel.RouteFor(skillLine, info)
  local skill = info.skillLevel or 0
  local maxRank = info.maxSkillLevel or skill
  -- Herbalism, Fishing and Skinning recipes don't level them: no route.
  if skill >= ns.MAX_SKILL or not ns.RECIPES[skillLine] or (ns.GATHERING[skillLine] and skillLine ~= MINING) then
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

-- Shows the target controls set to this profession's target, and returns it.
-- The slider is only reset when the profession, skill or guide kind changed.
local function syncTarget(skillLine, skill, maxRank, gathering)
  for _, control in ipairs({ targetLabel, targetSlider, targetBox }) do
    control:Show()
  end
  local target = chosenTarget(skillLine, skill, maxRank)
  if not current or current.skillLine ~= skillLine or current.skill ~= skill
    or (current.gathering and true or false) ~= gathering then
    targetSlider.updating = true
    targetSlider:Init(target, math.min(skill + 1, ns.MAX_SKILL - 1), ns.MAX_SKILL,
      math.max(1, ns.MAX_SKILL - skill - 1), targetSlider.formatters)
    targetSlider.updating = false
  end
  if not targetBox:HasFocus() then
    targetBox:SetText(tostring(target))
  end
  return target
end

-- The gathering guide as a route to your target: each skill range with where
-- to go and what to gather, and a "Train" step wherever a rank cap is in the
-- way (Apprentice stops at 75, Journeyman at 150, Expert at 225).
local function gatheringEntries(skillLine, skill, maxRank, target)
  local brackets, guide, hasCounts = ns.GatheringGuide(skillLine, skill)
  local caps = {}
  for _, step in ipairs(ns.RANK_STEPS) do
    if step.at >= skill and step.at < target and maxRank <= step.at then
      table.insert(caps, step)
    end
  end
  local entries = {}
  local nextCap = 1
  local function trainUpTo(at)
    while caps[nextCap] and caps[nextCap].at <= at do
      table.insert(entries, { kind = "train", rank = caps[nextCap].name, at = caps[nextCap].at, skillLine = skillLine })
      nextCap = nextCap + 1
    end
  end

  for index, bracket in ipairs(brackets) do
    if bracket.from >= target then
      break
    end
    local to = math.min(bracket.to, target)
    trainUpTo(math.max(bracket.from, skill))  -- a rank you need before this range starts
    table.insert(entries, { kind = "bracket", from = bracket.from, to = to, current = bracket.current,
                            skill = skill, maxRank = maxRank, skillLine = skillLine, items = bracket.items,
                            nextBracket = brackets[index + 1] })
    table.insert(entries, { kind = "zones", from = bracket.from, to = to, zones = bracket.zones,
                            hasCounts = hasCounts })
    for _, item in ipairs(bracket.items) do
      if item.need < target then
        table.insert(entries, { kind = "gather", item = item.item, need = item.need, skill = skill })
      end
    end
    trainUpTo(to)  -- ranks you reach inside this range
  end
  trainUpTo(target)
  if guide.note then
    table.insert(entries, { kind = "note", text = guide.note })
  end
  return entries, guide
end

function Panel:ShowGatheringGuide(skillLine, skill, maxRank, target)
  local entries, guide = gatheringEntries(skillLine, skill, maxRank, target)
  scrollBox:SetDataProvider(CreateDataProvider(entries))
  setTotals(string.format("|cffffd100%s|r from %d to %d: where to go and what to gather", guide.noun, skill, target),
    "Prices: the better of AH (after cut) and vendor")
  sourceText:SetText("Zones shown for your faction. Hover a zone line for the full list.")
end

-- Plans all route styles so they can be compared; returns the chosen one and
-- all of them by key.
local function planRoutes(skillLine, skill, maxRank, target)
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
  return result or compare.cheap, compare
end

local function showRouteTotals(result, target)
  if #result.steps == 0 then
    setTotals("|cff909090Nothing to plan.|r", "")
    return
  end
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

function Panel:RefreshNow()
  if not frame or not frame:IsShown() or not scrollBox then
    return
  end

  local skillLine, info = ns.GetOpenProfession()
  if skillLine then
    ns.char.lastGuideProfession = skillLine
  end
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
  local showGuide = gathering and (skillLine ~= MINING or gatherView[skillLine] ~= "craft")
  modeButton:SetShown(skillLine == MINING)
  modeButton:SetText(showGuide and "Smelting route" or "Gathering guide")
  setCraftingControlsShown(not showGuide)
  if showGuide and skill < ns.MAX_SKILL then
    -- Same target as a crafting route: the gathering guide is a route to it.
    local target = syncTarget(skillLine, skill, maxRank, true)
    current = { skillLine = skillLine, skill = skill, maxRank = maxRank, target = target, gathering = true }
    self:ShowGatheringGuide(skillLine, skill, maxRank, target)
    return
  end

  if skill >= ns.MAX_SKILL then
    current = { skillLine = skillLine, skill = skill }
    scrollBox:SetDataProvider(CreateDataProvider({}))
    setTotals("|cff40c040Maxed out. Well done!|r", "")
    targetSlider:Hide()
    targetBox:Hide()
    return
  end

  local target = syncTarget(skillLine, skill, maxRank, false)
  local result, compare = planRoutes(skillLine, skill, maxRank, target)
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
  showRouteTotals(result, target)

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

-- Blizzard's profession side tabs sit between the window and the guide:
-- leave room for them, measured from where they actually end.
local function sideTabsGap()
  local right = ProfessionsFrame:GetRight()
  local edge
  local tabs = { ProfessionsFrame.ProfessionsOverviewTab }
  for _, professionTab in ipairs(ProfessionsFrame.rightProfessionTabs or {}) do
    table.insert(tabs, professionTab)
  end
  for _, sideTab in ipairs(tabs) do
    local tabRight = sideTab and sideTab:IsShown() and sideTab:GetRight()
    if tabRight and (not edge or tabRight > edge) then
      edge = tabRight
    end
  end
  if right and edge and edge > right then
    return math.ceil(edge - right) + 4
  end
  return TAB_GAP + 14
end

local function placePanel()
  frame:ClearAllPoints()
  local gap = sideTabsGap()
  frame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", gap, 0)
  frame:SetPoint("BOTTOMLEFT", ProfessionsFrame, "BOTTOMRIGHT", gap, 0)
end

-- Target skill: a slider and a box you can type a number in.
local function createTargetControls()
  targetLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  targetLabel:SetPoint("TOPLEFT", 16, -74)
  targetLabel:SetText("Target skill")

  targetSlider = CreateFrame("Frame", nil, frame, "MinimalSliderWithSteppersTemplate")
  targetSlider:SetWidth(180)
  targetSlider:SetPoint("LEFT", targetLabel, "RIGHT", 12, 0)
  targetSlider.formatters = {}  -- the number is the typeable box beside it
  targetSlider:Init(150, 1, ns.MAX_SKILL, ns.MAX_SKILL - 1, targetSlider.formatters)

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
      value = math.max(current.skill + 1, math.min(ns.MAX_SKILL, value))
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
end

-- Route style: Most profit / Fewest crafts / Balanced. A dropdown when the
-- client has one, otherwise a button that cycles through them.
local function createRouteModeControl()
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
      ns.TooltipHeading(GameTooltip, string.format("To %d:", current.target))
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
end

local function createList()
  local inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
  inset:SetPoint("TOPLEFT", 10, -152)
  inset:SetPoint("BOTTOMRIGHT", -10, 88)

  scrollBox = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", 4, -4)
  scrollBox:SetPoint("BOTTOMRIGHT", -20, 4)
  local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(ROW_HEIGHT)
  view:SetElementInitializer("Button", ns.PanelRows.Setup)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
end

local function createFooter()
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
    local ok, err = Prices.SendShoppingList(ns.TITLE, missingShopping(current.result))
    ns.Print(ok and ("Shopping list \"" .. ns.TITLE .. "\" created in Auctionator.") or err)
  end)
  auctionatorButton:SetPoint("BOTTOMRIGHT", -12, 20)

  sourceText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  sourceText:SetPoint("BOTTOM", 0, 6)
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
  frame:SetWidth(PANEL_WIDTH)
  placePanel()
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

  createTargetControls()

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

  createRouteModeControl()
  createList()
  createFooter()

  frame:SetScript("OnShow", function()
    placePanel()
    ns.Fire("GUIDE_SHOWN", true)
    Panel:Refresh()
  end)
  frame:SetScript("OnHide", function()
    ns.Fire("GUIDE_SHOWN", false)
  end)
end

--------------------------------------------------------------------------------
-- Showing and hiding
--------------------------------------------------------------------------------

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

function Panel:IsShown()
  return frame ~= nil and frame:IsShown()
end

-- Moves the panel clear of Blizzard's side tabs (they change with the page).
function Panel:Place()
  if frame and frame:IsShown() then
    placePanel()
  end
end

ns.OnProfessionsLoaded(function()
  createPanel()
  -- The guide sits beside the crafting page, not Blizzard's professions overview.
  local page = ProfessionsFrame.CraftingPage
  page:HookScript("OnShow", function()
    if ns.db.panelShown then frame:Show() end
  end)
  page:HookScript("OnHide", function()
    frame:Hide()
  end)
  if ns.db.panelShown and page:IsShown() then
    frame:Show()
  end
end)
