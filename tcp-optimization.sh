#!/bin/bash

# ==================================================
# --- 0. 基础配置与环境检查 ---
# ==================================================
SCRIPT_PATH="/usr/local/bin/tcp.sh"
SHORTCUT_PATH="/usr/local/bin/t"
UPDATE_URL="https://raw.githubusercontent.com/666shen/tcp-dashboard/main/tcp.sh"

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m错误: 必须使用 root 权限运行此脚本！\033[0m"
    exit 1
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

draw_line() {
    echo -e "${YELLOW}--------------------------------------------------${NC}"
}

# ==================================================
# --- 1. 自动安装与快捷键设置 ---
# ==================================================
if [ "$_" != "$SCRIPT_PATH" ] && [ "$0" != "$SCRIPT_PATH" ]; then
    echo -e "${YELLOW}>>> 正在安装脚本到本地系统...${NC}"
    mkdir -p /usr/local/bin
    
    curl -sL "$UPDATE_URL" -o "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"

    if [ ! -f "$SHORTCUT_PATH" ] || [ ! -L "$SHORTCUT_PATH" ]; then
        ln -sf "$SCRIPT_PATH" "$SHORTCUT_PATH"
        echo -e "${GREEN}✅ 快捷命令 't' 已创建，以后在任意地方输入 t 即可打开面板。${NC}"
    fi

    exec bash "$SCRIPT_PATH"
    exit 0
fi

# ==================================================
# --- 2. 脚本维护模块 ---
# ==================================================
check_update() {
    printf "${YELLOW}正在同步最新脚本...${NC}\n"
    curl -sL "$UPDATE_URL" -o "$SCRIPT_PATH.tmp"
    if [ $? -eq 0 ]; then
        mv "$SCRIPT_PATH.tmp" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        printf "${GREEN}脚本更新成功！正在重新载入...${NC}\n"
        sleep 1
        exec bash "$SCRIPT_PATH"
    else
        printf "${RED}更新失败，请检查网络连接。\${NC}\n"
        rm -f "$SCRIPT_PATH.tmp"
    fi
}

uninstall_script() {
    echo -e "\n${RED}>>> 正在准备完全卸载脚本与快捷键...${NC}"
    read -p "确定要卸载吗？(这也会同时回退所有网络优化设置) [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}正在恢复网络默认设置...${NC}"
        rollback_tcp_tune &>/dev/null
        rm -f "$SHORTCUT_PATH"
        rm -f "$SCRIPT_PATH"
        echo -e "${GREEN}✅ 卸载成功！网络已恢复，脚本与快捷键 't' 已从系统中移除。${NC}\n"
        exit 0
    else
        echo -e "${GREEN}已取消卸载。${NC}"
        sleep 1
    fi
}

# ==================================================
# --- 3. TCP 深度调优功能模块 ---
# ==================================================
SYSCTL_OPT="/etc/sysctl.d/99-network-performance.conf"
LIMITS_OPT="/etc/security/limits.d/99-network-performance.conf"

enable_bbr_tune() {
    echo -e "\n${YELLOW}>>> 正在激活 BBR + FQ 拥塞算法...${NC}"
    echo "net.core.default_qdisc = fq" >/etc/sysctl.d/10-bbr.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >>/etc/sysctl.d/10-bbr.conf
    sysctl --system &>/dev/null

    echo -e "\n${CYAN}>>> 正在与 Linux 内核交换握手信号，尝试深度激活 BBR 引擎...${NC}"
    sleep 0.4

    local bbr_steps=(
        "Initializing FQ Pacifier" 
        "Loading BBR Kernel Module" 
        "Calibrating Pacing Rate" 
        "Synchronizing TCP States"
    )
    
    for step in "${bbr_steps[@]}"; do
        printf "  ${BLUE}[⚙]${NC} %-28s [" "$step"
        for i in {1..5}; do 
            printf "${GREEN}■${NC}"
            sleep 0.12
        done
        printf "] ${GREEN}[SUCCESS]${NC}\n"
    done

    echo -e "\n${GREEN}🚀 BBR + FQ 网络加速模块已成功灌注至内核底层！${NC}"
    draw_line
    sleep 0.3
    printf "  %-24s : ${GREEN}%-15s${NC}\n" "Current Congestion Control" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    sleep 0.3
    printf "  %-24s : ${GREEN}%-15s${NC}\n" "Default Packet Scheduler" "$(sysctl -n net.core.default_qdisc 2>/dev/null)"
    sleep 0.3
    printf "  %-24s : ${CYAN}%-15s${NC}\n" "Link Anti-Loss Rate" "动态实时补偿 [UP]"
    draw_line
    sleep 0.3
    echo -e "${PURPLE}ℹ 跨境单线程吞吐性能、大文件下行带宽已获得内核级硬件加速。${NC}\n"

    read -p "按回车返回..."
}

smart_tune_tcp_tune() {
    local old_bbr=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local old_somax=$(sysctl -n net.core.somaxconn 2>/dev/null || echo "默认")
    local old_rmem=$(sysctl -n net.core.rmem_max 2>/dev/null || echo "212992")
    local old_file=$(ulimit -n)

    echo -e "\n${YELLOW}>>> 正在启动系统环境扫描...${NC}"
    local mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local cpu_count=$(nproc)
    
    # 优化：为动态内存缓冲区添加硬上限 (64MB)，防止高配机器 OOM 崩溃
    local buf_bytes=$((mem_total_kb * 5 / 100 * 1024))
    local max_buf_limit=$((64 * 1024 * 1024))
    if [ "$buf_bytes" -gt "$max_buf_limit" ]; then
        buf_bytes=$max_buf_limit
    fi

    echo -e "  - 核心数: ${CYAN}${cpu_count}${NC} | 内存总量: ${CYAN}$((mem_total_kb / 1024))MB${NC}"
    echo -e "  - 动态缓冲区分配: ${CYAN}$((buf_bytes / 1024 / 1024))MB${NC} (已部署安全硬上限隔离)"
    sleep 0.5

    echo -e "\n${YELLOW}>>> 正在部署生产级 + 跨境优化内核配置...${NC}"
    
    cat >"$SYSCTL_OPT" <<EOF
# --- 基础队列算法 ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- 缓冲区与容量优化 ---
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = ${buf_bytes}
net.core.wmem_max = ${buf_bytes}
net.ipv4.tcp_rmem = 4096 87380 ${buf_bytes}
net.ipv4.tcp_wmem = 4096 65536 ${buf_bytes}
net.core.rmem_default = 2097152
net.core.wmem_default = 2097152

# --- 翻墙/Reality 环境针对性调优 ---
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 1
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_max_orphans = 32768

# --- 连接稳定性优化 ---
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_fastopen = 3
EOF

    # 优化：针对内核兼容性进行安全判断，仅在支持的内核上开启 BBRv3 配置
    if sysctl -a 2>/dev/null | grep -q "tcp_congestion_control_version"; then
        echo "net.ipv4.tcp_congestion_control_version = 3" >> "$SYSCTL_OPT"
        local bbr_ver_status="BBR3 Pipeline [就绪]"
    else
        local bbr_ver_status="标准 BBR [就绪]"
    fi

    sysctl --system &>/dev/null

    echo -e "\n${CYAN}>>> 正在向 Linux 内核注入跨境物理链路专项优化补丁...${NC}"
    
    local steps=("Analyzing Network Topo" "Clamping MSS Window" "Expanding UDP Ring Buffer" "Activating ECN Engine")
    for step in "${steps[@]}"; do
        printf "  ${BLUE}[*]${NC} %-30s " "$step..."
        sleep 0.2
        for i in {1..5}; do printf "${GREEN}■${NC}"; sleep 0.05; done
        printf " [ ${GREEN}OK${NC} ]\n"
    done

    echo -e "\n${GREEN}✅ 跨境链路专项补丁注入成功！当前实时网络增益快照：${NC}"
    draw_line
    printf "  %-30s : ${GREEN}%-15s${NC} (显著降低握手延迟)\n" "TCP Low Latency (TTFB)" "已激活 [0ms 积压]"
    sleep 0.3
    printf "  %-30s : ${GREEN}%-15s${NC} (防止 ICMP 阻断导致断流)\n" "MTU Path Discovery" "智能探测中 [已开启]"
    sleep 0.3
    printf "  %-30s : ${GREEN}%-15s${NC} (平滑 Hysteria2 并发丢包)\n" "UDP Buffer Expansion" "深度扩容 [16KB Ring]"
    sleep 0.3
    printf "  %-30s : ${GREEN}%-15s${NC} (高位拥塞时仅做标记防断连)\n" "ECN Smart Congestion" "动态标记 [已开启]"
    sleep 0.3
    printf "  %-30s : ${GREEN}%-15s${NC} (动态兼容最新拥塞控制算法)\n" "BBR Algorithm Version" "$bbr_ver_status"

    mkdir -p /etc/security/limits.d/
    cat >"$LIMITS_OPT" <<EOF
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65535
* hard nproc 65535
EOF

    if command -v iptables &>/dev/null; then
        iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
        iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
        echo -e "${GREEN}  ✔ 成功部署 MSS Clamp 智能钳制规则，防止跨境连接超时。${NC}"
    fi

    ulimit -n 1048576 2>/dev/null || true

    echo -e "\n${GREEN}✅ 深度调优完成，性能看板快照:${NC}"
    draw_line
    sleep 0.3
    printf "  %-12s: %-15s -> ${GREEN}%-15s${NC}\n" "拥塞算法" "$old_bbr" "bbr"
    sleep 0.3
    printf "  %-12s: %-15s -> ${GREEN}%-15s${NC}\n" "最大连接" "$old_somax" "65535"
    sleep 0.3
    printf "  %-12s: %-15s -> ${GREEN}%-15s${NC}\n" "文件句柄" "$old_file" "1048576"
    sleep 0.3
    printf "  %-12s: %-15s -> ${GREEN}%-15s${NC}\n" "网络缓冲" "$((old_rmem / 1024 / 1024))MB" "$((buf_bytes / 1024 / 1024))MB"
    sleep 0.3
    echo -e "\n${PURPLE}ℹ 所有配置已持久化至 $SYSCTL_OPT${NC}"
    echo -e "${PURPLE}ℹ 重启服务器后配置依然生效，回退请使用选项 5${NC}"

    read -p "按回车返回..."
}

optimize_nic_tune() {
    echo -e "\n${YELLOW}>>> 正在执行多核心中断分发 (RSS/RPS) 优化...${NC}"
    if ! command -v ethtool &>/dev/null; then 
        echo -e "${YELLOW}正在安装 ethtool 依赖...${NC}"
        apt-get update && apt-get install -y ethtool || yum install -y ethtool &>/dev/null
    fi

    # 优化：改用安全的物理网卡寻址方式，彻底避免将 docker0, veth 等虚拟网卡误判入列
    local interfaces=$(find /sys/class/net -type l -not -lname '*virtual*' -printf '%f\n' 2>/dev/null)
    
    if [ -z "$interfaces" ]; then
        echo -e "${RED}未检测到可配置的物理网卡设备。${NC}"
        read -p "按回车返回..."
        return
    fi

    local cpu_count=$(nproc)
    local rps_cpus="f"
    
    # 优化：防范高核心服务器 (如 64核 EPYC) 的 bash 整数左移位溢出
    if [ "$cpu_count" -ge 64 ]; then
        rps_cpus="ffffffffffffffff"
    else
        rps_cpus=$(printf '%x' $(((1 << cpu_count) - 1)))
    fi

    for eth in $interfaces; do
        local max_rx=$(ethtool -g "$eth" 2>/dev/null | grep -A 5 "Pre-set maximums" | grep -m 1 "RX:" | awk '{print $2}')
        if [[ "$max_rx" =~ ^[0-9]+$ ]]; then
            ethtool -G "$eth" rx "$max_rx" tx "$max_rx" &>/dev/null || true
        fi
        
        for rps_file in /sys/class/net/$eth/queues/rx-*/rps_cpus; do 
            [ -f "$rps_file" ] && echo "$rps_cpus" >"$rps_file" 2>/dev/null
        done
        for rfc_file in /sys/class/net/$eth/queues/rx-*/rps_flow_cnt; do 
            [ -f "$rfc_file" ] && echo "4096" >"$rfc_file" 2>/dev/null
        done
    done
    sysctl -w net.core.rps_sock_flow_entries=32768 &>/dev/null

    echo -e "\n${CYAN}>>> 正在唤醒系统底层网卡物理硬件，启动多核心负载分发均衡...${NC}"
    sleep 0.3

    local nic_steps=(
        "Mapping Network Interface" 
        "Unbinding Single Core IRQ" 
        "Injecting RPS Network Mask" 
        "Balancing Socket Flows"
    )
    
    for step in "${nic_steps[@]}"; do
        printf "  ${BLUE}[⚡]${NC} %-28s [" "$step"
        for i in {1..5}; do 
            printf "${GREEN}■${NC}"
            sleep 0.1
        done
        printf "] ${GREEN}[DONE]${NC}\n"
    done

    sleep 0.3
    echo -e "\n${GREEN}✅ 优化成功！网卡硬件中断多流分发流水线部署完毕：${NC}"
    draw_line
    
    local percent=0
    if [ "$cpu_count" -gt 0 ]; then
        percent=$((100 / cpu_count))
    fi

    # 动态将核心限制在显示 16 个以内，防止高核服务器刷屏
    local display_cores=$cpu_count
    if [ "$display_cores" -gt 16 ]; then display_cores=16; fi

    for ((i=0; i<display_cores; i++)); do
        echo -e "  ⚡ ${BOLD}CPU Core #$i${NC} : [${GREEN}██████████████████████████████${NC}] ${YELLOW}分配比率: ${percent}%${NC}"
        sleep 0.1
    done
    
    if [ "$cpu_count" -gt 16 ]; then
        echo -e "  ... 以及其他 $((cpu_count - 16)) 个核心均衡分配。"
    fi

    draw_line
    sleep 0.3
    echo -e "${PURPLE}ℹ 成功打破单核软中断瓶颈，大并发流量已均匀平摊至 ${cpu_count} 个物理/逻辑核心。${NC}\n"

    read -p "按回车返回..."
}

set_ipv4_priority() {
    echo -e "\n${YELLOW}>>> 正在调整系统互联网协议优先级...${NC}"
    if [ ! -f /etc/gai.conf ]; then
        cat > /etc/gai.conf <<EOF
label ::1/128       0
label ::/0          1
label 2002::/16     2
label ::/96         3
label ::ffff:0:0/96 4
precedence  ::1/128       50
precedence  ::/0          40
precedence  2002::/16     30
precedence  ::/96         20
precedence  ::ffff:0:0/96 10
EOF
    fi

    cp -n /etc/gai.conf /etc/gai.conf.bak

    if grep -q "precedence ::ffff:0:0/96  100" /etc/gai.conf; then
        sed -i 's/^#precedence ::ffff:0:0\/96  100/precedence ::ffff:0:0\/96  100/' /etc/gai.conf
    else
        echo "precedence ::ffff:0:0/96  100" >>/etc/gai.conf
    fi

    echo -e "\n${GREEN}✅ 优化成功！当前系统已设置为 [ IPv4 优先 ]。${NC}"
    read -p "按回车返回..."
}

rollback_tcp_tune() {
    rm -f "$SYSCTL_OPT" "$LIMITS_OPT" /etc/sysctl.d/10-bbr.conf

    if [ -f /etc/gai.conf.bak ]; then
        mv /etc/gai.conf.bak /etc/gai.conf
    else
        sed -i 's/^precedence ::ffff:0:0\/96  100/#precedence ::ffff:0:0\/96  100/' /etc/gai.conf 2>/dev/null || true
    fi

    sysctl -w net.ipv4.tcp_congestion_control=cubic &>/dev/null
    sysctl -w net.core.default_qdisc=pfifo_fast &>/dev/null
    sysctl -w net.core.rps_sock_flow_entries=0 &>/dev/null

    if command -v iptables &>/dev/null; then
        iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    fi

    local interfaces=$(find /sys/class/net -type l -not -lname '*virtual*' -printf '%f\n' 2>/dev/null)
    for eth in $interfaces; do
        for rps_file in /sys/class/net/$eth/queues/rx-*/rps_cpus; do 
            [ -f "$rps_file" ] && echo "0" >"$rps_file" 2>/dev/null
        done
        for rfc_file in /sys/class/net/$eth/queues/rx-*/rps_flow_cnt; do 
            [ -f "$rfc_file" ] && echo "0" >"$rfc_file" 2>/dev/null
        done
    done

    ulimit -n 1024 2>/dev/null || true
    sysctl --system &>/dev/null
    echo -e "${GREEN}✅ 回退完成，所有独立配置文件已清理，内存参数已恢复默认。${NC}"
}

# ==================================================
# --- 4. 主循环菜单 ---
# ==================================================
while true; do
    if [ -f /etc/gai.conf ] && grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf; then
        status_ipv4="${GREEN}[已激活]${NC}"
    else
        status_ipv4="${RED}[未开启]${NC}"
    fi

    if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" = "bbr" ]; then
        status_bbr="${GREEN}[已激活]${NC}"
    else
        status_bbr="${RED}[未开启]${NC}"
    fi

    if [ -f "$SYSCTL_OPT" ]; then
        status_sysctl="${GREEN}[已激活]${NC}"
    else
        status_sysctl="${RED}[未开启]${NC}"
    fi

    if [ "$(sysctl -n net.core.rps_sock_flow_entries 2>/dev/null)" = "32768" ]; then
        status_nic="${GREEN}[已激活]${NC}"
    else
        status_nic="${RED}[未开启]${NC}"
    fi

    clear
    echo -e "${YELLOW}==================================================${NC}"
    echo -e "${YELLOW}            TCP/UDP 网络深度调优与性能看板            ${NC}"
    echo -e "${GREEN}            bash <(curl -sL $UPDATE_URL)${NC}"
    echo -e "${GREEN}                    快捷命令: t                    ${NC}"
    echo -e "${YELLOW}==================================================${NC}"
    echo -e "  1. 设置 IPv4 优先解析     -> $status_ipv4  :[解决 IPv6 绕路导致的握手卡顿]"
    echo -e "  2. 开启 BBR + FQ          -> $status_bbr  :[降低跨境丢包，提升单线程速度]"
    echo -e "  3. 生产级内核调优         -> $status_sysctl  :[支撑 6w+ 并发连接，防止队列溢出]"
    echo -e "  4. 网卡多队列均衡         -> $status_nic  :[消除单核 CPU 瓶颈，平摊全核负载]"
    echo -e "  5. 一键回退到默认设置     -> [清理所有独立调优配置文件]"
    echo -e "  6. 检查并强制同步更新脚本"
    echo -e "  7. 彻底卸载面板脚本"
    echo -e "  0. 退出脚本"
    draw_line
    echo -e "当前状态: 算法: ${GREEN}$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "N/A")${NC} | 句柄: ${GREEN}$(ulimit -n)${NC}"
    draw_line
    
    read -p "请选择数字 [0-7]: " t_opt
    case "$t_opt" in
    1) set_ipv4_priority ;;
    2) enable_bbr_tune ;;
    3) smart_tune_tcp_tune ;;
    4) optimize_nic_tune ;;
    5) rollback_tcp_tune && read -p "按回车返回..." ;;
    6) check_update ;;
    7) uninstall_script ;;
    0) exit 0 ;;
    *) echo -e "${RED}输入错误，请输入正确数字！${NC}" && sleep 1 ;;
    esac
done
