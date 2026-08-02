#!/usr/bin/env python3
"""Synchronize the single-target Xcode project's physical source tree and groups."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import re
import sys


REPO = Path(__file__).resolve().parents[1]
SOURCE_ROOT = REPO / "Screen-Remote"
PROJECT = REPO / "Screen-Remote.xcodeproj" / "project.pbxproj"

ROOT_GROUP_ID = "D10000000000000000000001"
SOURCE_GROUP_ID = "D10000000000000000000002"
PRODUCTS_GROUP_ID = "D10000000000000000000003"
PRODUCT_FILE_ID = "B1000000000000000000000B"
SOURCES_PHASE_ID = "C10000000000000000000003"
RESOURCES_PHASE_ID = "C10000000000000000000002"


def stable_id(kind: str, value: str) -> str:
    return hashlib.sha1(f"{kind}:{value}".encode()).hexdigest()[:24].upper()


def quoted(value: str) -> str:
    return f'"{value}"' if re.search(r"[^A-Za-z0-9_./-]", value) else value


def comment(value: Path | str) -> str:
    return Path(value).name


def source_files() -> list[Path]:
    return sorted(path.relative_to(SOURCE_ROOT) for path in SOURCE_ROOT.rglob("*.swift"))


def resource_files() -> list[Path]:
    catalogs = [path.relative_to(SOURCE_ROOT) for path in SOURCE_ROOT.rglob("*.xcstrings")]
    assets = [path.relative_to(SOURCE_ROOT) for path in SOURCE_ROOT.rglob("*.xcassets") if path.is_dir()]
    return sorted(catalogs + assets)


def file_type(path: Path) -> str:
    if path.suffix == ".swift":
        return "sourcecode.swift"
    if path.suffix == ".xcstrings":
        return "text.json.xcstrings"
    if path.suffix == ".xcassets":
        return "folder.assetcatalog"
    raise ValueError(f"Unsupported Xcode file type: {path}")


def file_reference_section(files: list[Path]) -> str:
    lines = ["/* Begin PBXFileReference section */"]
    for path in files:
        identifier = stable_id("file", path.as_posix())
        lines.append(
            f"\t\t{identifier} /* {comment(path)} */ = "
            f"{{isa = PBXFileReference; lastKnownFileType = {file_type(path)}; "
            f"path = {quoted(path.name)}; sourceTree = \"<group>\"; }};"
        )
    lines.append(
        f"\t\t{PRODUCT_FILE_ID} /* Screen Remote.app */ = "
        "{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; "
        'path = "Screen Remote.app"; sourceTree = BUILT_PRODUCTS_DIR; };'
    )
    lines.append("/* End PBXFileReference section */")
    return "\n".join(lines)


def build_file_section(sources: list[Path], resources: list[Path]) -> str:
    lines = ["/* Begin PBXBuildFile section */"]
    for path in sources:
        build_id = stable_id("build", path.as_posix())
        file_id = stable_id("file", path.as_posix())
        lines.append(
            f"\t\t{build_id} /* {comment(path)} in Sources */ = "
            f"{{isa = PBXBuildFile; fileRef = {file_id} /* {comment(path)} */; }};"
        )
    for path in resources:
        build_id = stable_id("build", path.as_posix())
        file_id = stable_id("file", path.as_posix())
        lines.append(
            f"\t\t{build_id} /* {comment(path)} in Resources */ = "
            f"{{isa = PBXBuildFile; fileRef = {file_id} /* {comment(path)} */; }};"
        )
    lines.append("/* End PBXBuildFile section */")
    return "\n".join(lines)


def group_id(directory: Path) -> str:
    return SOURCE_GROUP_ID if not directory.parts else stable_id("group", directory.as_posix())


def group_section(files: list[Path]) -> str:
    directories: set[Path] = {Path()}
    for file in files:
        parent = file.parent
        while parent != Path("."):
            directories.add(parent)
            parent = parent.parent

    child_directories: dict[Path, list[Path]] = {directory: [] for directory in directories}
    child_files: dict[Path, list[Path]] = {directory: [] for directory in directories}
    for directory in directories:
        if directory.parts:
            child_directories[directory.parent if directory.parent != Path(".") else Path()].append(directory)
    for file in files:
        parent = file.parent if file.parent != Path(".") else Path()
        child_files[parent].append(file)

    lines = ["/* Begin PBXGroup section */"]
    lines.extend(
        [
            f"\t\t{ROOT_GROUP_ID} = {{",
            "\t\t\tisa = PBXGroup;",
            "\t\t\tchildren = (",
            f"\t\t\t\t{SOURCE_GROUP_ID} /* Screen-Remote */ ,".replace(" */ ,", " */,"),
            f"\t\t\t\t{PRODUCTS_GROUP_ID} /* Products */ ,".replace(" */ ,", " */,"),
            "\t\t\t);",
            "\t\t\tsourceTree = \"<group>\";",
            "\t\t};",
        ]
    )

    for directory in sorted(directories, key=lambda item: (len(item.parts), item.as_posix())):
        identifier = group_id(directory)
        name = "Screen-Remote" if not directory.parts else directory.name
        lines.append(f"\t\t{identifier} /* {name} */ = {{")
        lines.append("\t\t\tisa = PBXGroup;")
        lines.append("\t\t\tchildren = (")
        for child in sorted(child_directories[directory], key=lambda item: item.name.lower()):
            lines.append(f"\t\t\t\t{group_id(child)} /* {child.name} */,")
        for child in sorted(child_files[directory], key=lambda item: item.name.lower()):
            lines.append(f"\t\t\t\t{stable_id('file', child.as_posix())} /* {child.name} */,")
        lines.append("\t\t\t);")
        if not directory.parts:
            lines.append('\t\t\tpath = "Screen-Remote";')
        else:
            lines.append(f"\t\t\tpath = {quoted(directory.name)};")
        lines.append("\t\t\tsourceTree = \"<group>\";")
        lines.append("\t\t};")

    lines.extend(
        [
            f"\t\t{PRODUCTS_GROUP_ID} /* Products */ = {{",
            "\t\t\tisa = PBXGroup;",
            "\t\t\tchildren = (",
            f"\t\t\t\t{PRODUCT_FILE_ID} /* Screen Remote.app */ ,".replace(" */ ,", " */,"),
            "\t\t\t);",
            "\t\t\tname = Products;",
            "\t\t\tsourceTree = \"<group>\";",
            "\t\t};",
            "/* End PBXGroup section */",
        ]
    )
    return "\n".join(lines)


def phase_section(name: str, phase_id: str, files: list[Path]) -> str:
    phase = "Sources" if name == "PBXSourcesBuildPhase" else "Resources"
    lines = [f"/* Begin {name} section */", f"\t\t{phase_id} /* {phase} */ = {{"]
    lines.extend(
        [
            f"\t\t\tisa = {name};",
            "\t\t\tbuildActionMask = 2147483647;",
            "\t\t\tfiles = (",
        ]
    )
    for path in files:
        lines.append(f"\t\t\t\t{stable_id('build', path.as_posix())} /* {comment(path)} in {phase} */,")
    lines.extend(
        [
            "\t\t\t);",
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
            "\t\t};",
            f"/* End {name} section */",
        ]
    )
    return "\n".join(lines)


def replace_section(text: str, name: str, replacement: str) -> str:
    pattern = re.compile(rf"/\* Begin {re.escape(name)} section \*/.*?/\* End {re.escape(name)} section \*/", re.S)
    updated, count = pattern.subn(replacement, text)
    if count != 1:
        raise RuntimeError(f"Expected one {name} section, found {count}")
    return updated


def render() -> str:
    sources = source_files()
    resources = resource_files()
    all_files = sources + resources
    text = PROJECT.read_text()
    text = replace_section(text, "PBXBuildFile", build_file_section(sources, resources))
    text = replace_section(text, "PBXFileReference", file_reference_section(all_files))
    text = replace_section(text, "PBXGroup", group_section(all_files))
    text = replace_section(text, "PBXResourcesBuildPhase", phase_section("PBXResourcesBuildPhase", RESOURCES_PHASE_ID, resources))
    text = replace_section(text, "PBXSourcesBuildPhase", phase_section("PBXSourcesBuildPhase", SOURCES_PHASE_ID, sources))
    return text.rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail when project.pbxproj is out of sync")
    args = parser.parse_args()
    current = PROJECT.read_text()
    generated = render()
    if args.check:
        if current != generated:
            print("Xcode project is out of sync; run scripts/sync-xcode-project.py", file=sys.stderr)
            return 1
        print("Xcode project source references are synchronized")
        return 0
    if current != generated:
        PROJECT.write_text(generated)
        print(f"Synchronized {PROJECT.relative_to(REPO)}")
    else:
        print("Xcode project already synchronized")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
