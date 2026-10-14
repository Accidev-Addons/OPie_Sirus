local MAJ, REV, _GG, _, T = 1, 50, _G, ...
if T.SkipLocalActionBook then
	return
end
local RW, EV, WR, AB, KR = {}, T.Evie, T.Ware, T.ActionBook:compatible(2, 36), T.ActionBook:compatible("Kindred", 1, 29)
assert(EV and WR and AB and KR and 1, "Incompatible library bundle")
local PYROLYSIS = {}
local AreDangerousScriptsAllowed, strcmputf8i = T.compat.AreDangerousScriptsAllowed, T.compat.strcmputf8i

local function assert(condition, err, ...)
	return condition or error(tostring(err):format(...), 3)((0)[0])
end
local rtnext = rtable.next

local Spell_CheckCastable = {}

local namedMacros, namedMacroText, namedMacroTextOwnerPriority, coreNamedMacroText = {}, {}, {}
local coreExecCleanup = {}
local core = CreateFrame("Frame", nil, nil, "SecureHandlerBaseTemplate")
local coreEnvW, coreEnv = WR.GetRestrictedEnvironment(core)
do
	local bni = 1
	for i = 1, 9 do
		local bn
		repeat
			bn, bni = "RW!" .. bni, bni + 1
		until GetClickFrame(bn) == nil
		local bw = CreateFrame("Button", bn, core, "SecureActionButtonTemplate")
		core:WrapScript(bw, "OnClick", [=[-- Rewire:OnClick_Pre
			if ns == 0 then return false end
			idle[self], numIdle, numActive, ns = nil, numIdle - 1, numActive + 1, ns - 1
			self:SetAttribute("macrotext", owner:RunAttribute("RunMacro", nil))
			return nil, 1
		]=], [=[-- Rewire:OnClick_Post
			idle[self], numIdle, numActive = 1, numIdle + 1, numActive - 1
			if ns == 0 and #execQueue > 0 then
				owner:CallMethod("throw", "Rewire executor pool exhausted; spilling queue (n=" .. #execQueue .. ").")
				wipe(execQueue)
				overfull, mutedAbove, modLock = false, -1, mutedAbove >= 0 and owner:CallMethod("setMute", false), nil
			end
		]=])
	end
	core:SetFrameRef("Kindred", KR:seclib())
	core:SetFrameRef("ActionBook", AB:seclib())
	core:SetAttribute("execPending", 0)
	local toAlphabetString
	do
		local a = {}
		for c in ("焼払解次善策氷雨"):gmatch("%S[\128-\191]*") do
			a[#a + 1] = c
		end
		function toAlphabetString(v)
			local s, n, r = "", #a
			repeat
				r = v % n
				s, v = s .. a[1 + r], (v - r) / n
			until v < 1
			return s
		end
	end
	local slashKey, slashCommand
	do
		local sb, si = "REWIRE_ICE_", 1
		repeat
			slashKey, si = sb .. si .. "X", si + 1
		until SlashCmdList[slashKey] == nil
		local slash = {}
		for k, v in pairs(_GG) do
			if type(k) == "string" and k:match("^SLASH_") then
				slash[v] = k
			end
		end
		si = 0
		repeat
			slashCommand, si = "/" .. toAlphabetString(si), si + 1
		until slash[slashCommand] == nil
	end
	_GG["SLASH_" .. slashKey .. "1"] = slashCommand
	local si, psabName = 0
	repeat
		psabName, si = toAlphabetString(si), si + 1
	until GetClickFrame(psabName) == nil
	local psab = CreateFrame("Button", psabName, nil, "SecureActionButtonTemplate")
	core:WrapScript(psab, "OnClick", [=[-- Rewire:PSAB_OnClick_PreWrap
		local idx, sqi = PY and PY.pendingResolve and (PY.runSIndex or 1)
		if not (idx and (PY.nextSIndex or 0) > idx) then return false end
		PY.runSIndex, sqi = idx + 1, PY.qS[idx]
		local kind = sqi[1]
		if kind == "CAST" then
			self:SetAttribute("type", "spell")
			self:SetAttribute("useOnKeyDown", down)
			self:SetAttribute("spell", sqi[2])
			self:SetAttribute("unit", sqi[3])
		elseif kind == "CLICK" then
			if sqi[4] and false == sqi[2]:RunAttribute("RunSlashCmd-PreClick", sqi[3], sqi[4]) then
				return false
			end
			self:SetAttribute("type", "click")
			self:SetAttribute("useOnKeyDown", down)
			return PY.delegateButton[sqi[2]] or false
		else
			return false
		end
	]=])
	core:SetAttribute("PY", true)
	core:SetAttribute("PYs", "/click " .. psabName)
	core:SetAttribute("PYi", slashCommand)
	core:SetAttribute("OnNotifyPostUse", [=[-- Rewire:OnNotifyPostUse
		if PY and PY.pendingResolve and PY.pendingResolve == ... then
			PY.pendingResolve = nil
			owner:CallMethod("quietCleanup")
		end
	]=])
	core:Execute([=[-- Rewire_PyrolysisInit
		PY, PYtokens, PYshortName, PYdangerCommands = newtable(), newtable(), newtable(), newtable()
		PY.delegateButton, PY.freeDelegateID, PY.dangerMode, PY.chatUnlocked = newtable(), 2^16 + math.random(2^16), true, true
		PY.qI, PY.qS, PY.id = newtable(), newtable(), 2^16 + math.random(2^16)
		PY.execI, PY.execS = self:GetAttribute("PYi"), self:GetAttribute("PYs")
		PY.execIL, PY.execSL = #PY.execI:gsub("[\128-\191]+", ""), #PY.execS:gsub("[\128-\191]+", "")
		PYtokens.nounshift, PYtokens.unshift_restore = newtable("#nounshift"), newtable("#nounshift-restore")
		PYtokens.unmute, PYtokens.mute = newtable("#mute"), newtable("#unmute")
		PYdangerCommands["/run"], PYdangerCommands["/dump"], PYdangerCommands["/tinspect"] = "/run", "/dump", "/tinspect"
		self:SetAttribute("PYs", nil)
		self:SetAttribute("PYi", nil)
		PY_EnqRun = [==[-- Rewire_PY_EnqRun
			local mt, tok = ...
			local mtc = mt and PY.dm and (mt:match("^/%S+") or mt:match("\n(/%S+)"))
			mt = mt or PYtokens[tok]
			if not (mt and PY.nextOIndex) then return false end
			mtc = mtc and mtc:lower()
			if PYdangerCommands[commandAlias[mtc] or mtc] then
				local nextLine = commandAlias["/run"] or "/run"
				nextLine, PY.dm = PYshortName[nextLine] or nextLine, nil
				local oi, lim, sz = PY.nextOIndex, PY.cFree
				sz = #nextLine:gsub("[\128-\191]+", "") + (oi > 1 and 1 or 0)
				PY[oi], PY.nextOIndex, PY.cFree, PY.lOver = nextLine, lim >= sz and oi + 1 or oi, lim - sz, PY.lOver + (lim < 0 and 1 or 0)
			end
			local oi, ii, ei, lim, sz = PY.nextOIndex, PY.nextIIndex, PY.execI, PY.cFree
			sz = PY.execIL + (oi > 1 and 1 or 0)
			if oi > 1 and ii > 1 and PY[oi-1] == ei then
				ii = ii - 1
			else
				PY[oi], PY.nextOIndex, PY.cFree, PY.lOver = ei, lim >= sz and oi + 1 or oi, lim - sz, PY.lOver + (lim < 0 and 1 or 0)
			end
			PY.qI[ii], PY.qI[ii+1], PY.nextIIndex = mt, 0, ii + 2
			return true
		]==]
	]=])
	function core:quietCleanup()
		for i = 1, #coreExecCleanup do
			securecall(coreExecCleanup[i])
		end
	end
	function PYROLYSIS:RegisterSlashCmdDelegate(delegate, id)
		psab:SetAttribute("clickbutton-" .. id, delegate)
	end
	do -- SlashCmdList[slashKey](msg, box)
		local runHandlers = {
			[coreEnv.PYtokens.unshift_restore] = function()
				core:manageUnshift(true)
			end,
			[coreEnv.PYtokens.nounshift] = function()
				core:manageUnshift(false)
			end,
			[coreEnv.PYtokens.mute] = function()
				core:setMute(true)
			end,
			[coreEnv.PYtokens.unmute] = function()
				core:setMute(false)
			end
		}
		local pyRunID, pyRunIIndex, commentLeads = nil, 0, {
			[35] = '#',
			[45] = '-',
			[47047] = '//'
		}
		SlashCmdList[slashKey] = function(_msg, box)
			local sPY = coreEnv.PY
			if not sPY.pendingResolve then
				return
			end
			local runID, nii, qI, rt, h = sPY.id, sPY.nextIIndex, sPY.qI
			if runID ~= pyRunID then
				pyRunIIndex, pyRunID = 1, runID
			end
			while pyRunIIndex < nii do
				rt, pyRunIIndex = qI[pyRunIIndex], pyRunIIndex + 1
				h = runHandlers[rt]
				if rt == 0 then
					break
				elseif h then
					securecall(h)
				elseif rt then
					local noRun = not AreDangerousScriptsAllowed() and coreEnv.PYdangerCommands
					for l in rt:gmatch("[^\r\n]+") do
						local b1, b2 = l:byte(1, 2)
						if not (commentLeads[b1] or b2 and commentLeads[b1 * 1e3 + b2]) then
							local c = noRun and l:match("^/%S+")
							c = c and c:lower()
							if not (c and noRun[coreEnv.commandAlias[c] or c]) then
								box:SetText(l)
								securecall(ChatEdit_SendText, box, false)
							end
						end
					end
				end
			end
		end
	end
	core:Execute([=[-- Rewire_Init
		KR, AB = self:GetFrameRef("Kindred"), self:GetFrameRef("ActionBook")
		execQueue, mutedAbove, QUEUE_LIMIT, overfull = newtable(), -1, 20000, false
		idle, cache, numIdle, numActive, ns, modLock = newtable(), newtable(), 0, 0, 0
		macros, namedMacroText, commandFlags, commandHandler, commandAlias = newtable(), newtable(), newtable(), newtable(), newtable()
		MACRO_TOKEN, NIL, metaCommands, transferTokens = newtable(nil, nil, nil, "MACRO_TOKEN"), newtable(), newtable(), newtable()
		metaCommands.mute, metaCommands.unmute, metaCommands.mutenext, metaCommands.parse, metaCommands.nounshift = 1, 1, 1, 1, 1
		castEscapes, castAliases = newtable(), newtable()
		reVars, soLiteralToEscapeSeq, soEscapeSeqToLiteral, soEscapePattern = newtable(), newtable(), newtable(), ""
		reMacroExt, reMacroExtOwner = newtable(), newtable()
		for c, e in KR:GetAttribute('SecureOptionEscapes'):gmatch("([^ ])(\\.)") do
			soLiteralToEscapeSeq[c], soEscapeSeqToLiteral[e], soEscapePattern = e, c, soEscapePattern .. c
		end
		soEscapePattern = "[" .. soEscapePattern:gsub("[%%[%]%.%-+*?()]", "%%%0") .. "]"
		valueToBooleanTruthy = newtable() do
			local fs = 'yYtT123456789'
			for i=1,#fs do
				valueToBooleanTruthy[fs:byte(i)] = true
			end
			valueToBooleanTruthy.on, valueToBooleanTruthy.enabled = true, true
		end
		cfTargetKey = newtable() do
			cfTargetKey[256*1] = "target"
			cfTargetKey[256*2] = "focus"
			cfTargetKey[256*3] = "pettarget"
			cfTargetKey[256*4] = true
			cfTargetKey[256*5] = false
		end
		cfTargetEffect = newtable() do
			cfTargetEffect[2^14*1] = "--clear"              -- CF_EARG_CLEAR
			cfTargetEffect[2^14*4] = "--last-target"        -- CF_EARG_LAST_ANY
			cfTargetEffect[2^14*5] = "--last-enemy-target"  -- CF_EARG_LAST_ENEMY
			cfTargetEffect[2^14*6] = "--last-friend-target" -- CF_EARG_LAST_FRIEND
		end
		for _, k in pairs(self:GetChildList(newtable())) do
			idle[k], numIdle = 1, numIdle + 1
			k:SetAttribute("type", "macro")
		end
		RW_ReleaseTransferToken = [==[-- RW_ReleaseTransferToken
			local m = transferTokens[#transferTokens]
			if m[3] ~= NIL then
				modLock, m[3] = m[3], NIL
			end
			reVars.args, m[5] = m[5]
		]==]
		RW_ReleaseExecQueue = [==[-- RW_ReleaseExecQueue
			local onlyTopMacro, r, m = ..., nil
			for i=#execQueue, 1, -1 do
				r, execQueue[i] = execQueue[i]
				m = r and r[4]
				if m == "TRANSFER_TOKEN" then
					transferTokens[#transferTokens+1] = r
					self:Run(RW_ReleaseTransferToken)
				elseif m == "UNSHIFT_RESTORE" then
					if PY and PY.nextOIndex then
						owner:Run(PY_EnqRun, nil, "unshift_restore")
					else
						self:CallMethod("manageUnshift", true)
					end
				elseif onlyTopMacro and r == MACRO_TOKEN then
					break
				end
			end
			if mutedAbove > #execQueue then
				if PY and PY.nextOIndex then
					owner:Run(PY_EnqRun, nil, "unmute")
				else
					self:CallMethod("setMute", false)
				end
				mutedAbove = - 1
			end
			self:SetAttribute("execPending", #execQueue)
		]==]
	]=])
	coreNamedMacroText = coreEnv.namedMacroText
	local cf = CreateFrame("Frame", nil, core, "SecureFrameTemplate")
	SecureHandlerWrapScript(cf, "OnAttributeChanged", core, [[-- Rewire_TickOAC
		if value ~= nil then
			return self:SetAttribute(name, nil)
		elseif name == "tick" then
			if #execQueue > 0 then
				owner:Run(RW_ReleaseExecQueue, false)
			end
			if PY and PY.pendingResolve then
				PY.pendingResolve, PY.nextOIndex = nil
			end
			owner:SetAttribute("PyrolysisRunID", nil)
			mutedAbove = -1
		end
	]])
	RegisterAttributeDriver(cf, "tick", "1")
end
core:SetAttribute("ResolveOptionsClauseValue", [==[-- Rewire:ResolveOptionsClauseValue
	local esc, v, resolveUnit, resolveVars, escapeMode, futureID = nil, ...
	esc = escapeMode ~= 2 and escapeMode ~= 3 and 1 or 0
	if v and resolveVars then
		local endP, esc, vn, cl, sp = 1 repeat
			sp, vn, cl, endP = endP, v:match("^%s*%%([a-zA-Z\128-\255][a-zA-Z0-9_\128-\255]*)(%S?)%s*()", endP)
			if not vn or cl ~= ":" and endP <= #v then
				v = sp == 1 and v or v:sub(sp)
				break
			elseif (reVars[vn] or "") ~= "" then
				esc, v = 0, reVars[vn]
				break
			elseif endP > #v then
				v = cl == ":" and "" or nil
				break
			end
		until nil
	end
	if resolveUnit then
		v = v and KR:RunAttribute("ResolveUnit", v:match("^%s*(.-)%s*$"), futureID)
	elseif (v or "") == "" or esc == (escapeMode and escapeMode % 2 or 0) then
		-- It's fine as is
	elseif esc == 0 then
		v = rtgsub(v, soEscapePattern, soLiteralToEscapeSeq)
	else
		v = rtgsub(v, "\\.", soEscapeSeqToLiteral)
	end
	return v
]==])
core:SetAttribute("RunSlashCmd", [=[-- Rewire:Internal_RunSlashCmd
	local slash, v, target, exArg = ...
	if not v then
	elseif slash == "/cast" or slash == "/use" then
		local vl = v:lower()
		local ac, av = 0, castAliases[vl]
		while av and ac < 10 do
			ac, v, vl = ac + 1, av, av:lower()
		end
		local oid = v and castEscapes[vl]
		local sid = v and not oid and v:match("^%s*!?%s*spell:(%d+)%s*$")
		if oid then
			return AB:RunAttribute("UseAction", oid, target)
		elseif sid and PY and PY.nextOIndex then
			local si, oi, lim, sz = PY.nextSIndex, PY.nextOIndex, PY.cFree
			sz = PY.execSL + (oi > 1 and 1 or 0)
			PY.qS[si], PY.nextSIndex = newtable("CAST", tonumber(sid), target), si + 1
			PY[oi], PY.nextOIndex, PY.cFree, PY.lOver = PY.execS, lim >= sz and oi + 1 or oi, PY.cFree - sz, PY.lOver + (lim < 0 and 1 or 0)
		elseif sid then
			return AB:RunAttribute("CastSpellByID", tonumber(sid), target)
		elseif v then
			local vn = tonumber(v)
			if vn and vn < 20 and vn > 0 then
				slash = "/use" -- /cast does not resolve inventory slots
			elseif exArg == "opt-into-cr-fallback" and (vn or v:match("^%s*[Ii][Tt][Ee][Mm]:%d")) then
				slash = "/castrandom"
			end
			slash = PY and PYshortName[slash] or slash
			return (target and (slash .. " [@" .. target .. "]") or (slash .. " ")) .. v
		end
	elseif slash == "/stopmacro" then
		owner:Run(RW_ReleaseExecQueue, true)
	elseif slash == "#mutenext" or slash == "#mute" then
		local breakOnCommand = slash == "#mutenext"
		for i=#execQueue,1,-1 do
			local m = execQueue[i]
			if m == MACRO_TOKEN or (breakOnCommand and m[4] == nil) then
				if i > 1 then i = i - 1 end
				if mutedAbove < 0 or i < mutedAbove then
					if mutedAbove >= 0 then
					elseif PY and PY.nextOIndex then
						owner:Run(PY_EnqRun, nil, "mute")
					else
						self:CallMethod("setMute", true)
					end
					mutedAbove = i
				end
				return
			end
		end
	elseif slash == "#unmute" and mutedAbove > -1 then
		for i=#execQueue,mutedAbove+1,-1 do
			if execQueue[i] == MACRO_TOKEN then
				return
			end
		end
		if PY and PY.nextOIndex then
			owner:Run(PY_EnqRun, nil, "unmute")
		else
			self:CallMethod("setMute", false)
		end
		mutedAbove = -1
	elseif slash == "#nounshift" then
		local breakOnCommand = v:lower() == "next"
		for i=#execQueue,1,-1 do
			local m = execQueue[i]
			if m == MACRO_TOKEN or (breakOnCommand and m[4] == nil) or i == 1 then
				table.insert(execQueue, i, newtable(nil, nil, nil, "UNSHIFT_RESTORE"))
				break
			end
		end
		if PY and PY.nextOIndex then
			owner:Run(PY_EnqRun, nil, "nounshift")
		else
			self:CallMethod("manageUnshift", false)
		end
	elseif slash == "#parse" then
		local m = execQueue[#execQueue]
		if m and m[2] and m[3] then
			execQueue[#execQueue] = nil
			local futureID = PY and PY.futureID or nil
			local parsed = KR:RunAttribute("EvaluateCmdOptions", m[3], modLock, futureID)
			parsed = parsed and self:RunAttribute("ResolveOptionsClauseValue", parsed, false, true, nil, futureID)
			if parsed then
				return m[2] .. " " .. parsed
			end
		end
	elseif slash == "/runmacro" then
		if macros[v] then
			return macros[v]:RunAttribute("RunNamedMacro", v)
		elseif namedMacroText[v] then
			return self:RunAttribute("RunMacro", namedMacroText[v])
		end
		print(('|cffffff00Macro %q is unknown.'):format(v))
	elseif slash == "/varset" then
		local vname, vnEnd = v:match("^%s*([a-zA-Z\128-\255][a-zA-Z0-9_\128-\255]*)()")
		if not vname then return end
		local val = v:match("^%s+(.-)%s*$", vnEnd)
		local futureID = PY and PY.futureID or nil
		val = val and self:RunAttribute("ResolveOptionsClauseValue", val, false, true, 2, futureID)
		reVars[vname] = val
	elseif slash then
		slash = commandAlias[slash] or slash
		local sn = PY and PYshortName[slash] or slash
		return (target and (sn .. " [@" .. target .. "]") or v ~= "" and (sn .. " ") or sn) .. v
	end
]=])
core:SetAttribute("RunMacro", [=[-- Rewire:RunMacro
	local m, macrotext, _transferButtonState, applyModLock, argVal = cache[...], ...
	if macrotext and PY and PY.pendingResolve then
		owner:CallMethod("NotNowError")
		return ""
	elseif macrotext and not m then
		m = newtable()
		for line in macrotext:gmatch("[^\n\r]+") do
			local meta, head, rest = nil, line:match("^(%S+)%s*(.-)%s*$")
			if head then
				head = head:lower()
				meta = head:match("^#(.*)") or head:sub(1,1) == '-' or head:sub(1,2) == '//' or nil
			end
			if meta == nil or metaCommands[meta] then
				m[#m+1] = newtable(line, head, rest, meta, head and head:match("^(/!)%S"))
			end
		end
		cache[macrotext] = m
	end

	if m and #m > 0 and not overfull then
		if #execQueue > QUEUE_LIMIT then
			overfull = true, owner:CallMethod("throw", "Rewire execution queue overfull; ignoring subsequent commands.")
		else
			local ni = #execQueue+1
			local nbs = nil
			local nml = (applyModLock == true and KR:GetAttribute("cndLock") or type(applyModLock) == "string" and applyModLock) or nil
			nml = nml and nml ~= modLock and nml
			local nt = #transferTokens
			local tt = nt > 0 and transferTokens[nt] or newtable(nil, nil, NIL, "TRANSFER_TOKEN")
			execQueue[ni], ni, transferTokens[nt] = tt, ni + 1
			modLock, tt[3], tt[5] = nml or modLock, modLock, reVars.args
			execQueue[ni], ni, reVars.args = MACRO_TOKEN, ni + 1, argVal
			for i=#m, 1, -1 do
				execQueue[ni], ni = m[i], ni + 1
			end
		end
	end

	local futureID, nextLine, pyTop = "rwpyrex"
	if PY and not PY.nextOIndex then
		pyTop, PY.nextOIndex, PY.nextIIndex, PY.nextSIndex, PY.id = 1, 1, 1, 1, (PY.id or 0) % 2^30 + 1
		PY.cFree, PY.lOver, PY.runSIndex, PY.dm, PY.futureID = 255, 0, nil, PY.dangerMode, futureID
		if PY.dm and commandAliasChanged then
			for k in pairs(PYdangerCommands) do
				PYdangerCommands[k] = nil
			end
			PYdangerCommands[commandAlias["/run"] or "/run"] = "/run"
			PYdangerCommands[commandAlias["/dump"] or "/dump"] = "/dump"
			PYdangerCommands[commandAlias["/tinspect"] or "/tinspect"] = "/tinspect"
			commandAliasChanged = nil
		end
		self:SetAttribute("PyrolysisRunID", PY.id)
		KR:RunAttribute("StartFuture", futureID)
	end
	repeat
		if ns < #execQueue and numIdle > 0 and not PY then
			local m = "\n/click " .. next(idle):GetName() .. " x 1"
			local n = math.min(math.floor(1000/#m), math.ceil(#execQueue*1.25 + numActive*1.3^numActive))
			ns = ns + n
			self:SetAttribute("execPending", #execQueue)
			return m:rep(n)
		end
		local i, m, t, k, v, ct = #execQueue
		repeat
			m, i, execQueue[i] = execQueue[i], i-1
		until i < 1 or m ~= MACRO_TOKEN
		if mutedAbove > 0 and mutedAbove > i then
			owner:RunAttribute("RunSlashCmd", "#unmute")
		end
		self:SetAttribute("execPending", #execQueue)
		if not m then
			overfull, nextLine = false, ""
			break
		end
		local ocmd, meta = m[2], m[4]
		k, v = commandAlias[ocmd] or ocmd, m[3]
		local isMacroExt = m[5] and commandFlags[k] == nil
		local scmd = PY and (PYshortName[k] or k) or ocmd
		ct = commandFlags[k] or isMacroExt and 1 or 0
		if isMacroExt and not reMacroExt[k] then
			v = nil -- do not emit undeclared/inactive macro extensions
		elseif ct % 2 > 0 then --# block:command_parse
			if v == "" then
				v, t = "", nil
			else
				v, t = KR:RunAttribute("EvaluateCmdOptions", v, modLock, futureID)
			end
			if v then
				local cvf, ctf, cef, caf = ct % 2^8, ct % 2^11, ct % 2^14, ct % 2^18
				cvf, ctf, cef, caf = cvf - ct % 2^5, ctf - cvf, cef - ctf, caf - cef
				local tarKeyUnit, needValueResolve = cfTargetKey[ctf], true
				if tarKeyUnit then
					v, t = t ~= tarKeyUnit and t or v, nil
				elseif tarKeyUnit == false then
					t = nil
				end
				if cvf == 2^5*1 then
					v, needValueResolve = "", false
				elseif cvf == 2^5*2 then
					v, needValueResolve = v ~= "" and v or nil, v ~= ""
				elseif cvf == 2^5*3 then
					v, needValueResolve = (valueToBooleanTruthy[v:byte(1)] or valueToBooleanTruthy[v:lower()]) and "1" or "0", false
				end
				if needValueResolve and v then
					v = self:RunAttribute("ResolveOptionsClauseValue", v, ct % 32 >= 16, true)
				end
				if v and cef >= 2^11*1 and cef < 2^11*3 then
					local setUnit, toUnit = cef < 2^11*2 and "target" or "focus", cfTargetEffect[caf]
					if toUnit ~= nil then
					elseif caf == 2^14*2 then -- CF_EARG_SET_VALUE
						toUnit = v
					elseif caf == 2^14*3 then -- CF_EARG_ASSIST_VALUE
						toUnit = v .. "-target"
					end
					if toUnit then
						KR:RunAttribute("SetFutureUnit", futureID, setUnit, toUnit)
					end
				end
			end --# end:command_parse
			if v and t then
				nextLine = scmd .. " [@" .. t .. "]" .. v
			else
				nextLine = v and (v ~= "" and scmd .. " " .. v or scmd) or nil
			end
		elseif meta == "TRANSFER_TOKEN" then
			transferTokens[#transferTokens+1], nextLine = m
			self:Run(RW_ReleaseTransferToken)
		elseif meta == "UNSHIFT_RESTORE" then
			self:CallMethod("manageUnshift", true)
		else
			nextLine = m[1]
		end
		local pyNotify, pyNotifyArg
		if commandHandler[k] then
			-- NB: call Rewire::RunMacro instead of returning non-trivial macrotext from RunSlashCmd
			nextLine, pyNotify, pyNotifyArg = commandHandler[k]:RunAttribute("RunSlashCmd", k, v, t)
			pyNotify = PY and pyNotify == "notified-click"
		elseif isMacroExt and v then
			nextLine = self:RunAttribute("RunMacro", reMacroExt[k], nil, nil, v)
		end
		if pyNotify then
			local si, oi, lim, sz = PY.nextSIndex, PY.nextOIndex, PY.cFree
			sz = PY.execSL + (oi > 1 and 1 or 0)
			PY.qS[si], PY.nextSIndex = newtable("CLICK", commandHandler[k], m[2], pyNotifyArg), si + 1
			PY[oi], PY.nextOIndex, PY.cFree, PY.lOver = PY.execS, lim >= sz and oi + 1 or oi, PY.cFree - sz, PY.lOver + (lim < 0 and 1 or 0)
			nextLine = ""
		elseif PY and (nextLine or "") ~= "" then
			local ck, cf = (commandHandler[k] or isMacroExt) and nextLine:match("^\n*(/%S+)")
			ck = ck and ck:lower()
			cf = ct ~= 0 and commandFlags[commandAlias[ck] or ck] or ct or 0
			local canEnq = (cf == 0 or cf % 2^19 >= 2^18) and (PY.chatUnlocked or cf % 2^22 < 2^21 and ck)
			if canEnq then
				nextLine = "", self:Run(PY_EnqRun, nextLine)
			else
				local oi, lim, sz = PY.nextOIndex, PY.cFree
				sz = #nextLine:gsub("[\128-\191]+", "") + (oi > 1 and 1 or 0)
				PY[oi], PY.nextOIndex, PY.cFree, PY.lOver = nextLine, lim >= sz and oi + 1 or oi, lim - sz, PY.lOver + (lim < 0 and 1 or 0)
				nextLine = ""
			end
		end
	until (nextLine or "") ~= "" or #execQueue == 0
	if pyTop then
		owner:Run(RW_ReleaseExecQueue)
		local m, n = PY[1], PY.nextOIndex - 1
		for i=2, n do
			m = m .. "\n" .. PY[i]
		end
		if PY.cFree < 0 then
			owner:CallMethod("LongMacroError", -PY.cFree, PY.lOver+1)
		end
		PY.pendingResolve, PY.runSIndex, PY.nextOIndex, PY.cFree, PY.lOver, PY.futureID = n > 0 and PY.id or nil, nil
		self:SetAttribute("PyrolysisRunID", nil)
		KR:RunAttribute("ReleaseFuture", futureID)
		return n > 0 and m or "", PY.pendingResolve
	end
	return nextLine or ""
]=])
core:SetAttribute("SetNamedMacroHandler", [=[-- Rewire:SetNamedMacroHandler
	local handlerFrame, name, skipNotifyAB = self:GetFrameRef("SetNamedMacroHandler-handlerFrame"), ...
	local om, nm = macros[name], handlerFrame or (namedMacroText[name] and false)
	if type(name) == "string" and om ~= nm then
		macros[name] = nm
		self:CallMethod("clearNamedMacroHinter", name, skipNotifyAB or (om == nil) == (nm == nil))
	end
	self:SetAttribute("frameref-SetNamedMacroHandler-handlerFrame", nil)
]=])
core:SetAttribute("SetMacroExtensionCommand", [=[-- Rewire:SetMacroExtensionCommand
	local cname, remacrotext, owner = ...
	cname = type(cname) == "string" and cname:lower()
	if not (cname or ""):match("^%S+$") or remacrotext ~= nil and type(remacrotext) ~= "string" or type(owner) ~= "string" then
		return self:CallMethod("throw", 'Syntax: SetMacroExtensionCommand("commandName", "remacrotext" or nil)')
	elseif remacrotext == nil and reMacroExtOwner[cname] ~= owner then
		return
	end
	reMacroExt["/!" .. cname], reMacroExtOwner[cname] = remacrotext ~= "" and remacrotext or nil, remacrotext and owner
]=])
function core:LongMacroError(overChars, overLines)
	local msg = "Executed macro was too long: %d |4command:commands; (%d |4character:characters;) over limit."
	print("|cffffff00" .. msg:format(tonumber(overLines) or -1, tonumber(overChars) or -1))
end
function core.NotNowError()
	print("|cffffff00blz: cannot run more macro commands now")
end
function core:throw(err)
	return error(err, 2)
end
function core:clearNamedMacroHinter(name, skipNotifyAB)
	namedMacros[name] = nil
	if skipNotifyAB ~= true then
		AB:NotifyObservers("macro")
	end
end
do -- core:setMute(mute)
	local f, oSFX, oES, oUEM = CreateFrame("Frame")
	local muteArmed, muteReqState = false, false
	function core:setMute(mute)
		local arm, disarm = mute and not muteArmed, not mute
		if arm then
			oSFX, oES = GetCVar("Sound_EnableSFX"), GetCVar("Sound_EnableErrorSpeech")
			UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
			oUEM = true
		elseif oUEM and disarm then
			UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
		end
		if arm or disarm then
			SetCVar("Sound_EnableSFX", mute and 0 or oSFX)
			SetCVar("Sound_EnableErrorSpeech", mute and 0 or oES)
		elseif muteArmed and not mute then
			SetCVar("Sound_EnableSFX", oSFX)
			SetCVar("Sound_EnableErrorSpeech", oES)
		end
		muteReqState, muteArmed = mute, arm or muteArmed and not disarm
		f:SetShown(muteArmed)
	end
	f:SetScript("OnUpdate", function()
		local ost = muteReqState
		core:setMute(false)
		if ost then
			error("Muted state persisted after macro execution")
		end
	end)
	coreExecCleanup[#coreExecCleanup + 1] = function()
		if muteArmed then
			core:setMute(false)
		end
	end
	f:Hide()
end
do -- core:manageUnshift(isRestore)
	local isModified, origValue, modDepth = false, nil, 0
	local cleanupArmed = false
	local function cleanup()
		cleanupArmed = false
		if isModified then
			SetCVar("autoUnshift", origValue)
			isModified, modDepth = false, 0
			securecall(error, "RW unshift cleanup panic")
		end
		return "remove"
	end
	function core:manageUnshift(isRestore)
		if isRestore then
			if modDepth > 0 then
				modDepth = modDepth - 1
				if modDepth <= 0 then
					SetCVar("autoUnshift", origValue)
					isModified = false
				end
			end
		else
			if not isModified then
				origValue = GetCVar("autoUnshift")
				SetCVar("autoUnshift", 0)
			end
			isModified, modDepth = true, modDepth > 0 and modDepth + 1 or 1
			if not cleanupArmed then
				EV.After(0, cleanup)
				cleanupArmed = true
			end
		end
	end
	coreExecCleanup[#coreExecCleanup + 1] = function()
		if cleanupArmed and isModified then
			modDepth = 1
			core:manageUnshift(true)
		end
	end
end

local function setCommandType(slash, ctype, handler)
	local PY = coreEnvW.PY
	coreEnvW.commandFlags[slash], coreEnvW.commandHandler[slash] = ctype, handler
	if handler and PY and PY.delegateButton[handler] == nil then
		local oid = PY.freeDelegateID
		local hid = "p" .. oid
		PY.delegateButton[handler], PY.freeDelegateID = hid, oid + 1
		PYROLYSIS:RegisterSlashCmdDelegate(handler, hid)
	end
end
local function getAliases(p, i)
	local v = _G[p .. i]
	if v then
		return v, getAliases(p, i + 1)
	end
end

local setCommandHinter, getMacroHint, getCommandHint, getCommandHintRaw, getSpeculationID, metaFilters, metaFilterTypes,
	reVarsSP, resolveOptionsClauseValue
do
	local hintFunc, pri, cache, ht, ht2, cDepth = {}, {}, {}, {}, {}, 0
	local DEPTH_LIMIT, UNKNOWN_PRIORITY, nInf = 20, -2 ^ 52, -math.huge
	local speculationID, nextSpeculationID, SPECULATION_ID_WRAP = nil, 221125, 2 ^ 53
	local store
	do
		local function write(t, n, i, a, b, c, d, ...)
			if n > 0 then
				t[i], t[i + 1], t[i + 2], t[i + 3] = a, b, c, d
				return write(t, n - 4, i + 4, ...)
			end
		end
		function store(ok, ...)
			if ok then
				local n = select("#", ...)
				write(ht2, n + 1, 0, n, ...)
			end
			return ok
		end
	end
	metaFilters, metaFilterTypes = {}, {}
	do
		local function fillToSize(sz, stopFillAt)
			if ht[0] < sz then
				for i = ht[0] + 1, stopFillAt do
					ht[i] = nil
				end
				ht[0] = sz
			end
			return true
		end
		local function setIcon(icon, isAtlas, _si)
			ht[3], _si = icon, 2
			if isAtlas == true or isAtlas == false then
				local st = ht[0] >= 2 and ht[2]
				st = st and type(st) == "number" and st or 0
				if isAtlas ~= (st % 524288 >= 262144) then
					ht[2], _si = isAtlas and (st + 262144) or (st - 262144), 1
				end
			end
			return fillToSize(3, _si)
		end
		function metaFilterTypes:replaceIcon(...)
			local doReplace, icon, isAtlas = self(...)
			if doReplace then
				return setIcon(icon, isAtlas)
			end
		end
		function metaFilterTypes:replaceIconB(...)
			local doReplace, usable, icon, isAtlas = self(ht[3], ...)
			if doReplace then
				if usable == true or usable == false or ht[0] == 0 or ht[1] == nil then
					ht[0], ht[1] = ht[0] > 1 and ht[0] or 1, usable ~= false
				end
				return setIcon(icon, isAtlas)
			end
		end
		function metaFilterTypes:replaceTooltip(...)
			local doReplace, tipFunc, tipArg = self(...)
			if doReplace then
				ht[8], ht[9] = tipFunc, tipArg
				return fillToSize(9, 7)
			end
		end
		function metaFilterTypes:replaceCooldown(...)
			local doReplace, cdLeft, cdLength = self(...)
			if doReplace then
				ht[6], ht[7] = cdLeft, cdLength
				return fillToSize(7, 5)
			end
		end
		function metaFilterTypes:replaceCount(...)
			local doReplace, count = self(...)
			if doReplace then
				local st = ht[0] >= 2 and ht[2]
				st = st and type(st) == "number" and st or 0
				st = st % 2097152 < 1048576 and st + 1048576 or st
				ht[2], ht[5] = st, count
				return fillToSize(5, 4)
			end
		end
		function metaFilterTypes:replaceLabel(...)
			local doReplace, stext = self(...)
			if doReplace then
				ht[11] = stext
				return fillToSize(11, 10)
			end
		end
		function metaFilterTypes:macroFallback(...)
			local doReplace, usable, icon, label = self(...)
			if doReplace then
				local d, hl = false, ht[0]
				if label and (hl < 11 or ht[11] == nil) then
					ht[11], d = label, d or fillToSize(11, 10)
				end
				if label and (hl < 4 or ht[4] == nil) then
					ht[4], d = label, d or fillToSize(4, 3)
				end
				if icon and (doReplace == 2 or hl < 3 or not ht[3]) then
					ht[3], d = icon, d or fillToSize(3, 2)
				end
				if usable == true and (ht[1] == nil or hl < 1) then
					ht[1], ht[2], d = true, 0, d or fillToSize(2, 0)
				end
				return d
			end
		end
		function metaFilterTypes:replaceHint(...)
			if store(self(...)) then
				ht, ht2 = ht2, ht
				return true
			end
		end
	end
	function getCommandHintRaw(hslash, ...)
		local hf = hintFunc[hslash]
		if not hf then
			return false
		end
		return hf(...)
	end
	local function clearDepth(...)
		KR:ClearFuture(speculationID)
		cDepth, speculationID = 0, nil
		return ...
	end
	local function prepCall(...)
		if cDepth ~= 0 then
			error("invalid state")
		end
		cDepth, speculationID, nextSpeculationID = 1, nextSpeculationID, nextSpeculationID ~= SPECULATION_ID_WRAP and
			nextSpeculationID + 1 or -nextSpeculationID
		KR:ClearFuture(speculationID)
		return clearDepth(securecall(...))
	end
	reVarsSP = {}
	do
		local specVarVal, specVarID = {}, {}
		local function vp__index(_, k)
			if speculationID and specVarID[k] == speculationID then
				return specVarVal[k]
			end
			return coreEnv.reVars[k]
		end
		local function vp__newindex(_, k, v)
			specVarVal[k], specVarID[k] = v ~= nil and tostring(v) or v, speculationID
		end
		setmetatable(reVarsSP, {
			__index = vp__index,
			__newindex = vp__newindex
		})
	end
	local parseCommandOptions
	do -- resolveOptionsClauseValue(v, resolveUnits, resolveVars) / parseCommandOptions
		local sKR, sRW = {}, {}
		local function sRunAttribute(h, a, ...)
			if h == sRW and a == "ResolveOptionsClauseValue" then
				return resolveOptionsClauseValue(...)
			elseif h ~= sKR then
			elseif a == "ResolveUnit" then
				return KR:ResolveUnit(...)
			elseif a == "EvaluateCmdOptions" then
				return KR:EvaluateCmdOptions(...)
			elseif a == "SetFutureUnit" then
				return KR:SetFutureUnit(...)
			end
			error('Invalid s' .. (h == sRW and 'RW' or h == sKR and 'KR' or '') .. ':RunAttribute("' .. tostring(a) ..
					  '")')
		end
		sKR.RunAttribute, sRW.RunAttribute = sRunAttribute, sRunAttribute
		local env = setmetatable({
			rtgsub = string.rtgsub,
			reVars = reVarsSP,
			KR = sKR,
			self = sRW
		}, {
			__index = coreEnv
		})
		resolveOptionsClauseValue = setfenv(loadstring(
			("-- shadowRW:ResolveOptionsClauseValue\nreturn function(...)\n%s\nend"):format(core:GetAttribute(
				"ResolveOptionsClauseValue")))(), env)
		parseCommandOptions = setfenv(loadstring(
			("-- shadowRW:ParseCommandOptions\nreturn function(ct, v, modLock, futureID)\nlocal t\n%s\n return v, t end"):format(
				core:GetAttribute("RunMacro"):match("%-%-# block:command_parse%s*\n(.-)%s*%-%-# end:command_parse%s")))(),
			env)
	end
	local function applyBias(pri, def, bias)
		return bias == nInf and nInf or ((pri ~= true and pri or def or UNKNOWN_PRIORITY) + (bias or 0))
	end
	function getCommandHint(minPriority, slash, args, modState, otarget, msg, priBias)
		-- Two ways to get here:
		-- 1. RW:GetCommandAction calls with minPriority/priBias = nil, but supplies otarget/msg
		-- 2. getMacroHint calls supplying minPriority and priBias, but otarget/msg == nil
		slash = coreEnv.commandAlias[slash] or slash
		local hf, pri, args2, target = hintFunc[slash], pri[slash]
		local reText = hf == nil and coreEnv.reMacroExt[slash]
		local ctype = (coreEnv.commandFlags[slash] or reText and 1 or 0)
		local minPriorityA = priBias ~= nInf and ((minPriority or nInf) - (priBias or 0)) or -nInf
		if hf and pri > minPriorityA or reText or (ctype > 0 and (ctype < 2 ^ 22 or ctype % 2 ^ 23 < 2 ^ 22)) then
			if cDepth == 0 then
				return prepCall(getCommandHint, minPriority, slash, args, modState, otarget, msg, priBias)
			elseif cDepth > DEPTH_LIMIT then
				return false
			elseif hf and otarget ~= nil then
				args, args2, target = nil, args, otarget
			else
				args2, target = parseCommandOptions(ctype, args, modState, speculationID)
				if not args2 then
					return -- no option clause applies, not executed
				end
				if reText then
					local res = store(getMacroHint(reText, modState, minPriorityA, args2))
					if minPriority then
						return res, applyBias(res, UNKNOWN_PRIORITY, priBias)
					end
					return res, unpack(ht2, 1, res and ht2[0] or 0)
				elseif not hf or pri <= minPriorityA then
					return -- no custom hint (pCO may have side effects)
				end
			end
			cDepth = cDepth + 1
			local res = store(securecall(hf, slash, args, args2, target, modState, minPriorityA, msg, speculationID))
			cDepth = cDepth - 1
			if res == "stop" then
				return res, pri
			elseif minPriority then
				return res, applyBias(res, pri, priBias)
			elseif res then
				return res, unpack(ht2, 1, ht2[0])
			end
		elseif not pri then
			return false
		end
	end
	function getMacroHint(macrotext, modState, minPriority, argsVar)
		if not macrotext then
			return
		end
		if cDepth == 0 then
			return prepCall(getMacroHint, macrotext, modState, minPriority)
		end
		local m, lowPri = cache[macrotext], minPriority or nInf
		if not m then
			m = {}
			for line in macrotext:gmatch("%S[^\n\r]*") do
				local slash, args = line:match("^(%S+)%s*(.-)%s*$")
				slash = slash:lower()
				local meta, meta4 = slash:match("^#((.?.?.?.?).*)")
				if meta4 == "show" and args ~= "" then
					m[-1], m[0] = "/use", args
				elseif meta == nil or meta == "skip" or meta == "important" then
					m[#m + 1], m[#m + 2] = slash, args
				else
					if m.metaKeys == nil then
						m.metaKeys, m.metaArgs = {}, {}
					end
					local idx = #m.metaKeys + 1
					m.metaKeys[idx], m.metaArgs[idx] = meta, args
				end
			end
			cache[macrotext] = m
		end

		local bestPri, bias, oldArgsVar, haveUnknown = lowPri, m[-1] and 1000 or 0, reVarsSP.args
		reVarsSP.args = argsVar
		for i = m[-1] and -1 or 1, #m, 2 do
			local cmd, args = m[i], m[i + 1]
			if cmd == "#skip" or cmd == "#important" then
				local v = args == "" or KR:EvaluateCmdOptions(args, modState)
				if v ~= nil then
					v = tonumber(v)
					bias = cmd == "#skip" and (v and -v or nInf) or (v or 1000)
				end
			else
				local res, pri = getCommandHint(bestPri, cmd, args, modState, nil, nil, bias)
				if res == "stop" then
					break
				elseif res and pri > bestPri then
					bestPri, ht, ht2 = pri, ht2, ht
				elseif res == false and i > 0 then
					haveUnknown = true
				end
				bias = 0
			end
		end
		local mk, mv = m.metaKeys
		if (bestPri <= lowPri) and (haveUnknown or mk) then
			store(true, nil, 0, nil, "", 0, 0, 0)
			ht, ht2 = ht2, ht
		end
		for i = 1, mk and #mk or 0 do
			local k = mk[i]
			local fi = metaFilters[k]
			if fi then
				mv = mv or m.metaArgs
				local filterRun, parseConditional, filterFunc, filterType = fi[1], fi[2], fi[3], fi[4]
				local v, vt = mv[i], nil
				local ic = filterType == "replaceIconB" and ht[0] >= 3 and ht[3]
				if filterType == "replaceIconB" and ic and ic ~= 134400 and
					(type(ic) ~= "string" or not ic:lower():find("inv_misc_questionmark", 1, true)) then
					v = nil
				elseif parseConditional then
					v, vt = KR:EvaluateCmdOptions(v, modState)
					v = v and resolveOptionsClauseValue(v, false, true)
				end
				if v and securecall(filterRun, filterFunc, k, v, vt) then
					haveUnknown = true
				end
			end
		end
		reVarsSP.args = oldArgsVar

		if bestPri > lowPri or haveUnknown then
			if minPriority then
				if haveUnknown and bestPri == nInf then
					bestPri = UNKNOWN_PRIORITY - cDepth
				end
				return bestPri > lowPri and bestPri or false, unpack(ht, 1, ht[0])
			else
				return unpack(ht, 1, ht[0])
			end
		end
	end
	function setCommandHinter(slash, priority, hint)
		hintFunc[slash], pri[slash] = hint, hint and priority
	end
	function getSpeculationID()
		return speculationID
	end
end

local getCommandKeyFlags
do
	local CF_SECURE_OPTIONS = 2 ^ 0
	local CF_RESOLVE_VAR_VAL = 2 ^ 1 -- requires %variable resolution prior to invocation
	local CF_COMMA_LIST_VAL = 2 ^ 2 -- /castrandom value rules
	local CF_CSEQUENCE_VAL = 2 ^ 3 -- /castsequence value rules
	local CF_RESOLVE_UNIT_VAL = 2 ^ 4 -- resolve virtual units in clause values
	local CF_IGNORES_VAL = 2 ^ 5 * 1 -- value is ignored
	local CF_NOBLANK_VAL = 2 ^ 5 * 2 -- blank values are noops
	local CF_BOOLEAN_VAL = 2 ^ 5 * 3 -- ValueToBoolean'd values
	local CF_TARVAL_NOT_TARGET = 2 ^ 8 * 1 -- target, if specified and not "target", overrides value
	local CF_TARVAL_NOT_FOCUS = 2 ^ 8 * 2 -- target, if specified and not "focus", overrides value
	local CF_TARVAL_NOT_PETTARGET = 2 ^ 8 * 3 -- target, if specified and not "pettarget", overrides value
	local CF_TARVAL_ANY = 2 ^ 8 * 4 -- target, if specified, overrides value
	local CF_IGNORES_TARGET = 2 ^ 8 * 5 -- target is ignored
	local CF_EFFECT_TARGET = 2 ^ 11 * 1 -- command affects target
	local CF_EFFECT_FOCUS = 2 ^ 11 * 2 -- command affects focus
	local CF_EFFECT_CAST_USE = 2 ^ 11 * 3
	local CF_EFFECT_USE_CAST = 2 ^ 11 * 4
	local CF_EFFECT_EQUIP = 2 ^ 11 * 5
	local CF_EARG_CLEAR = 2 ^ 14 * 1 -- new unit is "none" (/cleartarget)
	local CF_EARG_SET_VALUE = 2 ^ 14 * 2 -- new unit is specified by options (/target)
	local CF_EARG_ASSIST_VALUE = 2 ^ 14 * 3 -- new unit is option-value-target (/assist)
	local CF_EARG_LAST_ANY = 2 ^ 14 * 4 -- pop from history (i.e. /targetlasttarget)
	local CF_EARG_LAST_ENEMY = 2 ^ 14 * 5 -- pop last hostile
	local CF_EARG_LAST_FRIEND = 2 ^ 14 * 6 -- pop last friendly
	local CF_INSECURE = 2 ^ 18 -- execute insecurely
	local CF_PERFECTLY_ORDINARY = 2 ^ 19 -- PH: keyFlags == 0 is special; this avoids that
	local CF_PREAPPLIED_BASE = 2 ^ 20 -- PH: threshold: don't apply CF_SECURE_BASE
	local CF_CHAT_LOCKDOWN = 2 ^ 21 -- chat lockdown applies
	local CF_FEEDBACK_BLACKBOX = 2 ^ 22 -- PH: don't base feedback solely on flag presence
	local CF_SECURE_BASE = CF_SECURE_OPTIONS + CF_RESOLVE_VAR_VAL
	local CF_CHAT_MESSAGE = CF_INSECURE + CF_PREAPPLIED_BASE + CF_CHAT_LOCKDOWN + CF_FEEDBACK_BLACKBOX
	local keyFlags = {
		STARTATTACK = CF_RESOLVE_UNIT_VAL + CF_TARVAL_NOT_TARGET,
		STOPATTACK = CF_IGNORES_VAL + CF_IGNORES_TARGET,
		CAST = CF_NOBLANK_VAL + CF_EFFECT_CAST_USE,
		USE = CF_NOBLANK_VAL + CF_EFFECT_USE_CAST,
		CASTRANDOM = CF_NOBLANK_VAL + CF_COMMA_LIST_VAL + CF_EFFECT_CAST_USE,
		USERANDOM = CF_NOBLANK_VAL + CF_COMMA_LIST_VAL + CF_EFFECT_CAST_USE,
		CASTSEQUENCE = CF_NOBLANK_VAL + CF_CSEQUENCE_VAL,
		STOPCASTING = CF_IGNORES_VAL + CF_IGNORES_TARGET,
		STOPSPELLTARGET = CF_IGNORES_VAL + CF_IGNORES_TARGET,
		CANCELAURA = CF_IGNORES_TARGET,
		CANCELFORM = CF_IGNORES_VAL + CF_IGNORES_TARGET,
		EQUIP = CF_IGNORES_TARGET + CF_EFFECT_EQUIP,
		EQUIP_TO_SLOT = CF_IGNORES_TARGET + CF_EFFECT_EQUIP,
		CHANGEACTIONBAR = CF_IGNORES_TARGET,
		SWAPACTIONBAR = CF_IGNORES_TARGET,
		TARGET = CF_RESOLVE_UNIT_VAL + CF_TARVAL_NOT_TARGET + CF_EFFECT_TARGET + CF_EARG_SET_VALUE,
		TARGET_EXACT = CF_RESOLVE_UNIT_VAL + CF_TARVAL_NOT_TARGET + CF_EFFECT_TARGET + CF_EARG_SET_VALUE,
		TARGET_NEAREST_ENEMY = CF_BOOLEAN_VAL + CF_IGNORES_TARGET + CF_EFFECT_TARGET + CF_EARG_SET_VALUE,
		TARGET_NEAREST_ENEMY_PLAYER = CF_BOOLEAN_VAL + CF_IGNORES_TARGET + CF_EFFECT_TARGET + CF_EARG_SET_VALUE,
		TARGET_NEAREST_FRIEND = CF_BOOLEAN_VAL + CF_IGNORES_TARGET + CF_EFFECT_TARGET + CF_EARG_SET_VALUE,
		TARGET_NEAREST_FRIEND_PLAYER = CF_BOOLEAN_VAL + CF_IGNORES_TARGET + CF_EFFECT_TARGET + CF_EARG_SET_VALUE,
		TARGET_NEAREST_PARTY = CF_BOOLEAN_VAL + CF_IGNORES_TARGET + CF_EFFECT_TARGET + CF_EARG_SET_VALUE,
		TARGET_NEAREST_RAID = CF_BOOLEAN_VAL + CF_IGNORES_TARGET + CF_EFFECT_TARGET + CF_EARG_SET_VALUE,
		CLEARTARGET = CF_IGNORES_VAL + CF_IGNORES_TARGET + CF_EFFECT_TARGET + CF_EARG_CLEAR,
		TARGET_LAST_TARGET = CF_IGNORES_VAL + CF_IGNORES_TARGET + CF_EFFECT_TARGET + CF_EARG_LAST_ANY,
		TARGET_LAST_ENEMY = CF_IGNORES_VAL + CF_IGNORES_TARGET + CF_EFFECT_TARGET + CF_EARG_LAST_ENEMY,
		TARGET_LAST_FRIEND = CF_IGNORES_VAL + CF_IGNORES_TARGET + CF_EFFECT_TARGET + CF_EARG_LAST_FRIEND,
		ASSIST = CF_RESOLVE_UNIT_VAL + CF_TARVAL_ANY + CF_EFFECT_TARGET + CF_EARG_ASSIST_VALUE,
		FOCUS = CF_RESOLVE_UNIT_VAL + CF_TARVAL_NOT_FOCUS + CF_EFFECT_FOCUS + CF_EARG_SET_VALUE,
		CLEARFOCUS = CF_IGNORES_VAL + CF_IGNORES_TARGET + CF_EFFECT_FOCUS + CF_EARG_CLEAR,
		MAINTANKON = CF_RESOLVE_UNIT_VAL + CF_TARVAL_ANY, -- defaults to target, though?
		MAINTANKOFF = CF_RESOLVE_UNIT_VAL + CF_TARVAL_ANY, -- defaults to target, though?
		MAINASSISTON = CF_RESOLVE_UNIT_VAL + CF_TARVAL_ANY, -- defaults to target, though?
		MAINASSISTOFF = CF_RESOLVE_UNIT_VAL + CF_TARVAL_ANY, -- defaults to target, though?
		DUEL = CF_RESOLVE_UNIT_VAL + CF_IGNORES_TARGET,
		DUEL_CANCEL = CF_PREAPPLIED_BASE,
		PET_ATTACK = CF_RESOLVE_UNIT_VAL + CF_TARVAL_NOT_PETTARGET,
		PET_FOLLOW = CF_IGNORES_VAL + CF_IGNORES_TARGET,
		PET_MOVE_TO = CF_IGNORES_VAL,
		PET_STAY = CF_IGNORES_VAL + CF_IGNORES_TARGET,
		PET_PASSIVE = CF_IGNORES_VAL + CF_IGNORES_TARGET,
		PET_DEFENSIVE = CF_IGNORES_VAL + CF_IGNORES_TARGET,
		PET_DEFENSIVEASSIST = CF_IGNORES_VAL + CF_IGNORES_TARGET,
		PET_AGGRESSIVE = CF_IGNORES_VAL + CF_IGNORES_TARGET,
		PET_ASSIST = CF_IGNORES_VAL + CF_IGNORES_TARGET,
		PET_AUTOCASTON = CF_IGNORES_TARGET,
		PET_AUTOCASTOFF = CF_IGNORES_TARGET,
		PET_AUTOCASTTOGGLE = CF_IGNORES_TARGET,
		STOPMACRO = CF_IGNORES_VAL + CF_IGNORES_TARGET,
		CANCELQUEUEDSPELL = CF_IGNORES_VAL + CF_IGNORES_TARGET,
		CLICK = CF_IGNORES_TARGET,
		EQUIP_SET = CF_IGNORES_TARGET,
		WORLD_MARKER = CF_PERFECTLY_ORDINARY,
		CLEAR_WORLD_MARKER = CF_IGNORES_TARGET,
		SUMMON_BATTLE_PET = CF_IGNORES_TARGET,
		RANDOMPET = CF_IGNORES_VAL + CF_IGNORES_TARGET,
		RANDOMFAVORITEPET = CF_IGNORES_VAL + CF_IGNORES_TARGET,
		DISMISSBATTLEPET = CF_IGNORES_VAL + CF_IGNORES_TARGET,
		PET_DISMISS = CF_PREAPPLIED_BASE,
		USE_TOY = CF_IGNORES_TARGET,
		LOGOUT = CF_PREAPPLIED_BASE,
		QUIT = CF_PREAPPLIED_BASE,
		GUILD_UNINVITE = CF_PREAPPLIED_BASE,
		GUILD_PROMOTE = CF_PREAPPLIED_BASE,
		GUILD_DEMOTE = CF_PREAPPLIED_BASE,
		GUILD_LEADER = CF_PREAPPLIED_BASE,
		GUILD_LEAVE = CF_PREAPPLIED_BASE,
		GUILD_DISBAND = CF_PREAPPLIED_BASE,
		PING = CF_PERFECTLY_ORDINARY, -- (quirk'd)
		DISMOUNT = CF_IGNORES_VAL + CF_IGNORES_TARGET + CF_INSECURE,
		LEAVEVEHICLE = CF_IGNORES_VAL + CF_IGNORES_TARGET + CF_INSECURE,
		SET_TITLE = CF_IGNORES_TARGET + CF_INSECURE,
		USE_TALENT_SPEC = CF_IGNORES_TARGET + CF_INSECURE,
		TARGET_MARKER = CF_INSECURE,
		SCRIPT = CF_INSECURE + CF_NOBLANK_VAL + CF_PREAPPLIED_BASE + CF_FEEDBACK_BLACKBOX,
		TABLEINSPECT = CF_INSECURE + CF_PREAPPLIED_BASE + CF_FEEDBACK_BLACKBOX,
		DUMP = CF_INSECURE + CF_PREAPPLIED_BASE + CF_FEEDBACK_BLACKBOX,
		EMOTE = CF_CHAT_MESSAGE,
		SAY = CF_CHAT_MESSAGE,
		YELL = CF_CHAT_MESSAGE,
		WHISPER = CF_CHAT_MESSAGE,
		SMART_WHISPER = CF_CHAT_MESSAGE,
		CHAT_DND = CF_CHAT_MESSAGE,
		CHAT_AFK = CF_CHAT_MESSAGE,
		REPLY = CF_CHAT_MESSAGE,
		GUILD_MOTD = CF_CHAT_MESSAGE,
		PARTY = CF_CHAT_MESSAGE,
		RAID = CF_CHAT_MESSAGE,
		INSTANCE_CHAT = CF_CHAT_MESSAGE,
		GUILD = CF_CHAT_MESSAGE,
		OFFICER = CF_CHAT_MESSAGE,
		CHANNEL = CF_CHAT_MESSAGE
	}
	function getCommandKeyFlags(commandKey)
		local kf = keyFlags[commandKey]
		if kf then
			return kf > 0 and kf < CF_PREAPPLIED_BASE and CF_SECURE_BASE + kf or kf
		end
		return IsSecureCmd(_G["SLASH_" .. commandKey .. "1"] or "-?-") and CF_SECURE_BASE or 0
	end
end
local function init()
	local ik = {
		USE = 1,
		CAST = 1,
		STOPMACRO = 1
	}
	for k in pairs(type(ChatTypeInfo) == "table" and ChatTypeInfo or hash_ChatTypeInfoList) do
		local cf = ik[k] == nil and getCommandKeyFlags(k) or 0
		ik[k] = 1
		if cf ~= 0 then
			RW:ImportSlashCmdEx(k, cf)
		end
	end
	for k in pairs(SlashCmdList) do
		local cf = ik[k] == nil and getCommandKeyFlags(k) or 0
		ik[k] = 1
		if cf ~= 0 then
			RW:ImportSlashCmdEx(k, cf)
		end
	end
	for m in ("#mute #unmute #mutenext #parse #nounshift"):gmatch("%S+") do
		RW:RegisterCommand(m, true, false, core)
	end
	RW:RegisterCommandEx("/stopmacro", getCommandKeyFlags("STOPMACRO"), core)
	RW:AddCommandAliases("/stopmacro", getAliases("SLASH_STOPMACRO", 1))
	RW:SetCommandHint("/stopmacro", math.huge, function(_, _, clause)
		return clause and "stop" or nil
	end)
	RW:RegisterCommand("/varset", true, true, core)
	RW:SetCommandHint("/varset", math.huge, function(_, _, v)
		if not v then
			return
		end
		local vname, vnEnd = v:match("^%s*([a-zA-Z\128-\255][a-zA-Z0-9_\128-\255]*)()")
		if not vname then
			return
		end
		local val = v:match("^%s+(.-)%s*$", vnEnd)
		val = val and resolveOptionsClauseValue(val, false, true, 2)
		RW:SetSpeculativeMacroVarValue(vname, val)
	end)
	RW:SetCommandHint(SLASH_CLICK1, math.huge, function(...)
		local _, _, clause = ...
		local name = clause and clause:match("%S+")
		return getCommandHintRaw(name and ("/click " .. name), ...)
	end)
	setCommandType("/use", getCommandKeyFlags("USE"), core)
	RW:AddCommandAliases("/use", getAliases("SLASH_USE", 1))
	setCommandType("/cast", getCommandKeyFlags("CAST"), core)
	RW:AddCommandAliases("/cast", getAliases("SLASH_CAST", 1))
	RW:AddCommandAliases(SLASH_USERANDOM1, getAliases("SLASH_CASTRANDOM", 1))
	RW:RegisterCommand("/runmacro", true, true, core)
	RW:SetCommandHint("/runmacro", math.huge, function(_slash, _, n, _t, ...)
		local f = namedMacros[n]
		if f then
			return f(n, nil, ...)
		end
		local mt = coreNamedMacroText[n]
		if mt then
			local cndState, minPriority = ...
			return getMacroHint(mt, cndState, minPriority)
		end
	end)
	local iconAtlasCache = {}
	local iconReplCache = setmetatable({}, {
		__index = function(t, k)
			if not k then
				return
			end
			local v, a = (tonumber(k))
			if not v then
				if k:match("[/\\]") then
					v = k
				elseif k ~= "" then
					if C_Texture.GetAtlasInfo(k) then
						v, a = k, true
					else
						v = "Interface\\Icons\\" .. k
					end
				end
			end
			t[k], iconAtlasCache[k] = v ~= 0 and v, a or v and false
			return v
		end
	})
	local function iconBC(_oico, meta, value, _target)
		return true, meta == "iconb" and nil, iconReplCache[value], iconAtlasCache[value]
	end
	RW:SetMetaHintFilter("icon", "replaceIcon", true, function(_meta, value, _target)
		return true, iconReplCache[value], iconAtlasCache[value]
	end)
	RW:SetMetaHintFilter("iconb", "replaceIconB", true, iconBC)
	RW:SetMetaHintFilter("iconc", "replaceIconB", true, iconBC)
	RW:SetMetaHintFilter("count", "replaceCount", true, function(_meta, value, _target)
		local c = value == "none" and 0 or (value and GetItemCount(value))
		return not not c, c
	end)
	RW:SetMetaHintFilter("label", "replaceLabel", true, function(_meta, value, _target)
		return not not value, value or ""
	end)
end
local caEscapeCache, caAliasCache, caIsOptional, cuHints, caFlush = {}, {}, {}, {}
do
	setmetatable(caEscapeCache, {
		__index = function(t, k)
			if k then
				local v = coreEnv.castEscapes[k:lower()] or false
				t[k] = v
				return v
			end
		end
	})
	setmetatable(caAliasCache, {
		__index = function(t, k)
			if k then
				local at = coreEnv.castAliases
				local v = at[k:lower()]
				repeat
					local vl = v and v:lower()
					v = at[vl] or v
				until not at[vl]
				t[k] = v
				return v
			end
		end
	})
	function caFlush()
		wipe(caEscapeCache)
		wipe(caAliasCache)
	end
	local function mixHint(slash, _, clause, target, ...)
		clause = caAliasCache[clause] or clause
		local ca = caEscapeCache[clause]
		if ca then
			return true, AB:GetSlotInfo(ca)
		else
			local hint = cuHints[slash]
			if hint then
				return hint(slash, _, clause, target, ...)
			end
		end
	end
	setCommandHinter("/use", 100, mixHint)
	setCommandHinter("/cast", 100, mixHint)
end
local function nextReVar(_, k)
	return rtnext(coreEnv.reVars, k)
end

function RW:compatible(cmaj, crev)
	local acceptable = (cmaj == MAJ and crev <= REV)
	if acceptable and init then
		init()
		init = nil
	end
	return acceptable and RW or nil, MAJ, REV
end
function RW:seclib()
	return core
end
function RW:RegisterCommand(slash, isConditional, allowVars, handlerFrame)
	assert(type(slash) == "string" and
			   (handlerFrame == nil or type(handlerFrame) == "table" and type(handlerFrame.GetAttribute) == "function"),
		'Syntax: Rewire:RegisterCommand("/slash", parseConditional, allowVars[, handlerFrame])')
	assert(handlerFrame == nil or handlerFrame:GetAttribute("RunSlashCmd"),
		'Handler frame must have "RunSlashCmd" attribute set.')
	assert(not InCombatLockdown(), 'Combat lockdown in effect')
	local ct = (isConditional and 1 or 0) + (allowVars and 2 or 0)
	return RW:RegisterCommandEx(slash, ct, handlerFrame)
end
function RW:AddCommandAliases(primary, ...)
	assert(type(primary) == "string", 'Syntax: Rewire:AddCommandAliases("/slash", ["/alias1", "/alias2", ...])')
	assert(not InCombatLockdown(), 'Combat lockdown in effect')
	local commandAlias = coreEnvW.commandAlias
	local shortLen, shortAlias = PYROLYSIS and strlenutf8(coreEnv.PYshortName[primary] or primary), nil
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		commandAlias[v] = primary
		local aliasLen = shortLen and strlenutf8(v)
		if aliasLen and aliasLen < shortLen then
			shortLen, shortAlias = aliasLen, v
		end
	end
	if shortAlias then
		coreEnvW.PYshortName[primary] = shortAlias
	end
	coreEnvW.commandAliasChanged = 1
end
function RW:GetCommandInfo(slash)
	assert(type(slash) == "string",
		'Syntax: isConditional, allowVars, isCommaListArg, isSequenceListArg, resolveUnitTargets = Rewire:GetCommandInfo("/slash")')
	local ct = coreEnv.commandFlags[slash]
	if ct then
		return ct % 2 >= 1, ct % 4 >= 2, ct % 8 >= 4, ct % 16 >= 8, ct % 32 >= 16
	end
end
function RW:ImportSlashCmd(key, isConditional, allowVars, priority, hint)
	assert(type(key) == "string" and (hint == nil or type(hint) == "function" and type(priority) == "number"),
		'Syntax: Rewire:ImportSlashCmd("KEY", parseConditional, allowVars[, hintPriority, hintFunc])')
	assert(not InCombatLockdown(), 'Combat lockdown in effect')
	local cf = (isConditional and 1 or 0) + (allowVars and 2 or 0)
	return RW:ImportSlashCmdEx(key, cf, priority, hint)
end
function RW:SetCommandHint(slash, priority, hint)
	assert(type(slash) == "string" and (hint == nil or type(hint) == "function" and type(priority) == "number"),
		'Syntax: Rewire:SetCommandHint("/slash", priority, hintFunc)')
	if slash ~= "/use" and slash ~= "/cast" then
		setCommandHinter(slash, priority, hint)
	else
		cuHints[slash] = hint
	end
end
function RW:SetClickHint(buttonName, priority, hint)
	assert(type(buttonName) == "string" and (hint == nil or type(hint) == "function" and type(priority) == "number"),
		'Syntax: Rewire:SetClickHint("buttonName", priority, hintFunc)')
	setCommandHinter("/click " .. buttonName, priority, hint)
end
function RW:SetMetaHintFilter(meta, filterType, isConditional, hint)
	assert(type(meta) == "string" and type(isConditional) == "boolean" and type(hint) == "function",
		'Syntax: Rewire:SetMetaHintFilter("meta", "filterType", isConditional, hintFunc)')
	local filterRun = assert(metaFilterTypes[filterType], 'Unsupported meta hint filter type')
	metaFilters[meta:lower()] = {filterRun, isConditional, hint, filterType}
end
function RW:SetNamedMacroHandler(name, handlerFrame, hintFunc, skipNotifyAB)
	assert(
		type(name) == "string" and type(handlerFrame) == "table" and type(handlerFrame.GetAttribute) == "function" and
			(hintFunc == nil or type(hintFunc) == "function"),
		'Syntax: Rewire:SetNamedMacroHandler(name, handlerFrame, hintFunc?, skipNotifyAB?)')
	assert(handlerFrame:GetAttribute("RunNamedMacro"), 'Handler frame must have "RunNamedMacro" attribute set.')
	if handlerFrame ~= GetFrameHandleFrame(coreEnv.macros[name]) then
		assert(not InCombatLockdown(), 'Combat lockdown in effect')
		core:SetFrameRef("SetNamedMacroHandler-handlerFrame", handlerFrame)
		WR.RunAttribute(coreEnvW, "SetNamedMacroHandler", name, skipNotifyAB == true)
	end
	namedMacros[name] = hintFunc
end
function RW:ClearNamedMacroHandler(name, handlerFrame, skipNotifyAB)
	assert(type(handlerFrame) == "table" and type(name) == "string",
		'Syntax: Rewire:ClearNamedMacroHandler("name", handlerFrame)')
	if GetFrameHandleFrame(coreEnv.macros[name]) == handlerFrame then
		assert(not InCombatLockdown(), 'Combat lockdown in effect')
		coreEnvW.macros[name] = coreNamedMacroText[name] == nil and nil
		core:clearNamedMacroHinter(name, skipNotifyAB)
	end
end
function RW:GetNamedMacros()
	return rtable.pairs(coreEnv.macros)
end
function RW:IsNamedMacroKnown(name)
	return coreEnv.macros[name] ~= nil
end
function RW:RegisterNamedMacroTextOwner(owner, priority)
	assert(owner ~= nil and type(priority) == "number",
		'Syntax: ownerToken = Rewire:RegisterNamedMacroTextOwner(owner, priority)')
	assert(namedMacroTextOwnerPriority[owner] == nil, 'Duplicate registration')
	namedMacroTextOwnerPriority[owner] = priority
	return owner
end
function RW:SetNamedMacroText(name, text, ownerToken, skipNotifyAB)
	assert(type(name) == "string" and (not text or type(text) == "string"),
		'Syntax: Rewire:SetNamedMacroText("name", "text", ownerToken, priority?, skipNotifyAB?)')
	assert(not InCombatLockdown(), 'Combat lockdown in effect')
	assert(namedMacroTextOwnerPriority[ownerToken], 'ownerToken is not registered')
	local a = namedMacroText[name]
	local et = a and a[ownerToken]
	if not (text or et) or et == text then
		return
	else
		a = a or {}
		namedMacroText[name], a[ownerToken] = a, text or nil
	end
	local nv, k, p = nil, next(a)
	if k == nil then
		namedMacroText[name] = nil
	else
		nv, p = p, namedMacroTextOwnerPriority[k]
		for co, text in next, a, k do
			local cp = namedMacroTextOwnerPriority[co]
			if cp > p then
				nv, p = text, cp
			end
		end
	end
	if nv ~= coreNamedMacroText[name] then
		local t = nv or nil
		coreEnvW.namedMacroText[name] = t
		coreEnvW.macros[name] = coreEnvW.macros[name] or (t and false)
		if skipNotifyAB then
			return true
		elseif AB then
			AB:NotifyObservers("macro")
		end
	end
end
function RW:GetMacroAction(macrotext, cndState, minPriority)
	return getMacroHint(macrotext, cndState, minPriority)
end
function RW:GetNamedMacroAction(name, cndState, minPriority)
	local hf = namedMacros[name]
	if hf then
		return hf(name, nil, cndState, minPriority)
	end
	local mt = coreNamedMacroText[name]
	if mt then
		return getMacroHint(mt, cndState, minPriority)
	end
end
function RW:GetCommandAction(slash, args, target, modState, msg)
	return getCommandHint(nil, slash, args, modState, target, msg)
end
function RW:SetCastEscapeAction(castArg, action, isOptional)
	assert(type(castArg) == "string" and (type(action) == "number" and action % 1 == 0 or action == nil) and
			   (type(isOptional) == "boolean" or isOptional == nil),
		'Syntax: Rewire:SetCastEscapeAction("castAction", abActionID or nil[, isOptional])')
	assert(not InCombatLockdown(), 'Combat lockdown in effect')
	local lowArg = castArg:lower()
	coreEnvW.castEscapes[lowArg], coreEnvW.castAliases[lowArg] = action, nil
	caIsOptional[lowArg] = action and isOptional or nil
	caFlush()
end
function RW:GetCastEscapeAction(castArg)
	return caEscapeCache[castArg]
end
function RW:SetCastAlias(castArg, aliasTo, isOptional)
	assert(type(castArg) == "string" and (aliasTo == nil or type(aliasTo) == "string") and
			   (isOptional == true or not isOptional),
		'Syntax: Rewire:SetCastAlias("castAction", "aliasTo" or nil[, isOptional])')
	assert(not InCombatLockdown(), 'Combat lockdown in effect')
	local lowArg = castArg:lower()
	if aliasTo == castArg or aliasTo and strcmputf8i(aliasTo, castArg) == 0 then
		aliasTo = nil
	elseif aliasTo then
		local al, at = aliasTo:lower(), coreEnv.castAliases
		while al ~= lowArg and al and at[al] do
			al = at[al]:lower()
		end
		assert(al ~= lowArg, 'Aliasing %q creates an alias cycle.', aliasTo)
	end
	coreEnvW.castAliases[lowArg], coreEnvW.castEscapes[lowArg] = aliasTo, nil
	caIsOptional[lowArg] = aliasTo and isOptional or nil
	caFlush()
end
function RW:GetCastAlias(castArg)
	return caAliasCache[castArg]
end
function RW:IsCastEscape(castArg, excludeOptional)
	local lowArg = type(castArg) == "string" and castArg:lower() or nil
	if excludeOptional and caIsOptional[lowArg] then
		return false
	end
	return (caEscapeCache[lowArg] or caAliasCache[lowArg]) ~= nil
end
function RW:IsSpellCastable(id, castContext, laxRank)
	local ccf, cc, re, defer = Spell_CheckCastable[id]
	if ccf then
		cc, re, defer = ccf(id, castContext, laxRank)
	end

	local name = (cc == nil or defer) and GetSpellInfo(id)
	if name and (caEscapeCache[name] or caAliasCache[name]) then
		local disallowRewireEscapes = castContext == true or castContext and type(castContext) == "number" and
										  castContext % 2 < 1
		if disallowRewireEscapes ~= true or (disallowRewireEscapes == true and not caIsOptional[name:lower()]) then
			return disallowRewireEscapes ~= true, "rewire-escape"
		end
	end
	if cc ~= nil then
		return cc, re
	elseif not name then
		return false, "unknown-sid"
	end

	return false
end
function RW:SetSpellCastableChecker(id, callback)
	assert(type(id) == "number" and (callback == nil or type(callback) == "function"),
		'Syntax: Rewire:SetSpellCastableChecker(spellID, callback or nil)')
	Spell_CheckCastable[id] = callback
end
function RW:SetMacroExtensionCommand(name, remacrotext, owner)
	assert(type(name) == "string" and (remacrotext == nil or type(remacrotext) == "string") and type(owner) == "string",
		'Syntax: Rewire:SetMacroExtensionCommand("commandName", "remacrotext" or nil, "owner")')
	assert(not InCombatLockdown(), 'Combat lockdown in effect')
	WR.RunAttribute(coreEnvW, "SetMacroExtensionCommand", name, remacrotext, owner)
end
function RW:GetMacroExtensionCommand(name, checkOwner)
	assert(type(name) == "string", 'Syntax: Rewire:GetMacroExtensionCommand("commandName"[, "checkOwner"])')
	name = name:lower()
	return coreEnv.reMacroExt["/!" .. name], coreEnv.reMacroExtOwner[name] == checkOwner
end
function RW:SetSpeculativeMacroVarValue(vname, value)
	assert(type(vname) == "string", 'Syntax: Rewire:SetSpeculativeMacroVarValue("vname", "value" or nil)')
	reVarsSP[vname] = value
end
function RW:SetMacroVarValue(vname, value)
	assert(type(vname) == "string" and (value == nil or type(value) == "string"),
		'Syntax: Rewire:SetMacroVarValue("vname", "value" or nil)')
	assert(not InCombatLockdown(), 'Combat lockdown in effect')
	coreEnvW.reVars[vname] = value
end
function RW:ResolveOptionsClauseValue(value, resolveUnit, resolveVars, escapeMode)
	assert((value == nil or type(value) == "string") and (escapeMode == nil or type(escapeMode) == "number"),
		'Syntax: Rewire:ResolveOptionsClauseValue("value", resolveUnit, resolveVars[, escapeMode])')
	return resolveOptionsClauseValue(value, resolveUnit, resolveVars, escapeMode)
end
RW.GetSpeculationID = getSpeculationID

-- HIDDEN, UNSUPPORTED METHODS: May vanish at any time.
local hum = {}
setmetatable(RW, {
	__index = hum
})
hum.HUM = hum
function hum:AllMacroVars()
	return nextReVar
end
function hum:IsPyrolysisActive()
	return true
end
function hum:RegisterCommandEx(slash, flags, handlerFrame)
	assert(type(slash) == "string" and type(flags) == "number" and
			   (handlerFrame == nil or type(handlerFrame) == "table" and type(handlerFrame.GetAttribute) == "function"),
		'Syntax: Rewire:RegisterCommandEx("/slash", flags[, handlerFrame])')
	assert(flags % 1 == 0 and flags >= 0, 'RegisterCommandEx: invalid flags')
	assert(handlerFrame == nil or handlerFrame:GetAttribute("RunSlashCmd"),
		'Handler frame must have "RunSlashCmd" attribute set.')
	assert(not InCombatLockdown(), 'Combat lockdown in effect')
	setCommandType(slash, flags, handlerFrame)
end
function hum:ImportSlashCmdEx(key, flags, priority, hint)
	assert(type(key) == "string" and (hint == nil or type(hint) == "function" and type(priority) == "number"),
		'Syntax: Rewire:ImportSlashCmdEx("KEY", flags[, hintPriority, hintFunc])')
	assert(type(flags) == "number" and flags % 1 == 0 and flags >= 0, 'ImportSlashCmdEx: invalid flags')
	assert(not InCombatLockdown(), 'Combat lockdown in effect')
	local primary = _G["SLASH_" .. key .. "1"]
	RW:RegisterCommandEx(primary, flags)
	if _G["SLASH_" .. key .. "2"] then
		RW:AddCommandAliases(getAliases("SLASH_" .. key, 1))
	end
	if primary and hint then
		self:SetCommandHint(primary, priority, hint)
	end
end
function hum:GetCommandFlags(slash)
	return coreEnv.commandFlags[slash]
end

AB:RegisterModule("Rewire", {
	compatible = RW.compatible
})
