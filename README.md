# ForeverHub (v0.8.5) — World of Warcraft: Forever Addon

**ForeverHub** is a standalone, MIT-licensed addon for **World of Warcraft: Forever** (`Interface: 16001` / `1.60.1.70862`) with zero external network dependencies.

- **Official Website Download:** https://foreverhub.cc/addon
- **Standard Archive:** `ForeverHub-v0.8.5.zip` (`SHA-256`: `9cc774792af1b4b412399fb9801af32635d75b13563ef4cd9644c0b87bb8f501`)
- **WowUp Flavor Alias (Identical Bytes):** `ForeverHub-v0.8.5-forever.zip` (`SHA-256`: `9cc774792af1b4b412399fb9801af32635d75b13563ef4cd9644c0b87bb8f501`)

## Included Modules & Scope

| Module | Faction / Level Scope | Command |
|---|---|---|
| **3-Tab Workspace: Crates & Artisan's Writs** | All Factions & Classes (Lv 1–60) | `/fh` |
| **Riverglades Quest Chains, Auto-Advance & World Map Pins** | Alliance (Lv 36–47 · Full Zone Hubs & Bounties) | `/fh rg` |
| **Gold & Mount Workspace + Purse Rate Meter** | Alliance Mage (~Lv 40 · 5 Verified Candidate Spots) | `/fh gold` |
| **Quest Reward Vendor Advisor & Diagnostics** | All Factions & Classes (Lv 1–60) | `/fh doctor` |

## Installation

### Option 1 — Manual `.zip` Install (Recommended)
1. Close **World of Warcraft: Forever**.
2. Download `ForeverHub-v0.8.5.zip` from **Releases** (do *not* click `Code → Download ZIP`), or from https://foreverhub.cc/addon.
3. Use Battle.net's **Options → Show in Explorer** to open your WoW folder, then open `Interface/AddOns/` inside `_forever_` (if Explorer already opened `_forever_`, do not create a nested `_forever_` folder).
4. Extract the `.zip` to a temporary folder, copy the inner `ForeverHub` folder into `AddOns` (replacing any old `ForeverHub` folder while preserving `WTF/`), and verify this exact file path exists:
   ```text
   _forever_/Interface/AddOns/ForeverHub/ForeverHub.toc
   ```

### Option 2 — WowUp (`Install from URL` — Optional)
1. If your **WowUp** installation detects your **WoW Forever** (`_forever_`) client, click **Get Addons → Install from URL** and paste this GitHub repository URL.
   *(Releases include `ForeverHub-v0.8.5-forever.zip` matching WowUp's Classic-family `-forever` asset suffix convention; use Option 1 if your manager does not list `_forever_`.)*

## Maintainer Tag Protection Note
Configure a GitHub Repository Ruleset on `refs/tags/v*` blocking tag deletion and force-pushes so published release tags remain immutable.
