local uci = require("luci.model.uci").cursor()
local m = Map("xxwan", translate("线路接口"), translate("配置参与调度的广域网接口及其优先级。"))

-- 优先级说明
local s_note = m:section(NamedSection, "status", "status", translate("优先级说明"))
s_note.anonymous = true
local note = s_note:option(DummyValue, "_tier_note", "")
note.rawhtml = true
note.cfgvalue = function(self, section)
    return [[
        <div style="line-height:1.9; color:var(--text-muted);">
            <div><b style="color:var(--text);">主干宽带 (Tier 1)</b> — 默认出口，在线时流量走这条</div>
            <div><b style="color:var(--text);">次级备线 (Tier 2)</b> — 主干离线时自动接管</div>
            <div><b style="color:var(--text);">末级兜底 (Tier 3)</b> — 前两级都离线时才启用</div>
            <div style="margin-top:8px;">系统按优先级 1 到 3 的顺序，选择第一条在线的线路作为出口；高优先级线路恢复在线后会自动切回。</div>
        </div>
    ]]
end

local s = m:section(TypedSection, "interface", translate("接口列表"))
s.template = "cbi/tblsection"; s.addremove = true; s.anonymous = true

local ifname = s:option(ListValue, "ifname", translate("网络接口"))
ifname.width = "12%"
uci:foreach("network", "interface", function(sec)
    local name = sec['.name']
    -- 排除回环与内网接口，避免误将 LAN 选为出口
    if name ~= "loopback" and name:sub(1, 3) ~= "lan" then
        ifname:value(name, name:upper())
    end
end)

local tier = s:option(ListValue, "tier", translate("优先级"))
tier.width = "14%"
tier:value("1", translate("主干宽带 (Tier 1)"))
tier:value("2", translate("次级备线 (Tier 2)"))
tier:value("3", translate("末级兜底 (Tier 3)"))
tier.default = "1"

-- 表格布局下 depends 会因表头不参与依赖而错位，故不做字段联动，
-- 改用「标题标注」说明各字段对应的探测方式（标题已含 Ping/cURL）
local chk = s:option(ListValue, "check_type", translate("探测方式"))
chk.width = "13%"
chk:value("ping", "ICMP Ping"); chk:value("curl", "HTTP cURL"); chk.default = "ping"

local ips = s:option(DynamicList, "check_targets", translate("探测目标 (Ping)"))
ips.width = "26%"
local curl_u = s:option(Value, "curl_url", translate("检测地址 (cURL)"))
curl_u.width = "25%"
local curl_c = s:option(Value, "curl_code", translate("期望状态码 (cURL)")); curl_c.default = "204"
curl_c.width = "8%"
return m
