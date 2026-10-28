# 参考 o3root 仓库后的对照结论

参考对象：<https://github.com/zsw125/o3root>（v3.0，2026-10-25）。
本地留档：`o3root-ref/`（README、AGENT_HANDOFF、ARCHITECTURE、relink_ksu.py、
ROOT_ACHIEVED、build-payload.sh、kernel_cfg_btf.py）。

## 一、我们已经在用的部分（移植自该仓库）

- `o3root-port/o3p.c` 由仓库 `payload/o3p.c` 移植，保持同一套利用链：
  kprobe 任意读 → KASLR slide（`cred->user_ns - INIT_USER_NS_STATIC`）→
  回收 order-1 `posix_timers_cache` slab → 伪造 RB 节点 → `rb_erase` 任意写
  → stage 0 清 `selinux_state.enforcing`、stage 1 换 `task_struct.cred`
- 加载方式一致：`kallsyms_patch()` 把 LKM 未定义符号改写成 `SHN_ABS` + 运行时
  地址，写 `/data/local/tmp/o3p_ksu.ko`，再 `fork + exec("/system/bin/sh","-c","insmod ...")`
  （不是为了绕签名，而是让新 exec 的 cred 一致）

## 二、之前漏读的关键信息

### 1. 官方推荐的载荷参数（我们用错了）

仓库 `docs/AGENT_HANDOFF.zh-CN.md` 的独立测试命令：

```
10000 14000 300 1 6 1 8000 800
```

我们今晚一直用 `10000 8192 0 0 6 1 8000 200` —— **pairs 少 40%、delay 0 vs 300、
mode 0 vs 1、chwait 200 vs 800**。喷页规模直接决定回收命中率。

### 2. 仓库自己把"自编 LKM"列为待办第 9 条（困难）

> 上游 LKM 是为 `6.18.32-4k` 构建的，被重链接后加载到 `6.18.21`。用 KernelSU
> 源码针对本内核配置（或匹配的 GKI）构建，可消除 ABI 错配与"修改过的模块"顾虑；
> 需要内核源码/配置。

也就是说：**他们从未在真机上让自编 LKM 跑起来**，我们做的正是他们留下的空位。

### 3. 他们的验证设备内核和我们也不同

| | 仓库验证机 | 我们的 dijun |
|---|---|---|
| 内核 | `6.18.21-android17-5-g805aa6adea19-abogki565292102-4k` | `6.18.21-android17-5-g1d099fcb35e0-abogki538445360-4k` |
| 官方 375 KB LKM | `KALLSYMS_PATCH found=225` → `rc=0` → `LIVE` | `found=224 missing=18` → 加载失败 |

同一套官方 LKM 在 dijun 上有 18 个符号解析不到，所以对 dijun 而言**必须自编**，
这进一步确认了我们的方向。

### 4. 设备内核配置确认（dijun）

```
CONFIG_CFI=y
CONFIG_MODVERSIONS=y / EXTENDED_MODVERSIONS=y
CONFIG_KALLSYMS_ALL=y
CONFIG_PANIC_ON_OOPS=y       # 运行时 panic_on_oops=1
CONFIG_PANIC_TIMEOUT=-1      # panic 后不自重启（会挂住）
panic_on_warn=0
```

## 三、当前卡点的性质（已排除的假设）

| 假设 | 结论 |
|---|---|
| 内存不足 / OOM | ❌ 排除：`MemAvailable` 8.2–8.8 GB，`Cached` 7.9 GB |
| 我加的"每轮删除 al/fs 探针"补丁导致 | ❌ 排除：完全回退后仍会崩 |
| 我加的 `probe_on` 重试破坏时序 | ❌ 排除：完全回退到原始代码后仍会崩 |
| 传输损坏 | ✅ 已修：每轮 push 后校验 sha256 |
| **stage 1 命中后内核 oops** | ✅ 当前现象：写 `task_struct.cred` 时崩溃 → `panic_on_oops=1` → 看门狗复位（`AP_S_COLDBOOT`） |

stage 0（清 `enforcing`）目前很稳：用 `att=1` 单次尝试，第 1 次就拿到 Permissive。

## 四、仓库给出但我们还没试的路径

1. **用官方 LKM 在 dijun 上跑不通**（缺 18 符号），所以自编是唯一路径 —— 已确认。
2. `O3P_RELINK_ONLY=1` 回退路径：248 符号并集 + slide 偏移。对自编 LKM 不适用
   （我们 missing=0）。
3. 仓库提醒的"第二次 `timerqueue_del` 会 WARN，靠 `panic_on_warn=0` 容忍"——
   dijun 也是 `panic_on_warn=0`，这条对我们是安全的。

## 五、下一步建议

1. 设备静置冷却后，**用官方参数** `10000 14000 300 1 6 1 8000 800` 跑一次
   （此前用 14000 参数时恰好赶上设备不稳定，未得到有效结论）。
2. 若 stage 1 仍崩，改用 `O3P_D3` 之外的两段流程：先 `att=1` 拿 Permissive，
   再 `O3P_NOSEL=1 att=6` 只做 cred。
3. KSU 模块本身已验证：同配方 `hello.ko` → `insmod rc=0` → `Live`；
   `kernelsu.ko`（835,336 B）只差一次不崩的 stage 1 + insmod。
