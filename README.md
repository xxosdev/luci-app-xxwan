# luci-app-xxwan — OpenWrt 多线策略路由与故障切换

OpenWrt LuCI 的多线（多 WAN）策略路由插件，以 **pbr** 为底层，按优先级（Tier）管理多条外网线路：持续探测线路存活，主线路故障时自动把出口切到备线，恢复后自动切回。全部操作在 LuCI 网页完成，无需命令行。

- 当前版本：`1.0.2`（`PKG_VERSION`）
- 适用：OpenWrt 21.02+（opkg）/ OpenWrt 25.12+（apk）
- 许可：GPL-2.0

---

## 核心功能

| 功能 | 说明 |
|---|---|
| 线路优先级（Tier） | 每条线路指定 Tier 1 / 2 / 3。系统按优先级从高到低，选择**第一条在线**的线路作为出口；高优先级线路恢复后自动切回 |
| 存活探测 | 每条线路独立配置探测方式：**ICMP Ping**（多目标）或 **HTTP cURL**（URL + 期望状态码，默认 204）。探测间隔、判定离线/恢复所需次数均可调 |
| 自动故障切换 | 连续失败达阈值判定离线 → 切换出口；连续成功达阈值判定恢复 → 切回。默认间隔 5 秒、离线/恢复各 3 次 |
| 全局出口策略 | 未命中分流规则的流量：可选「自动（按优先级选可用线路）」或**固定**某条线路（不自动切换） |
| 分流规则 | 按 源 IP / 源 MAC / 源端口 / 目标 IP / 目标域名 / 目标端口 / 协议 匹配，指定出口线路；支持三个防火墙链（prerouting 局域网设备 / output 路由器本机 / forward 纯转发）；规则按顺序匹配，第一条命中生效 |
| 固定出口（strict_bind） | 规则可勾选「固定出口」：即使该线路离线也不切换，该流量中断（用于必须走指定线路的场景） |
| 切换动作 | 切换时可**清除连接跟踪表**（三种模式：每次切换 / 仅恢复时 / 不清除）、重启指定服务（如 ddns、wireguard）使其重建连接 |
| Hook 脚本 | 线路离线/恢复时执行自定义脚本，变量 `$XXWAN_EVENT`（UP/DOWN）、`$XXWAN_IFACE`（线路名） |
| Webhook 通知 | GET/POST 推送，支持变量 `$EVENT` / `$IFACE` / `$IP` / `$TIME` / `$HOSTNAME`；页面提供「发送测试」按钮 |
| 严格模式 | 所有线路都离线时阻断流量，避免流量从非预期出口漏出 |
| 服务控制 | 「全局设置」页显示**引擎运行状态**（`[运行中]`/`[未运行]`），并提供「启动服务」/「停止服务」按钮。「启动服务」会自动勾选「启用 XXWAN」并立即启动后台引擎 |
| 备份与恢复 | 一键导出 `/etc/config/xxwan`；上传备份文件恢复（校验 UCI 格式，恢复前自动留存 `.bak`） |
| 运行日志 | 记录探测结果与切换过程，页面可刷新/清空，日志落 `/var/log/xxwan.log`（tmpfs，不磨损闪存） |

**依赖**（`Makefile` `DEPENDS`，编译安装自动拉齐）：

```
+pbr        # 策略路由底层（本插件只改它的 uplink_interface，不动路由表与防火墙）
+curl       # HTTP 探测与 Webhook 通知
+conntrack  # 切换时清理连接跟踪表
+luci-base
```

> ⚠ **pbr 有两级开关**：`/etc/init.d/pbr enable`（开机自启）与 `pbr.config.enabled`（功能开关）。只 enable 不置 1 的话分流规则不会生效。本插件在「全局设置」页的「PBR 操作」一行提供「启用并重启 PBR」与「停止 PBR」两个按钮，一次搞定开关 + 自启 + 服务启停。

---

## 目录结构

