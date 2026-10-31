# FNTV for iPad 1

面向初代 iPad / iOS 5.1.1 的实验性原生飞牛影视客户端，使用 Objective-C、UIKit 和系统播放器。**这是个人开发的非官方客户端，与飞牛影视及其厂商没有关联、授权或背书。** FNTV/飞牛影视名称仅用于说明兼容目标。

它直接连接你自己的 NAS，日常使用不需要 Mac 中转。应用内的 HLS 适配器仅监听设备回环地址，通过随机会话路径向系统播放器提供内容；它不是远程控制服务。

## 功能

- 配置 NAS 地址、登录、退出登录；令牌保存在应用自己的 Keychain 访问组中，密码不保存。
- 媒体库选择、海报、分页、搜索、电影详情、目录浏览、电视剧季与集选择。
- 系统播放器的播放、暂停、拖动、音量和返回；记录播放进度、继续播放及从头播放。
- 登录过期、网络失败、签名失败和不兼容媒体的可恢复提示。
- 针对旧设备限制海报下载、解码尺寸、缓存和并发；HLS 地址注册表保留已验证的查找性能改进。

界面主要为简体中文。当前没有离线下载、直播、媒体库编辑、遥测、云端中转或自动更新功能。

## 运行条件与边界

需要 ARMv7 初代 iPad、iOS 5.1.1，以及你已经配置好的越狱与兼容 AppSync 环境。此仓库不提供越狱、解锁或设备控制工具，也不通过 App Store 分发。你需要有权访问的 NAS 和飞牛影视账号；正常播放会创建转码会话并更新观看进度。

iOS 5 的系统 TLS 与解码能力有限，NAS 必须能提供设备支持的连接和 HLS 音视频流。项目不绕过证书校验；如果使用 HTTP，登录和媒体流不具备传输加密，只应在你信任的网络中使用。不要把 NAS 管理端口直接暴露到公网来解决连接问题。

此前的应用核心在一台 iPad 1 / iOS 5.1.1 与一套 NAS 环境中经过实际使用确认，覆盖声音、流畅播放、暂停/继续、拖动到影片中段及退出重开后的续播。**本公开版替换了全部内置美术资源，并默认关闭诊断功能；公开版构建通过不等于已重新完成真机验收。** 尚未覆盖所有服务器版本、编码/封装/码率、媒体库排列、长时间播放或热稳定性。

## 从源码构建

需要 macOS、提供 `clang` 与 `ld-classic` 的 Xcode、Python 3.9+、CMake、Ninja，以及你自行取得且有权使用的 **iPhoneOS9.3 SDK**。SDK 必须包含 ARMv7 库和 `usr/lib/crt1.3.1.o`。仓库不包含、也不会自动下载 Apple SDK。

已验证的本机构建工具版本为 Xcode 26.5、Python 3.13、CMake 4.4、Ninja 1.13。其他版本需要自行验证，尤其是 `ld-classic` 与旧 ARMv7 支持。

```sh
# 克隆后在仓库根目录运行
export SDK_PATH="/path/to/iPhoneOS9.3.sdk"
./build.sh
```

构建脚本会：

1. 将 SDK 克隆复制到 `build/sdk/iPhoneOS9.3.sdk`，只修改这个副本里的链接声明：整理混合模拟器架构、处理缺失的空 liblaunch 声明、补齐已在 iOS 5 上验证的 libc 别名，并让六个 URL 类绑定到 iOS 5 的 Foundation。原 SDK 不改动；复制使用 macOS 的 APFS clone 功能。
2. 从官方 WebM 下载地址获取 libwebp **1.6.0**，校验 SHA-256 `e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564`，仅构建静态解码器。上游源码与缓存均位于忽略的 `build/webp/`。
3. 编译 ARMv7 / iOS 5.1、手动引用计数的应用，保留 iOS 5 必需的 `LC_UNIXTHREAD` 启动方式，执行 SHA-1 + SHA-256 ad hoc 签名。
4. 检查 Mach-O 架构、最低系统版本、Foundation 绑定、资源尺寸/哈希、许可证和默认诊断关闭状态，生成 `build/FNTV.ipa`。

SDK 路径或准备脚本变化时，旧副本会被拒绝复用；删除 `build/sdk/` 后重试。如果原 SDK 内容在同一路径被替换，也请先删除这个构建副本。所有 `build/` 内容都可以重新生成。

