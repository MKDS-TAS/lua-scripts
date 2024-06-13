-- Addresses from https://tasvideos.org/GameResources/DS/MarioKartDS
-- Script by lexikiq, Quantum, ALAKTORN, MKDasher

-- v1.8: Add compatibility to different game versions.
-- v1.7: Motion angle is now CORRECTLY 0-360
-- v1.6: Motion angle is now 0-360
-- v1.5: Changed motion angle to be relative to starting angle
-- v1.4: Changed motion angle to be velocity based, changes sign based on direction (absolute) 
-- v1.3: Added motion angle (absolute)
-- v1.2: Fixed angle representations to degrees
-- v1.1: Re-added 'realSpeed' variable
-- v1.0: Initial port

local verUSA = true -- set to false for EUR

local xPrev = 0
local zPrev = 0
local angNormal = 0.0054931640625 --360/65536
local radToDeg = 57.295779513082320876798154814105170332405472466564321549160243861 -- 180/pi (decimal is long, we just want this to be above machine precision so the number is as accurate as possible)
local degToRad = 0.0174532925199432957692369076848861271344287188854172545609719144 -- pi/180
local initAngle = 1
local motionAngleOffset = 0
local theta0 = 0
local cTheta0 = 0
local sTheta0 = 0
local function padNum(num, digits, sign)
	local str = tostring(math.abs(num))
	while #str < digits do
		str = "0" .. str
	end
	if sign then
		if num > 0 then
			str = "+" .. str
		elseif num < 0 then
			str = "-" .. str
		else
			str = " " .. str
		end
	end
	return str
end

local function time(secs)
    local sec = padNum(math.floor(secs) % 60, 2)
    local min = math.floor(secs / 60)
    local milli = padNum(math.floor(secs * 1000) % 1000, 3)
    return min .. ":" .. sec .. ":" .. milli
end

local function text(x, y, str)
	gui.text(x, y, str)
	return y + 14
end

