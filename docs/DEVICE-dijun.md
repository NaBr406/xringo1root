# dijun 实机版本与 boot 镜像

最近核对：**2026-10-29（UTC+08:00）**。通过已连接设备的普通 ADB shell 只读采集，未运行载荷、切换安全状态、重启或写入分区。可审计字段与命令结果见 [JSON 快照](device/dijun-2026-10-29.json)，未收录设备序列号。

## 实机配置

| 项目 | 当前读数 |
| --- | --- |
| 厂商 / 型号 | Xiaomi / `25042PN24C` |
| 产品名 / 设备代号 | `dijun` / `dijun` |
| SoC / 平台 | XRing O1 / `O1_asic` |
| ABI | `arm64-v8a` |
| 系统版本 | `OS4.0.0.19.XODCNXM` |
| Android / SDK | 17 / 37 |
| Build ID | `CP2A.260605.016` |
| 系统 / vendor 安全补丁日期 | 均为 `2026-09-01` |
| 构建类型 | `user` / `release-keys`，`ro.debuggable=0` |
| 内核 | `6.18.21-android17-5-g1d099fcb35e0-abogki538445360-4k` |
| 内核构建时间 | `Tue Jul 28 13:29:24 UTC 2026` |
| 内存页大小 | 4096 字节 |
| 内核可见总内存 | `15958384 kB`（`/proc/meminfo`，不是标称物理容量） |
| 当前启动槽位 | `_b` |
| boot 分区映射 | `boot_a → /dev/block/sdc17`；`boot_b → /dev/block/sdc49` |
| Bootloader / AVB 状态 | `vbmeta.device_state=locked`、`flash.locked=1`、`verifiedbootstate=green` |
| verity / AVB 版本 | `enforcing` / `1.4` |
| 当前 SELinux | **Permissive** |
| 本次 ADB shell 身份 | `uid=2000(shell)`，`u:r:shell:s0` |
| 已安装客户端 | `o1.st.shell`，versionName `2.0`，versionCode `2` |

`ro.boot.bootloader` 和 `ro.bootimage.build.version.security_patch` 返回空值，未据此推测 bootloader 版本或 boot image 补丁日期。verity enforcing 与 SELinux Permissive 是不同机制的读数，不矛盾。普通 ADB shell 为 uid 2000 也不能证明设备没有其他 root 进程；本次未复测 rootd 权限。

## 系统、boot image 与 vendor 指纹

这些属性来自不同构建部分，不能互相替代：

**系统（`ro.build.fingerprint`）**

```text
Xiaomi/dijun/dijun:17/CP2A.260605.016/OS4.0.0.19.XODCNXM:user/release-keys
```

**Boot image（`ro.bootimage.build.fingerprint`）**

```text
Xiaomi/missi/missi:17/CP2A.260605.016/17OS4.0.260920.221408987.XRPECN.S:user/release-keys
```

**Vendor（`ro.vendor.build.fingerprint`）**

```text
Xiaomi/dijun/dijun:15/AP3A.240905.015.A2/OS4.0.0.19.XODCN:user/release-keys
```

以上保留实机属性原值；vendor 指纹中的 `15` 不表示当前 Android 系统版本为 15。Boot image 属性是构建标识，不是分区内容的哈希证明。

## 本地研究使用的 boot 镜像

原工作区中的 `boot.img` 来自同系统版本的官方 OTA 提取，提取过程见 [REPORT.md](../REPORT.md) 和 [extract_boot.py](../extract_boot.py)。本次重新计算了本地镜像哈希并解析 Android boot header。

- OTA 文件：`dijun-ota_full-OS4.0.0.19.XODCNXM-user-17.0-aa6a58e947.zip`。
- [历史提取所用 OTA 地址](https://bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com/OS4.0.0.19.XODCNXM/dijun-ota_full-OS4.0.0.19.XODCNXM-user-17.0-aa6a58e947.zip)（本次未重新下载）。
- `boot.img`：100,663,296 字节（96 MiB）；magic `ANDROID!`；header v4。
- 内核起始偏移：4096；内核大小：42,936,832 字节。

| 文件 | 本次重新计算的 SHA-256 |
| --- | --- |
| `boot.img` | `8563cbf6f196daec15e23f773276dd811b023b6f76df1953b24af4d1b5066f07` |
| `kernel_image.bin` | `0d9917ca00657798e258889e258931b8b1fb0b2bbb8c0ad90e8c89ce517da0ac` |

从本地内核镜像提取的完整 `Linux version ...` 字符串与当前实机 `/proc/version` 一致（忽略末尾换行），包括构建工具链和时间。完整字符串保存在 JSON 快照中。

**核验边界：**本次尝试读取当前 `boot_b` 分区的 SHA-256，普通 ADB shell 返回 `Permission denied`。因此已确认的是系统版本和内核版本串对应，尚未通过分区哈希确认本地 `boot.img` 与实机 `boot_b` 逐字节一致。本次没有为补文档启用或调用提权通道。

镜像保留在本地，未随此文档提交。

## 与历史记录的关系

[REPORT.md 第 5 节](../REPORT.md#5-设备指纹只读采集) 保存了 2026-10-28 的早期状态，其中 SELinux 为 Enforcing。本次采集为 Permissive，故不直接覆盖历史报告。[PORT-dijun.md](../PORT-dijun.md) 中的 root 成功结果也属于历史实验记录。

上述信息只描述这台设备和这个构建，不能作为其他固件、其他机型或当前漏洞修复状态的兼容性结论。
