# 介绍

精简版 Xray 一键安装脚本 & 管理脚本，支持 VLESS-REALITY + XHTTP 的 IPv4/IPv6 双栈智能分流架构。

# 特点

- 快速安装
- 零学习成本
- 简化所有流程
- 屏蔽 BT
- 屏蔽中国 IP
- 兼容 Xray 命令
- 强大的快捷参数
- 默认采用双栈结构：v4/v6 REALITY 入站 + XHTTP stream-up 架构
- 支持自动回退 8443 端口
- 一键启用 BBR
- 一键更改双栈详细参数 (目标地址/SNI/ShortIds/密钥/等...)

# 设计理念

设计理念为：**高效率，超快速，极易用**

脚本专注于 VLESS-REALITY 双栈协议，以 **多配置同时运行** 为核心设计

并且专门优化了，添加、更改、查看、删除、这四项常用功能

你只需要一条命令即可完成 添加、更改、查看、删除、等操作

例如，添加一个配置仅需不到 1 秒！瞬间完成添加！其他操作亦是如此！

# 使用

安装完成后，使用 `xray` 命令进入主菜单，可选操作：

1. 添加配置
2. 更改配置
3. 查看配置
4. 删除配置
5. 运行管理
6. 更新
7. 卸载
8. 其他（启用BBR、查看日志、测试运行、重装脚本、设置DNS、切换v6only）

## 常用命令

```
xray add                 添加一个配置
xray change              更改配置
xray del                 删除配置
xray info                查看配置
xray start/stop/restart  启动/停止/重启
xray update core         更新 Xray 内核
xray update sh           更新脚本
xray uninstall           卸载
```

## 更改相关命令

```
xray port [name] [port | auto]                       更改端口
xray id [name] [uuid | auto]                         重新生成 UUID
xray key [name] [Private key | auto] [Public key]    重新生成密钥
xray v4dest [name] [domain]                          更改 v4 目标地址
xray v4sni [name] [domain]                           更改 v4 SNI
xray v4path [name] [path]                            更改 v4 路径
xray v6dest [name] [domain]                          更改 v6 目标地址
xray v6sni [name] [domain]                           更改 v6 SNI
xray v6path [name] [path]                            更改 v6 路径
xray v4sid [name]                                    重新生成 v4 Short IDs
xray v6sid [name]                                    重新生成 v6 Short IDs
xray v6only [name]                                   切换 v6only 状态
```


### 3. 启用 GitHub Actions 自动打包
非常关键的一步：**原脚本是通过下载 Release 里的 `code.zip` 来安装核心代码的，而不是直接克隆仓库。**

好在原作者留下了 `.github/workflows/release.yml`，所以你只需要：
1. 打开你 GitHub 仓库主页，点击上方的 **Actions** 标签页。
2. 如果提示 "Workflows aren't being run"，点击绿色按钮 **I understand my workflows, go ahead and enable them** 启用它。
3. 以后每次你修改了代码想要更新发布，**一定要记得修改 `xray.sh` 文件里的版本号**（例如把 `is_sh_ver=v1.33` 改成 `v1.34`）。
4. 将改动 Push 到 GitHub 后，Actions 会自动读取新版本号，自动帮你把代码打包成 `code.zip`，并生成一个新的 Release。

### 4. 在你的 VPS 上安装使用
当你看到 GitHub 的 Releases 页面已经自动生成了带有 `code.zip` 的版本后，你就可以在你的服务器上跑自己的安装指令了：

```bash
bash <(wget -qO- -o- https://github.com/233boy/Xray/raw/main/install.sh)
```