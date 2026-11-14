# SPDX-License-Identifier: GPL-2.0-only
include $(TOPDIR)/rules.mk

PKG_NAME:=h248-mg
PKG_RELEASE:=2
PKG_LICENSE:=Apache-2.0 GPL-2.0-only
ERLC:=$(STAGING_DIR_HOSTPKG)/lib/erlang/bin/erlc
MEGACO_INCLUDE:=$(wildcard $(STAGING_DIR_HOSTPKG)/lib/erlang/lib/megaco-*/include)

include $(INCLUDE_DIR)/package.mk

define Package/h248-mg
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Telephony
  TITLE:=Minimal H.248/Megaco media gateway
  DEPENDS:=+erlang +erlang-megaco +erlang-asn1 +erlang-runtime-tools +kmod-airoha-en7581-pcm-spi
endef

define Package/h248-mg/description
 Minimal H.248/Megaco media gateway using the Erlang/OTP megaco application.
 The FXS port helper is a small C control port for /dev/en75xx-fxs0.
endef

define Package/h248-mg/conffiles
/etc/config/h248-mg
endef

define Build/Compile
	mkdir -p $(PKG_BUILD_DIR)/ebin
	$(ERLC) -o $(PKG_BUILD_DIR)/ebin -I$(MEGACO_INCLUDE) \
		$(CURDIR)/src/h248_mg.erl $(CURDIR)/src/megaco_simple_mg.erl
	$(TARGET_CC) $(TARGET_CPPFLAGS) $(TARGET_CFLAGS) \
		-Wall -Wextra -Werror -I$(CURDIR)/src \
		-o $(PKG_BUILD_DIR)/en75xx_fxs_port \
		$(CURDIR)/src/en75xx_fxs_port.c $(TARGET_LDFLAGS)
endef

define Package/h248-mg/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/en75xx_fxs_port $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/usr/lib/erlang/lib/h248_mg-0.1/ebin
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/ebin/h248_mg.beam $(PKG_BUILD_DIR)/ebin/megaco_simple_mg.beam $(1)/usr/lib/erlang/lib/h248_mg-0.1/ebin/
	$(INSTALL_DATA) $(CURDIR)/src/h248_mg.app $(1)/usr/lib/erlang/lib/h248_mg-0.1/ebin/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/h248-mg.init $(1)/etc/init.d/h248-mg
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/h248-mg.config $(1)/etc/config/h248-mg
endef

$(eval $(call BuildPackage,h248-mg))
