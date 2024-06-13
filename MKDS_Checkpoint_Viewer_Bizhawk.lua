-- Checkpoint viewer bottom screen
-- Author: MKDasher
-- Contributor: Suuper

-- Added region compatibility

memory.usememorydomain("ARM9 System Bus")
local showNonKeyCheckpoints = true;

local lastInput = {};

local angle = 0;
local angle2 = 0;
local pAng1, pAng2 = 0, 0;
local anglerad = 0;

local checkpoint, keycheckpoint, checkpointghost, keycheckpointghost = 0, 0, 0, 0;
local xpos, ypos, zpos, speed = 0, 0, 0, 0;

local pntMaster, pntPlayerData, pntCheckNum, pntCheckData = 0,0,0,0

local chkAddr = 0;
local chkDataLength = 0x24;
-- + chkDataLength + (0,4,8,12)

local totalcheckpoints = 0;
-- centro = (127.5,97)

local x1aux, y1aux, x2aux, y2aux = 0, 0, 0, 0;

local zoomFactor = 24000;

local screen = { height = 192, width = 256}

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
	local checkpointData2 = memory.read_u32_le(masterPointer + 0x62E0)

	-- Add Korean compatibility cause why not. (Only game where main pointer doesn't work on CP data)
	if gameVersion == 0x4B434D41 then
		checkpointData = memory.read_u32_le(0x216F9A0)
		checkpointData2 = memory.read_u32_le(0x216F9A4)
	end

	return masterPointer, playerData, checkpointData, checkpointData2
end

local function drawCheckpointText(x, y, text, color)
	gui.drawText(x,y,text,color, "black", 10, "Arial", "bold", "center", "center")
end
local function drawText(x, y, text, color)
	gui.pixelText(x,y,text,color, nil, 1)
end


function fn()
   pntMaster, pntPlayerData, pntCheckNum, pntCheckData = getPointers()

   --angle = memory.read_s16_le(pntPlayerData + 0x236)
   checkpoint = memory.read_u8(pntCheckNum + 0x46)
   keycheckpoint = memory.read_u8(pntCheckNum + 0x48)
   checkpointghost = memory.read_u8(pntCheckNum + 0xD2)
   --keycheckpointghost = memory.read_u8(pntCheckNum + 0xD4)
   totalcheckpoints = memory.read_u16_le(pntCheckData + 0x48)

   pAng2 = pAng1;
   pAng1 = angle2;
   angle2 = memory.read_s16_le(pntMaster + 0xC32C) / 4096;
   angle2 = math.asin(angle2) * -2;

   xpos = memory.read_s32_le(pntPlayerData + 0x80);
   zpos = memory.read_s32_le(pntPlayerData + 0x80 + 4);
   ypos = memory.read_s32_le(pntPlayerData + 0x80 + 8);
   speed = memory.read_s8(pntPlayerData + 0x45E);

   chkAddr = memory.read_u32_le(pntCheckData + 0x44);

   -- Default value of this address is 134, for which zoomFactor should be 24,000.
    local zoomAddress = memory.read_u32_le(pntMaster + 0xC010) + 0x854;
    zoomFactor = 134 / memory.read_u32_le(zoomAddress);
    zoomFactor = zoomFactor * 24576;

    local currentInput = input.get();
    if (currentInput.T and not lastInput.T) then
        showNonKeyCheckpoints = not showNonKeyCheckpoints;
    end
    lastInput = currentInput;
end

function fm()
  if (totalcheckpoints < 1 or totalcheckpoints > 80) then
    totalcheckpoints = 0;
  end
  if pntPlayerData == 0 then
	gui.clearGraphics()
	return
  end
  if (totalcheckpoints > 0) then
    drawText(5, (screen.height * 2 - 12), "Cur. checkpoint = " .. checkpoint .. " (" .. keycheckpoint .. ")", "white")
    drawText(12, (5 + screen.height), "Start line", "red");
    gui.drawBox(2, 5 + screen.height, 8, 11 + screen.height, "black", "red");
    drawText(12, (15 + screen.height), "Key checkpoint", "cyan");
    gui.drawBox(2, 15 + screen.height, 8, 21 + screen.height,"black", "cyan");
  	if (showNonKeyCheckpoints) then
        drawText(12, (25 + screen.height), "Normal checkpoint", "yellow");
        gui.drawBox(2, 25 + screen.height, 8, 31 + screen.height, "black", "yellow");
  	end
  end
  for i = 0, totalcheckpoints - 1 do
	-- CheckPoint X, Y for both end
    local cp1x = memory.read_s32_le(chkAddr + i * chkDataLength + 0x0) / zoomFactor;
    local cp1y = memory.read_s32_le(chkAddr + i * chkDataLength + 0x4) / zoomFactor;
    local cp2x = memory.read_s32_le(chkAddr + i * chkDataLength + 0x8) / zoomFactor;
    local cp2y = memory.read_s32_le(chkAddr + i * chkDataLength + 0xC) / zoomFactor;
	-- Local vars because the draw function may be called multiple times between frames
    local xpos = xpos / zoomFactor;
    local ypos = ypos / zoomFactor;

	anglerad = pAng2;
    x1aux = screen.width/2 + (xpos - cp1x) * math.cos(anglerad) - (ypos - cp1y) * math.sin(anglerad);
    y1aux = 97 + (ypos - cp1y) * math.cos(anglerad) + (xpos - cp1x) * math.sin(anglerad);
    x2aux = screen.width/2 + (xpos - cp2x) * math.cos(anglerad) - (ypos - cp2y) * math.sin(anglerad);
    y2aux = 97 + (ypos - cp2y) * math.cos(anglerad) + (xpos - cp2x) * math.sin(anglerad);

	local color = "";
    if (i == 0) then
      color = "red";
    elseif (memory.read_s16_le(chkAddr + i * chkDataLength + 0x20) >= 0) then
      color = "cyan";
    else
	  if (showNonKeyCheckpoints) then
        color = "yellow";
	  end
    end

	cp1x = x1aux;
	cp1y = y1aux;
	cp2x = x2aux;
	cp2y = y2aux;
    if (y1aux >= 0 and y2aux >= 0) then
	  -- nothing
    elseif(y1aux > 0) then
      distauxy = y1aux - y2aux;
      distauxx = x1aux - x2aux;
      cp2x = x1aux - (y1aux * distauxx / distauxy);
	  cp2y = 0;
    elseif(y2aux > 0) then
      distauxy = y2aux - y1aux;
      distauxx = x2aux - x1aux;
      cp1x = x2aux - (y2aux * distauxx / distauxy);
	  cp1y = 0;
    end

	-- Don't attempt to draw super-long lines.
	if (color ~= "" and math.abs(cp2x - cp1x) < 1000 and math.abs(cp2y - cp1y) < 1000) then
	  if (cp1y >= 0 or cp2y >= 0) then
        gui.drawLine(cp1x, cp1y+screen.height, cp2x, cp2y+screen.height, color);
      end

      if (y1aux > 0) then
        drawCheckpointText(x1aux, (y1aux+screen.height), i, color);
      end
      if (y2aux > 0) then
        drawCheckpointText(x2aux, (y2aux+screen.height), i, color);
      end
	end

  end -- for
end

function onExit()
	collectgarbage()
	gui.clearGraphics()
end

while true do
  fn()
  fm()
  emu.frameadvance()
end

event.onexit(onExit)
