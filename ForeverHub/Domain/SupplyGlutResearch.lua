local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns.Domain = ns.Domain or {}

local SupplyGlutResearch = {}
ns.Domain.SupplyGlutResearch = SupplyGlutResearch

SupplyGlutResearch.ALLOWED_STATES = {
  OBSERVED_LOW_PRICE = true,
  PLAUSIBLE_TEMPORARY_GLUT = true,
  STRUCTURAL_OVERSUPPLY_RISK = true,
  INSUFFICIENT_EVIDENCE = true,
}

SupplyGlutResearch.FALLBACK_TYPES = {
  DIRECT_VENDOR = "DIRECT_VENDOR",
  CRAFT_TO_VENDOR_ACCESSIBLE = "CRAFT_TO_VENDOR_ACCESSIBLE",
  CRAFT_TO_VENDOR_LOCKED = "CRAFT_TO_VENDOR_LOCKED",
  UNVERIFIED = "UNVERIFIED",
}

SupplyGlutResearch.ACTIVITY_CLASSES = {
  VENDOR_ARBITRAGE = "VENDOR_ARBITRAGE",
  PROGRESSION_AND_COOLDOWN = "PROGRESSION_AND_COOLDOWN",
  SPECULATIVE_HOLD = "SPECULATIVE_HOLD",
}

SupplyGlutResearch.FALLBACK_LOSS_LABEL = "Loss under stated fallback"
SupplyGlutResearch.FALLBACK_CAVEAT_NOTE =
  "Applies only under the stated immediate vendor fallback; access failure or a client SellPrice hotfix can invalidate this bound."

SupplyGlutResearch.PRICE_DEPRESSION_THRESHOLD_BPS = 7500
SupplyGlutResearch.SUPPLY_EXPANSION_THRESHOLD_BPS = 12500
SupplyGlutResearch.MIN_COMPARABLE_HISTORY_DAYS = 5

-- Single unified candidate registry (Astra P1: never duplicate metadata merely to satisfy a count assertion).
-- `BASELINE_WATCHLIST_IDS` exposes the stable 6-item Core Watchlist view while `CANDIDATE_REGISTRY`
-- provides the full verification-first playbook across separated activity classes.
SupplyGlutResearch.BASELINE_WATCHLIST_IDS = { 7067, 13463, 13464, 11176, 7068, 14047 }

