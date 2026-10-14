local MAJ, REV, _, T = 2, 52, ...
if T.SkipLocalActionBook or T.ActionBook then
	return
end
local EV, WR = T.Evie, T.Ware
assert(EV and WR and 1, 'Incompatible library bundle')
local C_Widget = T.compat.C_Widget

local apiV, AB, ext, RWsec = {}, {}, {
	Kindred = T.Kindred
}, nil
apiV[MAJ], T.Kindred = AB

local function assert(condition, err, ...)
	return condition or error(tostring(err):format(...), 3)((0)[0])
end
local istore
do
	local function write(t, n, i, a, b, ...) -- overwrites by up to 1 element
		if n > 0 then
			t[i], t[i + 1] = a, b
			return write(t, n - 2, i + 2, ...)
		end
		return i + n - 1
	end
	local base, api, inner = newproxy(true), {}, setmetatable({}, {
		__mode = "k"
	})
	function istore()
		local r, d = newproxy(base), {
			[0] = 0
		}
		inner[r] = d
		return r
	end
	function api:reset()
		local h = inner[self]
		h[0] = 0, wipe(h)
	end
	function api:insert(...)
		local h, n = inner[self], select("#", ...)
		if n > 0 then
			local c = h[0]
			h[0], h[-c - 1] = c + 1, write(h, n, h[-c] + 1, ...)
		end
	end
	function api:filter(func, farg)
		local h, c, ni, first = inner[self], 0, 0, 0
		for i = 1, h[0] do
			local last = h[-i]
			if securecall(func, farg, unpack(h, first + 1, last)) then
				c, h[-c - 1] = c + 1, ni + last - first
				for j = 1, last == h[-c] and 0 or (last - first) do
					h[ni + j] = h[first + j]
				end
				ni = h[-c]
			end
			first = last
		end
		h[0] = c
	end
	function api:size()
		return inner[self][0]
	end
	function api:get(i)
		local h = inner[self]
		if i > 0 and h[-i] then
			return unpack(h, (i == 1 and 0 or h[-i + 1]) + 1, h[-i])
		end
	end
	local meta = getmetatable(base)
	meta.__index, meta.__len, meta.__call = api, api.size, api.get
end

local L
do
	local LT, LR = {}, newproxy(true)
	local function lookup(_, k, t)
		return LT[k] or t or k
	end
	local LM = getmetatable(LR)
	LM.__index, LM.__call, LM.__metatable = lookup, lookup, false
	T.ActionBook = {
		L = LR,
		LW = LT
	}
	L = T.ActionBook.L
end

local actionCallbacks, core = {}, CreateFrame("Frame", nil, nil, "SecureHandlerBaseTemplate")
local sabtHost = CreateFrame("Frame", nil, nil, "SecureFrameTemplate")
local coreEnvW, coreEnv = WR.GetRestrictedEnvironment(core)
do
	local re, newtable = coreEnvW, WR.newtable
	re._NIL, re.busy, re.idle = newtable, newtable, newtable
	re.collections, re.tokens, re.metadata = newtable, newtable, newtable
	re.actConditionals, re.tokConditionals = newtable, newtable
	re.actInfo, re.sidCastID = newtable, 30 + math.random(9)
	re.actInfo[re.sidCastID] = "psabt"
	sabtHost:SetAttribute("type-" .. re.sidCastID, "spell")
	re.colStack, re.idxStack, re.ecStack, re.etStack, re.onStack, re.outCount = newtable, newtable, newtable, newtable,
		newtable, newtable
	re.paNextID, re.paSlot, re.paLock, re.paCount = 36000, newtable, newtable, 0
	re.cndLockNext, re.cndLockMap, re.cndLockRes, re.cndLockCount = 36000, newtable, newtable, 0
	re.pendingNotify, re.nextNotifyId = newtable, 45000
	re.KR, re.sabtHost = ext.Kindred:compatible(1, 0):seclib(), sabtHost
	core:SetAttribute("execID", 1e3)
	local function uniqueName(s)
		local bni, bn = 1
		repeat
			bn, bni = "AB!" .. bni .. s, bni + 1
		until GetClickFrame(bn) == nil
		return bn
	end
	local RUNNER_ONCLICK_PRE = [=[-- AB:OnClick_Pre
		local paID = tonumber(button)
		local slot = paSlot[paID]
		local at = actInfo[slot]
		if not at then return end
		local at1, cndLock = type(at) == "table" and at[1], paLock[paID]
		owner:SetAttribute("execID", (tonumber((owner:GetAttribute("execID"))) or 0) % 2^42 + 1)
		if cndLock ~= nil then
			paLock[paID] = KR:GetAttribute("cndLock") or false
			KR:SetAttribute("cndLock", cndLock)
		end
		if at == "icall" then
			owner:CallMethod("icall", slot)
		elseif at == "psabt" then
			busy[self], idle[self] = paID
			self:SetAttribute("useparent*", true)
			return slot, "apr"
		elseif at1 == "recall" then
			busy[self], idle[self] = paID
			local m = at[2]:RunAttribute(select(3, unpack(at)))
			if type(m) == "string" and m ~= "" then
				self:SetAttribute("type", "macro")
				self:SetAttribute("macrotext", m)
				return nil, "rem"
			end
			idle[self], busy[self] = self:GetName()
		end
		cndLock = paLock[paID]
		if cndLock ~= nil then
			KR:SetAttribute("cndLock", cndLock or nil)
		end
		paCount, paLock[paID], paSlot[paID] = paCount - 1, nil, nil
		return false
	]=]
	local RUNNER_ONCLICK_POST = [=[-- AB:OnClick_Post
		local paID = busy[self]
		local cndLock, at = paLock[paID], actInfo[paSlot[paID]]
		idle[self], busy[self] = self:GetName()
		paCount, paLock[paID], paSlot[paID] = paCount - 1, nil, nil
		if message == "apr" then
			self:SetAttribute("useparent*", nil)
		elseif message == "rem" then
			self:SetAttribute("type", nil)
			self:SetAttribute("macrotext", nil)
		end
		if cndLock ~= nil then
			KR:SetAttribute("cndLock", cndLock or nil)
		end
	]=]
	for s in ("0123456789QWERTYUIOP"):gmatch(".") do
		local bn = uniqueName(s)
		local b = CreateFrame("Button", bn, sabtHost, "SecureActionButtonTemplate")
		core:WrapScript(b, "OnClick", RUNNER_ONCLICK_PRE, RUNNER_ONCLICK_POST)
		re.idle[b] = bn
	end
