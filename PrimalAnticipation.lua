-- TODO: we should probably clear the saved errors sometimes and set a maximum amount.

-- We lose combo points when missing with Maim now... hopefully a bug. TODO: make changes so the AddOn doesn't break
-- when that happens without a target.

-- TODO: don't raise an error when we figured out how many combo points we have initially.

-- TODO: only wait until the next frame after SPELL_DAMAGE is posted for Swipe before the ComboPointsChange can be
-- removed again.

--PrimalAnticipation = setmetatable({}, { __index = _G })
PrimalAnticipation = LibStub("AceAddon-3.0"):NewAddon("PrimalAnticipation", "AceConsole-3.0")
--setmetatable(PrimalAnticipation, { __index = _G })
PrimalAnticipation._G = _G

setfenv(1, PrimalAnticipation)

local PrimalAnticipation = _G.PrimalAnticipation
local AceGUI = _G.LibStub("AceGUI-3.0")
local AceConfig = _G.LibStub("AceConfig-3.0")
local AceConfigDialog = _G.LibStub("AceConfigDialog-3.0")

local optionsFrame, optionsFrameTabGroup, logBox
local comboPointFrame = _G.CreateFrame("Frame", nil, _G.UIParent)

log = nil

shred = {
  [5221] = true,
}
rake = {
  [1822] = true,
}
moonfire = {
  [155625] = true, -- TODO.
}
swipe = {
  [106785] = true,
}
primalFury = {
  [16953] = true,
}
cPGenerators = {
  [1822]   = true, -- Rake
  [5221]   = true, -- Shred
  [155625] = true, -- TODO: confirm
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
}
finishers = {
  [1079]   = true, -- Rip
  [22568]  = true, -- Ferocious Bite
  [22570]  = true, -- Maim
  [52610]  = true, -- Savage Roar
}
--[[
comboPoint = {
  [139546] = true, -- http://www.wowhead.com/spell=138352
}
]]

-- We can GetComboPoints() on any unit we have a unitID for. These are the units we try.
local unitIDs = { "target", "focus", "mouseover", "arena1", "arena2", "arena3", "arena4", "arena5" }

-- State ---------------------------------------------------------------------------------------------------------------
local comboPoints -- Number of combo points we THINK we have.
local cPChange
local oOCTime = _G.GetTime()
------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------------------------
-- Prototype. Created in response to SPELL_CAST_SUCCESS and updated with information from SPELL_DAMAGE,
-- UNIT_COMBO_POINTS, etc. Removed once fully resolved or after one second expires. Corresponds to at most one
-- UNIT_COMBO_POINTS event.
local ComboPointsChange = {
  expires = .5,
  --spellId = nil,
  --critical = nil,
  --SPELL_CAST_SUCCESS = nil, -- Value of GetTime() when SPELL_CAST_SUCCESS fired.
  --UNIT_COMBO_POINTS = nil, -- Value of GetTime() when UNIT_COMBO_POINTS fired.
  --SPELL_MISSED = nil,
  --SPELL_AURA_APPLIED = nil,
  --SPELL_AURA_REFRESH = nil,
}

ComboPointsChange.__index = ComboPointsChange

function ComboPointsChange:new()
  log(", new combo point change")
  return _G.setmetatable({}, ComboPointsChange)
end

