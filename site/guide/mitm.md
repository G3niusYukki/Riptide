# MITM & Scripting

Riptide includes a built-in **MITM (Man-in-the-Middle) engine** for
HTTPS traffic inspection, request rewriting, and ad blocking —
powered by a Surge-compatible JavaScript scripting bridge.

## Enabling MITM

1. Go to **Settings → MITM**.
2. Toggle **Enable MITM**.
3. Install the Riptide CA certificate:
   - Click **Generate CA Certificate**
   - Open the generated `.crt` file (double-click)
   - In Keychain Access, mark the certificate as **Always Trust**
4. Add hosts to intercept:

```yaml
mitm:
  hosts:
    - "*.example.com"
    - "api.openai.com"
```

## HTTP Rewrite Engine

Modify requests and responses without writing code:

```yaml
http-rewrite:
  # Block ads
  - pattern: ".*/ads/.*"
    type: reject

  # Redirect CDN
  - pattern: "https://cdn.example.com/(.*)"
    type: redirect
    target: "https://fast-cdn.example.com/$1"

  # Modify headers
  - pattern: "https://api.example.com/.*"
    type: header-modify
    request-headers:
      X-Custom: "riptide"
    response-headers:
      Access-Control-Allow-Origin: "*"
```

Types: `reject`, `redirect`, `header-modify`.

## Scripting (Surge-compatible)

Riptide's JS engine mirrors the Surge scripting API.
Write once, run on both platforms.

### Script Types

| Type | Trigger | Receives |
|------|---------|----------|
| `request-modify` | Before request sent | `$request` (method, url, headers, body) |
| `response-modify` | After response received | `$request` + `$response` (status, headers, body) |
| `rule-provider` | During rule evaluation | `$request` (hostname, sourceIP) |
| `profile-script` | Config load | `$environment` (profile metadata) |

### Example: Request Modifier

```javascript
// strip-tracking.js
if ($request.url.includes('utm_')) {
  const url = new URL($request.url);
  url.searchParams.delete('utm_source');
  url.searchParams.delete('utm_medium');
  $done({ url: url.toString() });
} else {
  $done({});
}
```

### Example: Response Modifier

```javascript
// inject-csp.js
const headers = $response.headers;
headers['Content-Security-Policy'] = "default-src 'self'";
$done({ headers });
```

### Available APIs

| API | Description |
|-----|-------------|
| `$request` | `{ method, url, headers, body, hostname, sourceIP }` |
| `$response` | `{ status, headers, body }` |
| `$done(object?)` | Complete the script with optional modified data |
| `$persistentStore` | Key-value store persisted across sessions |
| `$notification` | Post system notification |
| `$httpClient` | Make sub-requests (async) |
| `$utils.geoip(ip)` | Look up country code |
| `$environment` | Profile name, mode, timestamp |

## Configuration

```yaml
scripts:
  - name: "strip-tracking"
    type: request-modify
    url: "https://scripts.example.com/strip-tracking.js"
    update-interval: 86400

rules:
  - SCRIPT,strip-tracking,Proxy
```
