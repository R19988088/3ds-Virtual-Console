# 多核心与 3DS 下屏中文菜单实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 保持现有 GBA/SNES 功能与小体积 macOS App，恢复图标区 `48×48 PNG` 文案，并增加 MD、GG、NGP/NGPC、单一 FBA 街机核心的 CIA 生成，以及所有模拟器路线的简体中文下屏菜单。

**架构：** GBA 继续使用现有 AGB_FIRM 注入。MD/GG、NGP、街机使用裁剪后的静态 RetroArch 3DS RGUI 前端，分别链接 Genesis Plus GX、Beetle NeoPop、FBA 2012；MD 与 GG 共用同一核心包。核心包是与宿主系统无关的 3DS ELF/RSF 压缩包，由 App 首次使用时按需下载、SHA-256 校验并缓存，避免扩大基础安装包。SNES 保持当前 bubble2k16 Snes9x 3DS 路线，只重新编译加入 RomFS 直启、UTF-8 字体渲染和中文菜单。

**技术栈：** Swift 6、SwiftUI、AppKit/ImageIO、Foundation URLSession、CryptoKit、devkitARM/libctru、RetroArch 3DS RGUI、libretro 静态核心、makerom、bannertool、Swift Testing。

---

## 已确认边界

- 基线提交：`af63bd3dcc285828f469b148f4fd6bdb67e64fa3`。
- 图标区恢复显示 `48×48 PNG`，但 `iconURL == nil` 时仍自动按标题生成文字图标。
- GBA 没有模拟器下屏菜单，不参与菜单中文化。
- SNES、MD、GG、NGP/NGPC、街机在游戏内打开的下屏菜单默认使用简体中文。
- 街机只暴露一个“街机（FBA）”平台和一个 FBA 2012 核心，不显示 CPS/Neo Geo 子核心。
- FBA 2012 固定兼容 ROM-set `v0.2.97.29`。ROM、BIOS、父集由用户提供，ZIP 原样写入 RomFS。
- MD/GG 共用 Genesis Plus GX，不增加 PicoDrive。
- 基础 macOS ZIP 不内置新增核心。首次使用时下载到 `~/Library/Application Support/vcoven/CorePacks/1.0.0/`。
- 下载失败、哈希错误、版本不匹配时停止生成 CIA，并显示具体中文错误。
- 当前 GUI 仍是 macOS 13+ SwiftUI。核心包和 CIA 配方可供后续 Windows/Linux 外壳复用；本计划不新增另一套桌面 UI。

## 固定上游版本

| 组件 | 仓库 | 固定提交 |
| --- | --- | --- |
| RetroArch 3DS 前端 | `libretro/RetroArch` | `f3d2eedbfc58908d2c60cec9ed40e95c653cf261` |
| RetroArch 字体资源 | `libretro/retroarch-assets` | `6a1bbdeff5bca537a5712e2226a2aeeaee211fd0` |
| Genesis Plus GX | `libretro/Genesis-Plus-GX` | `84fcf2ec8e6b8d901c2fec55c884f285f93a1679` |
| Beetle NeoPop | `libretro/beetle-ngp-libretro` | `a50d5ac288a81f2104ddf43195a4efdd15c72227` |
| FBA 2012 | `libretro/fbalpha2012` | `0ce31536bef3162fe7e69ff5f555334ec4913cef` |
| Snes9x 3DS | `bubble2k16/snes9x_3ds` | `3e5cdba3577aafefb0860966a3daf694ece8e168` |

## 文件结构

### App 源码

- 修改 `Sources/VcovenApp/ContentView.swift`：恢复图标文案；显示平台、核心和街机附属 ZIP 控件。
- 修改 `Sources/VcovenApp/BuildIdentity.swift`：集中定义支持扩展名和平台检测。
- 修改 `Sources/VcovenApp/BuildConfiguration.swift`：增加平台、核心状态和街机附属 ZIP。
- 创建 `Sources/VcovenApp/CoreCatalog.swift`：核心 ID、版本、扩展名、RomFS 名称和内存模式。
- 创建 `Sources/VcovenApp/CorePackStore.swift`：下载、缓存、解压、SHA-256 与清单校验。
- 创建 `Sources/VcovenApp/CoreCIAConverter.swift`：统一打包 libretro 核心 CIA。
- 修改 `Sources/VcovenApp/VcovenConverter.swift`：保留 GBA/SNES，其他平台委派给核心转换器。
- 修改 `Sources/VcovenApp/AppModel.swift`：下载核心、打包进度和错误状态。
- 修改 `scripts/build-macos-app.sh`：注册新增 ROM 扩展名，不内置下载核心。

### 3DS 核心构建源码

