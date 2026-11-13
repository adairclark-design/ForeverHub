# ForeverHub (v0.8.7) — World of Warcraft: Forever Addon

**ForeverHub** is a standalone, MIT-licensed addon for **World of Warcraft: Forever** (`Interface: 16001` / `1.60.1.70862`) with zero external network dependencies.

- **Official Website & Fallback Installer:** https://foreverhub.cc/addon
- **WowUp / GitHub Release Archive:** `ForeverHub-v0.8.7-forever.zip` (`SHA-256`: `8766de142cdfb84c0ba3c328836596e208ad379622721a56bfe1e48153acb988`)
- **Website Standard Archive (Identical Bytes):** `ForeverHub-v0.8.7.zip` (`SHA-256`: `8766de142cdfb84c0ba3c328836596e208ad379622721a56bfe1e48153acb988`)

## Included Modules & Scope

| Module | Faction / Level Scope | Command |
|---|---|---|
| **3-Tab Workspace: Crates & Artisan's Writs** | All Factions & Classes (Lv 1–60) | `/fh` |
| **Riverglades Quest Chains, Auto-Advance & World Map Pins** | Alliance (Lv 36–47 · Full Zone Hubs & Bounties) | `/fh rg` |
| **Gold & Mount Workspace + Purse Rate Meter** | Alliance Mage (~Lv 40 · 5 Verified Candidate Spots) | `/fh gold` |
| **Quest Reward Vendor Advisor & Diagnostics** | All Factions & Classes (Lv 1–60) | `/fh doctor` |

## Installation & Updates

### Option 1 — WowUp (`Install from URL` — Ongoing 1-Click Updates)
Download WowUp from [wowup.io](https://wowup.io/). Either **WowUp with Wago** or **WowUp with CurseForge** supports this installation method; existing WowUp-CF users can keep it. Select **World of Warcraft: Forever** and verify its installation path. Close WoW, then choose **Get Addons → Install from URL** and paste `https://github.com/adairclark-design/ForeverHub`.

- **Wrong-Client Warning (`Retail` vs `Forever`):** GitHub Releases publish only `ForeverHub-v0.8.7-forever.zip`, its `.sha256` file, and `release.json` to prevent silent `Retail` matching. Because WowUp's URL dialog shows a warning alert when no asset matches the selected client but leaves the fallback Install button active, **click Cancel if you see a missing-asset / compatibility warning**, switch the client dropdown to **World of Warcraft: Forever**, and import again.
- **Do not paste a raw `.zip` URL into WowUp:** Installing a direct `.zip` link in WowUp performs a one-time ignored install that will never receive updates. Always paste `https://github.com/adairclark-design/ForeverHub`.

#### Migrating an Existing Manual Installation to WowUp
Do not rely on WowUp's *Re-scan Folders* to attach a manually installed folder to GitHub (`allowReScan = false`). Follow this safe adoption sequence:
1. **Close WoW completely.** Back up your existing `_forever_/Interface/AddOns/ForeverHub` folder and relevant account/character `WTF/Account/.../SavedVariables/ForeverHub.lua` (including `.bak`) files outside the game directory.
2. Verify WowUp's selected client points to your intended `_forever_` installation.
3. Choose **Get Addons → Install from URL** and install using `https://github.com/adairclark-design/ForeverHub`. *(If a folder conflict prevents adoption, move the old `AddOns/ForeverHub` folder outside `AddOns`, leave `WTF` untouched, and install again.)*
4. Confirm a single `AddOns/ForeverHub` folder, version `0.8.7`, and a persistent `GitHub` update source in WowUp.
5. Before launching WoW, verify your `SavedVariables` files remain unchanged, then launch WoW: Forever and check your existing settings.

### Option 2 — Manual `.zip` Install (Fallback)
1. **Close World of Warcraft: Forever** completely.
2. Download **`ForeverHub-v0.8.7-forever.zip`** from **Releases** under **Assets** (or `ForeverHub-v0.8.7.zip` from https://foreverhub.cc/addon). **Do not** download GitHub's automatic `Source code (zip)` / `Source code (tar.gz)` archives or click `Code → Download ZIP`.
3. Use Battle.net's **Options (⚙) → Show in Explorer / Reveal in Finder**, then open `_forever_/Interface/AddOns/` (create `Interface` and `AddOns` if missing; if Explorer already opened inside `_forever_`, do not create a nested `_forever_` folder).
4. Extract the `.zip` to a temporary folder, copy the inner `ForeverHub` folder into `AddOns` (replacing any old `ForeverHub` folder while leaving `WTF/` untouched), and verify this exact path exists before launching WoW:
   ```text
   _forever_/Interface/AddOns/ForeverHub/ForeverHub.toc
   ```

## Changelog
See [`CHANGELOG.md`](CHANGELOG.md) for release notes across `v0.8.5` – `v0.8.7`.

## Maintainer Security & Release Controls
- Default GitHub Actions permissions are restricted to `contents: read`; `contents: write` is granted solely to the tag-publishing job with `persist-credentials: false`.
- Repository Rulesets protect `main` and `refs/tags/v*` against deletion and force-pushes, and **GitHub Immutable Releases** lock published release assets and tags after publication.
