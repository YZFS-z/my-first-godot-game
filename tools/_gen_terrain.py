# -*- coding: utf-8 -*-
"""重写 map_desert / map_europe 地形：降低坡度，消除陡坡/坑洼（载具陷入问题）"""
import json, math

def gen_heights(grid, size, func, flat_zones=None):
    """flat_zones: [(cx, cz, r)] 圆形平坦区，半径内高度向 0 平滑衰减"""
    flat_zones = flat_zones or []
    n = grid + 1
    cell = size / grid
    half = size * 0.5
    out = []
    for iz in range(n):
        z = iz * cell - half
        for ix in range(n):
            x = ix * cell - half
            h = func(x, z)
            for cx, cz, r in flat_zones:
                d = math.hypot(x - cx, z - cz)
                if d < r:
                    h *= max(0.0, 1.0 - d / r) ** 2
            out.append(round(h, 3))
    return out

# ============ map_desert：开阔沙丘，平缓起伏（cell 31m） ============
def desert_h(x, z):
    # 大波长沙丘（~500m）+ 次级丘（~240m），无高频波纹，坡度全程 <8°
    h = 7.0 * math.sin(x * 0.012) * math.cos(z * 0.010) \
        + 3.0 * math.sin(x * 0.026 + 1.3) * math.cos(z * 0.022 + 0.7)
    return h

desert = json.load(open('data/maps/map_desert.json', encoding='utf-8'))
desert['terrain'] = {
    'grid_size': 64,
    'heights': gen_heights(64, 2000, desert_h, flat_zones=[(0, 800, 220), (0, -800, 220)])
}
desert['obstacles'] = [o for o in desert['obstacles'] if o.get('type') != 'ramp']
desert['description'] = '开阔的沙漠地形，绵延平缓的沙丘起伏适合长距离射击与地形隐蔽'
json.dump(desert, open('data/maps/map_desert.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('desert: min=%.2f max=%.2f' % (min(desert['terrain']['heights']), max(desert['terrain']['heights'])))

# ============ map_europe：欧洲小镇，低矮平缓丘陵、小镇圆形平坦（cell 7.8m） ============
def europe_h(x, z):
    # 低矮丘陵（主波长 ~260m、次级 ~130m），去掉高频波纹避免陡坡
    h = 4.0 * math.sin(x * 0.024) * math.cos(z * 0.020) \
        + 1.8 * math.sin(x * 0.05 + 1.0) * math.cos(z * 0.045 + 0.5)
    return h

europe = json.load(open('data/maps/map_europe.json', encoding='utf-8'))
europe['terrain'] = {
    'grid_size': 64,
    'heights': gen_heights(64, 500, europe_h, flat_zones=[(0, 0, 95)])
}
europe['obstacles'] = [o for o in europe['obstacles'] if o.get('type') != 'ramp']
europe['description'] = '欧洲小镇，周围低矮丘陵起伏、镇中心平坦，适合巷战与丘陵迂回'
json.dump(europe, open('data/maps/map_europe.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('europe: min=%.2f max=%.2f' % (min(europe['terrain']['heights']), max(europe['terrain']['heights'])))
