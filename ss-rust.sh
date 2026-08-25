#!/bin/bash
# Shadowsocks-rust 安装与管理
# Author: https://1024.day

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

SS_DIR="/etc/shadowsocks"
SS_CONFIG="${SS_DIR}/config.json"
SS_CLIENT="${SS_DIR}/client.json"
SS_STATE="${SS_DIR}/ss.conf"
SS_SERVICE="shadowsocks.service"
METHOD="aes-128-gcm"
REPO_RAW="https://raw.githubusercontent.com/945967063/v2ray-wss/main"

SS_PASSWORD=""
SS_PORT=""
IP=""

install_console_shortcut() {
    local tmp="/tmp/sb.cli.$$"
    mkdir -p /usr/local/lib/sb-menu
    if wget --no-cache -q -O "$tmp" "${REPO_RAW}/sb" 2>/dev/null || curl -fsSL -o "$tmp" "${REPO_RAW}/sb" 2>/dev/null; then
        install -m 755 "$tmp" /usr/local/bin/sb
        ln -sfn /usr/local/bin/sb /usr/local/bin/ssrust
        ln -sfn /usr/local/bin/sb /usr/local/bin/reality
        ln -sfn /usr/local/bin/sb /usr/local/bin/hy2
        rm -f /usr/local/bin/proxy
        rm -rf /usr/local/lib/proxy-menu
        cp -f "$0" /usr/local/lib/sb-menu/ss-rust.sh 2>/dev/null || \
            wget --no-cache -q -O /usr/local/lib/sb-menu/ss-rust.sh "${REPO_RAW}/ss-rust.sh" 2>/dev/null || true
        chmod +x /usr/local/lib/sb-menu/ss-rust.sh 2>/dev/null || true
        rm -f "$tmp"
        echo -e "${GREEN}快捷命令已就绪: 输入 sb 或 ssrust 打开管理菜单${PLAIN}"
    else
        rm -f "$tmp"
    fi
}
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 必须以 root 运行${PLAIN}" 1>&2
        exit 1
    fi
}

is_installed() {
    [[ -f "$SS_CONFIG" ]] || [[ -x /usr/local/bin/ssserver ]]
}

save_state() {
    mkdir -p "$SS_DIR"
    cat > "$SS_STATE" <<EOF
SS_PORT='${SS_PORT}'
SS_PASSWORD='${SS_PASSWORD}'
IP='${IP}'
METHOD='${METHOD}'
EOF
    chmod 600 "$SS_STATE"
}

load_state() {
    if [[ -f "$SS_STATE" ]]; then
        # shellcheck source=/dev/null
        source "$SS_STATE"
        [[ -n "$SS_PORT" && -n "$SS_PASSWORD" ]] && return 0
    fi
    if [[ -f "$SS_CONFIG" ]] && command -v jq &>/dev/null; then
        SS_PORT=$(jq -r '.server_port' "$SS_CONFIG" 2>/dev/null)
        SS_PASSWORD=$(jq -r '.password' "$SS_CONFIG" 2>/dev/null)
        METHOD=$(jq -r '.method // "aes-128-gcm"' "$SS_CONFIG" 2>/dev/null)
        [[ -n "$SS_PORT" && -n "$SS_PASSWORD" && "$SS_PORT" != "null" ]] && return 0
    fi
    return 1
}

generate_credentials() {
    if [[ -f /proc/sys/kernel/random/uuid ]]; then
        SS_PASSWORD=$(cat /proc/sys/kernel/random/uuid)
    else
        SS_PASSWORD=$(uuidgen 2>/dev/null || openssl rand -hex 16)
    fi

    echo -e "${YELLOW}请输入端口 [1-65535]，回车随机（15秒）${PLAIN}"
    read -r -t 15 -p "> " SS_PORT || true
    if [[ -z "$SS_PORT" ]]; then
        SS_PORT=$(shuf -i 10000-65000 -n 1)
    elif ! [[ "$SS_PORT" =~ ^[0-9]+$ ]] || [[ "$SS_PORT" -lt 1 || "$SS_PORT" -gt 65535 ]]; then
        echo -e "${YELLOW}端口无效，使用随机端口${PLAIN}"
        SS_PORT=$(shuf -i 10000-65000 -n 1)
    fi
}

