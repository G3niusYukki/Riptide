# Mihomo TUN 模式推进计划

## 背景

Riptide 的 TUN 模式采用 mihomo sidecar 方案：mihomo 自带完整的 TUN 实现（gvisor 网络栈），通过 root 权限创建 utun 接口，无需 Apple Developer 账户或 Network Extension。

当前状态：**架构已就绪，但被 gated（UI 禁用）且未端到端验证。**

## 现有代码分析

### 已完成 ✅
1. **MihomoConfigGenerator** — TUN 配置生成已实现
   - `tun.enable: true/false` 根据 mode 切换
   - `stack: gvisor`（用户态网络栈，macOS 兼容）
   - `dns-hijack: 0.0.0.0:53`（劫持所有 DNS 查询）
   - `auto-route: true`（自动设置路由）
   - `strict-route: true`（严格路由，防止泄漏）

2. **SudoMihomoLauncher** — sudo 提权启动已实现
   - 通过 `/usr/bin/sudo` 启动 mihomo，无需 Apple Developer 证书
   - 会弹出系统密码认证对话框（sudo 缓存 5-15 分钟）
   - SIGTERM + SIGKILL 优雅停止

3. **MihomoRuntimeManager.start()** — 启动流程已包含 TUN 路径
   - 生成 config.yaml（含 TUN 配置）
   - 通过 XPC helper 或 sudo 启动 mihomo
   - 健康检查等待 API 就绪

4. **MihomoRuntimeManager.stop()** — 停止流程已实现
   - systemProxy 模式会清除系统代理
   - TUN 模式：mihomo 退出时自动清理 utun 接口

5. **mihomo API 客户端** — 完整的 REST API 集成
   - 代理切换、连接管理、流量统计、日志获取

### 需要完成 ❌
1. mihomo 二进制未下载到正确位置
2. UI 中 TUN 模式被 `.disabled(true)` 禁用
3. TUN 配置缺少 `device-name` 字段
4. stop() 中 TUN 模式缺少清理逻辑（路由恢复等）
5. TUN 模式无健康检查/状态监控
6. TUN 模式无端到端测试

---

## 推进计划

### Phase 1: 基础设施（让 mihomo TUN 能启动）

#### Task 1.1: 下载 mihomo 二进制
- 运行 `./Scripts/download-mihomo.sh` 或通过 MihomoCoreManager 下载
- 验证二进制能执行：`~/Library/Application Support/Riptide/mihomo/mihomo -v`
- 确保路径与 MihomoPaths.executable 一致

#### Task 1.2: 完善 TUN 配置生成
**文件**: `Sources/Riptide/Mihomo/MihomoConfigGenerator.swift`

在 TUN section 中添加：
```yaml
tun:
  enable: true
  device: utun120        # 指定设备名，避免冲突
  stack: gvisor
  dns-hijack:
    - any:53             # mihomo 新版语法
  auto-route: true
  strict-route: true
  route-address:
    - 0.0.0.0/1          # 分流：覆盖默认路由的一半
    - 128.0.0.0/1         # 分流：覆盖另一半
    - ::/1
    - 8000::/1
```

关键改动：
- 添加 `device: utun120`（固定设备名，方便调试和清理）
- 将 `0.0.0.0:53` 改为 `any:53`（mihomo 新版语法）
- 评估是否需要 `route-address`（auto-route 通常已足够）

#### Task 1.3: 添加 TUN 设备名配置支持
**文件**: `Sources/Riptide/Control/RuntimeControlSurface.swift`

在 RuntimeMode 或新配置结构中添加 TUN 设备名参数，允许用户自定义（默认 `utun120`）。

---

### Phase 2: UI 解锁（让用户能选择 TUN 模式）

#### Task 2.1: 启用菜单栏 TUN 选项
**文件**: `Sources/RiptideApp/MenuBarScene.swift` (line 82)

```swift
// 改前：
Text("TUN（暂不可用）").tag(RuntimeMode.tun).disabled(true)

// 改后：
Text("TUN模式").tag(RuntimeMode.tun)
```

#### Task 2.2: 添加 TUN 模式前置检查
**文件**: `Sources/RiptideApp/AppViewModel.swift`

在 `requestModeChange(.tun)` 时添加检查：
- mihomo 二进制是否存在
- 是否有 sudo 权限（首次会弹密码框）
- 提示用户 TUN 模式需要管理员权限

#### Task 2.3: 添加 TUN 模式状态指示
**文件**: `Sources/RiptideApp/MenuBarScene.swift`

在 TUN 模式运行时显示特殊状态图标，区分于系统代理模式。

---

### Phase 3: 运行时完善（让 TUN 模式稳定运行）

#### Task 3.1: TUN 模式停止时的清理
**文件**: `Sources/Riptide/Mihomo/MihomoRuntimeManager.swift`

