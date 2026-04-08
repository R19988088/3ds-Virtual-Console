#!/usr/bin/env python3
"""
vcoven — bake GBA Virtual Console CIA injects for the Nintendo 3DS.

Usage:
  vcoven setup <donor.cia>             Extract a donor CIA once and cache its
                                       parts. Required before building.
  vcoven build <rom.gba> [options]     Build a single CIA inject from a ROM.
  vcoven batch <config.toml>           Build multiple CIAs from a TOML config.
  vcoven info                          Show paths and tool versions.

Run `vcoven <command> --help` for per-command details.
"""
from __future__ import annotations

import argparse
import hashlib
import logging
import os
import shutil
import struct
import subprocess
import sys
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Tuple

# ─── Paths ────────────────────────────────────────────────────────────────────

PROG_NAME    = "vcoven"
DEFAULT_DATA = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / PROG_NAME
DATA_DIR     = Path(os.environ.get("VCOVEN_DATA_DIR", DEFAULT_DATA))
DONOR_CACHE  = DATA_DIR / "donor_cache"
WORK_ROOT    = DATA_DIR / "work"

# Bundled tool binaries and template — looked up relative to the script first
SCRIPT_DIR    = Path(__file__).resolve().parent
TOOLS_DIR     = SCRIPT_DIR / "tools"
TEMPLATE_DIR  = SCRIPT_DIR / "template"

def find_tool(name: str) -> str:
    """Locate a bundled or system-installed tool binary."""
    bundled = TOOLS_DIR / name
    if bundled.exists():
        return str(bundled)
    found = shutil.which(name)
    if found:
        return found
    raise VcovenError(
        f"Required tool '{name}' not found. Looked in {TOOLS_DIR} and $PATH.\n"
        f"Install via your package manager or build from source. See README."
    )

# ─── Errors and logging ───────────────────────────────────────────────────────

class VcovenError(Exception):
    """User-facing error. Caught at the top level and printed cleanly."""

log = logging.getLogger(PROG_NAME)

def configure_logging(verbose: bool) -> None:
    handler = logging.StreamHandler()
    fmt = "%(message)s" if not verbose else "[%(levelname)s] %(message)s"
    handler.setFormatter(logging.Formatter(fmt))
    log.addHandler(handler)
    log.setLevel(logging.DEBUG if verbose else logging.INFO)

def run_cmd(cmd: list[str], label: str) -> None:
    log.debug("$ %s", " ".join(cmd))
    res = subprocess.run(cmd, capture_output=True)
    if res.returncode != 0:
        raise VcovenError(
            f"{label} failed (exit {res.returncode})\n"
            f"  cmd: {' '.join(cmd)}\n"
            f"  stdout: {res.stdout.decode(errors='replace')[-500:]}\n"
            f"  stderr: {res.stderr.decode(errors='replace')[-500:]}"
        )

# ─── AGB_FIRM footer (the GBA VC config block at end of code.bin) ─────────────

# Save type IDs from the AGB_FIRM footer spec.
SAVE_NONE      = 0xFF
SAVE_EEPROM_8  = 0x00
SAVE_EEPROM_64 = 0x02
SAVE_FLASH_512 = 0x04
SAVE_FLASH_1M  = 0x0A
SAVE_SRAM_256  = 0x0E

SAVE_NAMES = {
    SAVE_EEPROM_8:  "EEPROM 8K",
    SAVE_EEPROM_64: "EEPROM 64K",
    SAVE_FLASH_512: "FLASH 512K",
    SAVE_FLASH_1M:  "FLASH 1M",
    SAVE_SRAM_256:  "SRAM 256K",
    SAVE_NONE:      "none",
}

def detect_save_type(rom_bytes: bytes) -> int:
    """Scan a GBA ROM for save signature strings to identify the save type.
    Order matters: more specific signatures must be checked first."""
    if b"FLASH1M_V" in rom_bytes:
        return SAVE_FLASH_1M
    if b"FLASH512_V" in rom_bytes or b"FLASH_V" in rom_bytes:
        return SAVE_FLASH_512
    if b"EEPROM_V" in rom_bytes:
        return SAVE_EEPROM_64
    if b"SRAM_V" in rom_bytes or b"SRAM_F_V" in rom_bytes:
        return SAVE_SRAM_256
    return SAVE_NONE

