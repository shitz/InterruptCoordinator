-----------------------------------------------------------------------------------------------
-- Client Lua Script for InterruptCoordinator
-- Created by Regex@Progenitor
-----------------------------------------------------------------------------------------------
 
require "Window"
require "ActionSetLib"
require "GameLib"
require "GroupLib"
require "ICCommLib"
require "AbilityBook"

 
-----------------------------------------------------------------------------------------------
-- InterruptCoordinator Module Definition
-----------------------------------------------------------------------------------------------
local InterruptCoordinator = {} 
local glog, GeminiLogging

-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
-- keys are AbilityIds not spellIds!
-- values are base tier spellIds
local Interrupts = {
	-- Spellslinger
	[20325] = 34355, -- Gate
	[30160] = 46160, -- Arcane Shock
	[16454] = 30006, -- Spatial Shift
	-- Esper
	[19022] = 32812, -- Crush
	[19029] = 32819, -- Shockwave
	[19355] = 33359, -- Incapacitate
	-- Stalker
	[23173] = 38791, -- Stagger
	[23705] = 39372, -- Collapse
	[23587] = 39246, -- False retreat
	-- Engineer
	[25635] = 41438, -- Zap
	[34176] = 51605, -- Obstruct Vision
	-- Warrior
	[38017] = 58591, -- kick
	[18363] = 32132, -- Grapple
	[18547] = 32320, -- Flash Bang
	-- Medic
	[26543] = 42352, -- paralytic surge
}

local InterruptNamesToAbilityIDs = {
	-- Spellslinger
	["Gate"] = 20325,
	["Arcane Shock"] = 30160,
	["Spatial Shift"] = 16454,
	["Pforte"] = 20325,
	["Arkansto�"] = 30160,
	["Raumverschiebung"] = 16454,
	-- Esper
	["Crush"] = 19022,
	["Shockwave"] = 19029,
	["Incapacitate"] = 19255,
	["Zermalmen"] = 19022,
	["Schockwelle"] = 19029,
	["Lahmlegen"] = 19255,
	-- Stalker
	["Stagger"] = 23173,
	["Collapse"] = 23705,
	["False Retreat"] = 23587,
	["Links-Rechts-Kombination"] = 23173,
	["Kleinkriegen"] = 23705,
	["R�ckzugsfinte"] = 23587,
	-- Engineer
	["Zap"] = 25635,
	["Obstruct Vision"] = 34176,
	["Schocken "] = 25635,
	["Sicht behindern"] = 34176,
	-- Warrior
	["Kick"] = 38017,
	["Grapple"] = 18363,
	["Flash Bang"] = 18547,
	["Tritt"] = 38017,
	["Einhaken"] = 18363,
	["Blendgranate"] = 18547,
	-- Medic
	["Paralytic Surge"] = 26543,
	["Hochspannungsl�hmung"] = 26543,
}

local MsgType = {
	INTERRUPTS_UPDATE = 1,
	CD_UPDATE = 2,
	SYNC_REQUEST = 3,
}

local kBarHeight = 25
local kPlayerNameHeight = 18
local kVerticalBarPadding = 0
local kVerticalPlayerPadding = 0
local kGroupContainerWidth = 164

local kDefaultGroup = "Main"

local kUIUpdateInterval = 0.033
local kBroadcastInterval = 1

local kNumOfChannels = 3

local function hexToCColor(color, a)
	if not a then a = 1 end
	local r = tonumber(string.sub(color,1,2), 16) / 255
	local g = tonumber(string.sub(color,3,4), 16) / 255
	local b = tonumber(string.sub(color,5,6), 16) / 255
	return CColor.new(r,g,b,a)
end

local kProgressBarBGColorEnabled = hexToCColor("069e0a")
local kProgressBarBGColorDisabled = "darkgray"

local kVersionString = "0.3.1"
local kVersion = 301
local kMinVersion = 300
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function InterruptCoordinator:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    -- initialize variables here
	self.syncChannel = {channel = nil, name = ""}
	self.broadCastChannel = { channel = nil, name = ""}
	self.groupLeaderInfo = nil
	self.partyInterrupts = {}
	self.currLAS = nil
	self.groups = {}
	self.playerToGroup = {}
	self.isInitialized = false
	self.isVisible = false
	
    return o
end

function InterruptCoordinator:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
		"Gemini:Logging-1.2"
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 

-----------------------------------------------------------------------------------------------
-- InterruptCoordinator OnLoad
-----------------------------------------------------------------------------------------------
function InterruptCoordinator:OnLoad()
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("InterruptCoordinator.xml")
	-- Setup Gemini Logging
    GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
	glog = GeminiLogging:GetLogger({
        level = GeminiLogging.DEBUG,
        pattern = "%d %n %c %l - %m",
        appender = "GeminiConsole"
    })
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

