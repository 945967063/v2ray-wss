一键脚本：Shadowsocks-rust、Reality（xtls-rprx-vision）、Hysteria2。支持 Debian / Ubuntu / CentOS，含甲骨文 ARM。

## 一键入口

```bash
wget -O tcp-wss.sh https://raw.githubusercontent.com/945967063/v2ray-wss/main/tcp-wss.sh && bash tcp-wss.sh
```

菜单：

1. Shadowsocks-rust（落地）
2. Reality（xtls-rprx-vision）
3. Hysteria2

进入后各自有子菜单：安装/重装、查看链接、重启、更换密码或 UUID、更换端口、完全卸载。

## 单独使用

```bash
# Shadowsocks-rust
wget --no-cache -O ss-rust.sh https://raw.githubusercontent.com/945967063/v2ray-wss/main/ss-rust.sh && bash ss-rust.sh

# Reality
wget --no-cache -O reality.sh https://raw.githubusercontent.com/945967063/v2ray-wss/main/reality.sh && bash reality.sh

# Hysteria2
wget --no-cache -O hy2.sh https://raw.githubusercontent.com/945967063/v2ray-wss/main/hy2.sh && bash hy2.sh
```

## 配置位置

| 协议 | 服务端配置 | 客户端信息 |
|------|------------|------------|
| Shadowsocks-rust | `/etc/shadowsocks/config.json` | `/etc/shadowsocks/client.json` |
| Reality | `/usr/local/etc/xray/config.json` | `/usr/local/etc/xray/reclient.json` |
| Hysteria2 | `/etc/hysteria/config.yaml` | `/etc/hysteria/hyclient.json` |

## 完全卸载

在对应脚本菜单选「完全卸载」，或：

```bash
bash ss-rust.sh uninstall
bash reality.sh uninstall
bash hy2.sh uninstall
```

**提醒：** 连不上时先检查云安全组 / 本机防火墙是否放行对应端口（Hysteria2 为 UDP）。
