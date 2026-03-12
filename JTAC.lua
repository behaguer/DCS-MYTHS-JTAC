JTAC = {};

local eventJtac = {};

-- =====================================================================================
-- CONFIG (Editable Section)
-- =====================================================================================

JTAC = {

    debug = true,             -- enable debug messages in DCS log and on screen

    -- Options
    groupPrefix = false,        -- restrict F10 menu to group with specific prefix
    Prefix = "Only",           -- choose group prefix
    searchRadius = 5000,       -- define radius for scanning zone (meters)
    dfaultLaserCode = "1688",  -- Default laser code
    targetPriority = "None",   -- Target priority: "Air Defence", "Armour", "Artillery", "Infantry", "None"

    -- System state
    model = nil,
    support = true,
    groupAuth = false,
    player = nil,
    playerGroupID = nil,
    playerGroupName = nil,
    playerUnitName = nil,
    playerUnit = nil,
    playerPos = nil,

    -- Target management
    target = {
        availability = 100,         -- chance of lase support available in the mission. 0 = no available at all; 1 - 99 = % chances availability; 100% = always available
        waitTime = 30,              -- time in seconds between request a lase support and the lase support became available to use
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

    -- List all unit you want to exclude from scanning you need to found the Type of the unit (e.g. "Barrier B" which is ["shape_name"] = "M92_BarrierB",["type"] = "Barrier B",
    -- sometime the type in mission editor is not real type like in ME : ORCA type is: Orca Whale but in mission (file inside the miz file) type - Orca
    -- you can also found the type in the traget list it ithe first name you see "target type: target name" in the list

    -- Target filtering
    exclude_Targets = {
        {typeName = "Barrier B"}
    },

    exclude_TargetNames = {
        "Static",   -- excludes "Static_AAA", "Static_123", etc
        "Hidden_"
    },

    IR = {},
    LASER = {},
    BILLUM = {},
    SMOKE = {},
    MESSAGES = {},
    SCAN = {},
    TARGETMENU = { menuHandles = {}};

};

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
-- FUNCTIONS INITIALIZATION
-- =====================================================================================

function eventJtac:onEvent(event)

    if (world.event.S_EVENT_BIRTH == event.id) and event.initiator and event.initiator:getPlayerName() then
		JTAC.player = event.initiator:getPlayerName()               -- player name
		JTAC.model = event.initiator:getTypeName()                  -- aircraft model
        JTAC.playerGroupID = event.initiator:getGroup():getID()              -- group ID 
        JTAC.playerGroupName = event.initiator:getGroup():getName()       -- group Name
        JTAC.playerUnitName = event.initiator:getName()             -- Pilote Name in DCS
        JTAC.playerUnit = event.initiator                           -- Unit table
        JTAC.playerPos = event.initiator:getPoint()            -- Unit position

		theatre = env.mission.theatre
																	   
        if JTAC.groupPrefix == true and string.sub(JTAC.playerGroupName,1,4) == JTAC.Prefix  then
            JTAC.setMenu(JTAC.playerGroupID)
            JTAC.groupAuth = true
        elseif JTAC.groupPrefix == false then
            JTAC.setMenu(JTAC.playerGroupID)
            JTAC.groupAuth = true
        end    
	end

    if (world.event.S_EVENT_PLAYER_LEAVE_UNIT == event.id) and event.initiator and event.initiator:getPlayerName() then
        if JTAC.support == false then
            if JTAC.target.droneName ~= "" then
                JTAC.dismissPackage("DRONE")
            elseif JTAC.target.groundName ~= "" then
                JTAC.dismissPackage("GROUND")
            end
        end
	end

    if (world.event.S_EVENT_PILOT_DEAD == event.id) and event.initiator and event.initiator:getPlayerName() then
        if JTAC.support == false then
            if JTAC.target.droneName ~= "" then
                JTAC.dismissPackage("DRONE")
            elseif JTAC.target.groundName ~= "" then
                JTAC.dismissPackage("GROUND")
            end
        end
	end

    if (world.event.S_EVENT_EJECTION == event.id) and event.initiator and event.initiator:getPlayerName() then
        if JTAC.support == false then
            if JTAC.target.droneName ~= "" then
                JTAC.dismissPackage("DRONE")
            elseif JTAC.target.groundName ~= "" then
                JTAC.dismissPackage("GROUND")
            end
        end
	end


	if (world.event.S_EVENT_MARK_CHANGE == event.id) then
        JTAC.markerIDx = event.idx
       -- trigger.action.outText(" ID Marker : " .. JTAC.markerIDx , 10, false)
		if (string.match(event.text, "jtac:") ~= nil) then
			if coalition.getPlayers(coalition.side.RED)[1] ~= nil or coalition.getPlayers(coalition.side.BLUE)[1] ~= nil then
				if JTAC.target.laserSpot ~= nil then
					JTAC.target.laserSpot:destroy()
					JTAC.target.laserSpot = nil;
				end

                if JTAC.target.irSpot ~= nil then
					JTAC.target.irSpot:destroy()
					JTAC.target.irSpot = nil;
				end
				local index1 = string.find(event.text, ";", 0)
				JTAC.target.laserCode = JTAC.trim(string.sub(event.text, index1 + 1, string.len(event.text)))
				JTAC.target.laserPos = event.pos
                JTAC.target.irPos = event.pos
                JTAC.target.scanPos = event.pos
				if JTAC.target.laserPos ~= nil and JTAC.target.laserCode ~= nil and JTAC.target.laserCode ~= "" and JTAC.isInteger(JTAC.target.laserCode) then
					debugMsg("You can request drone to IR mark or lase targets now. Code: " .. JTAC.target.laserCode)
				else
					debugMsg("Target for laser not created. Wrong mark format.")
				end
			else
				debugMsg("There is no player in the mission. Can't request support")
			end
		elseif (string.match(event.text, "spot") ~= nil) and (string.match(event.text, "SPOT;") == nil) then
			if coalition.getPlayers(coalition.side.RED)[1] ~= nil or coalition.getPlayers(coalition.side.BLUE)[1] ~= nil then
				if JTAC.target.laserSpot ~= nil then
					JTAC.target.laserSpot:destroy()
					JTAC.target.laserSpot = nil;
				end
                if JTAC.target.irSpot ~= nil then
					JTAC.target.irSpot:destroy()
					JTAC.target.irSpot = nil;
				end
				JTAC.target.laserCode = JTAC.dfaultLaserCode
				JTAC.target.laserPos = event.pos
                JTAC.target.irPos = event.pos
                JTAC.target.scanPos = event.pos
                debugMsg("You can request drone to IR mark or lase targets now. Code: " .. JTAC.target.laserCode)
			else
				debugMsg("There is no player in the mission. Can't request support")
			end
		
		end
    end
end;

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

function JTAC.requestDismissPackage(groupType)
	JTAC.MESSAGES.setMessageDelayed(JTAC.player .." : You can RTB. Thank you for the support.", 10, 2, true)
	timer.scheduleFunction(JTAC.dismissPackage,  groupType, timer.getTime() + 30)
	if groupType == "DRONE" and Group.getByName(JTAC.target.droneName):getUnit(1) ~= nil then
		JTAC.MESSAGES.setMessageDelayed("UZI 1: Roger. RTB.", 10, 7, true)
	elseif groupType == "GROUND" and Group.getByName(JTAC.target.groundName):getUnit(1) ~= nil then
		JTAC.MESSAGES.setMessageDelayed("Axeman 1: Roger. RTB.", 10, 10, true)
	end
end

function JTAC.dismissPackage(groupType)
	JTAC.MESSAGES.setMessageDelayed("[INFO]: " .. groupType  .. " package has left the Zone.", 15, 2, true)

	if groupType == "DRONE" and Group.getByName(JTAC.target.droneName):getUnit(1) ~= nil then
		JTAC.destroyGroup(JTAC.target.droneName)
		JTAC.removeMenu(JTAC.playerGroupID)
		JTAC.setMenu(JTAC.playerGroupID)
		JTAC.target.laserPos = nil;
        JTAC.target.irPos = nil;
		JTAC.target.laserCode = nil;
		JTAC.target.laserSpot = nil;
        JTAC.target.irSpot = nil;
		JTAC.target.droneName = "";
		JTAC.target.droneInFlight = false;
		JTAC.target.droneInZone = false;
		JTAC.target.isLaseAvailable = false;
		JTAC.target.currentLasedTarget = "STOP";
        JTAC.support = true;
        JTAC.player =  nil;
        JTAC.model =  nil;
        JTAC.playerGroupID =  nil;
        JTAC.playerGroupName =  nil;
        JTAC.playerUnitName =  nil;
        JTAC.playerUnit =  nil;
        JTAC.playerPos =  nil;

	elseif groupType == "GROUND" and Group.getByName(JTAC.target.groundName):getUnit(1) ~= nil then
		JTAC.destroyGroup(JTAC.target.groundName)
		JTAC.removeMenu(JTAC.playerGroupID)
		JTAC.setMenu(JTAC.playerGroupID)
		JTAC.target.laserPos = nil;
        JTAC.target.irPos = nil;
		JTAC.target.laserCode = nil;
		JTAC.target.laserSpot = nil;
        JTAC.target.irSpot = nil;
		JTAC.target.groundName = "";
		JTAC.target.droneInFlight = false;
		JTAC.target.droneInZone = false;
		JTAC.target.isLaseAvailable = false;
		JTAC.target.currentLasedTarget = "STOP";
        JTAC.support = true;
        JTAC.player =  nil;
        JTAC.model =  nil;
        JTAC.playerGroupID =  nil;
        JTAC.playerGroupName =  nil;
        JTAC.playerUnitName =  nil;
        JTAC.playerUnit =  nil;
        JTAC.playerPos =  nil;
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

function JTAC.setAvailability()
	local randomLase = math.random() * 100
	if randomLase < JTAC.target.availability then
		JTAC.isLaseAvailable = true
	else
		JTAC.isLaseAvailable = false
	end

end;

function JTAC.MenuOptionOnOff(vars)
    local gpID = JTAC.playerGroupID


end;

function JTAC.setTargetPriority(priority)
    JTAC.targetPriority = priority
    debugMsg("Target Priority set to: " .. priority)
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

function JTAC.requestDrone()
    if  JTAC.support == true then

        if JTAC.target.laserPos ~= nil and JTAC.target.laserCode ~= nil then
            JTAC.MESSAGES.setMessageDelayed(JTAC.player.. " : Requesting drone for painting target near following coordinates: ", 7, 1, true)
            local lat, long, alt = coord.LOtoLL(JTAC.target.laserPos)
            local coordSTR = JTAC.getCoordinatesSTR(lat, long, alt)
            local MGRS = coord.LLtoMGRS(coord.LOtoLL(JTAC.target.laserPos))
            JTAC.MESSAGES.setMessageDelayed(coordSTR.lat .. " " .. coordSTR.long .. " " .. coordSTR.alt .. "m", 7, 1, false)
            if JTAC.isLaseAvailable == true then
                if (JTAC.target.droneInZone == false and JTAC.target.droneInFlight == false) then
                    timer.scheduleFunction(JTAC.createDroneDelayed, nil, timer.getTime() + JTAC.target.waitTime)
                    JTAC.MESSAGES.setMessageDelayed("COMMAND: Copied, sending Reaper drone to Zone", 10, 12, true)
                    JTAC.MESSAGES.setMessageDelayed("INFO: Total ETA for drone " .. JTAC.target.waitTime .." secs", 10, 12, false)
                    JTAC.MESSAGES.setMessageDelayed(coordSTR.lat .. " " .. coordSTR.long .. " " .. coordSTR.alt .. "m", 60, 12, false)
                    JTAC.MESSAGES.setMessageDelayed("     Grid: " .. MGRS.UTMZone .. ' ' .. MGRS.MGRSDigraph .. ' ' .. string.format("%05d", MGRS.Easting) .. ' ' .. string.format("%05d", MGRS.Northing), 60, 12, false)
                    JTAC.target.droneInFlight = true;
                elseif (JTAC.target.droneInZone == false and JTAC.target.droneInFlight == true) then
                    JTAC.MESSAGES.setMessageDelayed("COMMAND: Negative, MQ-9 Reaper is on its way yet.", 10, 12, true)
                end
            else
                JTAC.MESSAGES.setMessageDelayed("COMMAND: Negative, there is not support available.", 10, 12, true)
            end
        else
            debugMsg("INFO: You need to create a mark SPOT;XXXX for target in F10 map (where XXXX is the laser code)")

        end
    else
        debugMsg("Jtac unavalaible , Already in service")
            if JTAC.target.droneName ~= "" then
                debugMsg('Drone: Uzi 1 '..JTAC.target.droneName .. " unavalaible , Already in service")
                JTAC.JD99 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'Dismiss DRONE package', JTAC.N9, JTAC.requestDismissPackage, "DRONE")
            else
                return false
            end
        return false
    end
end;

function JTAC.createDroneDelayed()
    JTAC.target.droneName = "JtacDrone" .. math.random(9999,99999)
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
                                                                ["callname"] = 3,
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
                                            ["y"] = JTAC.target.laserPos.z + 1000, -- spawn coord JTAC.target.laserPos.z + 1000
                                            ["x"] = JTAC.target.laserPos.x + 1000, -- spawn coord JTAC.target.laserPos.x + 1000
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
                                            ["y"] = JTAC.target.laserPos.z, -- orbit spot coord JTAC.target.laserPos.z
                                            ["x"] = JTAC.target.laserPos.x, -- orbit spot coord JTAC.target.laserPos.x
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
                                        ["y"] = JTAC.target.laserPos.z + 1000, -- spawn coord JTAC.target.laserPos.z + 1000
                                        ["x"] = JTAC.target.laserPos.x + 1000,  -- spawn coord JTAC.target.laserPos.x + 1000,
                                        ["name"] = JTAC.target.droneName, --JTAC.target.droneName
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
                                            ["name"] = "Uzi 1",
                                            [3] = 1,
                                        }, -- end of ["callsign"]
                                    }, -- end of [1]
                                }, -- end of ["units"]
                                ["y"] = JTAC.target.laserPos.z + 1000, -- 0
                                ["x"] = JTAC.target.laserPos.x + 1000, -- 0
                                ["name"] = JTAC.target.droneName, -- JTAC.target.droneName
                                ["communication"] = true,
                                ["start_time"] = 0,
                                ["frequency"] = 251,
                        }

	coalition.addGroup(_country, Group.Category.AIRPLANE, _droneData)
    jtacname = Group.getByName(JTAC.target.droneName):getUnit(1)
    JTAC.TARGETMENU.menu(jtacname, JTAC.target.irPos, JTAC.playerGroupID)
	JTAC.MESSAGES.setMessageDelayed("UZI 1: Drone is in the Operation area. Ready to copy target. Over", 20, 2, true)
	missionCommands.removeItemForGroup(JTAC.playerGroupID, JTAC.JD11)
    missionCommands.removeItemForGroup(JTAC.playerGroupID, JTAC.JG11)
    
    JTAC.JD13 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'Lase my mark', JTAC.J1, JTAC.LASER.createLaserOnMark, {jtac = jtacname, GroupPosition = JTAC.target.laserPos, TGT = "Mark", currentLasedTarget = "STOP"})
    JTAC.JD23 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'IR my mark', JTAC.J1, JTAC.IR.createInfraRedOnMark, {jtac = jtacname, GroupPosition = JTAC.target.irPos, TGT = "Mark", currentLasedTarget = "STOP"})
    JTAC.JD14 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'Terminate lasing', JTAC.J1, JTAC.LASER.stopLaser, nil)
    JTAC.JD24 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'Terminate IR lasing', JTAC.J1, JTAC.IR.stopIR, nil)
    JTAC.N31 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'Illumination Bomb', JTAC.J1, JTAC.BILLUM.illuminationBombOnMark, JTAC.target.irPos)
    JTAC.N32 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'Smoke my mark', JTAC.J1, JTAC.SMOKE.smokeOnMark, JTAC.target.irPos)
    JTAC.JD98 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'ReScan', JTAC.J1, JTAC.NewMarkerScan, nil)
    JTAC.JD99 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'Dismiss DRONE package', JTAC.N9, JTAC.requestDismissPackage, "DRONE")
	JTAC.target.droneInZone = true
    JTAC.support = false

