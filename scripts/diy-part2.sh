#!/bin/bash
# DIY part2: feeds install 完成、make defconfig 之前执行
# 作用：写入默认配置、生成精简插件、处理版本要求
set -e
ROOT="$(pwd)"
CUSTOM="$ROOT/package/openwrt-custom"

echo "[diy2] ========== 默认系统设置 =========="

# 1) 管理 IP -> 10.0.1.1
LAN_CFG="$ROOT/package/base-files/files/bin/config_generate"
[ -f "$LAN_CFG" ] && sed -i "s/ipaddr='192.168.1.1'/ipaddr='10.0.1.1'/g; s/ip6assign='60'/ip6assign='60'/g" "$LAN_CFG"

# 2) 主机名 -> OpenWRT
[ -f "$LAN_CFG" ] && sed -i "s/hostname='.*'/hostname='OpenWRT'/g" "$LAN_CFG"

# 3) 默认中文界面 + 时区（uci-defaults 方式，避免覆盖整份 luci 配置冲突）
mkdir -p "$ROOT/files/etc/config" "$ROOT/files/etc/uci-defaults"
cat > "$ROOT/files/etc/uci-defaults/10-luci-lang-zh" <<'EOF'
#!/bin/sh
uci set luci.main.lang='zh_cn'
uci set luci.core.lang='zh_cn' 2>/dev/null || true
uci commit luci
exit 0
EOF
chmod +x "$ROOT/files/etc/uci-defaults/10-luci-lang-zh"

# 时区
cat > "$ROOT/files/etc/config/system" <<'EOF'
config system
        option hostname 'OpenWRT'
        option tz 'CST-8'
        option tzname 'CST-8'
        option zonename 'Asia/Shanghai'
        option log_size '64'
        option conloglevel '8'
        option cronloglevel '8'
EOF

# 4) root 密码 -> password (shadow 哈希)
mkdir -p "$ROOT/files/etc"
cat > "$ROOT/files/etc/shadow" <<'EOF'
root:$1$abcdef$AVdKyYQ1Yq4JqF1JqF1Jq0:0:0:99999:7:::
EOF
# 上面占位，下面用 openssl 生成真实哈希覆盖
HASH=$(openssl passwd -1 -salt openwrt password 2>/dev/null || echo "")
if [ -n "$HASH" ]; then
  printf "root:%s:0:0:99999:7:::\n" "$HASH" > "$ROOT/files/etc/shadow"
fi
chmod 600 "$ROOT/files/etc/shadow"

echo "[diy2] ========== 内核网络/BBR 调优 =========="
# 默认开启 fq + bbr（TurboACC 也会管理，此处兜底）
mkdir -p "$ROOT/files/etc/sysctl.d"
cat > "$ROOT/files/etc/sysctl.d/99-custom.conf" <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 65536 33554432
EOF

echo "[diy2] ========== dnsmasq 版本校验(需 >=2.92 供 passwall) =========="
DM_MK="$ROOT/package/network/services/dnsmasq/Makefile"
if [ -f "$DM_MK" ]; then
    DM_VER=$(grep -oP 'PKG_VERSION:=\K[0-9.]+' "$DM_MK" | head -1)
    echo "[diy2] 当前 dnsmasq 版本: ${DM_VER:-unknown}"
    # 若低于 2.92，尝试通过反代升级到 2.92（Lean 主线通常已满足；这里只校验不强制改源码避免破坏）
fi

echo "[diy2] ========== iStore 强制中文 =========="
STORE_DIR="$ROOT/feeds/istore"
if [ -d "$STORE_DIR" ]; then
    # 给 istore 注入默认中文环境变量
    grep -q "istore_vue_lang" "$STORE_DIR/root/etc/uci-defaults/*" 2>/dev/null || true
    mkdir -p "$ROOT/files/etc/uci-defaults"
    cat > "$ROOT/files/etc/uci-defaults/99-istore-zh" <<'EOF'
#!/bin/sh
uci set istore.@main[0].lang='zh-cn' 2>/dev/null || true
uci commit istore 2>/dev/null || true
exit 0
EOF
    chmod +x "$ROOT/files/etc/uci-defaults/99-istore-zh"
fi

echo "[diy2] ========== 修复 alist cgofuse 缺 fuse.h =========="
ALIST_MK="$CUSTOM/luci-app-alist/alist/Makefile"
if [ -f "$ALIST_MK" ]; then
    # 1) 加 fuse3 构建依赖(让头文件进 staging)
    sed -i 's|^PKG_BUILD_DEPENDS:=golang/host$|PKG_BUILD_DEPENDS:=golang/host fuse3|' "$ALIST_MK"
    # 2) Build/Prepare 开头把 fuse3 全部头文件软链到 include 根目录(cgofuse 需要 fuse.h / fuse_common.h 等)
    sed -i '/^define Build\/Prepare$/a\\tln -sf $(STAGING_DIR)/usr/include/fuse3/*.h $(STAGING_DIR)/usr/include/ 2>/dev/null || true' "$ALIST_MK"
    # 3) 运行期也依赖 fuse3
    sed -i 's|^  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle$|  DEPENDS:=$(GO_ARCH_DEPENDS) +ca-bundle +fuse3|' "$ALIST_MK"
    echo "[diy2] alist Makefile 已打 fuse3 补丁"
    grep -n "fuse3\|PKG_BUILD_DEPENDS" "$ALIST_MK" | head
fi

echo "[diy2] ========== 生成精简 luci-app-freemem (释放内存) =========="
FM="$CUSTOM/luci-app-freemem"
mkdir -p "$FM/luasrc/controller" "$FM/luasrc/model/cbi" "$FM/root/usr/bin" "$FM/root/etc/uci-defaults"

cat > "$FM/Makefile" <<'EOF'
# SPDX-License-Identifier: MIT
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-freemem
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/luci.mk

# call BuildPackage - OpenWrt buildroot signature
EOF

cat > "$FM/luasrc/controller/freemem.lua" <<'EOF'
module("luci.controller.freemem", package.seeall)
function index()
    entry({"admin", "system", "freemem"}, cbi("freemem"), _("释放内存"), 60).dependent = true
end
EOF

cat > "$FM/luasrc/model/cbi/freemem.lua" <<'EOF'
m = Map("freemem", translate("释放内存"), translate("点击下方按钮释放系统缓存占用的内存。"))
s = m:section(SimpleSection)
s.sud = true
s:option(DummyValue, "info", translate("说明")).value = translate("向 /proc/sys/vm/drop_caches 写入 3，释放 pagecache、dentries 与 inodes。")
btn = s:option(Button, "free", translate("立即释放"))
btn.inputstyle = "apply"
btn.write = function()
    luci.util.exec("echo 3 > /proc/sys/vm/drop_caches")
end
return m
EOF

cat > "$FM/root/usr/bin/freemem" <<'EOF'
#!/bin/sh
echo 3 > /proc/sys/vm/drop_caches
echo "freemem: dropped caches"
EOF
chmod +x "$FM/root/usr/bin/freemem"

# 中文翻译
mkdir -p "$FM/po/zh-cn"
cat > "$FM/po/zh-cn/freemem.po" <<'EOF'
msgid ""
msgstr ""
msgid "释放内存"
msgstr "释放内存"
msgid "说明"
msgstr "说明"
msgid "立即释放"
msgstr "立即释放"
EOF

echo "[diy2] ========== 完成 =========="
