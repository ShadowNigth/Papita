"""Analizador estatico completo de GDScript para Godot 4.4 (extension_api.json + AST)."""
import gzip
import json, re, glob, os
from gdtoolkit.parser import parser
from lark import Tree, Token

API = json.load(gzip.open(os.path.join(os.path.dirname(__file__), 'godot44_api.json.gz'), 'rt', encoding='utf-8'))

def norm_api_type(t: str) -> str:
    if not t:
        return 'void'
    if t.startswith('enum::') or t.startswith('bitfield::'):
        return 'int'
    if t.startswith('typedarray::'):
        inner = t.split('::', 1)[1]
        if '/' in inner:
            inner = inner.split('/')[-1]
        return f'Array[{inner}]'
    if ',' in t:
        parts = [p.strip() for p in t.split(',')]
        return parts[0]
    return t

GLOBAL_ENUMS = {}
GLOBAL_CONSTS = {'PI': 'float', 'TAU': 'float', 'INF': 'float', 'NAN': 'float'}
for gc in API.get('global_constants', []):
    GLOBAL_CONSTS[gc['name']] = 'int'
for ge in API.get('global_enums', []):
    ename = ge['name']
    GLOBAL_ENUMS[ename] = {v['name']: 'int' for v in ge.get('values', [])}
    for v in ge.get('values', []):
        GLOBAL_CONSTS[v['name']] = 'int'

UTIL_FUNCS = {}
for uf in API.get('utility_functions', []):
    rt = norm_api_type(uf.get('return_type', 'void'))
    args = uf.get('arguments', [])
    req = sum(1 for a in args if 'default_value' not in a)
    UTIL_FUNCS[uf['name']] = {
        'ret': rt,
        'min_args': 0 if uf.get('is_vararg') and not args else req,
        'max_args': None if uf.get('is_vararg') else len(args),
        'arg_types': [norm_api_type(a['type']) for a in args],
        'vararg': uf.get('is_vararg', False),
    }

# Fix min/max vararg min_args = 2
for k in ('min', 'max'):
    if k in UTIL_FUNCS:
        UTIL_FUNCS[k]['min_args'] = 2

GDSCRIPT_FUNCS = {
    'Color8': ('Color', 3, 4, ['int', 'int', 'int', 'int'], False),
    'assert': ('void', 1, 2, ['bool', 'String'], False),
    'char': ('String', 1, 1, ['int'], False),
    'convert': ('Variant', 2, 2, ['Variant', 'int'], False),
    'dict_to_inst': ('Object', 1, 1, ['Dictionary'], False),
    'get_stack': ('Array', 0, 0, [], False),
    'inst_to_dict': ('Dictionary', 1, 1, ['Object'], False),
    'is_instance_of': ('bool', 2, 2, ['Variant', 'Variant'], False),
    'len': ('int', 1, 1, ['Variant'], False),
    'load': ('Resource', 1, 1, ['String'], False),
    'print_debug': ('void', 0, None, [], True),
    'print_stack': ('void', 0, 0, [], False),
    'range': ('Array', 1, 3, ['int', 'int', 'int'], False),
    'type_exists': ('bool', 1, 1, ['StringName'], False),
}
for k, (rt, mn, mx, at, va) in GDSCRIPT_FUNCS.items():
    UTIL_FUNCS[k] = {'ret': rt, 'min_args': mn, 'max_args': mx, 'arg_types': at, 'vararg': va}

BUILTINS = {}
BUILTIN_OPS = {}
BUILTIN_UNARY = {}

for bc in API.get('builtin_classes', []):
    bname = bc['name']
    members = {m['name']: norm_api_type(m['type']) for m in bc.get('members', [])}
    consts = {c['name']: norm_api_type(c['type']) for c in bc.get('constants', [])}
    enums = {}
    for en in bc.get('enums', []):
        enums[en['name']] = {v['name']: 'int' for v in en.get('values', [])}
        for v in en.get('values', []):
            consts[v['name']] = 'int'
    methods = {}
    for m in bc.get('methods', []):
        args = m.get('arguments', [])
        req = sum(1 for a in args if 'default_value' not in a)
        methods[m['name']] = {
            'ret': norm_api_type(m.get('return_type', 'void')),
            'min_args': req,
            'max_args': None if m.get('is_vararg') else len(args),
            'arg_types': [norm_api_type(a['type']) for a in args],
            'vararg': m.get('is_vararg', False),
            'static': m.get('is_static', False),
        }
    ctors = []
    for c in bc.get('constructors', []):
        cargs = c.get('arguments', [])
        ctors.append([norm_api_type(a['type']) for a in cargs])
    BUILTINS[bname] = {
        'members': members,
        'consts': consts,
        'enums': enums,
        'methods': methods,
        'ctors': ctors,
        'index_ret': norm_api_type(bc.get('indexing_return_type')) if bc.get('indexing_return_type') else None,
    }
    for op in bc.get('operators', []):
        oname = op['name']
        rt = norm_api_type(op['return_type'])
        if 'right_type' in op:
            BUILTIN_OPS[(bname, oname, norm_api_type(op['right_type']))] = rt
        else:
            BUILTIN_UNARY[(oname, bname)] = rt

ENGINE_CLASSES = {}
for cl in API.get('classes', []):
    cname = cl['name']
    props = {}
    readonly_props = set()
    method_rets = {}
    methods = {}
    for m in cl.get('methods', []):
        rv = m.get('return_value', {})
        rt = norm_api_type(rv.get('type', 'void'))
        method_rets[m['name']] = rt
        args = m.get('arguments', [])
        req = sum(1 for a in args if 'default_value' not in a)
        methods[m['name']] = {
            'ret': rt,
            'min_args': req,
            'max_args': None if m.get('is_vararg') else len(args),
            'arg_types': [norm_api_type(a['type']) for a in args],
            'vararg': m.get('is_vararg', False),
            'static': m.get('is_static', False),
            'virtual': m.get('is_virtual', False),
        }
    for p in cl.get('properties', []):
        pt = norm_api_type(p['type'])
        getter = p.get('getter')
        setter = p.get('setter')
        if getter and getter in method_rets and method_rets[getter] != 'void':
            if ',' in p['type']:
                pt = method_rets[getter]
        props[p['name']] = pt
        if not setter:
            readonly_props.add(p['name'])
    consts = {c['name']: 'int' for c in cl.get('constants', [])}
    enums = {}
    for en in cl.get('enums', []):
        enums[en['name']] = {v['name']: 'int' for v in en.get('values', [])}
        for v in en.get('values', []):
            consts[v['name']] = 'int'
    signals = {s['name']: 'Signal' for s in cl.get('signals', [])}
    ENGINE_CLASSES[cname] = {
        'inherits': cl.get('inherits'),
        'instantiable': cl.get('is_instantiable', True),
        'props': props,
        'readonly_props': readonly_props,
        'methods': methods,
        'consts': consts,
        'enums': enums,
        'signals': signals,
    }

