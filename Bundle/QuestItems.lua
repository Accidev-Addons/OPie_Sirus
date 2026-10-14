local ADDON, T = ...

local AB, ORI, EV, L, PC, XU, config, KR = T.ActionBook, OPie.UI, T.Evie, T.L, T.OPieCore, T.exUI, T.config, nil
AB, KR = AB and AB:compatible(2, 14), AB and AB:compatible("Kindred", 1, 34)
assert(ORI and EV and L and PC and XU and config and AB and KR, "Incompatible library bundle")
local GameTooltip = T.NotGameTooltip or GameTooltip
local TS, GFX = T.TenSettings, ([[Interface\AddOns\%s\gfx\]]):format(ADDON)
local C_QuestLog = T.compat.C_QuestLog

local exclude = PC:RegisterPVar("AutoQuestExclude", {})
local IsQuestItem
local function getContainerItemQuestInfo(bag, slot)
	if bag and slot then
		return GetContainerItemQuestInfo(bag, slot)
	end
end
do
	local include
	do
		local function have1()
			return true, false, false, 4
		end
		include = {
			[21746] = have1, -- lucky red envelope
			[33634] = true,
			[35797] = true,
			[37888] = true,
			[37860] = true,
			[37859] = true,
			[37815] = true,
			[46847] = true,
			[47030] = true,
			[39213] = true,
			[42986] = true,
			[49278] = true,
			[37586] = have1 -- handful of treats [hallow's end]
		}
	end
	function IsQuestItem(iid, bag, slot)
		if exclude[iid] or not iid then
			return false
		end
		local rcat
		local inc, isQuest, startQuestId, isQuestActive = include[iid], getContainerItemQuestInfo(bag, slot)
		isQuest = iid and ((isQuest and GetItemSpell(iid)) or (inc == true) or
					  (startQuestId and not isQuestActive and not C_QuestLog.IsQuestFlaggedCompleted(startQuestId)))
		if inc and not isQuest and type(inc) == "function" then
			isQuest, startQuestId, isQuestActive, rcat = inc(iid)
		end
		return isQuest, startQuestId and not isQuestActive, rcat
	end
end
local colId, current, changed, pendingChanges
local collection, inring, tokItemID, ctok = {
	__embed = true
}, {}, {}, 0
local addSlice, sortQICollection
do
	local tokCat, colOrder = {}, {}
	function addSlice(tok, cat, at, ...)
		if inring[tok] then
			inring[tok], tokCat[tok] = current, cat
		else
			local slot = AB:GetActionSlot(at, ...)
			if slot then
				inring[tok], tokCat[tok] = current, cat
				collection[#collection + 1], collection[tok], changed = tok, slot, true
				if at == "item" or at == "disenchant" then
					tokItemID[tok] = ...
				end
			end
		end
		return tok
	end
	local function cmpEntry(a, b)
		local ac, bc = tokCat[a], tokCat[b]
		if ac ~= bc then
			if (not ac) ~= (not bc) then
				return not ac
			end
			return ac < bc
		end
		return colOrder[a] < colOrder[b]
	end
	function sortQICollection()
		for i = 1, #collection do
			colOrder[collection[i]] = i
		end
		for k in pairs(tokCat) do
			if not inring[k] then
				tokCat[k], tokItemID[k] = nil
			end
		end
		table.sort(collection, cmpEntry)
	end
end
local function syncRing(_, event, upId)
	if event ~= "internal.collection.preopen" or upId ~= colId then
		return
	end
	changed, current = false, (ctok + 1) % 2

	local ns = GetContainerNumSlots
	local giid = GetContainerItemID
	for bag = 0, 4 do
		for slot = 1, ns(bag) or 0 do
			local iid = giid(bag, slot)
			local include, startsQuestMark, qiCat = IsQuestItem(iid, bag, slot)
			if include then
				local tok = addSlice("OPbQIi" .. iid, qiCat or 2, "item", iid)
				ORI:SetQuestHint(tok, startsQuestMark)
			end
		end
	end
	for i = 0, INVSLOT_LAST_EQUIPPED do
		local tok = "OPbQIi" .. (GetInventoryItemID("player", i) or 0)
		if inring[tok] then
			inring[tok] = current
		end
	end
	local freePos, oldCount = 1, #collection
	for i = freePos, oldCount do
		local v = collection[i]
		collection[freePos], freePos, collection[v], inring[v] = collection[i],
			freePos + (inring[v] == current and 1 or 0), (inring[v] == current and collection[v] or nil),
			inring[v] == current and current or nil
	end
	for i = oldCount, freePos, -1 do
		collection[i] = nil
	end
	changed, ctok = changed or freePos <= oldCount, current

	if changed then
		sortQICollection()
	end
	if not (changed or pendingChanges) then
	elseif InCombatLockdown() then
		pendingChanges = true
	else
		AB:UpdateActionSlot(colId, collection)
		pendingChanges = nil
	end
end
colId = AB:CreateActionSlot(nil, nil, "collection", collection)
AB:AddObserver("internal.collection.preopen", syncRing)
function EV.PLAYER_REGEN_DISABLED()
	syncRing(nil, "internal.collection.preopen", colId)
end

local function createQI(name)
	return name == 1 and colId or nil
end
local function describeQI(name)
	if name == 1 then
		return L "Quest Items", L "Quest Items", ([[Interface\AddOns\%s\gfx\opie_ring_icon]]):format(ADDON), nil, nil,
			nil, "collection"
	end
end
AB:RegisterActionType("opie.autoquest", createQI, describeQI, 1)

local edFrame = CreateFrame("Frame")
do
	edFrame:Hide()
	local clipRoot = CreateFrame("ScrollFrame", nil, edFrame)
	clipRoot:SetPoint("TOPLEFT", 0, -2)
	clipRoot:SetPoint("BOTTOMRIGHT", -20, 0)
	local clipContent = CreateFrame("Frame", nil, clipRoot)
	clipContent:SetSize(1, 26)
	clipRoot:SetScrollChild(clipContent)
	local clipOrigin = CreateFrame("Frame", nil, clipContent)
	clipOrigin:SetSize(0, 1)
	clipOrigin:SetPoint("TOPLEFT")
	local bar = XU:Create("ScrollBar", nil, edFrame)
	bar:SetPoint("TOPRIGHT", -1, 0)
	bar:SetPoint("BOTTOMRIGHT", -1, 0)
	bar:SetCoverTarget(clipRoot)

	local rows, controller, idList, numRowsPV, visibleRange = {}, {}, {}, 2, 0
	do
		clipRoot:SetScript("OnSizeChanged", function(self)
			clipOrigin:SetWidth(self:GetWidth() or clipOrigin:GetWidth() or 0)
			visibleRange = (self:GetHeight() + 2) / 26
			numRowsPV = 1 + math.ceil(visibleRange)
			clipContent:SetSize(self:GetWidth() or 1, 26 * numRowsPV)
			bar:SetWindowRange(visibleRange)
			bar:SetStepsPerPage(math.max(1, numRowsPV - 5))
			bar:SetMinMaxValues(0, controller:GetNumRows() - visibleRange)
			bar:SetShown(select(2, bar:GetMinMaxValues()) > 0)
			controller:SetOffset(bar:GetValue(), nil)
		end)
		edFrame:SetScript("OnMouseWheel", function(_, delta)
			bar:Step(-delta * math.max(1, math.ceil(numRowsPV / 4)), true)
		end)
		bar:SetScript("OnValueChanged", function(_, nv, isInternal)
			controller:SetOffset(nv, isInternal)
		end)
		edFrame:SetScript("OnEvent", function(_, e, iid, ok)
			if e == "ITEM_DATA_LOAD_RESULT" and iid and ok then
				controller:CheckPendingItemIDs()
			end
		end)
	end

	function controller:NewRow(idx)
		local x, t = CreateFrame("Button", nil, clipContent, nil, idx)
		x:SetPoint("TOPLEFT", clipOrigin, 0, 26 - 26 * idx)
		x:SetPoint("TOPRIGHT", clipOrigin, 0, 26 - 26 * idx)
		x:SetHeight(24)
		x:SetText(" ")
		x:SetNormalFontObject(GameFontNormalMed2)
		x:SetHighlightFontObject(GameFontHighlightMed2)
		t = x:CreateTexture(nil, "ARTWORK")
		t:SetPoint("LEFT", 34, 0)
		t:SetTexture("Interface/Icons/Temp")
		t:SetSize(24, 24)
		t, x.Icon = x:GetFontString(), t
		t:ClearAllPoints()
		t:SetPoint("LEFT", 64, 0)
		t:SetPoint("RIGHT", -2, 0)
		t:SetHeight(20)
		t:SetJustifyH("LEFT")
		t, x.Text = x:CreateTexture(nil, "ARTWORK", nil, 0), t
		t:SetTexture(TS.SKIN.btn[1], TS.SKIN.btn[2], TS.SKIN.btn[3], 1)
		t:SetSize(16, 16)
		t:SetPoint("LEFT", 4, 0)
		local checkBox = t
		for i = 1, 4 do
			local e = x:CreateTexture(nil, "ARTWORK", nil, 1)
			e:SetTexture(TS.SKIN.edge[1], TS.SKIN.edge[2], TS.SKIN.edge[3], 1)
			if i < 3 then
				e:SetHeight(1)
				e:SetPoint("LEFT", checkBox, "LEFT")
				e:SetPoint("RIGHT", checkBox, "RIGHT")
				e:SetPoint(i == 1 and "TOP" or "BOTTOM", checkBox, i == 1 and "TOP" or "BOTTOM")
			else
				e:SetWidth(1)
				e:SetPoint("TOP", checkBox, "TOP")
				e:SetPoint("BOTTOM", checkBox, "BOTTOM")
				e:SetPoint(i == 3 and "LEFT" or "RIGHT", checkBox, i == 3 and "LEFT" or "RIGHT")
			end
		end
		t = x:CreateTexture(nil, "ARTWORK", nil, 2)
		t:SetTexture(GFX .. "check.tga")
		t:SetVertexColor(TS.SKIN.accent[1], TS.SKIN.accent[2], TS.SKIN.accent[3])
		t:SetSize(12, 12)
		t:SetPoint("CENTER", checkBox, "CENTER")
		x.Mark = t
		x:SetScript("OnClick", controller.OnRowClick)
		x:SetScript("OnEnter", controller.OnRowEnter)
		x:SetScript("OnLeave", controller.OnRowLeave)
		return x
	end
	function controller:SetRow(w, idx)
		local iid = idList[idx]
		if not (iid and w) then
			return w and w:Hide()
		end
		local n, _, _iq, _, _, _, _, _, _, ico = GetItemInfo(iid or 0)
		if n then
			w.pendingItemID = nil
		else
			w.pendingItemID, n, ico = iid, "item:" .. iid, select(10, GetItemInfo(iid or 0))
		end
		w.Text:SetText(n)
		w.Icon:SetTexture(ico)
		w.Mark:SetShown(not exclude[iid])
		w:SetID(idx)
		w:Show()
	end
	function controller.OnRowClick(w)
		local nv = not w.Mark:IsShown()
		w.Mark:SetShown(nv)
		PlaySound(SOUNDKIT[nv and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF"])
		local iid = idList[w:GetID()]
		if not config.undo:search("opie.autoquest.state") then
			controller:SaveState()
		end
		exclude[iid] = nv ~= true or nil
	end
	function controller.OnRowEnter(w)
		local iid = idList[w:GetID()]
		if iid then
			GameTooltip:SetOwner(w, "ANCHOR_NONE")
			GameTooltip:SetPoint("TOPRIGHT", w, "TOPLEFT", -4, 4)
			GameTooltip:SetHyperlink("item:" .. iid)
			GameTooltip:Show()
		end
	end
	controller.OnRowLeave = config.ui.HideTooltip
	function controller:SetOffset(nv, _isInternal)
		local fv = nv % 1
		clipRoot:SetVerticalScroll(26 * fv)
		local ofs, hadPendingGIIR = nv - fv, false
		for i = 1, numRowsPV do
			local w = rows[i] or controller:NewRow(i)
			controller:SetRow(w, i + ofs)
			rows[i], hadPendingGIIR = w, hadPendingGIIR or w and w.pendingItemID
		end
		for i = numRowsPV + 1, #rows do
			rows[i]:Hide()
		end
		edFrame[hadPendingGIIR and "RegisterEvent" or "UnregisterEvent"](edFrame, "ITEM_DATA_LOAD_RESULT")
	end
	function controller:GetNumRows()
		return #idList
	end

	function controller.CheckPendingItemIDs()
		local allDone = 1
		for i = 1, numRowsPV do
			local pid = rows[i].pendingItemID
			local n = pid and GetItemInfo(pid)
			allDone = allDone and (n or not pid)
			if n then
				rows[i].pendingItemID = nil
				rows[i].Text:SetText(n)
			end
		end
		if allDone or not edFrame:IsVisible() then
			edFrame:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
			edFrame:SetScript("OnShow", not allDone and controller.CheckPendingItemIDs or nil)
		end
	end
	function controller:SaveState()
		local clone = {}
		for k, v in pairs(exclude) do
			clone[k] = v
		end
		config.undo:push("opie.autoquest.state", controller.RestoreState, clone)
	end
	function controller.RestoreState(msg, clone)
		if msg == "archive-unwind" then
			controller:SaveState()
		end
		wipe(exclude)
		for k, v in pairs(clone) do
			exclude[k] = v
		end
	end

	function edFrame:SetAction(owner, _action)
		local op = edFrame:GetParent()
		if op and op ~= owner and type(op.OnEditorRelease) == "function" then
			securecall(op.OnEditorRelease, op, self)
		end
		edFrame:SetParent(nil)
		edFrame:ClearAllPoints()
		edFrame:SetAllPoints(owner)
		edFrame:SetParent(owner)
		do -- load data
			local ni, nj = 1, 0
			wipe(idList)
			syncRing(nil, "internal.collection.preopen", colId)
			for iid, ex in pairs(exclude) do
				idList[ni], ni = ex and iid, ex and ni + 1 or ni
			end
			table.sort(idList)
			for i = #collection, 1, -1 do
				local iid = tokItemID[collection[i]]
				idList[nj], nj = iid, iid and nj - 1 or nj
			end
			for i = nj < 0 and ni - nj - 1 or 0, 1 + nj, -1 do
				idList[i] = idList[i + nj]
			end
			bar:SetMinMaxValues(0, #idList - visibleRange)
		end
		edFrame:Show()
		edFrame:GetLeft()
		bar:SetValue(0)
		controller:SetOffset(0)
	end
	function edFrame:GetAction(into)
		into[1], into[2] = "opie.autoquest", 1
	end
	function edFrame:Release(owner)
		if edFrame:IsOwned(owner) then
			edFrame:SetParent(nil)
			edFrame:ClearAllPoints()
			edFrame:Hide()
		end
	end
	function edFrame:IsOwned(owner)
		return edFrame:GetParent() == owner
	end
	AB:RegisterEditorPanel("opie.autoquest", edFrame)
end

local function excludeItemID(iid)
	if iid > 0 then
		exclude[iid] = true
	else
		exclude[-iid] = nil
	end
end
T.AddSlashSuffix(function(msg)
	local args = msg:match("^%s*%S+%s*(.*)$")
	if args:match("^[%d%s%-]+$") then
		for iid in args:gmatch("[%-]?%d+") do
			excludeItemID(tonumber(iid))
		end
	else
		local flag, _, link
		flag, args = args:match("^(%-?)(.*)$")
		_, link = GetItemInfo(args:match("|H(item:%d+)") or args)
		local iid = link and link:match("item:(%d+)")
		if iid then
			excludeItemID(tonumber(iid) * (flag == "-" and -1 or 1))
		end
	end
end, "exclude-quest-item")
