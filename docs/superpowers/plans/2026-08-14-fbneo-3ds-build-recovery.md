# FBNeo 3DS 构建恢复实现计划

> 本文件已被 `2026-08-14-fbneo-3ds-build-recovery-v2.md` 替代。原计划曾把全量 1102 对象构建作为过早门槛，导致诊断周期过长；后续执行只采用 v2 的短实验顺序。

> **面向 AI 代理的工作者：** 必须使用 `superpowers:executing-plans` 或 `superpowers:subagent-driven-development` 逐任务执行。每项任务都要先完成验证命令，再进入下一项；不要把静态检查、交叉编译和真机验收合并成一个结论。

**目标：** 在固定 FBNeo 提交 `2fcb2628fbfd529806e75f3559a9d82758c8a5cc` 的前提下恢复 FBNeo 3DS 自托管核心构建，保留 `Cyclone` 68000 核心，生成可验证的 `runtime.a`、`fbneo_3ds.elf` 和 GitHub Actions artifact；再把该 artifact 接入 macOS app 的 arcade CIA 路线，并完成 SRAM、ROM/BIOS、视频、音频、输入和 Old/New 3DS 验收。

**架构：** GitHub Actions 使用固定的 devkitARM 容器构建；本地 macOS 只执行源码契约、脚本语法和 Swift 测试，除非用户补充可运行的 devkitARM 工具链。FBNeo 源码固定为独立 checkout，不把生成的源码或工具链提交到主仓库。构建按 `Cyclone.S` 单目标诊断、全量对象、archive、launcher、artifact、macOS 集成、真机验收分层，每层保留日志、哈希和失败产物。

**技术栈：** GNU `arm-none-eabi-gcc/as/ar/g++/strip/readelf`、devkitARM/libctru、GNU Make、GitHub Actions、Swift 6/Swift Testing、`gh` CLI、SHA-256。

---

## 现状与证据边界

- 主仓库：`/Users/ddd/Documents/ai/3DS_VC/work/3ds-Virtual-Console`，`main` 与 `origin/main` 均为 `d0388ea101495c85d95685a4a6cf9ec992fab24c`，工作树干净。
- 固定 FBNeo checkout：`/Users/ddd/Documents/ai/3DS_VC/work/3ds-Virtual-Console/work/FBNeo`，HEAD 为 `2fcb2628fbfd529806e75f3559a9d82758c8a5cc`。
- 失败总结：`/Users/ddd/Documents/Codex/2026-08-13/vedoot-vcoven-https-github-com-vedoot/work/vcoven/docs/FBNEO_3DS_BUILD_FAILURE.md`。
- 失败 run `31708938762` 与 `31710830158` 都在 `arm-none-eabi-gcc ... -c ../../cpu/cyclone/Cyclone.S ...` 后退出 1，没有 `Cyclone.o`、`runtime.a`、ELF 或 artifact；第二次已串行并启用 `--output-sync=target`。
- 失败容器当前是漂移的 `devkitpro/devkitarm:latest`，已观测 digest：`sha256:116afba8df8453961de2936ffab20dd441edf4d682856c1ec8b0e53d7ed0bbf5`。该 digest 只作为失败证据，不作为最终 pin。
- 本机没有 Docker/Podman、`arm-none-eabi-gcc` 或 `/opt/devkitpro/devkitARM`，因此本地证据范围仅到源码契约、脚本语法和 Swift 测试；真实 ARM 交叉编译安排在 GitHub Actions devkitARM 容器。
- 已通过的本地门：`core-runtime/tests/verify-fbneo-contract.sh`、两个构建脚本 `bash -n`、`git diff --check`、`swift test`（8 项，0 failures）。这些结果不证明 assembler、链接器或 3DS 运行时。
- Apple Clang 对 `Cyclone.S` 的旧式条件码助记符报错仅作辅助线索；修复选择必须依据同一 devkitARM 容器内 GNU driver 与 GNU assembler 的独立输出。

## 不变约束

- FBNeo commit、launcher 自托管路线、`platform=ctr`、`SUBSET=all`、`INCLUDE_CHD_SUPPORT=0` 和 `SPLIT_UP_LINK=1` 保持不变，除非某个诊断结果直接要求最小范围调整。
- 不把 Musashi 作为默认替代；只有 Cyclone 在固定工具链上有可重复、不可接受的汇编障碍，并通过性能/兼容矩阵后才启用明确的 fallback 分支。
- 不直接手工维护 1.8 MB 的生成 `Cyclone.S`；若需语法修复，修改生成器或以固定 patch 应用，并把生成结果哈希纳入检查。
- 每次成功构建必须记录源码 commit、容器 image digest、工具版本、对象数、archive member 数、ELF header、文件大小和 SHA-256。

