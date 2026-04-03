# Riptide macOS 1.0 Compatibility Matrix

## Supported Rule Types

| Type | Status | Notes |
|------|--------|-------|
| DOMAIN | Supported | Exact domain match |
| DOMAIN-SUFFIX | Supported | Domain suffix match |
| DOMAIN-KEYWORD | Supported | Domain keyword match |
| IP-CIDR | Supported | IPv4 CIDR match |
| IP-CIDR6 | Supported | IPv6 CIDR match |
| GEOIP | Supported | GeoIP country code match |
| PROCESS-NAME | Supported | Process name match |
| MATCH | Supported | Match-all fallback |
| FINAL | Supported | Final fallback rule |
| SRC-IP-CIDR | Parsed | Source IP CIDR match |
| SRC-PORT | Parsed | Source port match |
| DST-PORT | Parsed | Destination port match |
| IP-ASN | Parsed | IP ASN match |
| GEOSITE | Parsed | Geosite match |
| RULE-SET | Parsed | Rule set reference |

## Supported Proxy Types

| Type | Config Key | Status | Notes |
|------|-----------|--------|-------|
| SOCKS5 | `socks5` | Supported | Full handshake |
| HTTP | `http` | Supported | HTTP CONNECT |
| Shadowsocks | `ss` | Supported | AEAD ciphers |

### Parsed but Not Fully Wired

| Type | Config Key | Status | Notes |
|------|-----------|--------|-------|
| VMess | `vmess` | Parsed | Stream actor exists, not wired to ProxyConnector |
| VLESS | `vless` | Parsed | Stream actor exists, not wired to ProxyConnector |
| Trojan | `trojan` | Parsed | Stream actor exists, not wired to ProxyConnector |
| Hysteria2 | `hysteria2` | Parsed | Stream actor exists, not wired to ProxyConnector |

## Supported Group Types

| Type | Config Key | Status | Notes |
|------|-----------|--------|-------|
| Select | `select` | Model only | No runtime resolver yet |
| URL-Test | `url-test` | Model only | No runtime resolver yet |
| Fallback | `fallback` | Model only | No runtime resolver yet |
| Load-Balance | `load-balance` | Model only | No runtime resolver yet |

## Supported Subscription / Import Inputs

| Input | Status | Notes |
|-------|--------|-------|
| Clash YAML | Supported | Full config import |
| `ss://` URI | Supported | Shadowsocks SIP002 parsing |
| `vmess://` URI | Supported | Base64 JSON parsing |
| `vless://` URI | Supported | URI parameter parsing |
| `trojan://` URI | Supported | URI parameter parsing |

## Explicitly Unsupported (1.0)

The following inputs must raise diagnostics when encountered:

| Input | Status | Reason |
|-------|--------|--------|
| TUIC | Unsupported | Protocol not in scope for 1.0 |
| WireGuard | Unsupported | Protocol not in scope for 1.0 |
| MASQUE | Unsupported | Protocol not in scope for 1.0 |
| MITM | Unsupported | Certificate authority scaffold only |
| WebDAV | Unsupported | Not in scope for 1.0 |
| ScriptEngine | Unsupported | Scaffold only |

## Runtime Modes

| Mode | Status | Notes |
|------|--------|-------|
| System Proxy | Planned for Alpha | HTTP/SOCKS local proxy |
| TUN | Planned for Beta | Packet tunnel via NetworkExtension |
