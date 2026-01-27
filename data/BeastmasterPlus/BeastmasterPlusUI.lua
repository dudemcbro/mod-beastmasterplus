-- Beastmaster Plus UI
-- Complete in-game UI with accessibility and QoL improvements

local addonName, HSP = ...

-- UI Constants
local FRAME_WIDTH = 720
local FRAME_HEIGHT = 580
local ROW_HEIGHT = 36
local ROWS_VISIBLE = 10
local HEADER_HEIGHT = 40
local FILTER_HEIGHT = 70
local FOOTER_HEIGHT = 40

-- Colors (WoW-themed dark fantasy - improved contrast)
local COLORS = {
    background = { 0.06, 0.06, 0.10, 0.98 },
    header = { 0.10, 0.10, 0.16, 1 },
    border = { 0.50, 0.45, 0.25, 1 },
    gold = { 1, 0.82, 0.2, 1 },
    text = { 0.95, 0.95, 0.95, 1 },
    textDim = { 0.70, 0.70, 0.70, 1 },
    textMuted = { 0.50, 0.50, 0.50, 1 },
    row = { 0.08, 0.08, 0.12, 1 },
    rowAlt = { 0.10, 0.10, 0.14, 1 },
    rowHover = { 0.20, 0.18, 0.14, 1 },
    rowSelected = { 0.25, 0.22, 0.15, 1 },
    exotic = { 0.70, 0.30, 0.90, 1 },
    active = { 0.30, 0.90, 0.40, 1 },
    favorite = { 1, 0.82, 0.2, 1 },
    buttonBg = { 0.15, 0.15, 0.20, 1 },
    filterActive = { 0.30, 0.25, 0.15, 1 },
    -- Level colors for visual hierarchy
    levelLow = { 0.60, 0.60, 0.60, 1 },      -- 1-19 gray
    levelMid = { 0.30, 0.90, 0.30, 1 },      -- 20-39 green
    levelHigh = { 0.30, 0.60, 1.00, 1 },     -- 40-59 blue
    levelVeryHigh = { 0.70, 0.30, 0.90, 1 }, -- 60-79 purple
    levelMax = { 1.00, 0.50, 0.00, 1 },      -- 80 orange
}

-- Pet family icons (WoW 3.3.5a compatible)
local FAMILY_ICONS = {
    ["Bat"] = "Interface\\Icons\\Ability_Hunter_Pet_Bat",
    ["Bear"] = "Interface\\Icons\\Ability_Hunter_Pet_Bear",
    ["Bird of Prey"] = "Interface\\Icons\\Ability_Hunter_Pet_Owl",
    ["Boar"] = "Interface\\Icons\\Ability_Hunter_Pet_Boar",
    ["Carrion Bird"] = "Interface\\Icons\\Ability_Hunter_Pet_Vulture",
    ["Cat"] = "Interface\\Icons\\Ability_Hunter_Pet_Cat",
    ["Chimaera"] = "Interface\\Icons\\Ability_Hunter_Pet_Chimera",
    ["Core Hound"] = "Interface\\Icons\\Ability_Hunter_Pet_CoreHound",
    ["Crab"] = "Interface\\Icons\\Ability_Hunter_Pet_Crab",
    ["Crocolisk"] = "Interface\\Icons\\Ability_Hunter_Pet_Crocolisk",
    ["Devilsaur"] = "Interface\\Icons\\Ability_Hunter_Pet_Devilsaur",
    ["Dragonhawk"] = "Interface\\Icons\\Ability_Hunter_Pet_DragonHawk",
    ["Gorilla"] = "Interface\\Icons\\Ability_Hunter_Pet_Gorilla",
    ["Hyena"] = "Interface\\Icons\\Ability_Hunter_Pet_Hyena",
    ["Moth"] = "Interface\\Icons\\Ability_Hunter_Pet_Moth",
    ["Nether Ray"] = "Interface\\Icons\\Ability_Hunter_Pet_NetherRay",
    ["Raptor"] = "Interface\\Icons\\Ability_Hunter_Pet_Raptor",
    ["Ravager"] = "Interface\\Icons\\Ability_Hunter_Pet_Ravager",
    ["Rhino"] = "Interface\\Icons\\Ability_Hunter_Pet_Rhino",
    ["Scorpid"] = "Interface\\Icons\\Ability_Hunter_Pet_Scorpid",
    ["Serpent"] = "Interface\\Icons\\Ability_Hunter_Pet_Serpent",
    ["Silithid"] = "Interface\\Icons\\Ability_Hunter_Pet_Silithid",
    ["Spider"] = "Interface\\Icons\\Ability_Hunter_Pet_Spider",
    ["Spirit Beast"] = "Interface\\Icons\\Ability_Hunter_Pet_SpiritBeast",
    ["Sporebat"] = "Interface\\Icons\\Ability_Hunter_Pet_Sporebat",
    ["Tallstrider"] = "Interface\\Icons\\Ability_Hunter_Pet_TallStrider",
    ["Turtle"] = "Interface\\Icons\\Ability_Hunter_Pet_Turtle",
    ["Warp Stalker"] = "Interface\\Icons\\Ability_Hunter_Pet_WarpStalker",
    ["Wasp"] = "Interface\\Icons\\Ability_Hunter_Pet_Wasp",
    ["Wind Serpent"] = "Interface\\Icons\\Ability_Hunter_Pet_WindSerpent",
    ["Wolf"] = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
    ["Worm"] = "Interface\\Icons\\Ability_Hunter_Pet_Worm",
    ["Unknown"] = "Interface\\Icons\\INV_Misc_QuestionMark",
}