def build_code_bin(rom_bytes: bytes, donor_config_block: bytes,
                   save_override: Optional[int] = None) -> tuple[bytes, int]:
    """Build a code.bin: GBA ROM followed by the AGB_FIRM footer.
    Reuses the donor's config block (LUT, sleep mask, etc.) but overwrites
    rom_size and save_type for the new ROM."""
    rom_size = len(rom_bytes)
    save_type = save_override if save_override is not None else detect_save_type(rom_bytes)

    cfg = bytearray(donor_config_block)
    struct.pack_into("<I", cfg, 0x004, rom_size)
    struct.pack_into("<I", cfg, 0x008, save_type)

    # Layout matches the donor:
    #   [rom][config 0x324][12 byte pad][2x16 byte section descriptors][16 byte .CAA header]
    sections  = struct.pack("<IIII", 0, 0,        rom_size, 0)         # type=0 ROM
    sections += struct.pack("<IIII", 1, rom_size, 0x324,    0)         # type=1 Config

    section_offset_in_file = rom_size + 0x324 + 12
    caa_header = struct.pack("<4sIII", b".CAA", 1, section_offset_in_file, 2 << 4)

    new_code = (
        rom_bytes
        + bytes(cfg)
        + b"\x00" * 12
        + sections
        + caa_header
    )
    return new_code, save_type

# ─── NCCH header / exheader patches ───────────────────────────────────────────

def patch_ncch_header(hdr: bytes, title_id: int, product_code: str) -> bytes:
    """Patch the NCCH header with new title ID, product code, and the
    NoCrypto bit. NoCrypto MUST be set before 3dstool repacks; otherwise
    3dstool encrypts the exheader/exefs and our patches become garbage."""
    out = bytearray(hdr)
    struct.pack_into("<Q", out, 0x108, title_id)             # partition ID
    struct.pack_into("<Q", out, 0x118, title_id)             # program ID
    pc = product_code.encode("ascii")[:16].ljust(16, b"\x00")
    out[0x150:0x160] = pc
    out[0x18f] |= 0x04                                       # NoCrypto bit
    return bytes(out)

def patch_exheader(exh: bytes, title_id: int, product_code: str) -> bytes:
    """Patch exheader title-ID-bearing fields and the application title.

    The application title at offset 0x000 is an 8-byte ASCII identifier the
    3DS uses to tag the title. **It must be non-empty** — leaving it zeroed
    causes silent launch failures (ErrDisp 'SD card removed') even though the
    install succeeds. We derive it from the product code's 4-char suffix.

    The Access Descriptor (offset 0x400+) is left untouched — it's signed
    and CFW tolerates SCI/AD program ID mismatch, but tampering with the AD
    invalidates its signature."""
    out = bytearray(exh)
    # Application title from product code: "CTR-N-EMER" → "EMER\0\0\0\0"
    # Strip well-known prefixes, take up to 8 chars, pad with NULs
    tag = product_code
    for prefix in ("CTR-N-", "CTR-P-", "CTR-H-", "CTR-T-"):
        if tag.startswith(prefix):
            tag = tag[len(prefix):]
            break
    tag_bytes = tag.encode("ascii")[:8].ljust(8, b"\x00")
    out[0x000:0x008] = tag_bytes
    struct.pack_into("<Q", out, 0x1c8, title_id)             # SCI JumpId
    struct.pack_into("<Q", out, 0x200, title_id)             # ACI ProgramId
    return bytes(out)

