"""Pierwsza rybka OpenMWGodot – model, tekstura, szkielet i animacja `swim_idle` budowane od zera w Blenderze
(bez cudzych modeli i bez zasobów Morrowinda). Uruchomienie bez interfejsu:

    blender --background --python mods/first-fish/blender/build_fish.py
    # albo moduł bpy:  python -c "import runpy; runpy.run_path('mods/first-fish/blender/build_fish.py')"

Wynik: mods/first-fish/models/first_fish.glb (glTF 2.0, siatka + szkielet + animacja w pętli) oraz
mods/first-fish/textures/first_fish_albedo.png (tekstura 128×128 generowana proceduralnie, też osadzona w GLB)
i plik źródłowy mods/first-fish/blender/first_fish.blend.

Układ: Blender Z w górę, głowa w +Y, prawy bok +X → po eksporcie glTF (Y w górę) przód ryby to −Z, czyli „do
przodu” węzła Godota. Długość ok. 0,30 m (mała ryba przybrzeżna), skala 1 jednostka = 1 m."""
import math
import os
from pathlib import Path

import bpy
import numpy as np

HERE = Path(__file__).resolve().parent
MOD = HERE.parent
LENGTH = 0.30          # m, od pyska do nasady ogona (bez płetwy ogonowej)
RINGS = [              # (y od głowy [0..1], półszerokość, półwysokość, przesunięcie w pionie) – profil korpusu
    (0.00, 0.004, 0.004, 0.000),
    (0.06, 0.018, 0.022, 0.002),
    (0.18, 0.030, 0.042, 0.004),
    (0.34, 0.034, 0.052, 0.006),
    (0.52, 0.030, 0.046, 0.005),
    (0.70, 0.020, 0.030, 0.003),
    (0.86, 0.010, 0.014, 0.002),
    (1.00, 0.005, 0.008, 0.002),
]
SIDES = 8              # wierzchołki na pierścień (low-poly)
FPS = 24
LOOP_FRAMES = 24       # 1 s pętli
BONES = ["head", "spine", "tail1", "tail2"]       # łańcuch od głowy do ogona
BONE_Y = [0.0, 0.30, 0.58, 0.82, 1.08]             # granice kości (ułamek długości; ostatnia wchodzi w płetwę)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.fps = FPS
    s.frame_start = 0
    s.frame_end = LOOP_FRAMES - 1


# --- tekstura -----------------------------------------------------------------------------------------------

def make_texture() -> bpy.types.Image:
    """128×128: górna połowa – korpus (u wzdłuż ryby, v wokół obwodu), dolna – płetwy. Barwy „vvardenfellskie”:
    ciemny turkus grzbietu, piaskowy brzuch, ochrowe pasy z ciemną obwódką, rdzawe płetwy z promieniami."""
    w = h = 128
    img = np.zeros((h, w, 4), dtype=np.float32)
    img[..., 3] = 1.0
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    u = xs / (w - 1)
    rng = np.random.default_rng(7)
    noise = rng.random((h, w)).astype(np.float32)
    # korpus: wiersze 64..127 (v = 0 grzbiet … 0,5 brzuch … 1 znów grzbiet; around: 0 grzbiet, 1 brzuch)
    body = ys >= 64
    v = (ys - 64) / 63.0
    around = 1.0 - np.abs(v - 0.5) * 2.0                  # v = 0 i 1 – grzbiet (s = 0), v = 0,5 – brzuch
    back = np.array([0.10, 0.30, 0.32])
    belly = np.array([0.86, 0.78, 0.60])
    t = np.clip((around - 0.35) / 0.45, 0, 1)[..., None]
    col = back * (1 - t) + belly * t
    stripe = (np.sin(u * math.pi * 7.0 + 0.6) > 0.55) & (around < 0.75) & (u > 0.15) & (u < 0.85)
    edge = (np.sin(u * math.pi * 7.0 + 0.6) > 0.35) & ~stripe & (around < 0.75) & (u > 0.12) & (u < 0.88)
    col = np.where(stripe[..., None], np.array([0.80, 0.52, 0.16]), col)
    col = np.where(edge[..., None], col * 0.55, col)
    head = u < 0.10
    col = np.where(head[..., None], col * 0.8 + np.array([0.05, 0.03, 0.0]), col)
    eye = ((u - 0.07) ** 2 * 900 + (around - 0.42) ** 2 * 60) < 0.25
    col = np.where(eye[..., None], np.array([0.95, 0.85, 0.30]), col)
    pupil = ((u - 0.07) ** 2 * 900 + (around - 0.42) ** 2 * 60) < 0.08
    col = np.where(pupil[..., None], np.array([0.03, 0.03, 0.03]), col)
    col = col * (0.92 + 0.12 * noise[..., None])
    img[body, :3] = col[body]
    # płetwy: wiersze 0..63 – rdzawe z jaśniejszymi promieniami od nasady (u = 0) do brzegu
    fins = ys < 64
    fv = ys / 63.0
    base = np.array([0.55, 0.18, 0.10]) * (1 - u[..., None] * 0.35) + np.array([0.18, 0.08, 0.02]) * u[..., None]
    ray = (np.sin(fv * math.pi * 14.0) > 0.6)[..., None]
    fcol = np.where(ray, base * 1.45, base) * (0.9 + 0.15 * noise[..., None])
    img[fins, :3] = np.clip(fcol, 0, 1)[fins]
    img[..., :3] = np.clip(img[..., :3], 0, 1)
    im = bpy.data.images.new("first_fish_albedo", w, h, alpha=False)
    im.pixels = img.reshape(-1).tolist()                 # Blender: wiersz 0 = dół obrazu
    path = MOD / "textures" / "first_fish_albedo.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    im.filepath_raw = str(path)
    im.file_format = "PNG"
    im.save()
    im.pack()
    return im


