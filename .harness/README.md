# Riptide 项目 Agent 团队 (`.harness/`)

> 项目专属 reins,跟仓库一起 commit,负责把 Windows 端追到与 macOS v2.4.1 持平。
> 详细追赶路线见 [`docs/WINDOWS-CATCHUP-PLAN.md`](WINDOWS-CATCHUP-PLAN.md)。

## 团队成员

| Rein | 职责 | 目录 | 主要工具 |
|---|---|---|---|
| **rust-engineer** | Tauri Rust 后端:代理栈 / 配置 / 模式协调 / 服务 / 安全 | `reins/rust-engineer/` | `cargo`, `tauri`, `serde_yaml`, `tokio`, `reqwest` |
| **frontend-engineer** | Tauri React/TS 前端:UI / 状态 / IPC / CodeMirror / i18n | `reins/frontend-engineer/` | React 19, TypeScript, Tailwind v4, Zustand, TanStack Query, react-i18next |
| **qa** | 测试金字塔 + CI 工作流 + 覆盖率 | `reins/qa/` | `cargo test`, vitest, React Testing Library, Playwright + tauri-driver, `cargo-llvm-cov` |
| **doc-writer** | AGENTS / CHANGELOG / ADR / VitePress / rules | `reins/doc-writer/` | Markdown, VitePress, ripgrep |

## 工作边界

- `rust-engineer` 拥有 `riptide-windows/src-tauri/**`
- `frontend-engineer` 拥有 `riptide-windows/src/**`
- `qa` 拥有 `riptide-windows/{tests/,tests-e2e/,**/__tests__/, .github/workflows/}`
- `doc-writer` 拥有 `*.md`、`docs/`、`site/`、`rules/`、`CHANGELOG.md`
- 跨边界改动通过 `assigned_to` + `verified_by` 在 mavis-team plan 中显式编排

## 启动一个 plan

```powershell
# 列出本项目所有 reins
mavis agent list --project $PWD.Path --human

# 写一个 plan.yaml,例如 .mavis/plans/phase-a.yaml
# 然后:
mavis team plan run .mavis/plans/phase-a.yaml
```

## 运行时注册

项目 reins 是**项目内版本**(跟仓库 commit,给团队看"角色 / 边界 / 停止条件")。
daemon 引擎只认 `~/.mavis/agents/<name>/` 下的全局 agent,所以**每个 rein 都有一个全局镜像**,由下面命令创建:

```powershell
# 一次性注册 4 个全局镜像
$reins = @{
  "rust-engineer"     = "Win Rust 端工程师"
  "frontend-engineer" = "Win FE/TS 工程师"   # 20 字符以下;description 是 daemon 内部字段
  "qa"                = "Win 测试+CI 工程师"
  "doc-writer"        = "Win 文档工程师"
}
foreach ($r in $reins.Keys) {
  $path = Join-Path $PWD.Path ".harness\reins\$r\agent.md"
  $body = (Get-Content $path -Encoding UTF8 -Raw) -replace "(?s)^---\s*\n.*?\n---\s*\n", ""
  mavis agent new $r --description $reins[$r] --display-name "$r Win" --system-prompt $body
}
```

daemon 重启或换机器后重跑这段即可重建全局镜像。**项目 reins 文件不需要动** — 它是真相源。

## 维护规则

1. **新加 rein**:在 `reins/<name>/agent.md` 写 `name` + `description` 两行 frontmatter,然后写 4 段(scope / how / stop when)
2. **改 rein**:先改 `reins/<name>/agent.md`(项目真相),再用上面的脚本更新全局镜像
3. **删 rein**:用 `mavis-trash` 移动 `reins/<name>/` 到 `.harness/.trash/`,同时 `mavis agent delete <name>` 删全局镜像
4. **改完跑**:`mavis agent list --human` 确认 4 个都还在(全局列表中)
