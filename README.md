# Git Collaboration Workflow Plugin

适用于 Claude Code 的 Git 协作工作流插件 — 为多人 + 多 AI 团队提供分支保护、规范执行和自动化工作流。

## 功能概览

### 安全守卫（Hooks）— 自动触发，无需手动调用

| Hook | 触发条件 | 行为 | 实现方式 |
|------|---------|------|---------|
| prevent-direct-push | `git push` 到 main/integration | main 硬阻止 / integration 需确认 | Prompt |
| prevent-force-push | `git push --force` | main 硬阻止 / integration 需确认 / feature 警告 | Prompt |
| prevent-rebase-shared | `git rebase`（在 main/integration 上） | 硬阻止 | Prompt |
| enforce-commit-format | `git commit -m "..."` | 不符合 Conventional Commits 规范则阻止 | **Command + Prompt** |
| enforce-branch-naming | `git checkout -b ...` | 不符合命名规范则阻止 | **Command + Prompt** |
| detect-secrets | `git add` / `git commit` | 检测到凭证则阻止 | **Command + Prompt** |
| detect-conflict-markers | `git add` / `git commit` | 检测到冲突标记则阻止 | **Command + Prompt** |
| pr-scope-check | `git diff --stat` 后 | 超过 20 文件警告 | Prompt |
| repo-status-check | 会话启动时 | 检测仓库状态，推荐操作 + 需审批 | Command |

**混合架构**：4 个确定性验证同时使用命令脚本（毫秒级响应）和 Prompt（处理边界情况），并行执行取最严结果。

### 技能命令（Skills）— 用户按需调用

| 命令 | 功能 |
|------|------|
| `/start-feature` | 从 integration 创建规范命名的 feature 分支 |
| `/sync-branch` | 将 feature 分支 rebase 到最新 integration |
| `/create-pr` | 创建带模板、SemVer 标签和冲突检测的 PR |
| `/prepare-release` | 从 integration 创建发布 PR 到 main |
| `/hotfix` | 紧急修复：从 main 创建 hotfix → PR → cherry-pick 到 integration |
| `/rollback` | 回滚最近一次 main 上的发布 |
| `/cleanup-branches` | 清理已合并的 feature 分支 |
| `/check-status` | 仓库健康检查，推荐操作 + 原因 + 需审批 |
| `/setup-repo` | 检测并配置 GitHub 仓库最佳实践设置（分支保护、合并策略、SemVer 标签） |
| `/repo-graph` | 生成 Mermaid 分支拓扑图、提交时间线、分支状态图 |
| `/review-pr` | 结构化代码审查（正确性/安全性/性能/风格/架构 5 个维度） |

### 自动化代理（Agent）

| 代理 | 功能 | 工具 |
|------|------|------|
| merge-bot | 监控 PR，CI 通过后自动入队 Merge Queue | Bash, Read |

## 快速安装

### 前提条件

```bash
git --version        # >= 2.30
claude --version     # 最新或上一个大版本
gh --version         # >= 2.0
gh auth status       # 需已登录
```

### 安装步骤

```bash
# 1. 复制插件到项目目录
mkdir -p .claude/plugins
cp -r git-collaboration-workflow .claude/plugins/

# 2. 确保仓库有 integration 分支
git checkout -b integration 2>/dev/null || git checkout integration
git push -u origin integration

# 3. 重启 Claude Code（hooks 在会话启动时加载）
claude
```

### 验证安装

```bash
# 这应该被 阻止：
git commit -m "fixed stuff"

# 这应该被 允许：
git commit -m "feat: add initial feature"
```

详细配置请参考 [docs/setup-guide.md](docs/setup-guide.md)。

## 架构

```
                    ┌─────────┐
                    │  main   │  硬阻止（不可绕过）
                    └────┬────┘
                         │
                    ┌────┴────┐
                    │integra- │  软阻止（用户可确认）
                    │  tion   │
                    └────┬────┘
                         │
              ┌──────────┼──────────┐
              │          │          │
         ┌────┴───┐ ┌───┴────┐ ┌──┴─────┐
         │feature/│ │hotfix/ │ │release/│  仅警告
         │  ...   │ │  ...   │ │  ...   │  （允许通过）
         └────────┘ └────────┘ └────────┘
```

### 防御层次

| 层级 | 类型 | 响应速度 | 覆盖范围 |
|------|------|---------|---------|
| **命令脚本** | 确定性正则/文件扫描 | < 1 秒 | commit 格式、分支命名、凭证、冲突标记 |
| **Prompt 评估** | LLM 上下文推理 | 10-30 秒 | 所有 hook（含边界情况处理） |
| **GitHub 保护** | 服务端规则 | 推送时 | 分支保护、必需审批、状态检查 |

命令脚本和 Prompt 并行执行 — 脚本提供即时反馈，Prompt 捕获脚本遗漏的复杂场景。