## 文件范围

**将创建：**

- `core-runtime/scripts/diagnose-cyclone.sh`
- `core-runtime/tests/verify-cyclone-diagnostic-contract.sh`
- `core-runtime/tests/verify-fbneo-artifact.sh`
- `docs/FBNEO_3DS_BUILD_RECOVERY.md`（完成实施后记录真实结果，不在本计划阶段创建）

**将修改：**

- `.github/workflows/build-fbneo.yml`
- `core-runtime/scripts/build-fbneo.sh`
- `core-runtime/scripts/fbneo-no-archive.mk`
- `core-runtime/scripts/build-fbneo-launcher.sh`
- `core-runtime/launcher-3ds/fbneo_launcher.c`
- `Sources/VcovenApp/VcovenConverter.swift` 或其 arcade 路由测试所需的最小调用方
- `Tests/VcovenAppTests/*` 中现有测试文件
- `.github/workflows/build-macos-app.yml`

**不在本计划阶段修改：** FBNeo 上游源码、生成汇编大文件、无关核心、已有 GBA/SNES 路线和用户未请求的删除状态。

## 构建分支决策表

| 诊断结果 | 唯一实施动作 | 通过门 |
| --- | --- | --- |
| GCC driver 失败，预处理成功，直接 `arm-none-eabi-as` 成功 | 在 `fbneo-no-archive.mk` 为 `Cyclone.S` 增加专用规则，只传 assembler 所需 `-march/-mcpu/-mthumb-interwork` 等参数；保留 C/C++ 规则不变 | `Cyclone.o` 非空且 `readelf -h` 为 ARM relocatable |
| GCC driver 与直接 `as` 都失败，stderr 为真实语法/宏错误 | 定位对应生成器/模板；创建固定 patch，重新生成 `Cyclone.S`，记录前后行数和 SHA-256；加入该目标回归测试 | 同一容器内预处理、直接汇编和单目标重编译三次一致成功 |
| 单目标两条路径都成功，全量仍失败 | 检查对象路径、依赖 sidecar、磁盘/内存/进程状态和 `make -n` 展开；只调整 wrapper 的失败捕获/资源参数 | 1102 个对象全部生成，无异常退出码 |
| 只有 Cyclone 在该工具链不可行 | 建立显式 `USE_CYCLONE=0` Musashi fallback 分支；分别测量构建、ELF 体积、启动、帧率、ROM 兼容和 SRAM | 只有性能/兼容矩阵全部通过才允许发布 fallback artifact |

## 实施任务

### 任务 1：冻结复现输入并增加 Cyclone 单目标诊断

**文件：**

- 创建 `core-runtime/scripts/diagnose-cyclone.sh`
- 创建 `core-runtime/tests/verify-cyclone-diagnostic-contract.sh`

- [x] **步骤 1：写失败测试/契约。** 检查脚本拒绝错误 `FBNEO_COMMIT`，要求 `FBNEO_SOURCE`、`DEVKITARM`、输出目录存在，输出 `toolchain.txt`、`command.txt`、`driver.stderr`、`preprocessed.s`、`as.stderr`、`status.txt` 和 `files.txt`。
- [x] **步骤 2：先运行契约确认缺口。** 运行 `core-runtime/tests/verify-cyclone-diagnostic-contract.sh`；预期脚本尚不存在，测试失败。
- [x] **步骤 3：实现三段诊断。** 在固定源码目录执行：
  ```bash
  arm-none-eabi-gcc -v
  arm-none-eabi-gcc <Make 展开的完整参数> -c cpu/cyclone/Cyclone.S -o Cyclone.driver.o 2>driver.stderr
  arm-none-eabi-gcc <同一宏/架构参数> -E -x assembler-with-cpp cpu/cyclone/Cyclone.S -o preprocessed.s
  arm-none-eabi-as <仅 assembler 必要参数> preprocessed.s -o Cyclone.as.o 2>as.stderr
  ```
  每条命令用独立退出码记录，诊断收集逻辑使用独立状态处理而不由 `set -e` 提前终止；用 `tee` 保存 stdout/stderr，并记录源文件 SHA-256、容器 `/.dockerenv`、`gcc/as` 版本。
