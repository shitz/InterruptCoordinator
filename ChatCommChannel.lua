local Apollo = Apollo
local GameLib = GameLib
local GroupLib = GroupLib
local setmetatable = setmetatable
local unpack = unpack
local tonumber = tonumber
local Print = Print
local math = math
local next = next
local pairs = pairs
local ipairs = ipairs
local table = table
local string = string
local type = type
local os = os
local ChatSystemLib = ChatSystemLib
local tostring = tostring
-- --------------------------------------------------------------
-- ------------------ MODULE CLASS -------------------------
-- --------------------------------------------------------------
local ChatCommChannel  = {}
ChatCommChannel.__index = ChatCommChannel
 
setmetatable(ChatCommChannel, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})
 
function ChatCommChannel.new()
	local self = setmetatable({}, ChatCommChannel)
	self.sChannelName = nil
	self.sCallBackHandler = nil
	self.tCallBackTarget = nil
	self.json = Apollo.GetPackage("Lib:dkJSON-2.5").tPackage
	if not self.json then 
		Print("LibJSON not found")
		return nil 
	end
	self.geminiHook = Apollo.GetPackage("Gemini:Hook-1.0").tPackage
	if not self.geminiHook then
		Print("GeminiHook not found")
		return
	end
	self.geminiHook:Embed(self)
	self.chatAddon = nil
	self.tInputBuffer = {}
	self.tOutputBuffer = {}
	self.fLastClock = nil
	self.Floodlimit = 0
	self.RanDelay = 0
	Apollo.RegisterTimerHandler("ChatChannelTimer", "OnTimer", self)
	Apollo.RegisterEventHandler("ChatMessage", "OnChatMessage", self)
	Apollo.CreateTimer("ChatChannelTimer", 0.1, true)
	Apollo.StopTimer("ChatChannelTimer")
	return self
end
 
function ChatCommChannel:Leave(Channel)
	local strChannel
	if type(Channel)=="string" then
		strChannel = Channel
	elseif type(Channel)=="nil" then
		strChannel = self.sChannelName
	else
		strChannel = Channel:GetName()
	end
	local channel
	for k,v in pairs(ChatSystemLib.GetChannels()) do
		if v:GetName()==strChannel then
			v:Leave()
			break
		end
	end
	self:UnhookAll()
	self.sChannelName = nil
	Apollo.StopTimer("ChatChannelTimer")
end
 
function ChatCommChannel:Join(strChannel, callBackHandler, callBackTarget)
	if self.sChannelName ~= strChannel then
		if self.sChannelName then self:Leave(self.sChannelName) end
		-- check if already in this channel
		local bInChannel = false
		if ChatSystemLib.GetChannels() then
			for k,v in pairs(ChatSystemLib.GetChannels()) do
				if (v and v:GetName() and v:GetName()==strChannel) then
					bInChannel=true
					break
				end
			end
		end

		if not bInChannel then ChatSystemLib.JoinChannel(strChannel) end
		self.sChannelName = strChannel
		self.sCallBackHandler = callBackHandler
		self.tCallBackTarget = callBackTarget
	end

	-- Hide this Channel from Chat Addons
	local chanType
	for k,v in pairs(ChatSystemLib.GetChannels()) do
		--Print(v:GetName() .. " " .. v:GetType())
		if v:GetName()==strChannel then chanType=v:GetType() break end
	end
	local chatAddons = {
		"ChatLog",
		"BetterChatLog",
		"ChatFixed",
		"ImprovedChatLog"
	}
	for k,v in pairs(chatAddons) do
		self.chatAddon = Apollo.GetAddon(v)
		if self.chatAddon then break end
	end

	if self.chatAddon then
		self:RawHook(self.chatAddon, "OnChatMessage", "ChatMessageHook")
	end
end
 
