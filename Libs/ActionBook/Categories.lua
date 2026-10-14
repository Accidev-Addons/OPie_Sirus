local _, T = ...
if T.SkipLocalActionBook then
	return
end

local AB = T.ActionBook:compatible(2, 21)
local RW = T.ActionBook:compatible("Rewire", 1, 27)
local IM = T.ActionBook:compatible("Imp", 1, 8)
local EV = T.Evie
assert(AB and RW and IM and EV and 1, "Incompatible library bundle")
local L = T.ActionBook.L
local CA = T.compat
local strcmputf8i, GetSpellBookItemName, GetSpellBookItemInfo = CA.strcmputf8i, CA.GetSpellBookItemName, CA.GetSpellBookItemInfo
local C_EquipmentSet = CA.C_EquipmentSet
local mark = {}
local spellRankFilter = {
	maxOnly = true
}
T.SpellRankFilter = spellRankFilter

local function icmp(a, b)
	return strcmputf8i(a, b) < 0
end
local function getContainerItemLootState(bag, slot)
	local name, _, _, _, readable, lootable = GetContainerItemInfo(bag, slot)
	if not name then
		return nil
	end
	return {
		isReadable = readable,
		hasLoot = lootable
	}
end
local function isItemInteresting(tf, testIdx, bag, slot, iid)
	if testIdx == 2 then
		local r = tf(bag, slot)
		return r and (r.hasLoot or r.isReadable)
	end
	return tf(iid)
end

