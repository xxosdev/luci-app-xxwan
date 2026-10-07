local fs = require "nixio.fs"
local http = require "luci.http"

if http.formvalue("clear_log") then
    fs.writefile("/var/log/xxwan.log", "========== 日志已于 " .. os.date("%Y-%m-%d %H:%M:%S") .. " 手动清空 ==========\n")
    http.redirect(luci.dispatcher.build_url("admin", "network", "xxwan", "log"))
    return
end

local m = Map("xxwan", translate("运行日志"), translate("记录 XXWAN 的探测结果与线路切换过程。"))
local s = m:section(NamedSection, "status", "status", "")
s.anonymous = true

local btn = s:option(DummyValue, "_clear")
btn.rawhtml = true
btn.cfgvalue = function()
    local url = luci.dispatcher.build_url("admin", "network", "xxwan", "log")
    return [[
        <div style="margin-bottom: 15px; display: flex; gap: 15px; align-items: center;">
            <input class="cbi-button cbi-button-apply" type="button" value="刷新日志" onclick="location.href=']] .. url .. [['" />
            <input class="cbi-button cbi-button-action" type="button" value="清空日志" style="color:var(--danger);font-weight:bold;" onclick="if(confirm('确定清空 XXWAN 运行日志？')){location.href=']] .. url .. [[?clear_log=1'}" />
        </div>
    ]]
end

local log = s:option(TextValue, "syslog")
log.rows = 25
log.readonly = true
function log.cfgvalue()
    local content = fs.readfile("/var/log/xxwan.log")
    if not content or content == "" then return "暂无日志，或守护进程尚未启动。" end
    return content
end
function log.write() end

return m
