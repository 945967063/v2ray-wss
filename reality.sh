#!/bin/bash
# forum: https://1024.day
# Reality Plus — VLESS + Vision + Reality 安装与管理

if [[ $EUID -ne 0 ]]; then
    clear
    echo "错误: 此脚本必须以root身份运行!" 1>&2
    exit 1
fi

SCRIPT_VERSION="1.2.1"
CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="${CONFIG_DIR}/config.json"
CLIENT_FILE="${CONFIG_DIR}/reclient.json"
STATE_FILE="${CONFIG_DIR}/reality.conf"
LOG_FILE="/var/log/reality_install.log"
BACKUP_DIR="/tmp/reality_backup_$(date +%s)"

SERVER_IP=""
SERVER_HOST=""
PORT_NUMBER=""
UUID=""
SHORT_ID=""
SERVER_SNI=""
RE_PRIVATE_KEY=""
RE_PUBLIC_KEY=""
SHARE_LINK=""
ENABLE_SNI_FILTER=0
SPIDER_X="/"

SNI_PRESETS=(
    "www.microsoft.com"
    "www.cloudflare.com"
    "www.apple.com"
    "www.amazon.com"
    "gateway.icloud.com"
    "www.samsung.com"
    "dl.google.com"
    "www.yahoo.com"
)

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
touch "$LOG_FILE" 2>/dev/null || LOG_FILE=""

print_red() {
    echo -e "\033[31m$1\033[0m"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}
print_green() {
    echo -e "\033[32m$1\033[0m"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}
print_yellow() {
    echo -e "\033[33m$1\033[0m"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}