end;

function JTAC.requestGround()
    if  JTAC.support == true then

        if JTAC.target.laserPos ~= nil and JTAC.target.laserCode ~= nil then
            JTAC.MESSAGES.setMessageDelayed(JTAC.player .. " : Requesting Ground for painting target near following coordinates: ", 7, 1, true)
            local lat, long, alt = coord.LOtoLL(JTAC.target.laserPos)
            local coordSTR = JTAC.getCoordinatesSTR(lat, long, alt)
            local MGRS = coord.LLtoMGRS(coord.LOtoLL(JTAC.target.laserPos))
            JTAC.MESSAGES.setMessageDelayed(coordSTR.lat .. " " .. coordSTR.long .. " " .. coordSTR.alt .. "m", 7, 1, false)
            if JTAC.isLaseAvailable == true then
                if (JTAC.target.droneInZone == false and JTAC.target.droneInFlight == false) then
                    timer.scheduleFunction(JTAC.createGroundDelayed, nil, timer.getTime() + JTAC.target.waitTime)
                    JTAC.MESSAGES.setMessageDelayed("COMMAND: Copied, sending Ground to Zone.", 10, 12, true)
                    JTAC.MESSAGES.setMessageDelayed("INFO: Total ETA for Ground " .. JTAC.target.waitTime .." secs", 10, 12, false)
                    JTAC.MESSAGES.setMessageDelayed(coordSTR.lat .. " " .. coordSTR.long .. " " .. coordSTR.alt .. "m", 60, 12, false)
                    JTAC.MESSAGES.setMessageDelayed("     Grid: " .. MGRS.UTMZone .. ' ' .. MGRS.MGRSDigraph .. ' ' .. string.format("%05d", MGRS.Easting) .. ' ' .. string.format("%05d", MGRS.Northing), 60, 12, false)
                    JTAC.target.droneInFlight = true;
                elseif (JTAC.target.droneInZone == false and JTAC.target.droneInFlight == true) then
                    JTAC.MESSAGES.setMessageDelayed("COMMAND: Negative, Ground Units is on its way yet.", 10, 12, true)
                end
            else
                JTAC.MESSAGES.setMessageDelayed("COMMAND: Negative, there is not support available.", 10, 12, true)
            end
        else
            debugMsg("INFO: You need to create a mark SPOT;XXXX for target in F10 map (where XXXX is the laser code)")
        end
    else
        debugMsg("Jtac unavalaible , Already in service")
            if JTAC.target.groundName ~= "" then
                debugMsg('Ground: Axeman 1 '..JTAC.target.groundName .. " unavalaible , Already in service")
                JTAC.JD99 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'Dismiss GROUND package', JTAC.N9, JTAC.requestDismissPackage, "GROUND")
            else
                return false
            end
        return false
    end