首次构建需要联网下载 libwebp。离线构建可以先把官方的同版本压缩包放到 `build/webp/libwebp-1.6.0.tar.gz`；构建仍会检查相同哈希。本次公开版验证时官方域名在本机无法解析，因此使用已留存且哈希一致的官方包完成离线构建；在线下载流程尚未在该次验证中成功完成。

输出的 IPA 只在本地产生，仓库不附带安装包。用你现有且兼容 iOS 5/AppSync 的安装方式安装；构建脚本不会连接设备。默认 bundle ID 为 `ink.sunrui.fntv.ipad1`，与 Keychain entitlement、令牌服务名配套；它是公开应用标识，不是账号或凭据。修改它时需要同步相关配置，并会影响已有登录会话。

## 测试

不连接 NAS、不操作 iPad的主机测试：

```sh
python3 Tests/test_prepare_sdk.py
python3 Tests/run-network-tests.py
bash Tests/run-ui-tests.sh

# 完成一次 build.sh 后，测试同一固定版本解码器
bash Tests/run-webp-tests.sh
```

覆盖合成 SDK 修复及原文件保护、登录版本分支与 SHA-256、请求签名、同源/重定向/大小限制、HLS 改写、随机路径、Range 流、取消与会话隔离、诊断文件边界、播放器控制流程及音频会话清理。WebP 测试验证合成有损/无损图片缩放、像素校验和、截断拒绝。UI 测试使用最小框架替身；它们检查控制流程，不能证明实际视频画面、声音或触摸行为。

`build.sh` 自动运行 `Tests/verify_bundle.py`。首次真机运行后仍应手工检查登录、海报、搜索、目录/季/集、播放/暂停/拖动/续播、快速返回、前后台切换与退出登录。

## 诊断构建

普通构建的 `FNTV_DIAGNOSTICS` 默认为 `0`，不包含诊断登录导入、前台自动播放检查、只读检查文件输出、代理性能报告或音频释放日志。需要诊断时可以显式运行：

```sh
FNTV_DIAGNOSTICS=1 SDK_PATH="/path/to/iPhoneOS9.3.sdk" ./build.sh
```

诊断构建只支持固定的应用内检查，不接受远程命令：

- 登录页可消费 `Documents/.fntv-test-login.json`：仅限 0600 的普通文件、最多 16 KiB，三个字符串字段为 `server`、`username`、`password`。文件在提交前删除；删除失败不提交。如果登录页没有出现，文件不会消费，需自行清理。
- `Documents/.fntv-player-smoke.json` 只接受 `{"schema":1,"action":"foreground-movie-smoke"}`，必须为 0600 普通文件、最多 1 KiB、五分钟内创建。它可能启动首个可见电影的正常播放，并通过正常退出更新观看进度。命令先消费，再执行；有 60 秒总截止时间。
- 设置应用偏好 `FNTVRunReadOnlySelfCheck` 可以触发一次只读库/详情/海报及 Keychain 检查。输出的 `FNTV-selfcheck.json`、`FNTV-player-smoke.json` 和 `FNTV-proxy-metrics.json` 只记录受限的状态/统计，不输出账号、令牌、服务器地址、媒体标题或媒体 ID。

诊断不会调节系统音量。时间推进的数值不能证明画面流畅或有声音；应结合实际观察。不要提交任何真实设备诊断文件或登录资料。

## 源码与许可

- `Sources/Networking/`：直接 NAS 请求、签名、Keychain 会话、图片和 HLS 适配。
- `Sources/UI/`：UIKit 界面、系统播放器、音频会话与可选诊断。
- `Assets/`：本项目原创美术资源、尺寸/哈希清单及许可证。可用 `swift Tools/generate-assets.swift` 重新生成；普通构建直接使用仓库中的 PNG。
- `Tests/`：合成请求、图片与主机回归；来源说明见 [Tests/Fixtures/README.md](Tests/Fixtures/README.md)。

本项目原创源码和美术资源按 [MIT License](LICENSE) 提供。libwebp 使用 BSD 3-Clause 许可及其专利授权，完整文字位于 [Assets/libwebp-LICENSE.txt](Assets/libwebp-LICENSE.txt)，并随本地构建的应用打包。本仓库不含官方客户端 APK、厂商美术资源、Apple SDK、真实 NAS 数据或设备日志。
