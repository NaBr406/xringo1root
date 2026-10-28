# 工作区归档说明

整理日期：2026-10-29。此次提交保存现有工作，不代表重新完成真机验证。

## 目录

- `apk/src/`：当前 o1p Root Android 界面及 Bootstrap 源码。
- `apk/vendor-src/`：从 Ubuntu WSL 的 `/root/port/adb` 保存的实际 Kotlin 构建输入；与 `apk/src/` 中的旧副本分开保留。
- `apk/build.ps1`：现有 Windows SDK 命令行构建入口。
- `o3root-port/`：原生移植源码及符号表。
- `o3root-port/experiments/`：从 build 目录抢救出的 C 源码及脚本，保留实验版本名，不指定某版为最终实现。
- `wsl/`：历史构建、分析和实验脚本；编号反映工作过程，不是需要依次执行的安装流程。
- `ab-logs/`：文本验证记录；不包含大型测试内核镜像。
- `o3root-ref/`：上游参考文档及脚本快照。
- 根目录 Markdown：历史研究报告和设备操作记录，内容可能落后于当前代码。

## 构建边界

当前不是从干净克隆一键构建的发行版。`apk/build.ps1` 编译 Java 并消费 `apk/kout`，不会编译 Kotlin；历史 Kotlin 编译流程见 `wsl/65_stage_kotlin.sh`。SDK、JDK 和 WSL 路径仍保留原环境配置。

APK 依赖 Kotlin/Bouncy Castle JAR、JNI `libadb.so`、assets 原生产物及预编译 Kotlin class。这些二进制仅保留在原工作区，没有提交。原生载荷和 KernelSU 模块也未作为发行包上传。

设备镜像、设备转储、签名密钥、APK、编译产物和历史截图由 `.gitignore` 排除，本地原文件未删除。日志和报告是历史快照，不证明当前设备状态或当前上游补丁状态。

## 第三方来源

- 原生移植及 `o3root-ref/` 来源： https://github.com/zsw125/o3root 。对应关系见根目录 `O3ROOT-REFERENCE.md`。本次未为整个项目指定新的开源许可证。
- ADB Kotlin 代码来自本地 Shizuku checkout，提交 `b844bc491f1790c72328e1a8e5b2349f8978f0ea`，并包含已有本地适配。随附 `licenses/Shizuku-LICENSE`（Apache-2.0）；该许可证不自动覆盖本仓库其他代码。
