# KernelSU 安装手册（dijun，CVE-2026-98260 + 自编 LKM）

设备：`25042PN24C` / `dijun`，HyperOS `OS4.0.0.19.XODCNXM`，
内核 `6.18.21-android17-5-g1d099fcb35e0-abogki538445360-4k`。

## 产物

| 文件 | 说明 |
|---|---|
| `o3root-port/build/o3p_ksu_v331.bin` | 载荷 + 自编 KernelSU v3.3.1 LKM（1.14 MB，v1 单 LKM 布局） |
| `o3root-port/lkm/ksu-dijun-v331.ko` | 单独的内核模块（1.07 MB，已 strip） |
| `o3root-port/KernelSU-manager.apk` | 官方 v3.3.1 管理器（13 MB） |

## LKM 是怎么来的（与之前失败版本的区别）

| | 之前 | 现在 |
|---|---|---|
| 来源 | o3root 仓库预编译 | 从 `tiann/KernelSU` **v3.3.1 源码**自编 |
| 构建内核 | 6.18.32-4k（别人的） | GKI `android17-6.18` + **本机 config**，结构偏移经 BTF 比对与设备一致（`cred` 0x908 / `posix_cputimers` 0x868 / `real_cred` 0x900） |
| vermagic | `6.18.32-4k-g47cc22554442-dirty ...` | `6.18.21-android17-5-g1d099fcb35e0-abogki538445360-4k SMP preempt mod_unload modversions aarch64`（逐字一致） |

构建要点（复现用）：
1. `kernel/common` 分支 `android17-6.18`，用设备 `/proc/config.gz` 作 `.config`；
2. `CONFIG_TRIM_UNUSED_KSYMS`/`UNUSED_KSYMS_WHITELIST`/`MODULE_SIG_PROTECT_LIST` 置空（Android 构建系统才生成那两个文件）；
3. `PATCHLEVEL=18, SUBLEVEL=21` + `CONFIG_LOCALVERSION="-android17-5-g1d099fcb35e0-abogki538445360-4k"` + `LOCALVERSION_AUTO=n`，并在构建前移开 `.git`（否则追加 `-g<sha>-dirty` 或 `+`）；
4. KernelSU `Kbuild` 里 `obj-$(CONFIG_KSU)` 改成 `obj-m`，补 `nsimport.c` 导入 `ANDROID_GKI_VFS_...` 命名空间；
5. `KCFLAGS=-Wno-error KBUILD_MODPOST_WARN=1`（未导出符号由载荷运行时重链接）。

VM 验证（`qemu -M virt` + 自编 Image）：裸模块 `finit_module` 返回 ENOENT（未导出符号待重链接，预期），**失败后 exec 仍正常、无 panic**。

## 设备步骤

```bash
# 0. 干净启动后确认
adb devices
adb shell 'grep -c . /sys/kernel/tracing/kprobe_events'   # 应为 2（MIUI 自带）

# 1. 推入
adb push o3root-port/build/o3p_ksu_v331.bin /data/local/tmp/o3p_ksu.bin
adb shell chmod 755 /data/local/tmp/o3p_ksu.bin

# 2. 跑两阶段（SELinux + cred）+ 自动加载 LKM
adb shell 'cd /data/local/tmp; rm -f run.log o3p_insmod.out; \
  nohup ./o3p_ksu.bin 10000 8192 0 0 6 1 8000 200 > run.log 2>&1 & echo started'

# 3. 看进度（约 1-4 分钟）
adb shell 'grep -E "VERDICT|UIDNOW|FULLROOT|KSU_|HIT" /data/local/tmp/run.log | tail -20'
adb shell 'cat /data/local/tmp/o3p_insmod.out 2>/dev/null; grep -c kernelsu /proc/modules'

# 4. 装管理器（模块加载成功后再装）
adb install -r o3root-port/KernelSU-manager.apk
```

期望日志顺序：`UIDNOW uid=0` → `KSU_BLOB v1 len=1117280` → `KSU_INSMOD_OUT` 里 `rc=0` →
`/proc/modules` 出现 `kernelsu` → 管理器打开显示已安装。

## 失败处理

- **模块加载失败**（`o3p_insmod.out` 里 `version magic ... should be ...`）：说明 vermagic 又对不上，重新确认内核 release 串。
- **模块加载后 adb shell 报 `Function not implemented`**（之前踩过的坑）：立刻断电重启。此时系统被 KSU 的 hook 破坏，回不来。
- **没有任何 KSU 日志**：载荷没走到 ksu_load（多半是 `g_un`(slide) 没拿到或未 root），先确认 `UIDNOW uid=0`。

## 提醒

- 依旧是**当前 boot 有效**：重启后 root 和 KernelSU 都没了，需要重跑载荷。
- 持久化要改 `boot`/`init_boot`，被锁定的 bootloader 挡住。
