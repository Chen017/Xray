**XHTTP 单流约 500 Mbps：低操作负担的测试方案**

2026-10-17 补充：已收到实际订阅并完成 NewNB 的 XHTTP/Vision 初次对照，用户将上限更正为约 800 Mbps。实际采用官方 API 的临时运行副本，避免重复粘贴和 TUN 二次接管；结果与可复用工具见 [实测记录](newnb-validation-2026-10-17.md)。下文保留的是测前方案与后续尚未执行的实验设计，不能视作已经完成。

更新：2026-10-17。服务端固定 Xray 26.3.27，客户端使用最新正式版 Mihomo。用户报告：同一台标称单核 VPS 的 Vision REALITY 单流可接近千兆，XHTTP 单栈和分离约 500 Mbps；Komari CPU 约 50%。旧双核 VPS 的 XHTTP 曾接近千兆。当前缺少实际客户端配置、测速工具/目标和同步 CPU/网络数据，原因尚未确定。

**测试方式：独立临时实例，一次启动，自动生成报告**

日常订阅保持原样。测试程序从用户提供的实际节点建立临时配置，启动独立 Mihomo 进程，采用独立工作目录和 localhost 监听端口。通过 `listeners[].proxy` 把不同测试端口固定到候选节点，测速程序切换 localhost 端口即可切换配置，不操作日常代理组，也不要求用户反复修改订阅。

临时实例关闭自身 TUN、规则提供器自动更新等无关功能。需要检查正在运行的主实例是否通过 TUN 再次接管临时进程的出站；仅设置临时实例 `tun.enable: false` 不足以保证没有二次代理。隔离方式根据实际平台和配置确定，只对测试进程生效，不关闭日常全局保护。

所有修改仅作用于临时副本。测试结束停止自己创建的进程、释放临时端口，输出表格、JSON/CSV 和可重复运行所需的版本/参数信息。测试不作为持续运行的产品健康检查，不新增备用线路或 Hysteria2。

