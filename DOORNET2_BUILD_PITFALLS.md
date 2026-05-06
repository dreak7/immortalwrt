# DoorNet2 固件编译避坑总结

这份文档记录了这次从 0 开始，把 `ImmortalWrt 6.12` 适配到 `DoorNet2 (RK3399)` 并成功编译出带 `Docker + iStore + 指定插件` 固件的全过程。

目标不是重复步骤说明，而是把这次真正踩过、浪费时间最多、以后最容易再次踩到的坑总结出来，方便下次直接绕开。

## 1. 这次最终成功的结果

最终成功生成的 DoorNet2 固件产物在：

- `/tmp/immortalwrt-build/bin/targets/rockchip/armv8/immortalwrt-rockchip-armv8-embedfire_doornet2-squashfs-sysupgrade.img.gz`
- `/tmp/immortalwrt-build/bin/targets/rockchip/armv8/immortalwrt-rockchip-armv8-embedfire_doornet2-ext4-sysupgrade.img.gz`
- `/tmp/immortalwrt-build/bin/targets/rockchip/armv8/immortalwrt-rockchip-armv8-embedfire_doornet2.manifest`

最终固件已确认包含：

- `Docker` 相关：`containerd`、`runc`、`dockerd`
- `iStore` 相关：`luci-app-store`、`luci-lib-taskd`、`opkg`、`luci-lib-ipkg`、`libuci-lua`、`mount-utils`、`xz-utils`
- 指定插件中本次实际成功进入固件的一批包：`luci-app-openclash`、`mosdns`、`luci-app-smartdns`、`luci-app-argon-config`、`luci-app-filebrowser`、`luci-app-firewall`、`luci-app-upnp`、`luci-app-sqm`、`luci-app-ttyd`、`luci-app-acme`、`luci-app-diskman`、`luci-app-frpc`、`luci-app-minidlna`、`luci-app-natmap`、`luci-app-netdata`、`luci-app-qos`、`luci-app-ramfree`、`luci-app-udpxy`、`luci-app-zerotier`

## 2. 这次改动的核心方向

本次不是单纯“加几个插件”，而是同时做了 4 类工作：

1. 新增 DoorNet2 设备适配。
2. 让 RK3399 DoorNet2 在 ImmortalWrt 6.12 上能正常生成镜像。
3. 接入 `kenzok8/openwrt-packages` 和官方 `linkease/istore`。
4. 解决 ImmortalWrt 当前 APK 打包体系下，`iStore` 和 `base-files` 的兼容问题。

## 3. 这次已验证可行的源策略

这次最后验证通过的源策略是：

- `kenzo` 继续作为第三方插件参考源：
  - `src-git kenzo https://github.com/kenzok8/openwrt-packages.git`
- `iStore` 只认官方源：
  - `src-git istore https://github.com/linkease/istore;main`

关键经验：

- `luci-app-store` 不要继续混用 `kenzo` 的同名/相关包。
- `luci-app-store` 的唯一来源应当是官方 `istore` feed。
- 其它插件仍然可以继续保留在 `kenzo`。

## 4. DoorNet2 适配本身的关键点

DoorNet2 最终采用的思路不是自己从头找一套新 U-Boot，而是尽量复用已有成熟板型：

- SoC：`rk3399`
- DTS：新增 `rk3399-doornet2.dts` / `rk3399-doornet2.dtsi`
- U-Boot 映射：复用 `nanopi-r4se-rk3399`

这个方向最终证明是可行的，重点不是“完全原创适配”，而是：

- DTS 对硬件资源描述要正确。
- 镜像打包流程要和 Rockchip 现有生成逻辑兼容。
- U-Boot 名称映射要落在 ImmortalWrt 现有可用产物上。

## 5. 以后最容易重踩的坑

### 坑 1：WSL/Windows PATH 污染会直接打爆 Rockchip 镜像阶段

这次最隐蔽但也最典型的问题之一是：

- 编译到 `mkimage` 阶段时出现：
  - `/bin/sh: 1: Syntax error: "(" unexpected`

根因不是 `mkimage` 本身坏了，而是外部 PATH 混进了 Windows 路径：

- 典型污染项：
  - `Program Files (x86)`
  - 带空格和括号的 Windows 软件目录

