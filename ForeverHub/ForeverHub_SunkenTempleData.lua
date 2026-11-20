local addonName, ns = ...
ns = ns or _G.ForeverHub or {}

local SunkenTempleData = {
  SCHEMA = "foreverhub-sunken-temple-data-v1",
  SUNKEN_TEMPLE_INSTANCE_ID = 109,

  REFERENCE_VIDEO = {
    title = "How I Turned Sunken Temple Into a Mage Gold Mine (70K XP + 80G/HR) | WoW Forever",
    creator = "Broog",
    sourceUrl = "https://www.youtube.com/watch?v=ThMKbcktgdw",
    recordedCharacter = "Horde Orc Mage (Lv 56-57)",
    targetCharacter = "Alliance Gnome Frost Mage (Lv 54)",
    prepChecklist = "Weapon: Revelation · Boots: Minor Speed · Spells: Ice Barrier, Mana Shield, Dampen Magic, Mage Armor, R1 & Max Blizzard, R1 Frostbolt, Ice Lance, Counterspell, Cold Snap, Ice Block, Evocation · Consumables: Mana Gems, Mana/Health Potions, Food XP Buff (eat inside at 04:16), optional Swiftness Potion",
    allianceApproach = "Alliance approach: Duskwood -> Deadwind Pass -> Swamp of Sorrows (or Nethergarde Keep FP -> north into Swamp of Sorrows) -> Pool of Tears sunken temple stairs -> swim underwater archway -> spiral ramp to instance portal.",
  },

  -- Diagnostic hint only for unresolved entries; NEVER arms the coach without verified instanceID == 109 (ST-01).
  LOCALIZED_NAME_HINTS = {
    ["the temple of atal'hakkar"] = true,
    ["temple of atal'hakkar"] = true,
    ["sunken temple"] = true,
  },

  -- Positive sighting dictionary ONLY (ST-06): absence of a sighting NEVER implies reset, death, or patrol position.
  KNOWN_NPCS_BY_ID = {
    [5709] = "Shade of Eranikus",
    [5710] = "Jammal'an the Prophet",
    [5719] = "Morphaz",
    [5720] = "Weaver",
    [5721] = "Dreamscythe",
    [5722] = "Hazzas",
  },

  KNOWN_DRAGON_NAMES_LOWER = {
    ["dreamscythe"] = "Dreamscythe",
    ["weaver"] = "Weaver",
    ["morphaz"] = "Morphaz",
    ["hazzas"] = "Hazzas",
    ["shade of eranikus"] = "Shade of Eranikus",
  },

  -- Classic/Forever Mage spell ID fallback map for readable player cast/aura tagging.
  -- Live spell-name resolution takes precedence when readable; tags establish cast/sample observation ONLY (never ticks/absorb/slow uptime).
  SPELL_KEY_BY_ID = {
    [10] = "blizzard",
    [6141] = "blizzard",
    [8427] = "blizzard",
    [10185] = "blizzard",
    [10186] = "blizzard",
    [10187] = "blizzard",
    [11426] = "ice_barrier",
    [13031] = "ice_barrier",
    [13032] = "ice_barrier",
    [13033] = "ice_barrier",
    [1463] = "mana_shield",
    [8494] = "mana_shield",
    [8495] = "mana_shield",
    [10191] = "mana_shield",
    [10192] = "mana_shield",
    [10193] = "mana_shield",
    [11958] = "ice_block",
    [45438] = "ice_block",
    [12472] = "cold_snap",
    [235219] = "cold_snap",
    [122] = "frost_nova",
    [865] = "frost_nova",
    [6131] = "frost_nova",
    [10230] = "frost_nova",
    [120] = "cone_of_cold",
    [8492] = "cone_of_cold",
    [10159] = "cone_of_cold",
    [10160] = "cone_of_cold",
    [10161] = "cone_of_cold",
    [604] = "dampen_magic",
    [8450] = "dampen_magic",
    [8451] = "dampen_magic",
    [10173] = "dampen_magic",
    [10174] = "dampen_magic",
    [6143] = "frost_ward",
    [8461] = "frost_ward",
    [8462] = "frost_ward",
    [10177] = "frost_ward",
    [28609] = "frost_ward",
    [6117] = "mage_armor",
    [22782] = "mage_armor",
    [22783] = "mage_armor",
    [1953] = "blink",
    [2139] = "counterspell",
    [12051] = "evocation",
    [116] = "frostbolt",
  },

  SPELL_KEY_BY_EN_NAME_LOWER = {
    ["blizzard"] = "blizzard",
    ["ice barrier"] = "ice_barrier",
    ["mana shield"] = "mana_shield",
    ["ice block"] = "ice_block",
    ["cold snap"] = "cold_snap",
    ["frost nova"] = "frost_nova",
    ["cone of cold"] = "cone_of_cold",
    ["dampen magic"] = "dampen_magic",
    ["frost ward"] = "frost_ward",
    ["mage armor"] = "mage_armor",
    ["blink"] = "blink",
    ["counterspell"] = "counterspell",
    ["evocation"] = "evocation",
    ["frostbolt"] = "frostbolt",
    ["ice lance"] = "ice_lance",
    ["revelation"] = "revelation",
    ["nature protection"] = "nature_protection",
  },

  -- Strict RC1 Phase Checkpoints anchored to Broog's WoW: Forever guide (ST-05 & ST-10):
  -- Static entries default to `verificationState = "video_candidate"` (`liveConfirmedOnPlayerCharacter = false`)
  -- because Broog recorded on an Orc Mage (Lv 56-57) while the target character is an Alliance Gnome Frost Mage (Lv 54).
  -- Actionable cues remain gated behind `ST-10` until confirmed live on the player's Gnome (`/fh st confirm`).
  -- Notice: Unverified Post #9 shield-proc claims remain strictly excluded per Astra P0-4.
  PHASES = {
    {
      index = 1,
      phaseID = "APPROACH_SANCTUARY",
      shortTitle = "Entrance -> Reset #1",
      title = "1. Entrance Run to Reset Ledge #1",
      glyph = "travel",
      actionableKind = "traversal",
      verificationState = "video_candidate",
      locale = "enUS",
      checkpointPrompt = "Checkpoint 1/6 [Broog 02:34-03:36 · Unconfirmed on Lv54 Gnome]: Ice Barrier + Mana Shield, Cone of Cold entrance pack (watch stairwell patrol hitting through stairs), drop off stairwell ledge through mob gap + Blink onto Reset Ledge #1; drink & refresh Dampen Magic.",
      gnomeLv54Note = "Lv54 Gnome check: wider aggro radius than Broog's Lv56-57 Orc at the 03:05 drop-down gap — center the gap cleanly before Blinking.",
      provenance = {
        sourceUrl = "https://www.youtube.com/watch?v=ThMKbcktgdw",
        creator = "Broog",
        timestamps = "02:34-03:36",
        recordedBuildOrDate = "WoW: Forever 1.60.1 (Broog Orc Mage Lv56-57)",
        liveConfirmedOnPlayerCharacter = false,
      },
      geometry = {
        approachLandmark = "Entrance Stairwell Drop-Off -> Lower Hall Reset Ledge #1",
        referencePose = "Face the lower dragonkin hall from the stairwell drop-off lip",
        actionableInstruction = "Drop through the open gap between lower packs, Blink forward onto Reset Ledge #1, drink to full mana, cast Dampen Magic, and wait for Ice Barrier cooldown",
        visibleSuccessCue = "Out of combat on Reset Ledge #1 with full mana, Dampen Magic active, and Ice Barrier ready",
        abortRoute = "Run back up entrance ramp to instance portal if stairwell patrol tags early",
      },
    },
    {
      index = 2,
      phaseID = "DRAGON_PATROL_CHECK",
      shortTitle = "Perimeter & Pre-RP Ledge",
      title = "2. Perimeter Ledge & Initial Dragon Despawn",
      glyph = "elite",
      actionableKind = "patrol_check",
      verificationState = "video_candidate",
      locale = "enUS",
      checkpointPrompt = "Checkpoint 2/6 [Broog 03:37-04:41 · Unconfirmed on Lv54 Gnome]: Run perimeter ledge with Ice Barrier ready, Blink + jump onto Pre-RP Ledge (if boss dragons don't de-aggro right away, shift toward Shade side until they despawn; they respawn back-left). Eat Food XP buff & wait for Ice Barrier CD.",
      gnomeLv54Note = "Lv54 Gnome check: verify Gnome jump clearance at the 04:01 perimeter-to-Pre-RP ledge hop (jump near the outer stone lip).",
      provenance = {
        sourceUrl = "https://www.youtube.com/watch?v=ThMKbcktgdw",
        creator = "Broog",
        timestamps = "03:37-04:41",
        recordedBuildOrDate = "WoW: Forever 1.60.1 (Broog Orc Mage Lv56-57)",
        liveConfirmedOnPlayerCharacter = false,
      },
      geometry = {
        approachLandmark = "Dragon Ring Perimeter Ledge -> Pre-RP Sanctuary Ledge",
        referencePose = "Face Shade of Eranikus's chamber from the perimeter ledge end",
        actionableInstruction = "Blink and jump onto the Pre-RP Ledge; if Dreamscythe/Weaver stay aggroed, move across the ledge toward Shade until they despawn, then eat Food XP buff and refresh Ice Barrier + Mana Shield",
        visibleSuccessCue = "Out of combat on Pre-RP Ledge, boss dragons despawned (respawning back-left), Food buff + shields ready, Ice Barrier off CD",
        abortRoute = "Hold on Pre-RP Ledge edge toward Shade alcove until boss dragons finish despawning",
      },
    },
    {
      index = 3,
      phaseID = "RP_AND_GATHER",
      shortTitle = "Start Shade RP -> Corner",
      title = "3. Trigger Shade RP & Move to Forever Corner Reset",
      glyph = "focus",
      actionableKind = "rp",
      verificationState = "video_candidate",
      locale = "enUS",
      checkpointPrompt = "Checkpoint 3/6 [Broog 04:42-05:33 · Unconfirmed on Lv54 Gnome]: Tag Keeper #1 with R1 Frostbolt + Keeper #2 with Ice Lance + Counterspell caster so neither leashes. Wait until Shade of Eranikus activates (04:56), then Blink onto the left ledge, turn left past wide-swinging patrols into the new Forever Corner Reset Spot.",
      gnomeLv54Note = "Lv54 Gnome check: ensure R1 Frostbolt + Ice Lance both land (watch Lv54 spell resist) so Keepers don't leash before Shade RP starts.",
      provenance = {
        sourceUrl = "https://www.youtube.com/watch?v=ThMKbcktgdw",
        creator = "Broog",
        timestamps = "04:42-05:33",
        recordedBuildOrDate = "WoW: Forever 1.60.1 (Broog Orc Mage Lv56-57)",
        liveConfirmedOnPlayerCharacter = false,
      },
      geometry = {
        approachLandmark = "Sanctuary Keeper Pair -> Left Ledge -> Forever Corner Reset Spot",
        referencePose = "Face Shade of Eranikus's alcove from the Pre-RP Ledge",
        actionableInstruction = "Pull first mob with Rank 1 Frostbolt, Ice Lance the second, Counterspell caster, wait visually for Shade of Eranikus RP movement, then Blink to the left ledge and take the left passage into the front corner reset spot",
        visibleSuccessCue = "Shade of Eranikus RP triggered and character tucked in the Forever Corner Reset Spot",
        abortRoute = "Blink immediately to the Forever Corner Reset Spot to drop trash and dragon aggro",
      },
    },
    {
      index = 4,
      phaseID = "BOSS_DRAGON_RESET",
      shortTitle = "Dragon Despawn & Gather",
      title = "4. Corner Dragon Despawn & Shade Room Gather + 2x Block",
      glyph = "info",
      actionableKind = "reset",
      verificationState = "video_candidate",
      locale = "enUS",
      checkpointPrompt = "Checkpoint 4/6 [Broog 05:34-07:35 · Unconfirmed on Lv54 Gnome]: At Forever Corner Reset, swap Mage Armor + Dampen + shields & drink. If boss dragons aggro from back-left, pull to the side and WAIT UNTIL THEY DESPAWN before gathering! Then R1 Blizzard mobs around Shade, Blink out, stay out of caster range, hop onto Kill Ledge -> Ice Block #1 -> Cold Snap -> Ice Block #2.",
      gnomeLv54Note = "Lv54 Gnome check: never gather Shade packs while Dreamscythe/Weaver are still up; wait for clean despawn window (05:45-06:05), then keep casters out of cast range down the hall.",
      provenance = {
        sourceUrl = "https://www.youtube.com/watch?v=ThMKbcktgdw",
        creator = "Broog",
        timestamps = "05:34-07:35",
        recordedBuildOrDate = "WoW: Forever 1.60.1 (Broog Orc Mage Lv56-57)",
        liveConfirmedOnPlayerCharacter = false,
      },
      geometry = {
        approachLandmark = "Forever Corner Reset Spot -> Shade Alcove -> Hallway Kill Ledge",
        referencePose = "Face Shade of Eranikus's room from the Forever Corner Reset Spot after boss dragons despawn",
        actionableInstruction = "Wait out any boss-dragon aggro at the side of the corner until they despawn; run to Shade and cast Rank 1 Blizzard, Blink back down the hall out of caster range, jump onto the Kill Ledge, Ice Block when melee arrive, then Cold Snap into instant second Ice Block and break out with Ice Barrier",
        visibleSuccessCue = "Full trash + whelp pack tightly stacked at Kill Ledge base with boss dragons unpulled",
        abortRoute = "Return to Forever Corner Reset Spot if boss dragons aggro mid-setup before Shade pull",
      },
    },
    {
      index = 5,
      phaseID = "KILL_LEDGE",
      shortTitle = "Kill Ledge & Pillar LoS",
      title = "5. Kill Ledge Juggle, Pillar Tuck & Revelation Burn",
      glyph = "kill",
      actionableKind = "jump",
      verificationState = "video_candidate",
      locale = "enUS",
      checkpointPrompt = "Checkpoint 5/6 [Broog 07:37-12:22 · Unconfirmed on Lv54 Gnome]: Hop off/on Kill Ledge to juggle pack — hop up as soon as mobs reach the 2nd floor line (never greed an extra Blizzard!). Don't camp the ledge too long (wall-wrap melee hazard at 10:08); tuck behind the line between the two pillars for caster LoS. Burn whelps first (AoE cap), then pop Revelation + Max Blizzard.",
      gnomeLv54Note = "Lv54 Gnome check: test the Kill Ledge hop-up spot out of combat first — Gnomes jump cleanly from the seam right beside the pillar base rather than flush against the high wall.",
      provenance = {
        sourceUrl = "https://www.youtube.com/watch?v=ThMKbcktgdw",
        creator = "Broog",
        timestamps = "07:37-12:22",
        recordedBuildOrDate = "WoW: Forever 1.60.1 (Broog Orc Mage Lv56-57)",
        liveConfirmedOnPlayerCharacter = false,
      },
      geometry = {
        approachLandmark = "Hallway Kill Ledge Between Twin Pillars",
        referencePose = "Face the oncoming hallway pack from the Kill Ledge between the two pillars",
        jumpTakeoff = "Hallway floor seam directly alongside the inner pillar base (Gnome-safe step-up point)",
        jumpLanding = "Upper Kill Ledge lip tucked behind the imaginary line between the two pillars",
        actionableInstruction = "Hop off/on the Kill Ledge to juggle mobs; hop back up once mobs cross the second floor line, tuck behind the two-pillar line to LoS casters without lingering long enough for wall-wrap melee, Counterspell lone stuck casters, Evocate on clean LoS, kill whelps to clear AoE cap, then pop Revelation + Max Blizzard",
        visibleSuccessCue = "Whelplings cleared, dragonkin pack burned down cleanly without caster volleys or wall-wrap hits",
        abortRoute = "Frost Nova / Cone of Cold + Blink back toward Forever Corner Reset Spot if ledge juggle desyncs",
      },
    },
    {
      index = 6,
      phaseID = "LOOT_EXIT",
      shortTitle = "Loot, Skin & Reset",
      title = "6. Quick Loot, Skinning & Instance Reset",
      glyph = "loot",
      actionableKind = "loot_exit",
      verificationState = "video_candidate",
      locale = "enUS",
      checkpointPrompt = "Checkpoint 6/6 [Broog 12:25-13:35 · Unconfirmed on Lv54 Gnome]: Quick-loot all corpses (~15g raw/run; watch for Edgemaster's Handguards & Pattern: Mooncloth Bag), skin dragonkin if Skinning (Pristine Scales / Rugged Leather), click Finish, exit portal, and Reset all instances.",
      gnomeLv54Note = "Check hourly 5-instance lockout counter in ForeverHub Dungeons panel before resetting.",
      provenance = {
        sourceUrl = "https://www.youtube.com/watch?v=ThMKbcktgdw",
        creator = "Broog",
        timestamps = "12:25-13:35",
        recordedBuildOrDate = "WoW: Forever 1.60.1 (Broog Orc Mage Lv56-57)",
        liveConfirmedOnPlayerCharacter = false,
      },
      geometry = {
        approachLandmark = "Cleared Hallway Kill Ledge -> Instance Portal",
        referencePose = "Face the entrance hallway from the cleared Kill Ledge",
        actionableInstruction = "Loot all corpses (and skin dragonkin if applicable), click Finish Attempt to log completion, run out the instance portal, and reset instances",
        visibleSuccessCue = "All loot collected, attempt marked complete, outside portal ready for fresh copy",
        abortRoute = "Exit instance portal directly if bag space is full",
      },
    },
  },
}