SINGLETONS = {s['name']: s['type'] for s in API.get('singletons', [])}
AUTOLOADS = {
    'Settings': 'res://src/autoload/settings.gd',
    'I18n': 'res://src/autoload/i18n.gd',
    'AudioBank': 'res://src/autoload/audio_bank.gd',
    'Content': 'res://src/autoload/content.gd',
}

VAR_WEAK = ('Variant', False, False)
VOID_T = ('void', True, False)
NIL_T = ('Nil', True, False)
EMPTY_ARR_T = ('Array[]', True, False)

def rule(n):
    if isinstance(n, Tree):
        return n.data.value if hasattr(n.data, 'value') else str(n.data)
    return None

def line_of(n):
    if isinstance(n, Token):
        return getattr(n, 'line', 0) or 0
    if isinstance(n, Tree):
        if hasattr(n, 'meta') and getattr(n.meta, 'line', None):
            return n.meta.line
        for ch in n.children:
            ln = line_of(ch)
            if ln:
                return ln
    return 0

def parse_type_hint(node) -> str:
    if isinstance(node, Token):
        return node.value.strip()
    toks = [t.value for t in node.scan_values(lambda v: isinstance(v, Token))]
    return ''.join(toks) if toks else 'Variant'

PROJECT_FILES = {}
CLASS_BY_NAME = {}

for f in sorted(glob.glob('src/**/*.gd', recursive=True)):
    res = 'res://' + f.replace('\\', '/')
    code = open(f).read()
    tree = parser.parse(code, gather_metadata=True)
    cname = None
    extends_raw = 'RefCounted'
    for ch in tree.children:
        r = rule(ch)
        if r == 'classname_stmt':
            for tok in ch.scan_values(lambda v: isinstance(v, Token) and v.type == 'NAME'):
                cname = tok.value
                break
        elif r == 'extends_stmt':
            for tok in ch.scan_values(lambda v: isinstance(v, Token)):
                if tok.type in ('NAME', 'REGULAR_STRING', 'TYPE_HINT'):
                    extends_raw = tok.value.strip('"\'')
                    break
    info = {
        'file': f, 'res': res, 'code': code, 'lines': code.splitlines(),
        'tree': tree, 'class_name': cname, 'extends': extends_raw,
        'consts': {}, 'vars': {}, 'signals': {}, 'funcs': {},
    }
    PROJECT_FILES[res] = info
    if cname:
        CLASS_BY_NAME[cname] = res

def resolve_script_ref(ext: str):
    if ext.startswith('res://'):
        return ext if ext in PROJECT_FILES else None
    if ext in CLASS_BY_NAME:
        return CLASS_BY_NAME[ext]
    return None

def preload_type(path: str, info=None, node=None, record_errors=False):
    path = path.strip('"\'')
    disk = path[6:] if path.startswith('res://') else path
    if record_errors and not os.path.exists(disk):
        err(info, node, 'MISSING_PRELOAD', f'Preload file "{path}" does not exist')
    if path.endswith('.gd'):
        if path in PROJECT_FILES:
            cn = PROJECT_FILES[path]['class_name']
            return (cn if cn else f'script:{path}', True, True)
        return ('GDScript', True, False)
    if path.endswith('.tscn') or path.endswith('.scn'):
        return ('PackedScene', True, False)
    if path.endswith('.gdshader'):
        return ('Shader', True, False)
    if path.endswith('.ttf') or path.endswith('.otf'):
        return ('FontFile', True, False)
    if path.endswith('.svg') or path.endswith('.png') or path.endswith('.jpg') or path.endswith('.webp'):
        return ('Texture2D', True, False)
    return ('Resource', True, False)

ERRORS = []
def err(info, node, kind, msg):
    ln = line_of(node)
    src_line = info['lines'][ln - 1].strip() if 1 <= ln <= len(info['lines']) else ''
    ERRORS.append((info['file'], ln, kind, msg, src_line))

