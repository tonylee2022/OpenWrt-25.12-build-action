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
sed -i '/^CONFIG_IMAGEOPT=/d; /^# CONFIG_IMAGEOPT is not set/d; /^CONFIG_PREINITOPT=/d; /^# CONFIG_PREINITOPT is not set/d; /^CONFIG_TARGET_DEFAULT_LAN_IP_FROM_PREINIT=/d; /^CONFIG_TARGET_PREINIT_IP=/d; /^CONFIG_TARGET_PREINIT_BROADCAST=/d; /^CONFIG_VMDK_IMAGES=/d; /^# CONFIG_VMDK_IMAGES is not set/d' .config
cat >> .config <<'EOF'
CONFIG_IMAGEOPT=y
CONFIG_PREINITOPT=y
CONFIG_TARGET_DEFAULT_LAN_IP_FROM_PREINIT=y
CONFIG_TARGET_PREINIT_IP="192.168.5.3"
CONFIG_TARGET_PREINIT_BROADCAST="192.168.5.255"
CONFIG_VMDK_IMAGES=y
EOF

# 默认 shell 为 zsh
[ ! -f package/base-files/files/etc/passwd ] || sed -i 's#/bin/ash#/usr/bin/zsh#g' package/base-files/files/etc/passwd

# TTYD root 自动登录
[ ! -f feeds/packages/utils/ttyd/files/ttyd.config ] || sed -i 's#/bin/login#/bin/login -f root#g' feeds/packages/utils/ttyd/files/ttyd.config

# 移除官方 feeds 中需要由第三方仓库替换的冲突包。Transmission 和 firewall4 使用 OpenWrt 25.12 官方源。
remove_paths \
  feeds/packages/net/microsocks \
  feeds/packages/net/sing-box \
  feeds/packages/net/v2ray-core \
  feeds/packages/net/v2ray-geodata \
  feeds/packages/net/xray-core \
  feeds/luci/applications/luci-app-adguardhome \
  package/feeds/packages/microsocks \
  package/feeds/packages/sing-box \
  package/feeds/packages/v2ray-core \
  package/feeds/packages/v2ray-geodata \
  package/feeds/packages/xray-core \
  package/feeds/luci/luci-app-adguardhome

# AdGuardHome：仅装 kenzok8 LuCI，核心由界面在线下载。
git_sparse_clone main https://github.com/kenzok8/small-package luci-app-adguardhome

# 常用插件
git clone --depth=1 https://github.com/tonylee2022/luci-app-openclaw package/luci-app-openclaw
git clone --depth=1 https://github.com/sirpdboy/luci-app-poweroffdevice package/luci-app-poweroffdevice
git clone --depth=1 https://github.com/sirpdboy/netspeedtest package/netspeedtest-luci
git clone --depth=1 https://github.com/sirpdboy/luci-app-advanced package/luci-app-advanced
git_sparse_clone main https://github.com/sirpdboy/luci-app-netdata luci-app-netdata
git clone --depth=1 https://github.com/tonylee2022/luci-app-nezha-agent package/luci-app-nezha-agent

# OpenWrt 25.12 官方 feeds 未提供的 LEDE LuCI 应用。
git_sparse_clone openwrt-25.12 https://github.com/coolsnowwolf/luci \
  applications/luci-app-diskman \
  applications/luci-app-openvpn-server \
  applications/luci-app-ramfree \
  applications/luci-app-syncdial \
  applications/luci-app-zerotier

# 代理插件，优先使用 nftables/firewall4 方案。
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/openwrt-passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall package/luci-app-passwall
[ ! -f package/luci-app-passwall/luci-app-passwall/Makefile ] || sed -i 's/select PACKAGE_nftables$/select PACKAGE_nftables-json/' package/luci-app-passwall/luci-app-passwall/Makefile
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
