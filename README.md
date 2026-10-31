<p align="center">
  <img src="Support/logo.png" width="120" alt="番茄钟 logo">
</p>

# 番茄钟

一个 macOS 菜单栏番茄钟，SwiftUI + EventKit + Swift Charts，无第三方依赖。

## 功能

- **15 / 30 / 45 分钟** 专注：点开菜单栏图标就是开始卡片，选分类和时长后一步开始。
- 没有休息阶段：完成一个番茄后回到开始卡片，直接开始下一个。
- 菜单栏显示倒计时，桌面悬浮球同步显示进度。
- 完成的专注写入指定日历，标题形如 `专注 · 分类 · 45 分钟`，备注带第几个专注和完成时间。
- 设置 → 分类：顶部设置每日目标总分钟数，每个分类按百分比分配；分类右侧实时显示换算后的目标分钟数。
- 统计页：
  - 今日活动环：Apple Watch 风格的多级圆环，每个分类一圈、各自颜色，达到该分类的每日目标就闭合；中心显示总完成度
  - 最近 7 天趋势柱
  - 今天的分类进度：已专注 / 目标分钟、完成百分比、闭合标记
  - 获得日历权限后，会自动把日历里标题以分类名开头的日程（如「工作：周会」）按日程时长计入对应分类的统计；App 自己写入的专注记录不会重复计算
- 分类可增删改名、换 SF Symbol 图标，最多 8 个。
- 完成后可发送飞书群卡片：设置 → 通用 → 飞书，粘贴自定义机器人 Webhook；支持签名校验和测试发送。
- 提醒默认开启，结束发系统通知并播放提示音。
- 自动检查 GitHub Releases 上的新版本：启动后检查一次、之后每 6 小时检查；有更新时菜单栏出现小箭头，设置 → 通用 → 更新里可一键下载安装（安装会重启 App）。

## 运行