-----------------------------------------------------------------------------------------------
-- InterruptCoordinator OnDocLoaded
-----------------------------------------------------------------------------------------------
function InterruptCoordinator:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "InterruptCoordinatorForm", nil, self)
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
		end
		
	    self.wndMain:Show(false, true)

		-- if the xmlDoc is no longer needed, you should set it to nil
		--self.xmlDoc = nil
		
		-- Register handlers for events, slash commands and timer, etc.
		Apollo.RegisterSlashCommand("ic", "OnInterruptCoordinatorOn", self)
		
		Apollo.RegisterEventHandler("Group_Join", "OnGroupJoin", self)
		Apollo.RegisterEventHandler("Group_Left", "OnGroupLeft", self)
		Apollo.RegisterEventHandler("Group_Updated", "OnGroupUpdated", self)
		
		Apollo.RegisterEventHandler("ICCommJoinResult", "OnICCommJoinResult", self)

		Apollo.RegisterEventHandler("CombatLogCCState", "OnCombatLogCCState", self)
		--Apollo.RegisterEventHandler("CombatLogDeath", "OnCombatLogDeath", self)
		--Apollo.RegisterEventHandler("CombatLogRessurect", "OnCombatLogRessurect", self)
		--Apollo.RegisterEventHandler("CombatLogInterrupted", "OnCombatLogInterrupted", self)
		--Apollo.RegisterEventHandler("CombatLogModifyInterruptArmor", "OnCombatLogModifyInterruptArmor", self)

		Apollo.RegisterEventHandler("AbilityBookChange", "OnAbilityBookChange", self)
		Apollo.RegisterTimerHandler("DelayedAbilityBookChange", "OnDelayedAbilityBookChange", self)
		
		Apollo.RegisterTimerHandler("DelayedSyncTimer", "OnDelayedSyncTimer", self)

		
		Apollo.RegisterTimerHandler("BroadcastTimer", "OnBroadcastTimer", self)
		Apollo.RegisterTimerHandler("UITimer", "OnUITimer", self)
		-- Do additional Addon initialization here
	end
end

-----------------------------------------------------------------------------------------------
-- InterruptCoordinator Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here

-- on SlashCommand "/ic"
function InterruptCoordinator:OnInterruptCoordinatorOn(cmd, arg)
	args = splitString(arg)
	if #args < 1 then return end
	if args[1] == "init" or args[1] == "start" then
		self:Initialize()
		self:Show()
	elseif args[1] == "reset" then
		self:Reset()
	elseif args[1] == "show" then
		self:Show()
	elseif args[1] == "hide" then
		self:Hide()
	elseif args[1] == "sync" then
		self:OnGroupJoin()
	elseif args[1] == "join" then
		if #args < 2 then
			print("No channel name provided.")
			return
		end
		ICCommLib.JoinChannel(args[2], "OnCommMessageReceived", self)
		glog:debug("Joined channel " .. args[2])
	end
end

-- Initializes a new session. Is either called with "/ic" or automatically on joining a group
function InterruptCoordinator:Initialize()
	if self.isInitialized then return end
	
	local player = GameLib.GetPlayerUnit()
	if not player then return end
	-- Get all the interrupts (including their base cds) in the current LAS.
	self.partyInterrupts[player:GetName()] = self:GetCurrentInterrupts()
		
	-- Create new group.
	self:NewGroup(kDefaultGroup)
	self:AddPlayerWithInterruptsToGroup(kDefaultGroup, player:GetName())
	-- Layout GroupWindow
	self:LayoutGroupContainer(self.groups[kDefaultGroup])
	
	-- Create and start timers
	Apollo.CreateTimer("BroadcastTimer", kBroadcastInterval, true)
	Apollo.CreateTimer("UITimer", kUIUpdateInterval, true)
	Apollo.StartTimer("BroadcastTimer")
	
	self.isInitialized = true
end

function InterruptCoordinator:Reset()
	Apollo.StopTimer("BroadcastTimer")
	Apollo.StopTimer("UITimer")
	
	self:LeaveGroupChannels()
	
	for name, group in pairs(self.groups) do
		group.container:DestroyChildren()
		group.container:Destroy()
	end
	
	self.syncChannel = {channel = nil, name = ""}
	self.broadCastChannel = {channel = nil, name = ""}
	self.groupLeaderInfo = nil
	self.currentInterrupts = {}
	self.partyInterrupts = {}
	self.currLAS = nil
	self.groups = {}
	self.players = {}
	
	self.isInitialized = false
	self.isVisible = false
end

function InterruptCoordinator:Show()
	if self.isInitialized and not self.isVisible then
		-- Start UI timer.
		Apollo.StartTimer("UITimer")
		for name, group in pairs(self.groups) do
			group.container:Show(true)
		end
		self.isVisible = true
	end
end

function InterruptCoordinator:Hide()
	if self.isInitialized and self.isVisible then
		-- Stop UI timer.
		Apollo.StartTimer("UITimer")
		for name, group in pairs(self.groups) do
			group.container:Show(false, true)
		end
		self.isVisible = false	
	end
end

