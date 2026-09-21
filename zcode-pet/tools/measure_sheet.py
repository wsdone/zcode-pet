#!/usr/bin/env python3
"""测量精灵图网格并写 grid.json（zcode-pet 导入器用）。

用法: python3 measure_sheet.py <宠物目录>
petdex 官方规范优先：8 列 × 192×208 帧（v1=9 行 1536×1872，
v2=11 行 1536×2288，允许整数倍等比缩放）；不匹配规范时
按透明沟检测，再回退 8 列宽高比推断。
输出 grid.json: {mode,path,frameW,frameH,cols,rows,fps}
"""
import json
import os
import sys

from PIL import Image


def find_frames(length, alpha_profile, min_gap=2, thresh=0.02):
    """按透明沟切分：返回边界列表 [start...]（含末端 length）。"""
    empty = [i for i, v in enumerate(alpha_profile) if v <= thresh]
    if not empty:
        return None
    # 找内部沟：连续空段且两侧均有内容
    bounds, i = [], 0
    while i < len(empty):
        j = i
        while j + 1 < len(empty) and empty[j + 1] == empty[j] + 1:
            j += 1
        seg = (empty[i], empty[j])
        if seg[0] > 0 and seg[1] < length - 1:
            bounds.append((seg[0], seg[1]))
        i = j + 1
    if not bounds:
        return None
    cuts = [0]
    for a, b in bounds:
        cuts.append((a + b + 1) // 2)
    cuts.append(length)
    # 均匀性检查：间距方差过大则视为噪声
    widths = [cuts[k + 1] - cuts[k] for k in range(len(cuts) - 1)]
    if len(set(widths)) > 2 or max(widths) - min(widths) > 2:
        return None
    return cuts


def main():
    d = sys.argv[1]
    img_path = None
    for name in ("spritesheet.webp", "spritesheet.png"):
        p = os.path.join(d, name)
        if os.path.exists(p):
            img_path = os.path.abspath(p)
            break
    if not img_path:
        print("no spritesheet found", file=sys.stderr)
        sys.exit(1)

    img = Image.open(img_path)
    w, h = img.size

    # petdex 官方规范：8 列、帧 192×208，整数倍等比缩放
    for k in (1, 2, 3, 4):
        fw, fh = 192 * k, 208 * k
        if w == fw * 8 and h % fh == 0 and 9 <= h // fh <= 12:
            grid = {"mode": "sheet", "path": img_path, "frameW": fw,
                    "frameH": fh, "cols": 8, "rows": h // fh, "fps": 8}
            out = os.path.join(d, "grid.json")
            with open(out, "w") as f:
                json.dump(grid, f, ensure_ascii=False, indent=1)
            print(f"grid.json: petdex 规范 8x{grid['rows']} @ {fw}x{fh} (sheet {w}x{h}) -> {out}")
            return

    img = img.convert("RGBA")
    alpha = img.split()[3]
    px = alpha.load()

    col_profile = [sum(px[x, y] for y in range(0, h, 3)) / (255 * max(1, h // 3)) for x in range(w)]
    row_profile = [sum(px[x, y] for x in range(0, w, 3)) / (255 * max(1, w // 3)) for y in range(h)]

    col_cuts = find_frames(w, col_profile)
    row_cuts = find_frames(h, row_profile)

    if col_cuts and row_cuts:
        cols = len(col_cuts) - 1
        rows = len(row_cuts) - 1
        frame_w = col_cuts[1] - col_cuts[0]
        frame_h = row_cuts[1] - row_cuts[0]
    else:
        # petdex 惯例回退：8 列；行数按宽高比
        frame_w = w // 8
        rows = round(h / frame_w)
        cols, frame_h = 8, round(h / rows)

    grid = {
        "mode": "sheet",
        "path": img_path,
        "frameW": frame_w,
        "frameH": frame_h,
        "cols": cols,
        "rows": rows,
        "fps": 8,
    }
    out = os.path.join(d, "grid.json")
    with open(out, "w") as f:
        json.dump(grid, f, ensure_ascii=False, indent=1)
    print(f"grid.json: {cols}x{rows} @ {frame_w}x{frame_h} (sheet {w}x{h}) -> {out}")


if __name__ == "__main__":
    main()
