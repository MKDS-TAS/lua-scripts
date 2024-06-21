-- Authors: Suuper; some checkpoint and pointer stuffs from MKDasher
-- A Lua script that aims to be helpful for TASing.

-- Script options ---------------------
local showExactMovement = false -- set to true to display movement sine/cosine
local showAnglesAsDegrees = true
local giveGhostShrooms = false
---------------------------------------

-- Pointer internationalization -------
-- This is intended to make the script compatible with most ROM regions and ROM hacks.
-- This is not well-tested. There are some known exceptions, such as Korean version has different locations for checkpoint stuff.
local somePointerWithRegionAgnosticAddress = memory.read_u32_le(0x2000B54)
local valueForUSVersion = 0x0216F320
local ptrOffset = somePointerWithRegionAgnosticAddress - valueForUSVersion
-- Base addresses are valid for the US Version
local ptrPlayerDataAddr = 0x0217ACF8 + ptrOffset
local ptrPlayerInputsAddr = 0x02175630 + ptrOffset
local ptrGhostInputsAddr = 0x0217568C + ptrOffset
local ptrItemInfoAddr = 0x0217BC2C + ptrOffset
local ptrRaceTimersAddr = 0x0217AA34 + ptrOffset
local ptrMissionInfoAddr = 0x021A9B70 + ptrOffset
local ptrObjArrayAddr = 0x0217B598 + ptrOffset
local racerCountAddr = 0x0217ACF4 + ptrOffset
local ptrSomethingPlayerAddr = 0x021755FC + ptrOffset
local ptrSomeRaceDataAddr = 0x021759A0 + ptrOffset
local ptrCheckNumAddr = 0x021755FC + ptrOffset
local ptrCheckDataAddr = 0x02175600 + ptrOffset
---------------------------------------

local function NewMyData()
	local n = {}
	n.positionDelta = 0
	n.angleDelta = 0
	n.driftAngleDelta = 0
	n.pos = {x = 0, y = 0, z = 0}
	n.angles = {
		facing = 0, drift = 0,
		movement = { sine = 0, cosi = 0, mag = 0 },
		target = { sine = 0, cosi = 0, mag = 0 }
	}
	return n
end
local function UpdateMag(info)
	local s = info.sine / 4096
	local c = info.cosi / 4096
	info.mag = math.sqrt(s * s + c * c)
end
local myData = NewMyData()
local ghostData = NewMyData()

local raceData = {}
local nearestObjectData = {}

local function clearDataOutsideRace()
	ghostData = NewMyData()
	raceData = {
		coinsBeingCollected = 0,
	}
	nearestObjectData = {}
end

local lastFrame = 0

local form = nil
local watchingGhost = false

-- BizHawk ----------------------------
local guiScale = 2
memory.usememorydomain("ARM9 System Bus")
local function drawText(x, y, str)
	-- gui.drawText(x, y + 192, str) -- onto raw buffer
	-- onto scaled buffer
	gui.text(x, y + 192 * guiScale, str)
end

local shouldExit = false
local function main()
	_mkdsinfo_setup()
	while not shouldExit do
		_mkdsinfo_run_data()
		_mkdsinfo_run_draw()
		emu.frameadvance()
	end
	_mkdsinfo_close()
	
	gui.clearGraphics()
	gui.cleartext()
end

gui.clearGraphics()
gui.cleartext()
---------------------------------------
-- Lua versioning ---------------------
-- If we're on the newest version of BizHawk (it has a newer Lua version):
-- 1) Bitwise operators are built-in
-- 2) math.atan2 does not exist
local function band(v1, v2)
	return bit.band(v1, v2)
end
if client.getversion() == "2.9.1" then -- TODO: Handle future versions
	math.atan2 = math.atan
	band = function(v1, v2) return v1 & v2 end
end
---------------------------------------

function contains(list, x)
	for _, v in ipairs(list) do
		if v == x then return true end
	end
	return false
end

local function time(secs)
	t_sec = math.floor(secs) % 60
	if (t_sec < 10) then t_secaux = "0" else t_secaux = "" end
	t_min = math.floor(secs / 60)
	t_mili = math.floor(secs * 1000) % 1000
	if (t_mili < 10) then t_miliaux = "00" elseif (t_mili < 100) then t_miliaux = "0" else t_miliaux = "" end
	return (t_min .. ":" .. t_secaux .. t_sec .. ":" .. t_miliaux .. t_mili)