# Pass 1
for res, info in PROJECT_FILES.items():
    tree = info['tree']
    for ch in tree.children:
        r = rule(ch)
        if r == 'signal_stmt':
            for tok in ch.children:
                if isinstance(tok, Token) and tok.type == 'NAME':
                    info['signals'][tok.value] = ch
                    break
        elif r in ('func_def', 'static_func_def'):
            is_static = (r == 'static_func_def')
            fnode = ch.children[0] if is_static else ch
            hdr = fnode.children[0]
            fname = hdr.children[0].value
            args_node = None
            ret_hint = None
            for hch in hdr.children[1:]:
                if rule(hch) == 'func_args':
                    args_node = hch
                elif isinstance(hch, Token) and hch.type in ('TYPE_HINT', 'NAME'):
                    ret_hint = hch.value
                elif isinstance(hch, Tree):
                    ret_hint = parse_type_hint(hch)
            arg_list = []
            req = 0
            if args_node:
                for a in args_node.children:
                    ar = rule(a)
                    aname = a.children[0].value
                    has_def = False
                    atype = VAR_WEAK
                    def_expr = None
                    if ar == 'func_arg_regular':
                        has_def = len(a.children) > 1
                        if has_def: def_expr = a.children[1]
                        atype = VAR_WEAK
                    elif ar == 'func_arg_typed':
                        th = parse_type_hint(a.children[1])
                        has_def = len(a.children) > 2
                        if has_def: def_expr = a.children[2]
                        atype = (th, True, False) if th != 'Variant' else ('Variant', True, False)
                    elif ar == 'func_arg_inf':
                        has_def = True
                        def_expr = a.children[1]
                        atype = ('__INF__', False, False)
                    if not has_def: req += 1
                    arg_list.append([aname, atype, def_expr, a])
            if ret_hint is None:
                ret_t = VAR_WEAK
            elif ret_hint == 'void':
                ret_t = VOID_T
            elif ret_hint == 'Variant':
                ret_t = ('Variant', True, False)
            else:
                ret_t = (ret_hint, True, False)
            info['funcs'][fname] = {
                'ret': ret_t, 'min_args': req, 'max_args': len(arg_list),
                'arg_types': [a[1][0] for a in arg_list], 'vararg': False,
                'static': is_static, 'args': arg_list, 'node': fnode,
            }
        elif r == 'const_stmt':
            sub = ch.children[0]
            sr = rule(sub)
            cname = sub.children[0].value
            if sr == 'const_typed_assigned':
                th = parse_type_hint(sub.children[1])
                info['consts'][cname] = ((th, True, False), sub.children[2], sub, False)
            else:
                info['consts'][cname] = (('__INF__', False, False), sub.children[1], sub, True)
        elif r in ('class_var_stmt', 'static_class_var_stmt'):
            is_static = (r == 'static_class_var_stmt')
            vstmt = ch.children[0] if is_static else ch
            sub = vstmt.children[0]
            sr = rule(sub)
            vname = sub.children[0].value
            if sr == 'class_var_typed':
                th = parse_type_hint(sub.children[1])
                t = (th, True, False) if th != 'Variant' else ('Variant', True, False)
                info['vars'][vname] = (t, None, sub, False, is_static)
            elif sr == 'class_var_typed_assgnd':
                th = parse_type_hint(sub.children[1])
                t = (th, True, False) if th != 'Variant' else ('Variant', True, False)
                info['vars'][vname] = (t, sub.children[2], sub, False, is_static)
            elif sr == 'class_var_inf':
                info['vars'][vname] = (('__INF__', False, False), sub.children[1], sub, True, is_static)
            elif sr == 'class_var_assigned':
                info['vars'][vname] = (VAR_WEAK, sub.children[1], sub, False, is_static)
            else:
                info['vars'][vname] = (VAR_WEAK, None, sub, False, is_static)

def script_for_type(tname: str):
    if tname.startswith('script:'):
        return tname.split(':', 1)[1]
    if tname in CLASS_BY_NAME:
        return CLASS_BY_NAME[tname]
    return None

def get_parent_type(tname: str):
    sp = script_for_type(tname)
    if sp and sp in PROJECT_FILES:
        ext = PROJECT_FILES[sp]['extends']
        ext_sp = resolve_script_ref(ext)
        if ext_sp:
            cn = PROJECT_FILES[ext_sp]['class_name']
            return cn if cn else f'script:{ext_sp}'
        return ext
    if tname in ENGINE_CLASSES:
        return ENGINE_CLASSES[tname]['inherits']
    return None

def is_subclass(sub: str, sup: str) -> bool:
    if sub == sup:
        return True
    cur = sub
    seen = set()
    while cur and cur not in seen:
        seen.add(cur)
        if cur == sup:
            return True
        cur = get_parent_type(cur)
    return False

def is_compatible(target: str, src: str) -> bool:
    if target == src or target == 'Variant' or src == 'Variant' or src == 'Nil':
        return True
    if src == 'Array[]' and (target == 'Array' or target.startswith('Array[')):
        return True
    if src.startswith('ArrayLit['):
        el = src[9:-1]
        if target == 'Array': return True
        if target.startswith('Array['): return is_compatible(target[6:-1], el)
    if target == 'float' and src == 'int':
        return True
    if target in ('String', 'StringName') and src in ('String', 'StringName'):
        return True
    if target in ('String', 'NodePath') and src in ('String', 'NodePath'):
        return True
    if target == 'Color' and src == 'String':
        return False
    if target == 'Array' and src.startswith('Array['):
        return True
    # PackedArray conversions in GDScript calls? No, Array -> PackedVector3Array is NOT implicit except in constructors!
    # Wait: in Godot 4 C++ engine calls (ptrcall/varcall), Array[Vector3] or Array can convert to PackedVector3Array? Let's flag if any exist so we see!
    if is_subclass(src, target):
        return True
    return False

# Check member redefinition against parent classes!
for res, info in sorted(PROJECT_FILES.items()):
    self_t = info['class_name'] or f"script:{info['res']}"
    parent_t = get_parent_type(self_t)
    # Check class_name collisions
    cn = info['class_name']
    if cn and (cn in BUILTINS or cn in ENGINE_CLASSES or cn in AUTOLOADS or cn in SINGLETONS):
        err(info, info['tree'], 'CLASS_HIDE', f'Class "{cn}" hides native/builtin/singleton')
    all_own = list(info['vars'].items()) + list(info['consts'].items()) + [(s, (None, None, n)) for s, n in info['signals'].items()]
    for mname, mdata in all_own:
        mnode = mdata[2]
        if mname in BUILTINS or mname in ENGINE_CLASSES:
            err(info, mnode, 'MEMBER_SHADOW_CLASS', f'Member "{mname}" shadows native/builtin class')
        cur = parent_t
        while cur:
            sp = script_for_type(cur)
            if sp and sp in PROJECT_FILES:
                pi = PROJECT_FILES[sp]
                if mname in pi['vars'] or mname in pi['consts'] or mname in pi['signals'] or mname in pi['funcs']:
                    err(info, mnode, 'MEMBER_REDEFINED', f'Member "{mname}" already exists in parent class "{cur}"')
                    break
            elif cur in ENGINE_CLASSES:
                ec = ENGINE_CLASSES[cur]
                if mname in ec['props'] or mname in ec['consts'] or mname in ec['signals'] or mname in ec['methods']:
                    err(info, mnode, 'MEMBER_REDEFINED', f'Member "{mname}" redefined (original in native class "{cur}")')
                    break
            cur = get_parent_type(cur)

