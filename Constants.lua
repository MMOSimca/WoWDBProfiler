-----------------------------------------------------------------------
-- Upvalued Lua API.
-----------------------------------------------------------------------
local _G = getfenv(0)

local bit = _G.bit


-----------------------------------------------------------------------
-- AddOn namespace.
-----------------------------------------------------------------------
local ADDON_NAME, private = ...


-----------------------------------------------------------------------
-- Boss/Loot Data Constants.
-----------------------------------------------------------------------
-- Map of Alliance Logging NPC Summon spells to all possible Timber objectIDs of the proper tree size
private.LOGGING_SPELL_ID_TO_OBJECT_ID_MAP = {
    [167902] = 234021,
    [167969] = 234022,
    [168201] = 234023,
}
-- Account for Horde spell IDs
private.LOGGING_SPELL_ID_TO_OBJECT_ID_MAP[167961] = private.LOGGING_SPELL_ID_TO_OBJECT_ID_MAP[167902]
private.LOGGING_SPELL_ID_TO_OBJECT_ID_MAP[168043] = private.LOGGING_SPELL_ID_TO_OBJECT_ID_MAP[167969]
private.LOGGING_SPELL_ID_TO_OBJECT_ID_MAP[168200] = private.LOGGING_SPELL_ID_TO_OBJECT_ID_MAP[168201]

-- Map of Garrison Cache object names to Garrison Cache object IDs
private.GARRISON_CACHE_OBJECT_NAME_TO_OBJECT_ID_MAP = {
    ["Garrison Cache"] = 236916,
    ["Full Garrison Cache"] = 237722,
    ["Hefty Garrison Cache"] = 237723,
}
private.GARRISON_CACHE_LOOT_SOURCE_ID = 10

-- Mapping of items that, when right-clicked, fire a spell (which can fail, so we have to check success).
-- They reward loot via loot toast popups upon completion of that spell.
-- SHOW_LOOT_TOAST can be used to track loot.
private.LOOT_TOAST_CONTAINER_SPELL_ID_TO_ITEM_ID_MAP = {
    [142397] = 98134, -- Heroic Cache of Treasures
    [142901] = 98546, -- Bulging Heroic Cache of Treasures
    [143506] = 98095, -- Brawler's Pet Supplies
    [143507] = 94207, -- Fabled Pandaren Pet Supplies
    [143508] = 89125, -- Sack of Pet Supplies
    [143509] = 93146, -- Pandaren Spirit Pet Supplies
    [143510] = 93147, -- Pandaren Spirit Pet Supplies
    [143511] = 93149, -- Pandaren Spirit Pet Supplies
    [143512] = 93148, -- Pandaren Spirit Pet Supplies
    [146885] = 103535, -- Bulging Bag of Charms
    [147598] = 104014, -- Pouch of Timeless Coins
    [149222] = 105911, -- Pouch of Enduring Wisdom
    [149223] = 105912, -- Oversized Pouch of Enduring Wisdom
    [171513] = 116414, -- Pet Supplies
    [175767] = 118697, -- Big Bag of Pet Supplies
    [178508] = 120321, -- Mystery Bag
}

-- Mapping of items that, when right-clicked, fire a spell (which can fail, so we have to check success).
-- They reward loot upon completion of that spell.
-- CHAT_MSG_LOOT -must- be used to track loot, which is definitely not ideal.
private.DELAYED_CONTAINER_SPELL_ID_TO_ITEM_ID_MAP = {
    [168178] = 114116, -- Bag of Salvaged Goods
    [168179] = 114119, -- Crate of Salvage
    [168180] = 114120, -- Big Crate of Salvage
}

-- List of items that, when right-clicked, reward loot (includes items from DELAYED_CONTAINER_SPELL_ID_TO_ITEM_ID_MAP).
-- This means they -must- be tracked via CHAT_MSG_LOOT.
-- It also means there is a high margin for bad data since multiple bags can be clicked within a small time frame.
-- True = instant cast; false = cast time
private.CONTAINER_ITEM_ID_LIST = {
    [114116] = false, -- Bag of Salvaged Goods
    [114119] = false, -- Crate of Salvage
    [114120] = false, -- Big Crate of Salvage
    [116980] = true, -- Invader's Forgotten Treasure
    [120319] = true, -- Invader's Damaged Cache
    [120320] = true, -- Invader's Abandoned Sack
}

