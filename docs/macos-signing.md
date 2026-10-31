# macOS 签名与公证（Developer ID + notarytool）

> 目标：从 GitHub Release 下载的 `TomatoTimer.dmg` / `TomatoTimer.zip` 在别人的 Mac 上打开时，
> 不再出现「已损坏 / 无法验证开发者」。
>
> 路径：**Developer ID Application 签名 → notarytool 公证 → stapler 装订**。
> 这和 Mac App Store 上架不是同一条链路（MAS 强制 App Sandbox）。

未配置 secrets 时，本地 `./scripts/package.sh` 仍然是 ad-hoc 签名，只适合自己用。
`Release` workflow 在缺少签名凭据时会直接失败，避免把未签名的包发出去。

## 总览：需要准备什么

| 步骤 | 去哪里 | 得到什么 | 用途 |
|------|--------|----------|------|
| 1 | 本机「钥匙串访问」 | CSR 文件 | 向 Apple 申请证书 |
| 2 | [Apple Developer → Certificates](https://developer.apple.com/account/resources/certificates/list) | **Developer ID Application** `.cer` | 装进钥匙串，用于 codesign |
| 3 | 本机钥匙串 | `.p12` + base64 | 填进 GitHub Secrets |
| 4 | [App Store Connect → 集成](https://appstoreconnect.apple.com/access/integrations/api) | Issuer ID、Key ID、`.p8` | 给 notarytool 公证 |
| 5 | GitHub → Settings → Secrets and variables → Actions | — | 粘贴上面的值 |

只需要 Apple Developer Program（约 $99/年）。**不需要**在 App Store Connect 里创建 Mac App 记录。

## 第一步：生成 CSR

1. 打开 **钥匙串访问**。
2. 菜单：**钥匙串访问 → 证书助理 → 从证书颁发机构请求证书…**
3. 填邮箱和常用名称，选 **存储到磁盘**。
4. 得到 `CertificateSigningRequest.certSigningRequest`。

## 第二步：申请 Developer ID Application 证书

1. 打开 <https://developer.apple.com/account/resources/certificates/list>。
2. 点 **+**，类型选 **Developer ID Application**。
   - 不要选 Apple Development
   - 不要选 Apple Distribution（那是上架 / TestFlight 用的）
3. 上传第一步的 CSR，下载 `.cer`，双击装进 **login** 钥匙串。

确认本机能看到证书：

```bash
security find-identity -v -p codesigning
```

应出现：

```text
"Developer ID Application: 你的名字 (TEAMID)"
```

只有账号的 Account Holder 能创建 Developer ID Application 证书。

## 第三步：导出 .p12 并转 base64

1. 钥匙串访问 → **登录** → **我的证书**。
2. 展开 **Developer ID Application: …**，选中下面的私钥。
3. 右键 → **导出…** → 格式 **个人信息交换 (.p12)**，设置密码（就是 `APPLE_CERTIFICATE_PASSWORD`）。
4. 转成一行 base64：

```bash
openssl base64 -A -in /path/to/certificate.p12 -out certificate-base64.txt
# APPLE_CERTIFICATE = certificate-base64.txt 的全文
```

不要把 `.p12` 或 base64 提交进 git，填完 secret 后删除本地导出文件。

## 第四步：创建公证用的 API Key

1. 打开 <https://appstoreconnect.apple.com/access/integrations/api>。
2. **用户和访问 → 集成 → App Store Connect API → 生成 API 密钥**。
3. 记下 **Issuer ID**（表格上方）和 **Key ID**（表格中的一列）。
4. 下载 `AuthKey_XXXXXXXXXX.p8`（只能下载一次）。

| 东西 | Secret 名 |
|------|-----------|
| Issuer ID | `APPLE_API_ISSUER` |
| Key ID | `APPLE_API_KEY` |
| `.p8` 全文或它的 base64 | `APPLE_API_KEY_P8` |

备选方案：不用 API Key，改用 Apple ID + [App 专用密码](https://support.apple.com/102654) + Team ID，
对应 `APPLE_ID` / `APPLE_PASSWORD` / `APPLE_TEAM_ID`。API Key 更稳定，优先用它。

## 第五步：填写 GitHub Secrets

路径：仓库 **Settings → Secrets and variables → Actions → New repository secret**。

必需：

| Secret | 值 |
|--------|-----|
| `APPLE_CERTIFICATE` | `.p12` 的 base64 全文（一行） |
| `APPLE_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `APPLE_SIGNING_IDENTITY` | `Developer ID Application: 你的名字 (TEAMID)` 整串 |

公证（二选一）：

| 方案 | Secrets |
|------|---------|
| API Key（推荐） | `APPLE_API_KEY` + `APPLE_API_ISSUER` + `APPLE_API_KEY_P8` |
| Apple ID | `APPLE_ID` + `APPLE_PASSWORD` + `APPLE_TEAM_ID` |

Team ID 也可以不填：workflow 会从 `APPLE_SIGNING_IDENTITY` 末尾的 `(TEAMID)` 自动解析。

## CI 会做什么

### `.github/workflows/ci.yml`

- 在 `main` 的 push 和所有 PR 上运行。
- 使用 `macos-26` runner（Xcode 26；`macos-15` 的 Xcode 16 会在 Swift 6 并发检查上失败）。
- 用 XcodeGen 生成工程，跑 `./scripts/package.sh`（ad-hoc 签名）。
- 校验 App 签名、DMG、ZIP 和 `SHA256SUMS.txt` 都能产出。

### `.github/workflows/release.yml`

推送 `v*` tag 时运行：

1. 检查签名 / 公证 secrets，缺一个就失败。
2. 把 `APPLE_CERTIFICATE` 导入临时钥匙串，并校验 `APPLE_SIGNING_IDENTITY` 确实存在。
3. 把 `APPLE_API_KEY_P8` 写成 `AuthKey_<KeyID>.p8`。
4. 运行 `./scripts/package.sh`：
   - `xcodebuild` 构建未签名 Release 包
   - `codesign --options runtime --timestamp` 用 Developer ID 签名
   - 打包 zip 提交 notarytool，通过后 `stapler staple` 到 App
   - 用已装订的 App 生成 DMG，签名并再次公证、装订
   - 生成 ZIP 和 `SHA256SUMS.txt`
5. 用 `codesign` / `stapler` / `spctl` 复核，然后创建 GitHub Release 并上传三个文件。

## 发版

```bash
# 确认项目能构建
./scripts/run.sh

git tag v1.1.0
git push origin v1.1.0
```

tag 会触发 Release。版本号自动取 tag 去掉 `v` 的部分，写入
`CFBundleShortVersionString`；`CFBundleVersion` 使用 GitHub run number。

## 本地验证签名

不经过 CI，直接用钥匙串里的证书和 API Key 打一次包：

```bash
export APPLE_SIGNING_IDENTITY="Developer ID Application: 你的名字 (TEAMID)"
export APPLE_API_KEY="XXXXXXXXXX"
export APPLE_API_ISSUER="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export APPLE_API_KEY_PATH="$HOME/private_keys/AuthKey_${APPLE_API_KEY}.p8"

./scripts/package.sh
```

或者用 notarytool 的 keychain profile（先 `xcrun notarytool store-credentials`）：

```bash
export APPLE_SIGNING_IDENTITY="Developer ID Application: 你的名字 (TEAMID)"
export NOTARY_PROFILE="tomato-notary"
./scripts/package.sh
```

检查产物：

```bash
APP="dist/dmg-root/番茄钟.app"
codesign --verify --deep --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"

xcrun stapler validate "dist/TomatoTimer.dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "dist/TomatoTimer.dmg"
```

## 常见问题

**`APPLE_SIGNING_IDENTITY not found`**
证书导入成功但名字对不上。跑 `security find-identity -v -p codesigning`，
Secrets 里要用完整字符串，包括 `Developer ID Application: ` 前缀和括号里的 Team ID。

**`errSecInternalComponent` 或签名时卡住**
钥匙串没解锁或缺少 partition list。workflow 已经做了 `security set-key-partition-list`，
本地手动签名时也要先 `security unlock-keychain`。

**公证返回 `Invalid`**
用 `xcrun notarytool log <submission-id> --key ...` 看具体原因。常见原因：
没有 Hardened Runtime、没有安全时间戳、bundle 里有未签名的可执行文件。
本项目在 `scripts/package.sh` 里已经固定使用 `--options runtime --timestamp`。

**`spctl` 拒绝但 `stapler validate` 通过**
先确认 `codesign -dv` 里的 Authority 是 `Developer ID Application` 而不是 ad-hoc；
再确认公证是针对当前这个 App / DMG 提交的。改了代码就必须重新签名 + 重新公证。

**用户仍然看到「已损坏」**
通常是下载链路改动了文件（比如经过某些网盘 / 编辑器），或者用户系统时间不对。
可以让用户先校验 `shasum -a 256`，或执行
`xattr -dr com.apple.quarantine /Applications/番茄钟.app` 临时绕过。
