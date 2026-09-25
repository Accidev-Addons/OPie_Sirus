local _, T = ...
local XU = T.exUI
local _assert, getWidgetData, newWidgetData, setWidgetData, _AddObjectMethods, _CallObjectScript = XU:GetImpl()

local IndicatorData, Indicator, CooldownData = {}, {}, {}
local IndicatorProps = {
	api = Indicator,
	iconAspect = 1,
	ustate = -1,
	rcTextShown = false,
	cdTextShown = false
}

local darken
do
	local CSL = CreateFrame("ColorSelect")
	function darken(r, g, b, vf, sf)
		CSL:SetColorRGB(r, g, b)
		local h, s, v = CSL:GetColorHSV()
		CSL:SetColorHSV(h, s * (sf or 1), v * (vf or 1))
		return CSL:GetColorRGB()
	end
end

local function cooldownFormat(cd)
	if (cd or 0) == 0 then
		return ""
	end
	local f, n, unit = cd >= 9.95 and "%d%s" or "%.1f", cd, ""
	if n > 86400 then
		n, unit = ceil(n / 86400), "d"
	elseif n > 3600 then
		n, unit = ceil(n / 3600), "h"
	elseif n > 90 then
		n, unit = ceil(n / 60), "m"
	elseif cd >= 9.95 then
		n = ceil(n)
	end
	return f, n, unit
end
local function adjustIconAspect(d, aspect)
	if d.iconAspect ~= aspect then
		d.iconAspect = aspect
		local w, h = d.iconbg:GetSize()
		d.icon:SetSize(aspect < 1 and h * aspect or w, aspect > 1 and w / aspect or h)
	end