function InterruptCoordinator:OnBroadcastTimer()
	-- Check if the remaing cd of some interrupt has changed and if yes, let everyone know.
	local newlyStarted = self:UpdateRemainingCDForCurrentInterrupts()
	local toSend = {}
	local player = GameLib.GetPlayerUnit()
	if not player then return end
	for idx, interrupt in ipairs(self.partyInterrupts[player:GetName()]) do
		if interrupt.onCD then
			if interrupt.remainingCD <= 0 then
				interrupt.remainingCD = 0
			end
			if self:ShouldPeriodicallyBroadcastCDs() or 
			   interrupt.remainingCD == 0 or
			   setContains(newlyStarted, interrupt.ID) then
				table.insert(toSend, interrupt)
			end
		end
	end
	if #toSend > 0 then
		self:SendOnBroadCastChannel({type = MsgType.CD_UPDATE,
									 version = kVersion,
				      				 senderName = player:GetName(), 
				      				 interrupts = toSend})
	end
	
	-- Check if someone of the group is dead.
	local n = GroupLib.GetMemberCount()
	if n == 0 then
		local player = GameLib.GetPlayerUnit()
		if not player then return end
		local playerContainer = self:GetPlayer(player:GetName())
		for _, interrupt in ipairs(playerContainer.interrupts) do
			if player:IsDead() then
				interrupt.bar:FindChild("ProgressBar"):SetBGColor(kProgressBarBGColorDisabled)
			else
				interrupt.bar:FindChild("ProgressBar"):SetBGColor(kProgressBarBGColorEnabled)
			end
			interrupt.bar:FindChild("DisabledOverlay"):Show(player:IsDead())
		end
	else
		for i=1, n do
			local info = GroupLib.GetGroupMember(i)
			if not info then return end
			local isDead = info.nHealth == 0 and info.nHealthMax ~= 0
			local player = self:GetPlayer(info.strCharacterName)
			if not player then return end
			for _, interrupt in ipairs(player.interrupts) do
				if isDead then
					interrupt.bar:FindChild("ProgressBar"):SetBGColor(kProgressBarBGColorDisabled)
				else
					interrupt.bar:FindChild("ProgressBar"):SetBGColor(kProgressBarBGColorEnabled)
				end
				interrupt.bar:FindChild("DisabledOverlay"):Show(isDead)
			end
		end
	end
end

function InterruptCoordinator:OnUITimer()
	-- Update remaining cooldowns and progress bars.
	for groupName, group in pairs(self.groups) do
		for idx, player in ipairs(group.players) do
			for idx, interrupt in ipairs(player.interrupts) do
				local int = self:GetPlayerInterruptForID(player.name, interrupt.ID)
				if int and int.onCD then
					int.remainingCD = int.remainingCD - kUIUpdateInterval
					-- Make sure remainingCD is never < 0.
					if int.remainingCD <= 0 then
						int.remainingCD = 0
						int.onCD = false
					end
					interrupt.remainingCD = int.remainingCD
					interrupt.onCD = int.onCD
				end
				if interrupt.bar:FindChild("ProgressBar") then
					interrupt.bar:FindChild("ProgressBar"):SetProgress(interrupt.remainingCD)
				end
			end
		end
	end
end

function InterruptCoordinator:OnDelayedSyncTimer()
	-- We need this function since sometimes messages don't get sent over a channel if
	-- you just joined them.
	self:SendSyncRequest()
	self:SendPlayerInterrupts()
end
-----------------------------------------------------------------------------------------------
-- InterruptCoordinatorForm Functions
-----------------------------------------------------------------------------------------------
-- when the OK button is clicked
function InterruptCoordinator:OnOK()
	self.wndMain:Close() -- hide the window
end

-- when the Cancel button is clicked
function InterruptCoordinator:OnCancel()
	self.wndMain:Close() -- hide the window
end

function InterruptCoordinator:OnHideGroupContainerButtonPressed(wHandler)
	self:Hide()
end

function InterruptCoordinator:OnSyncButtonPressed(wHandler)
	Apollo.StopTimer("BroadcastTimer")
	Apollo.StopTimer("UITimer")
	for name, interrupts in pairs(self.partyInterrupts) do
		self:RemovePlayerFromGroup(self.playerToGroup[name], name)
	end
	self.partyInterrupts = {}
	self.playerToGroup = {}
	local player = GameLib.GetPlayerUnit()
	if not player then return end
	self.partyInterrupts[player:GetName()] = self:GetCurrentInterrupts()
	self:AddPlayerWithInterruptsToGroup(kDefaultGroup, player:GetName())
	-- Layout GroupWindow
	self:LayoutGroupContainer(self.groups[kDefaultGroup])
	self:OnGroupJoin()
	Apollo.StartTimer("BroadcastTimer")
	Apollo.StartTimer("UITimer")
end

function InterruptCoordinator:OnSave(level)
    if level ~= GameLib.CodeEnumAddonSaveLevel.Character then
        return nil
    end

	-- Create table to hold our save data.
	local saveData = {}
	saveData.left, saveData.top, saveData.right, saveData.bottom = self.groups[kDefaultGroup].container:GetAnchorOffsets()
	return saveData
end

function InterruptCoordinator:OnRestore(level, data)
	self.saveData = data
