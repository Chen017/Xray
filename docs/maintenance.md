# Xray Script 维护指南

## 模块与运行方式

| 位置 | 职责 |
| --- | --- |
| `install.sh`、`xray.sh`、`src/init.sh` | 安装固定版本核心，进入交互菜单或 Agent 子命令，载入已安装模块 |
| `src/core.sh`、`src/node.jq`、`src/routing.sh`、`src/export.sh` | 生成入站和路由，维护线路/落地关系，导出分享链接和 Mihomo YAML |
| `src/runtime.sh`、`src/firewall.sh`、`src/maintenance.sh` | 锁内校验和部署、回滚配置及两栈防火墙、迁移已安装配置 |
| `src/download.sh`、`update_geodata.sh`、`src/systemd.sh`、`src/bbr.sh` | 更新脚本及固定核心、事务替换 geodata、服务与系统维护 |
| `src/diagnostics.sh`、`src/network_probe.sh`、`src/status.*` | 菜单状态与只读探测，供 Panel Agent 复用 |
| `src/panel.sh`、`src/panel-report.py` | Agent 生命周期入口和机器可读报告 |

修改 `src/` 的协议、路由、探测或回滚实现时，同步检查 Xray Panel 的 `vendor/xray-script/`、`agent/bridge.sh` 和 `shared/config.mjs`。同步副本时保留 Panel 安装器的 `PANEL_UNATTENDED` 分支，并在 Panel 来源记录中注明 Script 提交。

## 本地测试

在 Linux x86_64 或 WSL 中使用 Bash、Git、Python 3.12、jq、ShellCheck、unzip 及 util-linux（`flock`）。使用独立 Python 虚拟环境。以下测试用临时目录、模拟服务及防火墙运行，可在没有生产节点凭据的环境中执行。

```bash
python -m pip install -r tests/requirements.txt
git ls-files -z -- '*.sh' | xargs -0 -n1 bash -n
git ls-files -z -- '*.sh' | xargs -0 shellcheck -S error
python -m unittest discover -s tests -p '*_checks.py'
python tests/fetch_tools.py
XRAY_TEST_BIN="$PWD/.test-tools/v26.3.27/xray" \
MIHOMO_TEST_BIN="$PWD/.test-tools/mihomo" bash tests/regression.sh
```

`fetch_tools.py` 从官方 Release 校验下载。Xray 固定为 26.3.27，Mihomo 每次查询最新正式版。排查回归时保留 `.test-tools/runtimes.json`，其中记录实际版本与二进制 SHA-256。GitHub API 限流时可为该步骤提供只读 `GITHUB_TOKEN`。`tests/mihomo_ab.py` 和其他线路测量工具用于受控实验，结果受网络路径和运行环境影响。

## CI 与发布

`Validate and release` 在 `main` 推送、PR 和手动触发时运行。CI 检查所有受 Git 跟踪的 Bash 文件，并从当前提交的 `install.sh`、`xray.sh`、`update_geodata.sh`、`src/`、`README.md` 和 `image.png` 生成 `code.zip`。回归从解压目录运行，测试工具与归档分开。CI 缓存固定 Xray 和 geodata，继续现场解析 Mihomo 正式版。同一 PR 的新提交可以取消旧验证。

只有 `main` 推送通过验证才进入发布队列，发布时使用已验证的 `code.zip`。更新版本时修改 `xray.sh` 的 `is_sh_ver`（格式 `vX.Y.Z`）。已有同名 Release 会跳过创建，旧版本的同名 Git tag 指向不同提交时发布失败。只保留最近三份正式 Release，Git tag 继续保留。手动触发用于验证。

本地检查待发布提交的归档成员和完整性：

```bash
git archive --format=zip -9 -o code.zip HEAD -- install.sh xray.sh update_geodata.sh src README.md image.png
unzip -tq code.zip
unzip -Z -1 code.zip
```

## 历史回归与排查

| 现象 | 维护约束和现有回归 |
| --- | --- |
| 同端口双栈连接进入错误的 REALITY SNI | IPv4 绑定路由源地址，IPv6 使用 IPv6-only。`tests/listener_checks.sh` 检查监听地址族，`tests/regression.sh` 检查旧配置迁移和高级参数保留。见[故障记录](xhttp-delay-investigation-2026-10-17.md)。 |
| IPv6 防火墙更新失败后 IPv4 已切换，或者重启失败 | `config_transaction` 负责回滚文件、服务与两栈规则。`tests/regression.sh` 注入失败并检查原配置、第三方规则及真实 `flock`。实际 LXC 防火墙权限降级需在目标环境验收。 |
| 多节点共用内部 XHTTP，或中继回退绕过私网拒绝 | schema v3 隔离内部入口，私网规则应早于普通路由和中继回退。`tests/audit_checks.sh` 验证多入口迁移，`tests/regression.sh` 检查私网规则顺序。 |
| NAT 公开入口挂上 Vision 后 HTTPS 异常 | schema v4 移除公开入口的旧 `flow`，保留互联入口 Vision 和公开入口随机加密/零 RTT。`tests/regression.sh` 与 `tests/check_exports.py` 检查迁移幂等性与客户端导出。真机升级顺序见 [Panel 的分路记录](https://github.com/Chen017/Xray-Panel/blob/HEAD/docs/nat-entry-review-2026-11-05.md)。 |

核心解析失败时先检查归档内版本、`XRAY_LOCATION_ASSET` 对应的 geodata 和完整配置。线上先用 `xray` 的配置校验和日志菜单定位，再检查 `systemctl status xray`。Panel 管理的节点经 Script 手动修改后，先导入当前配置并检查待部署差异，避免覆盖外部修改。