- 创建 `core-runtime/pins.json`：保存固定仓库和提交。
- 创建 `core-runtime/retroarch-vcoven.patch`：最小 RGUI、RomFS 直启、独立存档目录、默认简体中文。
- 创建 `core-runtime/core-options-zh/`：三个核心的中文选项覆盖。
- 创建 `core-runtime/snes9x-vcoven.patch`：SNES 的直启、UTF-8 中文和存档修正。
- 创建 `core-runtime/locale/zh-Hans.json`：共享中文菜单术语。
- 创建 `core-runtime/scripts/build-core-packs.sh`：devkitARM 可复现构建。
- 创建 `core-runtime/scripts/package-core-packs.sh`：ZIP、SHA-256 与 `manifest.json`。
- 创建 `core-runtime/tests/`：源码契约、ELF 架构、包结构和禁止内容检查。

### 测试与文档

- 创建 `Tests/VcovenAppTests/CoreCatalogTests.swift`。
- 创建 `Tests/VcovenAppTests/CorePackStoreTests.swift`。
- 创建 `Tests/VcovenAppTests/CoreCIAConverterTests.swift`。
- 修改 `Tests/VcovenAppTests/BuildIdentityTests.swift`。
- 修改 `README.md`、`THIRD_PARTY_NOTICES.md`、`docs/PLATFORM_SUPPORT.md`。
- 创建 `docs/CORE_DEVICE_ACCEPTANCE.md`。

---

### 任务 1：恢复图标区文案且锁定自动图标回归

**文件：**
- 修改：`Sources/VcovenApp/ContentView.swift`
- 测试：`Tests/VcovenAppTests/BuildIdentityTests.swift`

- [ ] **步骤 1：增加无图标配置仍可构建的断言**

在 `editableConfigurationValidatesAndRandomizesTitleID()` 中设置横幅并保持图标为空：

```swift
configuration.bannerURL = URL(fileURLWithPath: "/tmp/banner.png")
#expect(configuration.iconURL == nil)
#expect(configuration.validationMessage == nil)
```

- [ ] **步骤 2：运行测试确认当前功能**

运行：`swift test --filter editableConfigurationValidatesAndRandomizesTitleID`

预期：1 项测试通过，证明本任务只改显示文案。

- [ ] **步骤 3：恢复截图中的原文案**

```swift
uploadZone(
    title: "图标",
    subtitle: "48×48 PNG",
    icon: "photo",
    url: model.selected?.iconURL,
    kind: .icon
)
```

不修改 `ArtworkGenerator`、`validationMessage` 和 `VcovenConverter` 默认图标分支。

- [ ] **步骤 4：验证并提交**

```bash
swift test
rg -n 'subtitle: "48×48 PNG"|textIconPNG' Sources/VcovenApp
git add Sources/VcovenApp/ContentView.swift Tests/VcovenAppTests/BuildIdentityTests.swift
git commit -m "ui: restore icon size hint"
```

预期：7 项以上测试通过；搜索同时命中文案和自动图标实现。

### 任务 2：建立平台目录和扩展名检测

**文件：**
- 创建：`Sources/VcovenApp/CoreCatalog.swift`
- 修改：`Sources/VcovenApp/BuildIdentity.swift`
- 修改：`Sources/VcovenApp/BuildConfiguration.swift`
- 测试：`Tests/VcovenAppTests/CoreCatalogTests.swift`

- [ ] **步骤 1：先写平台检测失败测试**

```swift
@Test func detectsEverySupportedPlatform() {
    let cases: [(String, ROMPlatform)] = [
        ("game.gba", .gba), ("game.sfc", .snes), ("game.smc", .snes),
        ("game.md", .megaDrive), ("game.smd", .megaDrive), ("game.gen", .megaDrive),
        ("game.gg", .gameGear),
        ("game.ngp", .neoGeoPocket), ("game.ngc", .neoGeoPocket),
        ("game.ngpc", .neoGeoPocket), ("game.npc", .neoGeoPocket),
        ("game.zip", .arcade),
    ]
    for (name, expected) in cases {
        #expect(ROMPlatform.detect(URL(fileURLWithPath: "/tmp/\(name)")) == expected)
    }
    #expect(ROMPlatform.detect(URL(fileURLWithPath: "/tmp/readme.txt")) == nil)
}
```

- [ ] **步骤 2：运行并确认失败**

运行：`swift test --filter detectsEverySupportedPlatform`

预期：新枚举成员或 `detect` 不存在导致编译失败。

- [ ] **步骤 3：实现唯一的平台目录**

```swift
enum ROMPlatform: String, CaseIterable, Sendable {
    case gba = "GBA"
    case snes = "SNES"
    case megaDrive = "MD"
    case gameGear = "GG"
    case neoGeoPocket = "NGP / NGPC"
    case arcade = "街机（FBA）"

    static func detect(_ url: URL) -> Self? {
        switch url.pathExtension.lowercased() {
        case "gba": .gba
        case "sfc", "smc": .snes
        case "md", "smd", "gen", "bin", "rom": .megaDrive
        case "gg": .gameGear
        case "ngp", "ngc", "ngpc", "npc": .neoGeoPocket
        case "zip": .arcade
        default: nil
        }
    }
}
```

