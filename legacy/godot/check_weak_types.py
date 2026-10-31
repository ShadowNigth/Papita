"""Metodos de proyecto llamados sobre vars tipadas Node/Control (error de compilacion)."""
import re, glob

all_methods = set()
for f in glob.glob('src/**/*.gd', recursive=True):
    t = open(f).read()
    all_methods |= set(re.findall(r'^(?:static )?func\s+(\w+)', t, re.M))

problems = []
for f in sorted(glob.glob('src/**/*.gd', recursive=True)):
    lines = open(f).read().split('\n')
    weak = {}
    for i, line in enumerate(lines, 1):
        m = re.match(r'\s*var\s+(\w+)\s*:\s*(Node|Control|CanvasItem|Object|Variant)\b', line)
        if m:
            weak[m.group(1)] = (m.group(2), i)
    if not weak:
        continue
    for i, line in enumerate(lines, 1):
        for m in re.finditer(r'\b(\w+)\.(\w+)\s*\(', line):
            obj, meth = m.group(1), m.group(2)
            if obj in weak and meth in all_methods:
                problems.append((f, i, obj, weak[obj][0], meth, line.strip()))
for p in problems:
    print(f'{p[0]}:{p[1]} {p[2]}:{p[3]}.{p[4]}()  |  {p[5][:110]}')
print('TOTAL', len(problems))
