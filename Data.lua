-- GuildCrafters Forever
-- Copyright (C) 2026 jamiforever
-- Licensed under the GNU General Public License v3.0 or later (see LICENSE).
--------------------------------------------------------------------------------
-- GuildCrafters Forever: what we know. Your own record (professions, recipes,
-- talents) read from the game, the guild's records received from the other
-- members (kept between sessions, so offline members still show), and the
-- guild roster.
--
-- A record (what travels; short keys keep messages small):
--   { v = protocol, t = stamp (server time of the last change), c = class file,
--     l = level, p = { [skillLineID] = { n = name, i = icon, r = rank, m = max,
--     s = profession specialization name or nil, rc = { recipeIDs } } },
--     tl = { sp = specID, a = active group, g = { [group] = { str = export
--     string, tr = { { n = branch name, i = icon, s = points } } } } } }
--------------------------------------------------------------------------------

local ADDON, ns = ...
local L = ns.L

ns.PROTOCOL = 1

-- Vanilla's profession specializations, by profession: spells the player knows once picked
local PROF_SPECS = {
	[164] = { 9787, 9788, 17039, 17040, 17041 },   -- Blacksmithing: Weaponsmith, Armorsmith, Master Sword/Hammer/Axesmith
	[202] = { 20219, 20222 },                      -- Engineering: Gnomish, Goblin
	[165] = { 10656, 10658, 10660 },               -- Leatherworking: Dragonscale, Elemental, Tribal
}

-- Known professions in display order, with a fallback icon
-- Gathering professions: nothing to craft (Mining has its smelting, so it isn't one)
ns.GATHERING = { [182] = true, [393] = true, [356] = true }

ns.PROF_ORDER = { 171, 164, 333, 202, 182, 165, 186, 393, 197, 185, 129, 356 }
ns.PROF_ICONS = {
	[171] = "Interface\\Icons\\Trade_Alchemy", [164] = "Interface\\Icons\\Trade_BlackSmithing",
	[333] = "Interface\\Icons\\Trade_Engraving", [202] = "Interface\\Icons\\Trade_Engineering",
	[182] = "Interface\\Icons\\Trade_Herbalism", [165] = "Interface\\Icons\\Trade_LeatherWorking",
	[186] = "Interface\\Icons\\Trade_Mining", [393] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
	[197] = "Interface\\Icons\\Trade_Tailoring", [185] = "Interface\\Icons\\INV_Misc_Food_15",
	[129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", [356] = "Interface\\Icons\\Trade_Fishing",
}

-- Options (Options.lua shows them in Blizzard's settings)
ns.DEFAULTS = {
	tooltip = true,        -- "who crafts it" lines on item tooltips
	shortcut = "ALT-LeftButton", -- the click on an item that requests it: "ALT-CTRL-SHIFT-<mouse button>" (recorded), or "none"
	shareAlts = true,      -- tell the guild which characters are this player's
	sound = true,          -- sound with the notices
	acceptRequests = true, -- guildmates can send me requests (and board posts I can craft notify me)
}
function ns.Opt(key)
	local db = GuildCraftersForeverDB
	local v = db and db.opts and db.opts[key]
	if v == nil then return ns.DEFAULTS[key] end
	return v
end

ns.roster = {}        -- { { name, short, level, class, online, rank, guid } } in roster order
ns.inRoster = {}      -- key -> roster entry
ns.byGuid = {}        -- GUID -> roster entry

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffe6b85cGuildCrafters Forever|r " .. msg) end
ns.Print = Print

local function Secret(v) return issecretvalue and issecretvalue(v) end
ns.Secret = Secret

--------------------------------------------------------------------------------
-- Names and storage
--------------------------------------------------------------------------------

local realm
function ns.Realm()
	realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName() or ""):gsub("[%s%-]", "")
	return realm
end

-- One key per character, whatever API the name came from. A Forever character
-- is "Firstname Surname" with no realms; the same one also comes in the link
-- form "Firstname-Surname", or with a realm or number after a dash. All of
-- them become "Firstname Surname" (a name without a surname stays as it is).
function ns.Key(name)
	if type(name) ~= "string" or Secret(name) then return nil end
	name = name:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	if name == "" then return nil end
	local base, suffix = name:match("^(.-)%-([^%-]*)$")
	if base and base ~= "" then
		local r = ns.Realm()
		if base:find(" ", 1, true) or suffix == "" or suffix:match("^%d+$") or suffix == r
			or suffix:gsub("%s", "") == r or suffix:find("Realm", 1, true) then
			name = base                               -- "Firstname Surname-Realm", "Firstname-Realm"
		else
			name = base .. " " .. suffix              -- the link form "Firstname-Surname"
		end
	end
	return name
end
ns.FullName = ns.Key

function ns.Short(name)
	return name
end

-- You: your guild roster row (found by GUID) once the roster is in, else your own name
function ns.Me()
	local guid = UnitGUID and UnitGUID("player")
	local e = guid and ns.byGuid and ns.byGuid[guid]
	return (e and e.name) or ns.Key(UnitName("player"))
end

-- This guild's table in the saved variables, or nil outside a guild
function ns.Guild()
	local gname = IsInGuild() and GetGuildInfo("player")
	if not gname then return nil end
	local key = gname .. "-" .. ns.Realm()
	local db = GuildCraftersForeverDB
	db.guilds[key] = db.guilds[key] or { members = {} }
	return db.guilds[key]
end

function ns.Record(name)
	local g = ns.Guild()
	return g and g.members[name]
end

--------------------------------------------------------------------------------
-- Reading your own character
--------------------------------------------------------------------------------

local function ProfSpec(skillLine)
	for _, spell in ipairs(PROF_SPECS[skillLine] or {}) do
		if IsPlayerSpell and IsPlayerSpell(spell) then
			return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell)) or (GetSpellInfo and GetSpellInfo(spell))
		end
	end
