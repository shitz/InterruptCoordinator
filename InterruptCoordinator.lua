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

local MsgType = {
	--SLOTTED_INTERRUPTS = 1,
	INTERRUPTS_UPDATE = 1,
	CD_UPDATE = 2,
	SYNC_REQUEST = 3,
}

local kBarHeight = 25
local kPlayerNameHeight = 18
local kVerticalBarPadding = 0
local kVerticalPlayerPadding = 0

local kDefaultGroup = "Main"

local kUIUpdateInterval = 0.033
local kBroadcastInterval = 1

local kNumOfChannels = 3
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function InterruptCoordinator:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    -- initialize variables here
	self.commChannels = {}
	self.groupLeaderInfo = nil
	self.partyInterrupts = {}
	self.currLAS = nil
	self.groups = {}
	self.playerToGroup = {}
	self.isInitialized = false
	self.isVisible = false
	--self.playerToInterrupts = {}
	
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
	glog:debug("OnLoad")
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
		-- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)
		Apollo.RegisterSlashCommand("ic", "OnInterruptCoordinatorOn", self)
		
		Apollo.RegisterEventHandler("Group_Join", "OnGroupJoin", self)
		Apollo.RegisterEventHandler("Group_Left", "OnGroupLeft", self)
		Apollo.RegisterEventHandler("Group_Updated", "OnGroupUpdated", self)

		Apollo.RegisterEventHandler("CombatLogCCState", "OnCombatLogCCState", self)
		Apollo.RegisterEventHandler("CombatLogInterrupted", "OnCombatLogInterrupted", self)

		Apollo.RegisterEventHandler("AbilityBookChange", "OnAbilityBookChange", self)
		Apollo.RegisterTimerHandler("DelayedAbilityBookChange", "OnDelayedAbilityBookChange", self)
		
		Apollo.RegisterTimerHandler("DelayedSyncTimer", "OnDelayedSyncTimer", self)

		Apollo.RegisterEventHandler("CombatLogModifyInterruptArmor", "OnCombatLogModifyInterruptArmor", self)
		
		Apollo.RegisterTimerHandler("BroadcastTimer", "OnBroadcastTimer", self)
		Apollo.RegisterTimerHandler("UITimer", "OnUITimer", self)
		-- Do additional Addon initialization here
	end
	glog:debug("OnDocLoaded")
end

-----------------------------------------------------------------------------------------------
-- InterruptCoordinator Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here

-- on SlashCommand "/ic"
function InterruptCoordinator:OnInterruptCoordinatorOn(cmd, arg)
	-- show the window
	--ints = self:GetCurrentInterrupts()
	--glog:debug(dump(ints))
	if arg == "init" then
		self:Initialize()
		self:Show()
	elseif arg == "reset" then
		self:Reset()
	elseif arg == "show" then
		self:Show()
	elseif arg == "hide" then
		self:Hide()
	elseif arg == "sync" then
		self:OnGroupJoin()
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
	
	self:LeaveGroupChannel()
	
	for name, group in pairs(self.groups) do
		group.container:DestroyChildren()
		group.container:Destroy()
	end
	
	self.commsChannel = {}
	self.groupLeaderInfo = nil
	self.currentInterrupts = {}
	self.partyInterrupts = {}
	self.currLAS = nil
	self.groups = {}
	self.playerToGroup = {}
	
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
	self:UpdateRemainingCDForCurrentInterrupts()
	local toSend = {}
	local player = GameLib.GetPlayerUnit()
	if not player then return end
	for idx, interrupt in ipairs(self.partyInterrupts[player:GetName()]) do
		if interrupt.onCD then
			if interrupt.remainingCD <= 0 then
				interrupt.remainingCD = 0
				interrupt.onCD = false
			end
			table.insert(toSend, interrupt)
		end
	end
	if #toSend > 0 then
		self:SendMsg({type = MsgType.CD_UPDATE, 
				      senderName = player:GetName(), 
				      interrupts = toSend})
	end
	
	-- Update remaining cooldowns.
	for groupName, group in pairs(self.groups) do
		for idx, player in ipairs(group.players) do
			for idx, interrupt in ipairs(player.interrupts) do
				local int = self:GetPlayerInterruptForSpellID(player.name, interrupt.spellID)
				-- Only update if remaining cooldown has changed.
				if int and int.onCD then
					interrupt.remainingCD = int.remainingCD
					-- Make sure remainingCD is never < 0.
					if interrupt.remainingCD <= 0 then
						interrupt.remainingCD = 0
						interrupt.onCD = false
					else
						interrupt.onCD = true
					end
				end
			end
		end
	end
