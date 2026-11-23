# ForeverHub Changelog

## v0.9.0 (2026-11-22)
- **Cross-PC Raid-Readiness & Attunement Arrow Coach (`/fh raidready`):** Added `Domain.RaidReadinessCoach` driving the `240 × 48` Compact Tracker HUD step-by-step across the primary Onyxia + BRD Princess spine (`core_attune`) and parallel Linken + Maraudon Gizlock track (`linken_solo`) using server-authoritative 5-state quest resolution (`unknown`, `absent`, `active`, `ready_to_turn_in`, `turned_in`) and downstream evidence inference for zero-config Mac-to-Windows parity.
- **Non-Deadlocking Handoffs & Post-Boss Recovery Guards:** Advances the Burning Steppes field leg as soon as `12/12` Thaurissan Relics (`3701`) are collected and `4182` is turned in, supports both `6403` and `99435` Great Masquerade variants, verifies both `5102` kill credit and `Blood of the Black Dragon Champion (16663)` in bags after General Drakkisath, and audits `Drakefire Amulet (16309)` carrier status (`Onyxia attuned · amulet carried` vs. banked/missing recovery).
- **Instance Entry / Exit & Blackrock Spire Wing Disambiguation:** Automatically suppresses outdoor directional arrows and distances indoors while keeping the `240 × 48` tracker visible in `INSTANCE_OBJECTIVE` mode, disambiguates LBRS vs. UBRS inside Blackrock Spire, and suppresses Videre Elixir shopping when already in ghost form on Linken's `3912` graveyard leg.
- **Verified Build `70862` Gear & Tailoring Milestones:** Tracks Mooncloth unlock at Tailoring `230` (with Artisan `225 -> 300` cap raise reminder), separates `Robe of the Archmage` (`18457`, Tailoring `295`), and reconciles Forever `70862` weapon/gear baselines (`Spire of Hakkar` 62 SP, `Trindlehaven Staff 13161` 70 SP + 6 MP5, `Spellweaver's Turban 22267`, `Skyshroud Leggings 13170` 30 SP, `Eye of the Beast 13968` 1% crit + 7% hit use, `Nether Force Wand 11263` +9 Arcane SP).

## v0.8.9 (2026-11-20)
- **Portfolio & Profession Triage Engine (`/fh` -> `Research` -> `Portfolio`):** Classifies current bag, bank, and mailbox holdings into 6 deterministic action buckets (`VENDOR_ARBITRAGE_NOW`, `CRAFT_AND_VENDOR_NOW`, `CRAFT_FOR_SKILLUP`, `HOLD_FOR_SELF_USE`, `LIQUIDATE_OR_TEST_SPREAD`, `QUARANTINE_UNVERIFIED`), alongside a Top-20 Raid Investment Watchlist and a 3-tier Profession Roadmap (Skinning 275 -> 300, Tailoring 175 -> 250 Mooncloth cooldown planner, and Alchemy/Mining conversion analysis).
- **Optional Read-Only `BlackthornesBridge` (`Providers/BlackthornesBridge.lua`):** Safely reads `Blackthornes_TS_Data` character inventories, bank timestamps (`bankAt`), learned recipes, profession skill headers, and saved per-item AH price ladders with partial-scan and staleness disclosures.
- **Verified `1.60.1.70862` Economy Data & Custom Forever Conversion Spreads:** Reconciled saved-client `SellPrice` floors (`Fel Leather`, `Fel Hide`, `Rugged Hide`, `Pristine Hide`, `Pristine Scale`, `Black Mageweave Vest/Leggings`), quarantined disputed floors (`Bolt of Mageweave`, `Ironweb Spider Silk`, `Felcloth`), and wired verified Forever item IDs and yield-conflict guards for custom Alchemy elixirs, `Azerothium Bar`, `Ghost Dye`, and `Legionite`.
- **December 9, 2026 Raid Unlock Clock & Saved-Ladder Boundary Guards:** Corrected `DEC9_2026_RAID_UNLOCK_EPOCH` (`1796832000`) and enforced `rowPriceFixed` historical EMA-reset and flat-ladder stack-boundary guards in `SupplyGlutResearch`.

## v0.8.8 (2026-11-13)
- **Compact Tracker HUD (`240 × 48` Single-Row Bar):** Redesigned `ForeverHubRivergladesHUD` from `340 × 112` down to a streamlined `240 × 48` bar (~70% smaller screen footprint) showing only the directional arrow, clean quest/step title, distance/status line, and the `...` options button.
- **Eliminated Duplicate Step & Distance Text:** Line 1 displays only the clean quest or step name (full instructions, coordinates, objective counters, and provider details move to the hover tooltip), and `dockedArrowLane.distanceText` is permanently suppressed so distance is never duplicated or truncated under the arrow.
- **Table-Driven Status & Overflow Controls (`...`):** Added explicit state presentation for `Quest log full`, `Review in Workspace`, `Controlled by RXP`, `Position unavailable`, `Other instance`, `Paused`, and banked turn-in alerts (`%d in bank · Withdraw first`), plus **Pause / Resume navigation** and **Stop navigation** inside the scale-aware `...` menu.
- **Idempotent Schema v3 Width Migration:** Automatically upgrades legacy default `340` HUD width to `240` once while preserving custom widths in `[200, 440]`.

## v0.8.7 (2026-11-12)
- **Complete Riverglades & Krol'dok Quest Coverage:** Mapped and verified all **124 playable quests** (**330 active steps**) across Riverglades and Krol'dok, excluding only 6 confirmed unused/obsolete quest records.
- **World Map Pin Visibility Fix:** Fixed accepted Elite and bounty quests (including *Snargl's Snout* `94679`) so accepted quests always render active objective/turn-in map pins even when optional Available Elite discovery is toggled off.
- **2-Tier Coordinate Confidence & Live Auto-Snap:** Added clear `Search Area` badges (`subzone_verified`) alongside exact `artifact_verified` coordinates, plus live nameplate/mouseover/target coordinate auto-snap in `ForeverHubDB`.
- **In-Game Version & Update Drawer (`/fh`):** Added `Installed: v0.9.0`, local release notes, and a copyable `https://foreverhub.cc/addon` update link inside the Workspace diagnostics drawer.

## v0.8.6 (2026-11-11)
- Expanded Riverglades hub routing, Questie/TomTom coexistence guards, and custom uncompressed 32-bit RGBA `.tga` map/UI glyphs.
- Added standalone clean-room onboarding toast, minimap compass button, and Blizzard Addon Compartment integration.

## v0.8.5 (2026-11-10)
- Initial public friend-ready release of the 3-tab ForeverHub Workspace (Crates & Artisan's Writs, Riverglades Quest Chains, Gold & Mount Workspace, and Quest Reward Vendor Advisor).
