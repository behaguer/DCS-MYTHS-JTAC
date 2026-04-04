JTAC = {};

local EVENTJTAC = {};

-- =====================================================================================
-- CONFIG (Editable Section)
-- =====================================================================================

-- Add configuration properties to existing JTAC table (don't overwrite)
JTAC.debug = true             -- enable debug messages in DCS log and on screen
JTAC.production_mode = true  -- when true, disables all debug messages even if debug is true

-- Options
JTAC.groupPrefix = false        -- restrict F10 menu to group with specific prefix
JTAC.Prefix = "Only"            -- choose group prefix
JTAC.searchRadius = 5000        -- define radius for scanning zone (meters)
JTAC.dfaultLaserCode = "1688"   -- Default laser code (not used in multi-player mode)
JTAC.missionLimit = 5           -- Limit number of active JTAC missions per player (set to 1 for realism, can be increased for more casual play)

-- List all unit you want to exclude from scanning you need to found the Type of the unit (e.g. "Barrier B" which is ["shape_name"] = "M92_BarrierB",["type"] = "Barrier B",
-- sometime the type in mission editor is not real type like in ME : ORCA type is: Orca Whale but in mission (file inside the miz file) type - Orca
-- you can also found the type in the traget list it ithe first name you see "target type: target name" in the list

-- Target filtering
JTAC.exclude_Targets = {
    {typeName = "Barrier B"}
}

JTAC.exclude_TargetNames = {
    "Static",   -- excludes "Static_AAA", "Static_123", etc
    "Hidden_"
}

-- Initialize module tables
JTAC.IR = {}
JTAC.LASER = {}
JTAC.BILLUM = {}
JTAC.SMOKE = {}
JTAC.MESSAGES = {}
JTAC.SCAN = {}
JTAC.TARGETMENU = {}

-- =====================================================================================
-- DEBUG FUNCTIONS
-- =====================================================================================

-- Debug function that outputs to both log and players if debug is enabled
local function debugMsg(message, force)
    env.info("[JTAC] " .. message)
    if (JTAC.debug and not JTAC.production_mode) or force then
        trigger.action.outText(message, 10)
    end
end

-- =====================================================================================
-- MULTI-PLAYER STATE MANAGEMENT
-- =====================================================================================

-- Active JTAC missions per player
JTAC.ActiveMissions = {}

-- Used laser codes to ensure uniqueness
JTAC.UsedLaserCodes = {}

-- Used JTAC call signs to ensure uniqueness across active missions
JTAC.UsedJTACCodes = {}

-- Used air and ground callsigns to ensure uniqueness
JTAC.UsedAirCallsigns = {}
JTAC.UsedGroundCallsigns = {}

-- Phonetic alphabet for call signs
JTAC.PhoneticAlphabet = {
    "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", 
    "india", "juliet", "kilo", "lima", "mike", "november", "oscar", "papa", 
    "quebec", "romeo", "sierra", "tango", "uniform", "victor", "whiskey", "xray", "yankee", "zulu"
}

-- DCS available callsigns (limited to 8 unique bases, numbers will be added for uniqueness)
JTAC.callsign = {
    ground = {
        "Enfield", "Springfield", "Uzi", "Colt", "Dodge", "Ford", "Chevy", "Pontiac"
    },
    air ={ 
        "Enfield", "Springfield", "Uzi", "Colt", "Dodge", "Ford", "Chevy", "Pontiac"
    }
}

-- =====================================================================================
-- LASE AND CALLSIGN HELPER FUNCTIONS
-- =====================================================================================

-- Helper function for air callsign management
function JTAC.getRandomAirCallsign()
    local airCallsigns = JTAC.callsign.air
    local baseCallsign = airCallsigns[math.random(1, #airCallsigns)]
    
    -- Find the next available number for this base callsign
    local number = 1
    local fullCallsign = baseCallsign .. "-" .. number
    
    while JTAC.UsedAirCallsigns[fullCallsign] do
        number = number + 1
        fullCallsign = baseCallsign .. "-" .. number
    end
    
    JTAC.UsedAirCallsigns[fullCallsign] = true
    return fullCallsign
end

-- Helper function for ground callsign management
function JTAC.getRandomGroundCallsign()
    local groundCallsigns = JTAC.callsign.ground
    local baseCallsign = groundCallsigns[math.random(1, #groundCallsigns)]
    
    -- Find the next available number for this base callsign
    local number = 1
    local fullCallsign = baseCallsign .. "-" .. number
    
    while JTAC.UsedGroundCallsigns[fullCallsign] do
        number = number + 1
        fullCallsign = baseCallsign .. "-" .. number
    end
    
    JTAC.UsedGroundCallsigns[fullCallsign] = true
    return fullCallsign
end

-- Release air callsign when mission ends
function JTAC.releaseAirCallsign(callsign)
    if callsign and JTAC.UsedAirCallsigns[callsign] then
        JTAC.UsedAirCallsigns[callsign] = nil
    end
end

-- Release ground callsign when mission ends
function JTAC.releaseGroundCallsign(callsign)
    if callsign and JTAC.UsedGroundCallsigns[callsign] then
        JTAC.UsedGroundCallsigns[callsign] = nil
    end
end

-- Helper functions to parse callsigns for DCS format
function JTAC.parseCallsign(fullCallsign)
    -- Parse "Mantis-1" into base="Mantis", number=1
    local base, number = fullCallsign:match("^(.+)%-(%d+)$")
    if base and number then
        return base, tonumber(number)
    else
        -- Fallback if parsing fails
        return fullCallsign, 1
    end
end

-- Map custom air callsigns to DCS callname numbers for FAC task
function JTAC.getCallnameNumber(airCallsign)
    local base, number = JTAC.parseCallsign(airCallsign)
    
    -- Map DCS preset callsigns to their callname numbers
    local callnameMap = {
        ["Enfield"] = 1,
        ["Springfield"] = 2,
        ["Uzi"] = 3,
        ["Colt"] = 4,
        ["Dodge"] = 5,
        ["Ford"] = 6,
        ["Chevy"] = 7,
        ["Pontiac"] = 8
    }
    
    return callnameMap[base] or 3  -- Default to 3 (Uzi) if not found
end

-- Laser code generation constants
local LASER_SECOND_DIGITS = {5, 6, 7}
local LASER_THIRD_FOURTH_DIGITS = {1, 2, 3, 4, 5, 6, 7, 8}
local TOTAL_LASER_CODES = 3 * 8 * 8 -- 192 total possible codes

-- Generate unique laser code for new missions (follow proper laser code format)
-- First digit: always 1, Second digit: 5,6,7, Third/Fourth digits: 1-8
function JTAC.generateUniqueLaserCode()
    -- Try preferred code first (1688)
    if not JTAC.UsedLaserCodes["1688"] then
        JTAC.UsedLaserCodes["1688"] = true
        return "1688"
    end
    
    -- Count used codes to determine strategy
    local usedCount = 0
    for _ in pairs(JTAC.UsedLaserCodes) do
        usedCount = usedCount + 1
    end
    
    local availableCount = TOTAL_LASER_CODES - usedCount
    
    -- If we're running low on codes (less than 25% available), use systematic search
    if availableCount < TOTAL_LASER_CODES * 0.25 then
        for _, second in ipairs(LASER_SECOND_DIGITS) do
            for _, third in ipairs(LASER_THIRD_FOURTH_DIGITS) do
                for _, fourth in ipairs(LASER_THIRD_FOURTH_DIGITS) do
                    local codeStr = "1" .. second .. third .. fourth
                    if not JTAC.UsedLaserCodes[codeStr] then
                        JTAC.UsedLaserCodes[codeStr] = true
                        return codeStr
                    end
                end
            end
        end
    else
        -- Plenty of codes available, use efficient random selection
        local maxAttempts = math.min(20, availableCount) -- Limit attempts based on available codes
        for attempt = 1, maxAttempts do
            local second = LASER_SECOND_DIGITS[math.random(1, #LASER_SECOND_DIGITS)]
            local third = LASER_THIRD_FOURTH_DIGITS[math.random(1, #LASER_THIRD_FOURTH_DIGITS)]
            local fourth = LASER_THIRD_FOURTH_DIGITS[math.random(1, #LASER_THIRD_FOURTH_DIGITS)]
            local codeStr = "1" .. second .. third .. fourth
            
            if not JTAC.UsedLaserCodes[codeStr] then
                JTAC.UsedLaserCodes[codeStr] = true
                return codeStr
            end
        end
        
        -- Random attempts failed, fall back to systematic (shouldn't happen often)
        for _, second in ipairs(LASER_SECOND_DIGITS) do
            for _, third in ipairs(LASER_THIRD_FOURTH_DIGITS) do
                for _, fourth in ipairs(LASER_THIRD_FOURTH_DIGITS) do
                    local codeStr = "1" .. second .. third .. fourth
                    if not JTAC.UsedLaserCodes[codeStr] then
                        JTAC.UsedLaserCodes[codeStr] = true
                        return codeStr
                    end
                end
            end
        end
    end
    
    -- This should never happen with 192 possible codes
    debugMsg("ERROR: All laser codes exhausted! This should not happen.")
    return "1688" -- Fallback to default
end

-- Generate unique JTAC call sign with phonetic and laser code
function JTAC.generateJTACCallSign()
    local laserCode = JTAC.generateUniqueLaserCode()
    
    -- Find available phonetic
    local availablePhonetics = {}
    for _, phonetic in ipairs(JTAC.PhoneticAlphabet) do
        local callSign = "jt-" .. phonetic .. "-" .. laserCode
        if not JTAC.UsedJTACCodes[callSign] then
            table.insert(availablePhonetics, phonetic)
        end
    end
    
    if #availablePhonetics == 0 then
        -- Fallback to random phonetic if all are taken (very unlikely)
        local randomPhonetic = JTAC.PhoneticAlphabet[math.random(1, #JTAC.PhoneticAlphabet)]
        local callSign = "jt-" .. randomPhonetic .. "-" .. laserCode
        JTAC.UsedJTACCodes[callSign] = true
        return callSign, laserCode
    end
    
    -- Select random available phonetic
    local selectedPhonetic = availablePhonetics[math.random(1, #availablePhonetics)]
    local callSign = "jt-" .. selectedPhonetic .. "-" .. laserCode
    JTAC.UsedJTACCodes[callSign] = true
    
    return callSign, laserCode
end

-- Release laser code and call sign when mission ends
function JTAC.releaseLaserCode(laserCode)
    if laserCode and JTAC.UsedLaserCodes[laserCode] then
        JTAC.UsedLaserCodes[laserCode] = nil
    end
end

-- Release JTAC call sign when mission ends
function JTAC.releaseJTACCallSign(callSign)
    if callSign and JTAC.UsedJTACCodes[callSign] then
        JTAC.UsedJTACCodes[callSign] = nil
    end
end

-- Get or create mission state for a player
function JTAC.getPlayerMission(playerName, playerGroupID)
    if not JTAC.ActiveMissions[playerName] then
        -- Create new mission state for this player (without assigning codes yet)
        JTAC.ActiveMissions[playerName] = {
            -- Player info
            player = playerName,
            playerGroupID = playerGroupID,
            playerGroupName = nil,
            playerUnitName = nil,
            playerUnit = nil,
            playerPos = nil,
            model = nil,
            groupAuth = false,
            
            -- Mission state
            support = true,
            targetPriority = "None",
            
            -- Target management
            target = {
                availability = 100,
                waitTime = 30,
                laserPos = nil,
                laserCode = nil,
                laserSpot = nil,
                irPos = nil,
                irSpot = nil,
                billum = nil,
                droneName = "",
                groundName = "",
                droneInFlight = false,
                droneInZone = false,
                isLaseAvailable = false,
                currentLasedTarget = nil
            },
            
            -- JTAC call sign management
            jtacCallSign = nil,
            awaitingMarker = false,
            
            -- Dynamic callsigns
            airCallsign = JTAC.getRandomAirCallsign(),
            groundCallsign = JTAC.getRandomGroundCallsign(),
            
            -- UI Management
            menuHandles = {},
            currentUnitName = nil,  -- Track which unit currently has the menu
            currentGroupID = nil,   -- Track which group currently has the menu
            disconnectTime = nil    -- Track when player disconnected for cleanup delay
        }
        
        debugMsg("Created new JTAC mission for player: " .. playerName)
        
        -- Update availability for all missions after creating new mission
        JTAC.setAvailability()
    end
    
    return JTAC.ActiveMissions[playerName]
end

-- Remove menu from current unit (when switching units)
function JTAC.removeMenuFromUnit(playerName)
    local mission = JTAC.ActiveMissions[playerName]
    if mission and mission.currentUnitName then
        debugMsg("Removing menu from unit for player: " .. playerName .. " (unit: " .. mission.currentUnitName .. ") - preserving mission data: drone=" .. (mission.target.droneName or "none") .. ", ground=" .. (mission.target.groundName or "none"))
        -- Remove menu from current unit
        JTAC.removeMenuForPlayer(mission)
        -- Clear current unit tracking but keep mission data
        mission.currentUnitName = nil
        mission.currentGroupID = nil
        mission.playerUnit = nil
    else
        debugMsg("removeMenuFromUnit called for " .. playerName .. " but no mission or unit found")
    end
end

-- Clean up mission completely when player disconnects from server
function JTAC.cleanupPlayerMission(playerName)
    local mission = JTAC.ActiveMissions[playerName]
    if mission then
        -- Clean up any active assets
        if mission.target.droneName ~= "" then
            JTAC.dismissPackageForPlayer(mission, "DRONE")
        end
        if mission.target.groundName ~= "" then
            JTAC.dismissPackageForPlayer(mission, "GROUND")
        end
        
        -- Remove menu
        JTAC.removeMenuForPlayer(mission)
        
        -- Release laser code and call sign
        JTAC.releaseLaserCode(mission.target.laserCode)
        JTAC.releaseJTACCallSign(mission.jtacCallSign)
        
        -- Release air and ground callsigns
        JTAC.releaseAirCallsign(mission.airCallsign)
        JTAC.releaseGroundCallsign(mission.groundCallsign)
        
        -- Remove from active missions
        JTAC.ActiveMissions[playerName] = nil
        
        -- Update availability for all missions after cleanup
        JTAC.setAvailability()
        
        debugMsg("Cleaned up JTAC mission for player: " .. playerName)
    end
end

-- Clean up missions for players who have disconnected from server
function JTAC.cleanupDisconnectedPlayers()
    local activePlayers = {}
    
    -- Get all players currently in the mission
    for _, coalitionSide in pairs({coalition.side.RED, coalition.side.BLUE}) do
        local players = coalition.getPlayers(coalitionSide)
        for _, playerName in pairs(players) do
            activePlayers[playerName] = true
        end
    end
    
    -- Check for missions belonging to disconnected players
    for playerName, mission in pairs(JTAC.ActiveMissions) do
        if not activePlayers[playerName] then
            -- Extra safety check - don't clean up missions with active JTACs unless player has been gone for a while
            if mission.target.droneName ~= "" or mission.target.groundName ~= "" then
                -- Add a disconnect timer to prevent immediate cleanup of active missions
                if not mission.disconnectTime then
                    mission.disconnectTime = timer.getTime()
                    debugMsg("Player " .. playerName .. " disconnected but has active JTACs, starting disconnect timer")
                elseif timer.getTime() - mission.disconnectTime > 300 then  -- 5 minutes
                    debugMsg("Cleaning up mission for long-disconnected player with active JTACs: " .. playerName)
                    JTAC.cleanupPlayerMission(playerName)
                end
            else
                -- No active JTACs, safe to clean up immediately
                debugMsg("Cleaning up mission for disconnected player: " .. playerName)
                JTAC.cleanupPlayerMission(playerName)
            end
        else
            -- Player is active, clear any disconnect timer
            if mission.disconnectTime then
                mission.disconnectTime = nil
            end
        end
    end
end

-- =====================================================================================
-- JTAC EVENTS MANAGER
-- =====================================================================================

-- This function actually sets up the menu for the player, called with a delay
local function JTAC_delayedMenu(args, time)
    local event = args.event
    local playerName = args.playerName

    if not event.initiator or not event.initiator:isExist() then
        return  -- player unit gone, just stop
    end

    local group = event.initiator:getGroup()
    if not group then return end

    local groupID = group:getID()
    local groupName = group:getName()
    local unitName = event.initiator:getName()

    -- Check if player has existing mission
    local mission = JTAC.ActiveMissions[playerName]
    if mission then
        debugMsg("Found existing mission for player: " .. playerName .. " (drone: " .. (mission.target.droneName or "none") .. ", ground: " .. (mission.target.groundName or "none") .. ", laserCode: " .. (mission.target.laserCode or "none") .. ")")
        
        -- Player has existing mission, check if it's already connected to this unit
        if mission.currentUnitName == unitName and mission.currentGroupID == groupID then
            -- Same unit, menu already exists, do nothing
            debugMsg("Same unit reconnection, menu already exists for: " .. playerName)
            return nil
        else
            -- Different unit, remove menu from old unit and connect to new unit
            if mission.currentUnitName then
                debugMsg("Removing menu from old unit: " .. (mission.currentUnitName or "unknown"))
                JTAC.removeMenuForPlayer(mission)
            end
            
            -- Update mission to new unit
            mission.playerGroupID = groupID
            mission.playerGroupName = groupName
            mission.playerUnitName = unitName
            mission.playerUnit = event.initiator
            mission.playerPos = event.initiator:getPoint()
            mission.currentUnitName = unitName
            mission.currentGroupID = groupID
            
            -- Restore menu on new unit
            JTAC.setMenuForPlayer(mission)
            debugMsg("Reconnected existing mission to new unit for player: " .. playerName .. " (unit: " .. unitName .. ", group: " .. groupName .. ")")
            return nil
        end
    else
        debugMsg("No existing mission found for player: " .. playerName .. ", creating new one")
        -- No existing mission, create new one
        mission = JTAC.getPlayerMission(playerName, groupID)
    end

    -- Update player info in their mission
    mission.player = playerName
    mission.model = event.initiator:getTypeName()
    mission.playerGroupID = groupID
    mission.playerGroupName = groupName
    mission.playerUnitName = unitName
    mission.playerUnit = event.initiator
    mission.playerPos = event.initiator:getPoint()
    mission.currentUnitName = unitName
    mission.currentGroupID = groupID

    local theatre = env.mission.theatre

    if JTAC.groupPrefix == true and string.sub(groupName,1,4) == JTAC.Prefix then
        JTAC.setMenuForPlayer(mission)
        mission.groupAuth = true
    elseif JTAC.groupPrefix == false then
        JTAC.setMenuForPlayer(mission)
        mission.groupAuth = true
    end

    -- no repeat, so return nil
    return nil
end

function EVENTJTAC:onEvent(event)
    if event.id == world.event.S_EVENT_BIRTH and event.initiator then
        if event.initiator.getPlayerName then
            local playerName = event.initiator:getPlayerName()
            if playerName and playerName ~= "" then
                -- schedule menu creation 5 seconds after spawn
                local args = {
                    event = event,
                    playerName = playerName,
                }
                timer.scheduleFunction(
                    JTAC_delayedMenu,
                    args,
                    timer.getTime() + 1
                )
            end
        end
    end

    -- Handle all events that should trigger menu removal from unit (but preserve missions)
    if (event.id == world.event.S_EVENT_DEAD or event.id == world.event.S_EVENT_PILOT_DEAD or 
        event.id == world.event.S_EVENT_EJECTION or event.id == world.event.S_EVENT_PLAYER_LEAVE_UNIT) and event.initiator then
        if event.initiator and event.initiator.getPlayerName then
            local playerName = event.initiator:getPlayerName()
            if playerName and playerName ~= "" then
                -- Only remove menu from unit, keep mission data for reconnection
                JTAC.removeMenuFromUnit(playerName)
            end
        end
    end

	if (world.event.S_EVENT_MARK_CHANGE == event.id) then
        -- NEW: Handle JTAC call sign marker placement
        local markerText = event.text
        
        -- Look for JTAC call sign format: jt-phonetic-code
        if (string.match(markerText, "^jt%-[a-z]+%-[0-9]+$")) then
            -- Find the mission waiting for this specific call sign
            local targetPlayerName = nil
            local targetMission = nil
            
            for playerName, mission in pairs(JTAC.ActiveMissions) do
                if mission.awaitingMarker and mission.jtacCallSign == markerText then
                    targetPlayerName = playerName
                    targetMission = mission
                    break
                end
            end
            
            if targetMission then
                if coalition.getPlayers(coalition.side.RED)[1] ~= nil or coalition.getPlayers(coalition.side.BLUE)[1] ~= nil then
                    -- Clean up any existing laser/IR spots
                    if targetMission.target.laserSpot ~= nil then
                        targetMission.target.laserSpot:destroy()
                        targetMission.target.laserSpot = nil;
                    end

                    if targetMission.target.irSpot ~= nil then
                        targetMission.target.irSpot:destroy()
                        targetMission.target.irSpot = nil;
                    end

                    -- Set mission parameters
                    targetMission.target.laserPos = event.pos
                    targetMission.target.irPos = event.pos
                    targetMission.target.scanPos = event.pos
                    targetMission.awaitingMarker = false
                    
                    -- Refresh menu to show drone/ground options
                    JTAC.setMenuForPlayer(targetMission)
                    
                    -- Update availability after JTAC position is set
                    JTAC.setAvailability()
                    
                    JTAC.MESSAGES.setMsg(
                        targetPlayerName .. ": JTAC position confirmed. You can now request drone or ground support. Laser code: " .. targetMission.target.laserCode, 
                        12, 2, true, targetMission.playerGroupID)
                    
                    debugMsg("JTAC marker placed by " .. targetPlayerName .. " with call sign: " .. markerText)
                else
                    JTAC.MESSAGES.setMsg(
                        "There are no players in the mission. Can't request support", 10, 2, true, targetMission.playerGroupID)
                end
            else
                -- No mission found waiting for this call sign
                debugMsg("Unknown JTAC call sign marker placed: " .. markerText)
            end
        end
    end

    if (world.event.S_EVENT_MARK_REMOVED == event.id) then
        -- Handle JTAC marker removal
        local markerText = event.text
        
        -- Look for JTAC call sign format: jt-phonetic-code
        if (string.match(markerText, "^jt%-[a-z]+%-[0-9]+$")) then
            -- Find the mission using this call sign
            for playerName, mission in pairs(JTAC.ActiveMissions) do
                if mission.jtacCallSign == markerText then
                    -- Only reset if no active units (avoid disrupting active operations)
                    if mission.support == true and mission.target.droneName == "" and mission.target.groundName == "" then
                        debugMsg("JTAC marker removed for " .. playerName .. ", resetting mission state")
                        
                        -- Clear JTAC assignment completely
                        JTAC.releaseLaserCode(mission.target.laserCode)
                        JTAC.releaseJTACCallSign(mission.jtacCallSign)
                        mission.target.laserCode = nil
                        mission.jtacCallSign = nil
                        mission.awaitingMarker = false
                        mission.target.laserPos = nil
                        mission.target.irPos = nil
                        mission.target.scanPos = nil
                        
                        -- Refresh menu to show initial state
                        JTAC.setMenuForPlayer(mission)
                        
                        JTAC.MESSAGES.setMsg("JTAC marker removed. Request new JTAC assignment to continue.", 10, 2, true, mission.playerGroupID)
                    end
                    break
                end
            end
        end
    end
end

-- =====================================================================================
-- HELPER FUNCTIONS
-- =====================================================================================

function JTAC.getCoordinatesSTR(decLat, decLong, alt)
	local lat1, latF1 = math.modf(decLat)
	local latF2, latF3 = math.modf(latF1 * 60)
	local alt1 = alt
	local long1, longF1 = math.modf(decLong)
	local longF2, longF3 = math.modf(longF1 * 60)
	return {lat = "N " ..string.format("%02d", lat1) .. "°" .. string.format("%02d",latF2) .. "." .. string.format("%03d",math.floor(latF3 * 60)) .. "’",
			long = "E " ..string.format("%03d", long1) .. "°" .. string.format("%02d",longF2) .. "." .. string.format("%03d",math.floor(longF3 * 60)) .. "’",
			alt = string.format("%02d", alt1) }
end

-- =====================================================================================
-- JTAC REQUEST FUNCTIONS  
-- =====================================================================================

-- Request JTAC assignment - generates call sign and waits for marker
function JTAC.requestJTACAssignment(mission)
    if mission.awaitingMarker then
        JTAC.MESSAGES.setMsg("JTAC request already pending. Place marker: " .. mission.jtacCallSign, 10, 2, true, mission.playerGroupID)
        return
    end
    
    if mission.target.laserCode then
        JTAC.MESSAGES.setMsg("JTAC already assigned with code: " .. mission.target.laserCode, 10, 2, true, mission.playerGroupID)
        return
    end
    
    -- Generate unique JTAC call sign and laser code
    local callSign, laserCode = JTAC.generateJTACCallSign()
    
    mission.jtacCallSign = callSign
    mission.target.laserCode = laserCode
    mission.awaitingMarker = true
    
    -- Refresh menu to show reminder and cancel options
    JTAC.setMenuForPlayer(mission)
    
    JTAC.MESSAGES.setMsg(
        "COMMAND: JTAC assignment ready. Place map marker with text: " .. callSign, 30, 2, true, mission.playerGroupID)
    JTAC.MESSAGES.setMsg(
        "Your laser code will be: " .. laserCode, 30, 2, false, mission.playerGroupID)
    
    debugMsg("Generated JTAC assignment for " .. mission.player .. ": " .. callSign .. " (Code: " .. laserCode .. ")")
end

-- Cancel JTAC request
function JTAC.cancelJTACRequest(mission)
    if not mission.awaitingMarker then
        JTAC.MESSAGES.setMsg("No pending JTAC request to cancel.", 10, 2, true, mission.playerGroupID)
        return
    end
    
    -- Release the reserved codes
    JTAC.releaseLaserCode(mission.target.laserCode)
    JTAC.releaseJTACCallSign(mission.jtacCallSign)
    
    mission.jtacCallSign = nil
    mission.target.laserCode = nil
    mission.awaitingMarker = false
    
    -- Refresh menu to show initial state
    JTAC.setMenuForPlayer(mission)
    
    JTAC.MESSAGES.setMsg("JTAC request cancelled.", 10, 2, true, mission.playerGroupID)
    debugMsg("Cancelled JTAC request for player: " .. mission.player)
end

-- Request dismissal of active JTAC package (drone or ground) and clean up mission state
function JTAC.requestDismissPackageForPlayer(mission, groupType)
    JTAC.MESSAGES.setMsg(mission.player .." : Mission over " .. mission.jtacCallSign .. " you can RTB. Thanks for the support.", 10, 2, true, mission.playerGroupID)
    timer.scheduleFunction(JTAC.dismissPackageForPlayer, {mission = mission, groupType = groupType}, timer.getTime() + 15)
    if groupType == "DRONE" and mission.target.droneName ~= "" and Group.getByName(mission.target.droneName) and Group.getByName(mission.target.droneName):getUnit(1) ~= nil then
        JTAC.MESSAGES.setMessageDelayed(mission.airCallsign .. ": Mission over RTB.", 10, 7, true)
    elseif groupType == "GROUND" and mission.target.groundName ~= "" and Group.getByName(mission.target.groundName) and Group.getByName(mission.target.groundName):getUnit(1) ~= nil then
        JTAC.MESSAGES.setMessageDelayed(mission.groundCallsign .. ": Mission over RTB.", 10, 10, true)
    end
end

-- =====================================================================================
-- JTAC FUNCTIONS
-- =====================================================================================

function JTAC.isExcludedTarget(sType)
	for i, target_ in ipairs(JTAC.exclude_Targets) do
		if target_.typeName == sType then
			return false
		end
	end
	return true
end

function JTAC.isExcludedTargetName(TGT)
    for _, prefix in ipairs(JTAC.exclude_TargetNames) do
        if string.sub(TGT, 1, #prefix) == prefix then
            return true
        end
    end
    return false
end

function JTAC.dismissPackageForPlayer(params)
    local mission = params.mission
    local groupType = params.groupType or "UNKNOWN"
    
    JTAC.MESSAGES.setMessageDelayed(groupType .. " package has left the Zone.", 15, 2, true)

    if groupType == "DRONE" and mission.target.droneName ~= "" and Group.getByName(mission.target.droneName) and Group.getByName(mission.target.droneName):getUnit(1) ~= nil then
        JTAC.destroyGroup(mission.target.droneName)
        
        -- Clear all mission data first
        mission.target.laserPos = nil;
        mission.target.irPos = nil;
        mission.target.laserSpot = nil;
        mission.target.irSpot = nil;
        mission.target.droneName = "";
        mission.target.droneInFlight = false;
        mission.target.droneInZone = false;
        mission.target.isLaseAvailable = false;
        mission.target.currentLasedTarget = "STOP";
        
        -- Clear JTAC assignment completely
        JTAC.releaseLaserCode(mission.target.laserCode)
        JTAC.releaseJTACCallSign(mission.jtacCallSign)
        mission.target.laserCode = nil
        mission.jtacCallSign = nil
        mission.awaitingMarker = false
        
        mission.support = true;
        
        -- Explicitly remove dismiss package menu items
        if mission.menuHandles.N9 then
            missionCommands.removeItemForGroup(mission.playerGroupID, mission.menuHandles.N9)
            mission.menuHandles.N9 = nil
        end
        
        -- Rebuild menu with clean state
        JTAC.removeMenuForPlayer(mission)
        JTAC.setMenuForPlayer(mission)

    elseif groupType == "GROUND" and mission.target.groundName ~= "" and Group.getByName(mission.target.groundName) and Group.getByName(mission.target.groundName):getUnit(1) ~= nil then
        JTAC.destroyGroup(mission.target.groundName)
        
        -- Clear all mission data first
        mission.target.laserPos = nil;
        mission.target.irPos = nil;
        mission.target.laserSpot = nil;
        mission.target.irSpot = nil;
        mission.target.groundName = "";
        mission.target.droneInFlight = false;
        mission.target.droneInZone = false;
        mission.target.isLaseAvailable = false;
        mission.target.currentLasedTarget = "STOP";
        
        -- Clear JTAC assignment completely
        JTAC.releaseLaserCode(mission.target.laserCode)
        JTAC.releaseJTACCallSign(mission.jtacCallSign)
        mission.target.laserCode = nil
        mission.jtacCallSign = nil
        mission.awaitingMarker = false
        
        mission.support = true;
        
        -- Explicitly remove dismiss package menu items
        if mission.menuHandles.N9 then
            missionCommands.removeItemForGroup(mission.playerGroupID, mission.menuHandles.N9)
            mission.menuHandles.N9 = nil
        end
        
        -- Rebuild menu with clean state
        JTAC.removeMenuForPlayer(mission)
        JTAC.setMenuForPlayer(mission)
        
        -- Update availability for all missions after dismissing JTAC
        JTAC.setAvailability()
    end
end;

function JTAC.trim(s)
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

function JTAC.isInteger(str)
return not (str == "" or str:match("%D"))
end

function JTAC.destroyGroup(groupName)
	if Group.getByName(groupName):getUnit(1) ~= nil then
		Group.getByName(groupName):destroy()
	end
end;

function JTAC.setAvailability()
    -- Count active JTAC missions (those with assets deployed)
    local activeJtacCount = 0
    for playerName, mission in pairs(JTAC.ActiveMissions) do
        -- Count missions that have drones or ground units deployed
        if mission.support == false and (mission.target.droneName ~= "" or mission.target.groundName ~= "") then
            activeJtacCount = activeJtacCount + 1
        end
    end
    
    -- Set availability for all missions based on mission limit
    for playerName, mission in pairs(JTAC.ActiveMissions) do
        if activeJtacCount < JTAC.missionLimit then
            mission.target.isLaseAvailable = true
        else
            mission.target.isLaseAvailable = false
        end
    end
    
    debugMsg("Active JTAC count: " .. activeJtacCount .. "/" .. JTAC.missionLimit .. " - Availability: " .. tostring(activeJtacCount < JTAC.missionLimit))
end;

function JTAC.setTargetPriorityForPlayer(mission, priority)
    mission.targetPriority = priority
    JTAC.MESSAGES.setMsg("Target Priority set to: " .. priority, 10, 2, true, mission.playerGroupID)

    -- Refresh target menu if JTAC is active for this player
    if mission.support == false and (mission.target.droneName ~= "" or mission.target.groundName ~= "") then
        debugMsg("Refreshing target menu with new priority for player: " .. mission.player)
        JTAC.NewMarkerScanForPlayer(mission)
    end
end;

function JTAC.categorizeTarget(unit)
    -- Debug: Log unit type for troubleshooting
    local unitType = unit:getTypeName()
    debugMsg("Unit: " .. unitType)
    
    -- Use DCS hasAttribute method to categorize units
    if unit:hasAttribute("SAM") or unit:hasAttribute("AAA") or unit:hasAttribute("Air Defence") or unit:hasAttribute("MANPADS") then
        debugMsg(unitType .. " categorized as Air Defence")
        return "Air Defence"
    elseif unit:hasAttribute("Tanks") or unit:hasAttribute("IFV") or unit:hasAttribute("APC") or unit:hasAttribute("Armour") then
        debugMsg(unitType .. " categorized as Armour")
        return "Armour"
    elseif unit:hasAttribute("Artillery") or unit:hasAttribute("MLRS") then
        debugMsg(unitType .. " categorized as Artillery")
        return "Artillery"
    elseif unit:hasAttribute("Infantry") then
        debugMsg(unitType .. " categorized as Infantry")
        return "Infantry"
    else
        debugMsg(unitType .. " categorized as Other")
        return "Other"
    end
end;

function JTAC.requestDroneForPlayer(mission)
    if not mission.target.laserCode then
        JTAC.MESSAGES.setMsg("You need to request JTAC assignment first. Use 'Request JTAC map code' option.", 10, 2, true, mission.playerGroupID)
        return
    end
    
    if mission.awaitingMarker then
        JTAC.MESSAGES.setMsg("Place your JTAC marker first: " .. mission.jtacCallSign, 10, 2, true, mission.playerGroupID)
        JTAC.MESSAGES.setMsg("Your laser code: " .. mission.target.laserCode, 8, 2, false, mission.playerGroupID)
        return
    end
    
    if mission.support == true then
        if mission.target.laserPos ~= nil and mission.target.laserCode ~= nil then
            JTAC.MESSAGES.setMessageDelayed(mission.player.. " : Requesting drone for painting target near following coordinates: ", 7, 1, true)
            local lat, long, alt = coord.LOtoLL(mission.target.laserPos)
            local coordSTR = JTAC.getCoordinatesSTR(lat, long, alt)
            local MGRS = coord.LLtoMGRS(coord.LOtoLL(mission.target.laserPos))
            JTAC.MESSAGES.setMessageDelayed(coordSTR.lat .. " " .. coordSTR.long .. " " .. coordSTR.alt .. "m", 7, 1, false)
            if mission.target.isLaseAvailable == true then
                if (mission.target.droneInZone == false and mission.target.droneInFlight == false) then
                    -- Check if player has enough command tokens before spawning
                    if JTAC.spendCMDPoints(mission.player, 20) then
                        timer.scheduleFunction(JTAC.createDroneDelayedForPlayer, mission, timer.getTime() + mission.target.waitTime)
                        JTAC.MESSAGES.setMessageDelayed("COMMAND: Copied, sending Reaper drone to Zone", 10, 12, true)
                        JTAC.MESSAGES.setMessageDelayed("INFO: Total ETA for drone " .. mission.target.waitTime .." secs", 10, 12, false)
                        JTAC.MESSAGES.setMsg("Laser Code: " .. mission.target.laserCode, 10, 12, false, mission.playerGroupID)
                        JTAC.MESSAGES.setMessageDelayed(coordSTR.lat .. " " .. coordSTR.long .. " " .. coordSTR.alt .. "m", 60, 12, false)
                        JTAC.MESSAGES.setMessageDelayed("MGRS: " .. MGRS.UTMZone .. ' ' .. MGRS.MGRSDigraph .. ' ' .. string.format("%05d", MGRS.Easting) .. ' ' .. string.format("%05d", MGRS.Northing), 60, 12, false)
                        mission.target.droneInFlight = true;

                    else
                        JTAC.MESSAGES.setMsg("COMMAND: Negative, insufficient command points for JTAC request, who is this guy?.", 10, 12, true, mission.playerGroupID)
                    end

                elseif (mission.target.droneInZone == false and mission.target.droneInFlight == true) then
                    JTAC.MESSAGES.setMsg("COMMAND: Negative, MQ-9 Reaper is on its way yet.", 10, 12, true, mission.playerGroupID)
                end
            else
                JTAC.MESSAGES.setMsg("COMMAND: Negative, there is not support available.", 10, 12, true, mission.playerGroupID)
            end
        else
            -- This shouldn't happen if logic is correct - mission has laserCode but no laserPos
            JTAC.MESSAGES.setMsg("ERROR: Mission state inconsistent. Please restart JTAC assignment.", 10, 12, true, mission.playerGroupID)
            debugMsg("ERROR: Player " .. mission.player .. " has laserCode but no laserPos - resetting mission")
            -- Reset mission state
            JTAC.releaseLaserCode(mission.target.laserCode)
            JTAC.releaseJTACCallSign(mission.jtacCallSign)
            mission.target.laserCode = nil
            mission.jtacCallSign = nil
            mission.awaitingMarker = false
            JTAC.setMenuForPlayer(mission)
        end
    else
        JTAC.MESSAGES.setMsg("Jtac unavalaible , Already in service", 10, 12, true, mission.playerGroupID)
        if mission.target.droneName ~= "" then
            debugMsg('Drone: ' .. mission.airCallsign .. ' ' .. mission.target.droneName .. " unavalaible , Already in service")
        else
            return false
        end
        return false
    end
end;

function JTAC.createDroneDelayedForPlayer(mission)
    mission.target.droneName = "JtacDrone" .. math.random(9999,99999)
	local _country = country.id.CJTF_BLUE

	if coalition.getPlayers(coalition.side.RED)[1] ~= nil then
		_country = country.id.CJTF_RED
	elseif coalition.getPlayers(coalition.side.BLUE)[1] ~= nil then
		_country = country.id.CJTF_BLUE
	end

	local _droneData =
                        {
                            ["modulation"] = 0,
                                ["tasks"] =
                                {
                                }, -- end of ["tasks"]
                                ["radioSet"] = false,
                                ["task"] = "AFAC",
                                ["uncontrolled"] = false,
                                ["route"] =
                                {
                                    ["points"] =
                                    {
                                        [1] =
                                        {
                                            ["alt"] = 3048,
                                            ["action"] = "Turning Point",
                                            ["alt_type"] = "BARO",
                                            ["properties"] =
                                            {
                                                ["addopt"] =
                                                {
                                                }, -- end of ["addopt"]
                                            }, -- end of ["properties"]
                                            ["speed"] = 61.666666666667,
                                            ["task"] =
                                            {
                                                ["id"] = "ComboTask",
                                                ["params"] =
                                                {
                                                    ["tasks"] = 
                                                    {
                                                        [1] = 
                                                        {
                                                            ["enabled"] = true,
                                                            ["auto"] = true,
                                                            ["id"] = "FAC",
                                                            ["number"] = 1,
                                                            ["params"] = 
                                                            {
                                                                ["number"] = 1,
                                                                ["designation"] = "Auto",
                                                                ["modulation"] = 0,
                                                                ["callname"] = JTAC.getCallnameNumber(mission.airCallsign),
                                                                ["datalink"] = true,
                                                                ["frequency"] = 133000000,
                                                            }, -- end of ["params"]
                                                        }, -- end of [1]
                                                        [2] = 
                                                        {
                                                            ["enabled"] = true,
                                                            ["auto"] = true,
                                                            ["id"] = "WrappedAction",
                                                            ["number"] = 2,
                                                            ["params"] = 
                                                            {
                                                                ["action"] = 
                                                                {
                                                                    ["id"] = "EPLRS",
                                                                    ["params"] = 
                                                                    {
                                                                        ["value"] = true,
                                                                        ["groupId"] = 1,
                                                                    }, -- end of ["params"]
                                                                }, -- end of ["action"]
                                                            }, -- end of ["params"]
                                                        }, -- end of [2]
                                                        [3] = 
                                                        {
                                                            ["number"] = 3,
                                                            ["auto"] = false,
                                                            ["id"] = "WrappedAction",
                                                            ["enabled"] = true,
                                                            ["params"] = 
                                                            {
                                                                ["action"] = 
                                                                {
                                                                    ["id"] = "SetInvisible",
                                                                    ["params"] = 
                                                                    {
                                                                        ["value"] = true,
                                                                    }, -- end of ["params"]
                                                                }, -- end of ["action"]
                                                            }, -- end of ["params"]
                                                        }, -- end of [3]
                                                        [4] = 
                                                        {
                                                            ["number"] = 4,
                                                            ["auto"] = false,
                                                            ["id"] = "WrappedAction",
                                                            ["enabled"] = true,
                                                            ["params"] = 
                                                            {
                                                                ["action"] = 
                                                                {
                                                                    ["id"] = "SetImmortal",
                                                                    ["params"] = 
                                                                    {
                                                                        ["value"] = true,
                                                                    }, -- end of ["params"]
                                                                }, -- end of ["action"]
                                                            }, -- end of ["params"]
                                                        }, -- end of [4]
                                                    }, -- end of ["tasks"]
                                                }, -- end of ["params"]
                                            }, -- end of ["task"]
                                            ["type"] = "Turning Point",
                                            ["ETA"] = 0,
                                            ["ETA_locked"] = true,
                                            ["y"] = mission.target.laserPos.z + 1000, -- spawn coord
                                            ["x"] = mission.target.laserPos.x + 1000, -- spawn coord
                                            ["name"] = "Initial Point",
                                            ["speed_locked"] = true,
                                            ["formation_template"] = "",
                                        }, -- end of [1]
                                        [2] =
                                        {
                                            ["alt"] = 3048,
                                            ["action"] = "Turning Point",
                                            ["alt_type"] = "BARO",
                                            ["properties"] =
                                            {
                                                ["addopt"] =
                                                {
                                                }, -- end of ["addopt"]
                                            }, -- end of ["properties"]
                                            ["speed"] = 61.666666666667,
                                            ["task"] =
                                            {
                                                ["id"] = "ComboTask",
                                                ["params"] =
                                                {
                                                    ["tasks"] =
                                                    {
                                                        [1] =
                                                        {
                                                            ["number"] = 1,
                                                            ["auto"] = false,
                                                            ["id"] = "Orbit",
                                                            ["enabled"] = true,
                                                            ["params"] =
                                                            {
                                                                ["altitude"] = 7620,
                                                                ["pattern"] = "Circle",
                                                                ["speed"] = 55.555555555556,
                                                            }, -- end of ["params"]
                                                        }, -- end of [1]
                                                    }, -- end of ["tasks"]
                                                }, -- end of ["params"]
                                            }, -- end of ["task"]
                                            ["type"] = "Turning Point",
                                            ["ETA"] = 96.011094947238,
                                            ["ETA_locked"] = false,
                                            ["y"] = mission.target.laserPos.z, -- orbit spot coord
                                            ["x"] = mission.target.laserPos.x, -- orbit spot coord
                                            ["name"] = "spot",
                                            ["speed_locked"] = true,
                                            ["formation_template"] = "",
                                        }, -- end of [2]
                                    }, -- end of ["points"]
                                }, -- end of ["route"]
                                ["groupId"] = math.random(9999,99999),
                                ["hidden"] = false,
                                ["units"] =
                                {
                                    [1] =
                                    {
                                        ["alt"] = 7620,
                                        ["alt_type"] = "BARO",
                                        ["livery_id"] = "'camo' scheme",
                                        ["skill"] = "High",
                                        ["speed"] = 61.666666666667,
                                        ["type"] = "MQ-9 Reaper",
                                        ["unitId"] = 1,
                                        ["psi"] = 0,
                                        ["onboard_num"] = "010",
                                        ["y"] = mission.target.laserPos.z + 1000, -- spawn coord
                                        ["x"] = mission.target.laserPos.x + 1000,  -- spawn coord
                                        ["name"] = mission.target.droneName,
                                        ["payload"] =
                                        {
                                            ["pylons"] =
                                            {
                                            }, -- end of ["pylons"]
                                            ["fuel"] = 1300,
                                            ["flare"] = 0,
                                            ["chaff"] = 0,
                                            ["gun"] = 100,
                                        }, -- end of ["payload"]
                                        ["heading"] = 0,
                                        ["callsign"] =
                                        {
                                            [1] = 3,
                                            [2] = 1,
                                            ["name"] = mission.airCallsign,
                                            [3] = 1,
                                        }, -- end of ["callsign"]
                                    }, -- end of [1]
                                }, -- end of ["units"]
                                ["y"] = mission.target.laserPos.z + 1000,
                                ["x"] = mission.target.laserPos.x + 1000,
                                ["name"] = mission.target.droneName,
                                ["communication"] = true,
                                ["start_time"] = 0,
                                ["frequency"] = 251,
                        }

	coalition.addGroup(_country, Group.Category.AIRPLANE, _droneData)
    local jtacname = Group.getByName(mission.target.droneName):getUnit(1)
    JTAC.TARGETMENU.menuForPlayer(jtacname, mission.target.irPos, mission)
	JTAC.MESSAGES.setMessageDelayed(mission.airCallsign .. ": Drone is in the Operation area. Ready to copy target. Over", 20, 2, true)
	
    -- Remove the request menus and add control menus
    if mission.menuHandles.JD11 then missionCommands.removeItemForGroup(mission.playerGroupID, mission.menuHandles.JD11) end
    if mission.menuHandles.JG11 then missionCommands.removeItemForGroup(mission.playerGroupID, mission.menuHandles.JG11) end
    
    -- Remove any existing dismiss package menu items to prevent duplicates
    if mission.menuHandles.JD99 then missionCommands.removeItemForGroup(mission.playerGroupID, mission.menuHandles.JD99) end
    if mission.menuHandles.N9 then missionCommands.removeItemForGroup(mission.playerGroupID, mission.menuHandles.N9) end
    
    -- Create DISMISS PACKAGE submenu
    mission.menuHandles.N9 = missionCommands.addSubMenuForGroup(mission.playerGroupID, 'DISMISS PACKAGE', mission.menuHandles.menuPrinc)
    
    mission.menuHandles.JD13 = missionCommands.addCommandForGroup(mission.playerGroupID, 'Lase my mark', mission.menuHandles.J1, 
        function() JTAC.LASER.createLaserOnMarkForPlayer(mission, {jtac = jtacname, GroupPosition = mission.target.laserPos, TGT = "Mark", currentLasedTarget = "STOP"}) end)
    
    mission.menuHandles.JD23 = missionCommands.addCommandForGroup(mission.playerGroupID, 'IR my mark', mission.menuHandles.J1, 
        function() JTAC.IR.createInfraRedOnMarkForPlayer(mission, {jtac = jtacname, GroupPosition = mission.target.irPos, TGT = "Mark", currentLasedTarget = "STOP"}) end)
    
    mission.menuHandles.JD14 = missionCommands.addCommandForGroup(mission.playerGroupID, 'Terminate lasing', mission.menuHandles.J1, 
        function() JTAC.LASER.stopLaserForPlayer(mission) end)
    
    mission.menuHandles.JD24 = missionCommands.addCommandForGroup(mission.playerGroupID, 'Terminate IR lasing', mission.menuHandles.J1, 
        function() JTAC.IR.stopIRForPlayer(mission) end)
    
    mission.menuHandles.N31 = missionCommands.addCommandForGroup(mission.playerGroupID, 'Illumination Bomb', mission.menuHandles.J1, 
        function() JTAC.BILLUM.illuminationBombOnMarkForPlayer(mission, mission.target.irPos) end)
    
    mission.menuHandles.N32 = missionCommands.addCommandForGroup(mission.playerGroupID, 'Smoke my mark', mission.menuHandles.J1, 
        function() JTAC.SMOKE.smokeOnMarkForPlayer(mission, mission.target.irPos) end)
    
    mission.menuHandles.JD98 = missionCommands.addCommandForGroup(mission.playerGroupID, 'ReScan', mission.menuHandles.J1, 
        function() JTAC.NewMarkerScanForPlayer(mission) end)
    
    mission.menuHandles.JD99 = missionCommands.addCommandForGroup(mission.playerGroupID, 'Dismiss DRONE package', mission.menuHandles.N9,
        function() JTAC.requestDismissPackageForPlayer(mission, "DRONE") end)
    
	mission.target.droneInZone = true
    mission.support = false
    
    -- Update availability for all missions after deploying new JTAC
    JTAC.setAvailability()

end;

function JTAC.requestGroundForPlayer(mission)
    if not mission.target.laserCode then
        JTAC.MESSAGES.setMsg("You need to request JTAC assignment first. Use 'Request JTAC map code' option.", 10, 2, true, mission.playerGroupID)
        return
    end
    
    if mission.awaitingMarker then
        JTAC.MESSAGES.setMsg("Place your JTAC marker first: " .. mission.jtacCallSign, 10, 2, true, mission.playerGroupID)
        JTAC.MESSAGES.setMsg("Your laser code: " .. mission.target.laserCode, 8, 2, false, mission.playerGroupID)
        return
    end
    
    if mission.support == true then

        if mission.target.laserPos ~= nil and mission.target.laserCode ~= nil then
            JTAC.MESSAGES.setMessageDelayed(mission.player .. " : Requesting Ground for painting target near following coordinates: ", 7, 1, true)
            local lat, long, alt = coord.LOtoLL(mission.target.laserPos)
            local coordSTR = JTAC.getCoordinatesSTR(lat, long, alt)
            local MGRS = coord.LLtoMGRS(coord.LOtoLL(mission.target.laserPos))
            JTAC.MESSAGES.setMessageDelayed(coordSTR.lat .. " " .. coordSTR.long .. " " .. coordSTR.alt .. "m", 7, 1, false)
            if mission.target.isLaseAvailable == true then
                if (mission.target.droneInZone == false and mission.target.droneInFlight == false) then
                    -- Check if player has enough command tokens before spawning
                    if JTAC.spendCMDPoints(mission.player, 10) then
                        timer.scheduleFunction(JTAC.createGroundDelayedForPlayer, mission, timer.getTime() + mission.target.waitTime)
                        JTAC.MESSAGES.setMessageDelayed("COMMAND: Copied, sending Ground to Zone.", 10, 12, true)
                        JTAC.MESSAGES.setMessageDelayed("INFO: Total ETA for Ground " .. mission.target.waitTime .." secs", 10, 12, false)
                        JTAC.MESSAGES.setMsg("Laser Code: " .. mission.target.laserCode, 10, 12, false, mission.playerGroupID)
                        JTAC.MESSAGES.setMessageDelayed(coordSTR.lat .. " " .. coordSTR.long .. " " .. coordSTR.alt .. "m", 60, 12, false)
                        JTAC.MESSAGES.setMessageDelayed("MGRS: " .. MGRS.UTMZone .. ' ' .. MGRS.MGRSDigraph .. ' ' .. string.format("%05d", MGRS.Easting) .. ' ' .. string.format("%05d", MGRS.Northing), 60, 12, false)
                        mission.target.droneInFlight = true;
                    else
                        JTAC.MESSAGES.setMsg("COMMAND: Negative, insufficient command tokens for ground request.", 10, 12, true, mission.playerGroupID)
                    end

                elseif (mission.target.droneInZone == false and mission.target.droneInFlight == true) then
                    JTAC.MESSAGES.setMsg("COMMAND: Negative, Ground Units is on its way yet.", 10, 12, true, mission.playerGroupID)
                end
            else
                JTAC.MESSAGES.setMsg("COMMAND: Negative, there is currently no support available.", 10, 12, true, mission.playerGroupID)
            end
        else
            -- This shouldn't happen if logic is correct - mission has laserCode but no laserPos
            JTAC.MESSAGES.setMsg("ERROR: Mission state inconsistent. Please restart JTAC assignment.", 10, 12, true, mission.playerGroupID)
            debugMsg("ERROR: Player " .. mission.player .. " has laserCode but no laserPos - resetting mission")
            -- Reset mission state
            JTAC.releaseLaserCode(mission.target.laserCode)
            JTAC.releaseJTACCallSign(mission.jtacCallSign)
            mission.target.laserCode = nil
            mission.jtacCallSign = nil
            mission.awaitingMarker = false
            JTAC.setMenuForPlayer(mission)
        end
    else
        JTAC.MESSAGES.setMsg("Jtac unavalaible , Already in service", 10, 12, true, mission.playerGroupID)
        if mission.target.groundName ~= "" then
            JTAC.MESSAGES.setMsg('Ground: ' .. mission.groundCallsign .. ' ' .. mission.target.groundName .. " unavalaible , Already in service", 10, 12, true, mission.playerGroupID)
        else
            return false
        end
        return false
    end
end;

function JTAC.createGroundDelayedForPlayer(mission)
    mission.target.groundName = "JtacGround" .. math.random(9999,99999)

    local _country = country.id.CJTF_BLUE

	if coalition.getPlayers(coalition.side.RED)[1] ~= nil then
		_country = country.id.CJTF_RED
	elseif coalition.getPlayers(coalition.side.BLUE)[1] ~= nil then
		_country = country.id.CJTF_BLUE
	end

	local _GroundData =
                        {
                            ["visible"] = false,
                                ["tasks"] =
                                {
                                }, -- end of ["tasks"]
                                ["uncontrollable"] = false,
                                ["task"] = "Ground Nothing",
                                ["taskSelected"] = true,
                                ["route"] =
                                {
                                    ["spans"] =
                                    {
                                        [1] =
                                        {
                                            [1] =
                                            {
                                                ["y"] = mission.target.laserPos.z + 1000,
                                                ["x"] = mission.target.laserPos.x + 1000,
                                            }, -- end of [1]
                                            [2] =
                                            {
                                                ["y"] = mission.target.laserPos.z + 300,
                                                ["x"] = mission.target.laserPos.x + 300,
                                            }, -- end of [2]
                                        }, -- end of [1]
                                        [2] =
                                        {
                                            [1] =
                                            {
                                                ["y"] = mission.target.laserPos.z + 300,
                                                ["x"] = mission.target.laserPos.x + 300,
                                            }, -- end of [1]
                                            [2] =
                                            {
                                                ["y"] = mission.target.laserPos.z + 300,
                                                ["x"] = mission.target.laserPos.x + 300,
                                            }, -- end of [2]
                                        }, -- end of [2]
                                    }, -- end of ["spans"]
                                    ["points"] =
                                    {
                                        [1] =
                                        {
                                            ["alt"] = 42,
                                            ["type"] = "Turning Point",
                                            ["ETA"] = 0,
                                            ["alt_type"] = "BARO",
                                            ["formation_template"] = "",
                                            ["y"] = mission.target.laserPos.z + 1000,
                                            ["x"] = mission.target.laserPos.x + 1000,
                                            ["name"] = "spawn",
                                            ["ETA_locked"] = true,
                                            ["speed"] = 0,
                                            ["action"] = "Off Road",
                                            ["task"] =
                                            {
                                                ["id"] = "ComboTask",
                                                ["params"] =
                                                {
                                                    ["tasks"] =
                                                    {
                                                        [1] =
                                                        {
                                                            ["number"] = 1,
                                                            ["auto"] = true,
                                                            ["id"] = "WrappedAction",
                                                            ["enabled"] = true,
                                                            ["params"] =
                                                            {
                                                                ["action"] =
                                                                {
                                                                    ["id"] = "EPLRS",
                                                                    ["params"] =
                                                                    {
                                                                        ["value"] = true,
                                                                        ["groupId"] = 1,
                                                                    }, -- end of ["params"]
                                                                }, -- end of ["action"]
                                                            }, -- end of ["params"]
                                                        }, -- end of [1]
                                                        [2] =
                                                        {
                                                            ["enabled"] = true,
                                                            ["auto"] = false,
                                                            ["id"] = "WrappedAction",
                                                            ["number"] = 2,
                                                            ["params"] =
                                                            {
                                                                ["action"] =
                                                                {
                                                                    ["id"] = "SetInvisible",
                                                                    ["params"] =
                                                                    {
                                                                        ["value"] = true,
                                                                    }, -- end of ["params"]
                                                                }, -- end of ["action"]
                                                            }, -- end of ["params"]
                                                        }, -- end of [2]
                                                        [3] =
                                                        {
                                                            ["enabled"] = true,
                                                            ["auto"] = false,
                                                            ["id"] = "WrappedAction",
                                                            ["number"] = 3,
                                                            ["params"] =
                                                            {
                                                                ["action"] =
                                                                {
                                                                    ["id"] = "SetImmortal",
                                                                    ["params"] =
                                                                    {
                                                                        ["value"] = true,
                                                                    }, -- end of ["params"]
                                                                }, -- end of ["action"]
                                                            }, -- end of ["params"]
                                                        }, -- end of [3]
                                                        [4] =
                                                        {
                                                            ["enabled"] = true,
                                                            ["auto"] = false,
                                                            ["id"] = "WrappedAction",
                                                            ["number"] = 4,
                                                            ["params"] =
                                                            {
                                                                ["action"] =
                                                                {
                                                                    ["id"] = "Option",
                                                                    ["params"] =
                                                                    {
                                                                        ["value"] = 4,
                                                                        ["name"] = 0,
                                                                    }, -- end of ["params"]
                                                                }, -- end of ["action"]
                                                            }, -- end of ["params"]
                                                        }, -- end of [4]
                                                    }, -- end of ["tasks"]
                                                }, -- end of ["params"]
                                            }, -- end of ["task"]
                                            ["speed_locked"] = true,
                                        }, -- end of [1]
                                        [2] =
                                        {
                                            ["alt"] = 11,
                                            ["type"] = "Turning Point",
                                            ["ETA"] = 278.24736729865,
                                            ["alt_type"] = "BARO",
                                            ["formation_template"] = "",
                                            ["y"] = mission.target.laserPos.z + 300,
                                            ["x"] = mission.target.laserPos.x + 300,
                                            ["name"] = "SPOT",
                                            ["ETA_locked"] = false,
                                            ["speed"] = 5.5555555555556,
                                            ["action"] = "Off Road",
                                            ["task"] =
                                            {
                                                ["id"] = "ComboTask",
                                                ["params"] =
                                                {
                                                    ["tasks"] =
                                                    {
                                                    }, -- end of ["tasks"]
                                                }, -- end of ["params"]
                                            }, -- end of ["task"]
                                            ["speed_locked"] = true,
                                        }, -- end of [2]
                                    }, -- end of ["points"]
                                }, -- end of ["route"]
                                ["groupId"] = 1,
                                ["hidden"] = false,
                                ["units"] =
                                {
                                    [1] =
                                    {
                                        ["skill"] = "Average",
                                        ["coldAtStart"] = false,
                                        ["type"] = "M1045 HMMWV TOW",
                                        ["unitId"] = 1,
                                        ["y"] = mission.target.laserPos.z + 1000,
                                        ["x"] = mission.target.laserPos.x + 1000,
                                        ["name"] = mission.groundCallsign,
                                        ["heading"] = 0,
                                        ["playerCanDrive"] = true,
                                    }, -- end of [1]
                                }, -- end of ["units"]
                                ["y"] = mission.target.laserPos.z + 1000,
                                ["x"] = mission.target.laserPos.x + 1000,
                                ["name"] = mission.target.groundName,
                                ["start_time"] = 0,
                        }

	coalition.addGroup(_country, Group.Category.GROUND, _GroundData)

    local jtacname = Group.getByName(mission.target.groundName):getUnit(1)

    JTAC.TARGETMENU.menuForPlayer(jtacname, mission.target.irPos, mission)
	JTAC.MESSAGES.setMessageDelayed(mission.groundCallsign .. ": Ground is in the Operation area. Ready to copy target. Over", 20, 2, true)
	
    -- Remove the request menus and add control menus
    if mission.menuHandles.JD11 then missionCommands.removeItemForGroup(mission.playerGroupID, mission.menuHandles.JD11) end
    if mission.menuHandles.JG11 then missionCommands.removeItemForGroup(mission.playerGroupID, mission.menuHandles.JG11) end

    -- Remove any existing dismiss package menu items to prevent duplicates
    if mission.menuHandles.JD99 then missionCommands.removeItemForGroup(mission.playerGroupID, mission.menuHandles.JD99) end
    if mission.menuHandles.N9 then missionCommands.removeItemForGroup(mission.playerGroupID, mission.menuHandles.N9) end
    
    -- Create DISMISS PACKAGE submenu
    mission.menuHandles.N9 = missionCommands.addSubMenuForGroup(mission.playerGroupID, 'DISMISS PACKAGE', mission.menuHandles.menuPrinc)

    mission.menuHandles.JD13 = missionCommands.addCommandForGroup(mission.playerGroupID, 'Lase my mark', mission.menuHandles.J1, 
        function() JTAC.LASER.createLaserOnMarkForPlayer(mission, {jtac = jtacname, GroupPosition = mission.target.laserPos, Type = "Ground ", TGT = "Mark", currentLasedTarget = "STOP"}) end)
    
    mission.menuHandles.JD23 = missionCommands.addCommandForGroup(mission.playerGroupID, 'IR my mark', mission.menuHandles.J1, 
        function() JTAC.IR.createInfraRedOnMarkForPlayer(mission, {jtac = jtacname, GroupPosition = mission.target.irPos, Type = "Ground ", TGT = "Mark", currentLasedTarget = "STOP"}) end)
    
    mission.menuHandles.N31 = missionCommands.addCommandForGroup(mission.playerGroupID, 'Illumination Bomb', mission.menuHandles.J1, 
        function() JTAC.BILLUM.illuminationBombOnMarkForPlayer(mission, mission.target.irPos) end)
    
    mission.menuHandles.N32 = missionCommands.addCommandForGroup(mission.playerGroupID, 'Smoke my mark', mission.menuHandles.J1, 
        function() JTAC.SMOKE.smokeOnMarkForPlayer(mission, mission.target.irPos) end)
    
    mission.menuHandles.N33 = missionCommands.addCommandForGroup(mission.playerGroupID, 'Smoke Ground Jtac', mission.menuHandles.J1, 
        function() JTAC.SMOKE.smokeOnJtacForPlayer(mission, mission.target.groundName) end)
    
    mission.menuHandles.JD14 = missionCommands.addCommandForGroup(mission.playerGroupID, 'Terminate lasing', mission.menuHandles.J1, 
        function() JTAC.LASER.stopLaserForPlayer(mission) end)
    
    mission.menuHandles.JD24 = missionCommands.addCommandForGroup(mission.playerGroupID, 'Terminate IR lasing', mission.menuHandles.J1, 
        function() JTAC.IR.stopIRForPlayer(mission) end)
    
    mission.menuHandles.JD98 = missionCommands.addCommandForGroup(mission.playerGroupID, 'ReScan', mission.menuHandles.J1, 
        function() JTAC.NewMarkerScanForPlayer(mission) end)
    
    mission.menuHandles.JD99 = missionCommands.addCommandForGroup(mission.playerGroupID, 'Dismiss GROUND package', mission.menuHandles.N9,
        function() JTAC.requestDismissPackageForPlayer(mission, "GROUND") end)
    
	mission.target.droneInZone = true
    mission.support = false
    
    -- Update availability for all missions after deploying new JTAC
    JTAC.setAvailability()

end;

-- =====================================================================================
-- TARGETING FUNCTIONS
-- =====================================================================================

-- Player-specific target update functions
function JTAC.targetIRUpdatePosForPlayer(params)
    local mission = params.mission
    local time = timer.getTime()
    
    -- Check if we should still be tracking
    if not mission or not mission.target or mission.target.currentLasedTarget == "STOP" then
        return nil
    end
    
    local targetUnit = Unit.getByName(mission.target.currentLasedTarget)
    if not targetUnit or not targetUnit:isExist() then
        -- Check if unit was destroyed vs moved out of range
        if not targetUnit then
            -- Unit.getByName() returned nil - target was destroyed
            JTAC.MESSAGES.setMsg("GOOD EFFECT! Target destroyed: " .. mission.target.currentLasedTarget, 10, 2, true, mission.playerGroupID)
            debugMsg("Target destroyed: " .. mission.target.currentLasedTarget)
            -- Refresh target menu to remove destroyed target
            timer.scheduleFunction(function() 
                if mission.target.droneName ~= "" and Group.getByName(mission.target.droneName) then
                    local jtacunit = Group.getByName(mission.target.droneName):getUnit(1)
                    if jtacunit then JTAC.NewMarkerScanForPlayer(mission) end
                elseif mission.target.groundName ~= "" and Group.getByName(mission.target.groundName) then
                    local jtacunit = Group.getByName(mission.target.groundName):getUnit(1)
                    if jtacunit then JTAC.NewMarkerScanForPlayer(mission) end
                end
            end, nil, timer.getTime() + 1)
        else
            -- Unit exists but isExist() is false - moved out of range or inactive
            debugMsg("Target unit no longer active (out of range): " .. mission.target.currentLasedTarget)
        end
        mission.target.currentLasedTarget = "STOP"
        mission.target.lastIRPosition = nil
        if mission.target.irSpot ~= nil then
            mission.target.irSpot:destroy()
            mission.target.irSpot = nil
        end
        return nil
    end
    
    local targetCoord = targetUnit:getPosition().p
    
    -- Check if target has moved significantly
    local shouldUpdate = false
    if not mission.target.lastIRPosition then
        -- Store initial position but don't update IR (already created)
        mission.target.lastIRPosition = {x = targetCoord.x, y = targetCoord.y, z = targetCoord.z}
    else
        -- Check distance moved
        local dx = targetCoord.x - mission.target.lastIRPosition.x
        local dz = targetCoord.z - mission.target.lastIRPosition.z
        local distance = math.sqrt(dx*dx + dz*dz)
        
        if distance > 10 then  -- 10 meter threshold
            shouldUpdate = true
            mission.target.lastIRPosition = {x = targetCoord.x, y = targetCoord.y, z = targetCoord.z}
        end
    end
    
    -- Only update IR if target moved significantly
    if shouldUpdate then
        if mission.target.irSpot ~= nil then
            mission.target.irSpot:destroy()
        end
        
        local jtacunit = nil
        if mission.target.droneName ~= "" and Group.getByName(mission.target.droneName) then
            jtacunit = Group.getByName(mission.target.droneName):getUnit(1)
        elseif mission.target.groundName ~= "" and Group.getByName(mission.target.groundName) then
            jtacunit = Group.getByName(mission.target.groundName):getUnit(1)
        end
        if jtacunit then
            mission.target.irSpot = Spot.createInfraRed(jtacunit, nil, targetCoord)
        end
    end
    
    return time + 1.0  -- Check every second
end;

function JTAC.targetLaserUpdatePosForPlayer(params)
    local mission = params.mission
    local time = timer.getTime()
    
    -- Check if we should still be tracking
    if not mission or not mission.target or mission.target.currentLasedTarget == "STOP" then
        debugMsg("Laser tracking stopped for player: " .. (mission and mission.player or "unknown"))
        return nil
    end
    
    local targetUnit = Unit.getByName(mission.target.currentLasedTarget)
    if not targetUnit or not targetUnit:isExist() then
        -- Check if unit was destroyed vs moved out of range
        if not targetUnit then
            -- Unit.getByName() returned nil - target was destroyed
            JTAC.MESSAGES.setMsg("GOOD EFFECT! Target destroyed: " .. mission.target.currentLasedTarget, 10, 2, true, mission.playerGroupID)
            debugMsg("Target destroyed: " .. mission.target.currentLasedTarget)
            -- Refresh target menu to remove destroyed target
            timer.scheduleFunction(function() 
                if mission.target.droneName ~= "" and Group.getByName(mission.target.droneName) then
                    local jtacunit = Group.getByName(mission.target.droneName):getUnit(1)
                    if jtacunit then JTAC.NewMarkerScanForPlayer(mission) end
                elseif mission.target.groundName ~= "" and Group.getByName(mission.target.groundName) then
                    local jtacunit = Group.getByName(mission.target.groundName):getUnit(1)
                    if jtacunit then JTAC.NewMarkerScanForPlayer(mission) end
                end
            end, nil, timer.getTime() + 1)
        else
            -- Unit exists but isExist() is false - moved out of range or inactive
            debugMsg("Target unit no longer active (out of range): " .. mission.target.currentLasedTarget)
        end
        mission.target.currentLasedTarget = "STOP"
        mission.target.lastLasedPosition = nil
        if mission.target.laserSpot ~= nil then
            mission.target.laserSpot:destroy()
            mission.target.laserSpot = nil
        end

        return nil
    end
    
    local targetCoord = targetUnit:getPosition().p
    
    -- Check if target has moved significantly
    local shouldUpdate = false
    if not mission.target.lastLasedPosition then
        -- Store initial position but don't update laser (already created)
        mission.target.lastLasedPosition = {x = targetCoord.x, y = targetCoord.y, z = targetCoord.z}
        --debugMsg("Stored initial position for: " .. mission.target.currentLasedTarget)
    else
        -- Check distance moved
        local dx = targetCoord.x - mission.target.lastLasedPosition.x
        local dz = targetCoord.z - mission.target.lastLasedPosition.z
        local distance = math.sqrt(dx*dx + dz*dz)
        
        if distance > 8 then  -- 8 meter threshold to avoid micro-movements
            shouldUpdate = true
            mission.target.lastLasedPosition = {x = targetCoord.x, y = targetCoord.y, z = targetCoord.z}
            debugMsg("Target moved " .. string.format("%.1f", distance) .. "m, updating laser for: " .. mission.target.currentLasedTarget)
        end
    end
    
    -- Only update laser if target moved significantly
    if shouldUpdate then
        if mission.target.laserSpot ~= nil then
            mission.target.laserSpot:destroy()
        end
        
        local jtacunit = nil
        if mission.target.droneName ~= "" and Group.getByName(mission.target.droneName) then
            jtacunit = Group.getByName(mission.target.droneName):getUnit(1)
        elseif mission.target.groundName ~= "" and Group.getByName(mission.target.groundName) then
            jtacunit = Group.getByName(mission.target.groundName):getUnit(1)
        end
        
        if jtacunit then
            mission.target.laserSpot = Spot.createLaser(jtacunit, nil, targetCoord, mission.target.laserCode)
        else
            debugMsg("Warning: No JTAC unit found for laser update")
        end
    end
    
    return time + 1.0  -- Check every second
end;

function JTAC.BILLUM.illuminationBombOnMark(position)
    timer.scheduleFunction(JTAC.BILLUM.illuminationBombOnMarkDelay, position, timer.getTime() + 15)
    JTAC.MESSAGES.setMsg(" Requesting current target illumination. ", 7, 1, true, JTAC.playerGroupID)
	JTAC.MESSAGES.setMsg(" Roger, painting your target now.... Illumination round is on its way. " , 30, 8, true, JTAC.playerGroupID)
end;

function JTAC.BILLUM.triggerIllumBomb(mark)
    trigger.action.illuminationBomb(mark, 1000000 )
end;

function JTAC.BILLUM.illuminationBombOnMarkDelay(position)  
    local targetAlt =  position.y
    local altitude = targetAlt + math.random(600, 1200)
    local r1 = math.random(200, 300)
    local r2 = math.random(50, 150)

    local mark0 = {x = position.x, y = altitude, z = position.z}
    local mark1 = {x = position.x + r1, y = altitude, z = position.z}
    local mark2 = {x = position.x + r2, y = altitude, z = position.z}
    local mark3 = {x = position.x - r2, y = altitude, z = position.z}
    local mark4 = {x = position.x - r1, y = altitude, z = position.z}

    timer.scheduleFunction(JTAC.BILLUM.triggerIllumBomb, mark1, timer.getTime() + 5)
    timer.scheduleFunction(JTAC.BILLUM.triggerIllumBomb, mark2, timer.getTime() + 7)
    timer.scheduleFunction(JTAC.BILLUM.triggerIllumBomb, mark0, timer.getTime() + 9)
    timer.scheduleFunction(JTAC.BILLUM.triggerIllumBomb, mark3, timer.getTime() + 11)
    timer.scheduleFunction(JTAC.BILLUM.triggerIllumBomb, mark4, timer.getTime() + 13)
end;

function JTAC.SMOKE.smokeOnMark(position)
    timer.scheduleFunction(JTAC.SMOKE.triggerSmokeRed, position, timer.getTime() + 15)
    JTAC.MESSAGES.setMsg(" Requesting smoke on selected target. ", 7, 1, true, JTAC.playerGroupID)
	JTAC.MESSAGES.setMsg(" Roger, painting your target now with red smoke. ETA 15s " , 30, 8, true, JTAC.playerGroupID)
end;

function JTAC.SMOKE.smokeOnJtac(groundName)
    source = Group.getByName(groundName):getUnit(1)
    position = source:getPoint()
    timer.scheduleFunction(JTAC.SMOKE.triggerSmokeGreen, position, timer.getTime() + 15)
    JTAC.MESSAGES.setMsg(" Requesting smoke Jtac position. ", 7, 1, true, JTAC.playerGroupID)
	JTAC.MESSAGES.setMsg(" Roger, Green smoke on Jtac position. ETA 15s " , 30, 8, true, JTAC.playerGroupID)
end;

function JTAC.SMOKE.triggerSmokeRed(position)
    trigger.action.smoke(position , trigger.smokeColor.Red)
end;

function JTAC.SMOKE.triggerSmokeGreen(position)
    trigger.action.smoke(position , trigger.smokeColor.Green)
end;

function JTAC.SCAN.searchTargets(pPoint, pRadius, pType)
    local foundUnits = {}
    local volS = {
        id = world.VolumeType.SPHERE,
        params = {
            point = pPoint,
            radius = pRadius
        }
    }
    local ifFound = function(foundItem, val)
        local playerCoalition = coalition.side.BLUE
        if coalition.getPlayers(coalition.side.RED)[1] ~= nil then
            playerCoalition = coalition.side.RED
        elseif coalition.getPlayers(coalition.side.BLUE)[1] ~= nil then
            playerCoalition = coalition.side.BLUE
        end

        -- Only ground units
        local desc = foundItem:getDesc()
        local isGround = desc and desc.category == Unit.Category.GROUND_UNIT

        if isGround
           and not foundItem:inAir()
           and foundItem:getCoalition() ~= playerCoalition
           and foundItem:getCoalition() ~= coalition.side.NEUTRAL
           and foundItem:getLife() > 0 then
            foundUnits[#foundUnits + 1] = foundItem
        end
        return true
    end

    world.searchObjects(pType, volS, ifFound)  -- pType = Object.Category.UNIT

    -- priority sort unchanged...
    if JTAC.targetPriority ~= "None" then
        table.sort(foundUnits, function(a, b)
            local catA = JTAC.categorizeTarget(a)
            local catB = JTAC.categorizeTarget(b)
            if catA == JTAC.targetPriority and catB ~= JTAC.targetPriority then
                return true
            elseif catA ~= JTAC.targetPriority and catB == JTAC.targetPriority then
                return false
            else
                return a:getName() < b:getName()
            end
        end)
    end

    return foundUnits
end

function JTAC.TARGETMENU.menuForPlayer(jtacname, markerPos, mission)
    -- Find targets (only units; ground filter is inside searchTargets)
    local FoundUnits = JTAC.SCAN.searchTargets(
        markerPos,
        JTAC.searchRadius,
        Object.Category.UNIT
    )

    -- Remove previous menu if it exists
    if mission.menuHandles.L1 then
        missionCommands.removeItemForGroup(mission.playerGroupID, mission.menuHandles.L1)
        mission.menuHandles.L1 = nil
    end

    -- No targets
    if not FoundUnits or #FoundUnits == 0 then
        JTAC.MESSAGES.setMsg(mission.airCallsign .. ": No Target found in the zone, Lase the mark?", 30, 8, true, mission.playerGroupID)
        return false
    end

    -- Create the base submenu
    mission.menuHandles.L1 = missionCommands.addSubMenuForGroup(mission.playerGroupID, "Target List", mission.menuHandles.J1)

    local function addTargetsMenu(units, parentMenu)
        local count = 0
        local subMenu = parentMenu
        for i, targetUnit in ipairs(units) do
            local GroupPosition = targetUnit:getPoint()
            local TYP = targetUnit:getTypeName()
            local TGT = targetUnit:getName()
            local CAT = targetUnit:getCategory()
            local OBJCAT = Object.getCategory(targetUnit)
            if JTAC.isExcludedTarget(TYP) and not JTAC.isExcludedTargetName(TGT) then
                if count > 0 and count % 9 == 0 then
                    subMenu = missionCommands.addSubMenuForGroup(mission.playerGroupID, "More", subMenu)
                end
                count = count + 1
                local vars = {
                    jtac = jtacname,
                    GroupPosition = GroupPosition,
                    Type = TYP,
                    TGT = TGT,
                    currentLasedTarget = TGT,
                    Cat = CAT,
                    Objcat = OBJCAT
                }
                local tgtMenu = missionCommands.addSubMenuForGroup(mission.playerGroupID, TYP .. ":" .. TGT, subMenu)
                missionCommands.addCommandForGroup(mission.playerGroupID, 'Lase the target', tgtMenu,
                    function() JTAC.LASER.createLaserOnMarkForPlayer(mission, vars) end)
                missionCommands.addCommandForGroup(mission.playerGroupID, 'IR the target', tgtMenu,
                    function() JTAC.IR.createInfraRedOnMarkForPlayer(mission, vars) end)
                missionCommands.addCommandForGroup(mission.playerGroupID, 'Smoke the target', tgtMenu,
                    function() JTAC.SMOKE.smokeOnMarkForPlayer(mission, vars.GroupPosition) end)
            end
        end
    end

    addTargetsMenu(FoundUnits, mission.menuHandles.L1)
end

-- Legacy function for backward compatibility
function JTAC.TARGETMENU.menu(jtacname, markerPos, gpID)
    -- Find the mission associated with this group ID
    for playerName, mission in pairs(JTAC.ActiveMissions) do
        if mission.playerGroupID == gpID then
            JTAC.TARGETMENU.menuForPlayer(jtacname, markerPos, mission)
            return
        end
    end
end

-- =====================================================================================
-- PLAYER-SPECIFIC MODULE PLACEHOLDERS
-- =====================================================================================

-- LASER module player-specific functions
JTAC.LASER.createLaserOnMarkForPlayer = function(mission, vars)
    -- Check if laser code exists
    if not mission.target.laserCode then
        JTAC.MESSAGES.setMsg("ERROR: No laser code assigned. Request JTAC assignment first.", 10, 2, true, mission.playerGroupID)
        return
    end
    
    if vars.Type == nil then
		vars.Type = "Ground "
	end
	JTAC.MESSAGES.setMsg(mission.player .." : Requesting target: " .. vars.Type .. ":" .. vars.TGT .. " painted with Laser code: ".. mission.target.laserCode ..", sending coordinates... ", 7, 1, true, mission.playerGroupID)
    
    -- Clear any existing laser
	if mission.target.laserSpot ~= nil then
		mission.target.laserSpot:destroy()
		mission.target.laserSpot = nil
	end
	
	-- Stop any existing laser tracking  
	mission.target.currentLasedTarget = "STOP"
	mission.target.lastLasedPosition = nil
	
	-- Set the target before creating laser
	mission.target.currentLasedTarget = vars.currentLasedTarget
	mission.target.lastLasedPosition = nil  -- Reset position tracking
	
	debugMsg("Creating laser at position: " .. vars.GroupPosition.x .. ", " .. vars.GroupPosition.z .. " with code: " .. mission.target.laserCode)
	
	JTAC.MESSAGES.setMsg(mission.airCallsign .. ": Roger, painting the " ..vars.Type.. vars.TGT.. ".... Sparkle on, sparkle on, go hot .... code: " .. mission.target.laserCode, 30, 8, true, mission.playerGroupID)
	
	if coalition.getPlayers(coalition.side.RED)[1] ~= nil then
		mission.target.laserSpot = Spot.createLaser(vars.jtac, nil, vars.GroupPosition, tonumber(mission.target.laserCode))
		debugMsg("Created RED laser spot")
	elseif coalition.getPlayers(coalition.side.BLUE)[1] ~= nil then
		mission.target.laserSpot = Spot.createLaser(vars.jtac, nil, vars.GroupPosition, tonumber(mission.target.laserCode))
		debugMsg("Created BLUE laser spot")
	else
		debugMsg("ERROR: No coalition players found")
	end
	
	if mission.target.laserSpot then
		debugMsg("Laser spot created successfully")
	else
		debugMsg("ERROR: Failed to create laser spot")
	end
    
    -- Only start tracking if target is not STOP and not a static mark
    if mission.target.currentLasedTarget ~= "STOP" and vars.TGT ~= "Mark" then
        debugMsg("Starting laser tracking for target: " .. mission.target.currentLasedTarget .. " for player: " .. mission.player)
        timer.scheduleFunction(JTAC.targetLaserUpdatePosForPlayer, {mission = mission}, timer.getTime() + 2)
    else
        debugMsg("Static laser position for: " .. vars.TGT .. " for player: " .. mission.player)
    end
end

JTAC.LASER.stopLaserForPlayer = function(mission)
	mission.target.currentLasedTarget = "STOP"
	mission.target.lastLasedPosition = nil  -- Clear position tracking
	JTAC.MESSAGES.setMsg(mission.player .." : Terminate lasing.", 5, 1, true, mission.playerGroupID)
	if mission.target.laserSpot ~= nil then
		mission.target.laserSpot:destroy()
		mission.target.laserSpot = nil
		JTAC.MESSAGES.setMsg("Wilco. Laser terminated.", 10, 8, true, mission.playerGroupID)
	else
		JTAC.MESSAGES.setMsg("Negative. Currently not lasing a target", 10, 8, true, mission.playerGroupID)
	end
	debugMsg("Laser stopped for player: " .. mission.player)
end

-- IR module player-specific functions
JTAC.IR.createInfraRedOnMarkForPlayer = function(mission, vars)
    if vars.Type == nil then
		vars.Type = "Ground "
	end
	JTAC.MESSAGES.setMsg(mission.player .." : Requesting target: " .. vars.Type .. ":" .. vars.TGT .. " painted with IR laser, sending coordinates... ", 7, 1, true, mission.playerGroupID)
    
    -- Clear any existing IR
	if mission.target.irSpot ~= nil then
		mission.target.irSpot:destroy()
		mission.target.irSpot = nil
	end
	
	-- Set the target before creating IR
	mission.target.currentLasedTarget = vars.currentLasedTarget
	mission.target.lastIRPosition = nil  -- Reset position tracking
	
	JTAC.MESSAGES.setMsg(mission.airCallsign .. ": Roger, painting your target now.... IR Laser is now on. " , 30, 8, true, mission.playerGroupID)
	
	if coalition.getPlayers(coalition.side.RED)[1] ~= nil then
		mission.target.irSpot = Spot.createInfraRed(vars.jtac, nil, vars.GroupPosition)       
	elseif coalition.getPlayers(coalition.side.BLUE)[1] ~= nil then
		mission.target.irSpot = Spot.createInfraRed(vars.jtac, nil, vars.GroupPosition)
	end
	
	local lat, long, alt = coord.LOtoLL(vars.GroupPosition)
	local coordSTR = JTAC.getCoordinatesSTR(lat, long, alt)
	local MGRS = coord.LLtoMGRS(coord.LOtoLL(vars.GroupPosition))
    JTAC.MESSAGES.setMsg("MGRS: " .. MGRS.UTMZone .. ' ' .. MGRS.MGRSDigraph .. ' ' .. MGRS.Easting .. ' ' .. MGRS.Northing, 60, 12, false, mission.playerGroupID)
    
    -- Only start tracking if target is not STOP and not a static mark
    if mission.target.currentLasedTarget ~= "STOP" and vars.TGT ~= "Mark" then
        debugMsg("Starting IR tracking for target: " .. mission.target.currentLasedTarget .. " for player: " .. mission.player)
        timer.scheduleFunction(JTAC.targetIRUpdatePosForPlayer, {mission = mission}, timer.getTime() + 2)
    else
        debugMsg("Static IR position for: " .. vars.TGT .. " for player: " .. mission.player)
    end
end

JTAC.IR.stopIRForPlayer = function(mission)
	mission.target.currentLasedTarget = "STOP"
	mission.target.lastIRPosition = nil  -- Clear position tracking
	JTAC.MESSAGES.setMessageDelayed("PLAYER: Terminate IR lasing.", 5, 1, true)
	if mission.target.irSpot ~= nil then
		mission.target.irSpot:destroy()
		mission.target.irSpot = nil
		JTAC.MESSAGES.setMessageDelayed("Wilco. IR laser terminated.", 10, 8, true)
	else
		JTAC.MESSAGES.setMessageDelayed(" Negative. Currently not IR lasing a target", 10, 8, true)
	end
	debugMsg("IR stopped for player: " .. mission.player)
end

-- SMOKE module player-specific functions
JTAC.SMOKE.smokeOnMarkForPlayer = function(mission, pos)
    timer.scheduleFunction(JTAC.SMOKE.triggerSmokeRed, pos, timer.getTime() + 15)
    JTAC.MESSAGES.setMsg(mission.player .. " : Requesting smoke on target.", 7, 1, true, mission.playerGroupID)
	JTAC.MESSAGES.setMsg("Roger, painting your target now with red smoke. ETA 15s " , 30, 8, true, mission.playerGroupID)
end

JTAC.SMOKE.smokeOnJtacForPlayer = function(mission, groupName)
    if Group.getByName(groupName) and Group.getByName(groupName):getUnit(1) then
        local pos = Group.getByName(groupName):getUnit(1):getPosition().p
        timer.scheduleFunction(JTAC.SMOKE.triggerSmokeGreen, pos, timer.getTime() + 15)
        JTAC.MESSAGES.setMsg(mission.player .. " : Requesting smoke on JTAC position.", 7, 1, true, mission.playerGroupID)
        JTAC.MESSAGES.setMsg(" Roger, Green smoke on Jtac position. ETA 15s " , 30, 8, true, mission.playerGroupID)
    else
        JTAC.MESSAGES.setMsg("Error: Cannot find JTAC unit for smoke marking", 10, 2, true, mission.playerGroupID)
    end
end

-- BILLUM module player-specific functions  
JTAC.BILLUM.illuminationBombOnMarkForPlayer = function(mission, pos)
    timer.scheduleFunction(JTAC.BILLUM.illuminationBombOnMarkDelay, pos, timer.getTime() + 15)
    JTAC.MESSAGES.setMsg(mission.player .. " : Requesting current target illumination. ", 7, 1, true, mission.playerGroupID)
	JTAC.MESSAGES.setMsg(" Roger, painting your target now.... Illumination Bomb on its way. " , 30, 8, true, mission.playerGroupID)
end

-- =====================================================================================
-- MESSAGING FUNCTIONS
-- =====================================================================================

function JTAC.MESSAGES.setMessageDelayed(text, duration, delaySec, clear)
	-- Set default values for nil parameters
	if text == nil then
        text = "Missing message text"
    end
    
    if duration == nil then
        duration = 10
    end
    
    if delaySec == nil then
        delaySec = 0.1 -- Use a small default delay to ensure timer works properly
    end
    
    if clear == nil or clear == false then
        clear = false
	else
		clear = true
    end
	timer.scheduleFunction(JTAC.MESSAGES.showMessage, {ptext = text, pduration = duration, pclear = clear}, timer.getTime() + delaySec)
end

function JTAC.MESSAGES.showMessage(parameters)
	trigger.action.outText(parameters.ptext, parameters.pduration, parameters.pclear)
end

function JTAC.MESSAGES.showMessageForGroup(parameters)
	trigger.action.outTextForGroup(parameters.groupID, parameters.ptext, parameters.pduration, parameters.pclear)
end

function JTAC.MESSAGES.getPlayerGroupIDByName(playerName)
    if not playerName then
        return nil
    end
    
    local coalitions = {coalition.side.BLUE, coalition.side.RED, coalition.side.NEUTRAL}
    local categories = {Group.Category.AIRPLANE, Group.Category.GROUND, Group.Category.SHIP, Group.Category.HELICOPTER}
    
    for _, side in pairs(coalitions) do
        for _, category in pairs(categories) do
            local groups = coalition.getGroups(side, category)
            if groups then
                for _, group in pairs(groups) do
                    if group and group:isExist() then
                        local units = group:getUnits()
                        if units then
                            for _, unit in pairs(units) do
                                if unit and unit:isExist() then
                                    local unitPlayerName = unit:getPlayerName()
                                    if unitPlayerName == playerName then
                                        return group:getID()
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return nil
end

--- Enhanced message function that can target specific players or broadcast to all.
function JTAC.MESSAGES.setMsg(text, duration, delaySec, clear, groupID, playerName)
    
    -- If groupID is not provided, try to determine target
    if not groupID then
        if playerName then
            -- Try to find specific player's group
            groupID = getPlayerGroupIDByName(playerName)
        end
        
        -- If still no specific target, send to all players
        if not groupID then
            debugMsg("No specific player target, sending message to all players: " .. text)
            trigger.action.outText(text, duration or 10)
            return
        end
    end
    
	if clear == nil or clear == false then
        clear = false
	else
		clear = true
    end
    
    -- Use minimum delay of 0.1 seconds instead of 0 for timer reliability
    local actualDelay = math.max(delaySec or 0, 0.1)
	timer.scheduleFunction(JTAC.MESSAGES.showMessageForGroup, {groupID = groupID, ptext = text, pduration = duration or 10, pclear = clear}, timer.getTime() + actualDelay)
end

--- Broadcasts a message to all players in the mission.
function JTAC.MESSAGES.setMsgToAll(text, duration, delaySec, clear)
    if clear == nil or clear == false then
        clear = false
    else
        clear = true
    end
    
    local actualDelay = math.max(delaySec or 0, 0.1)
    timer.scheduleFunction(function()
        trigger.action.outText(text, duration or 10)
    end, nil, timer.getTime() + actualDelay)
end

-- =====================================================================================
-- UTILITY FUNCTIONS
-- =====================================================================================

function JTAC.NewMarkerScanForPlayer(mission)

    mission.target.currentLasedTarget = "STOP"
    if mission.target.irSpot ~= nil then
        mission.target.irSpot:destroy()
        mission.target.irSpot = nil
    end
    if mission.target.laserSpot ~= nil then
        mission.target.laserSpot:destroy()
        mission.target.laserSpot = nil
    end

    if mission.menuHandles.L1 ~= nil then
        missionCommands.removeItemForGroup(mission.playerGroupID, mission.menuHandles.L1)
        mission.menuHandles.L1 = missionCommands.addSubMenuForGroup(mission.playerGroupID, "Target List", mission.menuHandles.J1)
    end
    
    local source = nil
    if mission.target.droneName ~= "" and Group.getByName(mission.target.droneName) then
        source = Group.getByName(mission.target.droneName):getUnit(1)
    elseif mission.target.groundName ~= "" and Group.getByName(mission.target.groundName) then
        source = Group.getByName(mission.target.groundName):getUnit(1)
    end
    
    if source then
        JTAC.TARGETMENU.menuForPlayer(source, mission.target.scanPos, mission)
        debugMsg("Rescanning zone for player: " .. mission.player)
    end
end

function JTAC.setMenuForPlayer(mission)
    
    debugMsg("Setting menu for player: " .. (mission.player or "unknown") .. " - LaserCode: " .. (mission.target.laserCode or "none") .. ", AwaitingMarker: " .. tostring(mission.awaitingMarker or false) .. ", DroneName: " .. (mission.target.droneName or "none") .. ", GroundName: " .. (mission.target.groundName or "none"))
    
    if mission.menuHandles.menuPrinc then
        missionCommands.removeItemForGroup(mission.playerGroupID, mission.menuHandles.menuPrinc)
    end

    local gpID = mission.playerGroupID
    
    mission.menuHandles.menuPrinc = missionCommands.addSubMenuForGroup(gpID, 'JTAC Commms')
    mission.menuHandles.J1 = missionCommands.addSubMenuForGroup(gpID, 'Contact JTAC', mission.menuHandles.menuPrinc)
    
    -- Show different menu options based on mission state
    if not mission.target.laserCode then
        -- No JTAC assigned yet - show request option
        mission.menuHandles.JR1 = missionCommands.addCommandForGroup(gpID, 'Request JTAC map code', mission.menuHandles.J1, 
            function() JTAC.requestJTACAssignment(mission) end)
    elseif mission.awaitingMarker then
        -- JTAC assigned but waiting for marker - show reminder and cancel option
        mission.menuHandles.JR2 = missionCommands.addCommandForGroup(gpID, 'Reminder: Place marker (' .. (mission.jtacCallSign or "Unknown") .. ')', mission.menuHandles.J1, 
            function() 
                JTAC.MESSAGES.setMsg("Place map marker with text: " .. (mission.jtacCallSign or "Unknown"), 10, 2, true, mission.playerGroupID)
                JTAC.MESSAGES.setMsg("Your laser code: " .. mission.target.laserCode, 8, 2, false, mission.playerGroupID)
            end)
        mission.menuHandles.JC1 = missionCommands.addCommandForGroup(gpID, 'Cancel JTAC Request', mission.menuHandles.J1, 
            function() JTAC.cancelJTACRequest(mission) end)
    elseif mission.target.droneName ~= "" or mission.target.groundName ~= "" then
        -- JTAC units are active - show control options
        local jtacname = mission.target.droneName ~= "" and mission.target.droneName or mission.target.groundName
        local unitType = mission.target.droneName ~= "" and "DRONE" or "GROUND"
        
        mission.menuHandles.JD13 = missionCommands.addCommandForGroup(gpID, 'Lase my mark', mission.menuHandles.J1, 
            function() JTAC.LASER.createLaserOnMarkForPlayer(mission, {jtac = jtacname, GroupPosition = mission.target.laserPos, TGT = "Mark", currentLasedTarget = "STOP"}) end)
        
        mission.menuHandles.JD23 = missionCommands.addCommandForGroup(gpID, 'IR my mark', mission.menuHandles.J1, 
            function() JTAC.IR.createInfraRedOnMarkForPlayer(mission, {jtac = jtacname, GroupPosition = mission.target.irPos, TGT = "Mark", currentLasedTarget = "STOP"}) end)
        
        mission.menuHandles.JD14 = missionCommands.addCommandForGroup(gpID, 'Terminate lasing', mission.menuHandles.J1, 
            function() JTAC.LASER.stopLaserForPlayer(mission) end)
        
        mission.menuHandles.JD24 = missionCommands.addCommandForGroup(gpID, 'Terminate IR lasing', mission.menuHandles.J1, 
            function() JTAC.IR.stopIRForPlayer(mission) end)
        
        mission.menuHandles.N31 = missionCommands.addCommandForGroup(gpID, 'Illumination Bomb', mission.menuHandles.J1, 
            function() JTAC.BILLUM.illuminationBombOnMarkForPlayer(mission, mission.target.irPos) end)
        
        mission.menuHandles.N32 = missionCommands.addCommandForGroup(gpID, 'Smoke my mark', mission.menuHandles.J1, 
            function() JTAC.SMOKE.smokeOnMarkForPlayer(mission, mission.target.irPos) end)
        
        mission.menuHandles.JD98 = missionCommands.addCommandForGroup(gpID, 'ReScan', mission.menuHandles.J1, 
            function() JTAC.NewMarkerScanForPlayer(mission) end)
    else
        -- JTAC assigned and marker placed but no active units - show request options
        mission.menuHandles.JD11 = missionCommands.addCommandForGroup(gpID, 'Request Drone JTAC [20 CMD]', mission.menuHandles.J1, 
            function() JTAC.requestDroneForPlayer(mission) end)
        
        mission.menuHandles.JG11 = missionCommands.addCommandForGroup(gpID, 'Request Ground JTAC [10 CMD]', mission.menuHandles.J1,
            function() JTAC.requestGroundForPlayer(mission) end)
    end
    
    -- Only show OPTIONS and DISMISS PACKAGE when JTAC is assigned (has laser code)
    if mission.target.laserCode then
        mission.menuHandles.O2 = missionCommands.addSubMenuForGroup(gpID, 'OPTIONS', mission.menuHandles.menuPrinc)

        -- Target Priority submenu
        mission.menuHandles.TP = missionCommands.addSubMenuForGroup(gpID, 'Target Priority', mission.menuHandles.O2)
        
        missionCommands.addCommandForGroup(gpID, 'Priority: Air Defence', mission.menuHandles.TP, 
            function() JTAC.setTargetPriorityForPlayer(mission, "Air Defence") end)
        
        missionCommands.addCommandForGroup(gpID, 'Priority: Armour', mission.menuHandles.TP, 
            function() JTAC.setTargetPriorityForPlayer(mission, "Armour") end)
        
        missionCommands.addCommandForGroup(gpID, 'Priority: Artillery', mission.menuHandles.TP, 
            function() JTAC.setTargetPriorityForPlayer(mission, "Artillery") end)
        
        missionCommands.addCommandForGroup(gpID, 'Priority: Infantry', mission.menuHandles.TP, 
            function() JTAC.setTargetPriorityForPlayer(mission, "Infantry") end)
        
        missionCommands.addCommandForGroup(gpID, 'Priority: None (Default)', mission.menuHandles.TP, 
            function() JTAC.setTargetPriorityForPlayer(mission, "None") end)
        
        -- Only show DISMISS PACKAGE when there are active units to dismiss
        if (mission.target.droneName ~= "" and mission.target.droneInZone) or (mission.target.groundName ~= "" and mission.target.droneInZone) then
            mission.menuHandles.N9 = missionCommands.addSubMenuForGroup(gpID, 'DISMISS PACKAGE', mission.menuHandles.menuPrinc)
            
            -- Add specific dismiss commands based on what units are active
            if mission.target.droneName ~= "" then
                mission.menuHandles.JD99 = missionCommands.addCommandForGroup(gpID, 'Dismiss DRONE package', mission.menuHandles.N9,
                    function() JTAC.requestDismissPackageForPlayer(mission, "DRONE") end)
            end
            
            if mission.target.groundName ~= "" then
                mission.menuHandles.JG99 = missionCommands.addCommandForGroup(gpID, 'Dismiss GROUND package', mission.menuHandles.N9,
                    function() JTAC.requestDismissPackageForPlayer(mission, "GROUND") end)
            end
        end
    end
    
    local statusMsg = "Menu created for player: " .. mission.player
    if mission.target.laserCode then
        statusMsg = statusMsg .. " (Laser Code: " .. mission.target.laserCode .. ")"
    end
    if mission.jtacCallSign then
        statusMsg = statusMsg .. " (Call Sign: " .. mission.jtacCallSign .. ")"
    end
    -- Debug: Log menu state
    debugMsg(statusMsg .. " | DroneInZone: " .. tostring(mission.target.droneInZone) .. " | DroneName: '" .. mission.target.droneName .. "' | GroundName: '" .. mission.target.groundName .. "'")
end

function JTAC.removeMenuForPlayer(mission)
    if mission.menuHandles.menuPrinc then
        missionCommands.removeItemForGroup(mission.playerGroupID, mission.menuHandles.menuPrinc)
    end
end

-- =====================================================================================
-- MULTI-PLAYER UTILITY FUNCTIONS  
-- =====================================================================================

-- Get active missions status for debugging/monitoring
function JTAC.getActiveMissionsStatus()
    local statusLines = {}
    statusLines[#statusLines + 1] = "=== ACTIVE JTAC MISSIONS ==="
    
    local count = 0
    for playerName, mission in pairs(JTAC.ActiveMissions) do
        count = count + 1
        local status = mission.support and "Available" or "In Service"
        if mission.awaitingMarker then
            status = "Awaiting Marker"
        elseif not mission.target.laserCode then
            status = "No Assignment"
        end
        
        local assetType = ""
        if mission.target.droneName ~= "" then
            assetType = "Drone: " .. mission.target.droneName
        elseif mission.target.groundName ~= "" then
            assetType = "Ground: " .. mission.target.groundName
        else
            assetType = "No Asset"
        end
        
        statusLines[#statusLines + 1] = string.format("Player: %s | Status: %s | Code: %s | Call Sign: %s | %s", 
            playerName, status, mission.target.laserCode or "None", mission.jtacCallSign or "None", assetType)
    end
    
    if count == 0 then
        statusLines[#statusLines + 1] = "No active missions"
    end
    
    statusLines[#statusLines + 1] = string.format("Total missions: %d | Used laser codes: %d", 
        count, JTAC.getUsedLaserCodeCount())
    
    return table.concat(statusLines, "\n")
end

-- Get count of used laser codes
function JTAC.getUsedLaserCodeCount()
    local count = 0
    for code, inUse in pairs(JTAC.UsedLaserCodes) do
        if inUse then
            count = count + 1
        end
    end
    return count
end

-- Check if laser code is available
function JTAC.isLaserCodeAvailable(code)
    return not JTAC.UsedLaserCodes[code]
end

-- Get list of all used laser codes
function JTAC.getUsedLaserCodes()
    local codes = {}
    for code, inUse in pairs(JTAC.UsedLaserCodes) do
        if inUse then
            codes[#codes + 1] = code
        end
    end
    table.sort(codes)
    return codes
end

-- Find mission by player name
function JTAC.getMissionByPlayer(playerName)
    return JTAC.ActiveMissions[playerName]
end

-- Find mission by group ID
function JTAC.getMissionByGroupID(groupID)
    for playerName, mission in pairs(JTAC.ActiveMissions) do
        if mission.playerGroupID == groupID then
            return mission
        end
    end
    return nil
end

-- Debug command to show mission status (can be called from F10 menu if needed)
function JTAC.showMissionStatus()
    local status = JTAC.getActiveMissionsStatus()
    debugMsg(status)
    return status
end

-- =====================================================================================
-- COMMAND POINT FUNCTIONS
-- =====================================================================================

function JTAC.spendCMDPoints(playerName, cost)
    if PlayerTrackerInstance then
        local success = PlayerTrackerInstance:deductCommandTokens(playerName, cost)
        if success then
            debugMsg("Player " .. playerName .. " spent " .. cost .. " command tokens. Remaining: " .. PlayerTrackerInstance:getCommandTokens(playerName))
            return true
        else
            debugMsg("Player " .. playerName .. " does not have enough command tokens.")
            return false
        end
    else
        -- PlayerTrackerInstance doesn't exist, allow operation without cost
        debugMsg("PlayerTracker not available - allowing operation without command token cost")
        return true
    end
end

-- =====================================================================================
-- SCRIPT INITIALIZATION
-- =====================================================================================

-- Initialize the script
local function initialize()
    debugMsg("========================================")
    debugMsg("JTAC Script v0.2 Initializing...")
    debugMsg("========================================")

    world.addEventHandler(EVENTJTAC);
    timer.scheduleFunction(JTAC.setAvailability, nil, timer.getTime() + 1)
    
    -- Schedule periodic cleanup of disconnected players (every 5 minutes)
    timer.scheduleFunction(function()
        JTAC.cleanupDisconnectedPlayers()
        return timer.getTime() + 300  -- Repeat every 300 seconds (5 minutes)
    end, nil, timer.getTime() + 300)
    
    debugMsg("JTAC LOADED!")
end

-- Start initialization
initialize()