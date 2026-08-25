#!/bin/bash
# Hysteria2 安装与管理
# Author: https://1024.day

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

HY_DIR="/etc/hysteria"
HY_CONFIG="${HY_DIR}/config.yaml"
HY_CLIENT="${HY_DIR}/hyclient.json"
HY_STATE="${HY_DIR}/hy2.conf"
HY_SERVICE="hysteria-server.service"
SNI="bing.com"
REPO_RAW="https://raw.githubusercontent.com/945967063/v2ray-wss/main"

SERVER_PORT=""
HYSTERIA_PASSWORD=""
SERVER_IP=""

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
        cp -f "$0" /usr/local/lib/sb-menu/hy2.sh 2>/dev/null || true
        chmod +x /usr/local/lib/sb-menu/hy2.sh 2>/dev/null || true
        rm -f "$tmp"
        echo -e "${GREEN}快捷命令已就绪: 输入 sb 或 hy2${RESET}"
    else
        rm -f "$tmp"
    fi
}
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}必须以 root 运行${RESET}" 1>&2
    exit 1
fi

is_installed() {
    [[ -f "$HY_CONFIG" ]] || command -v hysteria &>/dev/null
}

save_state() {
    mkdir -p "$HY_DIR"
    cat > "$HY_STATE" <<EOF
SERVER_PORT='${SERVER_PORT}'
HYSTERIA_PASSWORD='${HYSTERIA_PASSWORD}'
SERVER_IP='${SERVER_IP}'
SNI='${SNI}'
EOF
    chmod 600 "$HY_STATE"
}

load_state() {
    if [[ -f "$HY_STATE" ]]; then
        # shellcheck source=/dev/null
        source "$HY_STATE"
        [[ -n "$SERVER_PORT" && -n "$HYSTERIA_PASSWORD" ]] && return 0
    fi
    if [[ -f "$HY_CONFIG" ]]; then
        SERVER_PORT=$(grep -E '^listen:' "$HY_CONFIG" 2>/dev/null | sed 's/.*://;s/[[:space:]]//g')
        HYSTERIA_PASSWORD=$(grep -E '^\s*password:' "$HY_CONFIG" 2>/dev/null | awk '{print $2}' | tr -d '"')
        [[ -n "$SERVER_PORT" && -n "$HYSTERIA_PASSWORD" ]] && return 0
    fi
    return 1
}

install_packages() {
    if command -v apt-get &>/dev/null; then
        apt-get update -y
        apt-get install -y curl wget openssl gawk ca-certificates
    elif command -v dnf &>/dev/null; then
        dnf install -y curl wget openssl gawk ca-certificates
    elif command -v yum &>/dev/null; then
        yum install -y epel-release
        yum install -y curl wget openssl gawk ca-certificates
    elif command -v zypper &>/dev/null; then
        zypper install -y curl wget openssl gawk ca-certificates
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm curl wget openssl gawk ca-certificates
    else
        echo -e "${RED}请手动安装依赖${RESET}"
        exit 1
    fi
}

generate_password() {
    if [[ -f /proc/sys/kernel/random/uuid ]]; then
        HYSTERIA_PASSWORD=$(cat /proc/sys/kernel/random/uuid)
    else
        HYSTERIA_PASSWORD=$(openssl rand -hex 16)
    fi
}

get_port() {
    read -r -t 15 -p "回车随机端口，或输入自定义端口(1-65535): " SERVER_PORT || true
    if [[ -z "$SERVER_PORT" ]]; then
        SERVER_PORT=$(shuf -i 2000-65000 -n 1 2>/dev/null || echo $((RANDOM % 63000 + 2000)))
    fi
    if ! [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] || [[ "$SERVER_PORT" -lt 1 || "$SERVER_PORT" -gt 65535 ]]; then
        echo -e "${RED}端口无效${RESET}"
        exit 1
    fi
}

