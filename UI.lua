-- GuildCrafters Forever
-- Copyright (C) 2026 jamiforever
-- Licensed under the GNU General Public License v3.0 or later (see LICENSE).
--------------------------------------------------------------------------------
-- GuildCrafters Forever: two tabs on the guild window (J, Blizzard's Guild &
-- Communities frame), under Blizzard's own side tabs, shown while the guild is
-- the selected community:
--   Professions  filter by profession, search recipes and items guild-wide,
--                each member's levels and recipes (hover: reagents; Shift-click:
--                link; whisper the crafter)
--   Talents      each member's specialization (points per branch, both spec
--                groups), profession specializations, and their tree in
--                Blizzard's own talent window (the shared loadout string)
-- Our panels lie over Blizzard's content; nothing of Blizzard's is changed but
-- its tabs' checked look.
--------------------------------------------------------------------------------

local ADDON, ns = ...
local L = ns.L

local PROF_TAB_ICON = "Interface\\Icons\\Trade_BlackSmithing"
local TAL_TAB_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local ROW = 20
local MEMBER_ROW = 34            -- member rows: the name, and under it what they have
local LEFT_W = 236
local PANEL_LEVEL = 1500         -- above everything of Blizzard's on the guild window (its chat box is at 1200)

local CF                         -- CommunitiesFrame
local tabs, panels = {}, {}
local state = {
	prof = nil, search = "", online = false, selected = nil,             -- professions tab
	expanded = {},                                                       -- professions opened in the detail (by skill)
	altsOpen = {},                                                       -- players whose alts are shown (by group id)
	talSearch = "", talOnline = false, talSelected = nil,                -- talents tab
}
ns._state = state

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function ClassRGB(class)
	local c = class and ((C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
	if c then return c.r, c.g, c.b end
	return 0.9, 0.9, 0.9
end

local function ClassHex(class)
	local r, g, b = ClassRGB(class)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

local function Icon(tex, size) return ("|T%s:%d:%d:0:0|t"):format(tostring(tex or 134400), size or 14, size or 14) end

local function InsertLink(link)
	if not link then return end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then ChatFrameUtil.InsertLink(link)
	elseif ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
end

local function Whisper(name)
	name = ns.Req and ns.Req.RawName(name) or name
	if ChatFrameUtil and ChatFrameUtil.SendTell then ChatFrameUtil.SendTell(name)
	elseif ChatFrame_SendTell then ChatFrame_SendTell(name) end
end

local function RecipeLink(id)
	local T = C_TradeSkillUI
	local link = T and T.GetRecipeLink and T.GetRecipeLink(id)
	if not link and C_Spell and C_Spell.GetSpellLink then link = C_Spell.GetSpellLink(id) end
	return link
end

local function ItemName(id)
	local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
	if not n and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
	return n or ("#" .. id)
end

local function ProfInfo(skill)
	local g = ns.Guild()
	for _, rec in pairs(g and g.members or {}) do
		local p = rec.p and rec.p[skill]
		if p and p.n then return p.n, p.i or ns.PROF_ICONS[skill] end
	end
	return "#" .. skill, ns.PROF_ICONS[skill]
end

-- Recipes of `rec` (one profession or all) matching the search text
local function Matches(rec, skill, q)
	local out = {}
	for s, p in pairs(rec.p or {}) do
		if not skill or s == skill then
			for _, id in ipairs(p.rc or {}) do
				if q == "" or ns.RecipeSearchText(id):find(q, 1, true) then out[#out + 1] = id end
			end
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local function BuildRow(b, extent)
	b:SetHeight(extent)
	b.sel = b:CreateTexture(nil, "BACKGROUND")
	b.sel:SetAllPoints()
	b.sel:SetColorTexture(1, 0.82, 0, 0.18)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(extent - 4, extent - 4)
	b.icon:SetPoint("LEFT", 4, 0)
	b.left = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.left:SetJustifyH("LEFT")
	b.right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.right:SetPoint("RIGHT", -6, 0)
	b.right:SetJustifyH("RIGHT")
	b.left:SetPoint("RIGHT", b.right, "LEFT", -6, 0)
	b.left:SetWordWrap(false)
	b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.sub:SetJustifyH("LEFT")
	b.sub:SetWordWrap(false)
	b.sub:Hide()
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.08)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	-- up to two small buttons at the row's right (Request on a recipe; Accept / Decline on a request)
	b.btn1 = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
	b.btn1:SetSize(84, 20)
	b.btn1:SetPoint("RIGHT", -6, 0)
	b.btn1:Hide()
	b.btn2 = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
	b.btn2:SetSize(84, 20)
	b.btn2:SetPoint("RIGHT", b.btn1, "LEFT", -4, 0)
	b.btn2:Hide()
	b.built = true
end

-- A scrolling list; init(button, data) fills a row
local function MakeList(parent, extent, init, twoLine)
	local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
	local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
	bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(extent)
	view:SetElementInitializer("Button", function(button, data)
		if not button.built then BuildRow(button, extent) end
		button.data = data
		button.icon:Hide()
		button.sel:Hide()
		button.btn1:Hide()
		button.btn2:Hide()
		button.btn1:SetSize(84, 20)
		button.btn1:SetEnabled(true)
		button.btn2:SetSize(84, 20)
		if twoLine then
			button.right:Hide()
			button.left:ClearAllPoints()
			button.left:SetPoint("TOPLEFT", 8, -4)
			button.left:SetPoint("TOPRIGHT", -6, -4)
			button.sub:ClearAllPoints()
			button.sub:SetPoint("BOTTOMLEFT", 8, 4)
			button.sub:SetPoint("BOTTOMRIGHT", -6, 4)
			button.sub:Show()
			init(button, data)
			return
		end
		button.right:Show()
		button.left:ClearAllPoints()
		button.left:SetPoint("LEFT", 6, 0)
		button.left:SetPoint("RIGHT", button.right, "LEFT", -6, 0)
		init(button, data)
		if button.icon:IsShown() then
			button.left:ClearAllPoints()
			button.left:SetPoint("LEFT", button.icon, "RIGHT", 4, 0)
			button.left:SetPoint("RIGHT", button.right, "LEFT", -6, 0)
		end
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
	local list = { box = box, bar = bar }
	function list:Set(items)
		box:SetDataProvider(CreateDataProvider(items), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
	end
	return list
end

local function MakeSearch(parent, hint, onChange)
	local box = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
	box:SetSize(170, 20)
	box:SetAutoFocus(false)
	if box.Instructions then box.Instructions:SetText(hint) end
	box:HookScript("OnTextChanged", function(self) onChange(strlower(strtrim(self:GetText() or ""))) end)
	return box
end

local function MakeCheck(parent, label, onChange)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(22, 22)
	local text = cb.Text or cb.text
	if text then text:SetText(label) text:SetFontObject("GameFontHighlightSmall") end
	cb:SetScript("OnClick", function(self) onChange(self:GetChecked() and true or false) end)
	return cb
end

local function MakePanel()
	local p = CreateFrame("Frame", nil, CF)
	p:SetFrameLevel(PANEL_LEVEL)
	p:EnableMouse(true)
	local bg = p:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	bg:SetColorTexture(0.06, 0.06, 0.07, 0.98)
	local border = p:CreateTexture(nil, "BACKGROUND", nil, -7)
	border:SetPoint("TOPLEFT", 0, 0)
	border:SetPoint("BOTTOMRIGHT", 0, 0)
	border:SetColorTexture(1, 0.82, 0, 0.04)
	p:Hide()
	return p
end

-- A member row of either tab's list
local function MemberRow(b, d, subText)
	local r, g, bl = ClassRGB(d.class)
	local name = d.short
	if d.head then
		name = name .. ("  |cffa0a0a0(+%d %s)|r"):format(d.altCount, d.altCount == 1 and L["alt"] or L["alts"])
	elseif d.alt then
		name = "|cff808080" .. L["alt"] .. ":|r " .. name
	end
	b.left:SetText(name)
	b.left:SetTextColor(r, g, bl)
	b.left:SetAlpha(d.online and 1 or 0.55)
	b.sub:SetText((d.alt and "      " or "") .. (subText or ""))
	b.sub:SetTextColor(0.85, 0.85, 0.85)
	b.sub:SetAlpha(d.online and 1 or 0.6)
	if d.noaddon then
		b.left:SetAlpha(0.4)
		b.sub:SetText(L["no addon"])
		b.sub:SetTextColor(0.5, 0.5, 0.5)
	end
	-- the player's other characters: shown or hidden with the small button
	local anchor
	if d.head then
		b.btn1:SetSize(28, 20)
		b.btn1:SetText(d.open and "-" or "+")
		b.btn1:SetScript("OnClick", function()
			state.altsOpen[d.gid] = not d.open or nil
			ns.RefreshUI()
		end)
		b.btn1:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(d.open and L["Hide alts"] or L["Show alts"])
			GameTooltip:Show()
		end)
		b.btn1:SetScript("OnLeave", GameTooltip_Hide)
		b.btn1:Show()
		anchor = b.btn1
	end
	for _, fs in ipairs({ b.left, b.sub }) do
		local p, rel, rp, x, y = fs:GetPoint(1)
		fs:ClearAllPoints()
		fs:SetPoint(p, rel, rp, (d.alt and 18 or 8), y)
		if anchor then fs:SetPoint("RIGHT", anchor, "LEFT", -6, 0) else fs:SetPoint("RIGHT", -6, 0) end
	end
end

-- Roster members with or without a record, filtered by `keep(entry, rec)`; cached records when there's no roster yet
local function Members(keep)
	local g = ns.Guild()
	local members = g and g.members or {}
	local out = {}
	local function add(name, entry)
		local rec = members[name]
		local d = { name = name, short = entry and entry.short or ns.Short(name), online = entry and entry.online or false,
			class = (rec and rec.c) or (entry and entry.class), rec = rec, noaddon = rec == nil,
			level = (entry and entry.level) or (rec and rec.l) }
		if keep(d) then out[#out + 1] = d end
	end
	if #ns.roster > 0 then
		for _, e in ipairs(ns.roster) do add(e.name, e) end
	else
		for name in pairs(members) do add(name, nil) end
	end
	return out
end

--------------------------------------------------------------------------------
-- The professions tab
--------------------------------------------------------------------------------

local prof = {}

local function ProfFilters()
	local present = {}
	local g = ns.Guild()
	for _, rec in pairs(g and g.members or {}) do
		for skill in pairs(rec.p or {}) do present[skill] = (present[skill] or 0) + 1 end
	end
	local order = {}
	for _, s in ipairs(ns.PROF_ORDER) do if present[s] then order[#order + 1] = s end end
	for s in pairs(present) do
		if not tContains(order, s) then order[#order + 1] = s end
	end
	return order, present
end

local function RefreshFilterButtons()
	local order, counts = ProfFilters()
	prof.all:SetEnabled(state.prof ~= nil)
	local x = 4
	for i, skill in ipairs(order) do
		local b = prof.filters[i]
		if not b then
			b = CreateFrame("Button", nil, prof.panel)
			b:SetSize(24, 24)
			b.tex = b:CreateTexture(nil, "ARTWORK")
			b.tex:SetAllPoints()
			b.ring = b:CreateTexture(nil, "OVERLAY")
			b.ring:SetTexture("Interface\\Buttons\\CheckButtonHilight")
			b.ring:SetBlendMode("ADD")
			b.ring:SetAllPoints()
			b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			b:SetScript("OnClick", function(self)
				state.prof = (state.prof == self.skill) and nil or self.skill
				ns.RefreshUI()
			end)
			b:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
				GameTooltip:AddLine((ProfInfo(self.skill)))
				GameTooltip:AddLine(("%d"):format(self.count or 0) .. " ·  " .. GUILD, 0.8, 0.8, 0.8)
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", GameTooltip_Hide)
			prof.filters[i] = b
		end
		local _, icon = ProfInfo(skill)
		b.skill, b.count = skill, counts[skill]
		b.tex:SetTexture(icon or 134400)
		b.tex:SetDesaturated(state.prof ~= nil and state.prof ~= skill)
		b.ring:SetShown(state.prof == skill)
		b:ClearAllPoints()
		b:SetPoint("LEFT", prof.all, "RIGHT", x, 0)
		x = x + 28
		b:Show()
	end
	for i = #order + 1, #prof.filters do prof.filters[i]:Hide() end
end

local function ProfRightText(d)
	local rec = d.rec
	if not rec then return nil end
	if state.search ~= "" then return L["%d matches"]:format(d.matches or 0) end
	if state.prof then
		local p = rec.p[state.prof]
		local t = ("%s %s %d/%d"):format(Icon(p.i or ns.PROF_ICONS[state.prof], 13), p.n or "", p.r or 0, p.m or 0)
		if p.s then t = t .. "  |cffffd100" .. p.s .. "|r" end
		return t
	end
	-- a player with hidden alts: every character's professions, each at its best
	local best = {}
	local recs = { rec }
	if d.head and not d.open then
		recs = {}
		for _, a in ipairs(d.group or {}) do if a.rec then recs[#recs + 1] = a.rec end end
	end
	for _, r in ipairs(recs) do
		for skill, p in pairs(r.p or {}) do
			if not best[skill] or (p.r or 0) > (best[skill].r or 0) then best[skill] = p end
		end
	end
	local parts = {}
	for _, skill in ipairs(ns.PROF_ORDER) do
		local p = best[skill]
		if p then parts[#parts + 1] = Icon(p.i or ns.PROF_ICONS[skill], 13) .. " " .. (p.r or 0) end
	end
	return table.concat(parts, "  ")
end

local function RefreshProfDetail()
	local d = state.selectedData
	local rows = {}
	prof.note:Hide()
	if not d then
		prof.title:SetText(L["Select a member"])
		prof.title:SetTextColor(0.6, 0.6, 0.6)
		prof.sub:SetText("")
		prof.whisper:Hide()
		prof.recipes:Set(rows)
		return
	end
	prof.title:SetText(d.short .. (d.level and ("  |cffa0a0a0" .. L["Level %d"]:format(d.level) .. "|r") or ""))
	prof.title:SetTextColor(ClassRGB(d.class))
	prof.whisper:SetShown(d.online)
	if not d.rec then
		prof.sub:SetText(L["This member doesn't have the addon."])
		prof.recipes:Set(rows)
		return
	end
	prof.sub:SetText(L["Last update: %s"]:format(ns.Ago(d.rec.t)))
	local missing = false
	local skills = {}
	for _, s in ipairs(ns.PROF_ORDER) do if d.rec.p[s] then skills[#skills + 1] = s end end
	for s in pairs(d.rec.p) do if not tContains(skills, s) then skills[#skills + 1] = s end end
	for _, s in ipairs(skills) do
		if not state.prof or state.prof == s then
			local p = d.rec.p[s]
			local head = ("%s  %d/%d"):format(p.n or ("#" .. s), p.r or 0, p.m or 0)
			if p.s then head = head .. "  ·  " .. p.s end
			local ids = Matches({ p = { [s] = p } }, s, state.search)
			table.sort(ids, function(a, b) return ns.RecipeName(a) < ns.RecipeName(b) end)
			if state.search == "" or #ids > 0 then
				local count = #(p.rc or {})
				-- open: picked by hand, or the one profession filtered on, or matches while searching
				-- (true / false: opened or closed by hand; nil: the default)
				local hand = state.expanded[s]
				local open = count > 0 and (hand == true or (hand == nil and (state.prof == s or state.search ~= "")))
				rows[#rows + 1] = { header = true, text = head, icon = p.i or ns.PROF_ICONS[s], count = count,
					gathering = ns.GATHERING[s], skill = s, open = open }
				if count == 0 and not ns.GATHERING[s] then missing = true end
				if open then
					for _, id in ipairs(ids) do rows[#rows + 1] = { id = id, crafter = d } end
				end
			end
		end
	end
	if missing then
		prof.note:SetText(L["No recipes shared yet: they're sent once the member opens that profession's window."])
		prof.note:Show()
	end
	prof.recipes.box:SetPoint("TOPLEFT", 0, missing and -(46 + (prof.note:GetStringHeight() or 12) + 6) or -46)
	prof.recipes:Set(rows)
end

local function RefreshProf()
	RefreshFilterButtons()
	local q = state.search
	local list = Members(function(d)
		if state.online and not d.online then return false end
		if state.takes and (d.noaddon or not ns.TakesRequests(d.name)) then return false end
		if d.noaddon then return state.prof == nil and q == "" end
		if state.prof and not d.rec.p[state.prof] then return false end
		if q ~= "" then
			d.matches = #Matches(d.rec, state.prof, q)
			if d.matches == 0 then return false end
		end
		return true
	end)
	table.sort(list, function(a, b)
		if a.noaddon ~= b.noaddon then return not a.noaddon end
		if a.online ~= b.online then return a.online end
		if state.prof and a.rec and b.rec then
			local ra, rb = a.rec.p[state.prof].r or 0, b.rec.p[state.prof].r or 0
			if ra ~= rb then return ra > rb end
		end
		if q ~= "" and (a.matches or 0) ~= (b.matches or 0) then return (a.matches or 0) > (b.matches or 0) end
		return a.short < b.short
	end)
	list = ns.GroupRows(list, state.altsOpen)
	state.selectedData = nil
	for _, d in ipairs(list) do if d.name == state.selected then state.selectedData = d end end
	if not state.selectedData and state.selected then
		-- still show the one picked, filtered out or not
		local all = Members(function(d) return d.name == state.selected end)
		state.selectedData = all[1]
	end
	prof.members:Set(list)
	RefreshProfDetail()
end

local function RecipeTooltip(owner, id)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, id)
	if not ok then GameTooltip:AddLine(ns.RecipeName(id), 1, 1, 1) end
	local s = ns.Schematic(id)
	if ns.AddMaterialLines and ns.AddMaterialLines(GameTooltip, id) then
		-- have/needed and who can get what's missing
	elseif s and #s.reagents > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Reagents:"], 1, 0.82, 0)
		for _, r in ipairs(s.reagents) do
			GameTooltip:AddLine(("  %d x %s"):format(r[2], ItemName(r[1])), 0.9, 0.9, 0.9)
		end
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Shift-click: link in chat"], 0.5, 0.75, 1)
	GameTooltip:Show()
end

local function BuildProfPanel()
	local p = MakePanel()
	prof.panel, prof.filters = p, {}

	prof.all = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
	prof.all:SetSize(64, 22)
	prof.all:SetText(L["All"])
	prof.all:SetPoint("TOPLEFT", 8, -8)
	prof.all:SetScript("OnClick", function() state.prof = nil ns.RefreshUI() end)

	prof.searchBox = MakeSearch(p, L["Search recipe or item"], function(q) state.search = q ns.RefreshUI() end)
	prof.searchBox:SetPoint("TOPRIGHT", -12, -9)
	prof.onlineBox = MakeCheck(p, L["Online only"], function(on) state.online = on ns.RefreshUI() end)
	prof.onlineBox:SetPoint("TOPLEFT", 8, -34)
	-- who takes requests right now (members with the addon who haven't turned them off)
	prof.takesBox = MakeCheck(p, L["Take requests"], function(on) state.takes = on ns.RefreshUI() end)
	prof.takesBox:SetPoint("LEFT", prof.onlineBox.Text or prof.onlineBox.text or prof.onlineBox, "RIGHT", 18, 0)

	prof.members = MakeList(p, MEMBER_ROW, function(b, d)
		MemberRow(b, d, ProfRightText(d))
		if not d.noaddon and not ns.TakesRequests(d.name) then
			b.left:SetText((b.left:GetText() or "") .. "  |cff909090(" .. L["no requests"] .. ")|r")
		end
		b.sel:SetShown(d.name == state.selected)
		b:SetScript("OnClick", function(_, button)
			if button == "RightButton" and d.online then Whisper(d.name) return end
			state.selected = d.name
			ns.RefreshUI()
		end)
		b:SetScript("OnEnter", nil)
		b:SetScript("OnLeave", nil)
	end, true)
	prof.members.box:SetPoint("TOPLEFT", 8, -60)
	prof.members.box:SetPoint("BOTTOMLEFT", 8, 8)
	prof.members.box:SetWidth(LEFT_W)

	local right = CreateFrame("Frame", nil, p)
	right:SetPoint("TOPLEFT", prof.members.box, "TOPRIGHT", 26, 0)
	right:SetPoint("BOTTOMRIGHT", -8, 8)
	prof.right = right
	prof.title = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	prof.title:SetPoint("TOPLEFT", 2, 2)
	prof.title:SetJustifyH("LEFT")
	prof.sub = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	prof.sub:SetPoint("TOPLEFT", prof.title, "BOTTOMLEFT", 0, -3)
	prof.whisper = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
	prof.whisper:SetSize(90, 22)
	prof.whisper:SetText(L["Whisper"])
	prof.whisper:SetPoint("TOPRIGHT", -18, 2)
	prof.whisper:SetScript("OnClick", function() if state.selectedData then Whisper(state.selectedData.name) end end)
	prof.note = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	prof.note:SetPoint("TOPLEFT", prof.sub, "BOTTOMLEFT", 0, -8)
	prof.note:SetPoint("RIGHT", right, "RIGHT", -18, 0)
	prof.note:SetJustifyH("LEFT")
	prof.note:SetWordWrap(true)
	prof.note:Hide()

	prof.recipes = MakeList(right, ROW, function(b, d)
		b:SetScript("OnEnter", nil)
		b:SetScript("OnLeave", GameTooltip_Hide)
		b:SetScript("OnClick", nil)
		if d.header then
			b.icon:SetTexture(d.icon or 134400)
			b.icon:Show()
			local fold = ""
			if (d.count or 0) > 0 then
				fold = (d.open and "|TInterface\\Buttons\\UI-MinusButton-Up:14:14|t " or "|TInterface\\Buttons\\UI-PlusButton-Up:14:14|t ")
				b:SetScript("OnClick", function()
					state.expanded[d.skill] = not d.open
					ns.RefreshUI()
				end)
			end
			b.left:SetText(fold .. d.text)
			b.left:SetTextColor(1, 0.82, 0)
			b.left:SetAlpha(1)
			b.right:SetText((d.count or 0) > 0 and L["%d recipes"]:format(d.count) or "")
			b.right:SetAlpha(0.7)
		else
			b.icon:SetTexture(ns.RecipeIcon(d.id))
			b.icon:Show()
			b.left:SetText(ns.RecipeName(d.id))
			b.left:SetTextColor(1, 1, 1)
			b.left:SetAlpha(1)
			b.right:SetText("")
			b:SetScript("OnEnter", function(self) RecipeTooltip(self, d.id) end)
			b:SetScript("OnClick", function()
				if IsShiftKeyDown() then InsertLink(RecipeLink(d.id))
				elseif d.crafter and d.crafter.online then Whisper(d.crafter.name) end
			end)
			if d.crafter and d.crafter.name ~= ns.Me() and ns.Req then
				local open = ns.TakesRequests(d.crafter.name)
				b.btn1:SetText(open and L["Request"] or L["No requests"])
				b.btn1:SetEnabled(open)
				b.btn1:SetScript("OnClick", function() ns.AskRequest(d.crafter.name, d.id) end)
				b.btn1:Show()
				b.right:SetText("")
			end
		end
	end)
	prof.recipes.box:SetPoint("TOPLEFT", 0, -46)
	prof.recipes.box:SetPoint("BOTTOMRIGHT", -14, 0)
	return p
end

--------------------------------------------------------------------------------
-- The talents tab
--------------------------------------------------------------------------------

local tal = {}

-- "Bestias 31/20/0" for the active spec group, or nil
local function TalentSummary(rec, group)
	local tl = rec and rec.tl
	local e = tl and tl.g and tl.g[group or tl.a or 1]
	if not e or not e.tr or #e.tr == 0 then return nil end
	local best, pts = nil, {}
	for _, t in ipairs(e.tr) do
		pts[#pts + 1] = t.s or 0
		if (t.s or 0) > 0 and (not best or t.s > best.s) then best = t end
	end
	return (best and (best.n .. " ") or "") .. table.concat(pts, "/"), best
end
ns.TalentSummary = TalentSummary

function ns.ViewTalents(rec, group, name)
	local e = rec and rec.tl and rec.tl.g and rec.tl.g[group]
	if not (e and e.str) then return end
	-- Blizzard's talent link: clicked in the chat, Blizzard's own handler opens its talent window (from our
	-- code it would load and show Blizzard's frames tainted)
	local text = ("[%s]"):format(L["Talents of %s"]:format(name or "?"))
	local link = ("|cff71d5ff|Htalentbuild:%d:%d:%s|h%s|h|r"):format(rec.tl.sp or 0, rec.l or 60, e.str, text)
	ns.Print(L["Click to see the tree: %s"]:format(link))
end

local function GroupBlock(parent)
	local b = CreateFrame("Frame", nil, parent)
	b:SetHeight(118)
	b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	b.title:SetPoint("TOPLEFT", 0, 0)
	b.bars = {}
	for i = 1, 3 do
		local bar = CreateFrame("StatusBar", nil, b)
		bar:SetSize(220, 16)
		bar:SetPoint("TOPLEFT", 22, -18 - (i - 1) * 21)
		bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		bar:SetMinMaxValues(0, 1)
		local bg = bar:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(1, 1, 1, 0.07)
		bar.icon = bar:CreateTexture(nil, "ARTWORK")
		bar.icon:SetSize(18, 18)
		bar.icon:SetPoint("RIGHT", bar, "LEFT", -4, 0)
		bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		bar.name:SetPoint("LEFT", 4, 0)
		bar.pts = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		bar.pts:SetPoint("RIGHT", -4, 0)
		b.bars[i] = bar
	end
	b.view = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
	b.view:SetSize(170, 22)
	b.view:SetText(L["View talent tree"])
	b.view:SetPoint("TOPLEFT", 22, -84)
	return b
end

local function FillGroup(block, d, g)
	local tl = d.rec.tl
	local e = tl and tl.g and tl.g[g]
	if not e then block:Hide() return false end
	local title = L["Specialization %d"]:format(g)
	if tl.a == g then title = title .. "  |cff40ff40(" .. L["active"] .. ")|r" end
	block.title:SetText(title)
	local total, best = 0, 0
	for _, t in ipairs(e.tr or {}) do total = total + (t.s or 0) best = math.max(best, t.s or 0) end
	local r, gg, b = ClassRGB(d.class)
	for i, bar in ipairs(block.bars) do
		local t = e.tr and e.tr[i]
		if t then
			bar:SetMinMaxValues(0, math.max(total, 1))
			bar:SetValue(t.s or 0)
			bar:SetStatusBarColor(r, gg, b, ((t.s or 0) == best and best > 0) and 0.9 or 0.45)
			bar.icon:SetTexture(t.i or 134400)
			bar.name:SetText(t.n or "")
			bar.pts:SetText(t.s or 0)
			bar:Show()
		else
			bar:Hide()
		end
	end
	block.view:SetEnabled(e.str ~= nil)
	block.view:SetScript("OnClick", function() ns.ViewTalents(d.rec, g, d.short) end)
	block:Show()
	return true
end

local function RefreshTalDetail(d)
	local blocks = tal.blocks
	if not d then
		tal.title:SetText(L["Select a member"])
		tal.title:SetTextColor(0.6, 0.6, 0.6)
		tal.sub:SetText("")
		for _, b in ipairs(blocks) do b:Hide() end
		tal.profHead:Hide()
		tal.profText:SetText("")
		return
	end
	local className = d.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[d.class]) or ""
	tal.title:SetText(d.short .. "  |cffa0a0a0" .. (d.level and L["Level %d"]:format(d.level) or "") .. " " .. (className or "") .. "|r")
	tal.title:SetTextColor(ClassRGB(d.class))
	if not d.rec then
		tal.sub:SetText(L["This member doesn't have the addon."])
		for _, b in ipairs(blocks) do b:Hide() end
		tal.profHead:Hide()
		tal.profText:SetText("")
		return
	end
	tal.sub:SetText(L["Last update: %s"]:format(ns.Ago(d.rec.t)))
	local y, shown = -44, 0
	for g = 1, 2 do
		local block = blocks[g]
		if FillGroup(block, d, g) then
			block:ClearAllPoints()
			block:SetPoint("TOPLEFT", 0, y)
			block:SetPoint("RIGHT", 0, 0)
			y = y - 122
			shown = shown + 1
		end
	end
	if shown == 0 then
		tal.sub:SetText(tal.sub:GetText() .. "  ·  " .. L["No talent data yet."])
	end
	tal.profHead:ClearAllPoints()
	tal.profHead:SetPoint("TOPLEFT", 0, y - 4)
	tal.profHead:Show()
	local lines = {}
	for _, skill in ipairs(ns.PROF_ORDER) do
		local p = d.rec.p and d.rec.p[skill]
		if p then
			lines[#lines + 1] = ("%s %s  %d/%d  —  %s"):format(Icon(p.i or ns.PROF_ICONS[skill], 14), p.n or "", p.r or 0, p.m or 0,
				p.s and ("|cffffd100" .. p.s .. "|r") or ("|cff808080" .. L["None"] .. "|r"))
		end
	end
	tal.profText:SetText(table.concat(lines, "\n"))
end

local function RefreshTal()
	local q = state.talSearch
	local list = Members(function(d)
		if state.talOnline and not d.online then return false end
		if q ~= "" and not d.short:lower():find(q, 1, true) then return false end
		return true
	end)
	table.sort(list, function(a, b)
		if a.noaddon ~= b.noaddon then return not a.noaddon end
		if (a.class or "") ~= (b.class or "") then return (a.class or "") < (b.class or "") end
		if a.online ~= b.online then return a.online end
		return a.short < b.short
	end)
	local count, picked = 0, nil
	for _, d in ipairs(list) do
		if not d.noaddon then count = count + 1 end
		if d.name == state.talSelected then picked = d end
	end
	tal.count:SetText(L["Members with the addon: %d"]:format(count))
	tal.members:Set(ns.GroupRows(list, state.altsOpen))
	RefreshTalDetail(picked)
end

local function BuildTalPanel()
	local p = MakePanel()
	tal.panel = p
	tal.searchBox = MakeSearch(p, L["Search member"], function(q) state.talSearch = q ns.RefreshUI() end)
	tal.searchBox:SetPoint("TOPLEFT", 14, -9)
	tal.onlineBox = MakeCheck(p, L["Online only"], function(on) state.talOnline = on ns.RefreshUI() end)
	tal.onlineBox:SetPoint("LEFT", tal.searchBox, "RIGHT", 10, 0)
	tal.count = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tal.count:SetPoint("TOPRIGHT", -14, -14)

	tal.members = MakeList(p, MEMBER_ROW, function(b, d)
		MemberRow(b, d, d.rec and TalentSummary(d.rec) or nil)
		b.sel:SetShown(d.name == state.talSelected)
		b:SetScript("OnClick", function(_, button)
			if button == "RightButton" and d.online then Whisper(d.name) return end
			state.talSelected = d.name
			ns.RefreshUI()
		end)
		b:SetScript("OnEnter", nil)
		b:SetScript("OnLeave", nil)
	end, true)
	tal.members.box:SetPoint("TOPLEFT", 8, -38)
	tal.members.box:SetPoint("BOTTOMLEFT", 8, 8)
	tal.members.box:SetWidth(LEFT_W)

	local right = CreateFrame("Frame", nil, p)
	right:SetPoint("TOPLEFT", tal.members.box, "TOPRIGHT", 26, 0)
	right:SetPoint("BOTTOMRIGHT", -12, 8)
	tal.title = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	tal.title:SetPoint("TOPLEFT", 2, 2)
	tal.sub = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tal.sub:SetPoint("TOPLEFT", tal.title, "BOTTOMLEFT", 0, -3)
	tal.blocks = { GroupBlock(right), GroupBlock(right) }
	tal.profHead = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tal.profHead:SetText(L["Profession specializations"])
	tal.profText = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tal.profText:SetPoint("TOPLEFT", tal.profHead, "BOTTOMLEFT", 4, -6)
	tal.profText:SetJustifyH("LEFT")
	tal.profText:SetSpacing(4)
	return p
end

--------------------------------------------------------------------------------
-- Tabs and panels on the guild window
--------------------------------------------------------------------------------

local BLIZZ_TABS = { "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab", "GuildPreferredPlaySettingsTab" }

local function IsGuildShown()
	if not (CF and CF:IsShown()) then return false end
	local mode = CF.GetDisplayMode and CF:GetDisplayMode()
	if COMMUNITIES_FRAME_DISPLAY_MODES and mode == COMMUNITIES_FRAME_DISPLAY_MODES.MINIMIZED then return false end
	local id = CF.GetSelectedClubId and CF:GetSelectedClubId()
	local info = id and C_Club and C_Club.GetClubInfo and C_Club.GetClubInfo(id)
	return info ~= nil and Enum.ClubType and info.clubType == Enum.ClubType.Guild
end

local function AnchorPanel(p)
	p:ClearAllPoints()
	local list = CF.CommunitiesList
	if list and list:IsShown() then
		p:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, 0)
	else
		p:SetPoint("TOPLEFT", CF, "TOPLEFT", 8, -23)
	end
	p:SetPoint("BOTTOMRIGHT", CF, "BOTTOMRIGHT", -8, 6)
end

-- Blizzard's content of the guild window that would show through our panel (its chat box, its
-- scrollbars in a higher strata): made invisible while a panel of ours shows, put back after.
-- Only their alpha: hiding them would run Blizzard's OnHide scripts from our code (the chat box's
-- writes the chat globals), which taints them, and later the Esc key's protected calls fail.
local COVERED = { "Chat", "ChatEditBox", "MemberList", "GuildMemberDetailFrame", "GuildBenefitsFrame",
	"GuildDetailsFrame", "GuildMemberListDropdown", "CommunityMemberListDropdown", "StreamDropdown",
	"ApplicantList", "GuildNameAlertFrame" }
local hidden = {}
local coveredMode                -- Blizzard's display mode when we covered it

local function CoverBlizzard()
	if not next(hidden) then coveredMode = CF.GetDisplayMode and CF:GetDisplayMode() end
	for _, key in ipairs(COVERED) do
		local f = CF[key]
		if f and f.GetAlpha and not hidden[key] then
			hidden[key] = f:GetAlpha()
			f:SetAlpha(0)
		end
	end
end

local function UncoverBlizzard()
	for key, alpha in pairs(hidden) do
		local f = CF[key]
		if f then f:SetAlpha(alpha) end
		hidden[key] = nil
	end
end

-- `restore`: put Blizzard's frames back (false when Blizzard just switched mode and set them itself)
local function HidePanels(restore)
	for _, p in pairs(panels) do p:Hide() end
	for _, t in pairs(tabs) do t:SetChecked(false) end
	UncoverBlizzard()
end

local function ShowPanel(which)
	for key, p in pairs(panels) do
		if key == which then
			AnchorPanel(p)
			p:Show()
		else
			p:Hide()
		end
	end
	for key, t in pairs(tabs) do t:SetChecked(key == which) end
	CoverBlizzard()
	for _, key in ipairs(BLIZZ_TABS) do
		if CF[key] then CF[key]:SetChecked(false) end
	end
	ns.RefreshUI(true)
end
ns.ShowPanel = ShowPanel
ns.OpenGuildTab = function(which) if ns.OpenGuild then ns.OpenGuild(which) end end

local function UpdateTabs()
	if not CF then return end
	local show = IsGuildShown()
	local last
	for _, key in ipairs(BLIZZ_TABS) do
		local t = CF[key]
		if t and t:IsShown() then last = t end
	end
	local prev = last
	for _, key in ipairs({ "prof", "tal", "req" }) do
		local t = tabs[key]
		t:SetShown(show and prev ~= nil)
		if prev then
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -20)
			prev = t
		end
	end
	if not show then HidePanels() end
end

local function MakeTab(key, icon, tooltip)
	local t = CreateFrame("CheckButton", nil, CF, "RightSideTabTemplate")
	if t.Icon then t.Icon:SetTexture(icon) end
	t.tooltip = tooltip
	t:SetFrameLevel((CF.RosterTab and CF.RosterTab:GetFrameLevel()) or (CF:GetFrameLevel() + 510))
	t:SetScript("OnClick", function()
		PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
		ShowPanel(key)
	end)
	t:Hide()
	tabs[key] = t
end

local function SetUp()
	if CF or not CommunitiesFrame then return end
	CF = CommunitiesFrame
	panels.prof = BuildProfPanel()
	panels.tal = BuildTalPanel()
	MakeTab("prof", PROF_TAB_ICON, L["Professions"])
	MakeTab("tal", TAL_TAB_ICON, L["Specializations and talents"])
	panels.req = ns.BuildReqPanel(MakePanel, MakeList, MemberRow, RecipeTooltip, ClassRGB)
	MakeTab("req", "Interface\\Icons\\INV_Letter_15", L["Requests"])
	local badge = tabs.req:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	badge:SetPoint("TOPRIGHT", tabs.req, "TOPRIGHT", -2, -2)
	badge:SetTextColor(1, 0.3, 0.3)
	tabs.req.badge = badge
	if CF.UpdateCommunitiesTabs then hooksecurefunc(CF, "UpdateCommunitiesTabs", UpdateTabs) end
	if CF.SetDisplayMode then
		hooksecurefunc(CF, "SetDisplayMode", function(_, mode)
			-- the same mode again (its tab clicked from ours): Blizzard did nothing, so we put its frames back
			local changed = next(hidden) ~= nil and mode ~= coveredMode
			HidePanels(not changed)
			UpdateTabs()
		end)
	end
	CF:HookScript("OnShow", function()
		UpdateTabs()
		if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
		if wantTab then
			local which = wantTab
			wantTab = nil
			C_Timer.After(0.1, function() if IsGuildShown() then ShowPanel(which) end end)
		end
	end)
	CF:HookScript("OnHide", function() HidePanels(true) end)
	UpdateTabs()
	-- what the guided tour points at
	ns.ui = { tabs = tabs, panels = panels, prof = prof, tal = tal, show = ShowPanel, shown = IsGuildShown }
end

--------------------------------------------------------------------------------
-- Refresh, at most once a frame, only what shows
--------------------------------------------------------------------------------

local queued = false
local function DoRefresh()
	queued = false
	if not CF then return end
	if panels.prof:IsShown() then RefreshProf() end
	if panels.tal:IsShown() then RefreshTal() end
	if panels.req:IsShown() then ns.RefreshReq() end
	ns.UpdateBadge()
end

-- The number on the Requests tab: requests waiting for my answer
function ns.UpdateBadge()
	local t = tabs.req
	if not (t and t.badge) then return end
	local n = ns.Req and ns.Req.PendingForMe() or 0
	t.badge:SetText(n > 0 and tostring(n) or "")
end

function ns.RefreshUI(now)
	if now then DoRefresh() return end
	if queued then return end
	queued = true
	C_Timer.After(0, DoRefresh)
end

--------------------------------------------------------------------------------
-- Loading with Blizzard's guild window, and /gcraft
--------------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
	if ns.disabled then return end
	if event == "PLAYER_LOGIN" or name == "Blizzard_Communities" then
		if CommunitiesFrame then SetUp() end
	end
end)

-- Our tab, shown now if the guild window is open, else as soon as the player opens it (J). The window
-- itself is never opened from here: a UI panel an addon shows taints Blizzard's panel manager.
local wantTab
local function OpenGuild(which)
	SetUp()
	if IsGuildShown() then
		ShowPanel(which)
	else
		wantTab = which
		ns.Print(L["Press J to open the guild window: it will open on that tab."])
	end
end

-- What used to be commands, now buttons in the options (the commands still work)
function ns.SendAgain()
	ns.Rescan("all")
	ns.Hello(false)
	ns.Print(L["Sharing your data with the guild."])
end

function ns.MakeMain()
	GuildCraftersForeverDB.main = ns.Me()
	ns.Rescan("all")
	ns.Print(L["%s is now your main: your other characters will show as its alts."]:format(ns.Me()))
end

function ns.PruneNow()
	ns.Print(L["Removed %d old members."]:format(ns.Prune()))
	ns.RefreshUI()
end

-- Sync diagnostics, for bug reports
function ns.PrintStatus()
	local g = ns.Guild()
	local n, mine = 0, 0
	for _ in pairs(g and g.members or {}) do n = n + 1 end
	local me = ns.MyRecord()
	for _, p in pairs(me.p or {}) do mine = mine + #(p.rc or {}) end
	ns.Print(L["Me: %s  ·  GUID %s  ·  game name: %s  ·  version %s"]:format(tostring(ns.Me()), tostring(UnitGUID("player")),
		tostring(UnitName("player")), tostring(ns.MyVersion and ns.MyVersion() or "?")))
	ns.Print(L["Guild: %s  ·  roster: %d members  ·  saved records: %d"]:format(tostring(IsInGuild() and GetGuildInfo("player")), #ns.roster, n))
	ns.Print(L["My record: stamp %s  ·  %d recipes  ·  talents: %s"]:format(tostring(me.t), mine, tostring(ns.TalentSummary(me))))
	ns.Print(L["Messages: sent %d (failed %d)  ·  received %d  ·  records received %d"]:format(ns.stats.sent, ns.stats.failed, ns.stats.got, ns.stats.records))
	for _, line in ipairs(ns.LogLines()) do ns.Print("  " .. line) end
end

local function Slash(msg)
	local cmd = strlower(strtrim(msg or ""))
	if cmd == "" or cmd == "prof" then
		OpenGuild("prof")
	elseif cmd == "talentos" or cmd == "talents" then
		OpenGuild("tal")
	elseif cmd == "solicitudes" or cmd == "requests" then
		OpenGuild("req")
	elseif cmd == "enviar" or cmd == "send" then
		ns.SendAgain()
	elseif cmd == "main" then
		ns.MakeMain()
	elseif cmd == "versiones" or cmd == "versions" then
		if ns.PrintVersions then ns.PrintVersions() end
	elseif cmd == "atajo" or cmd == "shortcut" then
		if ns.RecordShortcut then ns.RecordShortcut() end
	elseif cmd == "opciones" or cmd == "options" or cmd == "config" then
		if ns.OpenOptions then ns.OpenOptions() end
	elseif cmd == "estado" or cmd == "status" then
		ns.PrintStatus()
	elseif cmd == "limpiar" or cmd == "prune" then
		ns.PruneNow()
	elseif cmd == "tutorial" then
		if ns.StartTutorial then ns.StartTutorial() end
	else
		ns.Print(L["/gcraft opens GuildCrafters Forever. Everything else is in Esc > Options > AddOns > GuildCrafters Forever."])
	end
end

-- (not while the old folder runs: its /gcraft stays its own)
if not ns.disabled then
	SLASH_GUILDCRAFTERSFOREVER1 = "/gcraft"
	SLASH_GUILDCRAFTERSFOREVER2 = "/guildcrafters"
	SLASH_GUILDCRAFTERSFOREVER3 = "/gcf"
	SlashCmdList.GUILDCRAFTERSFOREVER = Slash
end
ns.OpenGuild = OpenGuild
ns.Whisper = Whisper
ns.RecipeLinkFor = RecipeLink
ns.InsertLinkFor = InsertLink
