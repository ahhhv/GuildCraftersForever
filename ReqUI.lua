-- GuildCrafters Forever
-- Copyright (C) 2026 jamiforever
-- Licensed under the GNU General Public License v3.0 or later (see LICENSE).
--------------------------------------------------------------------------------
-- Recipe requests on screen: the Requests tab of the guild window, the
-- confirmation when you ask, the notice when someone asks you (or answers
-- you), and the helper beside the mailbox.
--------------------------------------------------------------------------------

local ADDON, ns = ...
local L = ns.L

local req = { collapsed = {} }
local ROW = 40

local STATE_TEXT = {
	open = { "Waiting", 1, 0.82, 0 },
	accepted = { "Accepted", 0.3, 1, 0.3 },
	taken = { "Taken", 0.3, 1, 0.3 },
	declined = { "Declined", 1, 0.35, 0.3 },
	done = { "Done", 0.5, 0.8, 1 },
	cancelled = { "Cancelled", 0.6, 0.6, 0.6 },
	expired = { "Expired", 0.6, 0.6, 0.6 },
}

local BOARD_ICON = 134939 -- a scroll

local function Icon(tex, size) return ("|T%s:%d:%d:0:0|t"):format(tostring(tex or 134400), size or 16, size or 16) end

local function StateText(st)
	local s = STATE_TEXT[st] or STATE_TEXT.open
	return ("|cff%02x%02x%02x%s|r"):format(s[2] * 255, s[3] * 255, s[4] * 255, L[s[1]])
end

local function Sound()
	if not ns.Opt("sound") then return end
	if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081) end
end

--------------------------------------------------------------------------------
-- Asking
--------------------------------------------------------------------------------

-- Our own small confirmation (Blizzard's StaticPopup dialogs, shown by an addon, taint the dialog
-- system that the Esc key goes through)
local confirm

local function Confirm(text, okText, onOk)
	if not confirm then
		local c = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		c:SetSize(400, 150)
		c:SetPoint("CENTER", 0, 120)
		c:SetFrameStrata("DIALOG")
		c:EnableMouse(true)
		if c.SetBackdrop then
			c:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
			c:SetBackdropColor(0.05, 0.13, 0.08, 0.97)
			c:SetBackdropBorderColor(0.75, 0.5, 0.25, 1)
		end
		c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		c.text:SetPoint("TOPLEFT", 18, -18)
		c.text:SetPoint("TOPRIGHT", -18, -18)
		c.text:SetJustifyH("CENTER")
		c.ok = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
		c.ok:SetSize(120, 24)
		c.ok:SetPoint("BOTTOMRIGHT", c, "BOTTOM", -6, 14)
		c.no = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
		c.no:SetSize(120, 24)
		c.no:SetPoint("BOTTOMLEFT", c, "BOTTOM", 6, 14)
		c.no:SetText(CANCEL or "Cancel")
		c.no:SetScript("OnClick", function() c:Hide() end)
		c:Hide()
		confirm = c
	end
	confirm.text:SetText(text)
	confirm:SetHeight(math.max(130, (confirm.text:GetStringHeight() or 60) + 70))
	confirm.ok:SetText(okText)
	confirm.ok:SetScript("OnClick", function() confirm:Hide() onOk() end)
	confirm:Show()
end

function ns.AskRequest(to, recipe)
	local text = L["Ask %s to craft %s for you?\n\nThey'll get a notice (when they log in, if they're offline), and next time you open a mailbox the addon will have a letter ready for them."]
		:format("|cffffd100" .. to .. "|r", "|cffffffff" .. ns.RecipeName(recipe) .. "|r")
	if not ns.TakesRequests(to) then
		ns.Print(L["%s doesn't take requests. You can post it on the guild board instead."]:format(to))
		return
	end
	Confirm(text, L["Request"], function()
		local r, already = ns.Req.Create(to, recipe)
		if not r then return end
		if already then
			ns.Print(L["You had already asked %s for %s."]:format(to, ns.RecipeName(recipe)))
		else
			ns.Print(L["Request sent to %s: %s. Next time you open a mailbox you can also send them a letter."]:format(to, ns.RecipeName(recipe)))
		end
	end)
