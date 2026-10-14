local ADDON, T = ...
local config, L, TS, XU, PC, GameTooltip = {}, T.L, T.TenSettings, T.exUI, T.OPieCore, T.NotGameTooltip or GameTooltip
T.config = config
local IsMetaKeyDown = T.compat.IsMetaKeyDown

do -- /opie
	local slashExtensions = {}
	local function addSuffix(func, word, ...)
		if word then
			local key = word:lower()
			if slashExtensions[key] == nil then
				slashExtensions[key] = func
			end
			addSuffix(func, ...)
		end
	end
	local function showVersionText()
		local sx, m, ok, m2 = ""
		if not PC then
			m = "Restart World of Warcraft. If this message continues to appear, delete and re-install OPie."
			ok, m2 = pcall(L, m)
			sx = "\n  |cffe82020" .. (ok and m2 or m)
		end
		print("|cff0080ffOPie|r |cffffffff" .. (GetAddOnMetadata(ADDON, "Version") or "??") .. "|r" .. sx)
	end
	local function showConfigHome()
		T.ConfigHomePanel:OpenPanel()
	end
	T.AddSlashSuffix = addSuffix

	SLASH_OPIE1, SLASH_OPIE2 = "/opie", "/op"
	SlashCmdList["OPIE"] = function(args, ...)
		local ext = slashExtensions[(args:match("%S+") or ""):lower()]
		ext = ext or T.ConfigHomePanel and showConfigHome or showVersionText
		ext(args, ...)
	end
	addSuffix(showVersionText, "version", "v")
	addSuffix(showConfigHome, "conf", "c")
	OPie_OpenSettings = showConfigHome
end

local KR = T.ActionBook:compatible("Kindred", 1, 0)

if TS and TS.Localize then
	TS:Localize({
		REVERT = L "Revert...",
		REVERT_OPTION_LABEL = L "%d |4minute:minutes; ago (%s)",
		RESET_QUESTION = L "Do you want to reset all %s settings to their defaults, or only the settings in the %s category?",
		REVERT_CANCEL_HINT = L "You can cancel or revert to previous settings later.",
		DEFAULTS_ALL = L("All Settings", ALL_SETTINGS),
		DEFAULTS_VISIBLE = L("These Settings", CURRENT_SETTINGS)
	})
end

do -- config.ui
	config.ui = {}
	function config.ui.HideTooltip(self)
		if GameTooltip:IsOwned(self) then
			GameTooltip:Hide()
		end
	end
	function config.ui.AttachThumbDrag(thumb, track, getValue, getMax, setValue)
		local dragY0, dragS0
		local function onUpdate(self)
			local cy = select(2, GetCursorPosition()) / self:GetEffectiveScale()
			local th, tmbH = track:GetHeight(), self:GetHeight()
			if th > tmbH then
				setValue(dragS0 + (dragY0 - cy) * getMax() / (th - tmbH))
			end
		end
		thumb:SetScript("OnMouseDown", function(self, btn)
			if btn ~= "LeftButton" then
				return
			end
			dragY0 = select(2, GetCursorPosition()) / self:GetEffectiveScale()
			dragS0 = getValue()
			self:SetScript("OnUpdate", onUpdate)
		end)
		thumb:SetScript("OnMouseUp", function(self)
			self:SetScript("OnUpdate", nil)
		end)
	end
	function config.ui.ShowControlTooltip(self)
		local title, text = self.tooltipTitle, self.tooltipText
		if not (title or text) then
			return
		end
		GameTooltip:SetOwner(self, self.tooltipOwnerPoint or "ANCHOR_BOTTOMRIGHT")
		GameTooltip:AddLine(title or "", nil, nil, nil)
		GameTooltip:AddLine(text or "", nil, nil, nil, true)
		GameTooltip:Show()
	end