end
local CreateCooldown, CallCooldownUpdate
do
	local ninf = -math.huge
	local SWIPE_FADE_IN = 0.25
	local TAU = 2 * math.pi
	local sparkPos
	do
		local CORNER_CUT = 3.5 / 62
		local CORNER_A4MIN = math.atan2(0.5 - CORNER_CUT, 0.5)
		local CORNER_A4MAX = math.atan2(0.5, 0.5 - CORNER_CUT)
		local CORNER_R = (0.5 - CORNER_CUT + CORNER_CUT ^ 2) ^ 0.5
		local mcos, msin, mtan = math.cos, math.sin, math.tan
		function sparkPos(p)
			local a4, x, y = (p % 0.25) * TAU
			if a4 > CORNER_A4MIN and a4 < CORNER_A4MAX then
				x, y = mcos(a4) * CORNER_R, msin(a4) * CORNER_R
			elseif a4 <= CORNER_A4MIN then
				x, y = 0.5, 0.5 * mtan(a4)
			else
				x, y = 0.5 / mtan(a4), 0.5
			end
			if p < 0.25 then
				x, y = y, x
			elseif p < 0.50 then
				x, y = x, -y
			elseif p < 0.75 then
				x, y = -y, -x
			else
				x, y = -x, y
			end
			return x + 0.5, y + 0.5
		end
	end
	local function syncSwipe(d)
		local es = d.parent:GetEffectiveScale()
		if es and es > 0 and d.swipeScale ~= es then
			d.swipeScale = es
			d.swipe:SetScale(1 / es)
			d.swipe:SetSize(d.swipeSize * es, d.swipeSize * es)
		end
	end
	local function cdOnUpdate(self, elapsed)
		local d = getWidgetData(self, CooldownData)
		if d.swipeFade then
			local f = d.swipeFade + elapsed
			if f < SWIPE_FADE_IN then
				d.swipeFade = f
				d.swipe:SetAlpha(d.swipeAlpha * f / SWIPE_FADE_IN)
			else
				d.swipeFade = nil
				d.swipe:SetAlpha(d.swipeAlpha)
			end
		end
		syncSwipe(d)
		local ucd, expire, time = d.updateCooldown or 0, d.expire or ninf, GetTime()
		if ucd > elapsed and time < expire then
			d.updateCooldown = ucd - elapsed
			return
		end
		d.updateCooldown = d.updateCooldownStep

		local duration, progress = d.duration or 0, expire - time
		if progress >= duration or duration == 0 then
			self:Hide()
			return
		end
		progress = progress < 0 and 0 or (1 - progress / duration)
		if d.spark:IsShown() then
			local sx, sy = sparkPos(progress)
			d.spark:SetPoint("CENTER", self, "CENTER", 45 * (sx - 0.5), 45 * (sy - 0.5))
		end
	end
	local function cdOnHide(self)
		local d = getWidgetData(self, CooldownData)
		local toExpire = GetTime() - (d.expire or 0)
		d.expire, d.swipeFade, d.swipeScale = nil
		d.swipe:Hide()
		d.self:Hide()
		d.spark:Hide()
		if -0.1 < toExpire and toExpire < 0.25 then
			d.flashAG:Play()
		end
	end
	local function cdOnShow(self)
		local d = getWidgetData(self, CooldownData)
		if d.expire and (d.duration or 0) > 0 then
			syncSwipe(d)
			d.swipe:SetCooldown(d.expire - d.duration, d.duration)
			d.swipeFade = 0
			d.swipe:SetAlpha(0)
		end
		return cdOnUpdate(self, 0)
	end
	function CallCooldownUpdate(d)
		local self = d.self
		d.updateCooldown = nil
		self:Show()
		if d.updateCooldown == nil then
			return cdOnUpdate(self, 0)
		end
	end
	function CreateCooldown(parent, size, overParent, gx)
		local cd = CreateFrame("Frame", nil, parent)
		local d, w, b = setWidgetData(cd, CooldownData, {
			self = cd,
			parent = parent
		})
		cd:SetScale(size / 48)
		cd:SetAllPoints()
		cd:SetScript("OnShow", cdOnShow)
		cd:SetScript("OnHide", cdOnHide)
		cd:SetScript("OnUpdate", cdOnUpdate)
		w = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
		w:ClearAllPoints()
		w:SetPoint("CENTER")
		w:SetSize(size * 60 / 64, size * 60 / 64)
		w:SetFrameLevel(parent:GetFrameLevel() + 1)
		w:Hide()
		d.swipe, d.swipeAlpha, d.swipeSize = w, 1, size * 60 / 64
		w = (overParent or cd):CreateTexture(nil, "OVERLAY", nil, 2)
		w:SetTexture(gx.CooldownSpark)
		w:SetSize(24, 24)
		w, d.spark = w:CreateAnimationGroup(), w
		w:SetLooping("REPEAT")
		b = w:CreateAnimation("Rotation")
		b:SetDegrees(90)
		b:SetDuration(1 / 3)
		w:Play()

		w = parent:CreateTexture(nil, "OVERLAY")
		w:SetSize(size * 60 / 64, size * 60 / 64)
		w:SetPoint("CENTER")
		w:SetTexture(gx.CooldownStar)
		w:SetBlendMode("ADD")
		w:SetAlpha(0)
		w, d.flash = w:CreateAnimationGroup(), w
		b, d.flashAG = w:CreateAnimation("ROTATION"), w
		b:SetDuration(1 / 2)
		b:SetDegrees(-90)
		b = w:CreateAnimation("Alpha")
		b:SetChange(0.7)
		b:SetDuration(1 / 8)
		b = w:CreateAnimation("Alpha")
		b:SetChange(-0.7)
		b:SetDuration(1 / 8)
		b:SetStartDelay(3 / 8)

		return cd, d
	end
end

function Indicator:SetIcon(texture, aspect)
	local d = getWidgetData(self, IndicatorData)
	if texture then
		d.icon:SetTexture(texture)
		local ofs = 2.5 / 64
		d.icon:SetTexCoord(ofs, 1 - ofs, ofs, 1 - ofs)
	else
		d.icon:SetTexture("Interface/Icons/INV_Misc_QuestionMark")
		d.icon:SetTexCoord(0, 1, 0, 1)
	end
	return adjustIconAspect(d, aspect)
end
function Indicator:SetIconAtlas(atlas, aspect)
	local d = getWidgetData(self, IndicatorData)
	pcall(d.icon.SetAtlas, d.icon, atlas)
	return adjustIconAspect(d, aspect)
end
function Indicator:SetIconTexCoord(a, b, c, dc, e, f, g, h)
	if a and b and c and dc then
		local d = getWidgetData(self, IndicatorData)
		if e and f and g and h then
			d.icon:SetTexCoord(a, b, c, dc, e, f, g, h)
		else
			d.icon:SetTexCoord(a, b, c, dc)
		end
	end
