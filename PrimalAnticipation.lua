PrimalAnticipation = LibStub("AceAddon-3.0"):NewAddon("PrimalAnticipation", "AceConsole-3.0")
PrimalAnticipation._G = _G

setfenv(1, PrimalAnticipation)

local PrimalAnticipation = _G.PrimalAnticipation

local function print(...)
  --_G.print(...)
end

mangle = {
  [33876] = true,
}

pounce = {
  [9005]   = true, -- Pounce
  [102546] = true, -- Pounce (Incarnation)
}

pounceBleed = {
  [9007] = true,
}

cPGenerators = {
  [1822]   = true, -- Rake
  [5221]   = true, -- Shred
  [6785]   = true, -- Ravage
  [9005]   = true, -- Pounce
  [33876]  = true, -- Mangle
  [102545] = true, -- Ravage!
  [102546] = true, -- Pounce (Incarnation)
  [114236] = true, -- Shred!
}

rip = {
  [1079] = true, -- Rip
}

ferociousBite = {
  [22568] = true,
}

maim = {
  [22570] = true,
}

savageRoar = {
  [52610]  = true,
  [127538] = true, -- Glyphed
}

finishers = {
  [1079]   = true, -- Rip
  [22568]  = true, -- Ferocious Bite
  [22570]  = true, -- Maim
  [52610]  = true, -- Savage Roar
  [127538] = true, -- Savage Roar (glyphed)
}
swipe = {
  [62078] = true,
}
primalFury = {
  [16953] = true,
}
redirect = {
  [110730] = true, -- Symbiosis
}
comboPoint = {
  [139546] = true, -- http://www.wowhead.com/spell=138352
}

-- We can GetComboPoints() on any unit we have a unitID for. These are the units we try.
local unitIDs = {"target", "focus", "mouseover", "arena1", "arena2", "arena3", "arena4", "arena5"}

-- State ---------------------------------------------------------------------------------------------------------------
local comboTargetGUID    = nil -- GUID of the unit we ASSUME to be our combo target. We may have a combo target that has
                               -- no unitID. The combo target is the unique unit we have more than 0 combo points on.
local comboPoints        = 0   -- Number of combo points we THINK we have.
local pendingCPs         = 0   -- Number of combo points we THINK we'll have soon.
local unitsSwiped        = 0
local pendingCPEvents    = {}  -- Queue.
local cPEvents           = {}  -- Queue.
------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------------------------
local comboPointFrame = _G.CreateFrame("Frame", nil, _G.UIParent)
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

local comboPointFrames = {}

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

function comboPointFrame:update()
  local cPOnTarget = _G.GetComboPoints("player")
  _G.assert(cPOnTarget)

  if cPOnTarget ~= 0 and comboPoints ~= cPOnTarget then
    print("cPOnTarget: " .. cPOnTarget .. ", comboPoints: " .. comboPoints .. ", pendingCPs: " .. pendingCPs)
  end

  _G.assert(cPOnTarget == 0 or comboPoints == cPOnTarget)

  _G.assert(comboPoints <= _G.MAX_COMBO_POINTS)
  _G.assert(pendingCPs <= _G.MAX_COMBO_POINTS)

  for i = 1, _G.MAX_COMBO_POINTS - 1 do
    comboPointFrames[i]:SetBackdropColor(0, 0, 0, .25)
    comboPointFrames[i]:SetBackdropBorderColor(0, 0, 0)
  end
  if cPOnTarget <= pendingCPs then
    for i = 1, cPOnTarget do
      comboPointFrames[i]:SetBackdropColor(1, 1, 1, .75)
      comboPointFrames[i]:SetBackdropBorderColor(0, 0, 0)
    end
    for i = cPOnTarget + 1, pendingCPs do
      comboPointFrames[i]:SetBackdropColor(.75, .75, .75, .5)
      comboPointFrames[i]:SetBackdropBorderColor(0, 0, 0)
    end
  else--[[if pendingCPs < cPOnTarget then]]
    for i = 1, cPOnTarget do
      comboPointFrames[i]:SetBackdropColor(.75, .75, .75, .5)
      comboPointFrames[i]:SetBackdropBorderColor(0, 0, 0)
    end
  end

  if pendingCPs == _G.MAX_COMBO_POINTS or cPOnTarget == _G.MAX_COMBO_POINTS then
    if not comboPointFrames[5]:IsShown() then
      if db.global.sound then
        local file = [[Interface\AddOns\PrimalAnticipation\media\sounds\noisecrux\vio]] .. _G.math.random(10) .. ".ogg"
        _G.PlaySoundFile(file, "Master")
      end
      comboPointFrames[5]:Show()
    end
  else
    comboPointFrames[5]:Hide()
  end
