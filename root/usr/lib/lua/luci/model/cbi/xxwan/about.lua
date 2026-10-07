-- 版本号与 Makefile 的 PKG_VERSION 保持同步
local m = Map("xxwan", translate("关于"), translate("基于 pbr 的多线负载均衡与故障切换。"))
local s = m:section(NamedSection, "status", "status", "")
s.anonymous = true
local ab = s:option(DummyValue, "_about")
ab.rawhtml = true
ab.cfgvalue = function()
    return [[
        <div style="padding: 25px; background-color: var(--surface); border-left: 5px solid var(--brand); border-radius: 6px;">
            <h3 style="margin-top: 0; color: var(--text); font-size: 22px;">XXWAN <span style="font-size: 14px; color: var(--on-brand); background: var(--brand); padding: 3px 8px; border-radius: 12px; vertical-align: middle;">v1.0.2</span></h3>
            <p style="color: var(--text-muted); margin-bottom: 20px;">为家庭与小型办公网络提供多线容错。</p>
            <div style="color: var(--text-muted); font-size: 13px; line-height: 1.9;">
                <div>依赖：pbr、curl、conntrack</div>
                <div>许可：GPL-2.0</div>
            </div>
        </div>
    ]]
end
return m