def lookup_member(tname: str, attr: str, is_meta: bool):
    base_arr = 'Array' if tname in ('Array[]',) or tname.startswith('Array[') or tname.startswith('ArrayLit[') else tname
    if base_arr in BUILTINS:
        b = BUILTINS[base_arr]
        if not is_meta and attr in b['members']:
            return ('prop', (b['members'][attr], True, False), False)
        if attr in b['consts']:
            return ('const', (b['consts'][attr], True, False), True)
        if attr in b['enums']:
            return ('enum', ('Dictionary', True, True), True)
        if attr in b['methods']:
            return ('method', ('Callable', True, False), True)
        return None
    cur = tname
    seen = set()
    while cur and cur not in seen:
        seen.add(cur)
        sp = script_for_type(cur)
        if sp and sp in PROJECT_FILES:
            pinfo = PROJECT_FILES[sp]
            if attr in pinfo['consts']:
                ct = pinfo['consts'][attr][0]
                return ('const', ct if ct[0] != '__INF__' else VAR_WEAK, True)
            if attr in pinfo['vars']:
                vt = pinfo['vars'][attr][0]
                return ('prop', vt if vt[0] != '__INF__' else VAR_WEAK, False)
            if attr in pinfo['signals']:
                return ('signal', ('Signal', True, False), True)
            if attr in pinfo['funcs']:
                return ('method', ('Callable', True, False), True)
        elif cur in ENGINE_CLASSES:
            ec = ENGINE_CLASSES[cur]
            if attr in ec['props']:
                return ('prop', (ec['props'][attr], True, False), attr in ec['readonly_props'])
            if attr in ec['consts']:
                return ('const', (ec['consts'][attr], True, False), True)
            if attr in ec['enums']:
                return ('enum', ('Dictionary', True, True), True)
            if attr in ec['signals']:
                return ('signal', ('Signal', True, False), True)
            if attr in ec['methods']:
                return ('method', ('Callable', True, False), True)
            if is_meta and attr == 'new':
                return ('method', ('Callable', True, False), True)
        cur = get_parent_type(cur)
    return None

def lookup_method(tname: str, mname: str, is_meta: bool):
    if is_meta and mname == 'new':
        if tname in ENGINE_CLASSES and not ENGINE_CLASSES[tname]['instantiable']:
            return {'ret': (tname, True, False), 'min_args': 0, 'max_args': 0, 'arg_types': [], 'vararg': False, 'static': True, 'abstract': True}
        sp = script_for_type(tname)
        if sp and sp in PROJECT_FILES and '_init' in PROJECT_FILES[sp]['funcs']:
            fn = PROJECT_FILES[sp]['funcs']['_init']
            return {'ret': (tname, True, False), 'min_args': fn['min_args'], 'max_args': fn['max_args'], 'arg_types': [a[1][0] for a in fn['args']], 'vararg': False, 'static': True}
        return {'ret': (tname, True, False), 'min_args': 0, 'max_args': 0, 'arg_types': [], 'vararg': False, 'static': True}
    base_arr = 'Array' if tname in ('Array[]',) or tname.startswith('Array[') or tname.startswith('ArrayLit[') else tname
    if base_arr in BUILTINS:
        b = BUILTINS[base_arr]
        if mname in b['methods']:
            m = b['methods'][mname]
            rt = m['ret']
            if tname.startswith('Array[') and tname != 'Array[]' and mname in ('pop_back', 'pop_front', 'back', 'front', 'pick_random'):
                elem = tname[6:-1]
                return {**m, 'ret': (elem, True, False)}
            if tname.startswith('Array[') and tname != 'Array[]' and mname in ('duplicate', 'slice', 'filter'):
                return {**m, 'ret': (tname, True, False)}
            return {**m, 'ret': (rt, rt != 'Variant', False)}
        return None
    cur = tname
    seen = set()
    while cur and cur not in seen:
        seen.add(cur)
        sp = script_for_type(cur)
        if sp and sp in PROJECT_FILES:
            pinfo = PROJECT_FILES[sp]
            if mname in pinfo['funcs']:
                fn = pinfo['funcs'][mname]
                return {**fn, 'arg_types': [a[1][0] for a in fn['args']]}
        elif cur in ENGINE_CLASSES:
            ec = ENGINE_CLASSES[cur]
            if mname in ec['methods']:
                m = ec['methods'][mname]
                rt = m['ret']
                return {**m, 'ret': (rt, rt != 'Variant', False)}
        cur = get_parent_type(cur)
    return None

def check_call_args(info, node, label, m, arg_types):
    if m.get('abstract'):
        err(info, node, 'ABSTRACT_NEW', f'Cannot instantiate abstract native class "{label}"')
        return
    n = len(arg_types)
    if n < m['min_args'] or (m['max_args'] is not None and n > m['max_args']):
        err(info, node, 'ARITY', f'Wrong arg count for "{label}": got {n}, expected {m["min_args"]}..{m["max_args"]}')
        return
    expected = m.get('arg_types', [])
    for idx, (at, exp) in enumerate(zip(arg_types, expected)):
        aname, ahard, ameta = at
        if exp in ('Variant', '__INF__') or aname in ('Variant', 'Nil') or not ahard:
            continue
        if ameta:
            # Passing class metatype to Variant/Object (e.g. is_instance_of)
            if exp == 'Object' or exp == 'Script':
                continue
        if not is_compatible(exp, aname):
            err(info, node, 'ARG_TYPE', f'Invalid arg {idx+1} for "{label}": expected "{exp}", got "{aname}"')

def check_builtin_ctor(info, node, bname, arg_types):
    if bname in ('int', 'float', 'bool', 'String', 'StringName', 'NodePath'):
        if len(arg_types) > 1:
            err(info, node, 'CTOR_ARGS', f'Too many args for {bname}()')
        return
    ctors = BUILTINS[bname]['ctors']
    if not ctors:
        return
    # Check if any overload can accept arg_types
    for ct in ctors:
        if len(ct) != len(arg_types):
            continue
        ok = True
        for (aname, ahard, _), exp in zip(arg_types, ct):
            if aname == 'Variant' or not ahard:
                continue
            if not is_compatible(exp, aname):
                ok = False
                break
        if ok:
            return
    sig = ', '.join(a[0] for a in arg_types)
    err(info, node, 'CTOR_OVERLOAD', f'No constructor of "{bname}" matches ({sig})')

