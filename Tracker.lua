local _, ns = ...

--------------------------------------------------------------------------------
-- Materials popup: a small window at the side of the screen listing what you
-- still need. It stays up (even across reloads) until you have everything or
-- close it, and ticks items off as they land in your bags.
--------------------------------------------------------------------------------

local Tracker = {}
ns.Tracker = Tracker

local WIDTH = 250
local ROW_HEIGHT = 18

local frame = CreateFrame("Frame", "ProfessionSageTracker", UIParent, "BackdropTemplate")
frame:SetSize(WIDTH, 80)
frame:SetFrameStrata("MEDIUM")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetBackdrop({
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 14,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
frame:SetBackdropColor(0.05, 0.05, 0.05, 0.88)
frame:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
frame:Hide()

frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, _, x, y = self:GetPoint(1)
  ns.db.tracker = { point = point, x = x, y = y }
end)

local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
title:SetPoint("TOPLEFT", 10, -9)
title:SetPoint("RIGHT", -26, 0)
title:SetJustifyH("LEFT")
title:SetWordWrap(false)

local subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
subtitle:SetPoint("RIGHT", -10, 0)
subtitle:SetJustifyH("LEFT")
subtitle:SetTextColor(0.75, 0.75, 0.75)

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetSize(22, 22)
close:SetPoint("TOPRIGHT", -2, -2)
close:SetScript("OnClick", function()
  Tracker:Clear()
end)

local footer = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
footer:SetPoint("BOTTOMLEFT", 10, 10)
footer:SetJustifyH("LEFT")

local sendButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
sendButton:SetSize(84, 20)
sendButton:SetPoint("BOTTOMRIGHT", -8, 6)
sendButton:SetText("Auctionator")
sendButton:SetScript("OnClick", function()
  Tracker:SendToAuctionator()
end)
sendButton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText("Send to Auctionator")
  GameTooltip:AddLine("Creates a \"Profession Sage\" shopping list with what you still need.", 1, 1, 1, true)
  GameTooltip:Show()
end)
sendButton:SetScript("OnLeave", GameTooltip_Hide)

local rows = {}

local function getRow(index)
  local row = rows[index]
  if row then
    return row
  end
  row = CreateFrame("Frame", nil, frame)
  row:SetSize(WIDTH - 20, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 10, -40 - (index - 1) * ROW_HEIGHT)
  row:EnableMouse(true)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(15, 15)
  row.icon:SetPoint("LEFT")

  row.count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.count:SetPoint("RIGHT")
  row.count:SetJustifyH("RIGHT")

  row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
  row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  row:SetScript("OnEnter", function(self)
    if self.item then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetItemByID(self.item)
      local price, source = ns.Prices.Buy(self.item)
      if price then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(source == "vendor" and "Vendor price" or "Auction price", ns.Coins(price), 1, 0.82, 0, 1, 1, 1)
      end
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", GameTooltip_Hide)

  rows[index] = row
  return row
end

--------------------------------------------------------------------------------

local finishedAt

-- Items still missing: list of { item, need, have, missing }.
function Tracker:Missing()
  local shopping = ns.char and ns.char.shopping
  if not shopping then
    return {}
  end
  local list = {}
  for _, entry in ipairs(shopping.items) do
    local have = ns.GetItemCount(entry.item, true) or 0
    if have < entry.count then
      table.insert(list, { item = entry.item, need = entry.count, have = have, missing = entry.count - have })
    end
  end
  return list
end

function Tracker:Refresh()
  local shopping = ns.char and ns.char.shopping
  if not shopping then
    frame:Hide()
    return
  end

  local missing = self:Missing()
  title:SetText(shopping.title or "Materials needed")

  for _, row in ipairs(rows) do
    row:Hide()
  end

  if #missing == 0 then
    subtitle:SetText("|cff40c040All materials collected!|r")
    footer:SetText("")
    sendButton:Hide()
    frame:SetHeight(48)
    frame:Show()
    if not finishedAt then
      finishedAt = GetTime()
      C_Timer.After(6, function()
        if finishedAt and #Tracker:Missing() == 0 then
          Tracker:Clear()
        end
      end)
    end
    return
  end
  finishedAt = nil

  subtitle:SetText(shopping.subtitle or "Still to get:")
  local cost, unpriced = 0, false
  for index, entry in ipairs(missing) do
    local row = getRow(index)
    local name, icon = ns.ItemLabel(entry.item)
    row.item = entry.item
    row.icon:SetTexture(icon or 134400)
    row.name:SetText(name)
    row.count:SetText(string.format("|cffff6060%d|r / %d", entry.have, entry.need))
    row:Show()
    local price = ns.Prices.Buy(entry.item)
    if price then
      cost = cost + price * entry.missing
    else
      unpriced = true
    end
  end
  footer:SetText("Cost: " .. ns.Money(cost) .. (unpriced and " |cff808080+?|r" or ""))
  sendButton:SetShown(ns.Prices.HasAuctionator())
  frame:SetHeight(40 + #missing * ROW_HEIGHT + 30)
  frame:Show()
end

-- Starts tracking. items: list of { item, count } (total needed, not missing).
function Tracker:Track(titleText, items, subtitleText)
  ns.char.shopping = { title = titleText, subtitle = subtitleText, items = items }
  finishedAt = nil
  self:Refresh()
end

function Tracker:Clear()
  ns.char.shopping = nil
  finishedAt = nil
  frame:Hide()
end

function Tracker:IsTracking(titleText)
  return ns.char.shopping ~= nil and (titleText == nil or ns.char.shopping.title == titleText)
end

function Tracker:SendToAuctionator()
  local list = {}
  for _, entry in ipairs(self:Missing()) do
    table.insert(list, { item = entry.item, count = entry.missing })
  end
  local ok, err = ns.Prices.SendShoppingList(ns.TITLE, list)
  if ok then
    ns.Print("Shopping list \"" .. ns.TITLE .. "\" created in Auctionator.")
  else
    ns.Print(err)
  end
end

local refresh = ns.Debounce(function() Tracker:Refresh() end, 0.2)
ns.On("BAG_UPDATE_DELAYED", refresh)
ns.Listen("ITEM_INFO", refresh)
ns.Listen("PRICES_CHANGED", refresh)

ns.Listen("LOGIN", function()
  local saved = ns.db.tracker
  frame:ClearAllPoints()
  frame:SetPoint(saved.point or "RIGHT", UIParent, saved.point or "RIGHT", saved.x or -60, saved.y or 120)
  Tracker:Refresh()
end)
