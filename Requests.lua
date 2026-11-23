-- GuildCrafters Forever
-- Copyright (C) 2026 jamiforever
-- Licensed under the GNU General Public License v3.0 or later (see LICENSE).
--------------------------------------------------------------------------------
-- Recipe requests: ask a guildmate to craft one of their recipes for you.
--   open -> accepted -> done      (the crafter accepts, crafts, mails it back)
--        -> declined              (the crafter says no)
--        -> cancelled             (the requester takes it back)
--        -> expired               (7 days with no answer; each client decides it alone)
-- A request travels to the whole guild (O~...), and every client with the
-- addon keeps it, so it reaches the crafter even if both of you are never
-- online at the same time: when someone comes online, the requests that
-- involve them are sent again (by one of the two sides if online, else by
-- one other member, whoever goes first).
-- Plus the mailbox (MailHelper below): a real letter to the crafter, the
-- materials to the crafter, the crafted item back to the requester.
--
-- A request: { id, from, to (member keys), recipe (recipe ID), t (asked, server
--   time), st (state), u (last change, server time), letter (requester only:
--   the letter was mailed), seen (crafter only: the notice was shown) }
--
-- The guild board: a post asks the whole guild instead of one crafter.
--   open -> taken (by whoever takes it first) -> done
--        -> cancelled (the poster takes it back)   taken -> open (the taker lets it go)
--        -> expired (7 days with nobody taking it)
-- A post is a request with board = true, to = the taker (nil while open), and
-- recipe = 0 with a text for a free-text post ("looking for 20 Linen Cloth").
-- It travels as B~id~from~to~recipe~t~st~u~text (older versions ignore it).
-- Only the members who know the recipe (and take requests) get a notice.
--
-- Members can turn requests off (option acceptRequests, shared as rec.nr):
-- nobody can ask them, and a request that still reaches them (from an older
-- version) is declined at once.
--------------------------------------------------------------------------------

local ADDON, ns = ...
local L = ns.L

local R = {}
ns.Req = R

local SEP = "~"
local EXPIRE = 7 * 86400       -- an open request with no answer
local KEEP = 7 * 86400         -- a finished one stays listed this long
local RELAY_WAIT = { 2, 9 }    -- seconds a member who isn't a side waits before relaying (the sides go first)

local STATES = { open = true, accepted = true, declined = true, done = true, cancelled = true }
local BSTATES = { open = true, taken = true, done = true, cancelled = true }
local RANK = { open = 1, taken = 2, accepted = 2, done = 3, cancelled = 3, declined = 3, expired = 3 }
local TEXT_MAX = 120
local FINAL = { declined = true, done = true, cancelled = true, expired = true }
R.FINAL = FINAL

--------------------------------------------------------------------------------
-- Activity: each crafter counts the requests and board posts they finish, and
-- shares the count in their record (rec.cr = { a = all time, m = "YYYY-MM",
-- n = that month }), so every client shows the same ranking.
--------------------------------------------------------------------------------

local function MonthKey() return date("%Y-%m", GetServerTime()) end
R.MonthKey = MonthKey

local function CountDone(r)
	local db = GuildCraftersForeverDB
	if not (db and r and r.st == "done" and r.to == ns.Me()) then return end
	db.counted = db.counted or {}
	if db.counted[r.id] then return end
	db.counted[r.id] = GetServerTime()
	ns.Rescan("stats", function(rec)
		local month = MonthKey()
		local cr = rec.cr or { a = 0, m = month, n = 0 }
		if cr.m ~= month then cr.m, cr.n = month, 0 end
		cr.a, cr.n = cr.a + 1, cr.n + 1
		rec.cr = cr
	end)
end
R.CountDone = CountDone

local lastHeard = {}           -- id -> GetTime() a copy was last heard or sent (relays skip a fresh one)

local function Store()
	local g = ns.Guild()
	if not g then return nil end
	g.requests = g.requests or {}
	return g.requests
end

function R.Get(id)
	local s = Store()
	return s and s[id]
end