local function GetFamilyIcon(family)
    return FAMILY_ICONS[family] or FAMILY_ICONS["Unknown"]
end

local function GetLevelColor(level)
    level = tonumber(level) or 1
    if level >= 80 then return COLORS.levelMax
    elseif level >= 60 then return COLORS.levelVeryHigh
    elseif level >= 40 then return COLORS.levelHigh
    elseif level >= 20 then return COLORS.levelMid
    else return COLORS.levelLow end
end

-- Selected row tracking
local selectedRowIndex = nil

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function CreateBackdrop(frame, bgColor, borderColor)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        frame:SetBackdropColor(unpack(bgColor or COLORS.background))
        frame:SetBackdropBorderColor(unpack(borderColor or COLORS.border))
    end
end

local function CreateButton(parent, text, width, height, tooltip)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 80, height or 24)
    btn:SetText(text)
    btn:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 11)
    if tooltip then
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return btn
end

local function CreateIconButton(parent, size, icon, tooltip)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    CreateBackdrop(btn, COLORS.buttonBg, COLORS.border)
    
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(size - 6, size - 6)
    btn.icon:SetPoint("CENTER")
    btn.icon:SetTexture(icon)
    
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.22, 0.18, 1)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(COLORS.buttonBg))
        GameTooltip:Hide()
    end)
    
    return btn
end

local function CreateEditBox(parent, width, height, placeholder)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(width or 150, height or 24)
    edit:SetAutoFocus(false)
    edit:SetFont("Fonts\\FRIZQT__.TTF", 11)
    if placeholder then
        edit.placeholder = edit:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        edit.placeholder:SetPoint("LEFT", 5, 0)
        edit.placeholder:SetText(placeholder)
        edit:SetScript("OnTextChanged", function(self)
            if self:GetText() == "" then
                self.placeholder:Show()
            else
                self.placeholder:Hide()
            end
        end)
    end
    return edit
end

