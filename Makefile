include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-xxwan
PKG_VERSION:=1.0.2
PKG_RELEASE:=1

PKG_MAINTAINER:=Xx <xxosdev@users.noreply.github.com>
PKG_LICENSE:=GPL-2.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-xxwan
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=XXWAN - 多线策略路由
  PKGARCH:=all
  DEPENDS:=+pbr +curl +conntrack +luci-base
endef

define Package/luci-app-xxwan/description
  XXWAN 多线策略路由。

  以 pbr 为底层，按优先级（Tier）管理多条外网线路：探测线路存活，
  主线路故障时自动把出口切到备线，恢复后切回。全程只改 pbr 的一条
  uplink_interface 选项，不动路由表、不改防火墙。

  依赖：pbr（策略路由底层）、curl（HTTP 探测与通知）、conntrack（切换时清理连接）。
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/luci-app-xxwan/conffiles
/etc/config/xxwan
endef

define Package/luci-app-xxwan/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/xxwan $(1)/etc/config/xxwan

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/xxwan $(1)/etc/init.d/xxwan

	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./root/usr/sbin/xxwan-daemon $(1)/usr/sbin/xxwan-daemon
	$(INSTALL_BIN) ./root/usr/sbin/xxwan-install $(1)/usr/sbin/xxwan-install

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/controller/xxwan.lua $(1)/usr/lib/lua/luci/controller/xxwan.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/xxwan
	$(INSTALL_DATA) ./root/usr/lib/lua/luci/model/cbi/xxwan/*.lua $(1)/usr/lib/lua/luci/model/cbi/xxwan/
endef

define Package/luci-app-xxwan/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	chmod +x /etc/init.d/xxwan
	chmod +x /usr/sbin/xxwan-daemon
	chmod +x /usr/sbin/xxwan-install
	/etc/init.d/xxwan enable
	rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
	# pbr 有「开机自启」和「功能开关」两级开关，只 enable 不置 1 的话分流规则不会生效
	if [ "$$(uci -q get pbr.config.enabled)" != "1" ]; then
		echo "提示：pbr 功能开关当前为关闭状态，XXWAN 的分流规则不会生效。"
		echo "      请在 LuCI 的「网络 → XXWAN 多线策略 → 全局设置」页点击「启用并重启 PBR」。"
	fi
	echo "XXWAN 安装完成。默认未启用，请在「全局设置」页开启。"
fi
exit 0
endef

define Package/luci-app-xxwan/prerm
#!/bin/sh
# 必须在删文件之前停掉服务，否则会留下指向已删除脚本的自启条目
if [ -z "$${IPKG_INSTROOT}" ]; then
	if [ -x /etc/init.d/xxwan ]; then
		/etc/init.d/xxwan stop
		/etc/init.d/xxwan disable
	fi
	killall xxwan-daemon 2>/dev/null
fi
exit 0
endef

define Package/luci-app-xxwan/postrm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	rm -f /tmp/xxwan_state
	rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
fi
exit 0
endef

$(eval $(call BuildPackage,luci-app-xxwan))