删除 `BuildConfiguration.swift` 中旧枚举；`acceptedROMs` 只调用 `detect`。

- [ ] **步骤 4：设置核心和产品码**

```swift
var coreID: CoreID? {
    switch self {
    case .gba: nil
    case .snes: .snes9x3DS
    case .megaDrive, .gameGear: .genesisPlusGX
    case .neoGeoPocket: .beetleNeoPop
    case .arcade: .fba2012
    }
}
```

产品码固定为 GBA 原值、`CTR-N-SNES`、`CTR-N-MDRV`、`CTR-N-GGER`、`CTR-N-NGPC`、`CTR-N-FBA1`。

- [ ] **步骤 5：验证并提交**

```bash
swift test --filter detectsEverySupportedPlatform
git add Sources/VcovenApp/CoreCatalog.swift Sources/VcovenApp/BuildIdentity.swift Sources/VcovenApp/BuildConfiguration.swift Tests/VcovenAppTests/CoreCatalogTests.swift
git commit -m "feat: catalog additional ROM platforms"
```

### 任务 3：建立按需核心包协议

**文件：**
- 修改：`Sources/VcovenApp/CoreCatalog.swift`
- 创建：`Sources/VcovenApp/CorePackStore.swift`
- 创建：`Tests/VcovenAppTests/CorePackStoreTests.swift`
- 创建：`core-runtime/pins.json`

- [ ] **步骤 1：写清单和篡改测试**

临时包包含 `runtime.elf`、`runtime.rsf`、`licenses/NOTICE.txt`。测试有效包通过；篡改 ELF 一个字节后抛出 `.hashMismatch("runtime.elf")`；绝对路径和含 `..` 路径被拒绝。

- [ ] **步骤 2：运行并确认失败**

运行：`swift test --filter CorePackStoreTests`

预期：核心包类型尚不存在。

- [ ] **步骤 3：实现清单类型**

```swift
enum CoreID: String, Codable, Sendable {
    case snes9x3DS = "snes9x-3ds"
    case genesisPlusGX = "genesis-plus-gx"
    case beetleNeoPop = "beetle-neopop"
    case fba2012 = "fba2012"
}

struct CorePackManifest: Codable, Sendable {
    struct FileEntry: Codable, Sendable { let path: String; let sha256: String }
    let schemaVersion: Int
    let coreID: CoreID
    let version: String
    let files: [FileEntry]
}
```

- [ ] **步骤 4：实现下载、校验和原子缓存**

三个 URL 固定为：

```text
https://github.com/R19988088/vcoven-GBA-Virtual-Console-/releases/download/cores-v1.0.0/genesis-plus-gx.vcore.zip
https://github.com/R19988088/vcoven-GBA-Virtual-Console-/releases/download/cores-v1.0.0/beetle-neopop.vcore.zip
https://github.com/R19988088/vcoven-GBA-Virtual-Console-/releases/download/cores-v1.0.0/fba2012.vcore.zip
```

流程：命中已验证缓存即返回；否则下载同卷临时文件；用 `/usr/bin/ditto -x -k` 解压；校验 schema、core ID、版本、全部 SHA-256；原子移动至最终目录。失败时删除临时内容，不破坏已验证缓存。

- [ ] **步骤 5：验证并提交**

```bash
swift test --filter CorePackStoreTests
git add Sources/VcovenApp/CoreCatalog.swift Sources/VcovenApp/CorePackStore.swift Tests/VcovenAppTests/CorePackStoreTests.swift core-runtime/pins.json
git commit -m "feat: add verified on-demand core packs"
```

### 任务 4：构建最小 RetroArch 3DS 中文前端

**文件：**
- 创建：`core-runtime/retroarch-vcoven.patch`
- 创建：`core-runtime/locale/zh-Hans.json`
- 创建：`core-runtime/scripts/build-core-packs.sh`
- 创建：`core-runtime/tests/verify-runtime-source.sh`

- [ ] **步骤 1：先写源码契约检查**

```bash
test "$(git -C "$RA" rev-parse HEAD)" = "f3d2eedbfc58908d2c60cec9ed40e95c653cf261"
rg -q 'romfs:/content/game\.' "$RA/frontend/drivers/platform_ctr.c"
rg -q 'APT_GetProgramID' "$RA/frontend/drivers/platform_ctr.c"
rg -q 'RETRO_LANGUAGE_CHINESE_SIMPLIFIED' "$RA/configuration.c"
rg -q 'HAVE_RGUI' "$RA/Makefile.ctr"
! rg -q '^HAVE_NETWORKING = 1' "$RA/Makefile.ctr"
```

运行：`core-runtime/tests/verify-runtime-source.sh .core-build/RetroArch`

预期：补丁标记缺失而失败。

- [ ] **步骤 2：实现 RomFS 自动直启和存档隔离**

补丁固定行为：

