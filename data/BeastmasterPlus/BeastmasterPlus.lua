-- ============================================================================
-- BEASTMASTER PLUS - Core Logic
-- WoW 3.3.5a (WotLK) Addon for managing 99+ stabled hunter pets
-- ============================================================================

local addonName, HSP = ...

-- SavedVariables
BeastmasterPlusDB = BeastmasterPlusDB or {}
BeastmasterPlusCharDB = BeastmasterPlusCharDB or {}

local defaults = {
    favorites = {},
    sortBy = "name",
    sortOrder = "asc",
    filterFamily = nil,
    filterExoticOnly = false,
    filterFavoritesOnly = false,
    filterMinLevel = 1,
    filterMaxLevel = 80,
    frameWidth = 600,
    frameHeight = 500,
    minimapAngle = 225,
    itemsPerPage = 25,
    compactMode = false,
}

-- Pet family ID to name mapping (from WoW 3.3.5a CreatureFamily.dbc)
local PET_FAMILIES = {
    [1] = "Wolf",
    [2] = "Cat",
    [3] = "Spider",
    [4] = "Bear",
    [5] = "Boar",
    [6] = "Crocolisk",
    [7] = "Carrion Bird",
    [8] = "Crab",
    [9] = "Gorilla",
    [11] = "Raptor",
    [12] = "Tallstrider",
    [15] = "Felhunter",
    [16] = "Voidwalker",
    [17] = "Succubus",
    [19] = "Doomguard",
    [20] = "Scorpid",
    [21] = "Turtle",
    [23] = "Imp",
    [24] = "Bat",
    [25] = "Hyena",
    [26] = "Bird of Prey",
    [27] = "Wind Serpent",
    [28] = "Remote Control",
    [29] = "Felguard",
    [30] = "Dragonhawk",
    [31] = "Ravager",
    [32] = "Warp Stalker",
    [33] = "Sporebat",
    [34] = "Nether Ray",
    [35] = "Serpent",
    [37] = "Moth",
    [38] = "Chimaera",
    [39] = "Devilsaur",
    [40] = "Ghoul",
    [41] = "Silithid",
    [42] = "Worm",
    [43] = "Rhino",
    [44] = "Wasp",
    [45] = "Core Hound",
    [46] = "Spirit Beast",
}

-- Also keep a name-indexed list for UI display
local PET_FAMILY_NAMES = {
    "Bat", "Bear", "Bird of Prey", "Boar", "Carrion Bird", "Cat",
    "Chimaera", "Core Hound", "Crab", "Crocolisk", "Devilsaur",
    "Doomguard", "Dragonhawk", "Felhunter", "Felguard", "Ghoul",
    "Gorilla", "Hyena", "Imp", "Moth", "Nether Ray", "Raptor",
    "Ravager", "Rhino", "Scorpid", "Serpent", "Silithid", "Spider",
    "Spirit Beast", "Sporebat", "Succubus", "Tallstrider", "Turtle",
    "Voidwalker", "Warp Stalker", "Wasp", "Wind Serpent", "Wolf", "Worm"
}

-- Exotic families (require Beast Mastery)
local EXOTIC_FAMILIES = {
    ["Chimaera"] = true,
    ["Core Hound"] = true,
    ["Devilsaur"] = true,
    ["Silithid"] = true,
    ["Spirit Beast"] = true,
    ["Worm"] = true,
}

-- Expose to HSP namespace immediately (needed by UI file)
HSP.PET_FAMILIES = PET_FAMILIES
HSP.PET_FAMILY_NAMES = PET_FAMILY_NAMES
HSP.EXOTIC_FAMILIES = EXOTIC_FAMILIES

-- Local state
local pets = {}
local searchText = ""
local scrollOffset = 0
local currentPage = 1
local isLoaded = false
local debugMode = false
local logHistory = {}
local MAX_LOG_HISTORY = 100

-- Buffer safety limits (prevent crash from huge server responses)
local MAX_BUFFER_CHARS = 200000
local chunkCount = 0

-- Anti-spam for LIST requests (minimum 2 seconds between requests)
local lastListRequest = 0
local LIST_COOLDOWN = 2.0

-- Guard against double PETS_END handling
local listCompleted = false

-- Delay helper (3.3.5a safe, no C_Timer)
local function After(seconds, fn)
    local t = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        if t >= seconds then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            fn()
        end
    end)
end

-- Forward declarations for functions called before definition
local SavePetCache
local LoadPetCache

-- ============================================================================
-- DEBUG/LOGGING SYSTEM
-- ============================================================================

local function Log(level, message, ...)
    local timestamp = date("%H:%M:%S")
    local formatted = message
    if select("#", ...) > 0 then
        local success, result = pcall(string.format, message or "nil", ...)
        formatted = success and result or (message .. " [format error]")
    end
    local entry = string.format("[%s] [%s] %s", timestamp, level, formatted or "nil")
    
    table.insert(logHistory, entry)
    if #logHistory > MAX_LOG_HISTORY then
        table.remove(logHistory, 1)
    end
    
    if level == "ERROR" then
        print("|cFFFF0000BMP ERROR:|r " .. (formatted or "nil"))
    elseif level == "WARN" then
        print("|cFFFFAA00BMP WARN:|r " .. (formatted or "nil"))
    elseif level == "INFO" then
        print("|cFFFFD100BMP:|r " .. (formatted or "nil"))
    elseif level == "DEBUG" and debugMode then
        print("|cFF888888BMP DEBUG:|r " .. (formatted or "nil"))
    end
