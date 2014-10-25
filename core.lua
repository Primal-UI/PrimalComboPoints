-- We lose combo points when missing with Maim now... hopefully a bug. TODO: make changes so the AddOn doesn't break
-- when that happens without a target.

--FeralComboPoints = setmetatable({}, { __index = _G })
FeralComboPoints = LibStub("AceAddon-3.0"):NewAddon("FeralComboPoints", "AceConsole-3.0")
--setmetatable(FeralComboPoints, { __index = _G })
FeralComboPoints._G = _G

setfenv(1, FeralComboPoints)

local FeralComboPoints = _G.FeralComboPoints
local AceGUI = _G.LibStub("AceGUI-3.0")
local AceConfig = _G.LibStub("AceConfig-3.0")
local AceConfigDialog = _G.LibStub("AceConfigDialog-3.0")

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

local optionsFrame, optionsFrameTabGroup, logBox
local comboPointFrame = _G.CreateFrame("Frame", nil, _G.UIParent)
local comboPointFrames = {}

log = nil

-- State ---------------------------------------------------------------------------------------------------------------
local comboPoints -- Number of combo points we THINK we have.
local cPChange
local oOCTime = _G.GetTime()
------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------------------------
-- Prototype. Created in response to SPELL_CAST_SUCCESS and updated with information from SPELL_DAMAGE,
-- UNIT_COMBO_POINTS, etc. Removed once fully resolved or after it expires (an error is raised in that case).
-- Corresponds to one UNIT_COMBO_POINTS event.
local ComboPointsChange = {
  expires = .5,
  --destGUID = nil,
  --spellId = nil,
  --critical = nil,
  --SPELL_CAST_SUCCESS = nil, -- Value of GetTime() when SPELL_CAST_SUCCESS fired.
  --UNIT_COMBO_POINTS = nil,
  --SPELL_MISSED = nil,
  --SPELL_AURA_APPLIED = nil,
  --SPELL_AURA_REFRESH = nil,
  --UNIT_DIED = nil,
  --UNIT_DESTROYED = nil,
}

ComboPointsChange.__index = ComboPointsChange

function ComboPointsChange:new()
  log(", new combo point change")
  cPChange = _G.setmetatable({}, ComboPointsChange)
  return cPChange
end

function ComboPointsChange:set(key, value)
  if self[key] and self[key] ~= value then
    if _G.type(key) == "string" then
      logError("(cPChange[\"" .. key .. "\"] == " .. value .. ") expected")
    else
      logError("(cPChange[" .. key .. "] == " .. value .. ") expected")
    end
  end
  self[key] = value
end

function ComboPointsChange:delete()
  log(", cp change removed after " .. _G.string.format("%.3f", ComboPointsChange.expires - self.expires))
  cPChange = nil
end