这些路径被塞进 `PATH=... mkimage ...` 这样的 shell 命令后，会把 `(` 解释坏，直接导致镜像阶段失败。

规避方法：

- 编译时不要直接继承当前 WSL 的整条 PATH。
- 始终用干净 Linux PATH 启动 `make`。

推荐命令：

```bash
env PATH=/tmp/immortalwrt-build/staging_dir/host/bin:/tmp/immortalwrt-build/staging_dir/toolchain-aarch64_generic_gcc-14.3.0_musl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin make -j1 V=s
```

结论：

- 只要是 WSL 下编译 ImmortalWrt，尤其 Rockchip、U-Boot、mkimage 相关目标，一律默认先怀疑 PATH 污染。

### 坑 2：Rootfs 分区大小不够时，ext4 失败不是插件坏了，而是镜像装不下

这次早期真实报错之一是 ext4 根分区分配失败，本质上是 rootfs 太小。

最后验证通过的分区方案是：

- `CONFIG_TARGET_KERNEL_PARTSIZE=64`
- `CONFIG_TARGET_ROOTFS_PARTSIZE=1024`

同时设备侧用了：

- `RKIMG_ROOTFS_PARTSIZE := 1024`

经验：

- DoorNet2 这类要塞 Docker、OpenClash、mosdns、iStore、diskman、netdata 的固件，512M rootfs 非常容易不够。
- 如果插件较多、还要 ext4 镜像，`1024M rootfs` 更稳。

### 坑 3：Rockchip 镜像 Makefile 里直接复用 `ROOTFS_PARTSIZE` 容易和全局配置打架

这次为了解决 DoorNet2 设备侧 rootfs 分区大小覆盖，需要避免和全局 `CONFIG_TARGET_ROOTFS_PARTSIZE` 冲突。

最终采用的做法是：

- 在 Rockchip 镜像逻辑中使用设备侧变量：
  - `RKIMG_ROOTFS_PARTSIZE`

经验：

- 设备特定分区大小不要粗暴复用通用变量名。
- Rockchip image 生成逻辑里，设备级变量最好和全局配置分开。

### 坑 4：ImmortalWrt 当前 APK 体系下，`base-files` 版本格式非常敏感

这是这次最关键的真实阻塞点之一。

曾经尝试把 `base-files` 版本改成：

- `1-980833ac8d`

结果 `apk mkpkg` 直接报错：

- `package version is invalid`

最终验证可行的写法是：

- `1~980833ac8d`

也就是在 `package/base-files/Makefile` 中：

- `VERSION:=$(PKG_RELEASE)~$(lastword $(subst -, ,$(REVISION)))`
- `base-files.version` 也要同步写成 `~`

经验：

- 在 APK 体系下，不要想当然地把 OpenWrt/旧 opkg 时期常见版本写法原样搬过来。
- 如果强制重跑 `package/install`，`base-files` 是最先会暴露出版本格式问题的基础包。

### 坑 5：看到镜像已经出包，不代表 rootfs 真正按最新包重装过

这次一个非常容易误判的地方是：

- 旧镜像文件已经存在
- 新包也已经编出来了
- 但最终 manifest 里仍然没有 `luci-app-store`

根因不是 `luci-app-store` 没编出来，而是：

- 那次镜像只是沿用了旧 rootfs 结果
- `package/install` 没有按最新包仓库真正重装 rootfs

判断方法：

- 不要只看 `bin/targets/.../*.img.gz` 是否存在。
- 必须看：
  - 最终 `manifest`
  - `apk add` 的 rootfs 安装日志
  - 最终文件时间戳

经验：

- “包编出来了” 和 “包真的进 rootfs 了” 是两回事。
- 对 APK 体系尤其要看 `package/install` 有没有真正跑过。

### 坑 6：`luci-app-store` 编译成功，不代表它在 APK 下就能正常入包

官方 `istore` feed 里的 `luci-app-store` 在这次环境下原始写法会有 APK 兼容问题。

最终验证通过的修法是：

- `PKG_VERSION:=0.1.32`
- `PKG_RELEASE:=1`
- `APP_STORE_VERSION` 保持前端展示版本：
  - `$(PKG_VERSION)-$(PKG_RELEASE)`

