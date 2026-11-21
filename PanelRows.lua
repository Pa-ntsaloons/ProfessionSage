local _, ns = ...

local Recipes, Prices = ns.Recipes, ns.Prices

--------------------------------------------------------------------------------
-- Rows of the leveling guide: one drawing function per kind of entry.
--
--   craft, learn, train, stuck      crafting route steps (from the Planner)
--   bracket, zones, gather, note    gathering guide
--   item                            shopping list
--------------------------------------------------------------------------------

local PanelRows = {}
ns.PanelRows = PanelRows

local ICON_LEARN = "Interface\\Icons\\INV_Scroll_03"
local ICON_TRAIN = "Interface\\Icons\\INV_Misc_Book_11"
local ICON_STUCK = "Interface\\Icons\\INV_Misc_QuestionMark"
local ICON_UNKNOWN = 134400
local MINING = 186

--------------------------------------------------------------------------------
-- Tooltips
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
    GameTooltip:AddDoubleLine(string.format("|T%s:0|t %s x%d", icon or ICON_UNKNOWN, name, reagent.count * step.crafts),
      price and ns.Money(price * reagent.count * step.crafts) or "|cff808080no price|r", 1, 1, 1, 1, 1, 1)
  end
  GameTooltip:AddLine(" ")
  ns.TooltipPair(GameTooltip, "Materials", ns.Money(step.cost))
  if step.resale > 0 then
    local _, source = Prices.Sell(recipe.item)
    ns.TooltipPair(GameTooltip, source == "vendor" and "Sell back (vendor)" or "Sell back (AH, after cut)",
      ns.Money(step.resale))
  end
  GameTooltip:AddDoubleLine(step.net >= 0 and "Net cost" or "Net profit", ns.Money(math.abs(step.net)), 1, 0.82, 0,
    step.net >= 0 and 1 or 0.25, 1, step.net >= 0 and 1 or 0.25)
  ns.AddRecipeTooltip(GameTooltip, recipe, step.crafts)
  if Recipes.IsKnown(recipe) then
    GameTooltip:AddLine("Click to show this recipe.", 0.4, 0.8, 1)
  end
  GameTooltip:Show()
end

-- Gathering guide header: the rank steps inside a skill range that you
-- haven't trained past yet.
local function bracketCaps(entry)
  local caps = {}
  for _, step in ipairs(ns.RANK_STEPS) do
    if step.at > entry.from and step.at <= entry.to and (entry.maxRank or 0) <= step.at then
      table.insert(caps, step)
    end
  end
  return caps
end

local function bracketTooltip(owner, entry, caps)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(string.format("Skill %d - %d", entry.from, entry.to))
  GameTooltip:AddLine(string.format("Gather in the zones below until your skill reaches %d.", entry.to), 1, 1, 1, true)
  if entry.current then
    GameTooltip:AddLine(string.format("Your skill: %d (this rank goes up to %d).", entry.skill, entry.maxRank or entry.skill),
      0.25, 0.75, 0.25, true)
  end

  local newItems = {}
  for _, item in ipairs(entry.items or {}) do
    if item.need > entry.from then
      table.insert(newItems, string.format("%s (%d)", ns.ItemName(item.item) or ("item " .. item.item), item.need))
    end
  end
  if #newItems > 0 then
    GameTooltip:AddLine("New in this range: " .. table.concat(newItems, ", "), 0.8, 0.8, 0.8, true)
  end

  for _, cap in ipairs(caps) do
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format("At %d: learn %s", cap.at, cap.name), 1, 0.82, 0)
    ns.Sources.AddRankLines(GameTooltip, entry.skillLine, cap.rank, cap.name, cap.at)
  end

  if #caps == 0 then
    GameTooltip:AddLine(" ")
    local nextBracket = entry.nextBracket
    if entry.to >= ns.MAX_SKILL then
      GameTooltip:AddLine("300 is the highest skill.", 0.8, 0.8, 0.8, true)
    elseif nextBracket then
      local zones = {}
      for index = 1, math.min(3, #nextBracket.zones) do
        table.insert(zones, nextBracket.zones[index].name)
      end
      GameTooltip:AddLine(string.format("Nothing to train here. At %d, move on to %s.", entry.to,
        table.concat(zones, ", ")), 0.8, 0.8, 0.8, true)
    else
      GameTooltip:AddLine("Nothing to train in this range.", 0.8, 0.8, 0.8, true)
    end
  end
  GameTooltip:Show()
end

-- Shows a tooltip built by fill(tooltip) when the row is hovered.
local function onHover(row, fill)
  row:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    fill(GameTooltip)
    GameTooltip:Show()
  end)