end
function Indicator:SetIconVertexColor(r, g, b)
	local d = getWidgetData(self, IndicatorData)
	d.icon:SetVertexColor(r, g, b)
end
function Indicator:SetUsable(usable, _usableCharge, _cd, nomana, norange)
	local d = getWidgetData(self, IndicatorData)
	local state = usable and 0 or (norange and 1 or (nomana and 2 or 3))
	if d.ustate == state then
		return
	end
	d.ustate = state
	if not usable and (nomana or norange) then
		d.ribbon:Show()
		if norange then
			d.ribbon:SetVertexColor(1, 0.20, 0.15)
		else
			d.ribbon:SetVertexColor(0.15, 0.75, 1)
		end
	else
		d.ribbon:Hide()
	end
end
function Indicator:SetDominantColor(r, g, b)
	local d = getWidgetData(self, IndicatorData)
	r, g, b = r or 1, g or 1, b or 0.6
	if d.domR == r and d.domG == g and d.domB == b then
		return
	end
	d.domR, d.domG, d.domB = r, g, b
	local cdd = d.cdControl
	d.hiEdge:SetVertexColor(r, g, b)
	d.iglow:SetVertexColor(r, g, b)
	d.oglow:SetVertexColor(r, g, b)
	d.edge:Show()
	d.edge:SetVertexColor(darken(r, g, b, 0.80))
	d.cdText:SetTextColor(r, g, b)
	cdd.spark:SetVertexColor(r, g, b)
end
function Indicator:SetOverlayIcon(tex, w, h, ...)
	local oi = getWidgetData(self, IndicatorData).overIcon
	if not tex then
		return oi:Hide()
	end
	oi:Show()
	oi:SetTexture(tex)
	oi:SetSize(w, h)
	if ... then
		oi:SetTexCoord(...)
	else
		oi:SetTexCoord(0, 1, 0, 1)
	end
end
function Indicator:SetOverlayIconVertexColor(...)
	getWidgetData(self, IndicatorData).overIcon:SetVertexColor(...)
end
function Indicator:SetCount(count)
	getWidgetData(self, IndicatorData).count:SetText(count or "")
end
function Indicator:SetBinding(binding)
	binding = binding and GetBindingText(binding, "KEY_", 1) or ""
	getWidgetData(self, IndicatorData).key:SetText(binding)
end
function Indicator:SetCooldown(remain, duration, usableCharge)
	local d = getWidgetData(self, IndicatorData)
	local cdd = d.cdControl
	if (duration or 0) <= 0 or (remain or 0) <= 0 then
		d.cd:Hide()
		d.cdText:SetText("")
	else
		local now = GetTime()
		local expire, usable = now + remain, not not usableCharge
		local td, showSpark = expire - (cdd.expire or 0), usable and d.ustate == 0
		if td < -0.05 or td > 0.05 then
			cdd.duration, cdd.expire, cdd.updateCooldownStep, cdd.updateCooldown = duration, expire, duration / 1536 /
				d.self:GetEffectiveScale()
			cdd.swipe:SetCooldown(expire - duration, duration)
			cdd.spark:SetShown(showSpark)
		end
		if cdd.usable ~= usable then
			cdd.usable = usable
			cdd.swipeAlpha = usable and 0.5 or 1
			if not cdd.swipeFade then
				cdd.swipe:SetAlpha(cdd.swipeAlpha)
			end
			cdd.spark:SetShown(showSpark)
		end
		local _, gcL = GetSpellCooldown(61304)
		local isGCD = (gcL or 0) > 0 and duration <= gcL + 0.01
		if not isGCD and d[usableCharge and "rcTextShown" or "cdTextShown"] then
			d.cdText:SetFormattedText(cooldownFormat(remain))
			d.cdText:SetAlpha(1)
		else
			d.cdText:SetText("")
		end
		CallCooldownUpdate(cdd)
	end
end
function Indicator:SetCooldownTextShown(cooldownShown, rechargeShown)
	local d = getWidgetData(self, IndicatorData)
	d.cdTextShown, d.rcTextShown = cooldownShown, rechargeShown
end
function Indicator:SetHighlighted(highlight)
	getWidgetData(self, IndicatorData).hiEdge:SetShown(highlight)
end
function Indicator:SetActive(active)
	getWidgetData(self, IndicatorData).iglow:SetShown(active)