end
core:SetAttribute("GetCollectionContent", [[-- AB:GetCollectionContent(slot)
	local i, ret, root, col, idx, aid, ecol = 1, "", tonumber((...)) or 0
	wipe(outCount) wipe(onStack)
	colStack[i], idxStack[i], ecStack[i], etStack[i] = root, 1, nil, nil
	repeat
		col, idx, ecol = colStack[i], idxStack[i], ecStack[i]
		if idx == 1 and not outCount[col] then
			if outCount[col] == nil then
				self:CallMethod("notifyCollectionOpen", col)
			end
			if not ecol then
				onStack[col], outCount[col] = true, 0
			end
		end
		aid, idxStack[i] = collections[col][idx], idx + 1
		if aid then
			local tok = tokens[col][idx]
			local check1, check2 = actConditionals[aid], tokConditionals[tok]
			if (check1 == nil or KR:RunAttribute("EvaluateCmdOptions", check1) or "hide") ~= "hide" and
			   (check2 == nil or KR:RunAttribute("EvaluateCmdOptions", check2) or "hide") ~= "hide" then
				local isCollection, etok = collections[aid], etStack[i]
				local tem = isCollection and metadata["tokEmbed-" .. tok]
				local isEmbed = isCollection and (tem == nil and metadata["embed-" .. aid] or tem)
				if isEmbed then
					local canEmbed = true
					for j=1, i-1 do
						if colStack[j] == aid then
							canEmbed = false
							break
						end
					end
					if canEmbed then
						i, colStack[i+1], idxStack[i+1], ecStack[i+1], etStack[i+1] = i + 1, aid, 1, ecol or col, ":" .. (etok and tok .. etok or tok)
					end
				elseif isCollection and not outCount[aid] then
					i, idxStack[i], colStack[i+1], idxStack[i+1], ecStack[i+1], etStack[i+1] = i + 1, idx, aid, 1, false, nil
				elseif (outCount[aid] or 1) > 0 or onStack[aid] then
					local col = ecol or col
					local nid = outCount[col] + 1
					local pm = metadata["prMode-" .. tok] or 0
					local tok = etok and tok .. etok or tok
					ret = ret .. "\n" .. col .. " " .. nid .. " " .. aid .. " " .. tok .. " " .. pm
					outCount[col] = nid
				end
			end
		else
			if not ecol then
				onStack[col] = nil
				local openAction = (i == 1 or (outCount[col] or 0) > 0) and metadata["openAction-" .. col]
				if openAction then
					local openToken = metadata["openToken-" .. col] or ("AOOA::" .. col)
					local pm = openToken and metadata["prMode-" .. openToken] or 0
					ret = ret .. "\n" .. col .. " 0 " .. openAction .. " " .. openToken .. " " .. pm
					if collections[openAction] and not outCount[openAction] then
						i, colStack[i], idxStack[i], ecStack[i], etStack[i] = i + 1, openAction, 1, false, nil
					end
				end
			end
			i = i - 1
		end
	until i == 0
	return ret, metadata["openAction-" .. root] -- 2nd return is deprecated; use idx 0 actions in ret
]])
core:SetAttribute("UseAction", [[-- AB:UseAction(slot[, "cndLock"])
-- re.paNextID, re.paSlot, re.paLock, re.paCount
	local slot, cndLock = ...
	local at, paID, at1 = actInfo[slot], paNextID
	if not at then return "" end
	local at1, execIdMonitor = at[1], true
	if at1 == "macrotext" then
		return at[2], false
	else
		paNextID, paCount = (paNextID % 1e9) + 1, paCount + 1
		cndLock = type(cndLock) == "string" and cndLock or nil
		paLock[paID], paSlot[paID] = cndLock, slot
	end
	if at1 == "recall" then
		if cndLock then
			paLock[paID] = KR:GetAttribute("cndLock") or false
			KR:SetAttribute("cndLock", cndLock or nil)
		end
		local m, notifyKey = at[2]:RunAttribute(select(3, unpack(at)))
		if notifyKey then
			pendingNotify[nextNotifyId], notifyKey, nextNotifyId = newtable(notifyKey, at[2]), nextNotifyId, (nextNotifyId % 2^24) + 1
		end
		if cndLock then
			KR:SetAttribute("cndLock", paLock[paID] or nil)
			paCount, paLock[paID], paSlot[paID] = paCount - 1, nil, nil
		end
		return type(m) == "string" and m ~= "" and m or nil, false, notifyKey
	end
	local _, name = next(idle)
	return ("/click %s %d 1"):format(name, paID), true
]])
core:SetAttribute("NotifyPostUse", [[-- AB:NotifyPostUse("token")
	local ni = pendingNotify[...]
	pendingNotify[... or 0] = nil
	if ni[1] then
		ni[2]:RunAttribute("OnNotifyPostUse", ni[1])
	end
]])
core:SetAttribute("CastSpellByID", [[-- AB:CastSpellByID(sid[, "target"])
	local sid, unit = ...
	sabtHost:SetAttribute("spell-" .. sidCastID, sid)
	sabtHost:SetAttribute("unit-" .. sidCastID, unit)
	return self:RunAttribute("UseAction", sidCastID)
]])

