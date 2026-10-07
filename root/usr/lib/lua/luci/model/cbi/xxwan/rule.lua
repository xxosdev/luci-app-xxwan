local uci = require("luci.model.uci").cursor()

-- 未配置线路时给出引导，避免出口下拉为空却不知原因
local has_iface = false
uci:foreach("xxwan", "interface", function(sec) has_iface = true end)

local descr = "为指定设备或目标配置固定出口。留空则所有流量按全局出口策略。"
if not has_iface then
    descr = descr .. " <span style='color:var(--danger);'>尚未配置任何线路，请先在「线路接口」页添加。</span>"
end

local m = Map("xxwan", translate("分流规则"), translate(descr))

-- 匹配规则说明
local s_note = m:section(NamedSection, "status", "status", translate("匹配规则说明"))
s_note.anonymous = true
local note = s_note:option(DummyValue, "_rule_note", "")
note.rawhtml = true
note.cfgvalue = function(self, section)
    return [[
        <div style="line-height:1.9; color:var(--text-muted);">
            <div style="color:var(--text);">规则按列表顺序匹配，第一条命中的生效。</div>
            <div>未命中任何规则的流量，按「全局设置」中的出口选择方式处理。</div>
            <div>条件留空表示该条件匹配所有流量。</div>
            <div>勾选「固定出口」后，即使该线路离线也不切换，该流量会中断。</div>
        </div>
    ]]
end

local s = m:section(TypedSection, "rule", translate("规则列表"))
s.template = "cbi/tblsection"; s.addremove = true; s.anonymous = true

local en = s:option(Flag, "enabled", translate("启用")); en.rmempty = false; en.default = "1"
s:option(Value, "name", translate("规则名称")).rmempty = false

local chain = s:option(ListValue, "chain", translate("防火墙链"))
chain:value("prerouting", translate("prerouting（局域网设备）")); chain:value("output", translate("output（路由器本机）")); chain:value("forward", translate("forward（纯转发）"))
chain.default = "prerouting"

s:option(Value, "src_ip", translate("源 IP/网段"))
s:option(Value, "src_mac", translate("源 MAC"))
s:option(Value, "src_port", translate("源端口"))
s:option(Value, "dest_ip", translate("目标 IP/网段"))
s:option(Value, "dest_domain", translate("目标域名（DNS 拦截）"))
s:option(Value, "dest_port", translate("目标端口"))

local proto = s:option(ListValue, "proto", translate("协议"))
proto:value("all", translate("全部")); proto:value("tcp", "TCP"); proto:value("udp", "UDP")
proto:value("tcp udp", "TCP & UDP"); proto:value("icmp", translate("ICMP (Ping)"))
proto.default = "all"

local iface = s:option(ListValue, "target_iface", translate("指定出口线路"))
uci:foreach("xxwan", "interface", function(sec)
    local name = sec.ifname or sec['.name']
    iface:value(name, name:upper())
end)

local strict = s:option(Flag, "strict_bind", translate("固定出口"), translate("勾选后即使该线路离线也不切换，该流量将中断。"))
strict.rmempty = false; strict.default = "0"
return m