要求：macOS 14+、Xcode、[xcodegen](https://github.com/yonaskolb/XcodeGen)。

```bash
cd /Users/philfan/i/timer
./scripts/run.sh
```

或者手动：

```bash
xcodegen generate
xcodebuild -project TomatoTimer.xcodeproj -scheme TomatoTimer \
  -configuration Debug -derivedDataPath .build build
open .build/Build/Products/Debug/TomatoTimer.app
```

用 Xcode 打开 `TomatoTimer.xcodeproj` 也可以直接 Run（“Sign to Run Locally” 即可，不需要开发者账号）。

首次开启日历写入时系统会弹权限请求。如果之前拒绝过：

```bash
tccutil reset Calendar com.philfan.tomato
```

## 打包成 App

```bash
./scripts/package.sh
```

输出到 `dist/`：

- `番茄钟.dmg`：打开后把 App 拖进 Applications。
- `番茄钟.zip`：直接解压使用。

脚本会构建 Release、校验签名、生成 DMG（带 Applications 快捷方式）和 ZIP。App 图标由 `scripts/make-icon.swift` 生成。

### 正式分发

正式包通过 GitHub Actions 发布，使用 **Developer ID 签名 + notarytool 公证 + stapler 装订**：

```bash
git tag v1.1.0
git push origin v1.1.0
```

`Release` workflow 会构建、签名、公证，并把 `番茄钟.dmg`、`番茄钟.zip`、`SHA256SUMS.txt`
上传到 GitHub Release。首次使用需要在仓库 Secrets 里配置证书和公证凭据，
完整步骤见 [docs/macos-signing.md](docs/macos-signing.md)。

本地不带凭据运行 `./scripts/package.sh` 仍然是 ad-hoc 签名，只适合自己使用。

### 自己用或给朋友

当前是 ad-hoc 签名（Sign to Run Locally），在本机可以直接打开。复制到别的 Mac 时 Gatekeeper 可能拦截，可以：

- 右键 App → 打开，或
- 系统设置 → 隐私与安全性 → 仍要打开，或
- `xattr -dr com.apple.quarantine /Applications/番茄钟.app`

没有开发者账号时，ad-hoc 版本只适合自己使用，或让对方手动放行。

## 日历怎么配

1. 系统设置 → 互联网账户 → 添加 Google 账户，勾选「日历」。
2. 番茄钟 → 设置 → 日历 → 打开写入并选择该账户下的日历。
3. 想让别人只看到专注记录：在 Google 日历里单独建一个「专注」日历，只共享这个日历。
4. 飞书：日历 → 添加日历 → 添加第三方日历 → 谷歌日历，登录同一个 Google 账号即可看到这些记录。

飞书自己的 CalDAV 是只读的，所以 App 不直接往飞书写。

## 飞书通知

1. 飞书群 → 设置 → 群机器人 → 添加自定义机器人，复制 Webhook 地址。
2. 番茄钟 → 设置 → 通用 → 飞书：打开「完成后发送飞书卡片」，粘贴 Webhook。
3. 如果机器人开启了签名校验，把密钥填到「签名密钥」；然后点「发送测试卡片」确认。

Webhook 地址等同于发消息权限，不要公开分享。

## 自动更新

App 会读取 `https://api.github.com/repos/Phil-Fan/tomato-timer/releases/latest`，和当前
`CFBundleShortVersionString` 比较。有更新时：

1. 菜单栏图标旁出现向下箭头，设置窗口顶部也会出现提示。
2. 设置 → 通用 → 更新 → 下载并安装：下载 Release 里的 zip、核对 `SHA256SUMS.txt`、校验签名。
3. App 退出后由临时脚本替换 `/Applications` 里的旧版本并重新打开，进行中的专注会中断。

自动检查默认开启，可以随时关掉；也可以用「跳过此版本」忽略某次更新。

发布新版本时按现有流程打 tag 即可，版本号取自 tag（`v1.2.0` → App 内 `1.2.0`）。Release 需要包含：

- `番茄钟.zip`（自动更新下载这个）
- `SHA256SUMS.txt`（校验用；没有这个文件会跳过校验）
- `番茄钟.dmg`（手动下载用）

`scripts/package.sh` 和 `.github/workflows/release.yml` 已经会生成并上传这些文件。

> 自动安装要求 App 位于可写入的位置（通常是 `/Applications`），且不能是 Xcode/Debug 构建。
> 从 DMG 直接运行时 App 是只读的，会提示先拖进「应用程序」。

## 数据

设置、分类、完成记录保存在 `UserDefaults`（bundle id `com.philfan.tomato`）。完成记录保留 400 天。

## 开发提示

Debug 构建支持一个冒烟测试入口，直接启动一个短番茄（正式界面可选 15 / 30 / 45 分钟，这个只用于测试）：

```bash
TOMATO_AUTOSTART=1 TOMATO_AUTOSTART_MINUTES=1 \
  .build/Build/Products/Debug/TomatoTimer.app/Contents/MacOS/TomatoTimer
```

## 结构

```
Sources/
  TomatoTimerApp.swift     菜单栏入口 + 悬浮球装配
  AppModel.swift           依赖装配
  TimerEngine.swift        专注时长计时状态机
  AppSettings.swift        偏好设置（UserDefaults）
  CategoryStore.swift      分类与每日目标
  SessionHistory.swift     完成记录 + 今日统计
  CalendarService.swift    EventKit 读写
  NotificationScheduler.swift
  UpdateService.swift      GitHub Releases 检查、下载与安装
  FloatingBall.swift       桌面悬浮球
  Views/
    PopoverView.swift      开始卡片 + 计时界面
    StatsView.swift        统计与图表
    ActivityRingsView.swift Apple Watch 风格的多级活动圆环
    SettingsView.swift     设置
    Theme.swift            分类配色
Support/Info.plist         由 xcodegen 生成
project.yml                XcodeGen 工程定义
```