function core:notifyCollectionOpen(id)
	AB:NotifyObservers("internal.collection.preopen", id)
end
function core:icall(id)
	local t = actionCallbacks[id]
	local ttype = type(t)
	if ttype == "table" then
		t[1](unpack(t, 3, t[2]))
	elseif ttype == "function" then
		t()
	end
end
local UnlockedCall
do
	local q, qn = {}, 1
	local function packcall(pack)
		return pack[1](unpack(pack, 3, pack[2])) and false
	end
	function EV:PLAYER_REGEN_ENABLED()
		local i = 1
		while i < qn do
			i, q[i] = i + 1, securecall(packcall, q[i]) or nil
		end
		qn = 1
	end
	local function pack(f, ...)
		qn, q[qn] = qn + 1, {f, 2 + select("#", ...), ...}
	end
	function UnlockedCall(f, ...)
		return ((InCombatLockdown() or qn > 1) and pack or securecall)(f, ...)
	end
end
local checkEntryToken, reserveEntryToken
do
	local etCollection, etIndex = {}, {}
	local rtKey, rtNS = {}, {}
	function checkEntryToken(tok, colId, newIdx)
		local c, r = etCollection[tok]
		if c and c ~= colId then
			return false
		end
		r, etCollection[tok], etIndex[tok] = etIndex[tok], colId, newIdx
		return r or newIdx
	end
	function reserveEntryToken(tok, colId, ns, key)
		local c = etCollection[tok]
		if c then
			return c == colId
		end
		local rk, rn = rtKey[tok], rtNS[tok]
		if rk == nil then
			rtKey[tok], rtNS[tok] = key, ns
			return true
		end
		return rk == key and rn == ns
	end
end

local actionCreators, actionDescribers, actionFlags, actionNumArgs, categories = {}, {}, {}, {}, {}
local nextActionId, allocatedActions, allocatedActionType, allocatedActionArg = 42, {}, {}, {}

local createHandlers, updateHandlers = {}, {}
local function re_set_actInfo_attribute(id, count, ...)
	coreEnvW.actInfo[id] = "psabt"
	for i = 1, count, 2 do
		local an, av = select(i, ...)
		sabtHost:SetAttribute("*" .. an .. "-" .. id, av)
	end
end
function createHandlers.attribute(id, cnt, ...)
	UnlockedCall(re_set_actInfo_attribute, id, cnt, ...)
	return true
end
local function re_set_actInfo_icall(id)
	coreEnvW.actInfo[id] = "icall"
end
function createHandlers.func(id, cnt, func, ...)
	if type(func) ~= "function" then
		return false, "Callback expected, got %s", type(func)
	end
	UnlockedCall(re_set_actInfo_icall, id)
	actionCallbacks[id] = cnt > 1 and {func, cnt + 1, ...} or func
	return true