- [x] **步骤 4：验证。** 运行 `bash -n core-runtime/scripts/diagnose-cyclone.sh`、`core-runtime/tests/verify-cyclone-diagnostic-contract.sh` 和 `git diff --check`。预期错误命令仍产生完整诊断目录。
- [x] **步骤 5：提交。** `git add core-runtime/scripts/diagnose-cyclone.sh core-runtime/tests/verify-cyclone-diagnostic-contract.sh && git commit -m "build: capture Cyclone assembler diagnostics"`。

### 任务 2：让 Actions 在全量构建前发布可下载诊断

**文件：** `.github/workflows/build-fbneo.yml`

- [x] **步骤 1：固定 checkout 与身份输出。** 保持 FBNeo commit 校验；新增 `git rev-parse HEAD`、容器 image digest、`arm-none-eabi-* --version` 输出。
- [x] **步骤 2：新增诊断 job/step。** 在 FBNeo 全量对象之前调用 `diagnose-cyclone.sh`；诊断步骤允许命令失败但自身必须成功生成 `core-runtime/dist/cyclone-diagnostic`，随后用 `actions/upload-artifact@v4` 上传，`if: always()`，名称包含 `${{ github.run_id }}`。
- [x] **步骤 3：本地验证 YAML 与 shell。** 运行 `bash -n core-runtime/scripts/*.sh`、`core-runtime/tests/verify-fbneo-contract.sh`；用 `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build-fbneo.yml")'` 解析 YAML（若 Ruby YAML 解析器不支持表达式，则使用仓库已有 YAML lint 命令）。
- [ ] **步骤 4：触发并取证。** `gh workflow run build-fbneo.yml --ref main`；用 `gh run watch RUN_ID --exit-status`，再用 `gh run download RUN_ID --name cyclone-diagnostic-RUN_ID --dir /tmp/cyclone-RUN_ID`。把 driver/as 退出码和第一条真实 stderr 作为下一任务输入。
- [ ] **步骤 5：提交。** `git add .github/workflows/build-fbneo.yml && git commit -m "ci: publish Cyclone diagnostic artifact"`。

### 任务 3：按诊断结果实施唯一最小修复

**文件：** 依据任务 2 结果，优先 `core-runtime/scripts/fbneo-no-archive.mk`；仅在真实语法错误时修改上游生成器 patch 文件。

- [ ] **步骤 1：保存决策记录。** 在 PR/提交说明中引用诊断 artifact 的 run ID、两个退出码、完整错误类别和工具版本；不依据 Apple Clang 输出作结论。
- [ ] **步骤 2：driver 参数分支。** 若直接 `as` 成功，增加仅针对 `cpu/cyclone/Cyclone.S` 的 Make 规则，使用 `$(CC)` 预处理或显式 `$(AS)` 汇编，保持输出路径与 `OBJS` 一致；加入 `touch`/并行重复构建检查，防止隐式规则重新接管。
- [ ] **步骤 3：生成器分支。** 若 GNU `as` 也报语法错误，找到生成 `Cyclone.S` 的源模板/脚本，应用最小 patch；构建前固定生成，构建后检查 `sha256sum Cyclone.S`，禁止未审查的整文件替换。
- [ ] **步骤 4：回归单目标。** 在 devkitARM 容器中连续三次运行诊断，要求 `driver` 或 `as` 选定路径的退出码均为 0，`Cyclone.o` 非空，`arm-none-eabi-readelf -h Cyclone.o` 为 `ELF32/ARM relocatable`。
- [ ] **步骤 5：提交。** `git add core-runtime/scripts/fbneo-no-archive.mk <必要的生成器或 patch> core-runtime/tests && git commit -m "build: fix Cyclone object rule"`。

### 任务 4：恢复全量对象与 archive，并锁定成员完整性

**文件：** `core-runtime/scripts/build-fbneo.sh`、`core-runtime/scripts/fbneo-no-archive.mk`、`core-runtime/tests/verify-fbneo-artifact.sh`

- [ ] **步骤 1：增加对象级失败证据。** 让 wrapper 保存 `make` 完整日志、`OBJS` 展开列表、失败对象名、对象目录清单；保留默认 `JOBS=1`，只有基准测量通过才显式提高并行度。
- [ ] **步骤 2：运行全量对象构建。** 在固定容器执行：
  ```bash
  FBNEO_SOURCE="$PWD/work/FBNeo" FBNEO_OUTPUT="$PWD/core-runtime/dist/fbneo" \
    core-runtime/scripts/build-fbneo.sh
  ```
  预期 `fbneo_objects` 成功，`Cyclone.o` 和其余对象都非空。