end

--------------------------------------------------------------------------------
-- Drawing each kind of row
--------------------------------------------------------------------------------

local draw = {}

function draw.craft(row, entry)
  local recipe = entry.recipe
  local color = ns.DIFFICULTY_COLORS[entry.difficulty] or ns.DIFFICULTY_COLORS.yellow
  row.icon:SetTexture(Recipes.Icon(recipe) or ICON_UNKNOWN)
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
end

function draw.learn(row, entry)
  local recipe = entry.recipe
  row.icon:SetTexture(ICON_LEARN)
  row.left:SetText("|cff66bbffLearn:|r " .. Recipes.Name(recipe))
  if entry.how == "trainer" then
    row.right:SetText("|cffa0a0a0Trainer|r")
  else
    local kind = entry.how == "vendor" and "Vendor" or "AH"
    row.right:SetText(string.format("|cffa0a0a0%s|r  %s", kind, ns.Money(entry.cost)))
  end
  onHover(row, function(tooltip)
    if entry.how == "trainer" then
      tooltip:SetText("Learn " .. Recipes.Name(recipe))
      tooltip:AddLine(string.format("Taught by %s trainers from skill %d%s.",
        ns.PROFESSION_NAMES[recipe.skillLine] or "profession", recipe.learn,
        recipe.learnExact and "" or " (about; exact once you've seen it at a trainer)"), 1, 1, 1, true)
      ns.Sources.AddTrainerTooltip(tooltip, recipe.skillLine, ns.Sources.RankForSkill(recipe.learn))
    else
      tooltip:SetItemByID(recipe.recipeItem)
      tooltip:AddLine(" ")
      ns.TooltipPair(tooltip, entry.how == "vendor" and "Vendor price" or "Auction price", ns.Coins(entry.cost))
      ns.Sources.AddTooltip(tooltip, recipe.recipeItem)
    end
  end)
end

-- Learning the next rank: from a trainer, or a book or quest for the
-- secondary professions. Click for a waypoint.
function draw.train(row, entry)
  local Sources = ns.Sources
  row.icon:SetTexture(ICON_TRAIN)
  local skillLine = entry.skillLine
  local rankNumber = Sources.RankNumber(entry.rank)
  local special = skillLine and Sources.SpecialRank(skillLine, rankNumber)
  local trainers = skillLine and Sources.RankTrainers(skillLine, rankNumber)
  local spot = skillLine and Sources.RankSpot(skillLine, rankNumber)
  if special then
    row.left:SetText(special.book and string.format("|cffffd100%s:|r read %s", entry.rank, special.name)
      or string.format("|cffffd100%s:|r quest \"%s\"", entry.rank, special.quest))
  elseif trainers and #trainers == 1 then
    row.left:SetText(string.format("|cffffd100Train %s:|r %s", entry.rank, trainers[1].name))
  else
    row.left:SetText(string.format("|cffffd100Train %s|r", entry.rank))
  end
  row.right:SetText(string.format("|cffa0a0a0at %d|r", entry.at))
  if spot then
    row:SetScript("OnClick", function()
      Sources.SetWaypoint(spot)
    end)
  end
  onHover(row, function(tooltip)
    if skillLine then
      Sources.AddRankTooltip(tooltip, skillLine, rankNumber, entry.rank, entry.at)
    else
      tooltip:SetText("Train " .. entry.rank)
    end
  end)
