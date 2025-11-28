#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# 检查是否在 git 仓库中
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${red}错误: 当前目录不是 git 仓库${plain}"
    exit 1
fi

# 检查是否有未提交的修改
if ! git diff-index --quiet HEAD --; then
    echo -e "${red}错误: 存在未提交的修改，请先提交或暂存${plain}"
    git status --short
    exit 1
fi

echo -e "${green}开始同步上游代码...${plain}"

# 保存当前分支
CURRENT_BRANCH=$(git branch --show-current)
echo -e "${yellow}当前分支: $CURRENT_BRANCH${plain}"

# 检查 upstream 是否存在
if ! git remote | grep -q "^upstream$"; then
    echo -e "${yellow}未找到 upstream，正在添加...${plain}"
    git remote add upstream https://github.com/wyx2685/v2node.git
fi

# 1. 拉取上游最新代码
echo -e "${green}[1/7] 拉取上游最新代码...${plain}"
if ! git fetch upstream; then
    echo -e "${red}错误: 拉取上游代码失败${plain}"
    exit 1
fi

# 2. 切换到 main 分支
echo -e "${green}[2/7] 切换到 main 分支...${plain}"
if ! git checkout main; then
    echo -e "${red}错误: 切换到 main 分支失败${plain}"
    exit 1
fi

# 3. 重置 main 到上游最新状态
echo -e "${green}[3/7] 重置 main 到上游最新状态...${plain}"
if ! git reset --hard upstream/main; then
    echo -e "${red}错误: 重置 main 分支失败${plain}"
    exit 1
fi

# 4. 跳过推送（需要时手动推送）
echo -e "${green}[4/7] main 分支已更新（跳过推送）${plain}"

# 5. 切换到 dev 分支
echo -e "${green}[5/7] 切换到 dev 分支...${plain}"
if ! git checkout dev; then
    echo -e "${red}错误: 切换到 dev 分支失败${plain}"
    exit 1
fi

# 6. rebase dev 到最新的 main
echo -e "${green}[6/7] 将 dev 分支 rebase 到最新的 main...${plain}"
if git rebase main; then
    echo -e "${green}rebase 成功${plain}"
else
    echo -e "${red}错误: rebase 失败，可能存在冲突${plain}"
    echo -e "${yellow}请手动解决冲突后执行:${plain}"
    echo -e "  git add <冲突文件>"
    echo -e "  git rebase --continue"
    echo -e "${yellow}或者放弃 rebase:${plain}"
    echo -e "  git rebase --abort"
    exit 1
fi

# 7. 跳过推送（需要时手动推送）
echo -e "${green}[7/7] dev 分支已更新（跳过推送）${plain}"

# 恢复到原来的分支（如果不是 main 或 dev）
if [[ "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "dev" ]]; then
    echo -e "${green}恢复到原分支: $CURRENT_BRANCH${plain}"
    git checkout "$CURRENT_BRANCH"
fi

echo -e "${green}========================================${plain}"
echo -e "${green}同步完成！${plain}"
echo -e "${green}========================================${plain}"
echo -e "main 分支: 已同步到上游最新状态"
echo -e "dev 分支: 已 rebase 到最新的 main"
echo ""
echo -e "${yellow}如需推送到远程仓库，请手动执行:${plain}"
echo -e "  git push origin main --force-with-lease"
echo -e "  git push origin dev --force-with-lease"