end
-----------------------------------------------------------------------------------------------
-- LAS Functions
-----------------------------------------------------------------------------------------------
-- Returns the Spell IDs of the interrupts currently slotted in the LAS
function InterruptCoordinator:GetCurrentInterrupts()
	self.currLAS = ActionSetLib.GetCurrentActionSet()

	local interrupts = {}

	if not self.currLAS then return interrupts end
	-- We use spellIds because you can't get description from an abilityId if it is not for your class
	for idx, ID in ipairs(self.currLAS) do
		if Interrupts[ID] then
			local spellID = self:GetTieredSpellIDFromAbilityID(ID)
			local spell = GameLib.GetSpell(spellID)
			if spell then 
				local onCD = false
				if spell:GetCooldownRemaining() > 0 then
					onCD = true
				end
				table.insert(interrupts, {ID = ID,
										  spellID = spellID,
										  cooldown = spell:GetCooldownTime(), 
										  remainingCD = spell:GetCooldownRemaining(),
										  IAremoved = self:GetIARemovedForSpell(ID, spellID),
										  onCD = onCD})
			end
		end
	end
	
	return interrupts
end

-- Updates remaining cooldowns for currently slotted interrupts and returns
-- the ones that are newly started.
function InterruptCoordinator:UpdateRemainingCDForCurrentInterrupts()
	local player = GameLib.GetPlayerUnit()
	if not player then return end
	local newlyStarted = {}
	for idx, interrupt in ipairs(self.partyInterrupts[player:GetName()]) do
		spell = GameLib.GetSpell(interrupt.spellID)
		interrupt.remainingCD = spell:GetCooldownRemaining()
		if interrupt.remainingCD > 0 and not interrupt.onCD then 
			interrupt.onCD = true
			addToSet(newlyStarted, interrupt.ID)
		end
	end
	
	return newlyStarted
end

-- utility function that gets the spellId from abilityId
-- We use an ability window to read out the tiered ability and destroy it immediately
function InterruptCoordinator:GetTieredSpellIDFromAbilityID(ID)
	-- this only works for abilities the player can cast
	local wAbility = Apollo.LoadForm("InterruptCoordinator.xml", "TmpAbilityWin", nil, self)
	wAbility:SetAbilityId(ID)
	local sSpellId = wAbility:GetAbilityTierId()
	wAbility:Destroy()
	return sSpellId
end

function InterruptCoordinator:GetPlayerInterruptForID(playerName, ID)
	if not self.partyInterrupts[playerName] then return nil end
	for idx, interrupt in ipairs(self.partyInterrupts[playerName]) do
		if interrupt.ID == ID then return interrupt end
	end
	return nil
end

function InterruptCoordinator:GetAbilityIDForName(name)
	local abilities = AbilityBook.GetAbilitiesList()
	if not abilities then
		return 0 
	end
	for _, v in pairs(abilities) do
		if v.strName == name then
			return v.nId;
		end
	end
	return 0
end

function InterruptCoordinator:GetCooldownForSpell(spellId)
	local spell = GameLib.GetSpell(spellId)
	local spellName = spell:GetName()
	if spell:GetCooldownTime() and spell:GetCooldownTime() > 0 then 
		return spell:GetCooldownTime() 
	end 
	-- life is not always that easy lets try to get spell cooldown from our 
	-- known interrupt abilities by name matching
	for abilityId, spellIdForBaseTier in pairs(Interrupts) do
		local tmpSpell = GameLib.GetSpell(spellIdForBaseTier )
		if tmpSpell:GetName() == spellName then
			return tmpSpell:GetCooldownTime() 		
		end
	end
end

function InterruptCoordinator:GetIARemovedForSpell(abilityID, spellID)
	local IAremoved = 1
	local spell = GameLib.GetSpell(spellID)
	if not spell then return IAremoved end
	if abilityID == InterruptNamesToAbilityIDs["Gate"] and spell:GetTier() > 4 or
	   abilityID == InterruptNamesToAbilityIDs["Crush"] and spell:GetTier() > 4 or
	   abilityID == InterruptNamesToAbilityIDs["Zap"] and spell:GetTier() > 4 or
	   abilityID == InterruptNamesToAbilityIDs["Kick"] and spell:GetTier() > 8 or
	   abilityID == InterruptNamesToAbilityIDs["Paralytic Surge"] and spell:GetTier() > 4 then
		IAremoved = 2
	end
	return IAremoved
end

function InterruptCoordinator:OnAbilityBookChange()
	if not self.isInitialized then return end
	-- We have to delay the update, since at the time this event fires
	-- we will still get the previously equipped interrupts
	Apollo.CreateTimer("DelayedAbilityBookChange", 0.2, false)
end

function InterruptCoordinator:OnDelayedAbilityBookChange()
	local interrupts = self:GetCurrentInterrupts()
	local player = GameLib.GetPlayerUnit()
	if not player then return end
	self:UpdateBarsForPlayer(player:GetName(), self.partyInterrupts[player:GetName()], interrupts)
	self.partyInterrupts[player:GetName()] = interrupts
	self:LayoutGroupContainer(self.groups[self.playerToGroup[player:GetName()]])
	self:SendOnSyncChannel({type = MsgType.INTERRUPTS_UPDATE,
							version = kVersion,
				  	        senderName = player:GetName(), 
				            interrupts = self.partyInterrupts[player:GetName()]})
