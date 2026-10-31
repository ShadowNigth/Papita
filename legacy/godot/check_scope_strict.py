"""Analisis de ambitos sobre el AST real de GDScript (gdtoolkit)."""
import re, glob, sys
from gdtoolkit.parser import parser
from lark import Tree, Token

def rule(node):
    if isinstance(node, Tree):
        if node.data is not None and hasattr(node.data, 'value'):
            return node.data.value
        return str(node.data)
    return None

def name_of(token):
    return token.value if isinstance(token, Token) else None

# --- recoleccion de nombres declarados ---------------------------------------

def first_name(node):
    """Primer token NAME en orden de aparicion dentro del subarbol."""
    for tok in node.scan_values(lambda v: isinstance(v, Token) and v.type == 'NAME'):
        return tok.value
    return None

def decl_name(node):
    """Nombre declarado por un nodo de declaracion (var, for, arg...)."""
    return first_name(node)

def is_decl_rule(r):
    if r is None:
        return False
    if r.startswith(('class_var', 'func_var', 'var')) or 'var' in r:
        return True
    return r in ('for_stmt', 'for_stmt_typed', 'for_bare_stmt')

def class_members(tree):
    """Solo miembros de nivel de clase: hijos directos del nodo start."""
    names = set()
    for node in tree.children:
        r = rule(node)
        if is_decl_rule(r):
            n = decl_name(node)
            if n:
                names.add(n)
        elif r == 'func_def':
            for ch in node.children:
                if rule(ch) == 'func_header':
                    n = first_name(ch)
                    if n:
                        names.add(n)
        elif r in ('signal_stmt', 'enum_def', 'class_def', 'const_stmt'):
            n = first_name(node)
            if n:
                names.add(n)
    return names

def func_names(tree):
    out = set()
    for node in tree.iter_subtrees():
        if rule(node) == 'func_header':
            n = first_name(node)
            if n:
                out.add(n)
    return out

def params_of(header):
    out = set()
    if header is None:
        return out
    for node in header.iter_subtrees():
        r = rule(node) or ''
        if r.startswith('func_arg') or r.startswith('lambda_arg'):
            n = first_name(node)
            if n:
                out.add(n)
    return out

def func_locals(body):
    out = set()
    for node in body.iter_subtrees():
        r = rule(node)
        if is_decl_rule(r):
            n = decl_name(node)
            if n:
                out.add(n)
        elif r and (r.startswith('lambda') or r == 'func_def'):
            if r == 'func_def':
                for ch in node.children:
                    if rule(ch) == 'func_header':
                        out |= params_of(ch)
            else:
                out |= params_of(node)
    return out

# --- analisis ----------------------------------------------------------------

ENGINE_OK_ROOTS = set("""position rotation quaternion scale transform global_position global_rotation
global_transform global_basis basis visible modulate self_ modulate name owner z_index z_as_relative
size custom_minimum_size pivot_offset offset_left offset_top offset_right offset_bottom anchors_preset
mouse_filter mouse_default_cursor_shape clip_contents theme position_offset rotation_offset position_3d
emitting amount lifetime one_shot explosiveness randomness fixed_fps speed_scale local_coords
draw_pass_1 mesh material material_override cast_shadow layers visibility_aabb
velocity up_direction floor_max_angle floor_snap_length slide_on_ceiling wall_min_slide_angle
motion_mode sync_to_physics collision_layer collision_mask safe_margin
health armor money damage radius mass gravity_scale linear_velocity angular_velocity
continuous_cd contact_monitor max_contacts_reported physics_material_override
light_color light_energy light_indirect_energy shadow_enabled shadow_bias shadow_normal_bias
omni_range spot_range spot_angle spot_angle_attenuation attenuation distance_fade_enabled
text font_size font outline_size outline_modulate autowrap_mode horizontal_alignment
vertical_alignment bbcode_enabled scroll_following text_changed editable placeholder_text
pressed disabled toggle_mode button_pressed flat icon alignment value min_value max_value step
allow_greater allow_lesser rounded show_percentage stretch_mode expand_mode fit_content
columns separation h_separation v_separation alpha_cut always_emit particle_flag_disable_z
direction spread initial_velocity_min initial_velocity_max gravity damping angle
color colors gradient texture flipped hframes vframes frame region_rect tile stretch_ratio
""".split())

