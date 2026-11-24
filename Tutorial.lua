-- GuildCrafters Forever
-- Copyright (C) 2026 jamiforever
-- Licensed under the GNU General Public License v3.0 or later (see LICENSE).
--------------------------------------------------------------------------------
-- The guided tour: a bubble with Back / Next over the guild window, one step
-- at a time, with the part it talks about outlined. It only runs from its
-- button in the options. The guild window can't be opened for the player (an
-- addon opening it taints it), so the tour waits for J.
--------------------------------------------------------------------------------

local ADDON, ns = ...
local L = ns.L

local bubble, outline, waiter
local step = 0

-- Each step: the tab to show, what to outline (nil: the middle of the guild window), and the text
local function Steps()
	local ui, req = ns.ui or {}, ns.reqUI or {}
	local tabs, prof, tal = ui.tabs or {}, ui.prof or {}, ui.tal or {}
	local shortcut = ns.ShortcutText and ns.ShortcutText() or nil
	return {
		{ tab = "prof", target = tabs.prof, title = L["Professions"],
			text = L["This tab, added to the guild window, shows the professions of everyone in the guild with the addon."] },
		{ tab = "prof", target = prof.members and prof.members.box, title = L["Members"],
			text = L["Each member with their professions and skill. Click one to see their recipes. A player's alts are grouped under their main: the + button shows them."] },
		{ tab = "prof", target = prof.searchBox, title = L["Search"],
			text = L["Look for a recipe or an item to see who can craft it. The buttons above filter by profession, and the box, online members."] },
		{ tab = "prof", target = prof.right, title = L["Recipes"],
			text = L["Unfold a profession to see the recipes. Hover one for its materials: what you have, and who in the guild crafts or gathers what you're missing. Request asks that member to craft it."] },
		{ tab = "tal", target = tabs.tal, title = L["Specializations and talents"],
			text = L["Each member's specialization and talent points, for both specs. Open their build in the talent window from here."] },
		{ tab = "req", target = tabs.req, title = L["Requests"],
			text = L["What you're asked for and what you asked, with their state. The number on the tab: requests waiting for your answer."] },
		{ tab = "req", target = req.post, title = L["Guild board"],
			text = L["Post what you need to the whole guild, with an optional reward. Whoever can craft it gets a notice; the first to take it crafts it, and sends it cash on delivery for the reward."] },
		{ tab = "req", target = req.list and req.list.box, title = L["Guild crafters ranking"],
			text = L["Further down this list: the board, and the ranking of who has crafted the most for the guild, this month and all time."] },
		{ tab = "req", title = L["Item tooltips"],
			text = (L["Hover any item (bags, chat links, auction house) to see who in your guild can craft it. Use your shortcut on it (%s) to ask them."])
				:format(shortcut or L["none, see the options"]) },
		{ tab = "req", title = L["At the mailbox"],
			text = L["When you open a mailbox, a helper offers what's pending: the letter for a crafter, their materials, or the crafted item back (cash on delivery if there's a reward)."] },
		{ tab = "req", title = L["Options"],
			text = L["Esc > Options > AddOns > GuildCrafters Forever: tooltips, your shortcut, alts, whether you take requests, and this tour. That's all: happy crafting!"] },
	}
end

local function Box(f, r, g, b, a, edge)
	if not f.SetBackdrop then return end
	f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = edge or 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	f:SetBackdropColor(r, g, b, a)
	f:SetBackdropBorderColor(1, 0.82, 0, 1)
end

local function Stop()
	if bubble then bubble:Hide() end
	if outline then outline:Hide() end
	if waiter then waiter:Cancel() waiter = nil end
	step = 0
end
ns.StopTutorial = Stop

