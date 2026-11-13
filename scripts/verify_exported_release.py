#!/usr/bin/env python3
"""
Closed-fail verifier & release-bundle builder for ForeverHub public GitHub Releases.

Enforces GPT Astra's Round-1, Round-2 & Round-3 Release Boundary Contract:
1. Validates strict SemVer `vX.Y.Z` tag syntax (no leading zeros, no `-src`) and parity with
   `ForeverHub.toc` (`## Version`, `## Interface: 16001`).
2. Validates `BUILD_MANIFEST.json` (`addonName`, `version`, strict `int` `interfaceVersion == 16001`,
   `targetClientBuild == "1.60.1.70862"`, 40-hex `gitCommitSha`).
3. When inside a git repository (or when `--require-source-tag` is passed), resolves the
   peeled `refs/tags/vX.Y.Z-src^{commit}`, requires `gitCommitSha` to equal that commit,
   and verifies every archive member's payload bytes directly against the `vX.Y.Z-src`
   git tree (not merely the checked-out working tree).
4. Validates `dist/release.json` closed-fail (`nolib is False`, strict `int` `interface == 16001`,
   `version == "vX.Y.Z"`, `filename == "ForeverHub-vX.Y.Z-forever.zip"`) AND enforces
   byte-for-byte identity with canonical emitted `release.json`.
5. Extracts the exact `## vX.Y.Z` section from `CHANGELOG.md` without shell interpolation,
   failing closed if missing or empty, and appends the manual-visitor download warning.
6. Enforces monotonic SemVer release ordering (`--reconcile-releases-json`) so a lower or
   already-published version can never be published after a higher stable release, and safely
   reconciles interrupted matching drafts without overwriting published releases or deleting
   unexpected drafts.
7. Verifies post-publication anonymous GitHub Release API state (`immutable is True`,
   `draft is False`, `prerelease is False`, exact 3 assets, and anonymous download byte parity).
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

REPO_DIR = Path(__file__).resolve().parent.parent
ADDON_DIR = REPO_DIR / "ForeverHub"
DIST_DIR = REPO_DIR / "dist"
CHANGELOG_PATH = REPO_DIR / "CHANGELOG.md"

TAG_RE = re.compile(r"^v((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))$")
HEX40_RE = re.compile(r"^[0-9a-f]{40}$")
REPO_SLUG_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
EXPECTED_INTERFACE_VERSION = 16001
EXPECTED_TARGET_CLIENT_BUILD = "1.60.1.70862"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse_semver_tag(tag: str) -> tuple[str, tuple[int, int, int]]:
    m_tag = TAG_RE.fullmatch(tag)
    if not m_tag:
        raise SystemExit(
            f"Invalid release tag syntax {tag!r}; expected strict semantic version vMAJOR.MINOR.PATCH (no leading zeros, never -src)"
        )
    ver_str = m_tag.group(1)
    parts = ver_str.split(".")
    return ver_str, (int(parts[0]), int(parts[1]), int(parts[2]))


def expected_release_metadata(version: str) -> dict[str, object]:
    return {
        "releases": [
            {
                "name": f"ForeverHub v{version}",
                "version": f"v{version}",
                "filename": f"ForeverHub-v{version}-forever.zip",
                "nolib": False,
                "metadata": [
                    {
                        "flavor": "forever",
                        "interface": EXPECTED_INTERFACE_VERSION,
                    }
                ],
            }
        ]
    }


def canonical_release_json_bytes(version: str) -> bytes:
    return (json.dumps(expected_release_metadata(version), indent=2, sort_keys=True) + "\n").encode("utf-8")


def extract_changelog_release_notes(changelog_path: Path, version: str) -> str:
    if changelog_path.is_symlink() or not changelog_path.is_file():
        raise SystemExit(f"Missing or invalid CHANGELOG.md: {changelog_path}")
    text = changelog_path.read_text(encoding="utf-8")
    header_re = re.compile(rf"^##\s+v?{re.escape(version)}(?:\s+\([^)]+\))?\s*$")
    any_h2_re = re.compile(r"^##\s+")

    in_section = False
    collected: list[str] = []
    heading_line = ""
    for line in text.splitlines():
        if not in_section:
            if header_re.match(line):
                in_section = True
                heading_line = line.strip()
        else:
            if any_h2_re.match(line):
                break
            collected.append(line)

    if not in_section:
        raise SystemExit(f"CHANGELOG.md missing required section heading for v{version}")

    body = "\n".join(collected).strip()
    if not body:
        raise SystemExit(f"CHANGELOG.md section for v{version} is empty")

    wowup_fname = f"ForeverHub-v{version}-forever.zip"
    visitor_note = (
        "---\n"
        f"**Download Note (Manual GitHub Visitors):** Download **`{wowup_fname}`** under "
        "**Assets** below (or visit https://foreverhub.cc/addon). Do **not** download GitHub's "
        "automatic `Source code (zip)` or `Source code (tar.gz)` archives, which wrap the "
        "repository root instead of the `ForeverHub` addon folder.\n"
    )
    return f"{heading_line}\n\n{body}\n\n{visitor_note}"


def verify_source_tag_tree(repo_dir: Path, version: str, expected_rel_files: list[str]) -> tuple[str, dict[str, bytes]]:
    src_tag = f"v{version}-src"
    rev_proc = subprocess.run(
        ["git", "-C", str(repo_dir), "rev-parse", "--verify", "--quiet", f"refs/tags/{src_tag}^{{commit}}"],
        capture_output=True,
        text=True,
        timeout=15.0,
        check=False,
    )
    src_sha = rev_proc.stdout.strip()
    if rev_proc.returncode != 0 or not HEX40_RE.fullmatch(src_sha):
        raise SystemExit(
            f"Unable to resolve peeled source tag commit refs/tags/{src_tag}^{{commit}} in {repo_dir}"
        )

    ls_proc = subprocess.run(
        ["git", "-C", str(repo_dir), "ls-tree", "-r", "--full-tree", "-z", src_sha, "--", "ForeverHub"],
        capture_output=True,
        timeout=15.0,
        check=False,
    )
    if ls_proc.returncode != 0:
        raise SystemExit(f"git ls-tree failed for {src_tag} ({src_sha})")

    tree_entries: dict[str, str] = {}
    for raw_rec in ls_proc.stdout.split(b"\x00"):
        if not raw_rec:
            continue
        meta_b, path_b = raw_rec.split(b"\t", 1)
        mode_str, obj_type, blob_sha = meta_b.decode("ascii").split(" ")
        rel_path = path_b.decode("utf-8")
        if not rel_path.startswith("ForeverHub/"):
            raise SystemExit(f"Unexpected tree path outside ForeverHub/ in {src_tag}: {rel_path}")
        if obj_type != "blob" or mode_str == "120000":
            raise SystemExit(f"Symlink or non-blob entry forbidden in {src_tag}: {rel_path}")
        inner_rel = rel_path[len("ForeverHub/"):]
        tree_entries[inner_rel] = blob_sha

    if set(tree_entries.keys()) != set(expected_rel_files):
        raise SystemExit(
            f"{src_tag} tree file set mismatch: got {sorted(tree_entries)}, expected {sorted(expected_rel_files)}"
        )

    source_blobs: dict[str, bytes] = {}
    for rel in expected_rel_files:
        cat_proc = subprocess.run(
            ["git", "-C", str(repo_dir), "cat-file", "blob", tree_entries[rel]],
            capture_output=True,
            timeout=15.0,
            check=False,
        )
        if cat_proc.returncode != 0:
            raise SystemExit(f"Failed to read git blob for ForeverHub/{rel} in {src_tag}")
        source_blobs[rel] = cat_proc.stdout

    return src_sha, source_blobs


def validate_release_json_bytes(
    raw_json_bytes: bytes,
    version: str,
    *,
    require_canonical_bytes: bool = True,
) -> dict[str, object]:
    try:
        parsed = json.loads(raw_json_bytes.decode("utf-8"))
    except Exception as exc:
        raise SystemExit(f"Invalid UTF-8/JSON in release.json: {exc}") from exc

    if not isinstance(parsed, dict) or set(parsed.keys()) != {"releases"}:
        raise SystemExit(f"release.json top-level keys mismatch: {parsed!r}")

    releases = parsed.get("releases")
    if not isinstance(releases, list) or len(releases) != 1:
        raise SystemExit("release.json must contain exactly 1 release entry")
    entry = releases[0]
    if not isinstance(entry, dict):
        raise SystemExit("release.json release entry must be an object")
    if type(entry.get("nolib")) is not bool or entry["nolib"] is not False:
        raise SystemExit("release.json entry nolib must be boolean False")

    meta_list = entry.get("metadata")
    if not isinstance(meta_list, list) or len(meta_list) != 1 or not isinstance(meta_list[0], dict):
        raise SystemExit("release.json entry metadata must contain exactly 1 flavor mapping")
    meta_item = meta_list[0]
    iface_val = meta_item.get("interface")
    if type(iface_val) is not int or iface_val != EXPECTED_INTERFACE_VERSION:
        raise SystemExit(
            f"release.json metadata interface must be strict integer {EXPECTED_INTERFACE_VERSION}, got {iface_val!r} ({type(iface_val).__name__})"
        )

    expected = expected_release_metadata(version)
    if parsed != expected:
        raise SystemExit(f"release.json mismatch: got {parsed!r}, expected {expected!r}")

    canonical_bytes = canonical_release_json_bytes(version)
    if require_canonical_bytes and raw_json_bytes != canonical_bytes:
        raise SystemExit(
            "release.json bytes do not match canonical emitted release.json byte-for-byte"
        )
    return parsed


def _flatten_releases_payload(payload: object) -> list[dict[str, object]]:
    if not isinstance(payload, list):
        raise SystemExit("GitHub releases API payload must be a JSON array")
    flat: list[dict[str, object]] = []
    for item in payload:
        if isinstance(item, list):
            for sub in item:
                if not isinstance(sub, dict):
                    raise SystemExit("Invalid release object inside paginated releases list")
                flat.append(sub)
        elif isinstance(item, dict):
            flat.append(item)
        else:
            raise SystemExit(f"Unexpected entry type in releases payload: {type(item).__name__}")
    return flat


def reconcile_existing_releases(
    releases_json_path: Path,
    *,
    tag: str,
    target_semver: tuple[int, int, int],
    expected_asset_sizes: dict[str, int],
    expected_asset_digests: dict[str, str],
) -> dict[str, object]:
    if releases_json_path.is_symlink() or not releases_json_path.is_file():
        raise SystemExit(f"Invalid releases JSON file: {releases_json_path}")
    raw_payload = json.loads(releases_json_path.read_text(encoding="utf-8"))
    releases = _flatten_releases_payload(raw_payload)

    matching_drafts: list[dict[str, object]] = []
    expected_title = f"ForeverHub {tag}"

    for rel in releases:
        r_tag = rel.get("tag_name")
        r_name = rel.get("name")
        is_draft = rel.get("draft")
        is_prerelease = rel.get("prerelease")
        if type(is_draft) is not bool or type(is_prerelease) is not bool:
            raise SystemExit(f"Malformed release draft/prerelease flags on tag {r_tag!r}")

        if not is_draft:
            if r_tag == tag:
                raise SystemExit(
                    f"Published release for {tag} already exists; refusing to overwrite or republish"
                )
            if not is_prerelease:
                if not isinstance(r_tag, str) or not TAG_RE.fullmatch(r_tag):
                    raise SystemExit(
                        f"Unexpected non-semver published stable release tag {r_tag!r}; stopping for manual inspection"
                    )
                _, pub_semver = parse_semver_tag(r_tag)
                if pub_semver >= target_semver:
                    raise SystemExit(
                        f"Out-of-order release blocked: published stable release {r_tag} >= target {tag} "
                        "(WowUp GithubAddonProvider sorts releases by published_at timestamp)"
                    )
        else:
            if r_tag == tag or r_name == expected_title:
                matching_drafts.append(rel)

    if len(matching_drafts) > 1:
        raise SystemExit(f"Multiple draft releases match {tag}; stopping for manual inspection")

    if not matching_drafts:
        return {
            "action": "create_draft",
            "tag": tag,
            "draftReleaseId": None,
            "missingAssets": sorted(expected_asset_sizes.keys()),
        }

    draft = matching_drafts[0]
    if draft.get("tag_name") != tag or draft.get("prerelease") is not False:
        raise SystemExit(
            f"Existing draft matching {tag} has unexpected tag_name={draft.get('tag_name')!r} "
            f"or prerelease={draft.get('prerelease')!r}; stopping for manual inspection"
        )

    draft_assets = draft.get("assets")
    if not isinstance(draft_assets, list):
        raise SystemExit(f"Existing draft for {tag} has invalid assets list")

    seen_names: set[str] = set()
    for asset in draft_assets:
        if not isinstance(asset, dict):
            raise SystemExit(f"Invalid asset entry in existing draft for {tag}")
        aname = asset.get("name")
        astate = asset.get("state")
        asize = asset.get("size")
        adigest = asset.get("digest")
        if not isinstance(aname, str) or aname not in expected_asset_sizes:
            raise SystemExit(
                f"Existing draft for {tag} contains unexpected asset {aname!r}; refusing to delete or overwrite"
            )
        if aname in seen_names:
            raise SystemExit(f"Existing draft for {tag} contains duplicate asset {aname!r}")
        if astate != "uploaded" or type(asize) is not int or asize != expected_asset_sizes[aname]:
            raise SystemExit(
                f"Existing draft asset {aname!r} has state={astate!r}, size={asize!r} "
                f"(expected uploaded, {expected_asset_sizes[aname]}); stopping for manual inspection"
            )
        if isinstance(adigest, str) and adigest and adigest != expected_asset_digests[aname]:
            raise SystemExit(
                f"Existing draft asset {aname!r} digest {adigest!r} != expected {expected_asset_digests[aname]!r}"
            )
        seen_names.add(aname)

    missing_assets = sorted(set(expected_asset_sizes.keys()) - seen_names)
    return {
        "action": "resume_draft",
        "tag": tag,
        "draftReleaseId": draft.get("id"),
        "missingAssets": missing_assets,
    }


def verify_published_release_payload(
    published_json_path: Path,
    *,
    label: str,
    tag: str,
    repo_slug: str | None,
    expected_asset_sizes: dict[str, int],
    expected_asset_digests: dict[str, str],
) -> None:
    if published_json_path.is_symlink() or not published_json_path.is_file():
        raise SystemExit(f"Invalid published release JSON file ({label}): {published_json_path}")
    rel = json.loads(published_json_path.read_text(encoding="utf-8"))
    if not isinstance(rel, dict):
        raise SystemExit(f"Published release JSON ({label}) must be an object")

    if rel.get("tag_name") != tag:
        raise SystemExit(
            f"Post-publication check failed ({label}): tag_name={rel.get('tag_name')!r}, expected {tag!r}"
        )
    if type(rel.get("draft")) is not bool or rel["draft"] is not False:
        raise SystemExit(f"Post-publication check failed ({label}): release is still draft={rel.get('draft')!r}")
    if type(rel.get("prerelease")) is not bool or rel["prerelease"] is not False:
        raise SystemExit(
            f"Post-publication check failed ({label}): expected stable release (prerelease=False), got {rel.get('prerelease')!r}"
        )
    if type(rel.get("immutable")) is not bool or rel["immutable"] is not True:
        raise SystemExit(
            f"Post-publication check failed ({label}): GitHub Immutable Releases not active (immutable={rel.get('immutable')!r})"
        )

    assets = rel.get("assets")
    if not isinstance(assets, list):
        raise SystemExit(f"Post-publication check failed ({label}): missing assets array")

    seen: set[str] = set()
    for asset in assets:
        if not isinstance(asset, dict):
            raise SystemExit(f"Post-publication check failed ({label}): invalid asset object")
        aname = asset.get("name")
        if not isinstance(aname, str) or aname not in expected_asset_sizes:
            raise SystemExit(
                f"Post-publication check failed ({label}): unexpected asset {aname!r} on published release"
            )
        if aname in seen:
            raise SystemExit(f"Post-publication check failed ({label}): duplicate asset {aname!r}")
        if asset.get("state") != "uploaded":
            raise SystemExit(
                f"Post-publication check failed ({label}): asset {aname!r} state={asset.get('state')!r}"
            )
        asize = asset.get("size")
        if type(asize) is not int or asize != expected_asset_sizes[aname]:
            raise SystemExit(
                f"Post-publication check failed ({label}): asset {aname!r} size={asize!r}, expected {expected_asset_sizes[aname]}"
            )
        adigest = asset.get("digest")
        if isinstance(adigest, str) and adigest and adigest != expected_asset_digests[aname]:
            raise SystemExit(
                f"Post-publication check failed ({label}): asset {aname!r} digest={adigest!r}, expected {expected_asset_digests[aname]!r}"
            )
        dl_url = asset.get("browser_download_url")
        if not isinstance(dl_url, str) or not dl_url.startswith("https://github.com/"):
            raise SystemExit(
                f"Post-publication check failed ({label}): invalid browser_download_url on {aname!r}: {dl_url!r}"
            )
        if repo_slug is not None:
            expected_url = f"https://github.com/{repo_slug}/releases/download/{tag}/{aname}"
            if dl_url != expected_url:
                raise SystemExit(
                    f"Post-publication check failed ({label}): browser_download_url {dl_url!r} != {expected_url!r}"
                )
        seen.add(aname)

    if seen != set(expected_asset_sizes.keys()):
        raise SystemExit(
            f"Post-publication check failed ({label}): asset set {sorted(seen)} != {sorted(expected_asset_sizes.keys())}"
        )


def verify_tag_and_archives(
    tag: str,
    *,
    require_source_tag: bool = False,
    emit_bundle_dir: Path | None = None,
    verify_downloaded_dir: Path | None = None,
    compare_bundle_dir: Path | None = None,
    reconcile_releases_json: Path | None = None,
    reconcile_plan_out: Path | None = None,
    verify_published_json: Path | None = None,
    verify_published_tag_json: Path | None = None,
    repo_slug: str | None = None,
) -> dict[str, object]:
    _, target_semver = parse_semver_tag(tag)
    if repo_slug is not None and not REPO_SLUG_RE.fullmatch(repo_slug):
        raise SystemExit(f"Invalid repository slug {repo_slug!r}")

    toc_path = ADDON_DIR / "ForeverHub.toc"
    if toc_path.is_symlink() or not toc_path.is_file():
        raise SystemExit(f"Missing or invalid ForeverHub.toc: {toc_path}")
    toc_text = toc_path.read_text(encoding="utf-8")

    m_ver = re.search(r"^##\s*Version:\s*(\S+)\s*$", toc_text, re.M)
    if not m_ver:
        raise SystemExit("Missing ## Version in ForeverHub/ForeverHub.toc")
    version = m_ver.group(1)
    expected_tag = f"v{version}"
    if tag != expected_tag:
        raise SystemExit(f"Git tag {tag!r} does not match ForeverHub.toc version {expected_tag!r}")

    m_iface = re.search(r"^##\s*Interface:\s*(\S+)\s*$", toc_text, re.M)
    if not m_iface or m_iface.group(1) != str(EXPECTED_INTERFACE_VERSION):
        raise SystemExit(
            f"ForeverHub.toc ## Interface must be {EXPECTED_INTERFACE_VERSION}, "
            f"got {m_iface.group(1) if m_iface else None!r}"
        )

    rel_files = [
        "ForeverHub.toc",
        "LICENSE",
        "Textures/NavigationArrow.tga",
        "Textures/UIControls.tga",
        "Textures/QuestGlyphs.tga",
        "Textures/PinRing.tga",
        "Textures/PinGlow.tga",
        "Textures/CoinGlyphs.tga",
    ]
    for raw_line in toc_text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        norm = line.replace("\\", "/")
        if not norm.endswith(".lua"):
            raise SystemExit(f"Unexpected non-Lua entry in ForeverHub.toc: {norm}")
        if norm not in rel_files:
            rel_files.append(norm)

    checkout_bytes: dict[str, bytes] = {}
    for rel in rel_files:
        fpath = ADDON_DIR / rel
        if fpath.is_symlink() or not fpath.is_file():
            raise SystemExit(f"Missing or symlinked allowlisted addon file: {fpath}")
        checkout_bytes[rel] = fpath.read_bytes()

    has_git = (REPO_DIR / ".git").exists()
    if require_source_tag and not has_git:
        raise SystemExit(f"--require-source-tag set, but {REPO_DIR / '.git'} does not exist")

    peeled_src_sha: str | None = None
    canonical_bytes = checkout_bytes
    if has_git:
        peeled_src_sha, src_tree_bytes = verify_source_tag_tree(REPO_DIR, version, rel_files)
        for rel in rel_files:
            if checkout_bytes[rel] != src_tree_bytes[rel]:
                raise SystemExit(
                    f"Checked-out ForeverHub/{rel} diverges from v{version}-src ({peeled_src_sha})"
                )
        canonical_bytes = src_tree_bytes

    expected_hashes = {rel: sha256_bytes(raw) for rel, raw in canonical_bytes.items()}
    expected_members = {f"ForeverHub/{rel}" for rel in rel_files} | {"ForeverHub/BUILD_MANIFEST.json"}

    std_name = f"ForeverHub-v{version}.zip"
    wowup_name = f"ForeverHub-v{version}-forever.zip"
    std_zip = DIST_DIR / std_name
    wowup_zip = DIST_DIR / wowup_name
    std_sha_file = DIST_DIR / f"{std_name}.sha256"
    wowup_sha_file = DIST_DIR / f"{wowup_name}.sha256"
    release_json_file = DIST_DIR / "release.json"

    for req in (std_zip, wowup_zip, std_sha_file, wowup_sha_file, release_json_file):
        if req.is_symlink() or not req.is_file():
            raise SystemExit(f"Missing or invalid required release file: {req}")

    raw_zip = std_zip.read_bytes()
    if wowup_zip.read_bytes() != raw_zip:
        raise SystemExit(f"{wowup_name} bytes do not match {std_name}")

    zip_sha = sha256_bytes(raw_zip)
    expected_wowup_sha_bytes = f"{zip_sha}  {wowup_name}\n".encode("utf-8")
    if std_sha_file.read_text(encoding="utf-8") != f"{zip_sha}  {std_name}\n":
        raise SystemExit(f"Checksum mismatch in {std_sha_file.name}")
    if wowup_sha_file.read_bytes() != expected_wowup_sha_bytes:
        raise SystemExit(f"Checksum mismatch in {wowup_sha_file.name}")

    canonical_rel_json_bytes = canonical_release_json_bytes(version)
    dist_rel_json_bytes = release_json_file.read_bytes()
    validate_release_json_bytes(dist_rel_json_bytes, version, require_canonical_bytes=True)
    release_notes = extract_changelog_release_notes(CHANGELOG_PATH, version)

    expected_asset_sizes = {
        wowup_name: len(raw_zip),
        f"{wowup_name}.sha256": len(expected_wowup_sha_bytes),
        "release.json": len(canonical_rel_json_bytes),
    }
    expected_asset_digests = {
        wowup_name: f"sha256:{zip_sha}",
        f"{wowup_name}.sha256": f"sha256:{sha256_bytes(expected_wowup_sha_bytes)}",
        "release.json": f"sha256:{sha256_bytes(canonical_rel_json_bytes)}",
    }

    def _verify_archive_bytes(archive_bytes: bytes, label: str) -> dict[str, object]:
        with zipfile.ZipFile(io.BytesIO(archive_bytes), "r") as zf:
            infos = zf.infolist()
            names = [i.filename for i in infos]
            if len(names) != len(set(names)):
                raise SystemExit(f"Duplicate ZIP entries detected in {label}")
            for info in infos:
                if info.is_dir() or ((info.external_attr >> 16) & 0o170000) == 0o120000:
                    raise SystemExit(f"Directory or symlink entry forbidden in {label}: {info.filename}")
            if set(names) != expected_members:
                raise SystemExit(f"Archive member set mismatch in {label}: {sorted(names)}")

            manifest = json.loads(zf.read("ForeverHub/BUILD_MANIFEST.json").decode("utf-8"))
            if manifest.get("addonName") != "ForeverHub" or manifest.get("version") != version:
                raise SystemExit(f"BUILD_MANIFEST.json addonName/version mismatch in {label}")
            iface = manifest.get("interfaceVersion")
            if type(iface) is not int or iface != EXPECTED_INTERFACE_VERSION:
                raise SystemExit(
                    f"BUILD_MANIFEST.json interfaceVersion must be integer {EXPECTED_INTERFACE_VERSION}, got {iface!r}"
                )
            if manifest.get("targetClientBuild") != EXPECTED_TARGET_CLIENT_BUILD:
                raise SystemExit(
                    f"BUILD_MANIFEST.json targetClientBuild must be {EXPECTED_TARGET_CLIENT_BUILD!r}, "
                    f"got {manifest.get('targetClientBuild')!r}"
                )
            git_sha = manifest.get("gitCommitSha")
            if not isinstance(git_sha, str) or not HEX40_RE.fullmatch(git_sha):
                raise SystemExit(f"BUILD_MANIFEST.json gitCommitSha must be 40-hex commit SHA, got {git_sha!r}")
            if peeled_src_sha is not None and git_sha != peeled_src_sha:
                raise SystemExit(
                    f"BUILD_MANIFEST.json gitCommitSha {git_sha!r} != peeled v{version}-src commit {peeled_src_sha!r}"
                )
            if manifest.get("allowlistedFiles") != expected_hashes:
                raise SystemExit(f"BUILD_MANIFEST.json allowlistedFiles mismatch in {label}")

            for rel in rel_files:
                member = zf.read(f"ForeverHub/{rel}")
                if member != canonical_bytes[rel]:
                    raise SystemExit(f"Archive member payload mismatch in {label}: ForeverHub/{rel}")
            return manifest

    manifest_obj = _verify_archive_bytes(raw_zip, wowup_name)

    reconcile_plan: dict[str, object] | None = None
    if reconcile_releases_json is not None:
        reconcile_plan = reconcile_existing_releases(
            reconcile_releases_json,
            tag=tag,
            target_semver=target_semver,
            expected_asset_sizes=expected_asset_sizes,
            expected_asset_digests=expected_asset_digests,
        )
        if reconcile_plan_out is not None:
            if reconcile_plan_out.is_symlink():
                raise SystemExit(f"Symlink reconcile plan output forbidden: {reconcile_plan_out}")
            reconcile_plan_out.parent.mkdir(parents=True, exist_ok=True)
            reconcile_plan_out.write_text(
                json.dumps(reconcile_plan, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )

    if emit_bundle_dir is not None:
        if emit_bundle_dir.is_symlink():
            raise SystemExit(f"Symlink bundle output directory forbidden: {emit_bundle_dir}")
        if emit_bundle_dir.exists() and any(emit_bundle_dir.iterdir()):
            raise SystemExit(f"Bundle output directory must be empty or non-existent: {emit_bundle_dir}")
        emit_bundle_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(wowup_zip, emit_bundle_dir / wowup_name)
        shutil.copy2(wowup_sha_file, emit_bundle_dir / f"{wowup_name}.sha256")
        (emit_bundle_dir / "release.json").write_bytes(canonical_rel_json_bytes)
        (emit_bundle_dir / "RELEASE_NOTES.md").write_text(release_notes, encoding="utf-8")

    if verify_published_tag_json is not None:
        verify_published_release_payload(
            verify_published_tag_json,
            label="releases/tags",
            tag=tag,
            repo_slug=repo_slug,
            expected_asset_sizes=expected_asset_sizes,
            expected_asset_digests=expected_asset_digests,
        )

    if verify_published_json is not None:
        verify_published_release_payload(
            verify_published_json,
            label="releases/latest",
            tag=tag,
            repo_slug=repo_slug,
            expected_asset_sizes=expected_asset_sizes,
            expected_asset_digests=expected_asset_digests,
        )

    if verify_downloaded_dir is not None:
        if verify_downloaded_dir.is_symlink() or not verify_downloaded_dir.is_dir():
            raise SystemExit(f"Invalid downloaded release directory: {verify_downloaded_dir}")
        entries = sorted(verify_downloaded_dir.iterdir(), key=lambda p: p.name)
        for ent in entries:
            if ent.is_symlink() or not ent.is_file():
                raise SystemExit(f"Symlink or subdirectory forbidden in downloaded assets: {ent}")
        actual_names = {ent.name for ent in entries}
        expected_asset_names = {wowup_name, f"{wowup_name}.sha256", "release.json"}
        if actual_names != expected_asset_names:
            raise SystemExit(
                f"Downloaded release asset set mismatch: got {sorted(actual_names)}, "
                f"expected strictly {sorted(expected_asset_names)} (unsuffixed ZIP is forbidden)"
            )
        dl_zip_bytes = (verify_downloaded_dir / wowup_name).read_bytes()
        if dl_zip_bytes != raw_zip or sha256_bytes(dl_zip_bytes) != zip_sha:
            raise SystemExit(f"Downloaded {wowup_name} bytes do not match verified local archive")
        dl_sha_bytes = (verify_downloaded_dir / f"{wowup_name}.sha256").read_bytes()
        if dl_sha_bytes != expected_wowup_sha_bytes:
            raise SystemExit(f"Downloaded {wowup_name}.sha256 checksum mismatch")
        dl_rel_json_bytes = (verify_downloaded_dir / "release.json").read_bytes()
        validate_release_json_bytes(dl_rel_json_bytes, version, require_canonical_bytes=True)
        if dl_rel_json_bytes != dist_rel_json_bytes:
            raise SystemExit("Downloaded release.json bytes diverge from dist/release.json")
        if compare_bundle_dir is not None:
            if compare_bundle_dir.is_symlink() or not compare_bundle_dir.is_dir():
                raise SystemExit(f"Invalid emitted bundle comparison directory: {compare_bundle_dir}")
            for asset_fname, dl_bytes in (
                (wowup_name, dl_zip_bytes),
                (f"{wowup_name}.sha256", dl_sha_bytes),
                ("release.json", dl_rel_json_bytes),
            ):
                emitted_file = compare_bundle_dir / asset_fname
                if emitted_file.is_symlink() or not emitted_file.is_file():
                    raise SystemExit(f"Missing emitted bundle file for comparison: {emitted_file}")
                if dl_bytes != emitted_file.read_bytes():
                    raise SystemExit(
                        f"Downloaded {asset_fname} bytes diverge from emitted bundle file {emitted_file}"
                    )
        _verify_archive_bytes(dl_zip_bytes, f"downloaded:{wowup_name}")

    result = {
        "tag": tag,
        "version": version,
        "zipSha256": zip_sha,
        "gitCommitSha": manifest_obj["gitCommitSha"],
        "peeledSourceTagCommit": peeled_src_sha,
        "wowupAsset": wowup_name,
        "verifiedDownloadedAssets": verify_downloaded_dir is not None,
        "verifiedPublishedRelease": verify_published_json is not None,
        "reconcilePlan": reconcile_plan,
    }
    print(f"Verified {std_name}, {wowup_name}, release.json, and CHANGELOG.md (SHA-256: {zip_sha})")
    return result


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--require-source-tag", action="store_true")
    ap.add_argument("--emit-release-bundle", type=Path, default=None)
    ap.add_argument("--verify-downloaded-dir", type=Path, default=None)
    ap.add_argument("--compare-bundle-dir", type=Path, default=None)
    ap.add_argument("--reconcile-releases-json", type=Path, default=None)
    ap.add_argument("--reconcile-plan-out", type=Path, default=None)
    ap.add_argument("--verify-published-json", type=Path, default=None)
    ap.add_argument("--verify-published-tag-json", type=Path, default=None)
    ap.add_argument("--repo-slug", type=str, default=None)
    args = ap.parse_args()
    verify_tag_and_archives(
        args.tag,
        require_source_tag=args.require_source_tag,
        emit_bundle_dir=args.emit_release_bundle,
        verify_downloaded_dir=args.verify_downloaded_dir,
        compare_bundle_dir=args.compare_bundle_dir,
        reconcile_releases_json=args.reconcile_releases_json,
        reconcile_plan_out=args.reconcile_plan_out,
        verify_published_json=args.verify_published_json,
        verify_published_tag_json=args.verify_published_tag_json,
        repo_slug=args.repo_slug,
    )
