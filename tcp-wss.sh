#!/bin/bash
# 一键入口：Shadowsocks-rust / Reality / Hysteria2
# forum: https://1024.day

if [[ $EUID -ne 0 ]]; then
    clear
    echo "Error: This script must be run as root!" 1>&2
    exit 1
fi

REPO_RAW="https://raw.githubusercontent.com/945967063/v2ray-wss/main"

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
    echo
    echo "  1. Shadowsocks-rust（落地）"
    echo "  2. Reality（xtls-rprx-vision）"
    echo "  3. Hysteria2"
    echo "  0. 退出"
    echo
    read -r -p "请输入数字: " num
    case "$num" in
        1) run_remote ss-rust.sh ;;
        2) run_remote reality.sh ;;
        3) run_remote hy2.sh ;;
        0) exit 0 ;;
        *)
            echo "请输入正确数字"
            sleep 1
            start_menu
            ;;
    esac
}

start_menu
