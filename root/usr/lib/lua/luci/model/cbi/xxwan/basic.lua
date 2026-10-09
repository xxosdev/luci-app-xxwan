local uci = require("luci.model.uci").cursor()
local sys = require("luci.sys")
local m = Map("xxwan", translate("XXWAN 多线策略"), translate("管理多线负载均衡与故障切换。"))

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

-- 引擎运行状态 + 服务控制
-- 背景：安装脚本不会自动启动服务；只给「启用 XXWAN」开关时，用户不知道还要启动引擎，
-- 而命令行 start 在 enabled≠1 时会静默返回（rc=0 但不起进程），极易被误判成"启动不了"。
local svc_state = s_top:option(DummyValue, "svc_state", translate("引擎运行状态"))
svc_state.template = "cbi/dvalue"
function svc_state.cfgvalue(self, section)
    local running = (sys.call("pidof xxwan-daemon >/dev/null 2>&1") == 0)
    local en_val = uci:get("xxwan", "main", "enabled")
    local res
    if running then
        res = "<span style='color:var(--success, var(--success-color-high, #2dce89));font-weight:bold;'>[运行中]</span>"
    else
        res = "<span style='color:var(--danger, var(--error-color-high, #f5365c));font-weight:bold;'>[未运行]</span>"
    end
    if en_val ~= "1" then
        res = res .. " <span style='color:var(--text-muted, var(--text-color-medium, var(--gray, #8898aa)));'>(已禁用：xxwan.main.enabled=0，需先勾选上面的「启用 XXWAN」)</span>"
    end
    return res
end
svc_state.rawhtml = true

-- ★ 两个按钮必须画在同一行：LuCI 的 Button 选项每个独占一行，而且
--   cbi/full_valueheader.htm 只在选项有 title 时才输出 cbi-value-field 包裹 —— 所以
--   「没有 title 的第二个按钮」会贴到最左边、与上面的按钮错位。
--   这里只定义一个 Button 选项，由 view/xxwan/svc_buttons.htm 一次画出两个按钮：
--   二者共用同一个 name，浏览器只提交被点击的那一个，后端按 value 的 start/stop 区分动作。
local svc_ctl = s_top:option(Button, "_svc_ctl", translate("服务控制"),
    translate("「启动服务」会自动勾选「启用 XXWAN」并立即启动后台引擎；「停止服务」只停引擎，不改变启用开关（重启设备后仍会自启）。"))
svc_ctl.template = "xxwan/svc_buttons"
svc_ctl.inputtitle = translate("启动服务")
svc_ctl.inputstyle = "apply"
svc_ctl.inputtitle2 = translate("停止服务")
svc_ctl.inputstyle2 = "remove"
function svc_ctl.write(self, section, value)
    if value == "stop" then
        sys.call("/etc/init.d/xxwan stop >/dev/null 2>&1")
    else
        sys.call("uci set xxwan.main.enabled='1' 2>/dev/null")
        sys.call("uci commit xxwan 2>/dev/null")
        sys.call("/etc/init.d/xxwan start >/dev/null 2>&1")
    end
    sys.call("rm -f /tmp/luci-indexcache* 2>/dev/null")
end

-- 线路运行状态
local s_stat = m:section(NamedSection, "status", "status", translate("线路状态"))
s_stat.anonymous = true
local cur = s_stat:option(DummyValue, "active_nodes", translate("当前状态"))
cur.template = "cbi/dvalue"
function cur.cfgvalue(self, section) return uci:get("xxwan", "status", "active_nodes") or "<span style='color:var(--text-muted, var(--text-color-medium, var(--gray, #8898aa)));'>等待探测…</span>" end
cur.rawhtml = true