function ComboPointsChange:resolve()
  if not self.UNIT_COMBO_POINTS and not self.comboPointsBefore then
    self.comboPointsBefore = comboPoints
  end
  if self.spellId and not self.comboPointsAfter then
    if (rake[self.spellId] or shred[self.spellId]) and self.comboPointsBefore then
      if self.SPELL_DAMAGE or self.SPELL_MISSED or self.critical ~= nil then
        self.comboPointsAfter = _G.math.min(_G.MAX_COMBO_POINTS, self.comboPointsBefore + (self.critical and 2 or 1))
      end
    elseif swipe[self.spellId] and self.comboPointsBefore then
      if self.SPELL_DAMAGE and self.SPELL_DAMAGE < _G.GetTime() or self.SPELL_MISSED and
        self.SPELL_MISSED < _G.GetTime()
      then
        self.comboPointsAfter = _G.math.min(_G.MAX_COMBO_POINTS, self.comboPointsBefore + (self.critical and 2 or 1))
      end
    elseif ferociousBite[self.spellId] or maim[self.spellId] and self.SPELL_DAMAGE then
      self.comboPointsAfter = 0
    elseif rip[self.spellId] and (self.SPELL_AURA_APPLIED or self.SPELL_AURA_REFRESH) then
      self.comboPointsAfter = 0
    elseif maim[self.spellId] and self.SPELL_MISSED then
      -- TODO.
    end
  end
  -- Apply the combo point change.
  if self.UNIT_COMBO_POINTS and self.comboPointsAfter and (not comboPoints or comboPoints ~= self.comboPointsAfter) then
    if self.comboPointsAfter == _G.MAX_COMBO_POINTS then
      _G.assert(not comboPointFrames[5]:IsShown())
      if db.global.sound then
        local file = [[Interface\AddOns\FeralComboPoints\media\sounds\noisecrux\vio]] .. _G.math.random(10) .. ".ogg"
        _G.PlaySoundFile(file, "Master")
      end
    end
    comboPointFrame:update(self.comboPointsAfter)
    log(", cp changed" .. (self.comboPointsBefore and (" from " .. self.comboPointsBefore) or "") .. " to " ..
      self.comboPointsAfter .. " after " .. _G.string.format("%.3f", ComboPointsChange.expires - self.expires))
  end
  -- Remove the combo point change.
  if self.SPELL_CAST_SUCCESS then -- If there is no SPELL_CAST_SUCCESS, there is no combo point change.
    if swipe[self.spellId] then
      if self.UNIT_COMBO_POINTS or self.comboPointsBefore == 5 then
        if self.SPELL_DAMAGE and self.SPELL_DAMAGE < _G.GetTime() then
          self:delete()
          return
        elseif self.SPELL_MISSED and self.SPELL_MISSED < _G.GetTime() then
          -- TODO.
        end
      end
    end
    if shred[self.spellId] or rake[self.spellId] or moonfire[self.spellId] then
      if (self.UNIT_COMBO_POINTS or self.comboPointsBefore == 5) and (self.SPELL_DAMAGE or self.SPELL_MISSED) then
        self:delete()
        return
      end
    end
    if ferociousBite[self.spellId] then
      if self.UNIT_COMBO_POINTS then
        if self.SPELL_DAMAGE or self.SPELL_MISSED then
          self:delete()
          return
        end
      else--[[if not self.UNIT_COMBO_POINTS then]]
        if self.SPELL_MISSED and (self.missType == "DEFLECT" or self.missType == "DODGE" or self.missType == "EVADE" or
          self.missType == "MISS" or self.missType == "PARRY")
        then
          self:delete()
          return
        end
      end
    end
    if maim[self.spellId] then
      if self.UNIT_COMBO_POINTS and (self.SPELL_DAMAGE or self.SPELL_MISSED) then
        self:delete()
        return
      end
    end
    if rip[self.spellId] then
      if self.UNIT_COMBO_POINTS and (self.SPELL_AURA_APPLIED or self.SPELL_AURA_REFRESH) or self.SPELL_MISSED then
        self:delete()
        return
      end
    elseif self.UNIT_COMBO_POINTS and savageRoar[self.spellId] then
      self:delete()
      return
    end
    if self.UNIT_COMBO_POINTS then
      if self.UNIT_DIED or self.UNIT_DESTROYED then -- The unit we got SPELL_CAST_SUCCESS for died. What are we waiting for?
        self:delete()
        return
      end
    end
  elseif self.oOCDecay and self.UNIT_COMBO_POINTS then -- Mostly.
    self:delete()
    return
  elseif self.PLAYER_DEAD and self.UNIT_COMBO_POINTS then -- Mostly!
    self:delete()
    return
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
      message = message .. string
      if message ~= "\n" then
        local time = _G.GetTime()
        eventLogHead = (eventLogHead - 2) % 20 + 1 -- Decrement eventLogHead. (-1 % 20 == 19).
        eventLog[eventLogHead].timestamp = _G.string.format("%.3f", time)
        eventLog[eventLogHead].message = message
        if logBox then
          logBox:SetText(_G.string.format("%.3f: %s", time, message) .. logBox:GetText())
        end
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
  local caption = _G.date("%Y-%m-%d %X") .. " | "  .. _G.GetTime() .. " | " .. "FeralComboPoints-v" ..
                  _G.GetAddOnMetadata("FeralComboPoints", "Version")
  if not errorMessage then
    errorMessage = caption .. "\n\nUnkown error" .. "\n\n" .. _G.debugstack() .. "\nEvent log:\n"
  else
    errorMessage = caption .. "\n\n" .. errorMessage .. "\n\n" .. _G.debugstack() .. "\nEvent log:\n"
  end
  for i = -1, eventLogSize - 2 do
    local event = eventLog[(eventLogHead + i) % 20 + 1]
    if _G.GetTime() - event.timestamp > 10 then
      break
    end
    errorMessage = errorMessage .. event.timestamp .. ": " .. event.message
  end
  if #db.global.errors == maxErrors then
    _G.table.remove(db.global.errors, 1)
  end
  _G.table.insert(db.global.errors, errorMessage)
  if optionsFrame and optionsFrame:IsVisible() then
    optionsFrameTabGroup:SelectTab("errors")
  end