来源：[Mihomo listener 的 proxy 字段](https://wiki.metacubex.one/config/inbound/listeners/)、[mixed listener](https://wiki.metacubex.one/config/inbound/listeners/mixed/)。

**第一批只定位问题，不扫描几十组参数**

| 样本 | 变化 | 可以回答的问题 |
|---|---|---|
| A：当前 Mihomo Vision | 保留现有节点 | 同时间、同目的地的线路基线 |
| B：当前 Mihomo XHTTP 单栈 stream-up | 保留全部有效原参数 | 能否在受控请求下复现 500 Mbps |
| C：Mihomo 单栈 stream-one | 只改变客户端 mode，保留 XMUX 和其它适用参数 | 不改服务端，减少一个流式 HTTP 请求后有无变化 |
| D：临时 Xray 26.3.27 客户端 XHTTP stream-up | 尽量匹配 B 的传输、安全、padding 和池策略，记录两种实现的差异 | 问题是否主要出现在 Mihomo 的实现/本机路径 |

先跑 A、B；复现后才按需要增加 C、D。XHTTP 分离模式暂不重复整套矩阵；它已有相似上限，待需要区分双栈路线时再补。每批设置总时长与总流量上限；下载数据丢弃到内存消费/空设备，不把磁盘写入速度混进结果。

采用同一 HTTPS 测试资源，核对真实出口和实际连接数。一次请求与一个 TCP 应用连接分别记录，避免把测速工具的“一个线程”误认为必然只有一个连接。必要时交错 A→B→A 复核，减少路由/服务器负载时变的干扰。

更正先前方案：Xray 26.3.27 的 XHTTP `mode: stream-up` 服务端**已经接受 stream-one 请求**，这项单栈测试不必先将服务端改成 auto。它仍可使用 XMUX；分离模式继续 stream-up。

来源：[26.3.27 hub.go 的 mode 判断](https://github.com/XTLS/Xray-core/blob/v26.3.27/transport/internet/splithttp/hub.go#L138-L142)、[原作者 2024 年设计讨论](https://github.com/XTLS/Xray-core/discussions/4113)。

本机功能验证已完成：服务端保持 stream-up，Mihomo 1.19.32 客户端 stream-up 与 stream-one 各完成 3 次 HTTP 请求，全部返回 200 和正确内容。脚本断言客户端唯一差异是 mode，padding、PUT、Referer 与 XMUX 均保留。结果保存在 `.test-tools/audit-2026-10-17/stream-one-results.json`。这仅证明 Windows loopback 互通，不证明真实线路的吞吐或日常延迟改善。

**每批自动记录什么**

| 观察对象 | 指标 |
|---|---|
| 大下载 | 真正单应用连接的持续吞吐、失败/重连、连接数 |
| 日常加载近似 | 冷连接与复用连接分别测首字节、短请求完成时间；小规模并发请求的 p50/p95、失败率 |
| 下载与日常使用同时发生 | 大下载时，小请求是否明显变慢或失败 |
| 客户端 | Mihomo/Xray 进程与线程 CPU、内存、本机 CPU 是否受限 |
| 服务端 | Xray 各线程 CPU、各 logical CPU、softirq、steal、内存及连接数 |
| VPS 资源约束 | 可见 logical CPU 数、affinity、CPU cgroup 配额及 throttling；指标不可读时标记未知 |
| 网络 | 本机到入口的 RTT、TCP 重传/窗口信息；是否中继及两段路径 |

采集优先使用只读 `/proc` 和 cgroup 信息，或现成的 pidstat/mpstat/ss。若没有现成 SSH 连接，可由用户一次启动限时采集器；不要求边测速边截图或手抄占用率。未取得服务器访问方式前，不把这部分称为已经完成。

Mihomo API 的 delay 端点只是一种 HTTP 延迟测试，不能替代吞吐与日常加载实验；`unified-delay` 会处理握手差异，也不能直接拿它的显示值代表真实冷启动体验。小请求实验是近似，不能声称覆盖完整浏览器页面的渲染、缓存和所有应用。

来源：[Mihomo API](https://wiki.metacubex.one/api/)、[unified-delay](https://wiki.metacubex.one/en/config/general/#unified-delay)、[Linux cgroup v2 CPU 指标](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html#cpu-interface-files)。

**当前几个解释需要同时保留**

1. **CPU/调度约束仍是候选，但 50% 不能直接定案。** Komari 当前官方 agent 调用 `cpu.Percent(0, false)` 上报整机占用。若 VPS 实际只有一个 logical CPU 且 50% 是稳定测试区间的准确平均值，单个线程持续跑满唯一 CPU 不能单独解释它。应核对实际核心数、采样时间、steal、配额，以及本机客户端。旧 VPS 的 CPU 型号、RTT、供应商配额等也可能不同，不能只归因于核数。
2. **Vision 和 XHTTP 的单位流量开销不同。** Vision 在适合的 TLS 流量上可以使用 direct copy/splice；XHTTP 保留 HTTP/2 framing 与外层加解密。本项目还经过 RAW REALITY → VLESS fallback → Unix socket → XHTTP。Vision 千兆不能证明 XHTTP 不存在 CPU 或转发开销问题。
3. **H2 流控与读取背压也可能影响单流。** 所查 Mihomo 1.19.32 的 HTTP 依赖默认单 stream 接收窗口为 4 MiB；用窗口/RTT 做量级估算，4 MiB、约 67 ms 对应约 500 Mbps。这个数值只是说明另一种可能，不能把公式当成实际固定上限，更不能据此宣称已定位。需要结合 RTT、WINDOW_UPDATE/背压和实现对照判断；不添加文档未支持的窗口参数。

来源：[Komari 官方 CPU 采集](https://github.com/komari-monitor/komari-agent/blob/main/monitoring/unit/cpu.go)、[26.3.27 VLESS 的 flow 路径](https://github.com/XTLS/Xray-core/blob/v26.3.27/proxy/vless/inbound/inbound.go#L522-L565)、[direct copy/splice](https://github.com/XTLS/Xray-core/blob/v26.3.27/proxy/proxy.go#L680-L737)、[Mihomo XHTTP transport](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/transport/xhttp/client.go)、[该 HTTP 依赖的默认窗口](https://github.com/MetaCubeX/http/blob/v0.1.8/h2_bundle.go)。用户实际部署的 Komari 版本和采样口径尚未确认。

**保护日常体验与既有设计**

- XHTTP 的 XMUX、通用 Mux.Cool、Mihomo smux 分开讨论。用户口述的 SMUX 对应哪个字段，等实际订阅确定。
- `maxConcurrency` 决定多个独立代理连接如何共享 H2/H3 底层连接，不把一个下载拆成多条 TCP 连接。原帖“设为 1 方便测速”的说明针对多线程测试，不能直接用于修复真实单流上限。
- 默认保留现有上/下行复用范围、连接轮换、padding、请求方法、SNI、指纹和 ALPN。固定连接数、关闭复用、放大 buffer 只在确有诊断需要时单独评估，不作为自动默认修复。
- TFO 优先影响建连时延，不是长时间持续下载从 500 到 1000 Mbps 的直接解释。MPTCP 也不是自动增加 CPU 核心利用的开关。
- 候选必须满足日常短请求延迟、并发加载和失败率没有可重复的实质恶化。吞吐单独提高不算验收通过。结论不清楚就保留基线。

来源：[原作者 XMUX 说明](https://github.com/XTLS/Xray-core/discussions/4113)、[26.3.27 池分配逻辑](https://github.com/XTLS/Xray-core/blob/v26.3.27/transport/internet/splithttp/mux.go)、[TFO RFC 7413](https://www.rfc-editor.org/rfc/rfc7413.html)。

**导出字段清理单独验收**

只清理最新正式版解析结构明确没有读取的字段，并比较清理前后的有效参数、继承关系和本机功能测试。保留：上行全部有效混淆/padding，独立下行 reuse-settings，Chrome/Firefox、ALPN、host/path、REALITY 参数，顶层 tfo/mptcp。下行中未开放的重复 padding/session 等字段不能误删它们实际继承的上行值。

这属于等价清理，不需要要求用户进行多轮真实线路测速来证明“变快”；也不以 `mihomo -t` 通过作为所有字段有效的证据。随机 TLS/padding 不要求逐字节抓包一致。

来源：[Mihomo 下行字段](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/adapter/outbound/vless.go#L130-L153)、[下行复制与覆盖](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/adapter/outbound/vless.go#L811-L827)、[顶层 TFO/MPTCP](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/adapter/outbound/base.go#L193-L207)。

**等待实际配置后再处理 UDP**

保留现有 UDP/443 行为，待实际订阅到来后核对 TUN/嗅探/DNS 的具体字段、规则命中、节点 UDP 支持、中继 flow、QUIC 是否代理或直连。口述的 Showtime/QUIC 尝试不直接映射为某个开关。QUIC 嗅探、DNS 优先 H3 与实际 UDP 转发属于不同层次，需按配置确认。不会先批量屏蔽 QUIC 或引入另一协议。

本文件是可执行测试流程的设计与诊断依据。独立真实线路测试器还需要实际订阅、测试目标和服务器采集方式；当前没有完成真实 500 Mbps 瓶颈定位，也没有证明任何性能参数应当更改。
