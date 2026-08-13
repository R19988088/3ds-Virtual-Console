# Additional Platform Support

## Current Status

The app currently builds GBA and SNES CIAs. Merely accepting another extension
is insufficient: a distributable build needs a 3DS core that can embed the ROM,
boot it without a file picker, keep writable saves outside RomFS, and package as
a unique CIA.

## Candidate Cores

| Platform | Candidate | ROM notes | Main integration work |
| --- | --- | --- | --- |
| Mega Drive / Genesis | [PicoDrive 3DS](https://github.com/bubble2k16/emus3ds) or RetroArch `picodrive` / `genesis_plus_gx` | `.smd`, `.gen`, `.bin`, `.rom` | Add an embedded-ROM startup path; define SRAM/save-state paths; verify Old/New 3DS performance |
| Game Gear | RetroArch `gearsystem` or `genesis_plus_gx` | `.gg` | Build a dedicated core ELF; add direct boot; verify mapper and save behavior |
| Neo Geo Pocket / Color | RetroArch `mednafen_ngp` or `race` | `.ngp`, `.ngc` | Build a dedicated core ELF; add direct boot and persistent saves |
| Arcade | RetroArch FBA 2012 or FBNeo variants | Usually `.zip`; filenames alone do not identify hardware | Select a core from ROM-set metadata; preserve ZIP; handle parent/BIOS sets; verify per-system memory requirements |

RetroArch's official 3DS build definitions explicitly list `picodrive`,
`genesis_plus_gx`, `gearsystem`, `mednafen_ngp`, `race`, `fbalpha2012`, and
FBNeo variants. FBA 2012 CPS-2, CPS-3, and Neo Geo request 80 MB mode, so they
must be tested separately from CPS-1 and may be unsuitable for some Old 3DS
targets.

PicoDrive 3DS documents good Mega Drive support on Old 3DS, with reduced audio
rate, while 32X is intended for New 3DS. Its released application opens ROMs
from the SD card; vcoven therefore needs a source change for per-game embedded
ROM startup instead of wrapping the existing CIA unchanged.

## Recommended Order

1. **MD:** fork PicoDrive 3DS, embed one ROM in RomFS, bypass its file picker,
   redirect SRAM to a title-specific writable directory, then export a reusable
   ELF/RSF pair.
2. **GG:** reuse the proven injection contract with a small Gearsystem or
   Genesis Plus GX core.
3. **NGP/NGC:** apply the same contract to Mednafen NGP or RACE.
4. **Arcade:** expose explicit CPS-1, CPS-2, CPS-3, Neo Geo and general arcade
   choices; require a matching ROM-set/core version and required BIOS/parent
   archives.

Each stage is complete only after install, cold boot, input, audio, suspend,
save/reload and uninstall are verified on the intended Old/New 3DS hardware.

## Sources

- [RetroArch 3DS core build definitions](https://github.com/libretro/RetroArch/blob/master/pkg/ctr/Makefile.cores)
- [PicoDrive 3DS documentation and source](https://github.com/bubble2k16/emus3ds/blob/master/readme-picodrive.md)
- [Beetle NGP libretro](https://github.com/libretro/beetle-ngp-libretro)
