-- Beastmaster Plus Minimal UI (debug-focused)

local addonName, HSP = ...

local DEFAULT_WIDTH = 620
local DEFAULT_HEIGHT = 440
local HEADER_HEIGHT = 72
local FOOTER_HEIGHT = 28
local ROW_HEIGHT = 24
local SCROLLBAR_WIDTH = 16
local MINIMAP_BUTTON_SIZE = 32
local MINIMAP_ICON_SIZE = 14
local MINIMAP_BG_SIZE = 22
local MINIMAP_BORDER_SIZE = 54
local MINIMAP_BORDER_OFFSET_X = 0
local MINIMAP_BORDER_OFFSET_Y = 0
local MINIMAP_HIGHLIGHT_OFFSET_X = 0
local MINIMAP_HIGHLIGHT_OFFSET_Y = 0
local MINIMAP_ICON_OFFSET_X = 0
local MINIMAP_ICON_OFFSET_Y = 0

local selectedRowIndex = 1
local selectedPet = nil
local selectedPetId = nil

local COLORS = {
    text = { 0.95, 0.95, 0.95, 1 },
    textDim = { 0.75, 0.75, 0.75, 1 },
    highlight = { 1, 0.82, 0.2, 1 },
}

local function GetFamilyIcon(family)
    local icons = HSP.FAMILY_ICONS or {}
    if type(family) == "number" then
        family = (HSP.PET_FAMILIES and HSP.PET_FAMILIES[family]) or family
    end
    return icons[family] or icons["Unknown"] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function FormatPetNameForDisplay(petData)
    if petData then
        local name = petData.name
        if name and name ~= "" then
            return tostring(name)
        end
        local slot = tonumber(petData.stableIndex or petData.petNumber)
        if slot then
            return string.format("Slot %02d", slot)
        end
    end
    return "Pet"
end

local function FormatPetFamilyForDisplay(petData)
    if petData and petData.family then
        if type(petData.family) == "number" and HSP.PET_FAMILIES then
            return HSP.PET_FAMILIES[petData.family] or "Unknown"
        end
        if petData.family ~= "" then
            return tostring(petData.family)
        end
    end
    return "Unknown"
end

local function CreateBackdrop(frame)
    if not frame.SetBackdrop then
        return
    end
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
end

local function CreateButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 70, height or 22)
    btn:SetText(text)
    return btn
end

local function CreateEditBox(parent, width, height, placeholder)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(width or 160, height or 22)
    edit:SetAutoFocus(false)
    edit:SetFont("Fonts\\FRIZQT__.TTF", 10)
    if placeholder then
        edit.placeholder = edit:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        edit.placeholder:SetPoint("LEFT", 5, 0)
        edit.placeholder:SetText(placeholder)
        edit:SetScript("OnEditFocusGained", function(self)
            self.placeholder:Hide()
        end)
        edit:SetScript("OnEditFocusLost", function(self)
            if self:GetText() == "" then
                self.placeholder:Show()
            end
        end)
        edit:SetScript("OnTextChanged", function(self)
            if self:GetText() == "" and not self:HasFocus() then
                self.placeholder:Show()
            else
                self.placeholder:Hide()
            end
        end)
    end
    return edit
end

