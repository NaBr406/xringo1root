> **免责声明：** 本项目仅用于合法授权的安全研究、漏洞复现和防御性验证。内容包含可能改变设备安全状态、导致数据丢失、崩溃或无法启动的实验代码与记录；使用者须自行确认设备和环境已获授权并承担全部风险。项目不提供任何稳定性、安全性、适用性或法律合规保证，也不鼓励在他人设备、生产环境或未充分备份的设备上操作。

> **证据口径：** 文档分别记录静态分析、模拟器/KASAN 复现、设备只读采集和实机执行；其中任一层级都不自动证明其他层级成立。历史日志只代表采集时点，`active`、`running` 或进程返回成功也不等同于获得 root、完成利用或实现稳定性。

# xringo1root

面向 **XRing O1 / dijun** 的 Android 临时 root 研究项目，包含原生代码移植、`o1p Root` Android 客户端、内核分析脚本和实验记录。

项目基于已有研究与开源代码进行设备适配。感谢 [zsw125/o3root](https://github.com/zsw125/o3root) 提供的部分方案、原生实现和参考文档，也感谢 [RikkaApps/Shizuku](https://github.com/RikkaApps/Shizuku) 提供的无线 ADB 配对、连接等方案与相关源码。

## 当前状态

- Android 客户端：`o1p Root`，包名 `o1.st.shell`，支持无线调试配对、配对码悬浮窗/通知输入、rootd 通信、命令执行及应用授权。
- 设备适配：现有记录针对 `dijun / 25042PN24C`、`OS4.0.0.19.XODCNXM`。其他设备和系统版本未经本项目验证。
- 研究记录：包含内核镜像提取、静态分析、模拟器 KASAN 日志及修复前后对照。
- root 方案：历史记录中已有临时 root 成功结果；仅当前启动周期有效，仍存在失败及内核崩溃记录。
- KernelSU：保留了模块适配实验，尚不能据此宣称稳定可用。

当前仓库是研究工作区的源码归档，不是开箱即用的发行版。文档和日志记录的是当时的结果，不代表设备当前状态，也不保证其他环境能够复现。

## 实机与 boot 版本

2026-10-29 已通过 ADB 只读核对当前实机：

| 项目 | 读数 |
| --- | --- |
| 设备 / SoC | Xiaomi `25042PN24C`（`dijun`）/ XRing O1 |
| 系统 | `OS4.0.0.19.XODCNXM`，Android 17 / SDK 37 |
| Boot image 构建指纹 | `Xiaomi/missi/missi:17/CP2A.260605.016/17OS4.0.260920.221408987.XRPECN.S:user/release-keys` |
| 运行内核 | `6.18.21-android17-5-g1d099fcb35e0-abogki538445360-4k` |
| 启动状态 | 槽位 `_b`，bootloader locked，AVB green |
| 当前 SELinux | `Permissive`（不同于早期报告中的 Enforcing） |

研究用 `boot.img` 从同版本 OTA 提取，header v4，大小 96 MiB。本地内核镜像的版本串与实机 `/proc/version` 一致；直接读取实机 boot 分区哈希仍被拒绝，尚未确认镜像逐字节一致。

完整系统/vendor 指纹、镜像 SHA-256、采集证据及历史状态区别见 [实机版本页](docs/DEVICE-dijun.md)。

## 目录

| 路径 | 内容 |
| --- | --- |
| `apk/src/` | Android 界面与启动流程源码 |
| `apk/vendor-src/` | 从实际 WSL 构建环境保存的 ADB Kotlin 源码及适配代码 |
| `o3root-port/` | 基于 o3root 的原生移植及相关工具 |
| `o3root-port/experiments/` | 原 build 目录中的实验源码与脚本 |
| `o3root-ref/` | 上游文档和脚本参考快照 |
| `wsl/` | 历史构建、内核分析和实验脚本 |
| `ab-logs/` | 实验与对照验证的文本日志 |
| `licenses/` | 第三方许可证及上游声明 |

## 文档入口

- [o1p Root 使用说明](docs/o1p-USAGE.md)
- [实机配置、boot 版本和镜像校验值](docs/DEVICE-dijun.md)
- [工作区归档与构建边界](docs/WORKSPACE.md)
- [研究报告与验证记录](REPORT.md)
- [dijun 移植记录](PORT-dijun.md)
- [o3root 方案对照](O3ROOT-REFERENCE.md)
- [临时 root 与客户端历史记录](ROOT-WITHOUT-KSU.md)
- [第三方来源和著作权说明](THIRD_PARTY_NOTICES.md)

历史文档中的 `o3p` 命名、旧包名、路径和参数可能与当前代码不同，阅读时请结合源码及文档日期。

## 构建说明

Android 部分采用 SDK 命令行工具链，入口为 `apk/build.ps1`，没有使用 Gradle。现有环境使用 Android SDK 35、Build Tools 35.0.0 和 JDK 24。

该脚本编译 Java，但依赖预先生成的 Kotlin class。历史 Kotlin 编译与暂存流程见 `wsl/65_stage_kotlin.sh`；对应源码已归档到 `apk/vendor-src/`，脚本尚未改造成基于干净克隆的完整构建流程。

SDK/JDK 路径、WSL 目录和部分依赖仍需按环境调整。APK 所需的 JAR、JNI 库、原生产物和签名密钥未纳入当前源码树。不要将 `wsl/` 下的编号脚本视为可依次执行的安装程序。

本项目包含可能改变设备安全状态的实验代码。仅用于本人拥有或明确获授权的测试设备；执行前请备份数据，并了解相关操作可能导致崩溃或重启。

## 致谢与著作权

### o3root

感谢 **zsw125 及 O3Root contributors**。本项目的部分原生实现、适配思路和参考资料来自 [o3root](https://github.com/zsw125/o3root)，其中 `o3root-port/o3p.c` 是在上游实现基础上的移植，并非本项目从零独立实现。

上游自有代码采用 MIT 许可证，原版权声明及许可全文保存在 [licenses/o3root-LICENSE](licenses/o3root-LICENSE)。上游第三方声明另行保留，不能把 MIT 许可扩大到其所有依赖。

### Shizuku

感谢 **RikkaApps 和 Shizuku 的作者、贡献者**。本项目使用了 Shizuku 的部分无线 ADB 配对与连接方案，并复用了其 manager 中的相关 Kotlin 源码，包含本地适配。具体文件、来源版本及修改状态见 [第三方说明](THIRD_PARTY_NOTICES.md)。

这些上游源码遵循 Apache License 2.0，许可全文保存在 [licenses/Shizuku-LICENSE](licenses/Shizuku-LICENSE)。本项目与 Shizuku、o3root 均无官方隶属关系，致谢不表示上游认可或担保本项目。

### 许可范围

第三方代码及文档的著作权仍归各自权利人所有，相关许可、署名和修改说明应随再分发保留。本仓库目前未为新增原创部分指定统一的开源许可证；不能将第三方 MIT 或 Apache-2.0 许可自动套用到整个仓库。致谢不替代许可证要求。
