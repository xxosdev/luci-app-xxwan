local sys = require "luci.sys"
local m = Map("xxwan", translate("切换动作与通知"), translate("线路切换时执行的动作，以及通知推送配置。"))
local s = m:section(NamedSection, "advanced", "advanced", "")
s.anonymous = true

local d1 = s:option(DummyValue, "_d1", "")
d1.rawhtml = true
d1.default = "<h4 style='color:var(--brand); margin-bottom:10px; border-bottom: 1px solid var(--hairline); padding-bottom: 5px;'>切换时的动作</h4>"

local flush = s:option(ListValue, "conntrack_flush", translate("清除连接跟踪表"), translate("切换线路时清除已有连接，让连接快速重建。注意：会中断路由器上当前所有网络连接，包括 SSH、网页管理与其他设备的下载和在线游戏。"))
flush:value("always", translate("每次切换时清除（默认）"))
flush:value("restore", translate("仅线路恢复时清除"))
flush:value("never", translate("不清除"))
flush.default = "always"

local svcs = s:option(DynamicList, "reload_services", translate("切换时重启的服务"), translate("线路切换后自动重启这些服务，使其重新建立连接。"))
svcs.rmempty = true
for _, v in ipairs(sys.init.names()) do svcs:value(v, v) end

local hook_note = translate("可用变量：$XXWAN_EVENT（UP/DOWN）、$XXWAN_IFACE（线路名）。")
s:option(TextValue, "hook_down", translate("线路离线时执行的脚本"), hook_note).rows = 3
s:option(TextValue, "hook_up", translate("线路恢复时执行的脚本"), hook_note).rows = 3

local d2 = s:option(DummyValue, "_d2", "")
d2.rawhtml = true
d2.default = "<h4 style='color:var(--brand); margin-top:30px; margin-bottom:10px; border-bottom: 1px solid var(--hairline); padding-bottom: 5px;'>Webhook 通知</h4>"

local md = s:option(ListValue, "webhook_method", translate("请求方式"))
md:value("GET", "GET"); md:value("POST", "POST"); md.default = "GET"

s:option(Value, "webhook_url", translate("Webhook 地址"), translate("支持变量：$EVENT（UP/DOWN）、$IFACE（线路）、$IP（当前 IP）、$TIME（时间）、$HOSTNAME（主机名）。自动绑定当前在线线路发送。"))

local py = s:option(TextValue, "webhook_payload", translate("POST 请求体（JSON）"), translate("仅请求方式为 POST 时生效，同样支持上述变量。JSON 中的换行请使用 \\n 表示，否则服务器可能拒收。"))
py:depends("webhook_method", "POST"); py.rows = 4

local test_btn = s:option(Button, "_test_btn", translate("发送测试通知"), translate("请先点击「保存并应用」再测试，否则读取的是旧配置。测试结果写入运行日志，请在「运行日志」页查看。注意：测试走默认路由，不代表真实切换场景。"))
test_btn.inputtitle = translate("发送测试")
test_btn.inputstyle = "apply"
function test_btn.write(self, section)
    sys.call("/usr/sbin/xxwan-daemon test_webhook >/dev/null 2>&1 &")
end

return m