def eval_expr(node, info, scope, in_static=False, record_errors=True, as_value=False):
    if node is None:
        return VAR_WEAK
    if isinstance(node, Token):
        tt, val = node.type, node.value
        if tt == 'NUMBER':
            if ('.' in val or 'e' in val or 'E' in val) and not val.lower().startswith('0x'):
                return ('float', True, False)
            return ('int', True, False)
        if tt == 'REGULAR_STRING':
            return ('String', True, False)
        if tt in ('NAME', 'TYPE_HINT', 'GET', 'SET'):
            if val in ('true', 'false'): return ('bool', True, False)
            if val == 'null': return NIL_T
            if val == 'self':
                self_t = info['class_name'] or f"script:{info['res']}"
                return (self_t, True, False)
            if val == 'super':
                pt = get_parent_type(info['class_name'] or f"script:{info['res']}")
                return (pt or 'Object', True, False)
            if scope and val in scope:
                return scope[val]
            self_t = info['class_name'] or f"script:{info['res']}"
            mem = lookup_member(self_t, val, False)
            if mem is not None:
                mkind, mtype, _ = mem
                if in_static and mkind == 'prop':
                    sp = script_for_type(self_t)
                    is_st = sp and val in PROJECT_FILES[sp]['vars'] and PROJECT_FILES[sp]['vars'][val][4]
                    if not is_st and record_errors:
                        err(info, node, 'STATIC_VAR', f'Cannot access instance variable "{val}" in static function')
                return mtype
            if val in AUTOLOADS:
                ares = AUTOLOADS[val]
                cn = PROJECT_FILES[ares]['class_name']
                return (cn if cn else f'script:{ares}', True, False)
            if val in SINGLETONS: return (SINGLETONS[val], True, False)
            if val in CLASS_BY_NAME: return (val, True, True)
            if val in ENGINE_CLASSES: return (val, True, True)
            if val in BUILTINS: return (val, True, True)
            if val in GLOBAL_CONSTS: return (GLOBAL_CONSTS[val], True, False)
            if val in GLOBAL_ENUMS: return ('Dictionary', True, True)
            if val in UTIL_FUNCS: return ('Callable', True, False)
            if record_errors:
                err(info, node, 'UNDECLARED', f'Identifier "{val}" not declared in scope')
            return VAR_WEAK
        return VAR_WEAK

    r = rule(node)
    ch = node.children
    if r == 'expr':
        return eval_expr(ch[0], info, scope, in_static, record_errors, as_value) if ch else VAR_WEAK
    if r == 'par_expr':
        return eval_expr(ch[0], info, scope, in_static, record_errors, True) if ch else VAR_WEAK
    if r == 'expr_stmt':
        return eval_expr(ch[0], info, scope, in_static, record_errors, False) if ch else VAR_WEAK
    if r == 'string':
        return ('String', True, False)
    if r == 'array':
        elems = [el for el in ch if rule(el) != 'trailing_comma']
        ets = [eval_expr(el, info, scope, in_static, record_errors, True) for el in elems]
        if not ets:
            return EMPTY_ARR_T
        if all(e[1] and e[0] not in ('Variant', 'Nil') for e in ets) and len(set(e[0] for e in ets)) == 1:
            return (f'ArrayLit[{ets[0][0]}]', True, False)
        return ('Array', True, False)
    if r == 'dict':
        seen_keys = set()
        for el in ch:
            if rule(el) == 'c_dict_element':
                k, v = el.children[0], el.children[1]
                kstr = None
                if isinstance(k, Token) and k.type == 'NAME':
                    kstr = k.value
                else:
                    if rule(k) == 'string' or (isinstance(k, Token) and k.type == 'REGULAR_STRING'):
                        kstr = ''.join(t.value.strip('"\'') for t in (k.scan_values(lambda x: isinstance(x, Token)) if isinstance(k, Tree) else [k]))
                    eval_expr(k, info, scope, in_static, record_errors, True)
                if kstr is not None:
                    if kstr in seen_keys and record_errors:
                        err(info, k, 'DUP_DICT_KEY', f'Duplicate dictionary key "{kstr}"')
                    seen_keys.add(kstr)
                eval_expr(v, info, scope, in_static, record_errors, True)
        return ('Dictionary', True, False)
    if r == 'actual_type_cast':
        eval_expr(ch[0], info, scope, in_static, record_errors, True)
        th = parse_type_hint(ch[-1])
        return (th, True, False) if th != 'Variant' else ('Variant', True, False)
    if r in ('type_test', 'asless_type_test'):
        eval_expr(ch[0], info, scope, in_static, record_errors, True)
        return ('bool', True, False)
    if r == 'await_expr':
        at = eval_expr(ch[-1], info, scope, in_static, record_errors, False)
        return VAR_WEAK if at[0] == 'Signal' else at
    if r == 'lambda':
        lhdr = ch[0]
        lscope = dict(scope) if scope else {}
        lret = VAR_WEAK
        for h in lhdr.children:
            if rule(h) == 'func_args':
                for a in h.children:
                    ar = rule(a)
                    aname = a.children[0].value
                    if ar == 'func_arg_typed':
                        th = parse_type_hint(a.children[1])
                        lscope[aname] = (th, True, False) if th != 'Variant' else ('Variant', True, False)
                    elif ar == 'func_arg_inf':
                        dt = eval_expr(a.children[1], info, lscope, in_static, record_errors, True)
                        lscope[aname] = dt
                    else:
                        lscope[aname] = VAR_WEAK
            elif isinstance(h, Token) and h.type in ('TYPE_HINT', 'NAME'):
                lret = VOID_T if h.value == 'void' else (h.value, True, False)
        if record_errors:
            walk_stmts(ch[1:], info, lscope, in_static, lret)
        return ('Callable', True, False)
    if r == 'assnmnt_expr':
        op = ch[1].value if isinstance(ch[1], Token) else str(ch[1])
        lt = eval_expr(ch[0], info, scope, in_static, record_errors, False)
        rt = eval_expr(ch[2], info, scope, in_static, record_errors, True)
        if record_errors:
            if op == '=':
                if lt[0] not in ('Variant',) and lt[1] and rt[0] not in ('Variant', 'Nil') and rt[1]:
                    if not is_compatible(lt[0], rt[0]):
                        err(info, node, 'ASSIGN_MISMATCH', f'Cannot assign "{rt[0]}" to target of type "{lt[0]}"')
            else:
                bop = op[:-1] # += -> +
                res = eval_binop(lt, bop, rt, info, node, record_errors)
                if lt[0] not in ('Variant',) and lt[1] and res[0] not in ('Variant',) and res[1]:
                    if not is_compatible(lt[0], res[0]):
                        err(info, node, 'COMPOUND_ASSIGN', f'Cannot "{op}" "{rt[0]}" onto "{lt[0]}"')
        return lt
    if r == 'getattr':
        cur = eval_expr(ch[0], info, scope, in_static, record_errors, True)
        i = 1
        while i < len(ch):
            if isinstance(ch[i], Token) and ch[i].type == 'DOT':
                i += 1
                continue
            attr_tok = ch[i]
            attr = attr_tok.value if isinstance(attr_tok, Token) else str(attr_tok)
            i += 1
            bname, bhard, bmeta = cur
            if bname in ('Variant', 'Dictionary') and not bmeta:
                cur = VAR_WEAK
                continue
            if bname == 'Dictionary' and bmeta:
                cur = ('int', True, False)
                continue
            mem = lookup_member(bname, attr, bmeta)
            if mem is None:
                if bhard and record_errors:
                    err(info, attr_tok, 'NO_MEMBER', f'Cannot find member "{attr}" in base "{bname}"')
                cur = VAR_WEAK
            else:
                cur = mem[1]
        return cur
    if r == 'standalone_call':
        fname_tok = ch[0]
        fname = fname_tok.value if isinstance(fname_tok, Token) else str(fname_tok)
        args = ch[1:]
        if fname == 'preload' and args:
            s_tok = next(args[0].scan_values(lambda v: isinstance(v, Token) and v.type == 'REGULAR_STRING'), None)
            if s_tok:
                return preload_type(s_tok.value, info, fname_tok, record_errors)
            return ('Resource', True, False)
        arg_types = [eval_expr(a, info, scope, in_static, record_errors, True) for a in args]
        if fname in BUILTINS:
            if record_errors:
                check_builtin_ctor(info, fname_tok, fname, arg_types)
            return (fname, True, False)
        self_t = info['class_name'] or f"script:{info['res']}"
        m = lookup_method(self_t, fname, False)
        if m is not None:
            if in_static and not m.get('static', False) and record_errors:
                err(info, fname_tok, 'STATIC_CALL', f'Cannot call non-static function "{fname}()" from static function')
            if record_errors:
                check_call_args(info, fname_tok, fname, m, arg_types)
                if as_value and m['ret'][0] == 'void':
                    err(info, fname_tok, 'VOID_VALUE', f'Cannot use return value of void function "{fname}()"')
            return m['ret']
        if fname in UTIL_FUNCS:
            uf = UTIL_FUNCS[fname]
            if record_errors:
                check_call_args(info, fname_tok, fname, uf, arg_types)
                if as_value and uf['ret'] == 'void':
                    err(info, fname_tok, 'VOID_VALUE', f'Cannot use return value of void function "{fname}()"')
            rt = uf['ret']
            if rt == 'Variant': return VAR_WEAK
            if rt == 'void': return VOID_T
            return (rt, True, False)
        if scope and fname in scope and scope[fname][0] == 'Callable':
            if record_errors:
                err(info, fname_tok, 'CALLABLE_DIRECT', f'"{fname}" is a Callable; must use {fname}.call()')
            return VAR_WEAK
        if record_errors:
            err(info, fname_tok, 'NO_FUNC', f'Function "{fname}()" not found')
        return VAR_WEAK
    if r == 'getattr_call':
        ga = ch[0]
        args = ch[1:]
        arg_types = [eval_expr(a, info, scope, in_static, record_errors, True) for a in args]
        gch = ga.children
        m_tok = gch[-1]
        mname = m_tok.value if isinstance(m_tok, Token) else str(m_tok)
        if len(gch) <= 3:
            base_t = eval_expr(gch[0], info, scope, in_static, record_errors, True)
        else:
            base_t = eval_expr(Tree('getattr', gch[:-2]), info, scope, in_static, record_errors, True)
        bname, bhard, bmeta = base_t
        if bname == 'Variant':
            return VAR_WEAK
        m = lookup_method(bname, mname, bmeta)
        if m is None:
            if bname == 'GDScript' and mname == 'new':
                return ('Object', True, False)
            if record_errors:
                err(info, m_tok, 'NO_METHOD', f'Method "{mname}()" not found on base "{bname}"')
            return VAR_WEAK
        if record_errors:
            if bmeta and not m.get('static', False) and mname != 'new':
                err(info, m_tok, 'NON_STATIC_ON_CLASS', f'Cannot call non-static "{mname}()" on class "{bname}"')
            check_call_args(info, m_tok, f'{bname}.{mname}', m, arg_types)
            if as_value and m['ret'][0] == 'void':
                err(info, m_tok, 'VOID_VALUE', f'Cannot use return value of void method "{bname}.{mname}()"')
        ret = m['ret']
        if not bhard and ret[0] != 'Variant':
            return (ret[0], False, ret[2])
        return ret
    if r == 'subscr_expr':
        bt = eval_expr(ch[0], info, scope, in_static, record_errors, True)
        it = eval_expr(ch[1], info, scope, in_static, record_errors, True)
        bname, bhard, bmeta = bt
        if bname == 'Variant' or bmeta:
            return VAR_WEAK
        if bname.startswith('Array[') and bname != 'Array[]':
            return (bname[6:-1], bhard, False)
        if bname in ('Array', 'Array[]', 'Dictionary', 'Transform3D', 'Projection', 'Plane', 'Color') or bname.startswith('ArrayLit['):
            return VAR_WEAK
        if bname in BUILTINS and BUILTINS[bname]['index_ret']:
            ir = BUILTINS[bname]['index_ret']
            return VAR_WEAK if ir == 'Variant' else (ir, bhard, False)
        return VAR_WEAK
    if r in ('asless_actual_neg_expr', 'asless_actual_not_test'):
        op_tok = ch[0].value if isinstance(ch[0], Token) else str(ch[0])
        ot = eval_expr(ch[1], info, scope, in_static, record_errors, True)
        if op_tok == 'not':
            return VAR_WEAK if ot[0] == 'Variant' else ('bool', ot[1], False)
        if ot[0] == 'Variant':
            return VAR_WEAK
        uop = 'unary-' if op_tok == '-' else ('unary+' if op_tok == '+' else op_tok)
        rt = BUILTIN_UNARY.get((uop, ot[0]))
        if rt: return (rt, ot[1], False)
        if record_errors:
            err(info, node, 'UNARY_OP', f'Invalid unary {op_tok} on {ot[0]}')
        return VAR_WEAK
    if r in ('arith_expr', 'asless_arith_expr', 'mdr_expr', 'asless_mdr_expr',
             'comparison', 'asless_comparison', 'and_test', 'or_test',
             'bitw_or', 'asless_bitw_or', 'shift_expr'):
        cur = eval_expr(ch[0], info, scope, in_static, record_errors, True)
        i = 1
        while i < len(ch):
            op = ch[i].value if isinstance(ch[i], Token) else str(ch[i])
            rhs = eval_expr(ch[i + 1], info, scope, in_static, record_errors, True)
            i += 2
            cur = eval_binop(cur, op, rhs, info, node, record_errors)
        return cur
    if r == 'test_expr':
        tt = eval_expr(ch[0], info, scope, in_static, record_errors, as_value)
        ct = eval_expr(ch[2], info, scope, in_static, record_errors, True)
        ft = eval_expr(ch[4], info, scope, in_static, record_errors, as_value)
        if tt[0] == 'Variant' or ft[0] == 'Variant':
            return VAR_WEAK
        hard = tt[1] and ft[1]
        if tt[0] == 'Nil': return (ft[0], hard, False)
        if ft[0] == 'Nil': return (tt[0], hard, False)
        if is_compatible(tt[0], ft[0]): return (tt[0], hard, False)
        if is_compatible(ft[0], tt[0]): return (ft[0], hard, False)
        p = tt[0]
        while p:
            if is_subclass(ft[0], p): return (p, hard, False)
            p = get_parent_type(p)
        return VAR_WEAK
    for c in ch:
        if isinstance(c, Tree):
            eval_expr(c, info, scope, in_static, record_errors, False)
    return VAR_WEAK