end
function createHandlers.recall(id, _count, handle, attr, ...)
	if not C_Widget.IsFrameWidget(handle) or type(attr) ~= "string" then
		return false, "Frame handle, attribute method expected; got %s/%s", type(handle), type(attr)
	elseif not select(2, handle:IsProtected()) then
		return false, "Callback frame must be explicitly protected"
	elseif type(handle:GetAttribute(attr)) ~= "string" then
		return false, "Callback snippet expected in attribute %q, got %s", attr, type(handle:GetAttribute(attr))
	end
	UnlockedCall(WR.newtable, coreEnvW.actInfo, id, "recall", handle, attr, ...)
	return true
end
function createHandlers.macrotext(id, _cnt, mt)
	if type(mt) ~= "string" then
		return false, "macrotext: string expected, got %s", type(mt)
	end
	UnlockedCall(WR.newtable, coreEnvW.actInfo, id, "macrotext", mt)
	return true
end
function createHandlers.reslash(id, _cnt, slash, varg, target)
	if type(slash) ~= "string" then
		return false, "reslash: command string expected, got %s", type(slash)
	elseif varg ~= nil and type(varg) ~= "string" then
		return false, "reslash: message string expected, got %s", type(varg)
	elseif target ~= nil and type(target) ~= "string" then
		return false, "reslash: target string expected, got %s", type(target)
	elseif not RWsec then
		return false, "reslash: Rewire not available"
	end
	return createHandlers.recall(id, target and 5 or 4, RWsec, "RunSlashCmd", slash, varg or "",
		select(target and 1 or 2, target))
end
function createHandlers.retext(id, _cnt, retext)
	if type(retext) ~= "string" then
		return false, "retext: string expected, got %s", type(retext)
	elseif not RWsec then
		return false, "retext: Rewire not available"
	end
	return createHandlers.recall(id, 5, RWsec, "RunMacro", retext, false, true)
end
local function re_set_collection(id, pack)
	local nc, nt = WR.newtable(coreEnvW.collections, id), WR.newtable(coreEnvW.tokens, id)
	local m, v = coreEnvW.metadata, coreEnvW.tokConditionals
	local openToken = pack.__openToken
	for i = 1, #pack do
		local tok = pack[i]
		local vkey, ekey, pkey = '__visibility-' .. tok, '__embed-' .. tok, '__pmode-' .. tok
		nt[i], nc[i], v[tok] = tok, pack[tok], pack[vkey]
		m["tokEmbed-" .. tok], m["prMode-" .. tok] = pack[ekey], pack[pkey]
	end
	m['embed-' .. id] = pack.__embed
	m['openAction-' .. id], m['openToken-' .. id] = pack.__openAction, openToken
	if openToken then
		m['prMode-' .. openToken] = pack.__openPresent
	end
end
function updateHandlers.collection(id, _count, idList)
	if not (type(idList) == "table") then
		return false, "Expected table specifying collection actions, got %q", type(idList)
	elseif idList.__openAction and not allocatedActions[idList.__openAction] then
		return false, "Collection __openAction key does not specify a valid action"
	end
	local pack = {}
	for i = 1, #idList do
		local tok = idList[i]
		if type(tok) ~= "string" then
			return false, "Collection entry #%d: unsupported entry token type (%s)", i, type(tok)
		end
		local vkey, ekey, pkey = '__visibility-' .. tok, '__embed-' .. tok, '__pmode-' .. tok
		local aid, vis, emb, pmode = idList[tok], idList[vkey], idList[ekey], idList[pkey]
		if not tok:match("^[A-Za-z][A-Za-z0-9_=/]*$") then
			return false, "Collection entry #%d: improper entry token format (%s)", i, tok
		elseif allocatedActions[aid] == nil then
			return false, "Collection entry #%d: unallocated action id (%s:%s)", i, type(idList[i]), tostring(idList[i])
		elseif vis ~= nil and type(vis) ~= "string" then
			return false, "Collection entry #%d: improper visibility conditional type (%s)", i, type(vis)
		elseif emb ~= nil and type(emb) ~= "boolean" then
			return false, "Collection entry #%d: improper embed flag type (%s)", i, type(emb)
		elseif pmode ~= nil and (type(pmode) ~= "number" or pmode % 1 > 0 or pmode < 0) then
			return false, "Collection entry #%d: improper presentation mode type"
		end
		local uqi = checkEntryToken(tok, id, i)
		if not uqi then
			return false, "Collection entry #%d: entry token not globally unique (%s)", i, tok
		elseif uqi ~= i and idList[uqi] == tok then
			return false, "Collection entry #%d: entry token not locally unique (%s)", i, tok
		end
		pack[i], pack[tok], pack[vkey], pack[ekey], pack[pkey] = tok, aid, vis, emb, pmode and (pmode + 1 - pmode % 2)
	end
	local openAction, openToken, openPresent = idList.__openAction, idList.__openToken, idList.__openPresent
	local embed = idList.__embed
	if openPresent == nil and openAction and type(openToken) == "string" then
		openPresent = idList['__pmode-' .. openToken]
	end
	if openAction == nil then
		openToken, openPresent = nil, nil
	elseif type(openAction) ~= "number" or not allocatedActions[openAction] then
		return false, "Collection on-open: invalid action id (%s:%s)", type(openAction), tostring(openAction)
	elseif openToken == nil then
		openToken = "AOOA::" .. id
	elseif type(openToken) ~= "string" or not openToken:match("^[A-Za-z][A-Za-z0-9_=/]*$") then
		return false, "Collection on-open: invalid token format (%s)", tostring(openToken)
	end
	if openAction == nil then
	elseif openPresent ~= nil and (type(openPresent) ~= "number" or openPresent % 1 > 0 or openPresent < 0) then
		return false, "Collection on-open: invalid presentation mode (%s)", tostring(openPresent)
	elseif embed ~= nil and type(embed) ~= "boolean" then
		return false, "Collection embed flag invalid"
	end
	pack.__openAction, pack.__openToken, pack.__openPresent = openAction, openToken, openPresent
	pack.__embed = embed
	UnlockedCall(re_set_collection, id, pack)
	return true
