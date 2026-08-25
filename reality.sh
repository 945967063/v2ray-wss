#!/bin/bash
# forum: https://1024.day

# 确保以root用户运行
if [[ $EUID -ne 0 ]]; then
    clear
    echo "错误: 此脚本必须以root身份运行!" 1>&2
    exit 1
fi

# 全局变量定义
SCRIPT_VERSION="1.1.0"
SERVER_IP=""
SERVER_HOST=""
SHORT_ID=""
LOG_FILE="/var/log/reality_install.log"
BACKUP_DIR="/tmp/reality_backup_$(date +%s)"
XRAY_WAS_ACTIVE_BEFORE=0

# 创建日志目录
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
touch "$LOG_FILE" 2>/dev/null || {
    echo "无法创建日志文件，将只在屏幕显示输出"
    LOG_FILE=""
}

# 颜色输出函数 - 带日志
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

# 只显示颜色文字，不写入日志
display_red() {
    echo -e "\033[31m$1\033[0m"
}

display_green() {
    echo -e "\033[32m$1\033[0m"
}

display_yellow() {
    echo -e "\033[33m$1\033[0m"
}

# 日志记录函数 - 只写入日志，不显示在屏幕上
log_only() {
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 日志记录函数 - 同时显示在屏幕和日志
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 错误处理函数
exit_with_error() {
    print_red "错误: $1"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误: $1" >> "$LOG_FILE"
    cleanup_on_error
    exit 1
}

# 清理函数：只清临时文件，不停止可能已存在的 Xray 服务
cleanup_on_error() {
    log_info "执行错误清理..."
    rm -f /tmp/xray-install.sh /tmp/xray_config_$$.json 2>/dev/null || true
    log_info "错误清理完成（未停止现有 Xray 服务）"
}

# 信号陷阱
trap 'exit_with_error "脚本被中断"' INT TERM

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 验证端口参数（仅返回状态，不退出）
validate_port() {
    local port_to_check="$1"
    if [[ ! "$port_to_check" =~ ^[0-9]+$ ]] || [[ "$port_to_check" -lt 1 ]] || [[ "$port_to_check" -gt 65535 ]]; then
        return 1
    fi
    return 0
}

# 验证域名格式（仅返回状态，不退出）
validate_domain() {
    local domain_to_check="$1"
    if [[ ! "$domain_to_check" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

# 检查端口是否被占用
is_port_in_use() {
    local port="$1"
    if command_exists ss; then
        ss -tuln 2>/dev/null | grep -qE ":${port}[[:space:]]"
        return $?
    elif command_exists netstat; then
        netstat -tuln 2>/dev/null | grep -qE ":${port}[[:space:]]"
        return $?
    fi
    return 1
}

# IPv6 地址在 URL 中需要加方括号
format_host_for_url() {
    local ip="$1"
    if [[ "$ip" == *:* ]]; then
        echo "[${ip}]"
    else
        echo "$ip"
    fi
}

# 生成 Reality shortId（8 位 hex）
generate_short_id() {
    local sid=""
    if command_exists openssl; then
        sid=$(openssl rand -hex 4 2>/dev/null || true)
    fi
    if [[ -z "$sid" || ${#sid} -ne 8 ]]; then
        sid=$(head -c 4 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' | head -c 8)
    fi
    if [[ ! "$sid" =~ ^[0-9a-fA-F]{8}$ ]]; then
        sid=$(printf '%04x%04x' "$RANDOM" "$RANDOM")
    fi
    echo "${sid,,}"
}

# 安装完成后提示防火墙放行
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

# 检测系统发行版
detect_distribution() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS_ID=${ID:-unknown}
        OS_VERSION=${VERSION_ID:-unknown}
        OS_CODENAME=${VERSION_CODENAME:-}
    elif [[ -f /etc/redhat-release ]]; then
        if grep -q "CentOS" /etc/redhat-release; then
            OS_ID="centos"
            OS_VERSION=$(grep -oE '[0-9]+(\.[0-9]+)?' /etc/redhat-release | head -1)
        elif grep -q "Red Hat" /etc/redhat-release; then
            OS_ID="rhel"
            OS_VERSION=$(grep -oE '[0-9]+(\.[0-9]+)?' /etc/redhat-release | head -1)
        fi
    elif [[ -f /etc/debian_version ]]; then
        OS_ID="debian"
        OS_VERSION=$(cat /etc/debian_version)
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
    fi
    
    if [[ "$OS_ID" == "unknown" ]]; then
        print_yellow "无法确定系统类型，将尝试继续安装..."
    fi
    
    log_info "检测到系统: $OS_ID $OS_VERSION"
}

# 增强包管理器检测
detect_package_manager() {
    if command_exists apt-get; then
        PKG_MANAGER="apt"
        PKG_UPDATE="apt-get update -y"
        PKG_INSTALL="apt-get install -y"
        # 检查dpkg是否被锁（最多等待 120 秒）
        local lock_wait=0
        while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
            if [[ $lock_wait -ge 120 ]]; then
                exit_with_error "等待 dpkg/apt 锁超时，请检查是否有其他 apt 进程正在运行"
            fi
            log_info "等待dpkg锁释放... (${lock_wait}s/120s)"
            sleep 3
            lock_wait=$((lock_wait + 3))
        done
    elif command_exists yum; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum makecache"
        PKG_INSTALL="yum install -y"
        # 安装EPEL仓库
        yum install -y epel-release 2>/dev/null || true
    elif command_exists dnf; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf makecache"
        PKG_INSTALL="dnf install -y"
        # 安装EPEL仓库
        dnf install -y epel-release 2>/dev/null || true
    elif command_exists zypper; then
        PKG_MANAGER="zypper"
        PKG_UPDATE="zypper ref"
        PKG_INSTALL="zypper in -y"
    elif command_exists pacman; then
        PKG_MANAGER="pacman"
        PKG_UPDATE="pacman -Sy"
        PKG_INSTALL="pacman -S --noconfirm"
    else
        exit_with_error "不支持的包管理器，请手动安装依赖包"
    fi
    log_info "检测到包管理器: $PKG_MANAGER"
}

# 根据 apt update 报错，临时禁用失效的第三方源（如 Ookla speedtest 等）
disable_broken_apt_sources() {
    local update_output="$1"
    local disabled_count=0
    local repo_urls=()

    # 提取 "The repository 'URL' does not have a Release file"
    while IFS= read -r line; do
        if [[ "$line" =~ The\ repository\ \'([^\']+)\' ]]; then
            repo_urls+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$update_output"

    # 也匹配 Err: 行中的仓库 URL
    while IFS= read -r line; do
        if [[ "$line" =~ ^Err:[0-9]+\ +([^[:space:]]+) ]]; then
            repo_urls+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$update_output"

    if [[ ${#repo_urls[@]} -eq 0 ]]; then
        return 1
    fi

    local url host keyword
    for url in "${repo_urls[@]}"; do
        # 从 URL 提取特征关键字，用于匹配 sources 文件内容
        host=$(echo "$url" | sed -E 's#https?://([^/]+)/.*#\1#')
        keyword=$(echo "$url" | sed -E 's#https?://[^/]+/##' | cut -d/ -f1-2)
        [[ -z "$host" ]] && continue

        local src_file
        for src_file in /etc/apt/sources.list /etc/apt/sources.list.d/*; do
            [[ -f "$src_file" ]] || continue
            # 跳过已禁用或备份的源文件
            case "$src_file" in
                *.disabled|*.disabled.*|*.bak|*.save|*.distUpgrade) continue ;;
            esac

            if grep -qF "$host" "$src_file" 2>/dev/null; then
                # 优先匹配更具体的路径关键字，避免误伤同域名其他源
                if [[ -n "$keyword" ]] && ! grep -qF "$keyword" "$src_file" 2>/dev/null; then
                    continue
                fi
                local backup_file="${src_file}.disabled.reality"
                if mv "$src_file" "$backup_file" 2>/dev/null; then
                    log_info "已临时禁用失效软件源: $src_file -> $backup_file"
                    disabled_count=$((disabled_count + 1))
                fi
            fi
        done
    done

    [[ $disabled_count -gt 0 ]]
}

# 更新软件包列表（apt 遇到失效第三方源时自动处理并继续）
update_package_lists() {
    log_info "更新软件包列表..."
    local retry_count=0
    local update_output=""
    local update_status=0
    local disabled_once=0

    while [[ $retry_count -lt 3 ]]; do
        update_output=$(eval "$PKG_UPDATE" 2>&1)
        update_status=$?
        echo "$update_output"
        [[ -n "$LOG_FILE" ]] && echo "$update_output" >> "$LOG_FILE"

        if [[ $update_status -eq 0 ]]; then
            return 0
        fi

        # apt: 首次失败时尝试禁用失效第三方源并立即重试
        if [[ "$PKG_MANAGER" == "apt" && $disabled_once -eq 0 ]]; then
            if disable_broken_apt_sources "$update_output"; then
                disabled_once=1
                log_info "已处理失效软件源，重新更新软件包列表..."
                continue
            fi
        fi

        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt 3 ]]; then
            log_info "更新失败，重试 $retry_count/3..."
            sleep 5
        fi
    done

    # apt 主仓库通常仍可用，警告后继续安装依赖
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        print_yellow "警告: 软件包列表更新未完全成功（可能存在失效第三方源），将尝试继续安装..."
        return 0
    fi

    exit_with_error "更新软件包列表失败"
}

# 检查服务管理器
check_service_manager() {
    if command_exists systemctl && systemctl --version >/dev/null 2>&1; then
        SERVICE_MANAGER="systemctl"
        SERVICE_ENABLE="systemctl enable"
        SERVICE_START="systemctl start"
        SERVICE_RESTART="systemctl restart"
        SERVICE_STATUS="systemctl status"
        SERVICE_STOP="systemctl stop"
    elif command_exists service; then
        SERVICE_MANAGER="service"
        SERVICE_ENABLE="chkconfig --add"
        SERVICE_START="service"
        SERVICE_RESTART="service"
        SERVICE_STATUS="service"
        SERVICE_STOP="service"
    else
        exit_with_error "不支持的服务管理器"
    fi
    log_info "检测到服务管理器: $SERVICE_MANAGER"
}

# 获取系统IP地址 - 静默版本，成功时输出IP并返回0，失败返回1（勿在此exit，避免子shell问题）
get_server_ip_silent() {
    local server_ip=""
    local ip_sources=(
        "http://www.cloudflare.com/cdn-cgi/trace"
        "https://ipv4.icanhazip.com/"
        "https://ipinfo.io/ip"
        "https://api.ipify.org"
        "https://checkip.amazonaws.com"
    )
    
    # 优先尝试IPv4
    for source in "${ip_sources[@]}"; do
        if [[ "$source" == *"cloudflare"* ]]; then
            server_ip=$(curl -s -4 --connect-timeout 10 --max-time 15 "$source" 2>/dev/null | grep "ip=" | awk -F "=" '{print $2}' | tr -d '\r\n' || true)
        else
            server_ip=$(curl -s -4 --connect-timeout 10 --max-time 15 "$source" 2>/dev/null | tr -d '\r\n' || true)
        fi
        
        # 验证IP地址格式
        if [[ "$server_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            local valid=true
            local octet
            IFS='.' read -ra ADDR <<< "$server_ip"
            for octet in "${ADDR[@]}"; do
                if [[ $octet -gt 255 ]]; then
                    valid=false
                    break
                fi
            done
            if [[ "$valid" == "true" ]]; then
                echo "$server_ip"
                return 0
            fi
        fi
        
        server_ip=""
    done
    
    # 如果IPv4失败，尝试IPv6
    server_ip=$(curl -s -6 --connect-timeout 10 --max-time 15 "http://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null | grep "ip=" | awk -F "=" '{print $2}' | tr -d '\r\n' || true)
    
    if [[ "$server_ip" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$server_ip" == *":"* ]]; then
        echo "$server_ip"
        return 0
    fi
    
    return 1
}

# 生成UUID（成功输出UUID返回0，失败返回1）
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
    
    if [[ ! "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        return 1
    fi
    
    echo "${uuid,,}"
}

# 安装Xray
install_xray() { 
    log_info "开始安装系统依赖和Xray..."
    
    # 创建备份目录
    mkdir -p "$BACKUP_DIR"
    
    # 备份现有的xray配置
    if [[ -f "/usr/local/etc/xray/config.json" ]]; then
        log_info "备份现有Xray配置..."
        cp "/usr/local/etc/xray/config.json" "$BACKUP_DIR/config.json.backup"
    fi
    
    # 更新包列表（容错失效第三方 apt 源）
    update_package_lists
    
    # 安装基础依赖
    log_info "安装基础依赖包..."
    local basic_packages=""
    
    case $PKG_MANAGER in
        "apt")
            basic_packages="curl wget gawk ca-certificates gnupg lsb-release unzip"
            ;;
        "yum"|"dnf")
            basic_packages="curl wget gawk ca-certificates gnupg2 unzip"
            ;;
        "zypper")
            basic_packages="curl wget gawk ca-certificates gnupg2 unzip"
            ;;
        "pacman")
            basic_packages="curl wget gawk ca-certificates gnupg unzip"
            ;;
    esac
    
    # 安装包带重试机制
    local retry_count=0
    while [[ $retry_count -lt 3 ]]; do
        if eval "$PKG_INSTALL $basic_packages"; then
            break
        fi
        retry_count=$((retry_count + 1))
        log_info "安装依赖失败，重试 $retry_count/3..."
        sleep 5
    done
    
    if [[ $retry_count -eq 3 ]]; then
        exit_with_error "安装基础依赖包失败"
    fi
    
    # 验证关键工具是否可用
    for tool in curl wget; do
        if ! command_exists "$tool"; then
            exit_with_error "$tool 安装失败，无法继续"
        fi
    done
    
    print_green "基础依赖安装完成"
    
    # 安装Xray
    log_info "下载并安装Xray..."
    local install_script_url="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
    local script_path="/tmp/xray-install.sh"
    
    # 下载安装脚本带重试机制
    retry_count=0
    while [[ $retry_count -lt 3 ]]; do
        log_info "下载Xray安装脚本 (尝试 $((retry_count + 1))/3)..."
        if curl -L --connect-timeout 30 --max-time 300 --retry 2 --retry-delay 5 "$install_script_url" -o "$script_path"; then
            # 验证脚本下载是否正确
            if [[ -s "$script_path" ]] && head -1 "$script_path" | grep -q "#!/"; then
                chmod +x "$script_path"
                break
            else
                log_info "下载的脚本文件已损坏"
            fi
        fi
        retry_count=$((retry_count + 1))
        rm -f "$script_path"
        sleep 5
    done
    
    if [[ $retry_count -eq 3 ]]; then
        exit_with_error "下载Xray安装脚本失败"
    fi
    
    # 运行安装脚本：以二进制是否可用为准，忽略安装脚本非致命退出码
    # （XTLS 安装脚本在「已安装但未运行」等情况下可能返回非 0，实际已安装成功）
    log_info "执行Xray安装脚本..."
    local install_status=0
    timeout 600 bash "$script_path" install || install_status=$?

    if [[ $install_status -eq 124 ]]; then
        exit_with_error "Xray安装超时"
    fi

    # 验证Xray安装
    if [[ ! -f "/usr/local/bin/xray" ]] || [[ ! -x "/usr/local/bin/xray" ]]; then
        exit_with_error "Xray安装失败：未找到可执行文件"
    fi

    # 测试xray二进制文件
    if ! /usr/local/bin/xray version >/dev/null 2>&1; then
        exit_with_error "Xray二进制文件测试失败"
    fi

    if [[ $install_status -ne 0 ]]; then
        print_yellow "警告: Xray安装脚本退出码为 $install_status，但已检测到可用的 Xray，继续配置..."
    fi

    # 清理
    rm -f "$script_path"

    print_green "Xray安装完成"
}

# 生成密钥对
generate_keys() {
    log_info "生成Reality密钥对..."
    
    # 验证xray是否可用
    if [[ ! -f "/usr/local/bin/xray" ]] || [[ ! -x "/usr/local/bin/xray" ]]; then
        exit_with_error "Xray未正确安装，无法生成密钥"
    fi
    
    # 测试xray二进制文件
    if ! /usr/local/bin/xray version >/dev/null 2>&1; then
        exit_with_error "Xray二进制文件已损坏或不兼容"
    fi
    
    local raw=""
    local tries=0
    local max_tries=5
    
    while (( tries < max_tries )); do
        log_info "尝试生成密钥 ($((tries + 1))/$max_tries)..."
        
        # 使用超时防止挂起
        if raw=$(timeout 30 /usr/local/bin/xray x25519 2>/dev/null); then
            if [[ -n "$raw" ]]; then
                break
            fi
        fi
        
        ((tries++))
        if (( tries < max_tries )); then
            log_info "密钥生成失败，等待重试..."
            sleep 2
        fi
    done
    
    if [[ -z "$raw" ]]; then
        exit_with_error "生成X25519密钥失败，已尝试$max_tries次"
    fi
    
    log_info "解析密钥输出..."
    
    # 解析私钥
    RE_PRIVATE_KEY=$(echo "$raw" | grep -iE "(private|privatekey)" | awk -F ':' '{print $2}' | tr -d ' \r\n\t' || true)
    
    # 解析公钥，优先级：Password优先，然后Public
    RE_PUBLIC_KEY=$(echo "$raw" | grep -iE "password" | awk -F ':' '{print $2}' | tr -d ' \r\n\t' || true)
    
    # 如果没有Password字段，尝试Public字段
    if [[ -z "$RE_PUBLIC_KEY" ]]; then
        RE_PUBLIC_KEY=$(echo "$raw" | grep -iE "(public|publickey)" | awk -F ':' '{print $2}' | tr -d ' \r\n\t' || true)
    fi
    
    # 验证提取的密钥
    if [[ -z "$RE_PRIVATE_KEY" || -z "$RE_PUBLIC_KEY" ]]; then
        print_red "密钥解析失败。原始输出:"
        echo "================================"
        echo "$raw"
        echo "================================"
        print_red "提取的私钥: '$RE_PRIVATE_KEY'"
        print_red "提取的公钥: '$RE_PUBLIC_KEY'"
        print_red "注意: 公钥首先使用Password字段，然后是Public字段"
        exit_with_error "无法正确解析生成的密钥"
    fi
    
    # 验证密钥格式 (X25519密钥应该是44个字符的base64)
    if [[ ${#RE_PRIVATE_KEY} -lt 40 || ${#RE_PUBLIC_KEY} -lt 40 ]]; then
        exit_with_error "生成的密钥格式不正确 (私钥长度: ${#RE_PRIVATE_KEY}, 公钥长度: ${#RE_PUBLIC_KEY})"
    fi
    
    # 额外验证 - 密钥应该是URL安全的base64类型
    if [[ ! "$RE_PRIVATE_KEY" =~ ^[A-Za-z0-9+/=_-]+$ ]] || [[ ! "$RE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/=_-]+$ ]]; then
        exit_with_error "生成的密钥包含非法字符"
    fi
    
    print_green "密钥生成成功"
    log_only "密钥对已生成（不在日志中记录明文密钥）"
}

# 配置Xray
configure_xray() {
    log_info "配置Xray服务..."
    
    # 确保配置目录存在
    mkdir -p /usr/local/etc/xray
    chmod 755 /usr/local/etc/xray
    
    # 验证必要变量
    local required_vars=("PORT_NUMBER" "UUID" "SERVER_SNI" "RE_PRIVATE_KEY" "SHORT_ID")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            exit_with_error "必要变量 $var 未设置"
        fi
    done
    
    # 创建配置
    log_info "生成Xray配置文件..."
    
    # 先使用临时文件，然后移动到最终位置
    local temp_config="/tmp/xray_config_$$.json"
    
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
                    "xver": 0,
                    "serverNames": [
                        "$SERVER_SNI"
                    ],
                    "privateKey": "$RE_PRIVATE_KEY",
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimeDiff": 0,
                    "shortIds": [
                        "$SHORT_ID"
                    ]
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
    
    # 移动到最终位置
    mv "$temp_config" /usr/local/etc/xray/config.json
    chmod 600 /usr/local/etc/xray/config.json
    
    # 测试配置
    log_info "验证Xray配置..."
    if ! /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json >/dev/null 2>&1; then
        exit_with_error "Xray配置验证失败"
    fi
    
    print_green "配置文件验证成功"
    
    # 启动并启用Xray服务
    log_info "启动Xray服务..."
    if [[ "$SERVICE_MANAGER" == "systemctl" ]]; then
        # 如果服务在运行，先停止
        systemctl stop xray.service 2>/dev/null || true
        
        # 启用服务
        if ! systemctl enable xray.service; then
            print_yellow "启用Xray服务失败，尝试继续..."
        fi
        
        # 启动服务
        if ! systemctl start xray.service; then
            log_info "直接启动失败，尝试重启..."
            if ! systemctl restart xray.service; then
                print_red "Xray服务启动失败，检查详细错误信息:"
                systemctl status xray.service --no-pager || true
                journalctl -u xray.service --no-pager -n 20 || true
                exit_with_error "启动Xray服务失败"
            fi
        fi
        
        # 等待并检查服务是否运行
        sleep 3
        local check_attempts=0
        while [[ $check_attempts -lt 5 ]]; do
            if systemctl is-active --quiet xray.service; then
                break
            fi
            ((check_attempts++))
            log_info "等待服务启动... ($check_attempts/5)"
            sleep 2
        done
        
        if ! systemctl is-active --quiet xray.service; then
            print_red "Xray服务未正常运行，服务状态:"
            systemctl status xray.service --no-pager || true
            exit_with_error "Xray服务启动失败"
        fi
    else
        # 对非systemd系统的回退方案
        if ! service xray restart; then
            exit_with_error "启动Xray服务失败"
        fi
    fi
    
    print_green "Xray服务启动成功"
    
    # 生成客户端配置
    generate_client_config
}

# 生成客户端配置
generate_client_config() {
    log_info "生成客户端配置..."
    
    # 验证所有必要参数
    if [[ -z "$SERVER_IP" || -z "$PORT_NUMBER" || -z "$UUID" || -z "$RE_PUBLIC_KEY" || -z "$SERVER_SNI" || -z "$SHORT_ID" ]]; then
        exit_with_error "生成客户端配置时缺少必要参数"
    fi

    SERVER_HOST=$(format_host_for_url "$SERVER_IP")
    local share_link="vless://${UUID}@${SERVER_HOST}:${PORT_NUMBER}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SERVER_SNI}&fp=chrome&pbk=${RE_PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#1024-reality"
    
    cat > /usr/local/etc/xray/reclient.json <<EOF
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
  "shareLink": "$share_link"
}
EOF
    
    chmod 600 /usr/local/etc/xray/reclient.json
    SHARE_LINK="$share_link"
    log_info "客户端配置已保存到: /usr/local/etc/xray/reclient.json"
}

# 显示Xray服务状态
display_xray_status() {
    echo
    display_green "Xray服务状态:"
    if [[ "$SERVICE_MANAGER" == "systemctl" ]]; then
        systemctl status xray.service --no-pager || true
    else
        service xray status || true
    fi
}

# 显示客户端配置
display_client_config() {
    echo
    display_green "安装已经完成"
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
    display_green "========================================"
    echo
    display_green "客户端连接链接："
    echo "${SHARE_LINK}"
    echo
    display_green "配置信息已保存到: /usr/local/etc/xray/reclient.json"
    if [[ -n "$LOG_FILE" ]]; then
        display_green "安装日志文件位置: $LOG_FILE"
    fi
    show_firewall_hint "$PORT_NUMBER"
}

# 获取用户输入
get_user_input() {
    log_info "获取用户配置参数..."
    
    UUID=$(generate_uuid) || exit_with_error "无法生成UUID，请安装uuidgen或python"
    log_info "已生成UUID: $UUID"

    SHORT_ID=$(generate_short_id) || exit_with_error "无法生成 shortId"
    log_info "已生成 shortId: $SHORT_ID"
    
    local port_input
    read -r -t 15 -p "回车或等待15秒为默认端口443，或者自定义端口请输入(1-65535)："  port_input || true
    if [[ -z "$port_input" ]]; then
        PORT_NUMBER=443
        echo ""
    elif validate_port "$port_input"; then
        PORT_NUMBER="$port_input"
    else
        PORT_NUMBER=443
        print_yellow "端口号无效，使用默认端口443"
    fi

    if is_port_in_use "$PORT_NUMBER"; then
        if command_exists ss && ss -tulnp 2>/dev/null | grep -E ":${PORT_NUMBER}[[:space:]]" | grep -q xray; then
            print_yellow "端口 ${PORT_NUMBER} 当前由 Xray 占用，将在配置后重启服务"
        else
            exit_with_error "端口 ${PORT_NUMBER} 已被占用，请更换端口后重试"
        fi
    fi
    log_info "使用端口: $PORT_NUMBER"
    
    echo
    
    local sni_input
    read -r -t 30 -p "回车或等待30秒为默认域名 www.amazon.com，或者自定义SNI请输入："  sni_input || true
    if [[ -z "$sni_input" ]]; then
        SERVER_SNI="www.amazon.com"
        echo ""
    elif validate_domain "$sni_input"; then
        SERVER_SNI="$sni_input"
        print_yellow "提示: 请确保该 SNI 目标支持 TLS1.3/HTTP2，否则可能无法正常连接"
    else
        SERVER_SNI="www.amazon.com"
        print_yellow "域名格式无效，使用默认域名 www.amazon.com"
    fi
    log_info "使用SNI: $SERVER_SNI"
}

# 主函数
main() {
    log_info "开始Reality安装和配置..."
    log_info "脚本版本: Reality Plus v${SCRIPT_VERSION}"
    
    detect_distribution
    detect_package_manager
    check_service_manager

    if command_exists systemctl && systemctl is-active --quiet xray.service 2>/dev/null; then
        XRAY_WAS_ACTIVE_BEFORE=1
        log_info "检测到已有运行中的 Xray 服务，安装失败时不会强制停止它"
    fi
    
    get_user_input
    
    log_only "尝试获取服务器IP地址..."
    if ! SERVER_IP=$(get_server_ip_silent); then
        exit_with_error "无法获取服务器IP地址，请检查网络连接"
    fi
    SERVER_HOST=$(format_host_for_url "$SERVER_IP")
    log_only "服务器IP地址: $SERVER_IP"
    
    install_xray
    generate_keys
    configure_xray

    clear
    display_client_config
    display_xray_status
    
    log_only "Reality安装完成！"
    log_only "安装成功完成，时间: $(date)"
}

# 执行主函数
main "$@"