1. `romfsInit()` 后扫描 `romfs:/content/` 中唯一一个 `game.` 主文件。
2. 写入 `RARCH_PATH_CONTENT` 并跳过文件浏览器。
3. 主文件数量不是 1 时，在下屏显示中文错误后退出 HOME Menu。
4. 用 `APT_GetProgramID(&programID)` 读取当前 Title ID。
5. SRAM、即时存档、配置和 remap 写入 `sdmc:/3ds/vcoven/` 加 16 位大写十六进制 Title ID 组成的目录，例如 `sdmc:/3ds/vcoven/000400000F123400/`。
6. system/BIOS 目录指向 `romfs:/content/`，FBA 可在同目录读取 BIOS/父集。

- [ ] **步骤 3：裁剪为最小 RGUI**

保留：继续游戏、core options、controls/remap、音视频、即时存取、重置、退出。

关闭：XMB、网络、成就、在线更新、录制、串流、缩略图、数据库、播放列表、overlay、rewind、shader、动态核心加载。

RomFS 只带：

```text
assets/rgui/font/bitmap10x10_eng.bin
assets/rgui/font/bitmap10x10_chn.bin
retroarch.cfg
content/game.md
```

其中 `content/game.md` 是目录结构示例；打包器使用 ROM 的小写原扩展名，实际输出可能是 `game.gg`、`game.ngp` 或 `game.zip`。

配置固定为：

```ini
menu_driver = "rgui"
user_language = "12"
menu_show_load_core = "false"
menu_show_load_content = "false"
menu_show_online_updater = "false"
quit_press_twice = "false"
```

- [ ] **步骤 4：验证并提交**

```bash
core-runtime/tests/verify-runtime-source.sh .core-build/RetroArch
rg -n 'MENU_ENUM_LABEL_VALUE_(RESUME_CONTENT|SAVE_STATE|LOAD_STATE|CORE_OPTIONS|CONTROLS|RESTART_CONTENT|QUIT_RETROARCH)' .core-build/RetroArch/intl/msg_hash_chs.h
git add core-runtime/retroarch-vcoven.patch core-runtime/locale/zh-Hans.json core-runtime/scripts/build-core-packs.sh core-runtime/tests/verify-runtime-source.sh
git commit -m "feat: add minimal Chinese 3DS core runtime"
```

### 任务 5：编译 MD/GG 共用核心包

**文件：**
- 修改：`core-runtime/scripts/build-core-packs.sh`
- 创建：`core-runtime/scripts/build-fba2012.sh`
- 创建：`core-runtime/core-options-zh/genesis-plus-gx.h`
- 创建：`core-runtime/tests/verify-genesis-pack.sh`

- [ ] **步骤 1：先写失败检查**

检查 ARM EABI5 ELF、RSF、中文菜单、支持 `md/smd/gen/bin/rom/gg`，并确认包内不含 ROM。中文核心选项覆盖区域、宽高比、帧率、音频滤波、手柄类型、过扫描。

- [ ] **步骤 2：运行并确认失败**

运行：`core-runtime/tests/verify-genesis-pack.sh core-runtime/dist/genesis-plus-gx`

预期：缺少 `runtime.elf`。

- [ ] **步骤 3：按固定提交静态编译**

运行：`core-runtime/scripts/build-core-packs.sh genesis-plus-gx`

脚本使用 `LIBRETRO=genesis_plus_gx`，应用共享前端和中文覆盖，只输出 stripped `runtime.elf`、`runtime.rsf`、RomFS 资产和许可。MD/GG 不生成两份 ELF。

- [ ] **步骤 4：验证并提交**

```bash
core-runtime/tests/verify-genesis-pack.sh core-runtime/dist/genesis-plus-gx
git add core-runtime/scripts/build-core-packs.sh core-runtime/core-options-zh/genesis-plus-gx.h core-runtime/tests/verify-genesis-pack.sh
git commit -m "build: add shared MD and GG core pack"
```

### 任务 6：编译 NGP/NGPC 核心包

**文件：**
- 修改：`core-runtime/scripts/build-core-packs.sh`
- 创建：`core-runtime/core-options-zh/beetle-neopop.h`
- 创建：`core-runtime/tests/verify-ngp-pack.sh`

- [ ] **步骤 1：先写失败检查**

验证 `ngp/ngc/ngpc/npc`、ARM ELF、中文菜单、flash save 写入 Title ID 专属目录。

运行：`core-runtime/tests/verify-ngp-pack.sh core-runtime/dist/beetle-neopop`

预期：缺少产物。

- [ ] **步骤 2：编译固定 Beetle NeoPop**

运行：`core-runtime/scripts/build-core-packs.sh beetle-neopop`

使用固定提交，不启用 JIT，不要求 BIOS，将机器语言、颜色和音频选项翻译为简体中文。

- [ ] **步骤 3：验证并提交**