def fix_ncch_hashes(cxi_path: Path) -> None:
    """3dstool keeps the input NCCH header verbatim — it doesn't recompute
    the hashes covering exheader/exefs/romfs. We compute the SHA256s ourselves
    and overwrite them in the rebuilt CXI. Also re-sets the NoCrypto flag,
    which 3dstool clears when writing output."""
    cxi = bytearray(cxi_path.read_bytes())
    hdr = cxi[:0x200]

    exh_size = int.from_bytes(hdr[0x180:0x184], "little")
    exh_data = bytes(cxi[0x200:0x200 + exh_size])
    cxi[0x160:0x180] = hashlib.sha256(exh_data).digest()

    exefs_offset      = int.from_bytes(hdr[0x1a0:0x1a4], "little") * 0x200
    exefs_hash_region = int.from_bytes(hdr[0x1a8:0x1ac], "little") * 0x200
    cxi[0x1c0:0x1e0]  = hashlib.sha256(
        bytes(cxi[exefs_offset : exefs_offset + exefs_hash_region])
    ).digest()

    romfs_offset      = int.from_bytes(hdr[0x1b0:0x1b4], "little") * 0x200
    romfs_hash_region = int.from_bytes(hdr[0x1b8:0x1bc], "little") * 0x200
    if romfs_offset and romfs_hash_region:
        cxi[0x1e0:0x200] = hashlib.sha256(
            bytes(cxi[romfs_offset : romfs_offset + romfs_hash_region])
        ).digest()

    cxi[0x18f] |= 0x04
    cxi_path.write_bytes(bytes(cxi))

# ─── SMDH (icon.icn) patching ─────────────────────────────────────────────────

def pack_exefs(files: dict[str, bytes]) -> bytes:
    """Build a 3DS ExeFS file from a dict of {name: bytes}.

    The ExeFS format:
        - 0x000: file table — up to 10 entries × 16 bytes (name[8], off[4], size[4])
        - 0x0A0: reserved (0x20 bytes)
        - 0x0C0: file hashes — up to 10 × SHA256 (32 bytes), stored in REVERSE order
        - 0x200: file data, each file aligned to 0x200 bytes

    `files` maps short ASCII names ('.code', 'banner', 'icon') to raw bytes.
    Up to 10 files. Build order is dict insertion order, which sets the file
    table layout.
    """
    if len(files) > 10:
        raise VcovenError(f"ExeFS supports max 10 files (got {len(files)})")

    header = bytearray(0x200)
    data_blob = bytearray()
    file_offset = 0
    entries = list(files.items())

    for i, (name, content) in enumerate(entries):
        name_bytes = name.encode("ascii")
        if len(name_bytes) > 8:
            raise VcovenError(f"ExeFS file name too long (max 8 bytes): {name}")
        # File table entry
        struct.pack_into("8sII", header, i * 16,
                         name_bytes.ljust(8, b"\x00"),
                         file_offset,
                         len(content))
        # Hash table — reverse order, slot (9 - i)
        digest = hashlib.sha256(content).digest()
        hash_offset = 0xC0 + (9 - i) * 0x20
        header[hash_offset:hash_offset + 32] = digest

        data_blob += content
        # Pad to 0x200 alignment
        pad = (-len(content)) % 0x200
        data_blob += b"\x00" * pad
        file_offset += len(content) + pad

    return bytes(header) + bytes(data_blob)

def patch_smdh_titles(icon: bytes, short: str, long_: str, publisher: str) -> bytes:
    """Patch all 16 language slots with new title strings (UTF-16-LE)."""
    out = bytearray(icon)

    def encode(text: str, field_size: int) -> bytes:
        max_chars = (field_size // 2) - 1
        return text[:max_chars].encode("utf-16-le").ljust(field_size, b"\x00")

    short_b = encode(short, 0x80)
    long_b  = encode(long_, 0x100)
    pub_b   = encode(publisher, 0x80)
    for i in range(16):
        base = 0x8 + i * 0x200
        out[base:base + 0x80]               = short_b
        out[base + 0x80:base + 0x180]       = long_b
        out[base + 0x180:base + 0x200]      = pub_b
    return bytes(out)

# 3DS GPU swizzle: 8x8 tiles, pixels within each tile in Morton order.
TILE_MORTON_LUT = [
     0,  1,  4,  5, 16, 17, 20, 21,
     2,  3,  6,  7, 18, 19, 22, 23,
     8,  9, 12, 13, 24, 25, 28, 29,
    10, 11, 14, 15, 26, 27, 30, 31,
    32, 33, 36, 37, 48, 49, 52, 53,
    34, 35, 38, 39, 50, 51, 54, 55,
    40, 41, 44, 45, 56, 57, 60, 61,
    42, 43, 46, 47, 58, 59, 62, 63,
]

def rgb565(r: int, g: int, b: int) -> int:
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)

