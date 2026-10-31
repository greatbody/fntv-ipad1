#!/usr/bin/env python3
"""Copy a user-provided iPhoneOS9.3 SDK and prepare only that private build copy."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("destination", type=Path)
args = parser.parse_args()
source, sdk = args.source.resolve(), args.destination.resolve()
if sdk == source or source in sdk.parents or sdk in source.parents:
    parser.error("SDK source and destination must be separate directories")
if not (source / "usr/lib/crt1.3.1.o").is_file():
    parser.error("Provide an iPhoneOS9.3 SDK containing usr/lib/crt1.3.1.o")
marker = sdk / ".fntv-prepared.json"
identity = {"source": str(source), "recipe": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
if sdk.exists():
    if marker.is_file() and json.loads(marker.read_text()) == identity:
        print("Using prepared build SDK")
        raise SystemExit(0)
    parser.error("Destination already exists without matching preparation; remove the build SDK copy and retry")
sdk.parent.mkdir(parents=True, exist_ok=True)
# macOS clone copy preserves the input SDK and shares file storage on APFS.
subprocess.run(["/bin/cp", "-cR", str(source), str(sdk)], check=True)
for path in sdk.rglob("*"):
    if path.is_symlink() and not path.resolve().is_relative_to(sdk):
        parser.error("SDK contains a symlink outside its build copy; no stubs were modified")

# Modern TAPI misreads the merged simulator architectures: theos/sdks issue #56.
changed = 0
for path in sdk.rglob("*.tbd"):
    text = path.read_text()
    lines = text.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if line.startswith("archs:"):
            archs = [item.strip() for item in line.split("[", 1)[1].split("]", 1)[0].split(",")]
            if "armv7" in archs and any(arch in archs for arch in ("i386", "x86_64")):
                kept = [arch for arch in archs if arch not in ("i386", "x86_64")]
                lines[index] = "archs: [ " + ", ".join(kept) + " ]\n"
                path.write_text("".join(lines))
                changed += 1
            break

# The SDK references an omitted library with no exports: theos/sdks issue #10.
system = sdk / "usr/lib/libSystem.tbd"
text = system.read_text()
if not (sdk / "usr/lib/system/liblaunch.tbd").exists():
    text = text.replace("/usr/lib/system/liblaunch.dylib, ", "")
    assert "/usr/lib/system/liblaunch.dylib" not in text
# The extracted SDK omits these libc aliases; dlsym + behavior verified on iOS 5.1.1.
aliases = ("_memcmp", "_memcpy", "_memmove", "_memset")
missing = [symbol for symbol in aliases if symbol not in text]
if missing:
    export_marker = "symbols:            [ "
    assert text.count(export_marker) == 1, "Expected one libSystem export list"
    text = text.replace(export_marker, export_marker + ", ".join(missing) + ", ", 1)
assert all(text.count(symbol) == 1 for symbol in aliases)
temporary = system.with_suffix(".tbd.tmp")
temporary.write_text(text)
temporary.replace(system)
print(f"SDK prepared: {changed} mixed-architecture stubs corrected; empty liblaunch reference removed; {len(missing)} verified libc aliases restored")

# These six public URL classes moved to CFNetwork after iOS 5; device dlsym/dladdr
# proves both their classes and metaclasses belong to Foundation on iOS 5.1.1.
url_classes = ("_NSURLRequest", "_NSMutableURLRequest", "_NSURLConnection",
               "_NSHTTPURLResponse", "_NSURLResponse", "_NSCachedURLResponse")
for framework in ("Foundation", "CFNetwork"):
    path = sdk / f"System/Library/Frameworks/{framework}.framework/{framework}.tbd"
    text = path.read_text()
    matches = list(re.finditer(r"objc-classes:\s*\[\s*([^]]*)\]", text))
    assert len(matches) == 1, f"Expected one {framework} class export list"
    match = matches[0]
    classes = match.group(1)
    for name in url_classes:
        entries = [entry.strip() for entry in classes.split(",")]
        assert entries.count(name) <= 1
        if framework == "Foundation" and name not in entries:
            classes = name + ", " + classes
        elif framework == "CFNetwork" and name in entries:
            classes, removed = re.subn(r"(?<!\w)" + re.escape(name) + r",\s*", "", classes, count=1)
            assert removed == 1
    entries = [entry.strip() for entry in classes.split(",")]
    assert all((name in entries) == (framework == "Foundation") for name in url_classes)
    text = text[:match.start(1)] + classes + text[match.end(1):]
    temporary = path.with_suffix(".tbd.tmp")
    temporary.write_text(text)
    temporary.replace(path)
print("iOS 5 compatibility: six verified URL class/metaclass exports bound to Foundation")

marker.write_text(json.dumps(identity) + "\n")
