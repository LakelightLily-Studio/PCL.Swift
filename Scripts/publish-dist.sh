#!/usr/bin/env bash
# 把一次发版的更新包与清单推到国内分发仓库（GitCode）。
#
# 约定：
#   - 只推 git 内容（清单 + 图片 + 小体积 zip）：公开仓库审核期间 Release 附件接口
#     未必可用，而 API raw 直链一直可读，所以二进制跟着仓库走；
#   - token 只从环境变量读，不落盘、不进 URL（用 GIT_ASKPASS 传）；
#   - 任何一步失败都返回非 0，由 workflow 决定是否阻断。
set -eo pipefail

if [ -z "$GITCODE_TOKEN" ]; then
  echo "缺少 GITCODE_TOKEN" >&2
  exit 1
fi
if [ -z "$DIST_OWNER" ]; then DIST_OWNER=functy; fi
if [ -z "$DIST_REPO" ]; then DIST_REPO=pcl-swift-dist; fi
if [ -z "$ASSETS_DIR" ]; then ASSETS_DIR=./assets; fi
if [ -z "$TAG" ]; then
  TAG="v$(grep '^MARKETING_VERSION' Configs/Base.xcconfig | cut -d= -f2 | xargs)"
fi
VERSION=$(echo "$TAG" | sed 's/^v//')
if [ -z "$WORKDIR" ]; then WORKDIR=$(mktemp -d); fi

API_BASE="https://api.gitcode.com/api/v5/repos/$DIST_OWNER/$DIST_REPO/raw"
RAW_BASE="https://raw.gitcode.com/$DIST_OWNER/$DIST_REPO/raw/main"
if [ -z "$GITHUB_BASE" ]; then
  GITHUB_BASE="https://github.com/LakelightLily-Studio/PCL.Swift/releases/download/$TAG"
fi

echo "发布 $TAG → $DIST_OWNER/$DIST_REPO"

ASKPASS=$(mktemp)
printf '#!/bin/sh\necho "%s"\n' "$GITCODE_TOKEN" > "$ASKPASS"
chmod +x "$ASKPASS"
trap 'rm -f "$ASKPASS"' EXIT
export GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0

if [ -d "$WORKDIR/dist/.git" ]; then
  git -C "$WORKDIR/dist" fetch --depth 1 origin main
  git -C "$WORKDIR/dist" reset --hard origin/main
else
  git clone --depth 1 "https://$DIST_OWNER@gitcode.com/$DIST_OWNER/$DIST_REPO.git" "$WORKDIR/dist"
fi

mkdir -p "$WORKDIR/dist/dist"
cp "$ASSETS_DIR/PCL.Swift-$VERSION-arm64.zip" "$WORKDIR/dist/dist/"
cp "$ASSETS_DIR/PCL.Swift-$VERSION-x86_64.zip" "$WORKDIR/dist/dist/"

python3 Scripts/render_update_json.py \
  --tag "$TAG" \
  --assets-dir "$ASSETS_DIR" \
  --out "$WORKDIR/dist/update.json" \
  --base-url "$API_BASE" \
  --mirror-base "$RAW_BASE" \
  --github-base "$GITHUB_BASE" \
  --notes-url "https://github.com/LakelightLily-Studio/PCL.Swift/releases/tag/$TAG" \
  --summary "$SUMMARY" \
  --history "$WORKDIR/dist/channels/stable.json"

cp "$WORKDIR/dist/update.json" "$WORKDIR/dist/channels/stable.json"

git -C "$WORKDIR/dist" config user.name "pcl-swift-ci"
git -C "$WORKDIR/dist" config user.email "ci@users.noreply.gitcode.com"
git -C "$WORKDIR/dist" add -A

if git -C "$WORKDIR/dist" diff --cached --quiet; then
  echo "清单无变化，跳过提交"
else
  git -C "$WORKDIR/dist" commit -m "release: $VERSION"
  attempt=1
  while [ "$attempt" -le 3 ]; do
    if git -C "$WORKDIR/dist" push origin main; then
      break
    fi
    echo "push 第 $attempt 次失败，5s 后重试" >&2
    sleep 5
    attempt=$((attempt + 1))
  done
  if [ "$attempt" -gt 3 ]; then
    echo "push 连续失败" >&2
    exit 1
  fi
fi

echo "完成：$API_BASE/update.json?ref=main"
