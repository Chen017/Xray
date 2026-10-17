# NewNB 冷连接与延迟测试失败：监听地址族隔离

2026-10-17。只对 NewNB 实机操作；香港主节点和美国 AI/Antigravity 选择保持原值。窗口功能、Mihomo 官方 PR #3331 与此修复独立。

## 已证实的本机根因

NewNB 的配置分别使用 `0.0.0.0:443`、`[::]:443`，搭配不同的 REALITY 目标与 SNI。实际运行的官方 Xray 26.3.27（与磁盘二进制 SHA256 一致）却创建了两个 IPv6 双栈通配监听器；`ss -4` 没有监听，`ss -6` 显示两个同端口监听。Xray 的监听代码使用 Go 的 `tcp` 网络及 `SO_REUSEPORT`。因此两套配置能够同时绑定，但接收范围重叠。

IPv4、IPv6 新连接都可能被分给另一套 SNI 的入口，导致 REALITY/TLS 建链失败。热连接已经选对入口后，可通过 XMUX 持续复用，所以日常网页能访问、连续暖态延迟测试也可能全部正常。这次错误不能简单归为“XHTTP 不适配延迟检测”。

依据：[固定版本的监听实现](https://github.com/XTLS/Xray-core/blob/v26.3.27/transport/internet/system_listener.go)、[IPv6-only 与端口复用实现](https://github.com/XTLS/Xray-core/blob/v26.3.27/transport/internet/sockopt_linux.go)。这些源码解释与下述真实套接字、真实核心实验相互验证；不将本结论泛化成所有 Mihomo/XHTTP 用户的唯一故障原因。

## 自动对照

| 条件 | 结果 |
|---|---|
| 原官方核心，已有 NewNB 暖态，两个 HTTPS 204 地址 | 30/30 成功 |
| 主核心内独立 NewNB 副本，冷连接 | API 15 次失败 11 次；同 URL 普通 HEAD 15 次失败 2 次 |
| 同一 NewNB 入口改用 Vision 做冷连接对照 | 20 次失败 7 次，说明故障不专属于 XHTTP 或 unified-delay |
| 隔离客户端，分离/单栈、unified-delay 开/关、并发探测 | 冷连接仍可失败，热连接和并发探测大多成功 |
| 只加日志的诊断核心 | 取得 `remote error: tls: internal error`、`io: read/write on closed pipe`；多数在约 150–500 ms 失败，不是等到 5 秒预算才超时 |
| 本地纯内存公私钥一致性检查 | Chrome、Firefox 各 200 次均无 key-share 不一致；不据此编造 TLS 密钥实现补丁 |
| 仅将 TFO 作为临时诊断变量 | 开关两组均有冷连接失败，未更改日常 TFO 默认 |

进一步在 NewNB 上运行同一个官方核心的临时实例，使用原始节点配置、原始两套 SNI/指纹/密钥/Short IDs/XMUX，经 SSH 分别进入 IPv4/IPv6 本地入口。生产服务未改。仅改变监听隔离：

| 临时服务端 | XHTTP 分离，独立冷连接 |
|---|---|
| 原 `0.0.0.0` 与 `::` 通配组合 | 40 次失败 31 次 |
| IPv4 绑定具体本地地址，IPv6 设置 `v6only: true` | **40/40 成功** |

每组另有一次预热探测，原始记录保留，但上述 40 次统计排除了预热。预热只用于避开临时实例初次目标 DNS 的影响；统计中的每次连接仍使用独立节点/transport，保持冷连接。

另做 Linux 套接字实验：原双通配组合对 IPv4、IPv6 各 50 次连接，均约一半进入错误入口。**只给 IPv6 设置 v6only 还不够**：IPv4 的双栈通配监听仍可能吸收 IPv6，结果受绑定顺序影响。因此采用具体 IPv4 地址与 IPv6-only 的组合，不修改系统全局 `bindv6only`。

## 最小修复

- 新生成节点：IPv4 使用本机默认 IPv4 路由的 `src` 地址，IPv6 使用 `::` 并设置官方 `sockopt.v6only: true`。
- NAT VPS 使用本地内网地址监听，客户端导出的公网地址保持原值；没有全局 IPv4 的主机将 IPv4 入口限制为 loopback。
- 旧配置迁移只处理本脚本拥有的 `public_<port>_v4/v6` 入口。具体手动 IPv4 监听地址保持原样；旧 IPv4 通配绑定迁到本地地址，IPv6 通配启用 v6only。
- 迁移使用已有配置事务，失败自动恢复；需要的 `ip` 命令按 apt/yum 安装对应 iproute 包。
- 两个 SNI、REALITY 密钥与 Short IDs、指纹、路径、padding、XMUX、TFO/MPTCP、路由和核心版本均保留。没有给延迟测试添加重试、延长超时或伪造 alive 状态。

监听地址使用本机接口地址；接口地址发生变更后应重新检查对应监听。多地址主机既有手动具体绑定不被迁移覆盖。

## 验证与状态

Linux 无特权完整回归通过；新增集成测试启动真实 Xray，确认分别创建 IPv4、IPv6 监听，并确认 IPv6 通配不会接受另一个 IPv4 loopback 地址的连接。迁移测试对除监听地址和 v6only 外的节点字段逐项保持等价，覆盖 NAT 地址解析和 IPv6-only 主机。

诊断核心、临时 Xray 服务、SSH 隧道均在每轮结束清理，原订阅与分组恢复。生产应用与最终验收状态会在完成后补充；本记录不把临时实例成功冒充生产已修复。