get_server_ip() {
    IP=$(curl -s -4 --max-time 10 http://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep "ip=" | awk -F= '{print $2}' | tr -d '\r\n')
    [[ -z "$IP" ]] && IP=$(curl -s -4 --max-time 10 https://api.ipify.org 2>/dev/null)
    [[ -z "$IP" ]] && IP=$(curl -s -6 --max-time 10 http://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep "ip=" | awk -F= '{print $2}' | tr -d '\r\n')
    [[ -z "$IP" ]] && IP="<未知IP>"
}

install_dependencies() {
    if command -v apt-get &>/dev/null; then
        apt-get update -q
        apt-get install -y -q gzip wget curl unzip xz-utils jq openssl
    elif command -v dnf &>/dev/null; then
        dnf -q install -y gzip wget curl unzip xz jq openssl
    elif command -v yum &>/dev/null; then
        yum -q install -y epel-release
        yum -q install -y gzip wget curl unzip xz jq openssl
    else
        echo -e "${RED}请手动安装: gzip wget curl unzip xz jq${PLAIN}"
        exit 1
    fi
}

detect_architecture() {
    case "$(uname -m)" in
        i386|i686) ARCH="i686" ;;
        x86_64|amd64) ARCH="x86_64" ;;
        armv7l|armv7) ARCH="arm" ;;
        armv8|aarch64) ARCH="aarch64" ;;
        *) echo -e "${RED}不支持的架构${PLAIN}"; exit 1 ;;
    esac
}

install_shadowsocks() {
    echo -e "${CYAN}下载 Shadowsocks Rust...${PLAIN}"
    LATEST_VERSION=$(wget -qO- https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases |
        jq -r '[.[] | select(.prerelease == false) | select(.draft == false) | .tag_name] | .[0]')
    [[ -z "$LATEST_VERSION" ]] && { echo -e "${RED}无法获取版本${PLAIN}"; exit 1; }

    local pkg="shadowsocks-${LATEST_VERSION}.${ARCH}-unknown-linux-gnu.tar.xz"
    local url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${LATEST_VERSION}/${pkg}"
    wget --no-check-certificate -q --show-progress -N "$url" || curl -L --progress-bar -o "$pkg" "$url"
    [[ -f "$pkg" ]] || { echo -e "${RED}下载失败${PLAIN}"; exit 1; }

    tar -xf "$pkg"
    [[ -f ssserver ]] || { echo -e "${RED}解压失败${PLAIN}"; exit 1; }
    chmod +x ssserver
    mv -f ssserver /usr/local/bin/
    rm -f "$pkg" sslocal ssmanager ssservice ssurl 2>/dev/null
    echo -e "${GREEN}安装完成${PLAIN}"
}

write_ss_config() {
    mkdir -p "$SS_DIR"
    cat > "$SS_CONFIG" <<EOF
{
    "server":"::",
    "server_port":$SS_PORT,
    "password":"$SS_PASSWORD",
    "timeout":600,
    "mode":"tcp_and_udp",
    "method":"$METHOD"
}
EOF
    chmod 600 "$SS_CONFIG"

    cat > /etc/systemd/system/${SS_SERVICE} <<EOF
[Unit]
Description=Shadowsocks Rust Server
After=network.target

[Service]
ExecStart=/usr/local/bin/ssserver -c ${SS_CONFIG}
Restart=on-failure
RestartSec=3s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${SS_SERVICE}
    systemctl restart ${SS_SERVICE}
}

save_client() {
    local host="$IP"
    [[ "$IP" == *:* ]] && host="[$IP]"
    local link
    link=$(echo -n "${METHOD}:${SS_PASSWORD}@${host}:${SS_PORT}" | base64 -w 0 2>/dev/null || echo -n "${METHOD}:${SS_PASSWORD}@${host}:${SS_PORT}" | base64)
    SS_LINK="ss://${link}"
    cat > "$SS_CLIENT" <<EOF
{
  "server": "$IP",
  "port": $SS_PORT,
  "password": "$SS_PASSWORD",
  "method": "$METHOD",
  "shareLink": "$SS_LINK"
}
EOF
    chmod 600 "$SS_CLIENT"
}