function ComboPointsChange:resolve()
  if not self.UNIT_COMBO_POINTS and not self.comboPointsBefore then
    self.comboPointsBefore = comboPoints
  end
  if self.spellId and not self.comboPointsAfter then
    if (rake[self.spellId] or shred[self.spellId] or swipe[self.spellId]) and self.critical ~= nil and
       self.comboPointsBefore
    then
      self.comboPointsAfter = _G.math.min(_G.MAX_COMBO_POINTS, self.comboPointsBefore + (self.critical and 2 or 1))
    elseif finishers[self.spellId] then
      self.comboPointsAfter = 0
    elseif (rake[self.spellId] or shred[self.spellId] or swipe[self.spellId]) then
      -- ...
    end
  end
  -- Apply the combo point change.
  if self.comboPointsAfter and (not comboPoints or comboPoints ~= self.comboPointsAfter) then
      comboPointFrame:update(self.comboPointsAfter)
      log(", cp changed" .. (self.comboPointsBefore and (" from " .. self.comboPointsBefore) or "") ..
          " to " .. self.comboPointsAfter .. " after " .. (ComboPointsChange.expires - self.expires))
  end
  -- Remove the combo point change.
  if self.SPELL_CAST_SUCCESS then -- If there is no SPELL_CAST_SUCCESS, there is no combo point change.
    if swipe[self.spellId] then
      -- Can't remove this; there may be pending SPELL_DAMAGE events.
    elseif shred[self.spellId] or rake[self.spellId] or moonfire[self.spellId] then
      if (self.UNIT_COMBO_POINTS or self.comboPointsBefore == 5) and (self.SPELL_DAMAGE or self.SPELL_MISSED) then
        log(", cp change removed after " .. (ComboPointsChange.expires - self.expires))
        return true
      end
    elseif ferociousBite[self.spellId] then
      if self.UNIT_COMBO_POINTS and self.SPELL_DAMAGE or self.SPELL_MISSED then
        log(", cp change removed after " .. (ComboPointsChange.expires - self.expires))
        return true
      end
    elseif maim[self.spellId] then
      if self.UNIT_COMBO_POINTS and (self.SPELL_DAMAGE or self.SPELL_MISSED) then
        log(", cp change removed after " .. (ComboPointsChange.expires - self.expires))
        return true
      end
    elseif rip[self.spellId] then
      if self.UNIT_COMBO_POINTS and (self.SPELL_AURA_APPLIED or self.SPELL_AURA_REFRESH) or self.SPELL_MISSED then
        log(", cp change removed after " .. (ComboPointsChange.expires - self.expires))
        return true
      end
    elseif self.UNIT_COMBO_POINTS and savageRoar[self.spellId] then
      log(", cp change removed after " .. (ComboPointsChange.expires - self.expires))
      return true
    end
  elseif self.oOCDecay then
    log(", cp change removed after " .. (ComboPointsChange.expires - self.expires))
    return true
  end
end
------------------------------------------------------------------------------------------------------------------------

local maxErrors = 25
local eventLog = {} -- Circular buffer. It's always full and eventLogHead always is the index to the newest element.
local eventLogSize = 20
for i = 1, eventLogSize do
  eventLog[i] = { timestamp = 0, message = "" }
end
local eventLogHead = 1

do
  local message = ""
  log = function(string)
    if not string then -- Discard it.
      message = ""
    elseif _G.string.sub(string, -1, -1) == "\n" then -- Save it.
      local time = _G.GetTime()
      eventLogHead = (eventLogHead - 2) % 20 + 1 -- Decrement eventLogHead. (-1 % 20 == 19).
      eventLog[eventLogHead].timestamp = _G.string.format("%.3f", time)
      eventLog[eventLogHead].message = message .. string
      if logBox then
        --_G.print(_G.string.format("%.3f: %s%s", time, message, _G.string.sub(string, 1, -2)))
        logBox:SetText(logBox:GetText() .. _G.string.format("%.3f: %s%s", time, message, string))
      end
      message = ""
    else
      message = message .. string
    end
  end
end

function logError(errorMessage)
  log("\n")
  -- http://www.cplusplus.com/reference/ctime/strftime
  local caption = _G.date("%Y-%m-%d %X") .. " | "  .. _G.GetTime() .. " | " .. "PrimalAnticipation-v" ..
                  _G.GetAddOnMetadata("PrimalAnticipation", "Version")
  if not errorMessage then
    errorMessage = caption .. "\n\nUnkown error" .. "\n\n" .. _G.debugstack() .. "\nEvent log:\n"
  else
    errorMessage = caption .. "\n\n" .. errorMessage .. "\n\n" .. _G.debugstack() .. "\nEvent log:\n"
  end
  do
    for i = -1, eventLogSize - 2 do
      local event = eventLog[(eventLogHead + i) % 20 + 1]
      if _G.GetTime() - event.timestamp > 10 then
        break
      end
      errorMessage = errorMessage .. event.timestamp .. ": " .. event.message
    end
  end
  if #db.global.errors == maxErrors then
    _G.table.remove(db.global.errors, 1)
  end
  _G.table.insert(db.global.errors, errorMessage)
  if optionsFrame and optionsFrame:IsVisible() then
    optionsFrameTabGroup:SelectTab("errors")
  end
end