function ChatCommChannel:SendMessage(message)
	local strMessage="Could not serialize data"
	if type(message)=="table" then
		if not message.strSender then message.strSender = GameLib.GetPlayerUnit():GetName() end
		strMessage = self.json.encode(message)
	elseif ((type(message)=="boolean") or (type(message)=="number")) then
		strMessage = tostring(message)
	elseif (type(message)=="string") then
		strMessage = message
	end
	local limit = 400
	-- if message is too long, we need to split it up
	if #strMessage > limit then
		local tMessages={}
		local tMessageProto={}
		local tBigChunks={}
		local tChunkCount={}
		local nChunksCharCount = 0
		local nChunkCount = 0
		local charcount = 0
		for k,v in pairs(message) do
			local strValue = self.json.encode(v)
			local nCount = #strValue+#k+10
			if (nCount+charcount) < (limit) then
					--Print("Key "..k.." is small enough ("..(nCount).." Letters)")
					tMessageProto[k] = v
					charcount = charcount + nCount
			else
					--Print("Key "..k.." has to be broken up ("..(nCount).." Letters)")
					tBigChunks[k] = self.json.encode(v)
					tChunkCount[k] = nCount
					nChunksCharCount = nChunksCharCount + nCount
					nChunkCount = nChunkCount + 1
			end
		end

		local lastpart = math.ceil((nChunksCharCount+(nChunkCount*charcount))/limit)
		for key, BigChunk in pairs(tBigChunks) do
			local to = math.ceil((tChunkCount[key])/(limit-charcount))
			for i=1, to do
				tMessages[#tMessages+1] = self:GetCopy(tMessageProto)
				local starting, ending
				if i == 1 then starting = 0
				else starting = (i-1)*(limit-charcount)+1 end
				if (i*(limit-charcount)+1) > tChunkCount[key] then ending = tChunkCount[key]
				else ending = (i*(limit-charcount)) end

				tMessages[#tMessages]._id = tostring(tMessageProto):sub(7)
				tMessages[#tMessages]._key = key
				tMessages[#tMessages]._lastpart = lastpart
				tMessages[#tMessages]._data = BigChunk:sub(starting, ending)
				--Print("Chunk "..i..": "..tMessage._data)
			end
		end

		for index,message in pairs(tMessages) do
			message._part = index
			self:PushToOB(self.json.encode(message))
		end
	else
		self:PushToOB(self.json.encode(message))
	end
end
 
function ChatCommChannel:PushToOB(strMessage)
	if #self.tOutputBuffer == 0 then
		Apollo.StartTimer("ChatChannelTimer")
	end
    self.tOutputBuffer[#self.tOutputBuffer+1] = strMessage
end
 
function ChatCommChannel:OnTimer()
	if self.Floodlimit > 0 then self.Floodlimit = self.Floodlimit - (os.clock()-self.fLastClock) self.fLastClock = os.clock() Print("Floodlimit for "..self.Floodlimit) return end
	if self.RanDelay > 0 then self.RanDelay = self.RanDelay - (os.clock()-self.fLastClock) self.fLastClock = os.clock() Print("Random Delay for "..self.RanDelay) return end
	if #self.tOutputBuffer>0 then
		if self.sChannelName then
			for k,v in pairs(ChatSystemLib.GetChannels()) do
				if (v:GetName()==self.sChannelName and v:CanSend()) then
					--Print("SendMessage: " .. self.tOutputBuffer[1])
					v:Send(table.remove(self.tOutputBuffer, 1))
					self.RanDelay=math.random(0.001, 0.5)
				end
			end
		end
	else
		Apollo.StopTimer("ChatChannelTimer")
	end
end
 
function ChatCommChannel:OnChatMessage(channelCurrent, tMessage)
	if (channelCurrent:GetType() == 1) then
		local strMessage = ""
		for idx, tSegment in ipairs(tMessage.arMessageSegments) do
			strMessage = strMessage .. tSegment.strText
		end
		if strMessage:find("Error: You have sent too many messages") then self.Floodlimit = 5 end
	end
	if ((channelCurrent:GetName() == self.sChannelName) and (GameLib.GetPlayerUnit() and tMessage.strSender ~= GameLib.GetPlayerUnit():GetName())) then
		-- get message
		local strMessage = ""
		for idx, tSegment in ipairs(tMessage.arMessageSegments) do
			strMessage = strMessage .. tSegment.strText
		end
		-- if this message is in the buffer, delete it
		for i,v in ipairs(self.tOutputBuffer) do
				if v==strMessage then table.remove(self.tOutputBuffer, i) end
		end
		local tMsg = self.json.decode(strMessage)
		if tMsg then
			-- if its a partial message
			if tMsg._part then
				--Print("Received Part "..tMsg._part.." of "..tMsg._lastpart)
				if not self.tInputBuffer[tMsg._id] then self.tInputBuffer[tMsg._id] = {} end

				if not self.tInputBuffer[tMsg._id][tMsg._key] then
						self.tInputBuffer[tMsg._id][tMsg._key] = tMsg
				else
						self.tInputBuffer[tMsg._id][tMsg._key]._data = self.tInputBuffer[tMsg._id][tMsg._key]._data..tMsg._data
				end
				--Print("Current Data for Key "..tMsg._key..": "..self.tInputBuffer[tMsg._id][tMsg._key]._data)

				if tMsg._part >= tMsg._lastpart then
					for k,v in pairs(self.tInputBuffer[tMsg._id]) do
							tMsg[k] = self.json.decode(v._data)
							tMsg._id = nil
							tMsg._key = nil
							tMsg._part = nil
							tMsg._lastpart = nil
							tMsg._data = nil
					end
					--Print("Rebuilt Message: "..self.json.encode(tMsg))
				else
					return true
				end
			end
			--for k,v in pairs(tMsg) do
			--	Print("Row "..k..": "..v)
			--end
		else
			Print("Received data is corrupted")
		end
		--Print("Received: "..self.json.encode(tMsg))
		-- Process Message
		if tMsg then
			if not self.sCallBackHandler or not self.tCallBackTarget then return end
			self.tCallBackTarget[self.sCallBackHandler](self.tCallBackTarget, channelCurrent:GetName(), tMsg)
		end
	end
end
 
 function ChatCommChannel:ChatMessageHook(luaCaller, channel, msg)
	if self.sChannelName and self.sChannelName == channel:GetName() then
		--Print("Hide msg on comm channel")
		return
	else
		self.hooks[self.chatAddon].OnChatMessage(self.chatAddon, channel, msg)
	end
 end

 
function ChatCommChannel:GetCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[self:GetCopy(orig_key)] = self:GetCopy(orig_value)
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function ChatCommChannel:dump(o)
	if type(o) == 'table' then
		local s = '{ '
		for k,v in pairs(o) do
			if type(k) ~= 'number' then k = '"'..k..'"' end
				s = s .. '['..k..'] = ' .. self:dump(v) .. ','
		end
		return s .. '} '
	else
		return tostring(o)
	end
end
 
if _G["ICLibs"] == nil then
	_G["ICLibs"] = {}
end
_G["ICLibs"]["ChatCommChannel"] = ChatCommChannel