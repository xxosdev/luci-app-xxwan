local sys = require "luci.sys"
-- ★ 必须用 nixio.fs：LuCI Master（ucode 版）已移除 luci.fs 模块，
--   写成 require "luci.fs" 页面会直接 500（真机实测：
--   module 'luci.fs' not found）。同目录 log.lua / backup.lua 用的也是 nixio.fs。
local fs = require "nixio.fs"
local util = require "luci.util"

local m = Map("xxwan", translate("切换动作与通知"), translate("线路切换时执行的动作，以及通知推送配置。"))
local s = m:section(NamedSection, "advanced", "advanced", "")
s.anonymous = true

-- 分组标题：和「全局设置」页保持同一套观感（DummyValue + rawhtml 画一条带下划线的标题）
local _gid = 0
local function group(title, top)
    _gid = _gid + 1
    local d = s:option(DummyValue, "_g" .. _gid, "")
    d.rawhtml = true
    d.default = "<h4 style='color:var(--brand, var(--primary-color-high, var(--primary, #1976d2))); " ..
        (top and "margin-top:30px; " or "") ..
        "margin-bottom:10px; border-bottom: 1px solid var(--hairline, var(--border-color-medium, var(--light, #ced4da))); padding-bottom: 5px;'>" ..
        title .. "</h4>"
end

-- ══ 一、切换时的动作 ═══════════════════════════════════════════════════
group(translate("切换时的动作"))

local flush = s:option(ListValue, "conntrack_flush", translate("清除连接跟踪表"),
    translate("切换线路时清除已有连接，让连接快速重建。注意：清空整张表会中断路由器上当前所有网络连接，包括 SSH、网页管理与其他设备的下载和在线游戏。"))
flush:value("always", translate("每次切换时清除（默认）"))
flush:value("restore", translate("仅线路恢复时清除"))
flush:value("never", translate("不清除"))
flush.default = "always"

local scope = s:option(ListValue, "conntrack_scope", translate("清除范围"),
    translate("「整张表」= 清空所有连接（影响面最大）；「仅故障线路」= 只删除与刚离线那条线路相关的连接，影响面小得多。" ..
        "注意后者是尽力而为：底层 conntrack 没有接口过滤，只能按该线路 NAT 后的地址匹配，因此没走 NAT 的流量可能漏删。"))
scope:value("all", translate("整张表（默认，影响所有连接）"))
scope:value("iface", translate("仅故障线路相关（影响面小）"))
scope.default = "all"
scope:depends("conntrack_flush", "always")
scope:depends("conntrack_flush", "restore")

local on_boot = s:option(Flag, "actions_on_boot", translate("引擎启动时也执行上述动作"),
    translate("默认关闭。引擎每次启动（含重启设备）都会走一遍首轮同步；若开启，则每次启动都会清一次连接跟踪表并重启下面的服务 —— 即使一条线路都没有切换过。"))
on_boot.default = "0"
on_boot.rmempty = false

local svcs = s:option(DynamicList, "reload_services", translate("切换时重启的服务"),
    translate("线路切换后自动重启这些服务，使其重新建立连接。常用服务已排在列表最前面；列表里没有就直接输入服务名（对应 /etc/init.d/ 下的脚本名）。服务不存在或执行失败都会写入运行日志。"))
svcs.rmempty = true
-- 常用服务排前面，其余按 sys.init.names() 的顺序跟在后面，省得在 50 多项里翻
local COMMON = { "ddns", "mwan3", "wireguard", "openvpn", "nginx", "uhttpd", "dnsmasq",
                 "smbd", "aria2", "transmission", "frpc", "zerotier", "stubby" }
local _have = {}
for _, v in ipairs(sys.init.names()) do _have[v] = true end
for _, v in ipairs(COMMON) do
    if _have[v] then svcs:value(v, v); _have[v] = nil end
end
for _, v in ipairs(sys.init.names()) do
    if _have[v] then svcs:value(v, v) end
end

local ract = s:option(ListValue, "reload_action", translate("服务操作方式"),
    translate("restart = 完整重启，最彻底；reload = 只让服务重读配置，轻量得多，但并非所有服务都支持（不支持时会失败并记入日志）。"))
