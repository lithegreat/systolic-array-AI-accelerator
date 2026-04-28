# GitLab Issue Linking Guide | GitLab 问题关联指南

**English | 中文**

Track branches and MRs against issues like Jira—keep all work visible and linked.

像 Jira 一样跟踪分支和 MR 关联问题——保持所有工作可见且相互关联。

## Quick Start: Link a Branch to an Issue | 快速开始：关联分支到问题

### 1. Use Branch Naming Convention | 1. 使用分支命名规范

Name your branch to reference the issue:

为分支命名以引用问题：

```bash
git checkout -b 1-control-logic-reset-fix
```

**Format:** `{issue_number}-{short-description}`

**格式：** `{问题号}-{简短描述}`

GitLab will auto-detect and link this branch to Issue #1 when you push it.

当你推送时，GitLab 会自动检测并将此分支关联到问题 #1。

### 2. Create MR with Closing Action | 2. 创建带有关闭操作的合并请求

When creating a merge request, use a quick action to link it to the issue:

创建合并请求时，使用快速操作将其关联到问题：

```markdown
## Summary
Fix reset behavior in control logic

Closes #1
```

**Supported quick actions:**

**支持的快速操作：**

- `Closes #1` — Link and auto-close issue when MR merges | 链接并在 MR 合并时自动关闭问题
- `Fixes #1` — Synonym for Closes | 关闭的同义词
- `Resolves #1` — Synonym for Closes | 关闭的同义词
- `Relates to #1` — Link without auto-closing | 链接但不自动关闭
- `Blocks #2` — This MR blocks progress on Issue #2 | 此 MR 阻止问题 #2 的进展
- `Blocked by #3` — This MR is blocked by Issue #3 | 此 MR 被问题 #3 阻止

### 3. Use Work Item Relationships (GitLab 17.10+) | 3. 使用工作项关系（GitLab 17.10+）

In the MR description, establish work item hierarchy:

在 MR 描述中建立工作项层级：

```markdown
## Work Item Dependencies

**Parent:** Epic (if applicable)
**Blocks:** Issue #5 (can't start until this merges)
**Blocked by:** Issue #3 (waiting on this)
**Related:** Issue #2, Issue #4
```

## Branch Workflow Example | 分支工作流示例

### Scenario: Fixing MAC Unit Logic (Issue #2) | 场景：修复 MAC 单元逻辑（问题 #2）

1. **Create and push branch:**
   
   **创建并推送分支：**
   
   ```bash
   git checkout -b 2-mac-unit-pipeline-fix
   git push -u origin 2-mac-unit-pipeline-fix
   ```
   
   → GitLab detects issue #2 link automatically | GitLab 自动检测问题 #2 链接

2. **Create Draft MR early:**
   
   **早期创建草稿 MR：**
   
   - MR auto-links to Issue #2 | MR 自动关联到问题 #2
   - Add checks in description: | 在描述中添加检查：
     ```markdown
     /draft
     Closes #2
     
     ## Verification
     - [ ] Testbench sim/testbenches/mac_unit_tb.v passes
     ```

3. **Mark Ready for Review:**
   
   **标记准备好审查：**
   
   - When complete, remove `/draft` | 完成后，删除 `/draft`
   - Update MR with evidence and checklist | 使用证据和检查清单更新 MR
   - Reviewers see Issue #2 context in related panel | 审查者在相关面板中看到问题 #2 的上下文

4. **Merge and Auto-Close:**
   
   **合并并自动关闭：**
   
   - Merge MR → Issue #2 auto-closes | 合并 MR → 问题 #2 自动关闭
   - Branch auto-deleted | 分支自动删除
   - Commit message preserves link in history | 提交消息在历史中保留链接

## Dashboard: Track All Work | 仪表板：跟踪所有工作

### Issue Board | 问题板

1. Go to **Project > Plan > Issue boards** | 转到 **项目 > 规划 > 问题板**
2. Create a board for your module (e.g., "MAC Unit Work") | 为你的模块创建一个板（例如"MAC 单元工作"）
3. Filter by assignee and label | 按分配者和标签过滤

### Merge Request Dashboard | 合并请求仪表板

1. Go to **Project > Merge requests** | 转到 **项目 > 合并请求**
2. Filter: `state:opened author:@li` → See all your open MRs | 过滤：`state:opened author:@li` → 查看所有开放的 MR
3. View related issues in each MR's sidebar | 在每个 MR 的侧边栏中查看相关问题