end

do
  -- We can GetComboPoints() on any unit we have a unitID for. These are the units we try.
  local unitIDs = { "target", "focus", "mouseover", "arena1", "arena2", "arena3", "arena4", "arena5" }
  function GetComboPoints(target)
    if target then
      if _G.UnitExists(target) and _G.UnitCanAttack("player", target) then
        local actualCPs = _G.GetComboPoints("player", target); _G.assert(actualCPs)
        return actualCPs
      end
    else
      for _, unitID in _G.ipairs(unitIDs) do
        if _G.UnitExists(unitID) and _G.UnitCanAttack("player", unitID) then
          local actualCPs = _G.GetComboPoints("player", unitID); _G.assert(actualCPs)
          return actualCPs
        end
      end
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
  local comboPoints = comboPoints or 0

  _G.assert(comboPoints <= _G.MAX_COMBO_POINTS)

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
  -- TODO: move the event handler functions into FeralComboPoints to allow for better debugging output?
  return self[event](self, ...)
end)

handlerFrame:SetScript("OnUpdate", function(self, elapsed)
  if not cPChange then return end
  cPChange.expires = cPChange.expires - elapsed
  if cPChange.expires <= 0 then
    log("Combo point change expired")
    if not cPChange.UNIT_COMBO_POINTS then
      -- This is fine.
    else
      local errorMessage = "Combo point change expired"
      for k, v in _G.pairs(cPChange) do
        errorMessage = errorMessage .. ", (" .. _G.tostring(k) .. " == " .. _G.tostring(v) .. ")"
      end
      logError(errorMessage)
    end
    log("\n")
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
      if not swipe[spellId] then cPChange.destGUID = destGUID end
      cPChange[subEvent] = _G.GetTime()
      cPChange.spellId = spellId
      cPChange:resolve()
      log("\n")

    elseif primalFury[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. ")")
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      cPChange.critical = true
      cPChange:resolve()
      log("\n")

    elseif savageRoar[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. ")")
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      cPChange:set("spellId", spellId)
      cPChange:set(subEvent, _G.GetTime())
      cPChange:set("comboPointsAfter", 0)
      cPChange:resolve()
      log("\n")

    -- We can get SPELL_DAMAGE before SPELL_CAST_SUCCESS for at least Ferocious Bite.
    elseif ferociousBite[spellId] or rip[spellId] or maim[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. ")")
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      cPChange.destGUID = destGUID
      cPChange:set("spellId", spellId)
      cPChange:set(subEvent, _G.GetTime())
      cPChange:resolve()
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
      cPChange:set(subEvent, _G.GetTime())
      cPChange:set("spellId", spellId)
      cPChange:set("critical", critical and true or false)
      cPChange:resolve()
      log("\n")

    -- There is only one UNIT_COMBO_POINTS event, no matter how many units were hit by Swipe as of patch 6.0.2. The
    -- order in which SPELL_DAMAGE and UNIT_COMBO_POINTS are fired is inconsistent.
    elseif swipe[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. ")" .. (critical and ", critical" or ""))
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      cPChange:set("spellId", spellId)
      cPChange.critical = cPChange.critical or (critical and true or false)
      if not cPChange[subEvent] then
        cPChange:set(subEvent, _G.GetTime())
        _G.C_Timer.After(.001, function()
          if cPChange then
            log("Timer expired")
            cPChange:resolve()
            log("\n")
          end
        end)
      end
      log("\n")

    elseif ferociousBite[spellId] or maim[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. ")")
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      cPChange:set("spellId", spellId)
      cPChange:set(subEvent, _G.GetTime())
      cPChange.comboPointsAfter = 0
      cPChange:resolve()
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
    if rake[spellId] or shred[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. "), " .. missType)
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      cPChange:set("spellId", spellId)
      cPChange:set(subEvent, _G.GetTime())
      cPChange:resolve()
      log("\n")
    elseif swipe[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. "), " .. missType)
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      cPChange:set("spellId", spellId)
      cPChange:set(subEvent, _G.GetTime())
      cPChange:resolve()
      log("\n")
    elseif ferociousBite[spellId] or rip[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. "), " .. missType)
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      cPChange:set("spellId", spellId)
      cPChange:set(subEvent, _G.GetTime())
      cPChange:set("missType", missType)
      cPChange:resolve()
      log("\n")

    elseif maim[spellId] then
      log(subEvent .. ", " .. spellId .. " (" .. spellName .. "), " .. missType)
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      cPChange:set("spellId", spellId)
      cPChange:set(subEvent, _G.GetTime())
      cPChange:set("missType", missType)
      cPChange:resolve()
      log("\n")
    end

  elseif (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH") and sourceGUID == _G.UnitGUID("player")
  then
    local spellId, spellName, _, _, _ = ...
    log(subEvent .. ", " .. spellId .. " (" .. spellName .. ")")
    if rip[spellId] then
      if cPChange == nil then
        cPChange = ComboPointsChange:new()
      end
      cPChange:set("spellId", spellId)
      cPChange:set(subEvent, _G.GetTime())
      cPChange:set("comboPointsAfter", 0)
      cPChange:resolve()
      log("\n")
    end
  elseif subEvent == "UNIT_DIED" or subEvent == "UNIT_DESTROYED" then
    if cPChange and cPChange.destGUID and cPChange.destGUID == destGUID then
      log(subEvent .. ", " .. destGUID)
      cPChange[subEvent] = _G.GetTime()
      cPChange:resolve()
      log("\n")
    end
  end
  log() -- Discard the logged message if it doesn't end in a line feed.
end

-- Crits seem to only cause one UNIT_COMBO_POINTS event as of patch 6.0.2, even though 2 combo points are gained. It
-- only makes sense to GetComboPoints in response to this event, in response to the events informing us that some
-- unit changed (PLAYER_TARGET_CHANGED, PLAYER_FOCUS_CHANGED, ...), and in response to PLAYER_ENTERING_WORLD, I guess.
function handlerFrame:UNIT_COMBO_POINTS(unit, arg2)
  _G.assert(unit == "player")
  _G.assert(arg2 == nil)

  log("UNIT_COMBO_POINTS")

  if cPChange == nil then
    cPChange = ComboPointsChange:new()
  end
  cPChange:set("UNIT_COMBO_POINTS", _G.GetTime())
  cPChange:set("comboPointsBefore", comboPoints)

  local actualCPs = GetComboPoints()
  if actualCPs then
    cPChange:set("comboPointsAfter", actualCPs)
  end

  if not _G.UnitAffectingCombat("player") then
    -- Could be Savage Roar or OOC decay, I think.
    if cPChange.SPELL_CAST_SUCCESS then
      _G.assert(cPChange.spellId)
      if savageRoar[cPChange.spellId] then
        cPChange:set("comboPointsAfter", 0)
      else
        logError("(savageRoar[cPChange.spellId] ~= nil) expected")
        -- TODO: recover...
      end
    else
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
  end

  cPChange:resolve()
  log("\n")
end

function handlerFrame:PLAYER_REGEN_ENABLED()
  oOCTime = _G.GetTime()
end

local function onUnitChanged(unit)
  _G.assert(unit)
  if _G.UnitExists(unit) and _G.UnitCanAttack("player", unit) then
    local actualCPs = GetComboPoints(unit); _G.assert(actualCPs)
    if not cPChange then
      if not comboPoints then
        comboPointFrame:update(actualCPs)
        log(", " .. actualCPs .. " combo points\n")
      elseif comboPoints ~= actualCPs then
        logError("Was displaying " .. comboPoints .. " combo points, but GetComboPoints(\"player\"" ..
                 (target and (", \"" .. target .. "\"") or "") .. ") == " .. actualCPs .. "\n")
        comboPointFrame:update(actualCPs)
      end
    elseif not comboPoints or comboPoints ~= actualCPs then
      if cPChange.UNIT_COMBO_POINTS then
        if not cPChange.comboPointsAfter then
          cPChange.comboPointsAfter = actualCPs
          cPChange:resolve()
        elseif cPChange.comboPointsAfter ~= actualCPs then
          logError("(cPChange.comboPointsAfter == " .. cPChange.comboPointsAfter .. "), but GetComboPoints(\"player\""
                .. (unit and (", \"" .. unit .. "\"") or "") .. ") == " .. actualCPs .. "\n")
          cPChange.comboPointsAfter = actualCPs
        end
      else--[[if not cPChange.UNIT_COMBO_POINTS then]]
        if not cPChange.comboPointsBefore then
          cPChange.comboPointsBefore = actualCPs
          cPChange:resolve()
        elseif cPChange.comboPointsAfter ~= actualCPs then
          logError("(cPChange.comboPointsBefore == " .. cPChange.comboPointsBefore .. "), but GetComboPoints(\"player\""
                .. (unit and (", \"" .. unit .. "\"") or "") .. ") == " .. actualCPs .. "\n")
          cPChange.comboPointsBefore = actualCPs
        end
      end
      -- Still wrong.
      if comboPoints ~= actualCPs then
        logError("Displaying " .. comboPoints .. " combo points, but GetComboPoints(\"player\"" ..
                 (unit and (", \"" .. unit .. "\"") or "") .. ") == " .. actualCPs .. "\n")
        comboPointFrame:update(actualCPs)
      end
    end
  end
end

function handlerFrame:PLAYER_DEAD()
  log("PLAYER_DEAD")
  if not cPChange then
    cPChange = ComboPointsChange:new()
  end
  cPChange.PLAYER_DEAD = _G.GetTime()
  cPChange.comboPointsAfter = 0
  cPChange:resolve()
  log("\n")
end

function handlerFrame:PLAYER_TARGET_CHANGED(cause)
  log("PLAYER_TARGET_CHANGED")
  onUnitChanged("target")
  log()
end

function handlerFrame:PLAYER_FOCUS_CHANGED()
  log("PLAYER_FOCUS_CHANGED")
  onUnitChanged("focus")
  log()
end

function handlerFrame:UPDATE_MOUSEOVER_UNIT()
  log("UPDATE_MOUSEOVER_UNIT")
  onUnitChanged("mouseover")
  log()
end

function handlerFrame:ARENA_OPPONENT_UPDATE(unit, eventType)
  log("ARENA_OPPONENT_UPDATE")
  onUnitChanged(unit)
  log()
end

function handlerFrame:PLAYER_ENTERING_WORLD()
  self.PLAYER_ENTERING_WORLD = function()
    log("PLAYER_ENTERING_WORLD, combo points reset")
    comboPointFrame:update(nil)
    log("\n")
  end
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
        enableLogging = {
          type = "toggle",
          name = "Log Errors",
          desc = "Save error logs (requires UI reload).",
          set = function(info, val)
            db.global.log = val
          end,
          get = function(info) return db.global.log end,
          order = 120,
        },
      },
    },
  },
}

