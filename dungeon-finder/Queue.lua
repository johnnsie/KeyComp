local _, ns = ...

-- =========================================================================
-- Queue: the auto-apply engine. The whole point for a non-meta seeker -- keep a
-- handful of applications pending at once, refill as they decline/expire, blacklist
-- anyone who declines so we move on, and STOP + alarm the moment a group invites you.
--
--   Start()/Stop()  - arm/disarm the queue
--   Tick()          - called ~3s by Core: kick a search, then ProcessResults()
--   ProcessResults()- filter+rank current listings, then auto-apply ONE top match
--                     (one per pass keeps us under the server's apply throttle)
--   Sync()          - read application statuses: detect invited (win) / declined
--   ApplyManual(r)  - a row's Apply button (hardware-event apply; always allowed)
--
-- CAVEAT: scripted C_LFGList.ApplyToGroup is the one piece that can't be verified
-- without a live client. If Blizzard rate-limits or blocks auto-applies, the manual
-- Apply buttons on the Listings tab still work click-by-click.
-- =========================================================================

local Q = {}
ns.Queue = Q

Q.active = false
Q.startedAt = 0
Q.stats = { searched = 0, matched = 0, applied = 0, declined = 0, invited = 0 }
Q.applied = {}      -- resultID -> appliedAt (GetTime)
Q.leaderOf = {}     -- resultID -> leaderName (so we can blacklist on decline)
Q.blacklist = {}    -- leaderName -> expiry (GetTime)
Q.log = {}          -- recent activity, newest first: { t, ts, msg }
Q.matched = {}      -- last ranked matched list (for the UI)
Q.lastApplyAt = 0
Q.invitedBy = nil   -- leader of a pending invite we're holding (nil = none)
Q.invitedID = nil   -- resultID/appID of that invite, so we can watch how it resolves

local APPLY_CD = 2.5          -- min seconds between auto-applies (throttle guard)
local REAPPLY_GUARD = 90      -- don't re-apply to the same resultID within this

local function gt() return (GetTime and GetTime()) or 0 end

local INVITED  = { invited = true, inviteaccepted = true }
local DECLINED = { declined = true, declined_full = true, declined_delisted = true,
                   cancelled = true, timedout = true, failed = true }

function Q:Note(msg)
    local stamp = (date and date("%H:%M:%S")) or ""
    table.insert(self.log, 1, { t = gt(), ts = stamp, msg = msg })
    for i = #self.log, 17, -1 do self.log[i] = nil end
end

function Q:Role() return ns.Filter:Role() end

function Q:MyScore()
    if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
        local ok, v = pcall(C_ChallengeMode.GetOverallDungeonScore)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local ok, s = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, "player")
        if ok and type(s) == "table" and type(s.currentSeasonScore) == "number"
            and s.currentSeasonScore > 0 then
            return s.currentSeasonScore
        end
    end
    return 0
end

function Q:Ctx()
    local n = gt()
    for name, exp in pairs(self.blacklist) do
        if exp <= n then self.blacklist[name] = nil end
    end
    return { myScore = self:MyScore(), blacklist = self.blacklist }
end

-- id, status, pendingStatus from GetApplicationInfo (table on modern builds,
-- positional on older ones) -- mirrors KeyComp's defensive read on the host side.
function Q:AppStatus(resultID)
    if not (C_LFGList and C_LFGList.GetApplicationInfo) then return resultID, nil end
    local ok, a, b, c = pcall(C_LFGList.GetApplicationInfo, resultID)
    if not ok then return resultID, nil end
    if type(a) == "table" then
        return a.searchResultID or resultID,
               a.applicationStatus or a.status,
               a.pendingApplicationStatus or a.pendingStatus
    end
    return a or resultID, b, c
end

function Q:StatusOf(resultID)
    local _, status = self:AppStatus(resultID)
    return status
end

function Q:Pending()
    if not (C_LFGList and C_LFGList.GetApplications) then return 0 end
    local ok, apps = pcall(C_LFGList.GetApplications)
    if not ok or type(apps) ~= "table" then return 0 end
    local pending = 0
    for _, appID in ipairs(apps) do
        local _, status = self:AppStatus(appID)
        if status == "applied" then pending = pending + 1 end
    end
    return pending
end

