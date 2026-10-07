local fs = require "nixio.fs"
local http = require "luci.http"
local sys = require "luci.sys"

local UPLOAD_TMP = "/tmp/xxwan-restore.conf"

-- ★ 必须在任何 formvalue() 之前注册文件处理器。
--   LuCI 的 formvalue() 只返回普通表单字段，上传文件的**内容不会物化**，
--   只能靠 setfilehandler 边解析边落盘；而请求体是在第一次 formvalue() 时才解析，
--   所以注册必须早于它 —— 否则回调永远不被调用，恢复会一直提示「未选择文件」。
local up_fp, up_saved = nil, false
http.setfilehandler(function(meta, chunk, eof)
    if meta and (meta.file or meta.name == "archive") then
        if not up_fp then
            up_fp = io.open(UPLOAD_TMP, "w")
            up_saved = (up_fp ~= nil)
        end
    end
    if up_fp and chunk then up_fp:write(chunk) end
    if up_fp and eof then
        up_fp:close()
        up_fp = nil
    end
end)

-- 恢复配置：先校验格式，再备份原文件，最后覆盖
local restore_msg = ""
if http.formvalue("restore") then
    local file = up_saved and fs.readfile(UPLOAD_TMP) or nil
    if not file or #file == 0 then
        restore_msg = "<span style='color:var(--danger);'>未选择文件，已取消恢复。</span>"
    elseif not file:match("^%s*config%s+[%w_]+") then
        restore_msg = "<span style='color:var(--danger);'>上传的文件不是有效的 UCI 配置，已取消恢复，当前配置未改动。</span>"
    else
        sys.call("cp -f /etc/config/xxwan /etc/config/xxwan.bak >/dev/null 2>&1")
        local fp = io.open("/etc/config/xxwan", "w")
        if fp then
            fp:write(file); fp:close()
            -- ★ 重启放后台并延迟几秒：引擎重启会按配置执行 conntrack -F，
            --   同步执行会把当前这条 HTTP 连接一起清掉，用户看不到成功提示。
            sys.call("(sleep 3; /etc/init.d/xxwan restart) >/dev/null 2>&1 &")
            restore_msg = "<span style='color:var(--success);'>配置已恢复。原配置已备份为 /etc/config/xxwan.bak，引擎将在几秒后重启。</span>"
        else
            restore_msg = "<span style='color:var(--danger);'>写入失败，已取消恢复。</span>"
        end
    end
    fs.remove(UPLOAD_TMP)
end

local m = Map("xxwan", translate("备份与恢复"), translate("导出当前配置，或从备份文件恢复。"))
local s = m:section(NamedSection, "status", "status", "")
s.anonymous = true

local d = s:option(DummyValue, "_backup")
d.rawhtml = true
d.cfgvalue = function()
    return [[
        <div style="margin-bottom: 20px;">
            <h4 style="color:var(--brand); margin-bottom: 15px;">导出备份</h4>
            <input class="cbi-button cbi-button-apply" type="button" value="生成并下载备份文件" onclick="location.href=']] .. luci.dispatcher.build_url("admin", "network", "xxwan", "do_backup") .. [['" />
        </div>
        <hr style="margin: 30px 0; border: 0; border-top: 1px solid var(--hairline);" />
        <div style="margin-top: 20px;">
            <h4 style="color:var(--brand); margin-bottom: 15px;">从文件恢复</h4>
            <form method="post" action="]] .. luci.dispatcher.build_url("admin", "network", "xxwan", "backup") .. [[" enctype="multipart/form-data">
                <input type="file" name="archive" style="display: block; margin-bottom: 15px;" />
                <input class="cbi-button cbi-button-action" type="submit" name="restore" value="上传并覆盖（建议先导出备份）" />
            </form>
            <div style="margin-top: 15px;">]] .. restore_msg .. [[</div>
        </div>
    ]]
end
return m