### Notification/Workflow | 通知/工作流

When you link an issue to an MR:

当你关联问题到 MR 时：

- Issue subscribers get notified | 问题订阅者收到通知
- Issue shows MR in its "Related merge requests" panel | 问题在其"相关合并请求"面板中显示 MR
- MR shows issue in its "Related issues" panel | MR 在其"相关问题"面板中显示问题
- Reviewers see full issue context without clicking elsewhere | 审查者无需点击其他地方即可看到完整的问题上下文

## Git Commands for Issue Tracking | Git 问题跟踪命令

```bash
# List branches linked to issues | 列出关联到问题的分支
git branch -a | grep -E '^[0-9]+-'

# Create and push branch with issue link | 创建并推送带有问题链接的分支
git checkout -b 3-systolic-array-stall-logic
git push -u origin 3-systolic-array-stall-logic

# In your commit message, reference issue: | 在提交消息中引用问题：
git commit -m "Fix stall logic in systolic array

Related-to: #3
Closes: #3"
```

## Best Practices | 最佳实践

1. **Branch first, issue context always:**
   
   **分支优先，始终保持问题上下文：**
   
   - Name branch after issue number | 以问题号命名分支
   - One branch per issue (or clearly sub-scoped) | 每个问题一个分支（或明确的子范围）

2. **MR description must link:**
   
   **MR 描述必须关联：**
   
   - Use `Closes #N` for issue resolution | 使用 `Closes #N` 解决问题
   - Use `Relates to #N` if only loosely connected | 如果只是松散连接，使用 `Relates to #N`

3. **Update related issues in comments:**
   
   **在评论中更新相关问题：**
   
   - Add comments to parent/blocked issues as you progress | 在你的进展中向父问题/阻止问题添加评论
   - Use `/label`, `/assign`, `/unsubscribe` quick actions | 使用 `/label`、`/assign`、`/unsubscribe` 快速操作

4. **Keep templates updated:**
   
   **保持模板更新：**
   
   - Templates in `.gitlab/issue_templates/` and `.gitlab/merge_request_templates/` | 模板在 `.gitlab/issue_templates/` 和 `.gitlab/merge_request_templates/`
   - Always include module ownership and verification checkpoints | 始终包括模块所有权和验证检查点

5. **Use assignees to track ownership:**
   
   **使用分配者跟踪所有权：**
   
   - Assign issue to issue owner (per README) | 将问题分配给问题所有者（根据 README）
   - Assign MR to reviewer | 将 MR 分配给审查者
   - Use `/cc @team` to notify stakeholders | 使用 `/cc @team` 通知利益相关者

## Equivalent to Jira | Jira 等价对照

| Jira | GitLab | 说明 |
|------|--------|------|
| Issue → Link Jira issue | Quick action: `Closes #N`, `Relates to #N` | 快速操作：`Closes #N`、`Relates to #N` |
| Branch with issue key | Branch name: `N-description` | 分支名称：`N-描述` |
| Issue status (To Do, In Progress, Done) | Labels: `status::`, issue/MR state | 标签：`status::`、问题/MR 状态 |
| Epic/Component ownership | Labels + Assignee + Module path | 标签 + 分配者 + 模块路径 |
| Dependency tracking (blocker, relates) | `Blocks #N`, `Blocked by #N`, `Relates to #N` | `Blocks #N`、`Blocked by #N`、`Relates to #N` |
| Issue board | GitLab issue/MR boards | GitLab 问题/MR 板 |
| Automation (auto-close on merge) | MR quick actions: `Closes #N` | MR 快速操作：`Closes #N` |

## References | 参考资源

- [GitLab: Linking issues and MRs](https://docs.gitlab.com/ee/user/project/issues/managing_issues.html#linking-issues) | [GitLab：关联问题和 MR](https://docs.gitlab.com/ee/user/project/issues/managing_issues.html#linking-issues)
- [GitLab: Quick actions](https://docs.gitlab.com/ee/user/project/quick_actions.html) | [GitLab：快速操作](https://docs.gitlab.com/ee/user/project/quick_actions.html)
- [GitLab: Work items (17.10+)](https://docs.gitlab.com/ee/user/work_items/) | [GitLab：工作项 (17.10+)](https://docs.gitlab.com/ee/user/work_items/)