end

function draw.stuck(row, entry)
  local mining = entry.skillLine == MINING
  row.icon:SetTexture(ICON_STUCK)
  row.icon:SetDesaturated(true)
  row.left:SetText(string.format(mining and "|cff909090Mine ore from skill %d|r" or "|cff909090No priced recipe from skill %d|r",
    entry.at))
  row.right:SetText("")
  onHover(row, function(tooltip)
    tooltip:SetText("Route stops here")
    if mining then
      tooltip:AddLine("Smelting can't take you further at this skill. Mine ore nodes to keep leveling; smelting picks up again at higher skill.", 1, 1, 1, true)
    else
      tooltip:AddLine("None of the recipes that still give skill-ups here have prices for all their materials. Scan the auction house with Auctionator, or turn off \"Only recipes I know\".", 1, 1, 1, true)
    end
  end)
end

function draw.bracket(row, entry)
  row.icon:SetTexture(nil)
  row.left:SetText(string.format("|cffffd100Skill %d - %d|r%s", entry.from, entry.to,
    entry.current and string.format("  |cff40c040(your skill: %d)|r", entry.skill or 0) or ""))
  row.right:SetText("")
  local caps = bracketCaps(entry)
  local spot = caps[1] and ns.Sources.RankSpot(entry.skillLine, caps[1].rank)
  if spot then
    row:SetScript("OnClick", function()
      ns.Sources.SetWaypoint(spot)
    end)
  end
  row:SetScript("OnEnter", function(self)
    bracketTooltip(self, entry, caps)
  end)
end

function draw.zones(row, entry)
  row.icon:SetTexture(nil)
  local names = {}
  for _, zone in ipairs(entry.zones) do
    table.insert(names, zone.nodes > 0 and string.format("%s |cff40c040(%d)|r", zone.name, zone.nodes) or zone.name)
  end
  row.left:SetText("|cffc8c8c8" .. table.concat(names, ", ") .. "|r")
  row.right:SetText("")
  onHover(row, function(tooltip)
    tooltip:SetText(string.format("Where to go at %d - %d", entry.from, entry.to))
    for _, zone in ipairs(entry.zones) do
      if zone.nodes > 0 then
        tooltip:AddDoubleLine(zone.name, string.format("%d nodes found", zone.nodes), 1, 1, 1, 0.25, 0.75, 0.25)
      else
        tooltip:AddLine(zone.name, 1, 1, 1)
      end
    end
    tooltip:AddLine(" ")
    if entry.hasCounts then
      tooltip:AddLine("Sorted by the nodes for this bracket you've found there (GatherMate2).", 0.7, 0.7, 0.7, true)
    elseif ns.HasGatherMate() then
      tooltip:AddLine("Zones will sort by the nodes you find as GatherMate2 records them.", 0.7, 0.7, 0.7, true)
    else
      tooltip:AddLine("Install GatherMate2 to sort zones by the nodes you've found.", 0.7, 0.7, 0.7, true)
    end
  end)
end

function draw.gather(row, entry)
  local name, icon = ns.ItemLabel(entry.item)
  row.icon:SetTexture(icon or ICON_UNKNOWN)
  local locked = entry.skill and entry.need > entry.skill
  row.icon:SetDesaturated(locked)
  row.left:SetText(name .. (locked and string.format(" |cff808080(needs %d)|r", entry.need) or ""))
  local price, source = Prices.Sell(entry.item)
  row.right:SetText(price and (ns.Money(price) .. (source == "vendor" and " |cffa0a0a0v|r" or "")) or "|cff808080-|r")
  onHover(row, function(tooltip)
    tooltip:SetItemByID(entry.item)
    tooltip:AddLine(" ")
    ns.TooltipPair(tooltip, "Skill needed", tostring(entry.need))
    local auction = Prices.Auction(entry.item)
    if auction then
      ns.TooltipPair(tooltip, "Auction price", ns.Coins(auction))
    end
    local vendor = select(11, ns.GetItemInfo(entry.item))
    if vendor and vendor > 0 then
      ns.TooltipPair(tooltip, "Vendor price", ns.Coins(vendor))
    end
  end)