end
local function padLeft(str, pad, len)
	str = "" .. str -- ensure is string
	for i = #str, len - 1, 1 do
	str = pad .. str end
	return str
end
local function prettyFloat(value, neg)
	value = math.floor(value * 10000) / 10000
	local ret
	if (not (value == 1 or value == -1)) then
		if (value >= 0) then
			value = " " .. value end
		ret = string.sub(value .. "000000", 0, 6)
	else
		if (value == 1) then
			ret = " 1    "
		else
			ret = "-1    "
		end
	end
	if (not neg) then
		ret = string.sub(ret, 2, 6)
	end
	
	return ret
end
local function format01(value)
	-- Format a value expected to be between 0 and 1 (4096) based on script settings.
	if (not showExactMovement) then
		return prettyFloat(value / 4096, false)
	else
		return value .. ""
	end
end

local function read_pos(addr)
	return {
		x = memory.read_s32_le(addr),
		y = memory.read_s32_le(addr + 4),
		z = memory.read_s32_le(addr + 8),
	}
end
local function distanceSqBetween(p1, p2)
	local x = p2.x - p1.x
	local y = p2.y - p1.y
	local z = p2.z - p1.z
	return x * x + y * y + z * z
end

local function inRace()
	return myData.exists == true
end

local function getPlayerData(ptr, previousData)
	local newData = NewMyData()
	if ptr == 0 then
		newData.exists = false
		return newData
	end
	newData.exists = true

	-- Read positions and speed
	newData.pos.x = memory.read_s32_le(ptr + 0x80)
	newData.pos.y = memory.read_s32_le(ptr + 0x80 + 4)
	newData.pos.z = memory.read_s32_le(ptr + 0x80 + 8)
	newData.speed = memory.read_s32_le(ptr + 0x2A8)
	newData.boostAll = memory.read_s8(ptr + 0x238)
	newData.boostMt = memory.read_s8(ptr + 0x23C)
	newData.mtTime = memory.read_s32_le(ptr + 0x30C)
	newData.maxSpeed = memory.read_s32_le(ptr + 0xD0)
	newData.wallSpeedMult = memory.read_s32_le(ptr + 0x38C)
	-- Real speed
	local posDelta = math.sqrt((previousData.pos.z - newData.pos.z) ^ 2 + (previousData.pos.x - newData.pos.x) ^ 2)
	newData.posDelta = math.floor(posDelta * 10) / 10
	
	-- Read angles
	newData.angles.facing = memory.read_s16_le(ptr + 0x236)
	newData.angles.pitch = memory.read_s16_le(ptr + 0x234)
	newData.angles.drift = memory.read_s16_le(ptr + 0x388)
	newData.angles.facingDelta = newData.angles.facing - previousData.angles.facing
	newData.angles.driftDelta = newData.angles.drift - previousData.angles.drift
	newData.angles.movement.sine = memory.read_s32_le(ptr + 0x68)
	newData.angles.movement.cosi = memory.read_s32_le(ptr + 0x70)
	UpdateMag(newData.angles.movement)
	newData.angles.target.sine = memory.read_s32_le(ptr + 0x50)
	newData.angles.target.cosi = memory.read_s32_le(ptr + 0x58)
	UpdateMag(newData.angles.target)
	
	-- more stuff
	newData.turnLoss = memory.read_s32_le(ptr + 0x2D4)
	newData.grip = memory.read_s32_le(ptr + 0x240)
	if (memory.readbyte(ptr + 0x3DD) == 0) then
		newData.air = "Ground"
	else
		newData.air = "Air"
	end
	newData.spawnPoint = memory.read_s32_le(ptr + 0x3C4)
	
	return newData
end
local function getCheckpointData(dataObj)
	-- Read pointer values
	local ptrCheckNum = memory.read_s32_le(ptrCheckNumAddr)
	local ptrCheckData = memory.read_s32_le(ptrCheckDataAddr)
	
	if ptrCheckNum == 0 or ptrCheckData == 0 then
		return
	end
	
	-- Read checkpoint values
	dataObj.checkpoint = memory.read_u8(ptrCheckNum + 0x46)
	dataObj.keyCheckpoint = memory.read_s8(ptrCheckNum + 0x48)
	dataObj.checkpointGhost = memory.read_s8(ptrCheckNum + 0xD2)
	dataObj.keyCheckpointGhost = memory.read_s8(ptrCheckNum + 0xD4)
	dataObj.lap = memory.read_s8(ptrCheckNum + 0x36)
	
	-- Lap time
	dataObj.lap_f = memory.read_s32_le(ptrCheckNum + 0x18) * 1.0 / 60 - 0.05
	if (dataObj.lap_f < 0) then dataObj.lap_f = 0 end