end;

function JTAC.createGroundDelayed()
    JTAC.target.groundName = "JtacGround" .. math.random(9999,99999)
   -- jtacgroup = JTAC.target.groundName

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
                                                ["y"] = JTAC.target.laserPos.z + 1000,
                                                ["x"] = JTAC.target.laserPos.x + 1000,
                                            }, -- end of [1]
                                            [2] =
                                            {
                                                ["y"] = JTAC.target.laserPos.z + 300,
                                                ["x"] = JTAC.target.laserPos.x + 300,
                                            }, -- end of [2]
                                        }, -- end of [1]
                                        [2] =
                                        {
                                            [1] =
                                            {
                                                ["y"] = JTAC.target.laserPos.z + 300,
                                                ["x"] = JTAC.target.laserPos.x + 300,
                                            }, -- end of [1]
                                            [2] =
                                            {
                                                ["y"] = JTAC.target.laserPos.z + 300,
                                                ["x"] = JTAC.target.laserPos.x + 300,
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
                                            ["y"] = JTAC.target.laserPos.z + 1000,
                                            ["x"] = JTAC.target.laserPos.x + 1000,
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
                                            ["y"] = JTAC.target.laserPos.z + 300,
                                            ["x"] = JTAC.target.laserPos.x + 300,
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
                                        ["y"] = JTAC.target.laserPos.z + 1000,
                                        ["x"] = JTAC.target.laserPos.x + 1000,
                                        ["name"] = "Axeman 1",
                                        ["heading"] = 0,
                                        ["playerCanDrive"] = true,
                                    }, -- end of [1]
                                }, -- end of ["units"]
                                ["y"] = JTAC.target.laserPos.z + 1000,
                                ["x"] = JTAC.target.laserPos.x + 1000,
                                ["name"] = JTAC.target.groundName,
                                ["start_time"] = 0,
                        }

	coalition.addGroup(_country, Group.Category.GROUND, _GroundData)

    jtacname = Group.getByName(JTAC.target.groundName):getUnit(1)

    JTAC.TARGETMENU.menu(jtacname, JTAC.target.irPos, JTAC.playerGroupID)
	JTAC.MESSAGES.setMessageDelayed("AXEMAN 1: Ground is in the Operation area. Ready to copy target. Over", 20, 2, true)
	missionCommands.removeItemForGroup(JTAC.playerGroupID, JTAC.JD11)
    missionCommands.removeItemForGroup(JTAC.playerGroupID, JTAC.JG11)

    JTAC.JD13 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'Lase my mark', JTAC.J1, JTAC.LASER.createLaserOnMark, {jtac = jtacname, GroupPosition = JTAC.target.laserPos,Type = "Ground ", TGT = "Mark", currentLasedTarget = "STOP"})
    JTAC.JD23 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'IR my mark', JTAC.J1, JTAC.IR.createInfraRedOnMark, {jtac = jtacname, GroupPosition = JTAC.target.irPos,Type = "Ground ", TGT = "Mark", currentLasedTarget = "STOP"})
    JTAC.N31 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'Illumination Bomb', JTAC.J1, JTAC.BILLUM.illuminationBombOnMark, JTAC.target.irPos)
    JTAC.N32 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'Smoke my mark', JTAC.J1, JTAC.SMOKE.smokeOnMark, JTAC.target.irPos)
    JTAC.N33 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'Smoke Ground Jtac', JTAC.J1, JTAC.SMOKE.smokeOnJtac, JTAC.target.groundName)
    JTAC.JD14 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'Terminate lasing', JTAC.J1, JTAC.LASER.stopLaser, nil)
    JTAC.JD24 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'Terminate IR lasing', JTAC.J1, JTAC.IR.stopIR, nil)
    JTAC.JD98 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'ReScan', JTAC.J1, JTAC.NewMarkerScan, nil)
    JTAC.JD99 = missionCommands.addCommandForGroup(JTAC.playerGroupID, 'Dismiss GROUND package', JTAC.N9, JTAC.requestDismissPackage, "GROUND")
	JTAC.target.droneInZone = true
    JTAC.support = false

