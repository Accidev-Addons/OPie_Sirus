local ADDON, T = ...
local GetPhysicalScreenSize = GetPhysicalScreenSize or function()
	local w, h = string.match((({GetScreenResolutions()})[GetCurrentResolution()] or ""), "(%d+).-(%d+)")
	return tonumber(w) or 1024, tonumber(h) or 768
end
local PC, EV, XU, GameTooltip, L = T.OPieCore, T.Evie, T.exUI, T.NotGameTooltip or GameTooltip, T.L
local IsMetaKeyDown, C_KeyBindings = T.compat.IsMetaKeyDown, T.compat.C_KeyBindings
local api, iapi, configCache, vis = {}, {}, {}, {}
local max, min, abs, floor, sin, cos = math.max, math.min, math.abs, math.floor, sin, cos
local MIN_ANIMATION_FPS, LOCKED_FRAMERATE = 20, 60
do
	local ticks = 0
	local function unlockTick()
		if ticks < 2 then
			ticks = ticks + 1
			EV.After(0.55, unlockTick)
		else
			LOCKED_FRAMERATE = nil
		end
	end
	EV.After(0, unlockTick)
end
local Slices, GhostIndication, IndicatorFactories = {}, {}, {}
local ActiveIndicatorFactory, LastRegisteredIndicatorFactory

local function assert(condition, text, level)
	return condition or error(text, (level or 1) + 1)((0)[0])
end
local CreateQuadTexture
do
	local function qf(f)
		return function(self, ...)
			for i = 1, 4 do
				local v = self[i]
				v[f](v, ...)
			end
		end
	end
	local quadPoints, quadTemplate = {"BOTTOMRIGHT", "BOTTOMLEFT", "TOPLEFT", "TOPRIGHT"}, {
		__index = {
			SetVertexColor = qf("SetVertexColor"),
			SetAlpha = qf("SetAlpha"),
			SetShown = qf("SetShown")
		}
	}
	function CreateQuadTexture(layer, size, file, parent, qparent)
		local group, size = setmetatable({}, quadTemplate), size / 2
		for i = 1, 4 do
			local tex, d, l = (parent or qparent[i]):CreateTexture(nil, layer), i > 2, 2 > i or i > 3
			tex:SetSize(size, size)
			tex:SetTexture(file)
			tex:SetTexCoord(l and 0 or 1, l and 1 or 0, d and 1 or 0, d and 0 or 1)
			tex:SetPoint(quadPoints[i], parent or qparent[i], parent and "CENTER" or quadPoints[i])
			group[i] = tex
		end
		return group
	end
	T.CreateQuadTexture = CreateQuadTexture
end
local CreateIndicator
do
	local gx
	do
		local b = ([[Interface\AddOns\%s\gfx\]]):format(ADDON)
		gx = {
			BorderLow = b .. "borderlo",
			BorderHigh = b .. "borderhi",
			OuterGlow = b .. "oglow",
			InnerGlow = b .. "iglow",
			Ribbon = b .. "ribbon",
			CooldownStar = [[Interface\cooldown\star4]],
			CooldownSpark = b .. "spark"
		}
	end
	function CreateIndicator(name, parent, size, nested)
		return XU:Create("OPie:MirageIndicator", name, parent, size, nested, gx)
	end
end

local gfxBase = ([[Interface\AddOns\%s\gfx\]]):format((...))
local JUMP_ICON = gfxBase .. "opie_ring_icon"
local mainAnchor, proxyAnchor = CreateFrame("Frame"), CreateFrame("Frame")
for i = 1, 2 do
	i = i == 1 and mainAnchor or proxyAnchor
	i:SetSize(1, 1)
	i:SetPoint("CENTER")
	i:Hide()
end
local proxyFrame = CreateFrame("Frame", "OPieVisualElementsProxy", UIParent)
local mainFrame = CreateFrame("Frame", nil, UIParent)
for i = 1, 2 do
	local f = i == 1 and proxyFrame or mainFrame
	f:Hide()
	f:SetSize(150, 150)
	f:SetFrameStrata("FULLSCREEN")
	f:SetFrameLevel(50 * i)
	f:SetPoint("CENTER", i == 1 and proxyAnchor or mainAnchor)
end
local centerPointer = mainFrame:CreateTexture(nil, "ARTWORK")
centerPointer:SetSize(192, 192)
centerPointer:SetPoint("CENTER")
centerPointer:SetTexture(gfxBase .. "pointer")
local ringQuad, setRingRotationPeriod, centerCircle, centerGlow = {}
do
	local quadPoints, animations = {"BOTTOMRIGHT", "BOTTOMLEFT", "TOPLEFT", "TOPRIGHT"}, {}
	for i = 1, 4 do
		local qf = CreateFrame("Frame", nil, mainFrame)
		qf:SetSize(32, 32)
		qf:SetPoint(quadPoints[i], mainFrame, "CENTER")
		ringQuad[i] = qf
	end
	centerCircle = CreateQuadTexture("ARTWORK", 64, gfxBase .. "circle", nil, ringQuad)
	centerGlow = CreateQuadTexture("BACKGROUND", 128, gfxBase .. "glow", nil, ringQuad)
	for i = 1, 4 do
		local g, a = ringQuad[i]:CreateAnimationGroup()
		g:SetLooping("REPEAT")
		a = g:CreateAnimation("Rotation")
		a:SetOrigin(quadPoints[i], 0, 0)
		a:SetDuration(4)
		a:SetDegrees(-360)
		animations[i] = a
		g:Play()
	end
	function setRingRotationPeriod(p)
		local p = max(0.1, p)
		for i = 1, 4 do
			animations[i]:SetDuration(p)
		end
	end
