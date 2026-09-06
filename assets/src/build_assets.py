"""Reproducible original Infinity Reality models. Blender 5.2.1, metres, GLB.

Run: blender -b -noaudio --factory-startup --python assets/src/build_assets.py
Concept sources: ../concepts/{objects,environments}.png. No external model data.
"""
import bpy
import math
import json
import random
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/models"
SOURCE = ROOT / "assets/src"
OUT.mkdir(parents=True, exist_ok=True)
random.seed(41)
REPORT = {}


def material(name, color, metallic=0.0, roughness=0.5, glow=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Emission Color"].default_value = (*color, 1)
    shader.inputs["Emission Strength"].default_value = glow
    return mat


def reset():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def finish(obj, name, mat, bevel=0.0):
    obj.name = name
    if mat:
        obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("Small manufactured bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
        weighted = obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
        bpy.ops.object.modifier_apply(modifier=weighted.name)
    return obj


def box(name, loc, scale, mat, bevel=0.04):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat, bevel)


def sphere(name, loc, scale, mat, segments=16, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=loc)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return finish(obj, name, mat)


def cylinder(name, loc, radius, depth, mat, vertices=16, rotation=None, radius2=None):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius,
        radius2=radius if radius2 is None else radius2, depth=depth, location=loc)
    obj = bpy.context.object
    if rotation:
        obj.rotation_euler = rotation
    return finish(obj, name, mat, 0.015)


def ring(name, loc, radius, tube, mat, rotation=None, segments=32):
    bpy.ops.mesh.primitive_torus_add(major_segments=segments, minor_segments=6,
        location=loc, major_radius=radius, minor_radius=tube)
    obj = bpy.context.object
    if rotation:
        obj.rotation_euler = rotation
    return finish(obj, name, mat)


def crystal(name, loc, radius, height, mat, tilt=(0, 0, 0)):
    n = 6
    verts = []
    for z, r in [(0, radius * 0.65), (height * 0.22, radius), (height * 0.77, radius * 0.82)]:
        verts += [(math.cos(i*math.tau/n)*r, math.sin(i*math.tau/n)*r, z) for i in range(n)]
    verts.append((radius*0.12, 0, height))
    faces = [tuple(reversed(range(n)))]
    for level in range(2):
        for i in range(n):
            faces.append((level*n+i, level*n+(i+1)%n, (level+1)*n+(i+1)%n, (level+1)*n+i))
    for i in range(n):
        faces.append((12+i, 12+(i+1)%n, 18))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = tilt
    return finish(obj, name, mat)


def export(name, budget=10000):
    bpy.context.scene.render.fps = 30
    bpy.context.scene.frame_set(1)
    triangles = 0
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            obj.data.calc_loop_triangles()
            triangles += len(obj.data.loop_triangles)
    if triangles > budget:
        raise RuntimeError(f"{name}: {triangles} triangles exceed {budget}")
    anims = [a.name for a in bpy.data.actions if a.users > 0]
    REPORT[name] = {"triangles": triangles, "budget": budget, "animations": anims}
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / (name + ".blend")))
    bpy.ops.export_scene.gltf(filepath=str(OUT / (name + ".glb")),
        export_format="GLB", export_yup=True, export_animations=True,
        export_animation_mode="NLA_TRACKS", export_apply=False,
        export_cameras=False, export_lights=False)
    print(f"ASSET_OK {name} triangles={triangles}", flush=True)


def bind(obj, arm, bone):
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    obj.parent = arm
    mod = obj.modifiers.new("Rigid segmented skin", "ARMATURE")
    mod.object = arm