end

function draw.note(row, entry)
  row.icon:SetTexture(ICON_STUCK)
  row.icon:SetDesaturated(true)
  row.left:SetText("|cff909090" .. entry.text .. "|r")
  row.right:SetText("")
  onHover(row, function(tooltip)
    tooltip:SetText("Good to know")
    tooltip:AddLine(entry.text, 1, 1, 1, true)
  end)
end

function draw.item(row, entry)
  local name, icon = ns.ItemLabel(entry.item)
  local have = ns.HaveCount(entry.item)
  local missing = math.max(0, entry.count - have)
  row.icon:SetTexture(icon or ICON_UNKNOWN)
  -- Still needed and your other characters have some (Syndicator).
  local alts = missing > 0 and ns.AltCounts(entry.item) or 0
  row.left:SetText(name .. (alts > 0 and string.format(" |cff8fb8ff(alts %d)|r", alts) or ""))
  local countText = missing == 0 and string.format("|cff40c040%d/%d|r", entry.count, entry.count)
    or (have > 0 and string.format("%d |cffa0a0a0(have %d)|r", missing, have) or tostring(missing))
  local price = Prices.Buy(entry.item)
  row.right:SetText(countText .. "  " .. (missing > 0 and (price and ns.Money(price * missing) or "|cff808080?|r") or ""))
  onHover(row, function(tooltip)
    tooltip:SetItemByID(entry.item)
    Prices.AddBuyLine(tooltip, entry.item)
    ns.AddAltLines(tooltip, entry.item)
  end)
end

--------------------------------------------------------------------------------
-- Layout: rank training is a section header (no indent, gold band, a line
-- above), learning a recipe sits one step in (blue band), crafting further in.
-- The gathering guide follows the same pattern: zones in, items further in.
--------------------------------------------------------------------------------

local ROW_STYLES = {
  train = { indent = 0, band = { 1, 0.82, 0, 0.13 }, rule = { 1, 0.82, 0, 0.45 } },
  learn = { indent = 10, band = { 0.4, 0.73, 1, 0.07 } },
  craft = { indent = 22 },
  zones = { indent = 10 },
  gather = { indent = 22 },
}
local PLAIN_ROW = { indent = 0 }

local function showColor(texture, color)
  if color then
    texture:SetColorTexture(unpack(color))
    texture:Show()
  else
    texture:Hide()
  end
end

local function styleRow(row, kind)
  local style = ROW_STYLES[kind] or PLAIN_ROW
  row.icon:ClearAllPoints()
  row.icon:SetPoint("LEFT", 4 + style.indent, 0)
  showColor(row.band, style.band)
  showColor(row.rule, style.rule)
end

local function buildRow(row)
  row.band = row:CreateTexture(nil, "BACKGROUND")
  row.band:SetAllPoints()
  row.rule = row:CreateTexture(nil, "BORDER")
  row.rule:SetPoint("TOPLEFT")
  row.rule:SetPoint("TOPRIGHT")
  row.rule:SetHeight(1)
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

-- The scroll list's initializer: rows are reused, so everything is reset.
function PanelRows.Setup(row, entry)
  if not row.icon then
    buildRow(row)
  end
  row.icon:SetDesaturated(false)
  row:SetScript("OnClick", nil)
  row:SetScript("OnEnter", nil)
  styleRow(row, entry.kind)
  local drawRow = draw[entry.kind]
  if drawRow then
    drawRow(row, entry)
  end
end
