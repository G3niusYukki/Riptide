#!/bin/bash
# Windows Port PR 创建脚本
# 保存为 create-pr.sh 后执行: bash create-pr.sh

echo "🚀 Riptide Windows Port - PR 创建向导"
echo "======================================"
echo ""

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}步骤 1/4:${NC} 确保您在本地 master 分支且有最新提交"
echo "   git status"
echo ""

echo -e "${BLUE}步骤 2/4:${NC} 创建并切换到 feature 分支"
echo "   git checkout -b feat/windows-port-phase2"
echo ""

echo -e "${BLUE}步骤 3/4:${NC} 推送到远端"
echo "   git push -u origin feat/windows-port-phase2"
echo ""

echo -e "${BLUE}步骤 4/4:${NC} 创建 Pull Request"
echo ""
echo "方法 A - 使用 GitHub CLI (推荐):"
echo "   gh pr create --title \"feat: Windows Port Phase 1-2 - Tauri + mihomo integration\" \\"
echo "              --body-file pr-body.md \\"
echo "              --base master \\"
echo "              --label enhancement,windows"
echo ""
echo "方法 B - 使用浏览器:"
echo "   访问: https://github.com/G3niusYukki/Riptide/compare/master...feat/windows-port-phase2"
echo ""

echo -e "${YELLOW}PR 标题建议:${NC}"
echo "   feat: Windows Port Phase 1-2 - Tauri + mihomo integration"
echo ""
echo -e "${YELLOW}PR 标签建议:${NC}"
echo "   - enhancement"
echo "   - windows"
echo "   - tauri"
echo ""

echo "✅ 完成！"