SupplyGlutResearch.CANDIDATE_REGISTRY = {
  -- Core 6 Baseline Candidates (Reconciled Dreamfoil & Golden Sansam vendorUnitCopper = 250c to match EconomyData):
  {
    candidateID = "i1:item:7067",
    itemID = 7067,
    displayName = "Elemental Earth",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "SPECULATIVE_RAID_REAGENT",
    activityClass = "SPECULATIVE_HOLD",
    isCoreBaseline = true,
    vendorable = true,
    vendorUnitCopper = 400,
    maxStack = 10,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = false,
    isBoeEquipment = false,
    hypothesisSummary = "Used in Greater Nature Protection Potion (1x Elemental Earth + 1x Dreamfoil) and Elemental Sharpening Stone (2x Elemental Earth).",
    principalFailureMode = "Lv60 open-world + Dire Maul East lasher/elemental farming can outpace raid burn; test in small lots after confirming raid demand.",
  },
  {
    candidateID = "i1:item:13463",
    itemID = 13463,
    displayName = "Dreamfoil",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "SPECULATIVE_RAID_REAGENT",
    activityClass = "SPECULATIVE_HOLD",
    isCoreBaseline = true,
    vendorable = true,
    vendorUnitCopper = 250,
    maxStack = 20,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Used across Major Spellblasting (2x), Major Mender's (3x, verify 1 vs 2 output yield), Owl (4x), Sages (4x), and Greater protection potions (1x each in merged book).",
    principalFailureMode = "Instanced lasher runs and open-world herbalism expand supply; run small-lot sale-through tests before scaling.",
  },
  {
    candidateID = "i1:item:13464",
    itemID = 13464,
    displayName = "Golden Sansam",
    bucket = "B_FOREVER_CUSTOM",
    playbookCategory = "STRUCTURAL_RISK_WATCH",
    activityClass = "SPECULATIVE_HOLD",
    isCoreBaseline = true,
    vendorable = true,
    vendorUnitCopper = 250,
    maxStack = 20,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = false,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Used in Elixir of Sages (2x), Wicked Regeneration, Nature Power, First Aid healing potions, and Natural Accuracy flask (18x + 1x Death Lotus).",
    principalFailureMode = "Cheap ~= mispriced: abundant open-world nodes and Death Lotus / recipe bottlenecks cap total burn.",
  },
  {
    candidateID = "i1:item:11176",
    itemID = 11176,
    displayName = "Dream Dust",
    bucket = "B_FOREVER_CUSTOM",
    playbookCategory = "STRUCTURAL_RISK_WATCH",
    activityClass = "SPECULATIVE_HOLD",
    isCoreBaseline = true,
    vendorable = false,
    vendorUnitCopper = 0,
    maxStack = 20,
    demandRecurrence = "one_time_durable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Used in Enchanting formulas including custom Forever slot enchants, Greater Arcane Protection Potion, and Artisan Curiosities crate.",
    principalFailureMode = "Zero NPC vendor value (0c); full entry outlay is exposed if dungeon DE supply outpaces enchant demand.",
  },
  {
    candidateID = "i1:item:7068",
    itemID = 7068,
    displayName = "Elemental Fire",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "SPECULATIVE_RAID_REAGENT",
    activityClass = "SPECULATIVE_HOLD",
    isCoreBaseline = true,
    vendorable = true,
    vendorUnitCopper = 400,
    maxStack = 10,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = false,
    isBoeEquipment = false,
    hypothesisSummary = "Used in Greater Fire Protection Potion (1x Elemental Fire + 1x Dreamfoil) for Onyxia/Hyjal fire encounters.",
    principalFailureMode = "Small Onyxia trade; track Heart of Fire (7077) separately (23 endgame recipes vs 3 for Elemental Fire).",
  },
  {
    candidateID = "i1:item:14047",
    itemID = 14047,
    displayName = "Runecloth",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "VENDOR_AND_CONVERSION",
    activityClass = "VENDOR_ARBITRAGE",
    isCoreBaseline = true,
    vendorable = true,
    vendorUnitCopper = 400,
    maxStack = 20,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Used in Heavy Runecloth Bandages (500c/cloth at First Aid 290), Bolt of Runecloth (16-22 bolts per Cloth Tier 1 piece), and turn-ins.",
    principalFailureMode = "Continuous byproduct of all Lv52-60 dungeon and open-world humanoid farming.",
  },
  -- Expanded Playbook: Activity Class 1 — Immediate Vendor & Conversion Arbitrage
  {
    candidateID = "i1:item:4306",
    itemID = 4306,
    displayName = "Silk Cloth",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "VENDOR_AND_CONVERSION",
    activityClass = "VENDOR_ARBITRAGE",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 150,
    maxStack = 20,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Direct 150c NPC vendor floor; Heavy Silk Bandage (6451, First Aid 180) yields 200c/cloth (bolting adds 0c vendor uplift).",
    principalFailureMode = "Above 150c direct floor (or 200c accessible bandage floor), humanoid AoE supply suppresses resale margin.",
  },
  {
    candidateID = "i1:item:4338",
    itemID = 4338,
    displayName = "Mageweave Cloth",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "VENDOR_AND_CONVERSION",
    activityClass = "VENDOR_ARBITRAGE",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 250,
    maxStack = 20,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Direct 250c NPC vendor floor; used in Tailoring 175-250 progression and Expert Fabrics crates.",
    principalFailureMode = "Heavy Mageweave Bandage (8545) and White Bandit Mask (10047) have static sell-price conflicts requiring live-client confirmation.",
  },
  {
    candidateID = "i1:item:4304",
    itemID = 4304,
    displayName = "Thick Leather",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "VENDOR_AND_CONVERSION",
    activityClass = "VENDOR_ARBITRAGE",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 300,
    maxStack = 20,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Direct 300c NPC vendor floor; 20x option for Artisan Textiles crate (248698).",
    principalFailureMode = "High slot consumption (60s/stack of 20); above-floor purchases lose copper on NPC liquidation.",
  },
  {
    candidateID = "i1:item:8170",
    itemID = 8170,
    displayName = "Rugged Leather",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "VENDOR_AND_CONVERSION",
    activityClass = "VENDOR_ARBITRAGE",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 500,
    maxStack = 20,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Direct 500c NPC vendor floor; 20x option for Artisan Textiles crate (248698) and high-end LW.",
    principalFailureMode = "Continuous Lv52-60 beast skinning byproduct; above 500c is speculative exposure.",
  },
  -- Expanded Playbook: Activity Class 2 — Reconciled Forever Alchemy & Raid Reagents
  {
    candidateID = "i1:item:13465",
    itemID = 13465,
    displayName = "Mountain Silversage",
    bucket = "B_FOREVER_CUSTOM",
    playbookCategory = "SPECULATIVE_RAID_REAGENT",
    activityClass = "SPECULATIVE_HOLD",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 400,
    maxStack = 20,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = false,
    isBoeEquipment = false,
    hypothesisSummary = "Corpus-verified input for Major Spellblasting Potion (2 Dreamfoil + 1 Silversage), Elixir of the Owl (4 Dreamfoil + 2 Silversage), and Mongoose.",
    principalFailureMode = "Static vendor floor conflicts (250c vs 400c); test in small lots (<=30u) and verify completed sales before scaling.",
  },
  {
    candidateID = "i1:item:13466",
    itemID = 13466,
    displayName = "Plaguebloom",
    bucket = "B_FOREVER_CUSTOM",
    playbookCategory = "SPECULATIVE_RAID_REAGENT",
    activityClass = "SPECULATIVE_HOLD",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 250,
    maxStack = 20,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = false,
    isBoeEquipment = false,
    hypothesisSummary = "Corpus-verified input for Major Frenzy Potion (3 Plaguebloom + 2 Blindweed + 1 Imbued Vial) and Elixir of the Mongoose (2x).",
    principalFailureMode = "Thin lowest rung (only 6u at 28s 90c in saved scan); test small lots (<=15u) and check potion competition before scaling.",
  },
  {
    candidateID = "i1:item:8846",
    itemID = 8846,
    displayName = "Gromsblood",
    bucket = "B_FOREVER_CUSTOM",
    playbookCategory = "SPECULATIVE_RAID_REAGENT",
    activityClass = "SPECULATIVE_HOLD",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 250,
    maxStack = 20,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = false,
    isBoeEquipment = false,
    hypothesisSummary = "Used in Elixir of the Grizzly (3x, verify 1 vs 2 output yield), Flask of the Titans (30x in Classic base row — confirm live), and Mighty Rage (3x in Classic base row).",
    principalFailureMode = "Requires Alchemy 275-300 + Merchant's Favor recipe unlocks; confirm live Classic base rows before underwriting demand.",
  },
  {
    candidateID = "i1:item:8839",
    itemID = 8839,
    displayName = "Blindweed",
    bucket = "B_FOREVER_CUSTOM",
    playbookCategory = "SPECULATIVE_RAID_REAGENT",
    activityClass = "SPECULATIVE_HOLD",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 225,
    maxStack = 20,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Corpus-verified input for Major Frenzy Potion (2x), Elixir of the Grizzly (1x), Superior Frenzy (3x), and Limited Invulnerability Potion.",
    principalFailureMode = "Dense Swamp of Sorrows / Un'Goro nodes allow rapid farming response if prices rise.",
  },
  {
    candidateID = "i1:item:8838",
    itemID = 8838,
    displayName = "Sungrass",
    bucket = "B_FOREVER_CUSTOM",
    playbookCategory = "SPECULATIVE_RAID_REAGENT",
    activityClass = "SPECULATIVE_HOLD",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 150,
    maxStack = 20,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Corpus-verified input for Major Mender's Potion (3 Dreamfoil + 1 Sungrass, verify 1 vs 2 output yield), Nature Power, and Phalanx.",
    principalFailureMode = "Abundant mid-to-high zone spawns keep supply elastic.",
  },
  {
    candidateID = "i1:item:8845",
    itemID = 8845,
    displayName = "Ghost Mushroom",
    bucket = "B_FOREVER_CUSTOM",
    playbookCategory = "SPECULATIVE_RAID_REAGENT",
    activityClass = "SPECULATIVE_HOLD",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 375,
    maxStack = 20,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = false,
    isBoeEquipment = false,
    hypothesisSummary = "Cave-spawn herb used in Elixir of Ferocity, Caustic Smog Potion, Elixir of Shadow Power, LIP, and Ghost Dye (2x).",
    principalFailureMode = "Maraudon / Dire Maul instance resets provide repeatable indoor farming routes.",
  },
  {
    candidateID = "i1:item:248821",
    itemID = 248821,
    displayName = "Demonsage",
    bucket = "B_FOREVER_CUSTOM",
    playbookCategory = "SPECULATIVE_RAID_REAGENT",
    activityClass = "SPECULATIVE_HOLD",
    isCoreBaseline = false,
    vendorable = false,
    vendorUnitCopper = 0,
    maxStack = 20,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = false,
    isBoeEquipment = false,
    hypothesisSummary = "Custom WoW: Forever raid herb used (12x or 18x + 1x Death Lotus) in Natural Flasks and endgame demonic elixirs.",
    principalFailureMode = "Natural Flask demand is gated by Death Lotus (248822) availability and verified flask sale-through.",
  },
  {
    candidateID = "i1:item:248823",
    itemID = 248823,
    displayName = "Marefoil",
    bucket = "B_FOREVER_CUSTOM",
    playbookCategory = "SPECULATIVE_RAID_REAGENT",
    activityClass = "SPECULATIVE_HOLD",
    isCoreBaseline = false,
    vendorable = false,
    vendorUnitCopper = 0,
    maxStack = 20,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = false,
    isBoeEquipment = false,
    hypothesisSummary = "Custom WoW: Forever raid herb used (12x or 18x + 1x Death Lotus) in Natural Flasks and high-end caster/healer elixirs.",
    principalFailureMode = "Natural Flask demand is gated by Death Lotus (248822) availability and verified flask sale-through.",
  },
  -- Expanded Playbook: Activity Class 3 — Cooldown, Tier Progression & Direct-Demand Watchlist
  {
    candidateID = "i1:item:14256",
    itemID = 14256,
    displayName = "Felcloth",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "COOLDOWN_AND_PROGRESSION",
    activityClass = "PROGRESSION_AND_COOLDOWN",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 1000,
    maxStack = 20,
    demandRecurrence = "recurring_consumable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = false,
    isBoeEquipment = false,
    hypothesisSummary = "2x Felcloth -> 1x Mooncloth (96h cooldown at Tailoring 250, Pattern 14526; at most 5 casts = 10 Felcloth before Dec 9). First Cloth Tier 1 piece uses 2-3 Mooncloth.",
    principalFailureMode = "60u takes 39% of listed supply; buy only for near-term casts after verifying Tailoring 175->250 cost, pattern access, and first Mooncloth sale.",
  },
  {
    candidateID = "i1:item:12803",
    itemID = 12803,
    displayName = "Living Essence",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "COOLDOWN_AND_PROGRESSION",
    activityClass = "PROGRESSION_AND_COOLDOWN",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 4000,
    maxStack = 10,
    demandRecurrence = "one_time_durable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = false,
    isBoeEquipment = false,
    hypothesisSummary = "Top P2 direct-crafting essence watch (34s 97c across 53 endgame recipes including Ironvine, Bramblewood, Sylvan, and Gaea's Embrace).",
    principalFailureMode = "Rank by direct crafting breadth rather than shared transmute cooldown; static sell price (400c vs 4000c) is disputed.",
  },
  {
    candidateID = "i1:item:12808",
    itemID = 12808,
    displayName = "Essence of Undeath",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "COOLDOWN_AND_PROGRESSION",
    activityClass = "PROGRESSION_AND_COOLDOWN",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 4000,
    maxStack = 10,
    demandRecurrence = "one_time_durable",
    accessibleSinkVerified = false,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Used in 16 direct endgame recipes; Undeath->Water (4.57g) loses shared Alchemy cooldown competition to Arcanite (38.29g) and Legionite (30.66g).",
    principalFailureMode = "Shared cooldown competition explains cheap Undeath; rank strictly on direct crafting demand rather than transmute value.",
  },
  {
    candidateID = "i1:item:7078",
    itemID = 7078,
    displayName = "Essence of Fire",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "COOLDOWN_AND_PROGRESSION",
    activityClass = "PROGRESSION_AND_COOLDOWN",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 400,
    maxStack = 10,
    demandRecurrence = "one_time_durable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = false,
    isBoeEquipment = false,
    hypothesisSummary = "Direct 400c NPC vendor floor; used directly in 45 endgame recipes (Spitfire set, Robe of the Archmage, Biznicks Scope, Core Armor Kit).",
    principalFailureMode = "Fire->Earth (2.77g) loses shared cooldown competition to Arcanite/Legionite; evaluate strictly on direct crafting demand.",
  },
  {
    candidateID = "i1:item:248825",
    itemID = 248825,
    displayName = "Fel Leather",
    bucket = "B_FOREVER_CUSTOM",
    playbookCategory = "COOLDOWN_AND_PROGRESSION",
    activityClass = "PROGRESSION_AND_COOLDOWN",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 750,
    maxStack = 20,
    demandRecurrence = "one_time_durable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Verified 750c vendor floor. First Leather/Mail Tier 1 piece uses 18-24 Fel Leather (Artisan's Tier cap starts at 1 piece, rising to 2 with Revered Rousing Seed Pod).",
    principalFailureMode = "Self-farm while leveling with Skinning 300 and let 72 posted units test sale-through; 500u bulk buy ties up 44.95g and risks 150c/u (7.50g) 8h deposit expiry.",
  },
  {
    candidateID = "i1:item:251291",
    itemID = 251291,
    displayName = "Heavy Thorium Bar",
    bucket = "B_FOREVER_CUSTOM",
    playbookCategory = "COOLDOWN_AND_PROGRESSION",
    activityClass = "PROGRESSION_AND_COOLDOWN",
    isCoreBaseline = false,
    vendorable = false,
    vendorUnitCopper = 0,
    maxStack = 20,
    demandRecurrence = "one_time_durable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = false,
    isBoeEquipment = false,
    hypothesisSummary = "Smelted 1:1 from Heavy Thorium Ore (248815) at Mining 300; used in 42 endgame recipes (12-18 bars per first Plate Tier 1 piece + 1x in Transmute: Legionite).",
    principalFailureMode = "Week-1 tier demand is gated by Malleable Essence of Nature (274030) and reputation patterns; defer bulk bar position until raid crafts start moving.",
  },
  {
    candidateID = "i1:item:249426",
    itemID = 249426,
    displayName = "Pitchblende",
    bucket = "B_FOREVER_CUSTOM",
    playbookCategory = "COOLDOWN_AND_PROGRESSION",
    activityClass = "PROGRESSION_AND_COOLDOWN",
    isCoreBaseline = false,
    vendorable = false,
    vendorUnitCopper = 0,
    maxStack = 20,
    demandRecurrence = "one_time_durable",
    accessibleSinkVerified = false,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Tier-3 Scarce Mining drop; 2x Pitchblende + 1x Coal (3857) smelts at Mining 275 into 1x Azerothium Bar (249726), used in 14 Skill-300 recipes.",
    principalFailureMode = "Econa lacks Mining 275; test small lots only via a trusted miner and verify Azerothium Bar completed sales.",
  },
  {
    candidateID = "i1:item:249429",
    itemID = 249429,
    displayName = "Pristine Scale",
    bucket = "B_FOREVER_CUSTOM",
    playbookCategory = "COOLDOWN_AND_PROGRESSION",
    activityClass = "PROGRESSION_AND_COOLDOWN",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 375,
    maxStack = 20,
    demandRecurrence = "one_time_durable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Verified 375c vendor floor; Tier-3 Scarce Skinning drop used in 12 Skill-300 recipes (Dragonscale Helms, Pristine Scorpid Leggings, Bottomless Reagent Bag).",
    principalFailureMode = "Self-farm with Skinning 300 rather than committing liquid capital above the 375c vendor floor.",
  },
  {
    candidateID = "i1:item:249428",
    itemID = 249428,
    displayName = "Pristine Hide",
    bucket = "B_FOREVER_CUSTOM",
    playbookCategory = "STRUCTURAL_RISK_WATCH",
    activityClass = "SPECULATIVE_HOLD",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 250,
    maxStack = 20,
    demandRecurrence = "one_time_durable",
    accessibleSinkVerified = false,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Verified 250c vendor floor with recorded vendor payouts; Tier-2 Scarce Skinning drop (10 of 45 recipes are Skill 240+).",
    principalFailureMode = "Pass on bulk hides: 8h AH deposit is 50c/unit (1g loss per 200-unit expired lot vs 2s immediate vendor loss), and 3,356 units are already listed.",
  },
  {
    candidateID = "i1:item:8171",
    itemID = 8171,
    displayName = "Rugged Hide",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "STRUCTURAL_RISK_WATCH",
    activityClass = "SPECULATIVE_HOLD",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 500,
    maxStack = 10,
    demandRecurrence = "one_time_durable",
    accessibleSinkVerified = false,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Verified 500c vendor floor with recorded vendor payouts; pairs 1:1 with Refined Deeprock Salt (15409) to craft Cured Rugged Hide (15407).",
    principalFailureMode = "Pass on bulk hides: Refined Deeprock Salt (68.98g) + Rugged Hide (5.07s) = 69.03g vs Cured Rugged Hide (37.77g) implies a -33.15g conversion loss after 5% cut.",
  },
  {
    candidateID = "i1:item:9210",
    itemID = 9210,
    displayName = "Ghost Dye",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "COOLDOWN_AND_PROGRESSION",
    activityClass = "PROGRESSION_AND_COOLDOWN",
    isCoreBaseline = false,
    vendorable = false,
    vendorUnitCopper = 0,
    maxStack = 20,
    demandRecurrence = "one_time_durable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = false,
    isBoeEquipment = false,
    hypothesisSummary = "Trades at 36s below its 2x Ghost Mushroom (8845 @ 37s 29c) + Purple Dye + Crystal Vial (~80s) replacement craft cost; used in 10 endgame recipes.",
    principalFailureMode = "Sub-replacement cost requires an end buyer: 58 units takes 54% of listed supply with no verified NPC vendor floor.",
  },
  {
    candidateID = "i1:item:13926",
    itemID = 13926,
    displayName = "Golden Pearl",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "COOLDOWN_AND_PROGRESSION",
    activityClass = "PROGRESSION_AND_COOLDOWN",
    isCoreBaseline = false,
    vendorable = false,
    vendorUnitCopper = 0,
    maxStack = 20,
    demandRecurrence = "one_time_durable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = false,
    isBoeEquipment = false,
    hypothesisSummary = "Used in Truefaith Vestments, Runed Arcanite Rod (16207), and Enchant Weapon - Spell Power (2x); note Robe of the Archmage uses 4 essences, not pearls.",
    principalFailureMode = "Gearing and weapon-enchant watch only; unverified NPC vendor floor leaves full entry cost exposed.",
  },
  {
    candidateID = "i1:item:12363",
    itemID = 12363,
    displayName = "Arcane Crystal",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "COOLDOWN_AND_PROGRESSION",
    activityClass = "PROGRESSION_AND_COOLDOWN",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 10000,
    maxStack = 20,
    demandRecurrence = "one_time_durable",
    accessibleSinkVerified = false,
    byproductOrPerkFloodRisk = false,
    isBoeEquipment = false,
    hypothesisSummary = "1x Arcane Crystal + 1x Thorium Bar -> 1x Arcanite Bar (12360, 38.29g implied net cooldown margin; 2-4 bars per first Plate Tier 1 piece).",
    principalFailureMode = "Econa lacks Alchemy 275; buy crystals only against a priced cooldown partner or demonstrated raw-crystal resale.",
  },
  {
    candidateID = "i1:item:14227",
    itemID = 14227,
    displayName = "Ironweb Spider Silk",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "COOLDOWN_AND_PROGRESSION",
    activityClass = "PROGRESSION_AND_COOLDOWN",
    isCoreBaseline = false,
    vendorable = true,
    vendorUnitCopper = 500,
    maxStack = 20,
    demandRecurrence = "one_time_durable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = false,
    isBoeEquipment = false,
    hypothesisSummary = "Used across 75 endgame Tailoring/LW recipes; saved client cache shows 2500c vendor floor (disputed against 500c static reference).",
    principalFailureMode = "Saved lowest ask (89s 99c) exceeds the 75s target ceiling (0 visible units <= 75s).",
  },
  {
    candidateID = "i1:item:16204",
    itemID = 16204,
    displayName = "Illusion Dust",
    bucket = "A_CLASSIC_RAID",
    playbookCategory = "STRUCTURAL_RISK_WATCH",
    activityClass = "SPECULATIVE_HOLD",
    isCoreBaseline = false,
    vendorable = false,
    vendorUnitCopper = 0,
    maxStack = 20,
    demandRecurrence = "one_time_durable",
    accessibleSinkVerified = true,
    byproductOrPerkFloodRisk = true,
    isBoeEquipment = false,
    hypothesisSummary = "Used across 45 endgame Enchanting formulas (including Bracer/Chest/Weapon enchants); merits an enchant watch alongside Dream Dust.",
    principalFailureMode = "Zero NPC vendor floor (0c); Lv55-60 dungeon and crafted gear disenchanting expands supply continuously.",
  },
}