end

local function Debug(msg, ...) Log("DEBUG", msg, ...) end
local function Info(msg, ...) Log("INFO", msg, ...) end
local function Warn(msg, ...) Log("WARN", msg, ...) end
local function Error(msg, ...) Log("ERROR", msg, ...) end

function HSP.SetDebugMode(enabled)
    debugMode = enabled
    if enabled then
        print("|cFF00FF00BMP Debug mode ENABLED|r - verbose logging active")
    else
        print("|cFFFFD100BMP Debug mode DISABLED|r")
    end
end

function HSP.ShowLog(count)
    count = count or 20
    print("|cFFFFD100=== BMP Log History (last " .. count .. " entries) ===|r")
    local start = math.max(1, #logHistory - count + 1)
    for i = start, #logHistory do
        print(logHistory[i])
    end
    print("|cFFFFD100=== End of Log ===|r")
end

function HSP.DumpPetData()
    print("|cFFFFD100=== BMP Pet Data Dump ===|r")
    print("Total raw pets: " .. #pets)
    for i, pet in ipairs(pets) do
        print(string.format("  [%d] Slot:%d Name:%s Lvl:%s Family:%s", 
            i, pet.stableIndex or 0, tostring(pet.name), tostring(pet.level), 
            tostring(pet.family)))
    end
    print("|cFFFFD100=== End Dump ===|r")
end

-- ============================================================================
-- SERVER ADDON MESSAGE PROTOCOL
-- ============================================================================
local ADDON_PREFIX = "BMP"

-- Buffer for multi-part messages
local messageBuffer = ""
local bufferTimeout = 0

local function AppendPetData(chunk)
    if not chunk or chunk == "" then
        return
    end
    if messageBuffer ~= "" and messageBuffer:sub(-1) ~= ";" and chunk:sub(1, 1) ~= ";" then
        messageBuffer = messageBuffer .. ";" .. chunk
    else
        messageBuffer = messageBuffer .. chunk
    end
end

-- Send summon request to server via addon message
function HSP.SummonPet(petNumber, petName)
    if not petNumber then
        Warn("Cannot summon: missing pet ID")
        return
    end
    
    local msg = "SUMMON|" .. tostring(petNumber)
    Info("Sending summon request: prefix=BMP, message=%s", msg)
    SendAddonMessage(ADDON_PREFIX, msg, "WHISPER", UnitName("player"))
    print("|cFFFFD100BMP:|r Summoning " .. (petName or "pet") .. "...")
end

-- Dismiss active pet. Prefer built-in dismiss to match core behavior.
-- Falls back to BMP protocol if PetDismiss is unavailable.
function HSP.DismissPet(petNumber, petName)
    if type(PetDismiss) == "function" and UnitExists("pet") then
        PetDismiss()
        print("|cFFFFD100BMP:|r Pet dismissed.")
        return
    end

    local msg = "DISMISS"
    if petNumber then
        msg = "DISMISS|" .. tostring(petNumber)
    end
    Info("Sending dismiss request: prefix=BMP, message=%s", msg)
    SendAddonMessage(ADDON_PREFIX, msg, "WHISPER", UnitName("player"))
    print("|cFFFFD100BMP:|r Dismissing " .. (petName or "pet") .. "...")
end

function HSP.NormalizePets()
    local msg = "NORMALIZE"
    Info("Sending normalize request: prefix=BMP, message=%s", msg)
    SendAddonMessage(ADDON_PREFIX, msg, "WHISPER", UnitName("player"))
    print("|cFFFFD100BMP:|r Normalizing slot=0 pets (GM only)...")
end

local function EnsurePetTalentUI()
    if TogglePetTalentFrame or PetTalentFrame_Toggle or PetTalentFrame then
        return true
    end

    local addons = { "Blizzard_PetTalentUI", "Blizzard_PetTalents", "Blizzard_TalentUI" }
    for _, addon in ipairs(addons) do
        if IsAddOnLoaded and LoadAddOn and not IsAddOnLoaded(addon) then
            LoadAddOn(addon)
        end
    end

    if type(TalentFrame_LoadUI) == "function" then
        TalentFrame_LoadUI()
    end
    if type(PetTalentFrame_LoadUI) == "function" then
        PetTalentFrame_LoadUI()
    end

    return TogglePetTalentFrame or PetTalentFrame_Toggle or PetTalentFrame
end

local function ShowPetTalentTab()
    if not TalentFrame or not TalentFrameTab_OnClick then
        return false
    end
    local tabId = TALENTFRAME_TABID_PET or 3
    local tab = _G["TalentFrameTab" .. tabId]
    if not tab then
        return false
    end
    TalentFrameTab_OnClick(tab)
    return true
end

-- Open pet talents (client-side)
function HSP.OpenPetTalents()
    if UnitExists("pet") then
        EnsurePetTalentUI()
        -- WotLK 3.3.5a uses TogglePetTalentFrame() for pet talents
        if TogglePetTalentFrame then
            TogglePetTalentFrame()
            ShowPetTalentTab()
        elseif PetTalentFrame_Toggle then
            PetTalentFrame_Toggle()
        elseif PetTalentFrame then
            if PetTalentFrame:IsShown() then
                PetTalentFrame:Hide()
            else
                PetTalentFrame:Show()
            end
        elseif ToggleTalentFrame then
            ToggleTalentFrame()
            if not ShowPetTalentTab() then
                if TalentFrame and TalentFrame:IsShown() then
                    TalentFrame:Hide()
                end
                Warn("Pet talent frame not available.")
            end
        else
            Warn("Pet talent frame not available.")
        end
    else
        Warn("You must have a pet summoned to view talents.")
    end
end

-- Open pet spellbook (client-side)
function HSP.OpenPetSpellbook()
    if UnitExists("pet") then
        ToggleSpellBook(BOOKTYPE_PET)
    else
        Warn("You must have a pet summoned to view spells.")
    end
end

-- Request pet list from server
function HSP.RequestPetList()
    if not isLoaded then return end
    
    local target = UnitName("player")
    if not target or target == "" then
        Debug("RequestPetList: no player name yet, skipping")
        return
    end
    
    local now = GetTime()
    if now - lastListRequest < LIST_COOLDOWN then
        Debug("RequestPetList: cooldown active, skipping (%.1fs remaining)", LIST_COOLDOWN - (now - lastListRequest))
        return
    end
    lastListRequest = now
    
    Info("Requesting pet list from server: prefix=%s, message=LIST", ADDON_PREFIX)
    messageBuffer = ""
    bufferTimeout = 0
    chunkCount = 0
    listCompleted = false
    SendAddonMessage(ADDON_PREFIX, "LIST", "WHISPER", target)
end

-- Refresh from server
function HSP.Refresh()
    Info("Requesting fresh data from server...")
    HSP.RequestPetList()
end

-- Clear cache and refresh from server
function HSP.ClearAndRefresh()
    pets = {}
    BeastmasterPlusCharDB.petCache = {}
    BeastmasterPlusCharDB.cacheTime = nil
    BeastmasterPlusCharDB.manualPets = {}
    Info("Cache and manual pets cleared. Requesting fresh data from server...")
    scrollOffset = 0
    currentPage = 1
    if HSP.MainFrame and HSP.MainFrame:IsShown() then
        HSP.UpdateUI()
    end
    HSP.RequestPetList()
end

-- Family to icon mapping for WoW 3.3.5a
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
    ["Doomguard"] = "Interface\\Icons\\Spell_Shadow_SummonDoomGuard",
    ["Dragonhawk"] = "Interface\\Icons\\Ability_Hunter_Pet_DragonHawk",
    ["Felhunter"] = "Interface\\Icons\\Spell_Shadow_SummonFelHunter",
    ["Felguard"] = "Interface\\Icons\\Spell_Shadow_SummonFelGuard",
    ["Ghoul"] = "Interface\\Icons\\Ability_Creature_Cursed_05",
    ["Gorilla"] = "Interface\\Icons\\Ability_Hunter_Pet_Gorilla",
    ["Hyena"] = "Interface\\Icons\\Ability_Hunter_Pet_Hyena",
    ["Imp"] = "Interface\\Icons\\Spell_Shadow_SummonImp",
    ["Moth"] = "Interface\\Icons\\Ability_Hunter_Pet_Moth",
    ["Nether Ray"] = "Interface\\Icons\\Ability_Hunter_Pet_NetherRay",
    ["Raptor"] = "Interface\\Icons\\Ability_Hunter_Pet_Raptor",
    ["Ravager"] = "Interface\\Icons\\Ability_Hunter_Pet_Ravager",
    ["Rhino"] = "Interface\\Icons\\Ability_Hunter_Pet_Rhino",
    ["Scorpid"] = "Interface\\Icons\\Ability_Hunter_Pet_Scorpid",
    ["Serpent"] = "Interface\\Icons\\Spell_Nature_GuardianWard",
    ["Silithid"] = "Interface\\Icons\\Ability_Hunter_Pet_Silithid",
    ["Spider"] = "Interface\\Icons\\Ability_Hunter_Pet_Spider",
    ["Spirit Beast"] = "Interface\\Icons\\Ability_Druid_PrimalPrecision",
    ["Sporebat"] = "Interface\\Icons\\Ability_Hunter_Pet_Sporebat",
    ["Succubus"] = "Interface\\Icons\\Spell_Shadow_SummonSuccubus",
    ["Tallstrider"] = "Interface\\Icons\\Ability_Hunter_Pet_TallStrider",
    ["Turtle"] = "Interface\\Icons\\Ability_Hunter_Pet_Turtle",
    ["Voidwalker"] = "Interface\\Icons\\Spell_Shadow_SummonVoidWalker",
    ["Warp Stalker"] = "Interface\\Icons\\Ability_Hunter_Pet_WarpStalker",
    ["Wasp"] = "Interface\\Icons\\Ability_Hunter_Pet_Wasp",
    ["Wind Serpent"] = "Interface\\Icons\\Ability_Hunter_Pet_WindSerpent",
    ["Wolf"] = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
    ["Worm"] = "Interface\\Icons\\Ability_Hunter_Pet_Worm",
    ["Unknown"] = "Interface\\Icons\\INV_Misc_QuestionMark",
}

HSP.FAMILY_ICONS = FAMILY_ICONS

local function GetFamilyIcon(family)
    return FAMILY_ICONS[family] or FAMILY_ICONS["Unknown"]
end

local function ResolveFamily(creatureId, familyId)
    local resolvedId = tonumber(familyId)
    if not resolvedId or resolvedId == 0 then
        local entry = tonumber(creatureId)
        if entry and HSP.PET_ENTRY_FAMILY then
            resolvedId = HSP.PET_ENTRY_FAMILY[entry]
        end
    end
    return PET_FAMILIES[resolvedId] or "Unknown", resolvedId
end

-- Parse pet data from server response
-- NEW format: Slot|CreatureId|Level|Name|Flags|FamilyId (6 fields)
function HSP.ParseServerPetData(message)
    local serverPets = {}
    local seenSlots = {}
    
    for petData in message:gmatch("[^;]+") do
        -- Try 6-field format first (new server payload with familyId)
        -- Use [^|]* to allow empty names
        local slot, creatureId, level, name, flags, familyId = petData:match("(%d+)|(%d+)|(%d+)|([^|]*)|(%d+)|(%d+)")
        
        -- Fallback to 5-field format (old server payload)
        if not slot then
            slot, creatureId, level, name, flags = petData:match("(%d+)|(%d+)|(%d+)|([^|]*)|(%d+)")
            familyId = nil
        end
        
        if slot then
            local slotNum = tonumber(slot)
            if not seenSlots[slotNum] then
                seenSlots[slotNum] = true
                local isActive = (tonumber(flags) or 0) > 0
                
                -- Resolve family from familyId or fallback to entry->family map
                local family = ResolveFamily(creatureId, familyId)
                
                -- Ensure name has a fallback if empty
                local petName = (name and name ~= "") and tostring(name) or ("Slot " .. slotNum)
                
                table.insert(serverPets, {
                    petNumber = slotNum,
                    creatureId = tonumber(creatureId),
                    level = tonumber(level) or 1,
                    name = petName,
                    isActive = isActive,
                    stableIndex = slotNum,
                    family = family,
                    icon = GetFamilyIcon(family),
                    isExotic = EXOTIC_FAMILIES[family] or false,
                })
                Debug("Parsed pet slot %d: %s (Lv%d, %s)", slotNum, name, tonumber(level), family)
            end
        end
    end
    
    return serverPets
end

-- Process buffered messages (for multi-part PETS responses)
function HSP.ProcessPetBuffer()
    if messageBuffer ~= "" then
        local serverPets = HSP.ParseServerPetData(messageBuffer)
        if #serverPets > 0 then
            pets = serverPets
            SavePetCache()
            Info("Loaded %d pets from server", #serverPets)
            print("|cFF00FF00BMP:|r Loaded " .. #pets .. " pets")
            scrollOffset = 0
            currentPage = 1
            if HSP.MainFrame and HSP.MainFrame:IsShown() then
                HSP.UpdateUI()
            end
        end
        messageBuffer = ""
    end
end

-- Handle server payload (called from OnAddonMessage after filtering)
function HSP.HandleServerPayload(msg)
    if not msg or msg == "" then return end
    
    if debugMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[BMP RX]|r " .. tostring(msg):sub(1, 80))
    end
    
    if msg:find("^PETS|") then
        local petData = msg:sub(6)
        AppendPetData(petData)
        bufferTimeout = GetTime() + 0.5
        HSP.ProcessPetBuffer()
        
    elseif msg:find("^PETS_CHUNK|") then
        local petData = msg:sub(12)
        AppendPetData(petData)
        chunkCount = chunkCount + 1
        bufferTimeout = GetTime() + 1.0
        
        if #messageBuffer > MAX_BUFFER_CHARS then
            Warn("Server payload too large, resetting buffer")
            messageBuffer = ""
            chunkCount = 0
            return
        end
        
        if debugMode and (chunkCount == 1 or chunkCount % 5 == 0) then
            Debug("Received chunk %d (buffer=%d chars)", chunkCount, #messageBuffer)
        end
        
    elseif msg:find("^PETS_END") then
        if listCompleted then
            Debug("Ignoring duplicate PETS_END")
            return
        end
        listCompleted = true
        
        Debug("Received PETS_END, parsing buffered data (%d chunks)", chunkCount)
        
        local data = messageBuffer
        messageBuffer = ""
        local totalChunks = chunkCount
        chunkCount = 0
        
        local serverPets = HSP.ParseServerPetData(data)
        if serverPets and #serverPets > 0 then
            pets = serverPets
        end
        
        local petCount = #pets
        local chunkTotal = totalChunks
        
        After(0.0, function()
            SavePetCache()
            scrollOffset = 0
            currentPage = 1
            if HSP.MainFrame and HSP.MainFrame:IsShown() then
                HSP.UpdateUI()
            end
            Info("Loaded %d pets from %d chunks", petCount, chunkTotal)
            print("|cFF00FF00BMP:|r Loaded " .. tostring(petCount) .. " pets")
        end)
        
    elseif msg:find("^ERROR|") then
        local errMsg = tostring(msg:sub(7) or "Unknown error")
        Warn("Server error: %s", errMsg)
        print("|cFFFF0000BMP Error:|r " .. errMsg)
        
        -- Handle NO_PET error: clear stuck state and auto-refresh after delay
        if errMsg == "NO_PET" or errMsg:find("NO_PET") then
            -- Reset state to allow new summon attempts
            After(1.5, function()
                Info("Refreshing pet list after NO_PET error...")
                HSP.RequestPetList()
            end)
        end
        
    elseif msg:find("^OK|") then
        local okMsg = tostring(msg:sub(4) or "")
        Info("Server: %s", okMsg)
        print("|cFF00FF00BMP:|r " .. okMsg)
        
    elseif msg:find("^SUMMONED|") then
        local petName = tostring(msg:sub(10) or "pet")
        print("|cFF00FF00BMP:|r " .. petName .. " summoned!")
        HSP.RequestPetList()

    elseif msg:find("^DISMISSED|") then
        local petName = tostring(msg:sub(11) or "pet")
        print("|cFF00FF00BMP:|r " .. petName .. " dismissed!")
        HSP.RequestPetList()
        
    else
        Debug("Unknown message type: %s", msg)
    end
end

-- Handle addon messages from CHAT_MSG_ADDON event
function HSP.OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= ADDON_PREFIX then return end
    
    local playerName = UnitName("player")
    local isLocalEcho = (sender == playerName)
    
    if isLocalEcho then
        if message == "LIST" or message == "NORMALIZE" or message:find("^SUMMON|") or message:find("^DISMISS") then
            Debug("Ignoring local echo: %s", message)
            return
        end
    end
    
    if debugMode then
        print("|cFF00CCFF[BMP RECV]|r sender=" .. tostring(sender) .. " msg=" .. tostring(message):sub(1, 60))
    end
    
    if message:find("^PETS|") or 
       message:find("^PETS_CHUNK|") or 
       message == "PETS_END" or
       message:find("^OK|") or
       message:find("^ERROR|") or
       message:find("^SUMMONED|") or
       message:find("^DISMISSED|") then
        Debug("Server payload: %s", message:sub(1, 40))
        HSP.HandleServerPayload(message)
    else
        Debug("Unknown/ignored message: %s", message:sub(1, 40))
    end
end

-- Manual pet management
function HSP.AddPet(slot, name, level, family)
    if not BeastmasterPlusCharDB.manualPets then
        BeastmasterPlusCharDB.manualPets = {}
    end
    BeastmasterPlusCharDB.manualPets[slot] = {
        stableIndex = slot,
        name = name,
        level = level or 1,
        family = family or "Unknown",
        icon = GetFamilyIcon(family or "Unknown"),
        isExotic = EXOTIC_FAMILIES[family] or false,
        isActive = false,
        isManual = true,
    }
    Info("Added pet: %s (slot %d, level %d, %s)", name, slot, level or 1, family or "Unknown")
end

function HSP.RemovePet(slot)
    if BeastmasterPlusCharDB.manualPets and BeastmasterPlusCharDB.manualPets[slot] then
        local pet = BeastmasterPlusCharDB.manualPets[slot]
        BeastmasterPlusCharDB.manualPets[slot] = nil
        Info("Removed pet: %s from slot %d", pet.name, slot)
    else
        Warn("No manual pet in slot %d", slot)
    end
end

function HSP.ListManualPets()
    if not BeastmasterPlusCharDB.manualPets then
        Info("No manually added pets.")
        return
    end
    print("|cFFFFD100=== Manually Added Pets ===|r")
    local count = 0
    for slot, pet in pairs(BeastmasterPlusCharDB.manualPets) do
        print(string.format("  Slot %d: %s (Lv%d %s)", slot, pet.name, pet.level, pet.family))
        count = count + 1
    end
    if count == 0 then
        print("  (none)")
    end
end

function HSP.FindPetByNumber(petNumber)
    if not petNumber then
        return nil
    end

    for _, pet in ipairs(pets) do
        if pet.petNumber == petNumber or pet.stableIndex == petNumber then
            return pet
        end
    end

    return nil
end

-- ============================================================================
-- PET DATA MANAGEMENT (with caching)
-- ============================================================================

SavePetCache = function()
    BeastmasterPlusCharDB.petCache = {}
    for _, pet in ipairs(pets) do
        table.insert(BeastmasterPlusCharDB.petCache, {
            stableIndex = pet.stableIndex,
            petNumber = pet.petNumber,
            name = pet.name,
            level = pet.level,
            family = pet.family,
            icon = pet.icon,
            isExotic = pet.isExotic,
            isActive = pet.isActive,
        })
    end
    BeastmasterPlusCharDB.cacheTime = time()
    Debug("Saved %d pets to cache", #pets)
end

LoadPetCache = function()
    if BeastmasterPlusCharDB.petCache and #BeastmasterPlusCharDB.petCache > 0 then
        pets = {}
        for _, cached in ipairs(BeastmasterPlusCharDB.petCache) do
            table.insert(pets, cached)
        end
        local cacheAge = time() - (BeastmasterPlusCharDB.cacheTime or 0)
        Debug("Loaded %d pets from cache (age: %d seconds)", #pets, cacheAge)
        return true
    end
    return false
end

local function RefreshPetData()
    Debug("RefreshPetData: Loading from cache only")
    
    if #pets == 0 then
        LoadPetCache()
    end
    
    if BeastmasterPlusCharDB.manualPets then
        for slot, manualPet in pairs(BeastmasterPlusCharDB.manualPets) do
            local exists = false
            for _, pet in ipairs(pets) do
                if pet.stableIndex == slot then
                    exists = true
                    break
                end
            end
            if not exists then
                table.insert(pets, manualPet)
            end
        end
    end
    
    Debug("Total pets: %d", #pets)
    return pets
end

-- ============================================================================
-- FILTERING AND SORTING
-- ============================================================================

local function FilterPets(petList)
    local db = BeastmasterPlusCharDB
    local filtered = {}
    
    for _, pet in ipairs(petList) do
        local include = true
        local petName = tostring(pet.name or "")
        local petFamily = tostring(pet.family or "")
        local petLevel = tonumber(pet.level) or 1
        
        if searchText and searchText ~= "" then
            local search = searchText:lower()
            if not petName:lower():find(search, 1, true) and
               not petFamily:lower():find(search, 1, true) then
                include = false
            end
        end
        
        if include and db.filterFamily and db.filterFamily ~= "" then
            if petFamily ~= db.filterFamily then
                include = false
            end
        end
        
        if include and db.filterExoticOnly then
            if not pet.isExotic then
                include = false
            end
        end
        
        if include and db.filterFavoritesOnly then
            local fav = HSP.GetFavorite(pet.stableIndex or pet.petNumber)
            if not fav or not fav.isFavorite then
                include = false
            end
        end
        
        if include then
            local minLevel = db.filterMinLevel or 1
            local maxLevel = db.filterMaxLevel or 80
            if petLevel < minLevel or petLevel > maxLevel then
                include = false
            end
        end
        
        if include then
            table.insert(filtered, pet)
        end
    end
    
    return filtered
end

local function SortPets(petList)
    local db = BeastmasterPlusCharDB
    local sortBy = db.sortBy or "name"
    local sortOrder = db.sortOrder or "asc"
    
    table.sort(petList, function(a, b)
        local valA, valB
        
        if sortBy == "name" then
            valA, valB = tostring(a.name or ""):lower(), tostring(b.name or ""):lower()
        elseif sortBy == "level" then
            valA, valB = tonumber(a.level) or 1, tonumber(b.level) or 1
        elseif sortBy == "family" then
            valA, valB = tostring(a.family or ""):lower(), tostring(b.family or ""):lower()
        else
            valA, valB = a.stableIndex or a.petNumber or 0, b.stableIndex or b.petNumber or 0
        end
        
        if valA == valB then
            local idxA = a.stableIndex or a.petNumber or 0
            local idxB = b.stableIndex or b.petNumber or 0
            return idxA < idxB
        end

        if sortOrder == "desc" then
            return valA > valB
        else
            return valA < valB
        end
    end)
    
    return petList
end

local function GetFilteredSortedPets()
    local petList = RefreshPetData()
    petList = FilterPets(petList)
    petList = SortPets(petList)
    return petList
end

-- ============================================================================
-- PAGINATION (legacy UI compatibility)
-- ============================================================================

local function GetPagedPets()
    local allPets = GetFilteredSortedPets()
    local db = BeastmasterPlusCharDB
    local perPage = db.itemsPerPage or defaults.itemsPerPage or 25
    local totalPages = math.max(1, math.ceil(#allPets / perPage))
    if currentPage > totalPages then
        currentPage = totalPages
    elseif currentPage < 1 then
        currentPage = 1
    end

    local startIndex = ((currentPage - 1) * perPage) + 1
    local endIndex = math.min(startIndex + perPage - 1, #allPets)

    local pagedPets = {}
    for i = startIndex, endIndex do
        table.insert(pagedPets, allPets[i])
    end

    return pagedPets, currentPage, totalPages, #allPets
end

-- ============================================================================
-- SCROLLING (replaces pagination)
-- ============================================================================

function HSP.GetVisiblePets(rowCount)
    local allPets = GetFilteredSortedPets()
    local startIndex = scrollOffset + 1
    local endIndex = math.min(scrollOffset + rowCount, #allPets)
    
    local visiblePets = {}
    for i = startIndex, endIndex do
        table.insert(visiblePets, allPets[i])
    end
    
    return visiblePets, #allPets, scrollOffset
end

function HSP.SetScrollOffset(offset, maxRows)
    local allPets = GetFilteredSortedPets()
    local maxOffset = math.max(0, #allPets - maxRows)
    scrollOffset = math.max(0, math.min(offset, maxOffset))
end

function HSP.ScrollUp(amount)
    scrollOffset = math.max(0, scrollOffset - (amount or 1))
end

function HSP.ScrollDown(amount, maxRows)
    local allPets = GetFilteredSortedPets()
    local maxOffset = math.max(0, #allPets - maxRows)
    scrollOffset = math.min(maxOffset, scrollOffset + (amount or 1))
end

-- ============================================================================
-- FAVORITES MANAGEMENT
-- ============================================================================

function HSP.GetFavorite(stableIndex)
    local favorites = BeastmasterPlusDB.favorites or {}
    if not stableIndex then
        return { isFavorite = false, notes = "" }
    end
    return favorites[stableIndex] or { isFavorite = false, notes = "" }
end

function HSP.SetFavorite(stableIndex, isFavorite, notes)
    if not stableIndex then
        return
    end
    BeastmasterPlusDB.favorites = BeastmasterPlusDB.favorites or {}
    BeastmasterPlusDB.favorites[stableIndex] = {
        isFavorite = isFavorite or false,
        notes = notes or "",
    }
end

function HSP.ToggleFavorite(stableIndex)
    if not stableIndex then
        return false
    end
    local fav = HSP.GetFavorite(stableIndex)
    HSP.SetFavorite(stableIndex, not fav.isFavorite, fav.notes)
    return not fav.isFavorite
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

local recentPets = {}
local MAX_RECENT = 5

local function AddRecentPet(petData)
    if not petData then return end
    local petNumber = petData.petNumber or petData.stableIndex
    if not petNumber then
        return
    end
    for i = #recentPets, 1, -1 do
        if recentPets[i].petNumber == petNumber then
            table.remove(recentPets, i)
        end
    end
    table.insert(recentPets, 1, {
        petNumber = petNumber,
        name = petData.name,
        level = petData.level,
        family = petData.family,
        icon = petData.icon,
    })
    while #recentPets > MAX_RECENT do
        table.remove(recentPets)
    end
end

HSP.RefreshPets = RefreshPetData
HSP.GetPets = GetPagedPets
HSP.GetAllPets = function() return RefreshPetData() end
HSP.GetTotalPetCount = function() return #pets end
HSP.GetRecentPets = function() return recentPets end
HSP.AddRecentPet = AddRecentPet

HSP.SetPage = function(page)
    currentPage = math.max(1, tonumber(page) or 1)
end

HSP.NextPage = function()
    local _, _, totalPages = GetPagedPets()
    if currentPage < totalPages then
        currentPage = currentPage + 1
    end
end

HSP.PrevPage = function()
    if currentPage > 1 then
        currentPage = currentPage - 1
    end
end

HSP.SetItemsPerPage = function(count)
    BeastmasterPlusCharDB.itemsPerPage = math.max(1, tonumber(count) or defaults.itemsPerPage or 25)
    currentPage = 1
end

-- Quick filter helpers
HSP.SetQuickFilter = function(filterType)
    if filterType == "exotic" then
        BeastmasterPlusCharDB.filterExoticOnly = not BeastmasterPlusCharDB.filterExoticOnly
    elseif filterType == "favorites" then
        BeastmasterPlusCharDB.filterFavoritesOnly = not BeastmasterPlusCharDB.filterFavoritesOnly
    elseif filterType == "clear" then
        BeastmasterPlusCharDB.filterFamily = nil
        BeastmasterPlusCharDB.filterExoticOnly = false
        BeastmasterPlusCharDB.filterFavoritesOnly = false
        BeastmasterPlusCharDB.filterMinLevel = 1
        BeastmasterPlusCharDB.filterMaxLevel = 80
        searchText = ""
    end
    scrollOffset = 0
    currentPage = 1
end

HSP.GetActiveFilters = function()
    local filters = {}
    local db = BeastmasterPlusCharDB
    if db.filterFamily then table.insert(filters, db.filterFamily) end
    if db.filterExoticOnly then table.insert(filters, "Exotic") end
    if db.filterFavoritesOnly then table.insert(filters, "Favorites") end
    if db.filterMinLevel and db.filterMinLevel > 1 then table.insert(filters, "Lv" .. db.filterMinLevel .. "+") end
    if db.filterMaxLevel and db.filterMaxLevel < 80 then table.insert(filters, "Lv" .. db.filterMaxLevel .. "-") end
    return filters
end

HSP.SetSearch = function(text)
    searchText = text or ""
    scrollOffset = 0
    currentPage = 1
end

HSP.SetSort = function(sortBy, sortOrder)
    BeastmasterPlusCharDB.sortBy = sortBy
    if sortOrder then
        BeastmasterPlusCharDB.sortOrder = sortOrder
    end
    scrollOffset = 0
    currentPage = 1
end

HSP.ToggleSortOrder = function()
    local db = BeastmasterPlusCharDB
    db.sortOrder = db.sortOrder == "asc" and "desc" or "asc"
end

HSP.SetFilter = function(filterType, value)
    if filterType == "family" then
        BeastmasterPlusCharDB.filterFamily = value
    elseif filterType == "exotic" then
        BeastmasterPlusCharDB.filterExoticOnly = value
    elseif filterType == "favorites" then
        BeastmasterPlusCharDB.filterFavoritesOnly = value
    elseif filterType == "minLevel" then
        BeastmasterPlusCharDB.filterMinLevel = value
    elseif filterType == "maxLevel" then
        BeastmasterPlusCharDB.filterMaxLevel = value
    end
    scrollOffset = 0
    currentPage = 1
end

HSP.ClearFilters = function()
    BeastmasterPlusCharDB.filterFamily = nil
    BeastmasterPlusCharDB.filterExoticOnly = false
    BeastmasterPlusCharDB.filterFavoritesOnly = false
    BeastmasterPlusCharDB.filterMinLevel = 1
    BeastmasterPlusCharDB.filterMaxLevel = 80
    searchText = ""
    scrollOffset = 0
    currentPage = 1
end

HSP.ToggleCompactMode = function()
    BeastmasterPlusCharDB.compactMode = not BeastmasterPlusCharDB.compactMode
    return BeastmasterPlusCharDB.compactMode
end

HSP.IsCompactMode = function()
    return BeastmasterPlusCharDB.compactMode or false
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

SLASH_BEASTMASTERPLUS1 = "/bmp"
SLASH_BEASTMASTERPLUS2 = "/beastmaster"

SlashCmdList["BEASTMASTERPLUS"] = function(msg)
    local _, playerClass = UnitClass("player")
    if playerClass ~= "HUNTER" then
        print("|cFFFF6600Beastmaster Plus|r is only available for Hunters.")
        return
    end
    
    msg = msg:lower():trim()
    
    if msg == "show" or msg == "" then
        if HSP.MainFrame then
            HSP.MainFrame:Show()
            HSP.UpdateUI()
            Info("Opening stable manager...")
        else
            Warn("UI is loading, please wait a moment and try again.")
        end
    elseif msg == "hide" then
        if HSP.MainFrame then
            HSP.MainFrame:Hide()
        end
    elseif msg == "refresh" then
        HSP.Refresh()
        print("|cFFFFD100BMP:|r Requesting pet list from server...")
    elseif msg == "count" then
        RefreshPetData()
        Info("You have %d stabled pets.", #pets)
    elseif msg == "debug" or msg == "debug on" then
        HSP.SetDebugMode(true)
    elseif msg == "debug off" then
        HSP.SetDebugMode(false)
    elseif msg == "log" then
        HSP.ShowLog(20)
    elseif msg:find("^log ") then
        local count = tonumber(msg:match("^log (%d+)"))
        HSP.ShowLog(count or 20)
    elseif msg == "dump" then
        HSP.DumpPetData()
    elseif msg:find("^add ") then
        local slot, name, level, family = msg:match("^add (%d+) ([^%s]+) (%d+) (.+)")
        if slot and name then
            HSP.AddPet(tonumber(slot), name, tonumber(level) or 1, family or "Unknown")
            RefreshPetData()
            if HSP.MainFrame and HSP.MainFrame:IsShown() then HSP.UpdateUI() end
        else
            Warn("Usage: /bmp add <slot> <name> <level> <family>")
            Info("Example: /bmp add 10 Fluffy 55 Wolf")
        end
    elseif msg:find("^remove ") then
        local slot = tonumber(msg:match("^remove (%d+)"))
        if slot then
            HSP.RemovePet(slot)
            RefreshPetData()
            if HSP.MainFrame and HSP.MainFrame:IsShown() then HSP.UpdateUI() end
        else
            Warn("Usage: /bmp remove <slot>")
        end
    elseif msg:find("^dismiss") then
        local slot = tonumber(msg:match("^dismiss (%d+)"))
        if not slot then
            for _, pet in ipairs(pets) do
                if pet.isActive then
                    slot = pet.petNumber or pet.stableIndex
                    break
                end
            end
        end
        if slot then
            local pet = HSP.FindPetByNumber(slot) or { petNumber = slot, name = "pet" }
            HSP.DismissPet(pet.petNumber, pet.name)
        else
            Warn("Usage: /bmp dismiss <petNumber>")
        end
    elseif msg == "normalize" then
        HSP.NormalizePets()
    elseif msg == "list" then
        HSP.ListManualPets()
    elseif msg == "clear" then
        HSP.ClearAndRefresh()
    elseif msg == "compact" then
        local compact = HSP.ToggleCompactMode()
        Info("Compact mode: %s", compact and "ON" or "OFF")
        if HSP.MainFrame and HSP.MainFrame:IsShown() then HSP.UpdateUI() end
    else
        print("|cFFFFD100Beastmaster Plus commands:|r")
        print("  /bmp - Open stable manager")
        print("  /bmp refresh - Request pet list from server")
        print("  /bmp clear - Clear cache and refresh from server")
        print("  /bmp count - Show pet count")
        print("  /bmp compact - Toggle compact mode")
        print("  /bmp dismiss <petNumber> - Dismiss active pet (not permanent)")
        print("  /bmp normalize - Normalize slot=0 pets (GM only)")
        print("|cFF888888Debug:|r")
        print("  /bmp debug - Toggle debug mode")
        print("  /bmp dump - Dump pet data")
    end
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("UNIT_PET")
eventFrame:RegisterEvent("PET_UI_UPDATE")

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(ADDON_PREFIX)
end

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
    if event == "ADDON_LOADED" and arg1 == addonName then
        local _, playerClass = UnitClass("player")
        if playerClass ~= "HUNTER" then
            isLoaded = false
            return
        end
        
        for key, value in pairs(defaults) do
            if BeastmasterPlusDB[key] == nil then
                BeastmasterPlusDB[key] = value
            end
            if BeastmasterPlusCharDB[key] == nil then
                BeastmasterPlusCharDB[key] = value
            end
        end
        isLoaded = true
        print("|cFFFFD100Beastmaster Plus|r loaded. Type /bmp for commands.")
        
    elseif event == "PLAYER_LOGIN" then
        local _, playerClass = UnitClass("player")
        if playerClass ~= "HUNTER" then
            isLoaded = false
            return
        end
        
        LoadPetCache()
        if #pets > 0 then
            Info("Loaded %d pets from cache.", #pets)
        end
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not isLoaded then return end
        
        if HSP._didInitialRefresh then return end
        HSP._didInitialRefresh = true
        
        After(3.0, function()
            if not UnitExists("player") then return end
            if not UnitName("player") then return end
            HSP.RequestPetList()
        end)
        
    elseif event == "CHAT_MSG_ADDON" then
        HSP.OnAddonMessage(arg1, arg2, arg3, arg4)
    elseif event == "UNIT_PET" then
        if not isLoaded then return end
        if arg1 ~= "player" then return end
        HSP.RequestPetList()
    elseif event == "PET_UI_UPDATE" then
        if not isLoaded then return end
        HSP.RequestPetList()
    end
end)

_G.BeastmasterPlus = HSP
