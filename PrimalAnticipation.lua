PrimalAnticipation = LibStub("AceAddon-3.0"):NewAddon("PrimalAnticipation", "AceConsole-3.0")
local AceGUI = _G.LibStub("AceGUI-3.0")
PrimalAnticipation._G = _G
--PrimalAnticipation.__index = _G

setfenv(1, PrimalAnticipation)

local PrimalAnticipation = _G.PrimalAnticipation

local eventLog = ""
local lines = 0

-- TODO: Whenever we manage to get our actual combo points, assert they are the same as what we expected.

local function log(...)
  local string = ...
  if not string or string == "" then return end

  local time = _G.GetTime()
  if lines == 20 then
    eventLog = _G.string.sub(eventLog, (_G.select(2, _G.string.find(eventLog, "\n"))) + 1)
  else
    lines = lines + 1
  end
  eventLog = eventLog .. _G.string.format("%.3f: %s", time, string) .. "\n"
  --_G.print(_G.string.format("%.3f: %s", time, string), _G.select(2, ...))
end

local function saveError(errorMessage)
  --_G.assert(false, "Event log:\n" .. eventLog)
  if not errorMessage then
    errorMessage = "Error " .. (#db.global.errors + 1) .. "\n\nEvent log:\n" .. eventLog
  else
    errorMessage = "Error " .. (#db.global.errors + 1) .. "\n\n" .. errorMessage .. "\n\nEvent log:\n" .. eventLog
  end
  _G.table.insert(db.global.errors, errorMessage)
end

-- Set comboPoints to the actual combo points we have when we managed to get them. Save an error if that actually
-- changed comboPoints.
local function sync(actualCPs)

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
local anticipatedCPs     = 0   -- Number of combo points we THINK we'll have soon.
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
  if comboPoints > _G.MAX_COMBO_POINTS then saveError("comboPoints > MAX_COMBO_POINTS") end
  if anticipatedCPs > _G.MAX_COMBO_POINTS then saveError("anticipatedCPs > MAX_COMBO_POINTS") end

  local cPOnTarget = _G.GetComboPoints("player")
  _G.assert(cPOnTarget)

  if cPOnTarget ~= 0 and comboPoints ~= cPOnTarget then saveError() end

  for i = 1, _G.MAX_COMBO_POINTS - 1 do
    comboPointFrames[i]:SetBackdropColor(0, 0, 0, .25)
    comboPointFrames[i]:SetBackdropBorderColor(0, 0, 0)
  end
  if cPOnTarget <= anticipatedCPs then
    for i = 1, cPOnTarget do
      comboPointFrames[i]:SetBackdropColor(1, 1, 1, .75)
      comboPointFrames[i]:SetBackdropBorderColor(0, 0, 0)
    end
    for i = cPOnTarget + 1, anticipatedCPs do
      comboPointFrames[i]:SetBackdropColor(1, 1, 1, .35)
      comboPointFrames[i]:SetBackdropBorderColor(0, 0, 0)
    end
  else--[[if anticipatedCPs < cPOnTarget then]]
    for i = 1, cPOnTarget do
      comboPointFrames[i]:SetBackdropColor(.5, .5, .5, .25)
      comboPointFrames[i]:SetBackdropBorderColor(0, 0, 0)
    end
  end

  if anticipatedCPs == _G.MAX_COMBO_POINTS or cPOnTarget == _G.MAX_COMBO_POINTS then
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
  for i, pendingCPEvent in _G.ipairs(pendingCPEvents) do
    pendingCPEvent.expires = pendingCPEvent.expires - elapsed
    if pendingCPEvent.expires <= 0 then
      local spellId = pendingCPEvent.spellId
      if cPGenerators[spellId] or primalFury[spellId] then
        anticipatedCPs = anticipatedCPs - 1
      end
      _G.table.remove(pendingCPEvents, i)
      log("pendingCPEvent[" .. i .. "] expired")
      comboPointFrame:update()
    end
  end
  for i, cPEvent in _G.ipairs(cPEvents) do
    cPEvent.expires = cPEvent.expires - elapsed
    if cPEvent.expires <= 0 then -- TODO: what about the stuff that happened after this CPEvent was created?
      -- TODO: we have to redo everything that happened after this CPEvent was created.
      log("cPEvents[" .. i .. "] expired")
      if not cPEvent.resolved then
        comboTargetGUID = nil
        comboPoints = 0
        anticipatedCPs = 0
      end
      _G.table.remove(cPEvents, i)
      comboPointFrame:update()
    end
  end
end)

local timestamp

-- http://wowpedia.org/API_COMBAT_LOG_EVENT
function handlerFrame:COMBAT_LOG_EVENT_UNFILTERED(_, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, ...)
  -- We can get SPELL_CAST_SUCCESS but no SPELL_DAMAGE when the unit dies from white damage instantly. We still gain
  -- combo points in that case.
  if subEvent == "SPELL_CAST_SUCCESS" and sourceGUID == _G.UnitGUID("player") then
    local spellId, spellName = ...
    local debuggingOutput = ""

    -- It's inconsistent whether SPELL_CAST_SUCCESS or UNIT_COMBO_POINTS is posted first for Mangle (when Mangle is used
    -- while Prowling, UNIT_COMBO_POINTS appears to be posted first). For other combo moves UNIT_COMBO_POINTS is always
    -- posted first.
    if mangle[spellId] and not cPEvents[1] then
        debuggingOutput = debuggingOutput .. subEvent .. ", " .. spellId .. " (" .. spellName .. ")"
        _G.table.insert(pendingCPEvents, PendingCPEvent:new(destGUID, spellId))

    -- cPGenerators includes the spell ID for Mangle.
    elseif cPGenerators[spellId] and cPEvents[1] then
      debuggingOutput = debuggingOutput .. subEvent .. ", " .. spellId .. " (" .. spellName .. ")"
      debuggingOutput = debuggingOutput .. ", cPEvents[1] removed after " ..
                        _G.string.format("%.3f", (1 - cPEvents[1].expires))
      if not cPEvents[1].resolved then
        if not comboTargetGUID or destGUID ~= comboTargetGUID then
          comboTargetGUID = destGUID
          comboPoints = 1
          anticipatedCPs = 1
          comboPointFrame:update()
        elseif anticipatedCPs < _G.MAX_COMBO_POINTS then
          comboPoints = comboPoints + 1
          anticipatedCPs = anticipatedCPs + 1
          comboPointFrame:update()
        end
      end
      _G.table.remove(cPEvents, 1)

    elseif savageRoar[spellId] then -- SPELL_CAST_SUCCESS is posted before UNIT_COMBO_POINTS for Savage Roar.
      debuggingOutput = debuggingOutput .. subEvent .. ", " .. spellId .. " (" .. spellName .. ")"
      anticipatedCPs = 0
      _G.table.insert(pendingCPEvents, PendingCPEvent:new(destGUID, spellId))
      comboPointFrame:update()

    elseif swipe[spellId] then
      debuggingOutput = debuggingOutput .. subEvent .. ", " .. spellId .. " (" .. spellName .. ")"
      unitsSwiped = 0

    elseif pounce[spellId] then -- UNIT_COMBO_POINTS is posted before SPELL_CAST_SUCCESS for Pounce.
      if cPEvents[1] then
        comboTargetGUID = destGUID
        debuggingOutput = debuggingOutput .. ", cPEvents[1] removed after " ..
                          _G.string.format("%.3f", (1 - cPEvents[1].expires))
        if anticipatedCPs < _G.MAX_COMBO_POINTS then
          if not cPEvents[1].resolved then
            comboPoints = comboPoints + 1
            anticipatedCPs = anticipatedCPs + 1
          end
        end
        _G.table.remove(cPEvents, 1)
        comboPointFrame:update()
      else
        -- if not (false) then saveError() end
      end
    --[[
    elseif primalFury[spellId] then
      -- ...
    elseif comboPoint[spellId] then
      -- ...
    ]]
    end
    log(debuggingOutput)
  elseif subEvent == "SPELL_DAMAGE" and sourceGUID == _G.UnitGUID("player") then
    local spellId, spellName, _, _, _, _, _, _, _, critical = ...
    local debuggingOutput = ""
    if cPGenerators[spellId] then -- We got a hit with one of our single-target combo moves.
      debuggingOutput = debuggingOutput .. subEvent .. ", " .. spellId .. " (" .. spellName .. ")" ..
                        (critical and ", critical" or "")
      if mangle[spellId] then
        for i, pendingCPEvent in _G.ipairs(pendingCPEvents) do
          if mangle[pendingCPEvent.spellId] then
            if not comboTargetGUID or destGUID ~= comboTargetGUID then
              anticipatedCPs = 1
              comboPointFrame:update()
            elseif anticipatedCPs < _G.MAX_COMBO_POINTS then
              anticipatedCPs = anticipatedCPs + 1
              comboPointFrame:update()
            end
          end
        end
      end
      if critical then
        _G.table.insert(pendingCPEvents, PendingCPEvent:new(destGUID, 16953 --[[ Primal Fury ]]))
        if anticipatedCPs < _G.MAX_COMBO_POINTS then
          anticipatedCPs = anticipatedCPs + 1
          comboPointFrame:update()
        end
      end
      log(debuggingOutput)
    -- When we have no target and hit several units with Swipe a UNIT_COMBO_POINTS event is posted for each, but the one
    -- we hit first will be our combo target. UNIT_COMBO_POINTS is posted before SPELL_DAMAGE for Swipe.
    elseif swipe[spellId] then
      debuggingOutput = subEvent .. ", " .. spellId .. " (" .. spellName .. ")"
      if comboTargetGUID then
        if destGUID == comboTargetGUID then -- We hit our combo target with Swipe.
          debuggingOutput = debuggingOutput .. (destGUID == comboTargetGUID and ", combo target hit" or "")
          if cPEvents[1] then
            debuggingOutput = debuggingOutput .. ", cPEvents[1] removed after " ..
                              _G.string.format("%.3f", (1 - cPEvents[1].expires))
            if anticipatedCPs < _G.MAX_COMBO_POINTS and not cPEvents[1].resolved then
              debuggingOutput = debuggingOutput .. ", applied"
              comboPoints = comboPoints + 1
              anticipatedCPs = anticipatedCPs + 1
            else
              debuggingOutput = debuggingOutput .. ", discarded"
            end
            _G.table.remove(cPEvents, 1)
            log(debuggingOutput)
            comboPointFrame:update()
          else
            log(debuggingOutput)
          end
        -- We hit a unit that isn't our combo target but the same Swipe added the first combo point to our combo target.
        elseif comboPoints == 1 and --[[timestamp and timestamp == _G.GetTime()]] unitsSwiped > 0 then
          if cPEvents[1] then
            debuggingOutput = debuggingOutput .. ", cPEvents[1] removed after " ..
                              _G.string.format("%.3f", (1 - cPEvents[1].expires))
            _G.table.remove(cPEvents, 1)
          end
          log(debuggingOutput)
        else
          log(debuggingOutput)
        end
      else--[[if not comboTargetGUID then]]
        if cPEvents[1] then
          comboTargetGUID = destGUID
          debuggingOutput = debuggingOutput .. ", combo target acquired, cPEvents[1] removed after " ..
                            _G.string.format("%.3f", (1 - cPEvents[1].expires))
          if not cPEvents[1].resolved then
            debuggingOutput = debuggingOutput .. ", applied"
            comboPoints = 1
            anticipatedCPs = 1
            --timestamp = _G.GetTime()
          end
          _G.table.remove(cPEvents, 1)
          comboPointFrame:update()
        end
        log(debuggingOutput)
      end
      unitsSwiped = unitsSwiped + 1
    -- UNIT_COMBO_POINTS is posted before SPELL_DAMAGE for Ferocious Bite and Main. For finishers, we can never directly
    -- resolve UNIT_COMBO_POINTS.
    elseif ferociousBite[spellId] or maim[spellId] then
      debuggingOutput = subEvent .. ", " .. spellId .. " (" .. spellName .. ")"
      if cPEvents[1] then
        debuggingOutput = debuggingOutput .. ", cPEvents[1] removed after " ..
                          _G.string.format("%.3f", (1 - cPEvents[1].expires))
        if not cPEvents[1].resolved then
          comboTargetGUID = nil
          comboPoints = 0
          anticipatedCPs = 0
        end
        _G.table.remove(cPEvents, 1)
        comboPointFrame:update()
      else
        if not (false) then saveError() end
      end
      log(debuggingOutput)
    end

  elseif subEvent == "SPELL_MISSED" and sourceGUID == _G.UnitGUID("player") then
    local spellId, spellName, _, missType = ...
    if missType == "ABSORB" or missType == "BLOCK" then return end -- http://wowpedia.org/COMBAT_LOG_EVENT#Miss_type
    local debuggingOutput = ""
    if mangle[spellId] then
      debuggingOutput = debuggingOutput .. subEvent .. ", " .. spellId .. " (" .. spellName .. "), " .. missType
      for i, pendingCPEvent in _G.ipairs(pendingCPEvents) do
        if mangle[pendingCPEvent.spellId] then
          debuggingOutput = debuggingOutput .. ", pendingCPEvents[" .. i .. "] removed after " ..
                            _G.string.format("%.3f", (1 - pendingCPEvent.expires))
          _G.table.remove(pendingCPEvents, i)
          break
        end
      end
      log(debuggingOutput)
    elseif cPGenerators[spellId] then
      debuggingOutput = debuggingOutput .. subEvent .. ", " .. spellId .. " (" .. spellName .. "), " .. missType
      -- ...
      log(debuggingOutput)
    end

  elseif (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH") and sourceGUID == _G.UnitGUID("player")
  then
    local spellId, spellName, _, _, _ = ...
    debuggingOutput = subEvent .. ", " .. spellId .. " (" .. spellName .. ")"
    -- By checking for Pounce Bleed instead or Pouce we don't run into trouble when the target has full Stun DR.
    -- UNIT_COMBO_POINTS is posted before SPELL_AURA_APPLIED and SPELL_AURA_REFRESH for Pounce (Bleed).
    if pounceBleed[spellId] then
      -- ...
      log(debuggingOutput)
    elseif rip[spellId] then -- UNIT_COMBO_POINTS is posted before SPELL_AURA_APPLIED and SPELL_AURA_REFRESH for Rip.
      if cPEvents[1] then
        debuggingOutput = debuggingOutput .. ", cPEvents[1] removed after " ..
                          _G.string.format("%.3f", (1 - cPEvents[1].expires))
        if not cPEvents[1].resolved then
          comboTargetGUID = nil
          comboPoints = 0
          anticipatedCPs = 0
        end
        _G.table.remove(cPEvents, 1)
        comboPointFrame:update()
        log(debuggingOutput)
      else
        log(debuggingOutput)
        if not (false) then saveError() end
      end
    end
  -- If the combo target is dead (and we don't target it) Swipe can acquire a new combo target.
  elseif subEvent == "UNIT_DIED" or subEvent == "UNIT_DESTROYED" then
    if comboTargetGUID and comboTargetGUID == destGUID then
      comboTargetGUID = nil
    end
  end
end

function handlerFrame:UNIT_COMBO_POINTS(unit)
  if not (unit == "player") then saveError() end

  local debuggingOutput = ""
  local resolved = false

  for _, unitID in _G.ipairs(unitIDs) do
    if _G.UnitExists(unitID) then
      local comboPointsOnUnit = _G.GetComboPoints("player", unitID)
      if comboPointsOnUnit > 0 then -- We have combo points on this unit.
        if not _G.UnitIsDead(unitID) then
          debuggingOutput = debuggingOutput .. ", combo target acquired"
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
    local destGUID, spellId = pendingCPEvent.destGUID, pendingCPEvent.spellId
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
        debuggingOutput = debuggingOutput .. ", combo target acquired"
        comboTargetGUID = destGUID
      end
    elseif finishers[spellId] then
      comboTargetGUID = nil
      comboPoints = 0
    else
      saveError()
    end
    _G.table.remove(pendingCPEvents, 1)
    resolved = true
  else
    _G.table.insert(cPEvents, CPEvent:new(resolved))
  end

  if not pendingCPEvents[1] then
    anticipatedCPs = comboPoints
  end

  if not resolved then
    debuggingOutput = debuggingOutput .. ", failed to resolve"
  end

  comboPointFrame:update()
  log("UNIT_COMBO_POINTS" .. debuggingOutput)
end

-- Swiping a unit may cause us to acquire it as a target after UNIT_COMBO_POINTS and SPELL_CAST_SUCCESS but before
-- SPELL_DAMAGE. In that case we resolve the UNIT_COMBO_POINTS event here.
function handlerFrame:PLAYER_TARGET_CHANGED(cause)
  local unit = "target"
  local debuggingOutput = ""
  local comboPointsOnUnit = _G.GetComboPoints("player", unit)
  if comboPointsOnUnit > 0 then
    comboPoints = comboPointsOnUnit
    if not _G.UnitIsDead(unit) and (not comboTargetGUID or comboTargetGUID ~= _G.UnitGUID(unit)) then
      debuggingOutput = debuggingOutput .. ", combo target acquired"
      comboTargetGUID = _G.UnitGUID(unit)
    end
    if not pendingCPEvents[1] then
      anticipatedCPs = comboPoints
    end
    for i, cPEvent in _G.ipairs(cPEvents) do
      cPEvent.resolved = true
      debuggingOutput = debuggingOutput .. ", cPEvents[" .. i .. "] resolved after " ..
                        _G.string.format("%.3f", (1 - cPEvent.expires))
    end
    if debuggingOutput ~= "" then log("PLAYER_TARGET_CHANGED" .. debuggingOutput) end
  end
  comboPointFrame:update() -- We want to also update the display when we lost our target.
end

function handlerFrame:PLAYER_FOCUS_CHANGED()
  local unit = "focus"
  local debuggingOutput = ""
  local comboPointsOnUnit = _G.GetComboPoints("player", unit)
  if comboPointsOnUnit > 0 then
    comboPoints = comboPointsOnUnit
    if not _G.UnitIsDead(unit) and (not comboTargetGUID or comboTargetGUID ~= _G.UnitGUID(unit)) then
      debuggingOutput = debuggingOutput .. ", combo target acquired"
      comboTargetGUID = _G.UnitGUID(unit)
    end
    if not pendingCPEvents[1] then
      anticipatedCPs = comboPoints
    end
    for i, cPEvent in _G.ipairs(cPEvents) do
      cPEvent.resolved = true
      debuggingOutput = debuggingOutput .. ", cPEvents[" .. i .. "] resolved after " ..
                        _G.string.format("%.3f", (1 - cPEvent.expires))
    end
    if debuggingOutput ~= "" then log("PLAYER_FOCUS_CHANGED" .. debuggingOutput) end
    comboPointFrame:update()
  end
end

function handlerFrame:UPDATE_MOUSEOVER_UNIT()
  local unit = "mouseover"
  local debuggingOutput = ""
  local comboPointsOnUnit = _G.GetComboPoints("player", unit)
  if comboPointsOnUnit > 0 then
    comboPoints = comboPointsOnUnit
    if not _G.UnitIsDead(unit) and (not comboTargetGUID or comboTargetGUID ~= _G.UnitGUID(unit)) then
      debuggingOutput = debuggingOutput .. ", combo target acquired"
      comboTargetGUID = _G.UnitGUID(unit)
    end
    if not pendingCPEvents[1] then
      anticipatedCPs = comboPoints
    end
    for i, cPEvent in _G.ipairs(cPEvents) do
      cPEvent.resolved = true
      debuggingOutput = debuggingOutput .. ", cPEvents[" .. i .. "] resolved after " ..
                        _G.string.format("%.3f", (1 - cPEvent.expires))
    end
    if debuggingOutput ~= "" then log("UPDATE_MOUSEOVER_UNIT" .. debuggingOutput) end
    comboPointFrame:update()
  end
end

function handlerFrame:ARENA_OPPONENT_UPDATE(unit, eventType)
  local debuggingOutput = ""
  local comboPointsOnUnit = _G.GetComboPoints("player", unit)
  if comboPointsOnUnit > 0 then
    comboPoints = comboPointsOnUnit
    if not _G.UnitIsDead(unit) and (not comboTargetGUID or comboTargetGUID ~= _G.UnitGUID(unit)) then
      debuggingOutput = debuggingOutput .. ", combo target acquired"
      comboTargetGUID = _G.UnitGUID(unit)
    end
    if not pendingCPEvents[1] then
      anticipatedCPs = comboPoints
    end
    for i, cPEvent in _G.ipairs(cPEvents) do
      cPEvent.resolved = true
      debuggingOutput = debuggingOutput .. ", cPEvents[" .. i .. "] resolved after " ..
                        _G.string.format("%.3f", (1 - cPEvent.expires))
    end
    if debuggingOutput ~= "" then log("ARENA_OPPONENT_UPDATE" .. debuggingOutput) end
    comboPointFrame:update()
  end
end

function handlerFrame:PLAYER_ENTERING_WORLD()
  comboTargetGUID = nil
  comboPoints = 0
  anticipatedCPs = 0
  comboPointFrame:update()
end

------------------------------------------------------------------------------------------------------------------------
local AceConfig = _G.LibStub("AceConfig-3.0")

local options = {
  type = "group",
  name = "PrimalAnticipation Options",
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
    },
    errors = {
      type = "group",
      name = "Errors",
      order = 200,
      childGroups = "select",
      args = {
        errorNumber = {
          type = "range",
          name = "",
          order = 100,
          min = 0,
          max = 100,
          step = 1,
        },
        errorMessage = {
          type = "input",
          name = "",
          order = 200,
          width = "full",
          multiline = 20,
        },
      },
    },
  },
}