end;

function JTAC.targetIRUpdatePos(condition,time) 
        if condition == true and JTAC.target.currentLasedTarget ~= "STOP" then
            local targetCoord = Unit.getByName(JTAC.target.currentLasedTarget):getPoint()
            JTAC.target.irSpot:destroy()
            JTAC.target.irSpot = Spot.createInfraRed(jtacname, nil, targetCoord)
            return time + 0.15
        else
            return nil
        end  
end;

function JTAC.targetLaserUpdatePos(condition,time)
    if condition == true and JTAC.target.currentLasedTarget ~= "STOP" then
        local targetCoord = Unit.getByName(JTAC.target.currentLasedTarget):getPoint()
        JTAC.target.laserSpot:destroy()
        JTAC.target.laserSpot = Spot.createLaser(jtacname, nil, targetCoord, JTAC.target.laserCode)
        return time + 0.1
    else
        return nil
    end 
end;

function JTAC.IR.createInfraRedOnMark(vars)
    if vars.Type == nil then
		vars.Type = "Ground "
	end
	JTAC.MESSAGES.setMessageDelayed(JTAC.player .." : Requesting target: " .. vars.Type .. ":" .. vars.TGT .. " painted with IR laser, sending coordinates... ", 7, 1, true)
    JTAC.target.currentLasedTarget = "STOP"

	if JTAC.target.irSpot ~= nil then
		JTAC.target.irSpot:destroy()
		JTAC.target.irSpot = nil
	end
	JTAC.MESSAGES.setMessageDelayed("UZI 1: Roger, painting your target now.... IR Laser is now on. " , 30, 8, true)
	JTAC.MESSAGES.setMessageDelayed("INFO: lased target " ..vars.Type.. ":" .. vars.TGT, 30, 8, false)  
	JTAC.target.currentLasedTarget = vars.currentLasedTarget
	if coalition.getPlayers(coalition.side.RED)[1] ~= nil then
		JTAC.target.irSpot = Spot.createInfraRed(vars.jtac, nil, vars.GroupPosition)       
	elseif coalition.getPlayers(coalition.side.BLUE)[1] ~= nil then
		JTAC.target.irSpot = Spot.createInfraRed(vars.jtac, nil, vars.GroupPosition)
	end
	local lat, long, alt = coord.LOtoLL(vars.GroupPosition)
	local coordSTR = JTAC.getCoordinatesSTR(lat, long, alt)
	local MGRS = coord.LLtoMGRS(coord.LOtoLL(vars.GroupPosition))
    JTAC.MESSAGES.setMessageDelayed("Grid: " .. MGRS.UTMZone .. ' ' .. MGRS.MGRSDigraph .. ' ' .. MGRS.Easting .. ' ' .. MGRS.Northing, 60, 12, false)
    if vars.Type ~= "Ground " then
    timer.scheduleFunction(JTAC.targetIRUpdatePos, true, timer.getTime() + 1)
    end