end

-----------------------------------------------------------------------------------------------
-- GroupEvent Functions
-----------------------------------------------------------------------------------------------
function InterruptCoordinator:OnGroupJoin()
	if not self.isInitialized then
		self:Initialize()
	end

	local leaderInfo = self:GetGroupLeader()
	if not leaderInfo then
		glog:debug("No Group Leader found!!")
		return
	end
	glog:debug("OnGroupJoin: Group Leader: " .. leaderInfo.strCharacterName)
		
	-- Join the communication channel (if leader change)
	if not self.groupLeaderInfo or self.groupLeaderInfo.strCharacterName ~= leaderInfo.strCharacterName then
		self.groupLeaderInfo = leaderInfo
		self:JoinGroupChannels(self.groupLeaderInfo.strCharacterName)
	end
	
	-- Broadcast our current interrupts on the group channel.
	Apollo.CreateTimer("DelayedSyncTimer", 1, false)
end

function InterruptCoordinator:OnGroupLeft()
	self:Reset()
end

function InterruptCoordinator:GetGroupLeader()
	local leaderInfo = nil
	local n = GroupLib.GetMemberCount()	

	for i=1, n do
		leaderInfo = GroupLib.GetGroupMember(i)
		if leaderInfo.bIsLeader then
			break
		end
	end
	
	return leaderInfo
end

-- Checks if a given player belongs to your group.
function InterruptCoordinator:IsInGroup(playerName)
	local n = GroupLib.GetMemberCount()
	for i=1, n do
		local info = GroupLib.GetGroupMember(i)
		if info.strCharacterName == playerName then
			return true
		end
	end
	
	return false
end
-----------------------------------------------------------------------------------------------
-- CombatLogEvent Functions
-----------------------------------------------------------------------------------------------

function InterruptCoordinator:OnCombatLogCCState(event)
	if not event.unitCaster or not self.isInitialized then return end
	-- Ignore events of non group members
	local player = GameLib.GetPlayerUnit()
	if not player then return end
	local isLocalPlayer = player:GetName() == event.unitCaster:GetName()
	if not event.unitCaster:IsInYourGroup() and not isLocalPlayer then 
		glog:debug("Ignoring combat log event of non-group member.")
		return 
	end
	glog:debug(event.unitCaster:GetName() .. " uses " .. event.splCallingSpell:GetName())
	self:UpdateInterruptFromCombatLogEvent(event.unitCaster:GetName(), event.splCallingSpell)
end

function InterruptCoordinator:OnCombatLogInterrupted(event)
	glog:debug("OnCombatLogInterrupted: " .. dump(event))
end

function InterruptCoordinator:OnCombatLogModifyInterruptArmor(event)
	glog:debug("OnCombatLogModifyInterruptArmor: " .. dump(event))
end

function InterruptCoordinator:UpdateInterruptFromCombatLogEvent(playerName, spell)
	local ID = InterruptNamesToAbilityIDs[spell:GetName()]
	glog:debug(tostring(ID))
	if not ID or not Interrupts[ID] then return end
	local interrupt = self:GetPlayerInterruptForID(playerName, ID)
	-- If we haven't seen this interrupt yet we add it to the list of known interrupts.
	if not interrupt then
		glog:debug(string.format("Add spell from combat log. ID %d, CD %d", spell:GetId(), spell:GetCooldownTime()))
		interrupt = {ID = ID,
					 spellID = spell:GetId(),
				     cooldown = self:GetCooldownForSpell(spell:GetId()),
					 remainingCD = self:GetCooldownForSpell(spell:GetId()),
					 IAremoved = self:GetIARemovedForSpell(ID, spell:GetId()),	 
					 onCD = true}
		-- Add interrupt party interrupts.
		if not self.partyInterrupts[playerName] then
			self.partyInterrupts[playerName] = {}
		end
		table.insert(self.partyInterrupts[playerName], interrupt)
		-- Check if we ever recorded this player before.
		if not self.playerToGroup[playerName] then
			self:AddPlayerToGroup(kDefaultGroup, playerName)
		end
		self:AddBarToPlayer(playerName, interrupt)
		self:LayoutGroupContainer(self.groups[self.playerToGroup[playerName]])
	elseif interrupt.remainingCD < 5 then
		interrupt.remainingCD = interrupt.cooldown
		interrupt.onCD = true
	end
end

-----------------------------------------------------------------------------------------------
-- Communication Functions
-----------------------------------------------------------------------------------------------
-- Joins the group channel for inter addon communication.
function InterruptCoordinator:JoinGroupChannels(leaderName)
	-- Join the sync channel.
	local syncName = string.format("IC_sync_%s", leaderName)
	if self.syncChannel.name ~= syncName then
		self.syncChannel.name = syncName
		self.syncChannel.channel = ICCommLib.JoinChannel(syncName, "OnCommMessageReceived", self)
		glog:debug("Joined channel " .. syncName)
	end
	-- Join broadcast channel.
	local bcName = string.format("IC_bc_%s", leaderName)
	if self.broadCastChannel.name ~= bcName then
		self.broadCastChannel.name = bcName
		self.broadCastChannel.channel = ICCommLib.JoinChannel(bcName, "OnCommMessageReceived", self)
		glog:debug("Joined channel " .. bcName)
	end
