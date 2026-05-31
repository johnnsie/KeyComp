local _, ns = ...

-- =========================================================================
-- Recommend: per-removal-type "who can bring this" hint text, shown on the
-- Coverage status-icon tooltips when a type isn't covered. The proactive
-- comp/recruit builder was removed by design — which applicants to invite is
-- the player's call as the group fills.
-- =========================================================================

local Rec = {}
ns.Recommend = Rec

Rec.providerText = {
    magic     = "Disc/Holy Priest / Resto Dru / MW Monk / Resto Sham / Holy Pal / Pres Evoker",
    disease   = "Priest / Paladin / Monk / Evoker",
    curse     = "Mage / Druid / Resto Sham / Evoker",
    poison    = "Druid / Monk / Paladin / Evoker",
    bleed     = "Evoker (Cauterizing Flame)",
    soothe    = "Hunter / Druid / Rogue / Evoker",
    purge     = "Priest / Shaman / Mage / Hunter / DH / Warlock",
    shortkick = "Warrior / DK / Rogue / Pal / Monk / DH / Mage / Hunter / Ele-Enh Sham / Feral-Guard Dru",
}
