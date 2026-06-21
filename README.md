# 介绍

VLESS-REALITY + XHTTP 的 IPv4/IPv6 上下行分离的 Xray 一键安装脚本 & 管理脚本

# 特点

- 屏蔽 BT, 回国流量等
- 架构：v4/v6 REALITY 入站 + XHTTP stream-up
- 自动返回 mihomo 的节点配置信息
- 支持自动回退 8443 端口
- 一键启用 BBR
- 一键更改双栈详细参数 (目标地址/SNI/ShortIds/密钥/等...)

# 入门

## 安装

```bash
bash <(wget -qO- -o- https://github.com/Chen017/Xray/raw/main/install.sh)
```
初次使用，需要输入伪装的v4和v6 sni，并且选择分离模式

安装完成后，可进一步修改参数

## 使用

安装完成后，使用 `xray` 命令进入主菜单
