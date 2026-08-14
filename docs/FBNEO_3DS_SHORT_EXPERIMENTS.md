# FBNeo 3DS 短实验记录

## 固定输入

- FBNeo commit：`2fcb2628fbfd529806e75f3559a9d82758c8a5cc`
- 工具链镜像：`devkitpro/devkitarm:latest`
- 目标：`../../cpu/cyclone/Cyclone.o`
- 诊断 workflow：`.github/workflows/diagnose-fbneo-target.yml`
- 实验脚本：`core-runtime/scripts/diagnose-cyclone-target.sh`
- 对象边界脚本：`core-runtime/scripts/experiment-fbneo-object-boundary.sh`

## 实验 1：修复前

- Actions run：`31772096094`
- 提交：`0029d3b`
- 结果：workflow success，目标实验收集完成。
- `make_target=0`
- `gcc_driver=0`
- `preprocessor=0`
- `direct_as=0`
- `make.stderr` 包含：`fatal: detected dubious ownership in repository at '/__w/3ds-Virtual-Console/3ds-Virtual-Console'`
- `Cyclone.o`：506252 bytes，SHA-256 `5a680f5d1750c1f57465e40f25b7f30591edd5f8ab81a108261469b255427cc7`
- shell driver 与 direct `as` 生成对象的哈希一致。

该结果把问题边界收敛到构建目录中的 Git ownership 状态；汇编器本身未报错。

## 实验 2：补齐 safe.directory

- 修复提交：`96d70b8`
- Actions run：`31772300700`
- 结果：workflow success，四个退出码均为 0。
- `make.stderr` 仅保留 `set -x` 命令追踪，无 Git fatal 或 assembler 错误。
- Make、shell driver、direct `as` 对象均为 506252 bytes，SHA-256：`5a680f5d1750c1f57465e40f25b7f30591edd5f8ab81a108261469b255427cc7`
- 预处理输出：1864284 bytes，SHA-256 `9b10b8930b63bf5ac2389bca8678e9c63a00c73027c7ea674e7cf1cdd45a3355`
- `readelf -h`：ELF32、ARM、little-endian、REL、Version5 EABI。

## 实验 3：同提交复跑

- Actions run：`31772424289`
- 提交：`96d70b8`
- 结果：workflow success，四个退出码均为 0。
- 对象哈希与实验 2 完全一致。
- `make.stderr` 390 bytes，内容为 shell trace；`driver.stderr` 和 `as.stderr` 均为 0 bytes。

## 当前决策

1. `Cyclone.S` 语法和 GNU assembler 路径已有两次独立通过证据。
2. Git ownership 修复已在 target-only 路径重复验证。
3. 当前只允许进入 `object-boundary` 小对象实验；尚未满足全量 1102 对象构建前置条件。
4. 上层 archive、launcher、macOS app 和真机路径继续保持暂停。

## 实验 4：trace 复核

- Actions run：`31772723755`
- 提交：`a77d2ce`
- 结果：success，固定 FBNeo commit 一致，`make_trace=0`。
- `status.txt`：`make_target=0`、`gcc_driver=0`、`preprocessor=0`、`direct_as=0`。
- `trace.stdout` 在目标更新阶段只执行 `Cyclone.S -> Cyclone.o` 的隐式规则；`.d` 依赖为 `Cyclone.S`，没有二次 recipe、目录创建或隐藏错误。
- Make 产物与保存的 shell command、direct `as` 产物均为 506252 bytes，SHA-256 均为 `5a680f5d1750c1f57465e40f25b7f30591edd5f8ab81a108261469b255427cc7`。
- `readelf` 确认 ELF32、ARM、little-endian、REL、Version5 EABI。

该实验确认修复后的 target-only 路径已稳定，下一步是用固定的 10 个 C/C++/CPU 对象加 `Cyclone.o` 验证对象边界，不生成 archive，不触发 launcher。

## 实验 5：object-boundary（待运行）

workflow：`.github/workflows/experiment-fbneo-object-boundary.yml`

固定对象为：

```text
../../burner/libretro/libretro.o
../../burner/libretro/retro_common.o
../../burner/libretro/retro_input.o
../../burner/libretro/retro_memory.o
../../burner/libretro/retro_string.o
../../burn/burn.o
../../burn/burn_memory.o
../../burn/snd/ay8910.o
../../cpu/m68k/m68kcpu.o
../../cpu/z80/z80.o
../../cpu/cyclone/Cyclone.o
```

判定要求：`make_objects=0`、`missing_objects=0`，并且 `files.txt` 中 11 个对象都有大小和 SHA-256。失败时只分析该 artifact，不进入全量对象构建。

## 复现实验

```bash
gh workflow run diagnose-fbneo-target.yml --ref main
gh run list --workflow diagnose-fbneo-target.yml --branch main --limit 1 \
  --json databaseId,status,url
gh run download RUN_ID --name cyclone-target-RUN_ID --dir /tmp/cyclone-target-RUN_ID
cat /tmp/cyclone-target-RUN_ID/status.txt

gh workflow run experiment-fbneo-object-boundary.yml --ref main
gh run list --workflow experiment-fbneo-object-boundary.yml --branch main --limit 1 \
  --json databaseId,status,url
```
