local _, T = ...
if T.SkipLocalActionBook then
	return
end

local EV = T.Evie
local AB = T.ActionBook:compatible(2, 43)
local RW = T.ActionBook:compatible("Rewire", 1, 27)
local KR = T.ActionBook:compatible("Kindred", 1, 14)
local IM = T.ActionBook:compatible("Imp", 1, 0)
assert(EV and AB and RW and KR and IM and 1, "Incompatible library bundle")
local L = T.ActionBook.L
local CA = T.compat
local GetSpellBookItemInfo, FindSpellBookSlotBySpellID, DoesSpellExist = CA.GetSpellBookItemInfo, CA.FindSpellBookSlotBySpellID, CA.DoesSpellExist
local C_PetJournal, C_EquipmentSet, C_ToyBox = CA.C_PetJournal, CA.C_EquipmentSet, CA.C_ToyBox
local spellFeedback, itemHint, toyHint
local GetSpellSubtext = GetSpellSubtext or function(id)
	return select(2, GetSpellInfo(id))
end
local NormalizeInRange = {
	[0] = 0,
	1,
	[true] = 1,
	[false] = 0
}
local _, CLASS = UnitClass("player")
local lowered = setmetatable({}, {
	__index = function(t, k)
		if k ~= nil then
			local r = type(k) == "string" and k:lower() or k
			t[k] = r
			return r
		end
	end
})
local callMethod = setmetatable({}, {
	__index = function(t, k)
		t[k] = function(self, ...)
			local m = self[k]
			if type(m) == "function" then
				return m(self, ...)
			end
		end
		return t[k]
	end
})
local function newWidgetName(prefix)
	local bni, bn = 0
	repeat
		bn, bni = prefix .. bni, bni + 1
	until GetClickFrame(bn) == nil
	return bn
end
local function requestItemData(iid)
	local rq = C_Item and C_Item.RequestLoadItemDataByID
	local cached = C_Item and C_Item.IsItemDataCachedByID
	if rq and type(iid) == "number" and not (cached and cached(iid)) then
		securecall(rq, iid)
	end
end
local getCachedItemName, peekCachedItemName
do
	local itemNames = {}
	function EV:ITEM_DATA_LOAD_RESULT(iid, ok)
		if itemNames[iid] == false and ok then
			itemNames[iid] = GetItemInfo(iid) or false
		end
	end
	function getCachedItemName(ident)
		local iid = tonumber(ident) or tonumber(type(ident) == "string" and ident:match("item:(%d+)"))
		if iid then
			local c, f = itemNames[iid], GetItemInfo(iid)
			itemNames[iid] = f or c or false
			if not f then
				requestItemData(iid)
			end
			return f or c or nil
		end
	end
	function peekCachedItemName(ident)
		return itemNames[tonumber(ident) or tonumber(type(ident) == "string" and ident:match("item:(%d+)"))]
	end
end
local function toCooldown(now, start, duration, enabled)
	if start and start > now then
		start = start - 2 ^ 32 / 1000
	end
	duration, enabled = duration or 0, enabled and enabled ~= 0 and 1 or 0
	return duration > 0 and enabled ~= 0 and start + duration - now or 0, duration, enabled
end

local function actionHint(slot)
	local at, aid = GetActionInfo(slot)
	if at == nil then
		return false, 0, "Interface/Icons/inv_misc_questionmark", "", 0, 0, 0
	end
	local now, state = GetTime(), 0
	local inRange, usable, nomana, hasRange = NormalizeInRange[IsActionInRange(slot)], IsUsableAction(slot)
	inRange, hasRange = inRange ~= 0, inRange ~= nil
	local cdUsable, overCount
	local cdLeft, cdLength, cdEnabled = GetActionCooldown(slot)
	local count = GetActionCount(slot)
	cdLeft, cdLength, cdEnabled = toCooldown(now, cdLeft, cdLength, cdEnabled)
	cdUsable = cdLeft == 0 or cdEnabled == 0
	state =
		state + ((IsCurrentAction(slot) or cdEnabled == 0) and 1 or 0) + (nomana and 8 or 0) + (inRange and 0 or 16) +
			(hasRange and 512 or 0) + (usable and 0 or 1024) + (cdEnabled == 0 and 2048 or 0)
	usable = not not (usable and inRange and cdUsable)
	overCount = overCount or count
	return usable, state, GetActionTexture(slot), GetActionText(slot) or (at == "spell" and GetSpellInfo(aid)),
		overCount, cdLeft, cdLength, callMethod.SetAction, slot
end