display_red() { echo -e "\033[31m$1\033[0m"; }
display_green() { echo -e "\033[32m$1\033[0m"; }
display_yellow() { echo -e "\033[33m$1\033[0m"; }
log_only() { [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

cleanup_on_error() {
    log_info "执行错误清理..."
    rm -f /tmp/xray-install.sh /tmp/xray_config_$$.json 2>/dev/null || true
    log_info "错误清理完成（未停止现有 Xray 服务）"
}

exit_with_error() {
    print_red "错误: $1"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误: $1" >> "$LOG_FILE"
    cleanup_on_error
    exit 1
}

trap 'exit_with_error "脚本被中断"' INT TERM

command_exists() { command -v "$1" >/dev/null 2>&1; }

validate_port() {
    local p="$1"
    [[ "$p" =~ ^[0-9]+$ ]] && [[ "$p" -ge 1 && "$p" -le 65535 ]]
}

validate_domain() {
    local d="$1"
    [[ "$d" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]
}

is_port_in_use() {
    local port="$1"
    if command_exists ss; then
        ss -tuln 2>/dev/null | grep -qE ":${port}[[:space:]]"
    elif command_exists netstat; then
        netstat -tuln 2>/dev/null | grep -qE ":${port}[[:space:]]"
    else
        return 1
    fi
}

format_host_for_url() {
    local ip="$1"
    if [[ "$ip" == *:* ]]; then
        echo "[${ip}]"
    else
        echo "$ip"
    fi
}

# 16 位 hex shortId（8 字节）
generate_short_id() {
    local sid=""
    if command_exists openssl; then
        sid=$(openssl rand -hex 8 2>/dev/null || true)
    fi
    if [[ -z "$sid" || ${#sid} -ne 16 ]]; then
        sid=$(head -c 8 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' | head -c 16)
    fi
    if [[ ! "$sid" =~ ^[0-9a-fA-F]{16}$ ]]; then
        sid=$(printf '%04x%04x%04x%04x' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM")
    fi
    echo "${sid,,}"
}

generate_uuid() {
    local uuid=""
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        uuid=$(cat /proc/sys/kernel/random/uuid)
    elif command_exists uuidgen; then
        uuid=$(uuidgen)
    else
        uuid=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
               python -c "import uuid; print(uuid.uuid4())" 2>/dev/null || true)
    fi
    [[ "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || return 1
    echo "${uuid,,}"
}

urlencode_path() {
    local s="$1"
    if command_exists python3; then
        SPIDER_X_RAW="$s" python3 -c 'import os,urllib.parse; print(urllib.parse.quote(os.environ["SPIDER_X_RAW"], safe=""))' 2>/dev/null && return
    fi
    echo "${s//\//%2F}"
}

show_firewall_hint() {
    local port="$1"
    echo
    display_yellow "请确认已放行 TCP 端口 ${port}（云安全组 / 本机防火墙）："
    if command_exists ufw && ufw status 2>/dev/null | grep -qi "active"; then
        display_yellow "  ufw allow ${port}/tcp && ufw reload"
    elif command_exists firewall-cmd && systemctl is-active --quiet firewalld 2>/dev/null; then
        display_yellow "  firewall-cmd --permanent --add-port=${port}/tcp && firewall-cmd --reload"
    else
        display_yellow "  若使用 ufw: ufw allow ${port}/tcp && ufw reload"
        display_yellow "  若使用 firewalld: firewall-cmd --permanent --add-port=${port}/tcp && firewall-cmd --reload"
    fi
}

is_reality_installed() {
    [[ -f "$STATE_FILE" ]] || [[ -f "$CLIENT_FILE" ]] || \
    { [[ -f "$CONFIG_FILE" ]] && grep -q '"security"[[:space:]]*:[[:space:]]*"reality"' "$CONFIG_FILE" 2>/dev/null; }
}

detect_distribution() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS_ID=${ID:-unknown}
        OS_VERSION=${VERSION_ID:-unknown}
    elif [[ -f /etc/redhat-release ]]; then
        OS_ID="centos"
        OS_VERSION=$(grep -oE '[0-9]+(\.[0-9]+)?' /etc/redhat-release | head -1)
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
    fi
    [[ "$OS_ID" == "unknown" ]] && print_yellow "无法确定系统类型，将尝试继续..."
    log_info "检测到系统: $OS_ID $OS_VERSION"
}

detect_package_manager() {
    if command_exists apt-get; then
        PKG_MANAGER="apt"
        PKG_UPDATE="apt-get update -y"
        PKG_INSTALL="apt-get install -y"
        local lock_wait=0
        while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
            [[ $lock_wait -ge 120 ]] && exit_with_error "等待 dpkg/apt 锁超时"
            log_info "等待dpkg锁释放... (${lock_wait}s/120s)"
            sleep 3
            lock_wait=$((lock_wait + 3))
        done
    elif command_exists dnf; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf makecache"
        PKG_INSTALL="dnf install -y"
        dnf install -y epel-release 2>/dev/null || true
    elif command_exists yum; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum makecache"
        PKG_INSTALL="yum install -y"
        yum install -y epel-release 2>/dev/null || true
    elif command_exists zypper; then
        PKG_MANAGER="zypper"
        PKG_UPDATE="zypper ref"
        PKG_INSTALL="zypper in -y"
    elif command_exists pacman; then
        PKG_MANAGER="pacman"
        PKG_UPDATE="pacman -Sy"
        PKG_INSTALL="pacman -S --noconfirm"
    else
        exit_with_error "不支持的包管理器"
    fi
    log_info "检测到包管理器: $PKG_MANAGER"
}

disable_broken_apt_sources() {
    local update_output="$1"
    local disabled_count=0
    local repo_urls=()
    local line

    while IFS= read -r line; do
        if [[ "$line" =~ The\ repository\ \'([^\']+)\' ]]; then
            repo_urls+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$update_output"

    while IFS= read -r line; do
        if [[ "$line" =~ ^Err:[0-9]+\ +([^[:space:]]+) ]]; then
            repo_urls+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$update_output"

    [[ ${#repo_urls[@]} -eq 0 ]] && return 1

    local url host keyword src_file
    for url in "${repo_urls[@]}"; do
        host=$(echo "$url" | sed -E 's#https?://([^/]+)/.*#\1#')
        keyword=$(echo "$url" | sed -E 's#https?://[^/]+/##' | cut -d/ -f1-2)
        [[ -z "$host" ]] && continue
        for src_file in /etc/apt/sources.list /etc/apt/sources.list.d/*; do
            [[ -f "$src_file" ]] || continue
            case "$src_file" in
                *.disabled|*.disabled.*|*.bak|*.save|*.distUpgrade) continue ;;
            esac
            if grep -qF "$host" "$src_file" 2>/dev/null; then
                if [[ -n "$keyword" ]] && ! grep -qF "$keyword" "$src_file" 2>/dev/null; then
                    continue
                fi
                if mv "$src_file" "${src_file}.disabled.reality" 2>/dev/null; then
                    log_info "已临时禁用失效软件源: $src_file"
                    disabled_count=$((disabled_count + 1))
                fi
            fi
        done
    done
    [[ $disabled_count -gt 0 ]]
}

update_package_lists() {
    log_info "更新软件包列表..."
    local retry_count=0 update_output update_status disabled_once=0
    while [[ $retry_count -lt 3 ]]; do
        update_output=$(eval "$PKG_UPDATE" 2>&1)
        update_status=$?
        echo "$update_output"
        [[ -n "$LOG_FILE" ]] && echo "$update_output" >> "$LOG_FILE"
        [[ $update_status -eq 0 ]] && return 0
        if [[ "$PKG_MANAGER" == "apt" && $disabled_once -eq 0 ]]; then
            if disable_broken_apt_sources "$update_output"; then
                disabled_once=1
                log_info "已处理失效软件源，重新更新..."
                continue
            fi
        fi
        retry_count=$((retry_count + 1))
        [[ $retry_count -lt 3 ]] && log_info "更新失败，重试 $retry_count/3..." && sleep 5
    done
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        print_yellow "警告: 软件包列表更新未完全成功，将尝试继续安装..."
        return 0
    fi
    exit_with_error "更新软件包列表失败"
}

check_service_manager() {
    if command_exists systemctl && systemctl --version >/dev/null 2>&1; then
        SERVICE_MANAGER="systemctl"
    elif command_exists service; then
        SERVICE_MANAGER="service"
    else
        exit_with_error "不支持的服务管理器"
    fi
    log_info "检测到服务管理器: $SERVICE_MANAGER"
}

get_server_ip_silent() {
    local server_ip=""
    local ip_sources=(
        "http://www.cloudflare.com/cdn-cgi/trace"
        "https://ipv4.icanhazip.com/"
        "https://ipinfo.io/ip"
        "https://api.ipify.org"
        "https://checkip.amazonaws.com"
    )
    local source
    for source in "${ip_sources[@]}"; do
        if [[ "$source" == *"cloudflare"* ]]; then
            server_ip=$(curl -s -4 --connect-timeout 10 --max-time 15 "$source" 2>/dev/null | grep "ip=" | awk -F "=" '{print $2}' | tr -d '\r\n' || true)
        else
            server_ip=$(curl -s -4 --connect-timeout 10 --max-time 15 "$source" 2>/dev/null | tr -d '\r\n' || true)
        fi
        if [[ "$server_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            local valid=true octet
            IFS='.' read -ra ADDR <<< "$server_ip"
            for octet in "${ADDR[@]}"; do
                [[ $octet -gt 255 ]] && valid=false && break
            done
            if [[ "$valid" == "true" ]]; then
                echo "$server_ip"
                return 0
            fi
        fi
        server_ip=""
    done
    server_ip=$(curl -s -6 --connect-timeout 10 --max-time 15 "http://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null | grep "ip=" | awk -F "=" '{print $2}' | tr -d '\r\n' || true)
    if [[ "$server_ip" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$server_ip" == *":"* ]]; then
        echo "$server_ip"
        return 0
    fi
    return 1
}

ensure_qrencode() {
    command_exists qrencode && return 0
    log_info "安装 qrencode 用于生成二维码..."
    case $PKG_MANAGER in
        apt) apt-get install -y qrencode >/dev/null 2>&1 || true ;;
        yum|dnf) eval "$PKG_INSTALL qrencode" >/dev/null 2>&1 || true ;;
        zypper) zypper in -y qrencode >/dev/null 2>&1 || true ;;
        pacman) pacman -S --noconfirm qrencode >/dev/null 2>&1 || true ;;
    esac
    command_exists qrencode
}

enable_bbr() {
    log_info "检查并启用 BBR..."
    local current
    current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
    if [[ "$current" == "bbr" ]]; then
        print_green "BBR 已启用"
        return 0
    fi

    modprobe tcp_bbr 2>/dev/null || true
    if ! lsmod 2>/dev/null | grep -q bbr && ! grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        print_yellow "当前内核可能不支持 BBR，已跳过"
        return 1
    fi

    if [[ -f /etc/sysctl.conf ]]; then
        sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    fi
    {
        echo "net.core.default_qdisc=fq"
        echo "net.ipv4.tcp_congestion_control=bbr"
    } >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1 || true

    current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
    if [[ "$current" == "bbr" ]]; then
        print_green "BBR 启用成功"
        return 0
    fi
    print_yellow "BBR 启用失败，可稍后手动配置"
    return 1
}

build_share_link() {
    SERVER_HOST=$(format_host_for_url "$SERVER_IP")
    local spx
    spx=$(urlencode_path "${SPIDER_X:-/}")
    SHARE_LINK="vless://${UUID}@${SERVER_HOST}:${PORT_NUMBER}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SERVER_SNI}&fp=chrome&pbk=${RE_PUBLIC_KEY}&sid=${SHORT_ID}&spx=${spx}&type=tcp&headerType=none#1024-reality"
}

save_state() {
    mkdir -p "$CONFIG_DIR"
    cat > "$STATE_FILE" <<EOF
PORT_NUMBER='${PORT_NUMBER}'
UUID='${UUID}'
SHORT_ID='${SHORT_ID}'
SERVER_SNI='${SERVER_SNI}'
RE_PRIVATE_KEY='${RE_PRIVATE_KEY}'
RE_PUBLIC_KEY='${RE_PUBLIC_KEY}'
SERVER_IP='${SERVER_IP}'
ENABLE_SNI_FILTER='${ENABLE_SNI_FILTER}'
SPIDER_X='${SPIDER_X}'
EOF
    chmod 600 "$STATE_FILE"
}

load_state() {
    [[ -f "$STATE_FILE" ]] || return 1
    # shellcheck source=/dev/null
    source "$STATE_FILE"
    [[ -n "$SERVER_IP" && -n "$UUID" && -n "$RE_PUBLIC_KEY" && -n "$SHORT_ID" && -n "$PORT_NUMBER" && -n "$SERVER_SNI" ]] || return 1
    build_share_link
    return 0
}

save_client_file() {
    build_share_link
    cat > "$CLIENT_FILE" <<EOF
{
  "proxy": "vless",
  "address": "$SERVER_IP",
  "port": $PORT_NUMBER,
  "uuid": "$UUID",
  "flow": "xtls-rprx-vision",
  "network": "tcp",
  "publicKey": "$RE_PUBLIC_KEY",
  "security": "reality",
  "sni": "$SERVER_SNI",
  "shortId": "$SHORT_ID",
  "spiderX": "$SPIDER_X",
  "sniFilter": $ENABLE_SNI_FILTER,
  "shareLink": "$SHARE_LINK"
}
EOF
    chmod 600 "$CLIENT_FILE"
}

# Xray 默认以 nobody 运行，config.json 必须对其可读（600/root 会导致 permission denied / status=23）
fix_xray_config_perms() {
    mkdir -p "$CONFIG_DIR"
    chmod 755 "$CONFIG_DIR"

    local svc_user="nobody"
    local svc_group="nogroup"
    if getent group nobody >/dev/null 2>&1; then
        svc_group="nobody"
    elif getent group nogroup >/dev/null 2>&1; then
        svc_group="nogroup"
    else
        svc_group="root"
    fi

    if id "$svc_user" >/dev/null 2>&1; then
        chown "root:${svc_group}" "$CONFIG_FILE" 2>/dev/null || chown root:root "$CONFIG_FILE" 2>/dev/null || true
        chmod 640 "$CONFIG_FILE"
        # 若 group 仍读不到，回退 644 保证服务能启动
        if ! su -s /bin/sh "$svc_user" -c "test -r '$CONFIG_FILE'" 2>/dev/null; then
            chmod 644 "$CONFIG_FILE"
        fi
    else
        chmod 644 "$CONFIG_FILE"
    fi
}

write_xray_config() {
    local temp_config="/tmp/xray_config_$$.json"
    local filter_block=""
    if [[ "$ENABLE_SNI_FILTER" == "1" ]]; then
        filter_block=$(cat <<'FILTER'
,
                    "limitFallbackUpload": {
                        "afterBytes": 0,
                        "bytesPerSec": 65536,
                        "burstBytesPerSec": 0
                    },
                    "limitFallbackDownload": {
                        "afterBytes": 10485760,
                        "bytesPerSec": 262144,
                        "burstBytesPerSec": 0
                    }
FILTER
)
    fi

    cat > "$temp_config" <<EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": $PORT_NUMBER,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "$SERVER_SNI:443",
                    "target": "$SERVER_SNI:443",
                    "xver": 0,
                    "serverNames": [
                        "$SERVER_SNI"
                    ],
                    "privateKey": "$RE_PRIVATE_KEY",
                    "shortIds": [
                        "",
                        "$SHORT_ID"
                    ]${filter_block}
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "blocked"
        }
    ]
}
EOF
    mv "$temp_config" "$CONFIG_FILE"
    fix_xray_config_perms

    if ! /usr/local/bin/xray run -test -config "$CONFIG_FILE" >/dev/null 2>&1; then
        # 旧版核心可能不认识 target / limitFallback，回退精简配置
        print_yellow "完整配置校验失败，尝试兼容模式..."
        cat > "$temp_config" <<EOF
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $PORT_NUMBER,
        "protocol": "vless",
        "settings": {
            "clients": [{ "id": "$UUID", "flow": "xtls-rprx-vision" }],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "tcp",
            "security": "reality",
            "realitySettings": {
                "show": false,
                "dest": "$SERVER_SNI:443",
                "serverNames": ["$SERVER_SNI"],
                "privateKey": "$RE_PRIVATE_KEY",
                "shortIds": ["$SHORT_ID"]
            }
        }
    }],
    "outbounds": [
        { "protocol": "freedom", "tag": "direct" },
        { "protocol": "blackhole", "tag": "blocked" }
    ]
}
EOF
        mv "$temp_config" "$CONFIG_FILE"
        fix_xray_config_perms
        if ! /usr/local/bin/xray run -test -config "$CONFIG_FILE" >/dev/null 2>&1; then
            exit_with_error "Xray配置验证失败"
        fi
    fi
}

restart_xray_service() {
    if [[ "$SERVICE_MANAGER" == "systemctl" ]]; then
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable xray.service 2>/dev/null || true
        systemctl restart xray.service || return 1
        sleep 2
        systemctl is-active --quiet xray.service
    else
        service xray restart
    fi
}

install_xray() {
    log_info "开始安装系统依赖和Xray..."
    mkdir -p "$BACKUP_DIR"
    [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "$BACKUP_DIR/config.json.backup"

    update_package_lists
    log_info "安装基础依赖包..."
    local basic_packages
    case $PKG_MANAGER in
        apt) basic_packages="curl wget gawk ca-certificates gnupg lsb-release unzip openssl qrencode" ;;
        yum|dnf|zypper) basic_packages="curl wget gawk ca-certificates gnupg2 unzip openssl qrencode" ;;
        pacman) basic_packages="curl wget gawk ca-certificates gnupg unzip openssl qrencode" ;;
    esac

    local retry_count=0
    while [[ $retry_count -lt 3 ]]; do
        eval "$PKG_INSTALL $basic_packages" && break
        retry_count=$((retry_count + 1))
        log_info "安装依赖失败，重试 $retry_count/3..."
        sleep 5
    done
    [[ $retry_count -eq 3 ]] && exit_with_error "安装基础依赖包失败"
    for tool in curl wget; do
        command_exists "$tool" || exit_with_error "$tool 安装失败"
    done
    print_green "基础依赖安装完成"

    log_info "下载并安装Xray..."
    local install_script_url="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
    local script_path="/tmp/xray-install.sh"
    retry_count=0
    while [[ $retry_count -lt 3 ]]; do
        log_info "下载Xray安装脚本 (尝试 $((retry_count + 1))/3)..."
        if curl -L --connect-timeout 30 --max-time 300 --retry 2 --retry-delay 5 "$install_script_url" -o "$script_path"; then
            if [[ -s "$script_path" ]] && head -1 "$script_path" | grep -q "#!/"; then
                chmod +x "$script_path"
                break
            fi
        fi
        retry_count=$((retry_count + 1))
        rm -f "$script_path"
        sleep 5
    done
    [[ $retry_count -eq 3 ]] && exit_with_error "下载Xray安装脚本失败"

    log_info "执行Xray安装脚本..."
    local install_status=0
    timeout 600 bash "$script_path" install || install_status=$?
    [[ $install_status -eq 124 ]] && exit_with_error "Xray安装超时"
    [[ -x /usr/local/bin/xray ]] || exit_with_error "Xray安装失败：未找到可执行文件"
    /usr/local/bin/xray version >/dev/null 2>&1 || exit_with_error "Xray二进制文件测试失败"
    [[ $install_status -ne 0 ]] && print_yellow "警告: 安装脚本退出码 $install_status，但已检测到可用 Xray，继续..."
    rm -f "$script_path"
    print_green "Xray安装完成"
}

generate_keys() {
    log_info "生成Reality密钥对..."
    [[ -x /usr/local/bin/xray ]] || exit_with_error "Xray未正确安装"
    local raw="" tries=0
    while (( tries < 5 )); do
        if raw=$(timeout 30 /usr/local/bin/xray x25519 2>/dev/null) && [[ -n "$raw" ]]; then
            break
        fi
        ((tries++))
        sleep 2
    done
    [[ -n "$raw" ]] || exit_with_error "生成X25519密钥失败"

    RE_PRIVATE_KEY=$(echo "$raw" | grep -iE "(private|privatekey)" | awk -F ':' '{print $2}' | tr -d ' \r\n\t' || true)
    RE_PUBLIC_KEY=$(echo "$raw" | grep -iE "password" | awk -F ':' '{print $2}' | tr -d ' \r\n\t' || true)
    [[ -z "$RE_PUBLIC_KEY" ]] && RE_PUBLIC_KEY=$(echo "$raw" | grep -iE "(public|publickey)" | awk -F ':' '{print $2}' | tr -d ' \r\n\t' || true)

    if [[ -z "$RE_PRIVATE_KEY" || -z "$RE_PUBLIC_KEY" ]]; then
        echo "$raw"
        exit_with_error "无法正确解析生成的密钥"
    fi
    if [[ ${#RE_PRIVATE_KEY} -lt 40 || ${#RE_PUBLIC_KEY} -lt 40 ]]; then
        exit_with_error "生成的密钥格式不正确"
    fi
    print_green "密钥生成成功"
}

pick_sni() {
    local i choice
    echo
    display_green "推荐 SNI（回车随机，输入序号或自定义域名）："
    for i in "${!SNI_PRESETS[@]}"; do
        echo "  $((i + 1)). ${SNI_PRESETS[$i]}"
    done
    local sni_input
    read -r -t 30 -p "请选择: " sni_input || true
    echo
    if [[ -z "$sni_input" ]]; then
        SERVER_SNI="${SNI_PRESETS[$((RANDOM % ${#SNI_PRESETS[@]}))]}"
        print_green "已随机选择 SNI: $SERVER_SNI"
    elif [[ "$sni_input" =~ ^[0-9]+$ ]] && [[ "$sni_input" -ge 1 && "$sni_input" -le ${#SNI_PRESETS[@]} ]]; then
        SERVER_SNI="${SNI_PRESETS[$((sni_input - 1))]}"
        print_green "已选择 SNI: $SERVER_SNI"
    elif validate_domain "$sni_input"; then
        SERVER_SNI="$sni_input"
        print_yellow "提示: 请确保该目标支持 TLS1.3/HTTP2"
    else
        SERVER_SNI="${SNI_PRESETS[0]}"
        print_yellow "输入无效，使用 ${SERVER_SNI}"
    fi
}

get_user_input() {
    log_info "获取用户配置参数..."
    UUID=$(generate_uuid) || exit_with_error "无法生成UUID"
    SHORT_ID=$(generate_short_id) || exit_with_error "无法生成 shortId"
    log_info "UUID: $UUID"
    log_info "shortId: $SHORT_ID"

    local port_input
    read -r -t 15 -p "回车或等待15秒为默认端口443，或者自定义端口请输入(1-65535)：" port_input || true
    if [[ -z "$port_input" ]]; then
        PORT_NUMBER=443
        echo
    elif validate_port "$port_input"; then
        PORT_NUMBER="$port_input"
    else
        PORT_NUMBER=443
        print_yellow "端口号无效，使用默认端口443"
    fi

    if is_port_in_use "$PORT_NUMBER"; then
        if command_exists ss && ss -tulnp 2>/dev/null | grep -E ":${PORT_NUMBER}[[:space:]]" | grep -q xray; then
            print_yellow "端口 ${PORT_NUMBER} 当前由 Xray 占用，将在配置后重启"
        else
            exit_with_error "端口 ${PORT_NUMBER} 已被占用"
        fi
    fi
    log_info "使用端口: $PORT_NUMBER"

    pick_sni
    log_info "使用SNI: $SERVER_SNI"

    local filter_input
    read -r -t 15 -p "是否启用探测限速(防偷跑/sni-filter)? 回车默认否，输入 y 启用: " filter_input || true
    echo
    if [[ "${filter_input,,}" == "y" || "${filter_input,,}" == "yes" ]]; then
        ENABLE_SNI_FILTER=1
        print_green "已启用探测限速"
    else
        ENABLE_SNI_FILTER=0
    fi
}

display_client_config() {
    echo
    display_green "=========== Reality配置参数 ==========="
    echo "代理模式：vless"
    echo "地址：$SERVER_IP"
    echo "端口：$PORT_NUMBER"
    echo "UUID：$UUID"
    echo "流控：xtls-rprx-vision"
    echo "传输协议：tcp"
    echo "Public key：$RE_PUBLIC_KEY"
    echo "底层传输：reality"
    echo "SNI：$SERVER_SNI"
    echo "shortIds：$SHORT_ID"
    echo "探测限速：$([ "$ENABLE_SNI_FILTER" = "1" ] && echo 已启用 || echo 未启用)"
    display_green "========================================"
    echo
    display_green "客户端连接链接："
    echo "${SHARE_LINK}"
    echo
    display_green "配置已保存: $CLIENT_FILE"
    [[ -n "$LOG_FILE" ]] && display_green "安装日志: $LOG_FILE"
    show_firewall_hint "$PORT_NUMBER"
}

show_qr_code() {
    if ! load_state; then
        print_red "未找到已安装的 Reality 配置"
        return 1
    fi
    echo
    display_green "分享链接："
    echo "$SHARE_LINK"
    echo
    if ensure_qrencode; then
        display_green "二维码："
        qrencode -t ANSIUTF8 "$SHARE_LINK"
    else
        print_yellow "未安装 qrencode，无法显示二维码。可手动: apt install qrencode"
    fi
}

view_config() {
    if ! load_state; then
        print_red "未找到已安装的 Reality 配置，请先安装"
        return 1
    fi
    clear
    display_client_config
    if [[ "$SERVICE_MANAGER" == "systemctl" ]]; then
        echo
        systemctl status xray.service --no-pager || true
    fi
}

do_restart() {
    is_reality_installed || { print_red "尚未安装 Reality"; return 1; }
    if restart_xray_service; then
        print_green "Xray 已重启"
    else
        print_red "重启失败"
        [[ "$SERVICE_MANAGER" == "systemctl" ]] && systemctl status xray.service --no-pager || true
    fi
}

apply_config_changes() {
    write_xray_config
    save_state
    save_client_file
    restart_xray_service || exit_with_error "配置已写入但服务重启失败"
    print_green "配置已更新"
    display_client_config
}

change_uuid() {
    load_state || { print_red "未找到配置"; return 1; }
    [[ -n "$RE_PRIVATE_KEY" ]] || exit_with_error "状态文件缺少私钥，请重装"
    UUID=$(generate_uuid) || exit_with_error "生成UUID失败"
    log_info "新 UUID: $UUID"
    apply_config_changes
}

change_short_id() {
    load_state || { print_red "未找到配置"; return 1; }
    [[ -n "$RE_PRIVATE_KEY" ]] || exit_with_error "状态文件缺少私钥，请重装"
    SHORT_ID=$(generate_short_id) || exit_with_error "生成 shortId 失败"
    log_info "新 shortId: $SHORT_ID"
    apply_config_changes
}

uninstall_reality() {
    echo
    read -r -p "确认卸载 Reality 配置并停止 Xray? (y/N): " confirm
    [[ "${confirm,,}" == "y" ]] || { echo "已取消"; return 0; }

    if [[ "$SERVICE_MANAGER" == "systemctl" ]]; then
        systemctl stop xray.service 2>/dev/null || true
        systemctl disable xray.service 2>/dev/null || true
    else
        service xray stop 2>/dev/null || true
    fi

    rm -f "$CONFIG_FILE" "$CLIENT_FILE" "$STATE_FILE"
    print_green "已移除 Reality 配置文件"

    read -r -p "是否同时卸载 Xray 程序本身? (y/N): " remove_bin
    if [[ "${remove_bin,,}" == "y" ]]; then
        local script_path="/tmp/xray-install.sh"
        if curl -L --connect-timeout 30 --max-time 120 "https://github.com/XTLS/Xray-install/raw/main/install-release.sh" -o "$script_path"; then
            bash "$script_path" remove || true
            rm -f "$script_path"
        fi
        print_green "已尝试卸载 Xray"
    else
        print_yellow "已保留 /usr/local/bin/xray"
    fi
}

configure_and_start() {
    log_info "写入配置并启动服务..."
    mkdir -p "$CONFIG_DIR"
    write_xray_config
    save_state
    save_client_file
    if ! restart_xray_service; then
        print_red "Xray服务启动失败"
        [[ "$SERVICE_MANAGER" == "systemctl" ]] && systemctl status xray.service --no-pager || true
        exit_with_error "启动Xray服务失败"
    fi
    print_green "Xray服务启动成功"
}

do_install() {
    log_info "开始 Reality 安装/重装..."
    log_info "脚本版本: Reality Plus v${SCRIPT_VERSION}"

    get_user_input

    if ! SERVER_IP=$(get_server_ip_silent); then
        exit_with_error "无法获取服务器IP地址"
    fi
    SERVER_HOST=$(format_host_for_url "$SERVER_IP")
    log_info "服务器IP: $SERVER_IP"

    install_xray
    generate_keys
    enable_bbr || true
    configure_and_start

    clear
    display_green "安装已经完成"
    display_client_config
    show_qr_code || true
    log_only "Reality安装完成: $(date)"
}

pause_return() {
    echo
    read -r -p "按回车返回菜单..." _
}

start_menu() {
    while true; do
        clear
        echo " ================================================== "
        echo "  Reality Plus v${SCRIPT_VERSION}  |  https://1024.day"
        echo "  VLESS + Vision + Reality 安装与管理"
        echo " ================================================== "
        if is_reality_installed; then
            display_green "  状态: 已安装"
        else
            display_yellow "  状态: 未安装"
        fi
        echo
        echo "  1. 安装 / 重装 Reality"
        echo "  2. 查看配置与链接"
        echo "  3. 显示二维码"
        echo "  4. 重启 Xray"
        echo "  5. 更换 UUID"
        echo "  6. 更换 shortId"
        echo "  7. 启用 BBR"
        echo "  8. 卸载 Reality"
        echo "  0. 退出"
        echo
        local num
        read -r -p "请输入数字: " num
        case "$num" in
            1) do_install; pause_return ;;
            2) view_config; pause_return ;;
            3) show_qr_code; pause_return ;;
            4) do_restart; pause_return ;;
            5) change_uuid; pause_return ;;
            6) change_short_id; pause_return ;;
            7) enable_bbr; pause_return ;;
            8) uninstall_reality; pause_return ;;
            0) exit 0 ;;
            *) echo "请输入正确数字"; sleep 1 ;;
        esac
    done
}

main() {
    detect_distribution
    detect_package_manager
    check_service_manager
    # 菜单模式下 Ctrl+C 直接退出，避免误触发安装清理文案过重
    trap 'echo; exit 130' INT TERM
    start_menu
}

main "$@"