private.RAID_BOSS_BONUS_SPELL_ID_TO_NPC_ID_MAP = {
    -----------------------------------------------------------------------
    -- World Bosses
    -----------------------------------------------------------------------
    [132205] = 60491, -- Sha of Anger Bonus (Sha of Anger)
    [132206] = 62346, -- Galleon Bonus (Galleon)
    [136381] = 69099, -- Nalak Bonus (Nalak)
    [137554] = 69161, -- Oondasta Bonus (Oondasta)
    [148317] = 71952, -- Celestials Bonus (Chi-Ji)
    [148316] = 72057, -- Ordos Bonus (Ordos)
    [178847] = 81252, -- Drov Bonus (Drov the Ruiner)
    [178849] = 81535, -- Tarlna Bonus (Tarlna the Ageless)
    [178851] = 83746, -- Rukhmar Bonus (Rukhmar)

    -----------------------------------------------------------------------
    -- Blackrock Foundry
    -----------------------------------------------------------------------
    [177529] = 76877, -- Gruul Bonus (Gruul)
    [177530] = 77182, -- Oregorger Bonus (Oregorger)
    [177531] = 76809, -- Blast Furnace (Foreman Feldspar)
    [177533] = 76973, -- Hans'gar & Franzok Bonus (Hans'gar)
    [177534] = 76814, -- Flamebender Ka'graz Bonus (Flamebender Ka'graz)
    [177535] = 77692, -- Kromog Bonus (Kromog)
    [177536] = 76865, -- Beastlord Darmac Bonus (Beastlord Darmac)
    [177537] = 76906, -- Operator Thogar Bonus (Operator Thogar)
    [177538] = 77557, -- The Iron Maidens Bonus (Admiral Gar'an)
    [177539] = 77325, -- Blackhand Bonus (Blackhand)

    -----------------------------------------------------------------------
    -- Highmaul
    -----------------------------------------------------------------------
    [177521] = 78714, -- Kargath Bladefist Bonus (Kargath Bladefist)
    [177522] = 77404, -- Butcher Bonus (The Butcher)
    [177523] = 78948, -- Tectus Bonus (Tectus)
    [177524] = 78491, -- Brackenspore Bonus (Brackenspore)
    [177525] = 78237, -- Twin Ogron Bonus (Phemos)
    [177526] = 79015, -- Ko'ragh Bonus (Ko'ragh)
    [177528] = 77428, -- Imperator Mar'gok Bonus (Imperator Mar'gok)

    -----------------------------------------------------------------------
    -- Mists of Pandaria
    -----------------------------------------------------------------------
    [125144] = 59915, -- Stone Guard Bonus (Jasper Guardian)
    [132189] = 60009, -- Feng the Accursed Bonus (Feng the Accursed)
    [132190] = 60143, -- Gara'jal the Spiritbinder Bonus (Gara'jal the Spiritbinder)
    [132191] = 60709, -- Spirit Kings Bonus (Qiang the Merciless)
    [132192] = 60410, -- Elegon Bonus (Elegon)
    [132193] = 60399, -- Will of the Emperor Bonus (Qin-xi)
    [132200] = 60583, -- Protectors of the Endless Bonus (Protector Kaolan)
    [132204] = 60583, -- Protectors of the Endless (Elite) Bonus (Protector Kaolan)
    [132201] = 62442, -- Tsulong Bonus (Tsulong)
    [132202] = 62983, -- Lei Shi Bonus (Lei Shi)
    [132203] = 60999, -- Sha of Fear Bonus (Sha of Fear)
    [132194] = 62980, -- Imperial Vizier Zor'lok Bonus (Imperial Vizier Zor'lok)
    [132195] = 62543, -- Blade Lord Tay'ak Bonus (Blade Lord Ta'yak)
    [132196] = 62164, -- Garalon Bonus (Garalon)
    [132197] = 62397, -- Wind Lord Mel'jarak Bonus (Wind Lord Mel'jarak)
    [132198] = 62511, -- Amber-Shaper Un'sok Bonus (Amber-Shaper Un'sok)
    [132199] = 62837, -- Grand Empress Shek'zeer Bonus (Grand Empress Shek'zeer)
    [139674] = 69465, -- Jin'rokh the Breaker Bonus (Jin'rokh the Breaker)
    [139677] = 68476, -- Horridon Bonus (Horridon)
    [139679] = 69078, -- Zandalari Troll Council Bonus (Sul the Sandcrawler)
    [139680] = 67977, -- Tortos Bonus (Tortos)
    [139682] = 68065, -- Magaera Bonus (Megaera)
    [139684] = 69712, -- Ji'kun, the Ancient Mother Bonus (Ji-Kun)
    [139686] = 68036, -- Durumu the Forgotten Bonus (Durumu the Forgotten)
    [139687] = 69017, -- Primordious Bonus (Primordius)
    [139688] = 69427, -- Dark Animus Bonus (Dark Animus)
    [139689] = 68078, -- Iron Qon Bonus (Iron Qon)
    [139690] = 68904, -- The Empyreal Queens Bonus (Suen)
    [139691] = 68397, -- Lei Shen, The Thunder King Bonus (Lei Shen)
    [139692] = 69473, -- Ra-den Bonus (Ra-den)
    [145909] = 71543, -- Immerseus Bonus (Immerseus)
    [145910] = 71475, -- Fallen Protectors Bonus (Rook Stonetoe)
    [145911] = 72276, -- Norushen Bonus (Amalgam of Corruption)
    [145912] = 71734, -- Sha of Pride Bonus (Sha of Pride)
    [145913] = 72249, -- Galakras Bonus (Galakras)
    [145914] = 71466, -- Iron Juggernaut Bonus (Iron Juggernaut)
    [145915] = 71859, -- Dark Shaman Bonus (Earthbreaker Haromm)
    [145916] = 71515, -- General Nazgrim Bonus (General Nazgrim)
    [145917] = 71454, -- Malkorok Bonus (Malkorok)
    [145919] = 71889, -- Spoils of Pandaria Bonus (Secured Stockpile of Pandaren Spoils)
    [145920] = 71529, -- Thok the Bloodthirsty Bonus (Thok the Bloodthirsty)
    [145918] = 71504, -- Siegecrafter Blackfuse Bonus (Siegecrafter Blackfuse)
    [145921] = 71161, -- Klaxxi Paragons Bonus (Kil'ruk the Wind-Reaver)
    [145922] = 71865, -- Garrosh Hellscream Bonus (Garrosh Hellscream)
}


