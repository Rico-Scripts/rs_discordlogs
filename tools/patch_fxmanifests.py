#!/usr/bin/env python3
"""
RS Discord Logs - fxmanifest patcher

Host-side tool for Linux/Windows. It recursively finds fxmanifest.lua files and
adds @rs_discordlogs/server/intercept.lua to server script loading order.

Why host-side?
FiveM's sandbox blocks a resource from writing files in another resource.

Usage:
  Dry run:
    python3 patch_fxmanifests.py /home/container/resources

  Apply:
    python3 patch_fxmanifests.py /home/container/resources --apply

  Restore:
    python3 patch_fxmanifests.py /home/container/resources --restore /path/to/backup
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
from datetime import datetime, timezone

BRIDGE_PATH = "@rs_discordlogs/server/intercept.lua"
BRIDGE_ENTRY = f"'{BRIDGE_PATH}',"
BACKUP_FOLDER = ".rs_discordlogs_backups"

DEFAULT_EXCLUDES = {
    "rs_discordlogs",
}

SERVER_BLOCK_RE = re.compile(r"\bserver_scripts\s*(?:\(\s*)?\{", re.IGNORECASE)
SERVER_SINGLE_RE = re.compile(
    r"(?m)^[ \t]*server_script\s*(?:\(\s*)?['\"][^'\"]+['\"]\s*\)?"
    r"[ \t]*,?[ \t]*(?:--.*)?$"
)
CONFIG_QUOTED_RE = re.compile(
    r"['\"]([^'\"]*(?:config|settings)[^'\"]*\.lua)['\"]",
    re.IGNORECASE,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Patch alle FiveM fxmanifest.lua bestanden voor rs_discordlogs."
    )
    parser.add_argument(
        "resources_root",
        type=Path,
        help="Pad naar de FiveM resources-map, bijvoorbeeld /home/container/resources",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Wijzig bestanden echt. Zonder deze optie draait de tool als dry-run.",
    )
    parser.add_argument(
        "--restore",
        type=Path,
        default=None,
        help="Herstel manifests vanuit een eerder aangemaakte backup-map.",
    )
    parser.add_argument(
        "--exclude",
        action="append",
        default=[],
        help="Resourcefolder overslaan. Mag meerdere keren worden gebruikt.",
    )
    parser.add_argument(
        "--include-client-only",
        action="store_true",
        help="Voeg ook aan manifests zonder server_script(s) een server_script toe.",
    )
    parser.add_argument(
        "--no-backup",
        action="store_true",
        help="Geen backup maken. Niet aanbevolen.",
    )
    return parser.parse_args()


def newline_for(text: str) -> str:
    return "\r\n" if "\r\n" in text else "\n"


def line_indent_at(text: str, pos: int) -> str:
    start = text.rfind("\n", 0, pos) + 1
    match = re.match(r"[ \t]*", text[start:])
    return match.group(0) if match else ""


def find_matching_brace(text: str, open_pos: int) -> int | None:
    depth = 0
    quote: str | None = None
    line_comment = False
    block_comment = False
    i = open_pos

    while i < len(text):
        current = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""

        if line_comment:
            if current == "\n":
                line_comment = False

        elif block_comment:
            if current == "*" and nxt == "/":
                block_comment = False
                i += 1

        elif quote:
            if current == "\\":
                i += 1
            elif current == quote:
                quote = None

        else:
            if current == "-" and nxt == "-":
                line_comment = True
                i += 1
            elif current == "/" and nxt == "*":
                block_comment = True
                i += 1
            elif current in ("'", '"'):
                quote = current
            elif current == "{":
                depth += 1
            elif current == "}":
                depth -= 1
                if depth == 0:
                    return i

        i += 1

    return None


def insert_in_server_block(text: str, block_match: re.Match[str]) -> tuple[str | None, str]:
    nl = newline_for(text)
    open_pos = text.find("{", block_match.start(), block_match.end())
    close_pos = find_matching_brace(text, open_pos)

    if close_pos is None:
        return None, "malformed_server_scripts"

    inner = text[open_pos + 1 : close_pos]
    config_matches = list(CONFIG_QUOTED_RE.finditer(inner))

    # If config.lua/settings.lua is loaded server-side, the bridge must come after it.
    if config_matches:
        config_match = config_matches[-1]
        absolute_end = open_pos + 1 + config_match.end()
        line_end = text.find("\n", absolute_end, close_pos)

        if line_end != -1:
            remainder = text[absolute_end:line_end]
            if re.fullmatch(r"[ \t]*,?[ \t]*(?:--.*)?", remainder):
                indent = line_indent_at(text, absolute_end)
                if not indent:
                    indent = line_indent_at(text, open_pos) + "    "

                insert_pos = line_end + 1
                patched = (
                    text[:insert_pos]
                    + indent
                    + BRIDGE_ENTRY
                    + nl
                    + text[insert_pos:]
                )
                return patched, "after_server_config"

        # Single-line block fallback.
        insert_pos = absolute_end
        while insert_pos < close_pos and text[insert_pos] in " \t":
            insert_pos += 1
        if insert_pos < close_pos and text[insert_pos] == ",":
            insert_pos += 1

        indent = line_indent_at(text, open_pos) + "    "
        patched = (
            text[:insert_pos]
            + nl
            + indent
            + BRIDGE_ENTRY
            + text[insert_pos:]
        )
        return patched, "after_server_config_inline"

    # Config is usually shared, so loading first in the server_scripts block is safe.
    indent = line_indent_at(text, open_pos) + "    "
    insert_pos = open_pos + 1

    if text[insert_pos : insert_pos + 2] == "\r\n":
        insert_pos += 2
        patched = (
            text[:insert_pos]
            + indent
            + BRIDGE_ENTRY
            + nl
            + text[insert_pos:]
        )
    elif insert_pos < len(text) and text[insert_pos] == "\n":
        insert_pos += 1
        patched = (
            text[:insert_pos]
            + indent
            + BRIDGE_ENTRY
            + nl
            + text[insert_pos:]
        )
    else:
        patched = (
            text[:insert_pos]
            + nl
            + indent
            + BRIDGE_ENTRY
            + nl
            + text[insert_pos:]
        )

    return patched, "first_in_server_block"


def patch_manifest(text: str, include_client_only: bool) -> tuple[str, str]:
    if BRIDGE_PATH.lower() in text.lower():
        return text, "already_patched"

    blocks = list(SERVER_BLOCK_RE.finditer(text))
    if blocks:
        chosen = None

        # Prefer a server_scripts block containing config/settings.
        for block in blocks:
            open_pos = text.find("{", block.start(), block.end())
            close_pos = find_matching_brace(text, open_pos)
            if close_pos is not None and CONFIG_QUOTED_RE.search(
                text[open_pos + 1 : close_pos]
            ):
                chosen = block
                break

        chosen = chosen or blocks[0]
        patched, reason = insert_in_server_block(text, chosen)
        if patched is None:
            return text, reason
        return patched, reason

    single_lines = list(SERVER_SINGLE_RE.finditer(text))
    if single_lines:
        nl = newline_for(text)
        config_lines = [
            match
            for match in single_lines
            if re.search(
                r"(?:config|settings)[^'\"]*\.lua",
                match.group(0),
                re.IGNORECASE,
            )
        ]

        if config_lines:
            config_line = config_lines[-1]
            line_end = text.find("\n", config_line.end())
            indent = line_indent_at(text, config_line.start())

            if line_end == -1:
                return (
                    text
                    + nl
                    + indent
                    + f"server_script '{BRIDGE_PATH}'"
                    + nl,
                    "after_server_config_single",
                )

            return (
                text[: line_end + 1]
                + indent
                + f"server_script '{BRIDGE_PATH}'"
                + nl
                + text[line_end + 1 :],
                "after_server_config_single",
            )

        first = single_lines[0]
        indent = line_indent_at(text, first.start())
        nl = newline_for(text)

        return (
            text[: first.start()]
            + indent
            + f"server_script '{BRIDGE_PATH}'"
            + nl
            + text[first.start() :],
            "before_first_server_script",
        )

    if include_client_only:
        nl = newline_for(text)
        suffix = "" if text.endswith(("\n", "\r")) else nl
        return (
            text
            + suffix
            + nl
            + "-- Added by rs_discordlogs fxmanifest patcher"
            + nl
            + f"server_script '{BRIDGE_PATH}'"
            + nl,
            "added_to_client_only_manifest",
        )

    return text, "no_server_scripts"


def read_text(path: Path) -> tuple[str | None, str | None]:
    try:
        return path.read_text(encoding="utf-8-sig"), None
    except UnicodeDecodeError:
        return None, "not_utf8"
    except OSError as exc:
        return None, f"read_error:{exc}"


def atomic_write(path: Path, content: str) -> None:
    fd, temp_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=str(path.parent),
        text=True,
    )

    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())

        shutil.copymode(path, temp_name)
        os.replace(temp_name, path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def backup_path_for(root: Path, manifest: Path, backup_root: Path) -> Path:
    relative = manifest.relative_to(root)
    return backup_root / relative


def make_backup(root: Path, manifest: Path, backup_root: Path) -> None:
    target = backup_path_for(root, manifest, backup_root)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(manifest, target)


def find_manifests(root: Path, excludes: set[str]) -> list[Path]:
    manifests: list[Path] = []

    for manifest in root.rglob("fxmanifest.lua"):
        try:
            relative_parts = manifest.relative_to(root).parts
        except ValueError:
            continue

        if BACKUP_FOLDER in relative_parts:
            continue

        resource_name = manifest.parent.name
        if resource_name in excludes:
            continue

        manifests.append(manifest)

    return sorted(manifests, key=lambda item: str(item).lower())


def restore_backup(root: Path, backup_root: Path) -> int:
    if not backup_root.is_dir():
        print(f"[FOUT] Backup-map bestaat niet: {backup_root}")
        return 2

    restored = 0
    for backup_manifest in backup_root.rglob("fxmanifest.lua"):
        relative = backup_manifest.relative_to(backup_root)
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(backup_manifest, target)
        restored += 1
        print(f"[HERSTELD] {relative}")

    print(f"\nKlaar: {restored} manifest(s) hersteld.")
    return 0


def main() -> int:
    args = parse_args()
    root = args.resources_root.expanduser().resolve()

    if not root.is_dir():
        print(f"[FOUT] Resources-map bestaat niet: {root}")
        return 2

    if args.restore:
        return restore_backup(root, args.restore.expanduser().resolve())

    excludes = DEFAULT_EXCLUDES | {item.strip() for item in args.exclude if item.strip()}
    manifests = find_manifests(root, excludes)

    if not manifests:
        print("[INFO] Geen fxmanifest.lua bestanden gevonden.")
        return 0

    apply_changes = bool(args.apply)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup_root = root / BACKUP_FOLDER / timestamp

    results: list[dict[str, str]] = []
    changed = 0
    already = 0
    skipped = 0
    errors = 0

    mode = "APPLY" if apply_changes else "DRY-RUN"
    print(f"[rs_discordlogs] fxmanifest patcher - {mode}")
    print(f"[INFO] Root: {root}")
    print(f"[INFO] Gevonden manifests: {len(manifests)}")
    print("")

    for manifest in manifests:
        relative = manifest.relative_to(root)
        original, error = read_text(manifest)

        if error or original is None:
            errors += 1
            results.append({"file": str(relative), "status": error or "read_error"})
            print(f"[FOUT] {relative} -> {error}")
            continue

        patched, reason = patch_manifest(original, args.include_client_only)

        if reason == "already_patched":
            already += 1
            results.append({"file": str(relative), "status": reason})
            print(f"[OK]   {relative} -> al gekoppeld")
            continue

        if patched == original:
            skipped += 1
            results.append({"file": str(relative), "status": reason})
            print(f"[SKIP] {relative} -> {reason}")
            continue

        changed += 1
        results.append({"file": str(relative), "status": reason})

        if apply_changes:
            if not args.no_backup:
                make_backup(root, manifest, backup_root)

            try:
                atomic_write(manifest, patched)
                print(f"[PATCH] {relative} -> {reason}")
            except OSError as exc:
                errors += 1
                changed -= 1
                results[-1]["status"] = f"write_error:{exc}"
                print(f"[FOUT] {relative} -> schrijven mislukt: {exc}")
        else:
            print(f"[PLAN]  {relative} -> {reason}")

    print("")
    print(
        f"[SAMENVATTING] wijzigen={changed} | al gekoppeld={already} | "
        f"overgeslagen={skipped} | fouten={errors}"
    )

    if apply_changes and changed > 0 and not args.no_backup:
        backup_root.mkdir(parents=True, exist_ok=True)
        report = {
            "created_at_utc": timestamp,
            "resources_root": str(root),
            "bridge": BRIDGE_PATH,
            "results": results,
        }
        (backup_root / "report.json").write_text(
            json.dumps(report, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )

        print(f"[BACKUP] {backup_root}")
        print(
            "[HERSTEL] "
            f"{Path(sys.executable).name} {Path(__file__).name} "
            f"\"{root}\" --restore \"{backup_root}\""
        )

    if not apply_changes and changed > 0:
        print("")
        print("Dit was alleen een dry-run. Voer opnieuw uit met --apply om te wijzigen.")

    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