```bash
core-runtime/tests/verify-ngp-pack.sh core-runtime/dist/beetle-neopop
git add core-runtime/scripts/build-core-packs.sh core-runtime/core-options-zh/beetle-neopop.h core-runtime/tests/verify-ngp-pack.sh
git commit -m "build: add Neo Geo Pocket core pack"
```

### 任务 7：编译唯一的 FBA 街机核心包

**文件：**
- 修改：`core-runtime/scripts/build-core-packs.sh`
- 创建：`core-runtime/core-options-zh/fba2012.h`
- 创建：`core-runtime/tests/verify-fba-pack.sh`
- 创建：`core-runtime/patches/fba2012-ignore-rom-crc.patch`
- 创建：`core-runtime/tests/verify-fba-crc-patch.sh`
- 创建：`core-runtime/tests/verify-fba-crc-contract.sh`
- 创建：`.github/workflows/build-fba2012.yml`

- [x] **步骤 1：写单核心约束并确认失败**

```bash
test -f "$PACK/runtime.elf"
test ! -e "$DIST/fbalpha2012_cps1"
test ! -e "$DIST/fbalpha2012_cps2"
test ! -e "$DIST/fbalpha2012_cps3"
test ! -e "$DIST/fbalpha2012_neogeo"
strings "$PACK/runtime.elf" | rg -q '0.2.97.29'
```

运行：`core-runtime/tests/verify-fba-pack.sh core-runtime/dist/fba2012`

预期：通用 FBA 产物尚不存在。

- [ ] **步骤 2：编译一个通用 FBA 2012（已接入构建脚本，待 devkitARM）**

运行：`core-runtime/scripts/build-fba2012.sh`；GitHub Actions 使用 `.github/workflows/build-fba2012.yml` 在 Ubuntu runner 安装 devkitARM 后构建并上传 ARM 静态核心。

使用 `LIBRETRO=fbalpha2012`，不生成 CPS/NeoGeo 专用变体；RSF 使用 80 MB Old 3DS 模式和 124 MB New 3DS 扩展模式，保留上游 `APP_BIG_TEXT_SECTION`。

编译参数加入 `-DFBA_IGNORE_ROM_CRC=1` 并应用 `core-runtime/patches/fba2012-ignore-rom-crc.patch`。核心按归一化文件名寻找 ROM，CRC 不参与拒绝；仍要求文件名匹配且解压后的字节长度不小于驱动声明长度。CRC 差异只写入日志，映射失败、缺文件和长度不足仍返回加载失败。当前脚本固定上游提交 `0ce31536bef3162fe7e69ff5f555334ec4913cef`，产物为 `runtime.a`；生成 3DS 可加载 ELF 仍需 devkitARM/RetroArch 3DS 链接步骤。

- [ ] **步骤 3：翻译加载错误**

覆盖：ROM-set 不匹配、缺少 BIOS、缺少父集、不支持游戏、内存不足、载入失败。技术名 `CPS-1`、`CPS-2`、`CPS-3`、`Neo Geo`、`BIOS`、`ROM-set` 保留英文。

- [ ] **步骤 4：验证并提交**

```bash
core-runtime/tests/verify-fba-pack.sh core-runtime/dist/fba2012
core-runtime/tests/verify-fba-crc-patch.sh .core-build/fbalpha2012
git add core-runtime/scripts/build-core-packs.sh core-runtime/core-options-zh/fba2012.h core-runtime/tests/verify-fba-pack.sh
git commit -m "build: add single FBA 2012 core pack"
```

### 任务 8：让现有 SNES 核心直启并显示中文菜单

**文件：**
- 创建：`core-runtime/snes9x-vcoven.patch`
- 创建：`core-runtime/tests/verify-snes-pack.sh`
- 修改：`core-runtime/scripts/build-core-packs.sh`
- 替换产物：`Sources/VcovenApp/Resources/snes/snes9x_3ds.elf`

- [ ] **步骤 1：建立回归基线**

当前 ELF SHA-256：

```text
cd6ea544f83dee8cde1cfdf1268cb210d1fe48be430af8f7b63ed1156354de2d
```

运行：`swift test --filter buildsSNESCIAEndToEnd`

预期：现有 SNES CIA 测试通过。

- [ ] **步骤 2：写新 ELF 契约测试**

检查 UTF-8 解码符号和“继续游戏/即时存档/读取存档/按键设置/画面设置/声音设置/重新开始/退出”；确认启动路径为 `romfs:/rom.smc`，不进入 ROM 浏览器。

- [ ] **步骤 3：实现中文字体和直启**

基于固定 Snes9x 3DS：

- `source/3dsui.cpp` 从逐字节绘制改为严格 UTF-8 解码。
- ASCII 沿用 Tempesta；中文按 Unicode 索引读取 RetroArch assets 固定提交中的 `bitmap10x10_chn.bin`。
- 将 226,226 字节压缩中文字库作为只读资源编入 ELF，不依赖系统字体。
- 菜单字符串集中在 `source/vcoven_zh_hans.h`。
- 启动直接加载 `romfs:/rom.smc`，暂停菜单保留存取状态、画面、声音、按键、重置、退出。
- SRAM、配置、即时存档写入 `sdmc:/3ds/vcoven/` 加当前 16 位大写十六进制 Title ID 组成的目录。

