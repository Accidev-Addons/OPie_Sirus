local _, T = ...
local XU, type = T.exUI, type
local GetPhysicalScreenSize = GetPhysicalScreenSize or function()
	local w, h = string.match((({GetScreenResolutions()})[GetCurrentResolution()] or ""), "(%d+).-(%d+)")
	return tonumber(w) or 1024, tonumber(h) or 768
end
local assert, getWidgetData, newWidgetData, setWidgetData, AddObjectMethods, CallObjectScript = XU:GetImpl()

local TextArea, TextAreaData, int = {}, {}, {}
local function syncExtent(d)
	local cw, ch = d.clipArea:GetWidth(), d.clipArea:GetHeight()
	if not (cw and cw > 0 and ch and ch > 0) then
		return
	end
	if math.abs(d.editBox:GetWidth() - cw) > 0.5 then
		d.editBox:SetWidth(cw)
	end
	local m = d.measure
	m:SetWidth(cw)
	m:SetSpacing(d.spacingTarget or 0)
	m:SetText(d.editBox:GetText() or "")
	local th = math.max(ch, m:GetStringHeight() + 4)
	if math.abs(d.editBox:GetHeight() - th) > 0.5 then
		d.editBox:SetHeight(th)
	end
end
local TextAreaProps = {
	api = TextArea,
	spacingTarget = 0,
	scripts = {"OnCursorChanged"},
	self2scripts = {"OnKeyDown", "OnKeyUp", "OnChar"}
}
AddObjectMethods({"TextArea", "EditBox"}, TextAreaProps)

local function buildFlatSkin(d)
	if d.flatSkin then
		return d.flatSkin
	end
	local f, s = d.self, {}
	local bg = f:CreateTexture(nil, "BACKGROUND", nil, -7)
	bg:SetTexture(0.055, 0.060, 0.070, 0.96)
	bg:SetAllPoints()
	s[1] = bg
	for i = 1, 4 do
		local t = f:CreateTexture(nil, "BORDER", nil, -6)
		t:SetTexture(0.21, 0.23, 0.27, 1)
		s[i + 1] = t
		if i < 3 then
			local p = i == 1 and "TOP" or "BOTTOM"
			t:SetHeight(1)
			t:SetPoint("LEFT")
			t:SetPoint("RIGHT")
			t:SetPoint(p)
		else
			local p = i == 3 and "LEFT" or "RIGHT"
			t:SetWidth(1)
			t:SetPoint("TOP")
			t:SetPoint("BOTTOM")
			t:SetPoint(p)
		end
	end
	d.flatSkin = s
	return s
end

function TextArea:GetHighlightText()
	local d = assert(getWidgetData(self, TextAreaData), 'invalid object type')
	local editBox = d.editBox
	local text, curPos = editBox:GetText(), editBox:GetCursorPosition()
	editBox:Insert("")
	local text2, selStart = editBox:GetText(), editBox:GetCursorPosition()
	local selEnd = selStart + #text - #text2
	if text ~= text2 then
		TextArea.SetText(self, text)
		editBox:SetCursorPosition(curPos)
		editBox:HighlightText(selStart, selEnd)
	end
	return text:sub(selStart + 1, selEnd), selStart
