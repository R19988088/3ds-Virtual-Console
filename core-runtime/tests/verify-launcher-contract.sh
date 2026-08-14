#!/bin/sh
set -eu

SOURCE=${1:?usage: verify-launcher-contract.sh launcher.c}
test -f "$SOURCE"
grep -q 'static bool save_path_for_rom' "$SOURCE"
grep -q 'static void load_ram' "$SOURCE"
grep -q 'RETRO_MEMORY_SAVE_RAM' "$SOURCE"
grep -q 'fopen(save_path, "rb")' "$SOURCE"
grep -q 'fread(data, 1, size, file)' "$SOURCE"
grep -q 'memset(data, 0, size)' "$SOURCE"
grep -q '\.tmp' "$SOURCE"
grep -q 'rename(temp_path, save_path)' "$SOURCE"
grep -q 'load_ram(rom_path)' "$SOURCE"
grep -q 'save_ram(rom_path)' "$SOURCE"

printf '%s\n' 'FBNeo launcher SRAM contract passed.'
