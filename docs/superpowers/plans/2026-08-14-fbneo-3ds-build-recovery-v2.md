# FBNeo 3DS 构建恢复计划 v2

> **执行边界：** 本轮只按短实验推进。每个实验都必须产出可下载日志和明确退出码；前一个实验没有结论时，禁止启动全量 1102 对象构建、macOS app 构建或真机验收。

## 目标与停止条件

目标是确认 `Cyclone.S` 在“完整构建目录 + Make 规则”中的退出原因，再恢复 FBNeo archive 和 launcher。当前不追求发布 artifact；在对象边界解释清楚前，所有上层工作暂停。

连续两次短实验只产生空 stderr 或仍未能区分 Make/工具链边界时，停止新增修复，保留日志并提交调查报告。只有得到可复现的具体退出原因，才进入实现分支。

## 已确认事实

- 固定 FBNeo：`2fcb2628fbfd529806e75f3559a9d82758c8a5cc`。
- run `31770144069`（提交 `f63ea9a`）运行约 19 分 45 秒，在全量 C/C++ 对象完成后，于 `arm-none-eabi-gcc ... -c ../../cpu/cyclone/Cyclone.S -o ../../cpu/cyclone/Cyclone.o` 后退出 1；日志没有 assembler stderr，也没有 archive/ELF。
- 同一 run 的诊断 artifact 已验证：`gcc_driver=passed`、`preprocessor=0`、`direct_as=0`，三个 stderr 文件为空。由此排除“GNU assembler 直接拒绝该源文件”这一解释。
- run `31771289419`（提交 `d884fff`）加入了全量构建目录的 Cyclone preflight 和失败日志上传；该 run 已主动取消，未形成 preflight 或全量对象结论。
- 本地 macOS 没有 devkitARM；本地已通过 shell/契约/YAML 检查和 Swift 9 项测试。真实 ARM 证据只来自 Actions。
- 当前远端 `main` 为 `1576135`。`safe.directory` 修复已在两个 target-only run 中验证；trace run `31772723755`、object-boundary run `31773213035` 和 full-object run `31774399878` 均通过，不再追加 Cyclone 猜测性修复。

## v2 架构

将构建拆成四个互斥阶段：

1. `target-only`：生成头文件后只编译 `Cyclone.o`，最长 5 分钟。
2. `target-trace`：在同一构建目录对该目标分别运行 Make recipe、保存的 shell command、`gcc -###`/预处理器/直接 `as`，比较输出对象、环境和资源状态。
3. `object-boundary`：只有前两阶段都通过时，构建一个可控的小对象集合；成功后才允许一次全量对象构建。
4. `archive-link`：对象完整后才生成 `runtime.a`、launcher ELF 和 artifact。

每个阶段使用独立 workflow 或明确的 `workflow_dispatch` 输入，artifact 名称包含 run ID。失败阶段的日志必须先上传，再结束 job。

## 文件变更

**创建：**

- `core-runtime/scripts/diagnose-cyclone-target.sh`
- `core-runtime/tests/verify-cyclone-target-contract.sh`
- `.github/workflows/diagnose-fbneo-target.yml`
- `docs/FBNEO_3DS_SHORT_EXPERIMENTS.md`（实验完成后记录实际输出）

**修改：**

- `core-runtime/scripts/build-fbneo.sh`：保留当前失败日志上传；全量构建前只调用 target-only，不在脚本中加入未经验证的 fallback。
- `.github/workflows/build-fbneo.yml`：保留诊断 artifact；将全量构建步骤设置为依赖短实验结果。
- `core-runtime/tests/verify-fbneo-contract.sh`：锁定短实验 workflow 和 artifact 命名。

## 任务 1：建立分钟级 target-only 实验

- [x] **步骤 1：先写契约。** `verify-cyclone-target-contract.sh` 检查固定 commit、`Cyclone.S`、输出目录、`command.txt`、`make.stdout`、`make.stderr`、`driver.stderr`、`as.stderr`、`resource.txt` 和 `status.txt`。
- [x] **步骤 2：实现隔离脚本。** `diagnose-cyclone-target.sh` 复制固定源码到新 build 目录，只执行 `generate-files` 和：
  ```bash
  make -C "$BUILD/src/burner/libretro" \
    -f Makefile -f core-runtime/scripts/fbneo-no-archive.mk \
    --output-sync=target -B -j1 \
    platform=ctr SUBSET=all REGEN_HEADERS=1 INCLUDE_CHD_SUPPORT=0 SPLIT_UP_LINK=1 \
    ../../cpu/cyclone/Cyclone.o
  ```
  记录 `set -x`、`ulimit -a`、`/proc/meminfo`、`df -h`、工具版本和返回码；不执行其它对象。
- [x] **步骤 3：比较同一目录的三条路径。** 从 Make dry-run 提取命令；在同一 build 目录用 shell 直接执行该命令；再预处理并调用同一 `arm-none-eabi-as`。记录三个对象的大小、mtime 和 SHA-256。
- [x] **步骤 4：Actions 短跑。** `gh workflow run diagnose-fbneo-target.yml --ref main`，最长等待 5 分钟；下载 `cyclone-target-<run_id>`，先读取 `status.txt` 再决定下一步。

**判定：**

