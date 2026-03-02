# Changelog

本文件记录 Git Collaboration Workflow Plugin 的所有版本变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [1.6.0] - 2026-02-27

### Changed
- `setup-github-repo.sh` — `check_branch_protection()` 从 5 次 API 调用合并为 1 次（单次 `--jq` CSV 提取）
- `json_escape()` 使用 `printf '%s'` 替代 `echo`，新增 `\r` 转义处理
- 插件版本从 1.5.0 升级到 1.6.0

### Fixed
- `check_branch_protection()` 冗余 API 调用导致的性能问题和潜在速率限制风险
- `json_escape()` 使用 `echo` 可能误解释反斜杠参数和添加多余换行

## [1.5.0] - 2026-02-27

### Added
- `/setup-repo` 技能 — 检测并配置 GitHub 仓库最佳实践设置
  - `scripts/setup-github-repo.sh` — 三模式脚本（check / apply / create-and-apply）
  - 检查：合并策略（squash-only）、分支保护（main/integration）、SemVer 标签
  - 配置：一键应用所有最佳实践设置，GitHub Free Plan 自动降级兼容
- `check-repo-status.sh` 新增检查 #8：GitHub 远程仓库和分支保护检测
  - 无 GitHub remote → 推荐 `/setup-repo` 创建仓库
  - 有 remote 但 main 无保护 → 推荐 `/setup-repo` 配置保护
- `/check-status` 检测规则新增：无 GitHub remote、main 分支无保护

### Changed
- 插件版本从 1.4.0 升级到 1.5.0
- README.md 更新项目结构和技能列表

## [1.4.0] - 2026-02-26

### Added
- 所有技能添加配套脚本，实现「脚本收集数据 + LLM 编排交互」模式
  - `scripts/start-feature.sh` — 原子化分支创建（验证、fetch、创建、push）
  - `scripts/sync-branch.sh` — 自动 rebase + force-with-lease + stash 管理
  - `scripts/create-pr-preflight.sh` — PR 预检（变更文件、冲突检测、SemVer 建议）
  - `scripts/prepare-release-data.sh` — 发布数据收集（PR 列表、版本计算、changelog）
  - `scripts/hotfix-setup.sh` — 热修复分支原子化创建
  - `scripts/rollback-preflight.sh` — 回滚预检（版本信息、风险评估、复杂度判断）
  - `scripts/cleanup-branches.sh` — 已合并/陈旧分支候选收集
  - `scripts/repo-graph-data.sh` — 仓库拓扑数据收集（分支、提交、关系结构化 JSON）
  - `scripts/review-pr-diff.sh` — 代码审查差异数据收集（文件分类、变更统计）

### Changed
- 全部 10 个 skill .md 文件重写，从「逐步执行 git 命令」升级为「调用脚本解析 JSON + 编排用户交互」
- 插件版本从 1.3.0 升级到 1.4.0

## [1.3.0] - 2026-02-26

### Added
- 4 个命令脚本实现混合 hook 架构（命令 + Prompt 并行）
  - `scripts/validate-commit-msg.sh` — Conventional Commits 正则验证
  - `scripts/validate-branch-name.sh` — 分支命名正则验证
  - `scripts/scan-secrets.sh` — 凭证模式文件扫描（实际读取文件内容）
  - `scripts/scan-conflict-markers.sh` — 冲突标记文件扫描（实际读取文件内容）
- `/review-pr` 技能 — 结构化代码审查（5 维度：正确性/安全性/性能/风格/架构）
- `README.md` 中文项目文档
- `CHANGELOG.md` 版本历史
- `LICENSE` MIT 许可证

### Changed
- hooks.json 从纯 Prompt 升级为 4 个混合 hook（命令脚本 + Prompt 并行执行）
- 插件版本从 1.2.0 升级到 1.3.0
- 架构说明更新（ADR-007: 混合 Hook 策略）

### Fixed
- detect-secrets 和 detect-conflict-markers 不再依赖对话上下文 — 命令脚本直接扫描文件内容

## [1.2.0] - 2026-02-26

### Added
- `/repo-graph` 技能 — Mermaid 分支拓扑图、提交时间线、分支状态图
- `/check-status` 检测规则：本地 commits 未推送、已推送但无 PR

### Changed
- 插件版本从 1.1.0 升级到 1.2.0

## [1.1.0] - 2026-02-26

### Added
- `SessionStart` hook — 会话启动时自动检测仓库状态
- `scripts/check-repo-status.sh` — 仓库状态检查脚本
- `/check-status` 技能 — 手动健康检查，推荐操作 + 原因 + 审批

### Changed
- hooks.json 从 8 个 hook 扩展到 9 个（新增 SessionStart）
- 插件版本从 1.0.0 升级到 1.1.0

## [1.0.0] - 2026-02-26

### Added
- 初始版本发布
- 7 个 PreToolUse prompt hook（prevent-direct-push, prevent-force-push, prevent-rebase-shared, detect-conflict-markers, enforce-commit-format, enforce-branch-naming, detect-secrets）
- 1 个 PostToolUse prompt hook（pr-scope-check）
- 7 个技能（/start-feature, /sync-branch, /create-pr, /prepare-release, /hotfix, /rollback, /cleanup-branches）
- 1 个代理（merge-bot）
- `.secretsignore` 凭证白名单
- `VALIDATION.md` 安装验证清单
- `docs/` 完整文档（setup-guide, architecture, workflow-reference）
