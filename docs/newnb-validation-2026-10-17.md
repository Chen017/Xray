# NewNB 实测与 Beta 验证

2026-10-17。只操作用户授权的日本 NewNB，未连接或修改其他服务器。服务器 Xray 26.3.27，本机 Mihomo 1.19.32。用户更正可达上限约为 800 Mbps，不能再以千兆为验收目标。

## 真实线路结果

用户在相同 IPA CyberLab 400G 东京节点、Single 单连接模式手动测速。浏览器安全策略阻止代理自动操作 Speedtest，因此没有绕过限制；网页启动和截图由用户完成，其余配置切换、备份、采样和恢复自动完成。

| 对照 | 网页证据 | 服务器采样（高流量的约 16 个一秒区间） |
|---|---|---|
| 原 XHTTP 双栈分离 | 下载完成值 432.47 Mbps，ping 77 ms；Komari 截图 CPU 47.8% | 整机 busy 平均约 45.4%，Xray 线程合计约 39.5%，最忙线程约 26.6%，steal 约 0.2% |
| 临时 Vision | 测试进行中截图 757.21 Mbps；用户确认实际极限约 800 Mbps。没有取得最终下载完成值 | 整机 busy 平均约 21.3%，Xray 线程合计约 7.0%，最忙线程约 6.0%，steal 约 0.5%；网卡一秒发送峰值约 875 Mbps |

系统实际暴露 1 个 logical CPU，Xray 服务 CPUQuotaPerSecUSec 为 infinity。采样来自 `/proc/stat`、`/proc/PID/task/TID/stat`、`/proc/net/dev` 和进程所在 cgroup 的可用 CPU 字段。各来源计时口径和采样边界不同，不能将进程 CPU、softirq 等百分比直接相加。网卡速率包含协议开销，也不是 Speedtest 应用层成绩。

这批最初的数据**不支持服务端某个线程持续占满唯一逻辑 CPU 的解释**；XHTTP 的处理成本明显高于 Vision，但没有观察到服务器 CPU 饱和。随后增加了下述自动交错和窗口实验。Windows 客户端线程枚举未取得有效数据，以不可用记录，不能把它显示成 CPU 为零。

Mihomo 对应的 `metacubex/http v0.1.8` 默认 H2 单流接收窗口为 4 MiB。以 77 ms 作为粗略延迟量级，`4 MiB × 8 / 0.077 s ≈ 436 Mbps`。最初这只是量级吻合，Speedtest ping 不是已测得的外层 H2 RTT。随后用真正只改窗口的构建进行了因果对照，见下文；没有编造 YAML 缓冲区字段。

