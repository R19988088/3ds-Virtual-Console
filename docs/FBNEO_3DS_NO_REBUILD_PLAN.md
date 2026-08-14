# FBNeo 3DS 一次编译交付分支

## 当前事实

- Actions run `31774399878` 已完成 1102/1102 对象编译。
- 该 run 的 artifact 只有 `objects.txt`、`files.txt`、`status.txt` 和日志，没有 `runtime.a`、对象文件或 ELF；runner 已销毁，现有 run 不含可下载二进制。
- 本机没有 devkitARM，因此 `runtime.a` 不能在本地重新链接成 launcher ELF。
- 本机已有 `makerom`、`3dstool`、`bannertool`，可在拿到最终 ELF 后完成本地 CIA 容器和资源处理。
- RetroArch CIA 仅作为独立运行基准，不进入当前 Vcoven 内置核心链路。

## 唯一云端步骤

本轮允许一次受控的 Actions 构建，目的不是重复排查，而是把已经验证过的 1102 对象构建直接转成可下载交付物。

手动触发 `.github/workflows/experiment-fbneo-full-objects.yml`，设置 `FBNEO_DELIVER=1`，一次完成：

1. 编译 1102 个对象。
2. 生成 `runtime.a`。
3. 链接 `fbneo_3ds.elf`。
4. 上传 `runtime.a`、`fbneo_3ds.elf`、`SOURCE.txt`、`SHA256SUMS`。

这次交付成功后，后续只下载 artifact，不再触发核心编译。

## 本地步骤

1. 下载 embedded-core artifact。
2. 核对 `SHA256SUMS`、ELF header、archive member count 和 `Cyclone.o`。
3. 将 `fbneo_3ds.elf` 放入 `Sources/VcovenApp/Resources/arcade/`。
4. 本地完成 ROMFS、图标、banner、CIA 生成和 macOS 集成。

## 触发边界

- `build-fbneo.yml` 仅保留 `workflow_dispatch`，提交不会触发长跑。
- embedded-core workflow 只触发一次；失败时保留完整 artifact，不自动重试。
- 仅有对象清单或编译日志，不算核心交付物，也不作为下一阶段输入。

## 交付物

```text
runtime.a
fbneo_3ds.elf
SOURCE.txt
SHA256SUMS
```