ract:value("restart", translate("restart（完整重启，默认）"))
ract:value("reload", translate("reload（仅重载配置）"))
ract.default = "restart"

-- ══ 二、自定义脚本 ═════════════════════════════════════════════════════
group(translate("自定义脚本"), true)

local HOOK_VARS = translate(
    "可用变量：$XXWAN_EVENT（UP/DOWN）、$XXWAN_IFACE（线路名）、$XXWAN_TIER（优先级）、" ..
    "$XXWAN_IP / $XXWAN_WAN_IP（该线路 WAN 口 IPv4 地址）、" ..
    "$XXWAN_IPV6 / $XXWAN_WAN_IPV6（该线路 WAN 口 IPv6 地址）、" ..
    "$XXWAN_WAN_PREFIX6（该线路拿到的 IPv6 委派前缀 PD，形如 2408:824c:832:420::/60）、" ..
    "$XXWAN_TIME（时间）、$XXWAN_HOSTNAME（主机名）、" ..
    "$XXWAN_OLD_IFACE / $XXWAN_NEW_IFACE（切换前后的出口）。")

s:option(TextValue, "hook_down", translate("线路离线时执行的脚本"), HOOK_VARS).rows = 3
s:option(TextValue, "hook_up", translate("线路恢复时执行的脚本"), HOOK_VARS).rows = 3

local hto = s:option(Value, "hook_timeout", translate("脚本超时（秒）"),
    translate("★ 脚本在探测循环里执行。没有超时保护的话，脚本里一个 sleep、一个没加 -m 的 curl，" ..
        "或者一个等待输入的 read，就会让整轮探测停摆 —— 此后线路状态不再更新、故障切换彻底失效。" ..
        "默认 15 秒，超时会被强制终止并写入运行日志。"))
hto.default = "15"
hto.datatype = "range(1,300)"

local hbg = s:option(Flag, "hook_background", translate("脚本在后台执行"),
    translate("默认关闭 = 同步执行（但有上面的超时兜底），脚本里的操作与后续动作有确定的先后顺序。" ..
        "开启后脚本完全不阻塞探测，但先后顺序不再有保证 —— 只有脚本耗时较长、且不关心时序时才建议开启。"))
hbg.default = "0"
hbg.rmempty = false

local htest = s:option(Button, "_hook_test", translate("测试执行脚本"),
    translate("立即执行一次脚本并等待结果，输出写入「运行日志」页。脚本里 $XXWAN_IFACE 为模拟值 TEST_IFACE，其余变量为测试值。"))
htest.template = "xxwan/svc_buttons"
htest.inputtitle = translate("测试离线脚本")
htest.inputstyle = "apply"
htest.inputvalue = "down"
htest.inputtitle2 = translate("测试恢复脚本")
htest.inputstyle2 = "action"
htest.inputvalue2 = "up"
function htest.write(self, section, value)
    -- 点击提交按钮时整张表单本来就会提交，但 UCI 的 commit 在 LuCI 收尾阶段才发生；
    -- 这里显式 commit 一次，确保 daemon 读到的是刚填进去的值。
    sys.call("uci commit xxwan 2>/dev/null")
    sys.call("/usr/sbin/xxwan-daemon test_hook %s >/dev/null 2>&1 &" % (value == "up" and "up" or "down"))
end

-- ══ 三、通知推送 ═══════════════════════════════════════════════════════
group(translate("通知推送（Webhook）"), true)

-- 事件开关用三个 Flag 而不是一个多选列表：Flag 未勾选会明确写 0，
-- 而多选列表被清空后会变成"没有值"，daemon 那边就只能猜（历史行为是 DOWN/UP 都发）。
local evd = s:option(Flag, "notify_down", translate("线路离线时通知"))
evd.default = "1"; evd.rmempty = false

local evu = s:option(Flag, "notify_up", translate("线路恢复时通知"))
evu.default = "1"; evu.rmempty = false

