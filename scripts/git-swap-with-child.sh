#!/usr/bin/env bash
# swap-with-child.sh <commit-id>
# 交换 <commit-id> 与其直接子提交的位置
# 例: A→B→C→D 传入 B  =>  A→C→B→D
# 临时分支基于 TARGET^ 创建; 原分支全程不动

set -euo pipefail

[ $# -eq 1 ] || { echo "用法: $0 <commit-id>"; exit 1; }

TARGET=$(git rev-parse --verify "${1}^{commit}") || { echo "错误: 无效 commit"; exit 1; }

# 直接子提交：TARGET..HEAD 的 ancestry-path 中最早的一个
CHILD=$(git rev-list --ancestry-path --reverse "${TARGET}..HEAD" | head -n1 || true)
[ -n "$CHILD" ] || { echo "错误: $TARGET 没有子提交"; exit 1; }

# 拒绝合并提交
for c in "$TARGET" "$CHILD"; do
  [ "$(git rev-list --parents -n 1 "$c" | wc -w)" -eq 2 ] || {
    echo "错误: $c 是合并提交，不支持"; exit 1; }
done

# 工作区干净
git diff --quiet && git diff --cached --quiet || {
  echo "错误: 工作区/暂存区不干净"; exit 1; }

git merge-base --is-ancestor "$TARGET" HEAD || {
  echo "错误: $TARGET 不是 HEAD 的祖先"; exit 1; }

# 记录原位置
ORIG_BRANCH=$(git symbolic-ref --short -q HEAD || echo "")
ORIG_REF=$(git symbolic-ref -q HEAD || git rev-parse HEAD)

echo "启动位置: ${ORIG_BRANCH:-detached HEAD}"
echo "目标:     $TARGET  $(git log -1 --format=%s "$TARGET")"
echo "子提交:   $CHILD   $(git log -1 --format=%s "$CHILD")"

# 回退点 = TARGET 的父
PARENT_OF_TARGET=$(git rev-parse --verify "${TARGET}^" 2>/dev/null) || {
  echo "错误: 目标是根提交，本脚本不支持"; exit 1; }

# 重放列表 = CHILD 之后的提交
LATER=$(git rev-list --reverse "${CHILD}..HEAD")

# 基于回退点创建临时分支（原分支不动，B/C/D 有 ref 保护）
TMP="__swap_tmp_$(date +%s)"
git checkout -b "$TMP" "$PARENT_OF_TARGET"

cleanup() {
  echo "→ 失败，回滚"
  git checkout -q "$ORIG_REF" 2>/dev/null || true
  git branch -D "$TMP" 2>/dev/null || true
}
trap cleanup ERR

# 施工：先 CHILD，再 TARGET，最后重放后续
echo "→ 应用子提交 $CHILD ..."
git cherry-pick "$CHILD"
echo "→ 应用目标 $TARGET ..."
git cherry-pick "$TARGET"
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