local dropdownCounter = 0
local function CreateDropdown(parent, width, items, onSelect)
    dropdownCounter = dropdownCounter + 1
    local dropdownName = "BMPDropdown" .. dropdownCounter
    local dropdown = CreateFrame("Frame", dropdownName, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dropdown, width or 120)
    
    dropdown.items = items or {}
    dropdown.onSelect = onSelect
    dropdown.selectedValue = nil
    
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        level = level or 1
        for _, item in ipairs(dropdown.items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text or ""
            info.value = item.value or ""
            info.checked = (dropdown.selectedValue == item.value)
            info.func = function()
                UIDropDownMenu_SetSelectedValue(dropdown, item.value)
                UIDropDownMenu_SetText(dropdown, item.text)
                dropdown.selectedValue = item.value
                if dropdown.onSelect then dropdown.onSelect(item.value) end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    
    return dropdown
end

-- ============================================================================
-- MAIN FRAME
-- ============================================================================

local function CreateMainFrame()
    local frame = CreateFrame("Frame", "BeastmasterPlusFrame", UIParent)
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    
    CreateBackdrop(frame, COLORS.background, COLORS.border)
    
    -- Keyboard support (Escape to close) - 3.3.5a compatible
    -- Use tinsert to add to UISpecialFrames so ESC closes the frame
    tinsert(UISpecialFrames, "BeastmasterPlusFrame")
    
    -- Title bar with pet count
    local header = CreateFrame("Frame", nil, frame)
    header:SetSize(FRAME_WIDTH, HEADER_HEIGHT)
    header:SetPoint("TOP")
    CreateBackdrop(header, COLORS.header, { 0, 0, 0, 0 })
    
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", 15, 0)
    title:SetText("|cFFFFD100Beastmaster Plus|r")
    
    -- Pet count with filter status
    frame.petCount = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.petCount:SetPoint("LEFT", title, "RIGHT", 15, 0)
    frame.petCount:SetTextColor(unpack(COLORS.textDim))
    
    -- Filter status indicator
    frame.filterStatus = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.filterStatus:SetPoint("LEFT", frame.petCount, "RIGHT", 10, 0)
    frame.filterStatus:SetTextColor(unpack(COLORS.gold))
    
    -- Close button with tooltip
    local closeBtn = CreateButton(header, "X", 24, 24, "Close window (Escape)")
    closeBtn:SetPoint("RIGHT", -8, 0)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    return frame
end

-- ============================================================================
-- FILTER BAR WITH QUICK FILTERS
-- ============================================================================

local function CreateFilterBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(FRAME_WIDTH - 20, FILTER_HEIGHT)
    bar:SetPoint("TOP", 0, -HEADER_HEIGHT - 5)
    CreateBackdrop(bar, COLORS.header, { 0, 0, 0, 0 })
    
    -- Search box
    local searchBox = CreateEditBox(bar, 180, 24, "Search pets...")
    searchBox:SetPoint("TOPLEFT", 10, -8)
    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if self.placeholder then
            self.placeholder:SetShown(text == "")
        end
        HSP.SetSearch(text)
        HSP.UpdateUI()
    end)
    bar.searchBox = searchBox
    
    -- Family dropdown
    local familyItems = {{ text = "All Families", value = nil }}
    for _, family in ipairs(HSP.PET_FAMILIES or {}) do
        table.insert(familyItems, { text = family, value = family })
    end
    
    bar.familyDropdown = CreateDropdown(bar, 120, familyItems, function(value)
        HSP.SetFilter("family", value)
        HSP.UpdateUI()
    end)
    bar.familyDropdown:SetPoint("TOPLEFT", 200, -2)
    UIDropDownMenu_SetText(bar.familyDropdown, "All Families")
    
    -- Quick filter buttons (second row)
    local quickLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    quickLabel:SetPoint("TOPLEFT", 10, -38)
    quickLabel:SetText("Quick Filters:")
    quickLabel:SetTextColor(unpack(COLORS.textDim))
    
    -- Exotic only toggle
    bar.exoticBtn = CreateButton(bar, "Exotic", 60, 22, "Toggle exotic pets only")
    bar.exoticBtn:SetPoint("LEFT", quickLabel, "RIGHT", 10, 0)
    bar.exoticBtn:SetScript("OnClick", function()
        HSP.SetQuickFilter("exotic")
        HSP.UpdateUI()
    end)
    
    -- Max level toggle
    bar.maxLevelBtn = CreateButton(bar, "Lv 80", 55, 22, "Toggle max level pets only")
    bar.maxLevelBtn:SetPoint("LEFT", bar.exoticBtn, "RIGHT", 5, 0)
    bar.maxLevelBtn:SetScript("OnClick", function()
        HSP.SetQuickFilter("maxLevel")
        HSP.UpdateUI()
    end)
    
    -- Clear filters
    bar.clearBtn = CreateButton(bar, "Clear", 50, 22, "Clear all filters")
    bar.clearBtn:SetPoint("LEFT", bar.maxLevelBtn, "RIGHT", 5, 0)
    bar.clearBtn:SetScript("OnClick", function()
        HSP.SetQuickFilter("clear")
        bar.searchBox:SetText("")
        UIDropDownMenu_SetText(bar.familyDropdown, "All Families")
        HSP.UpdateUI()
    end)
    
    return bar
