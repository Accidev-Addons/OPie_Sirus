local MAJ, REV, _, T = 1, 34, ...
if T.SkipLocalActionBook then
	return
end
local KR, EV, WR = {}, T.Evie, T.Ware
assert(EV and WR and 1, "Incompatible library bundle")

local function assert(condition, err, ...)
	return condition or error(tostring(err):format(...), 3)((0)[0])
end

local rtgsub = string.rtgsub
local core = CreateFrame("Frame", nil, nil, "SecureHandlerStateTemplate")
local coreEnvW = WR.GetRestrictedEnvironment(core)
do
	core:Hide(core)
	coreEnvW.sandbox = CreateFrame("Frame", nil, nil, "SecureFrameTemplate")
	local watchProxy = CreateFrame("Frame", nil, nil, "SecureFrameTemplate")
	local bindProxy = CreateFrame("Frame", nil, nil, "SecureFrameTemplate")
	coreEnvW.watchProxy, coreEnvW.bindProxy = watchProxy, bindProxy
	coreEnvW.watchFor, coreEnvW.watchPrev, coreEnvW.watchKR = WR.newtable, WR.newtable, WR.newtable
	core:WrapScript(watchProxy, "OnAttributeChanged", [=[--Kindred_StateWatch_OAC
		local cnd, prev = watchFor[name], watchPrev[name]
		if cndType[cnd] == "state" then
			watchPrev[name] = value
			owner:RunAttribute("UpdateStateConditional", cnd, value or "", prev)
			return
		elseif watchKR[cnd] then
			owner:SetAttribute("frameref-RegisterStateDriver-frame", self)
			owner:RunAttribute("RegisterStateDriver", name:sub(#"state-x"), "")
		else
			RegisterStateDriver(self, name:sub(#"state-x"), "")
		end
		watchFor[name], watchPrev[name], watchKR[name] = nil
	]=])
	core:WrapScript(bindProxy, "OnAttributeChanged", [=[--Kindred_Bind_OnAttributeChanged
		local key = name:match("^state%-(bind%d+)$")
		if bindingDrivers[key] then
			owner:Run(BindingLink_Move, key, value)
		end
	]=])
	function core:SetOptFrameRef(ref, frame)
		if frame then
			return self:SetFrameRef(ref, frame)
		else
			return (self.SetAttributeNoHandler or self.SetAttribute)(self, "_frameref-" .. ref, nil)
		end
	end
end
core:SetAttribute("SecureOptionEscapes", [[ \\\ ;\s [\l ]\r %\p /\f ,\c ]] .. " \n\\n ")
core:Execute([==[-- Kindred.Init
	KR, pcache, nextDriverKey = self, newtable(), 4200
	cndType, cndState, cndDrivers, cndAlias, unitAlias = newtable(), newtable(), newtable(), newtable(), newtable()
	modArgCache, modStateCache, modTokens, modHoldMap = newtable(), newtable(), newtable(6, "ctrl", "alt", "shift", "meta", "cmd"), newtable(".", "L", "R", "B")
	modArgCache.any = newtable("any")
	stateDrivers, driverWatch = newtable(), newtable()
	driverWatch.mod = newtable("[mod] on; off", false, nil)
	driverWatch.bonusbar = newtable(("0 1 2 3 4 5 6 7 8 9 no"):gsub("%d+", "[bonusbar:%0] %0;"), false, nil)
	isInLockdown, cndInsecure = false, newtable()
	bindingDrivers, bindingKeys, nextBindingKey, bindEscapeMap = newtable(), newtable(), 42000, newtable()
	bindEscapeMap.SEMICOLON, bindEscapeMap.OPEN, bindEscapeMap.CLOSE = ";", "[", "]"
	soEscapeSeqToLiteral = newtable()
	for c, e in (self:GetAttribute("SecureOptionEscapes")):gmatch("([^ ])(\\.)") do
		soEscapeSeqToLiteral[e] = c
	end
	local mu = newtable()
	futureRemappableUnits, mu.target, mu.pettarget, mu.focus = mu, 1,1,1
	futureUnitMap, unitPrefixCache, fumOwner = newtable(), newtable(), nil
	baseUnitCache = newtable()
	baseUnitCache.target = newtable("target", "")

	OptionParse = [=[-- Kindred_OptionParse
		local ret, options = newtable(), ...
		local no, ns, lp = options:gmatch("()%["), options:gmatch("();"), #options + 1
		local po, lc, fi, pc, ps = no() or lp, 0, 0
		repeat
			ps = ns() or lp
			while po < ps do
				pc = options:match("()%]", po)
				if pc then
					local clause, ct = options:sub(po+1, pc-1):lower(), newtable()
					for m in clause:gmatch("[^,%s][^,]*") do
						m = m:match("^(.-)%s*$")
						if m:sub(1,1) == "@" or m:sub(1,7) == "target=" then
							local bu, suf = m:match("[=@]%s*([^-%d]*%d*)(.-)%s*$")
							ct.target, ct.targetS = bu, suf ~= "" and suf or nil
						else
							local cvalparsed, mark, wname, inv, name, col, cval = nil, m:match("^([+]?)((n?o?)([^:=]*))([:=]?)(.-)%s*$")
							if inv ~= "no" then inv, name = "", wname end
							cval, name = col == ":" and cval and ("/" .. cval .. "/"):gsub("%s*/%s*", "/"):sub(2,-2) or nil, col == ":" and name or (name .. col .. cval)
							if cval and cval ~= "" then
								cvalparsed = newtable()
								for s in cval:gmatch("[^/]+") do
									if ((name == "form" or name == "stance") and tonumber(s) or 1) < 1 then
										cvalparsed[0] = true -- treated as [noform]
									else
										cvalparsed[#cvalparsed+1] = s
									end
								end
							end
							cct = newtable(name, cvalparsed, inv ~= "no", mark, cval)
							ct[#ct+1], cct[0] = cct, m
						end
					end
					ret[#ret+1], lc, po = ct, pc, no() or lp
				else
					break
				end
			end
			if fi == #ret then
				ret[#ret+1] = newtable()
			end
			local v = options:sub(lc+1, ps-1):match("^%s*(.-)%s*$")
			for i=fi+1, #ret do
				ret[i].v, ret[i].idx = v, i
			end
			fi, lc = #ret, ps
		until ps == lp
		pcache[options] = ret
	]=]
	ParseRemapBaseUnit = [=[-- Kindred_ParseRemapBaseUnit
		local r, unit = false, ...
		local s1 = unit:match("^[Tt][Aa][Rr][Gg][Ee][Tt](.*)$")
		local s2 = s1 or unit:match("^[Pp][Ee][Tt][Tt][Aa][Rr][Gg][Ee][Tt](.*)$")
		local s3 = s2 or unit:match("^[Ff][Oo][Cc][Uu][Ss](.*)$")
		baseUnitCache[unit] = s3 and newtable(s1 and "target" or s2 and "pettarget" or s3 and "focus", s3) or false
		return s3 ~= nil
	]=]
	OptionConstruct = [=[-- Kindred_OptionConstruct
		local mode, cond, cndLock, futureID = ...
		local parse, out, outv = pcache[cond] or owner:Run(OptionParse, cond) or pcache[cond]
		local cndLockUnchecked, modKeyState, buttonOverride = true
		local cvk = mode == "eval" and "idx" or "v"
		local fum = futureID and (_shadowFUM or fumOwner == futureID and futureUnitMap)
		for i=1,#parse do
			local chunk, clause, cnext, chunkv = parse[i], "", ""
			local target, ts = chunk.target, chunk.targetS
			while unitAlias[target] do target = unitAlias[target] end
			target = ts and target and target .. ts or target
			local fc = fum and (baseUnitCache[target or "target"] or self:Run(ParseRemapBaseUnit, target) and baseUnitCache[target])
			target = fc and fum[fc[1]] and (fum[fc[1]] .. fc[2]) or target
			
			for j=1,#chunk do
				local c = chunk[j]
				local name, argp, goal, flag = c[1], c[2], c[3], c[4]
				if goal == false and (cndType[name] == nil and cndType["no" .. name]) then goal, name = true, "no" .. name end
				if cndAlias[name] then name = cndAlias[name] end
				if (name == "mod" or name == "btn") and cndLockUnchecked then
					if cndLock == nil or (cndLock and type(cndLock) ~= "string") then
						cndLock = owner:GetAttribute("cndLock")
						cndLock = type(cndLock) == "string" and cndLock
					end
					buttonOverride = cndLock and cndLock:match(">(.+)$")
					cndLockUnchecked = false
				end
				if name == "mod" then
					if modKeyState == nil then
						local t = wipe(modStateCache)
						t.lalt, t.lshift, t.lctrl, t.lmeta = IsLeftAltKeyDown(), IsLeftShiftKeyDown(), IsLeftControlKeyDown(), IsModifiedClick("LMETA-X")
						t.ralt, t.rshift, t.rctrl, t.rmeta = IsRightAltKeyDown(), IsRightShiftKeyDown(), IsRightControlKeyDown(), IsModifiedClick("RMETA-X")
						if cndLock then
							local a, s, c, m = cndLock:match("^([LRBK.])([LRBK.])([LRBK.])([LRBK.])")
							t.lalt,   t.ralt   = a ~= "K" and (a == "B" or a == "L" or t.lalt),   a ~= "K" and (a == "B" or a == "R" or t.ralt)
							t.lshift, t.rshift = s ~= "K" and (s == "B" or s == "L" or t.lshift), s ~= "K" and (s == "B" or s == "R" or t.rshift)
							t.lctrl,  t.rctrl  = c ~= "K" and (c == "B" or c == "L" or t.lctrl),  c ~= "K" and (c == "B" or c == "R" or t.rctrl)
							t.lmeta,  t.rmeta  = m ~= "K" and (m == "B" or m == "L" or t.lmeta),  m ~= "K" and (m == "B" or m == "R" or t.rmeta)
						end
						t.alt, t.shift, t.ctrl, t.meta = t.lalt or t.ralt, t.lshift or t.rshift, t.lctrl or t.rctrl, t.lmeta or t.rmeta
						t.lcmd, t.rcmd, t.cmd = t.lmeta, t.rmeta, t.meta
						t.any, modKeyState = t.alt or t.shift or t.ctrl or t.meta, t
					end
					local ai, aa, matched, modArg = 1
					repeat
						aa, ai = argp == nil and "any" or c[2][ai], ai + 1
						matched, modArg = true, modArgCache[aa]
						if modArg == nil then
							local r, a, p = newtable(), aa
							for k=2, modTokens[1] do
								p = "[rl]?" .. modTokens[k]
								for m in a:gmatch(p) do
									r[#r+1] = m
								end
								a = a:gsub(p, "")
							end
							modArg, modArgCache[aa] = r, r
						end
						for i=1, #modArg do
							if not modKeyState[modArg[i]] then
								matched = false
								break
							end
						end
					until matched or not argp or ai > #argp
					if matched ~= goal then
						clause = nil
						break
					end
				elseif name == "btn" and buttonOverride then
					local matched = argp == nil
					for i=1, matched and 0 or #argp do
						if argp[i] == buttonOverride then
							matched = true
							break
						end
					end
					if matched ~= goal then
						clause = nil
						break
					end
				elseif name == "bonusbar" and argp == nil then
					if (GetBonusBarOffset() == 0) == goal then
						clause = nil
						break
					end
				elseif cndType[name] == nil then
					clause, cnext = clause .. cnext .. c[0], ","
				else
					local cres, ctype = false, cndType[name]
					if ctype == "state" then
						local cs, cval = cndState[name]
						if argp == nil then
							cval = cs and cs["*"] or false
						else
							for k=1,cs and #argp or 0 do
								if cs[argp[k]] then
									cval = true
									break
								end
							end
							cval = cval or (argp[0] and not (cs and cs["*"]))
						end
						cres = (not not cval) == goal
					elseif ctype == "gt" then
						local cs, cval = cndState[name]
						if argp == nil then
							cval = not not cs
						elseif cs then
							for k=1,#argp do
								local n = tonumber(argp[k])
								if n and n <= cs then
									cval = true
									break
								end
							end
						end
						cres = (not not cval) == goal
					elseif ctype == "srun" then
						local s, dv = cndState[name]
						if type(s) == "string" then
							cres = sandbox:Run(s, c[5], target, c[4])
						elseif _shadowES and _shadowES[name] then
							cres = _shadowES[name](name, c[5], target, c[4], futureID)
						elseif s then
							cres, dv = s:RunAttribute("EvaluateMacroConditional", name, c[5], target, c[4], futureID)
							if cres == nil and dv == "use-scop" then
								clause, cnext = clause .. cnext .. c[0], ","
								cres = goal
							end
						end
						cres = (not not cres) == goal
					elseif ctype == "irun" then
						local markType = c[4]
						if isInLockdown then
							cres = markType == "+"
						elseif _shadowES and _shadowES[name] then
							cres = (not not _shadowES[name](name, c[5], target, markType, futureID)) == goal
						else
							self:CallMethod("irun", name, c[5], target, markType)
							local res = self:GetAttribute("irun-result")
							if res == "lockdown" then
								cres = markType == "+"
							else
								cres = (not not res) == goal
							end
						end
					end
					if not cres then
						clause = nil
						break
					end
				end
			end
			if clause then
				clause, chunkv = "[" .. (target and "@" .. target .. cnext .. clause or clause) .. "]", chunk[cvk]
				if outv == chunkv then
					out = out .. clause
				elseif clause == "[]" then
					out, outv = out and out .. outv .. ";" or "", chunkv
					break
				else
					out, outv = out and out .. outv .. ";" .. clause or clause, chunkv
				end
				if cnext == "" then
					break
				end
			end
		end
		out = outv and (out .. outv) or out or "[form:42]"
		if mode == "eval" then
			local v, ct = SecureCmdOptionParse(out)
			local chunk = v and parse[v+0]
			if not chunk then return end
			local target, ts = chunk.target, chunk.targetS
			while unitAlias[target] do target = unitAlias[target] end
			target = ts and target and target .. ts or target
			return chunk.v, target, ct
		end
		return out
	]=]
	RefreshDrivers = [=[-- Kindred_RefreshDrivers
		local name = ...
		if cndDrivers[name] then
			for key, info in pairs(cndDrivers[name]) do
				local nv = owner:Run(OptionConstruct, "driver", info[3], false, "driver-construct")
				if info[5] ~= nv then
					info[5] = nv
					RegisterStateDriver(info[1], info[2], nv == "" and "[]" or nv)
				end
			end
		end
	]=]
	BindingLink_Move = [=[-- Kindred_BindingLink_Move
		local ep, key, newValue = nil, ...
		local link = bindingDrivers[key]
		if not link then return end
		ep, newValue = strmatch(newValue or "", "^%s*(!*)%s*(%S.*)$")
		newValue = newValue and strmatch(rtgsub(rtgsub(newValue, "\\.", soEscapeSeqToLiteral), "[^%-]+$", bindEscapeMap), "^%s*(%S.-)%s*$") or nil
		local up, down, value = link.up, link.down, link.value
		if up then
			up.down, link.up = down
		end
		if down then
			down.up, link.down = up
		end
		if value and not up then
			bindingKeys[value] = down
			if down then
				bindProxy:SetBindingClick(down.priority > 0, value, down.target, down.button)
				if down.notify then
					down.notify:SetAttribute("binding-" .. down.button, value)
				end
			else
				bindProxy:ClearBinding(value)
			end
		end
		link.priority, link.value = link.basePriority + (ep and #ep*1e3 or 0), newValue
		if newValue then
			local down, up = bindingKeys[newValue]
			while down and down.priority > link.priority do
				down, up = down.down, down
			end
			link.down, link.up = down, up
			if down then
				down.up = link
			end
			if up then
				up.down = link
			else
				bindingKeys[newValue], link.down = link, down
				bindProxy:SetBindingClick(link.priority > 0, newValue, link.target, link.button)
			end
			if down and down.notify and not up then
				down.notify:SetAttribute("binding-" .. down.button, nil)
			end
		end
		if link.notify then
			link.notify:SetAttribute("binding-" .. link.button, not link.up and newValue or nil)
		end
	]=]
]==])
core:SetAttribute("RegisterStateDriver", [=[-- Kindred:RegisterStateDriver(*frame*, "state", "options")
	local frame = owner:GetFrameRef("RegisterStateDriver-frame")
	owner:SetAttribute("frameref-RegisterStateDriver-frame", nil)
	if frame == nil then return owner:CallMethod("throw", 'Set the "RegisterStateDriver-frame" frameref before calling RegisterStateDriver.') end
	local drivers, state, values = stateDrivers[frame], ...
	local old = drivers and drivers[state]
	if old then
		drivers[state] = nil
		RegisterStateDriver(frame, state, "")
		for _, t in pairs(cndDrivers) do
			t[old[4]] = nil
		end
	end
	if values and type(state) == "string" and values ~= "" then
		local info, key
		drivers, info, key = drivers or newtable(), newtable(frame, state, values, nextDriverKey), nextDriverKey
		stateDrivers[frame], drivers[state], nextDriverKey = drivers, info, nextDriverKey + 1
		local parse = pcache[values] or owner:Run(OptionParse, values) or pcache[values]
		local cv = owner:Run(OptionConstruct, "driver", values, false, "driver-construct")
		info[5] = cv
		RegisterStateDriver(frame, state, cv == "" and "[]" or cv)
		for j=1,#parse do
			local clause = parse[j]
			for k=1,#clause do
				local n = clause[k][1]
				cndDrivers[n] = cndDrivers[n] or newtable()
				cndDrivers[n][key] = info
			end
			local u = clause.target while u do
				local n = "unit:" .. u
				cndDrivers[n] = cndDrivers[n] or newtable()
				cndDrivers[n][key], u = info, unitAlias[u]
			end
		end
	end
	for cnd, info in pairs(driverWatch) do
		local cd = cndDrivers[cnd]
		local wantWatch = cd and next(cd) ~= nil
		if wantWatch and not info[2] then
			info[2] = true
			owner:SetAttribute("state-" .. cnd, nil)
			RegisterStateDriver(owner, cnd, info[1])
		elseif old and cd and not wantWatch then
			info[2], info[3], cndDrivers[cnd] = false, nil
			owner:SetAttribute("state-" .. cnd, nil)
			RegisterStateDriver(owner, cnd, "")
		end
	end
]=])
core:SetAttribute("EvaluateCmdOptions", [=[-- Kindred:EvaluateCmdOptions("options"[, cndLock, futureID])
	return owner:Run(OptionConstruct, "eval", ...)
]=])
core:SetAttribute("UpdateThresholdConditional", [=[-- Kindred:UpdateThresholdConditional("name", value or false)
	local name, new = ...
	if type(name) ~= "string" or (new ~= false and type(new) ~= "number") then
		return owner:CallMethod("throw", 'Syntax: ("UpdateThresholdConditional", "name", value or false)')
	end
	local ch = cndDrivers[name] and (cndType[name] ~= "gt" or cndState[name] ~= new)
	cndType[name], cndState[name] = "gt", new
	if ch then
		owner:Run(RefreshDrivers, name)
	end
]=])
core:SetAttribute("UpdateStateConditional", [=[-- Kindred:UpdateStateConditional("name", "addSet", "remSet")
	local name, new, kill = ...
	local cs = cndState[name] or newtable()
	cndType[name], cndState[name] = "state", cs
	if kill == "*" then
		wipe(cs)
	else
		for s in (kill and tostring(kill) or ""):lower():gmatch("[^/]+") do
			cs[s] = nil
		end
		cs["*"] = nil
	end
	for s in (new and tostring(new) or ""):lower():gmatch("[^/]+") do
		cs[s] = 1
	end
	cs["*"] = next(cs) and 2 or nil
	if cndDrivers[name] then
		owner:Run(RefreshDrivers, name)
	end
]=])
core:SetAttribute("SetStateConditionalDriver",
	[=[-- Kindred:SetStateConditionalDriver("name", "driverExpr", isFullyNative)
	local name, driverExpr, isFullyNative = ...
	if type(name) ~= "string" or type(driverExpr) ~= "string" then
		return owner:CallMethod("throw", 'Syntax: ("SetStateConditionalDriver", "name", "driverExpr"[, isFullyNative])')
	end
	local an = "state-" .. name
	if driverExpr == "" then
		watchFor[an] = nil
		return
	end
	cndType[name] = "state"
	watchFor[an], watchPrev[an], watchKR[an] = name, watchPrev[an] or "", not isFullyNative
	watchProxy:SetAttribute(an, nil)
	if isFullyNative then
		RegisterStateDriver(watchProxy, name, driverExpr)
	else
		owner:SetAttribute("frameref-RegisterStateDriver-frame", watchProxy)
		owner:RunAttribute("RegisterStateDriver", name, driverExpr)
	end
]=])
core:SetAttribute("SetAliasUnit", [=[-- Kindred:SetAliasUnit("alias", "unit" or nil)
	local alias, unit = ...
	if unitAlias[alias] == unit then
		return
	elseif not (type(alias) == "string" and (type(unit) == "string" or unit == nil)) then
		return owner:CallMethod("throw", 'Syntax: ("SetAliasUnit", "alias", "unit" or nil)')
	end
	local u = unit while unitAlias[u] and u ~= alias do u = unitAlias[u] end
	if u == alias then
		return owner:CallMethod("throw", ('Kindred:SetUnitAlias: would create a loop aliasing to %q'):format(alias))
	end
	unitAlias[alias] = unit
	owner:Run(RefreshDrivers, "unit:" .. alias)
]=])
core:SetAttribute("ResolveUnit", [=[-- Kindred:ResolveUnit("unit"[, futureID])
	local unit, futureID = ...
	local fum = futureID and (_shadowFUM or fumOwner == futureID and futureUnitMap)
	if type(unit) ~= "string" then
		return owner:CallMethod("throw", 'Syntax: ("ResolveUnit", "unit"[, futureID])')
	elseif fum and fum[unit] then
		unit, fum = fum[unit], nil
	end
	local ua, usuf = unit:match("^([^-%d]*%d*)(.-)$")
	while unitAlias[ua] do ua = unitAlias[ua] end
	ua = ua and usuf and ua .. usuf or unit
	local fc = fum and (baseUnitCache[ua] or self:Run(ParseRemapBaseUnit, ua) and baseUnitCache[ua])
	if fc and fum[fc[1]] then
		ua = fum[fc[1]] .. fc[2]
	end
	return ua
]=])
core:SetAttribute("PokeConditional", [=[-- Kindred:PokeConditional("name")
	owner:Run(RefreshDrivers, (...))
]=])
core:SetAttribute("RegisterBindingDriver",
	[=[-- Kindred:RegisterBindingDriver(*target*, "button", "options", priority[, *notify*])
	local target, notify, button, options, priority = self:GetFrameRef("RegisterBindingDriver-target"), self:GetFrameRef("RegisterBindingDriver-notify"), ...
	self:SetAttribute("frameref-RegisterBindingDriver-target", nil)
	self:SetAttribute("frameref-RegisterBindingDriver-notify", nil)
	if not target then return owner:CallMethod("throw", 'Set the "RegisterBindingDriver-target" frameref before calling RegisterBindingDriver.') end
	if type(options) ~= "string" then return owner:CallMethod("throw", 'Kindred:RegisterBindingDriver: options argument must be a string.') end
	if options == "" and not (bindingDrivers[target] and bindingDrivers[target][button]) then return end
	bindingDrivers[target] = bindingDrivers[target] or newtable()
	local driver = bindingDrivers[target][button] or newtable()
	if driver.id then
		bindProxy:SetAttribute("state-" .. driver.id, nil)
	else
		nextBindingKey, driver.id, driver.target, driver.button = nextBindingKey + 1, "bind" .. nextBindingKey, target, button
		bindingDrivers[target][button], bindingDrivers[driver.id] = driver, driver
	end
	driver.priority, driver.basePriority, driver.notify = priority, priority, notify
	self:SetAttribute("frameref-RegisterStateDriver-frame", bindProxy)
	self:RunAttribute("RegisterStateDriver", driver.id, options:match("[^;%s]%s*$") and options .. ";" or options)
]=])
core:SetAttribute("UnregisterBindingDriver", [=[-- Kindred:UnregisterBindingDriver(*target*, "button")
	local target, button = self:GetFrameRef("UnregisterBindingDriver-target"), ...
	self:SetAttribute("frameref-UnregisterBindingDriver-target", nil)
	if not target then return owner:CallMethod("throw", 'Set the "UnregisterBindingDriver-target" frameref before calling UnregisterBindingDriver.') end
	local drivers = bindingDrivers[target]
	local driver = drivers and drivers[button]
	if driver then
		bindProxy:SetAttribute("state-" .. driver.id, nil)
		self:SetAttribute("frameref-RegisterStateDriver-frame", bindProxy)
		self:RunAttribute("RegisterStateDriver", driver.id, "")
		drivers[button], bindingDrivers[driver.id] = nil
		if not next(drivers) then
			bindingDrivers[target] = nil
		end
	end
]=])
core:SetAttribute("ComputeConditionalLock", [=[-- Kindred:ComputeConditionalLock("bind"[, clickButton, "modState"])
	local bind, clickButton, modState = ...
	if not modState then
		modState = modHoldMap[(IsLeftAltKeyDown() and 2 or 1) + (IsRightAltKeyDown() and 2 or 0)] ..
				   modHoldMap[(IsLeftShiftKeyDown() and 2 or 1) + (IsRightShiftKeyDown() and 2 or 0)] ..
				   modHoldMap[(IsLeftControlKeyDown() and 2 or 1) + (IsRightControlKeyDown() and 2 or 0)] ..
				   modHoldMap[(IsModifiedClick("LMETA-X") and 2 or 1) + (IsModifiedClick("RMETA-X") and 2 or 0)]
	end
	if clickButton == nil or clickButton == true then
		clickButton = SecureCmdOptionParse("[btn:1] 1; [btn:2] 2; [btn:3] 3; [btn:4] 4; [btn:5] 5; 1")
	end
	local lock = modState
	if bind and type(bind) == "string" then
		lock = lock:gsub("^(.)(.)(.)(.)", (bind:match("ALT%-") and "K" or "%1") .. (bind:match("SHIFT%-") and "K" or "%2") .. (bind:match("CTRL%-") and "K" or "%3") .. (bind:match("META%-") and "K" or "%4"))
	end
	return clickButton and (lock .. ">" .. clickButton) or lock, modState
]=])
core:SetAttribute("UnescapeCmdOptionsValue", [=[-- Kindred:UnescapeCmdOptionsValue("str"])
	local s = ...
	return s and rtgsub(s, "\\.", soEscapeSeqToLiteral)
]=])
core:SetAttribute("StartFuture", [=[-- Kindred:StartFuture(futureID)
	local futureID = ...
	fumOwner = futureID
	wipe(futureUnitMap)
]=])
core:SetAttribute("ReleaseFuture", [=[-- Kindred:ReleaseFuture(futureID)
	if fumOwner == ... then
		fumOwner = nil
		wipe(futureUnitMap)
	end
]=])
core:SetAttribute("SetFutureUnit", [=[-- Kindred:SetFutureUnit(futureID, "unit", "newunit")
	local futureID, unit, newunit = ...
	local fum = futureRemappableUnits[unit] and (_shadowFUM or futureID == fumOwner and futureUnitMap)
	if fum then
		local nu = newunit == "--clear" and "raid41" or self:RunAttribute("ResolveUnit", newunit, futureID)
		local ot = unit == "target" and (fum[unit] or "target")
		if ot and UnitExists(ot) then
			local react = SecureCmdOptionParse("[@" .. ot .. ",harm] --last-enemy-target; [@" .. ot .. ",help] --last-friend-target; --last-void-target")
			fum["--last-target"], fum[react] = ot, ot
		end
		fum[unit] = (nu == "raid41" or UnitExists(nu)) and nu or fum[unit] or nil
	end
]=])
core:SetAttribute("ResolveUnitAlias", [=[-- DEPRECATED Kindred:ResolveUnitAlias("unit")
	return self:RunAttribute("ResolveUnit", ..., nil)
]=])

core:SetAttribute("_onstate-lockdown", [[-- Kindred:SyncLockdownState
	if newstate ~= nil then
		isInLockdown = newstate
	end
	if isInLockdown then
		return
	end
	for k in pairs(cndInsecure) do
		if cndType[k] ~= "irun" then
			cndInsecure[k] = nil
		elseif cndDrivers[k] then
			owner:Run(RefreshDrivers, k)
		end
	end
]])
core:SetAttribute("_onstate-mod", [[-- Kindred:SyncModifierState
	if not newstate then return end
	newstate = newstate ~= "on" and 0 or 0
			 + (IsLeftAltKeyDown() and 1 or 0) + (IsRightAltKeyDown() and 2 or 0)
			 + (IsLeftShiftKeyDown() and 4 or 0) + (IsRightShiftKeyDown() and 8 or 0)
			 + (IsLeftControlKeyDown() and 16 or 0) + (IsRightControlKeyDown() and 32 or 0)
			 + (IsModifiedClick("LMETA-X") and 64 or 0) + (IsModifiedClick("RMETA-X") and 128 or 0)
	if newstate > 0 then
		self:SetAttribute("state-mod", nil)
	end
	if driverWatch[stateid][3] ~= newstate then
		driverWatch[stateid][3] = newstate
		owner:Run(RefreshDrivers, "mod")
	end
]])
core:SetAttribute("_onstate-bonusbar", [[-- Kindred:SyncBonusBarState
	if not newstate then return end
	if driverWatch[stateid][3] ~= newstate then
		driverWatch[stateid][3] = newstate
		owner:Run(RefreshDrivers, "bonusbar")
	end
]])
local function syncLockdown(e)
	-- Not a StateDriver: grace expires before SSDM updates
	core:SetAttribute("state-lockdown", e == "PLAYER_REGEN_DISABLED")
end
EV.PLAYER_REGEN_DISABLED, EV.PLAYER_REGEN_ENABLED = syncLockdown, syncLockdown
function core:throw(err)
	return error(err, 2)
end
local PackDefer, ClearDefer
do
	local execQueue, cPack = {}
	local function execPack()
		return KR[cPack[1]](KR, unpack(cPack, 3, 2 + cPack[2]))
	end
	function PackDefer(key, method, ...)
		execQueue[key] = {method, select("#", ...), ...}
	end
	function ClearDefer(key)
		if execQueue[key] then
			execQueue[key] = nil
		end
	end
	function EV:PLAYER_REGEN_ENABLED()
		for k, v in pairs(execQueue) do
			cPack, execQueue[k] = v, nil
			securecall(execPack)
		end
		cPack = nil
	end
end

local soEscapeSeqToLiteral = WR.GetBackingRestrictedTable(coreEnvW).soEscapeSeqToLiteral
local SetExternalShadow, RunShadowAttribute, WipeShadowFuture
do
	local ShadowEnvironment, ShadowRun
	do
		local fcache, _R, _ENV, _FRAME = {}, {
			next = rtable.next,
			pairs = rtable.pairs,
			newtable = function(...)
				return {...}
			end
		}, {}, {}
		local _shadow = {
			__index = function(t, k)
				local v = _ENV[t] and _ENV[t][k]
				if v == nil then
					v = _R[k] or _G[k]
				elseif type(v) == "userdata" then
					v = IsFrameHandle(v) and ShadowEnvironment(GetFrameHandleFrame(v)) or setmetatable({}, {
						__index = v
					})
					t[k] = v
				end
				return v
			end
		}
		function ShadowRun(self, f, ...)
			local v = fcache[f] or
						  loadstring(
					("-- shadow:%s\nreturn function(self, ...)\n%s\nend"):format(tostring(f):match("^[%s%-]*([^\n]*)"),
						f))()
			fcache[f] = setfenv(v, _ENV[self])
			return securecall(v, self, ...)
		end
		local function ShadowGetAttribute(self, ...)
			return _FRAME[self]:GetAttribute(...)
		end
		local function ShadowRunAttribute(self, a, ...)
			local c = _FRAME[self]:GetAttribute(a)
			return ShadowRun(self, c, ...)
		end
		function ShadowEnvironment(h)
			local e = _ENV[h] or setmetatable({
				owner = {
					Run = ShadowRun,
					GetAttribute = ShadowGetAttribute,
					RunAttribute = ShadowRunAttribute
				}
			}, _shadow)
			_ENV[h], _ENV[e], _ENV[e.owner], _FRAME[e.owner] = e, GetManagedEnvironment(h), e, h
			return e.owner, e
		end
	end
	local sFUM, _core, _env = {}, ShadowEnvironment(core)
	_env._shadowES, _env._shadowFUM = {}, sFUM
	function RunShadowAttribute(name, ...)
		return securecall(ShadowRun, _core, core:GetAttribute(name), ...)
	end
	function SetExternalShadow(name, func)
		_env._shadowES[name] = func
	end
	function core:irun(...)
		self:SetAttribute("irun-result", _env._shadowES[...](...))
	end
	function WipeShadowFuture()
		wipe(sFUM)
	end
end

function KR:ClearConditional(name)
	assert(type(name) == "string", 'Syntax: Kindred:ClearConditional("name")')
	if InCombatLockdown() or ClearDefer(name) then
		return PackDefer(name, "ClearConditional", name)
	end
	coreEnvW.cndAlias[name], coreEnvW.cndType[name], coreEnvW.cndState[name], coreEnvW.cndInsecure[name] = nil
	WR.Run(coreEnvW, coreEnvW.RefreshDrivers, name)
end
function KR:SetStateConditionalValue(name, value)
	if type(value) == "boolean" then
		value = value and "*" or ""
	end
	assert(type(name) == "string" and type(value) == "string",
		'Syntax: Kindred:SetStateConditionalValue("name", "value")')
	if InCombatLockdown() or ClearDefer(name) then
		return PackDefer(name, "SetStateConditionalValue", name, value)
	end
	WR.RunAttribute(coreEnvW, "UpdateStateConditional", name, value, "*")
end
function KR:SetThresholdConditionalValue(name, value)
	assert(type(name) == "string" and (value == false or type(value) == "number"),
		'Syntax: Kindred:SetThresholdConditionalValue("name", value or false)')
	if InCombatLockdown() or ClearDefer(name) then
		return PackDefer(name, "SetThresholdConditionalValue", name, value)
	end
	WR.RunAttribute(coreEnvW, "UpdateThresholdConditional", name, value)
end
function KR:SetStateConditionalDriver(name, driverOptionExpr, isFullyNative)
	assert(type(name) == "string" and type(driverOptionExpr) == "string",
		'Syntax: Kindred:SetStateConditionalDriver("name", "driverOptionExpr"[, isFullyNative])')
	if InCombatLockdown() or ClearDefer(name) then
		return PackDefer(name, "SetStateConditionalDriver", name, driverOptionExpr, isFullyNative)
	end
	WR.RunAttribute(coreEnvW, "SetStateConditionalDriver", name, driverOptionExpr, not not isFullyNative)
end
function KR:SetSecureExecConditional(name, snippet)
	assert(type(name) == "string" and type(snippet) == "string",
		'Syntax: Kindred:SetSecureExecConditional("name", "snippet")')
	if InCombatLockdown() or ClearDefer(name) then
		return PackDefer(name, "SetSecureExecConditional", name, snippet)
	end
	coreEnvW.cndType[name], coreEnvW.cndState[name] = "srun", snippet
	WR.Run(coreEnvW, coreEnvW.RefreshDrivers, name)
end
function KR:SetSecureExternalConditional(name, handler, hint)
	assert(type(name) == "string" and type(handler) == "table" and handler[0] and type(hint) == "function",
		'Syntax: Kindred:SetSecureExternalConditional("name", handlerFrame, hintFunc)')
	assert(
		handler.IsProtected and select(2, handler:IsProtected()) and handler:GetAttribute("EvaluateMacroConditional"),
		"Handler frame must be explicitly protected; must have EvaluateMacroConditional attribute set")
	if InCombatLockdown() then
		return PackDefer(name, "SetSecureExternalConditional", name, handler, hint)
	end
	coreEnvW.cndType[name], coreEnvW.cndState[name] = handler and "srun", handler
	WR.Run(coreEnvW, coreEnvW.RefreshDrivers, name)
	SetExternalShadow(name, hint)
end
function KR:SetNonSecureConditional(name, handler)
	assert(type(name) == "string" and type(handler) == "function",
		'Syntax: Kindred:SetNonSecureConditional("name", handlerFunc)')
	if InCombatLockdown() or ClearDefer(name) then
		return PackDefer(name, "SetNonSecureConditional", name, handler)
	end
	coreEnvW.cndType[name], coreEnvW.cndInsecure[name], coreEnvW.cndState[name] = "irun", true
	WR.Run(coreEnvW, coreEnvW.RefreshDrivers, name)
	SetExternalShadow(name, handler)
end
function KR:SetAliasConditional(name, aliasFor)
	assert(type(name) == "string" and type(aliasFor) == "string",
		'Syntax: Kindred:SetAliasConditional("name", "aliasFor")')
	if InCombatLockdown() or ClearDefer(name) then
		return PackDefer(name, "SetAliasConditional", name, aliasFor)
	end
	coreEnvW.cndAlias[name] = aliasFor
	WR.Run(coreEnvW, coreEnvW.RefreshDrivers, name)
end
function KR:SetAliasUnit(alias, unit)
	assert(type(alias) == "string" and (type(unit) == "string" or unit == nil),
		'Syntax: Kindred:SetAliasUnit("alias", "unit" or nil)')
	if InCombatLockdown() or ClearDefer("_alias-" .. alias) then
		return PackDefer("_alias-" .. alias, "SetAliasUnit", alias, unit)
	end
	WR.RunAttribute(coreEnvW, "SetAliasUnit", alias, unit)
end
function KR:PokeConditional(name)
	assert(type(name) == "string", 'Syntax: Kindred:PokeConditional("name")')
	if InCombatLockdown() or ClearDefer("_poke-" .. name) then
		return PackDefer("_poke-" .. name, "PokeConditional", name)
	end
	WR.Run(coreEnvW, coreEnvW.RefreshDrivers, name)
end

function KR:EvaluateCmdOptions(options, ...)
	return RunShadowAttribute("EvaluateCmdOptions", options, ...)
end
function KR:ResolveUnit(unit, futureID)
	return RunShadowAttribute("ResolveUnit", unit, futureID) or unit
end
function KR:UnescapeCmdOptionsValue(str)
	return str and rtgsub(str, "\\.", soEscapeSeqToLiteral)
end
function KR:SetFutureUnit(futureID, unit, newunit)
	return RunShadowAttribute("SetFutureUnit", futureID, unit, newunit)
end
function KR:ClearFuture(_futureID)
	WipeShadowFuture()
end

function KR:RegisterStateDriver(frame, state, values)
	assert(type(frame) == "table" and type(state) == "string" and (values == nil or type(values) == "string"),
		'Syntax: Kindred:RegisterStateDriver(frame, "state"[, "values"])')
	local dkey = "_sd-" .. #state .. ":" .. state .. tostring(frame)
	if InCombatLockdown() or ClearDefer(dkey) then
		return PackDefer(dkey, "RegisterStateDriver", frame, state, values)
	end
	core:SetFrameRef("RegisterStateDriver-frame", frame)
	WR.RunAttribute(coreEnvW, "RegisterStateDriver", state, values or "")
end
function KR:RegisterBindingDriver(target, button, options, priority, notify)
	assert(type(target) == "table" and type(button) == "string" and type(options) == "string",
		'Syntax: Kindred:RegisterBindingDriver(targetButton, "button", "options", priority, notifyFrame)')
	assert(not notify or type(notify) == "table" and notify:IsProtected(),
		"If specified, notifyFrame must be a protected frame.")
	assert(type(priority or 0) == "number", "Binding priority must be a number")
	local dkey = "_bd-" .. #button .. ":" .. button .. tostring(target)
	if InCombatLockdown() or ClearDefer(dkey) then
		return PackDefer(dkey, "RegisterBindingDriver", target, button, options, priority, notify)
	end
	core:SetOptFrameRef("RegisterBindingDriver-notify", notify)
	core:SetFrameRef("RegisterBindingDriver-target", target)
	WR.RunAttribute(coreEnvW, "RegisterBindingDriver", button, options, priority or 0)
end
function KR:UnregisterBindingDriver(target, button)
	assert(type(target) == "table" and type(button) == "string",
		'Syntax: Kindred:UnregisterBindingDriver(targetButton, "button")')
	local dkey = "_bd-" .. #button .. ":" .. button .. tostring(target)
	if InCombatLockdown() or ClearDefer(dkey) then
		return PackDefer(dkey, "UnregisterBindingDriver", target, button)
	end
	core:SetFrameRef("UnregisterBindingDriver-target", target)
	WR.RunAttribute(coreEnvW, "UnregisterBindingDriver", button)
end

function KR:seclib()
	return core
end
function KR:compatible(cmaj, crev)
	return (cmaj == MAJ and crev <= REV) and KR or nil, MAJ, REV
end

function KR:ResolveUnitAlias(unit) -- DEPRECATED
	return RunShadowAttribute("ResolveUnit", unit, nil) or unit
end

KR:SetAliasConditional("modifier", "mod")
KR:SetAliasConditional("button", "btn")

T.Kindred = {
	compatible = KR.compatible
}