def humanoid(name, robot=False):
    reset()
    scale = 1.3 if robot else 1.0
    bpy.ops.object.armature_add()
    arm = bpy.context.object
    arm.name = "ExplorerRig" if not robot else "GuardianRig"
    bpy.ops.object.mode_set(mode="EDIT")
    bones = arm.data.edit_bones
    bones.remove(bones[0])
    coords = {"root": ((0,0,0), (0,0,0.8), None),
        "body": ((0,0,0.85),(0,0,1.42),"root"),
        "head": ((0,0,1.42),(0,0,1.82),"body"),
        "arm_l": ((-0.35,0,1.39),(-0.51,0,0.92),"body"),
        "arm_r": ((0.35,0,1.39),(0.51,0,0.92),"body"),
        "leg_l": ((-0.18,0,0.9),(-0.18,0,0.08),"root"),
        "leg_r": ((0.18,0,0.9),(0.18,0,0.08),"root")}
    for key, (head, tail, parent) in coords.items():
        bone = bones.new(key)
        bone.head = Vector(head)*scale
        bone.tail = Vector(tail)*scale
        if parent:
            bone.parent = bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    shell = DARK if robot else CREAM
    accent = ORANGE if robot else MINT
    def part(obj, bone):
        if scale != 1:
            obj.location *= scale
            obj.scale *= scale
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        bind(obj, arm, bone)
        return obj
    part(box("Armored torso", (0,0,1.18),(.68,.38,.57),shell,.10),"body")
    part(box("Pack", (0,.26,1.2),(.48,.22,.50),DARK,.07),"body")
    part(box("Waist webbing", (0,0,.91),(.56,.38,.13),GOLD),"root")
    part(sphere("Helmet",(0,0,1.64),(.29,.27,.30),shell),"head")
    part(sphere("Sealed visor",(0,-.19,1.67),(.235,.14,.19),VISOR),"head")
    if robot:
        part(cylinder("Single guardian eye",(0,-.31,1.68),.07,.06,accent,rotation=(math.pi/2,0,0)),"head")
    part(cylinder("Chest halo",(0,-.205,1.25),.125,.035,GOLD,rotation=(math.pi/2,0,0)),"body")
    part(cylinder("Chest light",(0,-.23,1.25),.085,.04,accent,rotation=(math.pi/2,0,0)),"body")
    for sign, suffix in [(-1,"l"),(1,"r")]:
        bone="arm_"+suffix
        part(sphere("Shoulder "+suffix,(sign*.38,0,1.39),(.23 if robot else .18,.23,.19),shell),bone)
        part(box("Arm sleeve "+suffix,(sign*.45,0,1.15),(.19,.22,.34),NAVY),bone)
        part(box("Forearm shell "+suffix,(sign*.5,-.01,.98),(.23,.24,.23),shell),bone)
        part(box("Gauntlet "+suffix,(sign*.50,0,.82),(.19,.2,.15),DARK),bone)
        bone="leg_"+suffix
        part(box("Thigh "+suffix,(sign*.18,0,.69),(.25,.28,.37),shell),bone)
        part(sphere("Knee joint "+suffix,(sign*.18,-.015,.47),(.15,.17,.14),NAVY),bone)
        part(box("Shin armor "+suffix,(sign*.18,0,.28),(.235,.27,.34),shell),bone)
        part(box("Boot "+suffix,(sign*.18,-.075,.08),(.28,.43,.16),DARK,.05),bone)
        part(box("Sole accent "+suffix,(sign*.18,-.09,.035),(.29,.43,.05),GOLD,.015),bone)
    if not robot:
        part(box("Blade emitter",(.52,-.06,.78),(.09,.14,.21),GOLD,.015),"arm_r")
        part(box("Energy blade",(.52,-.13,.48),(.045,.08,.53),MINT,.015),"arm_r")
    bpy.context.view_layer.objects.active=arm
    arm.animation_data_create()
    for clip,length,amplitude in [("idle",60,.025),("walk",30,.48),("run",20,.7),("attack",24,0),("death",35,0),("interact",24,0)]:
        action=bpy.data.actions.new(clip)
        arm.animation_data.action=action
        for frame in [1, length//4, length//2, 3*length//4, length]:
            phase=(frame-1)/max(1,length-1)*math.tau
            for bone in arm.pose.bones:
                bone.rotation_mode="XYZ"
                bone.rotation_euler=(0,0,0)
                if bone.name.startswith("leg") or bone.name.startswith("arm"):
                    direction=1 if bone.name.endswith("l") else -1
                    if bone.name.startswith("arm"):
                        direction*=-1
                    bone.rotation_euler.x=math.sin(phase)*amplitude*direction
                if clip=="attack" and bone.name=="arm_r":
                    bone.rotation_euler.x=-math.sin((frame-1)/(length-1)*math.pi)*1.6
                    bone.rotation_euler.z=math.sin((frame-1)/(length-1)*math.pi)*.65
                if clip=="interact" and bone.name=="arm_l":
                    bone.rotation_euler.x=-math.sin((frame-1)/(length-1)*math.pi)*1.2
                if clip=="death" and bone.name=="root":
                    bone.rotation_euler.x=(frame-1)/(length-1)*1.4
                bone.keyframe_insert(data_path="rotation_euler",frame=frame,group=bone.name)
        arm.animation_data.action=None
        track=arm.animation_data.nla_tracks.new()
        track.name=clip
        track.strips.new(clip,1,action)
        track.mute=True
    # Blender -Y model front becomes glTF +Z; rotate to Godot -Z character front.
    arm.rotation_euler.z = math.pi
    export(name,30000 if not robot else 10000)


CREAM=material("Warm ceramic shell",(.72,.74,.67),.32,.43)
GOLD=material("Aged brass",(.46,.30,.11),.76,.39)
DARK=material("Basalt alloy",(.065,.085,.10),.48,.65)
NAVY=material("Flexible navy joint",(.022,.033,.047),.18,.75)
VISOR=material("Obsidian glass",(.015,.035,.054),.75,.19)
MINT=material("Resonant mint light",(.11,.92,.68),.35,.25,2.4)
TEAL=material("Crystal facets",(.035,.37,.31),.32,.28,.23)
TEAL_LIGHT=material("Crystal pale facets",(.17,.61,.46),.24,.32,.12)
ORANGE=material("Guardian amber",(1,.22,.035),.2,.4,2)
STONE=material("Ruin limestone",(.53,.44,.29),.08,.85)
ROCK=material("Forest basalt",(.095,.145,.16),.15,.84)

humanoid("explorer")
humanoid("sentinel",True)

reset()
box("Fuselage",(0,0,1.05),(1.65,4.2,1.15),CREAM,.25)
sphere("Canopy",(0,-.85,1.59),(.66,1.13,.41),VISOR)
box("Nose",(0,-2.25,.93),(1.15,1.05,.55),CREAM,.15)
box("Bow light",(0,-2.81,.98),(.58,.035,.06),MINT,.01)
for sign in [-1,1]:
    wing=box("Delta wing",(sign*1.55,.42,.9),(2.15,2.0,.20),CREAM,.07)
    wing.rotation_euler.z=sign*-.28
    box("Wing leading trim",(sign*1.65,-.50,.9),(2.0,.10,.21),GOLD,.02)
    cylinder("Rear engine",(sign*.58,2.23,1.12),.43,.53,DARK,rotation=(math.pi/2,0,0))
    cylinder("Engine core",(sign*.58,2.53,1.12),.30,.05,MINT,rotation=(math.pi/2,0,0))
    box("Landing strut",(sign*1.15,.95,.41),(.14,.16,.70),GOLD,.02)
    box("Landing foot",(sign*1.15,.84,.09),(.52,.84,.18),DARK,.04)
box("Nose landing strut",(0,-1.8,.35),(.16,.18,.55),GOLD,.02)
box("Nose landing foot",(0,-1.88,.08),(.50,.8,.16),DARK,.03)
tail=box("Tail fin",(0,1.63,2.0),(.18,1.33,1.1),CREAM,.04)
tail.rotation_euler.x=-.2
export("ship",30000)

reset()
cylinder("Broad machine base",(0,0,.12),.72,.24,DARK)
cylinder("Brass base rim",(0,0,.28),.60,.10,GOLD)
cylinder("Rotating pedestal",(0,0,.52),.46,.4,DARK)
ring("Pedestal halo",(0,0,.7),.45,.035,MINT)
crystal("Prism",(0,0,.72),.27,1.18,TEAL_LIGHT)
box("Optical mirror",(0,-.01,1.2),(.045,.72,.65),CREAM,.02)
box("Direction marker",(0,-.46,.82),(.07,.28,.045),MINT,.01)
export("prism")

reset()
crystal("Main crystal",(0,0,.05),.26,.94,MINT)
for sign in [-1,1]:
    frame=box("Gold key frame",(sign*.27,0,.47),(.06,.11,.81),GOLD,.01)
    frame.rotation_euler.y=sign*.15
ring("Suspension halo",(0,0,.2),.31,.025,GOLD)
export("crystal")

reset()
box("Resonance gauntlet",(0,0,.27),(.48,.65,.37),CREAM,.08)
ring("Resonance emitter",(0,0,.49),.24,.055,GOLD)
ring("Resonance core",(0,0,.51),.16,.024,MINT)
cylinder("Emitter lens",(0,0,.49),.11,.04,TEAL_LIGHT)
export("artifact")

reset()
box("Portal foundation",(0,0,.12),(4.2,1.7,.24),DARK,.12)
for i in range(16):
    a=math.tau*i/16
    obj=box("Arch segment",(math.sin(a)*1.9,0,2.05+math.cos(a)*1.9),(.69,.67,.49),GOLD if i%4==0 else DARK,.045)
    obj.rotation_euler.y=a
ring("Inner portal light",(0,-.12,2.05),1.64,.055,MINT,rotation=(math.pi/2,0,0),segments=48)
ring("Outer brass inlay",(0,-.34,2.05),1.90,.025,GOLD,rotation=(math.pi/2,0,0),segments=48)
export("portal")

reset()
for i in range(6):
    angle=math.tau*i/6
    radius=.5 if i else 0
    height=4.7 if i==0 else 2.5+random.random()*1.3
    crystal("Growth crystal",(math.sin(angle)*radius,math.cos(angle)*radius,0),.55 if i==0 else .34,height,TEAL if i%2 else TEAL_LIGHT,(.1*math.cos(angle),.15*math.sin(angle),angle))
cylinder("Crystal bedrock",(0,0,.10),1.0,.3,ROCK,vertices=9,radius2=.85)
export("crystal_tree")

reset()
verts=[]
n=12
for z,r in [(0,1),(-.35,1.06),(-1.3,.55)]:
    for i in range(n):
        a=math.tau*i/n
        factor=1+random.uniform(-.075,.075)
        verts.append((math.cos(a)*r*factor,math.sin(a)*r*factor,z))
faces=[tuple(range(n))]
for level in range(2):
    for i in range(n):
        faces.append((level*n+i,(level+1)*n+i,(level+1)*n+(i+1)%n,level*n+(i+1)%n))
faces.append(tuple(reversed(range(24,36))))
mesh=bpy.data.meshes.new("Floating geology")
mesh.from_pydata(verts,[],faces)
obj=bpy.data.objects.new("Floating geology",mesh)
bpy.context.collection.objects.link(obj)
finish(obj,"Floating basalt island",ROCK)
export("island")

reset()
box("Architectural tile",(0,0,-.14),(2,2,.28),STONE,.035)
box("Thin edge inlay",(0,-.92,.005),(1.7,.025,.008),GOLD,.004)
export("tile")

reset()
box("Column foot",(0,0,.12),(1.1,1.1,.24),STONE)
box("Ancient column",(0,0,1.9),(.75,.75,3.5),STONE,.05)
box("Column capital",(0,0,3.7),(1.12,1.12,.30),STONE)
for z in [.45,3.35]:
    box("Brass course",(0,0,z),(.81,.81,.12),GOLD,.015)
export("column")

reset()
cylinder("Receiver base",(0,0,.15),.7,.30,DARK)
box("Receiver plinth",(0,0,.8),(.66,.55,1.2),DARK,.07)
ring("Receiver ring",(0,-.31,1.35),.36,.07,GOLD,rotation=(math.pi/2,0,0))
cylinder("Receiver surface",(0,-.34,1.35),.26,.04,MINT,rotation=(math.pi/2,0,0))
export("receiver")

reset()
cylinder("Pedestal base",(0,0,.18),.86,.36,DARK)
cylinder("Tapered pedestal",(0,0,.55),.67,.40,GOLD,radius2=.52)
cylinder("Pedestal cap",(0,0,.82),.65,.14,DARK)
ring("Pedestal illumination",(0,0,.92),.48,.025,MINT)
export("pedestal")

reset()
cylinder("Armillary base",(0,0,.22),1.4,.44,DARK)
cylinder("Armillary mount",(0,0,.6),.5,.65,GOLD)
for tilt in [0,.9,1.7]:
    ring("Celestial orbit",(0,0,2),1.15,.065,GOLD,rotation=(math.pi/2,tilt,.3))
crystal("Central star",(0,0,1.35),.34,1.2,MINT)
export("armillary")

(OUT / "manifest.json").write_text(json.dumps(REPORT,indent=2)+"\n")
print("ALL_ASSETS_OK",flush=True)