- [ ] **步骤 3：验证 archive。** 检查 `runtime.a` 存在；`arm-none-eabi-ar t runtime.a | wc -l` 必须等于脚本展开的对象数（当前基线约 1102），并检查 `libretro.o`、`retro_common.o`、`Cyclone.o` 等关键成员与 `arm-none-eabi-nm -g` 的 `retro_run`、`retro_load_game` 符号。
- [ ] **步骤 4：运行契约。** `core-runtime/tests/verify-fbneo-artifact.sh core-runtime/dist/fbneo/runtime.a` 验证 commit、成员数、关键对象、非零大小和 SHA-256 输出。
- [ ] **步骤 5：提交。** `git add core-runtime/scripts/build-fbneo.sh core-runtime/scripts/fbneo-no-archive.mk core-runtime/tests/verify-fbneo-artifact.sh && git commit -m "build: verify complete FBNeo archive"`。

### 任务 5：链接并验证自托管 launcher ELF

**文件：** `core-runtime/scripts/build-fbneo-launcher.sh`、`.github/workflows/build-fbneo.yml`

- [ ] **步骤 1：链接。** 使用任务 4 的 `runtime.a` 调用现有 launcher 脚本，禁止跳过 `strip`、`readelf` 或 libctru 链接错误。
- [ ] **步骤 2：验证 ELF。** 对 `fbneo_3ds.elf` 执行：
  ```bash
  arm-none-eabi-readelf -h core-runtime/dist/fbneo/fbneo_3ds.elf
  arm-none-eabi-size core-runtime/dist/fbneo/fbneo_3ds.elf
  test "$(wc -c < core-runtime/dist/fbneo/fbneo_3ds.elf)" -lt $((16 * 1024 * 1024))
  sha256sum core-runtime/dist/fbneo/* > core-runtime/dist/fbneo/SHA256SUMS
  ```
  预期 `ELF32`、little-endian、`Machine: ARM`、`Version5 EABI`、非空且小于 16 MiB。
- [ ] **步骤 3：上传并下载验证。** Actions 使用 `if-no-files-found: error` 上传 `fbneo-3ds`；本地用 `gh run download` 下载后执行 `sha256sum -c SHA256SUMS`，并核对 `SOURCE.txt`。
- [ ] **步骤 4：提交。** `git add core-runtime/scripts/build-fbneo-launcher.sh .github/workflows/build-fbneo.yml && git commit -m "ci: publish verified FBNeo 3DS launcher"`。

### 任务 6：补齐 launcher 的 SRAM 加载/保存契约

**文件：** `core-runtime/launcher-3ds/fbneo_launcher.c`、`core-runtime/tests/verify-launcher-contract.sh`（创建）、相关 Swift/脚本测试

- [x] **步骤 1：写契约测试。** 检查 launcher 在 `retro_load_game` 前从 `sdmc:/vcoven/saves/<basename>.sav` 读取已有 `RETRO_MEMORY_SAVE_RAM`，退出时只在获得有效指针和大小时写回，并对缺失文件按首次运行处理。
- [x] **步骤 2：实现最小 helper。** 增加 basename、加载、保存三个可独立检查的静态函数；加载文件大小超过核心报告的 RAM 大小时截断，短文件只覆盖已有字节并将剩余区域清零；保存使用临时文件后 rename，避免中途断电留下半个存档。
- [x] **步骤 3：静态验证。** `bash core-runtime/tests/verify-launcher-contract.sh core-runtime/launcher-3ds/fbneo_launcher.c`、`git diff --check`；在 devkitARM 容器重新链接并确认 ELF 门不回退。
- [ ] **步骤 4：提交。** `git add core-runtime/launcher-3ds/fbneo_launcher.c core-runtime/tests/verify-launcher-contract.sh && git commit -m "fix: restore FBNeo save RAM on launch"`。

### 任务 7：增加 arcade CIA 路由的 Swift 端到端测试

**文件：** `Sources/VcovenApp/VcovenConverter.swift`、`Tests/VcovenAppTests/*`