end

local function updateGhost(form)
	local ptr = memory.read_s32_le(ptrGhostInputsAddr)
	if ptr == 0 then return end
	memory.write_bytes_as_array(ptr, form.ghostInputs)
	memory.write_s32_le(ptr, 1765) -- max input count for ghost
	-- lap times
	ptr = memory.read_s32_le(ptrSomeRaceDataAddr)
	memory.write_bytes_as_array(ptr + 0x3ec, form.ghostLapTimes)
	
	-- This frame's state won't have it, but any future state will.
	form.firstStateWithGhost = emu.framecount() + 1
end
local function setGhostInputs(form)
	local ptr = memory.read_s32_le(ptrGhostInputsAddr)
	if ptr == 0 then return end
	local currentInputs = memory.read_bytes_as_array(ptr, 0xdce)
	updateGhost(form)
	
	-- Find the first frame where inputs differ.
	local frames = 0
	-- 5, not 4: Lua table is 1-based
	for i = 5, #currentInputs, 2 do
		if form.ghostInputs[i] ~= currentInputs[i] then
			break
		elseif form.ghostInputs[i + 1] ~= currentInputs[i + 1] then
			frames = frames + math.min(form.ghostInputs[i + 1], currentInputs[i + 1])
			break
		else
			frames = frames + currentInputs[i + 1]
		end
	end
	-- Rewind, clear state history
	local targetFrame = frames + form.firstGhostInputFrame
	if emu.framecount() > targetFrame then
		local inputs = movie.getinput(targetFrame)
		local isOn = inputs["A"]
		tastudio.submitinputchange(targetFrame, "A", not isOn)
		tastudio.applyinputchanges()
		tastudio.submitinputchange(targetFrame, "A", isOn)
		tastudio.applyinputchanges()
	end
end
local function ensureGhostInputs(form)
	-- This function's job is to re-apply the hacked ghost data when the user re-winds far enough back that the hacked ghost isn't in the savestate.

	-- Ensure we're still in the same race
	local firstInputFrame = emu.framecount() - memory.read_s32_le(memory.read_s32_le(ptrRaceTimersAddr) + 4) + 121
	if firstInputFrame ~= form.firstGhostInputFrame then
		return
	end

	-- We don't want to be constantly re-applying ever frame advance.
	-- So, make sure we have either just re-wound or have frame-advanced into the race.
	local frame = emu.framecount()
	if frame < lastFrame or form.firstStateWithGhost > frame then
		updateGhost(form)
	end
end

-- Objects ----------------------------
-- Objects code is WIP.
local t = { }
if true then -- I just want to collapse this block in my editor.
	t[0x000] = "follows player"
	t[0x00b] = "STOP! signage"; t[0x00d] = "puddle";
	t[0x065] = "item box"; t[0x066] = "post";
	t[0x067] = "wooden crate"; t[0x068] = "coin";
	t[0x06e] = "gate trigger";
	t[0x0c9] = "moving item box";
	t[0x0cd] = "clock"; t[0x0cf] = "pendulum";
	t[0x12e] = "coconut tree"; t[0x12f] = "pipe";
	t[0x130] = "wumpa-fruit tree";
	t[0x138] = "striped tree";
	t[0x145] = "autumn tree"; t[0x146] = "winter tree";
	t[0x148] = "palm tree";
	t[0x14f] = "pinecone tree"; t[0x150] = "beanstalk";
	t[0x156] = "N64 winter tree";
	t[0x191] = "goomba"; t[0x192] = "giant snowball";
	t[0x193] = "thwomp";
	t[0x195] = "bus"; t[0x196] = "chain chomp";
	t[0x197] = "chain chomp post";
	t[0x198] = "leaping fireball"; t[0x199] = "mole";
	t[0x19a] = "car";
	t[0x19b] = "cheep cheep"; t[0x19c] = "truck";
	t[0x19d] = "snowman";
	t[0x19e] = "coffin"; t[0x19f] = "bats";
	t[0x1a2] = "bullet bill"; t[0x1a3] = "walking tree";
	t[0x1a4] = "flamethrower"; t[0x1a5] = "stray chain chomp";
	t[0x1ac] = "crab";
	t[0x1a6] = "piranha plant"; t[0x1a7] = "rocky wrench";
	t[0x1a8] = "bumper"; t[0x1a9] = "flipper";
	t[0x1af] = "fireballs"; t[0x1b0] = "pinball";
	t[0x1b1] = "boulder"; t[0x1b2] = "pokey";
	t[0x1f5] = "bully"; t[0x1f6] = "Chief Chilly";
	t[0x1f8] = "King Bomb-omb";
	t[0x1fb] = "Eyerok"; t[0x1fd] = "King Boo";
	t[0x1fe] = "Wiggler";
