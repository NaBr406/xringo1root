# 第三方来源、许可与修改说明

核对日期：2026-10-29。本文件用于记录来源和许可范围，不替代许可证原文。未核实的来源版本不作推定。

## o3root

- 上游：[zsw125/o3root](https://github.com/zsw125/o3root)。
- 原版权声明：`Copyright (c) 2026 O3Root contributors`。
- 上游自有代码许可：MIT；全文见 [o3root-LICENSE](licenses/o3root-LICENSE)。
- 本次许可证及 NOTICE 核对版本：[`f59f4baf5d6e5449e5dbec060eaa0de16885ad27`](https://github.com/zsw125/o3root/tree/f59f4baf5d6e5449e5dbec060eaa0de16885ad27)。这是声明的取样版本，不代表本项目最初移植时使用的精确提交；后者尚未记录。
- 保留的上游声明：[英文 NOTICE](licenses/o3root-NOTICE.md)、[中文 NOTICE](licenses/o3root-NOTICE.zh-CN.md)。这两份文件中的“本仓库”指上游 o3root，不表示本仓库包含其列举的所有组件。

| 本地范围 | 来源及修改说明 |
| --- | --- |
| `o3root-port/o3p.c` | 基于上游 `payload/o3p.c` 移植；含 dijun 适配及本地 rootd/授权等改动，不是上游原样副本 |
| `o3root-port/mk_payload.py`、`o3root-port/ksu/ksu_symtab.h` | 从上游载荷工具和符号表引入；不宣称本地快照与当前上游逐字一致 |
| `o3root-ref/` 中的文档和脚本 | 上游资料的本地参考快照，保留原作者权利；文件名为归档形式 |

移植过程见 [O3ROOT-REFERENCE.md](O3ROOT-REFERENCE.md) 和 [PORT-dijun.md](PORT-dijun.md)。这些历史记录不是完整的逐行来源审计。上游 NOTICE 中的研究先例和其他组件署名一并保留，不将相关工作重新归为本项目原创。

## Shizuku

- 上游：[RikkaApps/Shizuku](https://github.com/RikkaApps/Shizuku)。
- 来源提交：[`b844bc491f1790c72328e1a8e5b2349f8978f0ea`](https://github.com/RikkaApps/Shizuku/tree/b844bc491f1790c72328e1a8e5b2349f8978f0ea)。
- 上游目录：`manager/src/main/java/moe/shizuku/manager/adb/`。
- 本地目录：`apk/vendor-src/moe/shizuku/manager/adb/`。
- 许可：Apache License 2.0；完整文本见 [Shizuku-LICENSE](licenses/Shizuku-LICENSE)。原作品权利归 Shizuku 作者及贡献者；本项目不为上游补造未经核实的版权年份或个人署名。

以下状态通过本地上游 checkout 与导入文件比较确认，描述的是本次追加来源注释之前的代码内容：

| 文件 | 导入状态 |
| --- | --- |
| `AdbClient.kt` | 已修改 |
| `AdbKey.kt` | 已修改 |
| `AdbMdns.kt` | 已修改 |
| `AdbPairingClient.kt` | 已修改 |
| `AdbException.kt` | 与来源文件一致 |
| `AdbMessage.kt` | 与来源文件一致 |
| `AdbProtocol.kt` | 与来源文件一致 |

上述文件现均附有来源注释，修改文件另有明确的修改声明。`ConscryptCompat.kt` 和 `Observer.kt` 是本地构建中的兼容辅助文件；对应上游目录中没有同名文件，不把它们列为逐文件直接复制的上游源码。`apk/src/` 下同名辅助类是历史副本。

已核对该 Shizuku 提交的根 LICENSE 和 README，未发现独立 NOTICE 文件。上游 README 另有限制品牌使用的说明：本项目不采用其启动图标、应用名称、application ID 或受限权限名称。内部源码包名用于保留来源及引用关系，不表示官方关联。

## 构建依赖与二进制

历史构建还使用 Kotlin、Bouncy Castle、Android SDK、ADB JNI 库以及 KernelSU 系列实验产物。当前源码树没有附带这些第三方二进制，不能把它们视为已被本文件统一授权。发布 APK、JNI 库或内核模块前，应针对实际包含的版本补齐许可证、来源和适用的源码提供材料。

归档历史中的首个提交曾包含 `apk/assets/su_arm64`，后续提交已从当前树移除；这不等于清除了 Git 历史中的二进制。当前仓库仍为私有研究归档，不将其描述为已经完成全量发行合规审核。

## 本项目新增部分

暂未指定覆盖所有新增原创部分的统一许可证。第三方文件继续按各自许可处理；署名不意味着取得额外授权，也不意味着上游为本项目背书。