local function CreatePetRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 4, -((index - 1) * ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", -4, -((index - 1) * ROW_HEIGHT))
    row:RegisterForClicks("AnyUp")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetWidth(210)
    row.name:SetJustifyH("LEFT")

    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.level:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.level:SetWidth(40)
    row.level:SetJustifyH("CENTER")

    row.family = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.family:SetPoint("LEFT", row.level, "RIGHT", 8, 0)
    row.family:SetJustifyH("LEFT")

    row.lastClick = 0
    row:SetScript("OnClick", function(self)
        if not self.petData then
            return
        end
        local now = GetTime()
        local isDoubleClick = (now - self.lastClick) < 0.4
        self.lastClick = now

        selectedRowIndex = self.rowIndex or 1
        selectedPet = self.petData
        selectedPetId = self.petData.petNumber or self.petData.stableIndex
        HSP.UpdateUI()

        if isDoubleClick then
            HSP.AddRecentPet(self.petData)
            HSP.SummonPet(self.petData.petNumber or self.petData.stableIndex, self.petData.name or "pet")
        end
    end)

    return row
end

local function CreatePetList(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", 8, -HEADER_HEIGHT)
    container:SetPoint("BOTTOMRIGHT", -(8 + SCROLLBAR_WIDTH), FOOTER_HEIGHT + 8)
    container.rows = {}

    local scrollFrame = CreateFrame("ScrollFrame", "BeastmasterPlusScrollFrame", parent, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", container, "TOPRIGHT", 2, 0)
    scrollFrame:SetPoint("BOTTOMLEFT", container, "BOTTOMRIGHT", 2, 0)
    scrollFrame:SetWidth(SCROLLBAR_WIDTH)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        if not FauxScrollFrame_OnVerticalScroll then
            return
        end
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function()
            local maxRows = math.max(1, math.floor(container:GetHeight() / ROW_HEIGHT))
            if FauxScrollFrame_GetOffset then
                local newOffset = FauxScrollFrame_GetOffset(self) or 0
                HSP.SetScrollOffset(newOffset, maxRows)
                HSP.UpdateUI()
            end
        end)
    end)

    parent.scrollFrame = scrollFrame
    return container
end

function HSP.RebuildRows()
    local frame = HSP.MainFrame
    if not frame or not frame.petList then return end

    local container = frame.petList
    local listHeight = container:GetHeight()
    local maxRows = math.max(1, math.floor(listHeight / ROW_HEIGHT))

    for _, row in ipairs(container.rows) do
        row:Hide()
        row:SetParent(nil)
    end
    container.rows = {}

    for i = 1, maxRows do
        container.rows[i] = CreatePetRow(container, i)
    end
end

function HSP.UpdateUI()
    local frame = HSP.MainFrame
    if not frame or not frame:IsShown() then return end

    local container = frame.petList
    local listHeight = container:GetHeight()
    local maxRows = math.max(1, math.floor(listHeight / ROW_HEIGHT))

    if #container.rows ~= maxRows then
        HSP.RebuildRows()
    end

    local pets, totalPets, scrollOff = HSP.GetVisiblePets(maxRows)
    pets = pets or {}

    if frame.scrollFrame and FauxScrollFrame_Update then
        FauxScrollFrame_Update(frame.scrollFrame, totalPets, maxRows, ROW_HEIGHT)
        if frame.scrollFrame.GetVerticalScroll and frame.scrollFrame.SetVerticalScroll then
            local desired = (scrollOff or 0) * ROW_HEIGHT
            if math.abs((frame.scrollFrame:GetVerticalScroll() or 0) - desired) > 0.1 then
                frame.scrollFrame:SetVerticalScroll(desired)
            end
        end
    end

    if selectedPetId then
        for idx, pet in ipairs(pets) do
            local petId = pet and (pet.petNumber or pet.stableIndex)
            if petId and petId == selectedPetId then
                selectedRowIndex = idx
                break
            end
        end
    end

    if selectedRowIndex > #pets then
        selectedRowIndex = math.max(1, #pets)
    end
    if selectedRowIndex < 1 then
        selectedRowIndex = 1
    end

    selectedPet = pets[selectedRowIndex]
    if selectedPet then
        selectedPetId = selectedPet.petNumber or selectedPet.stableIndex
    end

    if frame.petCount then
        frame.petCount:SetText(totalPets .. " pets")
    end

    for i, row in ipairs(container.rows) do
        local pet = pets[i]
        if pet then
            row:Show()
            row.rowIndex = i
            row.petData = pet

            local name = FormatPetNameForDisplay(pet)
            local family = FormatPetFamilyForDisplay(pet)
            row.name:SetText(name)
            row.level:SetText(tostring(pet.level or "?"))
            row.family:SetText(family)
            row.icon:SetTexture(pet.icon or GetFamilyIcon(family))

            if i == selectedRowIndex then
                row.name:SetTextColor(unpack(COLORS.highlight))
            else
                row.name:SetTextColor(unpack(COLORS.text))
            end
        else
            row:Hide()
        end
    end
end

local function CreateMainFrame()
    local db = BeastmasterPlusCharDB or {}
    local frameWidth = db.frameWidth or DEFAULT_WIDTH
    local frameHeight = db.frameHeight or DEFAULT_HEIGHT

    local frame = CreateFrame("Frame", "BeastmasterPlusFrame", UIParent)
    frame:SetSize(frameWidth, frameHeight)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        BeastmasterPlusCharDB.frameWidth = frame:GetWidth()
        BeastmasterPlusCharDB.frameHeight = frame:GetHeight()
    end)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")

    CreateBackdrop(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("|cFFFFD100Beastmaster Plus|r")

    frame.petCount = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.petCount:SetPoint("LEFT", title, "RIGHT", 12, 0)
    frame.petCount:SetTextColor(unpack(COLORS.textDim))

    local searchBox = CreateEditBox(frame, 160, 22, "Search...")
    searchBox:SetPoint("TOPLEFT", 12, -32)
    searchBox:SetScript("OnTextChanged", function(self)
        HSP.SetSearch(self:GetText() or "")
        HSP.UpdateUI()
    end)
    frame.searchBox = searchBox

    local function CreateSortHeader(text, field, x, width)
        local btn = CreateFrame("Button", nil, frame)
        btn:SetSize(width or 60, 16)
        btn:SetPoint("TOPLEFT", x, -56)

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", 0, 0)
        label:SetText(text)
        btn.label = label

        btn:SetScript("OnEnter", function(self)
            self.label:SetTextColor(unpack(COLORS.highlight))
        end)
        btn:SetScript("OnLeave", function(self)
            self.label:SetTextColor(unpack(COLORS.text))
        end)
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

        label:SetTextColor(unpack(COLORS.text))
        return btn
    end

    CreateSortHeader("Name", "name", 36, 210)
    CreateSortHeader("Lv", "level", 254, 40)
    CreateSortHeader("Family", "family", 302, 120)

    local refreshBtn = CreateButton(frame, "Refresh", 70, 20)
    refreshBtn:SetPoint("TOPRIGHT", -90, -32)
    refreshBtn:SetScript("OnClick", function()
        HSP.Refresh()
    end)

    local summonBtn = CreateButton(frame, "Summon", 70, 22)
    summonBtn:SetPoint("BOTTOMRIGHT", -12, 8)
    summonBtn:SetScript("OnClick", function()
        local petId = selectedPet and (selectedPet.petNumber or selectedPet.stableIndex) or selectedPetId
        if petId then
            if selectedPet then
                HSP.AddRecentPet(selectedPet)
            end
            HSP.SummonPet(petId, selectedPet and selectedPet.name or "pet")
        end
    end)
    frame.summonBtn = summonBtn

    local dismissBtn = CreateButton(frame, "Dismiss", 70, 22)
    dismissBtn:SetPoint("RIGHT", summonBtn, "LEFT", -6, 0)
    dismissBtn:SetScript("OnClick", function()
        local petId = nil
        if selectedPet and selectedPet.isActive then
            petId = selectedPet.petNumber or selectedPet.stableIndex
        end
        HSP.DismissPet(petId, selectedPet and selectedPet.name or "pet")
    end)
    frame.dismissBtn = dismissBtn

    frame.petList = CreatePetList(frame)

    frame:EnableKeyboard(true)
    frame:SetScript("OnKeyDown", function(self, key)
        local listHeight = frame.petList:GetHeight()
        local maxRows = math.max(1, math.floor(listHeight / ROW_HEIGHT))
        local pets = HSP.GetVisiblePets(maxRows)

        if key == "ESCAPE" then
            self:Hide()
        elseif key == "UP" then
            if selectedRowIndex > 1 then
                selectedRowIndex = selectedRowIndex - 1
            else
                HSP.ScrollUp(1)
            end
            HSP.UpdateUI()
        elseif key == "DOWN" then
            if selectedRowIndex < #pets and selectedRowIndex < maxRows then
                selectedRowIndex = selectedRowIndex + 1
            else
                HSP.ScrollDown(1, maxRows)
            end
            HSP.UpdateUI()
        elseif key == "ENTER" then
            local petId = selectedPet and (selectedPet.petNumber or selectedPet.stableIndex) or selectedPetId
            if petId then
                if selectedPet then
                    HSP.AddRecentPet(selectedPet)
                end
                HSP.SummonPet(petId, selectedPet and selectedPet.name or "pet")
            end
        end
    end)

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(self, delta)
        local listHeight = frame.petList:GetHeight()
        local maxRows = math.max(1, math.floor(listHeight / ROW_HEIGHT))
        if delta > 0 then
            HSP.ScrollUp(3)
        else
            HSP.ScrollDown(3, maxRows)
        end
        HSP.UpdateUI()
    end)

    frame:SetScript("OnSizeChanged", function()
        HSP.RebuildRows()
        HSP.UpdateUI()
    end)

    return frame
end

local function NormalizeAngle(angle)
    angle = tonumber(angle) or 0
    angle = angle % 360
    if angle < 0 then
        angle = angle + 360
    end
    return angle
end

local function CreateMinimapButton()
    local btn = CreateFrame("Button", "BeastmasterPlusMinimapButton", MinimapCluster or Minimap)
    btn:SetSize(MINIMAP_BUTTON_SIZE, MINIMAP_BUTTON_SIZE)
    btn:SetFrameStrata("MEDIUM")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local highlight = btn:GetHighlightTexture()
    if highlight then
        highlight:ClearAllPoints()
        highlight:SetPoint("TOPLEFT", btn, "TOPLEFT", MINIMAP_HIGHLIGHT_OFFSET_X, MINIMAP_HIGHLIGHT_OFFSET_Y)
        highlight:SetSize(MINIMAP_BUTTON_SIZE, MINIMAP_BUTTON_SIZE)
    end
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp")
    btn:RegisterForDrag("LeftButton")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(MINIMAP_BG_SIZE, MINIMAP_BG_SIZE)
    bg:SetPoint("CENTER", MINIMAP_ICON_OFFSET_X, MINIMAP_ICON_OFFSET_Y)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(MINIMAP_ICON_SIZE, MINIMAP_ICON_SIZE)
    icon:SetPoint("CENTER", MINIMAP_ICON_OFFSET_X, MINIMAP_ICON_OFFSET_Y)
    icon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastCall")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(MINIMAP_BORDER_SIZE, MINIMAP_BORDER_SIZE)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", MINIMAP_BORDER_OFFSET_X, MINIMAP_BORDER_OFFSET_Y)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local angle = NormalizeAngle(BeastmasterPlusCharDB.minimapAngle or 225)

    local function UpdatePosition()
        if not Minimap then return end
        local minimapWidth = Minimap:GetWidth() or 0
        local minimapHeight = Minimap:GetHeight() or 0
        local minimapRadius = math.min(minimapWidth, minimapHeight) / 2
        local radius = minimapRadius + 12
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
        angle = NormalizeAngle(angle)
        BeastmasterPlusCharDB.minimapAngle = angle
        UpdatePosition()
    end)

    btn:SetScript("OnUpdate", function(self)
        if self.dragging then
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            angle = NormalizeAngle(math.deg(math.atan2(cy - my, cx - mx)))
            UpdatePosition()
        end
    end)

    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if HSP.MainFrame then
                if HSP.MainFrame:IsShown() then
                    HSP.MainFrame:Hide()
                else
                    HSP.MainFrame:Show()
                    HSP.UpdateUI()
                end
            end
        elseif button == "RightButton" then
            HSP.RequestPetList()
        end
    end)

    UpdatePosition()
    return btn
end

function HSP.Toggle()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "HUNTER" then
        return
    end

    if HSP.MainFrame then
        if HSP.MainFrame:IsShown() then
            HSP.MainFrame:Hide()
        else
            HSP.MainFrame:Show()
            HSP.UpdateUI()
        end
    end
end

local function InitializeUI()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "HUNTER" then
        return
    end

    local frame = CreateMainFrame()
    frame:Hide()
    HSP.MainFrame = frame

    frame:HookScript("OnShow", function()
        if #frame.petList.rows == 0 then
            HSP.RebuildRows()
        end
        HSP.UpdateUI()
    end)

    CreateMinimapButton()
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    InitializeUI()
end)