end
local function setIndicationPosition(rel, ox, oy)
	mainAnchor:SetPoint("CENTER", nil, rel, ox, oy)
	proxyAnchor:ClearAllPoints()
	proxyAnchor:SetPoint("CENTER", nil, rel, ox, oy)
end
local function setIndicationScale(sc)
	mainFrame:SetScale(sc)
	proxyFrame:SetScale(sc)
end
local function setIndicationAlpha(alpha)
	mainFrame:SetAlpha(alpha)
	proxyFrame:SetAlpha(alpha)
end
local function setIndicationShown(shown)
	mainFrame:SetShown(shown)
	proxyFrame:SetShown(shown)
end
local function setAngle(self, angle, radius)
	self:SetPoint("CENTER", radius * cos(90 + angle), radius * cos(angle))
end
local function calculateRingRadius(n, fLength, aLength, min, baseAngle)
	if n < 2 then
		return min
	end
	local radius, mLength, astep = max(min, (fLength + aLength * (n - 1)) / 6.2831853071796), (fLength + aLength) / 2,
		360 / n
	repeat
		local ox, oy, clear, angle, i = radius * cos(baseAngle), radius * sin(baseAngle), true, baseAngle + astep, 1
		while clear and i <= n do
			local nx, ny, sideLength = radius * cos(angle), radius * sin(angle),
				(i == 1 or i == n) and mLength or aLength
			if abs(ox - nx) < sideLength and abs(oy - ny) < sideLength then
				radius, clear = radius + 5
			end
			ox, oy, angle, i = nx, ny, angle + astep, i + 1
		end
	until clear
	return radius
end
local function setupTransitionAnimation(anim, uf)
	local fps, _, screenHeight = LOCKED_FRAMERATE or GetFramerate(), GetPhysicalScreenSize()
	local radiusRaw, hadOnUpdate = vis.radius, mainFrame:IsVisible() and mainFrame:GetScript("OnUpdate")
	local radiusPix = (34 + radiusRaw) * UIParent:GetEffectiveScale() * configCache.RingScale / 768 * screenHeight
	local zoomTime = configCache.XTAnimation and fps >= MIN_ANIMATION_FPS and 0.25 or 0
	local miZoomScale = 140 * zoomTime * fps * radiusPix ^ -1.375
	configCache.XTZoomTime = zoomTime
	configCache.MIZoomInScale = max(0.25, min(1.5, miZoomScale))
	configCache.MIZoomOutScale = max(0.4, min(0.75, 0.4 * miZoomScale))
	configCache.MISpinOutProg = 150 * max(0.15, min(1, fps * fps * fps / 216000))
	configCache.MIScaleAdd = configCache.MIScale and (radiusRaw > 200 and 0.05 or 0.10) or 0
	vis.eleft = anim == "fast-in" and 0.5 * zoomTime or zoomTime
	mainFrame:SetScript("OnUpdate", uf)
	uf(mainFrame, hadOnUpdate and 0 or 1 / 60)
end
local function notifyAlpha(p, wa, wc, ws)
	local nf = ActiveIndicatorFactory.onParentAlphaChanged
	local pea = nf and p:GetEffectiveAlpha()
	for i = ws or 1, nf and wc or 0 do
		nf(wa[i], pea)
	end
end