local evs = s:option(Flag, "notify_switch", translate("出口切换时通知"),
    translate("★ 出口从一条线路换到另一条时，额外发一条 $EVENT=SWITCH 的通知，变量里带 " ..
        "$OLD_IFACE（切换前）与 $NEW_IFACE（切换后）。这条最贴近「我的出口变了」这个实际感受，" ..
        "不必再自己把「A 离线」和「B 恢复」两条通知拼起来。"))
evs.default = "1"; evs.rmempty = false

local md = s:option(ListValue, "webhook_method", translate("请求方式"))
md:value("GET", "GET"); md:value("POST", "POST"); md.default = "GET"

s:option(Value, "webhook_url", translate("Webhook 地址"),
    translate("支持变量 —— IPv4：$WAN_IP（该线路 WAN 口地址）、$PUBLIC_IP（公网出口 IP）；" ..
        "IPv6：$WAN_IPV6（该线路 WAN 口地址）、$WAN_PREFIX6（该线路拿到的委派前缀 PD）、$PUBLIC_IPV6（公网出口 IPv6）；" ..
        "通用：$EVENT、$IFACE、$TIER、$TIME、$HOSTNAME、$OLD_IFACE、$NEW_IFACE。" ..
        "旧别名 $IP = $WAN_IP、$IPV6 = $WAN_IPV6 仍然可用。" ..
        "★ $WAN_IPV6 / $WAN_PREFIX6 / $PUBLIC_IPV6 三者**互不相同**（真机实测）：" ..
        "$WAN_IPV6 是 OpenWrt 那个独立 wan6 接口上 WAN 侧的 /64 地址（如 2408:824c:802:2add:…）；" ..
        "$WAN_PREFIX6 是运营商委派给 LAN 的整段 PD（如 2408:824c:832:420::/60），双宽带时每条线各有一个；" ..
        "$PUBLIC_IPV6 是路由器实际对外用的地址，通常落在 PD 里面。" ..
        "要汇报「外面看到的地址」用 $PUBLIC_IPV6；要汇报「这条线拿到哪个网段」用 $WAN_PREFIX6。"))

-- ★ 强制绑定线路设备改为开关（默认关）。原实现无条件加 --interface，
--   但「通知」这个场景下强制走某条线路往往适得其反 —— 尤其线路 DOWN 时。
local fif = s:option(Flag, "webhook_force_iface", translate("强制通过该线路发送"),
    translate("默认关闭：交给系统路由表选出口，通知更容易发出去。" ..
        "开启后 curl 会绑定到该线路的设备（--interface），适用于「必须从指定线路发出」的场景。" ..
        "★ 注意：线路离线时，通知要汇报的正是这条刚挂掉的线路 —— 此时强制走它反而可能发不出去；" ..
        "接收端在局域网内时也会直接失败。"))
fif.default = "0"; fif.rmempty = false

local hdrs = s:option(TextValue, "webhook_headers", translate("自定义请求头"),
    translate("一行一条，格式 Name: value。例如 Authorization: Bearer xxxxx。企业微信、钉钉、Telegram " ..
        "等需要鉴权头的服务必须填这里，否则只能把凭据塞进 URL。"))
hdrs.rows = 3

local ct = s:option(Value, "webhook_content_type", translate("Content-Type"))
ct.default = "application/json"
ct:depends("webhook_method", "POST")

local py = s:option(TextValue, "webhook_payload", translate("POST 请求体（JSON）"),
    translate("仅请求方式为 POST 时生效，同样支持上述变量。JSON 中的换行请使用 \\n 表示，否则服务器可能拒收。"))
py:depends("webhook_method", "POST"); py.rows = 4

local rt = s:option(Value, "webhook_retries", translate("失败重试次数"),
    translate("发送失败（连接被拒 / 超时 / 5xx）时自动重试的次数，每次间隔 2 秒。默认 2 次，填 0 表示不重试。"))
rt.default = "2"
rt.datatype = "range(0,5)"

local vfy = s:option(Flag, "webhook_insecure", translate("忽略 TLS 证书校验"),
    translate("★ 默认关闭（即校验证书）。仅当接收端用自签名证书、且确实无法换成受信任证书时才开启 —— " ..
        "开启后中间人可伪造该连接。若开启后发送开始失败，运行日志里会给出具体原因。" ..
        "本开关同时作用于下面两个「公网 IP 查询地址」。"))
