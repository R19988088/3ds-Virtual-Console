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
| Arcade and supported consoles | One FBNeo core | Usually `.zip`; filenames alone do not identify hardware | Preserve ZIP; validate the matching ROM-set; handle parent/BIOS sets; verify per-system memory requirements |

FBNeo's libretro core includes the Sega, NEC, SNK and computer drivers listed
in its own DAT files. vcoven uses one FBNeo core in its user-facing pipeline;
the exact ROM-set, BIOS and parent archive remain part of validation and do not
need separate platform choices in the UI.

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
4. **Arcade and FBNeo consoles:** use one FBNeo core and automatically validate its matching ROM-set,
   required BIOS/parent archives and hardware memory requirements.

Each stage is complete only after install, cold boot, input, audio, suspend,
save/reload and uninstall are verified on the intended Old/New 3DS hardware.

## Sources

- [RetroArch 3DS core build definitions](https://github.com/libretro/RetroArch/blob/master/pkg/ctr/Makefile.cores)
- [PicoDrive 3DS documentation and source](https://github.com/bubble2k16/emus3ds/blob/master/readme-picodrive.md)
- [Beetle NGP libretro](https://github.com/libretro/beetle-ngp-libretro)
