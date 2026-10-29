# o1p Root 使用说明

一个 APK 拿走完整 root：不需要电脑、不需要解锁 bootloader、不需要 KernelSU/Magisk。

---

## 这是什么

利用无线调试拿到 **shell 域**进程（`uid 2000`, `Seccomp 0`），在 shell 域里运行
CVE-2026-98260 exploit，得到：

```
rootd    uid 0, Seccomp 0, PPid=1, oom_score_adj=-1000, 忽略 HUP/TERM
su       /system/bin/su、/system/bin/suu、/system/bin/magisk → 转发给 rootd
```

因为命令实际在 rootd 里执行，**不继承任何应用的 seccomp 限制**，所以 `mount`、
`insmod` 这类操作都可用——这是「完整 root」和「应用域自越权」的本质区别。

---

## 前置条件

| 条件 | 说明 |
|---|---|
| 内核未修复 CVE-2026-98260 | POSIX CPU timer UAF（`exec`/`de_thread`） |
| 无线调试可用 | 需要**配对一次**，密钥长期保存 |
| 内核镜像未变 | payload 里有两个硬编码符号地址，换内核需重新适配 |

SELinux 处于 Enforcing 也可以，载荷自己会把 stage 0 做完。

---

## 首次使用（只做一次）

1. 安装 `o1p-root.apk`
2. 打开 App，点 **「配对（无线调试）」**
   - 会自动跳到开发者设置
   - 同时弹出说明 + 发一条通知
3. 在设置里：**无线调试 → 使用配对码配对设备**，屏幕上出现 6 位码
4. **下拉通知栏**，展开 `o1p：输入无线调试配对码`，填入 6 位码 → 发送
5. 看到 `② 立即配对（端口 xxxxx）→ 配对成功`

> 配对码只在那个页面有效，所以下拉通知栏输入——下拉不会关闭配对对话框。

配对一次之后，密钥存在 App 私有目录，**重启也不用再配对**。

---

## 日常使用

### 拿 root

1. 确认无线调试是开着的
2. 点 **「获取 root」**
3. 等右上角胶囊从灰色 `root未就绪` 变成绿色 `root已就绪`

exploit 有概率性，没命中就再点一次。日志里看到这些就是成功：

```
FAKE_TREE_ARMED att=N
UIDNOW uid=0 euid=0 gid=0
ROOTD sock ready
FULLROOT armed=1
su 部署: ALLOW uid 10404
```

### 给其他应用 root

1. 点 **「授权应用」**
2. 列表里勾选目标应用（可滑动，共 190+ 项）
3. 点「授权」

被授权的应用就能直接用：

```sh
su -c "id -u"        # → 0
suu -c "id -u"       # → 0
magisk su -mm -c "id -u"   # → 0
```

```java
// Java
Runtime.getRuntime().exec(new String[]{"/system/bin/su", "-c", "id -u"});
```

**未授权的应用会被拒绝**：`ERR denied uid=xxxxx`。

### 执行命令

底部输入框 + `RUN` 按钮，命令通过 rootd 执行（真 root）。
`STATUS` 查看 daemon 状态，`CLEAR` 清空输出。

---

## 按钮一览

| 按钮 | 作用 |
|---|---|
| **配对（无线调试）** | 跳转开发者设置 + 弹窗指引 + 发配对通知 |
| **获取 ROOT** | 在无线调试 shell 域跑载荷，拿完整 root |
| **本地越权（受限）** | 应用域自越权，`Seccomp=2`，只能做文件/权限类操作，不能 mount |
| **授权应用** | 勾选应用写入 rootd 白名单 |
| **清理痕迹** | 卸载 overlay、删 su/suu/magisk 和 `/data/local/tmp` 残留 |
| **RUN / STATUS / CLEAR** | 执行命令 / 查 daemon 状态 / 清屏 |

## 状态胶囊（右上角）

