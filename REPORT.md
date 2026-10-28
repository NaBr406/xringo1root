# CVE-2026-98260 设备适用性评估（XRing O1 / 25042PN24C / dijun）

评估时间：2026-10-28　设备：`0484885189A00540`

## 1. 结论

**受影响，且已用厂商官方制品证明未修复。** 不是"版本可能不匹配"，而是"这条代码路径上的补丁确实不在本机内核里"。

三条独立证据：

| 证据 | 结果 |
|---|---|
| 本机内核构建时间 | 2026-07-28，早于修复补丁投递（2026-09-04）六周 |
| GKI `android17-6.18` 分支源码（今日 HEAD） | 仍是修复前布局，无 `posixtimer_exec()` |
| 本机官方 OTA 提取出的内核二进制 | `posixtimer_exec` 出现 0 次，对照符号齐全 |

补丁到 2026-10-28 为止只进了主线 7.3-rc3 一类，LTS/Android 通用内核尚未回移；dijun 当前也只有 `OS4.0.0.19.XODCNXM` 这一个版本，没有更新的 OTA 可升。

## 2. boot 提取结果（不需要线刷包）

官方 OTA 全量包可直接按 HTTP Range 取：

- URL：`https://bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com/OS4.0.0.19.XODCNXM/dijun-ota_full-OS4.0.0.19.XODCNXM-user-17.0-aa6a58e947.zip`
- 总长 `7,821,662,782` 字节（7.28 GiB），`Accept-Ranges` 生效（206）
- ZIP64 中央目录 → `payload.bin`（本地头 @5171，数据 @5238）
- payload v2，manifest `282,940` B，metadata 签名 `267` B，`block_size=4096`，共 42 个分区
- `boot` 分区：48 个 `REPLACE_XZ` op，压缩数据 12.22 MB，落到 24,576 块 = **96.00 MB** 分区
- 重建结果：[boot.img](E:\code\CVE\cve-2026-98260-xring\boot.img)，header v4，`kernel_size=42,936,832`（40.95 MB），内核位于 +4096，**未压缩的 arm64 Image**（`flags=0xa`、`ARM\x64` 魔数在 +56）
- 内核：[kernel_image.bin](E:\code\CVE\cve-2026-98260-xring\kernel_image.bin)，`sha256 = 0d9917ca00657798e258889e258931b8b1fb0b2bbb8c0ad90e8c89ce517da0ac`

提取出的内核版本串与设备运行时**逐字一致**：

```
Linux version 6.18.21-android17-5-g1d099fcb35e0-abogki538445360-4k
(kleaf@build-host) (Android (15323222, +pgo, +bolt, +lto, +mlgo, ...) clang 22.0.1)
```

所以 OTA 里的 boot.img 就是本机在跑的那个内核，可以直接做静态判定。

设备侧 `/dev/block/by-name/boot_b` 对 `shell` 是 `Permission denied`（`boot_block_device` 上下文 + 0640），因此无法直接 dd，走 OTA 是唯一无 root 的取镜像路径。

## 3. 漏洞与修复

