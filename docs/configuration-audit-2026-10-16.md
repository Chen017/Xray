**Xray 服务端与客户端配置更新调研，2026-10-16**

当前实施前提已调整为“Xray 固定 26.3.27、Mihomo 跟随最新正式版”。新的优化与功能清单见 [固定版本优化方案](optimization-plan-xray-26.3.27.md)；下文保留跨版本调研和历史测试依据。

审查对象：本地 `Xray` 仓库，HEAD `cc104c7`，脚本 v2.7.7。重点读取 `src/node.jq`、`src/export.sh`、`src/core.sh`、`src/runtime.sh`、`src/diagnostics.sh`、`src/download.sh`、`src/firewall.sh` 及现有导出测试。初次调研仅新增文档；2026-10-17 的版本锁定等后续改动以当前优化范围及 Beta 分支为准。

结论：现有 VLESS + REALITY + XHTTP 方案仍有保留价值。更新的第一优先级是核心版本与客户端能力匹配、UDP/443 策略一致性、无效字段清理。新 UDP 传输和更多混淆参数应作为可选方案，有测量结果后再考虑默认开启。

证据分为三类：已读取的官方文档/源码；本机实际互通测试；需要真实网络实验验证的优化建议。后两类不会混为一谈。

**1. 先明确版本与客户端名称**

截至核查日，GitHub API 的 Xray `releases/latest` 返回 **v26.3.27，stable**；发布列表顶部是 **v26.10.10，pre-release**。本项目安装器以及 `get_latest_version()` 跟随前者，并明确过滤 pre-release。因此，“已经更新到最新”不代表获得了 2026 年下半年所有功能。

