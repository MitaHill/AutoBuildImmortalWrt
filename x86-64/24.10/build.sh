#!/bin/bash
# Log file for debugging
source shell/custom-packages.sh
echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
echo "编译固件大小为: $PROFILE MB"
echo "Include Docker: $INCLUDE_DOCKER"

echo "Create pppoe-settings"
mkdir -p  /home/build/immortalwrt/files/etc/config

# 创建pppoe配置文件 yml传入环境变量ENABLE_PPPOE等 写入配置文件 供99-custom.sh读取
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ 未选择 任何第三方软件包"
else
  # ============= 同步第三方插件库==============
  # 同步第三方软件仓库run/ipk
  echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
  git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo

  # 拷贝 run/x86 下所有 run 文件和ipk文件 到 extra-packages 目录
  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-run-repo/run/x86/* /home/build/immortalwrt/extra-packages/

  echo "✅ Run files copied to extra-packages:"
  ls -lh /home/build/immortalwrt/extra-packages/*.run
  # 解压并拷贝ipk到packages目录
  sh shell/prepare-packages.sh
  ls -lah /home/build/immortalwrt/packages/
fi

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."

# ============= imm仓库内的插件==============
# 定义所需安装的包列表 下列插件你都可以自行删减
PACKAGES=""
# --- 核心代理 (PassWall & Core) ---
PACKAGES="$PACKAGES luci-app-passwall"
PACKAGES="$PACKAGES luci-i18n-passwall-zh-cn"
PACKAGES="$PACKAGES sing-box xray-core trojan-plus"
PACKAGES="$PACKAGES v2ray-geoip v2ray-geosite openssl-util"

# --- 基础工具与系统组件 (实体机优化) ---
PACKAGES="$PACKAGES curl wget-ssl nano htop tar unzip"
PACKAGES="$PACKAGES ca-certificates"
PACKAGES="$PACKAGES luci-app-ttyd openssh-sftp-server"

# --- 核心网络与诊断 ---
PACKAGES="$PACKAGES bind-dig"
PACKAGES="$PACKAGES iftop"
PACKAGES="$PACKAGES luci-app-upnp"
PACKAGES="$PACKAGES luci-app-wol"
PACKAGES="$PACKAGES luci-app-mwan3"
PACKAGES="$PACKAGES luci-app-ddns"

# --- 流量控制 (QoS) ---
PACKAGES="$PACKAGES luci-app-sqm"
# PACKAGES="$PACKAGES luci-app-access-control"
# PACKAGES="$PACKAGES luci-app-banip"

# --- 监控与统计 (官方源稳定包) ---
PACKAGES="$PACKAGES luci-app-netdata"
PACKAGES="$PACKAGES luci-app-nlbwmon"
PACKAGES="$PACKAGES luci-app-statistics"

# --- 磁盘管理 ---
PACKAGES="$PACKAGES luci-app-diskman"

# --- IPv6 支持 ---
PACKAGES="$PACKAGES odhcp6c odhcpd-ipv6only luci-proto-ipv6"
PACKAGES="$PACKAGES kmod-nft-bridge"

# ======== shell/custom-packages.sh =======
# 合并imm仓库以外的第三方插件 (Passwall)
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# ==========================================
# 🛑 尝试下载第三方实时监控插件 (Wrtbwmon)
# 暂时注释以确保构建成功 (Fix Build Failure)
# ==========================================
# echo "⬇️ Attempting to pre-download wrtbwmon..."
# mkdir -p /home/build/immortalwrt/packages
# wget -P /home/build/immortalwrt/packages/ https://github.com/brvphoenix/wrtbwmon/releases/download/v1.5.2/wrtbwmon_1.5.2_all.ipk || echo "wrtbwmon skip"
# wget -P /home/build/immortalwrt/packages/ https://github.com/brvphoenix/luci-app-wrtbwmon/releases/download/release-v2.0.10/luci-app-wrtbwmon_2.0.10_all.ipk || echo "luci-app-wrtbwmon skip"
# ==========================================

# 若构建openclash 则添加内核

# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-amd64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    # Download GeoIP and GeoSite
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$PROFILE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
