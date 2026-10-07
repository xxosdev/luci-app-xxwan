local uci = require("luci.model.uci").cursor()
local sys = require("luci.sys")
local m = Map("xxwan", translate("XXWAN 多线策略路由"), translate("管理多线负载均衡与故障切换。"))

-- 引擎开关与出口选择
local s_top = m:section(NamedSection, "main", "global", translate("引擎与出口"))
s_top.anonymous = true

local en = s_top:option(Flag, "enabled", translate("启用 XXWAN"))
en.rmempty = false

local gmode = s_top:option(ListValue, "global_mode", translate("出口选择方式"), translate("未命中分流规则的流量走哪条线路。"))
gmode:value("auto", translate("自动（按优先级选择可用线路）"))
uci:foreach("xxwan", "interface", function(sec)
    local name = sec.ifname or sec['.name']
    gmode:value("force_" .. name, translate("固定使用 ") .. name:upper() .. translate("（不自动切换）"))
end)
gmode.default = "auto"

-- 线路运行状态
local s_stat = m:section(NamedSection, "status", "status", translate("线路状态"))
s_stat.anonymous = true
local cur = s_stat:option(DummyValue, "active_nodes", translate("当前状态"))
cur.template = "cbi/dvalue"
function cur.cfgvalue(self, section) return uci:get("xxwan", "status", "active_nodes") or "<span style='color:var(--text-muted);'>等待探测…</span>" end
cur.rawhtml = true

local pbr_stat = s_stat:option(DummyValue, "pbr_status", translate("PBR 服务状态"))
pbr_stat.template = "cbi/dvalue"
function pbr_stat.cfgvalue(self, section)
    if sys.call("test -f /etc/init.d/pbr") ~= 0 then return "<span style='color:var(--danger);font-weight:bold;'>[未安装]</span> 请先在软件包中安装 pbr" end
    local running = (sys.call("/etc/init.d/pbr running 2>/dev/null") == 0)
    local enabled = (sys.call("/etc/init.d/pbr enabled 2>/dev/null") == 0)
    -- pbr.config.enabled 是功能开关，为 0 时 restart 也不会真正启动
    local func_en = uci:get("pbr", "config", "enabled")
    local res = ""
    if running then res = res .. "<span style='color:var(--success);font-weight:bold;'>[运行中]</span> " else res = res .. "<span style='color:var(--danger);font-weight:bold;'>[已停止]</span> " end
    if func_en ~= "1" then res = res .. "<span style='color:var(--danger);font-weight:bold;'>[功能未启用，分流不生效]</span> " end
    if enabled then res = res .. "<span style='color:var(--info);'>[开机自启已配置]</span>" else res = res .. "<span style='color:var(--text-muted);'>[开机自启未配置]</span>" end
    return res
end
pbr_stat.rawhtml = true

local pbr_btn = s_stat:option(Button, "_pbr_btn", translate("PBR 操作"), translate("将 pbr.config.enabled 设为 1 并重启服务。点击后需再点「保存并应用」才会执行。"))
pbr_btn.inputtitle = translate("启用并重启 PBR"); pbr_btn.inputstyle = "apply"
function pbr_btn.write(self, section)
    -- 必须先开功能开关，否则 restart 会被 pbr 拒绝启动
    sys.call("uci set pbr.config.enabled='1' 2>/dev/null")
    sys.call("uci commit pbr 2>/dev/null")
    sys.call("/etc/init.d/pbr enable >/dev/null 2>&1")
    sys.call("/etc/init.d/pbr restart >/dev/null 2>&1")
end
s_stat:option(DummyValue, "last_event", translate("最近事件"))

-- 高级参数
local s_adv = m:section(NamedSection, "main", "global", translate("高级参数"))
s_adv.anonymous = true
local ipv6_en = s_adv:option(Flag, "ipv6_enabled", translate("接管 IPv6 流量"), translate("跨运营商多线环境下开启可能导致 IPv6 不通，建议保持关闭。"))
ipv6_en.default = "0"; ipv6_en.rmempty = false
local strict_en = s_adv:option(Flag, "strict_enforcement", translate("严格模式"), translate("所有线路离线时阻断流量，避免流量走非预期出口。"))
strict_en.default = "1"; strict_en.rmempty = false
s_adv:option(Value, "check_interval", translate("探测间隔（秒）")).default = "5"
s_adv:option(Value, "fail_threshold", translate("判定离线所需失败次数")).default = "3"
s_adv:option(Value, "restore_threshold", translate("判定恢复所需成功次数")).default = "3"

return m