end
do -- config.bind
	local activeCaptureButton
	local alternateFrame = CreateFrame("Frame", nil, UIParent)
	do
		alternateFrame:Hide()
		TS.Box(alternateFrame, "BACKGROUND", -7, TS.SKIN.bg)
		TS.Outline(alternateFrame, "BACKGROUND", -6, TS.SKIN.edge)
		alternateFrame:SetSize(380, 115)
		alternateFrame:EnableMouse(1)
		alternateFrame:SetScript("OnHide", alternateFrame.Hide)
		local extReminder = CreateFrame("Button", nil, alternateFrame)
		extReminder:SetHeight(16)
		extReminder:SetPoint("TOPLEFT", 12, -10)
		extReminder:SetPoint("TOPRIGHT", -12, -10)
		extReminder:SetNormalTexture("Interface/Buttons/UI-OptionsButton")
		extReminder:SetPushedTextOffset(0, 0)
		extReminder:SetText(" ")
		extReminder:SetNormalFontObject(GameFontHighlightSmall)
		do
			local fs, tex = extReminder:GetFontString(), extReminder:GetNormalTexture()
			fs:ClearAllPoints()
			tex:ClearAllPoints()
			fs:SetPoint("LEFT", 18, -1)
			tex:SetSize(14, 14)
			tex:SetPoint("LEFT")
		end
		alternateFrame.caption = extReminder
		extReminder:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:SetPoint("TOP", self, "BOTTOM")
			GameTooltip:AddLine(L "Conditional Bindings", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
			GameTooltip:AddLine(L "The binding will update to reflect the value of this macro options expression.",
				HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, 1)
			GameTooltip:AddLine(
				"Готовые условия с описанием — в настройках фрагмента, под списком параметров.",
				HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b, 1)
			GameTooltip:AddLine((L "Example: %s."):format(GREEN_FONT_COLOR_CODE ..
															  "[combat] ALT-C; [nomounted] CTRL-F|r"),
				NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
			GameTooltip:Show()
		end)
		extReminder:SetScript("OnLeave", config.ui.HideTooltip)
		extReminder:SetScript("OnHide", extReminder:GetScript("OnLeave"))
		local textarea = XU:Create("TextArea", "OPC_AlternateBindInput", alternateFrame)
		textarea:SetStyle("tooltip")
		textarea:SetPoint("TOPLEFT", 12, -28)
		textarea:SetPoint("BOTTOMRIGHT", -10, 10)
		alternateFrame.input = textarea
		textarea:SetMaxBytes(1023)
		textarea:SetScript("OnEscapePressed", function()
			alternateFrame:Hide()
		end)
		textarea:SetScript("OnChar", function(self, c)
			if c == "\n" then
				local bind = strtrim((self:GetText():gsub("[\r\n]", "")))
				if bind ~= "" then
					alternateFrame.apiFrame.SetBinding(alternateFrame.owner, bind)
				end
				alternateFrame:Hide()
			end
		end)
	end
	local captureFrame = CreateFrame("Button")
	do
		captureFrame:Hide()
		captureFrame:RegisterForClicks("AnyUp")
		captureFrame:SetScript("OnClick", function(_, ...)
			if activeCaptureButton then
				activeCaptureButton:Click(...)
			end
		end)
	end
	local function MapMouseButton(button)
		if button == "MiddleButton" then
			return "BUTTON3"
		elseif type(button) == "string" and (tonumber(button:match("^Button(%d+)")) or 1) > 3 then
			return button:upper()
		end
	end
	local function Deactivate(self)
		self:UnlockHighlight()
		self:EnableKeyboard(false)
		self:EnableMouseWheel(false)
		self:SetScript("OnKeyDown", nil)
		self:SetScript("OnHide", nil)
		captureFrame:Hide()
		activeCaptureButton = activeCaptureButton ~= self and activeCaptureButton or nil
		return self
	end
	local unbindableKeys = {
		UNKNOWN = 1,
		ESCAPE = 1,
		ALT = 1,
		SHIFT = 1,
		META = 1,
		LALT = 1,
		LCTRL = 1,
		LSHIFT = 1,
		LMETA = 1,
		RALT = 1,
		RCTRL = 1,
		RSHIFT = 1,
		RMETA = 1
	}
	local function SetBind(self, bind)
		if bind == "ESCAPE" then
			return Deactivate(self)
		elseif unbindableKeys[bind] then
			return
		end
		Deactivate(self)
		local bind, p = bind and
							((IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") ..
								(IsShiftKeyDown() and "SHIFT-" or "") .. (IsMetaKeyDown() and "META-" or "") .. bind),
			self:GetParent()
		if p and type(p.SetBinding) == "function" then
			p.SetBinding(self, bind)
		end
	end
	local function OnClick(self, button)
		local parent = self:GetParent()
		PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
		if activeCaptureButton then
			local deactivated, mappedButton = Deactivate(activeCaptureButton), MapMouseButton(button)
			if deactivated == self and (mappedButton or button == "RightButton") then
				SetBind(self, mappedButton)
			end
			if deactivated == self then
				return
			end
		elseif parent and parent.OnBindingAltClick and IsAltKeyDown() then
			config.ui.HideTooltip(self)
			return parent.OnBindingAltClick(self, button)
		elseif parent and parent.OnBindingShiftClick and IsShiftKeyDown() then
			config.ui.HideTooltip(self)
			return parent.OnBindingShiftClick(self, button)
		elseif button == "RightButton" then
			PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
			if parent and type(parent.SetBinding) == "function" then
				SetBind(self, false)
			end
			return
		end
		activeCaptureButton = self
		self:LockHighlight()
		self:EnableKeyboard(true)
		self:EnableMouseWheel(true)
		self:SetScript("OnKeyDown", SetBind)
		self:SetScript("OnHide", Deactivate)
		config.ui.HideTooltip(self)
		if parent then
			captureFrame:SetParent(parent.bindingContainerFrame or parent)
			captureFrame:SetAllPoints()
			captureFrame:Show()
			captureFrame:SetFrameLevel(self:GetFrameLevel() - 1)
		end
	end
	local function OnWheel(self, delta)
		local aw = self:GetParent().AllowWheelBinding
		if activeCaptureButton == self and aw and (type(aw) ~= "function" or aw(self)) then
			SetBind(self, delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
		end
	end
	local function IsCapturingBinding(self)
		return activeCaptureButton == self
	end
	local function Binding_OnEnter(self)
		local hc, header = HIGHLIGHT_FONT_COLOR, self.bindingName
		if not header or IsCapturingBinding(self) or alternateFrame:IsVisible() then
			return
		end
		local parent = self:GetParent()
		GameTooltip:SetOwner(self, self.tooltipOwnerPoint or "ANCHOR_BOTTOMRIGHT")
		GameTooltip:AddLine(header, nil, nil, nil, 1)
		GameTooltip:AddLine(L "Left click to assign binding", hc.r, hc.g, hc.b)
		if parent.OnBindingAltClick then
			GameTooltip:AddLine(L "Alt click to set conditional binding", hc.r, hc.g, hc.b)
		end
		if parent.OnBindingShiftClick then
			GameTooltip:AddLine(L "Shift click to view ring macro command", hc.r, hc.g, hc.b)
		end
		if self.hasSetBinding then
			GameTooltip:AddLine(L "Right click to unbind", hc.r, hc.g, hc.b)
		end
		local title, text = self.tooltipTitle, self.tooltipText
		if title and text then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(title)
			GameTooltip:AddLine(text, hc.r, hc.g, hc.b, true)
		end
		GameTooltip:Show()
	end
	local specialSymbolMap = {
		OPEN = "[",
		CLOSE = "]",
		SEMICOLON = ";"
	}
	local function SetBindingText(self, bind, pre, post, hasBinding)
		local pre2, pre3
		if type(bind) == "string" and bind:match("%[.*%]") then
			bind, pre2, hasBinding = KR:EvaluateCmdOptions(bind), pre3 or "|cff20ff20[+]|r ", true
		end
		pre3, bind = (bind or ""):match('^%s*(!*)%s*(%S.*)$')
		bind = bind and KR:UnescapeCmdOptionsValue(bind):gsub("[^%-]+$", specialSymbolMap)
		local bindText = bind and bind ~= "" and GetBindingText(bind, "KEY_")
		self.hasSetBinding = not not (hasBinding or bindText)
		return self:SetText((pre or "") .. (pre2 or "") .. (pre3 or "") .. (bindText or L "Not bound") .. (post or ""))
	end
	local function ToggleAlternateEditor(self, bind)
		if alternateFrame:IsShown() and alternateFrame.owner == self then
			alternateFrame:Hide()
		else
			alternateFrame.apiFrame, alternateFrame.owner = self:GetParent(), self
			alternateFrame.caption:SetFormattedText(L "Press %s to save.",
				NORMAL_FONT_COLOR_CODE .. GetBindingText("ENTER", "KEY_") .. "|r")
			alternateFrame.input:SetText(bind or "")
			alternateFrame:SetParent(self)
			alternateFrame:SetFrameLevel(self:GetFrameLevel() + 10)
			alternateFrame:ClearAllPoints()
			local yOfs, clipParent = 4, self:GetParent()
			clipParent = clipParent.clipContainer or clipParent.bindingContainerFrame or clipParent
			alternateFrame:SetPoint("TOP", self, "BOTTOM", 0, yOfs)
			if alternateFrame:GetBottom() < clipParent:GetBottom() then
				yOfs = -yOfs
				alternateFrame:ClearAllPoints()
				alternateFrame:SetPoint("BOTTOM", self, "TOP", 0, yOfs)
			end
			local point, relpoint, xOfs
			if alternateFrame:GetLeft() < clipParent:GetLeft() then
				point, relpoint, xOfs = "TOPLEFT", "BOTTOMLEFT", -8
			elseif alternateFrame:GetRight() > clipParent:GetRight() then
				point, relpoint, xOfs = "TOPRIGHT", "BOTTOMRIGHT", 8
			end
			if point then
				if yOfs < 0 then
					point, relpoint = relpoint, point
				end
				alternateFrame:ClearAllPoints()
				alternateFrame:SetPoint(point, self, relpoint, xOfs, yOfs)
			end
			alternateFrame:Show()
			alternateFrame.input:SetFocus()
		end
	end
	function config.createBindingButton(parent, w)
		local btn = TS:StyleButton(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
		btn:SetSize(w or 120, 22)
		btn:RegisterForClicks("AnyUp")
		btn:SetScript("OnClick", OnClick)
		btn:SetScript("OnMouseWheel", OnWheel)
		btn:EnableMouseWheel(false)
		btn:SetText(" ")
		btn:SetNormalFontObject(GameFontNormalSmall)
		btn:SetHighlightFontObject(GameFontHighlightSmall)
		btn:SetScript("OnEnter", Binding_OnEnter)
		btn:SetScript("OnLeave", config.ui.HideTooltip)
		local fs = btn:GetFontString()
		fs:SetMaxLines(1)
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", 6, -0.5)
		fs:SetPoint("RIGHT", -6, -0.5)
		fs:SetJustifyH("CENTER")
		btn.IsCapturingBinding, btn.SetBindingText, btn.ToggleAlternateEditor = IsCapturingBinding, SetBindingText,
			ToggleAlternateEditor
		return btn
	end
end
config.undo = TS:CreateUndoHandle()
do
	local function CallSwitchProfile(msg, ...)
		if msg == "archive-unwind" then
			config.undo:saveActiveProfile()
		end
		return PC:SwitchProfile(...)
	end
	local function CallSetSpecProfiles(msg, ...)
		if msg == "archive-unwind" then
			config.undo:saveSpecProfiles()
		end
		return PC:SetSpecProfiles(...)
	end
	function config.undo:saveSpecProfiles()
		if not self:search("profile-specs-init") then
			self:sink("profile-specs-init", CallSetSpecProfiles, PC:GetSpecProfiles())
		end
	end
	function config.undo:saveActiveProfile()
		self:saveSpecProfiles()
		local name = PC:GetCurrentProfile()
		if not self:search("OPieProfile#" .. name) then
			self:push("OPieProfile#" .. name, CallSwitchProfile, name, (PC:ExportProfile(name)))
		end
	end
end

local svWarningAcknowledged
local function ackSVWarning()
	svWarningAcknowledged = 1
end
function config.checkSVState(frame, forceAlert)
	local svOk, state = PC:GetSVState()
	if svOk or (svWarningAcknowledged and not forceAlert) then
		return svOk
	end
	local msg
	if not state then
		msg =
			L "World of Warcraft could not load OPie's saved variables due to a lack of memory. Try disabling other addons."
	else
		msg = L "An error occurred while loading OPie." .. " (Code " .. tostring(state) .. ")"
	end
	TS:ShowAlertOverlay(frame, L "Changes will not be saved",
		msg .. "\n\n" .. L "Any changes you make now will not be saved.", L "Understood; edit anyway", ackSVWarning)
end

do -- minimap button
	local EV, GT = T.Evie, T.NotGameTooltip or GameTooltip
	local mmPrefs = PC:RegisterPVar("MinimapButton", {})
	local ownButton, DBIcon
	local function createOwnButton()
		local btn = CreateFrame("Button", "OPieMinimapButton", Minimap)
		ownButton = btn
		btn:SetSize(31, 31)
		btn:SetFrameStrata("MEDIUM")
		btn:SetFrameLevel(8)
		btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
		local bg = btn:CreateTexture(nil, "BACKGROUND")
		bg:SetSize(20, 20)
		bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
		bg:SetPoint("TOPLEFT", 7, -5)
		local icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetSize(20, 20)
		icon:SetTexture("Interface\\Icons\\INV_Misc_Wrench_01")
		icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
		icon:SetPoint("TOPLEFT", 7, -5)
		btn.icon = icon
		local border = btn:CreateTexture(nil, "OVERLAY")
		border:SetSize(53, 53)
		border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
		border:SetPoint("TOPLEFT")
		local mmAngle = tonumber(mmPrefs.minimapPos) or 220
		local function applyMinimapAngle(a)
			mmAngle = a
			btn:ClearAllPoints()
			btn:SetPoint("CENTER", Minimap, "CENTER", 79 * math.cos(math.rad(a)), 79 * math.sin(math.rad(a)))
		end
		applyMinimapAngle(mmAngle)
		local dragging = false
		btn:RegisterForDrag("LeftButton")
		btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		btn:SetScript("OnMouseDown", function(self)
			self.icon:SetTexCoord(0, 1, 0, 1)
		end)
		btn:SetScript("OnMouseUp", function(self)
			self.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
		end)
		btn:SetScript("OnDragStart", function(self)
			dragging = true
			self.icon:SetTexCoord(0, 1, 0, 1)
			self:LockHighlight()
			self:SetScript("OnUpdate", function()
				local mx, my = Minimap:GetCenter()
				local cx, cy = GetCursorPosition()
				local s = Minimap:GetEffectiveScale()
				applyMinimapAngle(math.deg(math.atan2(cy / s - my, cx / s - mx)) % 360)
			end)
		end)
		btn:SetScript("OnDragStop", function(self)
			dragging = false
			self.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
			self:UnlockHighlight()
			self:SetScript("OnUpdate", nil)
			mmPrefs.minimapPos = mmAngle
		end)
		btn:SetScript("OnClick", function(_, button)
			if not dragging and button == "LeftButton" then
				OPie_OpenSettings()
			end
		end)
		btn:SetScript("OnEnter", function(self)
			GT:SetOwner(self, "ANCHOR_LEFT")
			GT:AddLine("OPie")
			GT:AddLine(L "Left click: Open settings", 1, 1, 1)
			GT:Show()
		end)
		btn:SetScript("OnLeave", function()
			GT:Hide()
		end)
	end
	local function applyMinimapButtonState()
		local hide = mmPrefs.hide == true
		if DBIcon then
			if DBIcon.Refresh then
				DBIcon:Refresh("OPie", mmPrefs)
			elseif hide then
				DBIcon:Hide("OPie")
			else
				DBIcon:Show("OPie")
			end
		elseif ownButton then
			if hide then
				ownButton:Hide()
			else
				ownButton:Show()
			end
		end
	end
	function T.IsMinimapButtonShown()
		return mmPrefs.hide ~= true
	end
	function T.SetMinimapButtonShown(show)
		mmPrefs.hide = not show or nil
		applyMinimapButtonState()
	end
	EV.PLAYER_LOGIN = function()
		local lib = LibStub and LibStub("LibDBIcon-1.0", true)
		local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
		local obj = LDB and LDB.GetDataObjectByName and LDB:GetDataObjectByName("OPie")
		if lib and obj and not (lib.IsRegistered and lib:IsRegistered("OPie")) then
			DBIcon = lib
			lib:Register("OPie", obj, mmPrefs)
		else
			createOwnButton()
			applyMinimapButtonState()
		end
		return "remove"
	end
end