end

-- Leaves the group channel
function InterruptCoordinator:LeaveGroupChannels()
end

function InterruptCoordinator:OnICCommJoinResult(result)
	glog:debug(dump(result))
end

-- Send a message on the communication channel.
function InterruptCoordinator:SendOnBroadCastChannel(msg)
	-- Sanity check for broadcast channel.
	if self.groupLeaderInfo then
		local expectedName = string.format("IC_bc_%s", self.groupLeaderInfo.strCharacterName)
		if self.broadCastChannel.name ~= expectedName then
			glog:warn("You are in the wrong broadcast channel for this group.\n" ..
					  "Current: " .. self.broadCastChannel.name .. "\n" ..
					  "Expected: " .. expectedName)
			return
		end
	end
	if self.broadCastChannel.channel then
		self.broadCastChannel.channel:SendMessage(msg)
		--glog:debug(string.format("Send message on channel %d: %s", idx, dump(msg))) 
	end
end

function InterruptCoordinator:SendOnSyncChannel(msg)
	-- Sanity check for sync channel.
	if self.groupLeaderInfo then
		local expectedName = string.format("IC_sync_%s", self.groupLeaderInfo.strCharacterName)
		if self.syncChannel.name ~= expectedName then
			glog:warn("You are in the wrong broadcast channel for this group.\n" ..
					  "Current: " .. self.syncChannel.name .. "\n" ..
					  "Expected: " .. expectedName)
			return
		end
	end
	if self.syncChannel.channel then
		self.syncChannel.channel:SendMessage(msg)
		--glog:debug(string.format("Send message on channel %d: %s", idx, dump(msg))) 
	end
end

-- Broadcasts the local player interrupts.
function InterruptCoordinator:SendPlayerInterrupts()
	local player = GameLib.GetPlayerUnit()
	if not player then return end
	self:SendOnSyncChannel({type = MsgType.INTERRUPTS_UPDATE,
							version = kVersion, 
				            senderName = player:GetName(), 
				            interrupts = self.partyInterrupts[player:GetName()]})
end

-- Broadcast a sync request.
function InterruptCoordinator:SendSyncRequest()
	local player = GameLib.GetPlayerUnit()
	if not player then return end
	self:SendOnSyncChannel({type = MsgType.SYNC_REQUEST,
							version = kVersion,
				  			senderName = player:GetName()})
end

-- Main message handling routine.
function InterruptCoordinator:OnCommMessageReceived(channel, msg)
	-- Ignore messages of non group members.
	if not self:IsInGroup(msg.senderName) then 
		glog:debug("Ignoring message from non-group member " .. msg.senderName)
		return 
	end
	if not msg.version or msg.version < kMinVersion then
		glog:info("Ignoring message from " .. msg.senderName .. ". Addon version too old.")
		return
	end
	if msg.type == MsgType.INTERRUPTS_UPDATE then
		glog:debug("Received interrupts update from " .. msg.senderName .. ":\n" .. dump(msg.interrupts))
		-- Check if this a new player.
		if not self.playerToGroup[msg.senderName] then
			-- Add player to group.
			self:AddPlayerToGroup(kDefaultGroup, msg.senderName)
		end
		
		self:UpdateBarsForPlayer(msg.senderName, self.partyInterrupts[msg.senderName], msg.interrupts)
		self.partyInterrupts[msg.senderName] = msg.interrupts
		
		-- Layout window.
		self:LayoutGroupContainer(self.groups[self.playerToGroup[msg.senderName]])
	elseif msg.type == MsgType.CD_UPDATE then
		-- Update remaining cooldowns.
		for idx, interrupt in ipairs(msg.interrupts) do
			glog:debug("Received CD_UPDATE from " .. msg.senderName .. " for spell " .. tostring(interrupt.ID) ..
				   	   ". Remaining CD: " .. interrupt.remainingCD .. " s.")
			local int = self:GetPlayerInterruptForID(msg.senderName, interrupt.ID)
			if not int then
				glog:debug("Received CD update for untracked spell.")
				return
			end
			-- Update spell id from broadcast if necessary.
			if int.spellID ~= interrupt.spellID then
				int.spellID = interrupt.spellID
			end
			if not int.onCD or int.remainingCD > interrupt.remainingCD then
				int.remainingCD = interrupt.remainingCD
				int.onCD = true
				if int.remainingCD <= 0 then
					int.remainingCD = 0
				end
			end
		end
	elseif msg.type == MsgType.SYNC_REQUEST then
		-- Broadcast local interrupts.
		glog:debug("Received SYNC_REQUEST from " .. msg.senderName)
		self:SendPlayerInterrupts()
	end
end

