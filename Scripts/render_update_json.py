#!/usr/bin/env python3
"""把一次发版的产物渲染成 update.json。

只做机械转换：哈希现算、历史保留、字段顺序固定（方便 diff）。
"""

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone, timedelta


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--assets-dir", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--mirror-base", default="")
    parser.add_argument("--github-base", default="")
    parser.add_argument("--notes-url", default="")
    parser.add_argument("--summary", default="")
    parser.add_argument("--rollout", type=int, default=100)
    parser.add_argument("--history", default="")
    args = parser.parse_args()

    version = args.tag.lstrip("vV")
    assets = {}
    for arch in ("arm64", "x86_64"):
        name = "PCL.Swift-" + version + "-" + arch + ".zip"
        path = os.path.join(args.assets_dir, name)
        if not os.path.exists(path):
            print("缺少产物：" + name, file=sys.stderr)
            return 1
        mirrors = []
        if args.mirror_base:
            mirrors.append(args.mirror_base + "/" + name)
        if args.github_base:
            mirrors.append(args.github_base + "/" + name)
        assets[arch] = {
            "url": args.base_url + "/dist/" + name,
            "mirrors": mirrors,
            "size": os.path.getsize(path),
            "sha256": sha256_of(path),
        }

    releases = []
    if args.history and os.path.exists(args.history):
        try:
            with open(args.history, "r", encoding="utf-8") as handle:
                releases = json.load(handle).get("releases", [])
        except (OSError, ValueError) as error:
            print("历史清单读取失败，按空处理：" + str(error), file=sys.stderr)
    releases = [item for item in releases if item.get("version") != version]

    now = datetime.now(timezone(timedelta(hours=8))).replace(microsecond=0).isoformat()
    releases.insert(0, {
        "version": version,
        "tag": args.tag,
        "published_at": now,
        "prerelease": False,
        "yanked": False,
        "rollout": args.rollout,
        "name": version,
        "summary": args.summary,
        "notes_url": args.notes_url,
        "min_macos": "12.0",
        "assets": assets,
    })

    manifest = {
        "schema": 1,
        "channel": "stable",
        "generated_at": now,
        "latest": version,
        "min_supported": "2.0.0",
        "releases": releases[:10],
    }
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print("已写入 " + args.out + "（" + str(len(manifest["releases"])) + " 个版本）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
