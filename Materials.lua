-- GuildCrafters Forever
-- Copyright (C) 2026 jamiforever
-- Licensed under the GNU General Public License v3.0 or later (see LICENSE).
--------------------------------------------------------------------------------
-- The materials calculator: what a recipe needs, how much of it you have
-- (bags and bank), and for what you're missing, who in the guild can get it:
--   * crafters: members who know a recipe that makes that material
--     (Bolt of Linen Cloth: the tailors);
--   * gatherers: members with the gathering profession its kind of item comes
--     from (herbs: Herbalism, ore and stone: Mining, leather: Skinning,
--     enchanting materials: Enchanting, by disenchanting).
-- Nobody's bags are shared: only professions and recipes, as always.
--------------------------------------------------------------------------------

local ADDON, ns = ...
local L = ns.L

local MAX_NAMES = 3

-- Trade goods (item class 7) by subclass -> the skill line that gathers them
local TRADESKILL = 7
local GATHER = {
	[9] = 182,  -- Herb -> Herbalism
	[7] = 186,  -- Metal & Stone -> Mining
	[6] = 393,  -- Leather -> Skinning
	[12] = 333, -- Enchanting -> Enchanting (disenchant)
}

local function Count(itemID)
	if C_Item and C_Item.GetItemCount then
		local ok, n = pcall(C_Item.GetItemCount, itemID, true)
		if ok and n then return n end
	end
	if GetItemCount then
		local ok, n = pcall(GetItemCount, itemID, true)
		if ok and n then return n end
	end
	return 0
end

local function ItemName(id)
	return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ("#" .. id)
end

-- The members (not me) with `skill`, online first, then the highest skill
local function Gatherers(skill)
	local g, me, out = ns.Guild(), ns.Me(), {}
	for key, rec in pairs(g and g.members or {}) do
		local p = rec.p and rec.p[skill]
		if key ~= me and p and (#ns.roster == 0 or ns.inRoster[key]) then
			local e = ns.inRoster[key]
			out[#out + 1] = { key = key, online = e and e.online or false, rank = p.r or 0 }
		end
	end
	table.sort(out, function(a, b)
		if a.online ~= b.online then return a.online end
		if a.rank ~= b.rank then return a.rank > b.rank end
		return a.key < b.key
	end)
	return out
end

-- What `recipe` needs, `times` over: { { item, need, have, crafters, gatherers, skill } }
function ns.Materials(recipe, times)
	local s = recipe and recipe > 0 and ns.Schematic(recipe)
	if not s then return nil end
	times = times or 1
	local out = {}
	for _, r in ipairs(s.reagents) do
		local item, need = r[1], r[2] * times
		local m = { item = item, need = need, have = Count(item) }
		if m.have < need then
			m.crafters = ns.Crafters and ns.Crafters(ns.RecipesForItem(item)) or {}
			local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
			local classID, subClassID
			if info then
				local ok, _, _, _, _, _, c, sc = pcall(info, item)
				if ok then classID, subClassID = c, sc end
			end
			m.skill = classID == TRADESKILL and GATHER[subClassID] or nil
			m.gatherers = m.skill and Gatherers(m.skill) or {}
		end
		out[#out + 1] = m
	end
	return out
end

local function Names(list)
	local parts = {}
	for i, c in ipairs(list) do
		if i > MAX_NAMES then
			parts[#parts + 1] = L["+%d more"]:format(#list - MAX_NAMES)
			break
		end
		parts[#parts + 1] = c.key .. (c.online and " |cff40ff40•|r" or "")
	end
	return table.concat(parts, ", ")
end

-- Who can get a missing material, as one line ("" when nobody in the guild)
local function Sources(m)
	local parts = {}
	if m.crafters and #m.crafters > 0 then parts[#parts + 1] = L["crafted by %s"]:format(Names(m.crafters)) end
	if m.gatherers and #m.gatherers > 0 then parts[#parts + 1] = L["gathered by %s"]:format(Names(m.gatherers)) end
	return table.concat(parts, "; ")
end

-- The materials on a tooltip: have/need per material, and who can get what's missing
function ns.AddMaterialLines(tooltip, recipe)
	local list = ns.Materials(recipe)
	if not list or #list == 0 then return false end
	tooltip:AddLine(" ")
	tooltip:AddLine(L["Materials (you have / needed):"], 1, 0.82, 0)
	for _, m in ipairs(list) do
		local enough = m.have >= m.need
		local r, g, b = 0.4, 1, 0.4
		if not enough then r, g, b = 1, 0.45, 0.4 end
		tooltip:AddLine(("  %d/%d  %s"):format(math.min(m.have, m.need), m.need, ItemName(m.item)), r, g, b)
		if not enough then
			local src = Sources(m)
			if src ~= "" then tooltip:AddLine("      " .. src, 0.7, 0.7, 0.7, true) end
		end
	end
	return true
end

-- What you're missing, as text for a confirmation ("" when you have everything)
function ns.MaterialsText(recipe)
	local list = ns.Materials(recipe)
	if not list then return "" end
	local lines = {}
	for _, m in ipairs(list) do
		if m.have < m.need then
			local line = ("%d x %s"):format(m.need - m.have, ItemName(m.item))
			local src = Sources(m)
			if src ~= "" then line = line .. " |cffa0a0a0(" .. src .. ")|r" end
			lines[#lines + 1] = line
		end
	end
	if #lines == 0 then return "|cff40ff40" .. L["You have all the materials."] .. "|r" end
	return "|cffff7060" .. L["You're missing:"] .. "|r\n" .. table.concat(lines, "\n")
end