-- ★ 界面文案统一用「分流」，不再暴露底层包名 pbr：用户关心的是分流有没有生效，
--   而不是底层进程叫什么。pbr 只保留在「未安装」提示与配置项引用里（见下方 cfgvalue）。
local pbr_stat = s_stat:option(DummyValue, "pbr_status", translate("分流服务状态"))
pbr_stat.template = "cbi/dvalue"
function pbr_stat.cfgvalue(self, section)
    if sys.call("test -f /etc/init.d/pbr") ~= 0 then return "<span style='color:var(--danger, var(--error-color-high, #f5365c));font-weight:bold;'>[未安装]</span> 请先在软件包中安装 pbr" end
    local running = (sys.call("/etc/init.d/pbr running 2>/dev/null") == 0)
    local enabled = (sys.call("/etc/init.d/pbr enabled 2>/dev/null") == 0)
    -- pbr.config.enabled 是功能开关，为 0 时 restart 也不会真正启动
    local func_en = uci:get("pbr", "config", "enabled")
    local res = ""
    if running then res = res .. "<span style='color:var(--success, var(--success-color-high, #2dce89));font-weight:bold;'>[运行中]</span> " else res = res .. "<span style='color:var(--danger, var(--error-color-high, #f5365c));font-weight:bold;'>[已停止]</span> " end
    if func_en ~= "1" then res = res .. "<span style='color:var(--danger, var(--error-color-high, #f5365c));font-weight:bold;'>[功能未启用，分流不生效]</span> " end
    if enabled then res = res .. "<span style='color:var(--info, var(--primary-color-high, var(--primary, #5e72e4)));'>[开机自启已配置]</span>" else res = res .. "<span style='color:var(--text-muted, var(--text-color-medium, var(--gray, #8898aa)));'>[开机自启未配置]</span>" end
    return res
end
pbr_stat.rawhtml = true

-- 分流控制：同样用 svc_buttons.htm 把「启用」和「停用」放在一行
--   「启用分流」= 底层 pbr 功能开关置 1 + 配置开机自启 + restart
--   「停用分流」= 功能开关置 0 + 取消开机自启 + stop（彻底关闭，重启设备也不会自己起来）
-- ★ 按钮名只写用户意图（启用/停用），不写实现步骤（原来的「启用并重启」把 enabled=1 +
--   enable + restart 三件事塞进了名字，读起来绕口）；实现细节交给下面那行灰色说明。
-- ★ 用「启用/停用」而不是「启动/停止」：这两件事是持久的（重启设备也不会自己回来），
--   与上面「服务控制」的启动/停止（临时，重启仍自启）刻意用不同的词区分。
-- ★ 界面统一说「分流」，但灰色说明里首次出现时点明「底层 pbr」——用户去软件包搜索有据可依。
local pbr_btn = s_stat:option(Button, "_pbr_btn", translate("分流控制"),
    translate("分流由底层 pbr 提供：「启用分流」会把 pbr.config.enabled 设为 1、配置开机自启并重启服务；「停用分流」则设为 0、取消开机自启并停止服务（之后 XXWAN 的分流与故障切换都会失效）。"))
pbr_btn.template = "xxwan/svc_buttons"
pbr_btn.inputtitle = translate("启用分流")
pbr_btn.inputstyle = "apply"
pbr_btn.inputtitle2 = translate("停用分流")
pbr_btn.inputstyle2 = "remove"
function pbr_btn.write(self, section, value)
    if value == "stop" then
        -- 先置 0 再 stop：否则 pbr 的 restart/自启会把规则又装回去
        sys.call("uci set pbr.config.enabled='0' 2>/dev/null")
        sys.call("uci commit pbr 2>/dev/null")
        sys.call("/etc/init.d/pbr disable >/dev/null 2>&1")
        sys.call("/etc/init.d/pbr stop >/dev/null 2>&1")
    else
        -- 必须先开功能开关，否则 restart 会被 pbr 拒绝启动
        sys.call("uci set pbr.config.enabled='1' 2>/dev/null")
        sys.call("uci commit pbr 2>/dev/null")
        sys.call("/etc/init.d/pbr enable >/dev/null 2>&1")
        sys.call("/etc/init.d/pbr restart >/dev/null 2>&1")
    end
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
