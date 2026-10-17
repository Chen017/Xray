# Upstream feedback draft — not submitted

Prepared against Mihomo v1.19.32, Go 1.26.8, `with_gvisor`, Windows amd64; Xray server v26.3.27. No issue or PR has been posted.

## Configurable XHTTP H2 receive window

The current XHTTP transport constructs `http.HTTP2Config` with `SendPingTimeout`, leaving the per-stream receive window at its dependency's 4 MiB default. On a route with approximately 80 ms latency, single-stream downloads consistently stayed near 400 Mbps while neither endpoint showed sustained CPU saturation.

Official Mihomo and Xray clients were tested through the same localhost direct SOCKS bridge: Mihomo 411/400 Mbps, Xray 402/403 Mbps. Controlled builds of the same Mihomo source and compiler changed only:

```diff
 HTTP2: &http.HTTP2Config{
+    MaxReceiveBufferPerStream: 16 << 20,
     SendPingTimeout: keepAlivePeriod,
 },
```

In alternating runs, the unchanged 4 MiB build reached 405/418 Mbps and the 16 MiB build 674/828 Mbps. REALITY, TLS fingerprints, padding, paths, and both XMUX pools were unchanged. An 8 MiB build also improved sustained throughput. These were bounded HTTPS downloads from an authenticated temporary origin on the same server; no claim is made that they are identical to public Speedtest results.

Subsequent user-operated Single tests against IPA CyberLab 400G Tokyo recorded final downloads of 456.35 Mbps with the official baseline, 722 Mbps with an isolated 8 MiB diagnostic client, and 777 Mbps with an isolated 16 MiB client. The latter reported loaded download latency of 140 ms versus 74 ms for the baseline; the 8 MiB screenshot showed 78 ms during the test, without a final latency value. These are one run per variant, with variable server steal time. The diagnostic clients also add a localhost SOCKS bridge compared with the daily baseline, so the earlier controlled alternating builds remain the stronger causal comparison. The daily core and server configuration were restored and not upgraded.

A larger window increased short-request tail latency under a saturating download. It should not silently become a universal tuning recommendation. Consider a documented, bounded, opt-in XHTTP window option, or an upstream design for adaptive receive credit, with latency and memory validation. Existing YAML has no corresponding option; this installer does not emit a fictional field. Increasing only the server's receive window would affect the opposite direction and does not replace this client-side change.

## XMUX lifetime and request budget semantics

In `transport/xhttp/reuse.go`, `cleanupLocked` only removes an expired entry when openUsage is zero. `pickLocked` does not exclude an expired but still active entry. New requests can therefore continue using it after `h-max-reusable-secs` while a long-lived request remains active. Xray v26.3.27 removes expired entries from selection while existing requests finish.

The request budget is decremented in GetTransport, not RoundTrip. A single-stack stream-up proxy connection obtains one transport and performs an upload and download HTTP request, consuming one budget unit for two HTTP requests. Split mode has separate managers and must be evaluated per direction.

The following diagnostic test was run inside an otherwise unmodified v1.19.32 `transport/xhttp` package. It makes no network requests and prints the observed behavior rather than claiming a production fix.

```go
package xhttp

import (
    "io"
    "strings"
    "testing"
    "time"
    "github.com/metacubex/http"
)

type diagnosticTransport struct{ requests int }
func (d *diagnosticTransport) RoundTrip(r *http.Request) (*http.Response, error) {
    d.requests++
    return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader("")), Header: make(http.Header)}, nil
}

func TestDiagnosticReuseSemantics(t *testing.T) {
    maker := func() http.RoundTripper { return &diagnosticTransport{} }
    manager, err := NewReuseManager(&ReuseConfig{
        MaxConcurrency: "16", HMaxRequestTimes: "600", HMaxReusableSecs: "3600",
    }, maker)
    if err != nil { t.Fatal(err) }
    defer manager.Close()
    a := manager.GetTransport().(*ReuseTransport)
    a.entry.unreusableAt = time.Now().Add(-time.Second)
    b := manager.GetTransport().(*ReuseTransport)
    t.Logf("expired active entry reused: %v", a.entry == b.entry)
    a.Close(); b.Close()

    manager2, err := NewReuseManager(&ReuseConfig{
        MaxConcurrency: "16", HMaxRequestTimes: "600", HMaxReusableSecs: "3600",
    }, maker)
    if err != nil { t.Fatal(err) }
    defer manager2.Close()
    c := manager2.GetTransport().(*ReuseTransport)
    req, _ := http.NewRequest("GET", "http://localhost/", nil)
    for i := 0; i < 2; i++ {
        response, err := c.RoundTrip(req)
        if err != nil { t.Fatal(err) }
        response.Body.Close()
    }
    t.Logf("actual requests: %d, budget consumed: %d",
        c.entry.transport.(*diagnosticTransport).requests, 600-c.entry.leftRequests.Load())
    c.Close()
}
```

Observed: expired active entry reused = true; actual HTTP requests = 2; request budget consumed = 1. Any fix should stop new assignments without aborting existing long-lived requests and define the budget units explicitly.

References: [XHTTP transport](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/transport/xhttp/client.go), [reuse manager](https://github.com/MetaCubeX/mihomo/blob/v1.19.32/transport/xhttp/reuse.go), [default window](https://github.com/MetaCubeX/http/blob/v0.1.8/h2_bundle.go#L6933-L6941), [Xray XMUX](https://github.com/XTLS/Xray-core/blob/v26.3.27/transport/internet/splithttp/mux.go), [design discussion](https://github.com/XTLS/Xray-core/discussions/4113).