end

function ns.ScanProfessions(rec)
	local old = rec.p or {}
	local profs = {}
	if GetProfessions and GetProfessionInfo then
		local list = { n = select("#", GetProfessions()), GetProfessions() }
		for k = 1, list.n do
			local index = list[k]
			if index then
				local name, icon, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
				if skillLine and skillLine > 0 then
					local had = old[skillLine]
					if not had then
						for _, o in pairs(old) do
							if o.n and name and o.n == name then had = o break end
						end
					end
					profs[skillLine] = { n = name, i = icon, r = rank, m = maxRank, s = ProfSpec(skillLine),
						rc = had and had.rc or nil }
				end
			end
		end
	end
	rec.p = profs
end

-- The open profession window's learned recipes (only your own, local window).
-- Forever's window names its profession with other IDs than the spellbook's
-- (GetProfessionInfo's 165 is the window's 8167, say), so it's matched to one
-- of your professions by ID, then by name, then by its skill and cap.
local function Why(msg)
	if ns.Log then ns.Log("recetas: " .. msg) end
	return false
end

function ns.ScanRecipes(rec)
	local T = C_TradeSkillUI
	if not (T and T.GetRecipeInfo and T.GetBaseProfessionInfo) then return Why("sin API de profesiones") end
	if Professions and Professions.InLocalCraftingMode and not Professions.InLocalCraftingMode() then return Why("ventana ajena") end
	if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
		or (T.IsNPCCrafting and T.IsNPCCrafting()) then return Why("ventana ajena") end
	local info = T.GetBaseProfessionInfo()
	if not (info and info.professionName and info.professionName ~= "") then return Why("ninguna profesión abierta") end
	rec.p = rec.p or {}
	local p = info.professionID and rec.p[info.professionID]
	if not p then
		local want = info.professionName:lower()
		for _, o in pairs(rec.p) do
			if o.n and o.n:lower() == want then p = o break end
		end
	end
	if not p then
		local found, count = nil, 0
		for _, o in pairs(rec.p) do
			if o.r == info.skillLevel and o.m == info.maxSkillLevel then found, count = o, count + 1 end
		end
		if count == 1 then p = found end
	end
	if not p then return Why(("no sé qué profesión es %s (%s)"):format(info.professionName, tostring(info.professionID))) end
	local ids = (T.GetAllRecipeIDs and T.GetAllRecipeIDs()) or (T.GetFilteredRecipeIDs and T.GetFilteredRecipeIDs()) or {}
	if #ids == 0 then return Why(p.n .. ": la lista aún está vacía") end
	-- recipes are only ever learned: a filtered list can't drop one we saw before
	local set, learned = {}, 0
	for _, id in ipairs(p.rc or {}) do set[id] = true end
	for _, id in ipairs(ids) do
		local r = T.GetRecipeInfo(id)
		if r and r.learned and not r.isDummyRecipe and not r.isGatheringRecipe then
			set[id] = true
			learned = learned + 1
		end
	end
	local list = {}
	for id in pairs(set) do list[#list + 1] = id end
	table.sort(list)
	Why(("%s: %d aprendidas de %d"):format(p.n, learned, #ids))
	if #list == 0 then return false end
	p.rc = list
	return true
end

-- The bundled recipe list (RecipeList.lua), parsed on first use: skill -> { ids }, and recipe -> item it makes
local parsed, recipeItem = nil, {}
local function Parsed()
	if parsed then return parsed end
	parsed = {}
	for skill, text in pairs(ns.RECIPES or {}) do
		local ids = {}
		for id, item in text:gmatch("(%d+):(%d+)") do
			id, item = tonumber(id), tonumber(item)
			ids[#ids + 1] = id
			if item > 0 then recipeItem[id] = item end
		end
		parsed[skill] = ids
	end
	return parsed
end

function ns.RecipeItem(id)
	Parsed()
	return recipeItem[id]
end

-- The recipes that make `itemID` (usually one)
local itemRecipes
function ns.RecipesForItem(itemID)
	if not itemRecipes then
		Parsed()
		itemRecipes = {}
		for id, item in pairs(recipeItem) do
			itemRecipes[item] = itemRecipes[item] or {}
			table.insert(itemRecipes[item], id)
		end
	end
	return itemRecipes[itemID]
end

-- The recipe a pattern teaches, by its name: "Pattern: Woolen Bag" teaches "Woolen Bag" (in any language,
-- the item is the recipe's name after a prefix and a colon). Built once, on the first recipe item hovered.
local byName
function ns.RecipeForPatternName(itemName)
	if type(itemName) ~= "string" then return nil end
	local rest = itemName:match("^[^:]+:%s*(.+)$")
	if not rest then return nil end
	if not byName then
		byName = {}
		for _, ids in pairs(Parsed()) do
			for _, id in ipairs(ids) do
				local n = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id))
				if n then byName[n:lower()] = byName[n:lower()] or id end
			end
		end
	end
	return byName[rest:lower()]
end

-- Whether a member takes requests (members without the addon, or before 0.4.0-beta2, do)
function ns.TakesRequests(key)
	if key == ns.Me() then return ns.Opt("acceptRequests") and true or false end
	local rec = ns.Record(key)
	return not (rec and rec.nr)
end

-- Who knows each recipe: recipe -> { member keys }, rebuilt when any record changes
local craftIndex, craftVersion
function ns.CraftIndex()
	local v = ns.dataVersion or 0
	if craftIndex and craftVersion == v then return craftIndex end
	craftIndex, craftVersion = {}, v
	local g = ns.Guild()
	for key, rec in pairs(g and g.members or {}) do
		if #ns.roster == 0 or ns.inRoster[key] then
			for _, p in pairs(rec.p or {}) do
				for _, id in ipairs(p.rc or {}) do
					local list = craftIndex[id]
					if not list then list = {} craftIndex[id] = list end
					list[#list + 1] = key
				end
			end
		end
	end
	return craftIndex
end

local function Known(id)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
		if ok then return known end
	end
	return IsPlayerSpell and IsPlayerSpell(id) or false
end

-- Which bundled recipes you know, for every profession you have: no window needed
function ns.ScanKnownRecipes(rec)
	local lists = Parsed()
	for skill, p in pairs(rec.p or {}) do
		local ids = lists[skill]
		if ids and not ns.GATHERING[skill] then
			local set, before = {}, #(p.rc or {})
			for _, id in ipairs(p.rc or {}) do set[id] = true end
			for _, id in ipairs(ids) do
				if not set[id] and Known(id) then set[id] = true end
			end
			local list = {}
			for id in pairs(set) do list[#list + 1] = id end
			table.sort(list)
			if #list > 0 then p.rc = list end
			if #list ~= before and ns.Log then ns.Log(("recetas: %s: %d conocidas (sin abrir la ventana)"):format(p.n or skill, #list)) end
		end
	end
end

local function Spent(currencies, groupID)
	for _, c in ipairs(currencies or {}) do
		if c.traitNodeGroupID == groupID then
			local info = c.currencyInfos and c.currencyInfos[1]
			return info and info.spent or 0
		end
	end
	return 0
end

function ns.ScanTalents(rec)
	local S, T = C_SpecializationInfo, C_Traits
	if not (S and T and S.GetCombatConfigIDForSpecGroup and T.GetConfigInfo) then return end
	local tl = { a = S.GetActiveSpecGroup and S.GetActiveSpecGroup() or 1, g = {} }
	tl.sp = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID() or nil
	local groups = GetNumSpecGroups and GetNumSpecGroups() or 1
	for g = 1, math.max(1, groups) do
		local configID = S.GetCombatConfigIDForSpecGroup(g)
		if configID then
			local entry = { tr = {} }
			local ok, str = pcall(T.GenerateImportString, configID)
			if ok and type(str) == "string" and str ~= "" then entry.str = str end
			local cfg = T.GetConfigInfo(configID)
			local treeID = cfg and cfg.treeIDs and cfg.treeIDs[1]
			if not treeID and tl.sp and C_ClassTalents and C_ClassTalents.GetTraitTreeForSpec then
				treeID = C_ClassTalents.GetTraitTreeForSpec(tl.sp)
			end
			if treeID and T.GetGroupDisplayInfoByTreeID and T.GetGroupCurrencyInfo then
				local shown = T.GetGroupDisplayInfoByTreeID(treeID) or {}
				table.sort(shown, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
				local ids = {}
				for _, d in ipairs(shown) do ids[#ids + 1] = d.groupID end
				local currencies = T.GetGroupCurrencyInfo(configID, ids)
				for _, d in ipairs(shown) do
					entry.tr[#entry.tr + 1] = { n = d.displayName, i = d.icon, s = Spent(currencies, d.groupID) }
				end
			end
			tl.g[g] = entry
		end
	end
	rec.tl = tl
end

--------------------------------------------------------------------------------
-- Your record: rescans on change, and says when it changed
--------------------------------------------------------------------------------

local function Encode(t)
	if C_EncodingUtil and C_EncodingUtil.SerializeCBOR then
		local ok, s = pcall(C_EncodingUtil.SerializeCBOR, t)
		if ok then return s end
	end
end
ns.Encode = Encode

-- What the record says without its stamp, keys sorted (pairs' order isn't stable), to tell a change from a rescan
local function Canon(v, out)
	local kind = type(v)
	if kind ~= "table" then
		out[#out + 1] = kind:sub(1, 1) .. tostring(v)
		return
	end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	out[#out + 1] = "{"
	for _, k in ipairs(keys) do
		out[#out + 1] = tostring(k) .. "="
		Canon(v[k], out)
	end
	out[#out + 1] = "}"
end

local function Fingerprint(rec)
	local out = {}
	local copy = {}
	for k, v in pairs(rec) do if k ~= "t" then copy[k] = v end end
	Canon(copy, out)
	return table.concat(out, ",")
end

function ns.MyRecord()
	local db = GuildCraftersForeverDB
	local key = (UnitGUID and UnitGUID("player")) or ns.Me()
	db.me[key] = db.me[key] or { v = ns.PROTOCOL, t = 0 }
	return db.me[key]
end

-- Rescan what `what` says ("prof", "recipes", "talents", "all"), after `change(rec)` if given; a change bumps
-- the stamp and tells the guild
function ns.Rescan(what, change)
	local rec = ns.MyRecord()
	local before = Fingerprint(rec)
	if change then change(rec) end
	local _, class = UnitClass("player")
	rec.v, rec.c, rec.l, rec.g = ns.PROTOCOL, class, UnitLevel("player"), UnitGUID and UnitGUID("player") or nil
	-- alts: the account's token and the main picked with /gcraft main, unless the player keeps them private
	local db = GuildCraftersForeverDB
	if ns.Opt("shareAlts") then
		rec.ac, rec.mn = db.account, db.main
	else
		rec.ac, rec.mn = nil, nil
	end
	rec.nr = (not ns.Opt("acceptRequests")) or nil
	rec.ver = ns.MyVersion and ns.MyVersion() or nil
	if what == "all" or what == "prof" then
		ns.ScanProfessions(rec)
		ns.ScanKnownRecipes(rec)
	end
	if what == "recipes" then
		ns.ScanProfessions(rec)
		ns.ScanRecipes(rec)
	end
	if what == "all" or what == "talents" then ns.ScanTalents(rec) end
	local changed = Fingerprint(rec) ~= before
	if changed or rec.t == 0 then rec.t = GetServerTime() end
	local g = ns.Guild()
	if g then g.members[ns.Me()] = rec end
	if changed then
		ns.dataVersion = (ns.dataVersion or 0) + 1
		if ns.Announce then ns.Announce() end
		if ns.RefreshUI then ns.RefreshUI() end
	end
end

--------------------------------------------------------------------------------
-- The roster
--------------------------------------------------------------------------------

function ns.ReadRoster()
	local roster, index, byGuid = {}, {}, {}
	local n = GetNumGuildMembers and GetNumGuildMembers() or 0
	for i = 1, n do
		local name, rank, _, level, _, _, note, _, online, _, class, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		local key = ns.Key(name)
		if key then
			if Secret(guid) or type(guid) ~= "string" then guid = nil end
			if Secret(note) or type(note) ~= "string" then note = nil end
			local e = { name = key, short = key, raw = name, level = level, class = class, online = online and true or false, rank = rank, guid = guid, note = note }
			roster[#roster + 1] = e
			index[key] = e
			if guid then byGuid[guid] = e end
		end
	end
	ns.roster, ns.inRoster, ns.byGuid = roster, index, byGuid
	ns.dataVersion = (ns.dataVersion or 0) + 1
	-- records filed under a name the roster spells otherwise: moved to its row (by GUID)
	local g = ns.Guild()
	if g and #roster > 0 then
		for key, rec in pairs(g.members) do
			local e = rec.g and byGuid[rec.g]
			if e and e.name ~= key then
				local there = g.members[e.name]
				if not there or (there.t or 0) <= (rec.t or 0) then g.members[e.name] = rec end
				g.members[key] = nil
			end
		end
		g.members[ns.Me()] = ns.MyRecord()
	end
	if ns.RefreshUI then ns.RefreshUI() end
end

-- Members who left: their records go (/gcraft limpiar)
function ns.Prune()
	local g = ns.Guild()
	if not g or #ns.roster == 0 then return 0 end
	local gone = 0
	for name in pairs(g.members) do
		if not ns.inRoster[name] then
			g.members[name] = nil
			gone = gone + 1
		end
	end
	return gone
end

--------------------------------------------------------------------------------
-- Recipe names, icons and reagents (looked up here, never sent)
--------------------------------------------------------------------------------

local names, lowers = {}, {}

function ns.RecipeName(id)
	local n = names[id]
	if n then return n end
	n = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id))
	if n then names[id] = n end
	return n or ("#" .. id)
end

function ns.RecipeIcon(id)
	return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or 134400
end

-- The recipe's output item and reagents: { item = itemID or nil, reagents = { { item, qty } } }
local schematics = {}
function ns.Schematic(id)
	local s = schematics[id]
	if s ~= nil then return s or nil end
	s = false
	local T = C_TradeSkillUI
	if T and T.GetRecipeSchematic then
		local ok, sch = pcall(T.GetRecipeSchematic, id, false)
		if ok and sch then
			s = { item = sch.outputItemID, reagents = {} }
			for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
				local r = slot.reagents and slot.reagents[1]
				if r and r.itemID and (slot.required ~= false) then
					s.reagents[#s.reagents + 1] = { r.itemID, slot.quantityRequired or 1 }
				end
			end
		end
	end
	schematics[id] = s
	return s or nil
end

-- Lowercase text a search runs against: the recipe and what it makes
function ns.RecipeSearchText(id)
	local t = lowers[id]
	if t then return t end
	t = (ns.RecipeName(id) or ""):lower()
	local s = ns.Schematic(id)
	local itemID = ns.RecipeItem(id) or (s and s.item)
	if itemID and C_Item and C_Item.GetItemNameByID then
		local item = C_Item.GetItemNameByID(itemID)
		if item then
			t = t .. "\n" .. item:lower()
		else
			if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
			return t -- (not cached yet: asked again later)
		end
	end
	lowers[id] = t
	return t
end

function ns.Ago(stamp)
	if not stamp or stamp == 0 then return "?" end
	local s = GetServerTime() - stamp
	if s < 120 then return L["just now"] end
	if s < 3600 then return L["%d min ago"]:format(math.floor(s / 60)) end
	if s < 86400 then return L["%d h ago"]:format(math.floor(s / 3600)) end
	return L["%d days ago"]:format(math.floor(s / 86400))
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local pending = {}
local function Soon(what, delay)
	if pending[what] then return end
	pending[what] = true
	C_Timer.After(delay or 1, function()
		pending[what] = nil
		ns.Rescan(what)
	end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, ...)
	if ns.disabled then
		if event == "PLAYER_LOGIN" then
			C_Timer.After(6, function()
				ns.Print(L["The old \"GuildCrafters\" folder is still installed: delete Interface\\AddOns\\GuildCrafters and restart the game. GuildCrafters Forever stays off until then."])
			end)
		end
		return
	end
	if event == "PLAYER_LOGIN" then
		GuildCraftersForeverDB = GuildCraftersForeverDB or {}
		GuildCraftersForeverDB.guilds = GuildCraftersForeverDB.guilds or {}
		GuildCraftersForeverDB.me = GuildCraftersForeverDB.me or {}
		-- one random token per account: characters sharing it are the same player (alts)
		if not GuildCraftersForeverDB.account then
			GuildCraftersForeverDB.account = ("%04x%04x%04x%04x"):format(math.random(0, 65535), math.random(0, 65535),
				math.random(0, 65535), math.random(0, 65535))
		end
		GuildCraftersForeverDB.opts = GuildCraftersForeverDB.opts or {}
		for k, v in pairs(ns.DEFAULTS) do
			if GuildCraftersForeverDB.opts[k] == nil then GuildCraftersForeverDB.opts[k] = v end
		end
		if ns.SetUpOptions then ns.SetUpOptions() end
		for _, e in ipairs({ "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED",
			"TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_LEVEL_UP",
			"GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" }) do
			pcall(f.RegisterEvent, f, e)
		end
		if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
		C_Timer.After(5, function() ns.Rescan("all") if ns.Hello then ns.Hello(true) end end)
		C_Timer.NewTicker(60, function() if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end end)
	elseif event == "SKILL_LINES_CHANGED" or event == "PLAYER_LEVEL_UP" then
		Soon("prof", 2)
	elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "NEW_RECIPE_LEARNED" then
		Soon("recipes", 1.5)
	elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
		ns.ReadRoster()
	else
		Soon("talents", 2)
	end
end)
