# Pulse 发布（公证直装）

macOS 14+、单 Target、bundle id `com.qqzhangyanhua.pulse`、版本 `0.1.0`（`CFBundleVersion` `1`）。分发是 **Developer ID + notarytool + stapler**，不是 Mac App Store。沙盒保持关闭，`Pulse/Pulse.entitlements` 保持空 dict。Hardened Runtime 已在工程打开。

本仓库不存放证书、Team ID、Apple ID 或 app 专用密码。没有 Developer ID Application 证书时，`scripts/notarize.sh` 会在 archive 之前退出。

本地 Debug 冒烟继续用工程里的 ad-hoc：`CODE_SIGN_IDENTITY = "-"`（Debug 与 Release 都是这个值，方便没有证书的机器 Run）。公证脚本只在自己的那次 `xcodebuild archive` 上覆盖身份，不改工程文件。

## 环境变量

| 变量 | 何时需要 | 说明 |
| --- | --- | --- |
| `DEVELOPMENT_TEAM` | 公证必填 | 10 位 Team ID（大写字母与数字）。不要写入仓库。 |
| `NOTARY_KEYCHAIN_PROFILE` | 与下面二选一 | 推荐。由 `notarytool store-credentials` 写入登录钥匙串。 |
| `APPLE_ID` | 未使用钥匙串配置时必填 | Apple ID。 |
| `APPLE_APP_SPECIFIC_PASSWORD` | 未使用钥匙串配置时必填 | app 专用密码。只放在环境里，不要进 argv 历史以外的文件，更不要提交。 |
| `APPLE_TEAM_ID` | 可选 | 默认等于 `DEVELOPMENT_TEAM`。若设置，必须相同。 |
| `CODE_SIGN_IDENTITY` | 多张 Developer ID 证书时必填 | 完整名称，例如 `Developer ID Application: Name (TEAMID)`。不要设成 `-`。 |

只配了一张本 Team 的 Developer ID Application 时，可以不设 `CODE_SIGN_IDENTITY`，脚本会选中它。

## 1. 本地冒烟（不公证）

在 macOS 14+、Xcode 15+ 上打开 `Pulse.xcodeproj`，Scheme 选 Pulse，Run。Signing Team 可以留空。

