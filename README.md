# vcoven for macOS

一款小体积的原生 macOS ROM 转 CIA 工具，基于
[vedoot/vcoven](https://github.com/vedoot/vcoven) 与
[OldSNES](https://github.com/Ryuzaki-MrL/OldSNES)。

## 功能

- 同时拖入多个 `.gba`、`.sfc`、`.smc` ROM，逐个编辑并输出 CIA
- 左侧输入，右侧实时预览
- 可拖入或选择图标、横幅，输入标题、发布者和 Title ID
- 图标输入会自动裁切并缩放为 SMDH 所需的 24x24 与 48x48
- 未选择图标时，根据标题自动生成 48x48 文字图标
- 横幅会自动适配到 256x128
- CIA 默认输出到 ROM 所在目录
- 内置原生 Apple Silicon `3dstool`、`makerom`、`bannertool`

GBA 使用 AGB_FIRM 注入流程；SNES 使用 OldSNES/Snes9x 3DS 核心。

## 系统要求

- Apple Silicon Mac
- macOS 13 或更高版本

## 构建

```bash
swift test
./scripts/build-macos-app.sh
open dist/vcoven.app
```

生成的应用和压缩包位于 `dist/`。应用无需 Python、Pillow 或 Rosetta。

`3dstool` 可用以下命令从上游源码重新编译：

```bash
brew install cmake openssl@3
./scripts/build-3dstool-arm64.sh
```

## 其他平台

转换代码可移植，但当前发布包仅包含 macOS SwiftUI 界面和 macOS arm64
工具链。Windows/Linux 需要单独的轻量界面，以及对应平台的 `makerom`、
`3dstool`、`bannertool` 构建。

MD、GG、NGP、街机平台的核心选择和接入约束见
[docs/PLATFORM_SUPPORT.md](docs/PLATFORM_SUPPORT.md)。

## 致谢与许可

项目代码使用 MIT License。内置第三方工具及模拟器核心按各自许可发布，
详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。ROM、BIOS、封面等内容
由用户自行提供，仓库和发布包不包含游戏内容。
