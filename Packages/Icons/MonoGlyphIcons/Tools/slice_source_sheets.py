#!/usr/bin/env python3
"""Extract approved PNG artwork without tracing or redrawing its shapes."""
import argparse
import hashlib
import json
from collections import deque
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

SIZE = 128
ACTIVE = 108
PALETTE = {'light': (32, 32, 32), 'dark': (245, 245, 243)}


def bands(projection, expected, max_internal_gap=40):
    active = projection >= 3
    i = 0
    while i < len(active):
        if active[i]:
            i += 1
            continue
        end = i
        while end < len(active) and not active[end]:
            end += 1
        if i > 0 and end < len(active) and end-i <= max_internal_gap:
            active[i:end] = True
        i = end
    result = []
    i = 0
    while i < len(active):
        if not active[i]:
            i += 1
            continue
        end = i
        while end < len(active) and active[end]:
            end += 1
        if end-i >= 8:
            result.append((i, end))
        i = end
    if len(result) != expected:
        raise ValueError(f'Detected {len(result)} bands; expected {expected}. Inspect the source.')
    return result


def windows(bands, length):
    # Boundaries follow the actual blank gutters, not equal canvas subdivisions.
    boundaries = [0] + [(a[1]+b[0])//2 for a, b in zip(bands, bands[1:])] + [length]
    return list(zip(boundaries, boundaries[1:]))


def grid(image, rows, max_internal_gap=40):
    foreground = np.min(np.asarray(image.convert('RGB')), axis=2) < 160
    columns = bands(foreground.sum(axis=0), 5, max_internal_gap)
    row_bands = bands(foreground.sum(axis=1), rows, max_internal_gap)
    return {'columnBands': columns, 'rowBands': row_bands,
            'columnWindows': windows(columns, image.width), 'rowWindows': windows(row_bands, image.height)}


def components(mask):
    h, w = mask.shape
    visited = np.zeros_like(mask)
    kept = np.zeros_like(mask)
    areas, discarded = [], 0
    for sy, sx in np.argwhere(mask):
        if visited[sy, sx]:
            continue
        queue = deque([(int(sy), int(sx))])
        visited[sy, sx] = True
        component = []
        while queue:
            y, x = queue.popleft()
            component.append((y, x))
            for ny in range(max(0, y-1), min(h, y+2)):
                for nx in range(max(0, x-1), min(w, x+2)):
                    if mask[ny, nx] and not visited[ny, nx]:
                        visited[ny, nx] = True
                        queue.append((ny, nx))
        if len(component) < 5:
            discarded += len(component)
        else:
            ys, xs = zip(*component)
            kept[ys, xs] = True
            areas.append(len(component))
    return kept, sorted(areas, reverse=True), discarded


def bbox(alpha, threshold=8):
    ys, xs = np.where(alpha > threshold)
    if not len(xs):
        raise ValueError('Source cell contains no glyph.')
    return [int(xs.min()), int(ys.min()), int(xs.max())+1, int(ys.max())+1]


def extract(cell):
    gray = np.asarray(cell.convert('RGB'), dtype=np.float32) @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    border = np.concatenate((gray[:8].ravel(), gray[-8:].ravel(), gray[:, :8].ravel(), gray[:, -8:].ravel()))
    background = float(np.median(border))
    ink_pixels = gray[gray < 100]
    if not ink_pixels.size:
        raise ValueError('No dark artwork in the cell.')
    ink = float(np.percentile(ink_pixels, 10))
    alpha = np.clip((background-gray)/(background-ink), 0, 1)
    core, areas, discarded = components(alpha >= 0.3)
    if not areas or discarded > 12:
        raise ValueError(f'Ambiguous foreground components: {areas}, {discarded} noise pixels.')
    left, top, right, bottom = bbox(core.astype(np.uint8)*255)
    inset = min(left, top, cell.width-right, cell.height-bottom)
    if inset < 12:
        raise ValueError(f'Glyph approaches the cell boundary ({inset}px); inspect the crop.')
    # Retain antialiasing beside real ink, removing the generated white-paper texture.
    support = np.asarray(Image.fromarray(core.astype(np.uint8)*255).filter(ImageFilter.MaxFilter(5))) > 0
    alpha[~support | (alpha < 0.025)] = 0
    output = np.rint(alpha*255).astype(np.uint8)
    if np.any(core & (output < 76)):
        raise ValueError('Foreground pixels were lost during background extraction.')
    return output, {'sourceBBox': bbox(output), 'sourceInset': inset,
                    'componentAreas': areas, 'discardedNoisePixels': discarded}


def normalize(alpha):
    left, top, right, bottom = bbox(alpha)
    scale = ACTIVE/max(right-left, bottom-top)
    # Resize alpha alone with transparent padding to avoid matte-colored edge halos.
    crop = Image.fromarray(alpha[max(0, top-4):bottom+4, max(0, left-4):right+4])
    resized = crop.resize((round(crop.width*scale), round(crop.height*scale)), Image.Resampling.LANCZOS)
    left, top, right, bottom = bbox(np.asarray(resized))
    x, y = round(64-(left+right)/2), round(64-(top+bottom)/2)
    if x < 0 or y < 0 or x+resized.width > SIZE or y+resized.height > SIZE:
        raise ValueError('Centered artwork exceeds its canvas.')
    canvas = Image.new('L', (SIZE, SIZE))
    canvas.paste(resized, (x, y))
    return canvas


def metrics(alpha):
    a = np.asarray(alpha)
    left, top, right, bottom = bbox(a)
    inset = min(left, top, SIZE-right, SIZE-bottom)
    center = [(left+right)/2, (top+bottom)/2]
    span = max(right-left, bottom-top)
    if inset < 8 or not 105 <= span <= 110 or max(abs(c-64) for c in center) > 0.5:
        raise ValueError(f'Invalid centered bounds: {[left, top, right, bottom]}')
    if np.any(a[:4]) or np.any(a[-4:]) or np.any(a[:, :4]) or np.any(a[:, -4:]):
        raise ValueError('Nontransparent canvas edge.')
    ys, xs = np.indices(a.shape)
    weight = a.astype(np.float64)
    return {'bbox': [left, top, right, bottom], 'bboxCenter': center, 'inset': inset,
            'alphaCentroid': [round(float((xs*weight).sum()/weight.sum()), 3), round(float((ys*weight).sum()/weight.sum()), 3)]}


def variant(alpha, appearance):
    pixels = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    pixels[..., 3] = np.asarray(alpha)
    pixels[pixels[..., 3] > 0, :3] = PALETTE[appearance]
    return Image.fromarray(pixels)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-only', action='store_true', help='Validate all crops without replacing assets.')
    parser.add_argument('--style', choices=('classic', 'expressiveOutline'), default='classic')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[4]
    design = root/'Design/IconSystems/MonoGlyph'
    classic_catalog = root/'Packages/Icons/MonoGlyphIcons/Sources/MonoGlyphIcons/icons.xcassets'
    if args.style == 'expressiveOutline':
        design /= 'ExpressiveOutline'
    export_root = design/'BitmapRedesign' if args.style == 'classic' else design
    manifest = json.loads((design/'manifest.json').read_text())
    catalog = classic_catalog if args.style == 'classic' else classic_catalog.with_name('expressiveOutline.xcassets')
    prefix = '' if args.style == 'classic' else 'expressiveOutline_'
    names = [s['semantic'] for s in manifest['slots']]
    if len(names) != 233 or len(set(names)) != 233 or set(names) != {p.stem for p in classic_catalog.glob('*.imageset')}:
        raise ValueError('Source manifest does not match the complete 233-icon catalog.')
    expected_sets = {prefix+name for name in names}
    if {p.stem for p in catalog.glob('*.imageset')} - expected_sets:
        raise ValueError('Style catalog contains unknown image sets.')
    sources, grids = {}, {}
    for source in manifest['sources']:
        path = root/source['path']
        if hashlib.sha256(path.read_bytes()).hexdigest() != source['sha256']:
            raise ValueError(f'Source checksum changed: {path}')
        sources[source['sheet']] = Image.open(path).convert('RGB')
        try:
            grids[source['sheet']] = grid(sources[source['sheet']], source['rows'], source.get('maxInternalGap', 40))
        except ValueError as error:
            raise ValueError(f"Sheet {source['sheet']}: {error}") from error
    prepared, records = [], []
    for slot in manifest['slots']:
        sheet, cell, name = slot['sheet'], slot['cell'], slot['semantic']
        column, row = (cell-1)%5, (cell-1)//5
        x0, x1 = grids[sheet]['columnWindows'][column]
        y0, y1 = grids[sheet]['rowWindows'][row]
        try:
            alpha, source_info = extract(sources[sheet].crop((x0, y0, x1, y1)))
            alpha = normalize(alpha)
            measured = metrics(alpha)
        except ValueError as error:
            raise ValueError(f'{name} (sheet {sheet}, cell {cell}): {error}') from error
        for appearance in ('light', 'dark'):
            prepared.append((catalog/slot[appearance], variant(alpha, appearance)))
            records.append({'semantic': name, 'appearance': appearance, 'sheet': sheet, 'cell': cell,
                            'sourceWindow': [x0, y0, x1, y1], **source_info, **measured})
    if args.check_only:
        print(f'Validated all {len(prepared)} centered variants without writing assets.')
        return
    # Publish only after all source cells and all outputs have passed validation.
    for name in names:
        image_set = catalog/(prefix+name+'.imageset')
        image_set.mkdir(parents=True, exist_ok=True)
        if prefix:
            contents = json.loads((classic_catalog/(name+'.imageset')/'Contents.json').read_text())
            for image in contents['images']:
                if 'filename' in image:
                    image['filename'] = prefix+image['filename']
            (image_set/'Contents.json').write_text(json.dumps(contents, indent=2)+'\n')
    for path, output in prepared:
        temporary = path.with_suffix('.png.tmp')
        output.save(temporary, format='PNG', optimize=True)
        temporary.replace(path)
        appearance = 'dark' if path.stem.endswith('_dark') else 'light'
        export = export_root/'Assets'/appearance/(path.parent.stem.removeprefix(prefix)+'.png')
        export.parent.mkdir(parents=True, exist_ok=True)
        export.write_bytes(path.read_bytes())
    report = {'canvasSize': SIZE, 'targetActiveSize': ACTIVE, 'semanticCount': len(names),
              'assetCount': len(records), 'palette': PALETTE,
              'sourceGrids': [{'sheet': sheet, **g} for sheet, g in grids.items()], 'records': records}
    (design/'slicing-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    hashes = [f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root)}' for p, _ in sorted(prepared)]
    (design/'assets.sha256').write_text('\n'.join(hashes)+'\n')
    print(f'Integrated {len(records)} PNG variants from {len(sources)} approved bitmap sheets.')


if __name__ == '__main__':
    main()