### Commit 规范

```
<type>[optional scope]: <description>

类型: feat fix docs chore refactor test ci build perf style
```

示例：`feat: add login page` / `fix(auth): resolve token bug` / `chore!: drop Node 14`

### 分支命名

```
<type>/<kebab-case-name>

类型: feature phase hotfix release
```

示例：`feature/alice-login` / `hotfix/fix-auth-crash` / `release/v1.2.0`

## 项目结构

```
git-collaboration-workflow/
├── .claude-plugin/
│   └── plugin.json                 # 插件清单（v1.5.0）
├── .secretsignore                  # 凭证白名单
├── VALIDATION.md                   # 安装验证清单
├── README.md                       # 本文件
├── CHANGELOG.md                    # 版本历史
├── LICENSE                         # MIT 许可证
├── hooks/
│   └── hooks.json                  # 13 个 hook 实例（含 4 个混合 command+prompt hook）
├── scripts/
│   ├── check-repo-status.sh        # SessionStart 仓库状态检查
│   ├── setup-github-repo.sh        # GitHub 仓库最佳实践检查与配置
│   ├── validate-commit-msg.sh      # Conventional Commits 正则验证
│   ├── validate-branch-name.sh     # 分支命名正则验证
│   ├── scan-secrets.sh             # 凭证模式文件扫描
│   ├── scan-conflict-markers.sh    # 冲突标记文件扫描
│   ├── start-feature.sh            # 分支创建 + 活跃 PR 冲突预警
│   ├── sync-branch.sh              # Rebase + force-with-lease + stash 管理
│   ├── create-pr-preflight.sh      # PR 预检（变更文件、冲突、SemVer）
│   ├── prepare-release-data.sh     # 发布数据收集（PR 列表、版本计算）
│   ├── hotfix-setup.sh             # Hotfix 分支原子创建
│   ├── rollback-preflight.sh       # 回滚预检（版本信息、风险评估）
│   ├── cleanup-branches.sh         # 已合并/过期分支候选收集
│   ├── repo-graph-data.sh          # 仓库拓扑结构化 JSON（供 Mermaid 渲染）
│   └── review-pr-diff.sh           # 代码审查 diff 数据 + 文件分类
├── skills/
│   ├── start-feature/
│   │   └── SKILL.md                # /start-feature — 创建 feature 分支
│   ├── sync-branch/
│   │   └── SKILL.md                # /sync-branch — rebase 同步
│   ├── create-pr/
│   │   └── SKILL.md                # /create-pr — 创建 PR
│   ├── prepare-release/
│   │   └── SKILL.md                # /prepare-release — 准备发布
│   ├── hotfix/
│   │   └── SKILL.md                # /hotfix — 紧急修复
│   ├── rollback/
│   │   └── SKILL.md                # /rollback — 回滚发布
│   ├── cleanup-branches/
│   │   └── SKILL.md                # /cleanup-branches — 清理分支
│   ├── check-status/
│   │   └── SKILL.md                # /check-status — 仓库健康检查
│   ├── setup-repo/
│   │   └── SKILL.md                # /setup-repo — GitHub 仓库最佳实践配置
│   ├── repo-graph/
│   │   └── SKILL.md                # /repo-graph — 分支拓扑可视化
│   └── review-pr/
│       └── SKILL.md                # /review-pr — 结构化代码审查
├── agents/
│   └── merge-bot.md                # 自动合并代理
└── docs/
    ├── setup-guide.md              # 从 0 到 1 完整配置指南
    ├── architecture.md             # 架构决策记录（8 个 ADR）
    └── workflow-reference.md       # 命令速查卡
```

## 文档

- **[安装配置指南](docs/setup-guide.md)** — 完整的从零开始配置流程
- **[架构决策](docs/architecture.md)** — 8 个 ADR 记录设计决策和理由
- **[命令速查卡](docs/workflow-reference.md)** — 所有 skill、hook、格式规范速查
- **[验证清单](VALIDATION.md)** — 安装后逐项验证

## 设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| Hook 实现 | 命令脚本 + Prompt 混合 | 确定性检查用脚本（快），推理性检查用 Prompt（准） |
| Hook 配置 | 单一 hooks.json | 符合 Claude Code 插件 API，便于管理 |
| 阻止策略 | 三级分层 | main 硬阻止 / integration 软阻止 / feature 仅警告 |
| SemVer | PR 标签驱动 | 可见、可编辑、可查询，人类可覆盖 |
| 代码审查 | 插件内 Skill | 审查需要交互讨论 + 完整工具链，agent 受限太多 |
| 职责边界 | 仅开发侧验证 | GitHub 分支保护处理服务端，插件处理客户端 |

## 适用场景

- 多人协作的 GitHub 项目
- 多 AI Agent 并行开发的团队
- 需要规范化 Git 工作流的组织
- 需要自动化发布流程的产品团队

## 许可证

MIT License