def eval_binop(lt, op, rt, info, node, record_errors):
    ln, lhard, _ = lt
    rn, rhard, _ = rt
    if ln == 'Array[]': ln = 'Array'
    if rn == 'Array[]': rn = 'Array'
    if ln.startswith('Array[') or ln.startswith('ArrayLit['): ln = 'Array'
    if rn.startswith('Array[') or rn.startswith('ArrayLit['): rn = 'Array'
    if op in ('==', '!=') and (ln == 'Nil' or rn == 'Nil'):
        return ('bool', True, False)
    if op == '%' and ln == 'String':
        return ('String', lhard, False)
    if ln == 'Variant' or rn == 'Variant':
        return VAR_WEAK
    hard = lhard and rhard
    if op in ('and', 'or', 'in'):
        return ('bool', hard, False)
    res = BUILTIN_OPS.get((ln, op, rn))
    if res: return (res, hard, False)
    res_var = BUILTIN_OPS.get((ln, op, 'Variant'))
    if res_var: return (res_var, hard, False)
    if op in ('==', '!='):
        return ('bool', hard, False)
    if ln in ('String', 'StringName') and rn in ('String', 'StringName') and op in ('+', '==', '!=', '<', '<=', '>', '>='):
        return ('String' if op == '+' else 'bool', hard, False)
    if record_errors:
        err(info, node, 'BIN_OP', f'Invalid operands "{ln}" and "{rn}" for "{op}"')
    return VAR_WEAK