def image_to_swizzled_rgb565(img) -> bytes:
    """Convert a PIL RGB image (square, side multiple of 8) to the swizzled
    RGB565 layout the 3DS expects for SMDH icons."""
    img = img.convert("RGB")
    side = img.width
    if img.height != side or side % 8 != 0:
        raise VcovenError(f"Icon must be square with side multiple of 8 (got {img.size})")
    pixels = img.load()
    out = bytearray()
    tiles_per_row = side // 8
    for ty in range(tiles_per_row):
        for tx in range(tiles_per_row):
            tile = [0] * 64
            for py in range(8):
                for px in range(8):
                    morton = TILE_MORTON_LUT[py * 8 + px]
                    r, g, b = pixels[tx * 8 + px, ty * 8 + py]
                    tile[morton] = rgb565(r, g, b)
            for v in tile:
                out += v.to_bytes(2, "little")
    return bytes(out)

def load_square_icon(path: Path, side: int):
    """Load an image, center-crop to square, resize to `side`×`side`."""
    from PIL import Image
    img = Image.open(path).convert("RGB")
    s = min(img.width, img.height)
    left = (img.width - s) // 2
    top  = (img.height - s) // 2
    img = img.crop((left, top, left + s, top + s))
    return img.resize((side, side), Image.LANCZOS)

def load_banner_image(path: Path, width: int = 256, height: int = 128):
    """Load an image and fit it to 256×128, letterboxing on a black background."""
    from PIL import Image
    img = Image.open(path).convert("RGB")
    img.thumbnail((width, height), Image.LANCZOS)
    canvas = Image.new("RGB", (width, height), (0, 0, 0))
    x = (width - img.width) // 2
    y = (height - img.height) // 2
    canvas.paste(img, (x, y))
    return canvas

def patch_smdh_icons(icon: bytes, badge_large: bytes, badge_small: bytes) -> bytes:
    out = bytearray(icon)
    out[0x2040:0x2040 + 0x480]  = badge_small   # 24×24
    out[0x24c0:0x24c0 + 0x1200] = badge_large   # 48×48
    return bytes(out)

# ─── Banner ───────────────────────────────────────────────────────────────────

def make_silent_wav(path: Path, duration_sec: float = 1.0) -> None:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(22050)
        w.writeframes(b"\x00\x00" * int(22050 * duration_sec))

# ─── Donor extraction ─────────────────────────────────────────────────────────

@dataclass
class Template:
    """The minimal set of bytes vcoven needs to assemble a CIA inject. By
    default these come from the bundled `template/` directory; users can
    override with `--use-donor` to extract from their own GBA VC CIA dump."""
    ncch_header:  bytes
    exheader:     bytes
    icon:         bytes
    logo:         bytes  # logo.darc.lz — required by AGB_FIRM launcher
    romfs:        bytes
    config_block: bytes  # 0x324 bytes — color LUT and save performance config

def load_bundled_template() -> Template:
    """Load the template files bundled with vcoven."""
    if not TEMPLATE_DIR.exists():
        raise VcovenError(
            f"Bundled template not found at {TEMPLATE_DIR}. "
            f"This is a packaging bug — please report it."
        )
    return Template(
        ncch_header  = (TEMPLATE_DIR / "ncchheader.bin").read_bytes(),
        exheader     = (TEMPLATE_DIR / "exheader.bin").read_bytes(),
        icon         = (TEMPLATE_DIR / "icon.icn").read_bytes(),
        logo         = (TEMPLATE_DIR / "logo.darc.lz").read_bytes(),
        romfs        = (TEMPLATE_DIR / "romfs.bin").read_bytes(),
        config_block = (TEMPLATE_DIR / "config_block.bin").read_bytes(),
    )