end

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
------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------------------------
-- Prototype.
local PendingCPEvent = {
  expires = 1, -- Expires after a second.
}

PendingCPEvent.__index = PendingCPEvent

function PendingCPEvent:new(destGUID, spellId)
  local object = _G.setmetatable({}, PendingCPEvent)
  object.destGUID = destGUID
  object.spellId = spellId
  return object
end

-- Prototype. Created in response to UNIT_COMBO_POINTS and deleted once we see (what we assume to be) the corresponding
-- COMBAT_LOG_EVENT_UNFILTERED.
local CPEvent = {
  expires = 1, -- Expires after a second.
}

CPEvent.__index = CPEvent

function CPEvent:new(resolved)
  local object = _G.setmetatable({}, CPEvent)
  object.resolved = resolved
  return object
end
------------------------------------------------------------------------------------------------------------------------

local handlerFrame = _G.CreateFrame("Frame")

handlerFrame:SetScript("OnEvent", function(self, event, ...)
  return self[event](self, ...)
end)

handlerFrame:SetScript("OnUpdate", function(self, elapsed)
  --_G.assert(not pendingCPEvents[1] or not cPEvents[1]) -- TODO: this should hold, right?
  for i, pendingCPEvent in _G.ipairs(pendingCPEvents) do
    pendingCPEvent.expires = pendingCPEvent.expires - elapsed
    if pendingCPEvent.expires <= 0 then
      local spellId = pendingCPEvent.spellId
      if cPGenerators[spellId] or primalFury[spellId] then
        pendingCPs = pendingCPs - 1
      end
      _G.table.remove(pendingCPEvents, i)
      print("pendingCPEvent[" .. i .. "] expired")
      comboPointFrame:update()
    end
  end
  for i, cPEvent in _G.ipairs(cPEvents) do
    cPEvent.expires = cPEvent.expires - elapsed
    if cPEvent.expires <= 0 then
      print("cPEvents[" .. i .. "] expired")
      if not cPEvent.resolved then
        comboTargetGUID = nil
        comboPoints = 0
        pendingCPs = 0
      end
      _G.table.remove(cPEvents, i)
      comboPointFrame:update()
    end
  end
end)

local timestamp