do
	local GENERAL_TAB = 1
	local WRATH_SKIP_TABS = {
		["Спутники"] = true,
		["Транспортные средства"] = true,
		["Транспорт"] = true,
		["Питомец"] = true,
		["Питомцы"] = true,
		["Companions"] = true,
		["Mounts"] = true,
		["Pet"] = true,
		["Pets"] = true
	}
	local function isSkippedTab(index, name, icon)
		if index == GENERAL_TAB or icon == nil or WRATH_SKIP_TABS[name] then
			return true
		end
		return type(icon) == "string" and icon:lower():find("achievement_guild", 1, true) ~= nil
	end
	local isSpecHeaderName
	do
		local prefixes, seen = {}, {}
		local localized, cls = UnitClass("player")
		local function addPrefix(n)
			if type(n) == "string" and n ~= "" and not seen[n] then
				seen[n], prefixes[#prefixes + 1] = true, n .. " - "
			end
		end
		addPrefix(localized)
		addPrefix(LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls])
		addPrefix(LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[cls])
		function isSpecHeaderName(...)
			for i = 1, select("#", ...) do
				local name = select(i, ...)
				if type(name) == "string" then
					for j = 1, #prefixes do
						local p = prefixes[j]
						if name:sub(1, #p) == p then
							return true
						end
					end
				end
			end
			return false
		end
	end
	local function spellBookRank(slot)
		local bookName, rank = GetSpellBookItemName(slot, "spell")
		return bookName, type(rank) == "string" and tonumber(rank:match("(%d+)%s*$")) or nil
	end
	local function collectTopRanks()
		local top = {}
		for i = 1, GetNumSpellTabs() + 12 do
			local tabName, ico, ofs, c = GetSpellTabInfo(i)
			if not ofs or (c or 0) == 0 and i > GetNumSpellTabs() then
				break
			end
			if not isSkippedTab(i, tabName, ico) then
				for j = ofs + 1, ofs + c do
					local bookName, rank = spellBookRank(j)
					if bookName and rank and rank > (top[bookName] or 0) then
						top[bookName] = rank
					end
				end
			end
		end
		return top
	end
	local function addSpells(add)
		local asv = GetCVar("showAllSpellRanks")
		if asv and asv ~= "1" then
			SetCVar("showAllSpellRanks", "1")
		end
		local top = spellRankFilter.maxOnly and collectTopRanks()
		for i = 1, GetNumSpellTabs() + 12 do
			local tabName, ico, ofs, c = GetSpellTabInfo(i)
			if not ofs or (c or 0) == 0 and i > GetNumSpellTabs() then
				break
			end
			local isSkipped = isSkippedTab(i, tabName, ico)
			if not isSkipped then
				for j = ofs + 1, ofs + c do
					local tex = GetSpellTexture(j, "spell")
					if tex and type(tex) == "string" then
						local _, sid = GetSpellBookItemInfo(j, "spell")
						if sid and sid > 0 and not mark[sid] and not IsPassiveSpell(sid) then
							local name = GetSpellInfo(sid)
							local bookName, rank = spellBookRank(j)
							local isSpecHeader = isSpecHeaderName(name, bookName)
							local isLowRank = top and rank and bookName and top[bookName] and rank < top[bookName]
							if not isSpecHeader and not isLowRank then
								mark[sid] = 1
								local t2 = tex
								AB:SetSpellIconOverride(sid, function()
									return t2
								end)
								if name then
									AB:SetSpellIconOverride(name, function()
										return t2
									end)
								end
								add("spell", sid)
							end
						end
					end
				end
			end
		end
		if asv and asv ~= "1" then
			SetCVar("showAllSpellRanks", asv)
		end
	end
	local flyoutRing, flyoutOwner, staleRing = {}, {}, {}
	do
		local function syncFlyout(fid, aid)
			local col, ni = {}, 1
			local _, _, slots = GetFlyoutInfo(fid)
			for i = 1, slots or 0 do
				local sid, _osid, known = GetFlyoutSlotInfo(fid, i)
				if sid and known then
					local said = AB:GetActionSlot("spell", sid)
					if said then
						local tok = "OPbFO" .. fid .. "s" .. sid
						col[ni], col[tok], ni = tok, said, ni + 1
					end
				end
			end
			if aid then
				AB:UpdateActionSlot(aid, col)
				return aid
			end
			return AB:CreateActionSlot(nil, nil, "collection", col)
		end
		local function createFlyout(fid)
			fid = tonumber(fid)
			if not (fid and GetFlyoutInfo(fid)) then
				return
			end
			local aid = flyoutRing[fid]
			if not aid then
				aid = syncFlyout(fid)
				flyoutRing[fid], flyoutOwner[aid] = aid, fid
			end
			return aid
		end
		local function describeFlyout(fid)
			fid = tonumber(fid)
			local name = fid and GetFlyoutInfo(fid)
			local icon = fid and select(3, GetSpellInfo(fid)) or nil
			return L "Spell flyout", name or tostring(fid), icon, nil, nil, nil, "collection"
		end
		AB:RegisterActionType("opie.flyout", createFlyout, describeFlyout, 1)
		AB:AddObserver("internal.collection.preopen", function(_, _, aid)
			local fid = flyoutOwner[aid]
			if fid and staleRing[fid] and not InCombatLockdown() then
				staleRing[fid] = nil
				syncFlyout(fid, aid)
			end
		end)
		EV.SPELLS_CHANGED = function()
			for fid in pairs(flyoutRing) do
				staleRing[fid] = true
			end
		end
	end
	AB:AugmentCategory(L "General abilities", function(_, add)
		local _, _, ofs, count = GetSpellTabInfo(GENERAL_TAB)
		for j = (ofs or 0) + 1, (ofs or 0) + (count or 0) do
			local tex = GetSpellTexture(j, "spell")
			if type(tex) == "string" then
				local _, sid = GetSpellBookItemInfo(j, "spell")
				if sid and sid > 0 and not IsPassiveSpell(sid) and not C_SpellBook.IsSpellHiddenForUI(sid) then
					local name, t2 = GetSpellInfo(sid), tex
					AB:SetSpellIconOverride(sid, function()
						return t2
					end)
					if name then
						AB:SetSpellIconOverride(name, function()
							return t2
						end)
					end
					add(GetFlyoutInfo(sid) and "opie.flyout" or "spell", sid)
				end
			end
		end
	end)
	AB:AugmentCategory(L "Abilities", function(_, add)
		wipe(mark)
		addSpells(add)
		wipe(mark)
	end)
	local _, cl = UnitClass("player")
	if cl == "HUNTER" or cl == "WARLOCK" then
		AB:AugmentCategory(L "Pet abilities", function(_, add)
			wipe(mark)
			for i = 1, HasPetSpells() or 0 do
				local _, id = GetSpellBookItemInfo(i, "pet")
				if not id or id == 0 then
					local name, rank = GetSpellBookItemName(i, "pet")
					if name then
						local link = GetSpellLink(name, rank)
						id = tonumber(link and link:match("|Hspell:(%d+)"))
					end
				end
				if id and id > 0 and not IsPassiveSpell(id) and not mark[id] then
					mark[id] = true
					add("petspell", id)
				end
			end
			for s in ("attack stay follow assist defend passive"):gmatch("%S+") do
				add("petspell", s)
			end
			wipe(mark)
		end)
	end
end
AB:AugmentCategory(L "Items", function(_, add)
	wipe(mark)
	local ns, giid = GetContainerNumSlots, GetContainerItemID
	for t = 0, 2 do
		local tf = t == 0 and GetItemSpell or t == 1 and IsEquippableItem or getContainerItemLootState
		for bag = 0, 4 do
			for slot = 1, ns(bag) do
				local iid = giid(bag, slot)
				if iid and not mark[iid] and isItemInteresting(tf, t, bag, slot, iid) then
					add("item", iid)
					mark[iid] = 1
				end
			end
		end
		for slot = INVSLOT_FIRST_EQUIPPED, t < 2 and INVSLOT_LAST_EQUIPPED or -10 do
			local iid = GetInventoryItemID("player", slot)
			if iid and not mark[iid] and tf(iid) then
				add("item", iid)
				mark[iid] = 1
			end
		end
	end
end)
AB:AugmentCategory(L "Equipped", function(_, add)
	for w in
		("head neck shoulders back chest tabard shirt wrist hands waist legs feet finger1 finger2 trinket1 trinket2"):gmatch(
			"%S+") do
		add("peq", w)
	end
end)
local function registerCompanionIconOverrides()
	for i = 1, GetNumCompanions("MOUNT") do
		local _, _, sid, icon = GetCompanionInfo("MOUNT", i)
		if sid and sid > 0 and icon then
			local ic = icon
			AB:SetSpellIconOverride(sid, function()
				return ic
			end)
		end
	end
	for i = 1, GetNumCompanions("CRITTER") do
		local _, _, sid, icon = GetCompanionInfo("CRITTER", i)
		if sid and sid > 0 and icon then
			local ic = icon
			AB:SetSpellIconOverride(sid, function()
				return ic
			end)
		end
	end
end
do
	local f = CreateFrame("Frame")
	f:RegisterEvent("COMPANION_UPDATE")
	f:SetScript("OnEvent", registerCompanionIconOverrides)
	pcall(registerCompanionIconOverrides)
end

do
	AB:AugmentCategory(COMPANIONS, function(_, add)
		local seen = {}
		for i = 1, GetNumCompanions("CRITTER") do
			local _, _, sid, icon = GetCompanionInfo("CRITTER", i)
			if sid and sid > 0 and not seen[sid] then
				seen[sid] = true
				if icon then
					local ic = icon
					AB:SetSpellIconOverride(sid, function()
						return ic
					end)
				end
				add("spell", sid)
			end
		end
	end)
end
do
	AB:AugmentCategory(L "Mounts", function(_, add)
		local n2name, n2icon, sids = {}, {}, {}
		for i = 1, GetNumCompanions("MOUNT") do
			local _, name, sid, icon = GetCompanionInfo("MOUNT", i)
			if sid and sid > 0 and not n2name[sid] then
				n2name[sid] = name or ""
				n2icon[sid] = icon
				sids[#sids + 1] = sid
			end
		end
		table.sort(sids, function(a, b)
			return icmp(n2name[a], n2name[b])
		end)
		for i = 1, #sids do
			local sid = sids[i]
			local icon = n2icon[sid]
			if icon then
				local ic = icon
				AB:SetSpellIconOverride(sid, function()
					return ic
				end)
			end
			add("spell", sid)
		end
	end)
end
AB:AugmentCategory(L "Macros", function(_, add)
	add("imptext", "")
	local n, ni = {}, 1
	for name in RW:GetNamedMacros() do
		n[ni], ni = name, ni + 1
	end
	table.sort(n, icmp)
	for i = 1, #n do
		add("macro", n[i])
	end
end)
do
	local profCatName = TRADE_SKILLS or "Professions"
	local secCatName = ((SECONDARY_SKILLS or ""):gsub("%s*:%s*$", ""))
	local PROF_SECONDARY = {
		["Горное дело"] = {"Выплавка металлов"},
		["Ювелирное дело"] = {"Просеивание"},
		["Начертание"] = {"Просеивание"},
		["Наложение чар"] = {"Распыление"},
		["Кулинария"] = {"Костер", "Разведение костра"}
	}
	AB:AugmentCategory(profCatName, function(_, add)
		local profSkills, inProfsHeader = {}, false
		for i = 1, GetNumSkillLines() do
			local name, isHeader = GetSkillLineInfo(i)
			if name then
				if isHeader then
					inProfsHeader = (name == profCatName) or (secCatName ~= "" and name == secCatName)
				elseif inProfsHeader then
					profSkills[name] = true
				end
			end
		end

		local secondaryNames = {}
		for profName, list in pairs(PROF_SECONDARY) do
			if profSkills[profName] then
				for _, sn in ipairs(list) do
					secondaryNames[sn] = true
				end
			end
		end

		local profSpells, profIcons = {}, {}
		local secSpells, secIcons = {}, {}
		for i = 1, GetNumSpellTabs() do
			local _, _, ofs, count = GetSpellTabInfo(i)
			if not ofs then
				break
			end
			for j = ofs + 1, ofs + count do
				local link, tradeLink = GetSpellLink(j, "spell")
				local isTradeLink = (link and link:find("|Htrade:")) or (tradeLink and tradeLink:find("|Htrade:"))
				local sid =
					(link and (tonumber(link:match("|Hspell:(%d+)")) or tonumber(link:match("|Htrade:(%d+)")))) or
						(tradeLink and tonumber(tradeLink:match("|Htrade:(%d+)")))
				if sid and sid > 0 then
					local spellName = GetSpellInfo(sid)
					local tex = spellName and GetSpellTexture(j, "spell")
					local texStr = type(tex) == "string" and tex or nil
					if isTradeLink and spellName and not profSpells[spellName] then
						profSpells[spellName] = sid
						profIcons[spellName] = texStr
					elseif spellName and profSkills[spellName] and not profSpells[spellName] then
						profSpells[spellName] = sid
						profIcons[spellName] = texStr
					elseif spellName and secondaryNames[spellName] then
						secSpells[spellName] = sid
						secIcons[spellName] = texStr or secIcons[spellName]
					end
				end
			end
		end

		for name, sid in pairs(profSpells) do
			local ic = profIcons[name]
			if ic then
				AB:SetSpellIconOverride(sid, function()
					return ic
				end)
			end
			add("spell", sid)
		end
		for profName, list in pairs(PROF_SECONDARY) do
			if profSkills[profName] and profSpells[profName] then
				for _, secName in ipairs(list) do
					local sid = secSpells[secName]
					if sid then
						local ic = secIcons[secName]
						if ic then
							AB:SetSpellIconOverride(sid, function()
								return ic
							end)
						end
						add("spell", sid)
					end
				end
			end
		end
	end)
end
do
	AB:AugmentCategory(L "Equipment sets", function(_, add)
		for _, id in pairs(C_EquipmentSet.GetEquipmentSetIDs()) do
			add("equipmentset", (C_EquipmentSet.GetEquipmentSetInfo(id)))
		end
	end)
end
AB:AugmentCategory(L "Raid markers", function(_, add)
	for i = 0, 8 do
		add("raidmark", i)
	end
end)
if WORLD_RAID_MARKER_ORDER then
	AB:AugmentCategory(L "Raid world markers", function(_, add)
		for i = 0, #WORLD_RAID_MARKER_ORDER do
			add("worldmark", i)
		end
	end)
end
AB:AugmentCategory(L "Toys", function(_, add)
	if not (C_ToyBox and C_ToyBox.GetNumFilteredToys and C_ToyBox.GetToyFromIndex) then
		return
	end
	wipe(mark)
	for i = 1, C_ToyBox.GetNumFilteredToys() do
		local itemID, spellID = C_ToyBox.GetToyFromIndex(i)
		if spellID and spellID > 0 and not mark[spellID] and PlayerHasToy(itemID) then
			mark[spellID] = 1
			add("spell", spellID)
		end
	end
	wipe(mark)
end)
do
	AB:AddActionToCategory(L "Miscellaneous", "imptext", "")
end
do
	AB:AddCategoryAlias("Miscellaneous", L "Miscellaneous")
end
do
	local function registerSpellIcons()
		for i = 1, GetNumSpellTabs() do
			local _, _, ofs, c = GetSpellTabInfo(i)
			if not ofs then
				break
			end
			for j = ofs + 1, ofs + c do
				local tex = GetSpellTexture(j, "spell")
				if tex and type(tex) == "string" then
					local _, sid = GetSpellBookItemInfo(j, "spell")
					if sid and sid > 0 then
						local t2, name = tex, GetSpellInfo(sid)
						AB:SetSpellIconOverride(sid, function()
							return t2
						end)
						if name then
							AB:SetSpellIconOverride(name, function()
								return t2
							end)
						end
						RW:SetSpellCastableChecker(sid, function()
							return true
						end)
					end
				end
			end
		end
		for i = 1, HasPetSpells() or 0 do
			local tex = GetSpellTexture(i, "pet")
			if tex and type(tex) == "string" then
				local _, sid = GetSpellBookItemInfo(i, "pet")
				if sid and sid > 0 then
					local t2, name = tex, GetSpellInfo(sid)
					AB:SetSpellIconOverride(sid, function()
						return t2
					end)
					if name then
						AB:SetSpellIconOverride(name, function()
							return t2
						end)
					end
				end
			end
		end
	end
	do
		local f = CreateFrame("Frame")
		f:RegisterEvent("PLAYER_LOGIN")
		f:RegisterEvent("SPELLS_CHANGED")
		f:SetScript("OnEvent", registerSpellIcons)
	end
end
do
	local panels = {"character", "reputation", "currency", "spellbook", "talents", "achievements", "quests",
					"groupfinder", "collections", "adventureguide", "store", "guild", "map", "social", "calendar",
					"macro", "options", "gamemenu"}
	AB:AugmentCategory(L "UI panels", function(_, add)
		for i = 1, #panels do
			i = panels[i]
			if select(2, AB:GetActionListDescription("uipanel", i)) then
				add("uipanel", i)
			end
		end
	end)
end
