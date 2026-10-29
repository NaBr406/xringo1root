# 无 KernelSU 的 root 方案：临时 root + rootd 白名单 + su 包装

适用设备：dijun（`25042PN24C`，内核 `6.18.21-android17-5-g1d099fcb35e0-abogki538445360-4k`，
bootloader 锁定，无法持久化）。

## 为什么不用 KernelSU

- 模块能编出来、能过 CFI/CRC/struct module 四道检查（`hello.ko` 实测 `Live`），
  但每次开机都要重跑 exploit 再 insmod，**和临时 root 一样不持久**
- 自编 LKM 的 init 尚未在 dijun 上稳定跑通（`kernelsu_init` 阶段仍有崩溃面）
- bootloader 锁定 → 改不了 boot 分区 → 任何方案都只能是"本次 boot 有效"

所以直接做 su 通道，绕开那五个坑。

## 组成

| 文件（设备上） | 作用 |
|---|---|
| `/data/local/tmp/o3p_new.bin` | 载荷（74 KB），exploit + rootd + 白名单 + `su` 客户端 |
| `/data/local/tmp/su` | su 包装脚本，App 用 `Runtime.exec` 调用 |
| `/data/local/tmp/o3p_allow` | 白名单，每行一个 uid，必须 `root:root 0600` |
| `@o3p_rootd` | 抽象 unix socket，rootd 监听于此 |

## 每次开机后的步骤

```bash
# 0. 推送（重启后 /data/local/tmp 会被清）
adb push o3root-port/build/o3p.bin /data/local/tmp/o3p_new.bin
adb push o3root-port/build/su /data/local/tmp/su
adb shell 'chmod 755 /data/local/tmp/o3p_new.bin /data/local/tmp/su'

# 1. stage 0：清 SELinux（一次尝试，命中即退出，最安全）
adb shell 'cd /data/local/tmp; ./o3p_new.bin 10000 8192 0 0 1 1 8000 200 > s0.log 2>&1; getenforce'
#    重复直到输出 Permissive（实测 1-3 次）

# 2. stage 1：换 cred 拿 root（命中后 rootd 自动以 root 启动）
adb shell 'cd /data/local/tmp; O3P_NOSEL=1 ./o3p_new.bin 10000 8192 0 0 6 1 8000 200 > s1.log 2>&1'
adb shell 'grep -a UIDNOW /data/local/tmp/s1.log | tail -2'   # 期望 uid=0
adb shell 'ps -A | grep o3p'                                   # 期望 root 身份

# 3. 授权给 App
adb shell '/data/local/tmp/o3p_new.bin --shell "/data/local/tmp/o3p_new.bin --grant com.example.app"'
adb shell '/data/local/tmp/o3p_new.bin --shell "/data/local/tmp/o3p_new.bin --allow-list"'
```

## App 侧用法

```java
Process p = Runtime.getRuntime().exec(new String[]{"/data/local/tmp/su", "-c", "id -u"});
// 或
new String[]{"/data/local/tmp/su", "0", "id"}
```

脚本会转发给 rootd，rootd 用 `SO_PEERCRED` 校验调用方 uid 是否在白名单里。

## 内部命令

| 命令 | 说明 |
|---|---|
| `o3p_new.bin --shell "<cmd>"` | 通过 rootd 以 root 执行（调用方需在白名单或 uid 0/2000） |
| `o3p_new.bin --grant <pkg>` | 查 App uid（先 `packages.list`，再 `stat /data/user/0/<pkg>`）并写入白名单，**需 root** |
| `o3p_new.bin --allow <uid>` | 直接加一个 uid |
| `o3p_new.bin --allow-list` | 打印当前白名单 |
| `o3p_new.bin --test-uid <uid>` | 只做判定，不连接（自检用） |

## 安全边界

- 白名单文件必须 `root:root` 且不可被 group/other 写；`rootd_allow_file_ok()`
  会校验属主和权限，否则一律拒绝（防止 App 自己加自己）
- uid 0 和 2000 始终允许（rootd 自己 / adb shell）
- 抽象 socket 不落盘，重启即消失

## 实测结果（本机）

| 调用方 uid | 结果 |
|---|---|
| 0（root） | `id -u` → `0` |
| 2000（shell） | `id -u` → `0` |
| 1000（`--grant com.android.settings`） | `id -u` → `0` ✅ |
| 10999（未授权） | `ERR denied uid=10999` ✅ |

## 限制

1. **仅本次 boot 有效**：重启后 root、白名单、`su` 全部消失，需重跑步骤 1–3
2. 依赖 SELinux 处于 Permissive（stage 0 的产物），否则 App 域无法执行
   `/data/local/tmp/su`
3. 拿 root 是概率事件：stage 0 与 stage 1 各需一次命中，整轮约 1/4–1/6，
   通常 1–3 轮、2–6 分钟
4. 偶发命中后内核 oops → `panic_on_oops=1` → 看门狗复位重启（今晚出现过数次），
   重启后重来即可，不影响数据

## 与 KernelSU 的取舍

| | KernelSU LKM | 本方案 |
|---|---|---|
| 持久化 | 否 | 否 |
| 系统级 `su` 路径 | `/system/bin/su`（需管理器授权） | `/data/local/tmp/su` |
| 对 App 透明 | 是（标准 su 语义） | 需在 App 里写死路径 |
| 加载门槛 | CFI/CRC/struct module/KASAN/ABS32 五道 | 无 |
| 崩溃面 | LKM init 有额外风险 | 仅 exploit 本身 |

## 配套 APK：`o3p Root`

源码与构建脚本：`apk/`（不依赖 Gradle，直接用 SDK 命令行工具链构建）。

产物：`apk/build/o3p-root.apk`（12,691 B，debug 签名，包名 `o3.st.shell`）。

### 它怎么工作

不执行 `/data/local/tmp` 里的任何二进制，而是**直接连抽象 socket `@o3p_rootd`**：

```
App (uid 10175) --LocalSocket--> @o3p_rootd --fork/exec--> /system/bin/sh -c "<cmd>"
```

这样做的好处：不受 Android 10+ 对 app 域 exec 可写目录的限制，只依赖 socket 访问。

### 界面

- 命令输入框（默认 `id -u; getenforce`）
- **RUN AS ROOT** —— 执行输入的命令
- **STATUS** —— 打印 `id`、`getenforce`、`boot_id`
- **CLEAR** —— 清屏
- 下方滚动区显示输出，可长按选择复制

### 安装与授权

```bash
adb install -r apk/build/o3p-root.apk
adb shell '/data/local/tmp/o3p_new.bin --shell "/data/local/tmp/o3p_new.bin --grant o3.st.shell"'
adb shell am start -n o3.st.shell/.MainActivity
```

### 实测（本机，见 `docs/apk-root.png`）

App 进程 uid=10175，点 STATUS 后界面输出：

```
uid=0(root) gid=0(root) groups=0(root),1004(input),1007(log),1011(adb),...
context=u:r:shell:s0
---
Permissive
---
5e028eea-5c6e-4b47-9db2-a0c1c2cb8c04
__EXIT=0
```

### 重新构建

```powershell
pwsh -NoProfile -File apk\build.ps1
# 步骤：aapt2 link -> javac --release 11 -> d8 -> zip classes.dex -> zipalign -> apksigner
```

依赖：`F:\Android\Sdk\build-tools\35.0.0`、`platforms\android-35\android.jar`、
`C:\Program Files\Java\jdk-24`。首次运行会自动生成 `build/debug.keystore`。
