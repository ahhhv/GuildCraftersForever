-- GuildCrafters Forever
-- Copyright (C) 2026 jamiforever
-- Licensed under the GNU General Public License v3.0 or later (see LICENSE).
--------------------------------------------------------------------------------
-- "Who crafts it?" on item tooltips (bags, chat links, the auction house...):
--   * an item someone in the guild can craft: who (online first, alts shown
--     as their main), and whether you can too;
--   * a recipe item (Pattern, Plans, Formula...): who already knows it;
--   * the shortcut to request it (a modified click, chosen in the options).
-- The click goes through a post-hook of Blizzard's HandleModifiedItemClick,
-- which never changes what Blizzard does with the click.
--------------------------------------------------------------------------------

local ADDON, ns = ...
local L = ns.L

local MAX_NAMES = 5
local HEAD = { 0.9, 0.7, 0.35 }

local function ItemIDFrom(link)
	if type(link) ~= "string" or ns.Secret(link) then return nil end
	return tonumber(link:match("item:(%d+)"))
end

-- The members (not me) who know one of `recipes`: { { key, recipe, online, class } }, online first
local function Crafters(recipes)
	local index, me = ns.CraftIndex(), ns.Me()
	local out, seen = {}, {}
	for _, recipe in ipairs(recipes or {}) do
		for _, key in ipairs(index[recipe] or {}) do
			if key ~= me and not seen[key] then
				seen[key] = true
				local e = ns.inRoster[key]
				out[#out + 1] = { key = key, recipe = recipe, online = e and e.online or false, class = e and e.class,
					closed = not ns.TakesRequests(key) }
			end
		end
	end
	table.sort(out, function(a, b)
		if a.online ~= b.online then return a.online end
		return a.key < b.key
	end)
	return out
end
ns.Crafters = Crafters

local function IKnow(recipes)
	local index, me = ns.CraftIndex(), ns.Me()
	for _, recipe in ipairs(recipes or {}) do
		for _, key in ipairs(index[recipe] or {}) do
			if key == me then return true end
		end
	end
	return false
end

-- "Artema (online), Jami, Yusuke (alt of Jami)..."
local function Names(list)
	local parts = {}
	for i, c in ipairs(list) do
		if i > MAX_NAMES then
			parts[#parts + 1] = L["+%d more"]:format(#list - MAX_NAMES)
			break
		end
		local color = c.class and ((C_ClassColor and C_ClassColor.GetClassColor(c.class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]))
		local name = c.key
		if color and color.WrapTextInColorCode then name = color:WrapTextInColorCode(name) end
		local main = ns.MainOf(c.key)
		if main ~= c.key then name = name .. " |cff909090(" .. L["alt of %s"]:format(main) .. ")|r" end
		if c.online then name = name .. " |cff40ff40•|r" end
		if c.closed then name = name .. " |cff909090(" .. L["no requests"] .. ")|r" end
		parts[#parts + 1] = name
	end
	return table.concat(parts, ", ")
end

local SHORTCUT_TEXT = { alt = "Alt", ctrlalt = "Ctrl+Alt", shiftalt = "Shift+Alt" }

local function AddLines(tooltip, itemID, itemName)
	if not (ns.Opt("tooltip") and ns.Guild()) then return end
	local added = false
	local function head(text)
		if not added then
			tooltip:AddLine(" ")
			added = true
		end
		tooltip:AddLine(text, HEAD[1], HEAD[2], HEAD[3])
	end
	-- crafted by
	local recipes = ns.RecipesForItem(itemID)
	if recipes then
		local list = Crafters(recipes)
		if #list > 0 then
			head(L["Crafted in your guild by:"])
			tooltip:AddLine(Names(list), 1, 1, 1, true)
			local key = SHORTCUT_TEXT[ns.Opt("shortcut")]
			if key then
				local open = false
				for _, c in ipairs(list) do if not c.closed then open = true break end end
				tooltip:AddLine((open and L["%s+click: request it from the guild"] or L["%s+click: post it on the guild board"]):format(key), 0.5, 0.75, 1)
			end
		end
		if IKnow(recipes) then
			if not added then head(L["Crafted in your guild by:"]) end
			tooltip:AddLine(L["You can craft it too."], 0.4, 1, 0.4)
		end
	end
	-- a recipe item: who already knows what it teaches
	local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
	if classID == (Enum.ItemClass and Enum.ItemClass.Recipe or 9) then
		local teaches = ns.RecipeForPatternName(itemName)
		if teaches then
			local list = Crafters({ teaches })
			if #list > 0 then
				head(L["Already known in your guild by:"])
				tooltip:AddLine(Names(list), 1, 1, 1, true)
			end
			if IKnow({ teaches }) then
				if not added then head(L["Already known in your guild by:"]) end
				tooltip:AddLine(L["You already know it."], 0.4, 1, 0.4)
			end
		end
	end
	if added then tooltip:Show() end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		if ns.disabled or not tooltip or tooltip.IsForbidden and tooltip:IsForbidden() then return end
		local itemID = data and data.id
		if ns.Secret(itemID) or type(itemID) ~= "number" then return end
		local name = tooltip.GetItem and select(1, tooltip:GetItem())
		if ns.Secret(name) then name = nil end
		local ok, err = pcall(AddLines, tooltip, itemID, name or (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)))
		if not ok and ns.Log then ns.Log("tooltip: " .. tostring(err)) end
	end)
end

--------------------------------------------------------------------------------
-- The shortcut: a modified click on an item asks the guild for it
--------------------------------------------------------------------------------

local function ShortcutDown()
	local s = ns.Opt("shortcut")
	if s == "alt" then return IsAltKeyDown() and not IsControlKeyDown() and not IsShiftKeyDown() end
	if s == "ctrlalt" then return IsAltKeyDown() and IsControlKeyDown() and not IsShiftKeyDown() end
	if s == "shiftalt" then return IsAltKeyDown() and IsShiftKeyDown() and not IsControlKeyDown() end
	return false
end

function ns.RequestItem(itemID)
	local recipes = ns.RecipesForItem(itemID)
	local list = Crafters(recipes)
	if #list == 0 then
		-- nobody with the addon knows it: the guild board may still find someone
		if recipes and recipes[1] and ns.ConfirmPost then ns.ConfirmPost(recipes[1]) end
		return
	end
	if ns.ChooseCrafter then ns.ChooseCrafter(itemID, list) end
end

if hooksecurefunc and HandleModifiedItemClick then
	hooksecurefunc("HandleModifiedItemClick", function(link)
		if ns.disabled or not ShortcutDown() then return end
		local itemID = ItemIDFrom(link)
		if itemID and ns.RecipesForItem(itemID) then ns.RequestItem(itemID) end
	end)
end
