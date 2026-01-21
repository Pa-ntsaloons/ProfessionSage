-- Declare scanTimer at the top of the file
local scanTimer

local success, err = pcall(function(...)
    local addonName, addon = ...
    GatherProfitScanner = GatherProfitScanner or {}
    local frame, scrollFrame, content, sortByNameButton
    local sortCriteria = "level" -- Default sorting criteria
    local itemDataCache = {} -- Cache for item data
    local isUpdating = false -- Throttle flag
    local lastUpdateTime = 0 -- Last update timestamp
    local UPDATE_THROTTLE = 1 -- Throttle updates to once per second

    -- Persistent data
    GatherProfitScannerData = GatherProfitScannerData or {}

    -- Frame setup (Main results window)
    frame = CreateFrame("Frame", "GatherProfitScannerFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(550, 450)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG") -- Set to DIALOG strata
    frame:SetFrameLevel(100) -- Explicitly set frame level
    frame:Hide()
    -- Make the main frame draggable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    frame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)
    frame:SetScript("OnHide", function()
        frame.searchBox:SetText("") -- Clear the search bar
        frame.searchBox.placeholder:Show() -- Show the placeholder text
    end)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0, 0, 0, 0.95)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.title:ClearAllPoints()
    frame.title:SetPoint("TOP", 0, -3) -- Move the title down slightly
    frame.title:SetText("|cFF00FF00GatherProfitScanner - Gathering Item Values|r")

    -- Add a search box to the frame
    frame.searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.searchBox:SetSize(200, 25)
    frame.searchBox:ClearAllPoints()
    frame.searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -30) -- Move the search box below the title
    frame.searchBox:SetAutoFocus(false)
    frame.searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.searchBox:SetScript("OnTextChanged", function(self)
        GatherProfitScanner:RenderValues(self:GetText())
    end)
    frame.searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.searchBox:SetText("") -- Default empty text
    frame.searchBox.placeholder = frame.searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.searchBox.placeholder:SetPoint("LEFT", frame.searchBox, "LEFT", 5, 0)
    frame.searchBox.placeholder:SetText("Search...")
    frame.searchBox:SetScript("OnEditFocusGained", function(self) self.placeholder:Hide() end)
    frame.searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            self.placeholder:Show()
        end
    end)

    -- Last AH scan time display
    frame.lastScanText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.lastScanText:ClearAllPoints()
    frame.lastScanText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 15) -- Position it at the bottom-left corner
    frame.lastScanText:SetText("|cFFFF0000Last AH Scan: Unknown|r")

    -- Declare button variables first
    local nameSortButton, priceSortButton, levelSortButton

    -- Define the UpdateButtonHighlights function at the top
    local function UpdateButtonHighlights()
        for _, btn in ipairs({levelSortButton, priceSortButton, nameSortButton}) do
            if btn.sortType == sortCriteria then
                btn:SetButtonState("PUSHED", true) -- Make the button appear pressed
                btn:LockHighlight() -- Add a highlight effect
            else
                btn:SetButtonState("NORMAL", false) -- Reset to normal state
                btn:UnlockHighlight() -- Remove the highlight effect
            end

            -- Ensure the text color is always white
            local fontString = btn:GetFontString()
            fontString:SetTextColor(1, 1, 1) -- Set text color to white
        end
    end

    -- Create the three sort buttons with updated size and position
    local function CreateSortButton(label, sortType, xOffset)
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", xOffset, -35) -- Position horizontally
        button:SetSize(80, 20) -- Button size
        button:SetText(label)
        button.sortType = sortType -- Assign the sort type to the button

        -- Ensure the text color is always white
        local fontString = button:GetFontString()
        fontString:SetTextColor(1, 1, 1) -- Set text color to white

        button:SetScript("OnClick", function()
            -- Update sort criteria and re-render the UI
            sortCriteria = sortType
            GatherProfitScanner:SortItems(sortCriteria)
            GatherProfitScanner:RenderValues(frame.searchBox:GetText())

            -- Update button highlights
            UpdateButtonHighlights()
        end)
        return button
    end

    -- Create the buttons and position them horizontally
    nameSortButton = CreateSortButton("Name", "name", -190)
    priceSortButton = CreateSortButton("Price", "price", -105)
    levelSortButton = CreateSortButton("Level", "level", -20)

    -- Set the default highlighted button
    UpdateButtonHighlights()

    -- Scroll frame setup
    scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -65)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 45) -- Adjust the scroll frame to leave space for the "Last AH Scan" text
    scrollFrame.bg = scrollFrame:CreateTexture(nil, "OVERLAY")
    scrollFrame.bg:SetAllPoints()
    scrollFrame.bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
    scrollFrame.bg:SetDrawLayer("BACKGROUND", 0)

    -- Content frame inside the scroll frame
    content = CreateFrame("Frame", nil, scrollFrame)
    content:SetHeight(2000) -- Large enough to require scrolling
    content:SetWidth(scrollFrame:GetWidth()) -- Match the width of the scroll frame
    scrollFrame:SetScrollChild(content)

    -- Enable clipping to prevent mouse events outside the visible area
    scrollFrame:SetClipsChildren(true)

    -- Add a vertical scrollbar
    local scrollbar = CreateFrame("Slider", nil, scrollFrame, "UIPanelScrollBarTemplate")
    scrollbar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -15, -65)
    scrollbar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 45)
    scrollbar:SetWidth(16)
    scrollbar:SetMinMaxValues(0, 1) -- Default values; will be updated dynamically
    scrollbar:SetValueStep(1)
    scrollbar.scrollStep = 20 -- Amount to scroll per step
    scrollbar:SetValue(0)
    scrollbar:SetScript("OnValueChanged", function(self, value)
        scrollFrame:SetVerticalScroll(value)
    end)

    -- Update the scrollbar dynamically based on content height
    scrollFrame:HookScript("OnScrollRangeChanged", function(self, xrange, yrange)
        scrollbar:SetMinMaxValues(0, math.max(yrange, 0)) -- Ensure the range is non-negative
        scrollbar:SetValue(math.min(scrollbar:GetValue(), yrange))
    end)

    -- Enable mouse wheel scrolling
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = scrollbar:GetValue()
        local newValue = current - (delta * scrollbar.scrollStep)
        scrollbar:SetValue(newValue)
    end)

    -- Popup edit box for Wowhead link
    local linkFrame = CreateFrame("Frame", "GatherProfitScannerLinkFrame", UIParent, "BasicFrameTemplateWithInset")
    linkFrame:SetSize(400, 100)
    linkFrame:SetPoint("CENTER")
    linkFrame:SetFrameStrata("TOOLTIP") -- Set to TOOLTIP strata (higher than HIGH)
    linkFrame:SetFrameLevel(200) -- Explicitly set a higher frame level
    linkFrame:Hide()
    -- Make the popup frame draggable
    linkFrame:SetMovable(true)
    linkFrame:EnableMouse(true)
    linkFrame:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    linkFrame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)
    linkFrame.title = linkFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    linkFrame.title:SetPoint("TOP", 0, -5)
    linkFrame.title:SetText("|cFF00FF00Wowhead Link|r")

    local linkEditBox = CreateFrame("EditBox", nil, linkFrame, "InputBoxTemplate")
    linkEditBox:SetSize(380, 20)
    linkEditBox:SetPoint("TOP", 0, -30)
    linkEditBox:SetAutoFocus(true)
    linkEditBox:SetScript("OnEscapePressed", function(self) linkFrame:Hide() end)
    linkEditBox:SetScript("OnEnterPressed", function(self) linkFrame:Hide() end)
    linkEditBox:SetScript("OnShow", function(self) self:SetFocus() self:HighlightText() end)

    -- Object pools
    local fontStringPool = {}
    local activeFontStrings = {}
    local texturePool = {}
    local activeTextures = {}
    local activeHighlights = {}
    local separatorPool = {} -- New pool for separator textures
    local activeSeparators = {} -- Track active separators

    local function GetFontString()
        local fs = table.remove(fontStringPool)
        if not fs then fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormal") end
        fs:Show()
        fs:SetText("")
        fs:ClearAllPoints()
        fs:SetParent(content)
        fs:SetScript("OnEnter", nil)
        fs:SetScript("OnLeave", nil)
        fs:SetScript("OnMouseUp", nil)
        fs:EnableMouse(false)
        table.insert(activeFontStrings, fs)
        return fs
    end

    local function GetTexture()
        local tex = table.remove(texturePool)
        if not tex then tex = content:CreateTexture(nil, "OVERLAY") end
        tex:Show()
        tex:ClearAllPoints()
        tex:SetSize(18, 18)
        tex:SetScript("OnEnter", nil)
        tex:SetScript("OnLeave", nil)
        tex:SetScript("OnMouseUp", nil)
        tex:EnableMouse(false)
        table.insert(activeTextures, tex)
        return tex
    end

    local function GetSeparator()
        local sep = table.remove(separatorPool)
        if not sep then
            sep = content:CreateTexture(nil, "BACKGROUND")
        end
        sep:Show()
        sep:ClearAllPoints()
        sep:SetHeight(2)
        sep:SetColorTexture(0, 1, 1, 0.7)
        table.insert(activeSeparators, sep)
        return sep
    end

    -- Format money
    local function FormatMoney(copper)
        if not copper or copper < 0 then return "0c" end
        local gold = math.floor(copper / 10000)
        copper = copper % 10000
        local silver = math.floor(copper / 100)
        copper = copper % 100
        local parts = {}
        if gold > 0 then table.insert(parts, gold .. "g") end
        if silver > 0 or gold > 0 then table.insert(parts, silver .. "s") end
        if copper > 0 or (gold == 0 and silver == 0) then table.insert(parts, copper .. "c") end
        return table.concat(parts, " ")
    end

    -- Vendor price function
    local function GetVendorPrice(itemID, itemName)
        if not itemID then return 0 end
        if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetVendorPriceByItemID then
            return Auctionator.API.v1.GetVendorPriceByItemID("GatherProfitScanner", itemID) or 0
        end
        return 0
    end

    -- AH price function
    local function GetAHPrice(itemID, itemName)
        if not itemID then return 0 end
        local price = 0
        if IsAddOnLoaded("Auctionator") and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID then
            price = Auctionator.API.v1.GetAuctionPriceByItemID("GatherProfitScanner", itemID) or 0
            return price
        end
        return 0
    end

    -- Profession level function
    local function GetPlayerProfessionLevel(professionName)
        local professionMap = {
            ["Herbalism"] = {2366, 2368, 3570, 11993}, -- All possible spell IDs for Herbalism
            ["Mining"] = {2576, 3564, 10248, 2575}, -- Mining spell ID
            ["Fishing"] = {7731, 7620, 7732, 18248}, -- Fishing spell ID
            ["Skinning"] = {8617, 8618, 10768, 8613}, -- Skinning spell ID
        }

        local spellIDs = professionMap[professionName]
        if not spellIDs then
            print("Profession not found in map:", professionName)
            return 0
        end

        for i = 1, GetNumSkillLines() do
            local skillName, _, _, skillRank = GetSkillLineInfo(i)
            if skillName then
                for _, spellID in ipairs(spellIDs) do
                    local localizedName = GetSpellInfo(spellID)
                    if localizedName and (skillName == localizedName or skillName:lower() == professionName:lower()) then
                        return skillRank
                    end
                end

                -- Fallback: Directly compare with profession name
                if skillName:lower() == professionName:lower() then
                    return skillRank
                end
            end
        end

        return 0
    end

    -- Function to get last AH scan time
    local function GetLastAHScanTime()
        if C_AddOns.IsAddOnLoaded("Auctionator") then
            if AUCTIONATOR_SAVEDVARS and AUCTIONATOR_SAVEDVARS["TimeOfLastGetAllScan"] then
                return AUCTIONATOR_SAVEDVARS["TimeOfLastGetAllScan"]
            end
        end
        return 0
    end

    -- Update prices function (with optional silent mode and force update)
    function GatherProfitScanner:UpdatePrices(silent, force)
        if isUpdating or (not force and GetTime() - lastUpdateTime < UPDATE_THROTTLE) then return false end
        isUpdating = true

        if not C_AddOns.IsAddOnLoaded("Auctionator") then
            frame.lastScanText:SetText("|cFFFF0000Last AH Scan: Auctionator required|r")
            isUpdating = false
            return false
        end
        if not GatherProfitScannerItems then
            frame.lastScanText:SetText("|cFFFF0000Last AH Scan: Item list missing|r")
            isUpdating = false
            return false
        end

        local professionGroups = {}
        local pendingItems = GatherProfitScanner.pendingItems or {}
        local playerLevels = {}

        for profession, _ in pairs(GatherProfitScannerItems) do
            playerLevels[profession] = GetPlayerProfessionLevel(profession)
            professionGroups[profession] = { canGather = {}, cannotGather = {} }
        end

        for profession, items in pairs(GatherProfitScannerItems) do
            for _, item in ipairs(items) do
                local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(item.itemID)
                if not itemName then
                    pendingItems[item.itemID] = true -- Track items pending data
                else
                    local ahPrice = GetAHPrice(item.itemID, itemName)
                    local vendorPrice = GetVendorPrice(item.itemID, itemName)
                    local sellPrice = ahPrice > 0 and ahPrice or vendorPrice
                    local priceSource = ahPrice > 0 and "AH" or "Vendor"

                    local itemData = {
                        name = itemName,
                        profession = profession,
                        sellPrice = sellPrice,
                        icon = itemIcon,
                        priceSource = priceSource,
                        requiredLevel = item.requiredLevel or 1,
                        itemID = item.itemID
                    }

                    local playerLevel = playerLevels[profession] or 0
                    if playerLevel >= itemData.requiredLevel then
                        table.insert(professionGroups[profession].canGather, itemData)
                    else
                        table.insert(professionGroups[profession].cannotGather, itemData)
                    end
                end
            end
        end

        GatherProfitScanner.pendingItems = next(pendingItems) and pendingItems or nil
        itemDataCache = professionGroups

        if not GatherProfitScanner.pendingItems then
            GatherProfitScanner:RenderValues()
        end

        isUpdating = false
        lastUpdateTime = GetTime()
        return true
    end

    -- Render values function
    function GatherProfitScanner:RenderValues(searchQuery)
        searchQuery = searchQuery and searchQuery:lower() or ""

        -- Save the current scroll position
        local currentScroll = scrollFrame:GetVerticalScroll()

        -- Clear active font strings
        for _, fs in ipairs(activeFontStrings) do
            fs:Hide()
            fs:SetText("")
            fs:ClearAllPoints()
            fs:SetParent(nil)
            fs:SetScript("OnEnter", nil)
            fs:SetScript("OnLeave", nil)
            fs:SetScript("OnMouseUp", nil)
            fs:EnableMouse(false)
            table.insert(fontStringPool, fs)
        end
        activeFontStrings = {}

        -- Clear active textures
        for _, tex in ipairs(activeTextures) do
            tex:Hide()
            tex:ClearAllPoints()
            tex:SetScript("OnEnter", nil)
            tex:SetScript("OnLeave", nil)
            tex:SetScript("OnMouseUp", nil)
            tex:EnableMouse(false)
            table.insert(texturePool, tex)
        end
        activeTextures = {}

        -- Clear active highlights
        for _, highlight in ipairs(activeHighlights) do
            highlight:Hide()
            highlight:ClearAllPoints()
        end
        activeHighlights = {}

        -- Clear active separators
        for _, sep in ipairs(activeSeparators) do
            sep:Hide()
            sep:ClearAllPoints()
            table.insert(separatorPool, sep)
        end
        activeSeparators = {}

        -- Reset content size and scroll position
        content:SetHeight(1)
        content:SetWidth(500)

        -- Sort professions to prioritize those the character has
        local sortedProfessions = {}
        for profession, groups in pairs(itemDataCache) do
            table.insert(sortedProfessions, { profession = profession, groups = groups })
        end

        table.sort(sortedProfessions, function(a, b)
            local playerHasA = GetPlayerProfessionLevel(a.profession) > 0
            local playerHasB = GetPlayerProfessionLevel(b.profession) > 0
            if playerHasA and not playerHasB then
                return true
            elseif not playerHasA and playerHasB then
                return false
            else
                return a.profession < b.profession -- Alphabetical fallback
            end
        end)

        local yOffset = 10
        for _, entry in ipairs(sortedProfessions) do
            local profession = entry.profession
            local groups = entry.groups

            -- Sort items within each profession based on the selected criteria
            if sortCriteria == "price" then
                table.sort(groups.canGather, function(a, b) return a.sellPrice > b.sellPrice end)
                table.sort(groups.cannotGather, function(a, b) return a.sellPrice > b.sellPrice end)
            elseif sortCriteria == "name" then
                table.sort(groups.canGather, function(a, b) return a.name:lower() < b.name:lower() end)
                table.sort(groups.cannotGather, function(a, b) return a.name:lower() < b.name:lower() end)
            else
                table.sort(groups.canGather, function(a, b) return a.requiredLevel < b.requiredLevel end)
                table.sort(groups.cannotGather, function(a, b) return a.requiredLevel < b.requiredLevel end)
            end

            -- Filter items based on the search query
            local filteredCanGather = {}
            local filteredCannotGather = {}

            for _, item in ipairs(groups.canGather) do
                if searchQuery == "" or item.name:lower():find(searchQuery) then
                    table.insert(filteredCanGather, item)
                end
            end

            for _, item in ipairs(groups.cannotGather) do
                if searchQuery == "" or item.name:lower():find(searchQuery) then
                    table.insert(filteredCannotGather, item)
                end
            end

            -- Only render the section if there are matching items
            if #filteredCanGather > 0 or #filteredCannotGather > 0 then
                -- Profession header
                local header = GetFontString()
                header:SetFontObject("GameFontHighlightLarge")
                header:SetPoint("TOPLEFT", 10, -yOffset)
                header:SetText("|cFF00FFFF" .. profession .. " Items|r")
                yOffset = yOffset + 30

                -- Separator
                local separator = GetSeparator()
                separator:SetPoint("TOPLEFT", 10, -yOffset)
                separator:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -yOffset)
                yOffset = yOffset + 10

                -- Render "Can Gather" items
                if #filteredCanGather > 0 then
                    local subHeader = GetFontString()
                    subHeader:SetFontObject("GameFontNormalLarge")
                    subHeader:SetPoint("TOPLEFT", 15, -yOffset)
                    subHeader:SetText("|cFF00FF00Can Gather|r")
                    yOffset = yOffset + 25

                    for _, item in ipairs(filteredCanGather) do
                        yOffset = self:RenderItem(item, yOffset, true)
                    end
                    yOffset = yOffset + 15
                end

                -- Render "Cannot Gather" items
                if #filteredCannotGather > 0 then
                    local subHeader = GetFontString()
                    subHeader:SetFontObject("GameFontNormalLarge")
                    subHeader:SetPoint("TOPLEFT", 15, -yOffset)
                    subHeader:SetText("|cFFFF0000Cannot Gather|r")
                    yOffset = yOffset + 25

                    for _, item in ipairs(filteredCannotGather) do
                        yOffset = self:RenderItem(item, yOffset, false)
                    end
                    yOffset = yOffset + 15
                end
            end
        end

        content:SetHeight(yOffset)
        scrollFrame:UpdateScrollChildRect()

        -- Restore the saved scroll position
        scrollFrame:SetVerticalScroll(currentScroll)

        UpdateButtonHighlights() -- Ensure button highlights are updated
    end

    -- Helper function to render an individual item
    function GatherProfitScanner:RenderItem(item, yOffset, canGather)
        local highlight = content:CreateTexture(nil, "BACKGROUND")
        highlight:SetPoint("TOPLEFT", 0, -yOffset)
        highlight:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", 0, -(yOffset + 20))
        highlight:SetColorTexture(canGather and 0 or 1, canGather and 1 or 0, 0, 0.1)
        highlight:SetDrawLayer("BACKGROUND", 1)
        table.insert(activeHighlights, highlight)

        local icon = GetTexture()
        icon:SetPoint("TOPLEFT", 20, -yOffset - 3)
        icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon:EnableMouse(true)
        icon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(item.itemID)
            GameTooltip:AddLine("Right-click for Wowhead link", 0, 1, 1)
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        icon:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" then
                local wowheadLink = string.format("https://www.wowhead.com/classic/item=%d", item.itemID)
                linkEditBox:SetText(wowheadLink)
                linkFrame:Show()
            end
        end)

        local title = GetFontString()
        title:SetFontObject("GameFontNormal")
        title:SetPoint("TOPLEFT", 45, -yOffset)
        title:SetText(string.format(
            "%s%s|r |cFFFFFFFF(Req. %d): Sell Price |cFFFFD700%s|r (%s)|r",
            canGather and "|cFF00FF00" or "|cFFFF0000", -- Green for gatherable, red for non-gatherable
            item.name,
            item.requiredLevel,
            FormatMoney(item.sellPrice),
            item.priceSource
        ))
        title:EnableMouse(true)
        title:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(item.itemID)
            GameTooltip:AddLine("Right-click for Wowhead link", 0, 1, 1)
            GameTooltip:Show()
        end)
        title:SetScript("OnLeave", function() GameTooltip:Hide() end)
        title:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" then
                local wowheadLink = string.format("https://www.wowhead.com/classic/item=%d", item.itemID)
                linkEditBox:SetText(wowheadLink)
                linkFrame:Show()
            end
        end)

        return yOffset + 25
    end

    function GatherProfitScanner:SortItems(criteria)
        if not self.items then return end

        if criteria == "price" then
            table.sort(self.items, function(a, b)
                return a.price < b.price
            end)
        elseif criteria == "level" then
            table.sort(self.items, function(a, b)
                return a.requiredLevel < b.requiredLevel
            end)
        elseif criteria == "name" then
            table.sort(self.items, function(a, b)
                return a.name:lower() < b.name:lower()
            end)
        end
    end

    function GatherProfitScanner:CheckPendingItems()
        if not GatherProfitScanner.pendingItems then return end

        for itemID in pairs(GatherProfitScanner.pendingItems) do
            local itemName = GetItemInfo(itemID)
            if itemName then
                GatherProfitScanner.pendingItems[itemID] = nil
            end
        end

        if not next(GatherProfitScanner.pendingItems) then
            GatherProfitScanner.pendingItems = nil
            if frame:IsShown() then
                GatherProfitScanner:RenderValues() -- Re-render results when all item data is received
            end
        else
            -- Continue checking until all items are resolved
            C_Timer.After(0.5, function()
                GatherProfitScanner:CheckPendingItems()
            end)
        end
    end

    -- Minimap button setup
    local minimapButton = CreateFrame("Button", "GatherProfitScannerMinimapButton", Minimap)
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Button texture
    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01") -- Replace with a custom icon if desired
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")

    -- Border texture
    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54) -- Ensure the size matches the button's border
    border:SetPoint("CENTER", minimapButton, "CENTER", 11, -11.5) -- Align the border to the center of the button

    -- Dragging functionality
    local isDragging = false
    minimapButton:SetMovable(true)
    minimapButton:EnableMouse(true)
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetScript("OnDragStart", function(self)
        isDragging = true
        self:StartMoving()
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        isDragging = false
        self:StopMovingOrSizing()
    end)

    -- Click functionality
    minimapButton:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            -- Toggle the frame
            if GatherProfitScannerFrame:IsShown() then
                GatherProfitScannerFrame:Hide()
                if scanTimer then
                    scanTimer:Cancel() -- Stop the timer if it is running
                    scanTimer = nil -- Clear the reference to the timer
                end
            else
                local success, err = pcall(function()
                    if GatherProfitScanner:UpdatePrices(false, true) then -- Non-silent, force update
                        GatherProfitScanner:RenderValues()
                        GatherProfitScannerFrame:Show()

                        -- Start a 5-second timer to scan for changes
                        local scanStartTime = GetTime()
                        scanTimer = C_Timer.NewTicker(1, function()
                            if GetTime() - scanStartTime >= 3 then
                                scanTimer:Cancel() -- Stop the timer after 3 seconds
                                scanTimer = nil -- Clear the reference to the timer
                            else
                                
                                GatherProfitScanner:UpdatePrices(true) -- Silent update
                                GatherProfitScanner:RenderValues()
                            end
                        end)
                    end
                end)

                if not success then
                    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000GatherProfitScanner: Error toggling frame: " .. tostring(err) .. "|r")
                end
            end
        elseif button == "RightButton" then
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00GatherProfitScanner: Right-click functionality not implemented.|r")
        end
    end)

    -- Tooltip
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("GatherProfitScanner", 1, 1, 1)
        GameTooltip:AddLine("Left-click to toggle the frame.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag to move the button.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Slash command
    SLASH_GATHERPROFIT1 = "/gpscan"
    local function toggleFrame()
        if frame:IsShown() then
            frame:Hide()
            if scanTimer then
                scanTimer:Cancel() -- Stop the timer if it is running
                scanTimer = nil -- Clear the reference to the timer
            end
        else
            local success, err = pcall(function()
                if GatherProfitScanner:UpdatePrices(false, true) then -- Non-silent, force update
                    GatherProfitScanner:RenderValues()
                    frame:Show()

                    -- Start a 5-second timer to scan for changes
                    local scanStartTime = GetTime()
                    scanTimer = C_Timer.NewTicker(1, function()
                        if GetTime() - scanStartTime >= 3 then
                            scanTimer:Cancel() -- Stop the timer after 3 seconds
                            scanTimer = nil -- Clear the reference to the timer
                        else
                            
                            GatherProfitScanner:UpdatePrices(true) -- Silent update
                            GatherProfitScanner:RenderValues()
                        end
                    end)
                end
            end)

            if not success then
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000GatherProfitScanner: Error toggling frame: " .. tostring(err) .. "|r")
            end
        end
    end
    SlashCmdList["GATHERPROFIT"] = toggleFrame

    -- Event handling
    local auctionHouseOpen = false
    local auctionDataLastUpdated = 0

    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:RegisterEvent("SKILL_LINES_CHANGED")
    -- Register for auction house events
    frame:RegisterEvent("AUCTION_HOUSE_SHOW")
    frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
    frame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_LOGIN" then
            local lastScanTime = GetLastAHScanTime()
            local dateStr = lastScanTime > 0 and date("%Y-%m-%d %H:%M:%S", lastScanTime) or "Never"
            local timeDiff = time() - lastScanTime
            local color = (lastScanTime > 0 and timeDiff <= 2 * 3600) and "|cFF00FF00" or "|cFFFF0000"
            frame.lastScanText:SetText(color .. "Last AH Scan: " .. dateStr .. "|r")
            GatherProfitScanner:UpdatePrices() -- Show message on login
        elseif event == "GET_ITEM_INFO_RECEIVED" then
            local itemID = ...
            if GatherProfitScanner.pendingItems and GatherProfitScanner.pendingItems[itemID] then
                GatherProfitScanner.pendingItems[itemID] = nil
            end
        elseif event == "SKILL_LINES_CHANGED" then
            if frame:IsShown() and GetTime() - lastUpdateTime > UPDATE_THROTTLE then
                GatherProfitScanner:UpdatePrices(true) -- Silent update
                GatherProfitScanner:RenderValues()
            end
        elseif event == "AUCTION_HOUSE_SHOW" then
            auctionHouseOpen = true
            auctionDataLastUpdated = GetTime()
            C_Timer.NewTicker(1, function()
                if auctionHouseOpen and frame:IsShown() then
                    local currentTime = GetTime()
                    if currentTime - auctionDataLastUpdated > 1 then
                        auctionDataLastUpdated = currentTime
                        GatherProfitScanner:UpdatePrices(true) -- Silent update
                        GatherProfitScanner:RenderValues()
                    end
                end
            end)
        elseif event == "AUCTION_HOUSE_CLOSED" then
            auctionHouseOpen = false
        end
    end)
end)

if not success then
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000GatherProfitScanner: Error loading addon: " .. tostring(err) .. "|r")
end