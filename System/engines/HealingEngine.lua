--[[---------------------------------------------------------------------------------------------------



-----------------------------------------Bubba's Healing Engine--------------------------------------]]
if not metaTable1 then
	-- localizing the commonly used functions while inside loops
	local getDistance,tinsert,tremove,UnitGUID,UnitClass,UnitIsUnit = getDistance,tinsert,tremove,UnitGUID,UnitClass,UnitIsUnit
	local UnitDebuff,UnitExists,UnitHealth,UnitHealthMax = UnitDebuff,UnitExists,UnitHealth,UnitHealthMax
	local GetSpellInfo,GetTime,UnitDebuffID,getBuffStacks = GetSpellInfo,GetTime,UnitDebuffID,getBuffStacks
	br.friend = {} -- This is our main Table that the world will see
	memberSetup = {} -- This is one of our MetaTables that will be the default user/contructor
	memberSetup.cache = { } -- This is for the cache Table to check against
	metaTable1 = {} -- This will be the MetaTable attached to our Main Table that the world will see
	metaTable1.__call = function(_, ...) -- (_, forceRetable, excludePets, onlyInRange) [Not Implemented]
		local group =  IsInRaid() and "raid" or "party" -- Determining if the UnitID will be raid or party based
		local groupSize = IsInRaid() and GetNumGroupMembers() or GetNumGroupMembers() - 1 -- If in raid, we check the entire raid. If in party, we remove one from max to account for the player.
		if group == "party" then tinsert(br.friend, memberSetup:new("player")) end -- We are creating a new User for player if in a Group
		for i=1, groupSize do -- start of the loop to read throught the party/raid
			local groupUnit = group..i
			local groupMember = memberSetup:new(groupUnit)
			if groupMember then tinsert(br.friend, groupMember) end -- Inserting a newly created Unit into the Main Frame
		end
	end
	metaTable1.__index =  {-- Setting the Metamethod of Index for our Main Table
		name = "Healing Table",
		author = "Bubba",
	}
	-- Creating a default Unit to default to on a check
	memberSetup.__index = {
		name = "noob",
		hp = 100,
		unit = "noob",
		role = "NOOB",
		range = false,
		guid = 0,
		guidsh = 0,
		class = "NONE",
	}
	-- If ever somebody enters or leaves the raid, wipe the entire Table
	local updateHealingTable = CreateFrame("frame", nil)
	updateHealingTable:RegisterEvent("GROUP_ROSTER_UPDATE")
	updateHealingTable:SetScript("OnEvent", function()
		table.wipe(br.friend)
		table.wipe(memberSetup.cache)
		SetupTables()
	end)
	-- This is for those NPC units that need healing. Compare them against our list of Unit ID's
	local function SpecialHealUnit(tar)
		for i=1, #novaEngineTables.SpecialHealUnitList do
			if getGUID(tar) == novaEngineTables.SpecialHealUnitList[i] then
				return true
			end
		end
	end
	-- We are checking if the user has a Debuff we either can not or don't want to heal them
	local function CheckBadDebuff(tar)
		for i=1, #novaEngineTables.BadDebuffList do
			if UnitDebuff(tar, GetSpellInfo(novaEngineTables.BadDebuffList[i])) or UnitBuff(tar, GetSpellInfo(novaEngineTables.BadDebuffList[i])) then
				return false
			end
		end
		return true
	end
	-- This is for NPC units we do not want to heal. Compare to list in collections.
	local function CheckSkipNPC(tar)
		local npcId = (getGUID(tar))
		for i=1, #novaEngineTables.skipNPC do
			if npcId == novaEngineTables.skipNPC[i] then
				return true
			end
		end
	return false
	end
	local function CheckCreatureType(tar)
		local CreatureTypeList = {"Critter", "Totem", "Non-combat Pet", "Wild Pet"}
		for i=1, #CreatureTypeList do
			if UnitCreatureType(tar) == CreatureTypeList[i] then return false end
		end
		if not UnitIsBattlePet(tar) and not UnitIsWildBattlePet(tar) then return true else return false end
	end
	-- Verifying the target is a Valid Healing target
	function HealCheck(tar)
		if ((UnitIsVisible(tar)
			and not UnitIsCharmed(tar)
			and UnitReaction("player",tar) > 4
			and not UnitIsDeadOrGhost(tar)
			and UnitIsConnected(tar)
			and UnitInPhase(tar))
			or novaEngineTables.SpecialHealUnitList[tonumber(select(2,getGUID(tar)))] ~= nil	or (getOptionCheck("Heal Pets") == true and UnitIsOtherPlayersPet(tar) or UnitGUID(tar) == UnitGUID("pet")))
			and CheckBadDebuff(tar)
			and CheckCreatureType(tar)
			and getLineOfSight("player", tar)
			and UnitInPhase(tar)
		then return true
		else return false end

	end
	function memberSetup:new(unit)
		-- Seeing if we have already cached this unit before
		if memberSetup.cache[getGUID(unit)] then return false end
		local o = {}
		setmetatable(o, memberSetup)
		if unit and type(unit) == "string" then
			o.unit = unit
		end
		-- This is the function for Dispel checking built into the player itself.
		function o:Dispel()
			for i = 1, #novaEngineTables.DispelID do
				if UnitDebuff(o.unit,GetSpellInfo(novaEngineTables.DispelID[i].id)) ~= nil and novaEngineTables.DispelID[i].id ~= nil then
					if select(4,UnitDebuff(o.unit,GetSpellInfo(novaEngineTables.DispelID[i].id))) >= novaEngineTables.DispelID[i].stacks
                    and (isChecked("Dispel delay") and
                            (getDebuffDuration(o.unit, novaEngineTables.DispelID[i].id) - getDebuffRemain(o.unit, novaEngineTables.DispelID[i].id)) > (getDebuffDuration(o.unit, novaEngineTables.DispelID[i].id) * (math.random(getValue("Dispel delay")-2, getValue("Dispel delay")+2)/100) ))then -- Dispel Delay
						if novaEngineTables.DispelID[i].range ~= nil then
							if #getAllies(o.unit,novaEngineTables.DispelID[i].range) > 1 then
								return false
							end
						end
						return true
					end
				end
			end
			return false
		end
		-- We are checking the HP of the person through their own function.
		function o:CalcHP()
			-- Place out of range players at the end of the list -- replaced range to 40 as we should be using lib range
			if not UnitInRange(o.unit) and getDistance(o.unit) > 40 and not UnitIsUnit("player", o.unit) then
				return 250,250,250
			end
			-- Place Dead players at the end of the list
			if HealCheck(o.unit) ~= true then
				return 250,250,250
			end
			-- incoming heals
			local incomingheals
			if getOptionCheck("Incoming Heals") == true and UnitGetIncomingHeals(o.unit,"player") ~= nil then
				incomingheals = UnitGetIncomingHeals(o.unit,"player")
			else
				incomingheals = 0
			end
			-- absorbs
			local nAbsorbs
			if getOptionCheck("No Absorbs") ~= true then
				nAbsorbs = (UnitGetTotalAbsorbs(o.unit)*0.25)
			else
				nAbsorbs = 0
			end
			-- calc base + absorbs + incomings
			local PercentWithIncoming = 100 * ( UnitHealth(o.unit) + incomingheals + nAbsorbs ) / UnitHealthMax(o.unit)
			-- Using the group role assigned to the Unit
			if o.role == "TANK" then
				PercentWithIncoming = PercentWithIncoming - 5
			end
			-- Using Dispel Check to see if we should give bonus weight
			if o.dispel then
				PercentWithIncoming = PercentWithIncoming - 2
			end
			-- Using threat to remove 3% to all tanking units
			if o.threat == 3 then
				PercentWithIncoming = PercentWithIncoming - 3
			end
			-- Tank in Proving Grounds
			if o.guidsh == 72218  then
				PercentWithIncoming = PercentWithIncoming - 5
			end
			local ActualWithIncoming = ( UnitHealthMax(o.unit) - ( UnitHealth(o.unit) + incomingheals ) )
			-- Malkorok shields logic
			local SpecificHPBuffs = {
				{buff = 142865,value = select(15,UnitDebuffID(o.unit,142865))}, -- Strong Ancient Barrier (Green)
				{buff = 142864,value = select(15,UnitDebuffID(o.unit,142864))}, -- Ancient Barrier (Yellow)
				{buff = 142863,value = select(15,UnitDebuffID(o.unit,142863))}, -- Weak Ancient Barrier (Red)
			}
			if UnitDebuffID(o.unit, 142861) then -- If Miasma found
				for i = 1,#SpecificHPBuffs do -- start iteration
					if UnitDebuffID(o.unit, SpecificHPBuffs[i].buff) ~= nil then -- if buff found
						if SpecificHPBuffs[i].value ~= nil then
							PercentWithIncoming = 100 + (SpecificHPBuffs[i].value/UnitHealthMax(o.unit)*100) -- we set its amount + 100 to make sure its within 50-100 range
							break
						end
					end
				end
			PercentWithIncoming = PercentWithIncoming/2 -- no mather what as long as we are on miasma buff our life is cut in half so unshielded ends up 0-50
			end
			-- Tyrant Velhair Aura logic
			if UnitDebuffID(o.unit, 179986) then -- If Aura of Contempt found
				max_percentage = select(15,UnitAura("boss1",GetSpellInfo(179986))) -- find current reduction % in healing
				if max_percentage then 
					PercentWithIncoming = (PercentWithIncoming/max_percentage)* 100 -- Calculate Actual HP % after reduction
				end
			end
			-- Debuffs HP compensation
			local HpDebuffs = novaEngineTables.SpecificHPDebuffs
			for i = 1, #HpDebuffs do
				local _,_,_,count,_,_,_,_,_,_,spellID = UnitDebuffID(o.unit,HpDebuffs[i].debuff)
				if spellID ~= nil and (HpDebuffs[i].stacks == nil or (count and count >= HpDebuffs[i].stacks)) then
					PercentWithIncoming = PercentWithIncoming - HpDebuffs[i].value
					break
				end
			end
			if getOptionCheck("Blacklist") == true and br.data.blackList ~= nil then
				for i = 1, #br.data.blackList do
					if o.guid == br.data.blackList[i].guid then
						PercentWithIncoming,ActualWithIncoming,nAbsorbs = PercentWithIncoming + getValue("Blacklist"),ActualWithIncoming + getValue("Blacklist"),nAbsorbs + getValue("Blacklist")
						break
					end
				end
			end
			return PercentWithIncoming,ActualWithIncoming,nAbsorbs
		end
		-- returns unit GUID
		function o:nGUID()
			local nShortHand = ""
			if UnitExists(unit) then
				targetGUID = UnitGUID(unit)
				nShortHand = UnitGUID(unit):sub(-5)
			end
			return targetGUID, nShortHand
		end
		-- Returns unit class
		function o:GetClass()
			if UnitGroupRolesAssigned(o.unit) == "NONE" then
				if UnitIsUnit("player",o.unit) then
					return UnitClass("player")
				end
				if novaEngineTables.roleTable[UnitName(o.unit)] ~= nil then
					return novaEngineTables.roleTable[UnitName(o.unit)].class
				end
			else
				return UnitClass(o.unit)
			end
		end
		-- return unit role
		function o:GetRole()
			if UnitGroupRolesAssigned(o.unit) == "NONE" then
				-- if we already have a role defined we dont scan
				if novaEngineTables.roleTable[UnitName(o.unit)] ~= nil then
					return novaEngineTables.roleTable[UnitName(o.unit)].role
				end
			else
				return UnitGroupRolesAssigned(o.unit)
			end
		end
		-- sets actual position of unit in engine, shouldnt refresh more than once/sec
		function o:GetPosition()
			if UnitIsVisible(o.unit) then
				o.refresh = GetTime()
				local x,y,z = GetObjectPosition(o.unit)
				x = math.ceil(x*100)/100
				y = math.ceil(y*100)/100
				z = math.ceil(z*100)/100
				return x,y,z
			else
				return 0,0,0
			end
		end
		-- Group Number of Player: getUnitGroupNumber(1)
		function o:getUnitGroupNumber()
			-- check if in raid
			if IsInRaid() and UnitInRaid(o.unit) ~= nil then
				return select(3,GetRaidRosterInfo(UnitInRaid(o.unit)))
			end
			return 0
		end
		-- Unit distance to player
		function o:getUnitDistance()
			if UnitIsUnit("player",o.unit) then return 0 end
			return getDistance("player",o.unit)
		end
		-- Updating the values of the Unit
		function o:UpdateUnit()
            if br.data.settings[br.selectedSpec].toggles["isDebugging"] == true then
                local startTime, duration
                local debugprofilestop = debugprofilestop

                -- assign Name of unit
                startTime = debugprofilestop()
                o.name = UnitName(o.unit)
                br.debug.cpu.healingEngine.UnitName = br.debug.cpu.healingEngine.UnitName + debugprofilestop()-startTime

                -- assign real GUID of unit
                startTime = debugprofilestop()
                o.guid = o:nGUID()
                br.debug.cpu.healingEngine.nGUID = br.debug.cpu.healingEngine.nGUID + debugprofilestop()-startTime

                -- assign unit role
                startTime = debugprofilestop()
                o.role = o:GetRole()
                br.debug.cpu.healingEngine.GetRole = br.debug.cpu.healingEngine.GetRole + debugprofilestop()-startTime

                -- subgroup number
                startTime = debugprofilestop()
                o.subgroup = o:getUnitGroupNumber()
                br.debug.cpu.healingEngine.getUnitGroupNumber = br.debug.cpu.healingEngine.getUnitGroupNumber+ debugprofilestop()-startTime

                -- Short GUID of unit for the SetupTable
                o.guidsh = select(2, o:nGUID())

                -- set to true if unit should be dispelled
                startTime = debugprofilestop()
                o.dispel = o:Dispel(o.unit)
                br.debug.cpu.healingEngine.Dispel = br.debug.cpu.healingEngine.Dispel + debugprofilestop()-startTime

                -- distance to player
                startTime = debugprofilestop()
                o.distance = o:getUnitDistance()
                br.debug.cpu.healingEngine.getUnitDistance = br.debug.cpu.healingEngine.getUnitDistance + debugprofilestop()-startTime

                -- Unit's threat situation(1-4)
                startTime = debugprofilestop()
                o.threat = UnitThreatSituation(o.unit)
                br.debug.cpu.healingEngine.UnitThreatSituation = br.debug.cpu.healingEngine.UnitThreatSituation + debugprofilestop()-startTime

                -- Unit HP absolute
                startTime = debugprofilestop()
                o.hpabs = UnitHealth(o.unit)
                br.debug.cpu.healingEngine.UnitHealth = br.debug.cpu.healingEngine.UnitHealth + debugprofilestop()-startTime

                -- Unit HP missing absolute
                startTime = debugprofilestop()
                o.hpmissing = UnitHealthMax(o.unit) - UnitHealth(o.unit)
                br.debug.cpu.healingEngine.hpMissing = br.debug.cpu.healingEngine.hpMissing + debugprofilestop()-startTime

                -- Unit HP
                startTime = debugprofilestop()
                o.hp = o:CalcHP()
                o.absorb = select(3, o:CalcHP())
                br.debug.cpu.healingEngine.absorb = br.debug.cpu.healingEngine.absorb + debugprofilestop()-startTime

                -- Target's target
                o.target = tostring(o.unit).."target"

                -- Unit Class
                startTime = debugprofilestop()
                o.class = o:GetClass()
                br.debug.cpu.healingEngine.GetClass = br.debug.cpu.healingEngine.GetClass + debugprofilestop()-startTime

                -- Unit is player
                startTime = debugprofilestop()
                o.isPlayer = UnitIsPlayer(o.unit)
                br.debug.cpu.healingEngine.UnitIsPlayer = br.debug.cpu.healingEngine.UnitIsPlayer + debugprofilestop()-startTime

                -- precise unit position
                startTime = debugprofilestop()
                if o.refresh == nil or o.refresh < GetTime() - 1 then
                    o.x,o.y,o.z = o:GetPosition()
                end
                br.debug.cpu.healingEngine.GetPosition = br.debug.cpu.healingEngine.GetPosition + debugprofilestop()-startTime

                --debug
                startTime = debugprofilestop()
                o.hp, _, o.absorb = o:CalcHP()
                br.debug.cpu.healingEngine.absorbANDhp = br.debug.cpu.healingEngine.absorbANDhp + debugprofilestop()-startTime

            else
                -- assign Name of unit
                o.name = UnitName(o.unit)
                -- assign real GUID of unit and Short GUID of unit for the SetupTable
                o.guid, o.guidsh = o:nGUID()
                -- assign unit role
                o.role = o:GetRole()
                -- subgroup number
                o.subgroup = o:getUnitGroupNumber()
                -- set to true if unit should be dispelled
                o.dispel = o:Dispel(o.unit)
                -- distance to player
                o.distance = o:getUnitDistance()
                -- Unit's threat situation(1-4)
                o.threat = UnitThreatSituation(o.unit)
                -- Unit HP absolute
                o.hpabs = UnitHealth(o.unit)
                -- Unit HP missing absolute
                o.hpmissing = UnitHealthMax(o.unit) - UnitHealth(o.unit)
                -- Unit HP and Absorb
                o.hp, _, o.absorb = o:CalcHP()
                -- Target's target
                o.target = tostring(o.unit).."target"
                -- Unit Class
                o.class = o:GetClass()
                -- Unit is player
                o.isPlayer = UnitIsPlayer(o.unit)
                -- precise unit position
                if o.refresh == nil or o.refresh < GetTime() - 1 then
                    o.x,o.y,o.z = o:GetPosition()
                end
            end
			-- add unit to setup cache
			memberSetup.cache[select(2, getGUID(o.unit))] = o -- Add unit to SetupTable
		end
		-- Adding the user and functions we just created to this cached version in case we need it again
		-- This will also serve as a good check for if the unit is already in the table easily
		--Print(UnitName(unit), select(2, getGUID(unit)))
		memberSetup.cache[select(2, o:nGUID())] = o
		return o
	end
	-- Setting up the tables on either Wipe or Initial Setup
	function SetupTables() -- Creating the cache (we use this to check if some1 is already in the table)
		setmetatable(br.friend, metaTable1) -- Set the metaTable of Main to Meta
		function br.friend:Update()
			local refreshTimer = 0.666
			if br.friendTableTimer == nil or br.friendTableTimer <= GetTime() - refreshTimer then
				br.friendTableTimer = GetTime()
				-- Print("HEAL PULSE: "..GetTime())		-- debug Print to check update time
				-- This is for special situations, IE world healing or NPC healing in encounters
				local selectedMode,SpecialTargets = getOptionValue("Special Heal"), {}
				if getOptionCheck("Special Heal") == true then
					if selectedMode == 1 then
						SpecialTargets = { "target" }
					elseif selectedMode == 2 then
						SpecialTargets = { "target","mouseover","focus" }
					elseif selectedMode == 3 then
						SpecialTargets = { "target","mouseover" }
					else
						SpecialTargets = { "target","focus" }
					end
				end
				for p=1, #SpecialTargets do
					-- Checking if Unit Exists and it's possible to heal them
					if UnitExists(SpecialTargets[p]) and HealCheck(SpecialTargets[p]) and not CheckSkipNPC(SpecialTargets[p]) then
						if not memberSetup.cache[select(2, getGUID(SpecialTargets[p]))] then
							local SpecialCase = memberSetup:new(SpecialTargets[p])
							if SpecialCase then
								-- Creating a new user, if not already tabled, will return with the User
								for j=1, #br.friend do
									if br.friend[j].unit == SpecialTargets[p] then
										-- Now we add the Unit we just created to the Main Table
										for k,v in pairs(memberSetup.cache) do
											if br.friend[j].guidsh == k then
												memberSetup.cache[k] = nil
											end
										end
										tremove(br.friend, j)
										break
									end
								end
							end
							tinsert(br.friend, SpecialCase)
							novaEngineTables.SavedSpecialTargets[SpecialTargets[p]] = select(2,getGUID(SpecialTargets[p]))
						end
					end
				end
				for p=1, #SpecialTargets do
					local removedTarget = false
					for j=1, #br.friend do
						-- Trying to find a case of the unit inside the Main Table to remove
						if br.friend[j].unit == SpecialTargets[p] and (br.friend[j].guid ~= 0 and br.friend[j].guid ~= UnitGUID(SpecialTargets[p])) then
							tremove(br.friend, j)
							removedTarget = true
							break
						end
					end
					if removedTarget == true then
						for k,v in pairs(memberSetup.cache) do
							-- Now we're trying to find that unit in the Cache table to remove
							if SpecialTargets[p] == v.unit then
								memberSetup.cache[k] = nil
							end
						end
					end
				end
				for i=1, #br.friend do
					-- We are updating all of the User Info (Health/Range/Name)
					br.friend[i]:UpdateUnit()
				end
				-- We are sorting by Health first
				table.sort(br.friend, function(x,y)
					return x.hp < y.hp
				end)
				-- Sorting with the Role
				if getOptionCheck("Sorting with Role") then
					table.sort(br.friend, function(x,y)
						if x.role and y.role then return x.role > y.role
						elseif x.role then return true
						elseif y.role then return false end
					end)
				end
				if getOptionCheck("Special Priority") == true then
					if UnitExists("focus") and memberSetup.cache[select(2, getGUID("focus"))] then
						table.sort(br.friend, function(x)
							if x.unit == "focus" then
								return true
							else
								return false
							end
						end)
					end
					if UnitExists("target") and memberSetup.cache[select(2, getGUID("target"))] then
						table.sort(br.friend, function(x)
							if x.unit == "target" then
								return true
							else
								return false
							end
						end)
					end
					if UnitExists("mouseover") and memberSetup.cache[select(2, getGUID("mouseover"))] then
						table.sort(br.friend, function(x)
							if x.unit == "mouseover" then
								return true
							else
								return false
							end
						end)
					end
				end
				if pulseNovaDebugTimer == nil or pulseNovaDebugTimer <= GetTime() then
					pulseNovaDebugTimer = GetTime() + 0.5
					pulseNovaDebug()
				end
				-- update these frames to current br.friend values via a pulse in nova engine
			end -- timer capsule
		end
		-- We are creating the initial Main Table
		br.friend()
	end
	-- We are setting up the Tables for the first time
	SetupTables()
end