-- Change the display to the actual combo points if get them. Save an error if that actually changed it.
function GetComboPoints(unit, target)
  _G.assert(unit)
  target = target or "target"
  if _G.UnitExists(unit) and _G.UnitExists(target) and _G.UnitCanAttack(unit, target) then
    local actualCPs = _G.GetComboPoints(unit, target)
    _G.assert(actualCPs)
    if cPChange then
      if cPChange.comboPointsAfter and cPChange.comboPointsAfter ~= actualCPs and cPChange.UNIT_COMBO_POINTS then
        logError("Displaying " .. comboPoints .. " combo points, but GetComboPoints(\"" .. unit .. "\"" ..
                (target and (", \"" .. target .. "\"") or "") .. ") == " .. actualCPs)
        cPChange.comboPointsAfter = actualCPs
        cPChange:resolve()
      end
    else--[[if not cPChange then]]
      if comboPoints and comboPoints ~= actualCPs then
        logError("Displaying " .. comboPoints .. " combo points, but GetComboPoints(\"" .. unit .. "\"" ..
                (target and (", \"" .. target .. "\"") or "") .. ") == " .. actualCPs)
        comboPointFrame:update(actualCPs)
      end
    end
    if not comboPoints then
      comboPointFrame:update(actualCPs)
      log(", " .. actualCPs .. " combo points\n")
    end
    return actualCPs
  else
    return _G.GetComboPoints(unit, target)
  end
end

function sync()
  for _, unitID in _G.ipairs(unitIDs) do
    if _G.UnitExists(unitID) and _G.UnitCanAttack("player", unitID) then
      local actualCPs = GetComboPoints("player", unitID); break
    end
  end
end

------------------------------------------------------------------------------------------------------------------------
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
  _G.assert(newCP)
  _G.assert(newCP <= _G.MAX_COMBO_POINTS)
  comboPoints = newCP

  for i = 1, _G.MAX_COMBO_POINTS - 1 do
    comboPointFrames[i]:SetBackdropColor(0, 0, 0, .25)
  end
  for i = 1, comboPoints do
    comboPointFrames[i]:SetBackdropColor(1, 1, 1, .5)
  end

  if comboPoints == _G.MAX_COMBO_POINTS then
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
------------------------------------------------------------------------------------------------------------------------

handlerFrame = _G.CreateFrame("Frame")

handlerFrame:SetScript("OnEvent", function(self, event, ...)
  -- TODO: move the event handler functions into PrimalAnticipation to allow for better debugging output?
  return self[event](self, ...)
end)

handlerFrame:SetScript("OnUpdate", function(self, elapsed)
  if not cPChange then return end
  cPChange.expires = cPChange.expires - elapsed
  if cPChange.expires <= 0 then
    if cPChange.spellId and swipe[cPChange.spellId] then
      -- Can't remove combo point changes for Swipe without wating.
    else
      local errorMessage = "Combo point change expired"
      for k, v in _G.pairs(cPChange) do
        errorMessage = errorMessage .. ", (" .. _G.tostring(k) .. " == " .. _G.tostring(v) .. ")"
      end
      logError(errorMessage)
    end
    cPChange = nil
  end
end)

