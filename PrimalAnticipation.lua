PrimalAnticipation = LibStub("AceAddon-3.0"):NewAddon("PrimalAnticipation", "AceEvent-3.0", "AceConsole-3.0")
PrimalAnticipation._G = _G

setfenv(1, PrimalAnticipation)

local PrimalAnticipation = _G.PrimalAnticipation

local debug = true

local function print(...)
  if debug then _G.print(...) end
end

mangle = {
  [33876] = true,
}

pounce = {
  [9005]   = true, -- Pounce
  [102546] = true, -- Pounce (Incarnation)
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
  [1079]   = true, -- Rip
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
local pendingCPs         = 0   -- Number of combo points we didn't see a UNIT_COMBO_POINTS event for yet.
local pendingCPEvents    = {}  -- Queue.
local unresolvedCPEvents = {}  -- Queue.
------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------------------------
local comboPointFrame = _G.CreateFrame("Frame", nil, _G.UIParent)
comboPointFrame:SetSize(32, 32)

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
  local comboPoints = comboPoints
  local cPOnTarget = _G.GetComboPoints("player")
  _G.assert(cPOnTarget)

  if cPOnTarget ~= 0 and comboPoints ~= cPOnTarget then
    print("cPOnTarget: " .. cPOnTarget .. ", comboPoints: " .. comboPoints .. ", pendingCPs: " .. pendingCPs)
  end

  _G.assert(not cPOnTarget or cPOnTarget == 0 or comboPoints == cPOnTarget)

  if cPOnTarget == 0 then
    -- ...
  end

  local pendingCPs = 0
  for i, pendingCPEvent in _G.ipairs(pendingCPEvents) do
    if cPGenerators[pendingCPEvent.spellId] and pendingCPEvent.destGUID == comboTargetGUID then
      pendingCPs = pendingCPs + 1
    elseif finishers[pendingCPEvent.spellId] then
      pendingCPs = cPOnTarget -- These aren't actually combo points we think we're about to lose.
      comboPoints = 0
      cPOnTarget = 0
      break
    end
  end

  for i = 1, cPOnTarget do
    comboPointFrames[i]:SetBackdropColor(1, 1, 1, .75)
    comboPointFrames[i]:SetBackdropBorderColor(0, 0, 0)
  end
  for i = cPOnTarget + 1, comboPoints + pendingCPs do
    comboPointFrames[i]:SetBackdropColor(.75, .75, .75, .5)
    comboPointFrames[i]:SetBackdropBorderColor(0, 0, 0)
  end
  for i = comboPoints + pendingCPs + 1, _G.MAX_COMBO_POINTS - 1 do
    comboPointFrames[i]:SetBackdropColor(0, 0, 0, .25)
    comboPointFrames[i]:SetBackdropBorderColor(0, 0, 0)
  end
  if comboPoints + pendingCPs == _G.MAX_COMBO_POINTS then
    if not comboPointFrames[5]:IsShown() then
      if db.global.sound then
        local file = [[Interface\AddOns\PrimalAnticipation\media\sounds\noisecrux\vio]] .. _G.math.random(10) .. ".ogg"
        _G.assert(file)
        --[[_G.assert(]]_G.PlaySoundFile(file, "Master")--)
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

function PendingCPEvent:new(destGUID, spellId)
  local object = _G.setmetatable({}, { __index = self })
  object.destGUID = destGUID
  object.spellId = spellId
  return object
end

-- Prototype.
local UnresolvedCPEvent = {
  expires = 1,
}

function UnresolvedCPEvent:new()
  local object = _G.setmetatable({}, { __index = self })
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
      pendingCPs = pendingCPs - 1
      _G.table.remove(pendingCPEvents, i)
      print("pendingCPEvent[" .. i .. "] expired")
      comboPointFrame:update()
    end
  end
  for i, unresolvedCPEvent in _G.ipairs(unresolvedCPEvents) do
    unresolvedCPEvent.expires = unresolvedCPEvent.expires - elapsed
    if unresolvedCPEvent.expires <= 0 then
      _G.assert(i == 1)
      comboTargetGUID = nil
      comboPoints = 0
      _G.table.remove(unresolvedCPEvents, i)
      print("unresolvedCPEvents[" .. i .. "] expired")
      comboPointFrame:update()
    end
  end
end)