# Pass 2: fixed point
for _ in range(4):
    for res, info in PROJECT_FILES.items():
        for cname, (cur_t, expr, sub, is_inf) in list(info['consts'].items()):
            if expr is not None:
                dt = eval_expr(expr, info, {}, True, False, True)
                if is_inf and dt[0] != 'Variant':
                    dt_norm = ('Array', True, False) if (dt[0] == 'Array[]' or dt[0].startswith('ArrayLit[')) else (dt[0], True, dt[2])
                    info['consts'][cname] = (dt_norm, expr, sub, is_inf)
        for vname, (cur_t, expr, sub, is_inf, is_st) in list(info['vars'].items()):
            if is_inf and expr is not None:
                dt = eval_expr(expr, info, {}, is_st, False, True)
                if dt[0] != 'Variant':
                    dt_norm = ('Array', dt[1], False) if (dt[0] == 'Array[]' or dt[0].startswith('ArrayLit[')) else dt
                    info['vars'][vname] = (dt_norm, expr, sub, is_inf, is_st)
        for fname, fn in info['funcs'].items():
            for arg in fn['args']:
                if arg[1][0] == '__INF__' and arg[2] is not None:
                    dt = eval_expr(arg[2], info, {}, fn['static'], False, True)
                    arg[1] = ('Array', dt[1], False) if (dt[0] == 'Array[]' or dt[0].startswith('ArrayLit[')) else dt

def check_infer_valid(info, sub, name, kind_label, dt):
    tname, hard, _ = dt
    if tname in ('Variant', 'void', '__INF__') or not hard:
        err(info, sub, 'INFER_FAIL', f'Cannot infer the type of "{name}" {kind_label} (got {tname}, hard={hard})')
    elif tname == 'Nil' and kind_label != 'constant':
        err(info, sub, 'INFER_NULL', f'Cannot infer the type of "{name}" {kind_label} because value is null')

def for_iter_type(node, info, scope, in_static):
    inner = node.children[0] if rule(node) == 'expr' else node
    if rule(inner) == 'standalone_call' and inner.children[0].value == 'range':
        for a in inner.children[1:]:
            eval_expr(a, info, scope, in_static, True, True)
        return ('int', True, False)
    lt = eval_expr(node, info, scope, in_static, True, True)
    lname, lhard, _ = lt
    if lname == 'Variant' or not lhard:
        return VAR_WEAK
    if lname.startswith('Array[') and lname != 'Array[]':
        return (lname[6:-1], lhard, False)
    if lname in ('int', 'float', 'String'):
        return (lname, lhard, False)
    if lname in ('Vector2i', 'Vector3i', 'PackedByteArray', 'PackedInt32Array', 'PackedInt64Array'):
        return ('int', lhard, False)
    if lname in ('Vector2', 'Vector3', 'PackedFloat32Array', 'PackedFloat64Array'):
        return ('float', lhard, False)
    if lname == 'PackedStringArray':
        return ('String', lhard, False)
    if lname == 'PackedVector2Array':
        return ('Vector2', lhard, False)
    if lname == 'PackedVector3Array':
        return ('Vector3', lhard, False)
    if lname == 'PackedColorArray':
        return ('Color', lhard, False)
    return VAR_WEAK

