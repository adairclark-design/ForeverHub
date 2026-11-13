#!/usr/bin/env python3
"""
Closed-fail verifier & release-bundle builder for ForeverHub public GitHub Releases.

Enforces GPT Astra's Round-1 & Round-2 Release Boundary Contract:
1. Validates strict `vX.Y.Z` tag syntax and parity with `ForeverHub.toc` (`## Version`,
   `## Interface: 16001`).
2. Validates `BUILD_MANIFEST.json` (`addonName`, `version`, `interfaceVersion == 16001`,
   `targetClientBuild == "1.60.1.70862"`, 40-hex `gitCommitSha`).
3. When inside a git repository (or when `--require-source-tag` is passed), resolves the
   peeled `refs/tags/vX.Y.Z-src^{commit}`, requires `gitCommitSha` to equal that commit,
   and verifies every archive member's payload bytes directly against the `vX.Y.Z-src`
   git tree (not merely the checked-out working tree).
4. Validates `dist/release.json` closed-fail (`nolib is False`, `version == "vX.Y.Z"`,
   `filename == "ForeverHub-vX.Y.Z-forever.zip"`, `metadata == [{"flavor": "forever", "interface": 16001}]`).
5. Extracts the exact `## vX.Y.Z` section from `CHANGELOG.md` without shell interpolation,
   failing closed if missing or empty, and appends the manual-visitor download warning.
6. Supports `--emit-release-bundle <dir>` (stages the exact 3 GitHub Release assets +
   `RELEASE_NOTES.md`) and `--verify-downloaded-dir <dir>` (proves a downloaded draft
   release contains strictly those 3 assets—never an unsuffixed `.zip`—with identical bytes).
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

TAG_RE = re.compile(r"^v([0-9]+\.[0-9]+\.[0-9]+)$")
HEX40_RE = re.compile(r"^[0-9a-f]{40}$")
EXPECTED_INTERFACE_VERSION = 16001
EXPECTED_TARGET_CLIENT_BUILD = "1.60.1.70862"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


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


def validate_release_json_bytes(raw_json_bytes: bytes, version: str) -> dict[str, object]:
    try:
        parsed = json.loads(raw_json_bytes.decode("utf-8"))
    except Exception as exc:
        raise SystemExit(f"Invalid UTF-8/JSON in release.json: {exc}") from exc

    expected = expected_release_metadata(version)
    if parsed != expected:
        raise SystemExit(f"release.json mismatch: got {parsed!r}, expected {expected!r}")

    releases = parsed.get("releases")
    if not isinstance(releases, list) or len(releases) != 1:
        raise SystemExit("release.json must contain exactly 1 release entry")
    entry = releases[0]
    if type(entry.get("nolib")) is not bool or entry["nolib"] is not False:
        raise SystemExit("release.json entry nolib must be boolean False")
    return parsed


def verify_tag_and_archives(
    tag: str,
    *,
    require_source_tag: bool = False,
    emit_bundle_dir: Path | None = None,
    verify_downloaded_dir: Path | None = None,
) -> dict[str, object]:
    m_tag = TAG_RE.fullmatch(tag)
    if not m_tag:
        raise SystemExit(
            f"Invalid release tag syntax {tag!r}; expected strict vMAJOR.MINOR.PATCH (never -src)"
        )

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
    if std_sha_file.read_text(encoding="utf-8") != f"{zip_sha}  {std_name}\n":
        raise SystemExit(f"Checksum mismatch in {std_sha_file.name}")
    if wowup_sha_file.read_text(encoding="utf-8") != f"{zip_sha}  {wowup_name}\n":
        raise SystemExit(f"Checksum mismatch in {wowup_sha_file.name}")

    validate_release_json_bytes(release_json_file.read_bytes(), version)
    release_notes = extract_changelog_release_notes(CHANGELOG_PATH, version)

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

    if emit_bundle_dir is not None:
        if emit_bundle_dir.is_symlink():
            raise SystemExit(f"Symlink bundle output directory forbidden: {emit_bundle_dir}")
        if emit_bundle_dir.exists() and any(emit_bundle_dir.iterdir()):
            raise SystemExit(f"Bundle output directory must be empty or non-existent: {emit_bundle_dir}")
        emit_bundle_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(wowup_zip, emit_bundle_dir / wowup_name)
        shutil.copy2(wowup_sha_file, emit_bundle_dir / f"{wowup_name}.sha256")
        (emit_bundle_dir / "release.json").write_text(
            json.dumps(expected_release_metadata(version), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        (emit_bundle_dir / "RELEASE_NOTES.md").write_text(release_notes, encoding="utf-8")

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
        dl_sha_text = (verify_downloaded_dir / f"{wowup_name}.sha256").read_text(encoding="utf-8")
        if dl_sha_text != f"{zip_sha}  {wowup_name}\n":
            raise SystemExit(f"Downloaded {wowup_name}.sha256 checksum mismatch")
        validate_release_json_bytes((verify_downloaded_dir / "release.json").read_bytes(), version)
        _verify_archive_bytes(dl_zip_bytes, f"downloaded:{wowup_name}")

    result = {
        "tag": tag,
        "version": version,
        "zipSha256": zip_sha,
        "gitCommitSha": manifest_obj["gitCommitSha"],
        "peeledSourceTagCommit": peeled_src_sha,
        "wowupAsset": wowup_name,
        "verifiedDownloadedAssets": verify_downloaded_dir is not None,
    }
    print(f"Verified {std_name}, {wowup_name}, release.json, and CHANGELOG.md (SHA-256: {zip_sha})")
    return result


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--require-source-tag", action="store_true")
    ap.add_argument("--emit-release-bundle", type=Path, default=None)
    ap.add_argument("--verify-downloaded-dir", type=Path, default=None)
    args = ap.parse_args()
    verify_tag_and_archives(
        args.tag,
        require_source_tag=args.require_source_tag,
        emit_bundle_dir=args.emit_release_bundle,
        verify_downloaded_dir=args.verify_downloaded_dir,
    )