get_server_ip() {
    local ip
    ip=$(curl -s -4 --connect-timeout 10 http://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep "ip=" | awk -F= '{print $2}')
    [[ -z "$ip" ]] && ip=$(curl -s -4 --connect-timeout 10 https://api.ipify.org 2>/dev/null)
    [[ -z "$ip" ]] && ip=$(curl -s -6 --connect-timeout 10 http://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep "ip=" | awk -F= '{print $2}')
    [[ -z "$ip" ]] && { echo -e "${RED}无法获取 IP${RESET}"; return 1; }
    echo "$ip"
}

write_hy_config() {
    mkdir -p "$HY_DIR"
    if [[ ! -f /etc/hysteria/server.crt || ! -f /etc/hysteria/server.key ]]; then
        openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
            -keyout /etc/hysteria/server.key \
            -out /etc/hysteria/server.crt \
            -subj "/CN=${SNI}" -days 36500
        if id hysteria &>/dev/null; then
            chown hysteria:hysteria /etc/hysteria/server.key /etc/hysteria/server.crt
        fi
        chmod 600 /etc/hysteria/server.key
        chmod 644 /etc/hysteria/server.crt
    fi

    cat > "$HY_CONFIG" <<EOF
listen: :$SERVER_PORT

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

auth:
  type: password
  password: $HYSTERIA_PASSWORD

masquerade:
  type: proxy
  proxy:
    url: https://${SNI}
    rewriteHost: true

quic:
  initStreamReceiveWindow: 26843545
  maxStreamReceiveWindow: 26843545
  initConnReceiveWindow: 67108864
  maxConnReceiveWindow: 67108864
EOF
    chmod 600 "$HY_CONFIG"
}

save_client() {
    local host="$SERVER_IP"
    [[ "$SERVER_IP" == *:* ]] && host="[${SERVER_IP}]"
    SHARE_LINK="hysteria2://${HYSTERIA_PASSWORD}@${host}:${SERVER_PORT}/?insecure=1&sni=${SNI}#1024-Hysteria2"
    cat > "$HY_CLIENT" <<EOF
{
  "server": "${SERVER_IP}:${SERVER_PORT}",
  "auth": "${HYSTERIA_PASSWORD}",
  "tls": {
    "sni": "${SNI}",
    "insecure": true
  },
  "shareLink": "${SHARE_LINK}"
}
EOF
    chmod 600 "$HY_CLIENT"
}

show_config() {
    load_state || { echo -e "${RED}未找到配置，请先安装${RESET}"; return 1; }
    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP=$(get_server_ip) || return 1
    fi
    save_client
    local status="unknown"
    systemctl is-active --quiet ${HY_SERVICE} 2>/dev/null && status="active" || status="inactive"
    echo
    echo -e "${GREEN}=========== Hysteria2 配置 ===========${RESET}"
    echo -e "地址: ${YELLOW}${SERVER_IP}${RESET}"
    echo -e "端口: ${YELLOW}${SERVER_PORT}${RESET}"
    echo -e "密码: ${YELLOW}${HYSTERIA_PASSWORD}${RESET}"
    echo -e "SNI: ${YELLOW}${SNI}${RESET}"
    echo -e "状态: ${YELLOW}${status}${RESET}"
    echo -e "${GREEN}======================================${RESET}"
    echo -e "链接: ${CYAN}${SHARE_LINK}${RESET}"
    echo -e "配置: ${HY_CLIENT}"
    echo -e "请放行 UDP ${SERVER_PORT}"
    echo
}

do_install() {
    install_packages
    generate_password
    get_port
    echo "安装 Hysteria2..."
    if ! bash <(curl -fsSL https://get.hy2.sh/); then
        echo -e "${RED}Hysteria2 安装失败${RESET}"
        exit 1
    fi
    SERVER_IP=$(get_server_ip) || exit 1
    write_hy_config
    systemctl enable ${HY_SERVICE}
    systemctl restart ${HY_SERVICE}
    sleep 2
    save_state
    save_client
    install_console_shortcut
    clear
    echo -e "${GREEN}安装完成${RESET}"
    show_config
    echo -e "${CYAN}以后可直接输入: sb  或  hy2${RESET}"
    systemctl status ${HY_SERVICE} --no-pager || true
}

do_restart() {
    systemctl restart ${HY_SERVICE} && echo -e "${GREEN}已重启${RESET}" || echo -e "${RED}重启失败${RESET}"
    systemctl status ${HY_SERVICE} --no-pager || true
}

change_password() {
    load_state || { echo -e "${RED}未找到配置${RESET}"; return 1; }
    generate_password
    [[ -z "$SERVER_IP" ]] && SERVER_IP=$(get_server_ip)
    write_hy_config
    systemctl restart ${HY_SERVICE}
    save_state
    save_client
    echo -e "${GREEN}密码已更换${RESET}"
    show_config
}

change_port() {
    load_state || { echo -e "${RED}未找到配置${RESET}"; return 1; }
    read -r -p "新端口 (1-65535): " new_port
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 || "$new_port" -gt 65535 ]]; then
        echo -e "${RED}端口无效${RESET}"
        return 1
    fi
    SERVER_PORT="$new_port"
    [[ -z "$SERVER_IP" ]] && SERVER_IP=$(get_server_ip)
    write_hy_config
    systemctl restart ${HY_SERVICE}
    save_state
    save_client
    echo -e "${GREEN}端口已更换${RESET}"
    show_config
}

uninstall_hy2() {
    read -r -p "确认完全卸载 Hysteria2? (y/N): " c
    [[ "${c,,}" == "y" ]] || { echo "已取消"; return 0; }
    systemctl stop ${HY_SERVICE} 2>/dev/null || true
    systemctl disable ${HY_SERVICE} 2>/dev/null || true
    if [[ -x /usr/local/bin/hysteria ]] || command -v hysteria &>/dev/null; then
        bash <(curl -fsSL https://get.hy2.sh/) --remove 2>/dev/null || true
    fi
    rm -rf "$HY_DIR"
    rm -f /etc/systemd/system/${HY_SERVICE} /etc/systemd/system/multi-user.target.wants/${HY_SERVICE}
    rm -f /usr/local/bin/hysteria 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    echo -e "${GREEN}已完全卸载 Hysteria2${RESET}"
}

pause() { echo; read -r -p "按回车返回菜单..." _; }

start_menu() {
    while true; do
        clear
        echo " ================================================== "
        echo "  Hysteria2 管理"
        echo " ================================================== "
        if is_installed; then
            echo -e "  状态: ${GREEN}已安装${RESET}"
        else
            echo -e "  状态: ${YELLOW}未安装${RESET}"
        fi
        echo
        echo "  1. 安装 / 重装"
        echo "  2. 查看配置与链接"
        echo "  3. 重启服务"
        echo "  4. 更换密码"
        echo "  5. 更换端口"
        echo "  6. 完全卸载"
        echo "  7. 安装控制台快捷命令 (sb/hy2)"
        echo "  0. 退出"
        echo
        read -r -p "请输入数字: " num
        case "$num" in
            1) do_install; pause ;;
            2) show_config; pause ;;
            3) do_restart; pause ;;
            4) change_password; pause ;;
            5) change_port; pause ;;
            6) uninstall_hy2; pause ;;
            7) install_console_shortcut; pause ;;
            0) exit 0 ;;
            *) echo "输入错误"; sleep 1 ;;
        esac
    done
}

case "${1:-}" in
    uninstall|remove) uninstall_hy2; exit 0 ;;
    show|view) show_config; exit 0 ;;
    *) start_menu ;;
esac
