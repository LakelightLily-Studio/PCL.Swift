#!/usr/bin/env bash
# 把一次发版的更新包与清单推到国内分发仓库（GitCode）。
#
# 约定：
#   - 只推 git 内容（清单 + 图片 + 小体积 zip）：公开仓库审核期间 Release 附件接口
#     未必可用，而 API raw 直链一直可读，所以二进制跟着仓库走；
#   - token 只从环境变量读，不落盘、不进 URL（用 GIT_ASKPASS 传）；
#   - 任何一步失败都返回非 0，由 workflow 决定是否阻断。
#
# 只同步静态资源（头像 / 更新日志）时用 ASSETS_ONLY=1：跳过更新包与清单，
# 其余流程（克隆、提交、推送、重试）完全一样。见 .github/workflows/publish-dist.yml。
set -eo pipefail
ASSETS_ONLY=${ASSETS_ONLY:-0}

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

if [ "$ASSETS_ONLY" != "1" ]; then
  mkdir -p "$WORKDIR/dist/dist"
  cp "$ASSETS_DIR/PCL.Swift-$VERSION-arm64.zip" "$WORKDIR/dist/dist/"
  cp "$ASSETS_DIR/PCL.Swift-$VERSION-x86_64.zip" "$WORKDIR/dist/dist/"
fi

# 头像与更新日志：这两类资源不需要跟着发版走（客户端会自己刷新），
# 但每次发版顺手同步一次，国内仓库里的副本才不会落后于仓库里的源。
#   assets/about/<Name>.png —— 「更多」页的头像，文件名 = Assets.xcassets 里 imageset 的名字；
#   changelog.md            —— 主页预设「PCL.Swift 更新日志」读的那份。
sync_about_avatars() {
  local src="PCL.Swift/Assets.xcassets/Avatars"
  local dst="$WORKDIR/dist/assets/about"
  local imageset name best candidate png
  mkdir -p "$dst"
  for imageset in "$src"/*.imageset; do
    [ -d "$imageset" ] || continue
    name=$(basename "$imageset" .imageset)
    best=""
    # 取分辨率最高的那张位图；只有 SVG 的（PCLProto）走下面的预渲染补位。
    for candidate in "$imageset/$name@3x.png" "$imageset/$name@2x.png" "$imageset/$name.png"; do
      if [ -f "$candidate" ]; then
        best="$candidate"
        break
      fi
    done
    if [ -n "$best" ]; then
      cp "$best" "$dst/$name.png"
    fi
  done
  # SVG 头像没法在 ubuntu 上转位图，仓库里放了一份预渲染的（dist-assets/about）。
  if [ -d dist-assets/about ]; then
    for png in dist-assets/about/*.png; do
      [ -f "$png" ] || continue
      cp "$png" "$dst/"
    done
  fi
  echo "头像：$(ls "$dst" | wc -l | xargs) 张 → assets/about"
}

# 实例图标：图标选择器里的那些方块 / 物品（assets/icons/<id>.png，文件名就是图标的 id）。
# 客户端取不到时会退回打包在 App 里的同一张图，所以这里缺几张不会让选择器变成空格子。
sync_instance_icons() {
  local src="dist-assets/icons"
  local dst="$WORKDIR/dist/assets/icons"
  [ -d "$src" ] || return 0
  mkdir -p "$dst"
  cp "$src"/*.png "$dst/"
  echo "实例图标：$(ls "$dst" | wc -l | xargs) 张 → assets/icons"
}

sync_about_avatars
sync_instance_icons
cp CHANGELOG.md "$WORKDIR/dist/changelog.md"

if [ "$ASSETS_ONLY" != "1" ]; then
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
fi

COMMIT_MESSAGE="release: $VERSION"
if [ "$ASSETS_ONLY" = "1" ]; then
  COMMIT_MESSAGE="assets: 同步头像与更新日志"
fi

git -C "$WORKDIR/dist" config user.name "pcl-swift-ci"
git -C "$WORKDIR/dist" config user.email "ci@users.noreply.gitcode.com"
git -C "$WORKDIR/dist" add -A

if git -C "$WORKDIR/dist" diff --cached --quiet; then
  echo "国内仓库无变化，跳过提交"
else
  git -C "$WORKDIR/dist" commit -m "$COMMIT_MESSAGE"
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

if [ "$ASSETS_ONLY" = "1" ]; then
  echo "完成：$API_BASE/assets/about?ref=main"
else
  echo "完成：$API_BASE/update.json?ref=main"
fi
