-- Beastmaster Plus
-- Manage up to 99 stabled hunter pets
-- Requires custom server/client with extended stable API

local addonName, HSP = ...

-- Raw debug handler removed - was causing log spam and potential instability

-- Saved variables (loaded after ADDON_LOADED event)
BeastmasterPlusDB = BeastmasterPlusDB or {}
BeastmasterPlusCharDB = BeastmasterPlusCharDB or {}

-- Default settings
local defaults = {
    favorites = {},      -- [stableIndex] = { isFavorite = bool, notes = string }
    sortBy = "name",     -- "name", "level", "family"
    sortOrder = "asc",   -- "asc", "desc"
    itemsPerPage = 25,
    filterFamily = nil,
    filterExoticOnly = false,
    filterMinLevel = 1,
    filterMaxLevel = 80,
}

-- Pet family list (WotLK 3.3.5a)
local PET_FAMILIES = {
    "Bat", "Bear", "Bird of Prey", "Boar", "Carrion Bird", "Cat",
    "Chimaera", "Core Hound", "Crab", "Crocolisk", "Devilsaur",
    "Dragonhawk", "Gorilla", "Hyena", "Moth", "Nether Ray",
    "Raptor", "Ravager", "Rhino", "Scorpid", "Serpent", "Silithid",
    "Spider", "Spirit Beast", "Sporebat", "Tallstrider", "Turtle",
    "Warp Stalker", "Wasp", "Wind Serpent", "Wolf", "Worm"
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
HSP.EXOTIC_FAMILIES = EXOTIC_FAMILIES

-- Local state
local pets = {}
local currentPage = 1
local searchText = ""
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
    
    -- Store in history
    table.insert(logHistory, entry)
    if #logHistory > MAX_LOG_HISTORY then
        table.remove(logHistory, 1)
    end
    
    -- Print based on level
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
        print(string.format("  [%d] Slot:%d Name:%s Lvl:%s Family:%s Icon:%s", 
            i, pet.stableIndex or 0, tostring(pet.name), tostring(pet.level), 
            tostring(pet.family), pet.icon and "yes" or "nil"))
    end
    print("|cFFFFD100=== End Dump ===|r")
end

-- ============================================================================
-- CUSTOM SERVER API FUNCTIONS
-- These functions must be implemented by your custom WoW server/client
-- The default WoW 3.3.5a client only supports 5 stable slots
-- ============================================================================

-- Check if custom API is available
local function HasCustomAPI()
    return type(HSP_GetStablePetInfo) == "function"
end

-- Get pet info from custom stable slot (1-99)
-- Returns: name, level, family, icon, isExotic, isActive
local function GetExtendedStablePetInfo(index)
    if HasCustomAPI() then
        Debug("Using custom API for slot %d", index)
        return HSP_GetStablePetInfo(index)
    end
    -- Try standard API for any slot (some servers support higher indices)
    -- GetStablePetInfo returns: icon, name, level, petType, talent
    local icon, name, level, petType, talent = GetStablePetInfo(index)
    if name then
        Debug("Slot %d: icon=%s, name=%s, level=%s, type=%s", 
            index, tostring(icon), tostring(name), tostring(level), tostring(petType))
        return name, level or 1, petType or "Unknown", icon, false, false
    end
    return nil
end

-- ============================================================================
-- SERVER ADDON MESSAGE PROTOCOL
-- ============================================================================
local ADDON_PREFIX = "BMP"

-- Buffer for multi-part messages (declared early so all functions can access)
local messageBuffer = ""
local bufferTimeout = 0

-- Send summon request to server via addon message
-- WoW combines: prefix + "\t" + message -> server sees "BMP\tSUMMON|<petNumber>"
function HSP.SummonPet(petNumber, petName)
    if not petNumber then
        Warn("Cannot summon: missing pet ID")
        return
    end
    
    -- Just send the command - WoW automatically prepends "BMP\t"
    local msg = "SUMMON|" .. tostring(petNumber)
    Info("Sending summon request: prefix=BMP, message=%s", msg)
    SendAddonMessage(ADDON_PREFIX, msg, "WHISPER", UnitName("player"))
    print("|cFFFFD100BMP:|r Summoning " .. (petName or "pet") .. "...")
end

-- Request pet list from server
function HSP.RequestPetList()
    if not isLoaded then return end
    
    local target = UnitName("player")
    if not target or target == "" then
        Debug("RequestPetList: no player name yet, skipping")
        return
    end
    
    -- Anti-spam: refuse if we sent a request recently
    local now = GetTime()
    if now - lastListRequest < LIST_COOLDOWN then
        Debug("RequestPetList: cooldown active, skipping (%.1fs remaining)", LIST_COOLDOWN - (now - lastListRequest))
        return
    end
    lastListRequest = now
    
    Info("Requesting pet list from server: prefix=%s, message=LIST", ADDON_PREFIX)
    -- Clear any pending buffer from previous requests
    messageBuffer = ""
    bufferTimeout = 0
    chunkCount = 0
    listCompleted = false  -- Reset completion flag for new request
    -- Just send "LIST" - WoW automatically prepends "BMP\t"
    SendAddonMessage(ADDON_PREFIX, "LIST", "WHISPER", target)
end

-- Refresh from server (requests new data, doesn't clear existing until new data arrives)
function HSP.Refresh()
    Info("Requesting fresh data from server...")
    -- Request fresh data - existing pets remain visible until new data arrives
    HSP.RequestPetList()
end

-- Clear cache and refresh from server (use for full reset)
function HSP.ClearAndRefresh()
    -- Clear local pet list
    pets = {}
    -- Clear saved cache
    BeastmasterPlusCharDB.petCache = {}
    BeastmasterPlusCharDB.cacheTime = nil
    -- Clear manual pets too
    BeastmasterPlusCharDB.manualPets = {}
    Info("Cache and manual pets cleared. Requesting fresh data from server...")
    -- Reset to page 1
    currentPage = 1
    -- Update UI to show empty state
    if HSP.MainFrame and HSP.MainFrame:IsShown() then
        HSP.UpdateUI()
    end
    -- Request fresh data from server
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

-- Get icon for a pet family
local function GetFamilyIcon(family)
    return FAMILY_ICONS[family] or FAMILY_ICONS["Unknown"]
end

-- Parse pet data from server response
-- Expected format: Slot|CreatureId|Level|Name|Flags (semicolon delimited)
function HSP.ParseServerPetData(message)
    local serverPets = {}
    local seenSlots = {} -- Track already-added slots to prevent duplicates
    
    -- Handle multiple pets separated by semicolons
    for petData in message:gmatch("[^;]+") do
        local slot, creatureId, level, name, flags = petData:match("(%d+)|(%d+)|(%d+)|([^|]+)|(%d+)")
        if slot then
            local slotNum = tonumber(slot)
            -- Only add if we haven't seen this slot yet
            if not seenSlots[slotNum] then
                seenSlots[slotNum] = true
                local isActive = (tonumber(flags) or 0) > 0
                local family = HSP.GetFamilyFromCreature(tonumber(creatureId)) or "Unknown"
                table.insert(serverPets, {
                    petNumber = slotNum,
                    creatureId = tonumber(creatureId),
                    level = tonumber(level),
                    name = name,
                    isActive = isActive,
                    stableIndex = slotNum, -- Use actual slot from server
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
            -- Always print confirmation (visible proof that pets loaded)
            print("|cFF00FF00BMP:|r Loaded " .. #pets .. " pets")
            -- Reset to page 1 when new data loads
            currentPage = 1
            if HSP.MainFrame and HSP.MainFrame:IsShown() then
                HSP.UpdateUI()
            end
        end
        messageBuffer = ""
    end
end

-- Get family name from creature ID (basic mapping)
function HSP.GetFamilyFromCreature(creatureId)
    -- This could be expanded with a full mapping table
    -- For now return nil to use "Unknown"
    return nil
end

-- Handle server payload (called from OnAddonMessage after filtering)
function HSP.HandleServerPayload(msg)
    if not msg or msg == "" then return end
    
    -- Debug print to show receipt
    if debugMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[BMP RX]|r " .. tostring(msg):sub(1, 80))
    end
    
    if msg:find("^PETS|") then
        -- Server sent pet list: PETS|petNumber|creatureId|level|name|flags;...
        local petData = msg:sub(6) -- Remove "PETS|" prefix
        messageBuffer = messageBuffer .. petData
        bufferTimeout = GetTime() + 0.5
        HSP.ProcessPetBuffer()
        
    elseif msg:find("^PETS_CHUNK|") then
        -- Chunked message: PETS_CHUNK|<data> (more coming)
        local petData = msg:sub(12)
        messageBuffer = messageBuffer .. petData
        chunkCount = chunkCount + 1
        bufferTimeout = GetTime() + 1.0
        
        -- Safety: prevent runaway memory if protocol breaks
        if #messageBuffer > MAX_BUFFER_CHARS then
            Warn("Server payload too large, resetting buffer")
            messageBuffer = ""
            chunkCount = 0
            return
        end
        
        -- Debug: only print every 5 chunks to reduce spam
        if debugMode and (chunkCount == 1 or chunkCount % 5 == 0) then
            Debug("Received chunk %d (buffer=%d chars)", chunkCount, #messageBuffer)
        end
        
    elseif msg:find("^PETS_END") then
        -- Guard against double handling
        if listCompleted then
            Debug("Ignoring duplicate PETS_END")
            return
        end
        listCompleted = true
        
        -- End of chunked messages
        Debug("Received PETS_END, parsing buffered data (%d chunks)", chunkCount)
        
        local data = messageBuffer
        messageBuffer = ""
        local totalChunks = chunkCount
        chunkCount = 0
        
        -- Parse the data
        local serverPets = HSP.ParseServerPetData(data)
        if serverPets and #serverPets > 0 then
            pets = serverPets
        end
        
        -- Capture count before async call
        local petCount = #pets
        local chunkTotal = totalChunks
        
        -- UI update one frame later (safer during login)
        After(0.0, function()
            SavePetCache()
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
        
    elseif msg:find("^OK|") then
        local okMsg = tostring(msg:sub(4) or "")
        Info("Server: %s", okMsg)
        print("|cFF00FF00BMP:|r " .. okMsg)
        
    elseif msg:find("^SUMMONED|") then
        -- Pet was summoned successfully
        local petName = tostring(msg:sub(10) or "pet")
        print("|cFF00FF00BMP:|r " .. petName .. " summoned!")
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
    
    -- Ignore local echo of outgoing commands
    if isLocalEcho then
        if message == "LIST" or message:find("^SUMMON|") then
            Debug("Ignoring local echo: %s", message)
            return
        end
    end
    
    if debugMode then
        print("|cFF00CCFF[BMP RECV]|r sender=" .. tostring(sender) .. " msg=" .. tostring(message):sub(1, 60))
    end
    
    -- Only accept known server payload types
    if message:find("^PETS|") or 
       message:find("^PETS_CHUNK|") or 
       message == "PETS_END" or
       message:find("^OK|") or
       message:find("^ERROR|") or
       message:find("^SUMMONED|") then
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
        icon = "Interface\\Icons\\INV_Misc_QuestionMark",
        isExotic = false,
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

-- Get total number of stable slots available
local function GetExtendedNumStableSlots()
    if HasCustomAPI() and HSP_GetNumStableSlots then
        return HSP_GetNumStableSlots()
    end
    -- Try to get server-reported slots, or use configured max
    local serverSlots = GetNumStableSlots() or 5
    local configuredMax = BeastmasterPlusDB.maxStableSlots or 99
    -- Return the higher of server-reported or configured (for custom servers)
    return math.max(serverSlots, configuredMax)
end

-- ============================================================================
-- PET DATA MANAGEMENT (with caching)
-- ============================================================================

-- Removed isAtStableMaster - addon doesn't interact with stable flow

-- Save pet data to cache (SavedVariables)
-- Uses forward-declared local variable
SavePetCache = function()
    BeastmasterPlusCharDB.petCache = {}
    for _, pet in ipairs(pets) do
        table.insert(BeastmasterPlusCharDB.petCache, {
            stableIndex = pet.stableIndex,
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

-- Load pet data from cache
-- Uses forward-declared local variable
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

-- Load pet data from cache and merge manual pets (no stable master scanning)
local function RefreshPetData()
    Debug("RefreshPetData: Loading from cache only (stable scanning disabled)")
    
    -- Load from cache if not already loaded
    if #pets == 0 then
        LoadPetCache()
    end
    
    -- Merge in manually added pets
    if BeastmasterPlusCharDB.manualPets then
        for slot, manualPet in pairs(BeastmasterPlusCharDB.manualPets) do
            -- Check if this slot already exists
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
        
        -- Search filter
        if searchText and searchText ~= "" then
            local search = searchText:lower()
            if not pet.name:lower():find(search, 1, true) and
               not pet.family:lower():find(search, 1, true) then
                include = false
            end
        end
        
        -- Family filter
        if include and db.filterFamily and db.filterFamily ~= "" then
            if pet.family ~= db.filterFamily then
                include = false
            end
        end
        
        -- Exotic filter
        if include and db.filterExoticOnly then
            if not pet.isExotic then
                include = false
            end
        end
        
        -- Level filter
        if include then
            local minLevel = db.filterMinLevel or 1
            local maxLevel = db.filterMaxLevel or 80
            if pet.level < minLevel or pet.level > maxLevel then
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
            valA, valB = a.name:lower(), b.name:lower()
        elseif sortBy == "level" then
            valA, valB = a.level, b.level
        elseif sortBy == "family" then
            valA, valB = a.family:lower(), b.family:lower()
        else
            valA, valB = a.stableIndex, b.stableIndex
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
-- PAGINATION
-- ============================================================================

local function GetPagedPets()
    local allPets = GetFilteredSortedPets()
    local db = BeastmasterPlusCharDB
    local perPage = db.itemsPerPage or 25
    local startIndex = ((currentPage - 1) * perPage) + 1
    local endIndex = math.min(startIndex + perPage - 1, #allPets)
    
    local pagedPets = {}
    for i = startIndex, endIndex do
        table.insert(pagedPets, allPets[i])
    end
    
    local totalPages = math.ceil(#allPets / perPage)
    
    return pagedPets, currentPage, totalPages, #allPets
end

-- ============================================================================
-- FAVORITES MANAGEMENT
-- ============================================================================

local function GetFavorite(stableIndex)
    local favorites = BeastmasterPlusDB.favorites or {}
    return favorites[stableIndex] or { isFavorite = false, notes = "" }
end

local function SetFavorite(stableIndex, isFavorite, notes)
    BeastmasterPlusDB.favorites = BeastmasterPlusDB.favorites or {}
    BeastmasterPlusDB.favorites[stableIndex] = {
        isFavorite = isFavorite or false,
        notes = notes or "",
    }
end

local function ToggleFavorite(stableIndex)
    local fav = GetFavorite(stableIndex)
    SetFavorite(stableIndex, not fav.isFavorite, fav.notes)
    return not fav.isFavorite
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Recent pets tracking (last 5 summoned)
local recentPets = {}
local MAX_RECENT = 5

local function AddRecentPet(petData)
    if not petData then return end
    -- Remove if already in list
    for i = #recentPets, 1, -1 do
        if recentPets[i].petNumber == petData.petNumber then
            table.remove(recentPets, i)
        end
    end
    -- Add to front
    table.insert(recentPets, 1, {
        petNumber = petData.petNumber,
        name = petData.name,
        level = petData.level,
        family = petData.family,
        icon = petData.icon,
    })
    -- Trim to max
    while #recentPets > MAX_RECENT do
        table.remove(recentPets)
    end
end

HSP.GetPets = GetPagedPets
HSP.RefreshPets = RefreshPetData
HSP.GetAllPets = function() return pets end -- Returns all pets without pagination
HSP.GetRecentPets = function() return recentPets end
HSP.AddRecentPet = AddRecentPet
HSP.GetFavorite = GetFavorite
HSP.SetFavorite = SetFavorite
HSP.ToggleFavorite = ToggleFavorite
HSP.PET_FAMILIES = PET_FAMILIES
HSP.EXOTIC_FAMILIES = EXOTIC_FAMILIES

-- Quick filter helpers
HSP.SetQuickFilter = function(filterType)
    if filterType == "exotic" then
        BeastmasterPlusCharDB.filterExoticOnly = not BeastmasterPlusCharDB.filterExoticOnly
    elseif filterType == "maxLevel" then
        if BeastmasterPlusCharDB.filterMinLevel == 80 then
            BeastmasterPlusCharDB.filterMinLevel = 1
        else
            BeastmasterPlusCharDB.filterMinLevel = 80
        end
    elseif filterType == "clear" then
        BeastmasterPlusCharDB.filterFamily = nil
        BeastmasterPlusCharDB.filterExoticOnly = false
        BeastmasterPlusCharDB.filterMinLevel = 1
        BeastmasterPlusCharDB.filterMaxLevel = 80
    end
    currentPage = 1
end

HSP.GetActiveFilters = function()
    local filters = {}
    local db = BeastmasterPlusCharDB
    if db.filterFamily then table.insert(filters, db.filterFamily) end
    if db.filterExoticOnly then table.insert(filters, "Exotic") end
    if db.filterMinLevel and db.filterMinLevel > 1 then table.insert(filters, "Lv" .. db.filterMinLevel .. "+") end
    if db.filterMaxLevel and db.filterMaxLevel < 80 then table.insert(filters, "Lv" .. db.filterMaxLevel .. "-") end
    return filters
end

HSP.SetSearch = function(text)
    searchText = text or ""
    currentPage = 1
end

HSP.SetPage = function(page)
    currentPage = math.max(1, page)
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

HSP.SetSort = function(sortBy, sortOrder)
    BeastmasterPlusCharDB.sortBy = sortBy
    BeastmasterPlusCharDB.sortOrder = sortOrder
end

HSP.SetFilter = function(filterType, value)
    if filterType == "family" then
        BeastmasterPlusCharDB.filterFamily = value
    elseif filterType == "exotic" then
        BeastmasterPlusCharDB.filterExoticOnly = value
    elseif filterType == "minLevel" then
        BeastmasterPlusCharDB.filterMinLevel = value
    elseif filterType == "maxLevel" then
        BeastmasterPlusCharDB.filterMaxLevel = value
    end
    currentPage = 1
end

HSP.ClearFilters = function()
    BeastmasterPlusCharDB.filterFamily = nil
    BeastmasterPlusCharDB.filterExoticOnly = false
    BeastmasterPlusCharDB.filterMinLevel = 1
    BeastmasterPlusCharDB.filterMaxLevel = 80
    searchText = ""
    currentPage = 1
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

SLASH_BEASTMASTERPLUS1 = "/bmp"
SLASH_BEASTMASTERPLUS2 = "/beastmaster"

SlashCmdList["BEASTMASTERPLUS"] = function(msg)
    -- Hunter-only check
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
    elseif msg == "api" then
        if HasCustomAPI() then
            print("|cFF00FF00Beastmaster Plus:|r Custom stable API detected!")
        else
            Warn("Custom stable API NOT found. Using standard API (limited to 5 slots).")
        end
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
    elseif msg:find("^slots ") then
        local num = tonumber(msg:match("^slots (%d+)"))
        if num and num >= 5 and num <= 99 then
            BeastmasterPlusDB.maxStableSlots = num
            Info("Max stable slots set to %d. Use /bmp refresh to rescan.", num)
        else
            Warn("Usage: /bmp slots <5-99>")
        end
    elseif msg:find("^summon ") then
        local cmd = msg:match("^summon (.+)")
        if cmd and cmd ~= "" then
            BeastmasterPlusDB.summonCommand = cmd
            Info("Summon command set to: %s", cmd)
            Info("Use %%d as placeholder for slot number.")
        else
            Warn("Usage: /bmp summon <command with %%d for slot>")
        end
    elseif msg == "summon" then
        Info("Current summon command: %s", BeastmasterPlusDB.summonCommand or "(not set)")
        Info("To set: /bmp summon /.stablepet %%d")
    elseif msg:find("^add ") then
        -- /bmp add <slot> <name> <level> <family>
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
    elseif msg == "list" then
        HSP.ListManualPets()
    elseif msg == "clear" then
        HSP.ClearAndRefresh()
    else
        print("|cFFFFD100Beastmaster Plus commands:|r")
        print("  /bmp - Open stable manager")
        print("  /bmp refresh - Request pet list from server")
        print("  /bmp clear - Clear cache and refresh from server")
        print("  /bmp count - Show pet count")
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
-- Only use CHAT_MSG_ADDON - whisper/system paths are unstable and cause crashes
eventFrame:RegisterEvent("CHAT_MSG_ADDON")

-- Register addon prefix for server communication (support both old and new API)
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(ADDON_PREFIX)
end

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Check if player is a Hunter - addon only works for Hunters
        local _, playerClass = UnitClass("player")
        if playerClass ~= "HUNTER" then
            -- Silently disable for non-hunters
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
        -- Double-check hunter class (UnitClass may not be available at ADDON_LOADED)
        local _, playerClass = UnitClass("player")
        if playerClass ~= "HUNTER" then
            isLoaded = false
            return
        end
        
        LoadPetCache()
        if #pets > 0 then
            Info("Loaded %d pets from cache.", #pets)
        end
        -- Request moved to PLAYER_ENTERING_WORLD with delay
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not isLoaded then return end
        
        -- Don't spam refresh on zoning, only do it once per session
        if HSP._didInitialRefresh then return end
        HSP._didInitialRefresh = true
        
        -- Delay request to avoid login crash from immediate server response
        After(3.0, function()
            if not UnitExists("player") then return end
            if not UnitName("player") then return end
            HSP.RequestPetList()
        end)
        
    elseif event == "CHAT_MSG_ADDON" then
        -- arg1=prefix, arg2=message, arg3=channel, arg4=sender
        HSP.OnAddonMessage(arg1, arg2, arg3, arg4)
    end
end)

-- Make addon namespace global for debugging
_G.BeastmasterPlus = HSP