end
function Indicator:SetOuterGlow(shown)
	getWidgetData(self, IndicatorData).oglow:SetShown(shown)
end
function Indicator:SetEquipState(isInContainer, isInInventory)
	local s = getWidgetData(self, IndicatorData).equipBanner
	local v, r, g, b = isInContainer or isInInventory, 0.1, 0.9, 0.15
	s:SetShown(v)
	if v then
		if not isInInventory then
			r, g, b = 1, 0.9, 0.2
		end
		s:SetVertexColor(r, g, b)
	end
end
function Indicator:SetShortLabel(text)
	getWidgetData(self, IndicatorData).label:SetText(text)
end

local function CreateIndicator(name, parent, size, nested, gx)
	local cf, d, w, ef = CreateFrame("Frame", name, parent)
	cf:SetSize(size, size)
	d = newWidgetData(cf, IndicatorData, IndicatorProps)
	ef = CreateFrame("Frame", nil, cf)
	ef:SetAllPoints()
	w = ef:CreateTexture(nil, "OVERLAY")
	w:SetAllPoints()
	w:SetTexture(gx.BorderLow)
	w:Hide()
	w, d.edge = ef:CreateTexture(nil, "OVERLAY", nil, 1), w
	w:SetAllPoints()
	w:SetTexture(gx.BorderHigh)
	w:Hide()
	w, d.hiEdge = T.CreateQuadTexture("BACKGROUND", size * 2, gx.OuterGlow, cf), w
	w:SetShown(false)
	w, d.oglow = ef:CreateTexture(nil, "ARTWORK", nil, 1), w
	w:SetAllPoints()
	w:SetTexture(gx.InnerGlow)
	w:SetAlpha(nested and 0.6 or 1)
	w:Hide()
	w, d.iglow = ef:CreateTexture(nil, "ARTWORK"), w
	w:SetPoint("CENTER")
	w:SetSize(60 * size / 64, 60 * size / 64)
	w, d.icon = ef:CreateTexture(nil, "ARTWORK", nil, -2), w
	w:SetPoint("CENTER")
	w:SetSize(60 * size / 64, 60 * size / 64)
	w:SetTexture(0, 0, 0, 0)
	w, d.iconbg = CreateFrame("Frame", nil, cf), w
	w:SetAllPoints()
	w:SetFrameLevel(ef:GetFrameLevel() + 5)
	d.cd, d.cdControl = CreateCooldown(ef, size, w, gx)
	w = d.cd:CreateFontString(nil, "OVERLAY", "GameFontNormalLargeOutline")
	w:SetPoint("CENTER")
	w, d.cdText = ef:CreateTexture(nil, "ARTWORK", nil, 3), w
	w:SetAllPoints()
	w:SetTexture(gx.Ribbon)
	w:Hide()
	w, d.ribbon = ef:CreateTexture(nil, "ARTWORK", nil, 5), w
	w:SetPoint("BOTTOMLEFT", 4, 4)
	w, d.overIcon = ef:CreateFontString(nil, "OVERLAY", "NumberFontNormal"), w
	w:SetJustifyH("RIGHT")
	w:SetPoint("BOTTOMRIGHT", -2, 4)
	w, d.count = ef:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray"), w
	w:SetJustifyH("RIGHT")
	w:SetPoint("TOPRIGHT", -2, -3)
	w, d.key = ef:CreateTexture(nil, "ARTWORK", nil, 2), w
	w:SetSize(size / 5, size / 4)
	w:SetTexture("Interface\\GuildFrame\\GuildDifficulty")
	w:SetTexCoord(0, 42 / 128, 6 / 64, 52 / 64)
	w:SetPoint("TOPLEFT", 6 * size / 64, -3 * size / 64)
	w, d.equipBanner = ef:CreateFontString(nil, "OVERLAY", "TextStatusBarText", -1), w
	w:SetSize(size - 4, 12)
	w:SetJustifyH("CENTER")
	w:SetJustifyV("BOTTOM")
	w:SetMaxLines(1)
	w:SetPoint("BOTTOMLEFT", 3, 4)
	w:SetPoint("BOTTOMRIGHT", d.count, "BOTTOMLEFT", 2, 0)
	d.label = w
	return cf
end

XU:RegisterFactory("OPie:MirageIndicator", CreateIndicator)
