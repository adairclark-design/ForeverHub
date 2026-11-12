#!/usr/bin/env python3
"""
Closed-fail verifier executed by GitHub Actions before publishing a ForeverHub release.
Ensures tag, TOC version, BUILD_MANIFEST.json, every archive member's actual bytes,
and the `-forever.zip` WowUp flavor alias match byte-for-byte without recompression.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import zipfile

REPO_DIR = Path(__file__).resolve().parent.parent
ADDON_DIR = REPO_DIR / "ForeverHub"
DIST_DIR = REPO_DIR / "dist"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def verify_tag_and_archives(tag: str) -> None:
    toc_path = ADDON_DIR / "ForeverHub.toc"
    toc_text = toc_path.read_text(encoding="utf-8")
    m_ver = re.search(r"^##\s*Version:\s*(\S+)", toc_text, re.M)
    if not m_ver:
        raise SystemExit("Missing ## Version in ForeverHub/ForeverHub.toc")
    version = m_ver.group(1)
    expected_tag = f"v{version}"
    if tag != expected_tag:
        raise SystemExit(f"Git tag {tag!r} does not match ForeverHub.toc version {expected_tag!r}")

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

    expected_bytes = {rel: (ADDON_DIR / rel).read_bytes() for rel in rel_files}
    expected_hashes = {rel: sha256_bytes(raw) for rel, raw in expected_bytes.items()}
    expected_members = {f"ForeverHub/{rel}" for rel in rel_files} | {"ForeverHub/BUILD_MANIFEST.json"}

    std_name = f"ForeverHub-v{version}.zip"
    wowup_name = f"ForeverHub-v{version}-forever.zip"
    std_zip = DIST_DIR / std_name
    wowup_zip = DIST_DIR / wowup_name
    std_sha_file = DIST_DIR / f"{std_name}.sha256"
    wowup_sha_file = DIST_DIR / f"{wowup_name}.sha256"

    for req in (std_zip, wowup_zip, std_sha_file, wowup_sha_file):
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

    with zipfile.ZipFile(io.BytesIO(raw_zip), "r") as zf:
        infos = zf.infolist()
        names = [i.filename for i in infos]
        if len(names) != len(set(names)):
            raise SystemExit("Duplicate ZIP entries detected")
        for info in infos:
            if info.is_dir() or ((info.external_attr >> 16) & 0o170000) == 0o120000:
                raise SystemExit(f"Directory or symlink entry forbidden: {info.filename}")
        if set(names) != expected_members:
            raise SystemExit(f"Archive member set mismatch: {sorted(names)}")
        manifest = json.loads(zf.read("ForeverHub/BUILD_MANIFEST.json").decode("utf-8"))
        if manifest.get("version") != version or manifest.get("allowlistedFiles") != expected_hashes:
            raise SystemExit("BUILD_MANIFEST.json does not match checked-out ForeverHub files")
        for rel in rel_files:
            member = zf.read(f"ForeverHub/{rel}")
            if member != expected_bytes[rel]:
                raise SystemExit(f"Archive member payload mismatch: ForeverHub/{rel}")

    print(f"Verified {std_name} and {wowup_name} (SHA-256: {zip_sha})")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    args = ap.parse_args()
    verify_tag_and_archives(args.tag)
