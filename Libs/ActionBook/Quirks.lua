local _, T = ...
if T.SkipLocalActionBook then
	return
end

local EV, KR = T.Evie, T.ActionBook:compatible("Kindred", 1, 26)
assert(EV and KR and 1, "Incompatible library bundle")

securecall(function() -- spec conditional sync
	local IsSpecInfoReady = T.compat.IsSpecInfoReady
	local function syncSpec()
		local group = C_Talent and C_Talent.GetActiveTalentGroup and IsSpecInfoReady() and C_Talent.GetActiveTalentGroup() or
						  GetActiveTalentGroup() or 1
		local maxPts, bestName = 0, nil
		for i = 1, GetNumTalentTabs() do
			local name, _, pts = GetTalentTabInfo(i)
			if pts and pts > maxPts then
				maxPts, bestName = pts, name
			end
		end
		local v = group .. (bestName and "/" .. bestName .. "/p" or "/s")
		KR:SetStateConditionalValue("spec", v)
	end
	function EV:PLAYER_TALENT_UPDATE()
		syncSpec()
	end
	EV.PLAYER_LOGIN = syncSpec
	EV.ACTIVE_TALENT_GROUP_CHANGED = syncSpec
	EV.PLAYER_TALENT_UPDATE_EX = syncSpec
end)
