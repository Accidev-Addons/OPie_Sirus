local MAJ, REV, SVREV, ADDON, T, ORI = 4, 141, 122, ...
local EV, api, private = T.Evie, {
	ActionBook = T.ActionBook
}, {}
local OR_Rings, OR_LoadedState, OR_ModifierLockState = {}, 1, nil
local defaultConfig = {
	InteractionMode = 1,
	ClickPriority = true,
	NoClose = false,
	NoCloseOnSlice = false,
	ReOpenAction = 2,
	IndicationOffsetX = 0,
	IndicationOffsetY = 0,
	RingAtMouse = false,
	RingScale = 1,
	CenterAction = false,
	MotionAction = false,
	QuickActionOnRelease = true,
	CloseOnRelease = false,
	RunBindingsOnDown = false,
	MouseBucket = 1,
	PerCharRotationStore = false,
	UseDefaultBindings = true,
	PrimaryButton = "BUTTON4",
	SecondaryButton = "BUTTON5",
	SliceBinding = false,
	SliceBindingString = "1 2 3 4 5 6 7 8 9 0",
	OpenNestedRingButton = "BUTTON3",
	ScrollNestedRingUpButton = "MOUSEWHEELUP",
	ScrollNestedRingDownButton = "MOUSEWHEELDOWN",
	OpenNestedRingButton2 = "",
	ScrollNestedRingUpButton2 = "",
	ScrollNestedRingDownButton2 = "",
	SelectedSliceBind = "",
	SelectedSliceBind2 = "",
	SelectedCloseBind = "",
	SelectedCloseBind2 = "",
	CloseRingBind = "",
	CloseRingBind2 = ""
}
local configRoot, configInstance, activeProfile, PersistentStorageInfo, optionValidators = {
	CharProfiles = {},
	ProfileStorage = {},
	PersistentStorage = {}
}, nil, nil, {}, {}
local charId, internalFreeId = ("%s-%s"):format(GetRealmName(), UnitName("player")), 424
local RING_ICON = ([[Interface\AddOns\%s\gfx\opie_ring_icon]]):format(ADDON)

local L
do
	local TL = T.L or {}
	T.L = newproxy(true)
	L, getmetatable(T.L).__call = T.L, function(_, k, t)
		return TL[k] or t or k
	end
end
if T.PKT ~= 1645127413 then
	return EV.After(1, function()
		print("|cffe82020" ..
				  L "Restart World of Warcraft. If this message continues to appear, delete and re-install OPie.")
	end)
end

local WR, AB, KR, RW = T.Ware, T.ActionBook:compatible(2, 42), T.ActionBook:compatible("Kindred", 1, 11),
	T.ActionBook:compatible("Rewire", 1, 31)
do
	local function createRingAction(name)
		local ringInfo = type(name) == "string" and OR_Rings[name]
		return ringInfo and ringInfo.action or nil
	end
	local function describeRingAction(name)
		return L "OPie Ring", OR_Rings[name] and OR_Rings[name].name or name, RING_ICON, nil, nil, nil, "collection"
	end
	AB:RegisterActionType("ring", createRingAction, describeRingAction, 1)
	AB:AugmentCategory(L "OPie rings", function(_, add)
		for i = 1, #OR_Rings do
			add("ring", OR_Rings[i])
		end
	end)
end

local function assert(condition, text, level, ...)
	return condition or error(tostring(text):format(...), 1 + (level or 1))((0)[0])
end
local function copy(t, copies, into)
	copies, into = copies or {}, into or {}
	copies[t] = into
	for k, v in pairs(t) do
		k = type(k) == "table" and (copies[k] or copy(k, copies)) or k
		v = type(v) == "table" and (copies[v] or copy(v, copies)) or v
		into[k] = v
	end
	return into
end
local function getSpecCharIdent(specIdx)
	local tg = specIdx or GetActiveTalentGroup() or 1
	return (tg == 1 and "%s" or "%s-%d"):format(charId, tg)
end
local function getNumSpecs()
	return math.max(2, GetNumTalentGroups and GetNumTalentGroups() or 2)
end
local function getProfile(k)
	k = configRoot.ProfileStorage[k] and k or "default"
	return k, configRoot.ProfileStorage[k]
end
local function getProfileForSpec(specIdx)
	return getProfile(configRoot.CharProfiles[getSpecCharIdent(specIdx)])
end
local function normalizeStoredProfileIdent(ident)
	return ident ~= "default" and ident or nil
end
local registerExtAction
do
	local cf, df = {}, {}
	local function nop()
	end
	local function createExtAction(ident, ...)
		return (cf[ident] or nop)(ident, ...)
	end
	local function describeExtAction(ident, ...)
		return (df[ident] or nop)(ident, ...)
	end
	AB:RegisterActionType("opie.ext", createExtAction, describeExtAction, 2)
	function registerExtAction(ident, createFunc, describeFunc)
		assert(cf[ident] == nil, 'Identifier already registered: %q', 2, ident)
		cf[ident], df[ident] = createFunc, describeFunc
	end
end

local coreName = ("OPieRT-%08x-%04x"):format(time() % 2 ^ 30, math.random(2 ^ 16) - 1)
local OR_SecCore = CreateFrame("Button", coreName, UIParent,
	"SecureActionButtonTemplate,SecureHandlerAttributeTemplate,SecureHandlerMouseWheelTemplate")