end

--------------------------------------------------------------------------------
-- Posting on the guild board
--------------------------------------------------------------------------------

local function Posted(r, already)
	if not r then return end
	if already then
		ns.Print(L["It's already on the guild board: %s"]:format(ns.Req.Title(r)))
	else
		ns.Print(L["Posted on the guild board: %s. Whoever can craft it gets a notice."]:format(ns.Req.Title(r)))
	end
end

-- A recipe to the board, after a confirmation
function ns.ConfirmPost(recipe)
	Confirm(L["Post %s on the guild board?\n\nEveryone in the guild with the addon will see it, and those who can craft it get a notice. The first to take it crafts it."]
		:format("|cffffffff" .. ns.RecipeName(recipe) .. "|r"), L["Post"], function() Posted(ns.Req.Post(recipe)) end)
end

-- Free text to the board: our own little window with a text box
local poster
function ns.PostText()
	if not poster then
		local p = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		p:SetSize(420, 150)
		p:SetPoint("CENTER", 0, 120)
		p:SetFrameStrata("DIALOG")
		p:EnableMouse(true)
		if p.SetBackdrop then
			p:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
			p:SetBackdropColor(0.05, 0.13, 0.08, 0.97)
			p:SetBackdropBorderColor(0.75, 0.5, 0.25, 1)
		end
		p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		p.text:SetPoint("TOPLEFT", 18, -16)
		p.text:SetPoint("TOPRIGHT", -18, -16)
		p.text:SetJustifyH("LEFT")
		p.text:SetText(L["What are you looking for? (for an item someone can craft, Alt+click it instead)"])
		p.edit = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
		p.edit:SetSize(370, 24)
		p.edit:SetPoint("TOP", 0, -58)
		p.edit:SetAutoFocus(true)
		p.edit:SetMaxLetters(120)
		p.ok = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
		p.ok:SetSize(120, 24)
		p.ok:SetPoint("BOTTOMRIGHT", p, "BOTTOM", -6, 14)
		p.ok:SetText(L["Post"])
		p.no = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
		p.no:SetSize(120, 24)
		p.no:SetPoint("BOTTOMLEFT", p, "BOTTOM", 6, 14)
		p.no:SetText(CANCEL or "Cancel")
		local function Go()
			local text = ns.Req.CleanText(p.edit:GetText())
			if text == "" then return end
			p:Hide()
			Posted(ns.Req.Post(0, text))
		end
		p.ok:SetScript("OnClick", Go)
		p.edit:SetScript("OnEnterPressed", Go)
		p.edit:SetScript("OnEscapePressed", function() p:Hide() end)
		p.no:SetScript("OnClick", function() p:Hide() end)
		p:Hide()
		poster = p
	end
	poster.edit:SetText("")
	poster:Show()
	poster.edit:SetFocus()
end

