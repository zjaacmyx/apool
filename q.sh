#!/bin/bash

# Apool XMRMiner 自动部署和升级脚本
# 适用于Debian/Ubuntu系统

set -e

INSTALL_DIR="/opt/xmrminer"
WALLET_ADDRESS="CP_efl292npux"
POOL_URL="xmr.apool.io:3333"
VERSION="v3.2.3"
GITHUB_REPO="apool-io/xmrminer"

echo "=== 开始部署Apool XMRMiner挖矿程序 ==="

# 更新系统并安装依赖
echo "[1/5] 更新系统并安装依赖..."
apt update -y
apt install -y wget curl jq

# 下载XMRMiner
echo "[2/5] 下载XMRMiner ${VERSION}..."
if [ -d "$INSTALL_DIR" ]; then
    echo "检测到已存在的目录，正在删除..."
    rm -rf "$INSTALL_DIR"
fi

mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# 下载最新版本
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/xmrminer-${VERSION}-linux-x64.tar.gz"
echo "正在从 ${DOWNLOAD_URL} 下载..."
wget -O xmrminer.tar.gz $DOWNLOAD_URL
tar -xzf xmrminer.tar.gz
rm xmrminer.tar.gz

# 赋予执行权限
chmod +x $INSTALL_DIR/xmrminer

# 创建配置文件
echo "[3/5] 创建配置文件..."
cat > $INSTALL_DIR/config.json <<EOF
{
    "autosave": true,
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "hw-aes": null,
        "priority": null,
        "max-threads-hint": 100
    },
    "opencl": false,
    "cuda": false,
    "pools": [
        {
            "algo": "rx/0",
            "coin": "monero",
            "url": "$POOL_URL",
            "user": "$WALLET_ADDRESS",
            "pass": "x",
            "rig-id": null,
            "keepalive": true,
            "enabled": true,
            "tls": false,
            "tls-fingerprint": null
        }
    ],
    "log-file": "/var/log/xmrminer.log",
    "donate-level": 1
}
EOF

# 创建systemd服务
echo "[4/5] 创建systemd服务..."
cat > /etc/systemd/system/xmrminer.service <<EOF
[Unit]
Description=Apool XMRMiner Cryptocurrency Miner
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/xmrminer -c $INSTALL_DIR/config.json
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 创建自动升级脚本
echo "[5/5] 创建自动升级脚本..."
cat > /usr/local/bin/xmrminer-upgrade.sh <<'UPGRADE_SCRIPT'
#!/bin/bash

INSTALL_DIR="/opt/xmrminer"
GITHUB_REPO="apool-io/xmrminer"
LOG_FILE="/var/log/xmrminer-upgrade.log"
CURRENT_VERSION_FILE="$INSTALL_DIR/version.txt"

echo "$(date): 开始检查XMRMiner更新..." >> $LOG_FILE

# 获取当前版本
if [ -f "$CURRENT_VERSION_FILE" ]; then
    CURRENT_VERSION=$(cat $CURRENT_VERSION_FILE)
else
    CURRENT_VERSION="unknown"
fi

# 获取最新版本
LATEST_VERSION=$(curl -s https://api.github.com/repos/$GITHUB_REPO/releases/latest | jq -r '.tag_name')

if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" == "null" ]; then
    echo "$(date): 获取最新版本失败" >> $LOG_FILE
    exit 1
fi

echo "$(date): 当前版本: $CURRENT_VERSION, 最新版本: $LATEST_VERSION" >> $LOG_FILE

if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
    echo "$(date): 检测到新版本，开始升级..." >> $LOG_FILE
    
    # 停止服务
    systemctl stop xmrminer
    
    # 备份配置
    cp $INSTALL_DIR/config.json /tmp/xmrminer-config.json.bak
    
    # 下载新版本
    cd /tmp
    DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${LATEST_VERSION}/xmrminer-${LATEST_VERSION}-linux-x64.tar.gz"
    wget -O xmrminer-new.tar.gz $DOWNLOAD_URL
    
    # 删除旧版本
    rm -rf $INSTALL_DIR/*
    
    # 解压新版本
    tar -xzf xmrminer-new.tar.gz -C $INSTALL_DIR
    rm xmrminer-new.tar.gz
    
    # 恢复配置
    cp /tmp/xmrminer-config.json.bak $INSTALL_DIR/config.json
    
    # 赋予执行权限
    chmod +x $INSTALL_DIR/xmrminer
    
    # 保存版本信息
    echo $LATEST_VERSION > $CURRENT_VERSION_FILE
    
    # 重启服务
    systemctl start xmrminer
    
    echo "$(date): 升级完成，版本: $LATEST_VERSION" >> $LOG_FILE
else
    echo "$(date): 已是最新版本" >> $LOG_FILE
fi
UPGRADE_SCRIPT

chmod +x /usr/local/bin/xmrminer-upgrade.sh

# 保存当前版本信息
echo $VERSION > $INSTALL_DIR/version.txt

# 创建定时任务（每天凌晨3点检查更新）
echo "[6/6] 设置自动升级定时任务..."
cat > /etc/cron.d/xmrminer-upgrade <<EOF
# 每天凌晨3点检查并升级XMRMiner
0 3 * * * root /usr/local/bin/xmrminer-upgrade.sh
EOF

# 启用并启动服务
echo "=== 启动XMRMiner服务 ==="
systemctl daemon-reload
systemctl enable xmrminer
systemctl start xmrminer

# 显示状态
echo ""
echo "=== 部署完成 ==="
echo "程序版本: ${VERSION}"
echo "挖矿钱包: $WALLET_ADDRESS"
echo "矿池地址: $POOL_URL"
echo ""
echo "服务状态:"
systemctl status xmrminer --no-pager
echo ""
echo "查看实时日志: journalctl -u xmrminer -f"
echo "查看升级日志: tail -f /var/log/xmrminer-upgrade.log"
echo "手动升级: /usr/local/bin/xmrminer-upgrade.sh"
echo ""