来源：[Xray stable API](https://api.github.com/repos/XTLS/Xray-core/releases/latest)、[发布列表](https://github.com/XTLS/Xray-core/releases)。本地对应 `src/download.sh:3`、`install.sh` 的核心下载逻辑。

本次检查的 Mihomo 是 **v1.19.32**；v2rayN 当前 release 是 **7.25.6**。它们是不同层次：Mihomo 是内核，v2rayN 是可以调用不同内核的客户端。“Clash 配置”在本项目实际指 Mihomo 的 YAML；“V2Ray 客户端”需要明确为 v2rayN + Xray-core。不能把原版 Clash、V2Fly v2ray-core、Mihomo、Xray 当作支持相同字段的同一个实现。

来源：[Mihomo 发布列表](https://github.com/MetaCubeX/mihomo/releases)、[v2rayN 7.25.6](https://github.com/2dust/v2rayN/releases/tag/7.25.6)、[V2Fly VLESS 文档](https://www.v2fly.org/config/protocols/vless.html)。

建议保存“服务端核心版本 + 客户端内核版本 + 导出模板版本”，提供 stable 与经过验证的 pre-release 两条更新渠道。升级前保留上一核心、配置和客户端导出；解析通过以后仍要做实际连接测试。不要把自动跟随所有 pre-release 作为兼容性问题的修复。

**2. 已复现的高优先级问题：新 REALITY 与当前 Mihomo 导出不匹配**

当前 `src/export.sh:149` 等位置的 `reality-opts` 只包含 `public-key`、`short-id`。Mihomo v1.19.32 默认会从 ClientHello 中移除 X25519MLKEM768；需要显式设置 `support-x25519mlkem768: true` 才保留它。

Xray v26.10.10 使用 `xtls/reality` 的 `8cdf7bf9c7f0`。该实现要求 ClientHello 的 key share 中有 X25519MLKEM768，且它位于可选 X25519 之前。缺失时不能通过 REALITY 认证。

来源：[Mihomo REALITY 参数](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/adapter/outbound/reality.go)、[Mihomo 实际握手逻辑](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/component/tls/reality.go)、[Xray v26.10.10 依赖](https://github.com/XTLS/Xray-core/blob/v26.10.10/go.mod)、[该 REALITY 实现](https://github.com/XTLS/REALITY/blob/8cdf7bf9c7f0/tls.go)。

还有第二个独立问题：该版 Mihomo 使用 MetaCubeX/utls v1.8.8，`HelloFirefox_Auto` 实际指向 `HelloFirefox_120`。本项目下行固定 `client-fingerprint: firefox`，因此仅增加 MLKEM 开关还不能修好分离模式；这个 Firefox 模板本身没有所需的 key share。

来源：[Mihomo 依赖版本](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/go.mod)、[utls v1.8.8 指纹定义](https://github.com/MetaCubeX/utls/blob/v1.8.8/u_common.go)。

本机实际结果如下，客户端均为 Mihomo 1.19.32：

| 服务端 | 客户端设置 | Vision | XHTTP 单栈 | XHTTP 分离 |
|---|---|---|---|---|
| Xray 26.3.27 | 当前导出原样 | 成功 | 成功 | 成功 |
| Xray 26.10.10 | 当前导出原样 | 失败 | 失败 | 失败 |
| Xray 26.10.10 | 各 REALITY 段增加 MLKEM 开关 | 成功 | 成功 | 失败，Firefox 下行认证失败 |
| Xray 26.10.10 | MLKEM 开关 + 下行改为 Chrome | — | — | 成功 |

因此，对**本次验证过的组合**，现代导出的候选修复是：上行和下行 `reality-opts` 都增加开关，并将下行切换到支持现代握手的指纹；本次验证的是 Chrome。这个结论不能外推到所有历史核心、所有客户端版本。

```yaml
client-fingerprint: chrome
reality-opts:
  public-key: <原有公钥>
  short-id: <原有 short-id>
  support-x25519mlkem768: true
```

还需要正视上游支持边界：Mihomo 官方 TLS 文档明确表示不承诺 Xray v26.7.11+ 的 REALITY 兼容性。本次成功是限定版本的实验结果，不能写成官方兼容保证。v26.10.10 源码中，曾经默认设置 `minClientVer: 26.3.27` 的代码已被注释；不要把更早的提交直接当作当前所有失败的原因，更不要无依据地修改服务端版本限制。

来源：[Mihomo 官方 TLS 文档](https://wiki.metacubex.one/config/proxies/tls/#reality-opts)、[Xray v26.10.10 REALITY 配置实现](https://github.com/XTLS/Xray-core/blob/v26.10.10/infra/conf/transport_security.go)。

**3. UDP：先统一行为，再决定是否增加新传输**

当前 `udp: true`、`packet-encoding: xudp` 是有实际价值的，应保留。它们表示代理可以转发 UDP，并不表示客户端与服务器之间使用原生 UDP。项目当前的 XHTTP + REALITY 走 HTTP/2/TCP，RAW + Vision 也走 TCP；其中承载的 UDP 仍可能受 TCP 丢包重传和队头阻塞影响。

本次 SOCKS5 UDP ASSOCIATE + 本机 UDP echo 的结果：

| 客户端与配置 | 普通 UDP echo | UDP/443 echo |
|---|---|---|
| Mihomo 当前 Vision 导出，服务端 26.3.27 | 成功 | 成功 |
| Mihomo 当前 XHTTP 单栈/分离，服务端 26.3.27 | 成功 | 成功 |
| Xray 26.3.27，当前链接的 `xtls-rprx-vision` | 成功 | 被拒绝 |
| Xray 26.3.27，客户端 flow 改为 `xtls-rprx-vision-udp443` | 成功 | 成功 |
| Mihomo，按上节修复后连接 26.10.10，三种模式 | 成功 | 成功 |

这与 Mihomo 官方文档相符：其 `xtls-*` 相当于 Xray 的 `xtls-*-udp443`。所以当前 YAML 与链接的 Vision 行为并不一致。网站是否使用 QUIC，会随客户端而变化。

来源：[Mihomo VLESS 文档](https://wiki.metacubex.one/config/proxies/vless/)、[Xray v26.3.27 VLESS 出站实现](https://github.com/XTLS/Xray-core/blob/v26.3.27/proxy/vless/outbound/outbound.go)。

建议把 UDP/443 设计成明确选项：

- 允许：Xray 客户端按所选流控与 Mux 设置放行；Mihomo 同步允许。
- 拒绝：Mihomo 完整配置中增加 `AND,((NETWORK,UDP),(DST-PORT,443)),REJECT`，放在宽泛放行规则之前；Xray 同步设置对应策略。节点片段本身不足以携带完整规则策略。
- 不假定拒绝 UDP/443 后所有应用都会回退；浏览器通常可以回退 TCP，某些应用不一定可以。

Xray 的 `mux.xudpProxyUDP443` 与 Vision 的 flow 是不同配置层，应根据实际是否经过 Mux 分别处理。XHTTP 的 XMUX、XUDP、Mux.Cool TCP 复用、Mihomo smux 也不能混为一谈；不要为了“开启 XUDP”就给 XHTTP 随意叠加 TCP Mux 或 sing-mux。

来源：[Xray Mux/XUDP 文档](https://xtls.github.io/config/outbound.html#muxobject)。

2026 年确实有值得关注的新 UDP 功能：

| 功能 | 与本项目的关系 | 建议 |
|---|---|---|
| Xray TUN 的 UDP FullCone 与 XUDP UoT Migration | v26.1.23 新增的是 Xray 客户端 TUN 能力；本项目服务端没有 TUN，Mihomo 的 TUN 也不是它 | 在实际 Xray 客户端接管游戏/语音流量时测试；不是给服务端补一个 `fullcone: true` |
| XHTTP/3 + QUIC | 可以改变底层传输；当前 REALITY H2 配置不能只把 ALPN 改成 h3 | 新建 TLS + H3 入口，准备证书、域名及 UDP 端口；单独测试和回退 |
| Xray Hysteria2 | v26.1.23 增加出站/传输层，v26.3.27 增加入站；适合作为原生 UDP 场景的候选入口 | 有游戏、语音、丢包线路需求时增加可选节点，不替换现有默认入口 |
| Finalmask、Salamander、UDP hop、QUIC 拥塞控制 | 部分已在 stable 中；各变体的客户端和分享支持不同 | 单独核对能力和格式，不向所有 Mihomo/Xray 导出自动添加 `fm` |

来源：[v26.1.23 更新说明](https://github.com/XTLS/Xray-core/releases/tag/v26.1.23)、[TUN FullCone PR #5509](https://github.com/XTLS/Xray-core/pull/5509)、[v26.3.27 更新说明](https://github.com/XTLS/Xray-core/releases/tag/v26.3.27)、[Finalmask 文档](https://xtls.github.io/config/transports/finalmask.html)。

本次 UDP echo 只证明测试组合能正确转发小数据报；没有验证 FullCone NAT、长时间端口保持、网络切换迁移、吞吐或真实网络抗丢包能力。

**4. 应清理或重新映射的字段**

| 本项目位置/字段 | 实际情况 | 建议 |
|---|---|---|
| Mihomo 顶层 `tfo`、`mptcp` | 是其真实通用字段 | 是否开启仍需平台和对端能力判断 |
| Mihomo 节点及下行的 `sockopt.tcp-fast-open/tcp-no-delay/tcp-mptcp` | 该版 `BasicOption`、`VlessOption`、`XHTTPDownloadSettings` 没有这些字段 | 删除无效块，不能把 YAML 解析成功视为这些开关生效 |
| Mihomo 下行内重复的 padding、session、seq、no-grpc-header | 该版下行结构只开放少数 XHTTP 字段，其余从上行配置复制 | 清理无效重复项；未来需要下行独立参数时先确认内核已开放对应字段 |
| Xray 服务端 `xhttpSettings.xmux` | XMUX 在客户端选择底层连接；不是服务端吞吐开关 | 从服务端模板移除误导性设置，放入客户端配置 |
| Xray 服务端 `noGRPCHeader` | 控制客户端上传请求头 | 服务端不必重复写 |
| 链接 extra 中 `noSSEHeader`、`scStreamUpServerSecs` | 两项是服务端行为；写进客户端不会远程改变服务端 | 在服务端集中配置；客户端 extra 清理掉无效项 |
| `serverMaxHeaderBytes` | README 列出，但当前 `node.jq` 并未显式设置 | 修正文档；若需要限额，先测正常请求和 padding 后再定值 |
| `sessionPlacement/sessionKey` | stable 26.3.27 仍用此拼写；26.10.10 使用 `sessionIDPlacement/sessionIDKey`，并有 table/length | 按版本映射。当前值都是默认 `path`，因此未直接导致现有测试失败；若以后改 cookie/header，不能继续复制旧字段名 |

来源：[Mihomo BasicOption](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/adapter/outbound/base.go)、[Mihomo VLESS/XHTTP 结构及下行复制逻辑](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/adapter/outbound/vless.go)、[XHTTP 原作者参数作用域说明](https://github.com/XTLS/Xray-core/discussions/4113)、[Xray stable 配置定义](https://github.com/XTLS/Xray-core/blob/v26.3.27/infra/conf/transport_internet.go)、[Xray 26.10.10 配置定义](https://github.com/XTLS/Xray-core/blob/v26.10.10/infra/conf/transport_method.go)。

Xray 的 `dest`/`target`、客户端 `publicKey`/`password` 当前仍有兼容别名，不能仅因文档换名就断言旧配置坏了。项目把公钥保存在服务端 JSON 还承担了导出元数据的作用；清理服务端字段时要同时迁移导出读取逻辑。

来源：[REALITY 文档](https://xtls.github.io/config/transports/reality.html)、[配置兼容别名实现](https://github.com/XTLS/Xray-core/blob/v26.10.10/infra/conf/transport_security.go)。

**5. 伪装与性能中值得做、但不能宣称已经优化成功的事情**

第一，补齐 SNI 诊断。当前 `_check_sni_status()` 只看 `curl` 成功和日志中出现 `TLSv1.3`，没有确认协商出的 HTTP 版本为 h2，也没有检查现代 key exchange；但 README 和警告文案把结果描述为 TLS1.3/h2 安全自检。应分别报告证书、TLS、ALPN、key exchange、可达性。可以利用相应版本的 `xray tls ping` 辅助核对；按实际目标连接路径测试，不把入口 IPv6 与 target 必须走 IPv6 混为一谈。ASN/CDN 检测只能作线索，不能作为“安全域名认证”。

第二，默认优先 443；8443 只是端口冲突时的兼容备选。Xray 26.3.27 已对 REALITY 非 443 端口及部分 Apple target 给出警告，不能继续把 443 和 8443 描述成相同伪装等级。本次调研没有从真实服务器测量 `hahuma.com`、`dodoshort.com`，不对它们当前质量下结论。

来源：[REALITY 参数及 target 探测](https://xtls.github.io/config/transports/reality.html)、[26.3.27 的 REALITY 更新](https://github.com/XTLS/Xray-core/releases/tag/v26.3.27)。

第三，保留合理 padding，避免盲目加量。当前 `100-1000`、`tokenish`、混淆模式并非无效；是否需要更多字节或把 session 移到 cookie/header，应同时评估数据开销、代理中间件兼容性和连接成功率。HTTP 字段藏在加密连接里，其外部可见效果主要通过握手、长度、时序等体现；换一个 Header 名字本身不能证明更难识别。

第四，重新实测 XMUX。项目显式设置上行 `maxConcurrency: 16-32`、下行 `8-16`。Xray 源码的空配置默认已经变化：26.3.27 是 `maxConcurrency: 1`，26.10.10 是 `maxConnections: 3`。这些是不同连接池策略，不能把旧示例或新默认直接称为最优。可比较现有策略与固定少量连接策略，记录 p95 延迟、单流/多流吞吐、CPU、内存和连接数。`maxConnections` 与 `maxConcurrency` 不能同时配置为正值。

第五，保留双栈分离作为选项。它能利用不同方向的线路，也增加了两个入口均需可用的条件。在手机或 IPv6 不稳定网络上，应有单栈备用入口。实际测首包、上下行吞吐、失败率，不能只凭两个 IP 栈和两种指纹就宣称“最大化伪装”。本次分离模式测试使用同一台本机的两个逻辑端点，没有测真实 IPv4/IPv6 链路。

第六，为单栈 direct REALITY 场景测试 `stream-one`。2026-10-17 更正：Xray 26.3.27 的 `stream-up` 服务端已接受 `stream-one` 请求，无需先改服务端为 `auto`；可以只调整临时单栈客户端，分离客户端继续 `stream-up`。这是减少流式请求开销的候选项，尚无本项目吞吐实测。[该版 mode 判断](https://github.com/XTLS/Xray-core/blob/v26.3.27/transport/internet/splithttp/hub.go#L138-L142)

来源：[XMUX 与模式定义，stable](https://github.com/XTLS/Xray-core/blob/v26.3.27/infra/conf/transport_internet.go)、[现代 XMUX 定义](https://github.com/XTLS/Xray-core/blob/v26.10.10/infra/conf/transport_method.go)、[Xray 模式/HTTP 版本选择](https://github.com/XTLS/Xray-core/blob/v26.10.10/transport/internet/splithttp/dialer.go)、[Mihomo 模式选择](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/transport/xhttp/config.go)。

第七，指纹与 Header 需要一起看。只设置 `client-fingerprint: firefox` 并不能让 HTTP 栈整体成为 Firefox；两种内核的 HTTP 默认 Header 也有自身逻辑。如果将来恢复 Firefox，下行 HTTP Header 的选择也应检查。不要把自定义 UA、ALPN、uTLS 和真实浏览器网络行为等同。

来源：[Mihomo XHTTP Header 生成](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/transport/xhttp/browser.go)。

第八，TFO、MPTCP 应做能力检测。当前客户端开 MPTCP，服务端监听的 sockopt 没有 `tcpMptcp`，不能据此声称已经建立多路径连接；MPTCP 也不是现有 IPv4/IPv6 XHTTP 分离的实现方式。TFO 同样依赖操作系统、应用和中间网络。已有 BBR 可保留；不建议为此默认更换系统内核，或凭空增加巨大 socket buffer。

来源：[Linux MPTCP 文档](https://docs.kernel.org/networking/mptcp.html)、[Xray Sockopt 文档](https://xtls.github.io/config/transports/sockopt.html)。

**6. VLESS Encryption 中继：已有实现，但“后量子”需要分层说明**

项目已经在内部 RAW + Vision 中继使用 VLESS Encryption；它不是尚未引入的新功能。`relay_generate_vlessenc()` 明确选择 `Authentication: X25519`，忽略命令同时输出的 ML-KEM-768 身份认证方案。

应区分内容密钥交换的后量子性质与静态身份认证的后量子性质。当前选择并不等于整条中继拥有完整的后量子身份认证。若需求成立，可以增加 ML-KEM-768 authentication 选项，重建成对参数并更新两端，测试导入、重连与回滚；不要混用两组不同 authentication 的加解密参数。

`native`、0-RTT/ticket、padding 等同样是有代价的设计选择。现有 RAW + `security: none` 的链路由 VLESS Encryption 提供加密，但“有加密”不等于“具有普通 HTTPS 的外观”。若该段也经过需要伪装的网络，应单独评估其传输安全层和外观。客户端到线路机的 REALITY、线路机到落地机的 Encryption 是两段不同的配置。

来源：[VLESS Encryption 原始 PR](https://github.com/XTLS/Xray-core/pull/5067)、[当前 vlessenc 生成命令](https://github.com/XTLS/Xray-core/blob/v26.10.10/main/commands/all/vlessenc.go)、[VLESS 客户端参数](https://xtls.github.io/config/outbounds/vless.html)。

REALITY 的 ML-DSA 认证、VLESS Encryption 的 ML-KEM authentication、TLS 的 X25519MLKEM768 key exchange 也是三种不同机制。不能为了添加“后量子”标签就统一打开；要先核对客户端字段及双方版本支持。

**7. 新版 Freedom 的安全策略也要纳入升级检查**

较新 pre-release 的 Freedom 支持 `finalRules`，会对 VLESS 等入站默认阻止 private 目标，并在最终解析/连接阶段执行检查。本次第一轮本机实验就遇到这个保护；随后只在测试配置中显式允许 `127.0.0.1/32`，才隔离出握手差异。它不是 REALITY 认证失败。

这对公网代理防止意外访问私网是有价值的变化；本项目已有 `geoip:private` 路由阻断，仍应保留和核对。若用户自定义路由想访问内网、NAT 服务或反向代理目标，升级后可能需要精确的 finalRules 例外，不能用无条件 allow 来抹掉保护。FinalRules 和普通 routing 的阶段不同，需要测试域名解析后落到 private 的情况。

来源：[Freedom 官方文档](https://xtls.github.io/config/outbounds/freedom.html)、[PR #6027](https://github.com/XTLS/Xray-core/pull/6027)、[26.10.10 实现](https://github.com/XTLS/Xray-core/blob/v26.10.10/proxy/freedom/freedom.go)。

**8. v2rayN 导入需要验证完整链路**

当前 v2rayN 7.25.6 的源码会读取 XHTTP 分享链接的 `extra`，保存 JSON，再将其写入 Xray 的 `xhttpSettings.extra`。所以本项目的 extra 分享机制仍有实现基础；不能说它已经废弃。分享链接里的 `type=tcp` 也仍用于表示 RAW，不必为追求字段新名字而直接改为 `type=raw`。

来源：[BaseFmt 的导入和导出](https://github.com/2dust/v2rayN/blob/7.25.6/v2rayN/ServiceLib/Handler/Fmt/BaseFmt.cs)、[Xray 配置生成](https://github.com/2dust/v2rayN/blob/7.25.6/v2rayN/ServiceLib/Services/CoreConfig/V2ray/V2rayOutboundService.cs)、[官方分享链接提案 #716](https://github.com/XTLS/Xray-core/discussions/716)。

但仓库当前 `tests/check_exports.py` 自己解码 URL，再手动构造 Xray JSON；它没有覆盖 v2rayN 实际导入器，也没有验证被忽略字段。应补“导入 → 保存/再次导出 → 最终核心 JSON → 实际连接”的往返检查，尤其检查 downloadSettings、extra、所选核心与全局 Mux 设置。本次未运行 v2rayN GUI，不把源码检查称为 GUI 导入测试。

分享 fragment 中的中文备注也应按提案进行 URL 编码；Mihomo 的 name 等用户可控字符串宜通过可靠序列化输出。这属于导出正确性修复，对伪装性能没有直接结论。

**9. 实施顺序与验收**

| 顺序 | 建议改动 | 验收依据 |
|---|---|---|
| P0 | 明确 stable/pre-release 与客户端兼容矩阵，现代模板处理 MLKEM 和下行指纹 | 复测本文 TCP 矩阵，原版本仍可用，失败能回退 |
| P0 | 统一 UDP/443 策略，导出时明确说明 | 两种客户端普通 UDP、UDP/443 行为一致 |
| P1 | 按内核清理无效字段，按版本映射 session 字段；修正文档 | 除解析检查，还验证最终配置和实际传输行为 |
| P1 | SNI 诊断分别报告 TLS、h2、key exchange 和实际可达性 | 构造不支持 h2 的目标时不能再显示全面通过 |
| P1 | 升级检查纳入 Freedom finalRules、用户私网例外和中继 | 确保默认私网保护、明确例外及自定义路由都符合预期 |
| P2 | 对比 XMUX、单栈 stream-one、分离/非分离；按能力启用 TFO/MPTCP | 在同一网络条件下测首包/p95、吞吐、CPU/内存、重连 |
| P2 | 按需要提供中继 ML-KEM authentication | 双端成对更新，协议互通及回滚通过 |
| P3 | 独立增加 TLS H3 / Hysteria2 / 指定 Finalmask 方案 | 各自满足客户端支持、证书/端口要求，并有实际收益 |

默认仍建议保留一条保守的、经过互通验证的 REALITY 入口及单栈备用。任何“更隐蔽”“更快”结论，都要说明测试地区、运营商、时间、版本和失败样本；文档存在某参数只能证明可配置，不能证明适合本线路。

**10. 本次验证范围与复现材料**

实际完成：10 个 TCP 兼容场景；8 组客户端/服务端配置的普通 UDP 与 UDP/443 echo；核心版本核验；Xray v26.10.10 下载包 SHA256 对照官方 `.dgst` 通过。

Xray v26.10.10 测试包 SHA256：`bfefce8e9804e53b7d75b7c49d958b34e89890d9d5e672329089d1b3111647af`。

测试在 Windows 本机完成，所有监听及目的地址均为 loopback，使用临时 UUID/密钥和自签名 TLS1.3 target。读取当前 export.sh 的三个 YAML heredoc，替换测试地址；生产环境的抽象 Unix 回落在测试中换成 loopback TCP。新 Freedom 仅在测试配置中放行 `127.0.0.1/32`。后台测试进程已退出；没有安装服务或调整系统防火墙。

没有完成：真实服务器测量、真实双栈网络、丢包/限速实验、NAT 类型与 migration 测试、真实审查环境的隐蔽性评估、v2rayN GUI 操作。因此本报告不宣称安全性或性能已提升。

机器可读结果见同目录 `configuration-audit-2026-10-16-results.json`。本地复现脚本与官方源文件缓存保留在 `.test-tools/audit-2026-10-16/`，该目录按项目原有规则不进入 Git。运行脚本需要 Python、OpenSSL，以及上文所列本地测试核心；不要把测试用 loopback 放行配置部署到生产环境。