| 颜色 | 文字 | 含义 |
|---|---|---|
| 绿 | `root已就绪` | rootd 存活，su 可用 |
| 灰 | `root未就绪` | 没跑载荷，或 rootd 已退出 |

杀掉 App 不影响 rootd（它是 `PPid=1` 的独立进程），重开 App 会自动检测并点亮胶囊。

---

## 恢复银行类 App

这类 App 会检测 root，当前方案**没有隐藏能力**，所以只能切换使用：

1. 点 **「清理痕迹」**
   - 卸载 `/system/bin` 的 overlay
   - 删除 `su`、`suu`、`magisk`
   - 删除 `/data/local/tmp/o1p_*`、`o3p*`、`su_*` 等
2. **重启手机**

重启后自动清掉的：

| 痕迹 | 重启后 |
|---|---|
| SELinux `Permissive` | → `Enforcing` ✅ |
| `su` / `suu` / `magisk` | 消失 ✅ |
| rootd 进程 | 消失 ✅ |
| overlay 挂载 | 消失 ✅ |

之后银行 App 正常。想再用 root，重新点一次「获取 root」即可（不用重新配对）。

---

## 限制与注意

1. **root 和银行 App 不能共存** —— 没有 Magisk Hide/Shamiko 那层隐藏，`su` 文件、Permissive
   状态、rootd 进程都能被扫到。
2. **重启后 root 丢失** —— rootd 是内存态；但配对密钥和白名单（`/data/local/tmp/o1p_allow`）
   保留，只需重新「获取 root」。
3. **exploit 有概率** —— 一次没命中是正常的，多点几次。用 `10000 14000 300 1 12 1 8000 800`
   这组参数，实测 1~4 次内命中。
4. **换内核需要重新适配** —— payload 硬编码了 `init_user_ns` 和 `selinux_state` 两个地址。
   系统更新内核后需要重新提取（`kptr_restrict=2`，运行时读不到，只能从 vmlinux 离线提取）。
5. **别在系统异常时硬跑** —— 多轮连续尝试偶尔会触发 UWB 服务 `abort`，引起一次框架重启
   （内核不重启，rootd 不受影响）。

---

## 故障排查

| 现象 | 处理 |
|---|---|
| `root未就绪` 但记得有 root | rootd 可能被系统扰动带走了，点「获取 root」重来 |
| `ERR denied uid=xxxxx` | 该应用没授权，用「授权应用」勾选 |
| `释金载荷失败: EACCES` | `/data/local/tmp` 不可写，需要 `adb shell chmod 777 /data/local/tmp` |
| `找不到连接服务` | 无线调试被系统关了，重新打开（不用重新配对） |
| `EADDRINUSE` / bind 失败 | 残留 socket 占用，重启一次 |
| `su 部署: Text file busy` | 已忽略；su 本来就在跑，不影响 |

---

## 技术背景（简要）

```
无线调试 mDNS → SPAKE2 配对 → adb connect（shell 域, Seccomp=0）
  → CVE-2026-98260：exec/de_thread 里的 POSIX CPU timer UAF
  → tracefs kprobe 拿 KASLR slide
  → 回收 posix_timers_cache slab，伪造 RB 节点
  → rb_erase 任意写 → 清 selinux_state(enforcing)
  → 换 task_struct.cred（uid 0 + 全 capability）
  → fork 出 rootd（setsid、不 exec、CLOEXEC、oom 保护）
  → overlayfs 盖 /system/bin，放入转发型 su
```

四个曾经让整件事"看起来完全不工作"的坑：

1. rootd fork 后 `execve` → 内核按 dumpable 规则把 euid 重置回 ruid，rootd 变 shell 身份
2. rootd 缺 `setsid()` → adb 会话结束即被带走
3. `rootd_exec` 让子进程继承 listen socket → 名字泄漏，新 rootd `EADDRINUSE`
4. `su` 调 `setuid()` → App 的 seccomp 直接 `SIGSYS` 杀进程（`rc=159`）