- [ ] **步骤 4：构建、替换、验证并提交**

```bash
core-runtime/scripts/build-core-packs.sh snes9x-3ds
cp core-runtime/dist/snes9x-3ds/runtime.elf Sources/VcovenApp/Resources/snes/snes9x_3ds.elf
core-runtime/tests/verify-snes-pack.sh Sources/VcovenApp/Resources/snes/snes9x_3ds.elf
swift test --filter buildsSNESCIAEndToEnd
git add core-runtime/snes9x-vcoven.patch core-runtime/tests/verify-snes-pack.sh core-runtime/scripts/build-core-packs.sh Sources/VcovenApp/Resources/snes/snes9x_3ds.elf
git commit -m "feat: localize SNES runtime menu"
```

预期：ELF 契约与 SNES CIA 测试通过，新 SHA 与基线不同。

### 任务 9：实现统一核心 CIA 打包器

**文件：**
- 创建：`Sources/VcovenApp/CoreCIAConverter.swift`
- 修改：`Sources/VcovenApp/VcovenConverter.swift`
- 创建：`Tests/VcovenAppTests/CoreCIAConverterTests.swift`

- [ ] **步骤 1：写 RomFS 布局失败测试**

```swift
@Test func stagesCoreContentWithoutChangingROMBytes() throws {
    let staged = try CoreCIAConverter.stageContent(
        romURL: fixture("game.gg"),
        attachments: [],
        in: temporaryDirectory
    )
    #expect(staged.mainURL.lastPathComponent == "game.gg")
    #expect(try Data(contentsOf: staged.mainURL) == Data([0x47, 0x47]))
}
```

街机测试加入 `neogeo.zip` 和父集 ZIP，断言保留文件名并与 `game.zip` 同目录；重复文件名抛出中文错误。

运行：`swift test --filter CoreCIAConverterTests`

预期：类型尚不存在。

- [ ] **步骤 2：实现打包器**

固定流程：

1. `CorePackStore.resolve(coreID)`。
2. 主 ROM 原样复制到 `romfs/content/`，文件名由 `"game." + configuration.romURL.pathExtension.lowercased()` 生成。
3. 街机附属 ZIP 按原名复制到 `romfs/content/`。
4. 复制字体和 `retroarch.cfg`。
5. 复用现有 48×48 图标和 256×128 banner 生成。
6. 调用 `makerom`，传入 `runtime.elf`、`runtime.rsf`、唯一 ID、产品码和 RomFS。
7. 仅在 makerom 成功后原子替换最终 CIA。

- [ ] **步骤 3：按平台委派**

```swift
switch configuration.platform {
case .gba:
    try buildGBA(configuration, iconURL: iconURL, bannerURL: bannerURL, work: work)
case .snes:
    try buildSNES(configuration, iconURL: iconURL, bannerURL: bannerURL, work: work)
case .megaDrive, .gameGear, .neoGeoPocket, .arcade:
    try CoreCIAConverter(resources: resources).build(
        configuration, iconURL: iconURL, bannerURL: bannerURL, work: work
    )
}
```

- [ ] **步骤 4：验证并提交**

```bash
swift test --filter CoreCIAConverterTests
git add Sources/VcovenApp/CoreCIAConverter.swift Sources/VcovenApp/VcovenConverter.swift Tests/VcovenAppTests/CoreCIAConverterTests.swift
git commit -m "feat: package ROMs with downloadable 3DS cores"
```

### 任务 10：增加街机 BIOS/父集输入和核心状态 UI

**文件：**
- 修改：`Sources/VcovenApp/BuildConfiguration.swift`
- 修改：`Sources/VcovenApp/AppModel.swift`
- 修改：`Sources/VcovenApp/ContentView.swift`
- 测试：`Tests/VcovenAppTests/CoreCatalogTests.swift`

- [ ] **步骤 1：写附件行为失败测试**

```swift
@Test func arcadeAcceptsOnlyZipAttachments() {
    var configuration = BuildConfiguration(romURL: URL(fileURLWithPath: "/tmp/mslug.zip"))
    configuration.addArcadeAttachments([
        URL(fileURLWithPath: "/tmp/neogeo.zip"),
        URL(fileURLWithPath: "/tmp/readme.txt"),
    ])
    #expect(configuration.arcadeAttachments.map(\.lastPathComponent) == ["neogeo.zip"])
}
```

运行：`swift test --filter arcadeAcceptsOnlyZipAttachments`

预期：附件接口不存在。

- [ ] **步骤 2：实现平台相关 UI**