- Make、shell、direct-as 都为 0：Cyclone 目标自身通过，进入任务 2。
- Make 非 0、shell/direct-as 为 0：问题在 Make 规则、工作目录、依赖文件或资源状态，进入任务 3；禁止全量重跑。
- direct-as 非 0：只分析预处理输出和 GNU assembler stderr，修改生成器/参数前保留原始输入哈希。

## 任务 2：固定工具链和资源证据

- [x] **步骤 1：记录容器身份。** workflow 输出容器 image 字符串、`gcc/as` 完整版本、内核/架构、`ulimit -a`、`df -h` 和 `/proc/meminfo`；不把当前失败的 `latest` digest 直接当成功 pin。
- [x] **步骤 2：重复 target-only 两次。** 两次使用不同临时 build 目录，结果、对象哈希和退出码必须一致；任一次超时都保留 artifact。
- [x] **步骤 3：记录 Make 追踪。** run `31772723755` 增加 `--trace` 和 `-d`；`Cyclone.o` 只命中 `Cyclone.S`，`.d` 只依赖源文件，无二次 recipe 或隐藏目录操作。
- [x] **步骤 4：提交实验结果。** 更新 `docs/FBNEO_3DS_SHORT_EXPERIMENTS.md`，写入 run ID、命令、退出码、对象哈希和资源快照；此文档提交前不启动全量构建。

## 任务 3：验证对象边界

- [x] **步骤 1：固定对象集合。** 新增 `core-runtime/scripts/experiment-fbneo-object-boundary.sh`，只编译 10 个明确 C/C++/CPU 对象和 `Cyclone.o`。
- [x] **步骤 2：固定输出证据。** 脚本记录 `targets.txt`、Make stdout/stderr、每个对象大小和 SHA-256、Cyclone ELF header 及 `status.txt`。
- [x] **步骤 3：运行短实验。** run `31773213035` 得到 `make_objects=0`、`missing_objects=0`，11 个对象均有摘要。
- [x] **步骤 4：失败停止。** 本实验未失败；后续全量阶段仍保持失败即上传并停止的边界。

## 任务 4：一次性恢复全量对象（下一步）

- [x] **步骤 1：全量前置条件。** target-only、trace、object-boundary 的 artifact、对象哈希和实验文档均存在；object-boundary run `31773213035` 通过。
- [x] **步骤 2：运行一次全量对象实验。** run `31774399878` 使用 `object_boundary_run=31773213035`，`object_count=1102`、`make_objects=0`、`missing_objects=0`；对象 manifest 为 1102/1102，未生成 archive 或 launcher。
- [ ] **步骤 3：验证 archive。** 只在对象全部存在时用 `arm-none-eabi-ar` 生成 `runtime.a`，检查对象数量、`Cyclone.o`、`libretro.o`、`retro_common.o` 和关键 `retro_*` 符号。
- [ ] **步骤 3a：先固定失败证据。** 旧 run `31774385389` 在 full-object 之后失败但没有 post-object artifact；`build-fbneo.sh` 已增加失败 trap 及 archive/launcher 分阶段日志，下一次运行先读取这些日志再判断修复点。
- [ ] **步骤 3b：手动触发边界。** `build-fbneo.yml` 已移除 push 触发，只能在 archive/link 前置条件满足后通过 `workflow_dispatch` 运行，避免计划外重复全量构建。
- [ ] **步骤 4：记录成功工具链。** 只有完整对象和 archive 成功后才记录 image digest 为候选 pin；此前所有 digest 都是实验身份。

## 任务 5：链接与上层集成

- [ ] **步骤 1：链接 ELF。** 检查 ELF32、ARM、little-endian、EABI 和小于 16 MiB；生成 `SOURCE.txt`、`SHA256SUMS`。
- [ ] **步骤 2：下载验证。** macOS workflow 只消费成功 run 的 `fbneo-3ds` artifact，核对来源 commit、ELF/runtime 哈希和清单。
- [ ] **步骤 3：运行已有 arcade CIA 测试。** 当前本地 9 项 Swift 测试保持通过；新增 artifact 缺失和哈希错误测试后再构建 macOS app。
- [ ] **步骤 4：真机单独排期。** Old/New 3DS 的 ROM/BIOS、视频、音频、输入、退出和 SRAM 只在 ELF/artifact 成功后执行。

## 明确禁止的重复路径

- [ ] 未取得 object-boundary 的 11 个对象证据前，不运行 `fbneo_objects`。
- [ ] 不因空 stderr 直接改写 `Cyclone.S`，不切换 Musashi，不扩大参数集合。
- [ ] 不把 Swift CIA fixture 或静态契约测试当成 ARM 运行时证据。
- [ ] 不在没有成功 artifact 的情况下触发 macOS app workflow。

## 下一次执行命令

```bash
git status --short --branch
git log -2 --oneline
gh workflow run diagnose-fbneo-target.yml --ref main
gh run list --workflow diagnose-fbneo-target.yml --branch main --limit 1 \
  --json databaseId,status,url
gh workflow run experiment-fbneo-object-boundary.yml --ref main
gh run list --workflow experiment-fbneo-object-boundary.yml --branch main --limit 1 \
  --json databaseId,status,url
gh workflow run experiment-fbneo-full-objects.yml --ref main \
  -f object_boundary_run=31773213035
gh run list --workflow experiment-fbneo-full-objects.yml --branch main --limit 1 \
  --json databaseId,status,url
```

下一次只允许运行一次全量对象构建；保持 `JOBS=1`，失败时上传对象日志并停止，不自动重试，不生成 archive 或 launcher。
