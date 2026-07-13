#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# kenzok8 插件：AdGuardHome 仅装 LuCI，核心由界面在线下载。
git_sparse_clone main https://github.com/kenzok8/small-package \
  luci-app-adguardhome \
  luci-theme-glass
[ ! -f "$script_dir/patches/luci-theme-glass/po/zh_Hans/glass.po" ] || install -m 0644 "$script_dir/patches/luci-theme-glass/po/zh_Hans/glass.po" package/luci-theme-glass/po/zh_Hans/glass.po

# 常用插件
git clone --depth=1 https://github.com/tonylee2022/luci-app-openclaw package/luci-app-openclaw
git clone --depth=1 https://github.com/sirpdboy/luci-app-poweroffdevice package/luci-app-poweroffdevice
git clone --depth=1 https://github.com/sirpdboy/netspeedtest package/netspeedtest-luci
git clone --depth=1 https://github.com/sirpdboy/luci-app-advanced package/luci-app-advanced
# git_sparse_clone main https://github.com/sirpdboy/luci-app-netdata luci-app-netdata
git clone --depth=1 https://github.com/tonylee2022/luci-app-nezha-agent package/luci-app-nezha-agent

# OpenWrt 25.12 官方 feeds 未提供的 LEDE LuCI 应用。
git_sparse_clone openwrt-25.12 https://github.com/coolsnowwolf/luci \
  applications/luci-app-diskman \
  applications/luci-app-openvpn-server \
  applications/luci-app-ramfree \
  applications/luci-app-zerotier
# applications/luci-app-syncdial

# 代理插件，优先使用 nftables/firewall4 方案。
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/openwrt-passwall
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall package/luci-app-passwall
git clone --depth=1 https://github.com/vernesong/OpenClash package/openclash-luci

# Themes
git clone --depth=1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config

# LuCI 一级菜单：网络存储 / Docker。官方 25.12 的 Dockerman 默认在“服务”下，KSMBD 需要补父菜单。
mkdir -p package/base-files/files/usr/share/luci/menu.d
cat > package/base-files/files/usr/share/luci/menu.d/99-tonylee-menu.json <<'EOF'
{
	"admin/nas": {
		"title": "NAS",
		"order": 45,
		"action": { "type": "firstchild" }
	},
	"admin/docker": {
		"title": "Docker",
		"order": 46,
		"action": { "type": "firstchild" }
	}
}
EOF
for dockerman_menu in \
  feeds/luci/applications/luci-app-dockerman/root/usr/share/luci/menu.d/luci-app-dockerman.json \
  package/feeds/luci/luci-app-dockerman/root/usr/share/luci/menu.d/luci-app-dockerman.json; do
  [ ! -f "$dockerman_menu" ] || sed -i \
    -e 's#admin/services/dockerman#admin/docker#g' \
    -e 's#"title": "Dockerman JS"#"title": "Docker"#' \
    -e 's#"title": "DockerMan"#"title": "Docker"#' \
    "$dockerman_menu"
done
[ ! -f package/luci-theme-argon/htdocs/luci-static/argon/css/cascade.css ] || sed -i 's#\.main-left \.nav li \.menu\[data-title="NAS"\]:before#.main-left .nav li .menu[data-title="NAS"]:before,.main-left .nav li .menu[data-title="网络存储"]:before#' package/luci-theme-argon/htdocs/luci-static/argon/css/cascade.css
if [ -f feeds/luci/modules/luci-base/po/zh_Hans/base.po ] && ! grep -q '^msgid "NAS"$' feeds/luci/modules/luci-base/po/zh_Hans/base.po; then
cat >> feeds/luci/modules/luci-base/po/zh_Hans/base.po <<'EOF'

msgid "NAS"
msgstr "网络存储"
EOF
fi

# 在线用户
git_sparse_clone main https://github.com/haiibo/packages luci-app-onliner
[ ! -f package/luci-app-onliner/root/usr/share/onliner/setnlbw.sh ] || chmod 755 package/luci-app-onliner/root/usr/share/onliner/setnlbw.sh

# 固件版本标识。状态页会追加 VERSION_NUMBER / REVISION，这里只保留发行名，避免版本号重复。
sed -i "s#^VERSION_DIST:=.*#VERSION_DIST:=\$(if \$(VERSION_DIST),\$(VERSION_DIST),OpenWrt by TonyLee)#" include/version.mk

# LuCI 版本去掉 detached/head 前缀和最后的提交哈希，只保留形如 26.180.75667~128a781 的短版本。
[ ! -f feeds/luci/modules/luci-base/src/Makefile ] || sed -i "s#revision = '\$(LUCI_VERSION)'#revision = '\$(shell echo \$(LUCI_VERSION) | sed 's/.* branch //' | rev | cut -d- -f2- | rev)'#" feeds/luci/modules/luci-base/src/Makefile
[ ! -f feeds/luci/modules/luci-base/src/Makefile ] || sed -i "s#branch = '\$(LUCI_GITBRANCH)'#branch = 'LuCI'#" feeds/luci/modules/luci-base/src/Makefile
[ ! -f feeds/luci/modules/luci-lua-runtime/src/mkversion.sh ] || sed -i 's#^luciname    = .*#luciname    = "LuCI"#' feeds/luci/modules/luci-lua-runtime/src/mkversion.sh
[ ! -f feeds/luci/modules/luci-lua-runtime/src/mkversion.sh ] || sed -i 's#^luciversion = .*#luciversion = "$(printf '"'"'%s\\n'"'"' "${2:-Git}" | sed '"'"'s/.* branch //'"'"' | rev | cut -d- -f2- | rev)"#' feeds/luci/modules/luci-lua-runtime/src/mkversion.sh

# 兼容部分第三方 Makefile 的相对路径写法。
find package/*/ -maxdepth 2 -path "*/Makefile" -print0 | xargs -0 -r sed -i 's#../../luci.mk#$(TOPDIR)/feeds/luci/luci.mk#g'
find package/*/ -maxdepth 2 -path "*/Makefile" -print0 | xargs -0 -r sed -i 's#../../lang/golang/golang-package.mk#$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk#g'
find package/*/ -maxdepth 2 -path "*/Makefile" -print0 | xargs -0 -r sed -i 's#PKG_SOURCE_URL:=@GHREPO#PKG_SOURCE_URL:=https://github.com#g'
find package/*/ -maxdepth 2 -path "*/Makefile" -print0 | xargs -0 -r sed -i 's#PKG_SOURCE_URL:=@GHCODELOAD#PKG_SOURCE_URL:=https://codeload.github.com#g'