- ROM 区显示“拖入支持的 ROM 文件”，小字列出 `GBA / SNES / MD / GG / NGP / FBA`。
- 图标区保持 `48×48 PNG`。
- Title ID 刷新按钮对所有平台显示。
- “存档类型”只对 GBA 显示。
- 核心平台显示模拟器名称和“下屏菜单：简体中文”。
- 街机显示“BIOS / 父集 ZIP”多选拖放区。
- 缺少已知 Neo Geo BIOS 显示黄色提示；未知硬件不被静态提示阻止。
- 核心未缓存时按钮显示“下载核心并生成 CIA”，下载显示核心名与百分比。

- [ ] **步骤 3：扩展构建状态**

```swift
enum BuildState: Equatable, Sendable {
    case waiting
    case downloadingCore(name: String, progress: Double)
    case packaging
    case completed
    case failed(String)
}
```

`AppModel` 将 URLSession 下载进度映射到所选配置；切换 ROM 不丢失各自状态。

- [ ] **步骤 4：验证并提交**

```bash
swift test
git add Sources/VcovenApp/BuildConfiguration.swift Sources/VcovenApp/AppModel.swift Sources/VcovenApp/ContentView.swift Tests/VcovenAppTests/CoreCatalogTests.swift
git commit -m "ui: add core and arcade dependency controls"
```

### 任务 11：注册格式并守住基础包体

**文件：**
- 修改：`scripts/build-macos-app.sh`
- 创建：`scripts/verify-macos-app.sh`
- 修改：`.gitignore`

- [ ] **步骤 1：写包体验证并确认失败**

```bash
plutil -extract CFBundleDocumentTypes xml1 -o - "$APP/Contents/Info.plist" | rg -q '<string>gg</string>'
! find "$APP" -path '*CorePacks*' -print -quit | grep -q .
test "$(du -sk "$ZIP" | awk '{print $1}')" -lt 12288
codesign --verify --deep --strict "$APP"
unzip -tq "$ZIP"
```

运行：`scripts/verify-macos-app.sh outputs/vcoven.app outputs/vcoven-macOS.zip`

预期：缺少新增扩展名。

- [ ] **步骤 2：更新 Info.plist 和忽略项**

文档扩展名加入 `md/smd/gen/bin/rom/gg/ngp/ngc/ngpc/npc/zip`，保留 `gba/sfc/smc`。

`.gitignore` 加入对应 ROM 扩展、`.core-build/`、`core-runtime/dist/`，但不能忽略源码、patch、测试或已提交 manifest。

- [ ] **步骤 3：重新构建、验证并提交**

```bash
./scripts/build-macos-app.sh outputs
scripts/verify-macos-app.sh outputs/vcoven.app outputs/vcoven-macOS.zip
git add scripts/build-macos-app.sh scripts/verify-macos-app.sh .gitignore
git commit -m "build: register additional ROM formats"
```

预期：签名、ZIP、arm64 宿主程序、格式列表和 12 MiB 上限全部通过。

### 任务 12：可复现打包和发布核心

**文件：**
- 创建：`core-runtime/scripts/package-core-packs.sh`
- 创建：`core-runtime/tests/verify-packs.sh`
- 生成但不提交：`core-runtime/dist/*.vcore.zip`
- 生成并提交：`Sources/VcovenApp/Resources/core-pack-manifest.json`

- [ ] **步骤 1：实现固定包结构**

每个下载 ZIP 只包含：

```text
manifest.json
runtime.elf
runtime.rsf
romfs/assets/rgui/font/bitmap10x10_eng.bin
romfs/assets/rgui/font/bitmap10x10_chn.bin
romfs/retroarch.cfg
licenses/
source-provenance.json
```

按字典序、固定时间戳、无资源分叉打包。`source-provenance.json` 写入上游 URL、提交和补丁 SHA-256。

- [ ] **步骤 2：生成并验证**

```bash
core-runtime/scripts/package-core-packs.sh
core-runtime/tests/verify-packs.sh core-runtime/dist
```

预期：恰好生成 `genesis-plus-gx.vcore.zip`、`beetle-neopop.vcore.zip`、`fba2012.vcore.zip`；重复运行 SHA-256 不变；每个 ELF 为 ARM EABI5。

- [ ] **步骤 3：发布独立核心包 Release**

```bash
gh release create cores-v1.0.0 core-runtime/dist/*.vcore.zip \
  --repo R19988088/vcoven-GBA-Virtual-Console- \
  --title "vcoven core packs 1.0.0" \
  --notes "3DS runtime core packs for vcoven; ROM and BIOS files are not included."
```

- [ ] **步骤 4：从 Release 回读并提交清单**

下载三个资产到空目录，用 `core-pack-manifest.json` 校验 SHA-256，再确认 ELF 架构。

```bash
git add core-runtime/scripts/package-core-packs.sh core-runtime/tests/verify-packs.sh Sources/VcovenApp/Resources/core-pack-manifest.json
git commit -m "release: publish verified 3DS core packs"
```

### 任务 13：许可、文档和跨平台边界

