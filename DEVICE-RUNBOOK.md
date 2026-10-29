# CVE-2026-98260 真机复现手册（dijun / 25042PN24C）

> 结论前提：漏洞存在性已由"设备自身 boot.img 静态判定 + 同版本内核 KASAN A/B"确立。
> 本手册只描述"要不要在真机上跑一次"以及跑了会发生什么。

## 1. 现在的证据边界

| 证据 | 状态 |
|---|---|
| 设备内核未修复 | 已证：官方 OTA 提取的 `kernel_image.bin` 无 `posixtimer_exec`；GKI `android17-6.18` 分支头仍是修复前布局 |
| 触发能进窗口 | 已证：x86_64 6.18.21 + KASAN，40 次尝试内报 `slab-use-after-free in timerqueue_del`（对象 `posix_timers_cache`） |
| 因果闭合 | 已证：同一 harness，打上 `posixtimer_exec()` 的 6.18.21 内核 40 次尝试 0 报告 |
| 触发后的后果 | 未在真机验证；真机 `kasan=off`，后果是"静默破坏"或"panic 停住"二选一 |

## 2. 命中率的现实

KASAN 环境里实测命中率约 **1.1%/次尝试**（7 轮 × 40 次，共 3 次 UAF；已修复内核 2 轮 × 40 次，0 次）。要拿到"真机确实可达"的结论，需要累积尝试：

| 尝试次数 | 至少命中一次的概率（按 1.1%） |
|---|---|
| 40 | ~35% |
| 80 | ~57% |
| 120 | ~72% |
| 200 | ~88% |
| 300 | ~96% |

注意：未命中不代表"不漏洞"，只代表这次没抽中。另外 arm64 实时硬件上的命中率与 x86 KVM 不会相同，这个表只能当量级参考。

## 3. 真机上会怎样

- 内核 `kasan=off`，UAF 读到的是刚被释放的 `posix_timers_cache` 对象。是否崩取决于这块内存有没有被改造：
  - 未被改造 → 静默内存破坏，进程正常退出，系统继续跑（**最坏情况**：内核状态已脏，后续随机异常）。
  - 被改造 → 非规范指针 → GP fault。
- 一旦 oops：`CONFIG_PANIC_ON_OOPS=y` + `CONFIG_PANIC_TIMEOUT=-1` → **panic 后不自动重启，机器停在黑屏/重启界面**，需要长按电源 10–15 秒强制断电重启。
- harness 不写任何持久化数据（只用 `mmap/mprotect/timer_create/execve/fork/clone/tgkill`），重启后系统状态不变。
- 残留风险：panic 若恰好发生在文件系统回写过程中，有小概率造成文件系统不一致（f2fs/ext4 的 journal 会尽量修复，但可能丢少量数据）。
- oops 日志会进 pstore / `mtdoops`（`mtdoops.devname=/dev/block/by-name/oops`），但 shell 读不到，所以真机这次"崩没崩"只能靠人眼观察是否卡死。

## 4. 操作步骤

前提：设备已解锁、`adb devices` 可见、电量 > 30%。

```bash
# 1. 推入二进制
adb push ab98260_arm64 /data/local/tmp/ab98260
adb shell chmod 755 /data/local/tmp/ab98260

# 2. 干跑（不进入 exec 竞争，不可能 panic）——先确认 arm64 上定时器/VMA 都正常
adb shell /data/local/tmp/ab98260 --dry --iters 20 --nvma 8192 --lockers 8

# 3. 正式批次（每批 20 次，观察是否卡死）
adb shell /data/local/tmp/ab98260 --iters 20 --nvma 8192 --lockers 8

# 4. 若未命中且设备正常，重复第 3 步，累计到 80~120 次
```

参数说明：
- `--nvma 8192`：32 MB 的 VMA 弹幕（每页一个映射），用于拖住 mmap 写锁；真机上别开太大，避免内存压力。
- `--lockers 8`：mprotect 风暴进程数。进程会在父进程退出后自动退出，不会残留。
- `--iters N`：本批尝试次数。

判读：
- 设备卡死 → 命中（panic）。长按电源重启，核对数据完好，本次验证结束。
- 20 次后设备正常 → 未命中，继续下一批。
- 累计 120 次仍无异常 → 结论是"本次未观测到"，不是"已修复"。

## 5. 我的建议

**不建议为了"确认漏洞存在"去真机跑** —— 这件事已经用设备自己的内核镜像 + 同版本源码 A/B 证明了，真机跑只能得到"确实会崩"或"这次没抽中"，信息增益很小，代价是一台锁定 bootloader 的手机可能停在 panic 状态，且日志拿不到。

**要去真机，动机应该是"要拿 root"**，那是另一件事：窗口只负责 UAF 触发，之后还需要堆布局把 UAF 变成可控原语（`k_itimer` 回收 + 伪造 `cred`/`timer` 对象），公开实现还额外用了 VMA ballast、AIO/anon 页喷射、vtable 替换。那一步的失败代价远高于本次探针，且需要先在 arm64 上把利用链调到稳定。

## 6. 安全回滚

本次所有操作都不触碰分区。若真机需要恢复：
1. 长按电源强制重启；
2. 正常开机后删掉 `/data/local/tmp/ab98260`；
3. 不需要清数据、不需要线刷。
