# 番茄钟

一个 macOS 菜单栏番茄钟，SwiftUI + EventKit，无第三方依赖。

## 功能

- 点开菜单栏图标就是「开始专注」卡片：选分类、选时长（15/25/45/60，可在设置里加自定义默认值），一步开始。
- 菜单栏显示倒计时，专注 / 短休息 / 长休息自动轮转。
- 完成的专注可以写入指定日历，标题包含**分类**和**时长**，备注里带第几个番茄和完成时间。
- 今日番茄数与专注分钟数统计，跨天自动归零。
- 系统通知 + 提示音；支持自动开始下一段。
- 分类可在「设置 → 分类」里增删改名，最多 8 个。

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

用 Xcode 打开 `TomatoTimer.xcodeproj` 也可以直接 Run（签名用 “Sign to Run Locally” 即可，不需要开发者账号）。

首次开启日历写入时系统会弹权限请求。如果之前拒绝过，可以重置后再试：

```bash
tccutil reset Calendar com.philfan.tomato
```

## 日历怎么配

**Google 日历**

1. 系统设置 → 互联网账户 → 添加 Google 账户，勾选「日历」。
2. 打开番茄钟 → 设置 → 日历 → 选择该账户下的日历。
3. 想让别人只看到专注记录：在 Google 日历里单独建一个「🍅 专注」日历，只共享这个日历，不要共享主日历。

**飞书**

- 飞书 → 日历 → 添加日历 → 添加第三方日历 → 谷歌日历，登录同一个 Google 账号，专注记录就会出现在飞书里。
- 飞书自己的 CalDAV 是只读的，番茄钟不会往飞书写日程；要写飞书需要另外接飞书开放平台 API。

**共享给别人（Google 侧）**

Google 日历 → 目标日历 → 设置和共享 → 与特定人员共享，对方需要有 Google 账号；没有账号只能通过公开链接只读查看。不要把「iCal 格式的秘密地址」发给别人，它等于整个日历的读取权限。

## 数据

设置、分类和今日统计保存在 `UserDefaults`（bundle id `com.philfan.tomato`），没有自建数据库。

## 开发提示

Debug 构建支持一个冒烟测试入口，直接启动一个短番茄：

```bash
TOMATO_AUTOSTART=1 TOMATO_AUTOSTART_MINUTES=1 \
  .build/Build/Products/Debug/TomatoTimer.app/Contents/MacOS/TomatoTimer
```

## 结构

```
Sources/
  TomatoTimerApp.swift     菜单栏入口
  AppModel.swift           依赖装配
  TimerEngine.swift        计时状态机
  AppSettings.swift        偏好设置（UserDefaults）
  CategoryStore.swift      分类持久化
  CalendarService.swift    EventKit 读写
  StatsStore.swift         今日统计
  NotificationScheduler.swift
  Views/
    PopoverView.swift      开始卡片 + 计时界面
    SettingsView.swift     设置
    Theme.swift            分类配色
Support/Info.plist         由 xcodegen 生成
project.yml                XcodeGen 工程定义
```