end;

function JTAC.IR.stopIR()
	JTAC.target.currentLasedTarget = "STOP"
	JTAC.MESSAGES.setMessageDelayed("PLAYER: Terminate IR lasing.", 5, 1, true)
	if JTAC.target.irSpot ~= nil then
		JTAC.MESSAGES.setMessageDelayed(" Wilco. Terminate  IR lasing.... IR Laser is now off", 10, 8, true)
		JTAC.target.irSpot:destroy()
		JTAC.target.irSpot = nil
	else
		JTAC.MESSAGES.setMessageDelayed(" Negative. Currently not IR lasing a target", 10, 8, true)
	end
end;

function JTAC.LASER.createLaserOnMark(vars)
    if vars.Type == nil then
		vars.Type = "Ground "
	end
	JTAC.MESSAGES.setMessageDelayed(JTAC.player .." : Requesting target: " .. vars.Type .. ":" .. vars.TGT .. " painted with Laser code: ".. JTAC.target.laserCode ..", sending coordinates... ", 7, 1, true)
	JTAC.target.currentLasedTarget = "STOP"
	if JTAC.target.laserSpot ~= nil then
		JTAC.target.laserSpot:destroy()
		JTAC.target.laserSpot = nil
	end
	JTAC.MESSAGES.setMessageDelayed("UZI 1: Roger, painting your target now.... Laser is now on. Code: " .. JTAC.target.laserCode, 30, 8, true)
	JTAC.MESSAGES.setMessageDelayed("INFO: lased target " ..vars.Type.. ":" .. vars.TGT, 30, 8, false)
	JTAC.target.currentLasedTarget = vars.currentLasedTarget
	if coalition.getPlayers(coalition.side.RED)[1] ~= nil then
		JTAC.target.laserSpot = Spot.createLaser(vars.jtac, nil, vars.GroupPosition,JTAC.target.laserCode)
	elseif coalition.getPlayers(coalition.side.BLUE)[1] ~= nil then
		JTAC.target.laserSpot = Spot.createLaser(vars.jtac, nil, vars.GroupPosition,JTAC.target.laserCode)
	end
	local lat, long, alt = coord.LOtoLL(vars.GroupPosition)
	local coordSTR = JTAC.getCoordinatesSTR(lat, long, alt)
	local MGRS = coord.LLtoMGRS(coord.LOtoLL(vars.GroupPosition))
    JTAC.MESSAGES.setMessageDelayed("Grid: " .. MGRS.UTMZone .. ' ' .. MGRS.MGRSDigraph .. ' ' .. MGRS.Easting .. ' ' .. MGRS.Northing, 60, 12, false)
    if vars.Type ~= "Ground " then
    timer.scheduleFunction(JTAC.targetLaserUpdatePos, true, timer.getTime() + 1)
    end

