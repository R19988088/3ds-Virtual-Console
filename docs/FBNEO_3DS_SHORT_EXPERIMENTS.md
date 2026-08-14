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

## 实验 5：object-boundary

workflow：`.github/workflows/experiment-fbneo-object-boundary.yml`

- Actions run：`31773213035`
- 提交：`477c1a7`
- 结果：success；固定 commit 一致，`generate_files=passed`、`make_objects=0`、`missing_objects=0`。
- 11 个对象均有大小和 SHA-256；`Cyclone.o` 为 506252 bytes，SHA-256 仍为 `5a680f5d1750c1f57465e40f25b7f30591edd5f8ab81a108261469b255427cc7`。
- `Cyclone.o` 仍为 ELF32、ARM、little-endian、REL、Version5 EABI。
- `make.stderr` 只有完整命令追踪，没有 Git ownership、编译器或 assembler 错误。

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

判定要求已满足。下一阶段允许安排一次全量对象构建；失败时只保留全量对象 artifact，不自动重试、不进入 archive/link。

## 实验 6：full-object

workflow：`.github/workflows/experiment-fbneo-full-objects.yml`

该 workflow 接收实验 5 的成功 run ID `31773213035`，只执行 `fbneo_objects`，不调用 `arm-none-eabi-ar`、launcher 或 archive。

- Actions run：`31774399878`
- 提交：`9294184`
- 结果：success；`object_count=1102`、`make_objects=0`、`missing_objects=0`。
- `objects.txt` 和 `files.txt` 均为 1102 行，所有对象都有大小和 SHA-256。
- `Cyclone.o`：506252 bytes，SHA-256 `5a680f5d1750c1f57465e40f25b7f30591edd5f8ab81a108261469b255427cc7`。
- `make.stderr` 仅包含编译警告和命令输出，没有 fatal/error；本阶段没有生成 archive 或 launcher。

判定要求已满足。现在允许进入 archive/link 阶段；该阶段仍必须单独记录退出码和 ELF/archive 检查，失败时不进入 macOS app 或真机验收。

## 旧全量 workflow 复核

- 自动触发 run：`31774385389`（提交 `9294184`）失败，耗时约 19 分钟。
- 该 run 的 Cyclone diagnostic 通过，但旧 `build-fbneo.sh` 没有上传 post-object 失败日志；`fbneo-build-diagnostic` artifact 为空，无法区分 archive、launcher 或最终检查。
- 这不是新的 `Cyclone.S` 失败证据：full-object run `31774399878` 已独立生成 1102/1102 对象。
- 已补强 `build-fbneo.sh`：失败 trap 会复制全部输出，archive create/list 和 launcher 分别保存 stdout/stderr。下一次 archive/link 运行前必须使用这版脚本。
- 新 run `31775798061`（提交 `89bf1ce`）在 build step 运行约 15 分钟后被主动取消；取消不触发 shell `EXIT` trap，故没有新增 diagnostic 结论。
- 为避免计划外长跑，`.github/workflows/build-fbneo.yml` 已改为仅 `workflow_dispatch`；后续必须在 archive/link 前置条件满足后手动触发。

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
gh workflow run experiment-fbneo-full-objects.yml --ref main \
  -f object_boundary_run=31773213035
gh run list --workflow experiment-fbneo-full-objects.yml --branch main --limit 1 \
  --json databaseId,status,url
```