-- Drive the invite lifecycle from application statuses. A bare invite is NOT terminal
-- anymore -- we HOLD (alarm once, keep the queue armed) so turning the invite down picks
-- the search right back up where it left off:
--   invited        -> hold + alarm; one-tap apply is paused until you resolve it
--   inviteaccepted -> you joined the group: stop (the win)
--   invitedeclined -> YOU declined the invite: resume searching, skip that leader a while
--   declined/etc.  -> THEY declined or it expired: free the slot (+blacklist real declines)
-- A watchdog also resumes if the invite simply vanishes (withdrawn/expired, or you
-- declined and the client dropped the entry) and you didn't end up grouped.
function Q:Sync()
    if not (C_LFGList and C_LFGList.GetApplications) then return end
    local ok, apps = pcall(C_LFGList.GetApplications)
    if not ok or type(apps) ~= "table" then return end
    local mins = (ns.db and ns.db.blacklistMins) or 10
    local holding = false
    for _, appID in ipairs(apps) do
        -- only applications WE sent since Start -- ignore pre-existing/external ones
        if self.applied[appID] then
            local _, status, pending = self:AppStatus(appID)
            -- a resolved state in either field beats the neutral "applied"/"none"
            local eff = status
            if (eff == nil or eff == "applied" or eff == "none")
                and pending and pending ~= "applied" and pending ~= "none" then
                eff = pending
            end
            local leader = self.leaderOf[appID] or "a group"

            if eff == "inviteaccepted" then
                self:Note("Joined " .. leader .. "'s group -- nice!")
                self:Stop("joined " .. leader)              -- clears the hold + disarms
                return
            elseif eff == "invited" then
                if self.active then
                    holding = true
                    if self.invitedID ~= appID then         -- a NEW invite -> alarm once
                        self.invitedBy = leader
                        self.invitedID = appID
                        self.stats.invited = self.stats.invited + 1
                        self:Note("INVITED by " .. leader ..
                            " -- accept it, or decline to keep searching")
                        self:Alert(leader)
                    end
                end
            elseif eff == "invitedeclined" then             -- YOU declined the invite
                self.blacklist[leader] = gt() + mins * 60
                if self.invitedID == appID then self.invitedBy = nil; self.invitedID = nil end
                self.applied[appID] = nil; self.leaderOf[appID] = nil
                self:Note("You declined " .. leader .. " -- searching again")
            elseif DECLINED[eff or ""] then                 -- THEY declined / it expired
                if eff == "declined" or eff == "declined_full" then
                    self.blacklist[leader] = gt() + mins * 60
                    self.stats.declined = self.stats.declined + 1
                    self:Note("Declined by " .. leader .. " -- skipping " .. mins .. "m")
                end
                if self.invitedID == appID then self.invitedBy = nil; self.invitedID = nil end
                self.applied[appID] = nil; self.leaderOf[appID] = nil
            end
        end
    end

    -- watchdog: holding an invite that's gone from the list this pass -> if you're now
    -- grouped it's a win, otherwise the invite was withdrawn/declined -> resume the search.
    if self.active and self.invitedBy and not holding then
        local who = self.invitedBy
        if GetNumGroupMembers and GetNumGroupMembers() >= 2 then
            self:Note("Joined " .. who .. "'s group -- nice!")
            self:Stop("joined " .. who)
        else
            self.invitedBy = nil; self.invitedID = nil
            self:Note("Invite from " .. who .. " gone -- searching again")
        end
    end
end

function Q:Alert(leader)
    if PlaySound then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960, "Master")
    end
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        pcall(RaidNotice_AddMessage, RaidWarningFrame,
            "KeyQueue: INVITED by " .. (leader or "a group") .. " -- accept!",
            ChatTypeInfo["RAID_WARNING"])
    end
    if ns.UI and ns.UI.FlashInvite then ns.UI:FlashInvite() end
end

-- the apply primitive. Defensive about the ApplyToGroup signature.
function Q:Apply(r)
    if not (C_LFGList and C_LFGList.ApplyToGroup and r and r.resultID) then return false end
    local role = self:Role()
    local tank, heal, dps = role == "TANK", role == "HEALER", role == "DAMAGER"
    local ok = pcall(C_LFGList.ApplyToGroup, r.resultID, tank, heal, dps)
    if not ok then ok = pcall(C_LFGList.ApplyToGroup, r.resultID) end
    if ok then
        self.applied[r.resultID] = gt()
        self.leaderOf[r.resultID] = r.leaderName
        self.lastApplyAt = gt()
        -- optional: whisper your pitch to the leader (retail PGF has no native
        -- applicant note). Off by default -- it can trip WoW's whisper-spam squelch
        -- if it fires on many groups quickly.
        local note = ns.db and ns.db.note
        if ns.db and ns.db.whisperNote and note and note ~= "" and r.leaderName and SendChatMessage then
            pcall(SendChatMessage, note, "WHISPER", nil, r.leaderName)
        end
        -- verify ~1s later that the server actually recorded the application. pcall
        -- returning ok does NOT mean it worked (a blocked protected call also "ok"s).
        if C_Timer then
            local rid, who = r.resultID, (r.leaderName or "?")
            local label = "+" .. (r.keyLevel or "?") .. " " .. (r.abbr or "M+")
            C_Timer.After(1.0, function()
                local _, st = self:AppStatus(rid)
                if st == "applied" or INVITED[st or ""] then
                    self.stats.applied = self.stats.applied + 1   -- count only CONFIRMED applies
                    self:Note("Applied to " .. label .. " -- " .. who)
                else
                    self:Note("DID NOT register: " .. label .. " -- " .. who ..
                        " (status " .. tostring(st) .. ") -- blocked by Blizzard")
                end
                if ns.UI then ns.UI:Refresh() end
            end)
        end
    end
    return ok