-----------------------------------------------------------------------
-- Fundamental Constants.
-----------------------------------------------------------------------
private.wow_version, private.build_num = _G.GetBuildInfo()
private.region = GetCVar("portal"):sub(0,2):upper()
-- PTR/Beta return "public-test", but they are properly called "XX"
if private.region == "PU" then private.region = "XX" end

private.UNIT_TYPES = {
    PLAYER = "Player",
    OBJECT = "GameObject",
    UNKNOWN = "Unknown",
    NPC = "Creature",
    PET = "Pet",
    VEHICLE = "Vehicle",
    ITEM = "Item",
}

private.UNIT_TYPE_NAMES = {
    ["Player"] = "PLAYER",
    ["GameObject"] = "OBJECT",
    ["Unknown"] = "UNKNOWN",
    ["Creature"] = "NPC",
    ["Pet"] = "PET",
    ["Vehicle"] = "VEHICLE",
    ["Item"] = "ITEM",
}

private.ACTION_TYPE_FLAGS = {
    ITEM = 0x00000001,
    NPC = 0x00000002,
    OBJECT = 0x00000004,
    ZONE = 0x00000008,
}

private.ACTION_TYPE_NAMES = {}

for name, bit in _G.pairs(private.ACTION_TYPE_FLAGS) do
    private.ACTION_TYPE_NAMES[bit] = name
end

private.SPELL_LABELS_BY_NAME = {
    [_G.GetSpellInfo(13262)] = "DISENCHANT",
    [_G.GetSpellInfo(4036)] = "ENGINEERING",
    [_G.GetSpellInfo(30427)] = "EXTRACT_GAS",
    [_G.GetSpellInfo(131476)] = "FISHING",
    [_G.GetSpellInfo(2366)] = "HERB_GATHERING",
    [_G.GetSpellInfo(51005)] = "MILLING",
    [_G.GetSpellInfo(605)] = "MIND_CONTROL",
    [_G.GetSpellInfo(2575)] = "MINING",
    [_G.GetSpellInfo(3365)] = "OPENING",
    [_G.GetSpellInfo(921)] = "PICK_POCKET",
    [_G.GetSpellInfo(31252)] = "PROSPECTING",
    [_G.GetSpellInfo(73979)] = "SEARCHING_FOR_ARTIFACTS",
    [_G.GetSpellInfo(8613)] = "SKINNING",
}