修复：[`exec: Cleanup POSIX timers right after de_thread()`](https://lists.openwall.net/linux-kernel/2026/09/04/1517)（Hyunwoo Kim，tglx 整理，patch 2/8，2026-09-04；CVE 公告 2026-10-06；`Fixes: 55e8c8eb2c7b "posix-cpu-timers: Store a reference to a pid not a task"`）。

根因（原文摘要）：per-thread CPU timer 持有其所属线程 PID 的引用，武装时 node 挂在 `posix_cputimers` 上。非 leader 线程 B `exec()` 时 `de_thread()` 把 TID 换给 leader，`pid_task(timer->it.cpu.pid)` 就返回 NULL，但 node 仍排在活着的 `tsk` 上；`timer_lock_sighand()` 把"查不到"当成"已出队"，于是没有回滚。

正常路径靠 `begin_new_exec()` 里 `exec_task_namespaces()` 之后的 `posix_cpu_timers_exit(me)` 兜住。但 `bprm->point_of_no_return` 在 `de_thread()` 之前就置位了，所以只要 `unshare_files()`、`set_mm_exe_file()`、`exec_mmap()`、`exec_task_namespaces()` 任一失败，任务会在跑到清理之前 `do_exit()`：`exit_itimers()` 释放 `k_itimer`，而 node 仍在 rbtree 里，之后 `release_task(B)` → `posix_cpu_timers_exit(B)` → `timerqueue_del()` 擦除已释放 node → UAF。

触发序列（决定性细节）：

```
B: timer_create(CLOCK_THREAD_CPUTIME_ID); timer_settime(); execve()
   de_thread(B)
     exchange_tids(B, leader); release_task(leader)
   exec_mmap()  <-- kill(B, SIGKILL) 使 mmap_read_lock_killable 返回 -EINTR
   do_exit() -> exit_itimers() -> posix_cpu_timer_del(); posix_timer_unhash_and_free()
父: wait4() -> release_task(B) -> posix_cpu_timers_exit(B) -> cleanup_timerqueue() -> timerqueue_del()  // UAF
```

**关键点：必须在 `exec_mmap()` 的窗口里对被 exec 的线程投递 SIGKILL。** 我上一轮的探针没有这个 killer 线程，所以根本没有进入漏洞窗口 —— 之前"10 轮无异常"不能算作任何证据，特此更正。

## 4. 静态判定证据

源码侧（`https://android.googlesource.com/kernel/common/` 分支 `android17-6.18`，今日 HEAD，`fs/exec.c` 2111 行）：

```
1127: bprm->point_of_no_return = true;
1130: retval = de_thread(me);
1148: retval = unshare_files();                 // 失败 -> goto out
1161: retval = set_mm_exe_file(bprm->mm, ...); // 失败 -> goto out
1174: retval = exec_mmap(bprm->mm);            // 失败 -> goto out
1189: retval = exec_task_namespaces();         // 失败 -> goto out_unlock
1193: #ifdef CONFIG_POSIX_TIMERS
1195:   posix_cpu_timers_exit(me);               // 清理仍在这里 = 修复前布局
1197:   exit_itimers(me);
1198:   flush_itimer_signals();
1199: #endif
```

修复版是把 1193–1199 这段抽成 `posixtimer_exec()` 并紧贴 `de_thread()` 之后调用。分支头没有这个函数，也没有这段搬移 —— 即连通用内核的源码都还没修。

二进制侧（本机内核 Image 字符串/符号计数，BTF 内嵌）：

| 符号 | 次数 |
|---|---|
| `begin_new_exec` | 3 |
| `de_thread` | 1 |
| `exit_itimers` | 1 |
| `flush_itimer_signals` | 1 |
| `posix_cpu_timers_exit` | 2 |
| `posix_cpu_timer_del` | 1 |
| `timerqueue_del` | 1 |
| **`posixtimer_exec`** | **0** |

对照符号齐全说明检索面有效。但内核编译参数含 `+lto`，单调用点静态函数可能被内联进 `begin_new_exec` 而不出现在名字表里，所以这一条只作佐证，定论取源码侧与时间线。

## 5. 设备指纹（只读采集）

| 项 | 值 |
|---|---|
| 型号/代号 | Xiaomi `25042PN24C` / `dijun` |
| SoC | `XRing O1`（`ro.soc.manufacturer=XRing`, `ro.soc.model=O1`, `platform=O1_asic`） |
| 系统 | Android 17 / SDK 37，HyperOS `OS4.0.0.19.XODCNXM`，`CP2A.260605.016` |
| 内核 | `6.18.21-android17-5-g1d099fcb35e0-abogki538445360-4k`，2026-07-28，4K 页 |
| 补丁级别 | `2026-09-01`（system 与 vendor） |
| 启动链 | bootloader 锁定、`verifiedbootstate=green`、verity enforcing、slot `_b`、AVB 1.4 |
| 隔离 | SELinux enforcing、`ro.debuggable=0`、`user`/`release-keys` |
| adb | `uid=2000(shell)`、`u:r:shell:s0`，无 root、无 Magisk/KernelSU/Shizuku |
| 相关配置 | `CONFIG_POSIX_TIMERS=y`、`CONFIG_POSIX_CPU_TIMERS_TASK_WORK=y`、`CONFIG_KALLSYMS_ALL=y`、`CONFIG_ARM64_MTE=y`、`CONFIG_DEBUG_INFO_BTF=y` |
| 内核 cmdline | `kasan=off`、`android_arch_task_struct_size=1024`、`restrict_cma_redirect=on`、`disable_dma32=on` |
| CPU | arm64-v8a，`0xd80`，`paca/pacg`（PAC 生效），未见 `bti`/`mte` |

被 SELinux 挡住、无法读取的：`/proc/kallsyms`、`/proc/sys/kernel/*`、`/sys/kernel/btf/vmlinux`、`/data/adb`、`/dev/block/by-name/boot_b`。

## 6. 可利用性

有利：4K 页、`kasan=off`、`task_struct` 1 KB、`restrict_cma_redirect=on` 关掉跨页重定向、触发点只需一个 App/一个 shell 进程、SoC+内核组合已有公开定向研究（[xring-cve-2026-98260](https://github.com/Lw5959/xring-cve-2026-98260)、[o3root](https://github.com/zsw125/o3root) 同为 6.18.21）。

阻碍：bootloader 锁定 + AVB + verity 排除 fastboot 侧路径；SELinux enforcing 下拿到内核上下文后仍需处理策略才有持久 root；PAC 生效；无 MTE 实际启用（对攻击者是好事，对辩护者不是）。

## 7. 产物

| 文件 | 说明 |
|---|---|
| [extract_payload.py](E:\code\CVE\cve-2026-98260-xring\extract_payload.py) | Range 定位 payload.bin 与 boot 分区 |
| [extract_boot.py](E:\code\CVE\cve-2026-98260-xring\extract_boot.py) | 按 op 的 `data_offset`/`data_length` 解码 XZ 并重建 boot.img |
| [boot.img](E:\code\CVE\cve-2026-98260-xring\boot.img) | 重建的 96 MB boot 分区（与本机同版本） |
| [kernel_image.bin](E:\code\CVE\cve-2026-98260-xring\kernel_image.bin) | 40.95 MB 未压缩 arm64 Image，sha256 见 §2 |
| [trigger_v3.c](E:\code\CVE\cve-2026-98260-xring\trigger_v3.c) | **有效触发**：确定性同步 + mmap 锁竞争，已在模拟器复现 UAF |
| [emulator-crash.log](E:\code\CVE\cve-2026-98260-xring\emulator-crash.log) | 模拟器 panic 的 pstore 完整日志 |
| trigger.c / trigger_v2.c | 早期探针（缺 killer 同步），保留作对照 |
| [trigger_arm64](E:\code\CVE\cve-2026-98260-xring\trigger_arm64) | 已推送至设备 `/data/local/tmp/` |

## 8. 模拟测试：UAF 已在模拟器上复现

在 API35 `google_apis/x86_64` 模拟器上复现（内核 `6.6.50-android15-8-g8adecb593e9b-ab12525588`，2024-10-18，4K 页，与真机同为修复前的通用内核代码路径）。

### 8.1 触发时序（与补丁说明一致）

前两版探针失败的原因很清楚：窗口不是靠 `usleep` 猜出来的。

- killer 必须用 `clone(CLONE_VM|SIGCHLD)` 创建 —— 独立进程、共享地址空间，`de_thread()` 杀不到它；用 pthread 会被 de_thread 一起收掉。
- 同步点：轮询 `tgkill(tgid, old_tid, 0)`，直到返回 `ESRCH` —— 这正是 `de_thread()` 完成 `exchange_tids()` 的时刻。
- 随即 `tgkill(tgid, tgid, SIGKILL)` 打整组，让 `exec_mmap()` 的 `mmap_read_lock_killable()` 返回 `-EINTR`。
- 关键补充：`mmap_read_lock_killable()` 在锁空闲时**不检查**信号，只有等锁时才可被中断。所以必须让 locker（同样 clone 出来）在那一刻**占住 mmap 写锁** —— 用 50000 个独立 VMA 上的 `mprotect` 风暴来拖住它。

### 8.2 结果：第 3 次尝试即 panic

```
general protection fault, probably for non-canonical address 0x5bdf13cd62f415f0
CPU: 1 PID: 3527 Comm: trigger_v3
RIP: 0010:rb_next+0x21/0x50
Call Trace:
 ? asm_exc_general_protection
 ? rb_next+0x21/0x50
 timerqueue_del+0x24/0x60
 posix_cpu_timers_exit+0x92/0xc0
 release_task+0xfe/0x600
 wait_consider_task+0x712/0x970
 do_wait+0x176/0x2a0
 kernel_wait4+0x13d/0x190
 __x64_sys_wait4+0x63/0xd0
Kernel panic - not syncing: Fatal exception
```

这与补丁说明的预测路径逐帧对应：`exit_itimers()` 释放仍在 rbtree 中的 node → 父进程 `wait4()` → `release_task()` → `posix_cpu_timers_exit()` → `timerqueue_del()` 在已释放节点上做 `rb_next()` → 非规范地址 → GP fault → panic。

寄存器 `RAX/RCX = 0x5bdf13cd62f415e0` 是被释放对象里残留的随机化内容，非规范指针，符合 UAF 而不是普通的空指针崩溃。崩溃后模拟器自动重启（`ro.boot.bootreason = kernel_panic,fatal_exception`），日志落在 `/sys/fs/pstore/`。

结论：这条代码路径在修复前的通用内核上**可确定性触发**，一次成功尝试约 3 轮。真机内核（6.18.21，同源代码、同样未修复）自然具备同一路径；差别只在真机是 4K 页的 arm64、且 bootloader 锁定。

**可复现性**：连续两次运行均触发（2/2），调用栈签名完全相同，故障地址每次不同（`0x5bdf13cd62f415f0` 与 `0x8a2233652d85519c`），符合"读取已释放对象里的残留内容"这一特征；`nvma=50000/lockers=3` 与 `nvma=20000/lockers=2` 两种配置都能打中。

### 8.3 为什么仍在模拟器上做

真机 panic 的代价是不可逆的（锁定 bootloader → 循环重启 → 只能清数据恢复）；模拟器 panic 只是重启，正好用来把触发时序和判定口径调到确定，再决定是否碰真机。

## 9. A/B 因果验证（自建内核 + KASAN）

模拟器那一轮只证明"能打崩"，没证明"崩的就是这个补丁修的因"。补这一环：在 WSL2 Ubuntu 26.04 里用 **Linux 6.18.21 原始源码**（与真机同版本）自建两块内核，只差这一个补丁。

| 内核 | 构建 | 配置要点 |
|---|---|---|
| 未修复 | 上游 6.18.21 原样 | KASAN_INLINE + POSIX_CPU_TIMERS_TASK_WORK + 4K 页 |
| 已修复 | `apply_fix.py` 移植 `posixtimer_exec()`：`de_thread()` 之后立即清理 | 同上 |

判据不是"崩不崩"，而是 **KASAN 是否报 `slab-use-after-free`**。

### 9.1 未修复内核：UAF 被精确抓到

40 次尝试中第 ~30 次触发：

```
BUG: KASAN: slab-use-after-free in timerqueue_del+0x104/0x130
Read of size 8 at addr ffff888102e847e0 by task init/1
Call Trace:
 timerqueue_del
 posix_cpu_timers_exit
 release_task
 wait_consider_task
 __do_wait
 do_wait
 kernel_wait4
 __do_sys_wait4

Allocated by task 567:
 do_timer_create  <-- 我们的 timer_create(CLOCK_THREAD_CPUTIME_ID)

Freed by task 12:
 kvfree_rcu_bulk <- kfree_rcu_monitor
 Last potentially related work creation:
 exit_itimers
 do_exit
 do_group_exit
 get_signal

The buggy address belongs to the object at ... which belongs to the cache
posix_timers_cache of size 384
```

分配在 `do_timer_create`、释放在 `exit_itimers ← do_exit ← get_signal`、读在父进程 `wait4 → release_task → posix_cpu_timers_exit → timerqueue_del` —— 与补丁说明描述的因果链逐项对应，`posix_timers_cache` 正是 `k_itimer` 的缓存。

### 9.2 已修复内核：同一 harness，0 报告

同样 40 次尝试，`BUG: KASAN` 计数 **0**，进程正常走完并 poweroff。

### 9.3 一个重要的方法论结论

同一 harness 在**无 KASAN** 的 6.18.21 上跑 40 次一次没崩。原因是被释放的 `k_itimer` 内存当时仍被映射、内容未被改造，UAF 读不会必然 fault。所以"没崩"完全不能当作"没漏洞"——这也是必须用 KASAN 而不是崩溃作为判据的原因。反过来，6.6.50 Android 模拟器那次直接 GP fault panic，是因为那段被释放内存被改造成了非规范指针。

对真机的含义：真机 `kasan=off`，触发结果取决于释放后的内存被如何使用，可能是
1. 静默内存破坏（不崩，但内核状态已坏），或
2. GP fault → 因为 `CONFIG_PANIC_ON_OOPS=y` 且 `CONFIG_PANIC_TIMEOUT=-1`，会停在 panic 状态，**不会自动重启**，需要手动长按电源。

harness 本身不写任何持久化数据（只做 mmap/mprotect/timer_create/execve/kill），所以重启后设备状态不变。

### 9.4 命中率与 arm64 现状

七轮未修复内核（每轮 40 次尝试）合计：**3 次 UAF / 280 次尝试 ≈ 1.1%**；两轮已修复内核合计 0 / 80。试过的变体（12/16/48 个 locker、60000 个 memfd VMA、已填充 128 MB 匿名弹幕、亚微秒忙等）都没有明显改善 —— 窗口确实很窄。

由此推算真机需要的尝试次数（按 1.1%/次）：

| 尝试次数 | 至少命中一次 |
|---|---|
| 40 | ~35% |
| 80 | ~57% |
| 120 | ~72% |
| 200 | ~88% |
| 300 | ~96% |

**arm64（TCG）未能在 ~180 次尝试内复现**：同版本 aarch64 KASAN 内核（4K 页）在 qemu `-M virt`（4/8 vCPU）下 0 报告。这是环境因素（TCG 的调度粒度把 µs 级窗口抹平），不是 arm64 语义差异 —— UAF 代码路径与架构无关，且 x86_64 KVM 上同一 harness 能打中。arm64 的实机可达性仍需真机或 arm64 硬件虚拟化环境确认。

## 10. 下一步

已完成：静态判定（源码 + 二进制）、boot 提取、模拟器复现（2/2）、x86_64 KASAN A/B 因果验证、真机手册（[DEVICE-RUNBOOK.md](E:\code\CVE\cve-2026-98260-xring\DEVICE-RUNBOOK.md)）。

1. **真机复现**：证据已足以判断"该不该去"，剩下的只差"去了能看到什么"。风险画像：要么静默内存破坏、要么 panic 后停在原地需要手动断电重启；harness 不落盘，不需要清数据，但 panic 撞上写回仍有小概率文件系统损伤。
2. **若目标真是拿到 root**：窗口只负责 UAF 触发，还需要堆布局（`k_itimer` 回收 + 伪造对象）才能把 UAF 转成可控原语；公开实现（[InfinityCore](https://github.com/V4bel/InfinityCore)、[xring 端口](https://github.com/Lw5959/xring-cve-2026-98260)）在此之上还有 VMA ballast、AIO/anon 页喷射、vtable 替换等步骤。
3. **arm64 复现**：需要 arm64 硬件虚拟化（Apple/Ampere 主机）或直接真机；TCG 下不现实。

本轮未做任何清除、擦除、格式化、fastboot 写入操作。真机上只多了一个 `/data/local/tmp/trigger_arm64`；模拟器为一次性实例，可随时 `adb -s emulator-5556 emu kill` 丢弃。