-- Who to ask for an item (the tooltip's shortcut): one button per crafter who takes requests, online
-- first, and the guild board
local picker
function ns.ChooseCrafter(itemID, all)
	if not picker then
		local p = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		p:SetWidth(320)
		p:SetPoint("CENTER", 0, 120)
		p:SetFrameStrata("DIALOG")
		p:EnableMouse(true)
		if p.SetBackdrop then
			p:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
			p:SetBackdropColor(0.05, 0.13, 0.08, 0.97)
			p:SetBackdropBorderColor(0.75, 0.5, 0.25, 1)
		end
		p.text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		p.text:SetPoint("TOPLEFT", 16, -16)
		p.text:SetPoint("TOPRIGHT", -16, -16)
		p.buttons = {}
		p.cancel = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
		p.cancel:SetSize(120, 22)
		p.cancel:SetText(CANCEL or "Cancel")
		p.cancel:SetScript("OnClick", function() p:Hide() end)
		p:Hide()
		picker = p
	end
	local p = picker
	local list = {}
	for _, c in ipairs(all) do
		if not c.closed then list[#list + 1] = c end
	end
	local itemName = C_Item.GetItemNameByID(itemID) or ("#" .. itemID)
	if #list > 0 then
		p.text:SetText(L["Who do you want to ask for %s?"]:format("|cffffffff" .. itemName .. "|r"))
	else
		p.text:SetText(L["Nobody who crafts %s takes requests right now. You can post it on the guild board."]:format("|cffffffff" .. itemName .. "|r"))
	end
	p.text:SetJustifyH("CENTER")
	local y = -48 - math.max(0, (p.text:GetStringHeight() or 14) - 14)
	for i = 1, math.min(#list, 8) do
		local c = list[i]
		local b = p.buttons[i]
		if not b then
			b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
			b:SetSize(288, 24)
			p.buttons[i] = b
		end
		b:ClearAllPoints()
		b:SetPoint("TOP", 0, y)
		b:SetText(c.key .. (c.online and ("  |cff40ff40" .. L["online"] .. "|r") or ""))
		b:SetScript("OnClick", function()
			p:Hide()
			local r, already = ns.Req.Create(c.key, c.recipe)
			if not r then return end
			if already then
				ns.Print(L["You had already asked %s for %s."]:format(c.key, ns.RecipeName(c.recipe)))
			else
				ns.Print(L["Request sent to %s: %s. Next time you open a mailbox you can also send them a letter."]:format(c.key, ns.RecipeName(c.recipe)))
			end
		end)
		b:Show()
		y = y - 28
	end
	for i = math.min(#list, 8) + 1, #p.buttons do p.buttons[i]:Hide() end
	if not p.board then
		p.board = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
		p.board:SetSize(288, 24)
		p.board:SetText(L["Post it on the guild board"])
	end
	local recipe = (all[1] and all[1].recipe) or (ns.RecipesForItem(itemID) or {})[1]
	p.board:SetScript("OnClick", function()
		p:Hide()
		Posted(ns.Req.Post(recipe))
	end)
	p.board:ClearAllPoints()
	p.board:SetPoint("TOP", 0, y - 4)
	y = y - 32
	p.cancel:ClearAllPoints()
	p.cancel:SetPoint("TOP", 0, y - 6)
	p:SetHeight(-y + 44)
	p:Show()
end

--------------------------------------------------------------------------------
-- The notice
--------------------------------------------------------------------------------

local toast

local function Toast()
	if toast then return toast end
	local t = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	t:SetSize(380, 86)
	t:SetPoint("TOP", 0, -140)
	t:SetFrameStrata("DIALOG")
	if t.SetBackdrop then
		t:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		t:SetBackdropColor(0.05, 0.13, 0.08, 0.95)
		t:SetBackdropBorderColor(0.75, 0.5, 0.25, 1)
	end
	t:EnableMouse(true)
	t.icon = t:CreateTexture(nil, "ARTWORK")
	t.icon:SetSize(40, 40)
	t.icon:SetPoint("TOPLEFT", 12, -12)
	t.title = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	t.title:SetPoint("TOPLEFT", t.icon, "TOPRIGHT", 10, 0)
	t.title:SetPoint("RIGHT", -12, 0)
	t.title:SetJustifyH("LEFT")
	t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	t.text:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -3)
	t.text:SetPoint("RIGHT", -12, 0)
	t.text:SetJustifyH("LEFT")
	t.text:SetWordWrap(false)
	t.b1 = CreateFrame("Button", nil, t, "UIPanelButtonTemplate")
	t.b1:SetSize(90, 22)
	t.b1:SetPoint("BOTTOMRIGHT", -10, 8)
	t.b2 = CreateFrame("Button", nil, t, "UIPanelButtonTemplate")
	t.b2:SetSize(90, 22)
	t.b2:SetPoint("RIGHT", t.b1, "LEFT", -6, 0)
	local close = CreateFrame("Button", nil, t, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScale(0.8)
	t:Hide()
	toast = t
	return t
end

local function ShowToast(title, text, icon, b1, b2)
	local t = Toast()
	t.title:SetText(title)
	t.text:SetText(text)
	t.icon:SetTexture(icon or 134400)
	for i, spec in ipairs({ b1 or false, b2 or false }) do
		local b = (i == 1) and t.b1 or t.b2
		if spec then
			b:SetText(spec[1])
			b:SetScript("OnClick", function() t:Hide() spec[2]() end)
			b:Show()
		else
			b:Hide()
		end
	end
	t.shownAt = GetTime()
	t:Show()
	Sound()
	C_Timer.After(25, function()
		if t:IsShown() and GetTime() - (t.shownAt or 0) >= 24.5 then t:Hide() end
	end)
end

local function OpenRequests()
	if ns.OpenGuild then ns.OpenGuild("req") end
end

-- Someone asks me
function ns.NotifyRequest(r)
	local name = ns.RecipeName(r.recipe)
	ns.Print(L["%s asks you to craft %s. /gcraft requests"]:format("|cffffd100" .. r.from .. "|r", name))
	ShowToast(L["Recipe request"], L["%s asks you for: %s"]:format(r.from, name), ns.RecipeIcon(r.recipe),
		{ L["Accept"], function() ns.Req.Set(r.id, "accepted") end },
		{ L["View"], OpenRequests })
	if ns.RefreshUI then ns.RefreshUI() end
end

-- A board post I can craft
function ns.NotifyBoard(r)
	local title = ns.Req.Title(r)
	ns.Print(L["Guild board: %s is looking for %s, and you can craft it. /gcraft requests"]:format("|cffffd100" .. r.from .. "|r", title))
	ShowToast(L["Guild board"], L["%s is looking for: %s"]:format(r.from, title), ns.RecipeIcon(r.recipe),
		{ L["Take it"], function() ns.Req.Take(r.id) end },
		{ L["View"], OpenRequests })
	if ns.RefreshUI then ns.RefreshUI() end
end

-- Someone took my post, or crafted it
function ns.NotifyBoardAnswer(r)
	local title = ns.Req.Title(r)
	local line
	if r.st == "taken" then
		line = L["%s took your board post: %s"]:format(r.to or "?", title)
	else
		line = L["%s has crafted your %s: check your mailbox."]:format(r.to or "?", title)
	end
	ns.Print(line)
	ShowToast(L["Guild board"], line, r.recipe > 0 and ns.RecipeIcon(r.recipe) or BOARD_ICON, { L["View"], OpenRequests })
end

-- The crafter answered me
function ns.NotifyAnswer(r)
	local name = ns.RecipeName(r.recipe)
	local line
	if r.st == "accepted" then
		line = L["%s accepted your request: %s"]:format(r.to, name)
	elseif r.st == "declined" then
		line = L["%s declined your request: %s"]:format(r.to, name)
	else
		line = L["%s has crafted your %s: check your mailbox."]:format(r.to, name)
	end
	ns.Print(line)
	ShowToast(L["Recipe request"], line, ns.RecipeIcon(r.recipe), { L["View"], OpenRequests })
end

--------------------------------------------------------------------------------
-- The Requests tab
--------------------------------------------------------------------------------

local function Place(b, withButtons)
	local anchor = withButtons == 2 and b.btn2 or (withButtons == 1 and b.btn1) or nil
	for _, fs in ipairs({ b.left, b.sub }) do
		local p, rel, rp, x, y = fs:GetPoint(1)
		fs:ClearAllPoints()
		fs:SetPoint(p, rel, rp, x, y)
		if anchor then fs:SetPoint("RIGHT", anchor, "LEFT", -8, 0) else fs:SetPoint("RIGHT", -6, 0) end
	end
end

local function Button(btn, text, fn)
	btn:SetText(text)
	btn:SetScript("OnClick", fn)
	btn:Show()
end

local function InitRow(b, d)
	b:SetScript("OnEnter", nil)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("OnClick", nil)
	b.left:SetAlpha(1)
	b.sub:SetAlpha(1)
	if d.header then
		local fold = req.collapsed[d.key] and "|TInterface\\Buttons\\UI-PlusButton-Up:14:14|t " or "|TInterface\\Buttons\\UI-MinusButton-Up:14:14|t "
		b.left:SetText(fold .. d.text)
		b.left:SetTextColor(1, 0.82, 0)
		b.sub:SetText(d.hint or "")
		b.sub:SetTextColor(0.6, 0.6, 0.6)
		Place(b, 0)
		b:SetScript("OnClick", function()
			req.collapsed[d.key] = not req.collapsed[d.key] or nil
			ns.RefreshReq()
		end)
		return
	end
	local r = d.r
	local me = ns.Me()
	local mine = r.from == me
	if r.board then return ns.InitBoardRow(b, r, mine) end
	b.left:SetText(Icon(ns.RecipeIcon(r.recipe)) .. " " .. ns.RecipeName(r.recipe))
	b.left:SetTextColor(1, 1, 1)
	local who = mine and L["For: %s"]:format(r.to) or L["From: %s"]:format(r.from)
	local line = ("%s  ·  %s  ·  %s"):format(who, StateText(r.st), ns.Ago(r.u))
	if mine and r.st == "open" and not r.letter then line = line .. "  ·  |cffa0a0a0" .. L["letter ready at the mailbox"] .. "|r" end
	b.sub:SetText(line)
	b.sub:SetTextColor(0.85, 0.85, 0.85)
	local buttons = 0
	if not ns.Req.FINAL[r.st] then
		if not mine and r.st == "open" then
			Button(b.btn1, L["Decline"], function() ns.Req.Set(r.id, "declined") end)
			Button(b.btn2, L["Accept"], function() ns.Req.Set(r.id, "accepted") end)
			buttons = 2
		elseif not mine and r.st == "accepted" then
			Button(b.btn1, L["Done"], function() ns.Req.Set(r.id, "done") end)
			buttons = 1
		elseif mine then
			Button(b.btn1, L["Cancel"], function() ns.Req.Set(r.id, "cancelled") end)
			buttons = 1
		end
	else
		b.left:SetAlpha(0.55)
		b.sub:SetAlpha(0.55)
	end
	Place(b, buttons)
	b:SetScript("OnEnter", function(self)
		ns.RecipeTooltipFor(self, r.recipe)
	end)
	b:SetScript("OnClick", function(_, button)
		local other = mine and r.to or r.from
		if button == "RightButton" and ns.Whisper then ns.Whisper(other)
		elseif IsShiftKeyDown() and ns.RecipeLinkFor then ns.InsertLinkFor(ns.RecipeLinkFor(r.recipe)) end
	end)
end

-- A board post's row
function ns.InitBoardRow(b, r, mine)
	local me = ns.Me()
	local icon = r.recipe > 0 and ns.RecipeIcon(r.recipe) or BOARD_ICON
	b.left:SetText(Icon(icon) .. " " .. ns.Req.Title(r))
	b.left:SetTextColor(1, 1, 1)
	local who
	if mine then
		who = r.to and L["Crafted by: %s"]:format(r.to) or L["Your post"]
	else
		who = L["From: %s"]:format(r.from)
	end
	local line = ("%s  ·  %s  ·  %s"):format(who, r.st == "open" and ("|cffffd100" .. L["On the board"] .. "|r") or StateText(r.st), ns.Ago(r.u))
	if r.st == "open" and not mine and ns.Req.IKnow(r.recipe) then line = line .. "  ·  |cff40ff40" .. L["you can craft it"] .. "|r" end
	b.sub:SetText(line)
	b.sub:SetTextColor(0.85, 0.85, 0.85)
	local buttons = 0
	if not ns.Req.FINAL[r.st] then
		if r.st == "open" and not mine then
			Button(b.btn1, L["Take it"], function() ns.Req.Take(r.id) end)
			buttons = 1
		elseif r.st == "taken" and r.to == me then
			Button(b.btn1, L["Done"], function() ns.Req.Set(r.id, "done") end)
			Button(b.btn2, L["Let go"], function() ns.Req.Release(r.id) end)
			buttons = 2
		elseif mine and r.st == "taken" then
			Button(b.btn1, L["Done"], function() ns.Req.Set(r.id, "done") end)
			Button(b.btn2, L["Cancel"], function() ns.Req.Set(r.id, "cancelled") end)
			buttons = 2
		elseif mine then
			Button(b.btn1, L["Cancel"], function() ns.Req.Set(r.id, "cancelled") end)
			buttons = 1
		end
	else
		b.left:SetAlpha(0.55)
		b.sub:SetAlpha(0.55)
	end
	Place(b, buttons)
	b:SetScript("OnEnter", function(self)
		if r.recipe > 0 then
			ns.RecipeTooltipFor(self, r.recipe)
		elseif GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(r.text or "", 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnClick", function(_, button)
		local other = (r.from == me) and r.to or r.from
		if button == "RightButton" and other and ns.Whisper then ns.Whisper(other)
		elseif IsShiftKeyDown() and r.recipe > 0 and ns.RecipeLinkFor then ns.InsertLinkFor(ns.RecipeLinkFor(r.recipe)) end
	end)
end

function ns.BuildReqPanel(MakePanel, MakeList, _, RecipeTooltip)
	local p = MakePanel()
	req.panel = p
	ns.RecipeTooltipFor = RecipeTooltip
	local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText(L["Recipe requests"])
	local hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	hint:SetJustifyH("LEFT")
	hint:SetText(L["Ask a crafter with Request in the Professions tab, or Alt+click an item. Anything else, post it on the guild board. Requests reach people even when offline and wait 7 days."])
	-- Clear history: a second click within 4 seconds confirms
	req.clear = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	req.clear:SetSize(150, 22)
	req.clear:SetPoint("TOPRIGHT", -14, -12)
	req.clear:SetText(L["Clear history"])
	req.clear:SetScript("OnClick", function(self)
		if self.armed and GetTime() - self.armed < 4 then
			self.armed = nil
			self:SetText(L["Clear history"])
			local n = ns.Req.ClearHistory()
			ns.Print(L["Removed %d finished requests."]:format(n))
			ns.RefreshReq()
		else
			self.armed = GetTime()
			self:SetText(L["Sure? Click again"])
			C_Timer.After(4, function()
				if self.armed and GetTime() - self.armed >= 3.9 then self.armed = nil self:SetText(L["Clear history"]) end
			end)
		end
	end)
	req.post = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	req.post:SetSize(150, 22)
	req.post:SetPoint("TOPRIGHT", req.clear, "BOTTOMRIGHT", 0, -4)
	req.post:SetText(L["Post on the board"])
	req.post:SetScript("OnClick", function() ns.PostText() end)
	hint:SetPoint("RIGHT", req.clear, "LEFT", -10, 0)
	req.list = MakeList(p, ROW, InitRow, true)
	req.list.box:SetPoint("TOPLEFT", 10, -62)
	req.list.box:SetPoint("BOTTOMRIGHT", -28, 8)
	return p
end

function ns.RefreshReq()
	if not (req.list and ns.Req) then return end
	local me = ns.Me()
	local forMe, mine, board = {}, {}, {}
	for _, r in ipairs(ns.Req.List()) do
		if r.board and r.st == "open" then board[#board + 1] = { r = r }
		elseif r.to == me then forMe[#forMe + 1] = { r = r }
		elseif r.from == me then mine[#mine + 1] = { r = r } end
	end
	local rows = {}
	rows[#rows + 1] = { header = true, key = "forMe", text = L["Asked of you"] .. ("  (%d)"):format(ns.Req.PendingForMe()),
		hint = #forMe == 0 and L["Nothing for now."] or L["Right-click: whisper"] }
	if not req.collapsed.forMe then
		for _, d in ipairs(forMe) do rows[#rows + 1] = d end
	end
	rows[#rows + 1] = { header = true, key = "mine", text = L["Your requests"] .. ("  (%d)"):format(#mine),
		hint = #mine == 0 and L["Nothing for now."] or nil }
	if not req.collapsed.mine then
		for _, d in ipairs(mine) do rows[#rows + 1] = d end
	end
	rows[#rows + 1] = { header = true, key = "board", text = L["Guild board"] .. ("  (%d)"):format(#board),
		hint = #board == 0 and L["Nothing for now."] or (not ns.Opt("acceptRequests") and L["You don't take requests (options)"]) or nil }
	if not req.collapsed.board then
		for _, d in ipairs(board) do rows[#rows + 1] = d end
	end
	req.list:Set(rows)
	req.clear:SetEnabled(ns.Req.FinishedCount() > 0)
end

--------------------------------------------------------------------------------
-- Beside the mailbox
--------------------------------------------------------------------------------

local helper

local function Helper()
	if helper or not MailFrame then return helper end
	local h = CreateFrame("Frame", nil, MailFrame, "BackdropTemplate")
	h:SetWidth(280)
	h:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, -24)
	if h.SetBackdrop then
		h:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		h:SetBackdropColor(0.05, 0.13, 0.08, 0.95)
		h:SetBackdropBorderColor(0.75, 0.5, 0.25, 1)
	end
	h.title = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h.title:SetPoint("TOPLEFT", 12, -10)
	h.title:SetText(L["GuildCrafters: requests"])
	h.msg = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	h.msg:SetJustifyH("LEFT")
	h.msg:SetWidth(256)
	h.buttons = {}
	helper = h
	return h
end

local function Fill()
	local h = Helper()
	if not h then return end
	local actions = ns.Req and ns.Req.MailActions() or {}
	if #actions == 0 then h:Hide() return end
	local y = -32
	for i, a in ipairs(actions) do
		local b = h.buttons[i]
		if not b then
			b = CreateFrame("Button", nil, h, "UIPanelButtonTemplate")
			b:SetSize(256, 24)
			h.buttons[i] = b
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 12, y)
		b:SetText(a.text)
		local fs = b:GetFontString()
		if fs then fs:SetWidth(240) fs:SetWordWrap(false) end
		b:SetScript("OnClick", function()
			if not ns.Req.SendTabOpen() then
				h.msg:SetText("|cffffd100" .. L["Open the Send Mail tab first, then press it again."] .. "|r")
				return
			end
			local res = a.run()
			if a.mats and type(res) == "table" and #res > 0 then
				local parts = {}
				for _, m in ipairs(res) do
					parts[#parts + 1] = ("%d x %s"):format(m[2], (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(m[1])) or ("#" .. m[1]))
				end
				h.msg:SetText("|cffff6060" .. L["Missing from your bags:"] .. "|r " .. table.concat(parts, ", "))
			elseif a.result and res == false then
				h.msg:SetText("|cffff6060" .. L["The crafted item isn't in your bags."] .. "|r")
			else
				h.msg:SetText(L["Letter ready: check it and press Send."])
			end
		end)
		b:Show()
		y = y - 28
	end
	for i = #actions + 1, #h.buttons do h.buttons[i]:Hide() end
	h.msg:ClearAllPoints()
	h.msg:SetPoint("TOPLEFT", 12, y - 4)
	h:SetHeight(-y + 44)
	h:Show()
end

function ns.ShowMailHelper()
	if helper and helper.msg then helper.msg:SetText("") end
	Fill()
end

function ns.HideMailHelper()
	if helper then helper:Hide() end
end

function ns.RefreshMail()
	if helper and helper:IsShown() then Fill() end
end
