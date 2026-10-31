#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PCL.Swift 实例图标生成器 —— 27 张 128x128 透明 PNG（dist-assets/icons/）。

用法（在仓库根目录直接跑）：

    python3 Scripts/generate-instance-icons.py
    python3 Scripts/generate-instance-icons.py --contact /tmp/pclwork/icons_contact.png

只依赖 Pillow。不联网、不下载任何东西。


一、素材从哪来（脚本不负责下载）
--------------------------------
1) Minecraft 官方客户端贴图（方块 / 物品）：
   这些贴图必须从官方 client.jar 里解包，**脚本刻意不做下载**（client.jar 约 40MB，
   属于外部产物，不该混进仓库或构建流程）。手动准备一次即可：

       # 用官方启动器 / 任意渠道拿到与目标版本一致的 client.jar，然后：
       unzip -o client.jar 'assets/minecraft/textures/*' -d /tmp/mcassets/extract

   解包后应当存在：
       /tmp/mcassets/extract/assets/minecraft/textures/{item,block}/*.png

   本脚本读取的根目录由环境变量 PCL_MC_ASSETS 覆盖（默认 /tmp/mcassets/extract）。
   目录缺失时脚本会直接报错退出，并打印上面这条 unzip 命令。

2) PCL2 的参考图标（铁砧 / NeoForge / Fabric）：
   默认读 /tmp/pcl2/Plain Craft Launcher 2/Images/Blocks/，可用 PCL2_BLOCKS 覆盖。
   这三张是 PCL2 自带的 64x64 / 48x48 位图（Anvil 是 3D 铁砧渲染）。

3) Quilt / OptiFine 的 logo：
   官方取图后缓存到 PCL_ICON_LOGO_DIR（默认 /tmp/pclwork/logos），文件名：
       quilt.png   —— 官方 Quilt logo（GitHub QuiltMC 组织头像，深紫底）
       optifine.png —— optifine.net 的 favicon（16x16，深红底 + 金色 OF）
   取图方式（一次性，脚本不自动做）：
       curl -sL -o quilt.png    "https://github.com/QuiltMC.png?size=128"
       curl -sL -o optifine.png "https://optifine.net/favicon.ico"   # 再用 Pillow 存成 png
   缓存缺失时脚本会用 Pillow **现画**一张同款（3x3 彩色补丁 + 缝线 + 右下紫色菱形 /
   深红圆角底 + 金色 OF 块状字母），保证 27 张永远能出全。


二、渲染规格
------------
* 画布 128x128，RGBA，透明背景。
* 方块 = 2:1 等轴测立方体，宽高 120，水平垂直居中：
      顶面上角 (64,4)、右角 (124,34)、下角 (64,64)、左角 (4,34)
      左侧面 (4,34)-(64,64)-(64,124)-(4,94)
      右侧面 (64,64)-(124,34)-(124,94)-(64,124)
  用 Image.transform(..., Image.AFFINE) 把 16x16 贴图仿射到这三个平行四边形上
  （平行四边形是正方形的仿射像，所以 AFFINE 是精确映射，等价于 QUAD 贴图但无插值）。
  面亮度：顶面 x1.0、左面 x0.8、右面 x0.6（只乘 RGB，alpha 不变）。
* 物品 = 16x16 直接 8 倍最近邻放大到 128，不加额外边距（留白来自贴图自身）。
* 灰度物品贴图（整图 R==G==B）按平原树叶色 #77AB2F 着色；草方块顶面 / 侧面 overlay
  按平原草色 #91BD59 着色。
* logo 类（铁砧 / NeoForge / Fabric / Quilt / OptiFine）统一裁到内容边界后装进 112px
  的框里居中，保证四周有留白、不顶满画布。
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

# --------------------------------------------------------------------------- #
# 常量
# --------------------------------------------------------------------------- #

CANVAS = 128                 # 输出画布边长
CUBE = 120                   # 等轴测立方体的宽 / 高
HALF = CUBE // 2             # 60，顶面菱形半高
LOGO_FIT = 112               # logo 内容的最大边长（四周各留 8px）
ITEM_SCALE = 8               # 物品贴图放大倍数（16 * 8 = 128）

GRASS_TINT = (0x91, 0xBD, 0x59)   # 平原草色
LEAVES_TINT = (0x77, 0xAB, 0x2F)  # 平原树叶色

# 等轴测三个面的四个角（顺时针：左上 -> 右上 -> 右下 -> 左下）
TOP_QUAD = [(64, 4), (124, 34), (64, 64), (4, 34)]
LEFT_QUAD = [(4, 34), (64, 64), (64, 124), (4, 94)]
RIGHT_QUAD = [(64, 64), (124, 34), (124, 94), (64, 124)]

FACE_SHADE = {"top": 1.0, "left": 0.8, "right": 0.6}

REPO_ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = REPO_ROOT / "dist-assets" / "icons"

MC_ASSETS = Path(os.environ.get("PCL_MC_ASSETS", "/tmp/mcassets/extract"))
MC_TEX = MC_ASSETS / "assets" / "minecraft" / "textures"
PCL2_BLOCKS = Path(
    os.environ.get("PCL2_BLOCKS", "/tmp/pcl2/Plain Craft Launcher 2/Images/Blocks")
)
LOGO_DIR = Path(os.environ.get("PCL_ICON_LOGO_DIR", "/tmp/pclwork/logos"))


# --------------------------------------------------------------------------- #
# 基础工具
# --------------------------------------------------------------------------- #


def load_rgba(path: Path) -> Image.Image:
    """读图并统一转 RGBA（客户端贴图大量是 palette 模式，必须转换）。"""
    if not path.is_file():
        raise FileNotFoundError(f"缺少素材：{path}")
    with Image.open(path) as im:
        return im.convert("RGBA")


def tint(img: Image.Image, rgb: tuple[int, int, int]) -> Image.Image:
    """按 rgb/255 逐通道相乘（alpha 保持不变），等价于 Minecraft 的生物群系着色。"""
    r, g, b, a = img.split()
    tr, tg, tb, _ = Image.new("RGBA", img.size, rgb + (255,)).split()
    return Image.merge(
        "RGBA",
        (
            ImageChops.multiply(r, tr),
            ImageChops.multiply(g, tg),
            ImageChops.multiply(b, tb),
            a,
        ),
    )


def shade(img: Image.Image, factor: float) -> Image.Image:
    """整面调亮 / 调暗：RGB 乘系数，alpha 原样保留。"""
    if factor == 1.0:
        return img
    r, g, b, a = img.split()
    lut = [min(255, round(i * factor)) for i in range(256)]
    return Image.merge("RGBA", (r.point(lut), g.point(lut), b.point(lut), a))


def is_grayscale(img: Image.Image) -> bool:
    """全图不透明像素是否都满足 R==G==B（透明像素不参与判断）。"""
    r, g, b, a = img.split()
    diff = ImageChops.lighter(
        ImageChops.difference(r, g), ImageChops.difference(g, b)
    )
    opaque = a.point(lambda v: 255 if v > 0 else 0)
    if opaque.getextrema()[1] == 0:
        return False  # 全透明，无从判断
    return ImageChops.multiply(diff, opaque).getextrema()[1] == 0


def content_bbox(img: Image.Image) -> tuple[int, int, int, int]:
    """不透明内容的边界框；全透明时退回整图。"""
    return img.getbbox() or (0, 0, img.width, img.height)


# --------------------------------------------------------------------------- #
# 等轴测方块
# --------------------------------------------------------------------------- #


def warp_face(tex: Image.Image, quad, shade_factor: float) -> Image.Image:
    """把 16x16 贴图仿射贴到画布上的一个平行四边形（平行四边形是正方形的仿射像）。"""
    p0, p1, _p2, p3 = quad
    ux, uy = p1[0] - p0[0], p1[1] - p0[1]      # 贴图 +x 方向
    vx, vy = p3[0] - p0[0], p3[1] - p0[1]      # 贴图 +y 方向
    det = ux * vy - uy * vx
    if det == 0:
        raise ValueError(f"退化四边形：{quad}")

    # 输出像素 -> 贴图 uv 的逆矩阵
    ia = vy / det
    ib = -vx / det
    ic = -uy / det
    id_ = ux / det

    tw, th = tex.size
    data = (
        tw * ia,
        tw * ib,
        -tw * (ia * p0[0] + ib * p0[1]),
        th * ic,
        th * id_,
        -th * (ic * p0[0] + id_ * p0[1]),
    )
    layer = tex.transform((CANVAS, CANVAS), Image.AFFINE, data, Image.NEAREST)
    return shade(layer, shade_factor)


def polygon_mask(quad) -> Image.Image:
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(mask).polygon(quad, fill=255)
    return mask


def iso_cube(top: Image.Image, left: Image.Image, right: Image.Image) -> Image.Image:
    """三张贴图 -> 一张 128x128 的等轴测立方体。"""
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    for tex, quad, key in (
        (top, TOP_QUAD, "top"),
        (left, LEFT_QUAD, "left"),
        (right, RIGHT_QUAD, "right"),
    ):
        layer = warp_face(tex, quad, FACE_SHADE[key])
        canvas.paste(layer, (0, 0), polygon_mask(quad))
    return canvas


def block_textures(slug: str) -> tuple[Image.Image, Image.Image, Image.Image]:
    """按 slug 取（顶面, 左面, 右面）三张 16x16 贴图。"""
    def tex(name: str) -> Image.Image:
        return load_rgba(MC_TEX / "block" / f"{name}.png")

    if slug == "crafting_table":
        return tex("crafting_table_top"), tex("crafting_table_front"), tex("crafting_table_side")
    if slug == "furnace":
        return tex("furnace_top"), tex("furnace_front"), tex("furnace_side")
    if slug == "grass_block":
        top = tint(tex("grass_block_top"), GRASS_TINT)
        side = tex("grass_block_side")
        overlay = tint(tex("grass_block_side_overlay"), GRASS_TINT)
        side = Image.alpha_composite(side, overlay)
        return top, side, side
    return tex(slug), tex(slug), tex(slug)


# --------------------------------------------------------------------------- #
# 物品
# --------------------------------------------------------------------------- #


def item_icon(slug: str, tex_name: str | None = None) -> Image.Image:
    """16x16 物品贴图 -> 8 倍最近邻放大到 128。"""
    name = tex_name or slug
    path = MC_TEX / "item" / f"{name}.png"
    if not path.is_file():                      # 少数贴图在 block/ 下
        path = MC_TEX / "block" / f"{name}.png"
    img = load_rgba(path)
    if img.size != (16, 16):
        img = img.resize((16, 16), Image.NEAREST)
    if is_grayscale(img):
        img = tint(img, LEAVES_TINT)
    return img.resize((CANVAS, CANVAS), Image.NEAREST)


# --------------------------------------------------------------------------- #
# logo（铁砧 / 加载器）
# --------------------------------------------------------------------------- #


def fit_logo(img: Image.Image, resample: int = Image.NEAREST) -> Image.Image:
    """裁到内容边界，装进 LOGO_FIT 的方框里居中（保证四周留白）。"""
    img = img.convert("RGBA")
    img = img.crop(content_bbox(img))
    w, h = img.size
    longest = max(w, h)

    # 优先用整数倍最近邻，像素风不会被拉花
    k = round(LOGO_FIT / longest)
    if k >= 2 and longest * k <= CUBE:
        new = img.resize((w * k, h * k), Image.NEAREST)
    else:
        scale = LOGO_FIT / longest
        new = img.resize((max(1, round(w * scale)), max(1, round(h * scale))), resample)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.alpha_composite(new, ((CANVAS - new.width) // 2, (CANVAS - new.height) // 2))
    return canvas


def key_out_background(img: Image.Image, bg: tuple[int, int, int], tol: int = 6) -> Image.Image:
    """把纯色底（Quilt 头像的深紫底）抠成透明。"""
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a and abs(r - bg[0]) <= tol and abs(g - bg[1]) <= tol and abs(b - bg[2]) <= tol:
                px[x, y] = (0, 0, 0, 0)
    return img


QUILT_COLORS = {
    (0, 0): (151, 34, 255),
    (1, 0): (220, 41, 221),
    (2, 0): (39, 162, 253),
    (0, 1): (220, 41, 221),
    (1, 1): (39, 162, 253),
    (2, 1): (51, 68, 255),
    (0, 2): (151, 34, 255),
    (1, 2): (51, 68, 255),
}
QUILT_DARK = (27, 17, 43)      # 官方 logo 的底色，也用作缝线色
QUILT_STITCH = (45, 30, 72)    # 手绘兜底的缝线：比底色稍亮，深色底上也看得见
QUILT_VIOLET = (135, 31, 228)


def draw_quilt() -> Image.Image:
    """手绘 Quilt logo：3x3 彩色补丁 + 缝线 + 右下紫色菱形。"""
    img = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cell, gap = 26, 5
    ox = oy = (CANVAS - (cell * 3 + gap * 2)) // 2

    for (cx, cy), color in QUILT_COLORS.items():
        x = ox + cx * (cell + gap)
        y = oy + cy * (cell + gap)
        d.rounded_rectangle([x, y, x + cell - 1, y + cell - 1], radius=4, fill=color + (255,))

    # 缝线：在补丁交界处画深色十字
    for i in (1, 2):
        line = ox + i * (cell + gap) - gap // 2 - 1
        for k in range(3):
            y = oy + k * (cell + gap) + cell // 2
            d.rectangle([line - 3, y - 6, line + 3, y + 6], fill=QUILT_STITCH + (255,))
        line = oy + i * (cell + gap) - gap // 2 - 1
        for k in range(3):
            x = ox + k * (cell + gap) + cell // 2
            d.rectangle([x - 6, line - 3, x + 6, line + 3], fill=QUILT_STITCH + (255,))

    # 右下紫色菱形
    cx = ox + 2 * (cell + gap) + cell // 2
    cy = oy + 2 * (cell + gap) + cell // 2 + 2
    r = cell // 2 + 2
    d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=QUILT_VIOLET + (255,))
    return img


def draw_optifine() -> Image.Image:
    """手绘 OptiFine logo：深红圆角底 + 金色 OF 块状字母。"""
    img = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    box = (8, 8, CANVAS - 9, CANVAS - 9)
    d.rounded_rectangle(box, radius=10, fill=(128, 41, 41, 255), outline=(68, 22, 22, 255), width=3)

    gold = (226, 159, 0, 255)
    t = 9                                   # 笔画粗细
    # O
    ox, oy, ow, oh = 24, 40, 30, 48
    d.rectangle([ox, oy, ox + ow, oy + oh], fill=gold)
    d.rectangle([ox + t, oy + t, ox + ow - t, oy + oh - t], fill=(128, 41, 41, 255))
    # F
    fx = 64
    d.rectangle([fx, oy, fx + t, oy + oh], fill=gold)
    d.rectangle([fx, oy, fx + ow, oy + t], fill=gold)
    d.rectangle([fx, oy + 19, fx + ow - 6, oy + 19 + t], fill=gold)
    return img


def logo_icon(slug: str) -> tuple[Image.Image, str]:
    """返回 (图标, 来源说明)。"""
    if slug == "anvil":
        return fit_logo(load_rgba(PCL2_BLOCKS / "Anvil.png")), "PCL2 Anvil.png"
    if slug == "neoforge":
        return fit_logo(load_rgba(PCL2_BLOCKS / "NeoForge.png")), "PCL2 NeoForge.png"
    if slug == "fabric":
        return fit_logo(load_rgba(PCL2_BLOCKS / "Fabric.png")), "PCL2 Fabric.png"

    if slug == "quilt":
        official = LOGO_DIR / "quilt.png"
        if official.is_file():
            img = key_out_background(load_rgba(official), QUILT_DARK)
            return fit_logo(img, Image.LANCZOS), f"官方 Quilt logo（{official}）"
        return fit_logo(draw_quilt(), Image.LANCZOS), "手绘（3x3 补丁 + 缝线 + 菱形）"

    if slug == "optifine":
        official = LOGO_DIR / "optifine.png"
        if official.is_file():
            return fit_logo(load_rgba(official)), f"官方 OptiFine favicon（{official}）"
        return fit_logo(draw_optifine()), "手绘（深红底 + 金色 OF）"

    raise KeyError(slug)


# --------------------------------------------------------------------------- #
# 图标清单（顺序 = 设计稿 P1 的网格顺序，6 列 5 行）
# --------------------------------------------------------------------------- #

BLOCKS = [
    "stone",
    "mossy_cobblestone",
    "iron_block",
    "gold_block",
    "diamond_block",
    "nether_wart_block",
    "crafting_table",
    "furnace",
    "grass_block",
]

# slug -> 贴图名（默认与 slug 同名；oak_sapling / item_frame 需要指路）
ITEMS = [
    ("bread", None),
    ("carrot", None),
    ("cooked_porkchop", None),
    ("iron_pickaxe", None),
    ("diamond_sword", None),
    ("potion", None),
    ("golden_apple", None),
    ("totem_of_undying", None),
    ("water_bucket", None),
    ("paper", None),
    ("egg", None),
    ("oak_sapling", "oak_sapling"),   # block/oak_sapling.png
    ("item_frame", "item_frame"),
]

LOGOS = ["anvil", "neoforge", "fabric", "quilt", "optifine"]

SHEET_ORDER = [
    "bread", "carrot", "cooked_porkchop", "crafting_table", "iron_pickaxe", "diamond_block",
    "diamond_sword", "mossy_cobblestone", "furnace", "potion", "golden_apple", "gold_block",
    "grass_block", "iron_block", "item_frame", "nether_wart_block", "oak_sapling", "stone",
    "totem_of_undying", "water_bucket", "anvil", "paper", "fabric", "egg",
    "neoforge", "quilt", "optifine",
]


# --------------------------------------------------------------------------- #
# 对照图
# --------------------------------------------------------------------------- #


def build_contact_sheet(icons: dict[str, Image.Image], out_path: Path, cols: int = 6) -> None:
    cell_w, cell_h = 148, 152
    label_h = 22
    pad = 14
    rows = (len(SHEET_ORDER) + cols - 1) // cols
    sheet = Image.new(
        "RGB", (cols * cell_w + pad * 2, rows * cell_h + pad * 2), (0x1E, 0x21, 0x28)
    )
    try:
        font = ImageFont.load_default(size=12)
    except TypeError:                       # 老版本 Pillow 没有 size 参数
        font = ImageFont.load_default()

    draw = ImageDraw.Draw(sheet)
    for i, slug in enumerate(SHEET_ORDER):
        cx = pad + (i % cols) * cell_w
        cy = pad + (i // cols) * cell_h
        sheet.paste(icons[slug].convert("RGBA"), (cx + (cell_w - CANVAS) // 2, cy), icons[slug])
        tw = draw.textlength(slug, font=font)
        draw.text(
            (cx + (cell_w - tw) / 2, cy + CANVAS + 2),
            slug,
            font=font,
            fill=(0x9A, 0xA3, 0xB2),
        )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path)


# --------------------------------------------------------------------------- #
# 主流程
# --------------------------------------------------------------------------- #


def check_assets() -> None:
    missing = []
    if not MC_TEX.is_dir():
        missing.append(
            f"  {MC_TEX}\n"
            "      （Minecraft 官方贴图目录，需要先从 client.jar 解包：\n"
            "       unzip -o client.jar 'assets/minecraft/textures/*' -d /tmp/mcassets/extract\n"
            "       或用环境变量 PCL_MC_ASSETS 指向解包根目录）"
        )
    if not PCL2_BLOCKS.is_dir():
        missing.append(f"  {PCL2_BLOCKS}\n      （PCL2 的 Anvil/NeoForge/Fabric 图标，可用 PCL2_BLOCKS 覆盖）")
    if missing:
        sys.stderr.write(
            "素材缺失，无法生成图标：\n" + "\n".join(missing) + "\n"
            "脚本不会自行下载客户端 jar；按上面的说明准备一次即可。\n"
        )
        raise SystemExit(2)


def main() -> int:
    parser = argparse.ArgumentParser(description="生成 PCL.Swift 实例图标（27 张 128x128 PNG）")
    parser.add_argument("--contact", type=Path, help="额外输出一张 6 列对照图（深色底 + slug）")
    parser.add_argument("--out", type=Path, default=OUT_DIR, help=f"输出目录（默认 {OUT_DIR}）")
    args = parser.parse_args()

    check_assets()
    args.out.mkdir(parents=True, exist_ok=True)

    icons: dict[str, Image.Image] = {}
    sources: dict[str, str] = {}

    for slug in BLOCKS:
        icons[slug] = iso_cube(*block_textures(slug))
        sources[slug] = "MC 贴图 + 等轴测渲染"

    for slug, tex_name in ITEMS:
        icons[slug] = item_icon(slug, tex_name)
        sources[slug] = "MC 贴图 x8"

    for slug in LOGOS:
        icons[slug], sources[slug] = logo_icon(slug)

    expected = set(BLOCKS) | {s for s, _ in ITEMS} | set(LOGOS)
    assert expected == set(icons), f"清单不一致：{expected ^ set(icons)}"

    for slug, img in icons.items():
        img = img.convert("RGBA")
        assert img.size == (CANVAS, CANVAS), f"{slug} 尺寸不对：{img.size}"
        img.save(args.out / f"{slug}.png")

    if args.contact:
        build_contact_sheet(icons, args.contact)

    print(f"已生成 {len(icons)} 张 {CANVAS}x{CANVAS} 图标 -> {args.out}")
    for slug in SHEET_ORDER:
        print(f"  {slug:18s} {sources[slug]}")
    if args.contact:
        print(f"对照图 -> {args.contact}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
