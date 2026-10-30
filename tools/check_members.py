"""Comprueba que los accesos a miembros existan en la clase del receptor (AST)."""
import re, glob
from gdtoolkit.parser import parser
from lark import Tree, Token

def rule(n):
    if isinstance(n, Tree):
        return n.data.value if hasattr(n.data, 'value') else str(n.data)
    return None

def first_name(node):
    for tok in node.scan_values(lambda v: isinstance(v, Token) and v.type == 'NAME'):
        return tok.value
    return None

def type_of_node(node, classes):
    """Tipo declarado o inferido de un nodo de declaracion/argumento."""
    for tok in node.scan_values(lambda v: isinstance(v, Token) and v.type == 'TYPE_HINT'):
        if tok.value in classes:
            return tok.value
    raw = str(node)
    for cname in classes:
        if cname + '.new()' in raw:
            return cname
    return None


def is_decl(r):
    return r is not None and ('var' in r or r in ('for_stmt', 'for_bare_stmt'))

ENGINE_MEMBERS = set("""position rotation rotation_degrees quaternion scale transform
global_position global_rotation global_rotation_degrees global_scale global_transform basis
visible modulate visible_ratio self_modulate name owner get_name set_name
queue_free queue_redraw free is_queued_for_deletion get_parent add_child remove_child
add_to_group remove_from_group is_in_group get_groups get_tree get_viewport get_window
get_world_3d get_rid set_meta get_meta has_meta remove_meta set_deferred call_deferred call
callv emit_signal connect disconnect is_connected is_inside_tree is_node_ready get_node
get_node_or_null find_child find_children has_node set_process set_physics_process
set_process_input set_process_unhandled_input set_process_unhandled_key_input
is_processing process_mode process_priority process_physics_priority duplicate
get_class get_script set_script has_method has_signal get_signal_list get_method_list
get_property_list notify_property_list_changed notification set
create_tween get_tree_string_to_node_path notify_deferred_thread_group
move_and_slide move_and_collide test_move is_on_floor is_on_wall is_on_ceiling
is_on_floor_only is_on_wall_only get_slide_collision get_slide_collision_count
get_last_slide_collision get_slide_collisions apply_floor_snap get_floor_normal
get_real_velocity velocity up_direction motion_mode floor_max_angle floor_snap_length
floor_stop_on_slope floor_block_on_wall floor_constant_speed max_slides
slide_on_ceiling wall_min_slide_angle safe_margin platform_on_leave platform_floor_layers
platform_wall_layers collision_layer collision_mask collision_priority
max_contacts_reported contact_monitor linear_velocity angular_velocity mass gravity_scale
continuous_cd freeze lock_rotation axis_lock_linear_x physics_material_override sleepng
sleeping can_sleep apply_central_impulse apply_impulse apply_central_force apply_force
add_constant_central_force add_constant_force set_deferred put_pivot_type
global_basis local_basis look_at rotate rotate_x rotate_y rotate_z rotate_object_local
translate translate_object_local translate_global to_global to_local get_global_transform
get_transform transform align_with_y basis_xform scale_ xform
size custom_minimum_size position_ position pivot_offset anchors_preset offsets
offset_left offset_top offset_right offset_bottom grow_direction grow_horizontal
grow_vertical theme theme_type_variation mouse_filter mouse_default_cursor_shape
focus_mode focus_neighbor_top focus_neighbor_bottom clip_contents tooltip_text
show hide set_visible set_size get_size get_rect get_global_rect get_combined_minimum_size
set_anchors_preset set_anchor set_offsets set_position set_rotation set_scale
set_custom_minimum_size queue_sort update_minimum_size minimum_size_changed
grab_focus release_focus has_focus find_next_valid_focus
add_theme_stylebox_override add_theme_font_override add_theme_font_size_override
add_theme_constant_override add_theme_color_override add_theme_icon_override
remove_theme_stylebox_override get_theme_stylebox get_theme_font get_theme_font_size
get_theme_constant get_theme_color text set_text get_text placeholder_text editable
font_size autowrap_mode horizontal_alignment vertical_alignment bbcode_enabled
scroll_following append_text add_text clear scroll_to_line scroll_to_paragraph
align alignment icon flat disabled pressed toggle_mode button_pressed button_group
shortcut action_mode text_direction expand_icon icon_alignment
value min_value max_value step page allow_greater allow_lesser rounded ratio
show_percentage prefix suffix tick_count ticks_on_borders editable_ slider
item_count add_item clear_items select get_selected_id get_item_text
columns rows separation h_separation v_separation
stream bus volume_db pitch_scale playing autoplay max_polyphony panning_strength
play stop set_stream_paused get_stream_playback
light_color light_energy light_indirect_energy light_specular shadow_enabled shadow_bias
shadow_normal_bias shadow_opacity shadow_blur light_volumetric_fog_energy
omni_range omni_attenuation omni_shadow_mode spot_range spot_angle spot_angle_attenuation
spot_attenuation directional_shadow_mode directional_shadow_split_1
environment sky background_mode ambient_light_source ambient_light_color
ambient_light_energy ambient_light_sky_contribution tonemap_mode tonemap_exposure
glow_enabled glow_intensity glow_bloom glow_hdr_threshold glow_blend_mode
ssao_enabled ssao_radius ssao_intensity ssao_power ssil_enabled ssil_radius
ssil_intensity volumetric_fog_enabled volumetric_fog_density volumetric_fog_albedo
volumetric_fog_emission volumetric_fog_length volumetric_fog_detail_spread
volumetric_fog_gi_inject fog_enabled fog_light_color fog_light_energy fog_density
fog_sun_scatter fog_depth_adjustment adjustment_enabled adjustment_brightness
adjustment_contrast adjustment_saturation srgb_to_linear linear_to_srgb
sky_material radiance_size process_mode
mesh material material_override cast_shadow layers sorting_offset sorting_use_aabb_center
visibility_range_begin visibility_range_end visibility_aabb
point_count draw_pass_1 amount lifetime one_shot explosiveness randomness
emitting emission_shape emission_sphere_radius direction spread initial_velocity_min
initial_velocity_max gravity scale_min scale_max color colors color_ramp
scale_curve_ texture
bounds hit from to position normal distance collider collider_id shape rid
get_noise_2d get_noise_3d seed frequency fractal_octaves fractal_lacunarity
fractal_gain cellular_return_type noise_type
size_ get_width get_height get_data get_pixel set_pixel load create create_empty
save_png generate_mipmaps resize
format mix_rate stereo loop_mode loop_begin loop_end data get_length
instantiate new set_shader_parameter get_shader_parameter shader
add_bus set_bus_name set_bus_send get_bus_index bus_count set_bus_volume_db
get_bus_volume_db set_bus_mute get_keycode_string set_icon
set_locale get_locale translate
physics_frame process_frame create_timer get_first_node_in_group get_nodes_in_group
paused quit reload_current_scene change_scene_to_file root current_scene
""".split())

