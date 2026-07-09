#!/bin/bash
set -euo pipefail

remove_paths() {
  for path in "$@"; do
    [ ! -e "$path" ] || rm -rf "$path"
  done
}

git_sparse_clone() {
  local branch="$1" repourl="$2"
  shift 2
  local repodir
  repodir="$(basename "$repourl" .git)"
  git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl"
  (
    cd "$repodir"
    git sparse-checkout set "$@"
    mv -f "$@" ../package
  )
  rm -rf "$repodir"
}

# 默认 LAN IP
sed -i '/^CONFIG_IMAGEOPT=/d; /^# CONFIG_IMAGEOPT is not set/d; /^CONFIG_PREINITOPT=/d; /^# CONFIG_PREINITOPT is not set/d; /^CONFIG_TARGET_DEFAULT_LAN_IP_FROM_PREINIT=/d; /^CONFIG_TARGET_PREINIT_IP=/d; /^CONFIG_TARGET_PREINIT_BROADCAST=/d' .config
cat >> .config <<'EOF'
CONFIG_IMAGEOPT=y
CONFIG_PREINITOPT=y
CONFIG_TARGET_DEFAULT_LAN_IP_FROM_PREINIT=y
CONFIG_TARGET_PREINIT_IP="192.168.5.1"
CONFIG_TARGET_PREINIT_BROADCAST="192.168.5.255"
EOF

# 默认 shell 为 zsh
[ ! -f package/base-files/files/etc/passwd ] || sed -i 's#/bin/ash#/usr/bin/zsh#g' package/base-files/files/etc/passwd

# TTYD root 自动登录
[ ! -f feeds/packages/utils/ttyd/files/ttyd.config ] || sed -i 's#/bin/login#/bin/login -f root#g' feeds/packages/utils/ttyd/files/ttyd.config

# 移除需要由第三方仓库替换的冲突包。Transmission 和 firewall4 使用 OpenWrt 25.12 官方源。
remove_paths \
  feeds/packages/net/chinadns-ng \
  feeds/packages/net/dns2socks \
  feeds/packages/net/dns2tcp \
  feeds/packages/net/geoview \
  feeds/packages/net/gn \
  feeds/packages/net/hysteria \
  feeds/packages/net/ipt2socks \
  feeds/packages/net/microsocks \
  feeds/packages/net/naiveproxy \
  feeds/packages/net/shadowsocks-libev \
  feeds/packages/net/shadowsocks-rust \
  feeds/packages/net/shadowsocksr-libev \
  feeds/packages/net/simple-obfs \
  feeds/packages/net/sing-box \
  feeds/packages/net/ssocks \
  feeds/packages/net/tcping \
  feeds/packages/net/trojan-plus \
  feeds/packages/net/tuic-client \
  feeds/packages/net/v2ray-core \
  feeds/packages/net/v2ray-geodata \
  feeds/packages/net/v2ray-plugin \
  feeds/packages/net/xray-core \
  feeds/packages/net/xray-plugin \
  feeds/luci/themes/luci-theme-argon \
  feeds/luci/applications/luci-app-argon-config \
  feeds/luci/applications/luci-app-passwall \
  feeds/luci/applications/luci-app-passwall2 \
  feeds/luci/applications/luci-app-openclash \
  feeds/luci/applications/luci-app-netdata \
  package/feeds/packages/chinadns-ng \
  package/feeds/packages/dns2socks \
  package/feeds/packages/dns2tcp \
  package/feeds/packages/geoview \
  package/feeds/packages/gn \
  package/feeds/packages/hysteria \
  package/feeds/packages/ipt2socks \
  package/feeds/packages/microsocks \
  package/feeds/packages/naiveproxy \
  package/feeds/packages/shadowsocks-libev \
  package/feeds/packages/shadowsocks-rust \
  package/feeds/packages/shadowsocksr-libev \
  package/feeds/packages/simple-obfs \
  package/feeds/packages/sing-box \
  package/feeds/packages/ssocks \
  package/feeds/packages/tcping \
  package/feeds/packages/trojan-plus \
  package/feeds/packages/tuic-client \
  package/feeds/packages/v2ray-core \
  package/feeds/packages/v2ray-geodata \
  package/feeds/packages/v2ray-plugin \
  package/feeds/packages/xray-core \
  package/feeds/packages/xray-plugin \
  package/feeds/luci/luci-app-argon-config \
  package/feeds/luci/luci-app-passwall \
  package/feeds/luci/luci-app-passwall2 \
  package/feeds/luci/luci-app-openclash \
  package/feeds/luci/luci-app-netdata

