#!/usr/bin/env bash
# swap-with-parent.sh <commit-ish>
# 交换 <commit-ish> 与其父提交的位置
# 例: A→B→C→D 传入 B  =>  B→A→C→D
# 临时分支基于父的父(GRANDPARENT)创建; 原分支全程不动

set -euo pipefail

[ $# -eq 1 ] || { echo "用法: $0 <commit-ish>"; exit 1; }

TARGET=$(git rev-parse --verify "${1}^{commit}") || { echo "错误: 无效 commit"; exit 1; }

PARENT=$(git rev-parse --verify "${TARGET}^" 2>/dev/null) || {
  echo "错误: $TARGET 没有父提交"; exit 1; }

# 拒绝合并提交
[ "$(git rev-list --parents -n 1 "$TARGET" | wc -w)" -eq 2 ] || {
  echo "错误: $TARGET 是合并提交，不支持"; exit 1; }
[ "$(git rev-list --parents -n 1 "$PARENT" | wc -w)" -eq 2 ] || {
  echo "错误: 父提交 $PARENT 是合并提交，不支持"; exit 1; }

# 工作区必须干净
git diff --quiet && git diff --cached --quiet || {
  echo "错误: 工作区/暂存区不干净"; exit 1; }

# 目标必须是 HEAD 祖先
git merge-base --is-ancestor "$TARGET" HEAD || {
  echo "错误: $TARGET 不是当前 HEAD 的祖先"; exit 1; }

# 记录原位置
ORIG_BRANCH=$(git symbolic-ref --short -q HEAD || echo "")
ORIG_REF=$(git symbolic-ref -q HEAD || git rev-parse HEAD)

echo "启动位置: ${ORIG_BRANCH:-detached HEAD}"
echo "目标:     $TARGET  $(git log -1 --format=%s "$TARGET")"
echo "父提交:   $PARENT  $(git log -1 --format=%s "$PARENT")"

# 计算重放列表与回退点（此时原分支仍指向 D，B/C/D 有 ref 保护）
LATER=$(git rev-list --reverse "${TARGET}..HEAD")   # C、D...
GRANDPARENT=$(git rev-parse --verify "${PARENT}^" 2>/dev/null || true)

# 基于回退点创建临时分支
TMP="__swap_tmp_$(date +%s)"
if [ -n "$GRANDPARENT" ]; then
  git checkout -b "$TMP" "$GRANDPARENT"
else
  echo "提示: 父提交是根提交，使用 orphan 临时分支"
  git checkout --orphan "$TMP"
  git rm -rf . >/dev/null 2>&1 || true
fi

cleanup() {
  echo "→ 失败，回滚"
  git checkout -q "$ORIG_REF" 2>/dev/null || true
  git branch -D "$TMP" 2>/dev/null || true
}
trap cleanup ERR

# 施工：先 TARGET，再 PARENT，最后重放后续
echo "→ 应用目标 $TARGET ..."
git cherry-pick "$TARGET"
echo "→ 应用父提交 $PARENT ..."
git cherry-pick "$PARENT"
if [ -n "$LATER" ]; then
  echo "→ 重放后续提交 ..."
  for c in $LATER; do git cherry-pick "$c"; done
fi

trap - ERR

# 成功：原分支指向临时分支结果
if [ -n "$ORIG_BRANCH" ]; then
  git checkout -q "$ORIG_BRANCH"
  git reset --hard "$TMP"
  git branch -D "$TMP"
  echo "✅ 已更新分支 $ORIG_BRANCH"
else
  git checkout -q --detach "$TMP"
  git branch -D "$TMP"
  echo "✅ detached HEAD 已更新"
fi