-- http://wowpedia.org/API_COMBAT_LOG_EVENT
function handlerFrame:COMBAT_LOG_EVENT_UNFILTERED(timestamp, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, ...)
  -- We can get SPELL_CAST_SUCCESS but no SPELL_DAMAGE when the unit dies from white damage instantly. We still gain
  -- combo points in that case.
  if subEvent == "SPELL_CAST_SUCCESS" and sourceGUID == _G.UnitGUID("player") then
    local spellId, spellName = ...

    -- As of patch 6.0.2, the order in which SPELL_CAST_SUCCESS, SPELL_DAMAGE, UNIT_COMBO_POINTS, etc. are fired seems
    -- completely random. I had SPELL_CAST_SUCCESS be fired first for Primal Fury, followed by UNIT_COMBO_POINTS, then
    -- SPELL_DAMAGE, then SPELL_CAST_SUCCESS for Shred. The order seems to be more reasonable when using Shred and Rake
    -- when not stealhed (SPELL_CAST_SUCCESS before SPELL_DAMAGE and UNIT_COMBO_POINTS).
    if rake[spellId] or shred[spellId] or swipe[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. ")")
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      cPChange[subEvent] = timestamp
      cPChange.spellId = spellId
      if cPChange:resolve() then cPChange = nil end
      log("\n")

    elseif primalFury[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. ")")
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      cPChange.critical = true
      if cPChange:resolve() then cPChange = nil end
      log("\n")

    elseif savageRoar[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. ")")
      if cPChange ~= nil then
        -- SPELL_CAST_SUCCESS is posted before UNIT_COMBO_POINTS for Savage Roar. TODO: is this still true in 6.0.2?
        logError("(cPChange == nil) expected")
      else
        cPChange = ComboPointsChange:new()
      end
      if cPChange.spellId then
        logError("(cPChange.spellId == nil) expected")
      end
      cPChange.spellId = spellId
      if cPChange[subEvent] then
        logError("(cPChange[\"" .. subEvent .. "\" == nil) expected")
      end
      cPChange[subEvent] = timestamp
      if cPChange:resolve() then cPChange = nil end
      log("\n")

    elseif ferociousBite[spellId] or rip[spellId] or maim[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. ")")
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      if cPChange.spellId then
        logError("(cPChange.spellId == nil) expected")
      end
      cPChange.spellId = spellId
      if cPChange[subEvent] then
        logError("(cPChange[\"" .. subEvent .. "\" == nil) expected")
      end
      cPChange[subEvent] = timestamp
      if cPChange:resolve() then cPChange = nil end
      log("\n")
    end

  -- SPELL_DAMAGE can be posted before (or after) SPELL_CAST_SUCCESS.
  elseif subEvent == "SPELL_DAMAGE" and sourceGUID == _G.UnitGUID("player") then
    local spellId, spellName, _, _, _, _, _, _, _, critical = ...
    if rake[spellId] or shred[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. ")" .. (critical and ", critical" or ""))
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      if cPChange[subEvent] then
        logError("(cPChange[\"" .. subEvent .. "\"] == nil) expected")
        cPChange = ComboPointsChange:new()
      end
      cPChange[subEvent] = timestamp
      if not cPChange.spellId then
        cPChange.spellId = spellId
      elseif cPChange.spellId ~= spellId then
        logError("(cPChange.spellId == " .. spellId.. ") expected")
        cPChange = ComboPointsChange:new()
        cPChange.spellId = spellId
      end
      if cPChange.critical and cPChange.critical ~= (critical and true or false) then
        logError("(cPChange.critical == " .. (critical and "true" or "false") .. ") expected")
        cPChange = ComboPointsChange:new()
      end
      cPChange.critical = critical and true or false
      if cPChange:resolve() then cPChange = nil end
      log("\n")

    -- There is only one UNIT_COMBO_POINTS event, no matter how many units were hit by Swipe as of patch 6.0.2. The
    -- order in which SPELL_DAMAGE and UNIT_COMBO_POINTS are fired is inconsistent.
    elseif swipe[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. ")" .. (critical and ", critical" or ""))
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      if not cPChange.spellId then
        cPChange.spellId = spellId
      elseif cPChange.spellId ~= spellId then
        logError("(cPChange.spellId == " .. spellId.. ") expected")
        cPChange = ComboPointsChange:new()
        cPChange.spellId = spellId
      end
      if not cPChange[subEvent] then
        cPChange[subEvent] = timestamp
      end
      cPChange.critical = cPChange.critical or (critical and true or false) -- ((nil or false) == false)
      if cPChange:resolve() then cPChange = nil end
      log("\n")

    -- UNIT_COMBO_POINTS is posted before SPELL_DAMAGE for Ferocious Bite and Main. For finishers, we can never directly
    -- resolve UNIT_COMBO_POINTS. TODO: confirm this hasn't changed in patch 6.0.2.
    elseif ferociousBite[spellId] or maim[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. ")")
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      if not cPChange.spellId then
        cPChange.spellId = spellId
      elseif cPChange.spellId ~= spellId then
        logError("(cPChange.spellId == " .. spellId.. ") expected")
        cPChange = ComboPointsChange:new()
        cPChange.spellId = spellId
      end
      if cPChange[subEvent] then
        logError("(cPChange[\"" .. subEvent .. "\"] == nil) expected")
        cPChange = ComboPointsChange:new()
      end
      cPChange[subEvent] = timestamp
      if cPChange:resolve() then cPChange = nil end
      log("\n")
    end

  -- Apparently we still get combo points when we miss. Even with Swipe when it didn't do damage to any other unit. Is
  -- that change here to stay? Luckily, the same isn't true for Rip and Ferocious Bite.
  elseif subEvent == "SPELL_MISSED" and sourceGUID == _G.UnitGUID("player") then
    local spellId, spellName, _, missType = ...
    --[[
    if missType == "ABSORB" or missType == "BLOCK" then
      log()
      return
    end -- http://wowpedia.org/COMBAT_LOG_EVENT#Miss_type
    ]]
    if rake[spellId] or shred[spellId] or swipe[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. "), " .. missType)
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      if not cPChange.spellId then
        cPChange.spellId = spellId
      elseif cPChange.spellId ~= spellId then
        logError("(cPChange.spellId == " .. spellId.. ") expected")
        cPChange = ComboPointsChange:new()
        cPChange.spellId = spellId
      end
      if not cPChange[subEvent] then
        cPChange[subEvent] = timestamp
      else
        -- TODO: log an error unless this is Swipe.
      end
      if cPChange:resolve() then cPChange = nil end
      log("\n")
    end

  elseif (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH") and sourceGUID == _G.UnitGUID("player")
  then
    local spellId, spellName, _, _, _ = ...
    log(subEvent .. ", " .. spellId .. " (" .. spellName .. ")")
    if rip[spellId] then
      if cPChange == nil then
        -- TODO: error?
        cPChange = ComboPointsChange:new()
      end
      if not cPChange.spellId then
        -- TODO: error?
        cPChange.spellId = spellId
      elseif cPChange.spellId ~= spellId then
        logError("(cPChange.spellId == " .. spellId.. ") expected")
        cPChange = ComboPointsChange:new()
        cPChange.spellId = spellId
      end
      if cPChange[subEvent] then
        logError("(cPChange[\"" .. subEvent .. "\"] == nil) expected")
        cPChange = ComboPointsChange:new()
        cPChange.spellId = spellId
      end
      cPChange[subEvent] = timestamp
      if cPChange:resolve() then cPChange = nil end
      log("\n")
    end
  elseif subEvent == "UNIT_DIED" or subEvent == "UNIT_DESTROYED" then
    -- ...
  end
  log() -- Discard the logged message if it doesn't end in a line feed.
end

-- Crits seem to only cause one UNIT_COMBO_POINTS event as of patch 6.0.2, even though 2 combo points are gained.
function handlerFrame:UNIT_COMBO_POINTS(unit, arg2)
  _G.assert(unit == "player")
  _G.assert(arg2 == nil)

  log("UNIT_COMBO_POINTS")

  if cPChange == nil then
    cPChange = ComboPointsChange:new()
  end
  if cPChange.UNIT_COMBO_POINTS then
    logError("(cPChange.UNIT_COMBO_POINTS == nil) expected")
    cPChange = ComboPointsChange:new()
  end
  cPChange.UNIT_COMBO_POINTS = _G.GetTime()
  cPChange.comboPointsBefore = comboPoints

  for _, unitID in _G.ipairs(unitIDs) do
    if _G.UnitExists(unitID) and _G.UnitCanAttack("player", unitID) then
      local actualCPs = GetComboPoints("player", unitID)
      if not cPChange.comboPointsAfter then
        cPChange.comboPointsAfter = actualCPs
      elseif cPChange.comboPointsAfter ~= actualCPs then
        logError("(cPChange.comboPointsAfter == " .. actualCPs .. ") expected")
        cPChange = ComboPointsChange:new()
        cPChange.UNIT_COMBO_POINTS = _G.GetTime()
        cPChange.comboPointsBefore = comboPoints
        cPChange.comboPointsAfter = actualCPs
      end
      break
    end
  end

  if not _G.UnitAffectingCombat("player") then
    -- Could be Savage Roar or OOC decay, I think.
    local oOCDuration = _G.GetTime() - oOCTime
    if oOCTime >= 10 then
      if cPChange.comboPointsBefore then
        if not cPChange.comboPointsAfter then
          cPChange.comboPointsAfter = cPChange.comboPointsBefore - 1
        end
        if cPChange.comboPointsAfter == cPChange.comboPointsBefore - 1 then
          cPChange.oOCDecay = true
          log(", cp decay after OOC for " ..  _G.string.format("%.3f", oOCDuration))
        end
      end
    end
  end

  if cPChange:resolve() then cPChange = nil end
  log("\n")
end

function handlerFrame:PLAYER_REGEN_ENABLED()
  oOCTime = _G.GetTime()
end

local function onUnitExists(unit)
  if _G.UnitExists(unit) and _G.UnitCanAttack("player", unit) then
    GetComboPoints("player", unit)
  end
end

function handlerFrame:PLAYER_TARGET_CHANGED(cause)
  log("PLAYER_TARGET_CHANGED")
  onUnitExists("target")
  log()
end

function handlerFrame:PLAYER_FOCUS_CHANGED()
  log("PLAYER_FOCUS_CHANGED")
  onUnitExists("focus")
  log()
end

function handlerFrame:UPDATE_MOUSEOVER_UNIT()
  log("UPDATE_MOUSEOVER_UNIT")
  onUnitExists("mouseover")
  log()
end

function handlerFrame:ARENA_OPPONENT_UPDATE(unit, eventType)
  log("ARENA_OPPONENT_UPDATE")
  onUnitExists(unit)
  log()
end

function handlerFrame:PLAYER_ENTERING_WORLD()
  -- ...
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
  },
}