AUTOLOADS = set("Settings I18n AudioBank Content InputSetup".split())
ENGINE_METHODS = set("""queue_free queue_redraw set_meta get_meta has_meta remove_meta set_deferred
call_deferred call add_child add_to_group remove_from_group get_tree get_viewport get_world_3d
is_inside_tree is_queued_for_deletion get_parent find_child find_children get_node get_node_or_null
set_process set_physics_process set_process_input set_process_unhandled_input is_processing
move_and_slide move_and_collide test_move is_on_floor is_on_wall is_on_ceiling get_slide_collision
look_at rotate_y rotate_x rotate_z translate_global translate epsilon_equals get_rid rpc create_tween
tween_property tween_callback tween_interval tween_method queue_free emit_signal connect
disconnect connect_deferred set_script has_method has_signal get_signal_list duplicate instance
instantiate get_first_node_in_group get_nodes_in_group notify_property_list_changed
geometry_instance_set_cast_shadows set_shader_parameter get_shader_parameter grab_focus
release_focus has_focus set_anchors_preset set_anchors_and_offsets_preset
get_viewport_rect get_visible_rect get_global_transform get_global_transform_interpolated
physics_move_and_slide get_slide_collision_count rearent super tanh sinh cosh exp log pow
apply_central_impulse apply_impulse apply_torque_impulse """.split())
SHOW_CALLS = False
KEYWORDS = set("""true false null self super not and or in is as await if else elif while
for match return pass break continue func var const static class extends enum signal when
void int float bool String Array Dictionary""".split())
GLOBAL_CONSTANTS = set("""PI TAU INF NAN PASS FAILED OK ERR_BUSY ERR_UNAVAILABLE""".split())
ENGINE_METHOD_ROOTS = set("""get_tree get_viewport get_viewport_rect get_window get_world_3d
create_tween body_entered area_entered tree_exiting tree_exited timeout pressed text_changed
value_changed item_selected gui_input mouse_entered mouse_exited focus_entered focus_exited
animation_finished finished died super position rotation visible size modulate scale transform
queue_redraw queue_free set_meta get_meta has_meta call_deferred set_deferred add_child
remove_child add_to_group remove_from_group is_inside_tree get_parent look_at move_and_slide
test_move is_on_floor is_on_wall is_on_ceiling get_slide_collision rotate_y apply_shake
emit_signal connect update_input update_state physics_move_and_slide""".split())

GLOBAL_NAMES = set("""Vector2 Vector3 Vector4 Color Basis Quaternion Transform3D Transform2D
Rect2 AABB Plane Projection PackedFloat32Array PackedInt32Array PackedVector3Array
PackedVector2Array PackedStringArray PackedByteArray PackedFloat64Array PackedInt64Array
PackedColorArray Node Node3D Node2D Control CanvasItem CanvasLayer Viewport SubViewport Label
Button ColorRect TextureRect Panel PanelContainer VBoxContainer HBoxContainer GridContainer
MarginContainer ScrollContainer SubViewportContainer ImageTexture Image FontFile Theme
StyleBoxFlat LineEdit RichTextLabel ProgressBar HSlider OptionButton Timer Tween
RandomNumberGenerator FastNoiseLite AudioStreamWAV AudioStreamPlayer AudioStreamPlayer3D
ShaderMaterial StandardMaterial3D BaseMaterial3D Environment Sky ProceduralSkyMaterial
WorldEnvironment MeshInstance3D StaticBody3D CollisionShape3D BoxShape3D SphereShape3D
CapsuleShape3D CylinderShape3D CapsuleMesh BoxMesh SphereMesh PlaneMesh CylinderMesh QuadMesh
TorusMesh Camera3D RayCast3D ShapeCast3D OmniLight3D SpotLight3D DirectionalLight3D
CPUParticles3D GPUParticles3D ParticleProcessMaterial Label3D Decal MultiMesh
MultiMeshInstance3D ArrayMesh SurfaceTool PhysicsRayQueryParameters3D
PhysicsShapeQueryParameters3D PhysicsDirectSpaceState3D PhysicsServer3D RenderingServer
AudioServer DisplayServer OS Engine Time Input InputMap FileAccess DirAccess ConfigFile
JSON ResourceLoader Thread Mutex Callable Signal RID StringName NodePath Rect2i Vector2i
Vector3i Threading GeoNode TweenProperty BoxContainer CheckButton GeometryInstance3D
InputEventKey InputEventMouseButton Marker3D PhysicsMaterial Sprite3D TabContainer
TextServer TranslationServer AudioEffectInstance SceneState ViewportTexture StyleBoxTexture
SpriteBase3D RenderMode CollisionObject3D VisualInstance3D GeometryInstance3D""".split())