-- Only the classes with dynamic cooldown reducing effects (SS, Medic, Esper) will periodically
-- broadcast their remaining cooldowns (to save bandwith on the comm channel).
function InterruptCoordinator:ShouldPeriodicallyBroadcastCDs()
	local player = GameLib.GetPlayerUnit()
	if not player then return false end
	if player:GetClassId() == GameLib.CodeEnumClass.Spellslinger or
	   player:GetClassId() == GameLib.CodeEnumClass.Medic or
	   player:GetClassId() == GameLib.CodeEnumClass.Esper then
		return true
	else
		return false
	end
end
-----------------------------------------------------------------------------------------------
-- GUI builders
-----------------------------------------------------------------------------------------------
-- Creates a new group with a given name.
-- We only support one group at the moment.
function InterruptCoordinator:NewGroup(groupName)
	-- Check if group with this name already exists.
	if self.groups[groupName] then 
		glog:debug("A group with that name already exists.")
		return 
	end
	local group = {}
	group.container = Apollo.LoadForm(self.xmlDoc, "GroupContainer", nil, self)
	group.container:SetData({groupName = groupName})
	if self.saveData then
		group.container:SetAnchorOffsets(self.saveData.left, self.saveData.top,
										 self.saveData.left + kGroupContainerWidth, self.saveData.bottom)
	end
	group.players = {}
	self.groups[groupName] = group
end

-- Adds a member to a group
function InterruptCoordinator:AddPlayerToGroup(groupName, playerName)
	-- Check that member not in a group already.
	if self.playerToGroup[playerName] then
		glog:debug(playerName .. " is already in a group.")
		return
	end
	-- Check that group exists.
	if not self.groups[groupName] then
		glog:debug("Group '" .. groupName .. "' doesn't exist.")
		return
	end
	
	self.playerToGroup[playerName] = groupName
	--local n = #self.groups[groupName].members
	local player = {}
	player.name = playerName
	player.container = Apollo.LoadForm(self.xmlDoc, "PlayerContainer", self.groups[groupName].container, self)
	player.container:FindChild("PlayerName"):SetText(playerName)
	player.interrupts = {}
	table.insert(self.groups[groupName].players, player)
	glog:debug("Added " .. playerName .. "to group " .. groupName)
end

function InterruptCoordinator:RemovePlayerFromGroup(groupName, playerName)
	if not groupName then return end
	if not self.playerToGroup[playerName] or groupName ~= self.playerToGroup[playerName] then
		glog:debug(playerName .. " doesn't belong to group '" .. groupName .. "'.")
		return
	end
	local group = self.groups[groupName]
	local player = nil
	local idx = 0
	for _, p in ipairs(group.players) do
		idx = idx + 1
		glog:debug("pname " .. p.name)
		if p.name and p.name == playerName then
			player = p
			break
		end
	end
	if not player then
		glog:debug("Tried to remove non existant player.")
		return
	end
	glog:debug("Remove player " .. playerName .. " from group " .. groupName)
	self.playerToGroup[playerName] = nil
	player.container:Destroy()
	table.remove(group.players, idx)
end

-- Adds a bar for a given interrupt to the player frame.
function InterruptCoordinator:AddBarToPlayer(playerName, newInterrupt)
	local player = self:GetPlayer(playerName)
	if not player then
		glog:debug("Tried to add bar to non-existing player!")
		return
	end
	-- Make sure we only have one bar for each interrupt.
	for k, v in pairs(player.interrupts) do
		if v.ID and v.ID == newInterrupt.ID then
			glog:debug("Bar for this interrupt (" .. newInterrupt.ID .. ") already exists.")
			return
		end
	end
	local interrupt = {}
	interrupt.ID = newInterrupt.ID
	interrupt.spellID = newInterrupt.spellID
	interrupt.cooldown = newInterrupt.cooldown
	interrupt.remainingCD = newInterrupt.remainingCD
	interrupt.IAremoved = newInterrupt.IAremoved
	interrupt.onCD = newInterrupt.onCD
	interrupt.bar = Apollo.LoadForm(self.xmlDoc, "BarContainer", player.container, self)
	interrupt.bar:FindChild("ProgressBar"):SetMax(newInterrupt.cooldown)
	interrupt.bar:FindChild("ProgressBar"):SetProgress(newInterrupt.remainingCD)
	interrupt.bar:FindChild("Icon"):SetSprite(GameLib.GetSpell(newInterrupt.spellID):GetIcon())
	interrupt.bar:FindChild("Icon"):Show(true)
	interrupt.bar:FindChild("IARemovedIcon"):SetText(newInterrupt.IAremoved)
	interrupt.bar:FindChild("IARemovedIcon"):Show(true)
	table.insert(player.interrupts, interrupt)
	glog:debug("Added interrupt " .. newInterrupt.ID .. " to player " .. playerName)
end

