# 云端代码审查配置指南

本指南说明如何配置 GitHub Actions 云端代码审查，使 PR 指向 `main` 时自动触发 Claude Code 审查。

## 前提条件

- GitHub 仓库（public 或 private）
- `gh` CLI 已安装且已认证
- Claude Code 插件已安装

## GitHub Secrets 配置

需要在仓库 Settings > Secrets and variables > Actions 中配置以下 secrets：

| Secret 名称 | 说明 | 示例 |
|-------------|------|------|
| `ANTHROPIC_AUTH_TOKEN` | Anthropic API 认证令牌（通过 Backgrace 中继） | `sk-ant-...` |
| `ANTHROPIC_BASE_URL` | Backgrace 中继端点 URL | `https://your-relay.example.com` |

### 配置步骤

```bash
# 使用 gh CLI 配置 secrets
gh secret set ANTHROPIC_AUTH_TOKEN
# 粘贴你的 API 令牌，按 Enter

gh secret set ANTHROPIC_BASE_URL
# 粘贴你的 Backgrace 中继 URL，按 Enter
```

或通过 GitHub Web UI：`Settings > Secrets and variables > Actions > New repository secret`

### 验证 secrets 已配置

```bash
# 使用 /setup-repo 自动检测
# 在 Claude Code 中运行：
/setup-repo
```

脚本会检测 `ANTHROPIC_AUTH_TOKEN` 和 `ANTHROPIC_BASE_URL` 是否已配置。

## Workflow 文件

插件通过 `/setup-repo` 命令自动生成 `.github/workflows/claude-code-review.yml`。
你也可以手动创建或参考已有的工作流文件。

### 工作流结构

```yaml
name: Claude Code Review

on:
  pull_request:
    types: [opened, synchronize, ready_for_review, reopened]
    branches: [main]  # 仅在 PR 指向 main 时触发

jobs:
  claude-review:
    if: github.event.pull_request.draft == false
    runs-on: ubuntu-latest
    timeout-minutes: 60  # 审查可能需要较长时间
    permissions:
      contents: read
      pull-requests: write
      issues: write
      id-token: write
      actions: read
```

### 关键配置项

| 配置 | 说明 |
|------|------|
| `timeout-minutes: 60` | 云端审查可能需要较长时间，建议设置 60 分钟超时 |
| `claude_args` | 限制可用工具集，防止审查过程执行危险操作 |
| `show_full_output: true` | 显示完整审查输出用于调试 |
| `prompt` | 包含 REPO 和 PR NUMBER 上下文，确保审查定位正确 |

### 工具权限（claude_args）

审查工作流限制了 Claude 可使用的工具：

```
--allowedTools "Skill,Agent,Read,Glob,Grep,
  Bash(gh:*),Bash(git blame:*),Bash(git log:*),
  Bash(git diff:*),Bash(git show:*),Bash(cat:*),
  Bash(head:*),Bash(wc:*),Bash(find:*),Bash(ls:*),
  mcp__github_inline_comment__create_inline_comment"
```

这确保审查只能读取代码和创建评论，不能修改文件或执行危险命令。

## Backgrace 中继

如果你的组织使用 Backgrace 中继服务访问 Anthropic API：

1. 在中继服务中注册你的 API 密钥
2. 获取中继端点 URL（`ANTHROPIC_BASE_URL`）
3. 获取认证令牌（`ANTHROPIC_AUTH_TOKEN`）
4. 将两者配置为 GitHub Secrets

### API 连通性验证

工作流包含一个 API 连通性验证步骤，在运行审查前检查中继是否可达：

```yaml
- name: Verify API connectivity
  env:
    ANTHROPIC_BASE_URL: ${{ secrets.ANTHROPIC_BASE_URL }}
    ANTHROPIC_AUTH_TOKEN: ${{ secrets.ANTHROPIC_AUTH_TOKEN }}
  run: |
    set +e
    curl -s --connect-timeout 10 --max-time 15 \
      -X POST "${ANTHROPIC_BASE_URL}/v1/messages" \
      -H "x-api-key: ${ANTHROPIC_AUTH_TOKEN}" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d '{"model":"claude-sonnet-4-6","max_tokens":10,...}' \
      -o /dev/null -w "HTTP %{http_code}" && echo " OK" || echo "::warning::API connectivity check failed"
```

如果连通性检查失败，工作流会发出警告但仍继续执行。

## 审查追踪（Review Tracker）

### 本地 JSON DB

PR 审查状态通过 `.claude/review-tracker.json` 本地追踪，支持跨会话恢复。

```bash
# 手动操作追踪器
bash scripts/review-tracker.sh list        # 列出所有追踪的 PR
bash scripts/review-tracker.sh status 42   # 查看 PR #42 状态
bash scripts/review-tracker.sh cleanup     # 清理已完成的 PR
```

### 状态流转

```
pending_review → fixing → pending_review (新 round)
pending_review → passed
pending_review → closed (PR 被合并或关闭)
```

### review-watcher Teammate

当 `/create-pr` 创建指向 `main` 的 PR 时，会自动提供 spawn review-watcher teammate 的选项。
review-watcher 在后台运行：

1. 每 60 秒轮询 GitHub Actions 审查状态
2. 审查完成后获取评论
3. **代码级问题**（语法、格式、变量）→ 自动修复 + push
4. **逻辑级问题**（架构、设计）→ SendMessage 通知主控等待人类决策
5. PR 被合并或关闭 → 更新追踪器 → 关闭

## 故障排除

### 审查未触发

1. 检查 PR 是否指向 `main` 分支
2. 检查 PR 是否为 draft 状态（draft PR 不触发审查）
3. 确认 `.github/workflows/claude-code-review.yml` 已提交并推送
4. 运行 `/setup-repo` 检查配置

### 审查超时

- 默认超时 60 分钟，大型 PR 可能需要更长时间
- 考虑将 PR 拆分为更小的变更集
- 检查 `timeout-minutes` 设置

### API 连接失败

1. 验证 `ANTHROPIC_BASE_URL` 是否正确：
   ```bash
   curl -s "${ANTHROPIC_BASE_URL}/v1/messages" -H "x-api-key: ${ANTHROPIC_AUTH_TOKEN}" -w "%{http_code}"
   ```
2. 检查中继服务是否在线
3. 确认 `ANTHROPIC_AUTH_TOKEN` 未过期

### 工具权限错误

如果审查报告工具权限不足：
- 检查 `claude_args` 中的 `--allowedTools` 是否包含所需工具
- 确保 `actions: read` 权限已配置

### review-watcher 问题

- 如果 review-watcher 未收到通知，手动运行 `/check-review`
- 确认 `scripts/review-tracker.sh` 可执行：`chmod +x scripts/review-tracker.sh`
- 检查 `.claude/review-tracker.json` 是否存在且格式正确

## 参考

- [Claude Code Action](https://github.com/anthropics/claude-code-action) — GitHub Actions 集成
- [架构决策](architecture.md) — ADR-009: Teammates 审查引擎架构
