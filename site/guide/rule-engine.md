# Rule Engine

Riptide implements a **full Clash-compatible rule engine** with extensions
for script rules, RULE-SET providers, and native GeoIP/GeoSite resolution.

## Rule Types

| Rule | Example | Description |
|------|---------|-------------|
| `DOMAIN` | `DOMAIN,example.com,Proxy` | Exact domain match |
| `DOMAIN-SUFFIX` | `DOMAIN-SUFFIX,google.com,Proxy` | Match domain + subdomains |
| `DOMAIN-KEYWORD` | `DOMAIN-KEYWORD,google,Proxy` | Keyword in domain |
| `GEOIP` | `GEOIP,CN,DIRECT` | Country from MaxMind MMDB |
| `GEOSITE` | `GEOSITE,google,Proxy` | Domain category from GeoSite DB |
| `IP-CIDR` | `IP-CIDR,10.0.0.0/8,DIRECT` | IPv4 CIDR match |
| `IP-CIDR6` | `IP-CIDR6,::1/128,DIRECT` | IPv6 CIDR match |
| `SRC-IP-CIDR` | `SRC-IP-CIDR,192.168.1.0/24,DIRECT` | Source IP match |
| `SRC-PORT` | `SRC-PORT,8080,DIRECT` | Source port |
| `DST-PORT` | `DST-PORT,443,Proxy` | Destination port |
| `PROCESS-NAME` | `PROCESS-NAME,curl,DIRECT` | Process name (macOS only) |
| `RULE-SET` | `RULE-SET,reject-ads,REJECT` | Remote rule provider |
| `SCRIPT` | `SCRIPT,my-script,Proxy` | JavaScript rule (Riptide ext.) |
| `MATCH` | `MATCH,Proxy` | Fallback (must be last) |

## Rule Providers (RULE-SET)

Load rules from a remote URL or local file:

```yaml
rule-providers:
  reject-ads:
    type: http
    behavior: domain          # domain | ipcidr | classical
    url: https://rules.example.com/reject-ads.yaml
    path: ./rules/reject-ads.yaml
    interval: 86400           # update every 24h
```

Use in rules:

```yaml
rules:
  - RULE-SET,reject-ads,REJECT
  - MATCH,Proxy
```

## Script Rules

Write routing logic in JavaScript (Surge-compatible API):

```javascript
// rule.js
const domain = $request.hostname;
const country = $utils.geoip($request.sourceIP);

if (country === 'CN' && !domain.includes('google')) {
  $done('DIRECT');
} else {
  $done('Proxy');
}
```

Reference in config:

```yaml
rules:
  - SCRIPT,rule.js,Proxy
```

The script receives `$request` (hostname, sourceIP, port), `$utils.geoip()`,
and calls `$done()` with the target policy.

## Geo Assets

Riptide bundles MaxMind-compatible GeoIP databases and a GeoSite database:

- **GeoIP** — IP → country code (e.g., `CN`, `US`, `JP`)
- **GeoSite** — Domain → category (e.g., `google`, `netflix`, `openai`)
- **ASN** — IP → autonomous system number

Auto-updated weekly. Manage in **Settings → Geo Assets**.