```
luci-app-xxwan/
├── Makefile                                        # OpenWrt feed 打包（依赖 / conffiles / postinst·prerm·postrm）
├── LICENSE                                         # GPL-2.0 全文
├── .gitattributes                                  # * -text（禁止换行符转换）
├── .gitignore
└── root/
    ├── etc/config/xxwan                            # 默认 UCI 配置（conffile 保护，升级不丢活配置）
    ├── etc/init.d/xxwan                            # procd 守护服务（S95 / K10，respawn）
    ├── usr/sbin/xxwan-daemon                       # 探测与切换守护进程（busybox ash）
    ├── usr/sbin/xxwan-install                      # 在线安装 / 升级 / 卸载 / 状态查询
    └── usr/lib/lua/luci/
        ├── controller/xxwan.lua                    # 菜单与路由（含隐藏的备份下载接口）
        ├── model/cbi/xxwan/
        │   ├── basic.lua                           # 全局设置
        │   ├── iface.lua                           # 线路接口
        │   ├── rule.lua                            # 分流规则
        │   ├── advanced.lua                        # 动作与通知
        │   ├── log.lua                             # 运行日志
        │   ├── backup.lua                          # 备份与恢复
        │   └── about.lua                           # 关于
        └── view/xxwan/
            └── svc_buttons.htm                     # 「启动服务 / 停止服务」同排按钮
```

菜单入口：**网络 → XXWAN 多线策略**（`admin/network/xxwan`），共 7 个页面。

---

## 安装 / 编译

### 方式一：随固件编译（推荐，依赖自动拉齐）

```sh
cp -r luci-app-xxwan <openwrt>/package/luci-app-xxwan

make menuconfig    # LuCI → 3. Applications → luci-app-xxwan 选 <M>
make package/luci-app-xxwan/compile V=s
# 产物：bin/packages/<arch>/base/luci-app-xxwan-1.0.2-r1.apk（25.12+）
#                    bin/packages/<arch>/base/luci-app-xxwan_1.0.2-r1_all.ipk（23.05-）
```

`/etc/config/xxwan` 已声明为 conffile，升级不会覆盖你的活配置。`postinst` 会自动 `chmod +x`、`/etc/init.d/xxwan enable`，并在 pbr 功能开关未打开时给出提示；`prerm` 在删文件前先停服务、清自启；`postrm` 清理状态文件与 LuCI 缓存。

### 方式二：在线安装 / 升级 / 卸载（`xxwan-install`）

新机器一条命令：

```sh
wget -O /tmp/xxwan-install \
  https://raw.githubusercontent.com/xxosdev/luci-app-xxwan/main/root/usr/sbin/xxwan-install
sh /tmp/xxwan-install install
```

装过一次之后脚本会随包落到 `/usr/sbin/xxwan-install`，之后直接 `xxwan-install upgrade` 即可，不用再去取脚本。

```sh
xxwan-install install                 # 首次安装
xxwan-install upgrade                 # 升级（默认保留配置）
xxwan-install uninstall               # 卸载（默认保留配置，卸载后自动拷回）
xxwan-install info                    # 探测本机环境与安装状态
```

| 选项 | 说明 |
|---|---|
| `--keep-config` | 保留 `/etc/config/xxwan`（升级/卸载的默认行为） |
| `--no-keep-config` | 不保留：升级即恢复出厂默认，卸载连配置一起清 |
| `--from=<路径>` | 本地介质：源码 `.tar.gz` 或项目目录（离线/调试） |
| `--branch=<main>` | 指定分支，默认 `main` |
| `--mirror=<前缀>` | 下载镜像前缀，如 `https://ghfast.top/` |
| `--force` | 已安装也继续装 |
| `--yes` | 非交互，所有询问取默认值 |

装完浏览器打开 `http://<设备IP>/cgi-bin/luci/` → **网络 → XXWAN 多线策略**；菜单没出现就 Ctrl+F5 强刷。

> ⚠ **安装脚本不会自动启动服务**（避免安装瞬间改变网络）。装完请到「全局设置」页点一次「启动服务」，或执行 `/etc/init.d/xxwan start`；重启设备也会自动启动。
>
> 为什么专门做了这个按钮：`/etc/init.d/xxwan start` 在 `xxwan.main.enabled` 不为 `1` 时**会成功返回但什么都不做**（rc=0、无输出、无进程），命令行下极易被误判成"启动不了"。页面上的「启动服务」会**自动帮你勾上「启用 XXWAN」再启动**，不会踩这个坑；若确实未启用，命令行 `start` 现在也会明确打印跳过原因与启用命令。

> ⚠ **卸载为什么要"补扫残留"**：本机包数据库登记的版本可能与实际文件不一致（手动覆盖过就对不上），`apk del` / `opkg remove` 会按**旧清单**删文件、漏掉后来新增的。脚本在包管理器删完后会按**内置清单**（13 个文件）再扫一遍补删。
>
> ⚠ **卸载时脚本会先把自己复制到 `/tmp/xxwan-install`** 再删文件，所以删到一半中断也能重新跑。