def extract_donor(donor_cia: Path) -> None:
    """Extract a donor CIA into DONOR_CACHE for users who want to override
    the bundled template (e.g., to use their own GBA VC dump)."""
    if not donor_cia.exists():
        raise VcovenError(f"Donor file not found: {donor_cia}")

    log.info("Extracting donor: %s", donor_cia)
    if DONOR_CACHE.exists():
        shutil.rmtree(DONOR_CACHE)
    DONOR_CACHE.mkdir(parents=True)

    ctrtool = find_tool("ctrtool")
    run_cmd([ctrtool, "--contents=" + str(DONOR_CACHE / "file"), str(donor_cia)],
            "ctrtool: extract cia")

    candidates = sorted(DONOR_CACHE.glob("file.*"), key=lambda p: p.stat().st_size, reverse=True)
    if not candidates:
        raise VcovenError("ctrtool produced no NCCH files. Is the donor a valid GBA VC CIA?")
    main_ncch = candidates[0]

    threedstool = find_tool("3dstool")
    cxi_dir = DONOR_CACHE / "cxi"
    cxi_dir.mkdir()
    run_cmd([threedstool, "-xtf", "cxi", str(main_ncch),
             "--header", str(cxi_dir / "ncchheader.bin"),
             "--exh",    str(cxi_dir / "exheader.bin"),
             "--exefs",  str(cxi_dir / "exefs.bin"),
             "--romfs",  str(cxi_dir / "romfs.bin")],
            "3dstool: extract cxi")

    exefs_dir = cxi_dir / "exefs"
    exefs_dir.mkdir()
    run_cmd([threedstool, "-xtf", "exefs", str(cxi_dir / "exefs.bin"),
             "--header", str(cxi_dir / "exefsheader.bin"),
             "--exefs-dir", str(exefs_dir)],
            "3dstool: extract exefs")

    code = (exefs_dir / "code.bin").read_bytes()
    if b".CAA" not in code:
        raise VcovenError(
            "Donor doesn't look like a GBA VC title — no .CAA footer in code.bin. "
            "vcoven needs a Game Boy Advance Virtual Console donor (Mario Advance, "
            "Kirby, Metroid, F-Zero, etc.), not GBC/NES/SNES VC."
        )

    log.info("Donor extracted to %s", DONOR_CACHE)

def load_user_donor() -> Template:
    """Load template fields from a previously-extracted user donor."""
    cxi = DONOR_CACHE / "cxi"
    if not cxi.exists():
        raise VcovenError(
            f"No donor cached. Run `{PROG_NAME} setup <donor.cia>` first, "
            f"or omit --use-donor to use the bundled template."
        )

    code = (cxi / "exefs" / "code.bin").read_bytes()
    caa_idx = code.rfind(b".CAA")
    if caa_idx < 0:
        raise VcovenError("Donor's code.bin has no .CAA footer (corrupt cache?)")
    section_offset = int.from_bytes(code[caa_idx + 8 : caa_idx + 12], "little")
    rom_size = int.from_bytes(code[section_offset + 8 : section_offset + 12], "little")
    config_block = code[rom_size : rom_size + 0x324]

    return Template(
        ncch_header  = (cxi / "ncchheader.bin").read_bytes(),
        exheader     = (cxi / "exheader.bin").read_bytes(),
        icon         = (cxi / "exefs" / "icon.icn").read_bytes(),
        logo         = (cxi / "exefs" / "logo.darc.lz").read_bytes(),
        romfs        = (cxi / "romfs.bin").read_bytes(),
        config_block = config_block,
    )

# ─── Build pipeline ───────────────────────────────────────────────────────────

