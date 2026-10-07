module("luci.controller.xxwan", package.seeall)
function index()
    if not nixio.fs.access("/etc/config/xxwan") then return end
    entry({"admin", "network", "xxwan"}, alias("admin", "network", "xxwan", "basic"), _("XXWAN 多线策略"), 60).dependent = true
    entry({"admin", "network", "xxwan", "basic"}, cbi("xxwan/basic"), _("全局设置"), 1)
    entry({"admin", "network", "xxwan", "iface"}, cbi("xxwan/iface"), _("线路接口"), 2)
    entry({"admin", "network", "xxwan", "rule"}, cbi("xxwan/rule"), _("分流规则"), 3)
    entry({"admin", "network", "xxwan", "advanced"}, cbi("xxwan/advanced"), _("动作与通知"), 4)
    entry({"admin", "network", "xxwan", "log"}, cbi("xxwan/log"), _("运行日志"), 5)
    entry({"admin", "network", "xxwan", "backup"}, cbi("xxwan/backup"), _("备份与恢复"), 6)
    entry({"admin", "network", "xxwan", "about"}, cbi("xxwan/about"), _("关于"), 7)
    
    -- 隐藏的备份文件下载接口
    entry({"admin", "network", "xxwan", "do_backup"}, call("action_backup"), nil).leaf = true
end

function action_backup()
    local fs = require "nixio.fs"
    local http = require "luci.http"
    http.header('Content-Disposition', 'attachment; filename="xxwan_backup_'..os.date("%Y%m%d")..'.conf"')
    http.prepare_content("text/plain")
    http.write(fs.readfile("/etc/config/xxwan") or "")
end
