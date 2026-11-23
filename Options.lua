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

	local shortcut = Settings.RegisterAddOnSetting(category, "GUILDCRAFTERSFOREVER_shortcut", "shortcut", opts, "string",
		L["Shortcut to request an item"], ns.DEFAULTS.shortcut)
	Settings.CreateDropdown(category, shortcut, function()
		local c = Settings.CreateControlTextContainer()
		c:Add("alt", "Alt + " .. L["click"])
		c:Add("ctrlalt", "Ctrl + Alt + " .. L["click"])
		c:Add("shiftalt", "Shift + Alt + " .. L["click"])
		c:Add("none", L["None"])
		return c:GetData()
	end, L["Click an item with this in your bags, a chat link or the auction house to ask a guildmate to craft it."])

	Check("shareAlts", L["Share my alts with the guild"],
		L["Your characters with the addon show together under your main. Untick it to keep your alts private."],
		function() ns.Rescan("all") end)

	Check("sound", L["Sound with request notices"], L["Play a sound when someone asks you for a recipe or answers your request."])

	Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
	if category and Settings.OpenToCategory then Settings.OpenToCategory(category:GetID()) end
end