end

function InterruptCoordinator:OnUITimer()
	-- Update progress bars.
	for groupName, group in pairs(self.groups) do
		for idx, player in ipairs(group.players) do
			for idx, interrupt in ipairs(player.interrupts) do
				if interrupt.onCD then 
					interrupt.remainingCD = interrupt.remainingCD - kUIUpdateInterval
					-- Make sure remainingCD is never < 0.
					if interrupt.remainingCD <= 0 then
						interrupt.remainingCD = 0
						interrupt.onCD = false
					end
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
				table.insert(interrupts, {spellID = spellID, 
										  cooldown = spell:GetCooldownTime(), 
										  remainingCD = spell:GetCooldownRemaining(),
										  onCD = onCD})
			end
		end
	end
	
	return interrupts
end

-- Updates remaining cooldowns for currently slotted interrupts
function InterruptCoordinator:UpdateRemainingCDForCurrentInterrupts()
	local player = GameLib.GetPlayerUnit()
	if not player then return end
	for idx, interrupt in ipairs(self.partyInterrupts[player:GetName()]) do
		spell = GameLib.GetSpell(interrupt.spellID)
		interrupt.remainingCD = spell:GetCooldownRemaining()
		if interrupt.remainingCD > 0 then 
			interrupt.onCD = true
		end
	end
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