local function Build()
	if bubble then return end
	local b = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	b:SetSize(320, 150)
	b:SetFrameStrata("FULLSCREEN_DIALOG")
	b:EnableMouse(true)
	Box(b, 0.05, 0.08, 0.12, 0.97)
	b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	b.title:SetPoint("TOPLEFT", 14, -12)
	b.title:SetPoint("TOPRIGHT", -40, -12)
	b.title:SetJustifyH("LEFT")
	b.count = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	b.count:SetPoint("TOPRIGHT", -30, -15)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	b.text:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -8)
	b.text:SetWidth(292)
	b.text:SetJustifyH("LEFT")
	b.text:SetSpacing(2)
	b.next = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
	b.next:SetSize(96, 22)
	b.next:SetPoint("BOTTOMRIGHT", -12, 10)
	b.back = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
	b.back:SetSize(96, 22)
	b.back:SetPoint("RIGHT", b.next, "LEFT", -6, 0)
	b.back:SetText(L["Back"])
	local close = CreateFrame("Button", nil, b, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScale(0.8)
	close:SetScript("OnClick", Stop)
	b:Hide()
	bubble = b

	local o = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	o:SetFrameStrata("FULLSCREEN_DIALOG")
	if o.SetBackdrop then
		o:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 })
		o:SetBackdropBorderColor(1, 0.82, 0, 1)
	end
	local t = 0
	o:SetScript("OnUpdate", function(self, elapsed)
		t = t + elapsed
		self:SetAlpha(0.55 + 0.45 * math.abs(math.sin(t * 3)))
	end)
	o:Hide()
	outline = o
end

local Show

-- Put the bubble beside `target` (right of it if there's room, else left), or over the guild window
local function Place(target)
	bubble:ClearAllPoints()
	outline:ClearAllPoints()
	if target and target:IsVisible() then
		outline:SetPoint("TOPLEFT", target, "TOPLEFT", -6, 6)
		outline:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 6, -6)
		outline:Show()
		local right = target:GetRight() or 0
		local room = (UIParent:GetRight() or 1920) - right
		if room > bubble:GetWidth() + 24 then
			bubble:SetPoint("LEFT", target, "RIGHT", 16, 0)
		else
			bubble:SetPoint("RIGHT", target, "LEFT", -16, 0)
		end
	else
		outline:Hide()
		bubble:SetPoint("CENTER", CommunitiesFrame or UIParent, "CENTER", 0, 0)
	end
	bubble:SetClampedToScreen(true)
end

Show = function(i)
	local steps = Steps()
	if i < 1 then i = 1 end
	if i > #steps then Stop() ns.Print(L["Tour finished. You can start it again from the options."]) return end
	step = i
	local s = steps[i]
	if ns.ui and ns.ui.show and s.tab then ns.ui.show(s.tab) end
	bubble.title:SetText(s.title)
	bubble.text:SetText(s.text)
	bubble.count:SetText(("%d/%d"):format(i, #steps))
	bubble:SetHeight((bubble.text:GetStringHeight() or 60) + 82)
	bubble.back:SetEnabled(i > 1)
	bubble.next:SetText(i == #steps and L["Finish"] or L["Next"])
	bubble.next:SetScript("OnClick", function() Show(step + 1) end)
	bubble.back:SetScript("OnClick", function() Show(step - 1) end)
	bubble:Show()
	-- the panel lays itself out a frame later
	C_Timer.After(0, function() if step == i then Place(s.target) end end)
end

local function GuildShown()
	return ns.ui and ns.ui.shown and ns.ui.shown()
end

function ns.StartTutorial()
	Build()
	Stop()
	if ns.OpenGuild then ns.OpenGuild("prof") end -- sets things up (and, with the window closed, asks for J)
	if GuildShown() then Show(1) return end
	-- wait for the player to open the guild window
	bubble.title:SetText(L["Guided tour"])
	bubble.text:SetText(L["Press J to open the guild window and the tour will begin."])
	bubble.count:SetText("")
	bubble:SetHeight((bubble.text:GetStringHeight() or 30) + 82)
	bubble.back:SetEnabled(false)
	bubble.next:SetText(CANCEL or "Cancel")
	bubble.next:SetScript("OnClick", Stop)
	bubble:ClearAllPoints()
	bubble:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
	outline:Hide()
	bubble:Show()
	waiter = C_Timer.NewTicker(0.3, function()
		if GuildShown() then
			waiter:Cancel()
			waiter = nil
			C_Timer.After(0.2, function() Show(1) end)
		end
	end)
end

-- Closing the guild window ends the tour
local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function(self, elapsed)
	self.t = (self.t or 0) + elapsed
	if self.t < 0.5 then return end
	self.t = 0
	if step > 0 and not GuildShown() then Stop() end
end)

-- (for testing: jump to a step)
function ns.TutorialGo(i) Build() Show(i) end