end
local objectTypes = t
local function getObjectDetails(objectId)
	local ptrObjArray = memory.read_s32_le(ptrObjArrayAddr)
	local nodePtr = ptrObjArray + (objectId * 0x1c)
	local flags = memory.read_u16_le(nodePtr + 0x14)
	local objPtr = memory.read_s32_le(nodePtr + 0x18)
	if objPtr == 0 then
		error("null object")
	end
	
	local objectDetails = {}
	objectDetails.typeId = memory.read_u16_le(objPtr)
	objectDetails.type = objectTypes[objectDetails.typeId] or "unknown " .. objectDetails.typeId
	
	-- Hitbox
	local hitboxType = ""
	if band(memory.read_u16_le(objPtr + 2), 1) == 0 then
		local maybePtr = memory.read_s32_le(objPtr + 0x98)
		local hbType = 0
		if maybePtr > 0 then
			-- The game has no null check, but I don't want to keep seeing the "attempted read outside memory" warning
			hbType = memory.read_s32_le(maybePtr + 8)
		end
		if hbType == 0 or hbType > 5 or hbType < 0 then
			hitboxType = ""
		elseif hbType == 1 then
			hitboxType = "spherical"
		elseif hbType == 2 then
			hitboxType = "cylindrical"
		elseif hbType == 3 then
			hitboxType = "by_02ead80"
		elseif hbType == 4 then
			hitboxType = "by_02eafc4" -- gate activator?
		elseif hbType == 5 then
			hitboxType = "custom" -- Object defines its own collision check function
		end
	end
	if band(flags, 0x4000) ~= 0 then
		hitboxType = hitboxType .. "item"
		-- Idk if anyting can be an item AND have another hitbox type.
	end
	if hitboxType == "" then hitboxType = "no hitbox" end
	objectDetails.hitboxType = hitboxType
	
	-- Location
	objectDetails.pos = read_pos(memory.read_s32_le(nodePtr + 0xC))

	return objectDetails
end
local function isCoinAndCollected(objPtr)
	if memory.read_s16_le(objPtr) ~= 0x68 then -- not coin
		return false
	else
		return band(memory.read_u16_le(objPtr + 2), 0x01) ~= 0
	end