end;

function JTAC.LASER.stopLaser()
	JTAC.target.currentLasedTarget = "STOP"
	JTAC.MESSAGES.setMessageDelayed(JTAC.player .." : Terminate lasing.", 5, 1, true)
	if JTAC.target.laserSpot ~= nil then
		JTAC.MESSAGES.setMessageDelayed("Wilco. Terminate lasing.... Laser is now off", 10, 8, true)
		JTAC.target.laserSpot:destroy()
		JTAC.target.laserSpot = nil
	else
		JTAC.MESSAGES.setMessageDelayed("Negative. Currently not lasing a target", 10, 8, true)
	end
end;

function JTAC.BILLUM.illuminationBombOnMark(position)
    timer.scheduleFunction(JTAC.BILLUM.illuminationBombOnMarkDelay, position, timer.getTime() + 15)
    JTAC.MESSAGES.setMessageDelayed("PLAYER: Requesting current target illumination. ", 7, 1, true)
	JTAC.MESSAGES.setMessageDelayed(" Roger, painting your target now.... Illumination Bomb on its way. " , 30, 8, true)
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
    JTAC.MESSAGES.setMessageDelayed("PLAYER: Requesting smoke on selected target. ", 7, 1, true)
	JTAC.MESSAGES.setMessageDelayed(" Roger, painting your target now with red smoke. ETA 15s " , 30, 8, true)
