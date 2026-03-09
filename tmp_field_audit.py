import csv
import re
from pathlib import Path

root = Path(r'D:/game2/monster')
role_path = root / 'assets/data/role.csv'

with role_path.open('r', encoding='utf-8-sig', newline='') as f:
    reader = csv.reader(f)
    headers = [h.strip() for h in next(reader)]

ignore = {'id', 'name_cn', 'name_en', 'initial_weapon', 'Spec', ''}
stats = []
seen = set()
for h in headers:
    if h in ignore or h.startswith('Grow_') or h.startswith('Unnamed'):
        continue
    if h not in seen:
        seen.add(h)
        stats.append(h)

scripts = list((root / 'scripts').rglob('*.gd'))
text_map = {p: p.read_text(encoding='utf-8', errors='ignore') for p in scripts}

print('STAT_COUNT', len(stats))
for s in stats:
    pat = re.compile(re.escape(s))
    hits = []
    for p, t in text_map.items():
        c = len(pat.findall(t))
        if c > 0:
            hits.append((str(p.relative_to(root)).replace('\\', '/'), c))
    total = sum(c for _, c in hits)
    used = 'Y' if total > 0 else 'N'
    top = ', '.join([f'{p}:{c}' for p, c in sorted(hits, key=lambda x: -x[1])[:4]])
    print(f'{s}\t{used}\t{total}\t{top}')
