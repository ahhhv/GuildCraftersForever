-- GuildCrafters Forever
-- Copyright (C) 2026 jamiforever
-- Licensed under the GNU General Public License v3.0 or later (see LICENSE).
--------------------------------------------------------------------------------
-- "There's a new version": every client puts its version in its record
-- (rec.ver), so the guild knows who runs what, even members who are offline.
-- When a guildmate runs a newer release (betas and alphas never count), you
-- get one notice per session, in chat and as a toast. /gcraft versions lists
-- every member's version.
--------------------------------------------------------------------------------

local ADDON, ns = ...
local L = ns.L

-- This copy's version ("0.4.0", "0.4.0-beta3"); nil when it isn't a packaged one (a development copy)
local function MyVersion()
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local v = get and get(ADDON, "Version")
	if type(v) ~= "string" then return nil end
	v = v:gsub("^v", "")
	if not v:match("^%d+%.%d+") then return nil end
	return v
end
ns.MyVersion = MyVersion

-- "1.2.3-beta4" -> { 1, 2, 3, pre = "beta", n = 4 }; nil if it isn't a version
local function Parse(v)
	if type(v) ~= "string" then return nil end
	local a, b, c, rest = v:gsub("^v", ""):match("^(%d+)%.(%d+)%.?(%d*)(.*)$")
	if not a then return nil end
	local p = { tonumber(a), tonumber(b), tonumber(c) or 0 }
	local pre, n = rest:match("^%-(%a+)(%d*)")
	if pre then p.pre, p.n = pre:lower(), tonumber(n) or 0
	elseif rest ~= "" then return nil end
	return p
end

local PRE = { alpha = 1, beta = 2, rc = 3 }

-- a < b
local function Older(a, b)
	for i = 1, 3 do
		if a[i] ~= b[i] then return a[i] < b[i] end
	end
	if not a.pre ~= not b.pre then return a.pre ~= nil end -- a pre-release comes before its release
	if not a.pre then return false end
	local ra, rb = PRE[a.pre] or 0, PRE[b.pre] or 0
	if ra ~= rb then return ra < rb end
	return a.n < b.n
end

function ns.IsNewerRelease(v, than)
	local a, b = Parse(v), Parse(than)
	return a and b and not a.pre and Older(b, a) or false
end

local told -- the version we've already announced this session

-- The newest release any guildmate runs, if it's newer than ours: tell once
function ns.CheckVersion()
	local mine = MyVersion()
	local g = ns.Guild()
	if not (mine and g) then return end
	local best
	for _, rec in pairs(g.members) do
		local v = rec.ver
		if v and ns.IsNewerRelease(v, mine) and (not best or ns.IsNewerRelease(v, best)) then best = v end
	end
	if not best or best == told then return end
	told = best
	local line = L["There's a new version of GuildCrafters Forever (%s): you have %s. Update it from CurseForge."]:format(best, mine)
	ns.Print("|cffffd100" .. line .. "|r")
	if ns.ShowToast then ns.ShowToast(L["New version"], line, 134939) end
end

-- /gcraft versions: everyone's version, newest first, then members without one
function ns.PrintVersions()
	local g = ns.Guild()
	if not g then return end
	local list, none = {}, {}
	for key, rec in pairs(g.members) do
		if #ns.roster == 0 or ns.inRoster[key] then
			if rec.ver then list[#list + 1] = { key = key, ver = rec.ver, p = Parse(rec.ver) }
			else none[#none + 1] = key end
		end
	end
	table.sort(list, function(a, b)
		if a.p and b.p and (Older(a.p, b.p) or Older(b.p, a.p)) then return Older(b.p, a.p) end
		return a.key < b.key
	end)
	table.sort(none)
	ns.Print(L["Your version: %s"]:format(MyVersion() or L["development"]))
	for _, e in ipairs(list) do
		local mark = ""
		if ns.IsNewerRelease(e.ver, MyVersion() or "0.0.0") then mark = " |cff40ff40(" .. L["newer"] .. ")|r" end
		ns.Print(("  %s: %s%s"):format(e.key, e.ver, mark))
	end
	if #none > 0 then
		ns.Print("  |cffa0a0a0" .. L["Older than 0.4.0-beta4 (no version shared): %s"]:format(table.concat(none, ", ")) .. "|r")
	end
end

-- After logging in, once the guild's records have had a moment to arrive
C_Timer.After(45, function()
	if not ns.disabled then ns.CheckVersion() end
end)