- [x] **步骤 1：补失败测试。** 用临时目录中的固定 `fbneo_3ds.elf`、一个 arcade ZIP 和配置对象，验证 converter 选择 arcade CIA 配方、把 ZIP 原样放入 RomFS、保留 ELF、拒绝缺失 ELF，并验证错误包含具体路径/字段。
- [x] **步骤 2：运行确认失败。** `swift test --filter Arcade`；预期当前只有 ZIP 路由测试，缺少 arcade CIA 端到端覆盖。
- [x] **步骤 3：实现最小接线。** 复用现有 GBA/SNES packaging boundary；不新增第二个桌面下载协议。校验 `runtime.a`/ELF 的 SHA-256 和 `SOURCE.txt` 后再进入 CIA 配置，保持原有 ZIP 路径不变。
- [x] **步骤 4：验证。** `swift test`；检查生成 CIA 的 RomFS 文件表和 payload hash，测试无 arcade artifact 时明确失败。
- [ ] **步骤 5：提交。** `git add Sources/VcovenApp/VcovenConverter.swift Tests/VcovenAppTests && git commit -m "test: cover FBNeo arcade CIA route"`。

### 任务 8：固定 CI 依赖并串接 macOS app 构建

**文件：** `.github/workflows/build-fbneo.yml`、`.github/workflows/build-macos-app.yml`

- [ ] **步骤 1：固定成功容器。** 任务 5 成功后记录实际成功 digest，将 `devkitpro/devkitarm:latest` 改为该 digest；同时保留工具版本输出，后续更新必须产生新的诊断/构建证据。
- [ ] **步骤 2：限制 app 只能消费成功 artifact。** `build-macos-app.yml` 保持 `gh run list --status success`，加入 `SOURCE.txt`、`SHA256SUMS` 和 ELF 检查；手工输入 `fbneo_run_id` 时同样执行完整校验。
- [ ] **步骤 3：串行验证 workflow。** 先成功运行 `build-fbneo.yml`，再将其 run ID 传给 `gh workflow run build-macos-app.yml -f fbneo_run_id=RUN_ID`；下载 `vcoven-macOS-arm64` 并验证 `codesign --verify --deep --strict`。
- [ ] **步骤 4：提交。** `git add .github/workflows/build-fbneo.yml .github/workflows/build-macos-app.yml && git commit -m "ci: pin FBNeo toolchain and consume verified artifact"`。

### 任务 9：执行 3DS 真机验收并发布结果文档

**文件：** 创建 `docs/FBNEO_3DS_DEVICE_ACCEPTANCE.md`、更新 `docs/PLATFORM_SUPPORT.md`

- [ ] **步骤 1：准备固定测试矩阵。** 记录 Old 3DS/New 3DS、系统版本、CIA 安装方式、ROM-set 版本、父集/BIOS、SD 卡文件树和 artifact SHA-256。
- [ ] **步骤 2：冷启动与资源。** 验证空 `romfs:/content`、单 ROM、多个文件时的行为；确认 `sdmc:/vcoven/system`、`saves`、日志目录创建，错误写入 `fbneo.log`。
- [ ] **步骤 3：运行时。** 分别验证视频尺寸/旋转、稳定帧率、音频无持续 underrun、按键映射、Start+Select 退出、软复位和至少一款需要 BIOS 的街机 ROM。
- [ ] **步骤 4：SRAM。** 首次运行写入存档，退出并重新启动读取同一存档；模拟短文件、缺失文件和写入中断，确认不会破坏已有存档。
- [ ] **步骤 5：容量/性能。** 记录 ELF 大小、启动时间、内存峰值、Old/New 3DS 帧率与长时间运行结果；任何一项失败都保留 artifact 和日志，不宣称发布完成。
- [ ] **步骤 6：提交结果。** `git add docs/FBNEO_3DS_DEVICE_ACCEPTANCE.md docs/PLATFORM_SUPPORT.md && git commit -m "docs: record FBNeo 3DS acceptance matrix"`。

## 最终发布门

- [ ] 固定 commit 与成功 image digest 可复现。
- [ ] `Cyclone.o`、约 1102 个对象、`runtime.a` 成员/符号检查全部通过。
- [ ] ELF header、16 MiB 限制、`SHA256SUMS` 和 Actions artifact 下载检查全部通过。
- [ ] arcade CIA Swift 端到端测试通过，macOS app 使用同一已校验 artifact。
- [ ] SRAM 加载/保存、ROM/BIOS、视频、音频、输入、退出和 Old/New 3DS 矩阵均有真机记录。
- [ ] 只有以上证据齐全后，才在发布说明中标记 FBNeo 3DS 核心可用；静态测试通过或单次 CI 成功不替代真机验收。