do -- GhostIndication
	local spareGroups, spareSlices, currentGroups, visibleGroups, activeGroup = {}, {}, {}, {}
	local function AnimateHide(self, elapsed)
		local et, zoomTime = self.expire, configCache.XTZoomTime
		et = et and (et - elapsed) or zoomTime
		if et <= 0 then
			visibleGroups[self], self.expire = nil
			self:Hide()
		else
			self.expire = et
			self:SetAlpha(et <= zoomTime and et / zoomTime or 1)
			notifyAlpha(self, self, self.count, 2)
		end
	end
	local function AnimateShow(self, elapsed)
		local et, zoomTime = self.expire, configCache.XTZoomTime
		et = et and (et - elapsed) or (zoomTime + configCache.GhostShowDelay)
		if et <= 0 then
			visibleGroups[self], self.expire = false, nil
			self:SetAlpha(1)
		else
			self.expire = et
			self:SetAlpha(et > zoomTime and 0 or (1 - et / zoomTime))
		end
		notifyAlpha(self, self, self.count, 2)
	end
	local function newGhostGroup()
		local f = CreateFrame("Frame", nil, mainFrame)
		f:SetSize(1, 1)
		f:SetScale(0.80)
		f:Hide()
		return f
	end
	function GhostIndication:ActivateGroup(index, count, incidentAngle, mainRadius)
		local ret = currentGroups[index] or next(spareGroups) or newGhostGroup()
		currentGroups[index], spareGroups[ret] = ret
		if not ret:IsShown() then
			visibleGroups[ret], ret.expire = AnimateShow, nil
			AnimateShow(ret, 0)
			ret:Show()
		end
		if activeGroup ~= ret then
			GhostIndication:Deactivate()
		end
		if ret.incident ~= incidentAngle or ret.count ~= count then
			local radius, angleStep = calculateRingRadius(count, configCache.MIReserveSize, 48 * 0.80, 30,
				incidentAngle - 180) / 0.80, 360 / count
			local angle = incidentAngle - angleStep + 90
			for i = 2, count do
				local cell = ret[i] or next(spareSlices) or CreateIndicator(nil, ret, 48, true)
				cell:SetParent(ret)
				setAngle(cell, angle, radius)
				cell:SetShown(true)
				ret[i], angle, spareSlices[cell] = cell, angle - angleStep
			end
			for i = count + 1, ret.count or 0 do
				local cell = ret[i]
				cell:SetShown(false)
				spareSlices[cell], ret[i] = cell, nil
			end
			ret.incident, ret.count = incidentAngle, count
			ret:SetPoint("CENTER", (mainRadius / 0.80 + radius) * cos(incidentAngle),
				(mainRadius / 0.80 + radius) * sin(incidentAngle))
			ret:Show()
		end
		activeGroup = ret
		return ret
	end
	function GhostIndication:Deactivate()
		if activeGroup then
			visibleGroups[activeGroup], activeGroup.expire = AnimateHide, nil
			activeGroup = nil
		end
	end
	function GhostIndication:Reset()
		for k, g in pairs(currentGroups) do
			g:Hide()
			for i = 2, g.count or 0 do
				g[i]:SetShown(false)
				spareSlices[g[i]], g[i] = g[i]
			end
			spareGroups[g], currentGroups[k], visibleGroups[g], g.incident, g.count = g
		end
		activeGroup = nil
	end
	function GhostIndication:SwitchSparePool(pool)
		self:Reset()
		spareSlices = pool
	end
	function GhostIndication:OnUpdate(elapsed)
		for g, af in pairs(visibleGroups) do
			if af then
				af(g, elapsed)
			end
		end
	end
	function GhostIndication:NotifyAlpha()
		for g in pairs(visibleGroups) do
			notifyAlpha(g, g, g.count, 2)
		end
	end
end

local SwitchIndicatorFactory, ValidateIndicator
do
	local CURRENT_API_LEVEL, REQ_API_LEVEL, CURRENT_API_LEVEL_OOD = 4, 3, 3
	local RequiredIndicatorMethods = {
		SetPoint = 0,
		SetScale = 0,
		GetScale = 0,
		SetShown = 0,
		SetParent = 0,
		SetIcon = 0,
		SetIconTexCoord = 0,
		SetIconAtlas = 3,
		SetIconVertexColor = 0,
		SetDominantColor = 0,
		SetOverlayIcon = 0,
		SetOverlayIconVertexColor = 1,
		SetUsable = 0,
		SetCount = 0,
		SetBinding = 0,
		SetCooldown = 0,
		SetCooldownTextShown = "supportsCooldownNumbers",
		SetShortLabel = "supportsShortLabels",
		SetEquipState = 0,
		SetHighlighted = 0,
		SetActive = 0,
		SetOuterGlow = 0
	}
	function ValidateIndicator(apiLevel, reqAPILevel, info)
		if apiLevel < REQ_API_LEVEL or (reqAPILevel or apiLevel) > CURRENT_API_LEVEL then
			return false, "API level " .. apiLevel .. " is not supported (current is " .. CURRENT_API_LEVEL .. ")"
		end
		local f = info.CreateIndicator(nil, mainFrame, 48)
		for k, v in pairs(RequiredIndicatorMethods) do
			local tv = type(v)
			if type(f[k]) ~= "function" and ((tv == "number" and apiLevel >= v) or (tv == "string" and info[v])) then
				return false, ("Expected a function for indicator key %q, got %s."):format(k, type(f[k]))
			end
		end
		return {
			[f] = true
		}
	end
	function SwitchIndicatorFactory(iakey)
		local iakey = (iakey == nil or iakey == "_") and LastRegisteredIndicatorFactory or iakey
		local finfo = IndicatorFactories[iakey]
		if not (finfo and finfo.CreateIndicator) then
			finfo, iakey = IndicatorFactories.mirage, "mirage"
		end
		if finfo ~= ActiveIndicatorFactory then
			local oldPool = ActiveIndicatorFactory and ActiveIndicatorFactory.mainPool
			for k, v in pairs(Slices) do
				oldPool[v], Slices[k] = true, nil
				v:SetShown(false)
			end
			setIndicationShown(false)
			CreateIndicator, ActiveIndicatorFactory = finfo.CreateIndicator, finfo
			GhostIndication:SwitchSparePool(finfo.ghostPool)
		end
	end
	local function nextRIC(_, key)
		if key == "_" then
			return
		end
		local nk, nv = next(IndicatorFactories, key)
		if nk then
			return nk, nv.name, nv.apiLevel < CURRENT_API_LEVEL_OOD or nv.err ~= nil, nv.err
		end
		return "_", IndicatorFactories[LastRegisteredIndicatorFactory].name, false
	end
	function iapi:EnumerateRegisteredIndicatorConstructors()
		return nextRIC
	end
	function iapi:DoesIndicatorConstructorSupport(key, feature)
		if key == nil or key == "_" then
			key = LastRegisteredIndicatorFactory
		end
		if not (IndicatorFactories[key] and IndicatorFactories[key].CreateIndicator) then
			key = LastRegisteredIndicatorFactory or "mirage"
		end
		return not not IndicatorFactories[key]["supports" .. feature]
	end
	function iapi:GetIndicatorConstructorName(key)
		if key == nil or key == "_" then
			key = LastRegisteredIndicatorFactory
		end
		local ic = IndicatorFactories[key]
		return ic and ic.name, ic and ic.CreateIndicator and true
	end
	function iapi:HasMultipleIndicatorConstructors()
		return nil ~= next(IndicatorFactories, (next(IndicatorFactories)))
	end