BUILTIN_FUNCS = set("""print print_rich printerr print_debug prints push_error push_warning
str int float bool String len range randi randf randi_range randf_range randfn abs absi absf
min max mini maxi minf maxf clamp clampi clampf sign signi signf round roundi floor floori
ceil ceili sqrt pow fmod fposmod lerp lerpf lerp_angle inverse_lerp remap smoothstep
var_to_str str_to_var is_instance_valid is_instance_of is_equal_approx is_zero_approx
deg_to_rad rad_to_deg sin cos tan asin acos atan atan2 exp log db_to_linear linear_to_db
snapped ease wrap wrapi wrapf nearest_po2 char chr ord seed preload load weakref assert
type_exists typeof type_of Color8 ColorN PI TAU INF NAN""".split())

def leftmost_name(node):
    while isinstance(node, Tree):
        if not node.children:
            return None
        first = node.children[0]
        if isinstance(first, Token) and first.type == 'NAME':
            return name_of(first)
        node = first
    return None

def analyse(path, classes_map):
    code = open(path).read()
    try:
        tree = parser.parse(code)
    except Exception as e:
        print(f'{path}: NO PARSEA: {e}')
        return []

    own_members = class_members(tree)
    own_funcs = func_names(tree)
    ext = None
    for node in tree.iter_subtrees():
        if rule(node) == 'extends_stmt':
            for ch in node.children:
                if isinstance(ch, Token):
                    ext = ch.value
                elif isinstance(ch, Tree):
                    n = leftmost_name(ch)
                    if n:
                        ext = n
    inherited = set()
    seen = set()
    base = ext
    while base and base in classes_map and base not in seen:
        seen.add(base)
        inherited |= classes_map[base]['members']
        base = classes_map[base]['ext']

    project_names = set()
    for c in classes_map.values():
        project_names |= c['members']
    # nombres declarados como variable local en cualquier funcion del archivo
    file_declared = set()
    for node in tree.iter_subtrees():
        if is_decl_rule(rule(node)):
            n = first_name(node)
            if n:
                file_declared.add(n)

    problems = []
    for node in tree.iter_subtrees():
        if rule(node) != 'func_def':
            continue
        header = None
        body = []
        for ch in node.children:
            r = rule(ch)
            if r == 'func_header':
                header = ch
            else:
                body.append(ch)
        fname = '?'
        if header is not None:
            for ch in header.children:
                if isinstance(ch, Token) and ch.type == 'NAME':
                    fname = ch.value
                    break
        local = params_of(header) if header is not None else set()
        for b in body:
            if isinstance(b, Tree):
                local |= func_locals(b)

        known = (own_members | own_funcs | inherited | local | GLOBAL_NAMES |
                 BUILTIN_FUNCS | AUTOLOADS | set(classes_map) | ENGINE_OK_ROOTS |
                 ENGINE_METHODS | ENGINE_METHOD_ROOTS)

        line = node.meta.line if hasattr(node, 'meta') and hasattr(node.meta, 'line') else 0
        # raices de acceso a miembro y llamadas sueltas
        for sub in node.iter_subtrees():
            r = rule(sub)
            if r == 'getattr':
                root = leftmost_name(sub)
                if root and root not in known:
                    problems.append((path, fname, root, 'acceso a miembro'))
            elif r == 'standalone_call' and SHOW_CALLS:
                first = sub.children[0] if sub.children else None
                if isinstance(first, Token) and first.type == 'NAME':
                    nm = first.value
                    if nm not in known and nm not in ENGINE_METHODS:
                        problems.append((path, fname, nm, 'llamada'))
    # identificadores sueltos (no ALL_CAPS) usados como valor
    seen_nodes = set()
    skip_tokens = set()
    for node in tree.iter_subtrees():
        r = rule(node)
        if is_decl_rule(r):
            if node.children:
                skip_tokens.add(id(node.children[0]))
        elif r == 'getattr':
            names = [c for c in node.children if isinstance(c, Token) and c.type == 'NAME']
            start = 1 if (node.children and isinstance(node.children[0], Token)
                          and node.children[0].type == 'NAME') else 0
            for tok in names[start:]:
                skip_tokens.add(id(tok))
        elif r and (r.startswith('lambda') or r == 'func_header'):
            for tok in node.scan_values(lambda v: isinstance(v, Token) and v.type == 'NAME'):
                skip_tokens.add(id(tok))
        elif r in ('enum_def', 'class_def', 'signal_stmt'):
            for tok in node.scan_values(lambda v: isinstance(v, Token) and v.type == 'NAME'):
                skip_tokens.add(id(tok))
    for node in tree.iter_subtrees():
        if rule(node) != 'func_def':
            continue
        header = None
        local = set()
        for ch in node.children:
            if rule(ch) == 'func_header':
                header = ch
                local |= params_of(ch)
            else:
                local |= func_locals(ch)
        known2 = (own_members | own_funcs | inherited | local | GLOBAL_NAMES |
                  BUILTIN_FUNCS | AUTOLOADS | set(classes_map) | ENGINE_OK_ROOTS |
                  ENGINE_METHODS | ENGINE_METHOD_ROOTS | GLOBAL_CONSTANTS)
        fname = '?'
        if header is not None:
            for ch in header.children:
                if isinstance(ch, Token) and ch.type == 'NAME':
                    fname = ch.value
                    break
        for tok in node.scan_values(lambda v: isinstance(v, Token) and v.type == 'NAME'):
            if id(tok) in skip_tokens:
                continue
            nm = tok.value
            if nm in known2:
                continue
            if re.match(r'^[A-Z][A-Z0-9_]*$', nm):
                continue
            if nm in KEYWORDS:
                continue
            if nm in file_declared:
                problems.append((path, fname, nm, 'variable de otra funcion'))
            elif nm not in project_names:
                problems.append((path, fname, nm, 'desconocido'))

    return problems

def collect_classes():
    classes = {}
    for f in glob.glob('src/**/*.gd', recursive=True):
        code = open(f).read()
        m = re.search(r'^class_name\s+(\w+)', code, re.M)
        if not m:
            continue
        try:
            tree = parser.parse(code)
        except Exception:
            continue
        ext = None
        for node in tree.iter_subtrees():
            if rule(node) == 'extends_stmt':
                for ch in node.children:
                    if isinstance(ch, Token):
                        ext = ch.value
        classes[m.group(1)] = dict(members=class_members(tree), ext=ext, file=f)
    return classes

def main():
    classes = collect_classes()
    all_problems = []
    for f in sorted(glob.glob('src/**/*.gd', recursive=True)):
        all_problems += analyse(f, classes)
    by_name = {}
    for p in all_problems:
        by_name.setdefault(p[2], []).append(p)
    for name in sorted(by_name):
        items = by_name[name]
        print(f'== {name} ({len(items)})')
        for p in items[:6]:
            print(f'   {p[0]} :: {p[1]}() [{p[3]}]')
    print('TOTAL', len(all_problems), '| nombres distintos:', len(by_name))

main()
