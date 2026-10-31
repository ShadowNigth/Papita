"""Busca 'var x := <expr>' donde Godot no puede inferir el tipo (Variant)."""
import re, glob

BAD = [
    (r'\.get\(\s*[^)]*\)', 'Dictionary.get'),
    (r'\.get_meta\(', 'Object.get_meta'),
    (r'\.call\(', 'Object.call'),
    (r'\.callv\(', 'Object.callv'),
    (r'\.duplicate\(', 'duplicate'),
    (r'\.pop_back\(\)', 'Array.pop_back'),
    (r'\.pop_front\(\)', 'Array.pop_front'),
    (r'\.back\(\)', 'Array.back'),
    (r'\.front\(\)', 'Array.front'),
    (r'\.pick_random\(\)', 'Array.pick_random'),
    (r'\.values\(\)', 'Dictionary.values'),
    (r'\.keys\(\)', 'Dictionary.keys'),
    (r'\.find\(', 'Array.find'),
    (r'\.rfind\(', 'Array.rfind'),
    (r'\.max\(\)', 'Array.max'),
    (r'\.min\(\)', 'Array.min'),
    (r'\.reduce\(', 'Array.reduce'),
    (r'\.get_or_add\(', 'Dictionary.get_or_add'),
]
# funciones de proyecto con tipo de retorno declarado (distinto de Variant)
typed_funcs = set()
for f in glob.glob('src/**/*.gd', recursive=True):
    src = open(f).read()
    for m in re.finditer(r'^(?:static )?func\s+(\w+)\s*\([^)]*\)\s*->\s*([\w\[\]]+)', src, re.M):
        if m.group(2) not in ('void', 'Variant'):
            typed_funcs.add(m.group(1))

problems = []
for f in sorted(glob.glob('src/**/*.gd', recursive=True)):
    for i, line in enumerate(open(f).read().split('\n'), 1):
        m = re.search(r'\bvar\s+(\w+)\s*:=\s*(.+)$', line)
        if not m:
            continue
        name, expr = m.group(1), m.group(2).strip()
        if expr.startswith('"') or expr.startswith("'"):
            continue
        if re.search(r'\sas\s+\w+\s*$', expr):
            continue
        call = re.match(r'^(?:\w+\.)*(\w+)\s*\(', expr)
        if call and call.group(1) in typed_funcs:
            continue
        if re.match(r'^(?:\w+\.)*(label|button|panel|title|spacer|hsep)\s*\(', expr):
            continue
        for pat, why in BAD:
            if re.search(pat, expr):
                # los que empiezan con conversion explicita estan a salvo
                if re.match(r'^(String|int|float|bool|Array|Dictionary|Vector\d?|Color|str|abs|max|min)\s*\(', expr):
                    continue
                problems.append((f, i, name, why, line.strip()))
                break
for p in problems:
    print(f'{p[0]}:{p[1]} {p[2]} := ... [{p[3]}]  |  {p[4][:120]}')
print('TOTAL', len(problems))
