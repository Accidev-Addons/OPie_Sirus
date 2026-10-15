local _, T = ...
local CA = {}
T.compat = CA

local function shim(ns, fill)
	local native = _G[ns]
	local t = setmetatable({}, {
		__index = native
	})
	for k, v in pairs(fill) do
		if not (native and native[k]) then
			t[k] = v
		end
	end
	CA[ns] = t
end

-- C_Timer.After: Sirus calls it as colon method; Evie captures the reference before this file loads.
-- Patch via evie.raw rather than C_Timer.After to avoid tainting the global
-- (FrameXML reads C_Timer.After in secure paths → taint → SetTargetClampingInsets blocked).
do
	local pending = {}
	local sf = CreateFrame("Frame")
	sf:Hide()
	sf:SetScript("OnUpdate", function(_, dt)
		local now = GetTime()
		local i = 1
		while i <= #pending do
			local t = pending[i]
			if now >= t[1] then
				table.remove(pending, i)
				t[2]()
			else
				i = i + 1
			end
		end
		if #pending == 0 then
			sf:Hide()
		end
	end)
	local function safeAfter(a, b, c)
		local delay, fn
		if type(a) == "number" then
			delay, fn = a, b
		else
			delay, fn = b, c
		end
		if type(delay) == "number" and type(fn) == "function" then
			pending[#pending + 1] = {GetTime() + delay, fn}
			sf:Show()
		end
	end
	local evie = T.Evie and T.Evie.raw
	if type(evie) == "table" then
		evie.After = safeAfter
	end
end

shim("C_Widget", {
	IsFrameWidget = function(v)
		return type(v) == "table" and type(v[0]) == "userdata"
	end
})

CA.AreDangerousScriptsAllowed = AreDangerousScriptsAllowed or function()
	return true
end

shim("C_QuestLog", {
	IsQuestFlaggedCompleted = IsQuestFlaggedCompleted or function(qid)
		qid = tonumber(qid)
		return qid ~= nil and IsQuestCompleted(qid) or false
	end
})

shim("C_PetJournal", {
	IsCurrentlySummoned = C_PetJournal and C_PetJournal.GetSummonedPetID and function(guid)
		return guid ~= nil and C_PetJournal.GetSummonedPetID() == guid
	end or function()
		return false
	end,
	DismissSummonedPet = DismissCompanion and function()
		DismissCompanion("CRITTER")
	end or function()
	end,
	SummonPetByGUID = C_PetJournal and C_PetJournal.SummonPetByPetID or function()
	end,
	GetPetCooldownByGUID = function()
		return 0, 0, 1
	end
})

shim("C_ToyBox", {
	IsToyUsable = function()
		return true
	end
})

shim("C_MountJournal", {
	GetMountIDs = function()
		return {}
	end,
	GetMountInfoExtraByID = function()
		return nil
	end
})
-- force nil so mount spells route through the spell handler (GetSpellInfo/GetSpellTexture) instead

CA.FindSpellBookSlotBySpellID = FindSpellBookSlotBySpellID or function(spellID)
	if type(spellID) ~= "number" or spellID == 0 then
		return nil
	end
	for tab = 1, GetNumSpellTabs() do
		local _, _, offset, count = GetSpellTabInfo(tab)
		for i = offset + 1, offset + count do
			local link = GetSpellLink(i, "spell")
			local sid = link and tonumber(link:match("|Hspell:(%d+)"))
			if sid == spellID then
				return i
			end
		end
	end
end

CA.DoesSpellExist = DoesSpellExist or function(name)
	return not not (GetSpellInfo(name))
end

do
	local function iterSets()
		return GetNumEquipmentSets and GetNumEquipmentSets() or 0
	end
	CA.C_EquipmentSet = C_EquipmentSet or {
		GetEquipmentSetIDs = function()
			local ids = {}
			for i = 1, iterSets() do
				local _, _, id = GetEquipmentSetInfo(i)
				ids[i] = id
			end
			return ids
		end,
		GetEquipmentSetInfo = function(id)
			for i = 1, iterSets() do
				local name, icon, sid = GetEquipmentSetInfo(i)
				if sid == id then
					return name, icon
				end
			end
		end,
		GetEquipmentSetID = function(name)
			for i = 1, iterSets() do
				local n, _, id = GetEquipmentSetInfo(i)
				if n == name then
					return id
				end
			end
		end,
		UseEquipmentSet = function(id)
			local use, name = UseEquipmentSet
			for i = 1, iterSets() do
				local n, _, sid = GetEquipmentSetInfo(i)
				if sid == id then
					name = n
					break
				end
			end
			if use and name then
				use(name)
				return true
			end
			return false
		end
	}
end

CA.C_Minimap = C_Minimap or {
	GetNumTrackingTypes = GetNumTrackingTypes,
	GetTrackingInfo = function(id)
		local name, tex, active = GetTrackingInfo(id)
		if not name then
			return nil
		end
		return {
			name = name,
			texture = tex,
			active = active
		}
	end,
	SetTracking = function(id, enable)
		if SetTracking then
			SetTracking(enable and id or nil)
		end
	end
}

CA.C_KeyBindings = C_KeyBindings or {
	GetBindingByKey = GetBindingByKey or function()
		return nil
	end
}

CA.IsMetaKeyDown = IsMetaKeyDown or function()
	return false
end

CA.UnitFullName = UnitFullName or function(unit)
	local name = UnitName(unit)
	local realm = GetRealmName and GetRealmName() or ""
	return name, realm or ""
end

CA.strcmputf8i = strcmputf8i or function(a, b)
	local la, lb = (a or ""):lower(), (b or ""):lower()
	if la < lb then
		return -1
	elseif la > lb then
		return 1
	else
		return 0
	end
end

do
	local f = CreateFont("OPieFontNormalLargeOutline")
	local base = GameFontNormalLarge or GameFontNormal
	if base then
		local face, size = base:GetFont()
		f:SetFont(face, size or 12, "OUTLINE")
	end
end

CA.GetSpellBookItemName = GetSpellBookItemName or GetSpellName
CA.GetSpellBookItemInfo = GetSpellBookItemInfo or function(index, bookType)
	local link = GetSpellLink(index, bookType)
	local id = link and tonumber(link:match("|Hspell:(%d+)"))
	if id then
		return "SPELL", id
	end
end

CA.REVERT = REVERT or "Revert"

CA.IsSpecInfoReady = function()
	return not (C_GlobalStorage and C_GlobalStorage.GetVar) or C_GlobalStorage.GetVar("ASMSG_SPEC_INFO") ~= nil
end
