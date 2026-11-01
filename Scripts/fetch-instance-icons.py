#!/usr/bin/env python3
"""
下载实例图标的预设图（23 个原版方块 / 物品）。

来源：红河素材站（https://honghemc.cn/app/，Minecraft 图标库，1024×1024 透明 PNG）。
站点的文件路径规则是 /images/<分类>/<子分类>/<文件名>，分类与子分类带编号前缀，
所以下面的表里原样抄了站点的写法；换版本时按站点目录改这张表即可。

四个模组加载器的图标（neoforge / fabric / quilt / optifine）**不在这里**：
它们不是原版素材，取自 PCL2 与各自官网，直接放在 dist-assets/icons 里。

用法（在仓库根目录）：
    python3 Scripts/fetch-instance-icons.py            # 写入 dist-assets/icons
    python3 Scripts/fetch-instance-icons.py --out /tmp/icons

依赖：Pillow（下载后统一缩到 256×256，仓库与 App 里的那份都用这个尺寸）。
"""

import argparse
import io
import os
import urllib.parse
import urllib.request

from PIL import Image

BASE = "https://honghemc.cn/images/"
# 站点的图片带 30 天 immutable 缓存，换图后这个号跟着站点的 IMG_V 改。
IMAGE_VERSION = "20261021"
SIZE = 256

# slug -> (分类, 子分类, 站点文件名)
ICONS = {
    "grass_block": ("20. Blocks", "18. Decoration", "Grass_Block.png"),
    "stone": ("20. Blocks", "18. Decoration", "Stone.png"),
    "mossy_cobblestone": ("20. Blocks", "18. Decoration", "Mossy_Cobblestone.png"),
    "iron_block": ("20. Blocks", "08. Material", "Iron_Block.png"),
    "gold_block": ("20. Blocks", "08. Material", "Gold_Block.png"),
    "diamond_block": ("20. Blocks", "08. Material", "Diamond_Block.png"),
    "nether_wart_block": ("20. Blocks", "37. Nether", "Nether_Wart_Block.png"),
    "oak_sapling": ("10. Items", "13. Farmables", "Oak_Sapling.png"),
    "crafting_table": ("20. Blocks", "33. Workplaces", "Crafting_Table.png"),
    "furnace": ("20. Blocks", "33. Workplaces", "Furnace.png"),
    "anvil": ("20. Blocks", "33. Workplaces", "Anvil.png"),
    "item_frame": ("10. Items", "21. Decoration", "Item_Frame.png"),
    "iron_pickaxe": ("10. Items", "2. Pickaxes", "Iron_Pickaxe.png"),
    "water_bucket": ("10. Items", "19. Buckets", "Water_Bucket.png"),
    "diamond_sword": ("10. Items", "1. Swords", "Diamond_Sword.png"),
    "totem_of_undying": ("10. Items", "18. Consumables", "Totem_Of_Undying.png"),
    "bread": ("10. Items", "10. Food", "Bread.png"),
    "carrot": ("10. Items", "10. Food", "Carrot.png"),
    "cooked_porkchop": ("10. Items", "10. Food", "Cooked_Porkchop.png"),
    "golden_apple": ("10. Items", "18. Consumables", "Golden_Apple.png"),
    "potion": ("10. Items", "14. Potions", "Potion.png"),
    "paper": ("10. Items", "34. Uncategorized", "Paper.png"),
    "egg": ("10. Items", "15. Projectiles", "Egg.png"),
}


def url_for(category: str, subcategory: str, name: str) -> str:
    parts = [category, subcategory, name]
    return BASE + "/".join(urllib.parse.quote(part) for part in parts) + f"?v={IMAGE_VERSION}"


def fetch(slug: str, out_dir: str) -> None:
    category, subcategory, name = ICONS[slug]
    url = url_for(category, subcategory, name)
    with urllib.request.urlopen(url, timeout=60) as response:
        data = response.read()
    image = Image.open(io.BytesIO(data)).convert("RGBA")
    # 站点是 1024×1024，统一缩到 256：App 里最大只用到 36pt，2x 也只要 72px。
    image = image.resize((SIZE, SIZE), Image.LANCZOS)
    path = os.path.join(out_dir, slug + ".png")
    image.save(path, optimize=True)
    print(f"{slug:20s} {os.path.getsize(path):7d} B  {url}")


def main() -> None:
    parser = argparse.ArgumentParser(description="下载实例图标的预设图")
    parser.add_argument("--out", default=os.path.join("dist-assets", "icons"), help="输出目录")
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for slug in ICONS:
        fetch(slug, args.out)
    print(f"完成：{len(ICONS)} 张 → {args.out}")


if __name__ == "__main__":
    main()
