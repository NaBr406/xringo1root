# KernelSU LKM 加载：设备端五个坑与最终配方

设备内核：`6.18.21-android17-5-g1d099fcb35e0-abogki538445360-4k`（GKI，4K 页，`PANIC_ON_OOPS=y`）。

自己编译的模块要能 `insmod` 进去，必须同时满足下面五条。前四条已在本机验证通过，
第五条（kCFI）用 clang 重编后已验证：`hello.ko` 能加载成 `Live` 且 `rc=0`。

## 1. `struct module` 大小必须是 1664

```
module hello: .gnu.linkonce.this_module section size must match the kernel's
              built struct module size at run time
```

| 树 | sizeof(struct module) |
|---|---|
| 设备内核（BTF 实测） | **1664** |
| GKI `android17-6.18`（6.18.33）+ 设备 config | **1664** ✅ |
| vanilla 6.18.21 + 设备 config | 1344 ❌ |

结论：必须用 GKI 那棵树打模块，vanilla 6.18.21 不行。

## 2. 符号 CRC 对不上 → 把 `__version*` 段大小清零

```
kernelsu: disagrees about version of symbol module_layout
```

CRC 依赖 vendor 补丁（实测设备 `_printk` CRC = `0x16b5b21d`，我们 6.18.21 构建是
`0xe8213e80`），无法靠编译复现。做法：保留段名、把 `sh_size` 置 0。

- `has_crcs` 仍为真 → vermagic **只比较第一个空格之后的部分**，release 串不必一致
- 表里 0 条目 → 每个符号都退化成 `no symbol version for X`（仅警告）

工具：`wsl/50_zero_versions.py`

## 3. 调试信息产生的 `R_AARCH64_ABS32` 重定位不被支持

带 `-g` 编出来的模块有 ~3000 个 `R_AARCH64_ABS32`（来自 `.debug_*`），arm64 模块
重定位器不支持，静默返回 `-ENOEXEC`。`llvm-strip --strip-debug` 后归零。

## 4. KASAN 插桩 → `__asan_register_globals` 未定义

设备 config 开了 KASAN，模块会被插桩。在内核树里 `--disable KASAN` 后重编模块即可。

## 5. kCFI：必须用 clang 编（最后一道坎）

```
CFI failure at do_one_initcall+0xd4/0x374
  (target: kernelsu_init+0x0/0x140 [kernelsu]; expected type: 0x6fbb3035)
```

设备 config 是 `CONFIG_CFI=y`，GCC 不产生 kCFI 类型哈希，init 调用被拒绝，模块卡在
`Loading` 状态且**持住 module 互斥锁**，后续任何模块加载都会挂住（只能重启）。

解决：`LLVM=1` + 在内核树里 `--enable CFI --enable CFI_ICALL_NORMALIZE_INTEGERS`。

## 完整构建命令

```bash
cd /root/kernel-gki
make LLVM=1 olddefconfig && make LLVM=1 modules_prepare

cd /root/ksu/kernel          # v3.3.1 标签
sed -i 's/^obj-$(CONFIG_KSU) += kernelsu.o/obj-m += kernelsu.o/' Kbuild
printf '#include <linux/module.h>\nMODULE_IMPORT_NS("ANDROID_GKI_VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver");\n' > nsimport.c
echo 'kernelsu-objs += nsimport.o' >> Kbuild

make -C /root/kernel-gki M=$PWD ARCH=arm64 LLVM=1 \
     KCFLAGS="-Wno-error" KBUILD_MODPOST_WARN=1 -j$(nproc) modules

llvm-strip --strip-debug kernelsu.ko -o kernelsu-st.ko
python3 50_zero_versions.py kernelsu-st.ko kernelsu-final.ko
```

产物：`o3root-port/lkm/ksu-dijun-cfi.ko`（835,336 B），打包后
`o3root-port/build/o3p_ksu_cfi.bin`（909,384 B）。

## 验证状态

| 项 | 结果 |
|---|---|
| `hello.ko`（同配方） | `insmod rc=0`，`/proc/modules` 显示 `hello ... Live` ✅ |
| `kernelsu.ko` | 已按同配方产出；载荷跑到 `KSU_WROTE` / `KSU_EXEC`，最后两次因命中率未走到该阶段 |

载荷命中率约 1/6，需要多跑几次；一旦 `KSU_MODULE LIVE` 后再装管理器：

```bash
adb install -r o3root-port/KernelSU-manager.apk
```

## 注意

- 模块卡在 `Loading` 时**不要继续 insmod 别的模块**（module 锁被占住），直接重启。
- 若 `insmod` 报 `Exec format error` 且 dmesg 无输出：优先怀疑 ABS32 重定位（没 strip）。
- 若报 `CFI failure`：模块不是 clang 编的。
- 若报 `.gnu.linkonce.this_module section size`：用的是 vanilla 树，换成 GKI 树。