end

-- ============================================================================
-- SORT HEADERS
-- ============================================================================

local function CreateSortHeaders(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(FRAME_WIDTH - 20, 24)
    bar:SetPoint("TOP", 0, -HEADER_HEIGHT - FILTER_HEIGHT - 10)
    CreateBackdrop(bar, COLORS.header, { 0, 0, 0, 0 })
    
    local function CreateSortButton(text, field, xPos, width, tooltip)
        local btn = CreateFrame("Button", nil, bar)
        btn:SetSize(width, 24)
        btn:SetPoint("LEFT", xPos, 0)
        
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("LEFT", 5, 0)
        btn.text:SetText(text)
        btn.text:SetTextColor(unpack(COLORS.gold))
        
        btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.arrow:SetPoint("LEFT", btn.text, "RIGHT", 3, 0)
        btn.arrow:SetText("")
        
        btn:SetScript("OnClick", function()
            local db = BeastmasterPlusCharDB
            if db.sortBy == field then
                db.sortOrder = db.sortOrder == "asc" and "desc" or "asc"
            else
                db.sortBy = field
                db.sortOrder = "asc"
            end
            HSP.UpdateUI()
        end)
        
        btn:SetScript("OnEnter", function(self)
            self.text:SetTextColor(1, 1, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(tooltip or ("Sort by " .. text), 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self.text:SetTextColor(unpack(COLORS.gold))
            GameTooltip:Hide()
        end)
        
        btn.field = field
        return btn
    end
    
    bar.headers = {
        CreateSortButton("Icon", nil, 10, 40, "Pet family icon"),
        CreateSortButton("Name", "name", 50, 160, "Sort by pet name"),
        CreateSortButton("Level", "level", 210, 60, "Sort by level"),
        CreateSortButton("Family", "family", 270, 120, "Sort by family type"),
        CreateSortButton("Status", nil, 390, 70, "Active or Exotic status"),
    }
    
    -- Action column header
    local actionLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    actionLabel:SetPoint("LEFT", 520, 0)
    actionLabel:SetText("Actions")
    actionLabel:SetTextColor(unpack(COLORS.gold))
    
    return bar
end

-- ============================================================================
-- PET ROWS (updated with Call button, no slot #)
-- ============================================================================

local function CreatePetRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(FRAME_WIDTH - 20, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 10, -((index - 1) * ROW_HEIGHT))
    
    local bgColor = index % 2 == 0 and COLORS.rowAlt or COLORS.row
    CreateBackdrop(row, bgColor, { 0, 0, 0, 0 })
    
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(COLORS.rowHover))
        if self.petData then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.petData.name, 1, 0.82, 0)
            GameTooltip:AddLine("Level " .. self.petData.level .. " " .. self.petData.family, 1, 1, 1)
            if self.petData.isExotic then
                GameTooltip:AddLine("Exotic (requires Beast Mastery)", 0.7, 0.3, 0.9)
            end
            local fav = HSP.GetFavorite(self.petData.stableIndex)
            if fav.notes and fav.notes ~= "" then
                GameTooltip:AddLine("Notes: " .. fav.notes, 0.7, 0.7, 0.7, true)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Double-click to summon", 0.3, 1, 0.3)
            GameTooltip:AddLine("Slot #" .. self.petData.stableIndex, 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        if selectedRowIndex == self.index then
            self:SetBackdropColor(unpack(COLORS.rowSelected))
        else
            local bg = self.index % 2 == 0 and COLORS.rowAlt or COLORS.row
            self:SetBackdropColor(unpack(bg))
        end
        GameTooltip:Hide()
    end)
    
    row:RegisterForClicks("LeftButtonUp")
    row.lastClick = 0
    row:SetScript("OnClick", function(self)
        if self.petData then
            local now = GetTime()
            local isDoubleClick = (now - self.lastClick) < 0.4
            self.lastClick = now
            
            -- Update selection
            selectedRowIndex = self.index
            HSP.UpdateUI()
            
            if isDoubleClick then
                HSP.AddRecentPet(self.petData)
                HSP.SummonPet(self.petData.petNumber or self.petData.stableIndex, self.petData.name)
            end
        end
    end)
    
    -- Pet icon (family-based)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(28, 28)
    row.icon:SetPoint("LEFT", 10, 0)
    
    -- Pet name
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", 50, 0)
    row.name:SetWidth(150)
    row.name:SetJustifyH("LEFT")
    
    -- Level (color-coded)
    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.level:SetPoint("LEFT", 210, 0)
    row.level:SetWidth(50)
    row.level:SetJustifyH("CENTER")
    
    -- Family
    row.family = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.family:SetPoint("LEFT", 270, 0)
    row.family:SetWidth(110)
    row.family:SetJustifyH("LEFT")
    row.family:SetTextColor(unpack(COLORS.textDim))
    
    -- Status badge (exotic/active)
    row.badge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.badge:SetPoint("LEFT", 390, 0)
    row.badge:SetWidth(70)
    row.badge:SetJustifyH("LEFT")
    
    -- Favorite star button
    row.favBtn = CreateFrame("Button", nil, row)
    row.favBtn:SetSize(28, 28)
    row.favBtn:SetPoint("LEFT", 465, 0)
    row.favBtn.star = row.favBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.favBtn.star:SetPoint("CENTER", 0, 0)
    row.favBtn.star:SetText("*")
    row.favBtn.star:SetTextColor(0.4, 0.4, 0.4, 1)
    row.favBtn:SetScript("OnClick", function(self)
        local pet = self:GetParent().petData
        if pet then
            HSP.ToggleFavorite(pet.stableIndex)
            HSP.UpdateUI()
        end
    end)
    row.favBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Toggle Favorite", 1, 1, 1)
        GameTooltip:AddLine("Favorited pets appear in the Favorites panel", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    row.favBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- CALL BUTTON (new)
    row.callBtn = CreateButton(row, "Call", 50, 24, "Summon this pet")
    row.callBtn:SetPoint("LEFT", 500, 0)
    row.callBtn:SetScript("OnClick", function(self)
        local pet = self:GetParent().petData
        if pet then
            HSP.AddRecentPet(pet)
            HSP.SummonPet(pet.petNumber or pet.stableIndex, pet.name)
        end
    end)

    row.dismissBtn = CreateButton(row, "Dismiss", 70, 24, "Dismiss active pet")
    row.dismissBtn:SetPoint("LEFT", 555, 0)
    row.dismissBtn:SetScript("OnClick", function(self)
        local pet = self:GetParent().petData
        if pet then
            HSP.DismissPet(pet.petNumber or pet.stableIndex, pet.name)
        end
    end)

    row.index = index
    return row
end

local function CreatePetList(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(FRAME_WIDTH - 20, ROW_HEIGHT * ROWS_VISIBLE)
    container:SetPoint("TOP", 0, -HEADER_HEIGHT - FILTER_HEIGHT - 40)
    
    -- Empty state message
    container.emptyMsg = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    container.emptyMsg:SetPoint("CENTER", 0, 0)
    container.emptyMsg:SetText("|cFF888888No pets found.|r\n\nUse /bmp refresh to load pets from server\nor /bmp add to manually add pets.")
    container.emptyMsg:SetTextColor(unpack(COLORS.textDim))
    container.emptyMsg:Hide()
    
    container.rows = {}
    for i = 1, ROWS_VISIBLE do
        container.rows[i] = CreatePetRow(container, i)
    end
    
    return container
end

-- ============================================================================
-- PAGINATION
-- ============================================================================

local function CreatePagination(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(FRAME_WIDTH - 20, FOOTER_HEIGHT)
    bar:SetPoint("BOTTOM", 0, 10)
    CreateBackdrop(bar, COLORS.header, { 0, 0, 0, 0 })
    
    -- Previous button
    bar.prevBtn = CreateButton(bar, "< Prev", 70, 24, "Previous page")
    bar.prevBtn:SetPoint("LEFT", 10, 0)
    bar.prevBtn:SetScript("OnClick", function()
        HSP.PrevPage()
        HSP.UpdateUI()
    end)
    
    -- Page info
    bar.pageInfo = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bar.pageInfo:SetPoint("CENTER")
    bar.pageInfo:SetTextColor(unpack(COLORS.text))
    
    -- Next button
    bar.nextBtn = CreateButton(bar, "Next >", 70, 24, "Next page")
    bar.nextBtn:SetPoint("RIGHT", -10, 0)
    bar.nextBtn:SetScript("OnClick", function()
        HSP.NextPage()
        HSP.UpdateUI()
    end)
    
    -- Items per page dropdown
    local perPageItems = {
        { text = "10 per page", value = 10 },
        { text = "25 per page", value = 25 },
        { text = "50 per page", value = 50 },
    }
    
    bar.perPageDropdown = CreateDropdown(bar, 100, perPageItems, function(value)
        BeastmasterPlusCharDB.itemsPerPage = value
        HSP.SetPage(1)
        HSP.UpdateUI()
    end)
    bar.perPageDropdown:SetPoint("LEFT", bar.prevBtn, "RIGHT", 10, -2)
    UIDropDownMenu_SetText(bar.perPageDropdown, "25 per page")
    
    return bar
end

-- ============================================================================
-- FAVORITES PANEL (side panel - fixed)
-- ============================================================================

local function CreateFavoritesPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(220, 350)
    panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", 5, 0)
    CreateBackdrop(panel, COLORS.background, COLORS.border)
    
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cFFFFD100Favorites|r")
    
    -- Empty state for favorites
    panel.emptyMsg = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.emptyMsg:SetPoint("CENTER", 0, 0)
    panel.emptyMsg:SetText("|cFF888888No favorites yet.|r\n\nClick the star on any pet\nto add it here.")
    panel.emptyMsg:SetTextColor(unpack(COLORS.textDim))
    
    panel.content = CreateFrame("Frame", nil, panel)
    panel.content:SetSize(200, 280)
    panel.content:SetPoint("TOP", 0, -35)
    
    panel.rows = {}
    for i = 1, 8 do
        local row = CreateFrame("Button", nil, panel.content)
        row:SetSize(200, 32)
        row:SetPoint("TOP", 0, -((i - 1) * 34))
        CreateBackdrop(row, COLORS.row, { 0, 0, 0, 0 })
        
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", 5, 0)
        
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", 35, 0)
        row.name:SetWidth(110)
        row.name:SetJustifyH("LEFT")
        
        row.callBtn = CreateButton(row, "Call", 45, 20, "Summon this pet")
        row.callBtn:SetPoint("RIGHT", -5, 0)
        row.callBtn:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 9)
        
        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(unpack(COLORS.rowHover))
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropColor(unpack(COLORS.row))
        end)
        
        row:Hide()
        panel.rows[i] = row
    end
    
    panel:Hide()
    return panel
end

-- ============================================================================
-- RECENT PETS PANEL
-- ============================================================================

local function CreateRecentPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(220, 200)
    panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", 5, -360)
    CreateBackdrop(panel, COLORS.background, COLORS.border)
    
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cFFFFD100Recent|r")
    
    panel.emptyMsg = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.emptyMsg:SetPoint("CENTER", 0, 0)
    panel.emptyMsg:SetText("|cFF888888No recent pets.|r")
    panel.emptyMsg:SetTextColor(unpack(COLORS.textDim))
    
    panel.rows = {}
    for i = 1, 5 do
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(200, 28)
        row:SetPoint("TOP", 0, -30 - ((i - 1) * 30))
        CreateBackdrop(row, COLORS.row, { 0, 0, 0, 0 })
        
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 5, 0)
        
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", 32, 0)
        row.name:SetWidth(110)
        row.name:SetJustifyH("LEFT")
        
        row.callBtn = CreateButton(row, "Call", 45, 20, "Summon this pet")
        row.callBtn:SetPoint("RIGHT", -5, 0)
        row.callBtn:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 9)
        
        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(unpack(COLORS.rowHover))
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropColor(unpack(COLORS.row))
        end)
        
        row:Hide()
        panel.rows[i] = row
    end
    
    panel:Hide()
    return panel