-- Every request, newest first (expired and old ones swept first)
function R.List()
	R.Sweep()
	local out = {}
	for _, r in pairs(Store() or {}) do out[#out + 1] = r end
	table.sort(out, function(a, b) return (a.u or 0) > (b.u or 0) end)
	return out
end

function R.Mine() return ns.Me() end

-- Open requests waiting for me to answer
function R.PendingForMe()
	local me, n = ns.Me(), 0
	for _, r in pairs(Store() or {}) do
		if r.to == me and r.st == "open" then n = n + 1 end
	end
	return n
end

-- Accepted requests (and board posts taken) I'm to craft
function R.ToCraft()
	local me, n = ns.Me(), 0
	for _, r in pairs(Store() or {}) do
		if r.to == me and (r.st == "accepted" or r.st == "taken") then n = n + 1 end
	end
	return n
end

-- Open board posts by others
function R.BoardOpen()
	local me, n = ns.Me(), 0
	for _, r in pairs(Store() or {}) do
		if r.board and r.st == "open" and r.from ~= me then n = n + 1 end
	end
	return n
end

-- Finished requests of mine (either side): done, declined, cancelled, expired
function R.FinishedCount()
	local me, n = ns.Me(), 0
	for _, r in pairs(Store() or {}) do
		if FINAL[r.st] and (r.from == me or r.to == me) then n = n + 1 end
	end
	return n
end

-- Forget my finished requests; their ids are remembered so an old copy relayed later doesn't bring them back
function R.ClearHistory()
	local s, g = Store(), ns.Guild()
	if not (s and g) then return 0 end
	g.forgotten = g.forgotten or {}
	local me, n, now = ns.Me(), 0, GetServerTime()
	for id, r in pairs(s) do
		if FINAL[r.st] and (r.from == me or r.to == me) then
			g.forgotten[id] = now
			s[id] = nil
			n = n + 1
		end
	end
	return n
end

function R.Sweep()
	local s = Store()
	if not s then return end
	local now = GetServerTime()
	for id, r in pairs(s) do
		if r.st == "open" and now - (r.t or 0) > EXPIRE then
			r.st, r.u = "expired", now
		elseif FINAL[r.st] and now - (r.u or 0) > KEEP then
			s[id] = nil
		end
	end
	local g = ns.Guild()
	for id, at in pairs(g and g.forgotten or {}) do
		if now - at > 30 * 86400 then g.forgotten[id] = nil end
	end
end

--------------------------------------------------------------------------------
-- On the wire: O~id~from~to~recipe~t~st~u
--------------------------------------------------------------------------------

local function Encode(r)
	if r.board then
		return table.concat({ "B", r.id, r.from, r.to or "-", r.recipe or 0, r.t, r.st, r.u, r.text or "" }, SEP)
	end
	return table.concat({ "O", r.id, r.from, r.to, r.recipe, r.t, r.st, r.u }, SEP)
end

-- A post's free text, safe to send and to show (no separators, no escape codes)
local function CleanText(s)
	if type(s) ~= "string" then return "" end
	s = s:gsub("[~|\r\n\t]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	return s:sub(1, TEXT_MAX)
end
R.CleanText = CleanText

local function Broadcast(r)
	lastHeard[r.id] = GetTime()
	if ns.Send then ns.Send(Encode(r), "GUILD") end
end

local function Name(v) return type(v) == "string" and #v > 0 and #v <= 60 and not v:find(SEP, 1, true) and v or nil end

-- A request heard from the guild (new, or a newer state of one we have)
function R.Receive(id, from, to, recipe, t, st, u)
	id, from, to = Name(id), Name(from), Name(to)
	recipe, t, u = tonumber(recipe), tonumber(t), tonumber(u)
	if not (id and from and to and recipe and t and u and STATES[st]) then return end
	local s = Store()
	if not s then return end
	lastHeard[id] = GetTime()
	local g = ns.Guild()
	if g.forgotten and g.forgotten[id] then return end
	local cur = s[id]
	if cur and (cur.u or 0) >= u then return end
	local before = cur and cur.st
	local r = cur or { id = id }
	r.from, r.to, r.recipe, r.t, r.st, r.u = from, to, recipe, t, st, u
	s[id] = r
	local me = ns.Me()
	if r.to == me and st == "open" and not ns.Opt("acceptRequests") then
		-- I don't take requests (one sent by an older version, or before I turned them off... it waits for me)
		if not cur or before ~= "open" then
			r.seen = true
			C_Timer.After(1 + math.random(), function() R.Set(id, "declined") end)
		end
	elseif r.to == me and st == "open" and not r.seen and GetServerTime() - t < EXPIRE then
		r.seen = true
		if ns.NotifyRequest then ns.NotifyRequest(r) end
	elseif r.from == me and before ~= st and (st == "accepted" or st == "declined" or st == "done") then
		if ns.NotifyAnswer then ns.NotifyAnswer(r) end
	end
	CountDone(r)
	if ns.RefreshUI then ns.RefreshUI() end
end

-- Do I know this recipe?
local function IKnow(recipe)
	if not recipe or recipe == 0 then return false end
	local me = ns.Me()
	for _, key in ipairs(ns.CraftIndex()[recipe] or {}) do
		if key == me then return true end
	end
	return false
end
R.IKnow = IKnow

-- A board post heard from the guild
function R.ReceiveBoard(id, from, to, recipe, t, st, u, text)
	id, from = Name(id), Name(from)
	to = to ~= "-" and Name(to) or nil
	recipe, t, u = tonumber(recipe), tonumber(t), tonumber(u)
	text = CleanText(text)
	if not (id and from and recipe and recipe >= 0 and t and u and BSTATES[st]) then return end
	if recipe == 0 and text == "" then return end
	if st == "taken" and not to then return end
	local s = Store()
	if not s then return end
	lastHeard[id] = GetTime()
	local g = ns.Guild()
	if g.forgotten and g.forgotten[id] then return end
	local cur = s[id]
	if cur then
		local cu = cur.u or 0
		if u < cu then return end
		if u == cu then
			-- two changes in the same second (two members took it at once): every client picks the same one
			local a, b = RANK[st] or 0, RANK[cur.st] or 0
			if a < b or (a == b and not (st == "taken" and cur.st == "taken" and to and cur.to and to < cur.to)) then return end
		end
	end
	local before, beforeTo = cur and cur.st, cur and cur.to
	local r = cur or { id = id, board = true }
	r.board, r.from, r.to, r.recipe, r.t, r.st, r.u, r.text = true, from, to, recipe, t, st, u, text
	s[id] = r
	local me = ns.Me()
	if st == "open" and not cur and from ~= me and not r.seen and GetServerTime() - t < EXPIRE
		and ns.Opt("acceptRequests") and IKnow(recipe) then
		r.seen = true
		if ns.NotifyBoard then ns.NotifyBoard(r) end
	elseif from == me and before ~= st and (st == "taken" or st == "done") and to ~= me then
		if ns.NotifyBoardAnswer then ns.NotifyBoardAnswer(r) end
	elseif beforeTo == me and to ~= me and before == "taken" and st == "taken" then
		ns.Print(L["%s took the board post first: %s"]:format(to, R.Title(r)))
	end
	CountDone(r)
	if ns.RefreshUI then ns.RefreshUI() end
end

-- What a request or post is about: the recipe's name, or the post's text
function R.Title(r)
	if r.recipe and r.recipe > 0 then
		local name = ns.RecipeName(r.recipe)
		if r.text and r.text ~= "" then return name .. " (" .. r.text .. ")" end
		return name
	end
	return r.text or "?"
end

local function NewID()
	local guid = (UnitGUID and UnitGUID("player") or "x"):gsub("[^%w]", "")
	return ("%s%d%d"):format(guid:sub(-8), GetServerTime(), math.random(100, 999))
end

-- Post on the board: a recipe (recipe ID, an optional note) or free text (recipe 0 or nil)
function R.Post(recipe, text)
	local s, me = Store(), ns.Me()
	recipe, text = tonumber(recipe) or 0, CleanText(text)
	if not (s and me) or (recipe == 0 and text == "") then return nil end
	for _, r in pairs(s) do
		if r.board and r.from == me and (r.st == "open" or r.st == "taken")
			and r.recipe == recipe and (recipe > 0 or r.text == text) then return r, true end
	end
	local now = GetServerTime()
	local r = { id = NewID(), board = true, from = me, recipe = recipe, text = text, t = now, st = "open", u = now }
	s[r.id] = r
	Broadcast(r)
	if ns.RefreshUI then ns.RefreshUI() end
	return r
end

-- Take someone's open post: it's yours to craft
function R.Take(id)
	local r, me = R.Get(id), ns.Me()
	if not (r and r.board and r.st == "open" and r.from ~= me) then return end
	r.st, r.to, r.u = "taken", me, math.max(GetServerTime(), (r.u or 0) + 1)
	Broadcast(r)
	if ns.RefreshUI then ns.RefreshUI() end
	return r
end

-- Let a post you took go back to the board
function R.Release(id)
	local r, me = R.Get(id), ns.Me()
	if not (r and r.board and r.st == "taken" and r.to == me) then return end
	r.st, r.to, r.u = "open", nil, math.max(GetServerTime(), (r.u or 0) + 1)
	Broadcast(r)
	if ns.RefreshUI then ns.RefreshUI() end
end

--------------------------------------------------------------------------------
-- Making and answering
--------------------------------------------------------------------------------

function R.Create(to, recipe)
	local s = Store()
	local me = ns.Me()
	if not (s and to and recipe and me) or to == me then return nil end
	if not ns.TakesRequests(to) then return nil, "closed" end
	-- the same recipe already asked of the same crafter and still going: that one
	for _, r in pairs(s) do
		if r.from == me and r.to == to and r.recipe == recipe and (r.st == "open" or r.st == "accepted") then return r, true end
	end
	local now = GetServerTime()
	local r = { id = NewID(), from = me, to = to, recipe = recipe,
		t = now, st = "open", u = now, letter = false }
	s[r.id] = r
	Broadcast(r)
	if ns.RefreshUI then ns.RefreshUI() end
	return r
end

-- A new state by one of the sides: the crafter accepts, declines or marks it done; the requester cancels
function R.Set(id, st)
	local r = R.Get(id)
	local me = ns.Me()
	if not r or FINAL[r.st] then return end
	if r.board then
		-- a post: the taker or the poster marks it done; the poster cancels it
		local ok = (st == "done" and r.st == "taken" and (r.to == me or r.from == me)) or (st == "cancelled" and r.from == me)
		if not ok then return end
		r.st, r.u = st, math.max(GetServerTime(), (r.u or 0) + 1)
		Broadcast(r)
		CountDone(r)
		if ns.RefreshUI then ns.RefreshUI() end
		return
	end
	local crafter = (st == "accepted" or st == "declined" or st == "done") and r.to == me
	local requester = st == "cancelled" and r.from == me
	if not (crafter or requester) then return end
	r.st, r.u = st, math.max(GetServerTime(), (r.u or 0) + 1)
	Broadcast(r)
	CountDone(r)
	if ns.RefreshUI then ns.RefreshUI() end
end

--------------------------------------------------------------------------------
-- Someone came online: the requests that involve them, sent again
--------------------------------------------------------------------------------

local function Online(key)
	local e = ns.inRoster[key]
	return e and e.online
end

function R.MemberOnline(key)
	local me = ns.Me()
	if key == me then return end
	for _, r in pairs(Store() or {}) do
		if r.board and not FINAL[r.st] and not (GetServerTime() - (r.t or 0) > EXPIRE and r.st == "open") then
			-- every member should see the board: its poster (or taker) sends it, else anyone, whoever goes first
			local side = r.from == me or r.to == me
			if side or not (Online(r.from) or (r.to and Online(r.to))) then
				local asked = GetTime()
				local wait = side and (0.5 + math.random() * 2) or (RELAY_WAIT[1] + math.random() * (RELAY_WAIT[2] - RELAY_WAIT[1]))
				C_Timer.After(wait, function()
					if (lastHeard[r.id] or 0) > asked then return end
					if not FINAL[r.st] then Broadcast(r) end
				end)
			end
		elseif not r.board and not FINAL[r.st] and (r.to == key or r.from == key) then
			local side = r.from == me or r.to == me
			local otherSide = (r.from == key) and r.to or r.from
			-- the sides send at once; anyone else only when the other side is offline too, and only if nobody did first
			if side or not Online(otherSide) then
				local asked = GetTime()
				local wait = side and (0.5 + math.random() * 2) or (RELAY_WAIT[1] + math.random() * (RELAY_WAIT[2] - RELAY_WAIT[1]))
				C_Timer.After(wait, function()
					if not side and (lastHeard[r.id] or 0) > asked then return end
					if not FINAL[r.st] then Broadcast(r) end
				end)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- The mailbox
--------------------------------------------------------------------------------

local MAIL_SUBJECT_MAX = 64

local function RawName(key)
	local e = ns.inRoster[key]
	return (e and e.raw) or key
end
R.RawName = RawName

-- The Send Mail tab is open (we never switch Blizzard's tabs ourselves: that taints the mail window)
function R.SendTabOpen()
	return SendMailFrame and SendMailFrame:IsShown() and true or false
end

local function FillMail(to, subject, body)
	if SendMailNameEditBox then SendMailNameEditBox:SetText(RawName(to)) end
	if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(subject:sub(1, MAIL_SUBJECT_MAX)) end
	if body and SendMailBodyEditBox then SendMailBodyEditBox:SetText(body) end
end

-- Where `itemID` lies in your bags: { { bag, slot, count } }, biggest stacks first
local function FindInBags(itemID)
	local out = {}
	local C = C_Container
	if not C then return out end
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, (C.GetContainerNumSlots(bag) or 0) do
			local info = C.GetContainerItemInfo(bag, slot)
			if info and info.itemID == itemID and not info.isLocked then
				out[#out + 1] = { bag, slot, info.stackCount or 1 }
			end
		end
	end
	table.sort(out, function(a, b) return a[3] > b[3] end)
	return out
end

-- The first empty attachment slot of the letter being written
local function FreeAttachment()
	for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
		if not (HasSendMailItem and HasSendMailItem(i)) then return i end
	end
end

-- Put `count` of `itemID` on the letter (splitting a stack when it holds more). Returns how many went on.
local function Attach(itemID, count)
	local C = C_Container
	local put = 0
	for _, s in ipairs(FindInBags(itemID)) do
		if put >= count then break end
		local slot = FreeAttachment()
		if not slot then break end
		local take = math.min(count - put, s[3])
		ClearCursor()
		if take < s[3] then C.SplitContainerItem(s[1], s[2], take) else C.PickupContainerItem(s[1], s[2]) end
		if ClickSendMailItemButton then ClickSendMailItemButton(slot) end
		if CursorHasItem and CursorHasItem() then ClearCursor() else put = put + take end
	end
	return put
end

local pendingMail -- { id, kind = "letter" | "materials" | "result" } awaiting MAIL_SEND_SUCCESS

-- The letter that tells the crafter what you'd like (the addon's notice reaches them too)
function R.PrepareLetter(r)
	local name = ns.RecipeName(r.recipe)
	FillMail(r.to, L["Request: %s"]:format(name),
		L["Hi! Could you craft %s for me?\nI asked through GuildCrafters Forever: you'll find it in the guild window (J), Requests tab.\nThanks!"]:format(name))
	pendingMail = { id = r.id, kind = "letter" }
end

-- The recipe's materials from your bags, to the crafter. Returns the missing ones { { itemID, missing } }.
function R.PrepareMaterials(r)
	local name = ns.RecipeName(r.recipe)
	FillMail(r.to, L["Materials: %s"]:format(name), L["Materials for %s. Thanks!"]:format(name))
	local missing = {}
	local s = ns.Schematic(r.recipe)
	for _, reagent in ipairs(s and s.reagents or {}) do
		local got = Attach(reagent[1], reagent[2])
		if got < reagent[2] then missing[#missing + 1] = { reagent[1], reagent[2] - got } end
	end
	pendingMail = { id = r.id, kind = "materials" }
	return missing
end

-- The crafted item, back to whoever asked. False when it isn't in your bags.
function R.PrepareResult(r)
	local name = ns.RecipeName(r.recipe)
	local item = ns.RecipeItem(r.recipe) or (ns.Schematic(r.recipe) or {}).item
	FillMail(r.from, L["Your request: %s"]:format(name), L["Here's your %s. Enjoy!"]:format(name))
	local ok = item and Attach(item, 1) > 0 or false
	pendingMail = { id = r.id, kind = "result" }
	return ok
end

-- A letter went out: the one we prepared, as it was
local function MailSent()
	local p = pendingMail
	pendingMail = nil
	local r = p and R.Get(p.id)
	if not r then return end
	if p.kind == "letter" then
		r.letter = true
	elseif p.kind == "materials" then
		r.mats = true
	elseif p.kind == "result" then
		R.Set(r.id, "done")
	end
	if ns.RefreshMail then ns.RefreshMail() end
	if ns.RefreshUI then ns.RefreshUI() end
end

-- What the mailbox helper offers now: { { text, run, request } }
function R.MailActions()
	local me, out = ns.Me(), {}
	for _, r in ipairs(R.List()) do
		local name = r.recipe > 0 and ns.RecipeName(r.recipe) or ""
		if r.board then
			-- handled below
		elseif r.from == me and r.st == "open" and not r.letter then
			out[#out + 1] = { text = L["Letter to %s: %s"]:format(r.to, name), run = function() R.PrepareLetter(r) end, request = r }
		end
		if not r.board and r.from == me and (r.st == "open" or r.st == "accepted") and not r.mats then
			out[#out + 1] = { text = L["Materials to %s: %s"]:format(r.to, name), run = function() return R.PrepareMaterials(r) end, request = r, mats = true }
		end
		if not r.board and r.to == me and r.st == "accepted" then
			out[#out + 1] = { text = L["Send %s to %s"]:format(name, r.from), run = function() return R.PrepareResult(r) end, request = r, result = true }
		end
		if r.board and r.st == "taken" and r.recipe > 0 then
			if r.from == me and not r.mats then
				out[#out + 1] = { text = L["Materials to %s: %s"]:format(r.to, name), run = function() return R.PrepareMaterials(r) end, request = r, mats = true }
			elseif r.to == me then
				out[#out + 1] = { text = L["Send %s to %s"]:format(name, r.from), run = function() return R.PrepareResult(r) end, request = r, result = true }
			end
		end
	end
	return out
end

local f = CreateFrame("Frame")
f:RegisterEvent("MAIL_SEND_SUCCESS")
f:RegisterEvent("MAIL_FAILED")
f:RegisterEvent("MAIL_SHOW")
f:RegisterEvent("MAIL_CLOSED")
f:SetScript("OnEvent", function(_, event)
	if ns.disabled then return end
	if event == "MAIL_SEND_SUCCESS" then
		MailSent()
	elseif event == "MAIL_FAILED" then
		pendingMail = nil
	elseif event == "MAIL_SHOW" then
		if ns.ShowMailHelper then ns.ShowMailHelper() end
	elseif event == "MAIL_CLOSED" then
		pendingMail = nil
		if ns.HideMailHelper then ns.HideMailHelper() end
	end
end)

-- The login summary, once the guild has had a moment to send us what we missed
C_Timer.After(20, function()
	if ns.disabled or not ns.Guild() then return end
	-- what I finished while this version wasn't counting yet (the last week's requests), and old counted ids
	for _, r in pairs(Store() or {}) do CountDone(r) end
	local db, now = GuildCraftersForeverDB, GetServerTime()
	for id, at in pairs(db.counted or {}) do
		if now - at > 60 * 86400 then db.counted[id] = nil end
	end
	local n, c = R.PendingForMe(), R.ToCraft()
	if n > 0 then ns.Print(L["You have %d recipe requests waiting for an answer. /gcraft requests"]:format(n)) end
	if c > 0 then ns.Print(L["You have %d accepted requests to craft."]:format(c)) end
	local b = R.BoardOpen()
	if b > 0 then ns.Print(L["%d open posts on the guild board. /gcraft requests"]:format(b)) end
end)