end
local function getNearestTangibleObject(playerObjectId)
	local ptrObjArray = memory.read_s32_le(ptrObjArrayAddr)
	local playerObjPtr = ptrObjArray + (playerObjectId * 0x1c)
	local posPtr = memory.read_s32_le(playerObjPtr + 0xC)
	local playerPos = read_pos(posPtr)
	
	local id = 0
	local idOfNearest = -1
	local distanceToNearest = 1e300
	local positionOfNearest = {}
	while memory.read_u32_le(ptrObjArray + (id * 0x1c) + 0xC) ~= 0 do
		local current = ptrObjArray + (id * 0x1c)
		local oType = memory.read_u16_le(memory.read_s32_le(current + 0x18))
		
		local typesToIgnore = { 0 }
		-- flag 0x0200: activated or something
		-- flag 0x8000: racer (want to ignore the ghost)
		if id ~= playerObjectId and band(memory.read_u16_le(current + 0x14), 0x8200) == 0 and not contains(typesToIgnore, oType) and not isCoinAndCollected(memory.read_s32_le(current + 0x18)) then
			posPtr = memory.read_s32_le(current + 0xC)
			local objPos = read_pos(posPtr)
			local distance = distanceSqBetween(playerPos, objPos)
			if distance < distanceToNearest then
				distanceToNearest = distance
				idOfNearest = id
				positionOfNearest = objPos
			end
		end
		
		id = id + 1
	end
	if idOfNearest == -1 then
		return { id = -1 }
	end
	
	local objectDetails = getObjectDetails(idOfNearest)
	
	playerObjPtr = memory.read_s32_le(playerObjPtr + 0x18)
	local playerRadius = memory.read_s32_le(playerObjPtr + 0x1D0)
	local objPtr = ptrObjArray + (idOfNearest * 0x1c)
	objPtr = memory.read_s32_le(objPtr + 0x18)
	local objRadius = memory.read_s32_le(objPtr + 0x58)
	local hitboxType = objectDetails.hitboxType
	if hitboxType == "item" then
		objRadius = memory.read_s32_le(objPtr + 0xE0)
		playerPos = read_pos(playerObjPtr + 0x1D8)
	end
	if hitboxType == "cylindrical" then
		local xDist = positionOfNearest.x - playerPos.x
		local zDist = positionOfNearest.z - playerPos.z
		local distance = math.sqrt(xDist * xDist + zDist + zDist)
		distanceToNearest = distance - playerRadius - objRadius
		-- TODO: Check vertical distance? Obj height is at offset 0x5C. Player height is just radius.
	elseif hitboxType == "spherical" or hitboxType == "item" then
		local distance = math.sqrt(distanceSqBetween(positionOfNearest, playerPos))
		distanceToNearest = distance - playerRadius - objRadius
	else
		distanceToNearest = math.sqrt(distanceToNearest)
	end

	return {
		id = idOfNearest,
		distance = math.floor(distanceToNearest),
		object = objectDetails,
	}
end
---------------------------------------

-- All our other functions are local. This makes it so BizHawk won't share them with other scripts (avoiding potential name conflicts)
-- These functions cannot be local, since that makes them inaccessible to any function or code above them.
function _mkdsinfo_run_data()
	local frame = emu.framecount()

	local ptrPlayerData = memory.read_s32_le(ptrPlayerDataAddr)
	myData = getPlayerData(ptrPlayerData, myData)
	if not myData.exists then
		-- not in a race
		clearDataOutsideRace()
		return
	end
	
	getCheckpointData(myData)
	local ghostExists = memory.read_s32_le(racerCountAddr) >= 2 -- TODO: Don't call non-ghost CPU racers ghosts!
	if ghostExists then
		ptrPlayerData = 0x5A8 + ptrPlayerData
		ghostData = getPlayerData(ptrPlayerData, ghostData)
		myData.ghost = ghostData
	end
	
	local objId = 0
	if watchingGhost then objId = 2 end -- ?
	nearestObjectData = getNearestTangibleObject(objId)
	
	-- Ghost handling
	if form.ghostInputs ~= nil then
		ensureGhostInputs(form)
	end
	lastFrame = frame
	
	if giveGhostShrooms then
		local itemPtr = memory.read_s32_le(ptrItemInfoAddr)
		itemPtr = itemPtr + 0x210 -- ghost
		memory.write_u8(itemPtr + 0x4c, 5) -- mushroom
		memory.write_u8(itemPtr + 0x54, 3) -- count
	end

	-- Data not tied to a racer
	local ptrRaceTimers = memory.read_s32_le(ptrRaceTimersAddr)
	raceData.framesMod8 = memory.read_s32_le(ptrRaceTimers + 0xC)
	
	local ptrMissionInfo = memory.read_s32_le(ptrMissionInfoAddr)
	raceData.coinsBeingCollected = memory.read_s16_le(ptrMissionInfo + 0x8)