AceConfig:RegisterOptionsTable("PrimalAnticipation", options)

AceConfigDialog:SetDefaultSize("PrimalAnticipation", 480, 360)

local function toggleOptionsUI()
  if optionsFrame then return end
  optionsFrame = AceGUI:Create("Frame")
  optionsFrame:SetTitle("PrimalAnticipation")
  optionsFrame:SetCallback("OnClose", function(widget)
    AceGUI:Release(widget)
    optionsFrame = nil
    optionsFrameTabGroup = nil
    logBox = nil
  end)
  optionsFrame:SetLayout("Fill")

  optionsFrameTabGroup = AceGUI:Create("TabGroup")
  optionsFrameTabGroup:SetLayout("Flow")
  optionsFrameTabGroup:SetTabs({
    { text = "Options", value = "options" },
    { text = "Errors", value = "errors" },
    { text = "Log", value = "log" }, -- TODO.
  })
  optionsFrameTabGroup:SetCallback("OnGroupSelected", function(container, event, group)
    container:ReleaseChildren() -- ...
    logBox = nil
    if group == "options" then
      container:SetLayout("Fill")
      local inlineGroup = AceGUI:Create("SimpleGroup")
      AceConfigDialog:Open("PrimalAnticipation", inlineGroup)
      container:AddChild(inlineGroup)
      container:DoLayout()
    elseif group == "errors" then
      container:SetLayout("Flow")
      local i = #db.global.errors
      local previousButton = AceGUI:Create("Button")
      local deleteButton = AceGUI:Create("Button")
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
          if i > 0 and i > #db.global.errors then
            i = i - 1
          end
          --errorBox:SetLabel(i)
          deleteButton:SetText("Delete (" .. i .. "/" .. #db.global.errors .. ")")
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
      errorBox:SetText(db.global.errors[i] or "")
      errorBox:SetCallback("OnTextChanged", function(self, text)
        self:SetText(db.global.errors[i] or "")
      end)
      errorBox:SetFullWidth(true)
      errorBox:SetFullHeight(true)
      container:AddChild(previousButton)
      container:AddChild(deleteButton)
      container:AddChild(nextButton)
      container:AddChild(errorBox)
      --errorGroup:SetPoint("BOTTOM", previousButton, "TOP")
      container:DoLayout()
    elseif group == "log" then
      container:SetLayout("Fill")
      logBox = AceGUI:Create("MultiLineEditBox")
      logBox:DisableButton(true)
      logBox:SetLabel("")
      logBox:SetFullWidth(true)
      logBox:SetFullHeight(true)
      logBox:SetText("")
      for i = -1, eventLogSize - 2 do
        local event = eventLog[(eventLogHead + i) % 20 + 1]
        if event.message ~= "" then
          logBox:SetText(logBox:GetText() .. event.timestamp .. ": " ..event.message)
        end
      end
      container:AddChild(logBox)
      container:DoLayout()
    end
  end)
  optionsFrameTabGroup:SelectTab("options")
  optionsFrame:AddChild(optionsFrameTabGroup)
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
  --handlerFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
  --handlerFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
  handlerFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  handlerFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
  handlerFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
  handlerFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
  handlerFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
  handlerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
end

-- vim: tw=120 sw=2 et