local function getPointers()
	-- Calculate pointers:
	-- E: 0x217ACF8 / 0x21755FC
	-- U: 0x217AD18 / 0x217561C
	-- J: 0x217AD98 / 0x217569C
	-- Should automatically be compatible with ROM Hacks unless they mess up too much with the pointers.
	
	local gameVersion = memory.read_u32_le(0x023FFA8C)
	
	local masterPointerAddress = 0x2000B54
	local masterPointer = memory.read_u32_le(masterPointerAddress)
	
	local playerData = memory.read_u32_le(masterPointer + 0xB9D8)
	local checkpointData = memory.read_u32_le(masterPointer + 0x62DC)
	
	-- Add Korean compatibility cause why not. (Only game where main pointer doesn't work on CP data)
	if gameVersion == 0x4B434D41 then checkpointData = memory.read_u32_le(0x216F9A0) end
	
	return playerData, checkpointData
end

while true do
	-- Set memory domain
	memory.usememorydomain("ARM9 System Bus")
	-- Get pointers
	playerData, checkpointData = getPointers()
	-- Read values
	local x = memory.read_s32_le(playerData + 0x80)
	local y = memory.read_s32_le(playerData + 0x84)
	local z = memory.read_s32_le(playerData + 0x88)
	local lapTime = memory.read_u32_le(checkpointData + 0x18) * 1.0 / 60 - 0.05 -- weird
	local velocity = memory.read_s32_le(playerData + 0x2A8) -- this is velocity, not speed, because it's signed
	local xVel = x - xPrev
	local zVel = z - zPrev
	local facingAngle = memory.read_u16_le(playerData + 0x236)
	facingAngle = facingAngle*angNormal
	local xSpeed = math.abs(xPrev - x)
	local zSpeed = math.abs(zPrev - z)
	local realSpeed = math.sqrt(xSpeed * xSpeed + zSpeed * zSpeed)
	local motionAngle = math.asin(xVel/realSpeed)
	if motionAngle > 0 then
		if zVel < 0 then
			motionAngle = math.pi - motionAngle 
		end
	else
		if zVel > 0 then
			motionAngle = 2*math.pi + motionAngle
		else
			motionAngle = math.pi - motionAngle
		end
	end
	motionAngle = motionAngle*radToDeg
	-- if (lapTime == 0.0 and initAngle == 1) then
	-- 	theta0 = facingAngle*degToRad
	-- 	cTheta0 = math.cos(theta0)
	-- 	sTheta0 = math.sin(theta0)
	-- 	motionAngle = 0;
	-- 	initAngle = 0
	-- else
	-- 	motionAngle = (math.acos((xVel*cTheta0 + zVel*sTheta0)/(realSpeed)) - theta0)*radToDeg
	-- end
	-- if motionAngle > 90 then motionAngle = motionAngle - 180 end
	xPrev = x
	zPrev = z
	local maxVelocity = memory.read_s32_le(playerData + 0xD0)
	local boostTimer = memory.read_s32_le(playerData + 0x238) -- measured in frames
	local mtBoostTimer = memory.read_s32_le(playerData + 0x23C) -- measured in frames
	local mtChargeTimer = memory.read_s32_le(playerData + 0x30C) -- measured in frames
	local driftAngle = memory.read_s16_le(playerData + 0x388)
	driftAngle = driftAngle*angNormal
	local verticalAngle = memory.read_s16_le(playerData + 0x234)
	verticalAngle = verticalAngle*angNormal	
	local targetSine = memory.read_s32_le(playerData + 0x50)
	local targetCosine = memory.read_s32_le(playerData + 0x58)
	local target = math.sqrt((targetSine / 4096) ^ 2 + (targetCosine / 4096) ^ 2)
	local turningLoss = memory.read_s32_le(playerData + 0x2D4)
	local grip = memory.read_s32_le(playerData + 0x240)
	local grounded = "In Air"
	if memory.read_u8(playerData + 0x3DD) == 0 then grounded = "On Ground" end
	local spawnpoint = memory.read_u8(playerData + 0x3C4)
	if spawnpoint == 255 then spawnpoint = "N/A" end
	local checkpoint = memory.read_u8(checkpointData + 0x46)
	local keyCheckpoint = memory.read_u8(checkpointData + 0x48)
	local ghostCheckpoint = memory.read_u8(checkpointData + 0xD2)
	local ghostKeyCheckpoint = memory.read_u8(checkpointData + 0xD4)
	-- Prepare to draw values
	local sx, sy = 2, 2
	local layout = nds.getscreenlayout()
	if layout == "Vertical" then
		sy = sy + ((192 + nds.getscreengap()) * client.getwindowsize())
	elseif layout == "Horizontal" then
		sx = sx + (256 * client.getwindowsize())
	end
	-- Draw values
	gui.text(sx + (256 * client.getwindowsize()) - 196, sy + (20 * client.getwindowsize()), "Lap Time: " .. time(lapTime))
	sy = text(sx, sy, "X: " .. padNum(x, 8, true))
	sy = text(sx, sy, "Z: " .. padNum(z, 8, true))
	sy = text(sx, sy, "Y: " .. padNum(y, 8, true))
	sy = text(sx, sy, "Velocity: " .. padNum(velocity, 0, true)) -- TODO: /32767??
	sy = text(sx, sy, "Real Spd:  " .. tostring(realSpeed))
	sy = text(sx, sy, "Max Vel.:  " .. tostring(maxVelocity)) -- TODO: /32767??
	sy = text(sx, sy, "Boost Timer: " .. tostring(boostTimer) .. " (MT: " .. tostring(mtBoostTimer) .. ")")
	sy = text(sx, sy, "MT Timer: " .. tostring(mtChargeTimer))
	sy = text(sx, sy, "Turning Loss: " .. string.format("%.4f", turningLoss/-4096))
	sy = text(sx, sy, "Facing Angle: " .. tostring(facingAngle)) -- TODO: /32767??
	sy = text(sx, sy, "Motion Angle: " .. tostring(motionAngle))
	sy = text(sx, sy, "X Velocity: " .. padNum(xVel, 0, true))
	sy = text(sx, sy, "Z Velocity: " .. padNum(zVel, 0, true)) -- TODO: /32767??
	sy = text(sx, sy, "Drift Angle: " .. tostring(driftAngle)) -- TODO: /11000?
	--sy = text(sx, sy, "Total Angle:" .. tostring(facingAngle + driftAngle)) -- nonsense
	sy = text(sx, sy, "Vertical Angle: " .. tostring(verticalAngle))
	-- sy = text(sx, sy, "Initial Angle: " .. formatFloat(theta0*radToDeg))
	--sy = text(sx, sy, "TargetDir: " .. formatFloat(target)) -- this one neither
	sy = text(sx, sy, "Grip: " .. string.format("%.4f", grip/4096))
	sy = text(sx, sy, grounded)
	sy = text(sx, sy, "Checkpoint: " .. tostring(checkpoint) .. " (Key: " .. tostring(keyCheckpoint) .. ")")
	sy = text(sx, sy, "Spawnpoint: " .. tostring(spawnpoint))
	--sy = text(sx, sy, "Ghost Checkpoint: " .. tostring(ghostCheckpoint) .. " (Key: " .. tostring(ghostKeyCheckpoint) .. ")") -- meh
	-- Finish
	emu.frameadvance()
end