def walk_stmts(stmts, info, scope, in_static, expected_ret):
    local_declared = set()
    for st in stmts:
        if not isinstance(st, Tree):
            continue
        r = rule(st)
        ch = st.children
        if r == 'func_var_stmt':
            sub = ch[0]
            sr = rule(sub)
            vname = sub.children[0].value
            if vname in local_declared:
                err(info, sub, 'DUP_LOCAL', f'Variable "{vname}" already declared in the current block')
            local_declared.add(vname)
            if sr == 'func_var_inf':
                dt = eval_expr(sub.children[1], info, scope, in_static, True, True)
                check_infer_valid(info, sub, vname, 'variable', dt)
                scope[vname] = ('Array', dt[1], False) if (dt[0] == 'Array[]' or dt[0].startswith('ArrayLit[')) else dt
            elif sr == 'func_var_typed_assgnd':
                th = parse_type_hint(sub.children[1])
                dt = eval_expr(sub.children[2], info, scope, in_static, True, True)
                t = (th, True, False) if th != 'Variant' else ('Variant', True, False)
                if th != 'Variant' and dt[0] not in ('Variant', 'Nil') and dt[1]:
                    if not is_compatible(th, dt[0]):
                        err(info, sub, 'TYPE_MISMATCH', f'Cannot assign "{dt[0]}" to variable "{vname}" of type "{th}"')
                scope[vname] = t
            elif sr == 'func_var_typed':
                th = parse_type_hint(sub.children[1])
                scope[vname] = (th, True, False) if th != 'Variant' else ('Variant', True, False)
            elif sr == 'func_var_assigned':
                dt = eval_expr(sub.children[1], info, scope, in_static, True, True)
                dt_n = 'Array' if dt[0] == 'Array[]' else dt[0]
                scope[vname] = VAR_WEAK if dt_n in ('Variant', 'Nil') else (dt_n, False, False)
            else:
                scope[vname] = VAR_WEAK
        elif r == 'for_stmt':
            vname = ch[0].value
            it_t = for_iter_type(ch[1], info, scope, in_static)
            inner_scope = dict(scope)
            inner_scope[vname] = it_t
            walk_stmts(ch[2:], info, inner_scope, in_static, expected_ret)
        elif r == 'for_stmt_typed':
            vname = ch[0].value
            th = parse_type_hint(ch[1])
            eval_expr(ch[2], info, scope, in_static, True, True)
            inner_scope = dict(scope)
            inner_scope[vname] = (th, True, False) if th != 'Variant' else ('Variant', True, False)
            walk_stmts(ch[3:], info, inner_scope, in_static, expected_ret)
        elif r == 'if_stmt':
            for br in ch:
                br_r = rule(br)
                if br_r in ('if_branch', 'elif_branch'):
                    eval_expr(br.children[0], info, scope, in_static, True, True)
                    walk_stmts(br.children[1:], info, dict(scope), in_static, expected_ret)
                elif br_r == 'else_branch':
                    walk_stmts(br.children, info, dict(scope), in_static, expected_ret)
        elif r == 'while_stmt':
            eval_expr(ch[0], info, scope, in_static, True, True)
            walk_stmts(ch[1:], info, dict(scope), in_static, expected_ret)
        elif r == 'match_stmt':
            eval_expr(ch[0], info, scope, in_static, True, True)
            for br in ch[1:]:
                if rule(br) == 'match_branch':
                    walk_stmts(br.children[1:], info, dict(scope), in_static, expected_ret)
        elif r == 'return_stmt':
            if ch:
                rt = eval_expr(ch[0], info, scope, in_static, True, True)
                if expected_ret and expected_ret[0] == 'void':
                    err(info, st, 'RET_VOID', 'Void function cannot return a value')
                elif expected_ret and expected_ret[0] not in ('Variant', 'void') and rt[0] not in ('Variant', 'Nil') and rt[1]:
                    if not is_compatible(expected_ret[0], rt[0]):
                        err(info, st, 'RET_MISMATCH', f'Cannot return "{rt[0]}" from function expecting "{expected_ret[0]}"')
        elif r == 'expr_stmt':
            eval_expr(ch[0], info, scope, in_static, True, False)

for res, info in sorted(PROJECT_FILES.items()):
    for cname, (cur_t, expr, sub, is_inf) in info['consts'].items():
        if expr is not None:
            dt = eval_expr(expr, info, {}, True, True, True)
            if is_inf:
                check_infer_valid(info, sub, cname, 'constant', dt)
    for vname, (cur_t, expr, sub, is_inf, is_st) in info['vars'].items():
        if expr is not None:
            dt = eval_expr(expr, info, {}, is_st, True, True)
            if is_inf:
                check_infer_valid(info, sub, vname, 'variable', dt)
            elif cur_t[0] != 'Variant' and dt[0] not in ('Variant', 'Nil') and dt[1]:
                if not is_compatible(cur_t[0], dt[0]):
                    err(info, sub, 'TYPE_MISMATCH', f'Cannot assign "{dt[0]}" to class var "{vname}" of type "{cur_t[0]}"')
    for fname, fn in info['funcs'].items():
        fscope = {}
        for aname, atype, def_expr, anode in fn['args']:
            if def_expr is not None:
                dt = eval_expr(def_expr, info, fscope, fn['static'], True, True)
                if rule(anode) == 'func_arg_inf':
                    check_infer_valid(info, anode, aname, 'parameter', dt)
                    atype = ('Array', dt[1], False) if (dt[0] == 'Array[]' or dt[0].startswith('ArrayLit[')) else dt
            fscope[aname] = atype
        walk_stmts(fn['node'].children[1:], info, fscope, fn['static'], fn['ret'])

print(f"=== TOTAL ERRORS FOUND: {len(ERRORS)} ===")
from collections import Counter
print("By category:", Counter(e[2] for e in ERRORS))
for f, ln, kind, msg, sline in ERRORS:
    print(f"{f}:{ln} [{kind}] {msg}\n    {sline}")
