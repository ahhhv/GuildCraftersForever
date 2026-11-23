-- GuildCrafters Forever
-- Copyright (C) 2026 jamiforever
-- Licensed under the GNU General Public License v3.0 or later (see LICENSE).
--------------------------------------------------------------------------------
-- GuildCrafters Forever: talking to the rest of the guild (addon messages, unseen in chat).
--   H~stamp   (guild)    "my data is as of `stamp`": whoever has older asks for it
--   Q         (guild)    "I just came online": everyone answers with H, spread out
--   R         (whisper)  "send me your data"
--   D~id~i~n~part (guild) one piece of a record: CBOR, deflated, base64
-- Only what changed travels, and once: requests within a few seconds are
-- answered by one send to the whole guild (everyone who's behind needs it too).
-- Sends are paced under the game's limits (a burst, then about one a second).
--------------------------------------------------------------------------------

local ADDON, ns = ...
local L = ns.L

local PREFIX = "GCRAFT1"
local SEP = "~"
local PART = 220               -- payload characters a message (255 max with the header)
local BURST, REFILL = 6, 1     -- messages at once, then one a second
local ASK_AGAIN = 60           -- seconds before asking the same member again
local SEND_AGAIN = 30          -- seconds before sending the same record to the guild again
local SEND_GATHER = 3          -- seconds requests are gathered before the one send
local HELLO_GAP = 60           -- seconds between our own H (a profession levelling up says so once a minute at most)
local MAX_RECIPES = 3000       -- a profession's recipes kept from a record (a sanity cap)

local queue, tokens = {}, BURST
local asked, buffers = {}, {}
local sent = { stamp = nil, at = -1e9, queued = false }
local lastHello, helloQueued = 0, false
local msgID = 0

local E = C_EncodingUtil

-- What /gcraft estado shows: counts and the last few things that happened
ns.stats = { sent = 0, failed = 0, got = 0, records = 0 }
local log = {}
function ns.Log(line)
	log[#log + 1] = date("%H:%M:%S ") .. line
	if #log > 12 then table.remove(log, 1) end
end
function ns.LogLines() return log end
ns.PREFIX = PREFIX

--------------------------------------------------------------------------------
-- Sending, paced
--------------------------------------------------------------------------------

local function Pump()
	while tokens > 0 and #queue > 0 do
		local m = queue[1]
		local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, m[1], m[2], m[3])
		ns.stats.sent = ns.stats.sent + 1
		if not ok or (result ~= nil and result ~= 0 and result ~= true) then
			ns.stats.failed = ns.stats.failed + 1
			ns.Log(("-> %s %s: fallo %s"):format(m[1]:sub(1, 1), m[3] or m[2], tostring(result)))
		end
		local R = Enum.SendAddonMessageResult
		if ok and R and (result == R.AddonMessageThrottle or result == R.ChannelThrottle) then
			tokens = 0
			return
		elseif ok and R and result == R.AddOnMessageLockdown then
			tokens = -5 -- (an encounter: try again in a few seconds)
			return
		end
		table.remove(queue, 1)
		tokens = tokens - 1
	end
end

C_Timer.NewTicker(REFILL, function()
	if tokens < BURST then tokens = tokens + 1 end
	Pump()
end)

local function Send(msg, channel, target)
	queue[#queue + 1] = { msg, channel, target }
	Pump()
end
ns.Send = Send

--------------------------------------------------------------------------------
-- Records in and out
--------------------------------------------------------------------------------

local function Pack(rec)
	if not (E and E.SerializeCBOR and E.CompressString and E.EncodeBase64) then return nil end
	local ok, s = pcall(E.SerializeCBOR, rec)
	if not ok or not s then return nil end
	ok, s = pcall(E.CompressString, s)
	if not ok or not s then return nil end
	ok, s = pcall(E.EncodeBase64, s)
	return ok and s or nil
end

local function Unpack(s)
	if not (E and E.DeserializeCBOR and E.DecompressString and E.DecodeBase64) then return nil end
	local ok, v = pcall(E.DecodeBase64, s)
	if not ok or not v then return nil end
	ok, v = pcall(E.DecompressString, v)
	if not ok or not v then return nil end
	ok, v = pcall(E.DeserializeCBOR, v)
	return ok and v or nil
end

local function Str(v, max) return type(v) == "string" and v:sub(1, max or 80) or nil end
local function Num(v) return type(v) == "number" and v or nil end

-- A received record cleaned to what we use; nil if it isn't one
local function Clean(rec)
	if type(rec) ~= "table" or Num(rec.t) == nil or Num(rec.v) ~= ns.PROTOCOL then return nil end
	local out = { v = rec.v, t = rec.t, c = Str(rec.c, 20), l = Num(rec.l), g = Str(rec.g, 60), ac = Str(rec.ac, 32), mn = Str(rec.mn, 60), nr = rec.nr == true or nil, ver = Str(rec.ver, 24), p = {} }
	if type(rec.cr) == "table" and Num(rec.cr.a) then
		out.cr = { a = rec.cr.a, m = Str(rec.cr.m, 7), n = Num(rec.cr.n) or 0 }
	end
	if type(rec.p) == "table" then
		for skill, p in pairs(rec.p) do
			if Num(skill) and type(p) == "table" then
				local rc
				if type(p.rc) == "table" then
					rc = {}
					for i = 1, math.min(#p.rc, MAX_RECIPES) do
						if Num(p.rc[i]) then rc[#rc + 1] = p.rc[i] end
					end
				end
				out.p[skill] = { n = Str(p.n), i = Num(p.i) or Str(p.i, 200), r = Num(p.r), m = Num(p.m), s = Str(p.s), rc = rc }
			end
		end
	end
	if type(rec.tl) == "table" then
		local tl = { sp = Num(rec.tl.sp), a = Num(rec.tl.a) or 1, g = {} }
		if type(rec.tl.g) == "table" then
			for g = 1, 2 do
				local e = rec.tl.g[g]
				if type(e) == "table" then
					local entry = { str = Str(e.str, 2000), tr = {} }
					if type(e.tr) == "table" then
						for k = 1, math.min(#e.tr, 6) do
							local t = e.tr[k]
							if type(t) == "table" then
								entry.tr[#entry.tr + 1] = { n = Str(t.n), i = Num(t.i) or Str(t.i, 200), s = Num(t.s) or 0 }
							end
						end
					end
					tl.g[g] = entry
				end
			end
		end
		out.tl = tl
	end
	return out
end

local function SendRecord()
	local rec = ns.MyRecord()
	local packed = Pack(rec)
	if not packed then return end
	sent.stamp, sent.at = rec.t, GetTime()
	msgID = (msgID % 999) + 1
	local n = math.ceil(#packed / PART)
	for i = 1, n do
		Send(table.concat({ "D", msgID, i, n, packed:sub((i - 1) * PART + 1, i * PART) }, SEP), "GUILD")
	end
end

-- Someone asked: one send to the guild for everyone asking now (the same record not again for a while)
local function RecordWanted()
	if sent.queued then return end
	local stamp = ns.MyRecord().t or 0
	if sent.stamp == stamp and GetTime() - sent.at < SEND_AGAIN then return end
	sent.queued = true
	C_Timer.After(SEND_GATHER, function()
		sent.queued = false
		SendRecord()
	end)
end

local function Received(sender, rec)
	rec = Clean(rec)
	local g = ns.Guild()
	if not (rec and g) then
		ns.Log("descartado de " .. sender .. (rec and " (sin guild)" or " (registro no válido)"))
		return
	end
	-- its roster row by GUID, whatever form the sender's name came in
	local e = rec.g and ns.byGuid[rec.g]
	if e then sender = e.name end
	local had = g.members[sender]
	if had and (had.t or 0) > rec.t then return end
	g.members[sender] = rec
	ns.dataVersion = (ns.dataVersion or 0) + 1
	ns.stats.records = ns.stats.records + 1
	ns.Log("recibido el registro de " .. sender)
	if ns.CheckVersion then ns.CheckVersion() end
	if ns.RefreshUI then ns.RefreshUI() end
end

--------------------------------------------------------------------------------
-- Hello
--------------------------------------------------------------------------------

-- Tell the guild how new our data is; `ask` also asks everyone for theirs (logging in)
function ns.Hello(ask)
	if not IsInGuild() then return end
	lastHello = GetTime()
	Send("H" .. SEP .. (ns.MyRecord().t or 0), "GUILD")
	if ask then Send("Q", "GUILD") end
end

function ns.Announce()
	if helloQueued then return end
	local wait = HELLO_GAP - (GetTime() - lastHello)
	if wait <= 0 then ns.Hello(false) return end
	helloQueued = true
	C_Timer.After(wait, function()
		helloQueued = false
		ns.Hello(false)
	end)
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------

local function OnMessage(text, channel, rawSender)
	if ns.Secret(text) or ns.Secret(rawSender) then return end
	local sender = ns.Key(rawSender)
	if not sender or sender == ns.Me() then return end
	if text:sub(1, 2) == "O" .. SEP then
		ns.stats.got = ns.stats.got + 1
		ns.Log(("<- O %s (%s)"):format(rawSender, channel or "?"))
		if channel == "GUILD" and ns.Req then ns.Req.Receive(select(2, strsplit(SEP, text, 8))) end
		return
	end
	if text:sub(1, 2) == "B" .. SEP then
		ns.stats.got = ns.stats.got + 1
		ns.Log(("<- B %s (%s)"):format(rawSender, channel or "?"))
		if channel == "GUILD" and ns.Req then ns.Req.ReceiveBoard(select(2, strsplit(SEP, text, 9))) end
		return
	end
	local kind, a, b, c, d = strsplit(SEP, text, 5)
	ns.stats.got = ns.stats.got + 1
	ns.Log(("<- %s %s (%s)"):format(kind or "?", rawSender, channel or "?"))
	-- records travel only on the guild channel (a whisper could come from anyone)
	if kind == "D" and channel ~= "GUILD" then return end
	local now = GetTime()
	if kind == "H" then
		local stamp = tonumber(a) or 0
		local rec = ns.Record(sender)
		-- a newer stamp is always asked for; the same one again only after a while (the answer got lost)
		local last = asked[sender]
		if stamp > 0 and (not rec or (rec.t or 0) < stamp)
			and not (last and last.stamp == stamp and now - last.at < ASK_AGAIN) then
			asked[sender] = { stamp = stamp, at = now }
			Send("R", "WHISPER", rawSender)
		end
	elseif kind == "Q" then
		if ns.Req then ns.Req.MemberOnline(sender) end
		if not helloQueued then
			helloQueued = true
			C_Timer.After(1 + math.random() * 9, function()
				helloQueued = false
				ns.Hello(false)
			end)
		end
	elseif kind == "R" then
		RecordWanted()
	elseif kind == "D" then
		local id, i, n = tonumber(a), tonumber(b), tonumber(c)
		if not (id and i and n and d) or n > 200 or i < 1 or i > n then return end
		local key = sender .. ":" .. id
		local buf = buffers[key]
		if not buf or buf.n ~= n then
			buf = { n = n, got = 0, parts = {}, at = now }
			buffers[key] = buf
		end
		if not buf.parts[i] then
			buf.parts[i] = d
			buf.got = buf.got + 1
		end
		if buf.got == n then
			buffers[key] = nil
			Received(sender, Unpack(table.concat(buf.parts)))
		end
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
	if ns.disabled then return end
	if prefix == PREFIX then OnMessage(text, channel, sender) end
end)
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end

-- half-received records left behind (someone logged off mid-send)
C_Timer.NewTicker(120, function()
	local now = GetTime()
	for key, buf in pairs(buffers) do
		if now - buf.at > 300 then buffers[key] = nil end
	end
end)

ns._test = { Pack = Pack, Unpack = Unpack, Clean = Clean, OnMessage = OnMessage, queue = queue }