securecall(function() -- spell: spell ID + mount spell ID
	local actionMap, spellMap = {}, {}
	local function isCurrentForm(q, qsid)
		local id = GetShapeshiftForm()
		if id == 0 then
			return
		end
		local _, name = GetShapeshiftFormInfo(id)
		if not name then
			return
		end
		return q == name or (qsid and GetSpellInfo(qsid) == name) or false
	end
	local SetSpellBookItem, SetSpellByID, SetSpellByExactID
	do
		local tr1 = {}
		local function SetRankText(self, sid, ...)
			if sid then
				local tr = tr1[self]
				if tr == nil and self then
					local n = self:GetName()
					tr = n and _G[n .. "TextRight1"]
					tr =
						type(tr) == "table" and type(tr.IsObjectType) == "function" and tr:IsObjectType("FontString") and
							tr
					tr1[self] = tr or false
				end
				local sr = tr and not tr:IsShown() and select(2, GetSpellInfo(sid)) or ""
				if sr ~= "" then
					tr:SetText(sr)
					tr:SetTextColor(0.5, 0.5, 0.5)
					tr:Show()
					self:Show()
				end
			end
			return ...
		end
		function SetSpellBookItem(self, id)
			local st, sid = GetSpellBookItemInfo(id, "spell")
			return SetRankText(self, st == "SPELL" and sid, self:SetSpellBookItem(id, "spell"))
		end
		function SetSpellByID(self, ...)
			return SetRankText(self, (...), self:SetSpellByID(...))
		end
		function SetSpellByExactID(self, sid)
			return SetRankText(self, sid, self:SetSpellByID(sid, nil, nil, true))
		end
	end
	local getSpellIDFromName = function(n)
		return tonumber(((GetSpellLink(n) or ""):match("spell:(%d+)")))
	end
	local iconOverrideHandlers = {} -- keyed by numeric msid OR lowercased spell name (string)
	local sbslotCache = {} -- FindSpellBookSlotBySpellID result per spellID; wiped on SPELLS_CHANGED
	local function spellHint(n, _modState, target)
		if not n then
			return
		end
		local sname, _, gicon = GetSpellInfo(n) -- gicon=pos3: icon fallback (Sirus custom spells)
		local sid = type(n) == "number" and n or nil
		-- Sirus engine supports SetTexture(fileID) — keep numeric fileIDs as icon fallback.
		-- Only discard 0 and sub-1 floats (those would be misinterpreted as colour values).
		if type(gicon) == "number" and gicon < 2 then
			gicon = nil
		end
		if not sname then
			return
		end
		local origN = n -- capture numeric ID before transform (for slot-based texture fallback)
		if type(n) == "number" then
			n = sname
		end
		local state, now, msid = 0, GetTime(), sid or spellMap[lowered[n]]
		local inRange, usable, nomana, hasRange = NormalizeInRange[IsSpellInRange(type(n) == "string" and n or sname,
			target or "target")], IsUsableSpell(n)
		inRange, hasRange = inRange ~= 0, inRange ~= nil
		local cdUsable, overCount
		local cdLeft, cdLength, cdEnabled = GetSpellCooldown(n)
		local count = GetSpellCount(n)
		cdLeft, cdLength, cdEnabled = toCooldown(now, cdLeft, cdLength, cdEnabled)
		cdUsable = cdLeft == 0 or cdEnabled == 0
		state = state + ((IsCurrentSpell(n) or isCurrentForm(n, sid) or cdEnabled == 0) and 1 or 0) +
					(nomana and 8 or 0) + (inRange and 0 or 16) + (hasRange and 512 or 0) + (usable and 0 or 1024) +
					(cdEnabled == 0 and 2048 or 0)
		usable = not not (usable and inRange and cdUsable)
		local ih, ico, ohUsable = iconOverrideHandlers[msid] or
									  (type(n) == "string" and iconOverrideHandlers[n:lower()]), nil
		if ih then
			ico, ohUsable = ih(msid, n)
			if ohUsable ~= nil then
				usable = ohUsable == true
			end
		end
		local sbslot
		if msid then
			if sbslotCache[msid] == nil then
				sbslotCache[msid] = FindSpellBookSlotBySpellID(msid) or false
			end
			sbslot = sbslotCache[msid] or nil
		end
		local slotTex
		if not ico and type(origN) == "number" and origN then
			if not sbslot then
				if sbslotCache[origN] == nil then
					sbslotCache[origN] = FindSpellBookSlotBySpellID(origN) or false
				end
				slotTex = sbslotCache[origN] and GetSpellTexture(sbslotCache[origN], "spell") or nil
			end
		end
		overCount = overCount or count
		return usable, state, ico or slotTex or GetSpellTexture(n) or gicon, sname, overCount, cdLeft, cdLength,
			sbslot and SetSpellBookItem or msid and SetSpellByID, sbslot or msid
	end
	function spellFeedback(sname, target, spellId)
		spellMap[lowered[sname]] = spellId or spellMap[lowered[sname]] or getSpellIDFromName(sname)
		return spellHint(sname, nil, target)
	end
	local function createSpell(id, flags)
		if type(id) == "string" then
			-- Name-based spell (GetSpellLink=nil → no numeric sid available on Sirus).
			-- spellHint(name) resolves icon via iconOverrideHandlers[name:lower()] or GetSpellTexture(name) or gicon.
			local name = id
			if not actionMap[name] then
				actionMap[name] = AB:CreateActionSlot(spellHint, name, "attribute", "type", "spell", "spell", name,
					"checkselfcast", true, "checkfocuscast", true)
			end
			return actionMap[name]
		end
		if type(id) ~= "number" then
			return
		end
		local action
		local castable, rwCastType = RW:IsSpellCastable(id)
		if not castable then
			-- Create an action slot for any non-passive spell with a valid name;
			-- the button casts by name, and categories only add the player's own spells.
			local n0 = GetSpellInfo(id)
			if n0 and not IsPassiveSpell(id) then
				if not actionMap[n0] then
					actionMap[n0] = AB:CreateActionSlot(spellHint, id, "attribute", "type", "spell", "spell", n0,
						"checkselfcast", true, "checkfocuscast", true)
				end
				spellMap[lowered[n0]] = id
				return actionMap[n0]
			elseif n0 then
				-- Passive spell = profession opener (Алхимия, Наложение чар и т.д.).
				-- CastSpellByName находит не тот спелл на Sirus; нужен CastSpell(slot,"spell").
				local sbslot = FindSpellBookSlotBySpellID(id)
				if sbslot then
					local mac = "/run for t=1,GetNumSpellTabs() do local _,_,o,n=GetSpellTabInfo(t) for i=o+1,o+n do if tonumber((GetSpellLink(i,'spell') or ''):match('spell:(%d+)'))==" ..
									id .. " then return CastSpell(i,'spell') end end end"
					if not actionMap[n0] then
						actionMap[n0] = AB:CreateActionSlot(spellHint, id, "attribute", "type", "macro", "macrotext",
							mac)
					end
					spellMap[lowered[n0]] = id
					return actionMap[n0]
				end
			end
			return
		end
		if rwCastType == "rewire-escape" then
			return AB:GetActionSlot("macrotext", SLASH_CAST1 .. " " .. GetSpellInfo(id))
		else
			local s0, r0 = GetSpellInfo(id), GetSpellSubtext(id)
			local o, s = pcall(GetSpellInfo, s0, r0)
			if not (o and s and s0) then
				if s0 and not IsPassiveSpell(id) then
					action = s0
				else
					return
				end
			else
				local r1 = GetSpellSubtext(s0)
				action = (flags == 16 and r0 and r1 ~= r0 and FindSpellBookSlotBySpellID(id)) and
							 (s0 .. "(" .. r0 .. ")") or s0
			end
		end

		if action then
			if not actionMap[action] then
				actionMap[action] = AB:CreateActionSlot(spellHint, id, "attribute", "type", "spell", "spell", action,
					"checkselfcast", true, "checkfocuscast", true)
			end
			if type(action) == "string" and spellMap[lowered[action]] ~= id then
				spellMap[lowered[action]] = id
			end
		end
		return actionMap[action]
	end
	local function describeSpell(q, id, _flags)
		local name2, icon2, rank, name, _, icon = nil, nil, GetSpellSubtext(id), GetSpellInfo(id)
		local _, castType = RW:IsSpellCastable(id)
		if name and castType ~= "rewire-escape" then
			local qRank = (q == "list-query") and rank or nil
			rank, name2, _, icon2 = GetSpellSubtext(name, rank), GetSpellInfo(name, qRank)
		end
		local srank = rank and rank ~= "" and (rank ~= GetSpellSubtext(name)) and " (" .. rank .. ")" or ""
		local ts, ns = q == "list-query" and srank or "", q == "list-query" and "" or srank
		return L "Spell" .. ts, (name2 or name or "?") .. ns, icon2 or icon, nil, SetSpellByExactID, id
	end
	AB:RegisterActionType("spell", createSpell, describeSpell, 2, true)
	function EV.SPELLS_CHANGED()
		wipe(spellMap)
		wipe(sbslotCache)
		AB:NotifyObservers("spell")
	end
	function AB.HUM:SetSpellIconOverride(id, f)
		if not ((type(id) == "number" or type(id) == "string") and (f == nil or type(f) == "function")) then
			return error('SetSpellIconOverride: invalid arguments', 2)
		end
		-- Numeric key: used by msid lookup. String key: lowercased name, used by n-based lookup in spellHint.
		iconOverrideHandlers[type(id) == "string" and id:lower() or id] = f
	end
	function AB.HUM:GetNativeSpellFeedback(spell, target)
		return spellHint(spell, nil, target)
	end
end)
securecall(function() -- item: items ID/inventory slot
	local actionMap, itemIdMap, LAST_EQUIP_SLOT = {}, {}, INVSLOT_LAST_EQUIPPED
	local countOverrideHandlers = {}
	local function containerTip(self, bagslot)
		local slot = bagslot % 100
		self:SetBagItem((bagslot - slot) / 100, slot)
	end
	local function playerInventoryTip(self, slot)
		self:SetInventoryItem("player", slot)
	end
	local function GetItemLocation(iid, name, name2)
		local name2, cb, cs, n = name2 and lowered[name2]
		for i = 1, LAST_EQUIP_SLOT do
			if GetInventoryItemID("player", i) == iid then
				n = GetItemInfo(GetInventoryItemLink("player", i))
				if n == name or n and name2 and lowered[n] == name2 then
					return nil, i
				elseif not cs then
					cb, cs = nil, i
				end
			end
		end
		local ns, giid, gil = GetContainerNumSlots, GetContainerItemID, GetContainerItemLink
		for i = 0, 4 do
			for j = 1, ns(i) do
				if iid == giid(i, j) then
					n = GetItemInfo(gil(i, j))
					if n == name or n and name2 and lowered[n] == name2 then
						return i, j
					elseif not cs then
						cb, cs = i, j
					end
				end
			end
		end
		return cb, cs
	end
	function itemHint(ident, _modState, target, purpose, ibag, islot)
		local name, link, icon, _, bag, slot, tip, tipArg
		if type(ident) == "number" and ident <= LAST_EQUIP_SLOT then
			local invid = GetInventoryItemID("player", ident)
			if invid == nil then
				return
			end
			bag, slot, name, link = nil, invid, GetItemInfo(GetInventoryItemLink("player", ident) or invid)
			icon = GetInventoryItemTexture and GetInventoryItemTexture("player", ident) or nil
			ident = name or ident
		elseif ident then
			name, link, _, _, _, _, _, _, _, icon = GetItemInfo(ident)
		else
			return
		end
		local iid, cdLeft, cdLength, cdEnabled = (link and tonumber(link:match("item:([x%x]+)"))) or itemIdMap[ident]
		if iid then
			cdLeft, cdLength, cdEnabled = toCooldown(GetTime(), GetItemCooldown(iid))
		end
		target = target or "target"
		local canRange = not (InCombatLockdown() and (UnitIsFriend("player", target) or not UnitExists(target))) or nil
		local inRange, hasRange = canRange and NormalizeInRange[IsItemInRange(ident, target)]
		inRange, hasRange = inRange ~= 0, inRange ~= nil
		if ibag and islot then
			bag, slot = ibag, islot
		elseif iid then
			bag, slot = GetItemLocation(iid, name, ident)
		end
		if bag and slot then
			tip, tipArg = containerTip, bag * 100 + slot
		elseif slot then
			tip, tipArg = playerInventoryTip, slot
		elseif iid then
			tip, tipArg = callMethod.SetItemByID, iid
		end
		local nCharge = GetItemCount(ident, false, true) or 0
		local usable = nCharge > 0 and (GetItemSpell(ident) == nil or IsUsableItem(ident))
		local state = (IsCurrentItem(ident) and 1 or 0) + (inRange and 0 or 16) +
						  (slot and IsEquippableItem(ident) and
							  (bag and (purpose == "equip" and 128 or 0) or (slot and 256 or 0)) or 0) +
						  (hasRange and 512 or 0) + (usable and 0 or 1024) + (cdEnabled == 0 and 2048 or 0)
		usable = not not (usable and inRange and cdLeft == 0)
		icon = icon or select(10, GetItemInfo(ident))
		local oh = countOverrideHandlers[iid]
		if oh then
			local ohCharge, ohUsable = oh(iid, nCharge)
			nCharge = ohCharge or nCharge
			if ohUsable == true or ohUsable == false then
				usable = ohUsable
			end
		end
		return usable, state, icon, name or ident, nCharge, cdLeft, cdLength or 0, tip, tipArg
	end
	local function createItem(id, flags)
		local byName, forceShow, onlyEquipped
		if type(id) ~= "number" then
			return
		end
		if type(flags) == "number" then
			byName, forceShow, onlyEquipped = flags % 4 >= 2, flags % 2 >= 1, flags % 8 >= 4
		end
		local name = id <= LAST_EQUIP_SLOT and id or (byName and getCachedItemName(id) or ("item:" .. id))
		if not forceShow and onlyEquipped and
			not ((id > LAST_EQUIP_SLOT and IsEquippedItem(name)) or
				(id <= LAST_EQUIP_SLOT and GetInventoryItemLink("player", id))) then
			return
		end
		if not forceShow and GetItemCount(name) == 0 then
			return
		end
		if not actionMap[name] then
			actionMap[name], itemIdMap[name] = AB:CreateActionSlot(itemHint, name, "attribute", "type", "item", "item",
				name, "checkselfcast", true, "checkfocuscast", true), id
		end
		return actionMap[name]
	end
	local function describeItem(id, _flags)
		return L "Item", (GetItemInfo(id)) or peekCachedItemName(id), select(10, GetItemInfo(id)), nil,
			callMethod.SetItemByID, tonumber(id)
	end
	AB:RegisterActionType("item", createItem, describeItem, 2)
	function EV.BAG_UPDATE()
		AB:NotifyObservers("item")
	end
	RW:SetCommandHint(SLASH_EQUIP1, 70, function(_, _, clause, target)
		if clause and clause ~= "" and (GetItemInfo(clause)) then
			return true, itemHint(clause, nil, target, "equip")
		end
	end)
	RW:SetCommandHint(SLASH_EQUIP_TO_SLOT1, 70, function(_, _, clause)
		local item = clause and clause:match("^%s*%d+%s+(.*)")
		if item then
			return RW:GetCommandAction(SLASH_EQUIP1, item)
		end
	end)
	function AB.HUM:SetItemCountOverride(id, f)
		if not (type(id) == "number" and (f == nil or type(f) == "function")) then
			error('SetItemCountOverride: invalid arguments', 2)
		end
		countOverrideHandlers[id] = f
	end
end)
securecall(function() -- peq: slot token
	local slots = {
		head = "HEADSLOT",
		neck = "NECKSLOT",
		shoulders = "SHOULDERSLOT",
		shirt = "SHIRTSLOT",
		chest = "CHESTSLOT",
		waist = "WAISTSLOT",
		legs = "LEGSSLOT",
		feet = "FEETSLOT",
		wrist = "WRISTSLOT",
		hands = "HANDSSLOT",
		finger1 = "FINGER0SLOT",
		finger2 = "FINGER1SLOT",
		trinket1 = "TRINKET0SLOT",
		trinket2 = "TRINKET1SLOT",
		back = "BACKSLOT",
		tabard = "TABARDSLOT"
	}
	for tk, sk in pairs(slots) do
		local sn, suf, ok, slot = _G[sk], tk:match("%d+$"), pcall(GetInventorySlotInfo, sk)
		slots[tk] = ok and slot and {sk, sn and suf and (sn .. " " .. suf) or sn or sk} or nil
		if ok and slot then
			RW:SetCastAlias(tk, tostring(slot), false)
		end
	end
	local function describePlayerEquipmentSlot(tk)
		local si = slots[tk]
		if si then
			local slot, slotTex = GetInventorySlotInfo(si[1])
			local tex = GetInventoryItemTexture("player", slot) or slotTex
			return L "Equipment Slot", si[2], tex
		end
	end
	local function createPlayerEquipmentSlot(tk)
		local si = slots[tk]
		if si and not si[3] then
			local slot = GetInventorySlotInfo(si[1])
			si[3] = AB:CreateActionSlot(itemHint, slot, "conditional", "[uslot:" .. tk .. "]", "attribute", "type",
				"item", "item", slot)
		end
		return si and si[3]
	end
	AB:RegisterActionType("peq", createPlayerEquipmentSlot, describePlayerEquipmentSlot, 1)
end)
securecall(function() -- macrotext
	local map = {}
	local function macroHint(mtext, modLockState)
		return RW:GetMacroAction(mtext, modLockState)
	end
	local function createMacrotext(macrotext)
		if type(macrotext) ~= "string" then
			return
		end
		if not map[macrotext] then
			map[macrotext] = AB:CreateActionSlot(macroHint, macrotext, "retext", macrotext, false, true)
		end
		return map[macrotext]
	end
	local function describeMacrotext(macrotext)
		if macrotext == "" then
			return L "Custom Macro", L "New Macro", "Interface/Icons/INV_Misc_Note_03"
		end
		local _, _, ico = RW:GetMacroAction(macrotext)
		return L "Custom Macro", "", ico
	end
	AB:RegisterActionType("macrotext", createMacrotext, describeMacrotext, 1)
	local function checkReturn(pri, ...)
		if select("#", ...) > 0 then
			return pri, ...
		end
	end
	local function checkCountReturn(pri, ...)
		if select("#", ...) > 0 then
			local _, _, _, _, nc = ...
			return nc == 0 and pri - 5 or pri, ...
		end
	end
	local function canUseViaSCUI(clause)
		if (tonumber(clause) or 0) > INVSLOT_LAST_EQUIPPED then
			-- SCUI will pass to UseInventoryItem
			return false
		end
		return true
	end
	RW:SetCommandHint("/use", 100, function(_, _, clause, target, _, _, msg)
		if not clause or clause == "" then
			return
		end
		local isItemReturn, link, bag, slot = false, SecureCmdItemParse(clause)
		if (bag and slot) or (link and tonumber(link)) then
			if msg == "castrandom-fallback" or canUseViaSCUI(clause) then
				isItemReturn = true
			end
		end
		if isItemReturn then
			return checkCountReturn(90, itemHint(link, nil, target, nil, bag, slot))
		end
		local sid = clause:match("^spell:(%d+)$")
		if sid or not tonumber(clause, 10) then
			return checkReturn(true, spellFeedback(sid or clause, target))
		end
	end)
	RW:SetCommandHint("/cast", 100, function(_, _, clause, target, _, _, msg)
		if not clause or clause == "" then
			return
		end
		local sex = DoesSpellExist(clause) and not tonumber(clause, 10)
		local sid = not sex and clause:match("^spell:(%d+)$")
		if sex or sid then
			return checkReturn(true, spellFeedback(sid or clause, target))
		else
			local link, bag, slot = SecureCmdItemParse(clause)
			if ((bag and slot) or (link and tonumber(link))) and (msg == "castrandom-fallback" or canUseViaSCUI(clause)) then
				return checkCountReturn(90, itemHint(link, nil, target, nil, bag, slot))
			end
		end
	end)
	RW:SetCommandHint(SLASH_CASTSEQUENCE1, 100, function(_, _, clause, target)
		if not clause or clause == "" then
			return
		end
		local _, item, spell = QueryCastSequence(clause)
		clause = (item or spell)
		if clause then
			return RW:GetCommandAction("/use", clause, target)
		end
	end)
	do -- /userandom + /qsequence
		local f = CreateFrame("Frame", nil, nil, "SecureHandlerBaseTemplate")
		f:SetFrameRef("RW", RW:seclib())
		f:SetFrameRef("KR", KR:seclib())
		f:Execute([[-- AB_userandom_init
			seed, crState, qsState = math.random(2^30), newtable(), newtable()
			RW = self:GetFrameRef('RW'), self:SetAttribute('frameref-RW', nil)
			KR = self:GetFrameRef('KR'), self:SetAttribute('frameref-KR', nil)
		]])
		f:SetAttribute("RunSlashCmd", [=[-- AB_userandom
			local cmd, v, target, s, q = ...
			local isRand = cmd ~= "/qsequence"
			local tv, i, vt, _ = (isRand and crState or qsState)[v]
			if v == "" or not v then
				return
			elseif not tv then
				local iv, tn, np = newtable(), 1, 1 --@init_clause_start
				while np do
					local sp, spc, ev, eo = np, np
					repeat
						sp, spc = spc, v:match("^%s*<[^<]->()%s*", sp)
					until not spc
					eo = sp > np and v:sub(np, sp-1):gsub("<(.-)>", "[%1]") or nil
					ev, np = v:match("^%s*([^%s,][^,]*),?%s*()", sp)
					ev = ev and ev:match("^%s*(.-)%s*$") or ""
					if ev ~= "" then
						iv[-tn], iv[tn], tn = eo, ev, tn + 1
					end
				end
				tv, (isRand and crState or qsState)[v], iv[0] = iv, iv, isRand and 1 + seed % #iv or 1 --@init_clause_end
			end
			i = tv[0]
			v, vt, tv[0] = tv[i], tv[-i], isRand and math.random(#tv) or (1 + i % #tv)
			if v then
				if vt then
					_, vt = KR:RunAttribute("EvaluateCmdOptions", vt)
				end
				return RW:RunAttribute("RunSlashCmd", "/cast", v, vt or target, isRand and "opt-into-cr-fallback")
			end
		]=])
		local getNextCast
		do -- (kind, v, target) -> (v, target)
			local senv = GetManagedEnvironment(f)
			local uenv = setmetatable({
				qsState = {},
				crState = {},
				newtable = function()
					return {}
				end
			}, {
				__index = senv
			})
			local initF = setfenv(loadstring("return function(isRand, v)\n" ..
												 f:GetAttribute("RunSlashCmd")
					:match("[^\n]+@init_clause_start.-@init_clause_end") .. "\nreturn iv end"), {})
			initF = setfenv(initF(), uenv)
			function getNextCast(k, c, target)
				local t1, ucache, tv, i, v, vt = senv[k][c], uenv[k]
				tv = t1 or ucache[c] or initF(k == "crState", c)
				if t1 then
					ucache[c] = nil
				end
				i = tv[0]
				v, vt = tv[i], tv[-i]
				if vt then
					_, vt = KR:EvaluateCmdOptions(vt)
				end
				return v, vt or target
			end
		end
		RW:RegisterCommand(SLASH_USERANDOM1, true, true, f)
		local function hintCastRandom(_, _, clause, target)
			if (clause or "") == "" then
				return
			end
			local v, vt = getNextCast("crState", clause, target)
			if v then
				local nextN = tonumber(v)
				if nextN and nextN > 20 and (GetItemInfo(nextN)) then
					v = "item:" .. v
				end
				return RW:GetCommandAction("/use", v, vt or target, nil, "castrandom-fallback")
			end
		end
		local function hintQuickSequence(_slash, _unparsed, clause, target)
			if (clause or "") == "" then
				return
			end
			local v, vt = getNextCast("qsState", clause, target)
			if v then
				return RW:GetCommandAction("/cast", v, vt)
			end
		end
		RW:SetCommandHint(SLASH_USERANDOM1, 50, hintCastRandom)
		SLASH_ACTIONBOOK_QSEQUENCE1, SLASH_ACTIONBOOK_QSEQUENCE2 = "/qsequence", "/quicksequence"
		RW:RegisterCommand(SLASH_ACTIONBOOK_QSEQUENCE1, true, true, f)
		RW:AddCommandAliases(SLASH_ACTIONBOOK_QSEQUENCE1, SLASH_ACTIONBOOK_QSEQUENCE2)
		RW:SetCommandHint(SLASH_ACTIONBOOK_QSEQUENCE1, 100, hintQuickSequence)
		IM:AddTokenizableCommand("ACTIONBOOK_QSEQUENCE", SLASH_CASTRANDOM1)
		SLASH_ACTIONBOOK_QSEQUENCE1, SLASH_ACTIONBOOK_QSEQUENCE2 = nil, nil
	end
end)
securecall(function() -- macro: name
	local map, sm = {}, {}
	local function macroIndexByName(name)
		if type(GetMacroIndexByName) ~= "function" then
			return nil
		end
		local idx = GetMacroIndexByName(name)
		return idx and idx > 0 and idx or nil
	end
	do
		local wmSynced, owner = true, RW:RegisterNamedMacroTextOwner("ab-macro-wrapper", 10)
		local function syncWMacros()
			local notify, numGlobal, numChar = false, GetNumMacros()
			for k in pairs(sm) do
				if not GetMacroInfo(macroIndexByName(k) or k) then
					notify, sm[k] = RW:SetNamedMacroText(k, nil, owner, true) or notify, nil
				end
			end
			local ofs = MAX_ACCOUNT_MACROS - numGlobal
			for i = 1, numGlobal + numChar do
				local k, _, text = GetMacroInfo((i > numGlobal and ofs or 0) + i)
				if k and text ~= sm[k] then
					notify, sm[k] =
						RW:SetNamedMacroText(k, "#abmacrowrap " .. k .. "\n" .. text, owner, true) or notify, text
				end
			end
			if notify then
				AB:NotifyObservers("macro")
			end
			wmSynced = true
			return "remove"
		end
		function EV.UPDATE_MACROS()
			if not InCombatLockdown() then
				syncWMacros()
			elseif wmSynced then
				EV.PLAYER_REGEN_ENABLED, wmSynced = syncWMacros, nil
			end
		end
	end
	RW:SetMetaHintFilter("abmacrowrap", "macroFallback", false, function(_meta, v)
		if sm[v] then
			local n, ico = GetMacroInfo(macroIndexByName(v) or v)
			return true, not not n, ico, v
		end
	end)
	local function namedMacroHint(name, cndState)
		return RW:GetNamedMacroAction(name, cndState)
	end
	local function createNamedMacro(name, flags)
		local forceShow = flags == 1
		if type(name) == "string" and (forceShow or RW:IsNamedMacroKnown(name)) then
			if not map[name] then
				map[name] = AB:CreateActionSlot(namedMacroHint, name, "reslash", "/runmacro", name)
			end
			return map[name]
		end
	end
	local function describeMacro(name)
		local _, ico
		if RW:IsNamedMacroKnown(name) then
			_, _, ico = RW:GetNamedMacroAction(name)
		end
		return L "Macro", name, ico
	end
	AB:RegisterActionType("macro", createNamedMacro, describeMacro, 2)
end)
securecall(function() -- battlepet: pet ID, species ID
	local petAction = {}
	local BPET_ATYPE_NAME, SummonCompanion = COMPANIONS
	local SetBattlePetByID = callMethod.SetCompanionPet
	function SummonCompanion(guid)
		if C_PetJournal.IsCurrentlySummoned(guid) then
			C_PetJournal.DismissSummonedPet(guid)
		else
			DoEmote("STAND")
			C_PetJournal.SummonPetByGUID(guid)
		end
	end
	local function battlepetHint(pid)
		local n, _, tex = C_PetJournal.GetPetInfoByPetID(pid)
		local cdLeft, cdLength, cdEnabled = toCooldown(GetTime(), C_PetJournal.GetPetCooldownByGUID(pid))
		local state = (C_PetJournal.IsCurrentlySummoned(pid) and 1 or 0) + (cdEnabled == 0 and 2048 or 0)
		return n and cdLeft == 0 and C_PetJournal.PetIsSummonable(pid), state, tex, n or "", 0, cdLeft,
			cdLength, SetBattlePetByID, pid
	end
	local GetBattlePetInfo
	do -- (petID)
		local function checkInfoReturn(pid, ok, ...)
			if ok and ... then
				return pid, ...
			end
		end
		function GetBattlePetInfo(pid)
			return checkInfoReturn(pid, pcall(C_PetJournal.GetPetInfoByPetID, pid))
		end
	end
	local function createBattlePet(pid)
		local rpid = GetBattlePetInfo(pid)
		if not rpid then
			return
		end
		local pk = rpid:upper()
		if not petAction[pk] then
			petAction[pk] = AB:CreateActionSlot(battlepetHint, rpid, "func", SummonCompanion, rpid)
		end
		return petAction[pk]
	end
	local function describeBattlePet(pid)
		local rpid, n, _, tex = GetBattlePetInfo(pid)
		if not rpid then
			return BPET_ATYPE_NAME, "?"
		end
		return BPET_ATYPE_NAME, n or ("#" .. tostring(rpid)), tex, nil, SetBattlePetByID, rpid
	end
	AB:RegisterActionType("battlepet", createBattlePet, describeBattlePet, 2)
end)
securecall(function() -- equipmentset: equipment sets by name
	local setMap = {}
	local function resolveIcon(fid)
		if not fid or type(fid) == "number" then
			return "Interface/Icons/INV_Misc_QuestionMark"
		end
		if fid:find("[/\\]") then
			return fid
		end
		return "Interface/Icons/" .. fid
	end
	local function equipmentsetHint(name)
		local esid = name and C_EquipmentSet.GetEquipmentSetID(name) or -1
		local _, icon = C_EquipmentSet.GetEquipmentSetInfo(esid)
		if icon then
			return true, 0, resolveIcon(icon), name, nil, 0, 0, callMethod.SetEquipmentSet, esid
		end
	end
	local function wrapCommandHint(...)
		local _, state = ...
		if state then
			return true, ...
		end
	end
	function EV.EQUIPMENT_SETS_CHANGED()
		AB:NotifyObservers("equipmentset")
	end
	local function equipSetActionSpec(name)
		return "macrotext", SLASH_EQUIP_SET1 .. " " .. name
	end
	local function createEquipSet(name)
		local sid = type(name) == "string" and C_EquipmentSet.GetEquipmentSetID(name)
		if not sid then
			return
		end
		if not setMap[name] and name:match("^[^%[;%]]*$") then
			setMap[name] = AB:CreateActionSlot(equipmentsetHint, name, equipSetActionSpec(name))
		end
		return setMap[name]
	end
	local function describeEquipSet(name)
		local esid = name and C_EquipmentSet.GetEquipmentSetID(name) or -1
		local _, ico = C_EquipmentSet.GetEquipmentSetInfo(esid)
		return L "Equipment Set", name, ico and resolveIcon(ico) or "Interface/Icons/INV_Misc_QuestionMark", nil,
			callMethod.SetEquipmentSet, esid
	end
	AB:RegisterActionType("equipmentset", createEquipSet, describeEquipSet, 1)
	RW:SetCommandHint(SLASH_EQUIP_SET1, 80, function(_, _, clause)
		if clause and clause ~= "" then
			return wrapCommandHint(equipmentsetHint(clause))
		end
	end)
end)
securecall(function() -- raidmark
	local map, waitingToClearSelf = {}
	local function CanChangeRaidTargets(unit)
		-- UnitIsGroupAssistant is Cata+; WotLK uses UnitIsRaidOfficer
		local isAssist = UnitIsRaidOfficer and UnitIsRaidOfficer("player") or false
		return not not ((not IsInRaid() or UnitIsGroupLeader("player") or isAssist) and
				   not (unit and UnitIsPlayer(unit) and UnitIsEnemy("player", unit)))
	end
	local function setRaidTarget(id)
		SetRaidTarget("target", GetRaidTargetIndex("target") == id and 0 or id)
	end
	local function raidmarkHint(i, _, target)
		local target = target or "target"
		local state = GetRaidTargetIndex(target) == i and 1 or 0
		return CanChangeRaidTargets(target), state, "Interface/TargetingFrame/UI-RaidTargetingIcon_" .. i,
			_G["RAID_TARGET_" .. i], 0, 0, 0
	end
	local function removeHint()
		return CanChangeRaidTargets(), 0, "Interface/Icons/INV_Gauntlets_02", REMOVE_WORLD_MARKERS, 0, 0, 0
	end
	local function FinishClearRaidTargets()
		if waitingToClearSelf and GetRaidTargetIndex("player") == 1 then
			waitingToClearSelf = nil
			if CanChangeRaidTargets() then
				SetRaidTarget("player", 0)
			end
			return "remove"
		end
	end
	map[0] = AB:CreateActionSlot(removeHint, nil, "func", function()
		if not CanChangeRaidTargets() then
			return
		end
		local pt = GetRaidTargetIndex("player")
		for i = 8, 0, -1 do
			SetRaidTarget("player", i == pt and 1 or i == 1 and pt or i)
		end
		if not (pt or waitingToClearSelf) and IsInGroup() then
			waitingToClearSelf, EV.RAID_TARGET_UPDATE = 1, FinishClearRaidTargets
		end
	end)
	for i = 1, 8 do
		map[i] = AB:CreateActionSlot(raidmarkHint, i, "func", setRaidTarget, i)
	end
	local function createRaidMark(id)
		return map[id]
	end
	local function describeRaidMark(id)
		if id == 0 then
			return L "Raid Marker", REMOVE_WORLD_MARKERS, "Interface/Icons/INV_Gauntlets_02"
		end
		return L "Raid Marker", _G["RAID_TARGET_" .. id], "Interface/TargetingFrame/UI-RaidTargetingIcon_" .. id
	end
	AB:RegisterActionType("raidmark", createRaidMark, describeRaidMark, 1)
end)
securecall(function() -- worldmark
	local map, ORDER = {}, WORLD_RAID_MARKER_ORDER
	if not (ORDER and PlaceRaidMarker and ClearRaidMarker and IsRaidMarkerActive) then
		return
	end
	local CMD_PLACE = SLASH_WORLD_MARKER4 or SLASH_WORLD_MARKER2 or "/worldmarker"
	local CMD_CLEAR = SLASH_CLEAR_WORLD_MARKER4 or SLASH_CLEAR_WORLD_MARKER2 or "/clearworldmarker"
	local function CanPlaceWorldMarkers()
		if (IsRaidLeader() or IsRaidOfficer()) and GetNumRaidMembers() > 0 then
			return true
		end
		return not not (IsPartyLeader() and GetNumPartyMembers() > 0)
	end
	local function markerInfo(i)
		local mi = ORDER[i]
		local s = mi and _G["WORLD_MARKER" .. mi] or ""
		return mi, s:match("|T(.-):") or "Interface/TargetingFrame/UI-RaidTargetingIcon_" .. (9 - i),
			(s:gsub("|T.-|t%s*", ""))
	end
	local function worldmarkHint(i)
		local mi, icon, name = markerInfo(i)
		return CanPlaceWorldMarkers(), (mi and IsRaidMarkerActive(mi)) and 1 or 0, icon, name, 0, 0, 0
	end
	local function removeHint()
		return CanPlaceWorldMarkers(), 0, "Interface/RaidFrame/Raid-WorldPing", REMOVE_WORLD_MARKERS, 0, 0, 0
	end
	map[0] = AB:CreateActionSlot(removeHint, nil, "macrotext", CMD_CLEAR .. " " .. (ALL or "all"))
	for i = 1, #ORDER do
		map[i] = AB:CreateActionSlot(worldmarkHint, i, "macrotext", CMD_PLACE .. " " .. ORDER[i])
	end
	local function createWorldMark(id)
		return map[id]
	end
	local function describeWorldMark(id)
		if id == 0 then
			return L "Raid World Marker", REMOVE_WORLD_MARKERS, "Interface/RaidFrame/Raid-WorldPing"
		end
		local _, icon, name = markerInfo(id)
		return L "Raid World Marker", name, icon
	end
	AB:RegisterActionType("worldmark", createWorldMark, describeWorldMark, 1)
	if _G["SLASH_WORLD_MARKER1"] then
		RW:ImportSlashCmd("WORLD_MARKER", true, false, 40, function(_, _, clause)
			clause = tonumber(clause)
			for i = 1, #ORDER do
				if ORDER[i] == clause then
					return true, worldmarkHint(i)
				end
			end
		end)
	end
end)
securecall(function() -- action
	local amap = {}
	local function createAction(id, _flags)
		if type(id) ~= "number" or id < 0 or id % 1 ~= 0 then
			return
		end
		local aid = amap[id]
		if aid == nil then
			aid = AB:CreateActionSlot(actionHint, id, "attribute", "type", "action", "action", id)
			amap[id] = aid
		end
		return aid
	end
	local function describeAction(id)
		if type(id) ~= "number" or id < 0 or id % 1 ~= 0 then
			return
		end
		return L "Action", id, GetActionTexture(id)
	end
	AB:RegisterActionType("action", createAction, describeAction, 2)
end)
securecall(function() -- petspell: spell ID
	local actionInfo = {
		stay = {"Interface\\Icons\\Spell_Nature_TimeStop", "PET_ACTION_WAIT"},
		follow = {"Interface\\Icons\\Ability_Tracking", "PET_ACTION_FOLLOW"},
		attack = {"Interface\\Icons\\Ability_GhoulFrenzy", "PET_ACTION_ATTACK"},
		defend = {"Interface\\Icons\\Ability_Defend", "PET_MODE_DEFENSIVE"},
		assist = {"Interface/Icons/Ability_Racial_BloodRage", "PET_MODE_AGGRESSIVE"},
		passive = {"Interface\\Icons\\Ability_Seal", "PET_MODE_PASSIVE"},
		dismiss = {CLASS == "WARLOCK" and "Interface\\Icons\\spell_shadow_sacrificialshield" or
			"Interface\\Icons\\spell_nature_spiritwolf"}
	}
	local actionID = {}
	local petTip = function(self, slot)
		return self:SetPetAction(slot)
	end
	local petCommandFeedback = function(info)
		local ico, name, slot = info[1], info[2], info[3]
		local sname, _subtext, _texture, _isToken, isActive = GetPetActionInfo(slot or 0)
		if sname ~= name then
			info[3], slot = nil
			for i = 1, 10 do
				sname, _subtext, _texture, _isToken, isActive = GetPetActionInfo(i)
				if sname == name then
					info[3], slot = i, i
					break
				end
			end
		end
		local flags = slot and (isActive and 1 or 0) or 0
		-- Behavior tokens (attack/stay/follow etc.) don't need range check;
		-- usable as long as pet exists.
		return not not slot and not not UnitExists("pet"), flags, ico, _G[name] or name, 0, 0, 0,
			slot and petTip or nil, slot
	end
	local function petHint(sid)
		local info = actionInfo[sid]
		if sid == "dismiss" then
			if CLASS == "HUNTER" and PetCanBeAbandoned() then
				return spellFeedback(2641, nil, 2641)
			end
			return HasFullControl() and UnitExists("pet") and PetCanBeDismissed(), 0, info[1], PET_ACTION_DISMISS
		elseif info then
			return petCommandFeedback(info)
		elseif sid then
			return spellFeedback(sid, nil, sid)
		end
	end
	local function createPetAction(id)
		if type(id) == "number" and id > 0 and not actionID[id] and not IsPassiveSpell(id) and GetSpellInfo(id) then
			local cond = "[petcontrol];hide"
			actionID[id] = AB:CreateActionSlot(petHint, id, "conditional", cond, "attribute", "type", "spell", "spell",
				id)
		end
		return actionID[id]
	end
	local function describePetAction(id)
		if type(id) == "number" then
			local name, _, icon = GetSpellInfo(id)
			return L "Pet Ability", name, icon, nil, callMethod.SetSpellByID, id
		elseif actionID[id] then
			local _, _, icon, name, _, _, _, tipf, tipa = petHint(id)
			return L "Pet Ability", name, icon, nil, tipf, tipa
		end
	end
	AB:RegisterActionType("petspell", createPetAction, describePetAction, 1)
	do
		local cnd, macroMap = "[petcontrol,@pet,help,novehicleui]", {}
		local function check(...)
			if ... ~= nil then
				return true, ...
			end
		end
		local function petmacroHint(slash, _, clause, _target)
			local aid = clause and macroMap[slash]
			if aid then
				return check(petHint(aid))
			end
		end
		local function addPetCommand(cmd, key)
			actionID[key] = AB:CreateActionSlot(petHint, key, "conditional", cnd, "macrotext", cmd)
			RW:SetCommandHint(cmd, 75, petmacroHint)
			macroMap[cmd:lower()] = key
		end
		addPetCommand(SLASH_PET_STAY1, "stay")
		addPetCommand(SLASH_PET_FOLLOW1, "follow")
		addPetCommand(SLASH_PET_ATTACK1, "attack")
		addPetCommand(SLASH_PET_DEFENSIVE1, "defend")
		addPetCommand(SLASH_PET_PASSIVE1, "passive")
		if type(SLASH_PET_DISMISS1) == "string" then
			actionID.dismiss = AB:CreateActionSlot(petHint, "dismiss", "conditional", cnd, "macrotext",
				SLASH_PET_DISMISS1)
		end
		addPetCommand(SLASH_PET_AGGRESSIVE1, "assist")
	end
end)
securecall(function() -- toy: item ID, flags[FORCE_SHOW]
	local map, lastUsability, uq, whinedAboutGIIR = {}, {}, {}
	local OVERRIDE_TOY_ACQUIRED, IGNORE_TOY_USABILITY = {}, {
		[129149] = 1,
		[129279] = 1,
		[129367] = 1,
		[130157] = "[in:broken isles]",
		[130158] = 1,
		[130170] = 1,
		[130191] = 1,
		[130199] = 1,
		[130232] = 1,
		[131812] = 1,
		[131814] = 1,
		[140325] = 1,
		[147708] = 1,
		[165021] = 1,
		[153039] = 1,
		[119421] = 1,
		[128462] = "[alliance]",
		[128471] = "[horde]",
		[95589] = "[alliance]",
		[95590] = "[horde]",
		[89222] = 1,
		[63141] = "[alliance]",
		[64997] = "[horde]",
		[66888] = 1,
		[89869] = 1,
		[90175] = 1,
		[103685] = 1,
		[115468] = "[horde]",
		[115472] = "[alliance]",
		[119160] = "[horde]",
		[119182] = "[alliance]",
		[122283] = 1,
		[142531] = 1,
		[142532] = 1,
		[163211] = 1,
		[85500] = nil,
		[182773] = "[coven:necro][acoven80:necro]",
		[184353] = "[coven:kyrian][acoven80:kyrian]",
		[180290] = "[coven:fae][acoven80:fae]",
		[183716] = "[coven:venthyr][acoven80:venthyr]",
		[190237] = 1
	}
	local function playerHasToy(id)
		local f = OVERRIDE_TOY_ACQUIRED[id]
		if f then
			return f == true or f(id)
		end
		return f == nil and PlayerHasToy(id)
	end
	function toyHint(iid, _modState, target)
		local state, now = 0, GetTime()
		local _, _, name, icon = C_ToyBox.GetToyInfo(iid)
		local cdLeft, cdLength, cdEnabled = toCooldown(now, GetItemCooldown(iid))
		local ignUse, usable = IGNORE_TOY_USABILITY[iid]
		if not playerHasToy(iid) then
			usable = false
		elseif ignUse == nil then
			usable = C_ToyBox.IsToyUsable(iid) ~= false
		else
			usable = ignUse == 1 or (not not KR:EvaluateCmdOptions(ignUse))
		end
		target = target or "target"
		local canRange = not (InCombatLockdown() and (UnitIsFriend("player", target) or not UnitExists(target))) or nil
		local inRange, hasRange = canRange and NormalizeInRange[IsItemInRange(iid, target)]
		inRange, hasRange = inRange ~= 0, inRange ~= nil
		state = state + (inRange and 0 or 16) + (hasRange and 512 or 0) + (cdEnabled == 0 and 2048 or 0)
		icon = icon or select(10, GetItemInfo(iid))
		usable = name and cdLeft == 0 and inRange and usable or false
		return usable, state, icon, name, 0, cdLeft, cdLength, callMethod.SetItemByID, iid
	end
	function EV:ITEM_DATA_LOAD_RESULT(iid, ok)
		if not (ok and uq[iid]) then
			return
		end
		local iu = C_ToyBox.IsToyUsable(iid)
		if iu ~= nil then
			lastUsability[iid], uq[iid] = iu, nil
		elseif not whinedAboutGIIR then
			whinedAboutGIIR = true
			error("Curse your sudden but inevitable betrayal [" .. iid .. "]")
		end
	end
	local function wrapCondition(cnd, ...)
		if (cnd or 1) == 1 then
			return ...
		else
			return "conditional", cnd, ...
		end
	end
	local function createToy(id, flags)
		if type(id) ~= "number" or id < 1 then
			return
		end
		local forceShow, ignUse = flags == 1, IGNORE_TOY_USABILITY[id]
		local qid = forceShow and (ignUse or 1) ~= 1 and -id or id
		if not (forceShow or playerHasToy(id)) then
			return
		end
		local isUsable, mid = ignUse or C_ToyBox.IsToyUsable(id), map[qid]
		if isUsable == nil then
			isUsable, uq[id] = lastUsability[id], 1
			GetItemInfo(id)
			requestItemData(id)
		elseif not ignUse then
			lastUsability[id] = isUsable
		end
		if not (forceShow or isUsable) then
			mid = nil
		elseif mid == nil then
			mid = AB:CreateActionSlot(toyHint, id,
				wrapCondition(forceShow and 1 or ignUse, "attribute", "type", "item", "item", "item:" .. id))
			map[qid] = mid
		end
		return mid
	end
	local function describeToy(id)
		if type(id) ~= "number" then
			return
		end
		local ignUse, haveToy, _, _, name, tex = IGNORE_TOY_USABILITY[id], playerHasToy(id), C_ToyBox.GetToyInfo(id)
		local canUse = haveToy and (type(ignUse) ~= "string" or KR:EvaluateCmdOptions(ignUse)) and
						   (ignUse or C_ToyBox.IsToyUsable(id))
		local actionFlags = haveToy and not canUse and 1 or nil
		return L "Toy", name, tex or select(10, GetItemInfo(id)), nil, callMethod.SetItemByID, id, nil, actionFlags
	end
	AB:RegisterActionType("toy", createToy, describeToy, 2)
	function AB.HUM:SetPlayerHasToyOverride(id, filter)
		local tf = type(filter)
		if not (type(id) == "number" and (tf == "nil" or tf == "boolean" or tf == "function")) then
			return error('SetPlayerHasToyOverride: invalid arguments', 2)
		end
		OVERRIDE_TOY_ACQUIRED[id] = filter
	end
end)
securecall(function() -- disenchant: iid
	local map, DISENCHANT_SID = {}, 13262
	local DISENCHANT_SN = (GetSpellInfo(DISENCHANT_SID))
	local ICON_PREFIX = "|TInterface/Buttons/UI-GroupLoot-DE-Up:0:0|t "
	local SLASH_SPELL_TARGET_ITEM1 = '/spelltargetitem'
	do
		local wn = newWidgetName("AB:I!")
		local w = CreateFrame("Button", wn, nil, "SecureActionButtonTemplate")
		w:Hide()
		SecureHandlerWrapScript(w, "OnClick", w, [[return nil, 'post']], [[self:SetAttribute("target-item", nil)]])
		local er = {
			u = "\\117",
			["{"] = "\\123",
			["}"] = "\\125"
		}
		local function escape(s)
			return ("%q"):format(s):gsub('[{u}]', er):sub(2, -2)
		end
		w:SetAttribute("RunSlashCmd", ([[-- AB_SPELLTARGET_ITEM_RUN
			local cmd, v = ...
			if cmd == "%s" and v then
				self:SetAttribute("target-item", v)
				return "%s"
			end
		]]):format(escape(SLASH_SPELL_TARGET_ITEM1), escape(SLASH_CLICK1 .. " " .. wn .. " 1")))
		RW:RegisterCommand(SLASH_SPELL_TARGET_ITEM1, true, false, w)
	end
	local function disenchantTip(self, iid)
		self:SetItemByID(iid)
		self:AddLine(ICON_PREFIX .. DISENCHANT_SN, 0, 1, 0)
		self:Show()
	end
	local function disenchantHint(ident)
		local count = GetItemCount(ident, false, false, false)
		local usable = IsSpellKnown(DISENCHANT_SID) and count > 0
		local name = (GetItemInfo(ident))
		local state, cdUsable = 0, nil
		local cdLeft, cdLength, cdEnabled = GetSpellCooldown(DISENCHANT_SID)
		cdLeft, cdLength, cdEnabled = toCooldown(GetTime(), cdLeft, cdLength, cdEnabled)
		cdUsable = cdLeft == 0
		state = state + 131072 + (IsCurrentItem(ident) and 1 or 0) + (usable and 0 or 1024) +
					(cdEnabled == 0 and 2048 or 0)
		local disName = ICON_PREFIX .. (name or ("item:" .. ident))
		return not not (usable and cdUsable), state, select(10, GetItemInfo(ident)), disName, count, cdLeft or 0,
			cdLength or 0, disenchantTip, ident
	end
	local function createDisenchant(iid)
		if not (DISENCHANT_SN and IsSpellKnown(DISENCHANT_SID) and type(iid) == "number" and GetItemCount(iid) > 0) then
			return
		end
		local mid = map[iid]
		if not mid then
			local macrotext = ("%s [@none] %s\n%s item:%d"):format(SLASH_CAST1, DISENCHANT_SN, SLASH_SPELL_TARGET_ITEM1,
				iid)
			mid = AB:CreateActionSlot(disenchantHint, iid, "retext", macrotext)
			map[iid] = mid
		end
		return mid
	end
	local function describeDisenchant(iid)
		if type(iid) ~= "number" then
			return
		end
		local icon, name = select(10, GetItemInfo(iid)), (GetItemInfo(iid))
		return DISENCHANT_SN, name or ("item:" .. iid), icon, nil, disenchantTip, iid
	end
	AB:RegisterActionType("disenchant", createDisenchant, describeDisenchant, 1)
end)
securecall(function() -- uipanel: token
	local CLICK, widgetClickCommand, closeButton = SLASH_CLICK1 .. " "
	do
		local pyName = newWidgetName("AB:PY!")
		local py = CreateFrame("Button", pyName, nil, "SecureActionButtonTemplate")
		py:SetAttribute("type", "click")
		function widgetClickCommand(k, w)
			if w == nil then
				return ""
			end
			local tn = type(w) == "string" and w or w.GetName and w:GetName()
			if tn == nil then
				local w1 = py:GetAttribute("clickbutton-" .. k)
				k = (w1 and w1 ~= w) and k .. "2" or k
				py:SetAttribute("clickbutton-" .. k, w)
				tn = pyName .. " " .. k
			end
			return CLICK .. tn .. " 1\n"
		end
		function closeButton(p, reg)
			local r = CreateFrame("Button", nil, p, "UIPanelCloseButton")
			r:Hide()
			return r, reg and widgetClickCommand(reg, r)
		end
	end
	local panelMap, panels = {}, {
		character = {
			CHARACTER,
			icon = "Interface/Icons/inv_helmet_25",
			gw = CharacterFrame,
			tw = CharacterFrameTab1
		},
		reputation = {
			REPUTATION,
			icon = "Interface/Icons/Achievement_Reputation_01",
			gw = ReputationFrame,
			tw = CharacterFrameTab3
		},
		currency = {
			CURRENCY,
			icon = "Interface/Icons/INV_Misc_Coin_17",
			gw = TokenFrame,
			tw = CharacterFrameTab4,
			req = function()
				return GetCurrencyListSize() > 0
			end
		},
		spellbook = {
			SPELLBOOK,
			icon = "Interface/Icons/INV_Misc_Book_09",
			gw = SpellBookFrame,
			tmt = "/click SpellbookMicroButton\n/click SpellBookFrameCloseButton",
			cw = SpellBookFrameCloseButton
		},
		talents = {
			TALENTS_BUTTON,
			icon = "Interface/Icons/Ability_Marksmanship",
			gn = "PlayerTalentFrame",
			tw = TalentMicroButton,
			req = function()
				return (UnitLevel("player") or 0) >= 10
			end
		},
		achievements = {
			ACHIEVEMENTS,
			icon = "Interface/Icons/Achievement_General",
			gn = "AchievementFrame",
			tw = AchievementMicroButton,
			tcr = 1
		},
		quests = {
			QUESTLOG_BUTTON,
			icon = "Interface/Icons/INV_Misc_Book_08",
			gw = QuestLogFrame,
			tw = QuestLogMicroButton
		},
		groupfinder = {
			DUNGEONS_BUTTON,
			icon = "Interface/Icons/INV_Misc_GroupLooking",
			gw = LFDParentFrame,
			tw = LFDMicroButton
		},
		collections = {
			COLLECTIONS,
			icon = "Interface/Icons/Ability_Mount_RidingHorse",
			gw = CollectionsJournal,
			tw = CollectionsMicroButton
		},
		adventureguide = {
			ADVENTURE,
			icon = "Interface/Icons/INV_Misc_Book_07",
			gw = EncounterJournal,
			tw = EncounterJournalMicroButton
		},
		store = {
			MAINMENUBAR_STORE_BUTTON,
			icon = "Interface/Icons/INV_Misc_Coin_01",
			gw = StoreFrame,
			tw = StoreMicroButton,
			req = function()
				return C_StorePublic and C_StorePublic.IsEnabled() or false
			end
		},
		guild = {
			GUILD,
			icon = "Interface/Icons/INV_Shirt_GuildTabard_01",
			gw = GuildFrame,
			tw = GuildMicroButton,
			req = IsInGuild
		},
		map = {
			WORLD_MAP,
			icon = "Interface/Icons/Inv_Misc_Map08",
			gw = WorldMapFrame,
			tw = MiniMapWorldMapButton
		},
		social = {
			SOCIAL_BUTTON,
			icon = "Interface/Icons/INV_Letter_18",
			gw = FriendsFrame,
			tw = SocialsMicroButton
		},
		calendar = {
			L "Calendar",
			icon = "Interface/Icons/Spell_Holy_BorrowedTime",
			gn = "CalendarFrame",
			tw = GameTimeFrame
		},
		options = {
			OPTIONS,
			icon = "Interface/Icons/INV_Misc_Wrench_01",
			gw = InterfaceOptionsFrame,
			open = function()
				InterfaceOptionsFrame_Show()
			end
		},
		macro = {
			MACROS,
			icon = "Interface/Icons/INV_Misc_Note_06",
			gn = "MacroFrame",
			tmt = SLASH_MACRO1,
			cw = closeButton(MacroFrame)
		},
		gamemenu = {
			L "Game Menu",
			icon = "Interface/Icons/INV_Misc_Wrench_01",
			gw = GameMenuFrame,
			noduck = 1,
			pre = function()
				return not GameMenuFrame:IsShown() or nil
			end,
			post = function()
				RatingMenuFrame:Show()
				RatingMenuFrame:Hide()
				PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
			end
		},
		csp = {
			gw = InterfaceOptionsFrame,
			cpreamble = true,
			cw = closeButton(InterfaceOptionsFrame, "csp")
		},
		cgm = {
			gw = GameMenuFrame,
			cpreamble = true,
			cw = closeButton(GameMenuFrame, "cgm")
		}
	}
	do
		local exName = newWidgetName("AB:PX!")
		local clickEx = CLICK .. " " .. exName .. " "
		local cmdPrefix = clickEx
		local cmdDuckPrefix = cmdPrefix .. "csp 1\n" .. clickEx .. "cgm 1\n" .. clickEx
		local ex = CreateFrame("Button", exName, nil, "SecureActionButtonTemplate")
		ex:SetAttribute("type", "macro")
		local function isEnabled(w)
			local e = w:IsEnabled()
			return not not (e and e ~= 0)
		end
		local function prerun(k)
			local i, r = panels[k], 0
			local tw, gw, cw, cw2, ow, ofun = i.tw, i.gw, i.cw, i.cw2, i.ow, i.open
			if tw and not isEnabled(tw) then
				r = i.tcr and r + 1 or r;
				tw:Enable()
			end
			if cw or ow or ofun then
				local gh, cd, od = not (gw and gw:IsShown()), not (cw and isEnabled(cw)), not (ow and isEnabled(ow))
				if cw and gh ~= cd then
					r = r + (gh and 6 or 2);
					cw:SetEnabled(not gh)
				end
				if cw2 then
					r = r + (gh and 64 or 0);
					cw2:SetEnabled(not gh)
				end
				if ow and gh == od then
					r = r + (gh and 8 or 24);
					ow:SetEnabled(gh)
				end
				if ofun and gh == od then
					securecall(ofun, gw, k)
				end
			end
			return r ~= 0 and r or nil
		end
		local function postrun(k, m)
			local i, m1, m3, m5 = panels[k], m % 2, m % 8, m % 32
			if m5 >= 8 then
				i.ow:SetEnabled(m5 > 8)
			end
			if m3 >= 2 then
				i.cw:SetEnabled(m3 > 2)
			end
			if m >= 64 then
				i.cw2:SetEnabled(true)
			end
			if m1 >= 1 then
				i.tw:Disable()
			end
		end
		ex:SetScript("PreClick", function(_, b)
			local i = panels[b]
			if i and i.pre then
				i.postMessage = i.pre(b, i, prerun)
			end
		end)
		ex:SetScript("PostClick", function(_, b)
			local i, bp, pm = panels[b]
			bp = i and i.cpreamble and b or b:match("^post%-(.*)")
			i = panels[bp]
			pm = i and i.postMessage
			if pm ~= nil and i.post then
				i.postMessage = nil
				i.post(bp, pm, postrun)
			end
		end)
		local function prepareMacroText(k, v)
			local tmt = v.tmt
			if tmt then
				tmt = tmt:gsub("/click ", CLICK)
			elseif v.tw then
				tmt = widgetClickCommand(k, v.tw)
			elseif v.cw or v.ow then
				tmt = widgetClickCommand(k, v.ow) .. widgetClickCommand(k, v.cw)
				if v.cw2 then
					tmt = tmt .. widgetClickCommand(k, v.cw2)
				end
			end
			if v.tw or v.cw or v.ow or v.open then
				v.pre, v.post = v.pre or prerun, v.post or postrun
			end
			if tmt and v.postmt then
				tmt = tmt .. "\n" .. v.postmt
			end
			if v.post then
				tmt = tmt .. (tmt:sub(-1) ~= "\n" and "\n" or "") .. clickEx .. "post-" .. k
			end
			tmt = tmt and ((v.noduck and cmdPrefix or cmdDuckPrefix) .. k .. " 1\n" .. tmt)
			return tmt
		end
		local pmeta = {
			__index = function(t, k)
				local n, r = k == "gw" and t.gn
				if n then
					r = _G[n]
				elseif k == "mainText" then
					r = prepareMacroText(t.pk, t)
				end
				if k ~= nil then
					t[k] = r
				end
				return r
			end
		}
		for k, v in pairs(panels) do
			v.pk = k
			setmetatable(v, pmeta)
			if v.cpreamble and v.cw then
				ex:SetAttribute("type-" .. k, "click")
				ex:SetAttribute("clickbutton-" .. k, v.cw)
				v.pre, v.post = v.pre or prerun, v.post or postrun
			end
		end
	end
	do -- further panels init
		panels.options.cw = closeButton(InterfaceOptionsFrame)
		panels.macro.postmt = widgetClickCommand("cmf", panels.macro.cw)
		panels.gamemenu.cw = panels.cgm.cw
		function EV.ADDON_LOADED()
			if MacroFrame then
				panels.macro.cw:SetParent(MacroFrame)
				return "remove"
			end
		end
	end
	-- Force-evaluate mainText for all panels NOW (at load time, before PLAYER_ENTERING_WORLD).
	-- prepareMacroText calls py:SetAttribute — must happen before login to avoid taint.
	-- Tainted SecureActionButtonTemplate silently breaks all panel macro execution.
	for _k, _v in pairs(panels) do
		if _v and _v[1] and not _v.cpreamble then
			local _ = _v.mainText
		end
	end
	local function panelHint(tk)
		local i = panels[tk]
		if not i then
			return
		end
		local gw, icon, s = i.gw, i.icon, 0
		s = (gw and gw:IsVisible()) and s + 1 or s
		return true, s, icon, i[1]
	end
	local function createPanel(tk)
		local r = panelMap[tk]
		local pi = r == nil and panels[tk]
		if pi and pi[1] and pi.mainText and (pi.req == nil or pi.req()) then
			r = AB:CreateActionSlot(panelHint, tk, "macrotext", pi.mainText)
			panelMap[tk] = r
		end
		return r
	end
	local function describePanel(tk)
		local i = panels[tk]
		if i and i[1] then
			return L "Interface Panel", i[1], i.icon
		end
		return L "Interface Panel"
	end
	AB:RegisterActionType("uipanel", createPanel, describePanel, 1)
end)
