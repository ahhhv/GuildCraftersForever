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
	local myMain = ns.MainOf(me)
	local out, seen = {}, {}
	for _, recipe in ipairs(recipes or {}) do
		for _, key in ipairs(index[recipe] or {}) do
			if key ~= me and not seen[key] then
				seen[key] = true
				local e = ns.inRoster[key]
				-- mine: one of your own characters (nobody to ask)
				out[#out + 1] = { key = key, recipe = recipe, online = e and e.online or false, class = e and e.class,
					closed = not ns.TakesRequests(key), mine = ns.MainOf(key) == myMain }
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
		if c.mine then name = name .. " |cff909090(" .. L["your alt"] .. ")|r"
		elseif main ~= c.key then name = name .. " |cff909090(" .. L["alt of %s"]:format(main) .. ")|r" end
		if c.online then name = name .. " |cff40ff40•|r" end
		if c.closed and not c.mine then name = name .. " |cff909090(" .. L["no requests"] .. ")|r" end
		parts[#parts + 1] = name
	end
	return table.concat(parts, ", ")
end

--------------------------------------------------------------------------------
-- The shortcut, as the player recorded it: "ALT-CTRL-SHIFT-<mouse button>" (any modifiers, in that
-- order, at least one) or "none". Older versions saved "alt", "ctrlalt" or "shiftalt".
--------------------------------------------------------------------------------

local LEGACY = { alt = "ALT-LeftButton", ctrlalt = "ALT-CTRL-LeftButton", shiftalt = "ALT-SHIFT-LeftButton" }
local BUTTON_TEXT = { LeftButton = "click", RightButton = "right-click", MiddleButton = "middle-click",
	Button4 = "button 4", Button5 = "button 5" }

-- { alt, ctrl, shift, button } or nil when there's none
function ns.ParseShortcut(s)
	s = LEGACY[s] or s
	if type(s) ~= "string" or s == "none" then return nil end
	local k = { button = s:match("([%w]+)$") }
	k.alt, k.ctrl, k.shift = s:find("ALT-", 1, true) ~= nil, s:find("CTRL-", 1, true) ~= nil, s:find("SHIFT-", 1, true) ~= nil
	if not (k.button and BUTTON_TEXT[k.button] and (k.alt or k.ctrl or k.shift)) then return nil end
	return k
end

function ns.MakeShortcut(alt, ctrl, shift, button)
	if not (alt or ctrl or shift) or not BUTTON_TEXT[button] then return nil end
	return (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "") .. button
end

-- "Ctrl+Alt+right-click", or nil when there's none
function ns.ShortcutText(s)
	local k = ns.ParseShortcut(s or ns.Opt("shortcut"))
	if not k then return nil end
	local parts = {}
	if k.ctrl then parts[#parts + 1] = "Ctrl" end
	if k.alt then parts[#parts + 1] = "Alt" end
	if k.shift then parts[#parts + 1] = "Shift" end
	parts[#parts + 1] = L[BUTTON_TEXT[k.button]]
	return table.concat(parts, "+")
end

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
			local key = ns.ShortcutText()
			if key then
				local open = false
				for _, c in ipairs(list) do if not c.closed and not c.mine then open = true break end end
				tooltip:AddLine((open and L["%s: request it from the guild"] or L["%s: post it on the guild board"]):format(key), 0.5, 0.75, 1)
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
	local k = ns.ParseShortcut(ns.Opt("shortcut"))
	if not k then return false end
	if (IsAltKeyDown() and true or false) ~= k.alt or (IsControlKeyDown() and true or false) ~= k.ctrl
		or (IsShiftKeyDown() and true or false) ~= k.shift then return false end
	local button = GetMouseButtonClicked and GetMouseButtonClicked()
	return button == nil or button == k.button
end

function ns.RequestItem(itemID)
	local recipes = ns.RecipesForItem(itemID)
	local list = Crafters(recipes)
	local others, myAlt = {}, nil
	for _, c in ipairs(list) do
		if c.mine then myAlt = myAlt or c.key else others[#others + 1] = c end
	end
	-- nobody else can, but you (or one of your characters) can: nothing to ask
	if #others == 0 and (IKnow(recipes) or myAlt) then
		local name = C_Item.GetItemNameByID(itemID) or ("#" .. itemID)
		if IKnow(recipes) then ns.Print(L["You can craft %s yourself."]:format(name))
		else ns.Print(L["Your character %s can craft %s."]:format(myAlt, name)) end
		return
	end
	list = others
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