end

-- The strict key gate, shared by one-tap AND the Listings row buttons so they agree:
-- a readable key must be in your target range; a group whose key we CAN'T read (+?) is
-- refused unless you explicitly opt in (Settings -> "Apply to listings with no readable
-- +key"). This is what stops the addon from ever signing you to an off-target key.
function Q:Eligible(r, c)
    c = c or ns.Filter:Criteria()
    if not (r and r.resultID) then return false, "bad" end
    if r.keyLevel then
        if r.keyLevel < c.minKey or r.keyLevel > c.maxKey then return false, "key" end
        return true
    end
    if ns.db and ns.db.includeUnknownKey then return true end
    return false, "unknown-key"
end

-- Apply to the current top match. MUST be called from a hardware event (keybind or
-- a real button click) -- scripted applies from the timer are blocked by Blizzard.
-- Recomputes matches fresh so the "next best" is always current.
function Q:ApplyNext()
    if InCombatLockdown and InCombatLockdown() then
        self:Note("Can't apply while in combat"); if ns.UI then ns.UI:Refresh() end
        return false
    end
    -- a pending invite is a decision point: don't fire more applications until you've
    -- accepted it (you're done) or declined it (Sync resumes the search).
    if self.invitedBy then
        self:Note("Invite from " .. self.invitedBy ..
            " is pending -- accept it, or decline it to keep searching")
        if ns.UI then ns.UI:Refresh() end
        return false
    end
    if not self.active then self:Start() end   -- so invites/declines get tracked
    local c = ns.Filter:Criteria()
    local matched = ns.Filter:Apply(ns.Search:Read(), c, self:Ctx())
    self.matched = matched
    -- ONE tap fills all your open slots (up to maxPending). All these ApplyToGroup
    -- calls run inside this single hardware event, so they're allowed (a timer can't).
    -- STRICT: only apply to a group whose key we can VERIFY is in range, so we never
    -- auto-apply to a +11/+12 we couldn't read. Unreadable-key groups are skipped
    -- (apply to those by clicking their row, or enable includeUnknownKey).
    local cap = (ns.db and ns.db.maxPending) or 5
    local pending = self:Pending()
    local fired, skipped = 0, 0
    for _, r in ipairs(matched) do
        if pending + fired >= cap then break end
        local eligible = self:Eligible(r, c)
        if eligible then
            local status = self:StatusOf(r.resultID)
            local already = status == "applied" or INVITED[status or ""]
            local recent = self.applied[r.resultID] and (gt() - self.applied[r.resultID]) < REAPPLY_GUARD
            if not already and not recent then
                if self:Apply(r) then fired = fired + 1 end
            end
        elseif not r.keyLevel then
            skipped = skipped + 1
        end
    end
    if fired > 0 then
        self:Note("Fired " .. fired .. " +" .. c.minKey .. " application(s) -- confirming\226\128\166")
    elseif skipped > 0 then
        self:Note(skipped .. " group(s) have no readable +" .. c.minKey .. " in the title -- " ..
            "click a row's Apply if you've checked it, or enable 'no readable +key' in Settings")
    else
        self:Note("No new +" .. c.minKey .. " groups to apply to right now")
    end
    if ns.UI then ns.UI:Refresh() end
    return fired > 0
end

-- a Listings-tab Apply button (real click). Apply() handles the confirm + count.
function Q:ApplyManual(r)
    -- a row's Apply is a deliberate, manual click -- you can see the group in Blizzard's
    -- UI, so it applies even when KeyQueue can't read the key ("+?"). The only thing it
    -- refuses is a key we CAN read that's outside your range (you didn't mean that one).
    -- The automatic one-tap (Queue:ApplyNext) stays strict; this is the manual override.
    if r and r.keyLevel then
        local c = ns.Filter:Criteria()
        if r.keyLevel < c.minKey or r.keyLevel > c.maxKey then
            self:Note("Skipped " .. (r.abbr or "that group") .. " +" .. r.keyLevel ..
                " -- outside your +" .. c.minKey .. (c.maxKey ~= c.minKey and ("-" .. c.maxKey) or "") .. " range")
            if ns.UI then ns.UI:Refresh() end
            return false
        end
    end
    local applied = self:Apply(r)
    if ns.UI then ns.UI:Refresh() end
    return applied