function InterruptCoordinator:GetPlayerInterruptForSpellID(playerName, spellID)
	if not self.partyInterrupts[playerName] then return nil end
	for idx, interrupt in ipairs(self.partyInterrupts[playerName]) do
		if interrupt.spellID == spellID then return interrupt end
	end
	return nil
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
	self:SendMsg({type = MsgType.INTERRUPTS_UPDATE, 
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

-----------------------------------------------------------------------------------------------
-- Communication Functions
-----------------------------------------------------------------------------------------------
-- Joins the group channel for inter addon communication.
function InterruptCoordinator:JoinGroupChannels(leaderName)
	--if #self.commChannels == kNumOfChannels then return end
	
	for i=1,kNumOfChannels do
		local cname = string.format("IC_%s_%d", leaderName, i)
		self.commChannels[i] = ICCommLib.JoinChannel(cname, "OnCommMessageReceived", self)
		glog:debug("Joined channel " .. cname)
	end
end

-- Leaves the group channel
function InterruptCoordinator:LeaveGroupChannels()
	self.commChannels = {}
end

-- Send a message on the communication channel.
function InterruptCoordinator:SendMsg(msg)
	if #self.commChannels == kNumOfChannels then
		--glog:debug("Send message: " .. dump(msg))
		local idx = math.random(kNumOfChannels)
		self.commChannels[idx]:SendMessage(msg)
		glog:debug(string.format("Send message on channel %d: %s", i, dump(msg))) 
	end
end

-- Broadcasts the local player interrupts.
function InterruptCoordinator:SendPlayerInterrupts()
	local player = GameLib.GetPlayerUnit()
	if not player then return end
	self:SendMsg({type = MsgType.INTERRUPTS_UPDATE, 
				  senderName = player:GetName(), 
				  interrupts = self.partyInterrupts[player:GetName()]})
end

-- Broadcast a sync request.
function InterruptCoordinator:SendSyncRequest()
	local player = GameLib.GetPlayerUnit()
	if not player then return end
	self:SendMsg({type = MsgType.SYNC_REQUEST,
				  senderName = player:GetName()})
end

-- Main message handling routine.
function InterruptCoordinator:OnCommMessageReceived(channel, msg)
	-- Check the channel is currently one of the used ones.
	local found = false
	for idx, chan in ipairs(self.commChannels) do
		if chan == channel then
			found = true
			break
		end
	end	
	if not found then
		glog:debug("Received message on unknown channel.")
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
			glog:debug("Received CD_UPDATE from " .. msg.senderName .. " for spell " .. tostring(interrupt.spellID) ..
				   	   ". Remaining CD: " .. interrupt.remainingCD .. " s.")
			local int = self:GetPlayerInterruptForSpellID(msg.senderName, interrupt.spellID)
			if not int then
				glog:debug("Received cooldown update for untracked spell.")
				return
			end
			int.remainingCD = interrupt.remainingCD
			int.onCD = true
			if int.remainingCD <= 0 then
				int.remainingCD = 0
			end
		end
	elseif msg.type == MsgType.SYNC_REQUEST then
		-- Broadcast local interrupts.
		glog:debug("Received SYNC_REQUEST from " .. msg.senderName)
		self:SendPlayerInterrupts()
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
										 self.saveData.right, self.saveData.bottom)
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
	player.container:Destroy()
	table.remove(group.players, idx)
end

-- Adds a bar for a given interrupt to the player frame.
function InterruptCoordinator:AddBarToPlayer(playerName, spellID, CD, remainingCD, onCD)
	local player = self:GetPlayer(playerName)
	if not player then
		glog:debug("Tried to add bar to non-existing player!")
		return
	end
	-- Make sure we only have one bar for each interrupt.
	for k, v in pairs(player.interrupts) do
		if v.spellID and v.spellID == spellID then
			glog:debug("Bar for this interrupt (" .. spellID .. ") already exists.")
			return
		end
	end
	local interrupt = {}
	interrupt.spellID = spellID
	interrupt.cooldown = CD
	interrupt.remainingCD = remainingCD
	interrupt.onCD = onCD
	interrupt.bar = Apollo.LoadForm(self.xmlDoc, "BarContainer", player.container, self)
	interrupt.bar:FindChild("ProgressBar"):SetMax(CD)
	interrupt.bar:FindChild("ProgressBar"):SetProgress(remainingCD)
	interrupt.bar:FindChild("Icon"):SetSprite(GameLib.GetSpell(spellID):GetIcon())
	interrupt.bar:FindChild("Icon"):Show(true)
	table.insert(player.interrupts, interrupt)
	glog:debug("Added interrupt " .. spellID .. " to player " .. playerName)
end

function InterruptCoordinator:RemoveBarFromPlayer(playerName, spellID)
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
		if v.spellID and v.spellID == spellID then
			interrupt = v
			break
		end
	end
	if not interrupt then 
		glog:debug("Tried to remove bar for non existing interrupt " .. tostring(spellID) .. " from " .. playerName)
		return
	end
	glog:debug("Remove interrupt " .. tostring(spellID) .. " from player " .. playerName)
	-- Destroy bar.
	interrupt.bar:Destroy()
	-- Remove interrupt.
	table.remove(player.interrupts, idx)
end

function InterruptCoordinator:UpdateBarsForPlayer(playerName, prevInterrupts, newInterrupts)
	if prevInterrupts then
		-- Remove bar for all previous Interrupts.
		for idx, interrupt in ipairs(prevInterrupts) do
			self:RemoveBarFromPlayer(playerName, interrupt.spellID)
		end
	end
			
	if newInterrupts then
		-- Add progression bar for each interrupt.
		for idx, interrupt in ipairs(newInterrupts) do
			self:AddBarToPlayer(playerName, interrupt.spellID, interrupt.cooldown, interrupt.remainingCD, interrupt.onCD) 
		end
	end
end

function InterruptCoordinator:AddPlayerWithInterruptsToGroup(groupName, playerName)
	self:AddPlayerToGroup(groupName, playerName)
	-- Add bar for each interrupt currently equipped
	for idx, interrupt in ipairs(self.partyInterrupts[playerName]) do
		self:AddBarToPlayer(playerName, interrupt.spellID, interrupt.cooldown, 
							interrupt.remainingCD, interrupt.onCD) 
	end

end

-- Layout Group container.
function InterruptCoordinator:LayoutGroupContainer(group)
	if not group then return end
	-- We first call LayoutPlayerContainer for each player of the group
	-- and use the returned totalHeights to layout the group container.
	local totalHeight = 15
	for idx, player in ipairs(group.players) do
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
	for idx, interrupt in ipairs(player.interrupts) do
		l, t, r, b = interrupt.bar:GetAnchorOffsets()
		interrupt.bar:SetAnchorOffsets(l, voffset, r, voffset + kBarHeight)
		voffset = voffset + kBarHeight + kVerticalBarPadding
	end 
	return totalHeight
end

function InterruptCoordinator:GetPlayer(playerName)
	if not self.playerToGroup[playerName] then
		glog:debug(playerName .. " is not in a group yet.")
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

-----------------------------------------------------------------------------------------------
-- InterruptCoordinator Instance
-----------------------------------------------------------------------------------------------
local InterruptCoordinatorInst = InterruptCoordinator:new()
InterruptCoordinatorInst:Init()