end

-- ============================================================================
-- MINIMAP BUTTON
-- ============================================================================

local function CreateMinimapButton()
    local btn = CreateFrame("Button", "BeastmasterPlusMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    
    btn:SetNormalTexture("Interface\\Icons\\Ability_Hunter_BeastCall")
    btn:GetNormalTexture():SetSize(20, 20)
    btn:GetNormalTexture():SetPoint("CENTER")
    
    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(54, 54)
    overlay:SetPoint("CENTER")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    
    -- Drag functionality (around minimap edge)
    local minimapShape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local angle = 45
    
    local function UpdatePosition()
        local radius = (Minimap:GetWidth() / 2) + 5
        local x = math.cos(math.rad(angle)) * radius
        local y = math.sin(math.rad(angle)) * radius
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
    
    btn:SetScript("OnDragStart", function(self)
        self.dragging = true
    end)
    
    btn:SetScript("OnDragStop", function(self)
        self.dragging = false
    end)
    
    btn:SetScript("OnUpdate", function(self)
        if self.dragging then
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            angle = math.deg(math.atan2(cy - my, cx - mx))
            UpdatePosition()
        end
    end)
    
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            HSP.Toggle()
        elseif button == "RightButton" then
            HSP.RequestPetList()
        end
    end)
    
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Beastmaster Plus", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click: Open pet manager", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Refresh pet list", 1, 1, 1)
        GameTooltip:Show()
    end)
    
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    UpdatePosition()
    return btn