end
local function re_set_actInfo_clone(id, id2)
	coreEnvW.actInfo[id], coreEnvW.actConditionals[id] = coreEnvW.actInfo[id2], coreEnvW.actConditionals[id2]
end
function createHandlers.clone(id, _count, id2)
	UnlockedCall(re_set_actInfo_clone, id, id2)
	return true
end
local function nullInfoFunc()
	return false
end
local function re_set_actConditional(id, cnd)
	coreEnvW.actConditionals[id] = cnd
end

local getActionIdent, getActionArgs
do
	function getActionIdent(identTable)
		local itt = type(identTable)
		if itt == "string" then
			return identTable, nil
		elseif itt == "table" and type(identTable[1]) == "string" then
			return identTable[1], identTable
		end
	end
	local function private_unpack(t, a, b)
		if a <= b then
			return t[a], private_unpack(t, a + 1, b)
		end
	end
	function getActionArgs(it, ...)
		if it then
			return private_unpack(it, 2, 1 + (actionNumArgs[it[1]] or 1))
		end
		return ...
	end
end
local categoryAliases = {}
local function getCategoryName(id)
	local LM = id == (#categories + 1) and L "Miscellaneous"
	return categories[id] or (LM and categories[LM] and LM) or nil
end
local function getCategoryTable(name)
	name = categoryAliases[name] or name
	local r = categories[name]
	if not r then
		r = {}
		categories[name] = r
		if name ~= L "Miscellaneous" then
			categories[#categories + 1] = name
		end
	end
	return r
end
local function getActionDescription(q, ident, at, ...)
	local df = actionDescribers[ident]
	if df == nil then
	elseif actionFlags[ident] == 1 then
		return df(q, getActionArgs(at, ...))
	else
		return df(getActionArgs(at, ...))
	end
end

local editorPanels, createEditorHost = {}
do
	local copyActionKeys, clearActionKeys
	do
		local function copy(t, copies)
			local into = {}
			copies = copies or {}
			copies[t] = into
			for k, v in pairs(t) do
				k = type(k) == "table" and (copies[k] or copy(k, copies)) or k
				v = type(v) == "table" and (copies[v] or copy(v, copies)) or v
				into[k] = v
			end
			return into, copies
		end
		local function copyKeys(src, dst, lib, n, k, ...)
			if n == 0 then
				return dst
			end
			local v = src and src[k]
			if lib and lib[v] ~= nil then
				v = lib[v]
			elseif type(v) == "table" then
				v, lib = copy(v, lib)
			end
			dst[k] = v
			return copyKeys(src, dst, lib, n - 1, ...)
		end
		local function prefixCount(...)
			return select("#", ...), ...
		end
		local function allActionKeys(src, ak)
			local nk = next(src, ak)
			if nk == nil then
				return
			elseif type(nk) == "number" then
				return nk, allActionKeys(src, nk)
			end
			return allActionKeys(src, nk)
		end
		function copyActionKeys(src, dst)
			return copyKeys(src, dst, nil, prefixCount(allActionKeys(src)))
		end
		function clearActionKeys(dst)
			copyKeys(nil, dst, nil, prefixCount(allActionKeys(dst)))
		end
	end
	local hdata, hhproto = {}, newproxy(true)
	do
		local hhapi, m = {}, getmetatable(hhproto)
		m.__index, m.__metatable = hhapi, false
		local function pmcall(s, m, ...)
			return true, s[m](s, ...)
		end
		function hhapi:SetAction(actionTable)
			assert(type(actionTable) == "table", 'Syntax: ok = hh:SetAction(actionTable)')
			local d, ed = hdata[self], editorPanels[actionTable[1]]
			if not ed then
				return
			end
			local oed, oaction = d.editor, d.action
			d.editor, d.action = nil
			d.rq:Hide()
			if oed and oed ~= ed then
				securecall(oed.Release, oed, d.host)
			end
			--[[ There's a fair bit of copying involved here to avoid sharing table
				 references between the host and the editor panel. This serves to
				 protect both parties from each other. The host's copy cannot be
				 modified by the editor except when the host explicitly requests that
				 via :GetAction (limited to the action's option keys!). The copy the
				 editor panel receives is in principle solely its own, although other
				 code could call SetAction directly (with arbitrary arguments). ]]
			local edCopy = copyActionKeys(actionTable, {})
			if not securecall(pmcall, ed, "SetAction", d.host, edCopy) then
				securecall(ed.Release, ed, d.host)
				return false
			end
			d.editor = ed
			--[[ Keep a separate copy in case the editor is stolen from the host without
				 a :OnEditorRelease notification. When reacquiring the editor panel, it
				 is safe to keep the copy we're restoring from -- barring shenanigans,
				 it is immutable. ]]
			d.action = oaction == actionTable and oaction or copyActionKeys(actionTable, {})
			return true
		end
		function hhapi:GetAction(into)
			assert(type(into) == "table", 'Syntax: intoTable? = hh:GetAction(intoTable)')
			local d, src = hdata[self]
			if d.editor and d.editor:IsOwned(d.host) then
				src = {}
				d.editor:GetAction(src)
				d.action = copyActionKeys(src, {})
			elseif d.action then
				src = d.action
			end
			if src and actionCreators[src[1]] then
				clearActionKeys(into)
				copyActionKeys(src, into)
				return into
			end
		end
		function hhapi:Clear()
			local d = hdata[self]
			local ed = d.editor
			d.editor, d.action = nil
			d.rq:Hide()
			if ed then
				securecall(ed.Release, ed, d.host)
			end
		end
		function hhapi:IsCurrentEditor(ed)
			local d = hdata[self]
			return ed and ed == d.editor and ed:IsOwned(d.host) and true or false
		end
		function hhapi:GetTabFocusWidget(which)
			local d = hdata[self]
			local ed = d.editor
			return ed and type(ed.GetTabFocusWidget) == "function" and ed:IsOwned(d.host) and
					   ed:GetTabFocusWidget(which) or nil
		end
	end
	local function hf_OnEditorRelease(hf, ed)
		local d = hdata[hf]
		if ed and ed == d.editor then
			local ac = {}
			ed:GetAction(ac)
			d.action = copyActionKeys(ac, {})
			d.editor = nil
			d.rq:Show()
		end
	end
	local function hf_OnReaquireClick(self)
		local d = hdata[self:GetParent()]
		PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
		if d.action then
			d.hh:SetAction(d.action)
			local w = d.hh:GetTabFocusWidget(0)
			if w then
				w:SetFocus()
			end
		end
	end
	function createEditorHost(parent)
		local hf = CreateFrame("Frame", nil, parent)
		do
			hf.OnEditorRelease = hf_OnEditorRelease
		end
		local rq = CreateFrame("Button", nil, hf, "UIPanelButtonTemplate")
		do
			rq:Hide()
			rq:SetSize(30, 26)
			rq:SetPoint("CENTER")
			if T.TenSettings then
				T.TenSettings:StyleButton(rq)
			end
			local ico = rq:CreateTexture(nil, "ARTWORK")
			ico:SetSize(13, 13)
			ico:SetPoint("CENTER")
			ico:SetTexture("Interface\\Buttons\\UI-RotationRight-Button-Up")
			ico:SetVertexColor(0.78, 0.80, 0.84)
			rq:SetScript("OnClick", hf_OnReaquireClick)
		end
		local hd, hh = {
			host = hf,
			hh = 0,
			rq = rq
		}, newproxy(hhproto)
		hd.hh = hh
		hdata[hh], hdata[hf] = hd, hd
		return hf, hh
	end
end
do -- AB:CreateToken()
	local seq, dict, dictLength, prefix = 262143, "qwer1tyui2opas3dfgh4jklz5xcvb6nmQWE7RTYU8IOPA9SDFG0HJKL=ZXCV/BNM", 64
	local function encode(n)
		local ret, d = ""
		repeat
			d = n % dictLength
			ret, n = dict:sub(d + 1, d + 1) .. ret, (n - d) / dictLength
		until n == 0
		return ret
	end
	function AB:CreateToken()
		if seq > 262142 then
			prefix, seq = "ABu" .. encode(time() * 100 + (math.floor(GetTime() * 100) % 100)), 0
		end
		seq = seq + 1
		return prefix .. encode(seq)
	end
end
function AB:ReserveToken(token, ns, key, collectionID)
	assert(key ~= nil and (collectionID == nil or type(collectionID) == "number"),
		'Syntax: ok = ActionBook:ReserveToken("token", ns, key, collectionID or nil)')
	if type(token) ~= "string" or not token:match("^[A-Za-z][A-Za-z0-9_=/]*$") then
		return false, 'unacceptable-token'
	end
	return reserveEntryToken(token, collectionID, ns, key)
end

function AB:GetActionSlot(actionType, ...)
	local ident, at = getActionIdent(actionType)
	local id = actionCreators[ident] and actionCreators[ident](getActionArgs(at, ...))
	if allocatedActions[id] then
		return id
	end
	assert(ident, 'Syntax: actionId = ActionBook:GetActionSlot(actionTable or "actionType", ...)')
end
function AB:GetActionDescription(actionType, ...)
	local ident, at = getActionIdent(actionType)
	assert(ident,
		'Syntax: typeName, actionName, icon, ext, tipFunc, tipArg, actionType, actionFlags = ActionBook:GetActionDescription(actionTable or "actionType", ...)')
	return getActionDescription(nil, ident, at, ...)
end
function AB:GetActionNumArgs(actionType)
	local ident = getActionIdent(actionType) or
					  error('Syntax: numArgs? = ActionBook:GetActionNumArgs(actionTable or "actionType")', 2)
	return actionNumArgs[ident]
end
function AB:GetActionListDescription(actionType, ...)
	local ident, at = getActionIdent(actionType)
	assert(ident,
		'Syntax: typeName, actionName, icon, ext, tipFunc, tipArg, actionType = ActionBook:GetActionListDescription(actionTable or "actionType", ...)')
	return getActionDescription("list-query", ident, at, ...)
end
function AB:GetSlotInfo(id, cndLock)
	assert(type(id) == "number" and (cndLock == nil or type(cndLock) == "string"),
		'Syntax: usable, state, icon, caption, count, cdLeft, cdLength, tipFunc, tipArg, ext = ActionBook:GetSlotInfo(slot, "cndLockState"?)')
	if allocatedActions[id] then
		return allocatedActions[id](allocatedActionArg[id], cndLock)
	end
end
function AB:GetSlotImplementation(id)
	assert(type(id) == "number",
		"Syntax: actionType, colEntryCount, colEmbedDefault = ActionBook:GetSlotImplementation(slot)")
	local aType = allocatedActions[id] and allocatedActionType[id]
	local colData = coreEnv.collections[id]
	return aType, colData and #colData or nil, colData and coreEnv.metadata['embed-' .. id]
end

function AB:RegisterActionType(actionType, create, describe, numArgs, useListDescribe)
	assert(type(actionType) == "string" and type(create) == "function" and type(describe) == "function" and
			   type(numArgs) == "number" and (numArgs >= 0 and numArgs % 1 == 0) and
			   (useListDescribe == nil or type(useListDescribe) == "boolean"),
		'Syntax: ActionBook:RegisterActionType("actionType", createFunc, describeFunc, numArgs, useListDescribe?)')
	assert(not actionCreators[actionType], "Identifier %q is already registered", actionType)
	actionCreators[actionType], actionDescribers[actionType], actionFlags[actionType] = create, describe,
		useListDescribe and 1 or nil
	actionNumArgs[actionType] = numArgs
end
function AB:CreateActionSlot(infoFunc, infoArg, implType, ...)
	local as, an = 1, select("#", ...)
	local cnd
	if implType == "conditional" then
		as, an, cnd, implType = as + 2, an - 2, select(as, ...)
		assert(type(cnd) == "string", "Conditional options expected, got %s", type(cnd))
	end
	assert(type(implType) == "string" and (infoFunc == nil or type(infoFunc) == "function"),
		'Syntax: slot = ActionBook:CreateAction(infoFunc, infoArg, "implType", ...)')
	local cf, id = assert(createHandlers[implType] or updateHandlers[implType],
		"Implementation type %q is not creatable", implType), nextActionId
	nextActionId, allocatedActionType[id], allocatedActionArg[id] = id + 1, implType, infoArg
	assert(cf(id, an, select(as, ...)))
	allocatedActions[id] = infoFunc or nullInfoFunc
	if cnd then
		UnlockedCall(re_set_actConditional, id, cnd)
	end
	return id
end
function AB:UpdateActionSlot(id, ...)
	assert(type(id) == "number", "Syntax: ActionBook:UpdateActionSlot(slot, ...)")
	local at = assert(allocatedActionType[id], "Action %d does not exist", id)
	local uf = assert(updateHandlers[at], "Action type %q is not updatable", at)
	assert(uf(id, select("#", ...), ...))
end

function AB:AddCategoryAlias(name, aliasOf)
	assert(type(name) == "string" and type(aliasOf) == "string",
		'Syntax: ActionBook:AddCategoryAlias("name", "aliasOf")')
	assert(name == aliasOf or categories[name] == nil, "Category %q already exists.", name)
	categoryAliases[name] = categoryAliases[name] or aliasOf
end
function AB:AugmentCategory(name, augFunc)
	assert(type(name) == "string" and type(augFunc) == "function" and name ~= "*",
		'Syntax: ActionBook:AugmentCategory("name", augFunc)')
	table.insert(getCategoryTable(name), augFunc)
end
function AB:AddActionToCategory(name, actionType, ...)
	assert(type(name) == "string" and type(actionType) == "string" and name ~= "*",
		'Syntax: ActionBook:AddActionToCategory("name", "actionType"[, ...])')
	local ct = getCategoryTable(name)
	ct.extra = ct.extra or istore()
	ct.extra:insert(actionType, ...)
end
function AB:GetNumCategories()
	return #categories + (categories[L "Miscellaneous"] and 1 or 0)
end
function AB:GetCategoryInfo(id)
	assert(type(id) == "number", 'Syntax: name = ActionBook:GetCategoryInfo(index)')
	return getCategoryName(id)
end
function AB:GetCategoryContents(id, into)
	assert(type(id) == "number", 'Syntax: contents = ActionBook:GetCategoryContents(index[, into])')
	local cname, ret = assert(getCategoryName(id), 'Invalid category index'), into or istore()
	local co = categories[cname]
	local ex, addToRet = co.extra, #co > 0 and function(...)
		return ret:insert(...)
	end
	for i = 1, #co do
		securecall(co[i], cname, addToRet)
	end
	for i = 1, ex and #ex or 0 do
		ret:insert(ex(i))
	end
	return ret
end

local notifyCount, observers = 1, {
	["*"] = {},
	["internal.collection.preopen"] = {}
}
function AB:NotifyObservers(ident, data)
	assert(type(ident) == "string", 'Syntax: ActionBook:NotifyObservers("identifier"[, data])')
	assert(actionCreators[ident] or observers[ident] ~= nil, "Identifier %q is not registered", ident)
	notifyCount = (notifyCount + 1) % 4503599627370495
	for i = (ident == "*" or not observers[ident]) and 1 or 2, 1, -1 do
		for k, v in pairs(observers[i == 1 and "*" or ident]) do
			securecall(k, v, ident, data)
		end
	end
end
function AB:AddObserver(ident, callback, selfarg)
	assert(type(ident) == "string" and type(callback) == "function",
		'Syntax: ActionBook:AddObserver("identifier", callbackFunc, callbackSelfArg)')
	assert(ident == "*" or actionCreators[ident] or observers[ident], "Identifier %q is not registered", ident)
	if observers[ident] == nil then
		observers[ident] = {}
	end
	observers[ident][callback] = selfarg == nil and true or selfarg
end
function AB:GetLastObserverUpdateToken(ident)
	assert(type(ident) == "string", 'Syntax: token = ActionBook:GetLastObserverUpdateToken("identifier")')
	assert(ident == "*" or actionCreators[ident], "Identifier %q is not registered", ident)
	return notifyCount
end

function AB:RegisterEditorPanel(actionType, editorPanel)
	assert(type(actionType) == "string" and type(editorPanel) == "table",
		'Syntax: ActionBook:RegisterEditorPanel("actionType", editorPanel)')
	assert(actionCreators[actionType] ~= nil, "actionType %q is not registered", actionType)
	assert(editorPanels[actionType] == nil, "An editor for %q is already registered", actionType)
	assert(type(editorPanel.SetAction) == "function" and type(editorPanel.GetAction) == "function" and
			   type(editorPanel.IsOwned) == "function" and type(editorPanel.Release) == "function",
		"Required editor panel API methods not implemented")
	editorPanels[actionType] = editorPanel
end

function AB:seclib()
	return core
end
function AB:compatible(module, maj, rev, ...)
	if ext[module] then
		return ext[module]:compatible(maj, rev, ...)
	elseif type(module) == "number" and type(maj) == "number" and rev == nil then
		maj, rev = module, maj -- Oh hey, it's us!
		return rev <= REV and apiV[maj], MAJ, REV
	end
end

-- HIDDEN, UNSUPPORTED METHODS: May vanish at any time.
local hum = {
	L = L
}
setmetatable(AB, {
	__index = hum
})
hum.HUM = hum
function hum:CreateEditorHost(parent)
	assert(type(parent) == "table" and parent[0], 'Syntax: hostWidget = ActionBook:CreateEditorHost(parent)')
	return createEditorHost(parent)
end
function hum:RegisterModule(key, api)
	assert(type(key) == "string" and type(api) == "table" and type(api.compatible) == "function",
		'Syntax: ActionBook:RegisterModule("key", apiTable)')
	assert(ext[key] == nil, 'Duplicate module registration')
	ext[key] = api
	if key == "Rewire" then
		local RW = api:compatible(1, 34)
		RWsec = RW and RW:seclib()
		coreEnvW.RW = RWsec
	end
end

T.ActionBook.compatible, ext.ActionBook = AB.compatible, T.ActionBook
