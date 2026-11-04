# Release procedure

1. Update `project.godot` config/version, the menu caption and its English translation, Windows file/product versions and Android version/name in `export_presets.cfg`. Increase Android version/code even when renumbering a public version.
2. Update output paths in `tools/build.ps1` and `tools/build_android.py`, documentation and `CHANGELOG.md`. Do not change network or save versions unless their formats actually change.
3. Run the full checked build described in [BUILDING.md](BUILDING.md). Keep the existing private Android signing key; back it up outside Git.
4. Check the files staged for publication for private config, profiles, keys and generated data. Check APK signatures and Windows startup. Record hardware/deployment checks that were not run.
5. Commit the source, tag `vX.Y.Z` and publish a GitHub release with Windows ZIP, Android APK, VPS source ZIP, PHP hosting ZIP and `SHA256SUMS.txt`. The tag must point to the exact source used by the build. Include known limitations in release notes.
6. Verify the public repository, tag, attachment sizes and downloaded checksums. Never attach signing keys or a locally configured server archive.

## Source-only releases

When publishing without local builds, update versions and the changelog, run focused source checks, then commit and tag the exact source. Create the GitHub release without uploaded assets. GitHub provides source archives automatically. State clearly in the release notes and README that no EXE/APK or locally generated archives are attached. For 0.2.0 this source-only procedure replaces the full local export/attachment steps above.
