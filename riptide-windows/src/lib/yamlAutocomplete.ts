import { CompletionContext, CompletionResult } from '@codemirror/autocomplete';

// Clash YAML schema completions
const CLASH_TOP_LEVEL_KEYS = [
  { label: 'mixed-port', type: 'property', info: 'HTTP(S) and SOCKS5 proxy port' },
  { label: 'port', type: 'property', info: 'HTTP(S) proxy port' },
  { label: 'socks-port', type: 'property', info: 'SOCKS5 proxy port' },
  { label: 'redir-port', type: 'property', info: 'Transparent proxy port' },
  { label: 'tproxy-port', type: 'property', info: 'TProxy port' },
  { label: 'mode', type: 'property', info: 'Rule mode: rule, global, direct' },
  { label: 'allow-lan', type: 'property', info: 'Allow LAN connections' },
  { label: 'bind-address', type: 'property', info: 'Bind address' },
  { label: 'log-level', type: 'property', info: 'Log level: silent, error, warning, info, debug' },
  { label: 'ipv6', type: 'property', info: 'Enable IPv6' },
  { label: 'external-controller', type: 'property', info: 'External controller address' },
  { label: 'external-ui', type: 'property', info: 'External UI directory' },
  { label: 'external-ui-url', type: 'property', info: 'External UI download URL' },
  { label: 'secret', type: 'property', info: 'API secret' },
  { label: 'interface-name', type: 'property', info: 'Interface name' },
  { label: 'routing-mark', type: 'property', info: 'Routing mark' },
  { label: 'proxies', type: 'property', info: 'Proxy list' },
  { label: 'proxy-groups', type: 'property', info: 'Proxy groups' },
  { label: 'rules', type: 'property', info: 'Routing rules' },
  { label: 'dns', type: 'property', info: 'DNS configuration' },
  { label: 'tun', type: 'property', info: 'TUN configuration' },
  { label: 'hosts', type: 'property', info: 'Static hosts' },
  { label: 'rule-providers', type: 'property', info: 'Rule providers' },
  { label: 'proxy-providers', type: 'property', info: 'Proxy providers' },
];

const DNS_OPTIONS = [
  { label: 'enable', type: 'property', info: 'Enable DNS' },
  { label: 'listen', type: 'property', info: 'DNS listen address' },
  { label: 'ipv6', type: 'property', info: 'Enable IPv6 DNS' },
  { label: 'enhanced-mode', type: 'property', info: 'Enhanced mode: fake-ip, redir-host' },
  { label: 'fake-ip-range', type: 'property', info: 'Fake-IP range' },
  { label: 'fake-ip-filter', type: 'property', info: 'Fake-IP filter list' },
  { label: 'default-nameserver', type: 'property', info: 'Default nameserver' },
  { label: 'nameserver', type: 'property', info: 'Nameserver list' },
  { label: 'fallback', type: 'property', info: 'Fallback nameserver' },
  { label: 'fallback-filter', type: 'property', info: 'Fallback filter configuration' },
  { label: 'nameserver-policy', type: 'property', info: 'Nameserver policy' },
];

const TUN_OPTIONS = [
  { label: 'enable', type: 'property', info: 'Enable TUN' },
  { label: 'stack', type: 'property', info: 'TUN stack: system, gvisor, mixed' },
  { label: 'dns-hijack', type: 'property', info: 'DNS hijack list' },
  { label: 'auto-route', type: 'property', info: 'Auto route' },
  { label: 'auto-detect-interface', type: 'property', info: 'Auto detect interface' },
  { label: 'device', type: 'property', info: 'TUN device name' },
  { label: 'route-address', type: 'property', info: 'Route address set' },
  { label: 'mtu', type: 'property', info: 'MTU value' },
  { label: 'strict-route', type: 'property', info: 'Strict route' },
];

const PROXY_TYPES = [
  { label: 'ss', type: 'keyword', info: 'Shadowsocks' },
  { label: 'vmess', type: 'keyword', info: 'VMess' },
  { label: 'vless', type: 'keyword', info: 'VLESS' },
  { label: 'trojan', type: 'keyword', info: 'Trojan' },
  { label: 'hysteria2', type: 'keyword', info: 'Hysteria 2' },
  { label: 'snell', type: 'keyword', info: 'Snell' },
  { label: 'socks5', type: 'keyword', info: 'SOCKS5' },
  { label: 'http', type: 'keyword', info: 'HTTP' },
  { label: 'tuic', type: 'keyword', info: 'TUIC' },
  { label: 'wireguard', type: 'keyword', info: 'WireGuard' },
];

const PROXY_GROUP_TYPES = [
  { label: 'select', type: 'keyword', info: 'Manual selection' },
  { label: 'url-test', type: 'keyword', info: 'URL test with auto fallback' },
  { label: 'fallback', type: 'keyword', info: 'Fallback based on URL test' },
  { label: 'load-balance', type: 'keyword', info: 'Load balancing' },
  { label: 'relay', type: 'keyword', info: 'Relay chain' },
];

