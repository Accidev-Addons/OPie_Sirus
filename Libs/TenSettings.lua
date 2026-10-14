local M, I, _, T = {}, {}, ...
local EV, XU, noop = T.Evie, T.exUI, function()
end
local GFX = ([[Interface\AddOns\%s\gfx\]]):format((...))
local REVERT = T.compat.REVERT
T.TenSettings = M

local SKIN = {
	bg = {0.043, 0.047, 0.055, 0.96},
	edge = {0.21, 0.23, 0.27, 1},
	header = {0.075, 0.082, 0.096, 1},
	rail = {0.058, 0.063, 0.074, 1},
	line = {0.14, 0.15, 0.18, 1},
	accent = {0.16, 0.66, 1.00, 1},
	accentDim = {0.16, 0.66, 1.00, 0.13},
	hover = {1, 1, 1, 0.06},
	btn = {0.115, 0.125, 0.145, 1},
	card = {0.062, 0.067, 0.078, 0.98},
	danger = {0.72, 0.16, 0.16, 0.55}
}
M.SKIN = SKIN
local function fill(f, layer, sub, c)
	local t = f:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
	t:SetTexture(c[1], c[2], c[3], c[4])
	return t
end
local function box(f, layer, sub, c)
	local t = fill(f, layer, sub, c)
	t:SetAllPoints()
	return t
end
local function outline(f, layer, sub, c, inset)
	inset = inset or 0
	local e = {}
	for i = 1, 4 do
		local t = fill(f, layer, sub, c)
		e[i] = t
		if i < 3 then
			local p = i == 1 and "TOP" or "BOTTOM"
			t:SetHeight(1)
			t:SetPoint("LEFT", f, "LEFT", inset, 0)
			t:SetPoint("RIGHT", f, "RIGHT", -inset, 0)
			t:SetPoint(p, f, p, 0, i == 1 and -inset or inset)
		else
			local p = i == 3 and "LEFT" or "RIGHT"
			t:SetWidth(1)
			t:SetPoint("TOP", f, "TOP", 0, -inset)
			t:SetPoint("BOTTOM", f, "BOTTOM", 0, inset)
			t:SetPoint(p, f, p, i == 3 and inset or -inset, 0)
		end
	end
	return e
end
local function hideTextureRegions(f)
	for _, o in ipairs({f:GetRegions()}) do
		if o.GetObjectType and o:GetObjectType() == "Texture" then
			o:Hide()
		end
	end
end
M.Fill, M.Box, M.Outline = fill, box, outline

local styled = setmetatable({}, {
	__mode = "k"
})
local function prepCheckMark(tex, r, g, b)
	if not tex then
		return
	end
	tex:SetVertexColor(r, g, b)
	tex:SetBlendMode("BLEND")
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", 4, -4)
	tex:SetPoint("BOTTOMRIGHT", -4, 4)
end
function M:StyleButton(b, kind)
	if not b or styled[b] then
		return b
	end
	styled[b] = true
	hideTextureRegions(b)
	local primary = kind == "primary"
	box(b, "BACKGROUND", nil, primary and SKIN.accentDim or SKIN.btn)
	outline(b, "BORDER", nil, primary and SKIN.accent or SKIN.edge)
	box(b, "HIGHLIGHT", nil, SKIN.hover)
	b:SetNormalFontObject(GameFontNormalSmall)
	b:SetHighlightFontObject(GameFontHighlightSmall)
	b:SetDisabledFontObject(GameFontDisableSmall)
	b:SetPushedTextOffset(0, -1)
	return b
end
function M:StyleCloseButton(b)
	if not b or styled[b] then
		return b
	end
	styled[b] = true
	hideTextureRegions(b)
	b:SetSize(20, 20)
	box(b, "HIGHLIGHT", nil, SKIN.danger)
	local x = b:CreateTexture(nil, "ARTWORK")
	x:SetTexture(GFX .. "close.tga")
	x:SetSize(10, 10)
	x:SetPoint("CENTER")
	x:SetVertexColor(0.78, 0.79, 0.82)
	b.Icon = x
	return b
end
function M:StyleCheckButton(b)
	if not b or styled[b] then
		return b
	end
	styled[b] = true
	for _, g in ipairs({"GetNormalTexture", "GetPushedTexture", "GetDisabledTexture"}) do
		local t = b[g] and b[g](b)
		if t then
			t:SetTexture(0, 0, 0, 0)
		end
	end
	local hl = b:GetHighlightTexture()
	if hl then
		hl:SetTexture(SKIN.hover[1], SKIN.hover[2], SKIN.hover[3], 0.13)
		hl:SetBlendMode("BLEND")
		hl:ClearAllPoints()
		hl:SetPoint("TOPLEFT", 5, -5)
		hl:SetPoint("BOTTOMRIGHT", -5, 5)
	end
	local bg = fill(b, "BACKGROUND", nil, SKIN.btn)
	bg:SetPoint("TOPLEFT", 5, -5)
	bg:SetPoint("BOTTOMRIGHT", -5, 5)
	local e = CreateFrame("Frame", nil, b)
	e:SetPoint("TOPLEFT", 5, -5)
	e:SetPoint("BOTTOMRIGHT", -5, 5)
	outline(e, "BORDER", nil, SKIN.edge)
	b:SetCheckedTexture(GFX .. "check.tga")
	prepCheckMark(b:GetCheckedTexture(), 1, 1, 1)
	if b.SetDisabledCheckedTexture then
		b:SetDisabledCheckedTexture(GFX .. "check.tga")
		prepCheckMark(b:GetDisabledCheckedTexture(), 0.42, 0.44, 0.48)
	end
	return b
end