end

function Q:Start()
    self.active = true
    self.invitedBy = nil
    self.invitedID = nil
    self.startedAt = gt()
    self.stats = { searched = 0, matched = 0, applied = 0, declined = 0, invited = 0 }
    -- fresh slate: we only react to invites/declines for applications WE send from
    -- now on, never to whatever pre-existing/stale applications the server reports
    -- (that caused a phantom "invited" the instant you pressed Start).
    self.applied = {}
    self.leaderOf = {}
    local c = ns.Filter:Criteria()
    local dn = 0
    if c.dungeons then for _ in pairs(c.dungeons) do dn = dn + 1 end else dn = #ns.Dungeons.order end
    local keyStr = "+" .. c.minKey .. (c.maxKey ~= c.minKey and ("-" .. c.maxKey) or "")
    self:Note("Queue started -- " .. self:Role() .. ", " .. keyStr .. ", " .. dn .. " dungeons" ..
        ((ns.db and ns.db.autoApply) and "" or " (auto-apply OFF)"))
    ns.Search:Kick()
    if ns.UI then ns.UI:Refresh() end
end

function Q:Stop(reason)
    if not self.active then return end
    self.active = false
    self.invitedBy = nil
    self.invitedID = nil
    self:Note("Queue stopped" .. (reason and (" -- " .. reason) or ""))
    if ns.UI then ns.UI:Refresh() end
end

function Q:Toggle()
    if self.active then self:Stop("toggled off") else self:Start() end
end

-- filter + rank the current listings; if armed + auto-apply, apply one top match.
function Q:ProcessResults()
    local results = ns.Search:Read()
    local c = ns.Filter:Criteria()
    local ctx = self:Ctx()
    local matched, reasons = ns.Filter:Evaluate(results, c, ctx)
    self.matched = matched
    self.stats.searched = #results
    self.stats.matched = #matched
    if not self.active then return end

    self:Sync()
    if self.invitedBy then return end

    -- never a silent "0 matched": print why (throttled) so the blocker is obvious.
    -- Includes how many listings parsed to your exact target key and a real sample's
    -- role counts -- that distinguishes "key not parsing" from "no healer slot".
    if #matched == 0 and #results > 0 and (gt() - (self.lastDiag or 0)) > 12 then
        self.lastDiag = gt()
        -- full picture in one line: what key levels are listed (so we can see if your
        -- target is even up), why each was dropped, and your score vs the gates.
        local hist = {}
        for _, r in ipairs(results) do
            local k = r.keyLevel or 0
            hist[k] = (hist[k] or 0) + 1
        end
        local levels = {}
        for k in pairs(hist) do levels[#levels + 1] = k end
        table.sort(levels)
        local hs = {}
        for _, k in ipairs(levels) do
            hs[#hs + 1] = (k == 0 and "?" or ("+" .. k)) .. "x" .. hist[k]
        end
        local drop = {}
        for k, v in pairs(reasons) do drop[#drop + 1] = k .. " " .. v end
        print(("|cff66ccffKeyQueue|r %d found | keys: %s | drop: %s | yourScore=%d | want +%d-%d"):format(
            #results, table.concat(hs, " "), table.concat(drop, " "),
            ctx.myScore or 0, c.minKey, c.maxKey))
    end

    -- We do NOT apply from here. Scripted ApplyToGroup from a timer is blocked by
    -- Blizzard: pcall still returns "ok" but NO application is created (exactly the
    -- "applied climbs, pending stays 0" symptom). Applying must come from a hardware
    -- event -- the keybind or the "Apply to next best" button -> Queue:ApplyNext.
end

function Q:Tick()
    if not self.active then return end
    if GetNumGroupMembers and GetNumGroupMembers() >= 5 then
        self:Stop("group is full")
        return
    end
    -- if you're advertising your own listing, you can't apply to others; idle.
    if C_LFGList and C_LFGList.HasActiveEntry and C_LFGList.HasActiveEntry() then
        return
    end
    -- only run our own search if opted in -- otherwise it overwrites the filter you
    -- set in Blizzard's Group Finder. By default we just read what your PGF shows.
    if ns.db and ns.db.autoRefresh ~= false then pcall(function() ns.Search:Refresh() end) end
    self:ProcessResults()
end