冷启动应落在内存页。逐项检查见 [TECH.md「本机冒烟清单」](TECH.md#本机冒烟清单)，范围见 [PRD](PRD.md)。这一步的包是 ad-hoc，不能当直装包发出去。

## 2. 安装 Developer ID 证书

需要 **Developer ID Application**（不是 Apple Development，也不是 Mac App Store 的分发证书）。装进登录钥匙串后：

```bash
security find-identity -v -p codesigning
```

输出里要有一行 `Developer ID Application: 名字 (TEAMID)`，且括号中的 Team ID 就是 `DEVELOPMENT_TEAM`。

## 3. 把公证凭据放进钥匙串（推荐）

在 [appleid.apple.com](https://appleid.apple.com) 生成 app 专用密码，然后：

```bash
export APPLE_APP_SPECIFIC_PASSWORD='app-specific-password'
xcrun notarytool store-credentials "pulse-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "@env:APPLE_APP_SPECIFIC_PASSWORD"
unset APPLE_APP_SPECIFIC_PASSWORD
```

之后只需：

```bash
export DEVELOPMENT_TEAM=TEAMID
export NOTARY_KEYCHAIN_PROFILE=pulse-notary
```

不用钥匙串配置时，改为导出 `APPLE_ID` 与 `APPLE_APP_SPECIFIC_PASSWORD`。脚本把密码以 `@env:APPLE_APP_SPECIFIC_PASSWORD` 交给 `notarytool`，不会把它写进 `exportOptions` 或日志参数。不要用 `bash -x` 跑脚本。

## 4. 预检

```bash
./scripts/notarize.sh --preflight
```

Team、钥匙串身份或公证凭据缺任何一项，这里就会失败，并且不会开始 archive。

## 5. Archive → 导出 → 公证 → 装订

```bash
./scripts/notarize.sh
```

脚本依次做：

1. 确认本机是 macOS，且 `DEVELOPMENT_TEAM`、Developer ID Application 身份、公证凭据都在。
2. `xcodebuild archive`（scheme `Pulse`，configuration `Release`）。这次构建覆盖为手动签名：指定的 Developer ID、`ENABLE_HARDENED_RUNTIME=YES`、`ENABLE_APP_SANDBOX=NO`、`CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`，entitlements 仍是 `Pulse/Pulse.entitlements`。
3. 写一份临时的 export options（`method` = `developer-id`，`signingStyle` = `manual`）到 `build/export/exportOptions.plist`，再 `xcodebuild -exportArchive`。
4. 若 export 因描述文件失败，脚本会把失败打出来，并用同一身份对 archive 里的 `Pulse.app` 执行 `codesign --options runtime --timestamp`。App 不开沙盒、entitlements 为空，不需要 Mac App Store 描述文件。
5. `ditto` 打 zip，`xcrun notarytool submit --wait`。
6. `xcrun stapler staple` / `stapler validate`，再用 `spctl --assess --type execute` 看 Gatekeeper。

成功后的路径：

```text
build/export/Pulse.app
build/Pulse.zip
```

`build/` 已在 `.gitignore`，不要把 archive、zip 或 export options 提交上来。

装到本机：

```bash
ditto "build/export/Pulse.app" /Applications/Pulse.app
```

常用开关：

| 开关 | 作用 |
| --- | --- |
| `--preflight` | 只检查，不 archive |
| `--archive-path PATH` | 默认 `build/Pulse.xcarchive` |
| `--export-dir PATH` | 默认 `build/export` |
| `--skip-archive` | 用已有 archive 再导出并公证 |
| `--skip-export` | 直接公证 `build/export/Pulse.app` |
| `--app PATH` | 公证指定的、已经用 Developer ID 签过的 `.app` |

## 6. 可选 DMG

磁盘镜像里是 `Pulse.app` 和指向 `/Applications` 的替身，方便拖进去安装。App 必须已经是 Developer ID 签名（先跑 `notarize.sh`）。

```bash
./scripts/make-dmg.sh
./scripts/make-dmg.sh --notarize
```

默认产物：`build/Pulse-0.1.0.dmg`（版本读自 app 的 `CFBundleShortVersionString`）。`--notarize` 会用同一套环境变量提交 DMG 并 `stapler staple`。发出去的 DMG 用带 `--notarize` 的那一份。

## 7. 在 Xcode 里做同样的事

1. Scheme Pulse → Any Mac → Product → Archive（Release）。若仍要在 Organizer 里签名，把这次 archive 的签名设成 Developer ID Application，并填 `DEVELOPMENT_TEAM`。不要把 `CODE_SIGN_IDENTITY=-` 留在你要公证的那份包上。
2. Distribute App → Developer ID → Export。
3. 对导出的 `Pulse.app` 打 zip 后：

```bash
ditto -c -k --keepParent Pulse.app Pulse.zip
xcrun notarytool submit Pulse.zip --keychain-profile "pulse-notary" --wait
xcrun stapler staple Pulse.app
xcrun stapler validate Pulse.app
spctl --assess --type execute --verbose=4 Pulse.app
```

## 出货前再对一遍

用装订后的 `/Applications/Pulse.app` 跑一遍 [TECH.md「本机冒烟清单」](TECH.md#本机冒烟清单)，不要只看 Debug ad-hoc 包。另外确认：

- 首次打开没有 Gatekeeper 拦截，`spctl --assess` 通过
- 关掉主窗后菜单栏仍在，`⌘Q` 能退出
- 典型路径约 30 秒能定位并退出（见 [PRD](PRD.md)）

采样间隔、权限模型和界面不要为了发版改。公证完成前，Hardened Runtime 的本地包只用于自测。
