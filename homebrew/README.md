# Homebrew formula

This directory contains the Homebrew formula for `vcoven`. To publish:

## 1. Tag a release in the main repo

```bash
cd /path/to/vcoven
git tag v0.1.0
git push origin v0.1.0
```

GitHub will auto-generate a tarball at:
`https://github.com/vedoot/vcoven/archive/refs/tags/v0.1.0.tar.gz`

## 2. Compute checksums

```bash
# Main project tarball
curl -sL https://github.com/vedoot/vcoven/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256

# Third-party tool resources
curl -sL https://github.com/3DSGuy/Project_CTR/releases/download/makerom-v0.19.0/makerom-v0.19.0-macos_arm64.zip | shasum -a 256
curl -sL https://github.com/3DSGuy/Project_CTR/releases/download/makerom-v0.19.0/makerom-v0.19.0-macos_x86_64.zip | shasum -a 256
curl -sL https://github.com/3DSGuy/Project_CTR/releases/download/ctrtool-v1.3.0/ctrtool-v1.3.0-macos_arm64.zip  | shasum -a 256
curl -sL https://github.com/3DSGuy/Project_CTR/releases/download/ctrtool-v1.3.0/ctrtool-v1.3.0-macos_x86_64.zip | shasum -a 256
curl -sL https://github.com/dnasdw/3dstool/releases/download/v1.2.6/3dstool_macos_x86_64.tar.gz                  | shasum -a 256
curl -sL https://github.com/carstene1ns/3ds-bannertool/archive/refs/heads/master.tar.gz                          | shasum -a 256
```

Paste each sha256 into the corresponding `REPLACE_WITH_*` slot in `vcoven.rb`.

## 3. Create the tap repo

A Homebrew tap is just a separate GitHub repo whose name starts with `homebrew-`.
Create `https://github.com/vedoot/homebrew-vcoven` and put the formula at:

```
homebrew-vcoven/
└── Formula/
    └── vcoven.rb
```

## 4. Install via brew

```bash
brew tap vedoot/vcoven
brew install vcoven
vcoven info
```

## 5. Updates

When you cut a new release, update the `url`, `sha256`, and any tool resource
versions in `vcoven.rb`, then push to `homebrew-vcoven`. Users update with:

```bash
brew upgrade vcoven
```

## Graduating to homebrew-core

Once vcoven has 75+ stars on GitHub and a clear track record, you can submit it
to `Homebrew/homebrew-core` so users don't need to tap. See the
[Homebrew acceptable formulae policy](https://docs.brew.sh/Acceptable-Formulae)
for the exact criteria.