do -- EscapeCallback
	local catchers = {}
	local function refresh()
		if InCombatLockdown() then
			return
		end
		for i = 1, #catchers do
			ClearOverrideBindings(catchers[i])
		end
		for i = 1, #catchers do
			local c = catchers[i]
			if c.owner:IsVisible() then
				SetOverrideBindingClick(c, true, c.key, c:GetName())
			end
		end
	end
	local pending
	local function refreshSoon()
		refresh()
		if not pending then
			pending = true
			EV.After(0, function()
				pending = nil
				refresh()
			end)
		end
	end
	local function ESC_OnClick(self)
		if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() ~= nil then
			return
		end
		return self.callback(self.owner, self.key)
	end
	EV.PLAYER_REGEN_ENABLED = refresh
	function M:EscapeCallback(parent, key2, callback)
		if callback == nil then
			callback, key2 = key2, nil
		end
		for i = 1, key2 and 2 or 1 do
			local c = CreateFrame("Button", "TenSettingsEscapeCatcher" .. (#catchers + 1), parent)
			c.owner, c.callback, c.key = parent, callback, i == 2 and key2 or "ESCAPE"
			c:SetScript("OnClick", ESC_OnClick)
			catchers[#catchers + 1] = c
		end
		parent:HookScript("OnShow", refreshSoon)
		parent:HookScript("OnHide", refreshSoon)
		refreshSoon()
	end
end
do -- TenSettingsFrame
	local HEADER_HEIGHT, FOOTER_HEIGHT, RAIL_WIDTH, TAB_HEIGHT = 34, 46, 138, 30
	local CONTAINER_CONTENT_TOP_YOFFSET, CONTAINER_TITLE_YOFFSET = -30, -7
	local CONTAINER_PADDING_H, CONTAINER_PADDING_V = 10, 8
	local PANEL_VIEW_MARGIN_TOP, PANEL_VIEW_MARGIN_TOP_TITLESHIFT = -14, -35
	local PANEL_VIEW_MARGIN_LEFT, PANEL_VIEW_MARGIN_RIGHT = -15, -10
	M.PANEL_VIEW_MARGIN_TOP_TITLESHIFT = PANEL_VIEW_MARGIN_TOP_TITLESHIFT

	local PANEL_WIDTH, PANEL_HEIGHT = 585, 528
	local CONTAINER_WIDTH = PANEL_WIDTH + CONTAINER_PADDING_H * 2 + RAIL_WIDTH
	local CONTAINER_HEIGHT = PANEL_HEIGHT - CONTAINER_CONTENT_TOP_YOFFSET + CONTAINER_PADDING_V * 2
	local WINDOW_WIDTH = CONTAINER_WIDTH + 2
	local WINDOW_HEIGHT = CONTAINER_HEIGHT + HEADER_HEIGHT + FOOTER_HEIGHT

	local TenSettingsFrame, notifyTenant = CreateFrame("Frame", "TenSettingsFrame", UIParent)
	do
		box(TenSettingsFrame, "BACKGROUND", -8, SKIN.bg)
		outline(TenSettingsFrame, "BACKGROUND", -7, SKIN.edge)
		local header = CreateFrame("Frame", nil, TenSettingsFrame)
		header:SetPoint("TOPLEFT", 1, -1)
		header:SetPoint("TOPRIGHT", -1, -1)
		header:SetHeight(HEADER_HEIGHT - 1)
		box(header, "BACKGROUND", -6, SKIN.header)
		local hl = fill(header, "BORDER", nil, SKIN.line)
		hl:SetHeight(1)
		hl:SetPoint("BOTTOMLEFT")
		hl:SetPoint("BOTTOMRIGHT")
		local ha = fill(header, "BORDER", nil, SKIN.accent)
		ha:SetSize(3, 15)
		ha:SetPoint("LEFT", 11, 0)
		TenSettingsFrame.Header = header
		local _tsTitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		_tsTitle:SetPoint("LEFT", 21, 0)
		TenSettingsFrame.NineSlice = {
			Text = _tsTitle
		}
		local _tsVersion = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		_tsVersion:SetPoint("LEFT", _tsTitle, "RIGHT", 6, -1)
		TenSettingsFrame.HeaderVersion = _tsVersion
		local _tsClose = CreateFrame("Button", nil, header, "UIPanelCloseButton")
		_tsClose:SetPoint("RIGHT", -7, 0)
		M:StyleCloseButton(_tsClose)
		TenSettingsFrame.ClosePanelButton = _tsClose
		TenSettingsFrame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
		TenSettingsFrame:SetPoint("CENTER", 0, 50)
		TenSettingsFrame.NineSlice.Text:SetText(OPTIONS)
		TenSettingsFrame:SetFrameStrata("HIGH")
		TenSettingsFrame:SetToplevel(true)
		TenSettingsFrame:Hide()
		TenSettingsFrame:EnableMouse(true)
		TenSettingsFrame:SetClampedToScreen(true)
		TenSettingsFrame:SetClampRectInsets(5, 0, 0, 0)
		TenSettingsFrame:SetResizable(true)
		TenSettingsFrame:SetMinResize(WINDOW_WIDTH, WINDOW_HEIGHT)
		TenSettingsFrame:SetMaxResize(1100, 860)
		TenSettingsFrame:SetUserPlaced(true)
		local f = CreateFrame("Frame", nil, TenSettingsFrame)
		f:SetPoint("TOPLEFT", 1, -HEADER_HEIGHT)
		f:SetPoint("BOTTOMRIGHT", -1, 1)
		f.OverlayFaderMargin = 0
		TenSettingsFrame.WindowArea = f
		local fl = fill(f, "BORDER", nil, SKIN.line)
		fl:SetHeight(1)
		fl:SetPoint("BOTTOMLEFT", 0, FOOTER_HEIGHT)
		fl:SetPoint("BOTTOMRIGHT", 0, FOOTER_HEIGHT)
		f = CreateFrame("Frame", nil, f)
		f:SetPoint("TOPLEFT")
		f:SetPoint("BOTTOMRIGHT", 0, FOOTER_HEIGHT)
		TenSettingsFrame.ContentArea = f
		local cancel = CreateFrame("Button", nil, TenSettingsFrame.WindowArea, "UIPanelButtonTemplate")
		cancel:SetSize(112, 26)
		cancel:SetPoint("BOTTOMRIGHT", -12, 11)
		cancel:SetText(CANCEL)
		M:StyleButton(cancel)
		TenSettingsFrame.Cancel = cancel
		local save = CreateFrame("Button", nil, TenSettingsFrame.WindowArea, "UIPanelButtonTemplate")
		save:SetSize(112, 26)
		save:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
		save:SetText(OKAY)
		M:StyleButton(save, "primary")
		TenSettingsFrame.Save = save
		local defaults = CreateFrame("Button", nil, TenSettingsFrame.WindowArea, "UIPanelButtonTemplate")
		defaults:SetSize(112, 26)
		defaults:SetPoint("BOTTOMLEFT", 12, 11)
		defaults:SetText(DEFAULTS)
		M:StyleButton(defaults)
		TenSettingsFrame.Reset = defaults
		local revert = CreateFrame("Button", nil, TenSettingsFrame.WindowArea, "UIPanelButtonTemplate")
		do
			revert:SetSize(112, 26)
			revert:SetPoint("LEFT", defaults, "RIGHT", 8, 0)
			revert:SetText(REVERT)
			M:StyleButton(revert)
			local drop = CreateFrame("Frame", nil, revert, "UIDropDownMenuTemplate")
			UIDropDownMenu_SetAnchor(drop, 0, 2, "BOTTOM", revert, "TOP")
			UIDropDownMenu_SetDisplayMode(drop, "MENU")
			revert:SetScript("OnClick", function()
				ToggleDropDownMenu(1, nil, drop)
				PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
			end)
			function revert:HandlesGlobalMouseEvent(button, _ev)
				return button == "LeftButton"
			end
			local function performRevert(_, idx)
				if idx == -1 then
					I.undo:UnwindStack()
				else
					I.undo:UnwindArchives(idx)
				end
				notifyTenant("OnRefresh")
			end
			local function formatTime(td)
				if GetCVarBool("timeMgrUseMilitaryTime") then
					return date("%H:%M:%S", time() - td)
				end
				return (date("%I:%M:%S %p", time() - td):gsub("^0(%d)", "%1"))
			end
			function drop:initialize()
				local info, text = {
					func = performRevert,
					notCheckable = 1,
					justifyH = "CENTER"
				}, revert.optionText or "%2$s"
				local now, numEntries, numArchives, firstTime = GetServerTime(), I.undo:GetState()
				for i = 1, numArchives + (numEntries > 0 and 1 or 0) do
					local isCancel = i > numArchives
					local td = now - (isCancel and firstTime or I.undo:GetArchiveInfo(i))
					local cc = isCancel and "|cffffb000" or ""
					info.text, info.arg1 = cc .. text:format(math.floor(td / 60 + 0.5), formatTime(td)),
						isCancel and -1 or i
					UIDropDownMenu_AddButton(info)
				end
			end
			TenSettingsFrame.Revert, revert.drop = revert, drop
		end
		M:EscapeCallback(TenSettingsFrame, function(self)
			self.ClosePanelButton:Click()
		end)
		-- UISpecialFrames registration removed: causes taint in CloseAllWindows() secure path.
		-- EscapeCallback above already handles Escape key for this frame.
		local dragHandle = CreateFrame("Frame", nil, TenSettingsFrame)
		do
			dragHandle:SetPoint("TOPLEFT", TenSettingsFrame, "TOPLEFT", 1, -1)
			dragHandle:SetPoint("BOTTOMRIGHT", TenSettingsFrame, "TOPRIGHT", -30, -HEADER_HEIGHT)
			dragHandle:RegisterForDrag("LeftButton")
			dragHandle:EnableMouse(true)
			dragHandle:SetScript("OnDragStart", function()
				TenSettingsFrame:SetMovable(true)
				TenSettingsFrame:StartMoving()
			end)
			dragHandle:SetScript("OnDragStop", function()
				TenSettingsFrame:StopMovingOrSizing()
				I.settingsFrameMoved = true
			end)
		end
		do -- resize grip (bottom-right corner)
			local resizeGrip = CreateFrame("Button", nil, TenSettingsFrame)
			resizeGrip:SetSize(16, 16)
			resizeGrip:SetPoint("BOTTOMRIGHT", -4, 4)
			resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
			resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
			resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
			resizeGrip:GetNormalTexture():SetVertexColor(0.45, 0.47, 0.52)
			resizeGrip:SetScript("OnMouseDown", function(self, button)
				if button == "LeftButton" then
					TenSettingsFrame:StartSizing("BOTTOMRIGHT")
				end
			end)
			resizeGrip:SetScript("OnMouseUp", function()
				TenSettingsFrame:StopMovingOrSizing()
				I.settingsFrameMoved = true
			end)
		end
	end
	local ConfusableResetDialog, crd_show, CRD_QUESTION_TEXT = CreateFrame("Frame", nil)
	do
		local d, t, tenant = ConfusableResetDialog
		d:Hide()
		d:SetSize(460, 105)
		local function onResetButtonClick(self)
			local id = self:GetID()
			if id ~= 0 then
				notifyTenant("OnDefault", tenant, select(id, "current-panel-only"))
			end
			ConfusableResetDialog:Hide()
		end
		t = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		t:SetPoint("TOP", -15, -8)
		t:SetWidth(410)
		t, d.Question = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), t
		t:SetPoint("BOTTOM", -15, 38)
		t:SetWidth(410)
		t, d.Hint = CreateFrame("Button", nil, d, "UIPanelButtonTemplate", 2), t
		t:SetSize(150, 24)
		t:SetPoint("BOTTOM", -150, 6)
		t:SetText(ALL_SETTINGS)
		t:SetScript("OnClick", onResetButtonClick)
		t, d.AllSet = CreateFrame("Button", nil, d, "UIPanelButtonTemplate", 0), t
		t:SetSize(130, 24)
		t:SetPoint("BOTTOM", 0, 6)
		t:SetText(CANCEL)
		t:SetScript("OnClick", onResetButtonClick)
		t, d.Cancel = CreateFrame("Button", nil, d, "UIPanelButtonTemplate", 1), t
		t:SetSize(150, 24)
		t:SetPoint("BOTTOM", 150, 6)
		t:SetText(CURRENT_SETTINGS)
		t:SetScript("OnClick", onResetButtonClick)
		d.OnlyThese = t
		M:StyleButton(d.AllSet)
		M:StyleButton(d.Cancel)
		M:StyleButton(d.OnlyThese, "primary")
		d:SetScript("OnHide", function(self)
			self:Hide()
			tenant = nil
		end)
		function crd_show(forTenant, thisName, rootName)
			local qt, cc = CRD_QUESTION_TEXT or CONFIRM_RESET_INTERFACE_SETTINGS, NORMAL_FONT_COLOR_CODE
			ConfusableResetDialog.Question:SetFormattedText(qt, cc .. tostring(rootName) .. "|r",
				cc .. tostring(thisName) .. "|r")
			tenant = forTenant
			M:ShowFrameOverlay(TenSettingsFrame.WindowArea, ConfusableResetDialog)
		end
	end

	local minitabs = {}
	local function minitab_deselect(self)
		local r = minitabs[self]
		r.SelectedBG:Hide()
		r.Marker:Hide()
		self:SetNormalFontObject(GameFontDisableSmall)
	end
	local function minitab_select(self)
		local r = minitabs[self]
		r.SelectedBG:Show()
		r.Marker:Show()
		self:SetNormalFontObject(GameFontHighlightSmall)
	end
	local function minitab_new(parent, text)
		local b, r, t = CreateFrame("Button", nil, parent), {}
		minitabs[b], r.f = r, b
		t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		b:SetFontString(t)
		t:ClearAllPoints()
		t:SetPoint("LEFT", 16, 0)
		t:SetPoint("RIGHT", -8, 0)
		t:SetJustifyH("LEFT")
		b:SetDisabledFontObject(GameFontDisableSmall)
		b:SetHighlightFontObject(GameFontHighlightSmall)
		b:SetPushedTextOffset(0, 0)
		t:SetText(text)
		t:SetWordWrap(false)
		r.Text = t
		r.SelectedBG = box(b, "BACKGROUND", -2, SKIN.accentDim)
		box(b, "HIGHLIGHT", nil, SKIN.hover)
		t = fill(b, "ARTWORK", nil, SKIN.accent)
		t:SetWidth(3)
		t:SetPoint("TOPLEFT")
		t:SetPoint("BOTTOMLEFT")
		r.Marker = t
		b:SetSize(RAIL_WIDTH, TAB_HEIGHT)
		minitab_deselect(b)
		return b
	end

	local containers = {}
	local container_notifications, container_notifications_internal = {}, {}
	do
		local function container_notify_panels(self, notification, ...)
			local ci = containers[self]
			local onlyNotifyCurrentPanel = (...) == "current-panel-only"
			I.HandlePanelNotification(notification)
			for i = 1, math.max(#ci.tabs, 1) do
				local panel = ci.tabs[ci.tabs[i]] or ci.root
				if panel[notification] and (ci.currentPanel == panel or not onlyNotifyCurrentPanel) then
					securecall(panel[notification], panel)
				end
			end
			if container_notifications_internal[notification] then
				securecall(container_notifications_internal[notification], self, ...)
			end
		end
		for s in ("okay cancel default refresh"):gmatch("%S+") do
			container_notifications[s] = function(self, ...)
				container_notify_panels(self, s, ...)
			end
		end
	end
	local function container_setTenant(ci, newPanel)
		if ci.currentPanel == newPanel then
			return
		end
		if ci.currentPanel then
			ci.currentPanel:Hide()
			minitab_deselect(ci.tabs[ci.currentPanel])
		end
		ci.currentPanel = newPanel
		minitab_select(ci.tabs[newPanel])
		local oy = -PANEL_VIEW_MARGIN_TOP
		if newPanel.TenSettings_TitleBlock then
			newPanel.title:Hide()
			newPanel.version:Hide()
			oy = -PANEL_VIEW_MARGIN_TOP_TITLESHIFT
		end
		local isRoot = newPanel == ci.root
		local brandContainer = not (isRoot and ci.selfBrandedRoot)
		ci.Title:SetText(newPanel.name or ci.name)
		ci.Title:SetShown(brandContainer)
		ci.TitleRule:SetShown(brandContainer)
		TenSettingsFrame.NineSlice.Text:SetText(ci.name)
		TenSettingsFrame.HeaderVersion:SetText((ci.forceRootVersion and ci.root or newPanel).version and
												   (ci.forceRootVersion and ci.root or newPanel).version:GetText() or "")
		newPanel:SetParent(ci.View)
		newPanel:ClearAllPoints()
		newPanel:SetPoint("TOPLEFT", CONTAINER_PADDING_H + PANEL_VIEW_MARGIN_LEFT, oy - CONTAINER_PADDING_V)
		newPanel:SetPoint("BOTTOMRIGHT", -PANEL_VIEW_MARGIN_RIGHT - CONTAINER_PADDING_H, CONTAINER_PADDING_V)
		newPanel:Show()
		if newPanel.refresh and ci.f:IsShown() then
			securecall(newPanel.refresh, newPanel)
		end
		return true
	end
	local function container_selectTab(self, button)
		local ci = containers[self:GetParent()]
		local newPanel = ci.tabs[self]
		if container_setTenant(ci, newPanel) and button then
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
		end
	end
	local function container_addTab(ci, panel, text)
		local tabs = ci.tabs
		local prev, idx = tabs[#tabs], #tabs + 1
		local tab = minitab_new(ci.Rail, text or panel.name)
		tabs[idx], tabs[panel], tabs[tab] = tab, tab, panel
		tab:SetScript("OnClick", container_selectTab)
		if prev == nil then
			tab:SetPoint("TOPLEFT", ci.Rail, "TOPLEFT", 0, -10)
			container_selectTab(tab, nil)
		else
			tab:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, idx == 2 and -8 or 0)
		end
		return tab
	end
	local function container_new(name, rootPanel, opts)
		local cf = CreateFrame("Frame")
		do
			cf:Hide()
			cf:SetScript("OnMouseWheel", noop)
			cf:EnableMouseWheel(true)
			local cn = container_notifications
			cf.OnCommit, cf.OnDefault, cf.OnRefresh, cf.OnCancel = cn.okay, cn.default, cn.refresh, cn.cancel
			cf:SetSize(CONTAINER_WIDTH, CONTAINER_HEIGHT)
		end
		local ci = {
			f = cf,
			tabs = {},
			name = name,
			root = rootPanel
		}
		local rail = CreateFrame("Frame", nil, cf)
		rail:SetPoint("TOPLEFT")
		rail:SetPoint("BOTTOMLEFT")
		rail:SetWidth(RAIL_WIDTH)
		box(rail, "BACKGROUND", -5, SKIN.rail)
		local rl = fill(rail, "BORDER", nil, SKIN.line)
		rl:SetWidth(1)
		rl:SetPoint("TOPRIGHT")
		rl:SetPoint("BOTTOMRIGHT")
		ci.Rail = rail
		local t = cf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		t:SetPoint("TOPLEFT", RAIL_WIDTH + 16, CONTAINER_TITLE_YOFFSET)
		t:SetText(name)
		ci.Title = t
		t = fill(cf, "BORDER", nil, SKIN.line)
		t:SetHeight(1)
		t:SetPoint("TOPLEFT", RAIL_WIDTH + 16, CONTAINER_CONTENT_TOP_YOFFSET + 2)
		t:SetPoint("TOPRIGHT", -14, CONTAINER_CONTENT_TOP_YOFFSET + 2)
		ci.TitleRule = t
		t = CreateFrame("Frame", nil, cf)
		t:SetPoint("TOPLEFT", RAIL_WIDTH + 1, CONTAINER_CONTENT_TOP_YOFFSET)
		t:SetPoint("BOTTOMRIGHT", 0, 0)
		ci.View = t
		if type(opts) == "table" then
			ci.forceRootVersion = opts.forceRootVersion
			ci.rootTabText = opts.tabText
			ci.selfBrandedRoot = opts.selfBrandedRoot
		end
		containers[rootPanel], containers[name], containers[cf], containers[rail] = ci, ci, ci, ci
		return ci
	end
	local function container_selectRootPanel(self)
		local ci = containers[self]
		if ci and #ci.tabs > 1 then
			container_setTenant(ci, ci.root)
		end
	end
	local function container_isResetConfusable(f)
		local ci = containers[f]
		if ci and ci.f == f and ci.currentPanel.default then
			local dc = 0
			for i = 1, #ci.tabs do
				if ci.tabs[ci.tabs[i]].default ~= nil then
					dc = dc + 1
					if dc == 2 then
						local ct = ci.tabs[ci.currentPanel]
						return true, ct and ct:GetText() or ci.currentPanel.name, ci.name
					end
				end
			end
		end
		return false
	end
	container_notifications_internal.okay = container_selectRootPanel
	container_notifications_internal.cancel = container_selectRootPanel

	local currentSettingsTenant
	function notifyTenant(notification, filter, ...)
		local nf = currentSettingsTenant and currentSettingsTenant[notification]
		if nf and (filter == nil or currentSettingsTenant == filter) then
			securecall(nf, currentSettingsTenant, ...)
		end
	end
	local function settings_show(newTenant)
		if currentSettingsTenant then
			currentSettingsTenant:Hide()
			currentSettingsTenant:ClearAllPoints()
			currentSettingsTenant = nil
		end
		newTenant:ClearAllPoints()
		newTenant:SetParent(TenSettingsFrame.ContentArea)
		newTenant:SetPoint("TOPLEFT")
		newTenant:SetPoint("BOTTOMRIGHT")
		currentSettingsTenant = newTenant
		securecall(newTenant.OnRefresh, newTenant)
		newTenant:Show()
		if not (TenSettingsFrame:IsShown() or I.settingsFrameMoved) then
			TenSettingsFrame:ClearAllPoints()
			TenSettingsFrame:SetPoint("CENTER", 0, 50)
		end
		local cw, ch = TenSettingsFrame:GetSize()
		if (cw or 0) < WINDOW_WIDTH or (ch or 0) < WINDOW_HEIGHT then
			TenSettingsFrame:SetSize(math.max(cw or 0, WINDOW_WIDTH), math.max(ch or 0, WINDOW_HEIGHT))
		end
		I.OnUndoStateChange()
		TenSettingsFrame:Show()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
	end
	local function settings_hide(dismissCommit, skipSound)
		if dismissCommit and currentSettingsTenant and currentSettingsTenant.OnCommit then
			securecall(currentSettingsTenant.OnCommit, currentSettingsTenant, "commit-on-dismiss")
		end
		TenSettingsFrame:Hide()
		if currentSettingsTenant then
			currentSettingsTenant:Hide()
			currentSettingsTenant:ClearAllPoints()
			currentSettingsTenant = nil
		end
		I.undo:ArchiveStack()
		if not skipSound then
			PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
		end
	end

	do -- Detect settings dismissal, archive undo stack
		local cueWatcher
		do
			local waitLeft, watcher = 0, CreateFrame("Frame")
			watcher:Hide()
			watcher:SetScript("OnUpdate", function(_, elapsed)
				if elapsed and elapsed < waitLeft then
					waitLeft = waitLeft - elapsed
					return
				end
				waitLeft = 0.2
				if TenSettingsFrame:IsVisible() or I.undo:GetState() == 0 then
					watcher:Hide()
				elseif not TenSettingsFrame:IsShown() then
					if currentSettingsTenant then
						settings_hide(true, true)
					end
					I.undo:ArchiveStack()
					watcher:Hide()
				end
			end)
			function cueWatcher()
				waitLeft = 0
				watcher:Show()
			end
		end
		CreateFrame("Frame", nil, TenSettingsFrame):SetScript("OnHide", cueWatcher)
	end

	TenSettingsFrame.ClosePanelButton:SetScript("OnClick", function()
		settings_hide(true)
	end)
	TenSettingsFrame.Save:SetScript("OnClick", function()
		if currentSettingsTenant then
			securecall(currentSettingsTenant.OnCommit, currentSettingsTenant)
		end
		settings_hide()
	end)
	TenSettingsFrame.Reset:SetScript("OnClick", function()
		if currentSettingsTenant and currentSettingsTenant.OnDefault then
			local isConfusable, currentName, rootName = container_isResetConfusable(currentSettingsTenant)
			if isConfusable then
				crd_show(currentSettingsTenant, currentName, rootName)
			else
				securecall(currentSettingsTenant.OnDefault, currentSettingsTenant)
			end
			PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
		end
	end)
	TenSettingsFrame.Cancel:SetScript("OnClick", function()
		if currentSettingsTenant and currentSettingsTenant.OnCancel then
			securecall(currentSettingsTenant.OnCancel, currentSettingsTenant)
		end
		settings_hide()
	end)

	local function openSettingsPanel(panel)
		local ci = containers[panel]
		container_setTenant(ci, panel)
		settings_show(ci.f)
	end
	function I.AddOptionsCategory(panel, opts)
		local name, parent = panel.name, panel.parent
		local ci = containers[parent]
		assert(parent == nil or ci)
		if parent == nil then
			ci = container_new(name, panel, opts)
			panel:SetParent(ci.f)
		else
			containers[panel] = ci
			panel:SetParent(ci.f)
			if #ci.tabs == 0 then
				container_addTab(ci, ci.root, ci.rootTabText or OPTIONS)
			end
			container_addTab(ci, panel)
		end
		panel.OpenPanel = openSettingsPanel
	end
	function I.GetOverlayDefaults(f)
		local p2 = f and f:GetParent()
		p2 = p2 and p2:GetParent()
		local ci = containers[f]
		if ci and ci.f == p2 then
			return p2, f.OverlayFaderMargin or 0, 0
		end
		return nil, f.OverlayFaderMargin
	end
	function I.OnUndoStateChange()
		local nEntries, nArchives = I.undo:GetState()
		TenSettingsFrame.Revert:SetEnabled(nEntries > 0 or nArchives > 0)
	end
	function M:Localize(t)
		CRD_QUESTION_TEXT = t.RESET_QUESTION
		ConfusableResetDialog.AllSet:SetText(t.DEFAULTS_ALL or ALL_SETTINGS)
		ConfusableResetDialog.OnlyThese:SetText(t.DEFAULTS_VISIBLE or CURRENT_SETTINGS)
		TenSettingsFrame.Revert:SetText(t.REVERT or REVERT)
		TenSettingsFrame.Revert.optionText = t.REVERT_OPTION_LABEL
		ConfusableResetDialog.Hint:SetText(t.REVERT_CANCEL_HINT or "")
	end
end

do -- M:CreateUndoHandle()
	local undoStack, archives, undo, uhandle, pendingNotify = {}, {}, {}, {}, false
	local MAX_ARCHIVES = 10
	I.undo = undo
	local function storeUndoEntry(idx, ns, key, func, ...)
		local bot, now = undoStack.bottom, GetServerTime()
		undoStack[idx] = {
			ns = ns,
			key = key,
			func = func,
			n = select("#", ...),
			...
		}
		undoStack.bottom = (bot == nil or bot > idx) and idx or bot
		undoStack.firstTime, undoStack.lastTime = undoStack.firstTime or now, now
	end
	local function unwind(us, msg)
		undoStack = us == undoStack and {} or undoStack
		for i = #us, us.bottom or 1, -1 do
			i = us[i]
			securecall(i.func, msg, unpack(i, 1, i.n))
		end
	end
	local function archive(data)
		for i = 1, #archives == MAX_ARCHIVES and MAX_ARCHIVES or 0 do
			archives[i] = archives[i + 1]
		end
		data.archiveTime = data.archiveTime or GetServerTime()
		undoStack = undoStack == data and {} or undoStack
		archives[#archives + 1] = data
	end
	local function rearchive(_msg, aa)
		for i = #aa, 1, -1 do
			archive(aa[i])
		end
	end
	local function notifyStateChanged()
		pendingNotify = false
		I.OnUndoStateChange()
	end
	function undo:UnwindStack()
		unwind(undoStack, "unwind")
		undo:NotifyStateChanged()
	end
	function undo:UnwindArchives(idx)
		if undoStack.bottom then
			unwind(undoStack, "unwind")
		end
		local uw, ai = {}
		for i = #archives, idx, -1 do
			ai, uw[#uw + 1], archives[i] = archives[i], archives[i], nil
			unwind(ai, "archive-unwind")
		end
		if #uw > 0 and undoStack.bottom then
			storeUndoEntry(#undoStack + 1, nil, nil, rearchive, uw)
		end
		undo:NotifyStateChanged()
	end
	function undo:GetState()
		local bot = undoStack.bottom
		return #undoStack + (bot and 1 - bot or 0), #archives, undoStack.firstTime
	end
	function undo:ArchiveStack()
		if #undoStack > 0 or undoStack.bottom then
			archive(undoStack)
			undo:NotifyStateChanged()
		end
	end
	function undo:GetArchiveInfo(idx)
		local ai = archives[idx]
		if ai then
			return ai.firstTime, ai.lastTime, ai.archiveTime
		end
	end
	function undo:ClearStack()
		if undoStack.bottom then
			undoStack = {}
			undo:NotifyStateChanged()
		end
	end
	function undo:NotifyStateChanged()
		if not pendingNotify and I.OnUndoStateChange then
			pendingNotify = true
			EV.After(0, notifyStateChanged)
		end
	end
	function uhandle:search(key)
		for i = #undoStack, undoStack.bottom or 1, -1 do
			local e = undoStack[i]
			if e.ns == self and e.key == key then
				return true
			end
		end
	end
	function uhandle:push(...)
		storeUndoEntry(#undoStack + 1, self, ...)
		undo:NotifyStateChanged()
	end
	function uhandle:sink(...)
		storeUndoEntry((undoStack.bottom or 2) - 1, self, ...)
		undo:NotifyStateChanged()
	end
	local uhmeta = {
		__index = uhandle,
		__metatable = false
	}
	function M:CreateUndoHandle()
		return setmetatable({}, uhmeta)
	end
end
function I.HandlePanelNotification(notification)
	if notification == "okay" then
		I.undo:ArchiveStack()
	elseif notification == "cancel" then
		I.undo:UnwindStack()
	end
end

do -- M:ShowFrameOverlay(self, overlayFrame)
	local container, watcher, occupant = CreateFrame("Frame"), CreateFrame("Frame")
	do
		container:EnableMouse(true)
		container:Hide()
		M:EscapeCallback(container, function(self)
			self:Hide()
		end)
		container:SetScript("OnMouseWheel", function()
		end)
		container:EnableMouseWheel(true)
		container.fader = container:CreateTexture(nil, "BACKGROUND", nil, -6)
		container.fader:SetTexture(0, 0, 0, 0.55)
		local close = CreateFrame("Button", nil, container, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -5, -5)
		close:SetScript("OnClick", function()
			container:Hide()
		end)
		M:StyleCloseButton(close)
		box(container, "BACKGROUND", -5, SKIN.card)
		outline(container, "BORDER", -4, SKIN.edge)
		local ca = fill(container, "BORDER", -3, SKIN.accent)
		ca:SetHeight(2)
		ca:SetPoint("TOPLEFT", 1, -1)
		ca:SetPoint("TOPRIGHT", -1, -1)
		watcher:SetScript("OnHide", function()
			if occupant then
				container:Hide()
				PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
				occupant:Hide()
				occupant = nil
			end
		end)
	end
	function M:ShowFrameOverlay(self, overlayFrame)
		if occupant and occupant ~= overlayFrame then
			occupant:Hide()
		end
		local cw, ch = overlayFrame:GetSize()
		local w2, h2 = self:GetSize()
		local w, h, isRefresh = cw + 24, ch + 24, occupant == overlayFrame
		local frameLevel = (math.ceil(self:GetFrameLevel() / 500) + 1) * 500
		w2, h2, occupant = w2 > w and (w - w2) / 2 or 0, h2 > h and (h - h2) / 2 or 0
		container:SetSize(w, h)
		container:SetHitRectInsets(w2, w2, h2, h2)
		container:SetParent(self)
		container:SetPoint("CENTER")
		container:SetFrameLevel(frameLevel)
		container.fader:ClearAllPoints()
		local oaf, omd, omt, omr, omb, oml = I.GetOverlayDefaults(self)
		oaf, omd = oaf or self, type(omd) == "number" and omd or 2
		container.fader:SetPoint("TOPLEFT", oaf, "TOPLEFT", (oml or omd), -(omt or omd))
		container.fader:SetPoint("BOTTOMRIGHT", oaf, "BOTTOMRIGHT", -(omr or omd), omb or omd)
		container:SetFrameStrata("DIALOG")
		container:Show()
		overlayFrame:ClearAllPoints()
		overlayFrame:SetParent(container)
		overlayFrame:SetPoint("CENTER")
		overlayFrame:Show()
		watcher:SetParent(overlayFrame)
		watcher:Show()
		CloseDropDownMenus()
		if not isRefresh then
			PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
		end
		occupant = overlayFrame
	end
end
do -- M:Show{Prompt,Alert,Copy}Overlay(...)
	local promptFrame, promptInfo, promptTextChanged = CreateFrame("Frame"), {}
	do
		promptFrame:SetSize(400, 130)
		promptInfo.title = promptFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		promptInfo.prompt = promptFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		promptInfo.editBox = XU:Create("LineInput", nil, promptFrame)
		promptInfo.editBox:SetStyle("chat")
		promptInfo.editBox:SetWidth(300)
		promptInfo.accept = M:StyleButton(CreateFrame("Button", nil, promptFrame, "UIPanelButtonTemplate"), "primary")
		promptInfo.cancel = M:StyleButton(CreateFrame("Button", nil, promptFrame, "UIPanelButtonTemplate"))
		promptInfo.detail = promptFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		promptInfo.title:SetPoint("TOP", 0, -3)
		promptInfo.prompt:SetPoint("TOP", promptInfo.title, "BOTTOM", 0, -8)
		promptInfo.editBox:SetPoint("TOP", promptInfo.prompt, "BOTTOM", 0, -7)
		promptInfo.detail:SetPoint("TOP", promptInfo.editBox, "BOTTOM", 0, -8)
		promptInfo.prompt:SetWidth(380)
		promptInfo.detail:SetWidth(380)

		promptInfo.cancel:SetScript("OnClick", function()
			if promptInfo.callback and promptInfo.callbackOnCancel then
				promptInfo.callback(promptInfo.editBox, false)
			end
			promptFrame:Hide()
		end)
		promptTextChanged = function(self)
			local cb = promptInfo.callback
			promptInfo.accept:SetEnabled(type(cb) ~= "function" or
											 cb(self, self:GetText() or "", false, promptInfo.owner))
		end
		promptInfo.editBox:SetScript("OnTextChanged", promptTextChanged)
		promptInfo.accept:SetScript("OnClick", function()
			local callback, text = promptInfo.callback, promptInfo.editBox:GetText() or ""
			if callback == nil or callback(promptInfo.editBox, text, true, promptInfo.owner) then
				promptFrame:Hide()
			end
		end)
		promptInfo.editBox:SetScript("OnEnterPressed", function()
			promptInfo.accept:Click()
		end)
		promptInfo.editBox:SetScript("OnEscapePressed", function()
			promptInfo.cancel:Click()
		end)
	end
	function M:ShowPromptOverlay(frame, title, prompt, explainText, acceptText, callback, editBoxWidth, cancelText,
		editText)
		local showEditBox, editBox = editBoxWidth ~= false, promptInfo.editBox
		editText = showEditBox and type(editText) == "string" and editText or ""
		promptInfo.owner, promptInfo.callback, promptInfo.initEditText = frame, callback, nil
		promptInfo.callbackOnCancel = acceptText == false
		promptInfo.title:SetText(title or "")
		promptInfo.prompt:SetText(prompt or "")
		promptInfo.detail:SetText(explainText or "")
		editBox:SetScript("OnTextChanged", nil)
		editBox:SetText(editText)
		editBox:HighlightText(0, #editText)
		editBox:SetScript("OnTextChanged", promptTextChanged)
		promptTextChanged(editBox)
		editBox:SetShown(editBoxWidth ~= false)
		editBox:SetWidth(math.max(40, math.min(1, editBoxWidth or 0.50) * 380))
		promptFrame:SetHeight(55 + math.max(20, promptInfo.prompt:GetStringHeight()) +
								  (editBoxWidth ~= false and 30 or 0) + ((explainText or "") ~= "" and 20 or 0))
		promptInfo.cancel:ClearAllPoints()
		promptInfo.accept:ClearAllPoints()
		if acceptText ~= false then
			promptInfo.accept:SetText(acceptText or ACCEPT)
			promptInfo.cancel:SetText(cancelText or CANCEL)
			promptInfo.cancel:SetPoint("BOTTOMLEFT", promptFrame, "BOTTOM", 5, 2)
			promptInfo.accept:SetPoint("BOTTOMRIGHT", promptFrame, "BOTTOM", -5, 2)
			promptInfo.accept:Show()
		else
			promptInfo.accept:Hide()
			promptInfo.cancel:SetText(cancelText or OKAY)
			promptInfo.cancel:SetPoint("BOTTOM", 5, 2)
		end
		promptInfo.cancel:SetWidth(math.max(125, 25 + promptInfo.cancel:GetFontString():GetStringWidth()))
		promptInfo.accept:SetWidth(math.max(125, 25 + promptInfo.accept:GetFontString():GetStringWidth()))
		M:ShowFrameOverlay(frame, promptFrame)
		if showEditBox then
			editBox:SetFocus()
		end
	end
	local function restoreInitialCopyText(self)
		local restore = self == promptInfo.editBox and promptInfo.initEditText
		if restore and self:GetText() ~= restore then
			self:SetText(restore)
			self:HighlightText()
			self:SetCursorPosition(0)
		end
	end
	function M:ShowAlertOverlay(frame, title, message, dismissText, callback)
		return M:ShowPromptOverlay(frame, title, message, nil, false, callback, false, dismissText)
	end
	function M:ShowCopyOverlay(frame, title, message, copyText, explainText, cancelText, boxWidth)
		M:ShowPromptOverlay(frame, title, message, explainText, false, false, boxWidth or nil, cancelText, copyText)
		promptInfo.initEditText = copyText
		promptInfo.editBox:SetCursorPosition(0)
		promptInfo.editBox:SetScript("OnTextChanged", restoreInitialCopyText)
	end
end
function M:CreateOptionsPanel(name, parent, opts)
	local f, t, a = CreateFrame("Frame")
	f:Hide()
	f.name, f.parent = name, parent
	a = CreateFrame("Frame", nil, f)
	a:SetHeight(20)
	a:SetPoint("TOPLEFT")
	a:SetPoint("TOPRIGHT")
	t = a:CreateFontString(nil, "OVERLAY", "GameFontNormalLargeLeftTop")
	t:SetPoint("TOPLEFT", 16, -16)
	t:SetText(name)
	t, f.title = a:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), t
	t:SetPoint("TOPLEFT", f.title, "TOPRIGHT", 4, 3)
	t, f.version = a:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall2"), t
	t:SetJustifyH("LEFT")
	t:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
	t:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, 0)
	f.desc = t
	f.TenSettings_TitleBlock = true
	I.AddOptionsCategory(f, opts)
	return f
end
do -- M:CreateOptionsCheckButton(name, parent)
	local function updateCheckButtonHitRect(self)
		local b = self:GetParent()
		b:SetHitRectInsets(0, -self:GetStringWidth() - 5, 4, 4)
	end
	function M:CreateOptionsCheckButton(name, parent)
		local b = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
		b:SetSize(24, 24)
		M:StyleCheckButton(b)
		if not b.Text then
			b.Text = (name and _G[name .. "Text"])
			if not b.Text then
				for _, r in ipairs({b:GetRegions()}) do
					if r.GetObjectType and r:GetObjectType() == "FontString" then
						b.Text = r;
						break
					end
				end
			end
		end
		b.Text:SetPoint("LEFT", b, "RIGHT", 2, 1)
		b.Text:SetFontObject(GameFontHighlightLeft)
		hooksecurefunc(b.Text, "SetText", updateCheckButtonHitRect)
		return b
	end
end
