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
local FINAL = { declined = true, done = true, cancelled = true, expired = true }
R.FINAL = FINAL

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

-- Accepted requests I'm to craft
function R.ToCraft()
	local me, n = ns.Me(), 0
	for _, r in pairs(Store() or {}) do
		if r.to == me and r.st == "accepted" then n = n + 1 end
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
	return table.concat({ "O", r.id, r.from, r.to, r.recipe, r.t, r.st, r.u }, SEP)
end

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
	if r.to == me and st == "open" and not r.seen and GetServerTime() - t < EXPIRE then
		r.seen = true
		if ns.NotifyRequest then ns.NotifyRequest(r) end
	elseif r.from == me and before ~= st and (st == "accepted" or st == "declined" or st == "done") then
		if ns.NotifyAnswer then ns.NotifyAnswer(r) end
	end
	if ns.RefreshUI then ns.RefreshUI() end
end

--------------------------------------------------------------------------------
-- Making and answering
--------------------------------------------------------------------------------

function R.Create(to, recipe)
	local s = Store()
	local me = ns.Me()
	if not (s and to and recipe and me) or to == me then return nil end
	-- the same recipe already asked of the same crafter and still going: that one
	for _, r in pairs(s) do
		if r.from == me and r.to == to and r.recipe == recipe and (r.st == "open" or r.st == "accepted") then return r, true end
	end
	local now = GetServerTime()
	local guid = (UnitGUID and UnitGUID("player") or "x"):gsub("[^%w]", "")
	local r = { id = ("%s%d%d"):format(guid:sub(-8), now, math.random(100, 999)), from = me, to = to, recipe = recipe,
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
	local crafter = (st == "accepted" or st == "declined" or st == "done") and r.to == me
	local requester = st == "cancelled" and r.from == me
	if not (crafter or requester) then return end
	r.st, r.u = st, math.max(GetServerTime(), (r.u or 0) + 1)
	Broadcast(r)
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
	for _, r in pairs(Store() or {}) do
		if not FINAL[r.st] and (r.to == key or r.from == key) and key ~= me then
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
		local name = ns.RecipeName(r.recipe)
		if r.from == me and r.st == "open" and not r.letter then
			out[#out + 1] = { text = L["Letter to %s: %s"]:format(r.to, name), run = function() R.PrepareLetter(r) end, request = r }
		end
		if r.from == me and (r.st == "open" or r.st == "accepted") and not r.mats then
			out[#out + 1] = { text = L["Materials to %s: %s"]:format(r.to, name), run = function() return R.PrepareMaterials(r) end, request = r, mats = true }
		end
		if r.to == me and r.st == "accepted" then
			out[#out + 1] = { text = L["Send %s to %s"]:format(name, r.from), run = function() return R.PrepareResult(r) end, request = r, result = true }
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
	local n, c = R.PendingForMe(), R.ToCraft()
	if n > 0 then ns.Print(L["You have %d recipe requests waiting for an answer. /gcraft requests"]:format(n)) end
	if c > 0 then ns.Print(L["You have %d accepted requests to craft."]:format(c)) end
end)
