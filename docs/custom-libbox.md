# Building Android with a custom core

Android uses a local AAR; checking out a sibling sing-box repository does not
select that core automatically. Keep the Android revision compatible with the
core's `clients/android` gitlink. No client UI change is needed for legacy Snell
JSON configurations once the core implements them.

The pinned client predates the core's platform auto-redirect callbacks. Its
platform wrapper explicitly reports that capability as unavailable; this keeps
the existing service behavior while satisfying the generated binding interface.

Use the Go, gomobile/gobind, Java, and Android NDK versions specified by the core's
`Makefile` and `.github/workflows/build.yml`. At the starting revision these are
Go 1.26.10, gomobile/gobind v0.1.13, OpenJDK 17, and NDK r28. Install the mobile
tools with `make lib_install` in the core checkout and put `$(go env GOPATH)/bin`
on PATH. Set `JAVA_HOME`, `ANDROID_HOME`, and `ANDROID_NDK_HOME` explicitly.
The native builder enforces JDK 17. Run Gradle lint with JDK 21: its bundled
JavaDoc analyzer calls `List.removeLast()`, which is absent from JDK 17. Select
that JVM for the Gradle command only; the native build still uses JDK 17.

Commit the custom core before building. From this Android checkout:

```sh
./scripts/build-libbox.sh /path/to/sing-box /path/to/artifacts \
  /path/to/coordination/native-build.lock android/arm64

./gradlew :app:assembleOtherDebug \
  -PlibboxAar=/path/to/artifacts/libbox.aar
```

The build script invokes the core's standard Android library builder, preserving
its feature tags (including Tailscale), and builds both API 24 and API 21 AARs.
It serializes shared core native outputs using an exclusive directory lock. Every
client agent using that core must pass the same lock path. An existing lock is
an error; inspect its owner and coordinate instead of deleting a live lock.
The standard core builder may also copy AARs into a sibling client's `app/libs`
when that directory exists. The Gradle property above selects the recorded
artifact explicitly. Relative property paths resolve from the `app` directory.
Without these properties the original `app/libs` paths remain the defaults.
With an explicit override, packaging preserves `libbox.so` bytes instead of
stripping the recorded custom library again, so the AAR/APK comparison is exact.
Use `-PlibboxLegacyAar=/path/to/artifacts/libbox-legacy.aar` for `otherLegacy`.

The default native target is ARM64 only. Use `android` as the fourth script
argument for all supported ABIs. An ARM64-only AAR does not make the other ABI
split APKs usable; select the ARM64 APK or the universal APK containing ARM64.
These commands build debug APKs locally and do not install them.

The artifact directory contains `libbox-provenance.json` with the exact committed
core tree and library checksums. Verify the packaged library against it:

```sh
python3 scripts/verify-libbox.py \
  --aar /path/to/artifacts/libbox.aar \
  --apk /path/to/arm64-debug.apk \
  --provenance /path/to/artifacts/libbox-provenance.json \
  --core-commit FULL_CORE_COMMIT \
  --require-symbol EXPECTED_CUSTOM_GO_SYMBOL
```

This checks provenance consistency, byte-identical native inclusion, and any
requested custom symbols. It is not protocol interoperability evidence. Test
Snell v2 TCP and v3 TCP/UDP separately against a reference peer using throwaway
credentials; v2 has no UDP support. Local loopback results do not establish
acceptance by a real GIA server.

Keep AARs, APKs, logs, credentials, and local toolchains outside Git. The APK is a
local test build, not an app-store release.