---

## 使用步骤

1. **确认依赖就位**：安装 `pbr`、`curl`、`conntrack`，并在「全局设置」页点一次「启用并重启 PBR」（它会 `uci set pbr.config.enabled='1'` + commit + enable + restart）。旁边的「停止 PBR」则相反：`enabled='0'` + commit + `pbr disable` + `pbr stop`，用于彻底关闭（之后 XXWAN 的分流与故障切换都会失效）。
2. **添加线路**（「线路接口」页）：选择网络接口、指定优先级（Tier 1/2/3）、选探测方式并填探测目标。默认配置已预置 `wan`（Tier 1）与 `wan2`（Tier 2）两条，按实际接口名调整即可。
3. **（可选）配置分流规则**（「分流规则」页）：为指定设备或目标配置固定出口；不做规则则所有流量走全局出口策略。
4. **（可选）配置切换动作与通知**（「动作与通知」页）：连接跟踪清理模式、切换后要重启的服务、Hook 脚本、Webhook。
5. **启用并启动**：回到「全局设置」页，先看「引擎运行状态」是否为 `[运行中]`：
   - 若显示 `[未运行]`，勾选「启用 XXWAN」→「保存并应用」，再点「启动服务」；或直接点「启动服务」（它会自动勾上「启用 XXWAN」并立即启动引擎）。
   - 「停止服务」只停后台引擎、**不改变「启用 XXWAN」开关**，所以重启设备后仍会自启；要彻底不自启请取消勾选该开关。

   启动后页面顶部「线路状态」会显示当前出口。
6. **验证**：把主干线路拔掉/断开，观察「运行日志」与「线路状态」是否在数次探测内切换到备线。

---

## 工作机制要点

- **只改一条 UCI 选项**：切换出口的本质是改 pbr 的 `uplink_interface`（以及本插件在 pbr 里维护的 `xxwan_*` policy 段），**不动路由表、不改防火墙**，因此不会像整份 network restart 那样打断无关接口。
- **探测与切换分离**：`xxwan-daemon` 按 `check_interval` 轮询各线路；只有状态**发生变化**时才落盘（`sync_network_state`）并触发切换动作，避免每轮都写配置造成闪存写放大。
- **首次探测走快通道**：守护进程启动后第一轮立即完成全部线路探测，避免出现"刚启动时误判全部在线"的假在线窗口。
- **输入钳制**：`check_interval` / `fail_threshold` / `restore_threshold` 若被填成非数字或 0，守护进程会回退到安全默认值（`sleep 0` 会变成忙等吃满 CPU）。
- **连接跟踪清理是双刃剑**：`conntrack -F` 会清掉路由器上**所有**现有连接（含当前 SSH / 网页管理会话与其他设备的下载、在线游戏），所以默认虽为「每次切换时清除」，但页面已明确提示；不需要时改成「仅线路恢复时清除」或「不清除」。
- **恢复配置为何延迟重启**：恢复备份后若同步重启引擎，`conntrack -F` 会把承载成功提示的那条 HTTP 连接一起清掉，用户看不到结果。所以重启放在后台并延迟 3 秒。
- **备份恢复复用 CBI 表单**：CBI 页面本身已被包在 `<form method="post" enctype="multipart/form-data">` 里，所以上传控件直接用外层表单，**不再嵌套 `<form>`**（嵌套 form 是非法 HTML，浏览器会丢掉内层开始标签、并用内层 `</form>` 提前关掉外层表单）。CSRF `token` 随外层表单一起提交。

---

## 已知限制

- **切换会短暂中断现有连接**（尤其开启连接跟踪清理时），这是策略路由故障切换的固有代价。
- **`ip route del` 清理默认路由是按 `metric 1` 匹配的**：停服务时会删除 `metric 1` 的默认路由，若本机其他服务也依赖 `metric 1` 默认路由可能受牵连，请留意。
- **IPv6 默认不接管**：跨运营商多线环境下接管 IPv6 可能导致不通，故默认关闭。
- 探测的 ping 包数量、日志过滤等尚不可配置（当前为内置默认值）。

---

## 许可

GPL-2.0（见 `LICENSE`）。