SupplyGlutResearch.CURATED_WATCHLIST = {}
SupplyGlutResearch.CANDIDATES_BY_ITEM_ID = {}
local _dedupedRegistry = {}
for _, rec in ipairs(SupplyGlutResearch.CANDIDATE_REGISTRY) do
  if rec and rec.itemID and not SupplyGlutResearch.CANDIDATES_BY_ITEM_ID[rec.itemID] then
    SupplyGlutResearch.CANDIDATES_BY_ITEM_ID[rec.itemID] = rec
    table.insert(_dedupedRegistry, rec)
    if rec.isCoreBaseline then
      table.insert(SupplyGlutResearch.CURATED_WATCHLIST, rec)
    end
  end
end
SupplyGlutResearch.CANDIDATE_REGISTRY = _dedupedRegistry

function SupplyGlutResearch.GetPlaybookCatalog(filterCategory)
  local out = {}
  local seen = {}
  local cat = type(filterCategory) == "string" and filterCategory or "ALL"
  for _, rec in ipairs(SupplyGlutResearch.CANDIDATE_REGISTRY) do
    if rec and rec.itemID and not seen[rec.itemID] then
      if cat == "ALL"
        or (cat == "CORE_6" and rec.isCoreBaseline == true)
        or rec.playbookCategory == cat
        or rec.activityClass == cat
      then
        seen[rec.itemID] = true
        table.insert(out, rec)
      end
    end
  end
  return out
end

-- ============================================================================
-- Astra P0 & P1: Saved AH Ladder Snapshot Freshness, 10-Rung Truncation,
-- Commodity vs Whole-Stack Depth & Deposit/Vendor-Loss Evaluator
-- ============================================================================

SupplyGlutResearch.SAVED_LADDER_MAX_RIVAL_RUNGS = 10
SupplyGlutResearch.DEFAULT_MAX_FRESH_LADDER_AGE_SECONDS = 3600
SupplyGlutResearch.MAX_CREDIBLE_LADDER_COPPER = 2147483647 -- 2^31 - 1 (Prices.lua:85)