function InterruptCoordinator:RemoveBarFromPlayer(playerName, ID)
	local player = self:GetPlayer(playerName)
	if not player then
		glog:debug("Tried to remove bar from non-existing player!")
		return
	end
	-- Make sure the player actually has a bar for this spell.
	local interrupt = nil
	local idx = 0
	for _, v in ipairs(player.interrupts) do
		idx = idx + 1
		if v.ID and v.ID == ID then
			interrupt = v
			break
		end
	end
	if not interrupt then 
		glog:debug("Tried to remove bar for non existing interrupt " .. tostring(ID) .. " from " .. playerName)
		return
	end
	glog:debug("Remove interrupt " .. tostring(ID) .. " from player " .. playerName)
	-- Destroy bar.
	interrupt.bar:Destroy()
	-- Remove interrupt.
	table.remove(player.interrupts, idx)
end

function InterruptCoordinator:UpdateBarsForPlayer(playerName, prevInterrupts, newInterrupts)
	if prevInterrupts then
		-- Remove bar for all previous Interrupts.
		for idx, interrupt in ipairs(prevInterrupts) do
			self:RemoveBarFromPlayer(playerName, interrupt.ID)
		end
	end
			
	if newInterrupts then
		-- Add progression bar for each interrupt.
		for idx, interrupt in ipairs(newInterrupts) do
			self:AddBarToPlayer(playerName, interrupt) 
		end
	end
end

function InterruptCoordinator:AddPlayerWithInterruptsToGroup(groupName, playerName)
	self:AddPlayerToGroup(groupName, playerName)
	-- Add bar for each interrupt currently equipped
	for idx, interrupt in ipairs(self.partyInterrupts[playerName]) do
		self:AddBarToPlayer(playerName, interrupt) 
	end

end

-- Layout Group container.
function InterruptCoordinator:LayoutGroupContainer(group)
	if not group then return end
	-- We first call LayoutPlayerContainer for each player of the group
	-- and use the returned totalHeights to layout the group container.
	local totalHeight = 15
	for idx, player in spairs(group.players, sortByName) do
		local height = self:LayoutPlayerContainer(player)
		local l, t, r, b = player.container:GetAnchorOffsets()
		player.container:SetAnchorOffsets(l, totalHeight, r, totalHeight + height)
		totalHeight = totalHeight + kVerticalPlayerPadding + height
	end
	-- Set height of group container to totalHeight
	local l, t, r, b = group.container:GetAnchorOffsets()
	group.container:SetAnchorOffsets(l, t, r, t + totalHeight)
end

-- Layout Player container.
function InterruptCoordinator:LayoutPlayerContainer(player)
	local ninterrupts = #player.interrupts
	-- Set total height to be kPlayerNameHeight  + ninterrupts * (kBarHeight + kVerticalPadding)
	local totalHeight = kPlayerNameHeight + ninterrupts * (kBarHeight + kVerticalBarPadding)
	local l, t, r, b = player.container:GetAnchorOffsets()
	player.container:SetAnchorOffsets(l, t, r, totalHeight)
	
	-- Layout interrupt bars.
	local voffset = kPlayerNameHeight + kVerticalBarPadding
	for idx, interrupt in spairs(player.interrupts, sortByID) do
		l, t, r, b = interrupt.bar:GetAnchorOffsets()
		interrupt.bar:SetAnchorOffsets(l, voffset, r, voffset + kBarHeight)
		voffset = voffset + kBarHeight + kVerticalBarPadding
	end 
	return totalHeight
end

function InterruptCoordinator:GetPlayer(playerName)
	if not self.playerToGroup[playerName] then
		--glog:debug(playerName .. " is not in a group yet.")
		return
	end
	local group = self.groups[self.playerToGroup[playerName]]
	local player = nil
	for idx, p in ipairs(group.players) do
		if p.name == playerName then 
			player = p
			break
		end
	end
	
	return player
end

-----------------------------------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------------------------------
function dump(o)
	if type(o) == 'table' then
		local s = '{ '
		for k,v in pairs(o) do
			if type(k) ~= 'number' then k = '"'..k..'"' end
				s = s .. '['..k..'] = ' .. dump(v) .. ','
		end
		return s .. '} '
	else
		return tostring(o)
	end
end

function splitString(inputstr, sep)
	if sep == nil then
    	sep = "%s"
    end
    local t = {}
	local i = 1
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    	t[i] = str
        i = i + 1
    end
    return t
end

function addToSet(set, key)
    set[key] = true
end

function removeFromSet(set, key)
    set[key] = nil
end

function setContains(set, key)
    return set[key] ~= nil
end

-- Iterates over table in a given order (sorted by keys per default)
function spairs(t, order)
    -- collect the keys
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end

    -- if order function given, sort by it by passing the table and keys a, b,
    -- otherwise just sort the keys 
    if order then
        table.sort(keys, function(a,b) return order(t, a, b) end)
    else
        table.sort(keys)
    end

    -- return the iterator function
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
end

function sortByName(t, a, b)
	return t[a].name < t[b].name
end

function sortByID(t, a, b)
	return t[a].ID < t[b].ID
end

-----------------------------------------------------------------------------------------------
-- InterruptCoordinator Instance
-----------------------------------------------------------------------------------------------
local InterruptCoordinatorInst = InterruptCoordinator:new()
InterruptCoordinatorInst:Init()