private.NON_LOOT_SPELL_LABELS = {
    MIND_CONTROL = true,
}

local AF = private.ACTION_TYPE_FLAGS

private.SPELL_FLAGS_BY_LABEL = {
    DISENCHANT = AF.ITEM,
    ENGINEERING = AF.NPC,
    EXTRACT_GAS = AF.ZONE,
    FISHING = AF.ZONE,
    HERB_GATHERING = bit.bor(AF.NPC, AF.OBJECT),
    MILLING = AF.ITEM,
    MIND_CONTROL = AF.NPC,
    MINING = bit.bor(AF.NPC, AF.OBJECT),
    OPENING = AF.OBJECT,
    PICK_POCKET = AF.NPC,
    PROSPECTING = AF.ITEM,
    SEARCHING_FOR_ARTIFACTS = AF.OBJECT,
    SKINNING = AF.NPC,
}


-----------------------------------------------------------------------
-- Faction/Reputation Data Constants.
-----------------------------------------------------------------------

private.FACTION_DATA = {
    -- Used only for private.REP_BUFFS
    ARGENT_CRUSADE = { 1106, _G.GetFactionInfoByID(1106) },
    BILGEWATER_CARTEL = { 1133, _G.GetFactionInfoByID(1133) },
    CENARION_CIRCLE = { 609, _G.GetFactionInfoByID(609) },
    DARKSPEAR = { 530, _G.GetFactionInfoByID(530) },
    DARNASSUS = { 69, _G.GetFactionInfoByID(69) },
    DRAGONMAW_CLAN = { 1172, _G.GetFactionInfoByID(1172) },
    EARTHEN_RING = { 1135, _G.GetFactionInfoByID(1135) },
    EBON_BLADE = { 1098, _G.GetFactionInfoByID(1098) },
    EXODAR = { 930, _G.GetFactionInfoByID(930) },
    GILNEAS = { 1134, _G.GetFactionInfoByID(1134) },
    GNOMEREGAN = { 54, _G.GetFactionInfoByID(54) },
    GUARDIANS_OF_HYJAL = { 1158, _G.GetFactionInfoByID(1158) },
    GUILD = { 1168, _G.GetFactionInfoByID(1168) },
    HONOR_HOLD = { 946, _G.GetFactionInfoByID(946) },
    HUOJIN = { 1352, _G.GetFactionInfoByID(1352) },
    IRONFORGE = { 47, _G.GetFactionInfoByID(47) },
    KIRIN_TOR = { 1090, _G.GetFactionInfoByID(1090) },
    ORGRIMMAR = { 76, _G.GetFactionInfoByID(76) },
    RAMKAHEN = { 1173, _G.GetFactionInfoByID(1173) },
    SHATAR = { 935, _G.GetFactionInfoByID(935) },
    SILVERMOON = { 911, _G.GetFactionInfoByID(911) },
    STORMWIND = { 72, _G.GetFactionInfoByID(72) },
    THERAZANE = { 1171, _G.GetFactionInfoByID(1171) },
    THRALLMAR = { 947, _G.GetFactionInfoByID(947) },
    THUNDER_BLUFF = { 81, _G.GetFactionInfoByID(81) },
    TUSHUI = { 1353, _G.GetFactionInfoByID(1353) },
    UNDERCITY = { 68, _G.GetFactionInfoByID(68) },
    WILDHAMMER_CLAN = { 1174, _G.GetFactionInfoByID(1174) },
    WYRMREST_ACCORD = { 1091, _G.GetFactionInfoByID(1091) },
    -- Commendation Factions
    ANGLERS = { 1302, _G.GetFactionInfoByID(1302) },
    AUGUST_CELESTIALS = { 1341, _G.GetFactionInfoByID(1341) },
    DOMINANCE_OFFENSIVE = { 1375, _G.GetFactionInfoByID(1375) },
    GOLDEN_LOTUS = { 1269, _G.GetFactionInfoByID(1269) },
    KIRIN_TOR_OFFENSIVE = { 1387, _G.GetFactionInfoByID(1387) },
    KLAXXI = { 1337, _G.GetFactionInfoByID(1337) },
    LOREWALKERS = { 1345, _G.GetFactionInfoByID(1345) },
    OPERATION_SHIELDWALL = { 1376, _G.GetFactionInfoByID(1376) },
    ORDER_OF_THE_CLOUD_SERPENTS = { 1271, _G.GetFactionInfoByID(1271) },
    SHADO_PAN = { 1270, _G.GetFactionInfoByID(1270) },
    SHADO_PAN_ASSAULT = { 1435, _G.GetFactionInfoByID(1435) },
    SUNREAVER_ONSLAUGHT = { 1388, _G.GetFactionInfoByID(1388) },
    TILLERS = { 1272, _G.GetFactionInfoByID(1272) },
}