function SupplyGlutResearch.EvaluateSavedLadderSnapshot(opts)
  opts = type(opts) == "table" and opts or {}
  local itemID = tonumber(opts.itemID)
  local ladderAt = tonumber(opts.ladderAt)
  local lastFullScanAt = tonumber(opts.lastFullScanAt)
  local nowEpoch = tonumber(opts.nowEpoch) or tonumber(opts.characterSeenAt) or 0
  local maxFreshAge = tonumber(opts.maxFreshAgeSeconds) or SupplyGlutResearch.DEFAULT_MAX_FRESH_LADDER_AGE_SECONDS
  local maxRivalRungs = tonumber(opts.maxRivalRungs) or SupplyGlutResearch.SAVED_LADDER_MAX_RIVAL_RUNGS
  local maxClockSkew = math.max(0, math.floor(tonumber(opts.maxClockSkewSeconds) or 0))
  local marketIdentity = opts.marketIdentity
  local requireMarketIdentity = (opts.requireMarketIdentity == true)

  local freshnessStatus = "MISSING_TIMESTAMP"
  local ageSeconds = nil
  local isHistoricalSnapshot = true
  local isValidSnapshot = true

  if requireMarketIdentity and (type(marketIdentity) ~= "string" or marketIdentity == "") then
    freshnessStatus = "MISSING_MARKET_IDENTITY"
    isValidSnapshot = false
  elseif ladderAt and ladderAt > 0 and nowEpoch > 0 then
    if ladderAt > (nowEpoch + maxClockSkew) then
      -- Astra P0.3: Never clamp future timestamps to zero!
      freshnessStatus = "FUTURE_TIMESTAMP_INVALID"
      ageSeconds = nil
      isHistoricalSnapshot = true
      isValidSnapshot = false
    else
      ageSeconds = nowEpoch - ladderAt
      if ageSeconds <= maxFreshAge then
        freshnessStatus = "FRESH_ITEM_SCAN"
        isHistoricalSnapshot = false
      elseif lastFullScanAt and ladderAt > lastFullScanAt then
        freshnessStatus = "HISTORICAL_ITEM_SCAN"
        isHistoricalSnapshot = true
      else
        freshnessStatus = "HISTORICAL_FULL_SWEEP"
        isHistoricalSnapshot = true
      end
    end
  end

  -- Normalize either aggregate flat pairs `{ price1, qty1, price2, qty2, ... }`
  -- or explicit stack rungs `{ { stackSize = k, stackBuyoutCopper = B, numStacks = m }, ... }`:
  -- Astra P0.3: `rowPriceFixed` in Blackthornes_TS (Scanner.lua:1204) is a historical EMA reset marker
  -- and does NOT certify partial-stack fills. Flat ladders lose stack boundaries.
  local rawLadder = type(opts.ladder) == "table" and opts.ladder or {}
  local rowPriceFixed = (opts.rowPriceFixed ~= false)
  local commodityPartialFillVerified = (opts.commodityPartialFillVerified == true)
  local normalizedRungs = {}
  local isFlatAggregateLadder = false
  local stackBoundariesKnown = false
  local isMalformedLadder = false

  if #rawLadder > 0 and type(rawLadder[1]) == "number" then
    isFlatAggregateLadder = true
    stackBoundariesKnown = false
    if (#rawLadder % 2) ~= 0 then
      isMalformedLadder = true
      isValidSnapshot = false
    else
      for i = 1, #rawLadder - 1, 2 do
        local rawP = rawLadder[i]
        local rawQ = rawLadder[i + 1]
        if type(rawP) ~= "number" or type(rawQ) ~= "number"
          or rawP ~= rawP or rawQ ~= rawQ
          or rawP <= 0 or rawP > SupplyGlutResearch.MAX_CREDIBLE_LADDER_COPPER
          or rawQ <= 0 or math.floor(rawP) ~= rawP or math.floor(rawQ) ~= rawQ
        then
          isMalformedLadder = true
          isValidSnapshot = false
          break
        end
        table.insert(normalizedRungs, {
          unitPriceCopper = rawP,
          stackSize = 1,
          stackBuyoutCopper = rawP,
          numStacks = rawQ,
          totalUnits = rawQ,
          wholeStackOnly = false,
          stackBoundariesKnown = false,
        })
      end
    end
  else
    stackBoundariesKnown = (#rawLadder > 0)
    for _, r in ipairs(rawLadder) do
      if type(r) ~= "table" then
        isMalformedLadder = true
        isValidSnapshot = false
        stackBoundariesKnown = false
        break
      end
      local sSize = tonumber(r.stackSize) or 1
      local nStacks = tonumber(r.numStacks or r.quantity) or 0
      local sBuyout = tonumber(r.stackBuyoutCopper)
      local uPrice = tonumber(r.unitPriceCopper)
      if not sBuyout and uPrice and uPrice > 0 then
        sBuyout = uPrice * sSize
      end
      if type(sSize) ~= "number" or sSize <= 0 or math.floor(sSize) ~= sSize
        or type(nStacks) ~= "number" or nStacks <= 0 or math.floor(nStacks) ~= nStacks
        or type(sBuyout) ~= "number" or sBuyout <= 0 or sBuyout > SupplyGlutResearch.MAX_CREDIBLE_LADDER_COPPER
      then
        isMalformedLadder = true
        isValidSnapshot = false
        stackBoundariesKnown = false
        break
      end
      local effUnit = math.ceil(sBuyout / sSize)
      table.insert(normalizedRungs, {
        unitPriceCopper = effUnit,
        stackSize = sSize,
        stackBuyoutCopper = math.floor(sBuyout),
        numStacks = nStacks,
        totalUnits = sSize * nStacks,
        wholeStackOnly = (rowPriceFixed == false and sSize > 1) or (r.wholeStackOnly == true),
        stackBoundariesKnown = true,
      })
    end
  end

  if isMalformedLadder then
    freshnessStatus = "MALFORMED_LADDER"
  end

  local rungCount = #normalizedRungs
  local isTruncatedTenRungLadder = (rungCount >= maxRivalRungs)
  local maxUnitCap = tonumber(opts.maxUnitPriceCopper)
  local targetUnits = math.max(0, math.floor(tonumber(opts.targetUnits) or 0))

  local totalListedUnits = tonumber(opts.totalListedUnits) or 0
  local computedTotalUnits = 0
  local visibleUnitsWithinCap = 0
  local acquiredUnits = 0
  local excessWholeStackUnits = 0
  local entryCostCopper = 0
  local marginalUnitPriceCopper = nil

  if isValidSnapshot then
    for _, rung in ipairs(normalizedRungs) do
      computedTotalUnits = computedTotalUnits + rung.totalUnits
      local withinCap = (not maxUnitCap) or (rung.unitPriceCopper <= maxUnitCap)
      if withinCap then
        visibleUnitsWithinCap = visibleUnitsWithinCap + rung.totalUnits
        if targetUnits > 0 and acquiredUnits < targetUnits then
          local remaining = targetUnits - acquiredUnits
          if rung.wholeStackOnly and rung.stackSize > 1 then
            local stacksToBuy = math.min(rung.numStacks, math.ceil(remaining / rung.stackSize))
            if stacksToBuy > 0 then
              local unitsBought = stacksToBuy * rung.stackSize
              acquiredUnits = acquiredUnits + unitsBought
              entryCostCopper = entryCostCopper + (stacksToBuy * rung.stackBuyoutCopper)
              marginalUnitPriceCopper = rung.unitPriceCopper
            end
          else
            local unitsToBuy = math.min(rung.totalUnits, remaining)
            if unitsToBuy > 0 then
              acquiredUnits = acquiredUnits + unitsToBuy
              entryCostCopper = entryCostCopper + (unitsToBuy * rung.unitPriceCopper)
              marginalUnitPriceCopper = rung.unitPriceCopper
            end
          end
        end
      end
    end
  end

  if totalListedUnits <= 0 then
    totalListedUnits = computedTotalUnits
  end
  if targetUnits > 0 and acquiredUnits > targetUnits then
    excessWholeStackUnits = acquiredUnits - targetUnits
  end
  local unfilledUnits = (targetUnits > 0) and math.max(0, targetUnits - acquiredUnits) or 0
  local shareOfListedSupplyBps = (totalListedUnits > 0 and acquiredUnits > 0)
    and math.floor(((acquiredUnits * 10000) / totalListedUnits) + 0.5)
    or 0

  local vendorUnitCopper = tonumber(opts.verifiedVendorUnitCopper)
  local immediateVendorFallbackCopper = (vendorUnitCopper and vendorUnitCopper > 0 and acquiredUnits > 0)
    and (acquiredUnits * math.floor(vendorUnitCopper))
    or nil
  local immediateVendorLossCopper = (immediateVendorFallbackCopper ~= nil)
    and math.max(0, entryCostCopper - immediateVendorFallbackCopper)
    or nil

  local unitDepositCopper = math.max(0, math.floor(tonumber(opts.unitDepositCopper) or 0))
  local expectedExpirations = math.max(0, math.floor(tonumber(opts.expectedFailedExpirations) or 1))
  local singleExpirationDepositCopper = acquiredUnits * unitDepositCopper
  local cumulativeExpirationLossCopper = singleExpirationDepositCopper * expectedExpirations

  local executionAuthorized = isValidSnapshot
    and (freshnessStatus == "FRESH_ITEM_SCAN")
    and (stackBoundariesKnown or commodityPartialFillVerified)
    and (targetUnits > 0 and acquiredUnits >= targetUnits)

  local quoteConfidence
  if not isValidSnapshot then
    quoteConfidence = "INVALID_SNAPSHOT"
  elseif stackBoundariesKnown then
    quoteConfidence = "STACK_BOUNDARIES_VERIFIED"
  elseif commodityPartialFillVerified then
    quoteConfidence = "COMMODITY_PARTIAL_FILL_VERIFIED"
  else
    quoteConfidence = "AGGREGATE_RUNGS_STACK_BOUNDARIES_UNKNOWN"
  end

  return {
    itemID = itemID,
    marketIdentity = marketIdentity,
    ladderAt = ladderAt,
    lastFullScanAt = lastFullScanAt,
    nowEpoch = nowEpoch,
    ageSeconds = ageSeconds,
    freshnessStatus = freshnessStatus,
    isHistoricalSnapshot = isHistoricalSnapshot,
    isValidSnapshot = isValidSnapshot,
    isMalformedLadder = isMalformedLadder,
    isFlatAggregateLadder = isFlatAggregateLadder,
    stackBoundariesKnown = stackBoundariesKnown,
    rowPriceFixedSemantics = "HISTORICAL_EMA_RESET_NOT_PARTIAL_FILL",
    quoteConfidence = quoteConfidence,
    executionAuthorized = executionAuthorized,
    rungCount = rungCount,
    isTruncatedTenRungLadder = isTruncatedTenRungLadder,
    totalListedUnits = totalListedUnits,
    visibleUnitsWithinCap = visibleUnitsWithinCap,
    targetUnits = targetUnits,
    acquiredUnits = acquiredUnits,
    unfilledUnits = unfilledUnits,
    excessWholeStackUnits = excessWholeStackUnits,
    sufficientDepthWithinCap = (isValidSnapshot and targetUnits > 0 and acquiredUnits >= targetUnits),
    entryCostCopper = entryCostCopper,
    marginalUnitPriceCopper = marginalUnitPriceCopper,
    shareOfListedSupplyBps = shareOfListedSupplyBps,
    immediateVendorFallbackCopper = immediateVendorFallbackCopper,
    immediateVendorLossCopper = immediateVendorLossCopper,
    singleExpirationDepositCopper = singleExpirationDepositCopper,
    cumulativeExpirationLossCopper = cumulativeExpirationLossCopper,
  }
end


-- ============================================================================
-- Astra P0: Shared Verified Vendor & Conversion Fallback Resolver
--   Preserves separate fallback types:
--     1. DIRECT_VENDOR
--     2. CRAFT_TO_VENDOR_ACCESSIBLE
--     3. CRAFT_TO_VENDOR_LOCKED
--     4. UNVERIFIED
--   Always keeps direct vendor fallback visible alongside conversion fallback.
-- ============================================================================

function SupplyGlutResearch.ResolveVerifiedFallback(specOrItemID, acquiredUnits, opts)
  opts = type(opts) == "table" and opts or {}
  local MA = ns.Domain and ns.Domain.MarketAccounting
  local VA = ns.Domain and ns.Domain.VendorArbitrage
  local econ = ns.EconomyData

  local spec = type(specOrItemID) == "table" and specOrItemID or (SupplyGlutResearch.CANDIDATES_BY_ITEM_ID[tonumber(specOrItemID)] or { itemID = tonumber(specOrItemID) })
  local itemID = tonumber(spec.itemID)
  local units = math.max(1, math.floor(tonumber(acquiredUnits) or 1))
  local entryCostCopper = tonumber(opts.entryCostCopper)
  local opsCostCopper = math.max(0, math.floor(tonumber(opts.fallbackOperationsCostCopper) or 0))

  -- Resolve stack size from EconomyData tuple `{sellPrice, maxStack, flagsBitmask}`:
  local econTuple = (econ and type(econ.items) == "table" and itemID) and econ.items[itemID] or nil
  local verifiedStackSize = (econTuple and tonumber(econTuple[2])) or tonumber(spec.maxStack) or 20
  local slotsRequired = math.max(1, math.ceil(units / math.max(1, verifiedStackSize)))

  -- 1. Resolve Direct Vendor Sell Price via VendorArbitrage contract:
  local directUnitCopper = nil
  local directStatus = "unverified"
  local directVerifiedBy = nil
  local staticDispute = (VA and type(VA.GetStaticDisputeInfo) == "function" and itemID) and VA.GetStaticDisputeInfo(itemID) or nil

  if VA and type(VA.ResolveVerifiedVendorSellPrice) == "function" and itemID then
    local vRes = VA.ResolveVerifiedVendorSellPrice(itemID, {
      allowStaticWhenClientUnavailable = (opts.allowStaticWhenClientUnavailable ~= false),
      blockDisputedStaticWithoutLive = (opts.blockDisputedStaticWithoutLive == true),
      liveSellPriceLookup = opts.liveSellPriceLookup,
    })
    if vRes then
      directStatus = tostring(vRes.status or "unverified")
      directVerifiedBy = vRes.verifiedBy
      if vRes.status == "ok" and type(vRes.unitSellPrice) == "number" and vRes.unitSellPrice > 0 then
        directUnitCopper = math.floor(vRes.unitSellPrice)
      end
    end
  elseif spec.vendorable == true and type(spec.vendorUnitCopper) == "number" and spec.vendorUnitCopper > 0 then
    if not (staticDispute and opts.blockDisputedStaticWithoutLive == true) then
      directUnitCopper = math.floor(spec.vendorUnitCopper)
      directStatus = "ok"
      directVerifiedBy = "spec_fallback"
    else
      directStatus = "static_conflict_requires_live"
    end
  end

  local directTotalCopper = (directUnitCopper and directUnitCopper > 0) and (directUnitCopper * units) or nil
  local totalOutlayCopper = (entryCostCopper and entryCostCopper > 0) and (entryCostCopper + opsCostCopper) or nil
  local directLossCopper = (totalOutlayCopper and directTotalCopper) and math.max(0, totalOutlayCopper - directTotalCopper) or nil
  local directLossBps = (totalOutlayCopper and totalOutlayCopper > 0 and directLossCopper ~= nil)
    and math.floor(((directLossCopper * 10000) / totalOutlayCopper) + 0.5)
    or nil

  -- 2. Evaluate Craft-to-Vendor Conversion Fallback (whole batches + leftovers, 8-point access gate):
  local bestConversion = nil
  local lockedConversion = nil
  local reservedUnits = math.max(0, math.floor(tonumber(opts.reservedUnits) or 0))
  local itemProtected = (opts.itemProtected == true) or (reservedUnits >= units)
  local usableUnits = itemProtected and 0 or math.max(0, units - reservedUnits)

  local learnedProfessions = type(opts.learnedProfessions) == "table" and opts.learnedProfessions or nil
  local learnedRecipes = type(opts.learnedRecipes) == "table" and opts.learnedRecipes or nil
  local ownedTools = type(opts.ownedTools) == "table" and opts.ownedTools or nil
  local stationAvailable = (opts.stationAvailable ~= false)

  if econ and type(econ.craftToVendorRecipes) == "table" and itemID then
    for _, cRec in ipairs(econ.craftToVendorRecipes) do
      local primaryInputQty = nil
      local auxReagents = {}
      for _, rg in ipairs(cRec.reagents or {}) do
        if rg[1] == itemID then
          primaryInputQty = rg[2]
        else
          table.insert(auxReagents, { itemID = rg[1], quantity = rg[2] })
        end
      end

      if primaryInputQty and primaryInputQty > 0 then
        local lockReasons = {}
        if cRec.quantityVerified ~= true then
          table.insert(lockReasons, "unverified_recipe_quantity")
        end
        if itemProtected then
          table.insert(lockReasons, "item_reserved_or_protected")
        end
        if type(learnedProfessions) ~= "table" then
          table.insert(lockReasons, "missing_profession_snapshot")
        else
          local rank = tonumber(learnedProfessions[cRec.professionKey]) or 0
          if rank < (tonumber(cRec.minSkill) or 1) then
            table.insert(lockReasons, string.format("requires_%s_%d", tostring(cRec.professionKey), tonumber(cRec.minSkill) or 1))
          end
        end
        if type(learnedRecipes) == "table" then
          if learnedRecipes[cRec.recipeID] ~= true then
            table.insert(lockReasons, "recipe_not_learned")
          end
        elseif opts.assumeTrainerRecipesLearned ~= true then
          table.insert(lockReasons, "recipe_learned_unverified")
        end
        if cRec.requiresStation ~= nil and not stationAvailable then
          table.insert(lockReasons, "missing_station_" .. tostring(cRec.requiresStation))
        end
        if cRec.requiresToolItemID ~= nil and (not ownedTools or ownedTools[cRec.requiresToolItemID] ~= true) then
          table.insert(lockReasons, "missing_tool_" .. tostring(cRec.requiresToolItemID))
        end

        -- Verify output item vendor price (and block static disputes on output):
        local outVendorUnit = nil
        if VA and type(VA.ResolveVerifiedVendorSellPrice) == "function" then
          local outRes = VA.ResolveVerifiedVendorSellPrice(cRec.outputItemID, {
            allowStaticWhenClientUnavailable = (opts.allowStaticWhenClientUnavailable ~= false),
            blockDisputedStaticWithoutLive = true,
            liveSellPriceLookup = opts.liveSellPriceLookup,
          })
          if outRes and outRes.status == "ok" and type(outRes.unitSellPrice) == "number" and outRes.unitSellPrice > 0 then
            outVendorUnit = math.floor(outRes.unitSellPrice)
          else
            table.insert(lockReasons, "output_vendor_price_" .. tostring(outRes and outRes.status or "unverified"))
          end
        end

        -- Verify auxiliary merchant reagents:
        local auxCostPerBatch = 0
        for _, aux in ipairs(auxReagents) do
          local offer = econ.merchantOffers and econ.merchantOffers[aux.itemID]
          if offer and offer[3] == "unlimited_verified" then
            local unitBuy = math.ceil(tonumber(offer[1]) / math.max(1, tonumber(offer[2]) or 1))
            auxCostPerBatch = auxCostPerBatch + (unitBuy * aux.quantity)
          else
            table.insert(lockReasons, "unverified_auxiliary_reagent_" .. tostring(aux.itemID))
          end
        end

        local batches = math.floor(usableUnits / primaryInputQty)
        if batches <= 0 then
          table.insert(lockReasons, string.format("insufficient_batch_size_need_%d", primaryInputQty))
        end

        if #lockReasons == 0 and outVendorUnit and batches > 0 then
          local outQtyPerBatch = math.max(1, math.floor(tonumber(cRec.outputQuantity) or 1))
          local consumedUnits = batches * primaryInputQty
          local leftoverUnits = units - consumedUnits
          local grossCraftProceeds = batches * outQtyPerBatch * outVendorUnit
          local totalAuxCost = batches * auxCostPerBatch
          local leftoverProceeds = (directUnitCopper and directUnitCopper > 0) and (leftoverUnits * directUnitCopper) or 0
          local netConversionProceeds = grossCraftProceeds - totalAuxCost + leftoverProceeds
          if not bestConversion or netConversionProceeds > bestConversion.netConversionFallbackCopper then
            bestConversion = {
              recipeID = cRec.recipeID,
              professionKey = cRec.professionKey,
              minSkill = cRec.minSkill,
              outputItemID = cRec.outputItemID,
              batches = batches,
              consumedUnits = consumedUnits,
              leftoverUnits = leftoverUnits,
              auxiliaryReagentCostCopper = totalAuxCost,
              grossCraftVendorCopper = grossCraftProceeds,
              leftoverDirectVendorCopper = leftoverProceeds,
              netConversionFallbackCopper = netConversionProceeds,
            }
          end
        elseif not lockedConversion then
          lockedConversion = {
            recipeID = cRec.recipeID,
            professionKey = cRec.professionKey,
            minSkill = cRec.minSkill,
            outputItemID = cRec.outputItemID,
            lockReasons = lockReasons,
          }
        end
      end
    end
  end

  local fallbackType
  local statedFallbackCopper
  local fallbackPolicy
  if bestConversion and (not directTotalCopper or bestConversion.netConversionFallbackCopper > directTotalCopper) then
    fallbackType = SupplyGlutResearch.FALLBACK_TYPES.CRAFT_TO_VENDOR_ACCESSIBLE
    statedFallbackCopper = bestConversion.netConversionFallbackCopper
    fallbackPolicy = "accessible_craft_to_vendor_batch"
  elseif directTotalCopper and directTotalCopper > 0 then
    fallbackType = SupplyGlutResearch.FALLBACK_TYPES.DIRECT_VENDOR
    statedFallbackCopper = directTotalCopper
    fallbackPolicy = "immediate_npc_vendor_sell"
  elseif lockedConversion then
    fallbackType = SupplyGlutResearch.FALLBACK_TYPES.CRAFT_TO_VENDOR_LOCKED
    statedFallbackCopper = nil
    fallbackPolicy = "none"
  else
    fallbackType = SupplyGlutResearch.FALLBACK_TYPES.UNVERIFIED
    statedFallbackCopper = nil
    fallbackPolicy = "none"
  end

  local statedLossCopper = (totalOutlayCopper and statedFallbackCopper) and math.max(0, totalOutlayCopper - statedFallbackCopper) or nil
  local statedLossBps = (totalOutlayCopper and totalOutlayCopper > 0 and statedLossCopper ~= nil)
    and math.floor(((statedLossCopper * 10000) / totalOutlayCopper) + 0.5)
    or nil
  local statedLossPct = statedLossBps and (statedLossBps / 100.0) or nil

  local capitalPerSlotCopper = totalOutlayCopper and math.floor((totalOutlayCopper / slotsRequired) + 0.5) or nil
  local liquidationLossPerSlotCopper = (statedLossCopper ~= nil) and math.floor((statedLossCopper / slotsRequired) + 0.5) or nil

  return {
    fallbackAvailable = (statedFallbackCopper ~= nil and statedFallbackCopper > 0),
    fallbackType = fallbackType,
    fallbackPolicy = fallbackPolicy,
    fallbackLabel = SupplyGlutResearch.FALLBACK_LOSS_LABEL,
    fallbackValueCopper = statedFallbackCopper,
    lossUnderStatedFallbackCopper = statedLossCopper,
    lossUnderStatedFallbackBps = statedLossBps,
    lossUnderStatedFallbackPct = statedLossPct,
    -- Always keep direct vendor fallback visible even when conversion is better (Astra P0):
    directVendorAvailable = (directTotalCopper ~= nil and directTotalCopper > 0),
    directVendorStatus = directStatus,
    directVendorVerifiedBy = directVerifiedBy,
    directVendorUnitCopper = directUnitCopper,
    directVendorFallbackCopper = directTotalCopper,
    directVendorLossCopper = directLossCopper,
    directVendorLossBps = directLossBps,
    staticDispute = staticDispute,
    conversionFallback = bestConversion,
    lockedConversionInfo = lockedConversion,
    verifiedStackSize = verifiedStackSize,
    slotsRequired = slotsRequired,
    capitalPerSlotCopper = capitalPerSlotCopper,
    liquidationLossPerSlotCopper = liquidationLossPerSlotCopper,
    caveat = (statedFallbackCopper ~= nil and statedFallbackCopper > 0)
      and SupplyGlutResearch.FALLBACK_CAVEAT_NOTE
      or "No verified immediate NPC vendor fallback (SellPrice is 0c, quarantined, or disputed static conflict); full entry outlay is exposed.",
  }
end

function SupplyGlutResearch.ComputeCraftableSinkCeiling(accessibleProducerCapacity, bottleneckSupplies)
  local MA = ns.Domain and ns.Domain.MarketAccounting
  if not MA or not MA.CheckNonNegativeCopper(accessibleProducerCapacity) then
    return nil, "invalid_producer_capacity"
  end
  local cap = accessibleProducerCapacity
  for _, pair in ipairs(bottleneckSupplies or {}) do
    local sUnits = pair[1] or pair.supplyUnits
    local perCraft = pair[2] or pair.unitsPerCraft
    if not MA.CheckNonNegativeCopper(sUnits) then
      return nil, "invalid_bottleneck_supply"
    end
    if not MA.IsSafeIntegerCopper(perCraft) or perCraft <= 0 then
      return nil, "invalid_units_per_craft"
    end
    local ratio = math.floor(sUnits / perCraft)
    if ratio < cap then
      cap = ratio
    end
  end
  return math.max(0, cap), nil
end

function SupplyGlutResearch.ComputeLossUnderStatedFallback(entryCostCopper, fallbackOpsCopper, vendorable, vendorUnitCopper, acquiredUnits)
  local MA = ns.Domain and ns.Domain.MarketAccounting
  if not MA then
    return nil, "missing_market_accounting"
  end
  if not MA.IsSafeIntegerCopper(entryCostCopper) or entryCostCopper <= 0 then
    return nil, "invalid_entry_cost_copper"
  end
  local ops = fallbackOpsCopper or 0
  if not MA.CheckNonNegativeCopper(ops) then
    return nil, "invalid_fallback_operations_cost"
  end
  local units = acquiredUnits or 1
  if not MA.IsSafeIntegerCopper(units) or units <= 0 then
    return nil, "invalid_acquired_units"
  end

  if vendorable ~= true or not MA.IsSafeIntegerCopper(vendorUnitCopper) or vendorUnitCopper <= 0 then
    return {
      fallbackAvailable = false,
      fallbackType = SupplyGlutResearch.FALLBACK_TYPES.UNVERIFIED,
      fallbackPolicy = "none",
      fallbackLabel = SupplyGlutResearch.FALLBACK_LOSS_LABEL,
      fallbackValueCopper = nil,
      lossUnderStatedFallbackCopper = nil,
      lossUnderStatedFallbackBps = nil,
      lossUnderStatedFallbackPct = nil,
      caveat = "No verified immediate NPC vendor fallback (SellPrice is 0c or unverified); full entry outlay is exposed.",
    }, nil
  end

  local fbVal, errFB = MA.SafeMulNonNegativeCopper(vendorUnitCopper, units)
  if not fbVal then
    return nil, errFB
  end
  local totalCost = entryCostCopper + ops
  local lossCopper = math.max(0, totalCost - fbVal)
  local lossBps = totalCost > 0 and math.floor(((lossCopper * 10000) / totalCost) + 0.5) or 0
  return {
    fallbackAvailable = true,
    fallbackType = SupplyGlutResearch.FALLBACK_TYPES.DIRECT_VENDOR,
    fallbackPolicy = "immediate_npc_vendor_sell",
    fallbackLabel = SupplyGlutResearch.FALLBACK_LOSS_LABEL,
    fallbackValueCopper = fbVal,
    lossUnderStatedFallbackCopper = lossCopper,
    lossUnderStatedFallbackBps = lossBps,
    lossUnderStatedFallbackPct = lossBps / 100.0,
    directVendorFallbackCopper = fbVal,
    directVendorLossCopper = lossCopper,
    caveat = SupplyGlutResearch.FALLBACK_CAVEAT_NOTE,
  }, nil
end

local function buildResearchCard(spec, itemKey, classification, reason, entryAsk, vendorRatioBps, fallbackInfo, dimensions, sinkCeiling, capacityMeasured)
  return {
    candidateID = spec.candidateID,
    itemKey = itemKey,
    itemID = spec.itemID,
    displayName = spec.displayName,
    bucket = spec.bucket,
    playbookCategory = spec.playbookCategory or "CORE_WATCHLIST",
    activityClass = spec.activityClass or "SPECULATIVE_HOLD",
    rung = "RUNG_3_SUPPLY_GLUT_RESEARCH",
    mode = "RESEARCH_ONLY",
    classification = classification,
    classificationReason = reason,
    allowBuyCta = false,
    predictedAppreciationBps = nil,
    recommendedBuyQuantity = nil,
    capacityMeasured = capacityMeasured == true,
    observedUnitAskCopper = entryAsk,
    vendorFloorRatioBps = vendorRatioBps,
    craftableSinkCeilingUnits = sinkCeiling,
    fallbackLabel = fallbackInfo.fallbackLabel or SupplyGlutResearch.FALLBACK_LOSS_LABEL,
    fallbackAvailable = fallbackInfo.fallbackAvailable == true,
    fallbackType = fallbackInfo.fallbackType or SupplyGlutResearch.FALLBACK_TYPES.UNVERIFIED,
    fallbackPolicy = fallbackInfo.fallbackPolicy or "none",
    fallbackValueCopper = fallbackInfo.fallbackValueCopper,
    lossUnderStatedFallbackCopper = fallbackInfo.lossUnderStatedFallbackCopper,
    lossUnderStatedFallbackBps = fallbackInfo.lossUnderStatedFallbackBps,
    lossUnderStatedFallbackPct = fallbackInfo.lossUnderStatedFallbackPct,
    directVendorUnitCopper = fallbackInfo.directVendorUnitCopper,
    directVendorFallbackCopper = fallbackInfo.directVendorFallbackCopper,
    directVendorLossCopper = fallbackInfo.directVendorLossCopper,
    conversionFallback = fallbackInfo.conversionFallback,
    lockedConversionInfo = fallbackInfo.lockedConversionInfo,
    verifiedStackSize = fallbackInfo.verifiedStackSize,
    slotsRequired = fallbackInfo.slotsRequired,
    capitalPerSlotCopper = fallbackInfo.capitalPerSlotCopper,
    liquidationLossPerSlotCopper = fallbackInfo.liquidationLossPerSlotCopper,
    fallbackCaveat = fallbackInfo.caveat or "",
    hypothesisSummary = spec.hypothesisSummary,
    principalFailureMode = spec.principalFailureMode,
    dimensions = dimensions or {},
  }
end

function SupplyGlutResearch.EvaluateCandidate(spec, opts)
  opts = type(opts) == "table" and opts or {}
  local MA = ns.Domain and ns.Domain.MarketAccounting
  if not MA or type(spec) ~= "table" then
    return nil, "invalid_candidate_spec"
  end

  local resolvedKey = tostring(opts.itemKey or spec.candidateID or "")
  local isBlockedWrit = (type(opts.blockedWritByItemID) == "table" and opts.blockedWritByItemID[spec.itemID] == true)
    or (ns.Domain and ns.Domain.VendorArbitrage and ns.Domain.VendorArbitrage.IsBlockedUnverifiedWrit and ns.Domain.VendorArbitrage.IsBlockedUnverifiedWrit(spec.itemID) == true)

  if isBlockedWrit
    or string.sub(resolvedKey, 1, 11) == "i1:unk_var:"
    or (spec.isBoeEquipment == true and opts.boeSixPointGateVerified ~= true)
  then
    local reason = isBlockedWrit and "blocked_unverified_writ"
      or ((string.sub(resolvedKey, 1, 11) == "i1:unk_var:") and "collapsed_unknown_variant" or "unverified_boe_6_point_gate")
    return buildResearchCard(
      spec,
      resolvedKey,
      "INSUFFICIENT_EVIDENCE",
      reason,
      nil,
      nil,
      {
        fallbackAvailable = false,
        fallbackType = SupplyGlutResearch.FALLBACK_TYPES.UNVERIFIED,
        fallbackPolicy = "none",
        fallbackLabel = SupplyGlutResearch.FALLBACK_LOSS_LABEL,
        fallbackValueCopper = nil,
        lossUnderStatedFallbackCopper = nil,
        caveat = "Insufficient verified item/gate evidence.",
      },
      {},
      nil,
      false
    )
  end

  local entryCost1Lot = nil
  local acquiredUnits1Lot = 1
  local ladderMeasured = false
  if type(opts.ladderRungs) == "table" and #opts.ladderRungs > 0 then
    local walk = MA.WalkAskLadderEntryCost(opts.ladderRungs, 1, false, nil)
    if walk and walk.sufficientDepth == true and walk.entryCostCopper then
      entryCost1Lot = walk.entryCostCopper
      acquiredUnits1Lot = walk.acquiredUnits or 1
      ladderMeasured = true
    end
  end
  if not entryCost1Lot and MA.IsSafeIntegerCopper(opts.observedUnitAskCopper) and opts.observedUnitAskCopper > 0 then
    entryCost1Lot = opts.observedUnitAskCopper
    acquiredUnits1Lot = math.max(1, math.floor(tonumber(opts.acquiredUnits) or 1))
    if opts.observedUnitAskCopper and acquiredUnits1Lot > 1 then
      entryCost1Lot = opts.observedUnitAskCopper * acquiredUnits1Lot
    end
  end

  if not entryCost1Lot then
    return buildResearchCard(
      spec,
      resolvedKey,
      "INSUFFICIENT_EVIDENCE",
      "missing_price_observation",
      nil,
      nil,
      {
        fallbackAvailable = false,
        fallbackType = SupplyGlutResearch.FALLBACK_TYPES.UNVERIFIED,
        fallbackPolicy = "none",
        fallbackLabel = SupplyGlutResearch.FALLBACK_LOSS_LABEL,
        fallbackValueCopper = nil,
        lossUnderStatedFallbackCopper = nil,
        caveat = "No current ask observation available.",
      },
      {},
      nil,
      false
    )
  end

  local fallbackInfo = SupplyGlutResearch.ResolveVerifiedFallback(spec, acquiredUnits1Lot, {
    entryCostCopper = entryCost1Lot,
    fallbackOperationsCostCopper = tonumber(opts.fallbackOperationsCostCopper) or 0,
    allowStaticWhenClientUnavailable = (opts.allowStaticWhenClientUnavailable ~= false),
    blockDisputedStaticWithoutLive = (opts.blockDisputedStaticWithoutLive == true),
    liveSellPriceLookup = opts.liveSellPriceLookup,
    learnedProfessions = opts.learnedProfessions,
    learnedRecipes = opts.learnedRecipes,
    ownedTools = opts.ownedTools,
    stationAvailable = opts.stationAvailable,
    reservedUnits = opts.reservedUnits,
    itemProtected = opts.itemProtected,
    assumeTrainerRecipesLearned = opts.assumeTrainerRecipesLearned,
  })

  local effectiveVendorable = fallbackInfo.directVendorAvailable == true
  local effectiveVendorCopper = fallbackInfo.directVendorUnitCopper or 0

  local effectiveUnitAsk = math.max(1, math.floor(entryCost1Lot / acquiredUnits1Lot))
  local vendorRatioBps = MA.ComputeVendorFloorRatioBps(
    effectiveUnitAsk,
    effectiveVendorable,
    effectiveVendorable and effectiveVendorCopper or nil
  )

  local depressionBps = nil
  local priceDepressed = false
  local histDays = tonumber(opts.comparableHistoryDays) or 0
  local histMedianAsk = opts.historicalMedianAskCopper
  if histDays >= SupplyGlutResearch.MIN_COMPARABLE_HISTORY_DAYS
    and MA.IsSafeIntegerCopper(histMedianAsk)
    and histMedianAsk > 0
  then
    depressionBps = math.floor((effectiveUnitAsk * 10000) / histMedianAsk)
    priceDepressed = (depressionBps <= SupplyGlutResearch.PRICE_DEPRESSION_THRESHOLD_BPS)
  end
  local nearVendorFloor = (vendorRatioBps ~= nil and vendorRatioBps <= 13000)

  local supplyRatioBps = nil
  local supplyExpanded = false
  local obsActiveUnits = opts.observedActiveUnits
  local histMedianUnits = opts.historicalMedianUnits
  if MA.IsSafeIntegerCopper(obsActiveUnits) and obsActiveUnits >= 0
    and MA.IsSafeIntegerCopper(histMedianUnits) and histMedianUnits > 0
  then
    supplyRatioBps = math.floor((obsActiveUnits * 10000) / histMedianUnits)
    supplyExpanded = (supplyRatioBps >= SupplyGlutResearch.SUPPLY_EXPANSION_THRESHOLD_BPS)
  end

  local sinkCeiling = nil
  local bottleneckStarved = false
  if opts.accessibleProducerCapacity ~= nil then
    sinkCeiling = SupplyGlutResearch.ComputeCraftableSinkCeiling(
      opts.accessibleProducerCapacity,
      opts.bottleneckSupplies
    )
    if sinkCeiling ~= nil and MA.IsSafeIntegerCopper(obsActiveUnits) then
      bottleneckStarved = (sinkCeiling == 0) or (obsActiveUnits > math.max(1, sinkCeiling * 3))
    end
  end

  local capacityMeasured = ladderMeasured
    and MA.IsSafeIntegerCopper(opts.aggregateRealmCapacityUnits)
    and opts.aggregateRealmCapacityUnits > 0

  local dimensions = {
    priceDepressionBps = depressionBps,
    priceDepressed = priceDepressed,
    nearVendorFloor = nearVendorFloor,
    supplyExpansionBps = supplyRatioBps,
    supplyExpanded = supplyExpanded,
    accessibleSinkVerified = spec.accessibleSinkVerified == true,
    demandRecurrence = spec.demandRecurrence,
    byproductOrPerkFloodRisk = spec.byproductOrPerkFloodRisk == true,
    bottleneckStarved = bottleneckStarved,
    fallbackAvailable = fallbackInfo.fallbackAvailable,
    fallbackType = fallbackInfo.fallbackType,
    capacityMeasured = capacityMeasured,
  }

  local classification
  local reason
  if not priceDepressed and not nearVendorFloor then
    classification = "INSUFFICIENT_EVIDENCE"
    reason = "price_not_depressed_or_history_short"
  elseif spec.demandRecurrence == "one_time_durable"
    or spec.accessibleSinkVerified ~= true
    or bottleneckStarved
    or (spec.byproductOrPerkFloodRisk == true and supplyExpanded)
  then
    classification = "STRUCTURAL_OVERSUPPLY_RISK"
    reason = "durable_saturation_or_byproduct_or_bottleneck_cap"
  elseif priceDepressed and supplyExpanded and spec.accessibleSinkVerified == true and spec.demandRecurrence == "recurring_consumable" then
    classification = "PLAUSIBLE_TEMPORARY_GLUT"
    reason = "depressed_ask_with_expanded_supply_and_verified_recurring_sink"
  else
    classification = "OBSERVED_LOW_PRICE"
    reason = "low_observed_ask_without_confirmed_temporary_glut"
  end

  return buildResearchCard(
    spec,
    resolvedKey,
    classification,
    reason,
    effectiveUnitAsk,
    vendorRatioBps,
    fallbackInfo,
    dimensions,
    sinkCeiling,
    capacityMeasured
  )
end

function SupplyGlutResearch.EvaluateCuratedWatchlist(opts)
  opts = type(opts) == "table" and opts or {}
  local pricesByItemID = type(opts.observedPricesByItemID) == "table" and opts.observedPricesByItemID or {}
  local historyByItemID = type(opts.historyByItemID) == "table" and opts.historyByItemID or {}
  local catalog = opts.includeFullPlaybook == true
    and SupplyGlutResearch.GetPlaybookCatalog(opts.playbookCategory or "ALL")
    or SupplyGlutResearch.CURATED_WATCHLIST

  local results = {}
  for _, spec in ipairs(catalog) do
    local h = type(historyByItemID[spec.itemID]) == "table" and historyByItemID[spec.itemID] or {}
    local card = SupplyGlutResearch.EvaluateCandidate(spec, {
      observedUnitAskCopper = pricesByItemID[spec.itemID] or h.observedUnitAskCopper,
      ladderRungs = h.ladderRungs,
      historicalMedianAskCopper = h.historicalMedianAskCopper,
      comparableHistoryDays = h.comparableHistoryDays,
      observedActiveUnits = h.observedActiveUnits,
      historicalMedianUnits = h.historicalMedianUnits,
      accessibleProducerCapacity = h.accessibleProducerCapacity,
      bottleneckSupplies = h.bottleneckSupplies,
      fallbackOperationsCostCopper = h.fallbackOperationsCostCopper,
      aggregateRealmCapacityUnits = h.aggregateRealmCapacityUnits,
      blockedWritByItemID = opts.blockedWritByItemID,
      learnedProfessions = opts.learnedProfessions,
      learnedRecipes = opts.learnedRecipes,
      ownedTools = opts.ownedTools,
      stationAvailable = opts.stationAvailable,
      blockDisputedStaticWithoutLive = opts.blockDisputedStaticWithoutLive,
      liveSellPriceLookup = opts.liveSellPriceLookup,
    })
    if card then
      table.insert(results, card)
    end
  end
  return results
end

-- ============================================================================
-- Astra P1: Waylaid Crate Option & Craft Substitution Comparison Engine
--   - Evaluates all 30 Waylaid Crates in `FH.Data.cratesByItemID`
--   - Distinguishes `cheapestKnownOption` from `verifiedGlobalCheapestOption`
--   - Never treats missing prices as zero
--   - Enforces executable depth at required quantity (`INSUFFICIENT_DEPTH` when unit-only)
--   - Evaluates accessible vs locked crafting routes (`LOCKED_RECIPE` when missing prof/skill)
--   - Accounts for gross outlay, leftover inventory, owned-material opportunity cost,
--     reservation protection, and seller failed-listing deposit loss (`D_lost`)
-- ============================================================================

SupplyGlutResearch.CRATE_CRAFT_RECIPES = {
  [2996] = {
    recipeID = "craft_bolt_of_linen",
    professionKey = "TAILORING",
    minSkill = 1,
    outputItemID = 2996,
    outputQuantity = 1,
    quantityVerified = true,
    reagents = { { itemID = 2589, name = "Linen Cloth", quantity = 2 } },
  },
  [2997] = {
    recipeID = "craft_bolt_of_woolen",
    professionKey = "TAILORING",
    minSkill = 75,
    outputItemID = 2997,
    outputQuantity = 1,
    quantityVerified = true,
    reagents = { { itemID = 2592, name = "Wool Cloth", quantity = 3 } },
  },
  [4305] = {
    recipeID = "craft_bolt_of_silk",
    professionKey = "TAILORING",
    minSkill = 125,
    outputItemID = 4305,
    outputQuantity = 1,
    quantityVerified = true,
    reagents = { { itemID = 4306, name = "Silk Cloth", quantity = 4 } },
  },
  [4339] = {
    recipeID = "craft_bolt_of_mageweave",
    professionKey = "TAILORING",
    minSkill = 175,
    outputItemID = 4339,
    outputQuantity = 1,
    quantityVerified = true,
    reagents = { { itemID = 4338, name = "Mageweave Cloth", quantity = 5 } },
  },
  [14048] = {
    recipeID = "craft_bolt_of_runecloth",
    professionKey = "TAILORING",
    minSkill = 250,
    outputItemID = 14048,
    outputQuantity = 1,
    quantityVerified = true,
    reagents = { { itemID = 14047, name = "Runecloth", quantity = 5 } },
  },
  [4233] = {
    recipeID = "craft_cured_medium_hide",
    professionKey = "LEATHERWORKING",
    minSkill = 100,
    outputItemID = 4233,
    outputQuantity = 1,
    quantityVerified = true,
    reagents = {
      { itemID = 4232, name = "Medium Hide", quantity = 1 },
      { itemID = 4289, name = "Salt", quantity = 1, isMerchantReagent = true },
    },
  },
  [4236] = {
    recipeID = "craft_cured_heavy_hide",
    professionKey = "LEATHERWORKING",
    minSkill = 150,
    outputItemID = 4236,
    outputQuantity = 1,
    quantityVerified = true,
    reagents = {
      { itemID = 4235, name = "Heavy Hide", quantity = 1 },
      { itemID = 4289, name = "Salt", quantity = 3, isMerchantReagent = true },
    },
  },
  [8172] = {
    recipeID = "craft_cured_thick_hide",
    professionKey = "LEATHERWORKING",
    minSkill = 200,
    outputItemID = 8172,
    outputQuantity = 1,
    quantityVerified = true,
    reagents = {
      { itemID = 8169, name = "Thick Hide", quantity = 1 },
      { itemID = 8150, name = "Deeprock Salt", quantity = 1 },
    },
  },
}

function SupplyGlutResearch.ComputeSellerRealizedNetProfit(saleGrossCopper, acquisitionCostCopper, lostDepositsCopper, opsCostCopper, ahCutRate)
  local f = tonumber(ahCutRate) or 0.05
  local s = math.max(0, math.floor(tonumber(saleGrossCopper) or 0))
  local c = math.max(0, math.floor(tonumber(acquisitionCostCopper) or 0))
  local dLost = math.max(0, math.floor(tonumber(lostDepositsCopper) or 0))
  local o = math.max(0, math.floor(tonumber(opsCostCopper) or 0))
  local netAfterFee = math.floor((s * (1.0 - f)) + 0.5)
  -- Astra P1: Successful deposits are refunded; only failed/cancelled listing deposits (D_lost) reduce profit:
  return netAfterFee - c - dLost - o
end

function SupplyGlutResearch.EvaluateCrateSubstituteSpreads(opts)
  opts = type(opts) == "table" and opts or {}
  local MA = ns.Domain and ns.Domain.MarketAccounting
  local VA = ns.Domain and ns.Domain.VendorArbitrage
  local econ = ns.EconomyData
  local cratesMap = opts.cratesByItemID or (ns.Data and ns.Data.cratesByItemID) or {}

  local laddersByItemID = type(opts.laddersByItemID) == "table" and opts.laddersByItemID or {}
  local pricesByItemID = type(opts.observedPricesByItemID) == "table" and opts.observedPricesByItemID or {}
  local ownedByItemID = type(opts.ownedByItemID) == "table" and opts.ownedByItemID or {}
  local reservedByItemID = type(opts.reservedByItemID) == "table" and opts.reservedByItemID or {}
  local learnedProfessions = type(opts.learnedProfessions) == "table" and opts.learnedProfessions or {}
  local learnedRecipes = type(opts.learnedRecipes) == "table" and opts.learnedRecipes or nil
  local tierFilter = opts.tierFilter
  local marketIdentity = opts.marketIdentity or "UNVERIFIED_MARKET_IDENTITY"
  local snapshotAgeSeconds = tonumber(opts.snapshotAgeSeconds)

  local crateIDs = {}
  for cid in pairs(cratesMap) do
    local numID = tonumber(cid)
    if numID then
      table.insert(crateIDs, numID)
    end
  end
  table.sort(crateIDs)

  local crateResults = {}
  for _, cid in ipairs(crateIDs) do
    local crate = cratesMap[cid]
    if type(crate) == "table" and (not tierFilter or crate.tier == tierFilter) then
      local pricedAlternatives = {}
      local missingAlternatives = {}
      local anyQuarantined = false
      local anyInsufficientDepth = false
      local anyLockedRecipe = false
      local allOptionsExecutableDepth = true

      local alts = type(crate.alternatives) == "table" and crate.alternatives or {}
      for optIdx, alt in ipairs(alts) do
        local mat = (type(alt.materials) == "table" and alt.materials[1]) or nil
        if mat and mat.itemID and mat.quantity then
          local itemID = tonumber(mat.itemID)
          local reqQty = math.max(1, math.floor(tonumber(mat.quantity) or 1))
          local isQuarantined = (VA and VA.GetQuarantinedItem and VA.GetQuarantinedItem(itemID) ~= nil) or false
          if isQuarantined then
            anyQuarantined = true
          end

          local ownedTotal = math.max(0, math.floor(tonumber(ownedByItemID[itemID]) or 0))
          local reservedTotal = math.max(0, math.floor(tonumber(reservedByItemID[itemID]) or 0))
          local unreservedOwned = math.max(0, ownedTotal - reservedTotal)
          local netBuyNeeded = math.max(0, reqQty - unreservedOwned)
          local usedOwnedUnits = reqQty - netBuyNeeded

          local econTuple = (econ and econ.items and econ.items[itemID]) or nil
          local unitVendorFloor = econTuple and tonumber(econTuple[1]) or 0
          local ahUnitQuote = tonumber(pricesByItemID[itemID])

          -- 1. Evaluate Direct Finished-Item AH Purchase at Required Quantity:
          local ladder = laddersByItemID[itemID]
          local directOutlayCopper = nil
          local leftoverUnits = 0
          local depthVerified = false
          local unitMinBundleEstimateCopper = nil

          if netBuyNeeded == 0 then
            directOutlayCopper = 0
            depthVerified = true
          elseif type(ladder) == "table" and #ladder > 0 and MA then
            local walk = MA.WalkAskLadderEntryCost(ladder, netBuyNeeded, false, nil)
            if walk and walk.sufficientDepth == true and walk.entryCostCopper then
              directOutlayCopper = walk.entryCostCopper
              leftoverUnits = math.max(0, (walk.acquiredUnits or netBuyNeeded) - netBuyNeeded)
              depthVerified = true
            else
              anyInsufficientDepth = true
              allOptionsExecutableDepth = false
            end
          elseif ahUnitQuote and ahUnitQuote > 0 then
            -- Unit minimum price without depth ladder: never treat as executable depth!
            unitMinBundleEstimateCopper = ahUnitQuote * netBuyNeeded
            anyInsufficientDepth = true
            allOptionsExecutableDepth = false
          else
            allOptionsExecutableDepth = false
          end

          -- Owned-material opportunity cost (`max(vendorFloor, 0.95 * ahUnitQuote)`):
          local ownedUnitOppCost = unitVendorFloor
          if ahUnitQuote and ahUnitQuote > 0 then
            local netAhUnit = math.floor((ahUnitQuote * 0.95) + 0.5)
            if netAhUnit > ownedUnitOppCost then
              ownedUnitOppCost = netAhUnit
            end
          end
          local ownedOpportunityCostCopper = usedOwnedUnits * ownedUnitOppCost

          -- 2. Evaluate Accessible Crafting Route (if one exists for this crate option):
          local craftSpec = SupplyGlutResearch.CRATE_CRAFT_RECIPES[itemID]
          local craftEvaluation = nil
          if craftSpec then
            local profRank = tonumber(learnedProfessions[craftSpec.professionKey]) or 0
            local recipeLearnedOk = (type(learnedRecipes) ~= "table") or (learnedRecipes[craftSpec.recipeID] == true)
            if profRank < craftSpec.minSkill or not recipeLearnedOk or craftSpec.quantityVerified ~= true then
              anyLockedRecipe = true
              craftEvaluation = {
                recipeID = craftSpec.recipeID,
                professionKey = craftSpec.professionKey,
                minSkill = craftSpec.minSkill,
                accessible = false,
                status = "LOCKED_RECIPE",
                reason = (profRank < craftSpec.minSkill)
                  and string.format("Requires %s %d (character has %d)", craftSpec.professionKey, craftSpec.minSkill, profRank)
                  or "Recipe not learned or unverified",
              }
            else
              local batchesNeeded = math.ceil(netBuyNeeded / math.max(1, craftSpec.outputQuantity))
              local craftGrossOutlay = 0
              local craftAllPriced = true
              local craftDepthVerified = true
              for _, rg in ipairs(craftSpec.reagents) do
                local rgNeeded = batchesNeeded * rg.quantity
                if rg.isMerchantReagent and econ and econ.merchantOffers and econ.merchantOffers[rg.itemID] then
                  local off = econ.merchantOffers[rg.itemID]
                  local uBuy = math.ceil(tonumber(off[1]) / math.max(1, tonumber(off[2]) or 1))
                  craftGrossOutlay = craftGrossOutlay + (rgNeeded * uBuy)
                else
                  local rgLadder = laddersByItemID[rg.itemID]
                  local rgQuote = tonumber(pricesByItemID[rg.itemID])
                  if type(rgLadder) == "table" and #rgLadder > 0 and MA then
                    local rgWalk = MA.WalkAskLadderEntryCost(rgLadder, rgNeeded, false, nil)
                    if rgWalk and rgWalk.sufficientDepth == true and rgWalk.entryCostCopper then
                      craftGrossOutlay = craftGrossOutlay + rgWalk.entryCostCopper
                    else
                      craftAllPriced = false
                      craftDepthVerified = false
                    end
                  elseif rgQuote and rgQuote > 0 then
                    craftGrossOutlay = craftGrossOutlay + (rgNeeded * rgQuote)
                    craftDepthVerified = false
                  else
                    craftAllPriced = false
                    craftDepthVerified = false
                  end
                end
              end
              craftEvaluation = {
                recipeID = craftSpec.recipeID,
                professionKey = craftSpec.professionKey,
                minSkill = craftSpec.minSkill,
                accessible = true,
                status = craftAllPriced and (craftDepthVerified and "ACCESSIBLE_EXECUTABLE" or "ACCESSIBLE_UNIT_ESTIMATE") or "MISSING_REAGENT_PRICES",
                craftGrossOutlayCopper = craftAllPriced and craftGrossOutlay or nil,
                depthVerified = craftDepthVerified,
              }
            end
          end

          -- Seller 24h deposit estimate (60% of NPC vendor sell value in Classic, refunded on sale, lost on expiry):
          local bundleVendorCopper = unitVendorFloor * reqQty
          local estimated24hDepositCopper = math.floor((bundleVendorCopper * 0.60) + 0.5)

          local effectiveComparisonCopper = directOutlayCopper
            and (directOutlayCopper + ownedOpportunityCostCopper)
            or (unitMinBundleEstimateCopper and (unitMinBundleEstimateCopper + ownedOpportunityCostCopper) or nil)

          if craftEvaluation and craftEvaluation.accessible and craftEvaluation.craftGrossOutlayCopper then
            local totalCraftEconomicCost = craftEvaluation.craftGrossOutlayCopper + ownedOpportunityCostCopper
            if not effectiveComparisonCopper or totalCraftEconomicCost < effectiveComparisonCopper then
              effectiveComparisonCopper = totalCraftEconomicCost
            end
          end

          local optionRecord = {
            optionIndex = alt.optionIndex or optIdx,
            label = alt.label or string.format("%s x%d", tostring(mat.name or itemID), reqQty),
            itemID = itemID,
            itemName = mat.name,
            requiredQuantity = reqQty,
            ownedQuantity = ownedTotal,
            reservedQuantity = reservedTotal,
            unreservedOwnedUsed = usedOwnedUnits,
            netPurchaseQuantity = netBuyNeeded,
            leftoverUnits = leftoverUnits,
            executablePurchaseOutlayCopper = directOutlayCopper,
            unitMinBundleEstimateCopper = unitMinBundleEstimateCopper,
            ownedOpportunityCostCopper = ownedOpportunityCostCopper,
            effectiveTotalCostCopper = effectiveComparisonCopper,
            depthVerified = depthVerified,
            quarantined = isQuarantined,
            craftRoute = craftEvaluation,
            estimated24hSellerDepositCopper = estimated24hDepositCopper,
          }

          if not isQuarantined and effectiveComparisonCopper ~= nil then
            table.insert(pricedAlternatives, optionRecord)
          else
            table.insert(missingAlternatives, optionRecord)
          end
        end
      end

      table.sort(pricedAlternatives, function(a, b)
        if a.effectiveTotalCostCopper ~= b.effectiveTotalCostCopper then
          return a.effectiveTotalCostCopper < b.effectiveTotalCostCopper
        end
        return (a.optionIndex or 0) < (b.optionIndex or 0)
      end)

      local cheapestKnown = pricedAlternatives[1]
      local secondKnown = pricedAlternatives[2]
      local isCompleteCoverage = (#missingAlternatives == 0 and #pricedAlternatives == #alts and #alts > 0)
      local verifiedGlobalCheapest = (isCompleteCoverage and allOptionsExecutableDepth and not anyQuarantined)
        and cheapestKnown
        or nil

      local runnerUpSpreadCopper = (cheapestKnown and secondKnown)
        and (secondKnown.effectiveTotalCostCopper - cheapestKnown.effectiveTotalCostCopper)
        or nil

      local outcome
      if anyQuarantined then
        outcome = "QUARANTINED"
      elseif #pricedAlternatives == 0 then
        outcome = "NO_PRICES"
      elseif not isCompleteCoverage then
        outcome = "PARTIAL_COVERAGE"
      elseif anyInsufficientDepth then
        outcome = "INSUFFICIENT_DEPTH"
      elseif anyLockedRecipe then
        outcome = "LOCKED_RECIPE"
      else
        outcome = "COMPLETE_COVERAGE"
      end

      table.insert(crateResults, {
        crateItemID = cid,
        name = crate.name,
        shortName = crate.shortName,
        tier = crate.tier,
        category = crate.category,
        requiredLevel = crate.requiredLevel,
        binding = crate.binding or "soulbound",
        regularTurninGrantsReputation = (crate.regularTurninGrantsReputation == true),
        rewardCurrency = crate.rewardCurrency or "Merchant's Favor",
        isArtisanPartsCrate248713 = (cid == 248713),
        namespaceClarificationNote = (cid == 248713)
          and "Item 248713 is 'Waylaid Crate: Artisan Parts' (engineering parts crate), not a currency ID."
          or nil,
        outcome = outcome,
        totalOptionCount = #alts,
        pricedOptionCount = #pricedAlternatives,
        missingOptionCount = #missingAlternatives,
        pricedAlternatives = pricedAlternatives,
        missingAlternatives = missingAlternatives,
        cheapestKnownOption = cheapestKnown,
        verifiedGlobalCheapestOption = verifiedGlobalCheapest,
        runnerUpSpreadCopper = runnerUpSpreadCopper,
        spreadSemantics = "BUYER_SUBSTITUTION_ALTERNATIVE_NOT_FLIPPER_PROFIT",
        marketIdentity = marketIdentity,
        snapshotAgeSeconds = snapshotAgeSeconds,
        quantityConfidence = (isCompleteCoverage and allOptionsExecutableDepth) and "EXECUTABLE_LADDER_DEPTH" or "INCOMPLETE_OR_SUMMARY_ONLY",
      })
    end
  end

  return crateResults
end

return SupplyGlutResearch