end
function TextArea:SetHighlightText(newText, preserveCaret)
	assert(type(newText) == 'string', 'Syntax: TextArea:SetHighlightText("text"[, preserveCaret])')
	local d = assert(getWidgetData(self, TextAreaData), 'invalid object type')
	local editBox, op, op2 = d.editBox
	d.holdScroll, op = true, preserveCaret and editBox:GetCursorPosition()
	editBox:Insert("")
	op2 = editBox:GetCursorPosition()
	editBox:Insert(newText)
	d.editFS:SetText(editBox:GetText())
	d.holdScroll = nil
	if op == op2 then
		editBox:SetCursorPosition(op2)
	end
	editBox:HighlightText(op2, op2 + #newText)
end
function TextArea:SetStickyFocus(sticky)
	assert(sticky == nil or type(sticky) == "function" or type(sticky) == "boolean",
		'Syntax: TextArea:SetStickyFocus(sticky)')
	local d = assert(getWidgetData(self, TextAreaData), 'invalid object type')
	d.editBox.HasStickyFocus = sticky == true and int.alwaysHasStickyFocus or sticky or nil
end
function TextArea:SetStyle(style)
	assert(type(style) == "string", 'Syntax: TextArea:SetStyle("style")')
	local d = assert(getWidgetData(self, TextAreaData), 'invalid object type')
	local px, py = 0, 0
	if style == "tooltip" then
		local s = buildFlatSkin(d)
		for i = 1, #s do
			s[i]:Show()
		end
		px, py = 5, 5
	elseif d.flatSkin then
		for i = 1, #d.flatSkin do
			d.flatSkin[i]:Hide()
		end
	end
	d.clipArea:SetPoint("TOPLEFT", px, -py)
	d.scrollBar:SetPoint("TOPRIGHT", -px, -py)
	d.scrollBar:SetPoint("BOTTOMRIGHT", -px, py)
end
function TextArea:SetSpacing(spacing)
	assert(type(spacing) == "number" and spacing >= 0, 'Syntax: TextArea:SetStyle("style")')
	local d = assert(getWidgetData(self, TextAreaData), 'invalid object type')
	d.spacingTarget = spacing
	int.adjustSpacing(d, true)
end
function TextArea:SetText(text)
	local d = assert(getWidgetData(self, TextAreaData), 'invalid object type')
	d.editBox:SetText(text)
	d.editFS:SetText(text)
	int.OnSizeChanged(d.clipArea)
end

function int.alwaysHasStickyFocus()
	return true
end
function int.adjustSpacing(d, force)
	local fs, ct, _, screenHeight = d.editFS, d.cursorTex, GetPhysicalScreenSize()
	local spacing, fsLineHeight, screenLocalHeight = d.spacingTarget,
		fs.GetLineHeight and fs:GetLineHeight() or select(2, fs:GetFont()) or 12, fs:GetEffectiveScale() * screenHeight
	if force or d.cachedLineHeight ~= fsLineHeight or d.cachedScreenHeight ~= screenLocalHeight then
		local pixel, mceil = 768 / screenLocalHeight, math.ceil
		local pixSpacedLineHeight = mceil((spacing + fsLineHeight) / pixel) * pixel
		local correctedSpacing = pixSpacedLineHeight - fsLineHeight - 2 ^ -18
		d.proto.super2.SetSpacing(d.editBox, correctedSpacing > 0 and correctedSpacing or 0)
		d.cachedLineHeight, d.cachedScreenHeight = fsLineHeight, screenLocalHeight
		d.cachedCursorH, d.cachedCursorW = pixSpacedLineHeight, mceil(2 / pixel) * pixel
	end
	ct:SetSize(d.cachedCursorW, d.cachedCursorH)
end
function int:OnCursorChanged(...)
	local d = assert(getWidgetData(self, TextAreaData), 'invalid object type')
	if d.holdScroll then
		return
	end
	int.adjustSpacing(d)
	repeat -- runs once; just need a break
		local _x, y, _w, h = ...
		local sb, insT, insB = d.scrollBar, 2, 2
		local occH, occP, y = d.clipArea:GetHeight(), sb:GetValue(), -y
		if not self:HasFocus() then -- only move if focused
		elseif occP > y - insT then
			occP = y > insT and y - insT or 0 -- too far
		elseif occP < y + h - occH + insB + insT then
			occP = y + h - occH + insB + insT -- not far enough
		else
			break
		end
		local _, mx = sb:GetMinMaxValues()
		occP = (mx - occP) ^ 2 < 1 and mx or math.floor(occP)
		sb:SetMinMaxValues(0, occP < mx and mx or occP)
		sb:SetWindowRange(occH)
		sb:SetValue(occP)
	until 1
	CallObjectScript(d.self, "OnCursorChanged", ...)
end
function int:OnClick()
	local eb = assert(getWidgetData(self, TextAreaData), 'invalid object type').editBox
	eb:SetCursorPosition(#eb:GetText())
	if eb.ClearHighlightText then
		eb:ClearHighlightText()
	else
		eb:HighlightText(0, 0)
	end
	eb:SetFocus()
end
function int:OnScrollValueChanged(nv)
	local d = assert(getWidgetData(self, TextAreaData), 'invalid object type')
	d.clipArea:SetVerticalScroll(nv)
end
function int:OnSizeChanged()
	local d = assert(getWidgetData(self, TextAreaData), 'invalid object type')
	syncExtent(d)
	if d.holdScroll then
		return
	end
	local sb, ch = d.scrollBar, d.clipArea:GetHeight()
	local th = d.editBox:GetHeight() + (d.editBox:GetText():sub(-1) == "\n" and (d.cachedCursorH or 13) or 0)
	sb:SetMinMaxValues(0, th > ch and th - ch or 0)
	sb:SetWindowRange(ch)
	sb:SetStepsPerPage(math.min(5, math.ceil(ch / 18)))
end
function int:OnShow()
	local d = assert(getWidgetData(self, TextAreaData), 'invalid object type')
	d.scrollBar:SetValue(0)
	int.adjustSpacing(d)
end

local function CreateTextArea(name, parent, outerTemplate, id)
	local area, d = CreateFrame("Frame", name, parent, outerTemplate, id)
	local sb = XU:Create("ScrollBar", nil, area)
	sb:SetPoint("TOPRIGHT")
	sb:SetPoint("BOTTOMRIGHT")
	sb:SetScript("OnValueChanged", int.OnScrollValueChanged)
	sb:SetWheelScrollTarget(area)
	sb:SetValueStep(12)
	local ec = CreateFrame("ScrollFrame", nil, area)
	ec:SetPoint("TOPLEFT")
	ec:SetPoint("BOTTOMRIGHT", sb, "BOTTOMLEFT")
	ec:SetScript("OnSizeChanged", int.OnSizeChanged)
	ec:EnableMouse(1)
	ec:SetScript("OnMouseDown", int.OnClick)
	local input = CreateFrame("EditBox", type(name) == "string" and name .. "EB" or nil, ec)
	input:SetSize(1, 1)
	input:SetMultiLine(true)
	input:SetAutoFocus(false)
	input:SetFontObject(GameFontHighlight)
	if input.SetHyperlinkPropagateToParent then
		input:SetHyperlinkPropagateToParent(true)
	end
	input:SetTextInsets(1, 1, 1, 1)
	input:SetHitRectInsets(-1, -1, -1, 0)
	input:SetScript("OnCursorChanged", int.OnCursorChanged)
	input:SetScript("OnSizeChanged", int.OnSizeChanged)
	input:SetScript("OnShow", int.OnShow)
	local measure = area:CreateFontString(nil, "BACKGROUND", "GameFontHighlight")
	measure:SetPoint("TOPLEFT")
	measure:SetJustifyH("LEFT")
	measure:SetJustifyV("TOP")
	measure:Hide()
	d = newWidgetData(area, TextAreaData, TextAreaProps, input)
	d.clipArea, d.scrollBar, d.editBox, d.editFS, d.cursorTex = ec, sb, input, input:GetRegions()
	d.measure = measure
	setWidgetData(input, TextAreaData, d)
	setWidgetData(sb, TextAreaData, d)
	setWidgetData(ec, TextAreaData, d)
	ec:SetScrollChild(input)
	TextArea.SetSpacing(area, 2)
	return area
end

XU:RegisterFactory("TextArea", CreateTextArea)