end

-- ============================================================================
-- UPDATE UI
-- ============================================================================

function HSP.UpdateUI()
    local frame = HSP.MainFrame
    if not frame or not frame:IsShown() then return end
    
    local pets, currentPage, totalPages, totalPets = HSP.GetPets()
    local allPets = HSP.GetAllPets and HSP.GetAllPets() or {}
    
    -- Update pet count with filter status
    local filterList = HSP.GetActiveFilters and HSP.GetActiveFilters() or {}
    frame.petCount:SetText(totalPets .. " of " .. #allPets .. " pets")
    if #filterList > 0 then
        frame.filterStatus:SetText("(" .. table.concat(filterList, ", ") .. ")")
    else
        frame.filterStatus:SetText("")
    end
    
    -- Update quick filter button states
    local db = BeastmasterPlusCharDB
    if frame.filterBar then
        if db.filterExoticOnly then
            frame.filterBar.exoticBtn:SetText("|cFFFFD100Exotic|r")
        else
            frame.filterBar.exoticBtn:SetText("Exotic")
        end
        if db.filterMinLevel == 80 then
            frame.filterBar.maxLevelBtn:SetText("|cFFFFD100Lv 80|r")
        else
            frame.filterBar.maxLevelBtn:SetText("Lv 80")
        end
    end
    
    -- Show/hide empty state
    if #pets == 0 then
        frame.petList.emptyMsg:Show()
    else
        frame.petList.emptyMsg:Hide()
    end
    
    -- Update rows
    for i, row in ipairs(frame.petList.rows) do
        local pet = pets[i]
        if pet then
            row:Show()
            row.petData = pet
            row.name:SetText(pet.name)
            
            -- Level with color coding
            row.level:SetText(pet.level)
            row.level:SetTextColor(unpack(GetLevelColor(pet.level)))
            
            row.family:SetText(pet.family)
            
            -- Icon (family-based)
            local iconPath = GetFamilyIcon(pet.family)
            row.icon:SetTexture(iconPath)
            
            -- Badge (exotic/active)
            if pet.isActive then
                row.badge:SetText("|cFF00FF00Active|r")
            elseif pet.isExotic then
                row.badge:SetText("|cFF9933FFExotic|r")
            else
                row.badge:SetText("")
            end
            
            -- Favorite star
            local fav = HSP.GetFavorite(pet.stableIndex)
            if fav.isFavorite then
                row.favBtn.star:SetText("*")
                row.favBtn.star:SetTextColor(1, 0.82, 0.2, 1)
                row.favBtn.star:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
            else
                row.favBtn.star:SetText("*")
                row.favBtn.star:SetTextColor(0.4, 0.4, 0.4, 1)
                row.favBtn.star:SetFont("Fonts\\FRIZQT__.TTF", 18, "")
            end
            
            -- Selection highlight
            if selectedRowIndex == i then
                row:SetBackdropColor(unpack(COLORS.rowSelected))
            else
                local bg = i % 2 == 0 and COLORS.rowAlt or COLORS.row
                row:SetBackdropColor(unpack(bg))
            end
        else
            row:Hide()
        end
    end
    
    -- Update pagination
    frame.pagination.pageInfo:SetText(string.format("Page %d of %d", currentPage, math.max(1, totalPages)))
    frame.pagination.prevBtn:SetEnabled(currentPage > 1)
    frame.pagination.nextBtn:SetEnabled(currentPage < totalPages)
    
    -- Update favorites panel
    local favIndex = 1
    local hasFavorites = false
    for _, pet in ipairs(allPets) do
        local fav = HSP.GetFavorite(pet.stableIndex)
        if fav.isFavorite and frame.favPanel.rows[favIndex] then
            hasFavorites = true
            local row = frame.favPanel.rows[favIndex]
            row.icon:SetTexture(GetFamilyIcon(pet.family))
            row.name:SetText(pet.name .. " |cFF666666Lv" .. pet.level .. "|r")
            row.petData = pet
            row.callBtn:SetScript("OnClick", function()
                HSP.AddRecentPet(pet)
                HSP.SummonPet(pet.petNumber or pet.stableIndex, pet.name)
            end)
            row:Show()
            favIndex = favIndex + 1
        end
    end
    for i = favIndex, #frame.favPanel.rows do
        frame.favPanel.rows[i]:Hide()
    end
    frame.favPanel.emptyMsg:SetShown(not hasFavorites)
    
    -- Update recent pets panel
    local recentPets = HSP.GetRecentPets and HSP.GetRecentPets() or {}
    local hasRecent = #recentPets > 0
    for i, row in ipairs(frame.recentPanel.rows) do
        local pet = recentPets[i]
        if pet then
            row.icon:SetTexture(GetFamilyIcon(pet.family))
            row.name:SetText(pet.name)
            row.petData = pet
            row.callBtn:SetScript("OnClick", function()
                HSP.SummonPet(pet.petNumber, pet.name)
            end)
            row:Show()
        else
            row:Hide()
        end
    end
    frame.recentPanel.emptyMsg:SetShown(not hasRecent)
    
    -- Update sort arrows
    if frame.sortHeaders then
        for _, header in ipairs(frame.sortHeaders.headers) do
            if header.field and header.field == db.sortBy then
                header.arrow:SetText(db.sortOrder == "asc" and " ^" or " v")
            else
                header.arrow:SetText("")
            end
        end
    end
end

-- ============================================================================
-- INITIALIZE UI
-- ============================================================================

local function InitializeUI()
    local success, err = pcall(function()
        local frame = CreateMainFrame()
        frame.filterBar = CreateFilterBar(frame)
        frame.sortHeaders = CreateSortHeaders(frame)
        frame.petList = CreatePetList(frame)
        frame.pagination = CreatePagination(frame)
        frame.favPanel = CreateFavoritesPanel(frame)
        frame.recentPanel = CreateRecentPanel(frame)
        
        frame:Hide()
        HSP.MainFrame = frame
        
        -- Refresh button
        local refreshBtn = CreateButton(frame, "Refresh", 70, 22, "Fetch pets from server")
        refreshBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -140, -8)
        refreshBtn:SetScript("OnClick", function()
            HSP.Refresh()
        end)
        
        -- Toggle favorites panel
        local favToggle = CreateButton(frame, "Favorites", 80, 22, "Show/hide favorites panel")
        favToggle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -50, -8)
        favToggle:SetScript("OnClick", function()
            local showFav = not frame.favPanel:IsShown()
            frame.favPanel:SetShown(showFav)
            frame.recentPanel:SetShown(showFav)
            if showFav then HSP.UpdateUI() end
        end)
        
        -- Create minimap button
        CreateMinimapButton()
    end)
    
    if success then
        print("|cFFFFD100Beastmaster Plus:|r UI ready. Type /bmp or use minimap button.")
    else
        print("|cFFFF0000Beastmaster Plus ERROR:|r " .. tostring(err))
    end
end

InitializeUI()
