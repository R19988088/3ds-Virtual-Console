# FBNeo 3DS 无重复编译执行分支

## 当前事实

- Actions run `31774399878` 已完成 1102/1102 对象编译。
- 该 run 的 artifact 只有 `objects.txt`、`files.txt`、`status.txt` 和日志，没有 `runtime.a`、对象文件或 ELF；runner 已销毁，无法从该 run 恢复二进制。
- 本机没有 devkitARM，因此 `runtime.a` 不能在本地重新链接成 launcher ELF。
- 本机已有 `makerom`、`3dstool`、`bannertool`，可以完成 CIA 容器和资源处理。
- 已有可直接安装的 RetroArch CIA：
  - `/Users/ddd/Downloads/retroarch_cia/retroarch/cores/fbneo_cps12_libretro.cia`
  - `/Users/ddd/Downloads/retroarch_cia/retroarch/cores/fbneo_neogeo_libretro.cia`

## 不重新云编译的路线

### 路线 A：预构建 CIA 基准

直接使用现成 CIA 验证 3DS 上的 RetroArch/FBNeo 运行、ROM、BIOS、存档和性能。它是完整 RetroArch 应用，不是本项目所需的 `runtime.a`，不能直接进入当前 launcher 链接流程。

### 路线 B：本地 CIA 重打包

以现成 CIA 的 NCCH/ExeFS 为模板，在本地处理图标、banner、Title ID 和 RomFS。该路线不编译核心，但启动行为仍是 RetroArch 前端行为；现成 CIA 没有本项目 launcher 的 `romfs:/content` 自动加载逻辑，必须单独验证。

### 路线 C：当前自定义 launcher

继续使用 `fbneo_3ds.elf` 和 `runtime.a`。这条路线需要已有二进制 artifact 或一次受控的核心构建；在二进制真正保存前，不再启动全量 workflow。

## 本轮执行顺序

1. 保留 `build-fbneo.yml` 仅 `workflow_dispatch`，禁止提交触发长跑。
2. 本地先对路线 A 的两个 CIA 做结构和内容基准检查。
3. 本地验证路线 B 的 CIA 重打包能力，不修改核心代码。
4. 只有拿到 `runtime.a` 和 `fbneo_3ds.elf` 后，才恢复当前 Vcoven launcher 的本地资源集成。

## 产物保存要求

以后任何一次核心构建必须同时上传：

```text
runtime.a
fbneo_3ds.elf
SOURCE.txt
SHA256SUMS
```

仅有对象清单或编译日志，不算核心交付物，也不再作为下一阶段输入。