AceConfig:RegisterOptionsTable("FeralComboPoints", options)

AceConfigDialog:SetDefaultSize("FeralComboPoints", 480, 360)

local function toggleOptionsUI()
  if optionsFrame then return end
  optionsFrame = AceGUI:Create("Frame")
  optionsFrame:SetTitle("FeralComboPoints-v" .. _G.GetAddOnMetadata("FeralComboPoints", "Version"))
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
    { text = "Log", value = "log", disabled = not db.global.log },
  })
  optionsFrameTabGroup:SetCallback("OnGroupSelected", function(container, event, group)
    container:ReleaseChildren() -- ...
    logBox = nil
    if group == "options" then
      container:SetLayout("Fill")
      local inlineGroup = AceGUI:Create("SimpleGroup")
      AceConfigDialog:Open("FeralComboPoints", inlineGroup)
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
function FeralComboPoints:OnInitialize()
  _G.assert(_G.MAX_COMBO_POINTS and _G.MAX_COMBO_POINTS == 5)

  do -- http://www.wowace.com/addons/ace3/pages/api/ace-db-3-0/
    local defaults = {
      global = {
        sound = true,
        lock = false,
        log = true,
        errors = {},
      },
    }
    self.db = _G.LibStub("AceDB-3.0"):New("FeralComboPointsDB", defaults, true)
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

  if not db.global.log then
    log = function() end
    logError = function() end
  end

  self:RegisterChatCommand("feralcombopoints", toggleOptionsUI)
  self:RegisterChatCommand("fcp", toggleOptionsUI)
end

-- http://www.wowace.com/addons/ace3/pages/api/ace-addon-3-0/
function FeralComboPoints:OnEnable()
  if _G.select(2, _G.UnitClass("player")) ~= "DRUID" then
    comboPointFrame:Hide()
    _G.DisableAddOn("FeralComboPoints")
  else
    handlerFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    handlerFrame:RegisterUnitEvent("UNIT_COMBO_POINTS", "player")
    --handlerFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    handlerFrame:RegisterEvent("PLAYER_DEAD")
    --handlerFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    handlerFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    handlerFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    handlerFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    handlerFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    handlerFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
    handlerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  end
end

-- vim: tw=120 sw=2 et
