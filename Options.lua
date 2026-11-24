-- GuildCrafters Forever
-- Copyright (C) 2026 jamiforever
-- Licensed under the GNU General Public License v3.0 or later (see LICENSE).
--------------------------------------------------------------------------------
-- The addon's page in Blizzard's settings (Esc > Options > AddOns > GuildCrafters Forever).
-- Values live in GuildCraftersForeverDB.opts (defaults: ns.DEFAULTS in Data.lua).
--------------------------------------------------------------------------------

local ADDON, ns = ...
local L = ns.L

local category

function ns.SetUpOptions()
	if category or not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
	local opts = GuildCraftersForeverDB.opts
	category = Settings.RegisterVerticalLayoutCategory("GuildCrafters Forever")

	local function Check(key, name, tooltip, onChange)
		local setting = Settings.RegisterAddOnSetting(category, "GUILDCRAFTERSFOREVER_" .. key, key, opts, "boolean", name, ns.DEFAULTS[key])
		if onChange and setting.SetValueChangedCallback then setting:SetValueChangedCallback(onChange) end
		Settings.CreateCheckbox(category, setting, tooltip)
	end

	Check("tooltip", L["Show who crafts items on tooltips"],
		L["Item tooltips say who in your guild can craft them, and recipe items who already knows them."])

	-- buttons (each also has its old /gcraft command, unannounced)
	local layout = SettingsPanel and SettingsPanel.GetLayout and SettingsPanel:GetLayout(category)
	local function Header(text)
		if not (layout and CreateSettingsListSectionHeaderInitializer) then return end
		pcall(function() layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text)) end)
	end
	local function Button(name, text, tip, fn)
		if not (layout and CreateSettingsButtonInitializer) then return end
		local ok = pcall(function() layout:AddInitializer(CreateSettingsButtonInitializer(name, text, fn, tip, true)) end)
		if not ok and ns.Log then ns.Log("options: no button for " .. name) end
	end

	Button(L["Shortcut to request an item"], L["Record…"],
		L["Use it on an item in your bags, a chat link or the auction house to ask a guildmate to craft it. Pick any combination of Alt, Ctrl and Shift with a mouse button."],
		function() ns.RecordShortcut() end)

	Header(L["Getting started"])
	Button(L["Guided tour"], L["Start"], L["A step-by-step tour of the addon over the guild window."],
		function() if ns.StartTutorial then ns.StartTutorial() end end)

	Header(L["Your characters"])
	Button(L["Main character"], L["Make this one my main"],
		L["Your other characters show as its alts. Otherwise your main is your highest-level character."],
		function() ns.MakeMain() end)

	Header(L["Guild"])
	Button(L["Versions"], L["Show in chat"], L["Which version of the addon each member has."],
		function() if ns.PrintVersions then ns.PrintVersions() end end)
	Button(L["Your data"], L["Send again"], L["Share your professions, recipes and talents with the guild again."],
		function() ns.SendAgain() end)
	Button(L["Old members"], L["Forget"], L["Forget the data of members who left the guild."],
		function() ns.PruneNow() end)
	Button(L["Diagnostics"], L["Show in chat"], L["Sync details, to attach to a bug report."],
		function() ns.PrintStatus() end)

	Check("shareAlts", L["Share my alts with the guild"],
		L["Your characters with the addon show together under your main. Untick it to keep your alts private."],
		function() ns.Rescan("all") end)

	Check("acceptRequests", L["Take recipe requests"],
		L["Guildmates can ask you to craft their recipes, and board posts you can craft send you a notice. Untick it and nobody can send you requests; you still see the guild board."],
		function() ns.Rescan("all") end)

	Check("sound", L["Sound with request notices"], L["Play a sound when someone asks you for a recipe or answers your request."])

	Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
	if category and Settings.OpenToCategory then Settings.OpenToCategory(category:GetID()) end
end

--------------------------------------------------------------------------------
-- The shortcut recorder: click the box with the combination you want
--------------------------------------------------------------------------------

local recorder

local function Warn(s)
	if s == "SHIFT-LeftButton" then return L["Careful: Blizzard also uses Shift+click (it links the item in chat)."] end
	if s == "CTRL-LeftButton" then return L["Careful: Blizzard also uses Ctrl+click (it shows the item on your character)."] end
	return nil
end

function ns.RecordShortcut()
	if not recorder then
		local r = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		r:SetSize(380, 190)
		r:SetPoint("CENTER", 0, 120)
		r:SetFrameStrata("FULLSCREEN_DIALOG")
		r:EnableMouse(true)
		if r.SetBackdrop then
			r:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
			r:SetBackdropColor(0.05, 0.13, 0.08, 0.97)
			r:SetBackdropBorderColor(0.75, 0.5, 0.25, 1)
		end
		r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		r.text:SetPoint("TOPLEFT", 16, -14)
		r.text:SetPoint("TOPRIGHT", -16, -14)
		r.text:SetText(L["Hold Alt, Ctrl and/or Shift and click the box with the mouse button you want."])
		r.box = CreateFrame("Button", nil, r, "BackdropTemplate")
		r.box:SetSize(320, 56)
		r.box:SetPoint("TOP", 0, -50)
		r.box:RegisterForClicks("AnyUp")
		if r.box.SetBackdrop then
			r.box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
			r.box:SetBackdropColor(0.15, 0.15, 0.15, 1)
			r.box:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
		end
		r.current = r.box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		r.current:SetPoint("CENTER")
		r.msg = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		r.msg:SetPoint("TOP", r.box, "BOTTOM", 0, -8)
		r.msg:SetWidth(340)
		r.box:SetScript("OnClick", function(_, button)
			local s = ns.MakeShortcut(IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown(), button)
			if not s then
				r.msg:SetText("|cffff6060" .. L["Hold at least one of Alt, Ctrl or Shift while you click."] .. "|r")
				return
			end
			GuildCraftersForeverDB.opts.shortcut = s
			r.current:SetText(ns.ShortcutText(s))
			local warn = Warn(s)
			r.msg:SetText(warn and ("|cffffd100" .. warn .. "|r") or ("|cff40ff40" .. L["Saved."] .. "|r"))
			ns.Print(L["Shortcut to request an item: %s"]:format(ns.ShortcutText(s)))
			if ns.RefreshUI then ns.RefreshUI() end
		end)
		r.off = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
		r.off:SetSize(120, 22)
		r.off:SetPoint("BOTTOMRIGHT", r, "BOTTOM", -6, 12)
		r.off:SetText(L["Turn it off"])
		r.off:SetScript("OnClick", function()
			GuildCraftersForeverDB.opts.shortcut = "none"
			r.current:SetText(L["None"])
			r.msg:SetText(L["Saved."])
			ns.Print(L["Shortcut to request an item: %s"]:format(L["None"]))
		end)
		r.close = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
		r.close:SetSize(120, 22)
		r.close:SetPoint("BOTTOMLEFT", r, "BOTTOM", 6, 12)
		r.close:SetText(CLOSE or "Close")
		r.close:SetScript("OnClick", function() r:Hide() end)
		r:Hide()
		recorder = r
	end
	recorder.current:SetText(ns.ShortcutText() or L["None"])
	recorder.msg:SetText("")
	recorder:Show()
end