def make_material(im) -> bpy.types.Material:
    m = bpy.data.materials.new("first_fish")
    m.use_nodes = True
    m.use_backface_culling = False                       # płetwy są pojedynczymi płatami (double-sided w glTF)
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = im
    tex.interpolation = "Closest"                         # piksele jak tekstury z epoki Morrowinda
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.55
    bsdf.inputs["Metallic"].default_value = 0.0
    return m


# --- siatka --------------------------------------------------------------------------------------------------

def make_mesh(mat) -> bpy.types.Object:
    verts, faces, uvs, groups = [], [], [], []           # uvs: per ściana (lista UV dla rogów)

    def ring_y(f):
        return LENGTH * (0.5 - f)                         # głowa w +Y, środek ryby w 0

    # korpus – pierścienie eliptyczne
    ring_idx = []
    for (f, hw, hh, dz) in RINGS:
        idx = []
        for s in range(SIDES):
            a = 2 * math.pi * s / SIDES                   # 0 = grzbiet
            x = math.sin(a) * hw
            z = math.cos(a) * hh + dz
            verts.append((x, ring_y(f), z))
            idx.append(len(verts) - 1)
        ring_idx.append(idx)
    vb = 64 / 128                                         # korpus w górnej połowie tekstury (UV: v w górę)
    for r in range(len(RINGS) - 1):
        f0, f1 = RINGS[r][0], RINGS[r + 1][0]
        for s in range(SIDES):
            s1 = (s + 1) % SIDES
            a, b = ring_idx[r][s], ring_idx[r][s1]
            c, d = ring_idx[r + 1][s1], ring_idx[r + 1][s]
            faces.append((a, d, c, b))
            v0 = vb + (s / SIDES) * 0.5
            v1 = vb + ((s + 1) / SIDES) * 0.5
            uvs.append([(f0, v0), (f1, v0), (f1, v1), (f0, v1)])
    # pyszczek i koniec – wachlarze zamykające
    tip = len(verts)
    verts.append((0.0, ring_y(-0.02), 0.0))
    for s in range(SIDES):
        s1 = (s + 1) % SIDES
        faces.append((tip, ring_idx[0][s], ring_idx[0][s1]))
        uvs.append([(0.0, 0.75), (0.02, vb + s / SIDES * 0.5), (0.02, vb + (s + 1) / SIDES * 0.5)])

    def fin(points, uv):
        """Płetwa – wielokąt płaski (wachlarz od pierwszego punktu)."""
        base = len(verts)
        verts.extend(points)
        for i in range(1, len(points) - 1):
            faces.append((base, base + i, base + i + 1))
            uvs.append([uv[0], uv[i], uv[i + 1]])

    tail_root = ring_y(1.0)
    # ogonowa – widlasta, pionowa (płaszczyzna YZ)
    fin([(0.0, tail_root + 0.004, 0.002), (0.0, tail_root - 0.050, 0.055), (0.0, tail_root - 0.032, 0.006),
         (0.0, tail_root - 0.052, -0.045)],
        [(0.0, 0.25), (0.95, 0.48), (0.55, 0.26), (0.95, 0.03)])
    # grzbietowa – kolczasty grzebień (lekko fantastyczny akcent)
    fin([(0.0, ring_y(0.20), 0.044), (0.0, ring_y(0.26), 0.090), (0.0, ring_y(0.36), 0.070),
         (0.0, ring_y(0.46), 0.084), (0.0, ring_y(0.60), 0.040)],
        [(0.0, 0.05), (0.95, 0.10), (0.75, 0.25), (0.95, 0.40), (0.0, 0.45)])
    # brzuszna – mała
    fin([(0.0, ring_y(0.55), -0.040), (0.0, ring_y(0.62), -0.068), (0.0, ring_y(0.72), -0.028)],
        [(0.0, 0.10), (0.9, 0.20), (0.0, 0.35)])
    # piersiowe – po bokach, odchylone do tyłu i w dół
    for side in (1, -1):
        fin([(side * 0.030, ring_y(0.22), -0.010), (side * 0.072, ring_y(0.34), -0.030),
             (side * 0.040, ring_y(0.38), -0.018)],
            [(0.0, 0.15), (0.9, 0.25), (0.6, 0.40)])

    me = bpy.data.meshes.new("first_fish")
    me.from_pydata(verts, [], faces)
    me.update()
    uv_layer = me.uv_layers.new(name="UVMap")
    li = 0
    for p, fuv in zip(me.polygons, uvs):
        for k, loop in enumerate(p.loop_indices):
            uv_layer.data[loop].uv = fuv[k]
            li += 1
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(mat)
    ob = bpy.data.objects.new("first_fish", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# --- szkielet i wagi ---------------------------------------------------------------------------------------------

def make_rig(mesh_ob) -> bpy.types.Object:
    arm = bpy.data.armatures.new("first_fish_rig")
    rig = bpy.data.objects.new("first_fish_rig", arm)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    parent = None
    for i, name in enumerate(BONES):
        b = arm.edit_bones.new(name)
        b.head = (0.0, LENGTH * (0.5 - BONE_Y[i]), 0.004)
        b.tail = (0.0, LENGTH * (0.5 - BONE_Y[i + 1]), 0.004)
        if parent is not None:
            b.parent = parent
            b.use_connect = True
        parent = b
    bpy.ops.object.mode_set(mode="OBJECT")
    # wagi liniowe wzdłuż długości (sąsiednie kości – płynne wygięcie), płetwy idą z korpusem
    for name in BONES:
        mesh_ob.vertex_groups.new(name=name)
    for v in mesh_ob.data.vertices:
        f = 0.5 - v.co.y / LENGTH                         # 0 – głowa, 1 – nasada ogona
        f = min(max(f, 0.0), 1.2)
        centers = [(BONE_Y[i] + BONE_Y[i + 1]) / 2 for i in range(len(BONES))]
        for i, c in enumerate(centers):
            width = (BONE_Y[i + 1] - BONE_Y[i])
            wgt = max(0.0, 1.0 - abs(f - c) / width)
            if i == len(BONES) - 1 and f > c:
                wgt = 1.0
            if i == 0 and f < c:
                wgt = 1.0
            if wgt > 0:
                mesh_ob.vertex_groups[BONES[i]].add([v.index], wgt, "REPLACE")
    mesh_ob.parent = rig
    mod = mesh_ob.modifiers.new("rig", "ARMATURE")
    mod.object = rig
    return rig


def make_swim(rig) -> None:
    """swim_idle: fala biegnąca od głowy do ogona – obrót kości wokół osi pionowej (Z kości ≈ Z świata dla kości
    leżących wzdłuż −Y), amplituda rośnie ku ogonowi, faza opóźniona; pierwsza i ostatnia klatka równe (pętla)."""
    rig.animation_data_create()
    act = bpy.data.actions.new("swim_idle")
    rig.animation_data.action = act
    amps = [math.radians(a) for a in (3.0, 6.0, 12.0, 22.0)]
    phase = [0.0, 0.7, 1.4, 2.1]
    for pb in rig.pose.bones:
        pb.rotation_mode = "XYZ"
    for fr in range(LOOP_FRAMES + 1):
        t = 2 * math.pi * fr / LOOP_FRAMES
        for i, name in enumerate(BONES):
            pb = rig.pose.bones[name]
            # kość leży wzdłuż −Y świata; jej lokalna oś Z ≈ Z świata (w górę) → obrót „w lewo/prawo”
            pb.rotation_euler = (0.0, 0.0, amps[i] * math.sin(t - phase[i]))
            pb.keyframe_insert("rotation_euler", frame=fr)
        if fr == 0:
            pass
    # liniowa interpolacja – bez „zatrzymań” na kluczach; pętla bez skoku (klatka 24 = 0)
    for fc in _fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    track = rig.animation_data.nla_tracks.new()
    track.name = "swim_idle"
    track.strips.new("swim_idle", 0, act)
    rig.animation_data.action = None


def _fcurves(act):
    if hasattr(act, "fcurves") and len(getattr(act, "fcurves", [])) > 0:
        return list(act.fcurves)
    out = []                                              # Blender 4.4+: warstwy/kanały akcji
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                out.extend(bag.fcurves)
    return out


def export():
    out = MOD / "models" / "first_fish.glb"
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.frame_end = LOOP_FRAMES             # klatka 24 = klatka 0 (pętla zamknięta)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_yup=True, export_apply=False,
                              export_skins=True, export_image_format="AUTO")
    bpy.context.preferences.filepaths.save_version = 0      # bez kopii .blend1
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE / "first_fish.blend"), compress=True)
    me = bpy.data.objects["first_fish"].data
    print(f"FISH verts={len(me.vertices)} tris={sum(len(p.vertices) - 2 for p in me.polygons)} -> {out}")


def main():
    reset()
    im = make_texture()
    mat = make_material(im)
    ob = make_mesh(mat)
    rig = make_rig(ob)
    make_swim(rig)
    export()


main()
