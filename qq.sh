#!/bin/bash

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[开始部署]${NC}"

# ===== 配置区域 =====
# 挖矿配置
YOUR_ACCOUNT="CP_efl292npux"        # ⚠️ 请确认这是您的账户！
YOUR_POOL="xmr-us.apool.io:3333"    # XMR矿池地址
ALGO="rx/0"                          # RandomX算法

# SSH配置
ROOT_PASSWORD="NP1215GP55*3*AACAAC"

# Docker服务Token
TM_TOKEN="ayDMa3ja408jPdTBBzbTE52Mv9uWZ+QK963WOq7QVb4="
EARNFM_TOKEN="6e5e344d-2b78-42d5-b48e-0abf33411801"
PACKETSHARE_EMAIL="q2326426@gmail.com"
PACKETSHARE_PASSWORD="q7s4d6f9e2c39sd47f"
# ==========================================

echo -e "${YELLOW}使用配置:${NC}"
echo -e "挖矿账户: $YOUR_ACCOUNT"
echo -e "矿池: $YOUR_POOL"
echo -e "算法: $ALGO"
echo ""

# SSH配置
echo -e "${GREEN}[1/8] 配置SSH...${NC}"
echo "root:$ROOT_PASSWORD" | sudo chpasswd root
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
sudo service sshd restart

# 安装apool挖矿软件
echo -e "${GREEN}[2/8] 安装apool挖矿软件...${NC}"
APOOL_DIR="/root/apoolminer"
mkdir -p $APOOL_DIR
cd $APOOL_DIR

