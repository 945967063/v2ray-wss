#!/bin/bash
# 一键入口：Shadowsocks-rust / Reality / Hysteria2
# forum: https://1024.day

if [[ $EUID -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

REPO_RAW="https://raw.githubusercontent.com/945967063/v2ray-wss/main"

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
        rm -f "$tmp"
        for f in ss-rust.sh reality.sh hy2.sh; do
            wget --no-cache -q -O "/usr/local/lib/sb-menu/${f}" "${REPO_RAW}/${f}" 2>/dev/null || true
            chmod +x "/usr/local/lib/sb-menu/${f}" 2>/dev/null || true
        done
        echo
        echo "已安装控制台快捷命令:"
        echo "  sb              打开总菜单"
        echo "  ssrust          Shadowsocks-rust 管理"
        echo "  reality         Reality 管理"
        echo "  hy2             Hysteria2 管理"
        echo
    else
        rm -f "$tmp"
        echo "快捷命令安装失败（不影响使用菜单）"
    fi
}

run_remote() {
    local name="$1"
    shift
    local tmp="/tmp/${name}.$$"
    if ! wget --no-cache -O "$tmp" "${REPO_RAW}/${name}" ; then
        echo "下载 ${name} 失败"
        rm -f "$tmp"
        return 1
    fi
    chmod +x "$tmp"
    bash "$tmp" "$@"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

start_menu() {
    clear
    echo " ================================================== "
    echo "  代理一键脚本  |  https://1024.day"
    echo "  Shadowsocks-rust / Reality / Hysteria2"
    echo " ================================================== "
    if [[ -x /usr/local/bin/sb ]]; then
        echo "  快捷命令已启用: sb | ssrust | reality | hy2"
    else
        echo "  提示: 选 4 可安装控制台快捷命令 sb"
    fi
    echo
    echo "  1. Shadowsocks-rust（落地）"
    echo "  2. Reality（xtls-rprx-vision）"
    echo "  3. Hysteria2"
    echo "  4. 安装 / 更新控制台快捷命令"
    echo "  0. 退出"
    echo
    read -r -p "请输入数字: " num
    case "$num" in
        1) run_remote ss-rust.sh ;;
        2) run_remote reality.sh ;;
        3) run_remote hy2.sh ;;
        4) install_console_shortcut; read -r -p "按回车返回..." _; start_menu ;;
        0) exit 0 ;;
        *)
            echo "请输入正确数字"
            sleep 1
            start_menu
            ;;
    esac
}

install_console_shortcut >/dev/null 2>&1 || true
start_menu
