# Changelog

All notable changes to vcoven are recorded here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the CLI follows [SemVer](https://semver.org/spec/v2.0.0.html). Web-stack (Cloud Run + Firebase hosting) ships continuously from `main`.

## [Unreleased]

### Added
- `web/` tree now lives in the repo: Cloud Run API (`web/server/`) and Firebase hosting source (`web/public/`). Previous state lived only on local disk and deployed artifacts.
- Firebase Auth Google sign-in on `admin.html`. Admin dashboard data now requires a signed-in account on the allowlist.
- Firestore security rules tightened: `feedback` and `builds` collections are publicly writable (anonymous users can still submit feedback and log builds) but only admin-readable.
- `test-roms/` archival in Cloud Run server — every build attempt (success or failure) writes the ROM (deduped by SHA-256) and a per-build metadata JSON to `gs://vcoven-builds/test-roms/` for later replay.

### Changed
- TID generator (`regenTitleId()`) rewritten. New format: `0004000000XXXX00` where XXXX is pinned to `0xF000-0xFFFF`. Three empirically-verified AM/PM rules enforced:
  1. Top byte of the 24-bit unique ID must be `0x00` (otherwise AM rejects with `0xc8804478` when home menu queries the title)
  2. Variation byte (lowest byte of title ID) must be `0x00` (otherwise PM_LOW rejects launch with `0xd9605c05` and the home menu crashes)
  3. XXXX pinned to F-range to avoid Nintendo retail collisions
- Admin `/admin/stats` now sourced from Firestore (all-time, append-only) instead of the GCS `builds/` folder (which auto-deletes after 1 day). Counters no longer stuck at ~80.
- Admin dashboard paginates all Firestore build docs instead of capping at 200, so success/error/unique-ROM counts reflect all-time.
- Build output blob names changed from `builds/{uuid}/{filename}.cia` to `builds/{uuid}.cia` with a `Content-Disposition: attachment; filename="..."` header. Shorter URLs → denser, more reliably-scanned QR codes; file still downloads with its human-readable name.
- Python dependencies pinned in `web/server/Dockerfile` so Cloud Run rebuilds are deterministic.
- Alpha-warning banner on the form now points to GitHub issues instead of a one-off feedback button.

### Fixed
- Fixed the single biggest source of 3DS install/launch failures (see TID generator rules above). Prior generator output had a ~1/4096 chance of producing a TID the 3DS would accept.

## [0.1.0] — 2026-04-08

### Added
- Initial release of the `vcoven` CLI: builds installable GBA Virtual Console CIA files for the Nintendo 3DS from a `.gba` ROM plus user-provided icon/banner images. Self-contained; no donor CIA required.
- Homebrew tap (`vedoot/vcoven`) with prebuilt binaries for macOS arm64 and Linux x86_64.
- `vcoven batch` subcommand for building many injects from a TOML config.
- Bundled template (`template/`): NCCH header, exheader, SMDH shell, empty RomFS, GBA VC boot animation, AGB_FIRM config block. ~34 KB total, zero copyrighted game content.
- CI workflow to build `bannertool` from source on matrix runners.

[Unreleased]: https://github.com/vedoot/vcoven/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/vedoot/vcoven/releases/tag/v0.1.0