def collect():
    # pasada 1: nombres de clase por archivo
    trees = {}
    names = {}
    for f in glob.glob('src/**/*.gd', recursive=True):
        code = open(f).read()
        try:
            tree = parser.parse(code)
        except Exception:
            continue
        trees[f] = tree
        nm = None
        for node in tree.children:
            if rule(node) == 'classname_stmt':
                nm = first_name(node)
        names[f] = nm
    class_names = set(n for n in names.values() if n)

    classes = {}
    for f, tree in trees.items():
        name = names[f]
        if not name:
            continue
        ext = None
        for node in tree.children:
            if rule(node) == 'extends_stmt':
                for ch in node.children:
                    if isinstance(ch, Token):
                        ext = ch.value
        members = {}
        for node in tree.children:
            r = rule(node)
            if is_decl(r):
                nm = first_name(node)
                typ = type_of_node(node, class_names)
                if nm:
                    members[nm] = typ
            elif r == 'func_def':
                for ch in node.children:
                    if rule(ch) == 'func_header':
                        nm = first_name(ch)
                        if nm:
                            members[nm] = 'func'
            elif r == 'signal_stmt':
                nm = first_name(node)
                if nm:
                    members[nm] = 'signal'
        classes[name] = dict(ext=ext, members=members, file=f)
    return classes