local function isNonEmptyTrimmedString(v)
  if type(v) ~= "string" then
    return false
  end
  return string.match(v, "%S") ~= nil
end

local function containsRelativeTurnWord(s)
  if type(s) ~= "string" then
    return false
  end
  local low = string.lower(s)
  return string.find(low, "%f[%a]left%f[%A]") ~= nil
    or string.find(low, "%f[%a]right%f[%A]") ~= nil
end

-- Gate ST-10 (Data Readiness) & ST-02 (Reference-Pose Honesty):
-- Unverified route entries (`pending_live_walk`, `probe_observed`, `video_candidate`, missing locale,
-- missing provenance, missing geometry, or `liveConfirmedOnPlayerCharacter ~= true`) CANNOT render
-- as live-verified cues. Probe results NEVER satisfy this content gate.
function SunkenTempleData.ValidateStepDataReadiness(step, clientLocale)
  if type(step) ~= "table" then
    return false, "invalid_step"
  end
  if step.verificationState == "probe_observed" then
    return false, "probe_does_not_prove_route_readiness"
  end
  if step.verificationState ~= "live_confirmed" then
    return false, "unverified_route_entry"
  end
  if not isNonEmptyTrimmedString(clientLocale) then
    return false, "missing_client_locale"
  end

  local prov = step.provenance
  if type(prov) ~= "table" then
    return false, "missing_provenance"
  end
  if not isNonEmptyTrimmedString(prov.sourceUrl)
    or not isNonEmptyTrimmedString(prov.timestamps)
    or not isNonEmptyTrimmedString(prov.recordedBuildOrDate)
  then
    return false, "incomplete_provenance_metadata"
  end
  if prov.liveConfirmedOnPlayerCharacter ~= true then
    return false, "missing_live_character_confirmation"
  end

  local geom = nil
  if step.locale == clientLocale and type(step.geometry) == "table" then
    geom = step.geometry
  elseif type(step.localizedGeometry) == "table" and type(step.localizedGeometry[clientLocale]) == "table" then
    geom = step.localizedGeometry[clientLocale]
  end
  if type(geom) ~= "table" then
    return false, "missing_localized_geometry"
  end

  if not isNonEmptyTrimmedString(geom.approachLandmark)
    or not isNonEmptyTrimmedString(geom.referencePose)
    or not isNonEmptyTrimmedString(geom.visibleSuccessCue)
    or not isNonEmptyTrimmedString(geom.abortRoute)
  then
    return false, "incomplete_checkpoint_geometry"
  end

  if step.actionableKind == "jump" or step.phaseID == "KILL_LEDGE" then
    if not isNonEmptyTrimmedString(geom.jumpTakeoff) or not isNonEmptyTrimmedString(geom.jumpLanding) then
      return false, "missing_jump_takeoff_or_landing"
    end
  end

  local instruction = geom.actionableInstruction or step.actionableInstruction
  if not isNonEmptyTrimmedString(instruction) then
    return false, "missing_actionable_instruction"
  end

  if containsRelativeTurnWord(instruction) and not isNonEmptyTrimmedString(geom.referencePose) then
    return false, "relative_direction_without_reference_pose"
  end

  return true, {
    approachLandmark = geom.approachLandmark,
    referencePose = geom.referencePose,
    actionableInstruction = instruction,
    visibleSuccessCue = geom.visibleSuccessCue,
    abortRoute = geom.abortRoute,
    jumpTakeoff = geom.jumpTakeoff,
    jumpLanding = geom.jumpLanding,
  }
end

ns.SunkenTempleData = SunkenTempleData
return SunkenTempleData
