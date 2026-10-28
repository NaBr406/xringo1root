# o3root → dijun 移植笔记

参考项目：[zsw125/o3root](https://github.com/zsw125/o3root)（v3.0，Shizuku shell → CVE-2026-98260 → uid 0 + KernelSU LKM）。
目标设备：`25042PN24C` / `dijun`（XRing O1），HyperOS `OS4.0.0.19.XODCNXM`，Android 17，
内核 `6.18.21-android17-5-g1d099fcb35e0-abogki538445360-4k`。
参考设备：`yingtian`（Pad 9 Pro Max），内核 `6.18.21-android17-5-g805aa6adea19-abogki565292102-4k`。

## 1. 为什么这套链能直接搬

两台的**结构布局完全一致**（BTF 实测，见下表），因为都是同版本 6.18.21-android17 GKI + 4K 页。

| 项 | yingtian（参考） | dijun（本机，BTF 实测） | 是否一致 |
|---|---|---|---|
| `task_struct.cred` | 0x908 | **0x908** | ✅ |
| `task_struct.real_cred` | 0x900 | **0x900** | ✅ |
| `task_struct.posix_cputimers` | 0x868 | **0x868** | ✅ |
| `task_struct.signal` / `sighand` | 0x960 / 0x968 | **0x960 / 0x968** | ✅ |
| `cred` size / uid / euid / fsuid | 0xb8 / 0x08 / 0x18 / 0x20 | **相同** | ✅ |
| `cred.cap_*` | 0x30..0x50 | **0x30..0x50** | ✅ |
| `cred.security` / `user_ns` / `group_info` | 0x80 / 0x90 / 0xa0 | **相同** | ✅ |
| `k_itimer` size / `it` / `elist` | 0x180 / 0xe0 / 0x110 | **0x180 / 0xe0**（elist 见 BTF `it`+0x30） | ✅ |
| `init_user_ns` | `0xffffffc0826d10d8` | **`0xffffffc0826d10d8`** | ✅ 完全相同 |
| `selinux_state` | `0xffffffc082959630` | **`0xffffffc082958630`** | ❌ 差 0x1000 |
| `selinux_state-8` 邻居 | `avc_latest_notif_update.notif_lock` | **同名同布局，在 `0x…958628`** | ✅ |

写原语的载体也一致：`timerqueue_del`（本机 `0xffffffc080191230`）先比 `rb_leftmost`
再 `rb_next`，随后 `rb_erase`（`0xffffffc0801912a4`）做 `*(node->rb_left) = parent_color`
—— 反汇编已核对。

## 2. 移植改动：一个常量

`payload/o3p.c` 里只有两个硬编码内核地址（已 grep 确认没有第三个）：

```c
#define INIT_USER_NS_STATIC    0xffffffc0826d10d8ULL   // 与本机完全相同，不动
#define SELINUX_STATE_STATIC   0xffffffc082958630ULL   // 原 0xffffffc082959630，已改
```

其余地址（`task_struct`、`cred`）都是**运行时**从 kprobe 泄漏出来的，不需要静态常量。
KASLR slide 也由 `cred->user_ns - init_user_ns` 在运行时算出。

`selinux_state - 7` 的非对齐零写在本机同样安全：`selinux_state-8` 起是
`avc_latest_notif_update.notif_lock`（8 字节锁），写 `[selinux_state-7, selinux_state]`
只清 `enforcing`（+0），不动 `initialized`（+1）和 `policycap`（+2）——与参考实现同一手法。
**前提是该锁当时处于未加锁（0）状态**，移植时需在运行时复核。

## 3. 构建（已验证可编译）

参考 `payload/build-payload.sh`，本机实测：

```bash
# NDK r28，注意必须用 API >= 28（bionic 的 glob() 是 __INTRODUCED_IN(28)）
aarch64-linux-android35-clang -std=gnu11 -O2 -I ksu -o build/o3p.bin o3p.c
# 源文件需补 #include <glob.h>（作者用的工具链隐式包含）
```

产物：`build/o3p.bin`，73,768 字节，arm64 ELF。

打包 LKM（可选）：`mk_payload.py --payload build/o3p.bin --ko <ksu.ko> --out libo3p.so`。

## 4. 唯一的硬前提：shell 能否写 tracefs

整条链的**第一步**就是在 `__arm64_timer_...`/`__alloc_frozen_pages_noprof` 等符号上挂
kretprobe 泄漏内核指针，再算 slide。参考项目文档里写明他们那台
`/sys/kernel/tracing/kprobe_events` 权限是 **0777**（HyperOS 的配置问题）。

本机**尚未验证**。一条命令即可判定：

```
adb shell 'ls -l /sys/kernel/tracing/kprobe_events /sys/kernel/tracing/trace; id'
```

- 如果 `kprobe_events` 对 `uid=2000` 可写（0222/0777，或 shell 属于其 owner 组）→ 链路可行。
- 如果只有 `root:root 0200` → 泄漏拿不到，需要另找 slide 泄漏点，这套 payload 不能直接用。

参考项目在 `docs/APP_O3_ROOT.md` 里也承认这一点：「首次在 lhasa 上跑时若 shell 域写
tracefs 被拒，载荷会在 probe 阶段报错」。

## 5. 风险（沿用参考项目的口径）

- 全链**只改内核内存**，不动任何分区；bootloader 保持锁定，AVB/verity 不变。
- **重启即失效**，无持久化。持久化需要改 `boot`/`init_boot`，被锁的 bootloader 挡住，不在范围内。
- 概率性：作者实测 **1–6 次尝试**（有 churn 优化后），不是一次必中。
- 失败形态：内核 panic。本机 `PANIC_ON_OOPS=y` + `PANIC_TIMEOUT=-1` → 停在 panic，需长按电源重启。
  不落盘，重启后正常。
- 依赖 `# CONFIG_PANIC_ON_WARN is not set`（本机满足）、`CONFIG_KPROBES=y`（满足）、
  `# CONFIG_MODULE_SIG_FORCE is not set`（满足，LKM 可加载未签名模块）。

## 6. LKM 的额外注意

参考项目的预编译 LKM 是为 `6.18.21-android17-5-g805aa6adea19-abogki565292102-4k`
打的，与本机 `...-g1d099fcb35e0-abogki538445360-4k` **vermagic 不同**。两条路：

1. 先用 `O3P_NOKSU=1` 只拿 `uid=0`（不动 LKM），验证 cred 写通不通；
2. 再处理 LKM：vermagic 字符串长度相同（`6.18.21-android17-5-g` + 12 位 + `-abogki` + 9 位 + `-4k`），
   可以在 `.ko` 的 `.modinfo` 里原地改成我们的版本串；符号由 payload 运行时经
   `/proc/kallsyms` 解析，不依赖构建期地址。

## 7. 下一步顺序

1. **设备侧一条命令**：确认 `kprobe_events` 可写 —— 这决定整套方案是否成立。
2. 若可写：`--dry` 类探测（先只挂 probe + 读 trace，不做任何写），确认泄漏链路通。
3. 通了再跑 stage 0（`selinux_state` 零写）→ stage 1（`cred` 写）。
4. 最后才谈 LKM 与 rootd。

## 8. 实机结果（2026-10-28，dijun 25042PN24C / OS4.0.0.19.XODCNXM）

**已拿到 root。**

```
$ /data/local/tmp/o3p.bin --shell "id; getenforce; grep CapEff /proc/self/status"
uid=0(root) gid=0(root) groups=0(root),1004(input),...,3012(readtracefs) context=u:r:shell:s0
Permissive
CapEff:	000001ffffffffff
```

验证过的特权操作：`mount -t tmpfs` 成功、`/data/adb` 可列目录（root:root）。

关键日志：

```
SLIDE_CALC un=0xffffffed496d10d8 slide=0x2cc7000000 align=1
FAKEPAGE kva=0xffffff826b408000 S=0xffffffed49958629 stage=0   <- selinux_state-7
== reap window stage=0   UIDNOW uid=2000 ...  getenforce: Enforcing -> Permissive
== attempt 3  HIT  UIDNOW uid=0 euid=0 gid=0
FULLROOT armed=1 fakekva=0xffffff83ff197000
```

- stage 0 首轮即中（SELinux 清零），stage 1 第 3 次尝试命中（cred 写）。
- 全程只改内核内存，未写任何分区；bootloader 仍锁定；重启即失效。
- 期间设备重启 3 次，均由**悬空 trigger action** 导致（看门狗冷启，非 kernel panic），已修。

## 9. 移植补丁清单（相对上游 o3root）

1. `o3p.c`: `SELINUX_STATE_STATIC` `0xffffffc082959630` → `0xffffffc082958630`
2. `del_ev()`: 改成 `RSSEN=1 → disable_event → 触发 rss_stat → !disable_event → !enable_event → RSSEN=0 → 删除`，并加"trigger 仍引用则不删"的保护（本机固件里已启用的探针删不掉，且悬空 action 会崩内核）
3. `main()`: 清理名单补上 `o3p/fs`（上游漏了，残留会累积成悬空 action）

## 10. KernelSU LKM 的状态

内置 LKM 是 `6.18.32-4k-g47cc22554442-dirty` 构建的，本机 vermagic 是
`6.18.21-android17-5-g1d099fcb35e0-abogki538445360-4k`（长 22 字节），
且本机 `# CONFIG_MODULE_FORCE_LOAD is not set`，所以 `insmod` 会被 vermagic 检查拒绝。

三条可行路径（都还没做）：
1. 对 `.ko` 做 ELF 节区级改写，把 `.modinfo` 的 vermagic 换成我们的串（长度变化需重排 offsets）；
2. 用自写 loader 调 `finit_module(..., MODULE_INIT_IGNORE_VERMAGIC|IGNORE_MODVERSIONS)` —— 需要自己实现符号重写（载荷里的 `ksu_patch` 已完成大部分）；
3. 用 GKI `android17-6.18` 头文件按本机 KMI 重新编译 KernelSU LKM。

即便不装 LKM，当前 uid 0 + 全 caps + Permissive 已经是完整 root（只是重启丢失）。

## 11. KernelSU LKM：已自编完成（v3.3.1）

| 项 | 值 |
|---|---|
| 源码 | `tiann/KernelSU` tag **v3.3.1**（与官方管理器 APK 同版本、同签名） |
| 构建内核 | GKI `kernel/common` 分支 `android17-6.18` + 本机 `/proc/config.gz` |
| 结构偏移校验 | BTF 比对：`cred` 0x908、`real_cred` 0x900、`posix_cputimers` 0x868、`signal` 0x960 —— 与设备逐项一致 |
| vermagic | `6.18.21-android17-5-g1d099fcb35e0-abogki538445360-4k SMP preempt mod_unload modversions aarch64`（逐字一致） |
| 产物 | `lkm/ksu-dijun-v331.ko`（1.07 MB）、`build/o3p_ksu_v331.bin`（1.14 MB）、`KernelSU-manager.apk`（13 MB） |

构建中踩到的四个坑（都已解决）：`abi_symbollist.raw` / `protected_module_names_list`
（Android 构建系统才生成）、`CONFIG_KSU` 未定义导致 `obj-$(CONFIG_KSU)` 为空、
`ANDROID_GKI_VFS_...` 命名空间、以及 `setlocalversion` 往 release 串追加
`-g<sha>-dirty` / `+` 导致 vermagic 对不上。

VM 自检（qemu -M virt + 自编 Image）：裸模块 `finit_module` 返回 ENOENT（未导出符号等
载荷运行时重链接，属预期），失败后 exec 正常、无 panic。

设备安装步骤见 [DEVICE-RUNBOOK-KSU.md](E:\code\CVE\cve-2026-98260-xring\DEVICE-RUNBOOK-KSU.md)。