**文件：**
- 修改：`THIRD_PARTY_NOTICES.md`
- 修改：`README.md`
- 修改：`docs/PLATFORM_SUPPORT.md`
- 创建：`core-runtime/README.md`

- [ ] **步骤 1：更新许可**

记录 RetroArch GPLv3、Genesis Plus GX 非商业许可、Beetle NeoPop GPLv2、FBA 2012 非商业许可、Snes9x 上游许可。核心包 Release 包含对应 license 与补丁源码；README 不把这些核心称为 MIT 组件。

- [ ] **步骤 2：更新使用说明**

明确 MD/GG 共用 Genesis Plus GX；NGP/NGPC 使用 Beetle NeoPop；街机只使用 FBA 2012 并要求 `v0.2.97.29` ROM-set；BIOS/父集可附加；所有模拟器路线默认简体中文下屏菜单；GBA 无模拟器菜单。

- [ ] **步骤 3：写清跨平台事实**

固定表述：核心包是 3DS ARM ELF，与生成 CIA 的宿主系统无关；macOS App 仍依赖 SwiftUI、AppKit 和 macOS arm64 工具。Windows/Linux 复用核心包仍需对应宿主的 `makerom`、`3dstool`、`bannertool` 与非 AppKit UI/图像处理。

- [ ] **步骤 4：验证并提交**

```bash
rg -n 'PicoDrive|多个 FBA|CPS-1.*核心|CPS-2.*核心|CPS-3.*核心' README.md docs core-runtime/README.md
git add README.md THIRD_PARTY_NOTICES.md docs/PLATFORM_SUPPORT.md core-runtime/README.md
git commit -m "docs: document core packs and Chinese menus"
```

预期：没有把 PicoDrive 或多个 FBA 子核心列为实现；CPS 名称只用于兼容性说明。

### 任务 14：完整回归与真机验收

**文件：**
- 创建：`docs/CORE_DEVICE_ACCEPTANCE.md`
- 修改：`Tests/VcovenAppTests/BuildIdentityTests.swift`
- 修改：`Tests/VcovenAppTests/CoreCIAConverterTests.swift`

- [ ] **步骤 1：运行宿主端验证**

```bash
swift test
git diff --check
core-runtime/tests/verify-packs.sh core-runtime/dist
./scripts/build-macos-app.sh outputs
scripts/verify-macos-app.sh outputs/vcoven.app outputs/vcoven-macOS.zip
```

预期：所有命令退出码为 0。

- [ ] **步骤 2：逐平台生成并解包检查 CIA**

用自制测试 ROM 和匹配 FBA 2012 测试集生成 GBA、SNES、MD、GG、NGP、街机六个 CIA。用内置 `3dstool` 解包，确认 Title ID、产品码、icon、banner、RomFS 主 ROM、核心 ELF 与平台一致。

- [ ] **步骤 3：Old 3DS 真机矩阵**

每个平台执行：安装、冷启动、自动进入游戏、按键、音频、打开下屏菜单、中文无方框/乱码/截断、调整选项、退出重启、存档读取、卸载。

街机额外测试匹配 `0.2.97.29` 的 CPS-1、CPS-2、Neo Geo 各一套；缺 BIOS、缺父集、错 ROM-set 三类失败必须显示中文原因。性能和内存按机型记录。

- [ ] **步骤 4：New 3DS 真机矩阵**

重复六个平台，记录 FBA 加载内存、帧率和音频稳定性。CPS-3 只在有匹配测试 ROM 时验收；单一 FBA 核心不等于声明所有街机游戏兼容。

- [ ] **步骤 5：填写证据并提交**

`docs/CORE_DEVICE_ACCEPTANCE.md` 每项记录 CIA SHA-256、设备型号、系统/Luma 版本、通过/失败和失败日志。

```bash
git add docs/CORE_DEVICE_ACCEPTANCE.md Tests/VcovenAppTests/BuildIdentityTests.swift Tests/VcovenAppTests/CoreCIAConverterTests.swift
git commit -m "test: verify additional core workflows"
```

## 最终完成条件

- 图标区显示 `48×48 PNG`，不选图标仍生成文字图标。
- 同一 Genesis Plus GX 核心包构建 MD 和 GG CIA。
- Beetle NeoPop 构建 NGP/NGPC CIA。
- 只存在一个 FBA 2012 核心包，兼容集固定为 `v0.2.97.29`。
- SNES、MD、GG、NGP/NGPC、FBA 下屏菜单在真机显示简体中文，无乱码或文本溢出。
- 所有核心路线直接启动内嵌 ROM，不出现 ROM 文件选择器。
- 每个 Title ID 使用独立可写存档目录，重启后可读。
- 基础 macOS ZIP 小于 12 MiB，不含新增下载核心。
- 核心包 SHA-256、上游提交、补丁和许可可追溯。
- GBA 与现有 SNES 回归测试保持通过；真机证据与宿主构建证据分开记录。
