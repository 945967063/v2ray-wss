搭建 Shadowsocks-rust， V2ray+ Nginx + WebSocket 和 Reality(xtls-rprx-vision), Hysteria2, https 正向代理脚本，支持 Debian、Ubuntu、Centos，并支持甲骨文ARM平台。

简单点讲，没域名的用户可以安装 Reality 和 hy2 代理，有域名的可以安装 V2ray+wss 和 https 正向代理，各取所需。

## 一键安装

```bash
wget -O tcp-wss.sh https://raw.githubusercontent.com/945967063/v2ray-wss/main/tcp-wss.sh && bash tcp-wss.sh
```

菜单选项：

1. Shadowsocks-rust（落地）
2. v2ray+ws+tls（需要域名）
3. Reality（xtls-rprx-vision）
4. Hysteria2
5. Https 正向代理

## 单独安装 Reality

```bash
wget --no-cache -O reality.sh https://raw.githubusercontent.com/945967063/v2ray-wss/main/reality.sh && bash reality.sh
```

## 完全卸载 Reality / Xray

```bash
wget --no-cache -O reality.sh https://raw.githubusercontent.com/945967063/v2ray-wss/main/reality.sh && bash reality.sh uninstall
```

或通过菜单：

```bash
wget -O tcp-wss.sh https://raw.githubusercontent.com/945967063/v2ray-wss/main/tcp-wss.sh && bash tcp-wss.sh
```

选择 `6. 完全卸载 Reality / Xray`。

**便宜VPS推荐：** https://hostalk.net/deals.html

![image](https://github.com/user-attachments/assets/be9783bb-88a2-477a-a8af-4ffc86323805)

已测试系统如下：

Debian 9, 10, 11, 12, 13

Ubuntu 16.04, 18.04, 20.04, 22.04, 24.04

CentOS 7

* WSS客户端配置信息保存在：
`cat /usr/local/etc/v2ray/client.json`

* Shadowsocks客户端配置信息：
`cat /etc/shadowsocks/config.json`

* Reality客户端配置信息保存在：
`cat /usr/local/etc/xray/reclient.json`

* Hysteria2客户端配置信息保存在：
`cat /etc/hysteria/hyclient.json`

* Https正向代理客户端配置信息保存在：
`cat /etc/caddy/https.json`

卸载方法如下：
https://1024.day/d/1296

**提醒：连不上的朋友，建议先检查一下服务器自带防火墙有没有关闭？**