@dataclass
class BuildSpec:
    rom_path:      Path
    output_path:   Path
    title_id:      int
    product_code:  str
    short_title:   str
    long_title:    str
    publisher:     str
    icon_image:    Path  # Square image; auto-cropped + resized to 24×24 / 48×48
    banner_image:  Path  # Any aspect; letterboxed to 256×128
    save_override: Optional[int] = None

def build_inject(spec: BuildSpec, template: Template) -> None:
    log.info("Building %s", spec.output_path.name)
    log.info("  ROM:          %s", spec.rom_path)
    log.info("  Title ID:     %016x", spec.title_id)
    log.info("  Product code: %s", spec.product_code)

    if not spec.rom_path.exists():
        raise VcovenError(f"ROM not found: {spec.rom_path}")
    rom_bytes = spec.rom_path.read_bytes()
    log.info("  ROM size:     %d bytes (%d MB)", len(rom_bytes), len(rom_bytes) // 1024 // 1024)

    code, save_type = build_code_bin(rom_bytes, template.config_block, spec.save_override)
    log.info("  Save type:    0x%02x (%s)", save_type, SAVE_NAMES.get(save_type, "unknown"))

    # Stage everything in a fresh work dir
    work = WORK_ROOT / spec.output_path.stem
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)

    (work / "romfs.bin").write_bytes(template.romfs)
    (work / "ncchheader.bin").write_bytes(
        patch_ncch_header(template.ncch_header, spec.title_id, spec.product_code)
    )
    (work / "exheader.bin").write_bytes(
        patch_exheader(template.exheader, spec.title_id, spec.product_code)
    )

    # Patch SMDH icon: titles + image data
    if not spec.icon_image.exists():
        raise VcovenError(f"Icon image not found: {spec.icon_image}")
    if not spec.banner_image.exists():
        raise VcovenError(f"Banner image not found: {spec.banner_image}")

    icon_data = patch_smdh_titles(template.icon,
                                   spec.short_title, spec.long_title, spec.publisher)
    icon_big   = load_square_icon(spec.icon_image, 48)
    icon_small = load_square_icon(spec.icon_image, 24)
    icon_data = patch_smdh_icons(icon_data,
                                  image_to_swizzled_rgb565(icon_big),
                                  image_to_swizzled_rgb565(icon_small))

    # Build a fresh banner.bnr from the user's image
    banner_png = work / "banner.png"
    banner_wav = work / "banner.wav"
    banner_bnr = work / "banner.bnr"
    load_banner_image(spec.banner_image).save(banner_png)
    make_silent_wav(banner_wav)
    bannertool = (
        find_tool("bannertool_bin")
        if (TOOLS_DIR / "bannertool_bin").exists()
        else find_tool("bannertool")
    )
    run_cmd([bannertool, "makebanner",
             "-i", str(banner_png), "-a", str(banner_wav), "-o", str(banner_bnr)],
            "bannertool: makebanner")

    # Pack ExeFS in pure Python.
    # Order MATTERS: code, banner, icon, logo (matches official VC layout).
    # logo.darc.lz is required — without it the AGB_FIRM launcher refuses
    # to boot the title.
    exefs_data = pack_exefs({
        ".code":  code,
        "banner": banner_bnr.read_bytes(),
        "icon":   icon_data,
        "logo":   template.logo,
    })
    (work / "exefs.bin").write_bytes(exefs_data)

    # Repack CXI — --not-encrypt is mandatory (see Bug 2 in README)
    threedstool = find_tool("3dstool")
    cxi_path = work / "new.cxi"
    run_cmd([threedstool, "-ctf", "cxi", str(cxi_path),
             "--header", str(work / "ncchheader.bin"),
             "--exh",    str(work / "exheader.bin"),
             "--exefs",  str(work / "exefs.bin"),
             "--romfs",  str(work / "romfs.bin"),
             "--not-encrypt"],
            "3dstool: pack cxi")

    fix_ncch_hashes(cxi_path)

    spec.output_path.parent.mkdir(parents=True, exist_ok=True)
    makerom = find_tool("makerom")
    run_cmd([makerom, "-f", "cia", "-o", str(spec.output_path),
             "-content", f"{cxi_path}:0:0",
             "-ignoresign"],
            "makerom: build cia")

    log.info("  ✓ Built: %s (%d KB)", spec.output_path,
             spec.output_path.stat().st_size // 1024)

# ─── CLI ──────────────────────────────────────────────────────────────────────

def parse_title_id(s: str) -> int:
    """Parse a title ID — 16 hex chars, optionally with leading 0x."""
    s = s.strip().lower()
    if s.startswith("0x"):
        s = s[2:]
    if len(s) != 16:
        raise argparse.ArgumentTypeError(
            f"Title ID must be 16 hex digits (got '{s}', {len(s)} chars)"
        )
    try:
        return int(s, 16)
    except ValueError as e:
        raise argparse.ArgumentTypeError(f"Invalid title ID: {e}")

SAVE_TYPE_NAMES = {
    "auto":      None,
    "none":      SAVE_NONE,
    "eeprom8":   SAVE_EEPROM_8,
    "eeprom64":  SAVE_EEPROM_64,
    "flash512":  SAVE_FLASH_512,
    "flash1m":   SAVE_FLASH_1M,
    "sram":      SAVE_SRAM_256,
}

def cmd_setup(args: argparse.Namespace) -> int:
    """Optional: extract a user-provided donor CIA. Most users don't need
    this — vcoven ships with a bundled template by default."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    extract_donor(Path(args.donor_cia).expanduser())
    log.info(
        "Setup complete. Use `--use-donor` to build with this donor "
        "instead of the bundled template."
    )
    return 0

def get_template(use_donor: bool) -> Template:
    """Resolve which template to use based on --use-donor flag."""
    if use_donor:
        return load_user_donor()
    return load_bundled_template()

def cmd_build(args: argparse.Namespace) -> int:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    WORK_ROOT.mkdir(parents=True, exist_ok=True)

    template = get_template(args.use_donor)
    spec = BuildSpec(
        rom_path     = Path(args.rom).expanduser(),
        output_path  = (Path(args.output).expanduser() if args.output
                        else Path(args.rom).expanduser().with_suffix(".cia")),
        title_id     = args.title_id,
        product_code = args.product_code,
        short_title  = args.title,
        long_title   = args.long_title or args.title,
        publisher    = args.publisher,
        icon_image   = Path(args.icon).expanduser(),
        banner_image = Path(args.banner).expanduser(),
        save_override = SAVE_TYPE_NAMES[args.save_type],
    )
    build_inject(spec, template)
    return 0

def cmd_batch(args: argparse.Namespace) -> int:
    try:
        import tomllib
    except ModuleNotFoundError:
        import tomli as tomllib  # type: ignore

    config_path = Path(args.config).expanduser()
    if not config_path.exists():
        raise VcovenError(f"Config file not found: {config_path}")

    config = tomllib.loads(config_path.read_text())
    games = config.get("game", [])
    if not games:
        raise VcovenError("Config has no [[game]] entries")

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    WORK_ROOT.mkdir(parents=True, exist_ok=True)
    template = get_template(args.use_donor)

    base_dir = config_path.parent
    raw_out = config.get("output_dir", ".")
    output_dir = Path(raw_out).expanduser()
    if not output_dir.is_absolute():
        output_dir = (base_dir / raw_out).resolve()

    failures = []
    for entry in games:
        try:
            rom_path = (base_dir / entry["rom"]).resolve()
            spec = BuildSpec(
                rom_path     = rom_path,
                output_path  = (output_dir / f"{entry['name']}.cia").resolve(),
                title_id     = parse_title_id(entry["title_id"]),
                product_code = entry["product_code"],
                short_title  = entry["title"],
                long_title   = entry.get("long_title", entry["title"]),
                publisher    = entry.get("publisher", "Unknown"),
                icon_image   = (base_dir / entry["icon"]).resolve(),
                banner_image = (base_dir / entry["banner"]).resolve(),
                save_override = SAVE_TYPE_NAMES[entry.get("save_type", "auto")],
            )
            build_inject(spec, template)
        except Exception as e:
            log.error("Failed to build %s: %s", entry.get("name", "?"), e)
            failures.append(entry.get("name", "?"))

    if failures:
        raise VcovenError(f"{len(failures)} build(s) failed: {', '.join(failures)}")
    return 0

def cmd_info(args: argparse.Namespace) -> int:
    print(f"vcoven data dir:  {DATA_DIR}")
    cache_state = " (exists)" if DONOR_CACHE.exists() else " (empty — run setup)"
    print(f"donor cache:      {DONOR_CACHE}{cache_state}")
    print(f"work dir:         {WORK_ROOT}")
    print()
    print("Tools:")
    for name in ("makerom", "ctrtool", "3dstool"):
        try:
            print(f"  {name:15} {find_tool(name)}")
        except VcovenError:
            print(f"  {name:15} MISSING")
    bannertool_found = False
    for name in ("bannertool_bin", "bannertool"):
        try:
            path = find_tool(name)
            print(f"  {'bannertool':15} {path}")
            bannertool_found = True
            break
        except VcovenError:
            continue
    if not bannertool_found:
        print(f"  {'bannertool':15} MISSING")
    return 0

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog=PROG_NAME,
        description="Bake GBA Virtual Console CIA injects for the Nintendo 3DS.",
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose logging")
    sub = parser.add_subparsers(dest="command", required=True)

    p_setup = sub.add_parser("setup", help="Extract a donor CIA (run once)")
    p_setup.add_argument("donor_cia", help="Path to a GBA VC donor .cia file")
    p_setup.set_defaults(func=cmd_setup)

    p_build = sub.add_parser("build", help="Build a single inject from a ROM")
    p_build.add_argument("rom", help="Path to a .gba ROM")
    p_build.add_argument("-o", "--output", help="Output .cia path (defaults to <rom>.cia)")
    p_build.add_argument("-t", "--title", required=True,
                         help="Display title shown on the home menu (e.g., 'My GBA Game')")
    p_build.add_argument("--long-title", help="Long description (defaults to --title)")
    p_build.add_argument("-p", "--publisher", default="Homebrew", help="Publisher name")
    p_build.add_argument("--title-id", type=parse_title_id, required=True,
                         help="16-hex-digit title ID, e.g. 0004000000F00200")
    p_build.add_argument("--product-code", default="CTR-N-HMBW",
                         help="Product code, max 16 chars (e.g. CTR-N-EMER)")
    p_build.add_argument("--icon", required=True,
                         help="Path to a square-ish icon image (PNG/JPG). "
                              "Auto-cropped and resized to 24×24 and 48×48.")
    p_build.add_argument("--banner", required=True,
                         help="Path to a banner image (PNG/JPG). "
                              "Auto-letterboxed to 256×128 for the top-screen banner.")
    p_build.add_argument("--save-type", choices=list(SAVE_TYPE_NAMES.keys()), default="auto",
                         help="Force a save type (default: auto-detect from ROM)")
    p_build.add_argument("--use-donor", action="store_true",
                         help="Use the user-provided donor (run `setup` first) "
                              "instead of the bundled template")
    p_build.set_defaults(func=cmd_build)

    p_batch = sub.add_parser("batch", help="Build multiple injects from a TOML config")
    p_batch.add_argument("config", help="TOML config file")
    p_batch.add_argument("--use-donor", action="store_true",
                         help="Use the user-provided donor (run `setup` first) "
                              "instead of the bundled template")
    p_batch.set_defaults(func=cmd_batch)

    p_info = sub.add_parser("info", help="Show paths and tool versions")
    p_info.set_defaults(func=cmd_info)

    return parser

def main(argv: Optional[list[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    configure_logging(args.verbose)
    try:
        return args.func(args)
    except VcovenError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        return 130

if __name__ == "__main__":
    sys.exit(main())