show_config() {
    load_state || { echo -e "${RED}未找到配置，请先安装${PLAIN}"; return 1; }
    [[ -z "$IP" || "$IP" == "<未知IP>" ]] && get_server_ip
    save_client
    local status
    status=$(systemctl is-active ${SS_SERVICE} 2>/dev/null || echo unknown)
    echo
    echo -e "${GREEN}=========== Shadowsocks 配置 ===========${PLAIN}"
    echo -e "地址: ${YELLOW}${IP}${PLAIN}"
    echo -e "端口: ${YELLOW}${SS_PORT}${PLAIN}"
    echo -e "密码: ${YELLOW}${SS_PASSWORD}${PLAIN}"
    echo -e "加密: ${YELLOW}${METHOD}${PLAIN}"
    echo -e "状态: ${YELLOW}${status}${PLAIN}"
    echo -e "${GREEN}========================================${PLAIN}"
    echo -e "链接: ${CYAN}${SS_LINK}${PLAIN}"
    echo -e "配置文件: ${SS_CLIENT}"
    echo
}

do_install() {
    generate_credentials
    install_dependencies
    detect_architecture
    install_shadowsocks
    get_server_ip
    write_ss_config
    save_state
    save_client
    install_console_shortcut
    clear
    echo -e "${GREEN}安装完成${PLAIN}"
    show_config
    echo -e "${CYAN}以后可直接输入: sb  或  ssrust${PLAIN}"
}

do_restart() {
    systemctl restart ${SS_SERVICE} && echo -e "${GREEN}已重启${PLAIN}" || echo -e "${RED}重启失败${PLAIN}"
    systemctl status ${SS_SERVICE} --no-pager || true
}

change_password() {
    load_state || { echo -e "${RED}未找到配置${PLAIN}"; return 1; }
    if [[ -f /proc/sys/kernel/random/uuid ]]; then
        SS_PASSWORD=$(cat /proc/sys/kernel/random/uuid)
    else
        SS_PASSWORD=$(openssl rand -hex 16)
    fi
    [[ -z "$IP" ]] && get_server_ip
    write_ss_config
    save_state
    save_client
    echo -e "${GREEN}密码已更换${PLAIN}"
    show_config
}

change_port() {
    load_state || { echo -e "${RED}未找到配置${PLAIN}"; return 1; }
    read -r -p "新端口 (1-65535): " new_port
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 || "$new_port" -gt 65535 ]]; then
        echo -e "${RED}端口无效${PLAIN}"
        return 1
    fi
    SS_PORT="$new_port"
    [[ -z "$IP" ]] && get_server_ip
    write_ss_config
    save_state
    save_client
    echo -e "${GREEN}端口已更换${PLAIN}"
    show_config
}

uninstall_ss() {
    read -r -p "确认完全卸载 Shadowsocks-rust? (y/N): " c
    [[ "${c,,}" == "y" ]] || { echo "已取消"; return 0; }
    systemctl stop ${SS_SERVICE} 2>/dev/null || true
    systemctl disable ${SS_SERVICE} 2>/dev/null || true
    rm -f /etc/systemd/system/${SS_SERVICE}
    rm -rf "$SS_DIR"
    rm -f /usr/local/bin/ssserver /usr/local/bin/sslocal /usr/local/bin/ssmanager /usr/local/bin/ssservice /usr/local/bin/ssurl
    systemctl daemon-reload 2>/dev/null || true
    echo -e "${GREEN}已完全卸载 Shadowsocks-rust${PLAIN}"
}

pause() { echo; read -r -p "按回车返回菜单..." _; }

start_menu() {
    while true; do
        clear
        echo " ================================================== "
        echo "  Shadowsocks-rust 管理"
        echo " ================================================== "
        if is_installed; then
            echo -e "  状态: ${GREEN}已安装${PLAIN}"
        else
            echo -e "  状态: ${YELLOW}未安装${PLAIN}"
        fi
        echo
        echo "  1. 安装 / 重装"
        echo "  2. 查看配置与链接"
        echo "  3. 重启服务"
        echo "  4. 更换密码"
        echo "  5. 更换端口"
        echo "  6. 完全卸载"
        echo "  7. 安装控制台快捷命令 (sb/ssrust)"
        echo "  0. 退出"
        echo
        read -r -p "请输入数字: " num
        case "$num" in
            1) do_install; pause ;;
            2) show_config; pause ;;
            3) do_restart; pause ;;
            4) change_password; pause ;;
            5) change_port; pause ;;
            6) uninstall_ss; pause ;;
            7) install_console_shortcut; pause ;;
            0) exit 0 ;;
            *) echo "输入错误"; sleep 1 ;;
        esac
    done
}

check_root
case "${1:-}" in
    uninstall|remove) uninstall_ss; exit 0 ;;
    show|view) show_config; exit 0 ;;
    *) start_menu ;;
esac
