# homebrew/

This directory mirrors the **live Homebrew formula** that's deployed at
[`vedoot/homebrew-vcoven`](https://github.com/vedoot/homebrew-vcoven).

The file `vcoven.rb` here is a copy of `Formula/vcoven.rb` in the tap repo. It's
included in the source repo so anyone browsing vcoven on GitHub can see exactly
how it's installed without leaving the page.

**End users do not need anything in this directory.** Install with:

```bash
brew tap vedoot/vcoven
brew install vcoven
vcoven info
```

See the [main README](../README.md) for the supported platform matrix.

---

## Maintainer notes

This section is for whoever cuts new vcoven releases.

### Where things live

| File | Purpose |
|------|---------|
| `homebrew/vcoven.rb` (here) | Mirror of the deployed formula. Read-only reference. |
| `vedoot/homebrew-vcoven/Formula/vcoven.rb` | The actual formula Homebrew downloads when users tap. **This is the source of truth.** |
| `.github/workflows/build-bannertool.yml` | CI that builds bannertool for all supported platforms and uploads to a release. |

### Cutting a new release

1. **Tag a release** in this repo:
   ```bash
   git tag v0.X.Y
   git push origin v0.X.Y
   ```
2. **Create the GitHub release**:
   ```bash
   gh release create v0.X.Y --title "v0.X.Y" --notes-file release-notes.md
   ```
3. **Build prebuilt bannertool binaries** for all platforms by manually
   triggering the CI workflow:
   ```bash
   gh workflow run build-bannertool.yml -f release_tag=v0.X.Y
   ```
   Wait for it to finish — the workflow uploads `bannertool-<platform>.tar.gz`
   files directly to the release.
4. **Compute SHA256 checksums** for the new release:
   ```bash
   # Source tarball
   curl -sL https://github.com/vedoot/vcoven/archive/refs/tags/v0.X.Y.tar.gz | shasum -a 256

   # Bannertool binaries (after CI finishes)
   curl -sL https://github.com/vedoot/vcoven/releases/download/v0.X.Y/bannertool-macos-arm64.tar.gz | shasum -a 256
   curl -sL https://github.com/vedoot/vcoven/releases/download/v0.X.Y/bannertool-linux-x86_64.tar.gz | shasum -a 256
   ```
5. **Update the deployed formula** in `vedoot/homebrew-vcoven`:
   - Bump `url` and `sha256` to point at v0.X.Y
   - Update each `bannertool` resource block with the new URLs/SHAs
   - Commit and push to the tap repo
6. **Sync the mirror in this repo** by copying the updated formula:
   ```bash
   cp ../homebrew-vcoven/Formula/vcoven.rb homebrew/vcoven.rb
   git add homebrew/vcoven.rb && git commit -m "Sync formula mirror to v0.X.Y"
   ```
7. **Verify**:
   ```bash
   brew untap vedoot/vcoven 2>/dev/null
   brew tap vedoot/vcoven
   brew install vcoven
   vcoven info
   ```

### Why bannertool is built in CI but the others aren't

- `makerom`, `ctrtool`, `3dstool` all ship prebuilt binaries on their upstream
  GitHub releases for macOS arm64, macOS x86_64, and Linux x86_64. The formula
  references those URLs directly.
- `bannertool` (carstene1ns/3ds-bannertool fork) does **not** ship prebuilt
  binaries. We have to build it ourselves. The CI workflow at
  `.github/workflows/build-bannertool.yml` does this on a matrix of platforms
  and uploads the results to our own release.

### Graduating to homebrew-core

Once vcoven has 75+ stars on GitHub and a clear track record, you could
submit it to `Homebrew/homebrew-core` so users don't need to tap. See the
[Homebrew acceptable formulae policy](https://docs.brew.sh/Acceptable-Formulae)
for criteria. Until then, the personal tap is the right home.