def chain(cls, classes):
    out = []
    seen = set()
    while cls and cls in classes and cls not in seen:
        seen.add(cls)
        out.append(cls)
        cls = classes[cls]['ext']
    return out

def resolve(cls, classes):
    """Devuelve (existe, tipo_resultante)."""
    for c in chain(cls, classes):
        m = classes[c]['members']
        found = [k for k in m if k == cls or True]
    return None

def lookup(cls, attr, classes):
    for c in chain(cls, classes):
        m = classes[c]['members']
        if attr in m:
            return ('member', m[attr])
    if attr in ENGINE_MEMBERS:
        return ('engine', None)
    # miembros de la clase base de motor desconocidos -> aceptar
    return (None, None)

CHAINS = [0]

def main():
    classes = collect()
    problems = []
    for cls, info in classes.items():
        code = open(info['file']).read()
        tree = parser.parse(code)
        for node in tree.iter_subtrees():
            if rule(node) != 'func_def':
                continue
            fname = '?'
            vars_ = {}
            node_cls = cls
            seen_c = set()
            while node_cls and node_cls in classes and node_cls not in seen_c:
                seen_c.add(node_cls)
                for mname, mtyp in classes[node_cls]['members'].items():
                    if mtyp and mtyp in classes:
                        vars_[mname] = mtyp
                node_cls = classes[node_cls]['ext']
            for ch in node.children:
                if rule(ch) == 'func_header':
                    fname = first_name(ch)
                    for sub in ch.iter_subtrees():
                        if (rule(sub) or '').startswith('func_arg'):
                            nm = first_name(sub)
                            typ = type_of_node(sub, classes)
                            if nm:
                                vars_[nm] = typ
            for sub in node.iter_subtrees():
                r = rule(sub)
                if is_decl(r):
                    nm = first_name(sub)
                    typ = type_of_node(sub, classes)
                    if nm and typ in classes:
                        vars_[nm] = typ
            for sub in node.iter_subtrees():
                if rule(sub) != 'getattr':
                    continue
                # cadena a.b.c  -> resolver tipo del receptor
                parts = []
                children = sub.children
                if not (children and isinstance(children[0], Token) and children[0].type == 'NAME'):
                    continue
                parts.append((children[0].value, None))
                for i, ch in enumerate(children):
                    if isinstance(ch, Token) and ch.type == 'NAME' and i > 0:
                        parts.append((ch.value, True))
                    elif rule(ch) == 'GET' and ch.value == 'get':
                        break
                base = parts[0][0]
                if base not in vars_ or vars_[base] not in classes:
                    continue
                cur = vars_[base]
                CHAINS[0] += 1
                for (attr, is_attr) in parts[1:]:
                    if not is_attr:
                        continue
                    kind, typ = lookup(cur, attr, classes)
                    if kind is None:
                        problems.append((info['file'], fname, base, attr, cur, 'atributo inexistente'))
                        break
                    if kind == 'engine':
                        break
                    if typ in classes:
                        cur = typ
                    else:
                        break
    seen = set()
    for p in problems:
        k = (p[0], p[1], p[3])
        if k in seen:
            continue
        seen.add(k)
        print(f'{p[0]} :: {p[1]}() : {p[2]}.{p[3]} (tipo {p[4]})')
    print('cadenas resueltas:', CHAINS[0])
    print('TOTAL', len(seen))

main()
