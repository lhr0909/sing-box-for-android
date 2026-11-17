#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "Usage: $0 CORE_CHECKOUT OUTPUT_DIRECTORY NATIVE_BUILD_LOCK [android/arm64]" >&2
    exit 2
fi

core_dir=$(cd "$1" && pwd -P)
mkdir -p "$2"
output_dir=$(cd "$2" && pwd -P)
lock_dir=$(cd "$(dirname "$3")" && pwd -P)/$(basename "$3")
platform=${4:-android/arm64}

if [[ "$output_dir" == "$core_dir" || "$output_dir" == "$core_dir/"* ]]; then
    echo "Keep artifacts outside the core checkout." >&2
    exit 2
fi
git -C "$core_dir" diff --quiet HEAD --
if [[ -n "$(git -C "$core_dir" ls-files --others --exclude-standard)" ]]; then
    echo "Commit the core sources before building a traceable library." >&2
    exit 1
fi
core_commit=$(git -C "$core_dir" rev-parse HEAD)
core_tree=$(git -C "$core_dir" rev-parse 'HEAD^{tree}')

# All clients sharing this core checkout must use the same lock directory.
# A failed mkdir never removes or takes over another process's lock.
mkdir "$lock_dir"
cleanup() {
    rm -f "$lock_dir/android-owner.json"
    rmdir "$lock_dir"
}
trap cleanup EXIT
python3 - "$lock_dir/android-owner.json" "$$" "$core_commit" <<'PY'
import json, sys
from datetime import datetime, timezone
with open(sys.argv[1], "w") as f:
    json.dump({"role": "android", "pid": int(sys.argv[2]), "core_commit": sys.argv[3],
               "started_at": datetime.now(timezone.utc).isoformat()}, f, indent=2)
PY

cd "$core_dir"
go run ./cmd/internal/build_libbox -target android -platform "$platform"

# A concurrent source edit must not produce a misleading provenance record.
test "$(git rev-parse HEAD)" = "$core_commit"
git diff --quiet HEAD --
test -z "$(git ls-files --others --exclude-standard)"
cp libbox.aar libbox-legacy.aar "$output_dir/"
python3 - "$output_dir" "$core_commit" "$core_tree" "$platform" <<'PY'
import hashlib, json, os, pathlib, subprocess, sys
from datetime import datetime, timezone
p = pathlib.Path(sys.argv[1])
manifest = {
    "core_commit": sys.argv[2], "core_tree": sys.argv[3], "platform": sys.argv[4],
    "built_at": datetime.now(timezone.utc).isoformat(),
    "go": subprocess.check_output(["go", "version"], text=True).strip(),
    "java_home": os.environ.get("JAVA_HOME"),
    "android_ndk_home": os.environ.get("ANDROID_NDK_HOME"),
    "artifacts": {name: hashlib.sha256((p / name).read_bytes()).hexdigest()
                  for name in ("libbox.aar", "libbox-legacy.aar")},
}
(p / "libbox-provenance.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY
echo "Libraries and libbox-provenance.json written to $output_dir"