来源：[Mihomo HTTP 依赖默认 H2 窗口](https://github.com/MetaCubeX/http/blob/v0.1.8/h2_bundle.go#L6933-L6941)。

## 用户返回后的 IPA 单连接验收

2026-10-17 14:57–15:05（Asia/Singapore）附近，用户继续在同一 IPA CyberLab 400G Tokyo、Single 场景手动测试；每个方案一次，下载结果均已取得最终值。

| 客户端方案 | 最终下载 | 空闲 Ping | 下载负载延迟 |
|---|---:|---:|---:|
| 官方 Mihomo 原始 XHTTP，4 MiB | 456.35 Mbps | 73 ms | 74 ms |
| 临时诊断客户端，8 MiB | 722 Mbps（用户文字确认） | 截图时 74 ms | 截图时 78 ms；没有最终值 |
| 临时诊断客户端，16 MiB | 777.00 Mbps | 79 ms | 140 ms |

8 MiB 比本轮基线提高约 58%，16 MiB 比基线提高约 70%，但只比 8 MiB 高约 7.6%。这进一步验证了窗口方向在实际 IPA 场景的收益。8 MiB 截图中的实时 725.09 Mbps 未冒充最终值；它的最终成绩以用户随后确认的 722 Mbps 为准。Speedtest 的下载负载延迟与下文合成短请求 p95 是不同指标，不能混为一谈。

原始方案直接使用日常官方核心；两个候选通过 localhost SOCKS 接入隔离的诊断核心，再经相同的本地直连桥连接 NewNB，避免 TUN 重复代理。XMUX、两端 REALITY、TLS 指纹、padding、路径和服务端均未改；两个候选之间只改变窗口，但原始方案与候选的本地进程拓扑不同。严格的单变量因果依据仍是下文同编译器、同桥接的 4/16 MiB 交错实验，不能把本轮三次测速当成严格统计验证。

本轮 NewNB 仍为 1 个 logical CPU，Xray 26.3.27。按非 loopback 网卡速率超过 100 Mbps 的一秒区间筛选，原始、8 MiB、16 MiB 分别取得 31、30、15 个活跃样本；Xray 线程合计平均约 40.4%、49.0%、49.0%，最忙线程平均约 26.4%、36.2%、41.9%。steal 平均约 1.4%、15.0%、9.0%，提示共享主机调度波动也是本轮比较的限制，不把差值都归因于窗口，也没有观察到最忙线程平均占满唯一逻辑 CPU。百分比采用一核为 100% 的口径。

验收结束已核对原 Self-Host 订阅逐字节未变，所有选择组恢复，香港主节点与美国 AI/Antigravity 分流保持原选择；诊断核心和远端采样进程均已停止。生产服务运行 PID 为 38021，启动于 04:04:16 UTC，早于本轮约 06:57 UTC 的测试；本轮未重启服务、安装核心或修改服务端配置。

**决策仍是保留原默认。**若今后官方提供窗口选项，8 MiB 可作为优先评估日常取舍的候选，16 MiB 作为吞吐对照；当前单次结果不足以宣布 8 MiB 在所有日常场景最佳。最新官方 Mihomo 的 YAML 尚无该选项，不能仅靠修改脚本导出或服务端参数兑现本轮提升，也不将诊断二进制替换为日常核心。

## 窗口因果对照

为避免反复要求用户手动测速，在 NewNB 临时启动只提供有界随机字节的 HTTPS 数据源，校验证书，限制为服务器自身来源和随机令牌；数据源不提供目录或转发，测试后停止并删除临时证书。它不代表 IPA 的绝对成绩，只用来比较同线路、同目标下的受控变化。通过独立 localhost listener 或临时客户端进入 NewNB，香港主节点和美国 AI 分组保持原选择。

同参数客户端交错测试中，官方 Mihomo 1.19.32 为 411、400 Mbps，官方 Xray 26.3.27 为 402、403 Mbps。两者使用相同的 localhost SOCKS 直连桥，避免临时客户端被主 TUN 再次代理。桥仅在临时副本中对 NewNB 的两个 REALITY SNI 跳过目的地址改写，否则主 sniffer 会把指定 IP 改成伪装站地址；日常配置已恢复。

随后从官方 Mihomo v1.19.32 源码构建控制组和实验组：同为官方 Go 1.26.8、`with_gvisor`、相同编译设置。实验组唯一功能差异是 `transport/xhttp/client.go` 的 `http.HTTP2Config.MaxReceiveBufferPerStream`；未改 XMUX、TLS 指纹、REALITY、padding、Referer 或路径。版本字符串明确标记 diagnostic，未替换日常核心，也未部署服务端。

| 单流 256 MiB、交错次序 | 第一次 | 第二次 |
|---|---:|---:|
| 原 4 MiB 窗口 | 405 Mbps | 418 Mbps |
| 16 MiB 窗口 | 674 Mbps | 828 Mbps |

**这提供了 H2 接收窗口限制本次单流吞吐的因果证据。**不能再只把它当算式猜测，也不能把 CPU 核数作为已证实原因。仍不宣称这是任何线路的唯一瓶颈。

为检查日常体验，再在相同 XMUX 下测试 4、8、16 MiB。四个并发 32 KiB 短请求与大下载同时进行，避免超过原下行并发范围的最小值而混入连接数变化。结果如下；吞吐有冷启动和线路波动，未用最高值代替两次结果。

| 窗口 | 单流 128 MiB，两次 Mbps | 下载时短请求 p95，两次 | 临时客户端 RSS 峰值 |
|---|---|---|---|
| 4 MiB | 362 / 422 | 172 / 172 ms | 34–38 MiB |
| 8 MiB | 541 / 723 | 234 / 219 ms | 33–38 MiB |
| 16 MiB | 573 / 763 | 313 / 391 ms | 33–38 MiB |

空闲短请求 p95 在约 172–203 ms 范围，没有显示稳定恶化。满载时大窗口使用更多带宽，短请求尾延迟上升，16 MiB 更明显。因此**不把“调到最大窗口”作为无代价的日常优化**。当前小样本只能反映这个合成负载，不能代表所有网站、大量同时大流或手机端内存表现。

正式 Mihomo 1.19.32 的 XHTTP YAML 结构没有导出这个窗口选项。临时构建是定位工具，不符合“日常只用最新官方正式版”作为长期方案的要求；没有给导出添加会被忽略的伪参数。窗口还会改变加密内的 H2 SETTINGS 和流控行为，不能承诺所有流量时序特征完全相同。保留原伪装配置并不等于证明新的窗口没有任何取舍。

## XMUX 结论

原 XMUX、较小并发范围、单栈 stream-up 和 stream-one 都实际跑过自动下载和短请求对照。仅降低并发或改成 stream-one 没有稳定突破约 400 Mbps；较小并发还出现尾延迟波动，没有据此更改日常预设。没有把 `maxConcurrency: 1` 当作单流提速方案，也没有增加 Mux.Cool。

额外复核 8 MiB 窗口、仅把下行并发从 8–16 改成 2–4：原值两次满载短请求 p95 为 219/218 ms，候选为 578/204 ms，持续下载约 716–747 Mbps 与 723–727 Mbps。候选暖态有一次轻微改善，另一次尾延迟明显变差；之前一次启动还出现握手超时。因此没有证据支持将它作为稳定的日常改进，保留原范围。随机范围会带来实际取值差异，这也是不据单次最高分改默认的理由。

直接在官方 v1.19.32 `transport/xhttp` 包上运行了无网络假传输复现：

- 有活跃请求时，已经到 `h-max-reusable-secs` 的 entry 仍会被新请求复用；Xray 26.3.27 会从候选中移除过期连接，让旧请求继续完成。
- 一次 GetTransport 后发两个 RoundTrip，Mihomo 的 h-max-request-times 预算只扣一次。对于单栈 stream-up，一条代理连接有两个 HTTP 请求，语义与 Xray 的 HTTP 请求计数不完全相同；分离模式每个方向独立取得 transport，需分别看待。

这些是核心实现语义差异，不能靠在脚本中换一组数字声称已修复。当前数值仍保留，复现代码和上游反馈草稿可供后续提交；没有擅自向上游发布问题或 PR。

来源：[Mihomo reuse.go](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/transport/xhttp/reuse.go)、[Xray 26.3.27 mux.go](https://github.com/XTLS/Xray-core/blob/v26.3.27/transport/internet/splithttp/mux.go)、[官方 XMUX 设计说明](https://github.com/XTLS/Xray-core/discussions/4113)。

## UDP 和导出

原 NewNB XHTTP 双栈配置，经本机 SOCKS UDP ASSOCIATE 连续发送三次 UDP DNS 请求，三次收到匹配事务号的响应；Mihomo 连接记录确认经过 NewNB。随后补做真正的 QUIC/UDP 443：使用官方 QUIC 库，经原 XHTTP/XUDP 参数向 Cloudflare DoH 发起 HTTP/3 查询，校验证书、协商 h3、核对 HTTP/3 200 和 DNS 事务号。首组三次为一次冷启动超时、两次成功；复核三次全部成功。代理链记录确认经过 NewNB。

这证明实际 UDP/443 和 QUIC 能工作，不能概括为“UDP 不支持”，也不等于所有浏览器和网站都始终稳定。保留现有 QUIC 尝试与 TCP 回退行为，不强制全局 QUIC，也不添加全局 UDP/443 拒绝。QUIC 嗅探与成功转发仍是独立问题。目标依据：[Cloudflare DoH 支持 HTTP/3](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/)。

只从 Mihomo 导出中移除未被读取的节点 `sockopt`、下载 `sockopt`，及下载层重复的 no-grpc/padding/session/seq 字段。实际下载配置继承主 XHTTP 配置；顶层有效的 padding、Referer、PUT、session/seq、指纹、ALPN、REALITY、TFO/MPTCP 和两套 XMUX 参数保持原值。Xray/VLESS 链接中的同名有效字段未改。

清理前后三种 Mihomo 导出逐项比较：唯一差异为上述忽略字段；六份配置都通过真实 Mihomo 解析。回归中继续保护有效字段。来源：[v1.19.32 的配置结构和下载配置复制逻辑](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/adapter/outbound/vless.go)。

## 不再手工粘贴配置的工具

`tests/mihomo_ab.py` 使用现有的 localhost 控制接口或 Windows named pipe。它只替换指定节点，其他节点和规则保持原值，其他选择组恢复原选择；正常结束、Ctrl+C 或输入关闭时自动恢复运行配置。原订阅文件不写入。强制终止进程后可用 `--restore-only` 恢复。

需要 Python 和 PyYAML；`--config` 必须指向包含 Clash Verge 覆盖项的**实际运行配置**，不只是订阅节点文件。`--controller` 使用当前已存在的本地接口，无需开放新的接口或改变安全设置。状态目录含凭据，不得提交、上传或分享；默认位于 Git 忽略的 `.test-tools/`。退出后保留备份供恢复。

```text
python tests/mihomo_ab.py --config EFFECTIVE.yaml --controller LOCAL_CONTROLLER --node EXACT_NODE_NAME --group TEST_GROUP --state-dir .test-tools/my-session
python tests/mihomo_ab.py --controller LOCAL_CONTROLLER --state-dir .test-tools/my-session --restore-only
```

默认只跑 baseline、Vision。也可显式指定 `--variants baseline,single,stream-one`。Vision 必须由同一个服务端现有入口支持；stream-one 只用于无 download-settings 的单栈候选。本次没有把 stream-one 或改 XMUX 作为默认优化。

工具已经实测正常加载、退出恢复和恢复命令。官方接口依据：[Mihomo API 文档](https://wiki.metacubex.one/api/)。仅接收用户明确指定的服务器和节点，代码中没有固化个人 IP、域名、UUID、密钥或订阅地址。

服务器采样器 `tests/collect_linux_metrics.py --pid PID --seconds 180` 可经 SSH stdin 运行，不安装 agent、不写服务端配置，stdout 输出 JSONL；默认一秒采样，最多十五分钟。它只采集指标，不启动下载或操作测速网站。

`tests/transport_capabilities.py` 不修改系统，只探测未绑定套接字。NewNB 的 TFO mask=3，客户端/服务端开关开启，TFO 和 MPTCP 本地套接字可创建；Windows 的 TFO 选项可用、系统 Fast Open 和 Fallback 已开启。但 Go 1.26.8 在非 Linux 平台的 MPTCP 会走普通 TCP，所以本机配置中的 `mptcp: true` 不能被报告为已经建立多路径。两端开关可用仍不是端到端 TFO cookie 或 MPTCP subflow 协商证明。字段保留用于兼容，不盲目改系统设置。来源：[Go 非 Linux 的 MPTCP 实现](https://github.com/golang/go/blob/go1.26.8/src/net/mptcpsock_stub.go)、[Linux TCP sysctl 文档](https://docs.kernel.org/networking/ip-sysctl.html)。

## 自动验证完成情况

- Windows 隔离完整回归通过，使用真实 Xray 26.3.27 与 Mihomo 1.19.32 解析配置。
- NewNB 上的 Linux 完整回归通过：以 nobody 账号在独立临时目录运行，服务和防火墙操作使用测试替身；真实 flock 并发写入保护也通过。测试文件已清理，生产服务未重启。
- 最新正式版刷新、旧缓存保留、摘要与固定版本策略的四项离线测试通过；Shell 语法、ShellCheck 错误级检查和 Python 编译检查通过。
- 导出清理的有效参数等价检查、真实 UDP/HTTPS 检查、临时配置加载和两种恢复路径均通过。提交内容已扫描，未包含个人配置凭据或订阅地址。
- 最终核对：Self-Host 订阅文件逐字节未变，所有选择组恢复；日常 Mihomo 仍为官方 1.19.32，TUN 保持开启，NewNB 生产 Xray 仍为原运行进程和 26.3.27。

## 状态

各轮测试结束均恢复原 XHTTP 配置、香港主节点、美国 AI 和 Antigravity 分流；Self-Host 订阅文件内容保持原样。服务端现有配置、XMUX、伪装参数和内核未改变。测试收尾时变更只在 `codex/beta` 本地分支；随后按用户要求推送了该分支，未部署服务器脚本。

用户返回后的 IPA Single 验收已完成，结果见上文。日常浏览体验未取得长期验证；日常核心仍保留官方版。用户随后明确授权个人 Fork 与上游 PR，交付如下：

- [Xray Beta](https://github.com/Chen017/Xray/tree/codex/beta) 已推送，云端回归通过；main 未修改，服务器脚本未部署。
- [官方 Mihomo PR #3331](https://github.com/MetaCubeX/mihomo/pull/3331)：新增可选 `h2-max-receive-buffer-per-stream` 字节数，默认 0 沿用库默认；支持下载层继承与覆盖。尚不代表已获上游接受。
- [个人 Fork](https://github.com/Chen017/mihomo) 的默认分支 `codex/window-builds` 维护相同补丁和定时构建。[使用与替换说明](https://github.com/Chen017/mihomo/blob/codex/window-builds/WINDOW-CORE.md)，[自动构建](https://github.com/Chen017/mihomo/actions/workflows/window-release.yml)。本地项目位于同级独立目录 `mihomo-window`。
- 个人构建显式启用时，分离节点可只在已有 `download-settings` 中设置 8388608（8 MiB）。Xray 脚本默认导出不添加该字段，继续兼容官方核心。

个人构建未自动安装到用户电脑。无需更改服务器 Xray 26.3.27、XMUX 或伪装参数。