end

local tokenR, tokenG, tokenB, tokenIcon, tokenLabel, iconIsAtlas, tokenQuest = {}, {}, {}, {}, {}, {}, {}
local atlasRatio = setmetatable({}, {
	__index = function(t, k)
		local i, r = k and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(k), 1
		if i then
			r = i.width / i.height
			t[k] = r
		end
		return r
	end
})
local MOD_PREFIX = {
	[0] = ""
}
do
	for i = 1, 15 do
		MOD_PREFIX[i] =
			(i % 2 < 1 and "" or "ALT-") .. (i % 4 < 2 and "" or "CTRL-") .. (i % 8 < 4 and "" or "SHIFT-") ..
				(i < 8 and "" or "META-")
	end
end
local function GetModifierKeyState()
	return (IsAltKeyDown() and 1 or 0) + (IsControlKeyDown() and 2 or 0) + (IsShiftKeyDown() and 4 or 0) +
			   (IsMetaKeyDown() and 8 or 0)
end
local function IsSliceBindingConflicted(slice, bind, modState)
	local bindKey, bindMod = bind and bind:match("[^-]*.?$"), modState
	if bindKey and bindKey ~= bind then
		local prefix = bind:sub(1, -#bindKey - 1)
		bindMod = MOD_PREFIX[prefix] or
					  ((bind:match("ALT%-") and 1 or 0) + (bind:match("CTRL%-") and 2 or 0) +
						  (bind:match("SHIFT%-") and 4 or 0) + (bind:match("META%-") and 8 or 0))
		MOD_PREFIX[prefix], bindMod = bindMod, bit.bor(modState, bindMod)
	end
	local b = bindKey and C_KeyBindings.GetBindingByKey(MOD_PREFIX[bindMod] .. bindKey)
	return b and not PC:IsOpenRingSliceBinding(slice, b) and tostring(_G["BINDING_NAME_" .. b] or b) or nil
end

local getSliceColor, setIconColorOverride
do
	local overR, overG, overB = {}, {}, {}
	function getSliceColor(token, icon, token2)
		if tokenR[token] then
			return tokenR[token], tokenG[token], tokenB[token]
		elseif tokenR[token2] then
			return tokenR[token2], tokenG[token2], tokenB[token2]
		elseif overR[icon] then
			return overR[icon], overG[icon], overB[icon]
		end
		return 0.7, 1, 0.6
	end
	function setIconColorOverride(icon, r, g, b)
		overR[icon], overG[icon], overB[icon] = r, g, b
	end
end
local checkTipThrottle
do
	local throttleEnd, lastF, lastA = -2 ^ 40
	function checkTipThrottle(owner, f, a, t)
		local ret = f and a and lastF == f and lastA == a and throttleEnd > t and GameTooltip:IsOwned(owner)
		lastF, lastA, throttleEnd = f, a, ret and throttleEnd or (t + 0.0625)
		return ret
	end
end
local function applyExtIconCoord(self, ext)
	local t = type(ext.iconCoords)
	if t == "table" then
		self:SetIconTexCoord(unpack(ext.iconCoords))
	elseif t == "function" then
		self:SetIconTexCoord(ext.iconCoords())
	end
end
local function applyExtIconVertexColor(self, ext)
	local r, g, b = ext.iconR, ext.iconG, ext.iconB
	if type(r) == "number" and type(g) == "number" and type(b) == "number" then
		self:SetIconVertexColor(r, g, b)
		return true
	end
end
local function anchorTooltip(tt, owner, at, angle)
	if tt:IsOwned(owner) then
		tt:ClearLines()
	elseif at == "side" then
		tt:SetOwner(owner, "ANCHOR_NONE")
	else
		GameTooltip_SetDefaultAnchor(tt, owner)
	end
	if at == "side" then
		local left, s = angle < 280 and angle > 80, configCache.RingScale
		if vis[left and "noTL" or "noTR"] then
			left = not left
		end
		tt:ClearAllPoints()
		tt:SetPoint(left and "LEFT" or "RIGHT", proxyFrame, "CENTER", (vis.radius + 60) * (left and s or -s), 0)
	end
end
local function updateCentralElements(_self, si, _, tok, usable, state, icon, caption, _, cd, cd2, tipFunc, tipArg, _,
	stext)
	local osi, time = vis.oldSlice, GetTime()
	vis.oldSlice = si

	if tok then
		local r, g, b = getSliceColor(tok, tokenIcon[tok] or icon or "Interface/Icons/INV_Misc_QuestionMark")
		centerPointer:SetVertexColor(r, g, b, 0.9)
		centerCircle:SetVertexColor(r, g, b, 0.9)
		centerGlow:SetVertexColor(r, g, b)
	elseif si ~= osi then
		centerPointer:SetVertexColor(1, 1, 1, 0.1)
		centerCircle:SetVertexColor(1, 1, 1, 0.3)
		centerGlow:SetVertexColor(0.75, 0.75, 0.75)
	end

	if configCache.UseGameTooltip then
		if not (tipFunc and tipArg) then
			local text = caption and caption ~= "" and caption or tokenLabel[tok] or stext
			tipFunc, tipArg = text and GameTooltip.AddLine, text
		end
		if tipFunc then
			local bindConflict = vis.sliceBindConflict[si]
			if not checkTipThrottle(proxyFrame, tipFunc, tipArg, time) then
				anchorTooltip(GameTooltip, proxyFrame, configCache.TooltipAnchor, vis.angle)
				tipFunc(GameTooltip, tipArg)
				if bindConflict then
					GameTooltip:AddLine("\n|cffff0000" .. (L "Slice binding conflicts with %s."):format(bindConflict),
						1, 0, 0, 1)
				end
				GameTooltip:Show()
			end
		elseif GameTooltip:IsOwned(proxyFrame) then
			GameTooltip:Hide()
		end
	end

	local sm = state and (state % 4 > 1) and 0.625 or 1
	if vis.rotPeriod ~= sm then
		vis.rotPeriod = sm
		setRingRotationPeriod(configCache.XTRotationPeriod * sm)
	end
	local sUsable = usable or (state and usable ~= false) or false
	local glowAlpha = sUsable and 0.75 or 0
	local GLOW_FADE_TIME, gTarget, gEnd = 0.3, vis.glowTarget, vis.glowEnd
	if gTarget ~= glowAlpha then
		gTarget, gEnd = glowAlpha, time + GLOW_FADE_TIME - (gEnd and gEnd > time and (gEnd - time) or 0)
		vis.glowTarget, vis.glowEnd = gTarget, gEnd
	end
	if not gEnd then
	elseif gEnd > time then
		local r = (gEnd - time) / GLOW_FADE_TIME
		local a = gTarget > 0 and gTarget * (1 - r) or (0.75 * r)
		centerGlow:SetAlpha(a > 0 and a or 0)
	else
		centerGlow:SetAlpha(gTarget)
		vis.glowEnd = nil
	end
end
local function updateSlice(self, originAngle, selected, tok, usable, state, icon, _, count, cd, cd2, _tf, _ta, ext,
	stext)
	local isJump, origIcon, tokIcon, jumpOtherTok, isJumpIconOverlay, isAtlasIcon = false, icon, tokenIcon[tok]
	state, usable, ext = state or 0, usable or (state and usable ~= false) or false, not tokenIcon[tok] and ext or nil
	if state % 8192 >= 4096 then
		icon, jumpOtherTok, isJump, count = JUMP_ICON, count, true, 0
	end
	icon = tokIcon or icon or "Interface/Icons/INV_Misc_QuestionMark"
	isJumpIconOverlay, isAtlasIcon = isJump and icon == JUMP_ICON, icon == origIcon and state % 524288 >= 262144 or
		tokIcon and icon == tokIcon and iconIsAtlas[icon]
	local active, overlay, faded, isRecharge = state % 2 >= 1, state % 4 >= 2, not usable, state % 128 >= 64
	local isInContainer, isInInventory, isQuestStartItem = state % 256 >= 128, state % 512 >= 256,
		tokenQuest[tok] or (state % 64 >= 32)
	local isDisenchanting = state % 262144 >= 131072
	local onCooldown, noMana, noRange = cd and cd > 0, state % 16 >= 8, state % 32 >= 16
	local usableCharge = usable or isRecharge
	cd2 = cd and cd2 or nil
	self[isAtlasIcon and "SetIconAtlas" or "SetIcon"](self, icon, isAtlasIcon and atlasRatio[icon] or 1)
	if ext then
		securecall(applyExtIconCoord, self, ext)
	end
	if not (ext and securecall(applyExtIconVertexColor, self, ext)) then
		self:SetIconVertexColor(1, 1, 1)
	end
	local dr, dg, db = getSliceColor(tok, isJumpIconOverlay and origIcon or icon, jumpOtherTok)
	self:SetUsable(usable, usableCharge, onCooldown, noMana, noRange)
	self:SetDominantColor(dr, dg, db)
	self:SetOuterGlow(overlay)
	if isJumpIconOverlay then
		local isNestedJump = state % 16384 >= 8192
		local cx, cy, cr = 128 / 256, 45 / 256, 0.53 * 0.45 -- l, r, t, b = 97/256, 159/256, 14/256, 76/256
		local a1, x1, x2, x3, x4, y1, y2, y3, y4 = (isNestedJump and -45 or 135) - originAngle
		x1, y1 = cx + cr * cos(a1), cy - cr * sin(a1)
		x2, y2 = cx + cr * cos(a1 + 90), cy - cr * sin(a1 + 90)
		x3, y3 = cx + cr * cos(a1 + 180), cy - cr * sin(a1 + 180)
		x4, y4 = cx + cr * cos(a1 + 270), cy - cr * sin(a1 + 270)
		self:SetOverlayIcon(gfxBase .. "pointer", 40, 40, x2, y2, x3, y3, x1, y1, x4, y4)
		self:SetOverlayIconVertexColor(dr, dg, db)
	elseif isDisenchanting then
		self:SetOverlayIcon("Interface/Buttons/UI-GroupLoot-DE-Up", 20, 20)
		self:SetOverlayIconVertexColor(1, 1, 1)
	else
		self:SetOverlayIcon(isQuestStartItem and "Interface\\MINIMAP\\TRACKING\\OBJECTICONS", 21, 28, 40 / 256,
			64 / 256, 32 / 64, 1)
		self:SetOverlayIconVertexColor(1, 1, 1)
	end
	if ActiveIndicatorFactory.supportsShortLabels then
		self:SetShortLabel(configCache.ShowShortLabels and (tokenLabel[tok] or stext) or "")
	end
	local hideCount = configCache.ShowOneCount and 0 or 1
	local showCount = (count or 0) > hideCount
	self:SetCount(showCount and count)
	self:SetCooldown(cd, cd2, usableCharge)
	self:SetEquipState(isInContainer, isInInventory)
	self:SetActive(active)
	self:SetHighlighted(selected and not faded)
end
local ambiguateToken, wipeTokenCache
do
	local cache = {}
	function ambiguateToken(tok, ...)
		local atok = cache[tok]
		if atok == nil and type(tok) == "string" then
			atok = tok:match("^[^:]+")
			cache[tok] = atok
		end
		return atok or tok, ...
	end
	function wipeTokenCache()
		wipe(cache)
	end
end
local function callElementUpdate(self, f, si, ni, a1, a2)
	return true, f(self, a1, a2, ambiguateToken(PC:GetOpenRingSliceAction(si, ni)))
end
vis.sliceBindConflict = {}
local function updateSliceBindings(imode, curModState)
	local showSliceBinds, useSliceBinds = configCache.ShowKeys,
										  configCache.SliceBinding or configCache.InteractionMode == 3
	curModState = curModState or GetModifierKeyState()
	imode = showSliceBinds and (imode or PC:GetCurrentInputs())
	local _, sliceBind, sliceBind2, c1, c2
	for i = 1, vis.count do
		if useSliceBinds then
			_, _, sliceBind, sliceBind2 = PC:GetOpenRingSlice(i)
			c1, c2 = IsSliceBindingConflicted(i, sliceBind, curModState),
				IsSliceBindingConflicted(i, sliceBind2, curModState)
			if c2 then
				sliceBind2 = nil
			end
			if c1 then
				sliceBind, sliceBind2 = sliceBind2, nil
			end
			vis.sliceBindConflict[i] = (c1 and c2 and '"|cffffffff' .. c1 .. '|r", "|cffffffff' .. c2 .. '|r"') or
										   (c1 or c2) and ('"|cffffffff' .. (c1 or c2) .. '|r"') or nil
		else
			vis.sliceBindConflict[i] = nil
		end
		Slices[i]:SetBinding(showSliceBinds and (sliceBind or sliceBind2) or nil)
	end
	configCache.lastBindingMode = imode
end

local function forceMultiUpdate()
	vis.schedMultiUpdate = 0
end
local function OnUpdate_CheckAlpha(self, count)
	local ea = self:GetEffectiveAlpha()
	if vis.oldEA ~= ea then
		vis.oldEA = ea
		notifyAlpha(self, Slices, count)
		GhostIndication:NotifyAlpha()
	end
end
local function OnUpdate_Main(self, elapsed)
	local count, offset, lastBindingMode = vis.count, vis.offset, configCache.lastBindingMode
	local imode, qaid, angle, isActiveRadius = PC:GetCurrentInputs()
	local radius, miScaleAdd, frameRate = vis.radius, configCache.MIScaleAdd, LOCKED_FRAMERATE or GetFramerate()

	if qaid and count > 0 then
		angle = (90 - offset - (qaid - 1) * 360 / count) % 360
	end

	local oangle = qaid and angle or vis.angle or angle
	local adiff, arate = min((angle - oangle) % 360, (oangle - angle) % 360)
	if adiff > 60 then
		arate = 420 + 120 * sin(min(90, adiff - 60))
	elseif adiff > 15 then
		arate = 180 + 240 * sin(min(90, max((adiff - 15) * 2, 0)))
	else
		arate = 20 + 160 * sin(min(90, adiff * 6))
	end
	local abound = configCache.XTPointerSnap and 360 or (1.25 * arate / frameRate)
	local arotDirection = ((oangle - angle) % 360 < (angle - oangle) % 360) and -1 or 1
	vis.angle = (adiff < abound or frameRate < MIN_ANIMATION_FPS) and angle or (oangle + arotDirection * abound) % 360
	centerPointer:SetRotation(vis.angle / 180 * 3.1415926535898 - 90 / 180 * 3.1415926535898)

	local modState = GetModifierKeyState()
	local modStateChanged, mut = vis.omState ~= modState, vis.schedMultiUpdate or 0
	if modStateChanged or lastBindingMode and lastBindingMode ~= imode then
		updateSliceBindings(imode, modState)
	end

	local si = qaid or (count <= 0 and 0) or isActiveRadius and
				   (floor(((90 - angle - offset) * count / 360 + 0.5) % count) + 1) or 0
	securecall(callElementUpdate, self, updateCentralElements, si, nil, si)

	if count == 0 then
		return
	elseif miScaleAdd > 0 then
		local limit = frameRate >= 40 and 10 * miScaleAdd / frameRate or miScaleAdd
		for i = 1, count do
			local s, new = Slices[i], i == si and miScaleAdd + 1 or 1
			local old = s:GetScale()
			local d = new - old
			s:SetScale(d <= limit and -d <= limit and new or d < 0 and (old - limit) or (old + limit))
		end
	end
	OnUpdate_CheckAlpha(self, count)

	if modStateChanged or mut >= 0 then
		vis.omState, vis.schedMultiUpdate = modState, -0.05
		for i = 1, count do
			local originAngle = 90 - (i - 1) * 360 / count - offset
			securecall(callElementUpdate, Slices[i], updateSlice, i, nil, originAngle, si == i)
		end
		if configCache.GhostMIRings then
			local _, _, _, _, nestedCount, atype, isNested = PC:GetOpenRingSlice(si or 0)
			if (nestedCount or 0) == 0 then
				GhostIndication:Deactivate()
			else
				local jump1 = (atype == "jump" and not isNested) and 1 or 0
				local originAngle, nestAngleStep = 90 - 360 / count * (si - 1) - offset, 360 / (nestedCount + jump1)
				local nestAngleBase = 180 + originAngle + (1 - jump1) * nestAngleStep
				local group = GhostIndication:ActivateGroup(si, nestedCount + jump1, originAngle,
					radius * (miScaleAdd + 1))
				for i = 2 - jump1, nestedCount do
					securecall(callElementUpdate, group[i + jump1], updateSlice, si, i,
						nestAngleBase - nestAngleStep * i, false)
				end
			end
		end
	else
		vis.schedMultiUpdate = mut + elapsed
	end
	GhostIndication:OnUpdate(elapsed)
end
local function OnUpdate_ZoomIn(self, elapsed)
	local r, sm, a = vis.eleft - elapsed
	vis.eleft, r = r, r > 0 and r / configCache.XTZoomTime or 0
	if r == 0 then
		self:SetScript("OnUpdate", OnUpdate_Main)
	end
	sm = 1 + configCache.MIZoomInScale * 0.375 * r / (1.375 - r)
	a = r > 0.4 and 1 - (r - 0.4) / 0.6 or 1
	setIndicationScale(configCache.RingScale * sm)
	setIndicationAlpha(a < 0 and 0 or a)
	return OnUpdate_Main(self, elapsed)
end
local function OnUpdate_ZoomOut(self, elapsed)
	local r = vis.eleft - elapsed
	vis.eleft, r = r, r > 0 and r / configCache.XTZoomTime or 0
	if r <= 0 then
		self:SetScript("OnUpdate", nil)
		setIndicationShown(false)
		return
	elseif configCache.MISpinOnHide then
		local count = vis.count
		if count > 0 then
			local sliceAngle, angleStep, radius, prog = 45 - vis.offset + 45 * r, 360 / count, vis.radius,
				(1 - r) * configCache.MISpinOutProg
			for i = 1, count do
				Slices[i]:SetPoint("CENTER", cos(sliceAngle) * radius + cos(sliceAngle - 90) * prog,
					sin(sliceAngle) * radius + sin(sliceAngle - 90) * prog)
				sliceAngle = sliceAngle - angleStep
			end
		end
		setIndicationScale(configCache.RingScale * (1 + configCache.MIZoomOutScale * (1 - r)))
	else
		setIndicationScale(configCache.RingScale * r)
	end
	setIndicationAlpha(r < 1 and r or 1)
	OnUpdate_CheckAlpha(self, vis.count)
	GhostIndication:OnUpdate(elapsed)
end
mainFrame:SetScript("OnHide", function(self)
	if self:IsShown() and self:GetScript("OnUpdate") == OnUpdate_ZoomOut then
		self:SetScript("OnUpdate", nil)
		setIndicationShown(false)
	end
end)

function iapi:Show(_, _, fastOpen)
	local _, count, offset = PC:GetOpenRing(configCache)
	local baseSize, scale, radius = configCache.MIReserveSize, max(0.1, configCache.RingScale)
	radius = calculateRingRadius(count or 3, baseSize, baseSize, configCache.MIMinRadius, 90 - (offset or 0))
	vis.count, vis.offset, vis.radius = count, offset, radius
	vis.oldSlice, vis.angle, vis.omState, vis.rotPeriod, vis.oldEA, vis.glowEnd = -1
	vis.glowTarget = 0
	centerGlow:SetAlpha(0)
	GhostIndication:Reset()
	SwitchIndicatorFactory(configCache.IndicatorFactory)
	centerPointer:SetShown(configCache.InteractionMode ~= 3)

	local astep = count == 0 and 0 or -360 / count
	for i = 1, count do
		local indic = Slices[i] or
						  rawset(Slices, i, next(ActiveIndicatorFactory.mainPool) or CreateIndicator(nil, mainFrame, 48))[i]
		ActiveIndicatorFactory.mainPool[indic] = nil
		setAngle(indic, (i - 1) * astep - offset, radius)
		if ActiveIndicatorFactory.supportsCooldownNumbers then
			indic:SetCooldownTextShown(configCache.ShowCooldowns, configCache.ShowRecharge)
		end
		indic:SetShown(true)
		indic:SetScale(1)
	end
	for i = count + 1, #Slices do
		Slices[i]:SetShown(false)
	end
	updateSliceBindings(nil)

	configCache.RingScale = scale
	setIndicationScale(scale)
	if fastOpen ~= "inplace-switch" then
		local atMouse, ox, oy = configCache.RingAtMouse, configCache.IndicationOffsetX, -configCache.IndicationOffsetY
		if atMouse then
			local cx, cy = GetCursorPosition()
			ox, oy = cx + ox, cy + oy
		end
		setIndicationPosition(atMouse and "BOTTOMLEFT" or "CENTER", ox, oy)
	end
	if configCache.TooltipAnchor == "side" then
		local sw, sr = GetScreenWidth(), proxyFrame:GetCenter()
		local sl, rw = sw / scale - sr, radius + 60 + 220 / scale
		vis.noTL, vis.noTR = sl < rw and sr > rw, sr < rw and sl > rw
	end
	setupTransitionAnimation(fastOpen and "fast-in" or "in", OnUpdate_ZoomIn)
	setIndicationShown(true)
	EV.SPELL_UPDATE_COOLDOWN = forceMultiUpdate
end
function iapi:Hide()
	setupTransitionAnimation("out", OnUpdate_ZoomOut)
	GhostIndication:Deactivate()
	if GameTooltip:IsOwned(proxyFrame) then
		GameTooltip:Hide()
	end
	wipeTokenCache()
	EV.UnregisterEvent("SPELL_UPDATE_COOLDOWN", forceMultiUpdate)
end

function api:SetDisplayOptions(token, icon, label, r, g, b)
	if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
		r, g, b = nil
	end
	if label == "" or type(label) ~= "string" then
		label = nil
	end
	if iconIsAtlas[icon] or type(icon) == "string" and not icon:match("[/\\]") and C_Texture.GetAtlasInfo(icon) then
		iconIsAtlas[icon] = true
	end
	tokenR[token], tokenG[token], tokenB[token], tokenIcon[token], tokenLabel[token] = r, g, b, icon, label
end
function api:SetQuestHint(sliceToken, hint)
	tokenQuest[sliceToken] = hint or nil
end
function api:GetTexColor(icon)
	return getSliceColor(nil, icon)
end
function api:SetIconDefaultColor(icon, r, g, b)
	assert(type(icon) == "string" or type(icon) == "number", 'Syntax: OPieUI:SetIconDefaultColor(icon, r,g,b)')
	assert(
		type(r) == "number" and type(g) == "number" and type(b) == "number" and r >= 0 and g >= 0 and b >= 0 and r <= 1 and
			g <= 1 and b <= 1 or r == nil and g == nil and b == nil, 'SetIconDefaultColor: invalid color')
	setIconColorOverride(icon, r, g, b)
end

function api:RegisterIndicatorConstructor(key, info)
	assert(type(key) == "string" and type(info) == "table",
		'Syntax: OPieUI:RegisterIndicatorConstructor("key", infoTable)', 2)
	local func, apiLevel, iname, reqAPILevel = info.CreateIndicator, info.apiLevel, info.name, info.reqAPILevel
	local onPAC = info.onParentAlphaChanged
	assert(key ~= "_" and IndicatorFactories[key] == nil,
		'RegisterIndicatorConstructor: an indicator constructor with the specified key is already registered', 2)
	assert(type(func) == "function", 'RegisterIndicatorConstructor: info.CreateIndicator must be a function', 2)
	assert(type(apiLevel) == "number" and apiLevel < math.huge,
		'RegisterIndicatorConstructor: info.apiLevel must be a finite number', 2)
	assert(type(iname) == "string", 'RegisterIndicatorConstructor: info.name must be a string', 2)
	assert(type(reqAPILevel) == "number" or reqAPILevel == nil,
		'RegisterIndicatorConstructor: info.reqAPILevel, if set, must be a number', 2)
	assert(type(onPAC) == "function" or onPAC == nil,
		'RegisterIndicatorConstructor: info.onParentAlphaChanged, if set, must be a function', 2)

	local mainPool, err = ValidateIndicator(apiLevel, reqAPILevel, info)
	local fbKey = key == "elvui" and "fixedFrameBufferingClassic"
	if fbKey and not info[fbKey] then
		-- BUG[2408/11.0.2,1.15.4,4.4.1]: Showing buffered frames while a model frame is visible can crash to desktop with an assertion failure (test builds)/restart the renderer in a loop/crash the client
		mainPool, err = nil, 'Disabled to avoid triggering a client crash (missing flag: ' .. fbKey .. ').'
	end
	LastRegisteredIndicatorFactory, IndicatorFactories[key] = mainPool and key or LastRegisteredIndicatorFactory, {
		name = iname:gsub("|+", ""),
		apiLevel = apiLevel,
		CreateIndicator = mainPool and func,
		mainPool = mainPool,
		ghostPool = {},
		supportsCooldownNumbers = not not info.supportsCooldownNumbers,
		supportsShortLabels = not not info.supportsShortLabels,
		onParentAlphaChanged = onPAC,
		err = err
	}
	return not not mainPool, not mainPool and err or nil
end

for k, v in pairs({
	IndicatorFactory = "_",
	ShowCooldowns = false,
	ShowRecharge = false,
	UseGameTooltip = true,
	ShowKeys = true,
	ShowOneCount = false,
	ShowShortLabels = true,
	TooltipAnchor = "hud",
	MIScale = true,
	MISpinOnHide = true,
	GhostMIRings = true,
	XTPointerSnap = false,
	XTAnimation = true,
	XTRotationPeriod = 4,
	MIReserveSize = 54,
	MIMinRadius = 110,
	GhostShowDelay = 0.25
}) do
	PC:RegisterOption(k, v)
end
api:RegisterIndicatorConstructor("mirage", {
	name = "OPie",
	apiLevel = 4,
	CreateIndicator = CreateIndicator,

	supportsCooldownNumbers = true,
	supportsShortLabels = true
})

T.OPieUI, OPie.UI = iapi, api
