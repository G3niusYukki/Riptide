## Summary
新增 Riptide Windows 客户端 (Phase 1-2)，使用 Tauri 2.0 + React + Rust 技术栈，实现与 macOS 版本的功能对齐。

## Changes

### 🆕 New: Windows Client (`riptide-windows/`)

**Phase 1 - Foundation:**
- ✅ Tauri 2.0 项目初始化
- ✅ React 19 + TypeScript + TailwindCSS v4 前端
- ✅ Rust 后端架构 (cmds/core/config/utils)
- ✅ mihomo 进程生命周期管理
- ✅ 系统代理控制 (sysproxy)
- ✅ Windows Service 框架 (TUN 模式准备)

**Phase 2 - Core Features:**
- ✅ mihomo REST API 客户端 (11 个端点)
  - 代理列表/组管理
  - 延迟测试
  - 代理切换
  - 连接列表
  - 流量统计
- ✅ Clash YAML 配置解析器
  - 支持所有代理类型 (SS, VMess, VLESS, Trojan, Hysteria2, TUIC...)
  - Proxy Groups (select, url-test, fallback, load-balance)
  - DNS / TUN / Rules 配置
- ✅ URL 导入订阅
- ✅ 前端实时数据连接
  - 自动刷新: 代理 (5s), 连接 (2s), 流量 (1s)
  - React Query + Zustand 状态管理

### 📁 Directory Structure
```
riptide-windows/
├── src-tauri/           # Rust 后端
│   ├── src/
│   │   ├── cmds/        # Tauri 命令
│   │   ├── core/        # mihomo API + 进程管理
│   │   ├── config/      # YAML 解析器
│   │   └── utils/       # 工具函数
│   ├── Cargo.toml
│   └── tauri.conf.json
├── src/                 # React 前端
│   ├── components/      # UI 组件
│   ├── hooks/           # React Query hooks
│   ├── services/        # Tauri IPC
│   └── stores/          # Zustand stores
└── package.json
```

### 🔧 CI/CD
- ✅ Windows CI workflow (`.github/workflows/windows-ci.yml`)
  - Lint, Build, Test, Release 四个阶段
  - 仅 `riptide-windows/**` 变更时触发
  - 输出: `.msi` 和 `.exe` 安装包

### 📚 Documentation
- ✅ `docs/WINDOWS-PORT-PLAN.md` - 完整实施计划

## Testing

### 本地测试
```bash
cd riptide-windows
npm install
npm run tauri dev
```

### 构建测试
```bash
cd riptide-windows
npm run tauri build
```

## Compatibility

| 组件 | 平台 | 状态 |
|------|------|------|
| Swift macOS | macOS 14+ | ✅ 无影响 (独立目录) |
| Tauri Windows | Windows 11+ | ✅ 新增 |

**零冲突保证:**
- Windows 代码完全隔离在 `riptide-windows/` 目录
- 不修改任何 Swift 源文件
- 不修改 `Package.swift`
- macOS CI 与 Windows CI 独立运行

## Screenshots
*(将在 PR 中补充)*

## Checklist

- [x] Windows 项目可独立构建
- [x] mihomo API 客户端测试通过
- [x] Clash YAML 解析器支持标准配置
- [x] 前端组件连接真实 API 数据
- [x] CI workflow 配置完成
- [x] 文档已更新

## Related
- Closes: (后续 issues)
- References: [Tauri Docs](https://v2.tauri.app/), [mihomo API](https://github.com/MetaCubeX/mihomo/blob/master/docs/api.md)

---

**Reviewer Guide:**
1. 重点检查 `riptide-windows/src-tauri/src/core/mihomo_api.rs` - API 客户端实现
2. 检查 `riptide-windows/src/config/parser.rs` - YAML 解析完整性
3. 验证 CI workflow 路径过滤是否正确
