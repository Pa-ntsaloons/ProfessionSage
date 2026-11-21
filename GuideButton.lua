local _, ns = ...

--------------------------------------------------------------------------------
-- Guide button: in the profession window's title bar, next to the close
-- button. On a profession it shows or hides the guide; on the professions
-- overview it opens your last profession with the guide.
--------------------------------------------------------------------------------

local Panel = ns.Panel

local BUTTON_SIZE = 20  -- fits the title bar
local ICON = "Interface\\Icons\\INV_Misc_Book_09"

local button

-- The profession the overview button opens: the last one the guide showed,
-- or your first one.
local function guideProfession()
  local professions = ns.GetPlayerProfessions()
  for _, profession in ipairs(professions) do
    if profession.skillLine == ns.char.lastGuideProfession then
      return profession
    end
  end
  return professions[1]
end

-- Always in the title bar, left of the close button (and of the maximize
-- button when the window has one), so it never moves between pages.
local function anchorButton()
  if not button then
    return
  end
  Panel:Place()
  local page = ProfessionsFrame.CraftingPage
  button.overview = not (page and page:IsShown())
  local close = ProfessionsFrame.CloseButton
  local maximize = ProfessionsFrame.MaximizeMinimize
  local nextTo = (maximize and maximize:IsShown() and maximize) or close
  button:ClearAllPoints()
  if nextTo then
    button:SetPoint("RIGHT", nextTo, "LEFT", -10, 0)  -- a gap, so it's hard to hit the wrong one
  else
    button:SetPoint("TOPRIGHT", ProfessionsFrame, "TOPRIGHT", -28, -1)
  end
  -- Draw above the title bar and the page under it.
  local above = nextTo or ProfessionsFrame
  button:SetFrameStrata(above:GetFrameStrata())
  button:SetFrameLevel(math.max(ProfessionsFrame:GetFrameLevel() + 50, above:GetFrameLevel() + 10,
    page and page:GetFrameLevel() + 10 or 0))
  button:SetChecked(Panel:IsShown())
  button:Show()
end

local function openFromOverview()
  local profession = guideProfession()
  if not profession then
    ns.Print("Learn a profession first: the guide plans routes for crafting and gathering professions.")
    return
  end
  ns.db.panelShown = true
  if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
    local ok = pcall(C_TradeSkillUI.OpenTradeSkill, profession.skillLine)
    if ok then
      return
    end
  end
  ns.Print(string.format("Open %s from the professions window to see the guide.", profession.name or "a profession"))
end

local function createButton()
  button = CreateFrame("Button", nil, ProfessionsFrame)
  button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
  button:RegisterForClicks("LeftButtonUp")

  button.Icon = button:CreateTexture(nil, "ARTWORK")
  button.Icon:SetAllPoints()
  button.Icon:SetTexture(ICON)
  button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)
  border:SetAtlas("ui-hud-minimap-button-border", false)
  if not border:GetAtlas() then
    border:Hide()
  end

  -- Lit while the guide is open (not on the overview, where it opens one).
  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  button.SelectedTexture = button:CreateTexture(nil, "OVERLAY", nil, 1)
  button.SelectedTexture:SetAllPoints()
  button.SelectedTexture:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  button.SelectedTexture:SetBlendMode("ADD")
  button.SetChecked = function(self, checked)
    self.SelectedTexture:SetShown(checked and not self.overview)
  end

  button:SetScript("OnClick", function(self)
    if self.overview then
      openFromOverview()
    else
      Panel:Toggle()
    end
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.TITLE)
    if self.overview then
      local profession = guideProfession()
      GameTooltip:AddLine(profession and string.format("Open %s with the leveling guide.", profession.name)
        or "Leveling guide and shopping list", 1, 1, 1, true)
    else
      GameTooltip:AddLine("Leveling guide and shopping list", 1, 1, 1)
    end
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)

  anchorButton()
  button:SetChecked(Panel:IsShown())
  if type(ProfessionsFrame.RefreshRightTabs) == "function" then
    hooksecurefunc(ProfessionsFrame, "RefreshRightTabs", anchorButton)
  end
  ProfessionsFrame:HookScript("OnShow", anchorButton)
  local page = ProfessionsFrame.CraftingPage
  if type(page.Init) == "function" then
    hooksecurefunc(page, "Init", function() C_Timer.After(0, anchorButton) end)
  end
  page:HookScript("OnShow", function()
    anchorButton()
    C_Timer.After(0, anchorButton)  -- the link button may show a moment later
  end)
  page:HookScript("OnHide", anchorButton)
end

ns.Listen("GUIDE_SHOWN", function(shown)
  if button then
    button:SetChecked(shown)
  end
end)

ns.OnProfessionsLoaded(createButton)