# 获取最新版本
LATEST_VERSION=$(curl -s https://api.github.com/repos/apool-io/xmrminer/releases/latest | grep "tag_name" | cut -d '"' -f 4)
if [ -z "$LATEST_VERSION" ]; then
    LATEST_VERSION="v3.2.3"
fi

DOWNLOAD_URL="https://github.com/apool-io/xmrminer/releases/download/${LATEST_VERSION}/apoolminer_linux_xmr_${LATEST_VERSION}.tar.gz"

echo -e "${GREEN}下载版本: ${LATEST_VERSION}${NC}"
wget -P /root $DOWNLOAD_URL
tar -xf /root/apoolminer_linux_xmr_${LATEST_VERSION}.tar.gz -C /root
cp -a /root/apoolminer_linux_xmr_${LATEST_VERSION}/. $APOOL_DIR/
rm -f /root/apoolminer_linux_xmr_${LATEST_VERSION}.tar.gz

# 创建配置文件
cat > $APOOL_DIR/miner.conf << EOF
algo=$ALGO
pool=$YOUR_POOL
account=$YOUR_ACCOUNT
worker=$(hostname -I | awk '{print $1}')
cpu-off=false
gpu-off=false
log=true
EOF

# 创建启动脚本
cat > $APOOL_DIR/start_miner.sh << 'STARTSCRIPT'
#!/bin/bash

cd /root/apoolminer

# 获取公网IP作为worker名称
WORKER=$(curl -s https://api.ipify.org)
if [ -z "$WORKER" ]; then
    WORKER=$(hostname -I | awk '{print $1}')
fi

# 读取配置
source ./miner.conf

# 停止旧进程
pkill -f apoolminer
sleep 2

# 构建参数
params=()
params+=(--algo "$algo")
params+=(--pool "$pool")
params+=(--account "$account")
params+=(--worker "$WORKER")

[ "$cpu_off" == "true" ] && params+=(--cpu-off)
[ "$gpu_off" == "true" ] && params+=(--gpu-off)
[ "$log" == "true" ] && params+=(--log)

# 启动挖矿
nohup ./apoolminer "${params[@]}" > miner.log 2>&1 &

echo "============================================"
echo "挖矿已启动"
echo "账户: $account"
echo "Worker: $WORKER"
echo "矿池: $pool"
echo "算法: $algo"
echo "日志: tail -f /root/apoolminer/miner.log"
echo "============================================"
STARTSCRIPT

chmod +x $APOOL_DIR/start_miner.sh

# 创建自动升级脚本
echo -e "${GREEN}[3/8] 创建自动升级脚本...${NC}"
cat > /root/apool_update.sh << 'UPDATESCRIPT'
#!/bin/bash

APOOL_DIR="/root/apoolminer"
CURRENT_VERSION_FILE="$APOOL_DIR/.version"

# 获取当前版本
if [ -f "$CURRENT_VERSION_FILE" ]; then
    CURRENT_VERSION=$(cat $CURRENT_VERSION_FILE)
else
    CURRENT_VERSION="unknown"
fi

# 获取最新版本
LATEST_VERSION=$(curl -s https://api.github.com/repos/apool-io/xmrminer/releases/latest | grep "tag_name" | cut -d '"' -f 4)

if [ -z "$LATEST_VERSION" ]; then
    echo "[$(date)] 无法获取最新版本"
    exit 1
fi

# 比较版本
if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
    echo "[$(date)] 发现新版本: $LATEST_VERSION (当前: $CURRENT_VERSION)"
    
    # 停止挖矿进程
    pkill -f apoolminer
    sleep 5
    
    # 备份配置和日志
    [ -f "$APOOL_DIR/miner.conf" ] && cp $APOOL_DIR/miner.conf /tmp/miner.conf.bak
    [ -f "$APOOL_DIR/miner.log" ] && cp $APOOL_DIR/miner.log /tmp/miner.log.bak
    
    # 下载新版本
    cd /root
    wget -q https://github.com/apool-io/xmrminer/releases/download/${LATEST_VERSION}/apoolminer_linux_xmr_${LATEST_VERSION}.tar.gz
    
    if [ $? -eq 0 ]; then
        tar -xf apoolminer_linux_xmr_${LATEST_VERSION}.tar.gz -C /root
        
        # 备份旧版本
        [ -d "$APOOL_DIR.old" ] && rm -rf $APOOL_DIR.old
        cp -r $APOOL_DIR $APOOL_DIR.old
        
        # 安装新版本
        cp -a /root/apoolminer_linux_xmr_${LATEST_VERSION}/. $APOOL_DIR/
        
        # 恢复配置
        [ -f "/tmp/miner.conf.bak" ] && cp /tmp/miner.conf.bak $APOOL_DIR/miner.conf
        
        # 更新版本记录
        echo $LATEST_VERSION > $CURRENT_VERSION_FILE
        
        # 重启挖矿
        cd $APOOL_DIR
        chmod +x apoolminer start_miner.sh
        ./start_miner.sh
        
        echo "[$(date)] 升级成功: $CURRENT_VERSION -> $LATEST_VERSION"
        
        # 清理
        rm -f /root/apoolminer_linux_xmr_${LATEST_VERSION}.tar.gz
        rm -rf /root/apoolminer_linux_xmr_${LATEST_VERSION}
    else
        echo "[$(date)] 下载失败，重启旧版本"
        cd $APOOL_DIR
        ./start_miner.sh
        exit 1
    fi
else
    echo "[$(date)] 已是最新版本: $CURRENT_VERSION"
fi
UPDATESCRIPT

chmod +x /root/apool_update.sh

# 记录当前版本
echo $LATEST_VERSION > $APOOL_DIR/.version

# 设置定时任务（每天凌晨3点检查更新）
echo -e "${GREEN}[4/8] 配置自动升级定时任务...${NC}"
(crontab -l 2>/dev/null | grep -v "apool_update.sh"; echo "0 3 * * * /root/apool_update.sh >> /var/log/apool_update.log 2>&1") | crontab -

# 启动挖矿
echo -e "${GREEN}[5/8] 启动挖矿程序...${NC}"
cd $APOOL_DIR
./start_miner.sh

sleep 3

# 安装Docker
echo -e "${GREEN}[6/8] 安装Docker...${NC}"
if ! command -v docker &> /dev/null; then
    wget -qO- get.docker.com | bash
    systemctl enable docker
    systemctl start docker
else
    echo "Docker已安装"
fi

# 清理旧容器
echo -e "${GREEN}[7/8] 清理并启动Docker容器...${NC}"
docker stop tm earnfm-client packetshare 2>/dev/null
docker rm tm earnfm-client packetshare 2>/dev/null

# TraffMonetizer
echo "启动 TraffMonetizer..."
docker run -d \
    --restart=always \
    --name tm \
    traffmonetizer/cli_v2 start accept --token $TM_TOKEN

# EarnFM
echo "启动 EarnFM..."
docker run -d \
    --restart=always \
    -e EARNFM_TOKEN="$EARNFM_TOKEN" \
    --name earnfm-client \
    earnfm/earnfm-client:latest

# PacketShare
echo "启动 PacketShare..."
docker run -d \
    --restart unless-stopped \
    --name packetshare \
    packetshare/packetshare \
    -accept-tos \
    -email=$PACKETSHARE_EMAIL \
    -password=$PACKETSHARE_PASSWORD

# Titan Network
echo -e "${GREEN}[8/8] 部署Titan Network...${NC}"
cd /root
wget -q -O duokai.sh https://raw.githubusercontent.com/LSH160981/Titan-Network/main/duokai.sh
if [ -f duokai.sh ]; then
    chmod +x duokai.sh
    nohup ./duokai.sh > titan.log 2>&1 &
    echo "Titan Network 已启动"
fi

sleep 2

# 显示状态
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}         部署完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}挖矿信息:${NC}"
echo -e "  账户: $YOUR_ACCOUNT"
echo -e "  Worker: $(curl -s https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
echo -e "  矿池: $YOUR_POOL"
echo -e "  算法: $ALGO"
echo ""
echo -e "${YELLOW}服务状态:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null
echo ""
echo -e "${YELLOW}管理命令:${NC}"
echo -e "  查看挖矿日志: ${GREEN}tail -f /root/apoolminer/miner.log${NC}"
echo -e "  重启挖矿:     ${GREEN}/root/apoolminer/start_miner.sh${NC}"
echo -e "  手动升级:     ${GREEN}/root/apool_update.sh${NC}"
echo -e "  查看升级日志: ${GREEN}tail -f /var/log/apool_update.log${NC}"
echo -e "  查看Docker:   ${GREEN}docker ps${NC}"
echo ""
echo -e "${YELLOW}自动任务:${NC}"
echo -e "  ✓ 每天凌晨3点自动检查并升级apool"
echo -e "  ✓ 所有Docker容器设置为自动重启"
echo ""
echo -e "${RED}⚠️  重要提醒:${NC}"
echo -e "  请确认挖矿账户 ${YELLOW}$YOUR_ACCOUNT${NC} 是您的账户！"
echo -e "  如果不是，请修改脚本开头的 YOUR_ACCOUNT 参数"
echo -e "${GREEN}========================================${NC}"
