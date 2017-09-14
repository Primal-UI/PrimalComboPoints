local addonName, addon = ...

--PrimalComboPoints = setmetatable({}, { __index = _G })
PrimalComboPoints = LibStub("AceAddon-3.0"):NewAddon("PrimalComboPoints", "AceConsole-3.0")
--setmetatable(PrimalComboPoints, { __index = _G })
PrimalComboPoints._G = _G

setfenv(1, PrimalComboPoints)

local PrimalComboPoints = _G.PrimalComboPoints

local AceGUI = _G.LibStub("AceGUI-3.0")
local AceConfig = _G.LibStub("AceConfig-3.0")
local AceConfigDialog = _G.LibStub("AceConfigDialog-3.0")

local comboPointFrame = _G.CreateFrame("Frame", nil, _G.UIParent)
local comboPointFrames = {}

local comboPoints

comboPointFrame:SetSize(32, 32)
comboPointFrame:SetClampedToScreen(true)
comboPointFrame:SetScript("OnDragStart", function(self, button)
  self:StartMoving()
end)
comboPointFrame:SetScript("OnDragStop", function(self, button)
  self:StopMovingOrSizing()
  db.global.xOffset, db.global.yOffset = _G.math.floor(self:GetLeft() + .5), _G.math.floor(self:GetBottom() + .5)
  self:SetPoint("BOTTOMLEFT", db.global.xOffset, db.global.yOffset)
end)

local backdrop = {
  bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
  edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
  tile = false,
  edgeSize = 1,
  insets = {
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
  },
}

for i = 1, _G.MAX_COMBO_POINTS do
  local frame = _G.CreateFrame("Frame", nil, comboPointFrame)
  frame:SetSize(15, 15)
  comboPointFrames[i] = frame
end

for i = 1, _G.MAX_COMBO_POINTS - 1 do
  local frame = comboPointFrames[i]
  frame:SetSize(15, 15)
  frame:SetBackdrop(backdrop)
  frame:SetBackdropBorderColor(0, 0, 0)
  frame:SetBackdropColor(0, 0, 0, .25)
end

comboPointFrames[1]:SetPoint("BOTTOMLEFT", comboPointFrame)
comboPointFrames[2]:SetPoint("BOTTOMRIGHT", comboPointFrame)
comboPointFrames[3]:SetPoint("TOPRIGHT", comboPointFrame)
comboPointFrames[4]:SetPoint("TOPLEFT", comboPointFrame)

do
  local frame = comboPointFrames[5]
  frame:SetFrameLevel(comboPointFrame:GetFrameLevel() + 2)
  frame:SetSize(22, 22)
  frame:SetBackdrop(backdrop)
  frame:SetBackdropBorderColor(0, 0, 0)
  frame:SetBackdropColor(1, 1, 1, 0.75)
  frame:SetPoint("CENTER", comboPointFrame)
  frame:Hide()
end

function comboPointFrame:update(newCP)
  comboPoints = newCP

  for i = 1, comboPoints do
    comboPointFrames[i]:SetBackdropColor(1, 1, 1, .5)
  end
  for i = comboPoints + 1, _G.MAX_COMBO_POINTS - 1 do
    comboPointFrames[i]:SetBackdropColor(0, 0, 0, .25)
  end
  if comboPoints == _G.MAX_COMBO_POINTS then
    if not comboPointFrames[5]:IsShown() then
      comboPointFrames[5]:Show()
    end
  else
    comboPointFrames[5]:Hide()
  end
end
------------------------------------------------------------------------------------------------------------------------

handlerFrame = _G.CreateFrame("Frame")

handlerFrame:SetScript("OnEvent", function(self, event, ...)
  return self[event](self, ...)
end)

function handlerFrame:UNIT_POWER(unit, arg2)

	if unit ~= "player" -- Not related to the player's character
	or arg2 ~= "COMBO_POINTS" -- Not a Combo Point-related event
	then -- Skip update, as it isn't a relevant notification
		return
	end 

  local newCP = _G.UnitPower("player", 4)

  if db.global.sound and newCP == _G.MAX_COMBO_POINTS and newCP ~= comboPoints then
    local file = [[Interface\AddOns\PrimalComboPoints\media\sounds\noisecrux\vio]] .. _G.math.random(10) .. ".ogg"
    _G.PlaySoundFile(file, "Master")
  end

  comboPointFrame:update(newCP)
end

-- UNIT_COMBO_POINTS isn't posted even thought we lose combo points.
function handlerFrame:PLAYER_ENTERING_WORLD()
  local newCP = _G.UnitPower("player", 4)
  comboPointFrame:update(newCP)
end

------------------------------------------------------------------------------------------------------------------------
local options = {
  type = "group",
  name = "Options",
  args = {
    general = {
      type = "group",
      name = "General",
      order = 100,
      args = {
        toggleLock = {
          type = "toggle",
          name = "Lock Frame",
          desc = "Enable to prevent dragging of the combo point frame.",
          set = function(info, val)
            comboPointFrame:EnableMouse(not val)
            comboPointFrame:SetMovable(not val)
            comboPointFrame:RegisterForDrag(not val and "LeftButton" or nil)
            db.global.lock = val
          end,
          get = function(info) return db.global.lock end,
          order = 100,
        },
        enableSound = {
          type = "toggle",
          name = "Enable Sound",
          desc = "Play a sound when reaching 5 combo points.",
          set = function(info, val)
            db.global.sound = val
          end,
          get = function(info) return db.global.sound end,
          order = 110,
        },
      },
    },
  },
}

AceConfig:RegisterOptionsTable("PrimalComboPoints", options)

AceConfigDialog:SetDefaultSize("PrimalComboPoints", 480, 360)
------------------------------------------------------------------------------------------------------------------------

-- http://www.wowace.com/addons/ace3/pages/api/ace-addon-3-0/
function PrimalComboPoints:OnInitialize()
  _G.assert(_G.MAX_COMBO_POINTS and _G.MAX_COMBO_POINTS == 5)

  do -- http://www.wowace.com/addons/ace3/pages/api/ace-db-3-0/
    local defaults = {
      global = {
        sound = true,
        lock = false,
      },
    }
    self.db = _G.LibStub("AceDB-3.0"):New("PrimalComboPointsDB", defaults, true)
  end

  if not (db.global.xOffset and db.global.yOffset) then
    comboPointFrame:SetPoint("CENTER", 0, 0)
  else
    comboPointFrame:SetPoint("BOTTOMLEFT", db.global.xOffset, db.global.yOffset)
  end

  if not db.global.lock then
    comboPointFrame:EnableMouse(true)
    comboPointFrame:SetMovable(true)
    comboPointFrame:RegisterForDrag("LeftButton")
  end

  self:RegisterChatCommand("primalcombopoints", function() AceConfigDialog:Open("PrimalComboPoints") end)
  self:RegisterChatCommand("pcp", function() AceConfigDialog:Open("PrimalComboPoints") end)
end

-- http://www.wowace.com/addons/ace3/pages/api/ace-addon-3-0/
function PrimalComboPoints:OnEnable()
  handlerFrame:RegisterUnitEvent("UNIT_POWER", "player")
  handlerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
end

-- vim: tw=120 sts=2 sw=2 et
