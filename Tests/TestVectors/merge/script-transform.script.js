function transform(config) {
    // Add a new proxy
    config.proxies = config.proxies || [];
    config.proxies.push({
        name: "script-proxy",
        type: "ss",
        server: "3.3.3.3",
        port: 8388,
        cipher: "aes-256-gcm",
        password: "scriptpass"
    });

    // Add a rule
    config.rules = config.rules || [];
    config.rules.push("DOMAIN-KEYWORD,example,PROXY");

    return config;
}