# AdGuardHome：仅装 kenzok8 LuCI，核心由界面在线下载。
git_sparse_clone main https://github.com/kenzok8/small-package luci-app-adguardhome

# 常用插件
git clone --depth=1 https://github.com/tonylee2022/luci-app-openclaw package/luci-app-openclaw
git clone --depth=1 https://github.com/sirpdboy/luci-app-poweroffdevice package/luci-app-poweroffdevice
git clone --depth=1 https://github.com/sirpdboy/netspeedtest package/netspeedtest-luci
git clone --depth=1 https://github.com/sirpdboy/luci-app-advanced package/luci-app-advanced
git clone --depth=1 https://github.com/Jason6111/luci-app-netdata package/luci-app-netdata
git clone --depth=1 https://github.com/tonylee2022/luci-app-nezha-agent package/luci-app-nezha-agent

# 代理插件，优先使用 nftables/firewall4 方案。
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/openwrt-passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall package/luci-app-passwall
git clone --depth=1 https://github.com/vernesong/OpenClash package/openclash-luci

# Themes
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config

# 在线用户
git_sparse_clone main https://github.com/haiibo/packages luci-app-onliner
[ ! -f package/luci-app-onliner/root/usr/share/onliner/setnlbw.sh ] || chmod 755 package/luci-app-onliner/root/usr/share/onliner/setnlbw.sh

# 固件版本标识
openwrt_version="$(awk '/^VERSION_NUMBER:=\$\(if/{gsub(/.*,/ , ""); gsub(/\).*/, ""); print; exit}' include/version.mk)"
[ -n "$openwrt_version" ] || { echo "Unable to detect OpenWrt version" >&2; exit 1; }
sed -i "s#^VERSION_DIST:=.*#VERSION_DIST:=\$(if \$(VERSION_DIST),\$(VERSION_DIST),OpenWrt ${openwrt_version} by TonyLee)#" include/version.mk

# LuCI 版本保留 Git 日期，去掉最后的提交哈希。
[ ! -f feeds/luci/modules/luci-base/src/Makefile ] || sed -i "s#revision = '\$(LUCI_VERSION)'#revision = '\$(shell echo \$(LUCI_VERSION) | rev | cut -d- -f2- | rev)'#" feeds/luci/modules/luci-base/src/Makefile
[ ! -f feeds/luci/modules/luci-lua-runtime/src/mkversion.sh ] || sed -i 's/luciversion = "${2:-Git}"/luciversion = "${2%-*}"/' feeds/luci/modules/luci-lua-runtime/src/mkversion.sh

# 兼容部分第三方 Makefile 的相对路径写法。
find package/*/ -maxdepth 2 -path "*/Makefile" -print0 | xargs -0 -r sed -i 's#../../luci.mk#$(TOPDIR)/feeds/luci/luci.mk#g'
find package/*/ -maxdepth 2 -path "*/Makefile" -print0 | xargs -0 -r sed -i 's#../../lang/golang/golang-package.mk#$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk#g'
find package/*/ -maxdepth 2 -path "*/Makefile" -print0 | xargs -0 -r sed -i 's#PKG_SOURCE_URL:=@GHREPO#PKG_SOURCE_URL:=https://github.com#g'
find package/*/ -maxdepth 2 -path "*/Makefile" -print0 | xargs -0 -r sed -i 's#PKG_SOURCE_URL:=@GHCODELOAD#PKG_SOURCE_URL:=https://codeload.github.com#g'

./scripts/feeds update -a
./scripts/feeds install -a