已经把这个修补固化为仓库内脚本：

- `/tmp/immortalwrt-build/scripts/doornet2-apply-feed-patches.sh`

对应 patch：

- `/tmp/immortalwrt-build/scripts/patches/istore-luci-app-store-apk.patch`

推荐流程：

```bash
./scripts/feeds update -a
./scripts/feeds install -a
./scripts/doornet2-apply-feed-patches.sh
```

经验：

- 官方 feed 并不一定天然适配当前这棵 ImmortalWrt + APK 构建树。
- 只改本地 `feeds/istore/...` 不够，必须把修补方法固化到主仓，避免下次重新拉 feed 后又丢失。

### 坑 7：`luci-app-turboacc` 没进固件，不是“编译失败”，而是当前树里根本没有完整实现路径

这次已经确认：

- 当前树没有完整的 `luci-app-turboacc + shortcut-fe` 可用实现
- 当前系统主要路径是：
  - `firewall4 + nftables + flow offload`

经验：

- 如果只是“想要 TurboACC”，不要默认它在新内核、nftables、ImmortalWrt APK 体系下就一定有现成可编状态。
- 这类包要先确认：
  - 包是否存在
  - 依赖内核模块是否存在
  - 当前防火墙栈是否匹配

## 6. 这次最终验证通过的推荐重编流程

以后如果要在这套源码上重新编译 DoorNet2 固件，推荐按这个顺序：

```bash
git clone git@github.com:dreak7/immortalwrt.git
cd immortalwrt
git checkout codex/doornet2-firmware
./scripts/feeds update -a
./scripts/feeds install -a
./scripts/doornet2-apply-feed-patches.sh
```

确认 `.config` 后，用干净 PATH 编译：

```bash
env PATH=/tmp/immortalwrt-build/staging_dir/host/bin:/tmp/immortalwrt-build/staging_dir/toolchain-aarch64_generic_gcc-14.3.0_musl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin make -j1 V=s
```

如果只是重做最终镜像和 rootfs，可优先：

```bash
env PATH=/tmp/immortalwrt-build/staging_dir/host/bin:/tmp/immortalwrt-build/staging_dir/toolchain-aarch64_generic_gcc-14.3.0_musl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin make package/install target/linux/install V=s -j1
```

## 7. 编译后必须检查的 4 个点

每次不要只看“有没有 `.img.gz`”，至少检查下面 4 项：

1. `manifest` 是否刷新到本次时间。
2. `manifest` 里是否真的有目标包。
3. `img.gz` 时间戳是否刷新。
4. 关键包是否出现在 rootfs 安装日志里。

这次用于确认 iStore 已真正入包的关键检查项是：

- `luci-app-store`
- `luci-lib-taskd`
- `opkg`
- `libuci-lua`
- `mount-utils`
- `xz-utils`

示例检查：

```bash
rg -n '^luci-app-store - |^luci-lib-taskd - |^opkg - |^mount-utils - |^libuci-lua - |^xz-utils - ' \
  bin/targets/rockchip/armv8/immortalwrt-rockchip-armv8-embedfire_doornet2.manifest
```

## 8. 这次最值得记住的结论

如果以后只记 6 条，记下面这些：

1. 在 WSL 下编译 Rockchip，必须先清理 PATH 污染。
2. Docker + iStore + OpenClash 这类大包组合，DoorNet2 rootfs 直接上 `1024M` 更稳。
3. 不要把“包编出来了”等同于“包进固件了”。
4. `base-files` 在 APK 体系下的版本格式必须谨慎，`1~hash` 可行，`1-hash` 这次已证实会炸。
5. `luci-app-store` 必须走官方 `istore` feed，且要应用本仓库里的本地 APK 兼容 patch。
6. 出包后一定看 `manifest`，它比“镜像文件存在”更能说明真实结果。

## 9. 当前这条分支的意义

当前分支：

- `codex/doornet2-firmware`

已经包含：

- DoorNet2 设备适配
- 官方 `istore` feed 接入
- DoorNet2 默认包列表调整
- `base-files` APK 兼容修复
- `luci-app-store` 的 feed patch 固化脚本

所以以后如果要继续基于这次结果编译，不要再从完全原始的上游状态重新摸索，优先直接从这条分支开始。