vfy.default = "0"; vfy.rmempty = false

s:option(Value, "public_ip_url", translate("公网 IPv4 查询地址"),
    translate("可选。填了才会去查（例如 https://api.ipify.org），结果填入 $PUBLIC_IP；" ..
        "不填或查询失败则回退为 $WAN_IP。注意这会额外发起一次外网请求，5 秒超时。"))

s:option(Value, "public_ip6_url", translate("公网 IPv6 查询地址"),
    translate("可选。填了才会去查（例如 https://v6.ident.me），结果填入 $PUBLIC_IPV6；" ..
        "不填或查询失败则回退为 $WAN_IPV6。" ..
        "★ 查询强制走 IPv6（curl -6）：否则像 api64.ipify.org 这类双栈服务，在设备没有 IPv6 时会返回 IPv4 地址，" ..
        "$PUBLIC_IPV6 里就会混进一个 v4 地址 —— 静默错误比查不到更糟。" ..
        "★ 与 $WAN_IPV6 的区别：OpenWrt 把 IPv6 挂在独立接口（wan6）上，$WAN_IPV6 读的是该接口拿到的地址；" ..
        "本项查询得到的才是路由器**实际对外使用**的地址，实测两者常落在不同前缀段。" ..
        "★ 另有一种少见情况：运营商只下发前缀（PD）、不给 WAN 口地址，此时 $WAN_IPV6 会是「未知IPv6」，" ..
        "只能靠本项查询拿到真实出口地址。"))

-- 最近一次通知结果（daemon 把结果写到 /tmp/xxwan_webhook_last，格式 时间|事件|线路|结果）
local last = s:option(DummyValue, "_last_notify", translate("最近一次通知"))
last.template = "cbi/dvalue"
last.rawhtml = true
function last.cfgvalue()
    local raw = fs.readfile("/tmp/xxwan_webhook_last")
    if not raw or raw == "" then
        return "<span style='color:var(--text-muted, var(--text-color-medium, var(--gray, #8898aa)));'>" ..
               translate("暂无记录（引擎尚未发送过通知，或设备刚重启）") .. "</span>"
    end
    local t, ev, iface, res = raw:match("^([^|]*)|([^|]*)|([^|]*)|(.*)")
    if not t then
        return util.pcdata(raw)
    end
    -- 结果里出现「失败」或非 0 返回码就标红，其余标绿
    local bad = res:find("失败") or res:find("rc=[1-9]")
    local color = bad and "var(--danger, var(--error-color-high, #f5365c))"
                       or "var(--success, var(--success-color-high, #2dce89))"
    local muted = "color:var(--text-muted, var(--text-color-medium, var(--gray, #8898aa)));"
    return string.format(
        "<span style='%s'>%s</span> <b>%s</b> <span style='%s'>%s</span> " ..
        "<span style='color:%s;font-weight:bold;'>%s</span>",
        muted, util.pcdata(t), util.pcdata(ev), muted, util.pcdata(iface), color, util.pcdata(res))
end

local test_btn = s:option(Button, "_test_btn", translate("发送测试通知"),
    translate("点击会先保存本页当前填写的配置，再发送一次测试。结果写入运行日志，并显示在上面的「最近一次通知」里。" ..
        "注意：测试走默认路由，不代表真实切换场景。"))
test_btn.inputtitle = translate("发送测试")
test_btn.inputstyle = "apply"
function test_btn.write(self, section)
    -- ★ 原来是提示用户「先点保存并应用再测试」。点击提交按钮时整张表单本来就会提交，
    --   但 UCI 的 commit 在 LuCI 收尾阶段才发生；这里显式 commit 一次，
    --   确保 daemon 读到的是刚填进去的值，用户就不用再记着先保存了。
    sys.call("uci commit xxwan 2>/dev/null")
    sys.call("/usr/sbin/xxwan-daemon test_webhook >/dev/null 2>&1 &")
end

return m
