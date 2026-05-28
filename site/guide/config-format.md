# Config Format

Riptide uses a **Clash-compatible YAML profile format**.
Standard Clash configs work as-is; Riptide adds optional extensions
for features unique to its native Swift engine.

## Minimal Config

```yaml
proxies:
  - name: "my-ss"
    type: ss
    server: example.com
    port: 8388
    cipher: aes-256-gcm
    password: "your-password"

proxy-groups:
  - name: "Proxy"
    type: select
    proxies:
      - my-ss
      - DIRECT

rules:
  - DOMAIN-SUFFIX,google.com,Proxy
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
```

## All Supported Protocols

| Type | YAML `type` | Native Swift | Mihomo |
|------|-------------|:---:|:---:|
| Shadowsocks | `ss` | ✅ | ✅ |
| VMess | `vmess` | ✅ | ✅ |
| VLESS | `vless` | ✅ | ✅ |
| Trojan | `trojan` | ✅ | ✅ |
| Hysteria 2 | `hysteria2` | ✅ | ✅ |
| TUIC v5 | `tuic` | ✅ | ✅ |
| Snell v2/v3 | `snell` | ✅ | — |
| WireGuard | `wireguard` | planned v2.5 | ✅ |
| HTTP | `http` | ✅ | ✅ |
| SOCKS5 | `socks5` | ✅ | ✅ |

## Transports

Each proxy supports optional transport configuration:

```yaml
proxies:
  - name: "my-vless"
    type: vless
    # ...
    transport:
      type: ws              # ws | grpc | h2 | quic
      ws:
        path: /ws
        headers:
          Host: example.com
      tls: true
      reality:
        public-key: "..."
        short-id: "abcd"
```

Supported transports: `tcp`, `ws` (WebSocket), `grpc`, `h2` (HTTP/2),
`quic`, `reality` (TLS camouflage).

## DNS Configuration

```yaml
dns:
  enable: true
  enhanced-mode: fake-ip     # or redir-host
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://doh.example.com/dns-query
  fallback:
    - tls://8.8.8.8:853
  nameserver-policy:
    "google.com": tls://8.8.4.4:853
```

Riptide supports DoH, DoT, and **DoQ** (DNS-over-QUIC, Riptide-only).

## Riptide Extensions

Fields that are **Riptide-specific** (ignored by other Clash clients):

```yaml
# Per-proxy connection pool tuning
proxies:
  - name: "my-ss"
    riptide:
      pool:
        max-connections: 8
        idle-timeout: 300

# Rule script engine (JavaScript)
rules:
  - SCRIPT,check-bypass,Proxy
```

## Validation

Riptide validates configs on import and highlights issues:
- Missing required fields
- Invalid cipher/protocol combinations
- Circular proxy group references
- DNS syntax errors
