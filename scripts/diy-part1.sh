#!/bin/bash
# DIY part1: feeds update 之后、feeds install 之前执行
# 作用：把不在标准 feed 里的第三方插件精准 clone 到 package/
set -e
PKG_DIR="package/openwrt-custom"
mkdir -p "$PKG_DIR"
cd "$PKG_DIR"

clone() {
    # $1 = 仓库地址  $2 = 目标目录名  $3 = 分支(可选)
    local url="$1" name="$2" branch="${3:-}"
    if [ -d "$name" ]; then
        echo "[diy1] $name 已存在，跳过 clone"
        return 0
    fi
    if [ -n "$branch" ]; then
        git clone --depth=1 -b "$branch" "$url" "$name"
    else
        git clone --depth=1 "$url" "$name"
    fi
}

# ---- 推送类 ----
clone "https://github.com/tty228/luci-app-serverchan.git" "luci-app-serverchan"   # 微信推送 Server酱
clone "https://github.com/zzsj0928/luci-app-pushbot.git"    "luci-app-pushbot"      # 全能推送

# ---- 网络服务类 ----
clone "https://github.com/sirpdboy/luci-app-ddns-go.git"     "luci-app-ddns-go"      # ddns-go
clone "https://github.com/gdy666/luci-app-lucky.git"        "luci-app-lucky"        # lucky
clone "https://github.com/destan19/OpenAppFilter.git"      "OpenAppFilter"         # OAF 行为管理
clone "https://github.com/sbwml/luci-app-alist.git"         "luci-app-alist"        # alist
clone "https://github.com/sbwml/luci-app-openlist2.git"    "luci-app-openlist2"    # openlist

# ---- 系统工具类 ----
clone "https://github.com/lisaac/luci-app-diskman.git"      "luci-app-diskman"      # 磁盘管理
clone "https://github.com/sirpdboy/luci-app-eqosplus.git"   "luci-app-eqosplus"     # IP 限速
clone "https://github.com/sirpdboy/luci-app-poweroff.git"   "luci-app-poweroff"      # 关机(附赠)

# ---- 主题类 ----
clone "https://github.com/jerrykuku/luci-theme-argon.git"    "luci-theme-argon"       # Argon 主题
clone "https://github.com/jerrykuku/luci-app-argon-config.git" "luci-app-argon-config" # Argon 设置

# ---- 1Panel 运维面板 ----
clone "https://github.com/gcsong023/wrt1panel.git"          "wrt1panel"

echo "[diy1] 第三方插件 clone 完成："
ls -1