-- http://wowpedia.org/API_COMBAT_LOG_EVENT
function handlerFrame:COMBAT_LOG_EVENT_UNFILTERED(_, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, ...)
  if subEvent == "SPELL_CAST_SUCCESS" and sourceGUID == _G.UnitGUID("player") then
    local spellId, spellName, _ = ...
    if savageRoar[spellId] then
      print(subEvent .. ", " .. spellId .. " (" .. spellName .. ")")
      --comboTargetGUID = nil
      --comboPoints = 0
      _G.table.insert(pendingCPEvents, PendingCPEvent:new(destGUID, spellId))
      comboPointFrame:update()
    --[[
    elseif pounce[spellId] then
      print(subEvent .. ", " .. spellId .. " (" .. spellName .. ")")
    ]]
    --[[
    elseif cPGenerators[spellId] then
      print(subEvent, spellName, spellId)
      if mangle[spellId] then
        -- Mangle is weird. This combat event happens noticeably before the first combo point is added.  We could still
        -- get e.g. parried after this event happened. I'm guessing the combo target won't change in that scenario.
      end
    elseif finishers[spellId] then
      -- We could also speed this up, but it seems pointless.
      print(subEvent, spellName, spellId, "(" .. _G.GetComboPoints("player") .. " cp)")
    elseif swipe[spellId] then
      print(subEvent, spellName, spellId)
    elseif primalFury[spellId] then
      print(subEvent, spellName, spellId)
    elseif comboPoint[spellId] then
      print(subEvent, spellName, spellId)
    ]]
    end
  elseif subEvent == "SPELL_DAMAGE" and sourceGUID == _G.UnitGUID("player") then
    local spellId, spellName, _, _, _, _, _, _, _, critical = ...
    local debuggingOutput = ""
    if cPGenerators[spellId] then
      debuggingOutput = debuggingOutput .. subEvent .. ", " .. spellId .. " (" .. spellName .. ")" .. (critical and
                        ", critical" or "")
      print(debuggingOutput)
      -- We got a hit with one of our single-target combo moves.
      comboTargetGUID = destGUID
      --[[
      for _, unitID in _G.ipairs(unitIDs) do
        unitGUID = _G.UnitGUID(unitID)
        if unitGUID and unitGUID == destGUID then
          comboTarget = unitID
        end
      end
      ]]
      if mangle[spellId] then
        _G.assert(comboPoints)
        if comboPoints + pendingCPs < _G.MAX_COMBO_POINTS then
          pendingCPs = pendingCPs + 1
          comboPointFrame:update()
          _G.table.insert(pendingCPEvents, PendingCPEvent:new(destGUID, spellId))
        end
      else
        -- A combo point was added at this point.
      end
      if critical then
        if comboPoints + pendingCPs < _G.MAX_COMBO_POINTS then
          pendingCPs = pendingCPs + 1
          comboPointFrame:update()
          _G.table.insert(pendingCPEvents, PendingCPEvent:new(destGUID, spellId))
        end
      end
    -- When we have no target and hit several units with swipe a UNIT_COMBO_POINTS event is posted for each, but the one
    -- we hit first will be our combo target.
    elseif swipe[spellId] then
      debuggingOutput = subEvent .. ", " .. spellId .. " (" .. spellName .. ")"
      if comboTargetGUID then
        if destGUID == comboTargetGUID then -- We hit our combo target with Swipe.
          debuggingOutput = debuggingOutput .. (destGUID == comboTargetGUID and ", combo target" or "")
          if unresolvedCPEvents[1] then
            if comboPoints + pendingCPs < _G.MAX_COMBO_POINTS then
              debuggingOutput = debuggingOutput .. ", unresolvedCPEvents[1] removed after " ..
                                (1 - unresolvedCPEvents[1].expires)
              comboPoints = comboPoints + 1
              _G.table.remove(unresolvedCPEvents, 1)
              comboPointFrame:update()
              print(debuggingOutput)
            end
          end
        -- We hit a unit that isn't our combo target with swipe. We previously had no combo target because we have one
        -- combo point now; this means UNIT_COMBO_POINTS was posted for hitting this unit.
        elseif comboPoints == 1 then
            if unresolvedCPEvents[1] then
              debuggingOutput = debuggingOutput .. ", unresolvedCPEvents[1] removed after " ..
                                (1 - unresolvedCPEvents[1].expires)
              _G.table.remove(unresolvedCPEvents, 1)
              print(debuggingOutput)
            end
          end
      else--[[if not comboTargetGUID then]]
        comboTargetGUID = destGUID
        debuggingOutput = debuggingOutput .. (destGUID == comboTargetGUID and ", combo target" or "")
        if unresolvedCPEvents[1] then
          if comboPoints + pendingCPs < _G.MAX_COMBO_POINTS then
            debuggingOutput = debuggingOutput .. ", unresolvedCPEvents[1] removed after " ..
                              (1 - unresolvedCPEvents[1].expires)
            comboPoints = 1
            _G.table.remove(unresolvedCPEvents, 1)
            comboPointFrame:update()
            print(debuggingOutput)
          end
        end
      end
    elseif ferociousBite[spellId] or maim[spellId] then
      debuggingOutput = subEvent .. ", " .. spellId .. " (" .. spellName .. ")"
      if unresolvedCPEvents[1] then
        debuggingOutput = debuggingOutput .. ", unresolvedCPEvents[1] removed after " ..
                          (1 - unresolvedCPEvents[1].expires)
        _G.table.remove(unresolvedCPEvents, 1)
        comboTargetGUID = nil
        comboPoints = 0
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
    if pounce[spellId] then
      comboTargetGUID = destGUID
      if unresolvedCPEvents[1] and comboPoints + pendingCPs < _G.MAX_COMBO_POINTS then
        debuggingOutput = debuggingOutput .. ", unresolvedCPEvents[1] removed after " ..
                          (1 - unresolvedCPEvents[1].expires)
        comboPoints = comboPoints + 1
        _G.table.remove(unresolvedCPEvents, 1)
        comboPointFrame:update()
      else
        -- ...
      end
      print(debuggingOutput)
    elseif rip[spellId] then
      if unresolvedCPEvents[1] then
        debuggingOutput = debuggingOutput .. ", unresolvedCPEvents[1] removed after " ..
                          (1 - unresolvedCPEvents[1].expires)
        _G.table.remove(unresolvedCPEvents, 1)
        comboTargetGUID = nil
        comboPoints = 0
        comboPointFrame:update()
      else
        _G.assert(false)
      end
      print(debuggingOutput)
    end
  -- If the combo target is dead (and we don't target it) swipe can acquire a new combo target.
  elseif subEvent == "UNIT_DIED" or subEvent == "UNIT_DESTROYED" then
    if comboTargetGUID and comboTargetGUID == destGUID then
      comboTargetGUID = nil
    end
  end
end

function handlerFrame:UNIT_COMBO_POINTS(unit)
  local debuggingOutput = ""
  local resolved = false
  local comboTarget

  if pendingCPEvents[1] then
    local pendingCPEvent = pendingCPEvents[1]
    local spellId = pendingCPEvent.spellId
    debuggingOutput = debuggingOutput .. ", for " .. pendingCPEvents[1].spellId .. ", after " ..
      (1 - pendingCPEvents[1].expires)
    if cPGenerators[spellId] then
      pendingCPs = pendingCPs - 1
      comboPoints = comboPoints + 1
    elseif finishers[spellId] then
      comboTargetGUID = nil
      comboPoints = 0
    else
      _G.assert(nil)
    end
    _G.table.remove(pendingCPEvents, 1)
    resolved = true
  end

  for _, unitID in _G.ipairs(unitIDs) do
    if _G.UnitExists(unitID) then
      local comboPointsOnUnit = _G.GetComboPoints("player", unitID)
      if comboPointsOnUnit > 0 then -- We have combo points on this unit.
        comboTarget = unitID
        comboTargetGUID = _G.UnitGUID(unitID)
        comboPoints = comboPointsOnUnit
        if not resolved then
          resolved = true
          debuggingOutput = debuggingOutput .. ", resolved"
        end
        debuggingOutput = debuggingOutput .. ", \"" .. comboTarget .. "\" is combo target"
      -- Looks like that's not really the combo target. Might have been a finisher or we added a combo point to
      -- another unit. Or the combo target was dead long enough for our combo points to be purged.
      elseif _G.UnitGUID(unitID) == comboTargetGUID then
        comboTargetGUID = nil
        comboPoints = 0
      end
      break
    end
  end

  if not resolved then
    _G.table.insert(unresolvedCPEvents, UnresolvedCPEvent:new())
    debuggingOutput = debuggingOutput .. ", failed to resolve"
  end

  comboPointFrame:update()
  print("UNIT_COMBO_POINTS" .. debuggingOutput)
end

function handlerFrame:PLAYER_TARGET_CHANGED(cause)
  local comboPointsOnUnit = _G.GetComboPoints("player", "target")
  if comboPointsOnUnit > 0 then
    comboTargetGUID = _G.UnitGUID("target")
    comboPoints = comboPointsOnUnit
  end
  comboPointFrame:update()
end

function handlerFrame:PLAYER_FOCUS_CHANGED()
  local comboPointsOnUnit = _G.GetComboPoints("player", "focus")
  if comboPointsOnUnit > 0 then
    comboTargetGUID = _G.UnitGUID("focus")
    comboPoints = comboPointsOnUnit
  end
  comboPointFrame:update()
end

function handlerFrame:UPDATE_MOUSEOVER_UNIT()
  local comboPointsOnUnit = _G.GetComboPoints("player", "mouseover")
  if comboPointsOnUnit > 0 then
    comboTargetGUID = _G.UnitGUID("mouseover")
    comboPoints = comboPointsOnUnit
  end
  comboPointFrame:update()
end

function handlerFrame:ARENA_OPPONENT_UPDATE(unit, eventType)
  -- TODO: only handle for some values of eventType?
  local comboPointsOnUnit = _G.GetComboPoints("player", unit)
  if comboPointsOnUnit > 0 then
    comboTargetGUID = _G.UnitGUID(unit)
    comboPoints = comboPointsOnUnit
  end
  comboPointFrame:update()
end

function handlerFrame:PLAYER_ENTERING_WORLD()
  comboTargetGUID = nil
  comboPoints = 0
end

-- http://www.wowace.com/addons/ace3/pages/api/ace-addon-3-0/
function PrimalAnticipation:OnInitialize()
  _G.assert(_G.MAX_COMBO_POINTS and _G.MAX_COMBO_POINTS == 5)
  do -- http://www.wowace.com/addons/ace3/pages/api/ace-db-3-0/
    local defaults = {
      global = {
        sound = true,
        xOffset = 0,
        yOffset = 334,
      },
    }
    self.db = _G.LibStub("AceDB-3.0"):New("PrimalAnticipationDB", defaults, true)
  end

  comboPointFrame:SetPoint("BOTTOM", self.db.global.xOffset, self.db.global.yOffset)
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