private.REP_BUFFS = {
    -- Tabard Buffs
    [_G.GetSpellInfo(93830)] = { -- BILGEWATER CARTEL TABARD
        faction = private.FACTION_DATA.BILGEWATER_CARTEL[2],
        ignore = true,
    },
    [_G.GetSpellInfo(93827)] = { -- DARKSPEAR TABARD
        faction = private.FACTION_DATA.DARKSPEAR[2],
        ignore = true,
    },
    [_G.GetSpellInfo(93806)] = { -- DARNASSUS TABARD
        faction = private.FACTION_DATA.DARNASSUS[2],
        ignore = true,
    },
    [_G.GetSpellInfo(93811)] = { -- EXODAR TABARD
        faction = private.FACTION_DATA.EXODAR[2],
        ignore = true,
    },
    [_G.GetSpellInfo(93816)] = { -- GILNEAS TABARD
        faction = private.FACTION_DATA.GILNEAS[2],
        ignore = true,
    },
    [_G.GetSpellInfo(93821)] = { -- GNOMEREGAN TABARD
        faction = private.FACTION_DATA.GNOMEREGAN[2],
        ignore = true,
    },
    [_G.GetSpellInfo(126436)] = { -- HUOJIN TABARD
        faction = private.FACTION_DATA.HUOJIN[2],
        ignore = true,
    },
    [_G.GetSpellInfo(97340)] = { -- ILLUSTRIOUS GUILD TABARD
        faction = private.FACTION_DATA.GUILD[2],
        modifier = 1,
    },
    [_G.GetSpellInfo(93805)] = { -- IRONFORGE TABARD
        faction = private.FACTION_DATA.IRONFORGE[2],
        ignore = true,
    },
    [_G.GetSpellInfo(93825)] = { -- ORGRIMMAR TABARD
        faction = private.FACTION_DATA.ORGRIMMAR[2],
        ignore = true,
    },
    [_G.GetSpellInfo(97341)] = { -- RENOWNED GUILD TABARD
        faction = private.FACTION_DATA.GUILD[2],
        modifier = 0.5,
    },
    [_G.GetSpellInfo(93828)] = { -- SILVERMOON CITY TABARD
        faction = private.FACTION_DATA.SILVERMOON[2],
        ignore = true,
    },
    [_G.GetSpellInfo(93795)] = { -- STORMWIND TABARD
        faction = private.FACTION_DATA.STORMWIND[2],
        ignore = true,
    },
    [_G.GetSpellInfo(93337)] = { -- TABARD OF RAMKAHEN
        faction = private.FACTION_DATA.RAMKAHEN[2],
        ignore = true,
    },
    [_G.GetSpellInfo(57819)] = { -- TABARD OF THE ARGENT CRUSADE
        faction = private.FACTION_DATA.ARGENT_CRUSADE[2],
        ignore = true,
    },
    [_G.GetSpellInfo(94158)] = { -- TABARD OF THE DRAGONMAW CLAN
        faction = private.FACTION_DATA.DRAGONMAW_CLAN[2],
        ignore = true,
    },
    [_G.GetSpellInfo(93339)] = { -- TABARD OF THE EARTHEN RING
        faction = private.FACTION_DATA.EARTHEN_RING[2],
        ignore = true,
    },
    [_G.GetSpellInfo(57820)] = { -- TABARD OF THE EBON BLADE
        faction = private.FACTION_DATA.EBON_BLADE[2],
        ignore = true,
    },
    [_G.GetSpellInfo(93341)] = { -- TABARD OF THE GUARDIANS OF HYJAL
        faction = private.FACTION_DATA.GUARDIANS_OF_HYJAL[2],
        ignore = true,
    },
    [_G.GetSpellInfo(57821)] = { -- TABARD OF THE KIRIN TOR
        faction = private.FACTION_DATA.KIRIN_TOR[2],
        ignore = true,
    },
    [_G.GetSpellInfo(93368)] = { -- TABARD OF THE WILDHAMMER CLAN
        faction = private.FACTION_DATA.WILDHAMMER_CLAN[2],
        ignore = true,
    },
    [_G.GetSpellInfo(57822)] = { -- TABARD OF THE WYRMREST ACCORD
        faction = private.FACTION_DATA.WYRMREST_ACCORD[2],
        ignore = true,
    },
    [_G.GetSpellInfo(93347)] = { -- TABARD OF THERAZANE
        faction = private.FACTION_DATA.THERAZANE[2],
        ignore = true,
    },
    [_G.GetSpellInfo(94463)] = { -- THUNDERBLUFF TABARD
        faction = private.FACTION_DATA.THUNDER_BLUFF[2],
        ignore = true,
    },
    [_G.GetSpellInfo(126434)] = { -- TUSHUI TABARD
        faction = private.FACTION_DATA.TUSHUI[2],
        ignore = true,
    },
    [_G.GetSpellInfo(94462)] = { -- UNDERCITY TABARD
        faction = private.FACTION_DATA.UNDERCITY[2],
        ignore = true,
    },

    -- Banner Buffs
    [_G.GetSpellInfo(90216)] = { -- ALLIANCE GUILD STANDARD
        ignore = true,
    },
    [_G.GetSpellInfo(90708)] = { -- HORDE GUILD STANDARD
        ignore = true,
    },

    -- Holiday Buffs
    [_G.GetSpellInfo(136583)] = { -- DARKMOON TOP HAT
        modifier = 0.1,
    },
    [_G.GetSpellInfo(24705)] = { -- GRIM VISAGE
        modifier = 0.1,
    },
    [_G.GetSpellInfo(61849)] = { -- SPIRIT OF SHARING
        modifier = 0.1,
    },
    [_G.GetSpellInfo(95987)] = { -- UNBURDENED
        modifier = 0.1,
    },
    [_G.GetSpellInfo(46668)] = { -- WHEE!
        modifier = 0.1,
    },
    [_G.GetSpellInfo(100951)] = { -- WOW 8TH ANNIVERSARY
        modifier = 0.08,
    },
    [_G.GetSpellInfo(132700)] = { -- WOW 9TH ANNIVERSARY
        modifier = 0.09,
    },
    [_G.GetSpellInfo(150986)] = { -- WOW 10TH ANNIVERSARY
        modifier = 0.1,
    },

    -- Situational Buffs
    [_G.GetSpellInfo(39953)] = { -- ADALS SONG OF BATTLE
        faction = private.FACTION_DATA.SHATAR[2],
        modifier = 0.1,
    },
    [_G.GetSpellInfo(30754)] = { -- CENARION FAVOR
        faction = private.FACTION_DATA.CENARION_CIRCLE[2],
        modifier = 0.25,
    },
    [_G.GetSpellInfo(32098)] = { -- HONOR HOLD FAVOR
        faction = private.FACTION_DATA.HONOR_HOLD[2],
        modifier = 0.25,
    },
    [_G.GetSpellInfo(39913)] = { -- NAZGRELS FERVOR
        faction = private.FACTION_DATA.THRALLMAR[2],
        modifier = 0.1,
    },
    [_G.GetSpellInfo(32096)] = { -- THRALLMARS FAVOR
        faction = private.FACTION_DATA.THRALLMAR[2],
        modifier = 0.25,
    },
    [_G.GetSpellInfo(39911)] = { -- TROLLBANES COMMAND
        faction = private.FACTION_DATA.HONOR_HOLD[2],
        modifier = 0.1,
    },
}
