---
name: riptide-catchup
description: Riptide Windows 端追赶 v2.4.1 的项目 rein 集合；4 名成员（rust-engineer / frontend-engineer / qa / doc-writer）协作把 Windows 端追平与 macOS v2.4.1
---

# Riptide Catchup Harness

项目 rein 集合,把 Windows 端(`riptide-windows/`)追到与 macOS v2.4.1 持平。
追赶路线见 [`../docs/WINDOWS-CATCHUP-PLAN.md`](../docs/WINDOWS-CATCHUP-PLAN.md)。

## 成员

| Rein | 目录 | 职责 |
|---|---|---|
| `rust-engineer` | `reins/rust-engineer/` | Tauri Rust 后端 |
| `frontend-engineer` | `reins/frontend-engineer/` | Tauri React/TS 前端 |
| `qa` | `reins/qa/` | 测试 + CI |
| `doc-writer` | `reins/doc-writer/` | AGENTS / CHANGELOG / ADR / docs |

## 编排

- Phase A(W1,4-5 人天) — 紧急修复 + 治理基线
- Phase B(W2-W4,25 人天) — 基础设施 + 测试 + CI
- Phase C(W5-W9,80 人天) — 功能 + UI 补全
- Phase D(W10-W12,30 人天) — 治理 + 生态

每个 phase 由 `mavis team plan run` 启动,verifier 独立审查。
