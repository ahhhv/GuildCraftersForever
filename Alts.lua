-- GuildCrafters Forever
-- Copyright (C) 2026 jamiforever
-- Licensed under the GNU General Public License v3.0 or later (see LICENSE).
--------------------------------------------------------------------------------
-- Mains and alts: which guild members are the same player.
--   * the addon's own: characters of one account share a random token (the
--     record's `ac`, unless the player turned "Share my alts" off), and the
--     main is the one picked with /gcraft main (the record's `mn`), else the
--     highest level one;
--   * everyone else: the guild note, when it says whose alt it is ("alt de
--     Jami", "Jami alt", "alt: Jami", "alt of Jami"...), matched to a member
--     by first name (only when exactly one member has it).
-- ns.Groups() -> { of = { [key] = group }, list = { group } }, group = { id, main, members = { keys } }
--------------------------------------------------------------------------------

local ADDON, ns = ...

local NOTE_PATTERNS = {
	"alt%s+de%s+([%a\128-\255]+)",
	"alt%s+of%s+([%a\128-\255]+)",
	"alt%s*:%s*([%a\128-\255]+)",
	"alt%s*%-%s*([%a\128-\255]+)",
	"^%s*([%a\128-\255]+)%s+alt%f[%A]",
	"^%s*([%a\128-\255]+)'s%s+alt",
}

local cache, cacheVersion

local function FirstName(key) return (key:match("^(%S+)") or key):lower() end

-- The member a note names, or nil (no alt note, nobody with that name, or more than one)
local function NoteMain(note, self)
	if not note or note == "" then return nil end
	local lower = note:lower()
	local name
	for _, pat in ipairs(NOTE_PATTERNS) do
		name = lower:match(pat)
		if name then break end
	end
	if not name or name == "alt" then return nil end
	local found
	for _, e in ipairs(ns.roster) do
		if e.name ~= self and (FirstName(e.name) == name or e.name:lower() == name) then
			if found then return nil end
			found = e.name
		end
	end
	return found
end

function ns.Groups()
	local v = ns.dataVersion or 0
	if cache and cacheVersion == v then return cache end
	local g = ns.Guild()
	local members = g and g.members or {}
	local groups, of = {}, {}

	local function join(id, key)
		local grp = groups[id]
		if not grp then
			grp = { id = id, members = {} }
			groups[id] = grp
		end
		if of[key] ~= grp then
			grp.members[#grp.members + 1] = key
			of[key] = grp
		end
		return grp
	end

	-- the addon's account tokens
	for _, e in ipairs(ns.roster) do
		local rec = members[e.name]
		if rec and rec.ac then join("a:" .. rec.ac, e.name) end
	end
	-- the guild notes, for whoever isn't grouped yet
	for _, e in ipairs(ns.roster) do
		if not of[e.name] then
			local main = NoteMain(e.note, e.name)
			if main then
				local grp = of[main] or join("n:" .. main, main)
				grp.noteMain = grp.noteMain or main
				join(grp.id, e.name)
			end
		end
	end

	-- each group's main
	local list = {}
	for _, grp in pairs(groups) do
		if #grp.members > 1 then
			local main
			for _, key in ipairs(grp.members) do
				local rec = members[key]
				if rec and rec.mn and of[rec.mn] == grp then main = rec.mn break end
			end
			main = main or grp.noteMain
			if not main then
				for _, key in ipairs(grp.members) do
					local e, best = ns.inRoster[key], main and ns.inRoster[main]
					if not best or (e and (e.level or 0) > (best.level or 0)) or (e and best and (e.level or 0) == (best.level or 0) and key < main) then
						main = key
					end
				end
			end
			grp.main = main
			list[#list + 1] = grp
		else
			for _, key in ipairs(grp.members) do of[key] = nil end
		end
	end
	cache, cacheVersion = { of = of, list = list }, v
	return cache
end

-- The main of `key`'s player (itself when it's the main or has no alts)
function ns.MainOf(key)
	local grp = ns.Groups().of[key]
	return grp and grp.main or key
end

-- A filtered, sorted member list with each player's characters together: the main (or the first of
-- them in the list) heads them, with `altCount`, and the alts follow only while `open[group id]`.
-- `d.name` is a member key; every d gets `head`, `alt` or neither.
function ns.GroupRows(list, open)
	local G = ns.Groups()
	local byName = {}
	for _, d in ipairs(list) do byName[d.name] = d end
	local out, done = {}, {}
	for _, d in ipairs(list) do
		if not done[d.name] then
			local grp = G.of[d.name]
			local present = {}
			if grp then
				for _, key in ipairs(grp.members) do
					if byName[key] then present[#present + 1] = byName[key] end
				end
			end
			if #present > 1 then
				local head = byName[grp.main] or present[1]
				head.head, head.altCount, head.gid, head.open = true, #present - 1, grp.id, open[grp.id] and true or false
				head.group = present
				out[#out + 1] = head
				done[head.name] = true
				for _, a in ipairs(present) do
					if a ~= head then
						done[a.name] = true
						if head.open then
							a.alt = true
							out[#out + 1] = a
						end
					end
				end
			else
				done[d.name] = true
				out[#out + 1] = d
			end
		end
	end
	return out
end