end;

function JTAC.SMOKE.smokeOnJtac(groundName)
    source = Group.getByName(groundName):getUnit(1)
    position = source:getPoint()
    timer.scheduleFunction(JTAC.SMOKE.triggerSmokeGreen, position, timer.getTime() + 15)
    JTAC.MESSAGES.setMessageDelayed("PLAYER: Requesting smoke Jtac position. ", 7, 1, true)
	JTAC.MESSAGES.setMessageDelayed(" Roger, Green smoke on Jtac position. ETA 15s " , 30, 8, true)
end;

function JTAC.SMOKE.triggerSmokeRed(position)
    trigger.action.smoke(position , trigger.smokeColor.Red)
end;

function JTAC.SMOKE.triggerSmokeGreen(position)
    trigger.action.smoke(position , trigger.smokeColor.Green)
end;

function JTAC.MESSAGES.setMessageDelayed(text, duration, delaySec, clear)
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
				if foundItem:inAir() ~= true and foundItem:getCoalition() ~= playerCoalition and foundItem:getCoalition() ~= coalition.side.NEUTRAL and foundItem:getLife() > 0 then
					foundUnits[#foundUnits + 1] = foundItem
				end
				return true
			end
	world.searchObjects(pType, volS, ifFound)
	
	-- Sort targets by priority if set
	if JTAC.targetPriority ~= "None" then
		table.sort(foundUnits, function(a, b)
			local catA = JTAC.categorizeTarget(a)
			local catB = JTAC.categorizeTarget(b)
			
			-- Prioritize selected category first
			if catA == JTAC.targetPriority and catB ~= JTAC.targetPriority then
				return true
			elseif catA ~= JTAC.targetPriority and catB == JTAC.targetPriority then
				return false
			else
				-- If both same priority or both not priority, sort by name
				return a:getName() < b:getName()
			end
		end)
	end
	
	return foundUnits
end;

function JTAC.TARGETMENU.menu(jtacname, markerPos, gpID)
    -- Find targets
    local FoundUnits = JTAC.SCAN.searchTargets(markerPos, JTAC.searchRadius, {Object.Category.UNIT, Object.Category.STATIC, Object.Category.SCENERY})

    -- Remove previous menu if it exists
    if JTAC.TARGETMENU.menuHandles and JTAC.TARGETMENU.menuHandles[gpID] then
        missionCommands.removeItemForGroup(gpID, JTAC.TARGETMENU.menuHandles[gpID])
        JTAC.TARGETMENU.menuHandles[gpID] = nil
    end

    -- No targets
    if not FoundUnits or #FoundUnits == 0 then
        JTAC.MESSAGES.setMessageDelayed("UZI 1: No Target found in the zone, Lase the mark?", 30, 8, true)
        return false
    end

    -- Create the base submenu
    if not JTAC.TARGETMENU.menuHandles then JTAC.TARGETMENU.menuHandles = {} end
    local menu = missionCommands.addSubMenuForGroup(gpID, "Target List", JTAC.J1)
    JTAC.TARGETMENU.menuHandles[gpID] = menu

    -- Add targets in cascaded "More" submenus, zoneCommander style
    local function addTargetsMenu(units, parentMenu)
        local count = 0
        local subMenu = parentMenu
        for i, targetUnit in ipairs(units) do
           --[[ count = count + 1
            -- After every 9 entries, create a new "More" submenu and add further entries there
            if count > 1 and (count - 1) % 9 == 0 then
                subMenu = missionCommands.addSubMenuForGroup(gpID, "More", subMenu)
            end--]]
            
            local GroupPosition = targetUnit:getPoint()
            local TYP = targetUnit:getTypeName()
            local TGT = targetUnit:getName()
            local CAT = targetUnit:getCategory()
            local OBJCAT = Object.getCategory(targetUnit)
            if JTAC.isExcludedTarget(TYP) and not JTAC.isExcludedTargetName(TGT) then
                debugMsg("Adding target: "..TGT.." ("..TYP..")")
                if count > 0 and count % 9 == 0 then
                    subMenu = missionCommands.addSubMenuForGroup(gpID, "More", subMenu)
                end
                count = count + 1
                local vars = {
                    jtac = jtacname,
                    GroupPosition = GroupPosition,
                    Type = TYP,
                    TGT = TGT,
                    currentLasedTarget = JTAC.target.currentLasedTarget,
                    Cat = CAT,
                    Objcat = OBJCAT
                }
                local tgtMenu = missionCommands.addSubMenuForGroup(gpID, TYP .. ":" .. TGT, subMenu)
                missionCommands.addCommandForGroup(gpID, 'Lase the target', tgtMenu, JTAC.LASER.createLaserOnMark, vars)
                missionCommands.addCommandForGroup(gpID, 'IR the target', tgtMenu, JTAC.IR.createInfraRedOnMark, vars)
                missionCommands.addCommandForGroup(gpID, 'Smoke the target', tgtMenu, JTAC.SMOKE.smokeOnMark, vars.GroupPosition)
            else
                debugMsg("Excluded target: "..TGT.." ("..TYP..")") 
            end
        end
    end

    addTargetsMenu(FoundUnits, menu)
end

function JTAC.NewMarkerScan()

    JTAC.target.currentLasedTarget = "STOP"
    if JTAC.target.irSpot ~= nil then
        --JTAC.MESSAGES.setMessageDelayed("PLAYER: Terminate lasing.", 5, 1, true)
		JTAC.target.irSpot:destroy()
		JTAC.target.irSpot = nil
	end
    if JTAC.target.laserSpot ~= nil then
        --JTAC.MESSAGES.setMessageDelayed("PLAYER: Terminate lasing.", 5, 1, true)
		JTAC.target.laserSpot:destroy()
		JTAC.target.laserSpot = nil
	end

    if JTAC.TARGETMENU.L1 ~= nil then
        missionCommands.removeItemForGroup(JTAC.playerGroupID, JTAC.TARGETMENU.L1)
        JTAC.TARGETMENU.L1 = missionCommands.addSubMenuForGroup(JTAC.playerGroupID, "Target List", JTAC.J1)
    end
    if JTAC.target.droneName ~= "" then
        source = Group.getByName(JTAC.target.droneName):getUnit(1)
        --trigger.action.outText("source: " .. source, 10, false)
    elseif JTAC.target.groundName ~= "" then
        source = Group.getByName(JTAC.target.groundName):getUnit(1)
    end
    JTAC.TARGETMENU.menu(source, JTAC.target.scanPos, JTAC.playerGroupID)
				debugMsg("Rescanning zone")
end

function JTAC.removeMenu(gpID)
	missionCommands.removeItemForGroup(gpID, menuPrinc)
end;

function JTAC.setMenu(gpID)
    
    if menuPrinc then
        missionCommands.removeItemForGroup(gpID, menuPrinc)
    end

	menuPrinc = missionCommands.addSubMenuForGroup(gpID, 'JTAC')
	JTAC.J1 = missionCommands.addSubMenuForGroup(gpID, 'JTAC LASE', menuPrinc)
	JTAC.JD11 = missionCommands.addCommandForGroup(gpID, 'Request Drone JTAC', JTAC.J1, JTAC.requestDrone, nil)
	JTAC.JG11 = missionCommands.addCommandForGroup(gpID, 'Request Ground JTAC', JTAC.J1, JTAC.requestGround, nil)
	JTAC.O2 = missionCommands.addSubMenuForGroup(gpID, 'OPTIONS', menuPrinc)

	-- Target Priority submenu
	JTAC.TP = missionCommands.addSubMenuForGroup(gpID, 'Target Priority', JTAC.O2)
	missionCommands.addCommandForGroup(gpID, 'Priority: Air Defence', JTAC.TP, JTAC.setTargetPriority, "Air Defence")
	missionCommands.addCommandForGroup(gpID, 'Priority: Armour', JTAC.TP, JTAC.setTargetPriority, "Armour")
	missionCommands.addCommandForGroup(gpID, 'Priority: Artillery', JTAC.TP, JTAC.setTargetPriority, "Artillery")
	missionCommands.addCommandForGroup(gpID, 'Priority: Infantry', JTAC.TP, JTAC.setTargetPriority, "Infantry")
	missionCommands.addCommandForGroup(gpID, 'Priority: None (Default)', JTAC.TP, JTAC.setTargetPriority, "None")
	JTAC.N9 = missionCommands.addSubMenuForGroup(gpID, 'DISMISS PACKAGE', menuPrinc)
end;

-- =====================================================================================
-- SCRIPT INITIALIZATION
-- =====================================================================================

-- Initialize the script
local function initialize()
    debugMsg("========================================")
    debugMsg("JTAC Script v0.2 Initializing...")
    debugMsg("========================================")

    world.addEventHandler(eventJtac);
    timer.scheduleFunction(JTAC.setAvailability, nil, timer.getTime() + 1)
    debugMsg("JTAC LOADED!", true)
    debugMsg("JTAC LOADED!")
end

-- Start initialization
initialize()