local coreEnvW = WR.GetRestrictedEnvironment(OR_SecCore)
local OR_OpenProxy = CreateFrame("Button", "ORLOpen", nil, "SecureActionButtonTemplate")
local SLICE_BIND_PATTERN = "^CLICK " .. coreName:gsub("[-.*+()%[%]?%%]", "%%%0") .. ":slice(%d+)b?$"
local OR_ActiveRingName, OR_ActiveCollectionID, OR_ActiveSliceCount, activeProfileRE
local sfDelQueue, sfGlobalOptions, sfRingsAll, sfRingsOne, sfBindsAll, sfBindsOne
OR_SecCore:SetSize(2 ^ 15, 2 ^ 15)
OR_SecCore:SetFrameStrata("FULLSCREEN_DIALOG")
OR_SecCore:RegisterForClicks("AnyUp", "AnyDown")
OR_SecCore:SetAttribute("downbutton", true)
OR_SecCore:EnableMouseWheel(true)
OR_SecCore:Hide()
OR_SecCore:SetFrameRef("AB", AB:seclib())
OR_SecCore:SetFrameRef("KR", KR:seclib())
OR_SecCore:SetFrameRef("RW", RW:seclib())
local OR_RingBindingProxy
do -- + Click dispatcher
	local lowCH = CreateFrame("Button", ("OPieLBC-%08x-%04x"):format(time() % 2 ^ 30, math.random(2 ^ 16) - 1), nil,
		"SecureActionButtonTemplate")
	lowCH:SetFrameStrata("BACKGROUND")
	lowCH:SetFrameLevel(1)
	lowCH:RegisterForClicks("AnyDown", "AnyUp")
	lowCH:SetAllPoints()
	lowCH:Hide()
	OR_SecCore:WrapScript(lowCH, "OnClick", "return owner:RunFor(self, ORL_OnClick, button, down)",
		"owner:RunFor(self, ORL_PostClick, message)")
	OR_RingBindingProxy = CreateFrame("Frame", "ORL_BindProxy", nil, "SecureFrameTemplate")
	OR_SecCore:SetFrameRef("bindProxy", OR_RingBindingProxy)
	OR_SecCore:SetFrameRef("sliceBindProxy", CreateFrame("Frame", "ORL_BindProxySlice", nil, "SecureFrameTemplate"))
	OR_SecCore:SetFrameRef("overBindProxy", CreateFrame("Frame", "ORL_BindProxyOverride", nil, "SecureFrameTemplate"))
	OR_SecCore:SetFrameRef("lowCH", lowCH)
	OR_SecCore:SetFrameRef("screen", CreateFrame("Frame", nil, nil, "SecureFrameTemplate"))
	local closeProxy = CreateFrame("Button", "CloseOPieRing", nil, "SecureFrameTemplate")
	closeProxy:Hide()
	do -- Motion Trap
		local trap = CreateFrame("Frame", nil, nil, "SecureFrameTemplate")
		trap:SetFrameStrata("TOOLTIP")
		trap:SetAllPoints()
		trap:Hide()
		OR_SecCore:SetFrameRef("motion0", trap)
		for i = 1, 2 do
			local f = CreateFrame("Frame", nil, trap, "SecureFrameTemplate")
			f:SetSize(1 / 8, 1 / 8)
			f:SetFrameLevel(9001)
			f:EnableMouse(true)
			OR_SecCore:WrapScript(f, "OnLeave", "return owner:Run(ORL_SetMotionTrapArmed, false, true)")
			OR_SecCore:SetFrameRef("motion" .. i, f)
		end
	end
	OR_SecCore:Execute([=[-- OR_SecCore_Init
		AB, KR, RW = self:GetFrameRef("AB"), self:GetFrameRef("KR"), self:GetFrameRef("RW")
		UIParent = self:GetParent()
		ORL_GlobalOptions, ORL_RingData, ORL_RingDataN = newtable(), newtable(), newtable()
		ORL_KnownCollections, ORL_StoredCA, ORL_OverSAB = newtable(), newtable(), nil
		POL_RUN_ONOPEN_ON_SWITCH, POL_RUN_ONOPEN_ON_REOPEN, POL_JUMP_COUNT_LIMIT = true, true, 50
		POL_SWITCHED_FAST_ACTION, POL_SWICHED_FAST_ACTION_MOTION = true, true
		collections, ctokens, rotation, rtokens, fcIgnore, rotationMode, emptyTable = newtable(), newtable(), newtable(), newtable(), newtable(), newtable(), newtable()
		modState, modLockState, sizeSq, bindProxy, sliceProxy, overProxy = "", nil, 2^30, self:GetFrameRef("bindProxy"), self:GetFrameRef("sliceBindProxy"), self:GetFrameRef("overBindProxy")
		ALL_MODIFIERS = "ALT-CTRL-SHIFT-META-"
		lowCH = self:GetFrameRef("lowCH")
		sliceBindState, visitedSlices, buttonBindings = newtable(), newtable(), newtable()
		BUTTON_NAMEKEY_MAP = newtable()
		BUTTON_NAMEKEY_MAP.LeftButton, BUTTON_NAMEKEY_MAP.RightButton, BUTTON_NAMEKEY_MAP.MiddleButton = "BUTTON1", "BUTTON2", "BUTTON3"
		BUTTON_NAMEKEY_MAP.Button4, BUTTON_NAMEKEY_MAP.Button5 = "BUTTON4", "BUTTON5"
		NESTED_SCROLL_BIND_OPTS = newtable("ScrollNestedRingDownBinding", "ScrollNestedRingDownBinding2", "ScrollNestedRingUpBinding", "ScrollNestedRingUpBinding2")
		AIP_Binding, AIP_Key, AIP_Modifier, AIP_Handler, AIP_VirtualKey, AI_NoPointer = nil
		AIP_Action, AI_LeftAction, AI_RightAction, AIP_ActionFirstUp = nil
		AIP_OnDown, AI_LeftOnDown, AI_RightOnDown = nil
		AI_MotionArmed, AI_MotionArmedFC = false, false
		AI_ClickStack, AI_ClickStackIndex = newtable(), 0
		SCREEN, CENTERED_CURSOR_YPOS, MOTION_TRAP = self:GetFrameRef("screen"), 0.6, newtable()
		SCREEN:SetAllPoints()
		SCREEN:Hide()
		for i=0,2 do
			MOTION_TRAP[i] = self:GetFrameRef("motion" .. i)
		end
		pmode_RotationModeMap = newtable() do
			local m = pmode_RotationModeMap
			m[20] = "cycle"
			m[36] = "shuffle"
			m[52] = "random"
			m[68] = "reset"
			m[84] = "jump"
		end
		bindOverrides = newtable()

		ORL_RegisterOverride = [==[-- ORL_RegisterOverride
			local id, bind = ...
			if bindOverrides[id] then overProxy:ClearBinding(bindOverrides[id]) end
			if bindOverrides[bind] then bindOverrides[ bindOverrides[bind] ] = nil end
			if bind then
				overProxy:SetBindingClick(true, bind, self:GetFrameRef("proxy" .. id), "ro" .. id)
				bindOverrides[bind] = id
			end
			bindOverrides[id] = bind
		]==]
		ORL_SetMotionTrapArmed = [==[-- ORL_SetMotionTrapArmed
			local arm, armFC = ...
			if not arm then
				MOTION_TRAP[0]:Hide()
				AI_MotionArmed, AI_MotionArmedFC = false, false
				if armFC and AI_LeftAction then
					bindProxy:SetBindingClick(true, "BUTTON1", owner, "BUTTON1")
					lowCH:Hide()
				end
				return
			end
			local x, y = SCREEN:GetMousePosition()
			local w, h = SCREEN:GetWidth(), SCREEN:GetHeight()
			x, y = x*w, y*h
			for i=1,2 do
				MOTION_TRAP[i]:ClearAllPoints()
			end
			MOTION_TRAP[1]:SetPoint("CENTER", SCREEN, "BOTTOM", 0, h * CENTERED_CURSOR_YPOS)
			MOTION_TRAP[2]:SetPoint("CENTER", SCREEN, "BOTTOMLEFT", x, y)
			MOTION_TRAP[0]:Show()
			AI_MotionArmed, AI_MotionArmedFC = true, armFC == true
		]==]
		ORL_PrepareCollection = [==[-- ORL_PrepareCollection
			wipe(collections) wipe(ctokens)
			local firstFC, root, colData = nil, ..., AB:RunAttribute("GetCollectionContent", ...)
			for cid, i, aid, tok, pmode in (colData or ""):gmatch("\n(%d+) (%d+) (%d+) (%S+) (%d+)") do
				cid, i, aid, pmode = tonumber(cid), tonumber(i), tonumber(aid), tonumber(pmode) or 0
				if not collections[cid] then collections[cid], ctokens[cid] = newtable(), newtable() end
				if pmode > 0 then
					local b01 = pmode % 4
					fcIgnore[tok] = b01 >= 2 or nil
					if pmode % 8 >= 4 then
						rotationMode[tok] = pmode_RotationModeMap[pmode % 128 - b01]
					end
				end
				firstFC = firstFC or (cid == root and not fcIgnore[tok] and tok)
				collections[cid][i], ctokens[cid][i], ctokens[cid][tok] = aid, tok, i
			end
			collections[root], ctokens[root] = collections[root] or emptyTable, ctokens[root] or emptyTable
			for cid, list in pairs(collections) do
				for i, aid in pairs(list) do
					if collections[aid] then
						local tok = ctokens[cid][i]
						local rMode, rIdx, tIdx = rotationMode[tok]
						local isStoredRotation = rMode ~= "reset" and rMode ~= "jump"
						if isStoredRotation then
							rIdx = ctokens[aid][rtokens[tok]]
							if (rMode == "random" or rMode == "shuffle" and not rIdx) and #ctokens[aid] > 1 then
								tIdx = math.random(#ctokens[aid] - (rIdx and 1 or 0))
								rIdx = rIdx and tIdx >= rIdx and (tIdx + 1) or tIdx
							end
						end
						rotation[tok], rtokens[tok] = rIdx or 1, isStoredRotation and ctokens[aid][rIdx] or rtokens[tok] or nil
					end
				end
			end
			return collections[root][0], firstFC
		]==]
		ORL_CloseActiveRing = [[-- ORL_CloseActiveRing
			local old, shouldKeepOwner, selSliceIndex, selSliceAction = activeRing, ...
			if not shouldKeepOwner then
				owner:Hide()
			end
			bindProxy:ClearBindings()
			sliceProxy:ClearBindings()
			activeRing, openCollection, openCollectionID = nil
			AIP_Action, AIP_ActionFirstUp, AI_LeftAction, AI_RightAction = nil
			AIP_OnDown, AI_LeftOnDown, AI_RightOnDown = nil
			AIP_Binding, AIP_Key, AIP_Modifier, AIP_Handler, AIP_VirtualKey = nil
			self:Run(ORL_SetMotionTrapArmed, false)
			lowCH:Hide()
			owner:CallMethod("NotifyState", "close", old.name, old.action, selSliceIndex, selSliceAction)
		]]
		ORL_RegisterVariations = [[-- ORL_RegisterVariations
			local binding, mapkey, downmix, skipKey = ...
			local bindKey = binding and binding:match("[^-]*.$")
			if skipKey and bindKey == skipKey or (binding or "") == "" then
				AIP_IntBindCollide = AIP_IntBindCollide or (skipKey and bindKey == skipKey)
				return
			end
			if bindKey:match("^BUTTON%d+$") then
				buttonBindings[binding] = mapkey
			end
			local hA, hC, hS, hM = downmix:match("ALT") and 1 or 0, downmix:match("CTRL") and 1 or 0, downmix:match("SHIFT") and 1 or 0, downmix:match("META") and 1 or 0
			local lA, lC, lS, lM = binding:match("ALT%-") and 1 or 0, binding:match("CTRL%-") and 1 or 0, binding:match("SHIFT%-") and 1 or 0, binding:match("META%-") and 1 or 0
			hA, hC, hS, hM = hA < lA and lA or hA, hC < lC and lC or hC, hS < lS and lS or hS, hM < lM and lM or hM
			for alt=lA,hA do for ctrl=lC,hC do for shift=lS,hS do for meta=lM,hM do
				self:SetBindingClick(true, (alt == 1 and "ALT-" or "") .. (ctrl == 1 and "CTRL-" or "") .. (shift == 1 and "SHIFT-" or "") .. (meta == 1 and "META-" or "") .. bindKey, owner, mapkey)
			end end end end
		]]
		ORL_CheckSliceBindings = [==[-- ORL_CheckSliceBindings
			local usedKeys, uncombine, sb = newtable(), false, newtable()
			sb[0], sb[-1], sb[-2], sb[-3], sb[-4], sb[-5] = ...
			for j=0, 1 do
				for i, b in pairs(j == 0 and sb or
								  j >  0 and activeRing.SliceBinding or emptyTable) do
					local bk = b and b:match("[^-]*.$")
					local uk = usedKeys[bk]
					if uk then
						uncombine = uncombine or newtable()
						uncombine[uk], uncombine[i] = 1, 1
					else
						usedKeys[bk or 0] = i
					end
				end
			end
			activeRing.SliceBindingUncombine = uncombine
			return uncombine and true
		]==]
		ORL_UpdateInteractionBindings2 = [==[-- ORL_UpdateInteractionBindings2
			local avoidPrimary = ...
			local down, up, open = ORL_GlobalOptions.ScrollNestedRingDownBinding or "", ORL_GlobalOptions.ScrollNestedRingUpBinding or "", ORL_GlobalOptions.OpenNestedRingBinding or ""
			local down2, up2, open2 = ORL_GlobalOptions.ScrollNestedRingDownBinding2 or "", ORL_GlobalOptions.ScrollNestedRingUpBinding2 or "", ORL_GlobalOptions.OpenNestedRingBinding2 or ""
			AIP_IntBindCollide = false
			owner:RunFor(bindProxy, ORL_RegisterVariations, down, down:match("MOUSEWHEEL") and "mwdownW" or "mwdownK", ALL_MODIFIERS, avoidPrimary)
			owner:RunFor(bindProxy, ORL_RegisterVariations, down2, down2:match("MOUSEWHEEL") and "mwdownW" or "mwdownK", ALL_MODIFIERS, avoidPrimary)
			owner:RunFor(bindProxy, ORL_RegisterVariations, up, up:match("MOUSEWHEEL") and "mwupW" or "mwupK", ALL_MODIFIERS, avoidPrimary)
			owner:RunFor(bindProxy, ORL_RegisterVariations, up2, up2:match("MOUSEWHEEL") and "mwupW" or "mwupK", ALL_MODIFIERS, avoidPrimary)
			owner:RunFor(bindProxy, ORL_RegisterVariations, open, "mwin", ALL_MODIFIERS, avoidPrimary)
			owner:RunFor(bindProxy, ORL_RegisterVariations, open2, "mwin", ALL_MODIFIERS, avoidPrimary)
		]==]
		ORL_UpdateInteractionBindings = [==[-- ORL_UpdateInteractionBindings
			local setToVirtualKey = ...

			local interactKey = AIP_Binding == "-" and "-" or (AIP_Binding or ""):match("[^-]*.$")
			if setToVirtualKey then
				AIP_Binding, AIP_Key, AIP_Modifier, AIP_Handler, AIP_VirtualKey =
				   AIP_Binding, interactKey, interactKey ~= AIP_Binding and AIP_Binding or nil, self, setToVirtualKey
			end

			bindProxy:ClearBindings()
			wipe(buttonBindings)
			wheelBucket = 0

			local a1, a2 = (AIP_Action and AIP_Action ~= "close"), (AIP_ActionFirstUp and AIP_ActionFirstUp ~= "close")
			owner:Run(ORL_UpdateInteractionBindings2, (a1 or a2) and interactKey or nil)
			AIP_IntBindCollide = AIP_IntBindCollide and a2 and not a1

			sliceProxy:ClearBindings()
			wipe(sliceBindState)
			local sliceBindings, uncombine = activeRing.SliceBinding or false, nil
			local prefix = AIP_Action and AIP_Binding and AIP_Binding:match("^(.-)[^-]*%-?$") or ""
			local ukBinding, ukBinding2 = activeRing.SelectedSliceBind or "", activeRing.SelectedSliceBind2 or ""
			local ucBinding, ucBinding2 = activeRing.SelectedCloseBind or "", activeRing.SelectedCloseBind2 or ""
			local crBinding, crBinding2 = activeRing.CloseRingBind or "", activeRing.CloseRingBind2 or ""
			local uncombineCount = (sliceBindings and 2 or 0)
								 + (ukBinding ~= "" and 1 or 0) + (ukBinding2 ~= "" and 1 or 0)
								 + (ucBinding ~= "" and 1 or 0) + (ucBinding2 ~= "" and 1 or 0)
								 + (crBinding ~= "" and 1 or 0) + (crBinding2 ~= "" and 1 or 0)
			if uncombineCount > 0 then
				uncombine = prefix ~= "" and uncombineCount > 1 and activeRing.SliceBindingUncombine
				uncombine = uncombine == nil and owner:Run(ORL_CheckSliceBindings, ukBinding, ukBinding2, ucBinding, ucBinding2, crBinding, crBinding2) and activeRing.SliceBindingUncombine or uncombine
				for i=1, sliceBindings and #openCollection or 0 do
					owner:RunFor(sliceProxy, ORL_RegisterVariations, sliceBindings[i], "slice" .. i, not (uncombine and uncombine[i]) and prefix or "")
					owner:RunFor(sliceProxy, ORL_RegisterVariations, sliceBindings[i+0.5], "slice" .. i .. "b", not (uncombine and uncombine[i+0.5]) and prefix or "")
				end
			end
			owner:RunFor(sliceProxy, ORL_RegisterVariations, ukBinding, "usekeep", not (uncombine and uncombine[0]) and prefix or "")
			owner:RunFor(sliceProxy, ORL_RegisterVariations, ukBinding2, "usekeep", not (uncombine and uncombine[-1]) and prefix or "")
			owner:RunFor(sliceProxy, ORL_RegisterVariations, ucBinding, "useclose", not (uncombine and uncombine[-2]) and prefix or "")
			owner:RunFor(sliceProxy, ORL_RegisterVariations, ucBinding2, "useclose", not (uncombine and uncombine[-3]) and prefix or "")
			owner:RunFor(sliceProxy, ORL_RegisterVariations, crBinding, "closebind", not (uncombine and uncombine[-4]) and prefix or "")
			owner:RunFor(sliceProxy, ORL_RegisterVariations, crBinding2, "closebind", not (uncombine and uncombine[-5]) and prefix or "")

			if AIP_Binding and AIP_Action then
				bindProxy:SetBindingClick(true, AIP_Binding, AIP_Handler, AIP_VirtualKey)
			end
			lowCH[AI_LeftAction and "Show" or "Hide"](lowCH)
			if AI_RightAction and AIP_Binding ~= "BUTTON2" and not AI_NoPointer then
				bindProxy:SetBindingClick(true, "BUTTON2", owner, "BUTTON2")
			end
			bindProxy:SetBindingClick(true, "ESCAPE", owner, "close")
		]==]
		ORL_OpenRing = [==[-- ORL_OpenRing
			local ring, ringID, openCause, ocIndex = ORL_RingData[...], ...
			local fastSwitch, cid, setToVirtualKey = activeRing == ring and ring.ReOpenAction, ring.action
			if not UIParent:IsShown() then
				return false
			elseif fastSwitch == 2 or fastSwitch == 1 and openCollectionID == cid then
				return false, owner:Run(ORL_CloseActiveRing)
			elseif activeRing and not fastSwitch then
				-- If the click-capturing overlay gets the binding DOWN event, only *it* will be notified of the corresponding UP.
				owner:Run(ORL_CloseActiveRing, self == owner)
			end
			local blockOnOpenAction
			AI_NoPointer = ring.NoPointer
			if openCause == "primary-binding" then
				AIP_Binding, setToVirtualKey = ring[ocIndex == 2 and "bind2" or "bind"], "r" .. ringID .. (ocIndex == 2 and "b" or "")
				AIP_Action, AIP_ActionFirstUp = ring.PrimaryAction, ring.PrimaryActionUp
				AI_LeftAction, AI_RightAction = ring.LeftAction, ring.RightAction
				AIP_OnDown, AI_LeftOnDown, AI_RightOnDown = AIP_Action == "close", false, true
			elseif openCause == "override-binding" then
				AIP_Binding, setToVirtualKey = bindOverrides[ringID], "ro" .. ringID
				AIP_Action, AIP_ActionFirstUp, AI_LeftAction, AI_RightAction = "use", nil, nil, "close"
				AIP_OnDown, AI_LeftOnDown, AI_RightOnDown, AI_NoPointer = false, false, true, false
			elseif openCause == "open-macro" then
				AIP_Binding, AIP_Key, AIP_Modifier, AIP_Handler, AIP_VirtualKey = nil
				AIP_Action, AIP_ActionFirstUp = nil, nil
				AI_LeftAction, AI_RightAction = ring.LeftAction2, ring.RightAction2
				AIP_OnDown, AI_LeftOnDown, AI_RightOnDown = false, false, true
				blockOnOpenAction = AB:GetAttribute("PY")
			end
			if AI_NoPointer then
				AI_LeftOnDown, AI_RightAction = nil
			end
			local stickyPrimaryMods = AIP_Action and AIP_Action ~= "close"
			modLockState, modState = KR:RunAttribute("ComputeConditionalLock", stickyPrimaryMods and AIP_Binding or "", "1", (not stickyPrimaryMods and "") or nil)

			local openAction, firstFC = owner:Run(ORL_PrepareCollection, cid)
			activeRing, openCollection, openCollectionID = ring, collections[cid], cid
			if ORL_StoredCA[ring.name] and not ring.fcToken then
				ring.fcToken, ORL_StoredCA[ring.name] = ORL_StoredCA[ring.name]
			end
			fastClick = (ring.CenterAction or ring.MotionAction) and ((not fcIgnore[ring.fcToken] and ctokens[cid][ring.fcToken]) or (ring.OpprotunisticCA and ctokens[cid][firstFC])) or nil
			fastClick = not AI_NoPointer and fastClick ~= 0 and fastClick or nil
			fastClickCA = fastClick and ring.CenterAction

			owner:SetScale(ring.scale)
			owner:SetPoint('CENTER', ring.ofs, ring.ofsx/owner:GetEffectiveScale(), ring.ofsy/owner:GetEffectiveScale())
			owner:RunFor(self, ORL_UpdateInteractionBindings, setToVirtualKey)
			if ring.ClickPriority and not AI_NoPointer then
				owner:Show()
				lowCH:Hide()
			end

			local armMotionFC = fastClick and ring.MotionAction and true
			local needMotionTrap = armMotionFC or AI_LeftAction or AI_MotionArmed
			owner:CallMethod("NotifyState", "open", ring.name, ring.action, fastClick, fastSwitch and true, modLockState)
			owner:Run(ORL_SetMotionTrapArmed, needMotionTrap, armMotionFC)
			if openCollection[0] and (POL_RUN_ONOPEN_ON_REOPEN or not fastSwitch) then
				if blockOnOpenAction then
					owner:CallMethod("NoOnOpenForMacros")
				else
					return owner:RunFor(self, ORL_PerformSliceAction, 0, false, true, "on-open")
				end
			end
			return false
		]==]
		ORL_SwitchRing = [==[-- ORL_SwitchRing
			local colID, switchCause = ...
			local ringID = ORL_KnownCollections[colID]
			local col, ring = collections[colID], ORL_RingData[ringID]
			if not col then
				owner:CallMethod("throw", "Cannot switch to unknown collection " .. tostring(colID))
				return false
			end
			local ring2 = ring or activeRing -- non-ring collections inherit preferences
			if switchCause == "switch-binding" then
			elseif switchCause == "jump-slice-release" or switchCause == "jump-slice-used" or switchCause == "jump-slice-switch" then
				AI_NoPointer = ring2.NoPointer -- override binding could have deferred this
				AIP_Binding, AIP_Key, AIP_Modifier, AIP_Handler, AIP_VirtualKey = nil
				AIP_Action, AIP_ActionFirstUp = (AIP_Action or "noop") ~= "noop" and "close" or nil, nil
				AI_LeftAction, AI_RightAction = ring2.LeftAction2, ring2.RightAction2
				if AI_NoPointer then
					AI_LeftAction, AI_RightAction = nil, nil
				end
				AIP_OnDown, AI_LeftOnDown, AI_RightOnDown = true, false, true
				modLockState, modState = nil, ""
			end

			activeRing = ORL_RingData[ringID] or activeRing
			openCollection, openCollectionID, fastClick, fastClickCA = col, colID, nil, nil
			if POL_SWITCHED_FAST_ACTION and (activeRing.CenterAction or activeRing.MotionAction) then
				local fcToken, arTokens = activeRing.fcToken, ctokens[colID]
				fastClick = fcToken and not fcIgnore[fcToken] and arTokens[fcToken] or nil
				for i=1, not fastClick and activeRing.OpprotunisticCA and #col or 0 do
					if not fcIgnore[arTokens[i]] then
						fastClick = i
						break
					end
				end
				fastClick = not AI_NoPointer and fastClick ~= 0 and fastClick or nil
				if fastClick then
					fastClickCA = fastClick and activeRing.CenterAction
					local armMotionFC = POL_SWICHED_FAST_ACTION_MOTION and fastClick and activeRing.MotionAction and true
					local needMotionTrap = armMotionFC or AI_LeftAction or AI_MotionArmed
					owner:Run(ORL_SetMotionTrapArmed, needMotionTrap, armMotionFC)
				end
			end
			owner:RunFor(self, ORL_UpdateInteractionBindings, nil)
			owner:CallMethod("NotifyState", "switch", ring and ring.name, openCollectionID, fastClick, true, modLockState)
			if openCollection[0] and POL_RUN_ONOPEN_ON_SWITCH and (ORL_JumpCount or 0) < POL_JUMP_COUNT_LIMIT then
				return owner:RunFor(self, ORL_PerformSliceAction, 0, false, true, "switch-onopen")
			end
			return false
		]==]
		ORL_GetCursorSlice = [[-- ORL_GetCursorSlice
			if not openCollection[1] or AI_NoPointer then return nil end
			if AI_MotionArmedFC then
				return fastClick, true
			end
			local x, y = owner:GetMousePosition()
			x, y = x - 0.5, y - 0.5
			local radius, segAngle = (x*x*sizeSq + y*y*sizeSq)^0.5, 360/#openCollection
			if radius >= 40 then
				return floor(((math.deg(math.atan2(x, y)) + segAngle/2 - activeRing.ofsDeg) % 360) / segAngle) + 1, false
			elseif fastClickCA and radius <= 20 then
				return fastClick, true
			end
		]]
		ORL_ResolveNestedSlice = [==[-- ORL_ResolveNestedSlice
			local visitedSlices, col, index, willPerform = wipe(visitedSlices), ...
			while 1 do
				local aid, ct = collections[col] and collections[col][index], ctokens[col] and ctokens[col][index]
				if visitedSlices[ct] or not aid then
					return
				elseif not collections[aid] then
					if willPerform then
						for ict, icol in pairs(visitedSlices) do
							local ort = rtokens[ict]
							local irMode, ctk = rotationMode[ict], ctokens[icol]
							if #ctk <= 1 then
							elseif irMode == "cycle" then
								local nid = (rotation[ict] or 0) % #ctk + 1
								rotation[ict], rtokens[ict] = nid, ctk[nid]
							elseif irMode == "shuffle" then
								local oid = rotation[ict]
								local nid = math.random(#ctk - (oid and 1 or 0))
								nid = nid + (oid and nid >= oid and 1 or 0)
								rotation[ict], rtokens[ict] = nid, ctk[nid]
							end
						end
					end
					return aid, "act"
				elseif rotationMode[ct] == "jump" then
					return aid, "jump"
				end
				visitedSlices[ct], col, index = aid, aid, rotation[ct] or 1
			end
		]==]
		ORL_PerformSliceAction = [[-- ORL_PerformSliceAction
			local pureSlice, shouldUpdateFastClick, noClose, interactionSource = ...
			local pureToken = ctokens[openCollectionID][pureSlice]
			local action, at = owner:Run(ORL_ResolveNestedSlice, openCollectionID, pureSlice, true)
			activeRing.fcToken = shouldUpdateFastClick and (activeRing.CenterAction or activeRing.MotionAction) and not fcIgnore[pureToken] and pureToken or activeRing.fcToken
			if at == "jump" then
				ORL_JumpCount = (ORL_JumpCount or 0) + 1
				return owner:RunFor(self, ORL_SwitchRing, action, interactionSource == "primary-binding" and "jump-slice-release" or "jump-slice-used")
			end
			if not noClose then
				owner:Run(ORL_CloseActiveRing, nil, pureSlice, action)
			end
			if action then
				local w, p, s = ORL_OverSAB or self, AI_ClickStackIndex + 1
				s = AI_ClickStack[p] or newtable()
				local mt, checkExecID, notifyToken = AB:RunAttribute("UseAction", action, modLockState)
				w:SetAttribute("type", "macro")
				w:SetAttribute("macrotext", mt)
				s[1], s[2], s[3] = checkExecID and AB:GetAttribute("execID") or -2, RW:GetAttribute("execPending"), notifyToken
				AI_ClickStack[p], AI_ClickStackIndex = s, p
				return action, AI_ClickStackIndex
			end
			return false
		]]
		ORL_OnWheel = [==[-- ORL_OnWheel
			local slice = owner:Run(ORL_GetCursorSlice)
			local nestedCol = collections[openCollection[slice]]
			local rMode = rotationMode[(ctokens[openCollectionID] or emptyTable)[slice]]
			if not (slice and nestedCol and rMode ~= "jump") then return end
			if slice ~= wheelSlice then wheelSlice, wheelBucket = slice, 0 end
			wheelBucket = wheelBucket + (...)
			if abs(wheelBucket) >= activeRing.bucket then wheelBucket = 0 else return end
			local stoken, step, count, c = ctokens[openCollectionID][slice], (...) > 0 and 0 or -2, #nestedCol, 0
			repeat
				rotation[stoken], c = (rotation[stoken] + step) % count + 1, c + 1
			until owner:Run(ORL_ResolveNestedSlice, openCollectionID, slice, false) or c == count
			rtokens[stoken] = (ctokens[openCollection[slice]] or emptyTable)[rotation[stoken]] or rtokens[stoken]
		]==]
		ORL_CheckButtonBindings = [==[-- ORL_CheckButtonBindings
			local lvalue, lkey, BUTTON, checkRingBindings = 0, nil, ...
			for bind, vbtn in pairs(buttonBindings) do
				local pm, btn = bind:match("()([^-]*%-?)$")
				if btn == BUTTON and #bind > lvalue and (pm == 1 or IsModifiedClick(bind)) then
					lkey, lvalue = vbtn, #bind
				end
			end
			if checkRingBindings and not lkey then
				for k, v in pairs(ORL_RingData) do
					if v.bindButton == BUTTON and (v.bindModifiedClick == nil or IsModifiedClick(v.bindModifiedClick)) and #v.bind > lvalue then
						lkey, lvalue = "r" .. k, #v.bind
					elseif v.bind2Button == BUTTON and (v.bind2ModifiedClick == nil or IsModifiedClick(v.bind2ModifiedClick)) and #v.bind2 > lvalue then
						lkey, lvalue = "r" .. k .. "b", #v.bind2
					end
				end
			end
			return lkey
		]==]
		ORL_OnClick = [==[-- ORL_OnClick
			local button, down = ...
			local BUTTON = BUTTON_NAMEKEY_MAP[button] or button and button:upper()
			local isActiveRingTriggerClick = (AIP_VirtualKey and AIP_VirtualKey == button) or (AIP_Key and AIP_Key == BUTTON and (AIP_Modifier == nil or IsModifiedClick(AIP_Modifier)))
			local openHotkeyOverride, openHotkeyId, openHotkeyV = button:match("^r(o?)(%d+)(b?)$")
			openHotkeyId = tonumber(openHotkeyId)
			if isActiveRingTriggerClick and (AIP_Action or AIP_ActionFirstUp and not down) then
				button = down == AIP_OnDown and AIP_Action or AIP_ActionFirstUp or "noop"
				-- If hovering over a nested ring/jump slice, allow global mwin/up/down bindings to override the ring binding (when down)
				local globalAction = down and owner:Run(ORL_CheckButtonBindings, (AIP_VirtualKey == ... and AIP_Key or BUTTON), false)
				local pointerAID = globalAction and openCollection[owner:Run(ORL_GetCursorSlice)]
				if AIP_ActionFirstUp and not down then
					AIP_ActionFirstUp = nil, AIP_IntBindCollide and owner:Run(ORL_UpdateInteractionBindings2, nil)
				end
				if collections[pointerAID] or ORL_KnownCollections[pointerAID] then
					-- Global override wins; ignore future (primary binding, up)
					button = globalAction
				end
			elseif BUTTON == "BUTTON1" and activeRing and AI_LeftAction then
				button = down == AI_LeftOnDown and AI_LeftAction or "noop"
			elseif BUTTON == "BUTTON2" and AI_RightAction then
				button = down == AI_RightOnDown and AI_RightAction or "noop"
			end

			if button == "noop" then
				return false
			elseif activeRing and (button == "use" or button == "useFC") then
				local slice, isFC = owner:Run(ORL_GetCursorSlice)
				if button == "useFC" and not (isFC and slice) then
					return false
				end
				return owner:RunFor(self, ORL_PerformSliceAction, slice, openCollectionID == activeRing.action, false, isActiveRingTriggerClick and "primary-binding")
			elseif activeRing and button == "usekeep" and down == activeRing.RunBindingsOnDown then
				return owner:RunFor(self, ORL_PerformSliceAction, owner:Run(ORL_GetCursorSlice), false, true, "use-binding")
			elseif activeRing and button == "useclose" and down == activeRing.RunBindingsOnDown then
				return owner:RunFor(self, ORL_PerformSliceAction, owner:Run(ORL_GetCursorSlice), true, false, "use-binding")
			elseif activeRing and button == "close" then
				return false, owner:Run(ORL_CloseActiveRing)
			elseif activeRing and button == "closebind" and down == activeRing.RunBindingsOnDown then
				return false, owner:Run(ORL_CloseActiveRing)
			elseif activeRing and button == "closeFC" then
				local slice, isFC = owner:Run(ORL_GetCursorSlice)
				if slice and isFC then
					return owner:RunFor(self, ORL_PerformSliceAction, slice, false, false, isActiveRingTriggerClick and "primary-binding")
				end
				return false, owner:Run(ORL_CloseActiveRing)
			elseif activeRing and button == "mwin" and down == activeRing.RunBindingsOnDown then
				local slice = owner:Run(ORL_GetCursorSlice)
				local aid, rt = openCollection[slice], rotationMode[(ctokens[openCollectionID] or "")[slice]]
				if collections[aid] then
					return owner:RunFor(self, ORL_SwitchRing, aid, rt == "jump" and "jump-slice-switch" or "switch-binding")
				end
			elseif activeRing and button:match("^mw[ud]") then
				return false, down and owner:Run(ORL_OnWheel, (button:match("^mwup") and 1 or -1) * (button:match("K$") and activeRing.bucket or 1))
			elseif BUTTON:match("^BUTTON%d+$") then
				-- The click-capturing overlay captures all mouse clicks, including bindings
				local lkey = owner:Run(ORL_CheckButtonBindings, BUTTON, true)
				if lkey then
					return owner:RunFor(self, ORL_OnClick, lkey, down)
				end
			elseif openHotkeyId and down then
				local isOverrideBinding = openHotkeyOverride == "o" and bindOverrides[openHotkeyId]
				return owner:RunFor(self, ORL_OpenRing, openHotkeyId, isOverrideBinding and "override-binding" or "primary-binding", openHotkeyV == "b" and 2 or 1)
			elseif activeRing and openCollection then
				local b = tonumber((button:match("^slice(%d+)b?$")))
				if openCollection[b] then
					if down and activeRing.RunBindingsOnDown or not down and sliceBindState[button] then
						return owner:RunFor(self, ORL_PerformSliceAction, b, true, activeRing.NoCloseOnSlice, "slice-binding")
					elseif down then
						sliceBindState[button] = true
					end
				end
			end
			return false
		]==]
		ORL_PostClick = [[-- ORL_PostClick
			local message = ...
			local cs, oi, bad = AI_ClickStack[message], AI_ClickStackIndex
			self:SetAttribute('type', nil)
			AI_ClickStackIndex, ORL_JumpCount = oi-1
			bad = message ~= oi or cs == nil or AB:GetAttribute("execID") == cs[1]
			if message == oi and cs and cs[3] then
				AB:RunAttribute("NotifyPostUse", cs[3])
			end
			if bad or (cs[2] or 0) < (RW:GetAttribute("execPending") or 0) then
				owner:CallMethod("BadLizardError")
			end
		]]
		ORL_OpenClick = [[-- ORL_OpenClick
			local rdata = ORL_RingDataN[...]
			if not rdata then
				return false, print('|cffff0000[OPie] Cannot open unknown ring "' .. tostring((...)) .. '".')
			end
			ORL_OverSAB = self -- Don't RunFor the /click handler button, as it won't fire an UP
			return owner:Run(ORL_ClearOverSAB, owner:Run(ORL_OpenRing, rdata.id, "open-macro"))
		]]
		ORL_ClearOverSAB = [[-- ORL_ClearOverSAB
			ORL_OverSAB = nil
			return ...
		]]
	]=])
	OR_SecCore:SetAttribute("_onmousewheel", [=[-- ORL_OnMouseWheel
		local wheelDirection, winDelta, winLength = delta == 1 and "UP" or "DOWN"
		for i=1, #NESTED_SCROLL_BIND_OPTS do
			local bind = ORL_GlobalOptions[NESTED_SCROLL_BIND_OPTS[i]]
			if bind and bind:match("MOUSEWHEEL([UPDOWN]+)$") == wheelDirection
			   and (bind:match("%-") == nil or IsModifiedClick(bind))
			   and (winLength == nil or #bind > winLength) then
				winDelta, winLength = i < 3 and -1 or 1, #bind
			end
		end
		if winDelta then
			return self:Run(ORL_OnWheel, winDelta)
		end
	]=])
	OR_SecCore:WrapScript(OR_SecCore, "OnClick", "return self:Run(ORL_OnClick, button, down)",
		"owner:RunFor(self, ORL_PostClick, message)")
	OR_SecCore:WrapScript(OR_OpenProxy, "OnClick", "return owner:RunFor(self, ORL_OpenClick, button)",
		"owner:RunFor(self, ORL_PostClick, message)")
	OR_SecCore:WrapScript(closeProxy, "OnClick", "return false, activeRing and owner:Run(ORL_CloseActiveRing)")
	OR_SecCore:WrapScript(OR_RingBindingProxy, "OnAttributeChanged", [[-- ORL.BindProxy-OnAttributeChanged
		if name == "state-combat" then
			if value == "combat" then
				overProxy:ClearBindings()
				wipe(bindOverrides)
			end
			return
		end
		local rid, bv, data = (name or ""):match("^binding%-r(%d+)(b?)$")
		data = ORL_RingData[rid and rid+0]
		if data then
			local bind, bindButton, bindModifiedClick
			if (value or "") ~= "" then
				local modifiedClick, modifiers, undash, button = value:match("^((.-)([^-]?)(BUTTON%d+))$")
				if undash ~= "" or modifiedClick == button then
					modifiedClick, modifiers = nil
				end
				bind, bindButton, bindModifiedClick = value, button, modifiedClick
			end
			if bv == "b" then
				data.bind2, data.bind2Button, data.bind2ModifiedClick = bind, bindButton, bindModifiedClick
			else
				data.bind, data.bindButton, data.bindModifiedClick = bind, bindButton, bindModifiedClick
			end
		end
	]])
	RegisterStateDriver(OR_RingBindingProxy, "combat", "[combat] combat; nocombat")
	function OR_SecCore:throw(err)
		return error(err, 2)
	end
end
local markSliceBindings
do -- Binding labels
	local base = "BINDING_NAME_CLICK " .. coreName .. ":"
	local function markBind(label, a, b)
		label = "OPie: " .. label
		_G[base .. a], _G[base .. (b or a)] = label, label
	end
	local sliceBase, sliceMarkIndex = base .. "slice", 0
	function markSliceBindings(n)
		for i = 1 + sliceMarkIndex, n do
			local label = "OPie: " .. L("Slice #%d"):format(i)
			_G[sliceBase .. i], _G[sliceBase .. i .. "b"] = label, label
		end
		sliceMarkIndex = sliceMarkIndex < n and n or sliceMarkIndex
	end
	markBind(L "Selected slice (keep ring open)", "usekeep")
	markBind(L "Selected slice (close ring)", "useclose")
	markBind(L "Close ring", "closebind")
	markBind(L "Open nested ring", "mwin")
	markBind(L "Scroll nested ring (down)", "mwdownW", "mwdownK")
	markBind(L "Scroll nested ring (up)", "mwupW", "mwupK")
end
local function OR_GetEffectiveGlobalOption(option, config)
	local global = (config or configInstance)[option]
	if global == nil then
		return defaultConfig[option]
	end
	return global
end
local function OR_GetRingOption(ringName, option, config)
	config = config or configInstance
	local default, value, setting = defaultConfig[option]
	if not config then
		return default, nil, nil, nil, default
	end
	local global, ring = config[option], ringName and config.RingOptions[ringName .. "#" .. option]
	if ringName and ring ~= nil then
		value, setting = ring, ring
	elseif global == nil then
		value, setting = default, nil
	elseif ringName == nil then
		value, setting = global, global
	else
		value, setting = global, nil
	end
	return value, setting, ring, global, default
end
local function OR_DeleteRingRE(name, internalId, actionId)
	coreEnvW.ORL_KnownCollections[actionId] = nil
	coreEnvW.ORL_RingData[internalId] = nil
	coreEnvW.ORL_RingDataN[name] = nil
	local clickProxy = GetFrameHandleFrame(OR_SecCore:GetAttribute("frameref-proxy" .. internalId))
	if clickProxy then
		KR:UnregisterBindingDriver(clickProxy, "r" .. internalId)
		KR:UnregisterBindingDriver(clickProxy, "r" .. internalId .. "b")
	end
end
local function OR_SyncDeletionQueue()
	for i = 1, sfDelQueue and #sfDelQueue or 0, 3 do
		OR_DeleteRingRE(sfDelQueue[i], sfDelQueue[i + 1], sfDelQueue[i + 2])
	end
	sfDelQueue = nil
end
local OR_SyncRingBinding
do -- Binding management
	local bindingEncodeChars = {
		["["] = "OPEN",
		["]"] = "CLOSE",
		[";"] = "SEMICOLON"
	}
	local encodedBindings = {
		OPEN = "[",
		CLOSE = "]",
		SEMICOLON = ";"
	}
	local function RemoveConflictingBindings(bind)
		local rawBind = KR:UnescapeCmdOptionsValue(bind:gsub("%a+$", encodedBindings))
		return GetBindingAction(rawBind) ~= "" and ";" or nil
	end
	function OR_SyncRingBinding(name, props)
		if sfDelQueue or InCombatLockdown() then
			props.reSyncBinding, sfBindsOne = true, true
			return
		end
		props.reSyncBinding = nil
		local hotkey, isSoftBinding, id = configInstance and configInstance.Bindings[name], false, props.internalID
		local hotkey2 = configInstance and configInstance.Bindings2[name]
		if hotkey == nil and type(props.hotkey) == "string" and OR_GetRingOption(name, "UseDefaultBindings") then
			hotkey, isSoftBinding = props.hotkey, true
		end
		if hotkey then
			if not hotkey:match("%[.*%]") then
				hotkey = "[] " .. hotkey:gsub("([^-!%s]+)%s*$", bindingEncodeChars)
			end
			if isSoftBinding then
				hotkey = (hotkey .. ";"):gsub("%s*!*%s*([^%s%[%];]+)%s*;", RemoveConflictingBindings):sub(1, -2)
			end
		end
		if hotkey2 and not hotkey2:match("%[.*%]") then
			hotkey2 = "[] " .. hotkey2:gsub("([^-!]+)%s*$", bindingEncodeChars)
		end
		if props.currentBindingConditional == hotkey and props.currentBindingConditional2 == hotkey2 and
			props.currentBindingSoft == isSoftBinding then
			return
		end
		local clickProxy = GetFrameHandleFrame(OR_SecCore:GetAttribute("frameref-proxy" .. id))
		if not clickProxy then
			clickProxy = CreateFrame("Button", "ORL_RProxy" .. id, nil, "SecureActionButtonTemplate")
			clickProxy:RegisterForClicks("AnyUp", "AnyDown")
			clickProxy:SetAttribute("downbutton", true)
			OR_SecCore:WrapScript(clickProxy, "OnClick", "return owner:RunFor(self, ORL_OnClick, button, down)",
				'owner:RunFor(self, ORL_PostClick, message)')
			OR_SecCore:SetFrameRef("proxy" .. id, clickProxy)
			local bk, lab = "BINDING_NAME_CLICK " .. clickProxy:GetName() .. ":r" .. id,
				(L "OPie ring: %s"):format(props.name or "?")
			_G[bk], _G[bk .. "b"] = lab, lab
		end
		props.currentBindingConditional, props.currentBindingConditional2, props.currentBindingSoft = hotkey, hotkey2,
			isSoftBinding
		local pri1, pri2 = isSoftBinding and -2600 or -2100, 20 - 2100
		KR:RegisterBindingDriver(clickProxy, "r" .. id, hotkey or "", pri1, OR_RingBindingProxy)
		KR:RegisterBindingDriver(clickProxy, "r" .. id .. "b", hotkey2 or "", pri2, OR_RingBindingProxy)
	end
	OR_SecCore.BadLizardError = GenerateClosure(error, "bad lizard", 2)
	function OR_SecCore.NoOnOpenForMacros()
		print("|cffe84010Cannot execute on-open actions when using |cffffffff/click ORLOpen|r.")
	end
end
local function OR_SyncRingRE(name, props)
	props.reSync = nil
	local imode, noClose = OR_GetRingOption(name, "InteractionMode"), OR_GetRingOption(name, "NoClose")
	local centerAction, motionAction = OR_GetRingOption(name, "CenterAction"), OR_GetRingOption(name, "MotionAction")
	local quickOnRelease = imode == 2 and (centerAction or motionAction) and
							   OR_GetRingOption(name, "QuickActionOnRelease")
	local sliceBindings = (imode == 3 or OR_GetRingOption(name, "SliceBinding")) and
							  OR_GetRingOption(name, "SliceBindingString")
	local primaryAction = imode == 1 and "use"
	local primaryActionUp = quickOnRelease and "useFC" or imode == 3 and OR_GetRingOption(name, "CloseOnRelease") and
								"close"
	local leftAction = imode == 2 and (noClose and "usekeep" or "use")
	local leftAction2 = imode ~= 3 and (noClose and "usekeep" or "use")
	local rightAction = imode ~= 3 and "close"

	local internalId, actionId = props.internalID, props.action
	local data = coreEnvW.ORL_RingData[internalId] or WR.newtable(coreEnvW.ORL_RingData, internalId)
	coreEnvW.ORL_KnownCollections[actionId], coreEnvW.ORL_RingDataN[name] = internalId, data
	data.action, data.name, data.id = actionId, name, internalId
	data.scale = math.max(0.1, (OR_GetRingOption(name, "RingScale")))
	data.ofs = OR_GetRingOption(name, "RingAtMouse") and "$cursor" or "$screen"
	data.ofsx = OR_GetRingOption(name, "IndicationOffsetX")
	data.ofsy = -OR_GetRingOption(name, "IndicationOffsetY")
	data.ofsDeg = props.offset
	data.CenterAction, data.MotionAction = centerAction or nil, motionAction or nil
	data.ClickPriority = OR_GetRingOption(name, "ClickPriority") or nil
	data.ReOpenAction = OR_GetRingOption(name, "ReOpenAction")
	data.NoPointer = imode == 3 or nil
	data.NoCloseOnSlice = OR_GetRingOption(name, "NoCloseOnSlice") or nil
	data.PrimaryAction, data.PrimaryActionUp = primaryAction, primaryActionUp
	data.LeftAction, data.LeftAction2 = leftAction, leftAction2
	data.RightAction, data.RightAction2 = rightAction, rightAction
	data.RunBindingsOnDown = OR_GetRingOption(name, "RunBindingsOnDown")
	data.bucket = OR_GetRingOption(name, "MouseBucket")
	if (sliceBindings or "") == "" then
		data.SliceBinding, data.SliceBindingS = false, nil
	elseif data.SliceBindingS ~= sliceBindings then
		data.SliceBindingS = sliceBindings
		local sb, bn = WR.newtable(data, "SliceBinding"), 1
		for s, s2 in sliceBindings:gmatch("([^%s\31]+)\31?(%S*)") do
			s =
				not (s == "false" or s:match("[Bb][Uu][Tt][Tt][Oo][Nn][123]$") or s:match("[Ee][Ss][Cc][Aa][Pp][Ee]$")) and
					s
			s2 = not (s2 == "false" or s2 == "" or s2:match("[Bb][Uu][Tt][Tt][Oo][Nn][123]$") or
					 s2:match("[Ee][Ss][Cc][Aa][Pp][Ee]$")) and s2
			sb[bn], sb[bn + 0.5], bn = s, s2, bn + 1
		end
	end
	data.SliceBindingUncombine, data.OpprotunisticCA = nil, props.opportunisticCA or nil
	data.SelectedSliceBind, data.SelectedSliceBind2 = OR_GetRingOption(name, "SelectedSliceBind") or "",
		OR_GetRingOption(name, "SelectedSliceBind2") or ""
	data.SelectedCloseBind, data.SelectedCloseBind2 = OR_GetRingOption(name, "SelectedCloseBind") or "",
		OR_GetRingOption(name, "SelectedCloseBind2") or ""
	data.CloseRingBind, data.CloseRingBind2 = OR_GetRingOption(name, "CloseRingBind") or "",
		OR_GetRingOption(name, "CloseRingBind2") or ""
	OR_SyncRingBinding(name, props)
end
local function OR_SyncRing(name, actionId, newprops)
	local props = OR_Rings[name] or {}
	if not OR_Rings[name] then
		OR_Rings[name], OR_Rings[#OR_Rings + 1], props.internalID, props.internalName, props.internalAP, internalFreeId =
			props, name, internalFreeId, name, #OR_Rings + 1, internalFreeId + 1
	end
	if newprops then
		props.action, props.offset, props.name, props.hotkey, props.internal = actionId, newprops.offset or 0,
			newprops.name or name, newprops.hotkey, newprops.internal
		props.opportunisticCA, props.noPersistentCA = not newprops.noOpportunisticCA, newprops.noPersistentCA
		props.sortScope = type(newprops.sortScope) == "number" and newprops.sortScope or 2
	end
	if sfDelQueue or InCombatLockdown() then
		props.reSync, sfRingsOne = true, true
	else
		OR_SyncRingRE(name, props)
	end
	if newprops and AB then
		AB:NotifyObservers("ring")
	end
end
local function OR_DeleteRing(name, data)
	if InCombatLockdown() then
		sfDelQueue = sfDelQueue or {}
		local i = #sfDelQueue + 1
		sfDelQueue[i], sfDelQueue[i + 1], sfDelQueue[i + 2] = name, data.internalID, data.action or 0
	else
		OR_DeleteRingRE(name, data.internalID, data.action or 0)
	end

	local bind = configInstance and configInstance.Bindings[name]
	if configRoot and configRoot.ProfileStorage then
		local rnOpt = "^" .. name:gsub("[%]%[().+*%-?^$%%]", "%%%1") .. "#"
		for _, v in pairs(configRoot.ProfileStorage) do
			if v.Bindings then
				v.Bindings[name] = nil
			end
			if v.Bindings2 then
				v.Bindings2[name] = nil
			end
			if v.RingOptions then
				for k2, _v2 in pairs(v.RingOptions) do
					if type(k2) ~= "string" or k2:match(rnOpt) then
						v.RingOptions[k2] = nil
					end
				end
			end
		end
	end
	OR_Rings[data.internalAP], OR_Rings[OR_Rings[#OR_Rings]].internalAP = OR_Rings[#OR_Rings], data.internalAP
	OR_Rings[name], OR_Rings[#OR_Rings] = nil

	for i = 1, bind and not sfBindsAll and #OR_Rings or 0 do
		local k = OR_Rings[i]
		local v = OR_Rings[k]
		if v and v.hotkey == bind then
			OR_SyncRingBinding(k, v)
		end
	end
end
local function OR_SyncGlobalOptionsRE()
	local up1, up2 = OR_GetEffectiveGlobalOption("ScrollNestedRingUpButton"),
		OR_GetEffectiveGlobalOption("ScrollNestedRingUpButton2")
	local down1, down2 = OR_GetEffectiveGlobalOption("ScrollNestedRingDownButton"),
		OR_GetEffectiveGlobalOption("ScrollNestedRingDownButton2")
	local p = "[mM][oO][uU][sS][eE][wW][hH][eE][eE][lL]"
	local hasWheelScroll = (up1 or ""):match(p) or (up2 or ""):match(p) or (down1 or ""):match(p) or
							   (down2 or ""):match(p)
	local r = coreEnvW.ORL_GlobalOptions
	r.OpenNestedRingBinding = OR_GetEffectiveGlobalOption("OpenNestedRingButton")
	r.ScrollNestedRingUpBinding, r.ScrollNestedRingDownBinding = up1, down1
	r.OpenNestedRingBinding2 = OR_GetEffectiveGlobalOption("OpenNestedRingButton2")
	r.ScrollNestedRingUpBinding2, r.ScrollNestedRingDownBinding2 = up2, down2
	OR_SecCore:EnableMouseWheel(not not hasWheelScroll)
	sfGlobalOptions = nil
end
local function OR_SecProfilePull()
	local pInstance = configRoot.ProfileStorage[activeProfileRE]
	if not pInstance then
		return
	end
	local tt = pInstance.RotationTokens
	for k, v in coreEnvW.rtokens(0) do
		tt[k] = v
	end
end
local function OR_SecProfilePush()
	if InCombatLockdown() or (activeProfile == activeProfileRE) then
		return
	end
	activeProfileRE = activeProfile
	local rt, rrt = configInstance.RotationTokens, coreEnvW.rtokens
	for k in rrt(0) do
		rrt[k] = rt[k]
	end
	for k, v in pairs(rt) do
		rrt[k] = v
	end
end
local function OR_PullQuickActions()
	local t = {}
	for k, v in coreEnvW.ORL_StoredCA(0) do
		t[k] = v
	end
	for _, k in ipairs(OR_Rings) do
		local rt = coreEnvW.ORL_RingDataN[k] and coreEnvW.ORL_RingDataN[k].fcToken or t[k]
		t[k] = not ((OR_Rings[k] and OR_Rings[k].noPersistentCA) or coreEnvW.fcIgnore[rt]) and rt or nil
	end
	return next(t) and t or nil
end
local OR_FindFinalAction
do
	local seen, wipe = {}, table.wipe
	local secRotation, secCollections, secTokens, secRotationMode = coreEnvW.rotation, coreEnvW.collections,
		coreEnvW.ctokens, coreEnvW.rotationMode
	function OR_FindFinalAction(collection, id, from, rotationBonus, followJumps)
		wipe(seen)
		for k = 1, 50 do
			local col = secCollections[collection]
			local act = col and col[id]
			if act then
				local nCol, tok, rot = secCollections[act], secTokens[collection][id]
				local isJump = secRotationMode[tok] == "jump"
				if nCol == nil then
					return act, tok, "act", k
				elseif isJump and tok ~= from and not followJumps then
					return act, tok, "jump", k
				elseif not seen[tok] then
					seen[tok], rot = true, secRotation[tok] or 1
					if tok == from then
						rot = (rot + rotationBonus - 1) % #nCol + 1
					end
					collection, id = act, rot
				else -- nCol and seen[tok] and (not isJump or tok == from or followJumps); arbitrarily break nesting loops
					return act, tok, isJump and "jump" or "act", k
				end
			end
		end
	end
end
function OR_SecCore:NotifyState(state, _ringName, collection, ...)
	if state == "open" then
		local fastClick, fastOpen, ms = ...
		OR_ActiveCollectionID, OR_ActiveRingName, OR_ActiveSliceCount, OR_ModifierLockState = collection,
			coreEnvW.activeRing.name, #coreEnvW.openCollection, ms
		markSliceBindings(OR_ActiveSliceCount)
		if ORI then
			securecall(ORI.Show, ORI, collection, fastClick, fastOpen, self)
		end
		if coreEnvW.AI_NoPointer then
			return
		end
		MouselookStop()
	elseif state == "switch" then
		local fastClick, _fastOpen, ms = ...
		OR_ActiveCollectionID, OR_ActiveSliceCount, OR_ModifierLockState = collection, #coreEnvW.openCollection, ms
		markSliceBindings(OR_ActiveSliceCount)
		if ORI then
			securecall(ORI.Show, ORI, collection, fastClick, "inplace-switch", self)
		end
	elseif state == "close" then
		if ORI then
			securecall(ORI.Hide, ORI, ...)
		end
		OR_ActiveSliceCount, OR_ActiveCollectionID, OR_ActiveRingName = 0
	end
end

-- Responding to WoW Events
local OR_NotifyPVars
do
	local function callNotify(k, event)
		local v = PersistentStorageInfo[k]
		v.f(event, k, v.t)
		return true
	end
	function OR_NotifyPVars(event, filter, perProfile)
		local ok = true
		for k, v in pairs(PersistentStorageInfo) do
			if type(v.f) == "function" and v.t == (filter or v.t) and (perProfile == nil or perProfile == v.perProfile) then
				ok = securecall(callNotify, k, event) and ok
			end
		end
		return ok
	end
end
local function OR_SyncRings()
	local iterateRings = sfRingsOne or sfBindsOne or sfRingsAll or sfBindsAll
	local allRings, allBinds = sfRingsAll, sfBindsAll
	sfRingsAll, sfBindsAll, sfRingsOne, sfBindsOne = nil
	for i = 1, iterateRings and #OR_Rings or 0 do
		local k = OR_Rings[i]
		local props = OR_Rings[k]
		if allRings or props.reSync then
			OR_SyncRingRE(k, props)
		elseif allBinds or props.reSyncBinding then
			OR_SyncRingBinding(k, props)
		end
	end
end
local function OR_PerfomDelayedSync()
	if not InCombatLockdown() then
		OR_SyncDeletionQueue()
		OR_SyncRings()
		if sfGlobalOptions then
			OR_SyncGlobalOptionsRE()
		end
		OR_SecProfilePush()
	end
end
function EV:PLAYER_REGEN_ENABLED()
	OR_PerfomDelayedSync()
end
local function OR_NotifyOptions()
	for option, func in pairs(optionValidators) do
		if func then
			securecall(func, option, OR_GetEffectiveGlobalOption(option))
		end
	end
end
local function OR_ThawConfigInstance(profile)
	local newCI
	activeProfile, newCI = getProfile(profile)
	local pc = newCI._pcStore
	if pc and OR_GetEffectiveGlobalOption("PerCharRotationStore", newCI) then
		newCI.RotationTokens = pc.RotationTokens
	end
	for t in ("RingOptions Bindings Bindings2 RotationTokens"):gmatch("%S+") do
		if type(newCI[t]) ~= "table" then
			newCI[t] = {}
		end
	end
	for k, v in pairs(PersistentStorageInfo) do
		if v.perProfile then
			wipe(v.t)
			copy(newCI[k], nil, v.t)
		end
	end
	configInstance = newCI
end
local function OR_UpgradeOptions(pv, isRingOptions, _oldRev)
	local nv = {}
	for k, v in pairs(pv) do
		local domain, opt = (isRingOptions and type(k) == "string" and k or ""):match("^(.*#)(.-)$")
		if not domain then
			domain, opt = "", k
		end
		if opt == "ClickActivation" and type(v) == "boolean" then
			nv[domain .. "InteractionMode"], pv[k] = pv[domain .. "InteractionMode"] or v and 2 or nil, nil -- DEPRECATED[2406/Z7]
		end
	end
	for k, v in pairs(nv) do
		pv[k], nv[k] = v, nil
	end
end
local function OR_UpgradeConfig()
	if not OR_UpgradeConfig then
		return
	end
	local svRev = tonumber(configRoot._StoreVersion) or 0
	local gameVersion, opieVersion = GetBuildInfo(), ("%s (%d.%d)"):format(api:GetVersion())

	if type(OPie_SavedDataPC) == "table" and type(OPie_SavedDataPC.ProfileStorage) == "table" then
		local oodPC = OPie_SavedDataPC._GameVersion ~= gameVersion
		for k, v in pairs(OPie_SavedDataPC.ProfileStorage) do
			local pv = type(v) == "table" and configRoot.ProfileStorage[k]
			if pv then
				local cv = copy(v)
				if oodPC then
					cv.RotationTokens = nil
				end
				pv._pcStore = cv
			end
		end
	end

	if svRev < 122 then
		for _, pv in pairs(configRoot.ProfileStorage) do
			if type(pv) == "table" then
				OR_UpgradeOptions(pv, false, svRev)
				if type(pv.RingOptions) == "table" then
					OR_UpgradeOptions(pv.RingOptions, true, svRev)
				end
			end
		end
	end
	if configRoot._GameVersion ~= gameVersion then
		for _, pv in pairs(configRoot.ProfileStorage) do
			if type(pv) == "table" then
				pv.RotationTokens = nil
			end
		end
	end

	configRoot._GameVersion, configRoot._OPieVersion, configRoot._GameLocale = gameVersion, opieVersion, GetLocale()
	configRoot._StoreVersion = svRev >= SVREV and svRev or SVREV
	OR_UpgradeConfig = nil
	return true
end
local function OR_InitConfigState()
	local from = OPie_SavedData
	if type(from) == "table" then
		for k, v in pairs(from) do
			configRoot[k] = v
		end
	end
	for t in ("CharProfiles PersistentStorage ProfileStorage"):gmatch("%S+") do
		configRoot[t] = type(configRoot[t]) == "table" and copy(configRoot[t]) or {}
	end
	if type(configRoot.ProfileStorage.default) ~= "table" then
		configRoot.ProfileStorage.default = {
			Bindings = {},
			RingOptions = {}
		}
	end

	local ok = securecall(OR_UpgradeConfig)
	OR_ThawConfigInstance(configRoot.CharProfiles[getSpecCharIdent()])

	if type(configRoot.CenterActions) == "table" then
		local rca = coreEnvW.ORL_StoredCA
		for name, tok in pairs(configRoot.CenterActions) do
			rca[name] = tok
		end
	end
	configRoot.CenterActions = nil

	-- Load variables into relevant tables, unlock core and fire notifications.
	for k, v in pairs(configRoot.PersistentStorage) do
		if PersistentStorageInfo[k] and not PersistentStorageInfo[k].perProfile then
			copy(v, nil, PersistentStorageInfo[k].t)
		end
	end
	ok = OR_NotifyPVars("LOADED") and ok
	OR_NotifyOptions()
	OR_LoadedState = OR_LoadedState == 2 and (ok and 4 or 3) or OR_LoadedState
end
local function OR_SaveCurrentProfile()
	OR_NotifyPVars("SAVE", nil, true)
	for k, v in pairs(PersistentStorageInfo) do
		if v.perProfile then
			configInstance[k] = next(v.t) and copy(v.t)
		end
	end
	OR_SecProfilePull()
end
local function OR_FreezeProfilePerCharSV(v)
	local pcStore = v._pcStore
	if OR_GetEffectiveGlobalOption("PerCharRotationStore", v) then
		if v.RotationTokens then
			pcStore = pcStore or {}
			pcStore.RotationTokens, v.RotationTokens = v.RotationTokens
		end
	elseif pcStore then
		pcStore.RotationTokens = nil
	end
	return pcStore and next(pcStore) ~= nil and pcStore
end
local function OR_SwitchProfile(ident)
	if ident ~= activeProfile then
		OR_SaveCurrentProfile()
	end
	local prevProfile = activeProfile
	OR_ThawConfigInstance(ident)
	OR_NotifyPVars("UPDATE", nil, true)
	OR_NotifyOptions()
	sfRingsAll, sfGlobalOptions = true, true
	OR_PerfomDelayedSync()
	if activeProfile ~= prevProfile then
		EV("OPIE_PROFILE_SWITCHED", activeProfile, prevProfile)
	end
end
function EV:ADDON_LOADED(addon)
	if addon == ADDON then
		ORI, OR_LoadedState = T.OPieUI, OR_LoadedState == 1 and 2 or OR_LoadedState
		OR_InitConfigState()
		sfRingsAll, sfGlobalOptions = true, true
		OR_PerfomDelayedSync()
		return "remove"
	end
end
function EV:SAVED_VARIABLES_TOO_LARGE(addon)
	if addon == ADDON then
		OR_LoadedState = false
	end
end
local greeted
function EV:PLAYER_LOGIN()
	OR_LoadedState = OR_LoadedState == 1 and -1 or OR_LoadedState
	OR_NotifyPVars("LOGIN")
	OR_NotifyPVars("POST-LOGIN")
	if not greeted then
		greeted = true
		EV.After(8, function()
			print(
				"|cFF00BFFFOPie|r |cFFFF4444»|r Спасибо за использование моей адаптации под Sirus. Другие аддоны в: -> |cff9aedff|Hhttp:https://discord.gg/wRPF8CCpNV|h[Discord]|h|r")
		end)
	end
	return "remove"
end
function EV:PLAYER_ENTERING_WORLD(_, isReload)
	if isReload and type(OPie_SavedDataPC) == "table" and type(OPie_SavedDataPC.FlagState) == "table" then
		local FM = AB and AB:compatible("FlagMast", 1)
		if FM then
			FM:RestoreState(OPie_SavedDataPC.FlagState)
		end
	end
	if OR_LoadedState == 4 then
		OPie_SavedDataPC = nil
	end
	return "remove"
end
function EV:PLAYER_LOGOUT()
	if OR_LoadedState ~= 4 then
		return
	end
	local pc, pcp = {}, {}
	OPie_SavedData = configRoot
	OR_NotifyPVars("LOGOUT")
	configRoot.CenterActions = OR_PullQuickActions()
	OR_SecProfilePull()
	for k, v in pairs(configInstance) do
		if v == defaultConfig[k] then
			configInstance[k] = nil
		end
	end
	for k, v in pairs(PersistentStorageInfo) do
		local store = v.perProfile and configInstance or configRoot.PersistentStorage
		store[k] = next(v.t) ~= nil and v.t or nil
	end
	for k, v in pairs(configRoot.ProfileStorage) do
		for t in ("RingOptions Bindings Bindings2 RotationTokens _pcStore"):gmatch("%S+") do
			if type(v[t]) ~= "table" or next(v[t]) == nil then
				v[t] = nil
			end
		end
		pcp[k], v._pcStore = securecall(OR_FreezeProfilePerCharSV, v) or nil, nil
	end
	pc.ProfileStorage = next(pcp) ~= nil and pcp or nil
	local FM = AB and AB:compatible("FlagMast", 1)
	pc.FlagState = FM and FM:GetState() or nil
	OPie_SavedDataPC = next(pc) ~= nil and pc or nil
	pc._GameVersion, pc._StoreVersion = configRoot._GameVersion, configRoot._StoreVersion
end
function EV.ACTIVE_TALENT_GROUP_CHANGED()
	local newProfile = getProfileForSpec()
	if newProfile ~= activeProfile then
		OR_SwitchProfile(newProfile)
	end
end
function EV.UPDATE_BINDINGS()
	sfBindsAll = true
	OR_PerfomDelayedSync()
end

local function cmpRingK(a, b)
	a, b = OR_Rings[a], OR_Rings[b]
	local ac, bc = b.sortScope or 0, a.sortScope or 0
	if ac == bc then
		ac, bc = (a.name or a.internalName), (b.name or b.internalName)
	end
	return ac < bc
end
local getProfileIdentComparator
do
	local pt, strcmputf8i = nil, T.compat.strcmputf8i
	local function cmpProfileIdent(a, b)
		local ac, bc = pt[a] or 0, pt[b] or 0
		if ac ~= bc then
			return ac > bc
		end
		return strcmputf8i(a, b) < 0
	end
	function getProfileIdentComparator()
		pt = {}
		for i = 1, getNumSpecs() do
			pt[getProfileForSpec(i) or 0] = 1
		end
		pt[activeProfile or 0] = 2
		pt.default, pt[0] = 3, nil
		return cmpProfileIdent
	end
end
local function retProfiles(n, i)
	if i <= n then
		return getProfileForSpec(i), retProfiles(n, i + 1)
	end
end
local function getRingBindings(ringName, skipDefault)
	local b1c, b1, isUser = configInstance.Bindings[ringName]
	if b1c == nil and not skipDefault then
		b1, isUser = OR_Rings[ringName].hotkey, false
	else
		b1, isUser = b1c, true
	end
	return b1, configInstance.Bindings2[ringName], isUser, b1c
end

function private:GetSVState()
	return OR_LoadedState == 4, OR_LoadedState
end
function private:RegisterOption(name, default, validator)
	assert(type(name) == "string" and default ~= nil and (validator == nil or type(validator) == "function"),
		'Syntax: api:RegisterOption("name", defaultValue[, validatorFunc])', 2)
	assert(name:match("^%a"), '%q is not a valid option name', 2, name)
	assert(defaultConfig[name] == nil and PersistentStorageInfo[name] == nil, "Option %q has a conflicting name", 2,
		name)
	defaultConfig[name], optionValidators[name] = default, validator or false
end
function private:RegisterPVar(name, into, notifier, perProfile)
	assert(type(name) == "string" and (into == nil or type(into) == "table") and
			   (notifier == nil or type(notifier) == "function"),
		'Syntax: api:RegisterPVar("name"[, storageTable[, notifierFunc[, perProfile]]])', 2)
	assert(PersistentStorageInfo[name] == nil and defaultConfig[name] == nil,
		"Persistent variable %q already declared.", 2, name)
	assert(name:match("^%a"), "%q is not a valid persistent variable name", 2, name)
	local store, into = ((perProfile == true) and configInstance or configRoot.PersistentStorage), into or {}
	PersistentStorageInfo[name] = {
		t = into,
		f = notifier,
		perProfile = perProfile == true
	}
	if configInstance then
		if store and store[name] then
			copy(store[name], nil, into)
		end
		OR_NotifyPVars("LOADED", into)
	end
	return into
end
function private:GetOption(option, ringName)
	assert(type(option) == "string" and (ringName == nil or type(ringName) == "string"),
		'Syntax: value, setting, ring, global, default = api:GetOption("option"[, "ringName"])', 2)
	if defaultConfig[option] == nil then
		return
	end
	return OR_GetRingOption(ringName, option)
end
function private:SetOption(option, value, ringName)
	assert(type(option) == "string" and (ringName == nil or type(ringName) == "string"),
		'Syntax: api:SetOption("option", value[, "ringName"])', 2)
	assert(defaultConfig[option] ~= nil, "Option %q is undefined.", 2, option)
	local props = assert(ringName == nil or OR_Rings[ringName], "Ring %q is undefined.", 2, ringName)
	assert(value == nil or type(defaultConfig[option]) == type(value),
		"Type mismatch: %q expected to be a %s (got %s).", 2, option, type(defaultConfig[option]), type(value))
	assert(not optionValidators[option] or optionValidators[option](option, value, ringName) ~= false,
		"Value rejected by option validator.", 2)
	local scope, prefix = ringName and configInstance.RingOptions or configInstance,
		ringName and (ringName .. "#") or ""
	scope[prefix .. option] = value
	if optionValidators[option] == nil then
		if ringName and props then
			props.reSync, sfRingsOne = true, true
		else
			sfRingsAll, sfGlobalOptions = true, true
		end
		OR_PerfomDelayedSync()
	end
end
function private:GetRingBinding(ringName, bidx)
	assert(type(ringName) == "string" and (bidx == nil or bidx == 1 or bidx == 2),
		'Syntax: binding, currentKey, isUserBinding, isActiveInternal, isActiveExternal = api:GetRingBinding("ringName"[, bindingIndex])',
		2)
	local rprop = assert(OR_Rings[ringName], 'Ring %q is not defined', 2, ringName)
	local b1, b2, isUser = getRingBindings(ringName)
	local iid, secK, bindSuffix = rprop.internalID, "bind", ""
	if (b1 ~= nil) == (bidx == 2) then
		b1, isUser, secK, bindSuffix = b2, true, "bind2", "b"
	end
	local secRingData = coreEnvW.ORL_RingData[iid]
	local curKey = secRingData and secRingData[secK]
	local curAct = curKey and GetBindingAction(curKey, true)
	curAct = (curKey == nil) or (curAct == ("CLICK ORL_RProxy" .. iid .. ":r" .. iid .. bindSuffix)) or curAct
	return b1, curKey, isUser, curKey ~= nil, curAct
end
function private:SetRingBinding(ringName, bidx, bind)
	assert(type(ringName) == "string" and (bidx == 1 or bidx == 2) and
			   (type(bind) == "string" or bind == false or bind == nil),
		'Syntax: api:SetRingBinding("ringName", bindingIndex, "binding" or false or nil)', 2)
	local rprop = assert(OR_Rings[ringName], "Ring %q is not defined", 2, ringName)
	local b1, b2, _b1u, b1c = getRingBindings(ringName)
	local niOffset = b2 and b1 == nil and 3 or -1 -- would GetRingBinding rewrite indices?
	local nb1, nb2 = select(niOffset + bidx + bidx, bind, b2, b1c, bind, bind, nil, b2, bind)
	if nb2 and not nb1 and (bidx ~= 2 or b1 == nil) then
		nb1, nb2 = nb2, nil
	elseif nb1 == nb2 then
		nb2 = nil
	end
	nb2 = nb2 or nil
	if (nb1 == b1c and nb2 == b2) or (nb1 == b2 and nb2 == b1c) then
		return
	end
	configInstance.Bindings[ringName], configInstance.Bindings2[ringName] = nb1, nb2
	local obind = b1 ~= nb1 and b1 ~= nb2 and b1 or b2 ~= nb1 and b2 ~= nb2 and b2
	for i = 1, #OR_Rings do
		local ikey = OR_Rings[i]
		local ib1, ib2, ib1u = getRingBindings(ikey)
		if ikey ~= ringName and (bind and (ib1 == bind or ib2 == bind) or obind and (ib1 == obind or ib2 == obind)) then
			if bind then
				if ib2 == bind then
					configInstance.Bindings2[ikey], ib2 = nil, nil
				end
				if ib1 == bind and ib1u then
					configInstance.Bindings[ikey], configInstance.Bindings2[ikey] = ib2, nil
				end
			end
			OR_SyncRingBinding(ikey, OR_Rings[ikey])
		end
	end
	OR_SyncRingBinding(ringName, rprop)
end
function private:ProfileExists(ident)
	return configRoot.ProfileStorage[ident] ~= nil
end
function private:GetAllProfiles()
	if not configInstance then
		return
	end
	local r = {}
	for k in pairs(configRoot.ProfileStorage) do
		r[#r + 1] = k
	end
	table.sort(r, getProfileIdentComparator())
	return r
end
function private:GetSpecProfiles()
	return retProfiles(getNumSpecs(), 1)
end
function private:SetSpecProfiles(...)
	assert(select("#", ...) == getNumSpecs(), 'SetSpecProfiles(...): improper argument count', 2)
	for i = 1, getNumSpecs() do
		configRoot.CharProfiles[getSpecCharIdent(i)] = normalizeStoredProfileIdent(select(i, ...))
	end
	local np = getProfileForSpec()
	if np ~= activeProfile then
		OR_SwitchProfile(np)
	end
end
function private:SwitchProfile(ident, inherit)
	assert(type(ident) == "string" and (inherit == nil or type(inherit) == "boolean" or type(inherit) == "table"),
		'Syntax: api:SwitchProfile("profile"[, deriveFromCurrent or profileData])', 2)
	if type(inherit) == "table" then
		local data = copy(inherit)
		if data._usedBy then
			for _, charid in pairs(data._usedBy) do
				configRoot.CharProfiles[charid] = ident
			end
			data._usedBy = nil
		end
		configRoot.ProfileStorage[ident] = data
	elseif not configRoot.ProfileStorage[ident] then
		configRoot.ProfileStorage[ident] = inherit and copy(configInstance) or {}
	end
	OR_SwitchProfile(ident)
	configRoot.CharProfiles[getSpecCharIdent()] = normalizeStoredProfileIdent(activeProfile)
end
function private:ExportProfile(ident)
	assert(type(ident) == "string" or ident == nil, 'Syntax: profileData = api:ExportProfile(["profile"])', 2)
	assert(ident == nil or configRoot.ProfileStorage[ident], 'Profile %q does not exist.', 2, ident)
	if ident == nil then
		OR_SaveCurrentProfile()
	end
	local data = copy(ident == nil and configInstance or configRoot.ProfileStorage[ident])
	if configRoot.CharProfiles then
		local id, ni, usedBy = ident or activeProfile, 1, {}
		for k, v in pairs(configRoot.CharProfiles) do
			if v == id then
				usedBy[ni], ni = k, ni + 1
			end
		end
		data._usedBy = ni > 1 and usedBy or nil
	end
	return data
end
function private:DeleteProfile(ident)
	assert(type(ident) == "string", 'Syntax: api:DeleteProfile("profile")', 2)
	local oldP = configRoot.ProfileStorage[ident]
	if not oldP then
		return
	end
	if configRoot.CharProfiles then
		for k, v in pairs(configRoot.CharProfiles) do
			if v == ident then
				configRoot.CharProfiles[k] = nil
			end
		end
	end
	configRoot.ProfileStorage[ident] = nil
	if configInstance == oldP then
		private:SwitchProfile("default")
	end
end
function private:ResetRingBindings()
	wipe(configInstance.Bindings)
	wipe(configInstance.Bindings2)
	sfBindsAll = true
	OR_PerfomDelayedSync()
end
function private:ResetOptions(includePerRing)
	assert(type(includePerRing) == "boolean" or includePerRing == nil, "Syntax: api:ResetOptions([includePerRing])", 2)
	for k, v in pairs(defaultConfig) do
		local iv = configInstance[k]
		configInstance[k] = nil
		if optionValidators[k] and (iv ~= nil and iv ~= v) then
			securecall(optionValidators[k], k, v)
		end
	end
	if includePerRing then
		configInstance.RingOptions = {}
	end
	sfRingsAll, sfGlobalOptions = true, true
	OR_PerfomDelayedSync()
end
function private:GetOpenRing(optTable)
	if type(optTable) == "table" then
		for k in pairs(defaultConfig) do
			optTable[k] = OR_GetRingOption(OR_ActiveRingName or "default", k)
		end
	end
	local ar = coreEnvW.activeRing
	return OR_ActiveRingName, OR_ActiveSliceCount, ar and ar.ofsDeg or 0
end
function private:GetOpenRingSlice(id)
	if type(id) ~= "number" or id < 1 or id > OR_ActiveSliceCount then
		return false
	end
	local sbt, act, tok, atype, nestLevel = coreEnvW.activeRing.SliceBinding,
		OR_FindFinalAction(OR_ActiveCollectionID, id)
	local nt = coreEnvW.collections[coreEnvW.collections[OR_ActiveCollectionID][id]]
	return act, tok, sbt and sbt[id], sbt and sbt[id + 0.5], nt and #nt or 0, atype, nestLevel and nestLevel > 1
end
function private:GetOpenRingSliceAction(id, id2)
	if id < 1 or id > OR_ActiveSliceCount then
		return
	end
	local s, tok, atype, nestLevel = OR_FindFinalAction(OR_ActiveCollectionID, id,
		id2 and coreEnvW.ctokens[OR_ActiveCollectionID][id] or nil, (id2 or 1) - 1)
	if type(s) == "number" then
		if atype == "jump" then
			local icon, aid, tok2, _ = nil, OR_FindFinalAction(s, 1, nil, 0, true)
			if type(aid) == "number" then
				_, _, icon = AB:GetSlotInfo(aid, OR_ModifierLockState)
			end
			local rid = coreEnvW.ORL_RingData[coreEnvW.ORL_KnownCollections[s]]
			rid = OR_Rings[rid and rid.name]
			local rname = rid and rid.name
			return tok, true, nestLevel and nestLevel > (id2 and 2 or 1) and 4096 + 8192 or 4096, icon or RING_ICON,
				rname or L "Open nested ring", tok2, 0, 0
		end
		return tok, AB:GetSlotInfo(s, OR_ModifierLockState)
	end
	return tok, false, 0, [[Interface\Icons\INV_Misc_QuestionMark]], "Unknown Slice", 0, 0, 0
end
function private:IsOpenRingSliceBinding(id, action)
	local cid = action and string.match(action, SLICE_BIND_PATTERN)
	return true == (cid and cid + 0 == id)
end
function private:GetCurrentInputs()
	if coreEnvW.AI_NoPointer then
		return "nopoint", nil, 0, false
	end
	local aframe, cx, cy = OR_SecCore, GetCursorPosition()
	local scale, l, b, w, h = aframe:GetEffectiveScale(), aframe:GetRect()
	local dx, dy = (cx / scale) - (l + w / 2), (cy / scale) - (b + h / 2)
	local radius2 = dx * dx + dy * dy
	local isActiveRadius, isCenterRadius = radius2 >= 1600, radius2 <= 400

	local aidx, qidx = coreEnvW.fastClick, nil
	if aidx then
		local ar = coreEnvW.activeRing
		if ar.MotionAction and coreEnvW.AI_MotionArmedFC then
			qidx = aidx
		elseif ar.CenterAction and isCenterRadius then
			qidx = aidx
		end
	end
	return "cursor", qidx, atan2(dy, dx) % 360, isActiveRadius
end
function private:RegisterExtAction(ident, createFunc, describeFunc)
	assert(type(ident) == "string" and type(createFunc) == "function" and type(describeFunc) == "function",
		'Syntax: api:RegisterExtAction("ident", createFunc, describeFunc)', 2)
	return registerExtAction(ident, createFunc, describeFunc)
end

-- Public API
function api:SetRing(name, actionId, props)
	assert(type(name) == "string" and (actionId == nil or (type(props) == "table" or type(actionId) == "number")),
		'Syntax: OPie:SetRing("ringName"[, actionId, propsTable])', 2)
	if actionId then
		OR_SyncRing(name, actionId, props)
	elseif OR_Rings[name] then
		OR_DeleteRing(name, OR_Rings[name])
	end
end
function api:GetNumRings()
	return #OR_Rings
end
function api:GetRingInfo(ring)
	assert(type(ring) == "number" or type(ring) == "string",
		'Syntax: name, key, macro, flags = OPie:GetRingInfo(index or "ringName")', 2)
	local key = type(ring) == "string" and OR_Rings[ring] and ring or OR_Rings[ring]
	if not key then
		return
	end
	local props = OR_Rings[key]
	return props.name, key, SLASH_CLICK1 .. " " .. OR_OpenProxy:GetName() .. " " .. key, (props.internal and 1 or 0)
end
function api:IterateRings(includeInternalRings)
	local ot = {}
	for i = 1, #OR_Rings do
		local props = OR_Rings[OR_Rings[i]]
		if props and (includeInternalRings or not props.internal) then
			ot[#ot + 1] = OR_Rings[i]
		end
	end
	table.sort(ot, cmpRingK)
	local p, props = 1
	return function()
		props, p = OR_Rings[ot[p]], p + 1
		if props then
			return props.internalName, props.name or props.internalName, props.sortScope, props.internal and 1 or 0
		end
	end
end
function api:IsKnownRingName(ringName)
	assert(type(ringName) == "string", 'Syntax: isKnown = OPie:IsKnownRingName("ringName")', 2)
	if OR_Rings[ringName] then
		return true
	end
	for _, v in pairs(configRoot.ProfileStorage) do
		if type(v.Bindings) == "table" and v.Bindings[ringName] then
			return true
		end
	end
	return false
end
function api:GetCurrentProfile()
	return activeProfile
end
function api:GetVersion()
	return GetAddOnMetadata(ADDON, "Version") or "?", MAJ, REV
end

-- HIDDEN, UNSUPPORTED METHODS: May vanish at any time.
local hum = {
	NotGameTooltip = T.NotGameTooltip
}
setmetatable(api, {
	__index = hum
})
hum.HUM = hum
hum.GetOption = private.GetOption
hum.GetRingBinding = private.GetRingBinding
hum.GetOpenRing = private.GetOpenRing
hum.GetOpenRingSlice = private.GetOpenRingSlice
hum.GetOpenRingSliceAction = private.GetOpenRingSliceAction
function hum:OverrideRingBinding(ringName, bind)
	assert(type(ringName) == "string" and (bind == nil or type(bind) == "string"),
		'Syntax: api:OverrideRingBinding("ringName", "binding")', 2)
	local id = assert(OR_Rings[ringName], 'Ring %q is not defined', 2, ringName).internalID
	if coreEnvW.bindOverrides[id] ~= bind then
		WR.Run(coreEnvW, coreEnvW.ORL_RegisterOverride, id, bind)
	end
end
function hum:SetRingOpensAtMousePreference(ringName, pref)
	assert(type(ringName) == "string" and type(pref) == "boolean",
		'Syntax: api:SetRingOpensAtMousePreference("ringName", preferAtMouse)')
	if select(3, OR_GetRingOption(ringName, "RingAtMouse")) == nil then
		private:SetOption("RingAtMouse", pref, ringName)
	end
end
hum.GetSVState = private.GetSVState

for k, v in pairs(api) do
	if private[k] == nil then
		private[k] = v
	end
end

_G.OPie, T.OPieCore = api, private