AceConfig:RegisterOptionsTable("PrimalAnticipation", options)

local AceConfigDialog = _G.LibStub("AceConfigDialog-3.0")
AceConfigDialog:SetDefaultSize("PrimalAnticipation", 480, 360)

local function toggleOptionsUI()
  --AceConfigDialog:Open("PrimalAnticipation")
  local frame = AceGUI:Create("Frame")
  frame:SetTitle("PrimalAnticipation Options")
  frame:SetCallback("OnClose", function(widget) AceGUI:Release(widget) end)
  frame:SetLayout("Fill")

  local tab = AceGUI:Create("TabGroup")
  tab:SetLayout("Flow")
  tab:SetTabs({
    { text = "General", value = "general" },
    { text = "Errors", value = "errors" },
  })
  tab:SetCallback("OnGroupSelected", function(container, event, group)
    container:ReleaseChildren()
    if group == "general" then
      -- ...
    elseif group == "errors" then
      local i = 1
      local previousButton= AceGUI:Create("Button")
      local deleteButton= AceGUI:Create("Button")
      local nextButton = AceGUI:Create("Button")
      --local errorGroup = AceGUI:Create("InlineGroup")
      --local errorBox = AceGUI:Create("Label")
      local errorBox = AceGUI:Create("MultiLineEditBox")
      previousButton:SetText("Previous")
      previousButton:SetRelativeWidth(0.3)
      previousButton:SetCallback("OnClick", function()
        if i > 1 then
          i = i - 1
          --errorBox:SetLabel(i)
          deleteButton:SetText("Delete (" .. i .. "/" .. #db.global.errors .. ")")
          errorBox:SetText(db.global.errors[i] or "")
        end
      end)
      deleteButton:SetText("Delete (" .. i .. "/" .. #db.global.errors .. ")")
      deleteButton:SetRelativeWidth(0.4)
      deleteButton:SetCallback("OnClick", function()
        if i > 0 then
          _G.table.remove(db.global.errors, i)
          if i > 1 and i > #db.global.errors then
            i = i - 1
            --errorBox:SetLabel(i)
            deleteButton:SetText("Delete (" .. i .. "/" .. #db.global.errors .. ")")
          end
          errorBox:SetText(db.global.errors[i] or "")
        end
      end)
      nextButton:SetText("Next")
      nextButton:SetRelativeWidth(0.3)
      nextButton:SetCallback("OnClick", function()
        if i < #db.global.errors then
          i = i + 1
          --errorBox:SetLabel(i)
          deleteButton:SetText("Delete (" .. i .. "/" .. #db.global.errors .. ")")
          errorBox:SetText(db.global.errors[i] or "")
        end
      end)
      --errorGroup:SetLayout("Fill")
      --errorGroup:SetHeight(1024)
      --errorGroup:AddChild(errorBox)
      --errorBox:SetFont("Fonts\\FRIZQT__.TTF", 13)
      --errorBox:SetFont("Fonts\\ARIALN.TTF", 13)
      --errorBox:SetDisabled(true)
      --errorBox:EnableKeyboard(false)
      errorBox:DisableButton(true)
      errorBox:SetLabel("")
      errorBox:SetText(db.global.errors[1] or "")
      errorBox:SetCallback("OnTextChanged", function(self, text)
        self:SetText(db.global.errors[1] or "")
      end)
      errorBox:SetFullWidth(true)
      errorBox:SetFullHeight(true)
      container:AddChild(previousButton)
      container:AddChild(deleteButton)
      container:AddChild(nextButton)
      container:AddChild(errorBox)
      --errorGroup:SetPoint("BOTTOM", previousButton, "TOP")
      container:SetLayout("Flow")
    end
  end)
  tab:SelectTab("general")
  frame:AddChild(tab)
end
------------------------------------------------------------------------------------------------------------------------

-- http://www.wowace.com/addons/ace3/pages/api/ace-addon-3-0/
function PrimalAnticipation:OnInitialize()
  if not (_G.MAX_COMBO_POINTS and _G.MAX_COMBO_POINTS == 5) then saveError() end
  do -- http://www.wowace.com/addons/ace3/pages/api/ace-db-3-0/
    local defaults = {
      global = {
        sound = true,
        lock = false,
        errors = {},
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