-- http://wowpedia.org/API_COMBAT_LOG_EVENT
function handlerFrame:COMBAT_LOG_EVENT_UNFILTERED(_, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, ...)
  if subEvent == "SPELL_CAST_SUCCESS" and sourceGUID == _G.UnitGUID("player") then
    local spellId, spellName, _ = ...
    local debuggingOutput = ""
    if savageRoar[spellId] then
      debuggingOutput = debuggingOutput .. subEvent .. ", " .. spellId .. " (" .. spellName .. ")"
      pendingCPs = 0
      _G.table.insert(pendingCPEvents, PendingCPEvent:new(destGUID, spellId))
      comboPointFrame:update()
      print(debuggingOutput)
    elseif swipe[spellId] then
      debuggingOutput = debuggingOutput .. subEvent .. ", " .. spellId .. " (" .. spellName .. ")"
      unitsSwiped = 0
      print(debuggingOutput)
    --[[
    elseif pounce[spellId] then
      -- ...
    ]]
    --[[
    elseif primalFury[spellId] then
      -- ...
    elseif comboPoint[spellId] then
      -- ...
    ]]
    end
  elseif subEvent == "SPELL_DAMAGE" and sourceGUID == _G.UnitGUID("player") then
    local spellId, spellName, _, _, _, _, _, _, _, critical = ...
    local debuggingOutput = ""
    if cPGenerators[spellId] then -- We got a hit with one of our single-target combo moves.
      debuggingOutput = debuggingOutput .. subEvent .. ", " .. spellId .. " (" .. spellName .. ")" ..
                        (critical and ", critical" or "")
      if mangle[spellId] then
        _G.assert(comboPoints)
        if not comboTargetGUID or destGUID ~= comboTargetGUID then
          pendingCPs = 1
          comboPointFrame:update()
        elseif pendingCPs < _G.MAX_COMBO_POINTS then
          pendingCPs = pendingCPs + 1
          comboPointFrame:update()
        end
        _G.table.insert(pendingCPEvents, PendingCPEvent:new(destGUID, spellId))
      else -- One UNIT_COMBO_POINTS event was posted at this point.
        if cPEvents[1] then
          _G.assert(not pendingCPEvents[1])
          debuggingOutput = debuggingOutput .. ", cPEvents[1] removed after " ..
                            _G.string.format("%.3f", (1 - cPEvents[1].expires))
          if not cPEvents[1].resolved then
            if not comboTargetGUID or destGUID ~= comboTargetGUID then
              comboTargetGUID = destGUID
              comboPoints = 1
              pendingCPs = 1
            elseif pendingCPs < _G.MAX_COMBO_POINTS then
              comboPoints = comboPoints + 1
              pendingCPs = pendingCPs + 1
            end
          end
          _G.table.remove(cPEvents, 1)
          comboPointFrame:update()
        end
      end
      if critical then
        _G.table.insert(pendingCPEvents, PendingCPEvent:new(destGUID, 16953 --[[ Primal Fury ]]))
        if pendingCPs < _G.MAX_COMBO_POINTS then
          pendingCPs = pendingCPs + 1
          comboPointFrame:update()
        end
      end
      print(debuggingOutput)
    -- When we have no target and hit several units with Swipe a UNIT_COMBO_POINTS event is posted for each, but the one
    -- we hit first will be our combo target. UNIT_COMBO_POINTS is posted before SPELL_DAMAGE for Swipe.
    elseif swipe[spellId] then
      debuggingOutput = subEvent .. ", " .. spellId .. " (" .. spellName .. ")"
      if comboTargetGUID then
        if destGUID == comboTargetGUID then -- We hit our combo target with Swipe.
          debuggingOutput = debuggingOutput .. (destGUID == comboTargetGUID and ", combo target hit" or "")
          if cPEvents[1] then
            _G.assert(not pendingCPEvents[1])
            debuggingOutput = debuggingOutput .. ", cPEvents[1] removed after " ..
                              _G.string.format("%.3f", (1 - cPEvents[1].expires))
            if pendingCPs < _G.MAX_COMBO_POINTS then
              if not cPEvents[1].resolved then
                debuggingOutput = debuggingOutput .. ", applied"
                comboPoints = comboPoints + 1
                pendingCPs = pendingCPs + 1
              end
            end
            _G.table.remove(cPEvents, 1)
            comboPointFrame:update()
          end
        -- We hit a unit that isn't our combo target but the same Swipe added the first combo point to our combo target.
        elseif comboPoints == 1 and --[[timestamp and timestamp == _G.GetTime()]] unitsSwiped > 0 then
          if cPEvents[1] then
            _G.assert(not pendingCPEvents[1])
            debuggingOutput = debuggingOutput .. ", cPEvents[1] removed after " ..
                              _G.string.format("%.3f", (1 - cPEvents[1].expires))
            _G.table.remove(cPEvents, 1)
          end
        end
      else--[[if not comboTargetGUID then]]
        if cPEvents[1] then
          _G.assert(not pendingCPEvents[1])
          comboTargetGUID = destGUID
          debuggingOutput = debuggingOutput .. ", combo target acquired, cPEvents[1] removed after " ..
                            _G.string.format("%.3f", (1 - cPEvents[1].expires))
          if not cPEvents[1].resolved then
            debuggingOutput = debuggingOutput .. ", applied"
            comboPoints = 1
            pendingCPs = 1
            --timestamp = _G.GetTime()
          end
          _G.table.remove(cPEvents, 1)
          comboPointFrame:update()
        end
      end
      unitsSwiped = unitsSwiped + 1
      print(debuggingOutput)
    -- UNIT_COMBO_POINTS is posted before SPELL_DAMAGE for Ferocious Bite and Main. For finishers, we can never directly
    -- resolve UNIT_COMBO_POINTS.
    elseif ferociousBite[spellId] or maim[spellId] then
      debuggingOutput = subEvent .. ", " .. spellId .. " (" .. spellName .. ")"
      if cPEvents[1] then
        _G.assert(not pendingCPEvents[1])
        debuggingOutput = debuggingOutput .. ", cPEvents[1] removed after " ..
                          _G.string.format("%.3f", (1 - cPEvents[1].expires))
        if not cPEvents[1].resolved then
          comboTargetGUID = nil
          comboPoints = 0
          pendingCPs = 0
        end
        _G.table.remove(cPEvents, 1)
        comboPointFrame:update()
      else
        _G.assert(false)
      end
      print(debuggingOutput)
    end
  elseif (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH") and sourceGUID == _G.UnitGUID("player")
  then
    local spellId, spellName, _, _, _ = ...
    debuggingOutput = subEvent .. ", " .. spellId .. " (" .. spellName .. ")"
    -- By checking for Pounce Bleed instead or Pouce we don't run into trouble when the target has full Stun DR.
    -- UNIT_COMBO_POINTS is posted before SPELL_AURA_APPLIED and SPELL_AURA_REFRESH for Pounce (Bleed).
    if pounceBleed[spellId] then
      if cPEvents[1] then
        _G.assert(not pendingCPEvents[1])
        comboTargetGUID = destGUID
        debuggingOutput = debuggingOutput .. ", cPEvents[1] removed after " ..
                          _G.string.format("%.3f", (1 - cPEvents[1].expires))
        if pendingCPs < _G.MAX_COMBO_POINTS then
          if not cPEvents[1].resolved then
            comboPoints = comboPoints + 1
            pendingCPs = pendingCPs + 1
          end
        end
        _G.table.remove(cPEvents, 1)
        comboPointFrame:update()
      else
        -- ...
      end
      print(debuggingOutput)
    elseif rip[spellId] then -- UNIT_COMBO_POINTS is posted before SPELL_AURA_APPLIED and SPELL_AURA_REFRESH for Rip.
      if cPEvents[1] then
        debuggingOutput = debuggingOutput .. ", cPEvents[1] removed after " ..
                          _G.string.format("%.3f", (1 - cPEvents[1].expires))
        if not cPEvents[1].resolved then
          comboTargetGUID = nil
          comboPoints = 0
          pendingCPs = 0
        end
        _G.table.remove(cPEvents, 1)
        comboPointFrame:update()
      else
        _G.assert(false)
      end
      print(debuggingOutput)
    end
  -- If the combo target is dead (and we don't target it) Swipe can acquire a new combo target.
  elseif subEvent == "UNIT_DIED" or subEvent == "UNIT_DESTROYED" then
    if comboTargetGUID and comboTargetGUID == destGUID then
      comboTargetGUID = nil
    end
  end
end

function handlerFrame:UNIT_COMBO_POINTS(unit)
  local debuggingOutput = ""
  local resolved = false

  for _, unitID in _G.ipairs(unitIDs) do
    if _G.UnitExists(unitID) then
      local comboPointsOnUnit = _G.GetComboPoints("player", unitID)
      if comboPointsOnUnit > 0 then -- We have combo points on this unit.
        if not _G.UnitIsDead(unitID) then
          comboTargetGUID = _G.UnitGUID(unitID)
        end
        comboPoints = comboPointsOnUnit
        resolved = true
        debuggingOutput = debuggingOutput .. ", resolved"
      -- Looks like that's not really the combo target. Might have been a finisher or we added a combo point to
      -- another unit. Or the combo target was dead long enough for our combo points to be purged.
      elseif _G.UnitGUID(unitID) == comboTargetGUID then
        comboTargetGUID = nil
        comboPoints = 0
      end
      break
    end
  end

  if pendingCPEvents[1] then
    local pendingCPEvent = pendingCPEvents[1]
    local destGUID = pendingCPEvent.destGUID
    local spellId = pendingCPEvent.spellId
    debuggingOutput = debuggingOutput .. ", for " .. pendingCPEvents[1].spellId .. ", after " ..
                      _G.string.format("%.3f", (1 - pendingCPEvents[1].expires))
    if mangle[spellId] or primalFury[spellId] then
      if not resolved then
        if not comboTargetGUID then
          comboPoints = 1
        elseif destGUID ~= comboTargetGUID then
          comboPoints = 1
        elseif comboPoints < _G.MAX_COMBO_POINTS then
          comboPoints = comboPoints + 1
        end
      end
      comboTargetGUID = destGUID
    elseif finishers[spellId] then
      comboTargetGUID = nil
      comboPoints = 0
    else
      _G.assert(nil)
    end
    _G.table.remove(pendingCPEvents, 1)
    resolved = true
  else
    _G.table.insert(cPEvents, CPEvent:new(resolved))
  end

  if not pendingCPEvents[1] then
    pendingCPs = comboPoints
  end

  if not resolved then
    --_G.table.insert(cPEvents, CPEvent:new(false))
    debuggingOutput = debuggingOutput .. ", failed to resolve"
  end

  comboPointFrame:update()
  print("UNIT_COMBO_POINTS" .. debuggingOutput)
end

function handlerFrame:PLAYER_TARGET_CHANGED(cause)
  local comboPointsOnUnit = _G.GetComboPoints("player", "target")
  if comboPointsOnUnit > 0 then
    if not _G.UnitIsDead("target") then
      comboTargetGUID = _G.UnitGUID("target")
    end
    comboPoints = comboPointsOnUnit
    if not pendingCPEvents[1] then
      pendingCPs = comboPoints
    end
  end
  comboPointFrame:update() -- We want to also update the display when we lost our target.
end

function handlerFrame:PLAYER_FOCUS_CHANGED()
  local comboPointsOnUnit = _G.GetComboPoints("player", "focus")
  if comboPointsOnUnit > 0 then
    if not _G.UnitIsDead("focus") then
      comboTargetGUID = _G.UnitGUID("focus")
    end
    comboPoints = comboPointsOnUnit
    if not pendingCPEvents[1] then
      pendingCPs = comboPoints
    end
    comboPointFrame:update()
  end
end

function handlerFrame:UPDATE_MOUSEOVER_UNIT()
  local comboPointsOnUnit = _G.GetComboPoints("player", "mouseover")
  if comboPointsOnUnit > 0 then
    if not _G.UnitIsDead("mouseover") then
      comboTargetGUID = _G.UnitGUID("mouseover")
    end
    comboPoints = comboPointsOnUnit
    if not pendingCPEvents[1] then
      pendingCPs = comboPoints
    end
    comboPointFrame:update()
  end
end

function handlerFrame:ARENA_OPPONENT_UPDATE(unit, eventType)
  local comboPointsOnUnit = _G.GetComboPoints("player", unit)
  if comboPointsOnUnit > 0 then
    if not _G.UnitIsDead(unit) then
      comboTargetGUID = _G.UnitGUID(unit)
    end
    comboPoints = comboPointsOnUnit
    if not pendingCPEvents[1] then
      pendingCPs = comboPoints
    end
    comboPointFrame:update()
  end
end

function handlerFrame:PLAYER_ENTERING_WORLD()
  comboTargetGUID = nil
  comboPoints = 0
  pendingCPs = 0
  comboPointFrame:update()
end

------------------------------------------------------------------------------------------------------------------------
local AceConfig = _G.LibStub("AceConfig-3.0")

local options = {
  type = "group",
  name = "PrimalAnticipation Options",
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
    toggleSound = {
      type = "toggle",
      name = "Toggle Sound",
      desc = "Play a sound when reaching 5 combo points.",
      set = function(info, val)
        db.global.sound = val
      end,
      get = function(info) return db.global.sound end,
      order = 110,
    },
  },
}

AceConfig:RegisterOptionsTable("PrimalAnticipation", options)

local AceConfigDialog = _G.LibStub("AceConfigDialog-3.0")
AceConfigDialog:SetDefaultSize("PrimalAnticipation", 480, 360)

local function toggleOptionsUI()
  AceConfigDialog:Open("PrimalAnticipation")
end
------------------------------------------------------------------------------------------------------------------------

-- http://www.wowace.com/addons/ace3/pages/api/ace-addon-3-0/
function PrimalAnticipation:OnInitialize()
  _G.assert(_G.MAX_COMBO_POINTS and _G.MAX_COMBO_POINTS == 5)
  do -- http://www.wowace.com/addons/ace3/pages/api/ace-db-3-0/
    local defaults = {
      global = {
        sound = true,
        lock = false,
      },
    }
    self.db = _G.LibStub("AceDB-3.0"):New("PrimalAnticipationDB", defaults, true)
  end

  if not (db.global.xOffset and db.global.yOffset) then
    comboPointFrame:SetPoint("CENTER", 0, 0)
  else
    comboPointFrame:SetPoint("BOTTOMLEFT", db.global.xOffset, db.global.yOffset)
  end

  self:RegisterChatCommand("primalanticipation", toggleOptionsUI)
  self:RegisterChatCommand("pa", toggleOptionsUI)
end

-- http://www.wowace.com/addons/ace3/pages/api/ace-addon-3-0/
function PrimalAnticipation:OnEnable()
  handlerFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  handlerFrame:RegisterUnitEvent("UNIT_COMBO_POINTS", "player")
  handlerFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
  handlerFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
  handlerFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
  handlerFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
  handlerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
end

-- vim: tw=120 sw=2 et
