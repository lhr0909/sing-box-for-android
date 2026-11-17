#!/usr/bin/env python3
"""Check AAR provenance and byte-for-byte native library inclusion in an APK."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def verify(aar, apk, provenance, core_commit, required_symbols):
    manifest = json.loads(provenance.read_text())
    if manifest["core_commit"] != core_commit:
        raise ValueError("provenance core commit does not match the expected commit")
    if sha256(aar.read_bytes()) != manifest["artifacts"][aar.name]:
        raise ValueError("AAR checksum does not match provenance")
    libraries = []
    with zipfile.ZipFile(aar) as source, zipfile.ZipFile(apk) as package:
        for name in source.namelist():
            if not name.startswith("jni/") or not name.endswith(".so"):
                continue
            target = "lib/" + name.removeprefix("jni/")
            native = source.read(name)
            if sha256(native) != sha256(package.read(target)):
                raise ValueError(f"APK native library differs from AAR: {target}")
            for symbol in required_symbols:
                if symbol.encode() not in native:
                    raise ValueError(f"required native symbol missing from {target}: {symbol}")
            libraries.append({"path": target, "sha256": sha256(native)})
    if not libraries:
        raise ValueError("AAR has no JNI libraries")
    return {"core_commit": core_commit, "aar_sha256": sha256(aar.read_bytes()),
            "apk_sha256": sha256(apk.read_bytes()), "native_libraries": libraries,
            "required_symbols": required_symbols}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--aar", type=Path, required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--provenance", type=Path, required=True)
    parser.add_argument("--core-commit", required=True)
    parser.add_argument("--require-symbol", action="append", default=[])
    args = parser.parse_args()
    try:
        result = verify(args.aar, args.apk, args.provenance, args.core_commit, args.require_symbol)
    except (KeyError, ValueError, OSError, zipfile.BadZipFile) as exc:
        parser.exit(1, f"Verification failed: {exc}\n")
    print(json.dumps(result, indent=2))
