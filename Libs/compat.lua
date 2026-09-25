local _, T = ...

-- frame metatable — only SetAttributeNoHandler; other retail methods intentionally omitted
-- (Lua closures in frame metatable are tainted, propagating via NamePlate secure thread)
do
	local f = CreateFrame("Frame")
	local mt = getmetatable(f)
	local idx = mt and type(mt.__index) == "table" and mt.__index
	if idx and not idx.SetAttributeNoHandler then
		idx.SetAttributeNoHandler = idx.SetAttribute
	end
	f = nil
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

if not C_Widget then
	C_Widget = {}
end
if not C_Widget.IsFrameWidget then
	C_Widget.IsFrameWidget = function(v)
		return type(v) == "table" and type(v[0]) == "userdata"
	end
end

if not AreDangerousScriptsAllowed then
	AreDangerousScriptsAllowed = function()
		return true
	end
end

if not C_QuestLog then
	C_QuestLog = {
		IsQuestFlaggedCompleted = IsQuestFlaggedCompleted or function(qid)
			qid = tonumber(qid)
			return qid ~= nil and IsQuestCompleted(qid) or false
		end
	}
end

if not C_PetJournal then
	C_PetJournal = {}
end
if not C_PetJournal.IsCurrentlySummoned then
	C_PetJournal.IsCurrentlySummoned = C_PetJournal.GetSummonedPetID and function(guid)
		return guid ~= nil and C_PetJournal.GetSummonedPetID() == guid
	end or function()
		return false
	end
end
if not C_PetJournal.DismissSummonedPet then
	C_PetJournal.DismissSummonedPet = DismissCompanion and function()
		DismissCompanion("CRITTER")
	end or function()
	end
end
if not C_PetJournal.SummonPetByGUID then
	C_PetJournal.SummonPetByGUID = C_PetJournal.SummonPetByPetID or function()
	end
end
if not C_PetJournal.GetPetCooldownByGUID then
	C_PetJournal.GetPetCooldownByGUID = function()
		return 0, 0, 1
	end
end

if not C_ToyBox then
	C_ToyBox = {}
end
if not C_ToyBox.IsToyUsable then
	C_ToyBox.IsToyUsable = function()
		return true
	end
end

if not C_MountJournal then
	C_MountJournal = {}
end
if not C_MountJournal.GetMountIDs then
	C_MountJournal.GetMountIDs = function()
		return {}
	end
end
if not C_MountJournal.GetMountInfoExtraByID then
	C_MountJournal.GetMountInfoExtraByID = function()
		return nil
	end
end
-- force nil so mount spells route through the spell handler (GetSpellInfo/GetSpellTexture) instead

if not FindSpellBookSlotBySpellID then
	FindSpellBookSlotBySpellID = function(spellID)
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
end

if not DoesSpellExist then
	DoesSpellExist = function(name)
		return not not (GetSpellInfo(name))
	end
end

if not C_EquipmentSet then
	local function iterSets()
		return GetNumEquipmentSets and GetNumEquipmentSets() or 0
	end
	C_EquipmentSet = {
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

if not C_Minimap then
	C_Minimap = {
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
end

if not C_KeyBindings then
	C_KeyBindings = {
		GetBindingByKey = GetBindingByKey or function()
			return nil
		end
	}
end

if not IsMetaKeyDown then
	IsMetaKeyDown = function()
		return false
	end
end


if RAID_CLASS_COLORS then
	for _, c in pairs(RAID_CLASS_COLORS) do
		if not c.colorStr and c.r then
			c.colorStr = string.format("ff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5),
				math.floor(c.b * 255 + 0.5))
		end
	end
end

if not UnitFullName then
	UnitFullName = function(unit)
		local name = UnitName(unit)
		local realm = GetRealmName and GetRealmName() or ""
		return name, realm or ""
	end
end

if not strcmputf8i then
	strcmputf8i = function(a, b)
		local la, lb = (a or ""):lower(), (b or ""):lower()
		if la < lb then
			return -1
		elseif la > lb then
			return 1
		else
			return 0
		end
	end
end

do
	if not GameFontNormalLargeOutline then
		local f = CreateFont("GameFontNormalLargeOutline")
		local base = GameFontNormalLarge or GameFontNormal
		if base then
			local face, size = base:GetFont()
			f:SetFont(face, size or 12, "OUTLINE")
		end
	end
end

if not GetSpellBookItemName then
	GetSpellBookItemName = GetSpellName
end
if not GetSpellBookItemInfo then
	GetSpellBookItemInfo = function(index, bookType)
		local link = GetSpellLink(index, bookType)
		local id = link and tonumber(link:match("|Hspell:(%d+)"))
		if id then
			return "SPELL", id
		end
	end
end

if not REVERT then
	REVERT = "Revert"
end