end
function _mkdsinfo_run_draw()
	local data = myData
	if watchingGhost then data = ghostData end
	
	gui.drawRectangle(0, 192, 256, 192, 0x60000000, 0x60000000)

	local lineHeight = 15 -- there's no font size option!?
	local sectionMargin = 6
	local function p(s, l) return padLeft(s, " ", l or 6) end
	local y = 10
	local x = 3
	local function dt(s)
		if s == nil then
			print("drawing nil at y " .. y)
		end
		drawText(x, y, s)
		y = y + lineHeight
	end	
	
	if data.exists then
		-- Display speed, boost stuff
		dt("Speed C: " .. data.speed .. ", M: " .. data.maxSpeed)
		dt("Boost Timer = " .. p(data.boostAll, 2) .. " (MT: " .. p(data.boostMt, 2) .. ")")
		drawText(223, y, p(data.mtTime, 2))
		-- Display position
		y = y + sectionMargin
		dt(data.air)
		dt("XZ delta = " .. data.posDelta)
		dt("X, Z, Y = " .. data.pos.x .. ", " .. data.pos.z.. ", " .. data.pos.y)
		-- Display angles
		y = y + sectionMargin
		if showAnglesAsDegrees then
			-- People like this
			local function atd(a)
				local deg = (((a / 0x10000) * 360) + 360) % 360
				return math.floor(deg * 1000) / 1000
			end
			local function ttd(ti)
				local radians = math.atan2(ti.sine, ti.cosi)
				local deg = radians * 360 / (2 * math.pi)
				return math.floor(deg * 1000) / 1000
			end
			dt("Facing angle = " .. atd(data.angles.facing))
			dt("Drift angle " .. atd(data.angles.drift))
			dt("Movement angle " .. ttd(data.angles.movement) .. " (" .. ttd(data.angles.target) .. ")")
		else
			-- Suuper likes this
			dt("Angle = " .. p(data.angles.facing) .. " + " .. p(data.angles.drift) .. " = " .. p(data.angles.facing + data.angles.drift))
			dt("Diff. = " .. p(data.angles.facingDelta) .. " + " .. p(data.angles.driftDelta) .. " = " .. p(data.angles.facingDelta + data.angles.driftDelta))
			local function tta(ti)
				local radians = math.atan2(ti.sine, ti.cosi)
				local dsUnits = math.floor(radians * 0x10000 / (2 * math.pi))
				return "mag: " .. prettyFloat(ti.mag) .. ", dir: " .. p(dsUnits)
			end
			dt("Movement " .. tta(data.angles.movement))
			dt("Target   " .. tta(data.angles.target))
			if showExactMovement then
				dt("C s/c: " .. (data.angles.movement.sine .. ", " .. data.angles.movement.cosi) .. " - T s/c: " .. (data.angles.target.sine .. ", " .. data.angles.target.cosi))
			end
		end
		dt("Pitch = " .. data.angles.pitch)
		-- More stuff
		y = y + sectionMargin
		local wallClip = data.wallSpeedMult
		local losses = "turnLoss = " .. format01(data.turnLoss)
		if wallClip ~= 4096 then
			losses = losses .. ", clip speed: " .. format01(data.wallSpeedMult)
		end
		dt(losses)
		local displayGrip = data.grip
		if (not showExactMovement) then
			displayGrip = prettyFloat(data.grip / 4096, false)
		end
		dt("grip = " .. displayGrip)

		-- Ghost comparison
		if data.ghost then
			y = y + sectionMargin
			local distX = data.pos.x - data.ghost.pos.x
			local distY = data.pos.y - data.ghost.pos.y
			local dist = math.sqrt(distX * distX + distY * distY)
			local distAngle = math.atan2(distY, distX)
			local direction = math.atan2(data.angles.movement.sine, data.angles.movement.cosi)
			
			angleOffset = direction - distAngle
			distPerpendicular = math.cos(angleOffset) * dist
			distParallel = math.sin(angleOffset) * dist
					
			dt("Distance from ghost ^: " .. math.floor(distParallel) .. ", >: " .. math.floor(distPerpendicular))
		end
		
		-- Nearest object
		if nearestObjectData.id ~= -1 then
			y = y + sectionMargin
			dt("Distance to nearest object: " .. nearestObjectData.distance .. " (" .. nearestObjectData.object.hitboxType .. ")")
			dt(nearestObjectData.id .. ": " .. nearestObjectData.object.type)
		end
		
		-- Display checkpoints
		if data.checkpoint ~= nil then
			y = y + sectionMargin
			if (data.spawnPoint > -1) then dt("Spawn Point: " .. data.spawnPoint) end
			dt("Checkpoint number (player) = " .. data.checkpoint .. " (" .. data.keyCheckpoint .. ")")
		end
	else
		dt("No racer data.")
	end
	
	-- Point comparison
	if form.comparisonPoint ~= nil and data.exists then
		y = y + sectionMargin
		local delta = {
			x = data.pos.x - form.comparisonPoint.x,
			z = data.pos.z - form.comparisonPoint.z
		}
		local dist = math.floor(math.sqrt(delta.x * delta.x + delta.z * delta.z))
		local angleRad = math.atan2(delta.x, delta.z)
		dt("Distance travelled: " .. dist)
		dt("Angle: " .. math.floor(angleRad * 0x10000 / (2 * math.pi)))
	end
	
	-- Coins
	if raceData.coinsBeingCollected > 0 then
		y = y + sectionMargin
		local coinCheckIn = "in " .. (8 - raceData.framesMod8) .. " frames"
		if raceData.framesMod8 == 0 then
			coinCheckIn = "this frame"
		end
		dt("Coin increment " .. coinCheckIn)
	end
	
	y = 44
	x = 320
	-- Display lap time
	if data.lap_f then
		dt("Lap = " .. time(data.lap_f))
	end