在 stop() 中，当 mode == .tun 时：
1. mihomo 退出后会自动清理 utun 接口（这是 mihomo 的内置行为）
2. 但需要确认 DNS 设置是否恢复（macOS 的 /etc/resolv.conf 或 DNS 缓存）
3. 添加 DNS 缓存刷新：`sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`

```swift
// 在 stop() 的 TUN 分支中
if currentMode == .tun {
    // mihomo 退出时自动清理 utun 和路由
    // 但 DNS 缓存可能需要手动刷新
    if launchedViaSudo {
        // 通过 sudo 刷新 DNS
        let flushProc = Process()
        flushProc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        flushProc.arguments = ["dscacheutil", "-flushcache"]
        try? flushProc.run()
        flushProc.waitUntilExit()
    }
}
```

#### Task 3.2: TUN 模式健康检查增强
**文件**: `Sources/Riptide/Mihomo/MihomoRuntimeManager.swift`

在 TUN 模式启动后，除了 API 健康检查外，验证 TUN 接口是否创建成功：
```swift
if mode == .tun {
    // 验证 utun 接口存在
    let checkProc = Process()
    checkProc.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
    checkProc.arguments = ["utun120"]
    // ... 检查输出中是否有 "UP" 标志
}
```

#### Task 3.3: TUN 模式日志监控
利用已有的 MihomoLogClient 监控 TUN 相关日志：
- TUN 接口创建/销毁事件
- 路由设置/恢复事件
- DNS 劫持状态

---

### Phase 4: 测试验证

#### Task 4.1: 单元测试
- 测试 MihomoConfigGenerator 在 TUN 模式下生成正确的 YAML
- 测试 TUN 配置字段完整性
- 测试 stop() 时 TUN 清理逻辑

#### Task 4.2: 手动端到端测试
1. 启动 Riptide，选择 TUN 模式
2. 输入 sudo 密码
3. 验证：
   - `ifconfig utun120` 显示接口已创建
   - `netstat -rn` 显示路由已设置
   - `nslookup google.com` 通过 TUN DNS 解析
   - 浏览器访问被墙网站正常
   - 查看 mihomo API 的连接列表有数据
4. 停止 TUN 模式
5. 验证：
   - utun 接口已销毁
   - 路由已恢复
   - DNS 恢复正常

#### Task 4.3: 边界情况测试
- mihomo 进程崩溃时的清理
- 系统睡眠/唤醒后的恢复
- 与 VPN 软件的冲突检测
- 切换模式（TUN → System Proxy → TUN）

---

### Phase 5: 文档更新

#### Task 5.1: 更新 README.md
- 将 TUN 模式状态从 "Gated" 更新为 "Beta"
- 添加 TUN 模式使用说明（需要 sudo 权限）
- 添加已知限制

#### Task 5.2: 更新 ROADMAP.md
- 标记 TUN 模式为已完成

---

## 执行顺序

```
Phase 1 (基础设施)
  ├─ 1.1 下载 mihomo
  ├─ 1.2 完善 TUN 配置
  └─ 1.3 设备名配置
       │
Phase 2 (UI 解锁)
  ├─ 2.1 启用 TUN 选项
  ├─ 2.2 前置检查
  └─ 2.3 状态指示
       │
Phase 3 (运行时)
  ├─ 3.1 停止清理
  ├─ 3.2 健康检查
  └─ 3.3 日志监控
       │
Phase 4 (测试)
  ├─ 4.1 单元测试
  ├─ 4.2 端到端测试
  └─ 4.3 边界测试
       │
Phase 5 (文档)
```

## 风险与注意事项

1. **sudo 密码弹窗**：每次启动 TUN 模式都需要输入密码（sudo 缓存过期后）。这是无 Apple Developer 账户方案的固有限制。
2. **mihomo 版本兼容性**：确保下载的 mihomo 版本支持 macOS TUN（gvisor 栈）。
3. **系统完整性保护 (SIP)**：mihomo 的 TUN 实现不依赖 SIP 关闭，但某些路由操作可能受限。
4. **与其他 VPN 冲突**：如果系统已有其他 VPN（如 WireGuard、OpenVPN），utun 设备号可能冲突。使用固定设备名 `utun120` 可减少冲突概率。
5. **DNS 泄漏**：strict-route + dns-hijack 应该能防止泄漏，但需要验证。

## 预估工作量

- Phase 1: ~2 小时（配置调整 + 下载验证）
- Phase 2: ~1 小时（UI 改动）
- Phase 3: ~3 小时（清理逻辑 + 健康检查 + 日志）
- Phase 4: ~2 小时（测试）
- Phase 5: ~30 分钟（文档）

总计约 8-9 小时