const RULE_TYPES = [
  { label: 'DOMAIN', type: 'keyword', info: 'Exact domain match' },
  { label: 'DOMAIN-SUFFIX', type: 'keyword', info: 'Domain suffix match' },
  { label: 'DOMAIN-KEYWORD', type: 'keyword', info: 'Domain keyword match' },
  { label: 'IP-CIDR', type: 'keyword', info: 'IP CIDR match' },
  { label: 'IP-CIDR6', type: 'keyword', info: 'IPv6 CIDR match' },
  { label: 'SRC-IP-CIDR', type: 'keyword', info: 'Source IP CIDR match' },
  { label: 'SRC-PORT', type: 'keyword', info: 'Source port match' },
  { label: 'DST-PORT', type: 'keyword', info: 'Destination port match' },
  { label: 'PROCESS-NAME', type: 'keyword', info: 'Process name match' },
  { label: 'GEOIP', type: 'keyword', info: 'GeoIP match' },
  { label: 'GEOSITE', type: 'keyword', info: 'GeoSite match' },
  { label: 'RULE-SET', type: 'keyword', info: 'Rule set match' },
  { label: 'MATCH', type: 'keyword', info: 'Final match rule' },
];

const MODE_OPTIONS = [
  { label: 'rule', type: 'keyword', info: 'Rule-based routing' },
  { label: 'global', type: 'keyword', info: 'Global proxy' },
  { label: 'direct', type: 'keyword', info: 'Direct connection' },
];

const LOG_LEVEL_OPTIONS = [
  { label: 'silent', type: 'keyword', info: 'No logging' },
  { label: 'error', type: 'keyword', info: 'Error only' },
  { label: 'warning', type: 'keyword', info: 'Warnings' },
  { label: 'info', type: 'keyword', info: 'Informational' },
  { label: 'debug', type: 'keyword', info: 'Debug' },
];

/**
 * Provides autocompletion for Clash YAML configuration.
 */
export function clashYamlAutocomplete(context: CompletionContext): CompletionResult | null {
  const line = context.state.doc.lineAt(context.pos);
  const lineText = line.text.slice(0, context.pos - line.from);
  const trimmed = lineText.trimStart();

  // Determine context based on indentation and content
  const indent = lineText.length - trimmed.length;

  // Top-level keys (indent = 0)
  if (indent === 0 && !trimmed.includes(':')) {
    return {
      from: line.from + indent,
      options: CLASH_TOP_LEVEL_KEYS,
    };
  }

  // Check if we're in a specific section
  const prevLines = getPreviousLines(context.state.doc.toString(), line.number);
  const section = determineSection(prevLines, indent);

  if (section) {
    switch (section) {
      case 'mode':
        return {
          from: line.from + lineText.indexOf(trimmed),
          options: MODE_OPTIONS,
        };
      case 'log-level':
        return {
          from: line.from + lineText.indexOf(trimmed),
          options: LOG_LEVEL_OPTIONS,
        };
      case 'dns':
        if (indent === 2) {
          return {
            from: line.from + indent,
            options: DNS_OPTIONS,
          };
        }
        break;
      case 'tun':
        if (indent === 2) {
          return {
            from: line.from + indent,
            options: TUN_OPTIONS,
          };
        }
        break;
      case 'type-proxy':
        return {
          from: line.from + lineText.indexOf(trimmed),
          options: PROXY_TYPES,
        };
      case 'type-group':
        return {
          from: line.from + lineText.indexOf(trimmed),
          options: PROXY_GROUP_TYPES,
        };
      case 'rules':
        if (trimmed.startsWith('- ') && !trimmed.includes(',')) {
          return {
            from: line.from + lineText.indexOf(trimmed) + 2,
            options: RULE_TYPES,
          };
        }
        break;
    }
  }

  return null;
}

function getPreviousLines(text: string, currentLine: number): string[] {
  const lines = text.split('\n');
  return lines.slice(0, currentLine - 1);
}

function determineSection(prevLines: string[], currentIndent: number): string | null {
  // Look backwards to find the section we're in
  for (let i = prevLines.length - 1; i >= 0; i--) {
    const line = prevLines[i];
    const trimmed = line.trimStart();
    const indent = line.length - trimmed.length;

    // Check for specific keys at indent 0
    if (indent === 0) {
      if (trimmed.startsWith('dns:')) return 'dns';
      if (trimmed.startsWith('tun:')) return 'tun';
      if (trimmed.startsWith('proxies:')) return 'proxies';
      if (trimmed.startsWith('proxy-groups:')) return 'proxy-groups';
      if (trimmed.startsWith('rules:')) return 'rules';
      if (trimmed.startsWith('mode:')) return 'mode';
      if (trimmed.startsWith('log-level:')) return 'log-level';
    }

    // Check for type field in proxies or proxy-groups sections
    if (indent === 2 && trimmed.startsWith('type:')) {
      // Look further back to determine parent section
      for (let j = i - 1; j >= 0; j--) {
        const prevLine = prevLines[j];
        const prevTrimmed = prevLine.trimStart();
        const prevIndent = prevLine.length - prevTrimmed.length;

        if (prevIndent === 0) {
          if (prevTrimmed.startsWith('proxies:')) return 'type-proxy';
          if (prevTrimmed.startsWith('proxy-groups:')) return 'type-group';
          break;
        }
      }
    }

    // If we find a line with less or equal indent, we've left the section
    if (indent < currentIndent) {
      return null;
    }
  }

  return null;
}