end

local function useInputsClick()
	if not inRace() then
		print("You aren't in a race.")
		return
	end
	if not tastudio.engaged() then
		return
	end

	form.ghostInputs = memory.read_bytes_as_array(memory.read_s32_le(ptrPlayerInputsAddr), 0xdce)
	form.firstGhostInputFrame = emu.framecount() - memory.read_s32_le(memory.read_s32_le(ptrRaceTimersAddr) + 4) + 121
	form.ghostLapTimes = memory.read_bytes_as_array(memory.read_s32_le(ptrSomethingPlayerAddr) + 0x20, 0x4 * 5)
	setGhostInputs(form)
end
local function watchGhostClick()
	watchingGhost = not watchingGhost
	local s = "player"
	if watchingGhost then s = "ghost" end
	forms.settext(form.watchGhost, s)
	-- re-draw
	gui.cleartext()
	gui.clearGraphics()
	_mkdsinfo_run_draw()
end
local function setComparisonPointClick()
	if form.comparisonPoint == nil then
		local pos = myData.pos
		if watchingGhost then pos = ghostData.pos end
		form.comparisonPoint = { x = pos.x, z = pos.z }
		forms.settext(form.setComparisonPoint, "Clear comparison point")
	else
		form.comparisonPoint = nil
		forms.settext(form.setComparisonPoint, "Set comparison point")
	end
end
local function loadGhostClick()
	-- Not implemented
end

local function branchLoadHandler()
	if form.firstStateWithGhost ~= 0 then
		form.firstStateWithGhost = 0
	end
end

function _mkdsinfo_setup()
	form = {}
	form.firstStateWithGhost = 0
	form.comparisonPoint = nil
	form.handle = forms.newform(250, 80, "MKDS Ghost Hacker", function()
		shouldExit = true
	end)
	
	local buttonMargin = 5
	local labelMargin = 2
	local y = 10
	-- I would use a checkbox, but they don't get a change handler.
	local temp = forms.label(form.handle, "Watching: ", 10, y + 4)
	forms.setproperty(temp, "AutoSize", true)
	form.watchGhost = forms.button(
		form.handle, "player", watchGhostClick,
		forms.getproperty(temp, "Right") + labelMargin, y,
		50, 23
	)
	
	form.setComparisonPoint = forms.button(
		form.handle, "Set comparison point", setComparisonPointClick,
		forms.getproperty(form.watchGhost, "Right") + buttonMargin, y,
		100, 23
	)
	
	y = 38
	temp = forms.label(form.handle, "Ghost: ", 10, y + 4)
	forms.setproperty(temp, "AutoSize", true)
	temp = forms.button(
		form.handle, "Copy from player", useInputsClick,
		forms.getproperty(temp, "Right") + buttonMargin, y,
		100, 23
	)
	--temp = forms.button(
	--	form.handle, "Load from bk2m", loadGhostClick,
	--	forms.getproperty(temp, "Right") + labelMargin, y,
	--	40, 23
	--)
	-- I also want a save-to-bk2m at some point. Although BizHawk doesn't expose a file open function (Lua can still write to files, we just don't have a nice way to let the user choose a save location.) so we might instead copy input to the current movie and let the user save as bk2m manually.
end
function _mkdsinfo_close()
	forms.destroy(form.handle)
end

--emu.registerafter(fn)
--gui.register(fm)
if tastudio.engaged() then
	tastudio.onbranchload(branchLoadHandler)
end
main()
