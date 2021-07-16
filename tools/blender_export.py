import bpy
import bmesh
import argparse
import sys
import os
from mathutils import Vector, Matrix

# pack helpers
def tohex(val, nbits):
    return (hex((int(round(val,0)) + (1<<nbits)) % (1<<nbits))[2:]).zfill(nbits>>2)

# variable length packing (1 or 2 bytes)
def pack_variant(x):
    x=int(x)
    if x>0x7fff:
      raise Exception('Unable to convert: {} into a 1 or 2 bytes'.format(x))
    # 2 bytes
    if x>127:
        h = "{:04x}".format(x + 0x8000)
        if len(h)!=4:
            raise Exception('Unable to convert: {} into a word: {}'.format(x,h))
        return h
    # 1 byte
    h = "{:02x}".format(x)
    if len(h)!=2:
        raise Exception('Unable to convert: {} into a byte: {}'.format(x,h))
    return h

# single byte (unsigned short)
def pack_byte(x):
    h = tohex(x,8)
    if len(h)!=2:
        raise Exception('Unable to convert: {} into a byte: {}'.format(x,h))
    return h
    
# short must be between -32000/32000
def pack_int(x):
    h = tohex(x,16)
    if len(h)!=4:
        raise Exception('Unable to convert: {} into a word: {}'.format(x,h))
    return h

def pack_int32(x):
    h = tohex(x,32)
    if len(h)!=8:
        raise Exception('Unable to convert: {} into a dword: {}'.format(x,h))
    return h

# 16:16 fixed point value
# 4 bytes
def pack_fixed(x):
    h = tohex(int(x*(1<<16)),32)
    if len(h)!=8:
        raise Exception('Unable to convert: {} into a dword: {}'.format(x,h))
    return h

# short must be between -127/127
def pack_short(x):
    h = "{:02x}".format(int(round(x+128,0)))
    if len(h)!=2:
        raise Exception('Unable to convert: {} into a byte: {}'.format(x,h))
    return h

# float must be between -4/+3.968 resolution: 0.03125
# 1 byte
def pack_float(x):
    h = "{:02x}".format(int(round(32*x+128,0)))
    if len(h)!=2:
        raise Exception('Unable to convert: {} into a byte: {}'.format(x,h))
    return h
# double must be between -128/+127 resolution: 0.0078
# 2 bytes
def pack_double(x):
    h = "{}".format(tohex(128*x+16384,16))
    if len(h)!=4:
        raise Exception('Unable to convert: {} into a word: {}'.format(x,h))
    return h

argv = sys.argv
if "--" not in argv:
    argv = []
else:
   argv = argv[argv.index("--") + 1:]

try:
    parser = argparse.ArgumentParser(description='Exports Blender model as a byte array',prog = "blender -b -P "+__file__+" --")
    parser.add_argument('-o','--out', help='Output file', required=True, dest='out')
    args = parser.parse_args(argv)
except Exception as e:
    sys.exit(repr(e))

scene = bpy.context.scene

# https://blender.stackexchange.com/questions/153048/blender-2-8-python-input-rgb-doesnt-match-hex-color-nor-actual-color
# seriously???
# import matplotlib.colors
# matplotlib.colors.to_rgb('#B4FBB8')
# ['0 = (0.0, 0.0, 0.0)'
#  '1 = (0.11372549019607843, 0.16862745098039217, 0.3254901960784314)'
#  '2 = (0.49411764705882355, 0.1450980392156863, 0.3254901960784314)'
#  '3 = (0.0, 0.5294117647058824, 0.3176470588235294)'
#  '4 = (0.6705882352941176, 0.3215686274509804, 0.21176470588235294)'
#  '5 = (0.37254901960784315, 0.3411764705882353, 0.30980392156862746)'
#  '6 = (0.7607843137254902, 0.7647058823529411, 0.7803921568627451)'
#  '7 = (1.0, 0.9450980392156862, 0.9098039215686274)'
#  '8 = (1.0, 0.0, 0.30196078431372547)'
#  '9 = (1.0, 0.6392156862745098, 0.0)'
#  '10 = (1.0, 0.9254901960784314, 0.15294117647058825)'
#  '11 = (0.0, 0.8941176470588236, 0.21176470588235294)'
#  '12 = (0.1607843137254902, 0.6784313725490196, 1.0)'
#  '13 = (0.5137254901960784, 0.4627450980392157, 0.611764705882353)'
#  '14 = (1.0, 0.4666666666666667, 0.6588235294117647)'
#  '15 = (1.0, 0.8, 0.6666666666666666)']

p8_colors = ['000000','1D2B53','7E2553','008751','AB5236','5F574F','C2C3C7','FFF1E8','FF004D','FFA300','FFEC27','00E436','29ADFF','83769C','FF77A8','FFCCAA']
def diffuse_to_p8color(rgb):
    h = "{:02X}{:02X}{:02X}".format(int(round(255*rgb[0])),int(round(255*rgb[1])),int(round(255*rgb[2])))
    try:
        #print("diffuse:{} -> {}\n".format(rgb,p8_colors.index(h)))
        return p8_colors.index(h)
    except Exception as e:
        # unknown color
        raise Exception('Unknown color: 0x{}'.format(h))

# colliders (up to 8)
# ID must start at 1
solid_db = {
 "SOLID_1": 1,
 "SOLID_2": 2,
 "SOLID_3": 3,
 "SOLID_4": 4,
 "SOLID_5": 5,
 "SOLID_6": 6,
 "SOLID_7": 7,
 "SOLID_8": 8
}

# Convert from Blender format to y-up format
def pack_vector(co):
    return "{}{}{}".format(pack_double(co.x), pack_double(co.z), pack_double(co.y))

def export_layer(layer):
    # data
    s = ""
    
    # pick first object
    obcontext = [o for o in layer.objects if o.type == 'MESH'][0]
    obdata = obcontext.data
    bm = bmesh.new()
    bm.from_mesh(obdata)

    # create vertex group lookup dictionary for names
    vgroup_names = {vgroup.index: vgroup.name for vgroup in obcontext.vertex_groups}
    # create dictionary of vertex group assignments per vertex
    vgroups = {v.index: [vgroup_names[g.group] for g in v.groups] for v in obdata.vertices}

    # create a map loop index -> vertex index (see: https://www.python.org/dev/peps/pep-0274/)
    loop_vert = {l.index:l.vertex_index for l in obdata.loops}

    vlen = len(obdata.vertices)
    # vertices
    s += pack_variant(vlen)
    for v in obdata.vertices:
        s += pack_vector(v.co)

    # faces
    s += pack_variant(len(obdata.polygons))
    for f in obdata.polygons:
        # face flags
        is_dual_sided = 0
        color = 1   

        vlen = len(f.loop_indices)
        if vlen<3 or vlen>4:
            raise Exception("Only tri or quad supported (#verts: {})".format(vlen))

        is_quad = vlen==4 and 0x20 or 0
        has_edges = 0
        if len(obcontext.material_slots)>0:
            slot = obcontext.material_slots[f.material_index]
            mat = slot.material
            is_dual_sided = mat.use_backface_culling==False and 0x10 or 0
            color = diffuse_to_p8color(mat.diffuse_color)
            has_edges = mat.get('edges')=="true" and 0x40 or 0
        
        # bit layout:
        # 0x40: edges
        # 0x20: quad
        # 0x10: dual sided
        # 3-0: color index 
        s += "{:02x}".format(has_edges | is_quad| is_dual_sided | color)
            
        # is face part of a solid?
        face_verts = {loop_vert[li]:li for li in f.loop_indices}
        solid_group = {vgroups[k][0]:v for k,v in face_verts.items() if len(vgroups[k])==1}
        solid_group = set([solid_db[k] for k,v in solid_group.items() if k in solid_db])
        if len(solid_group)>1:
            raise Exception('Multiple vertex groups for the same face') 
        if len(solid_group)==1:
            # get group ID
            solid_group=solid_group.pop()
            s += "{:02x}".format(solid_group)
        else:
            s += "{:02x}".format(0)

        # + vertex ids (= edge loop)
        for li in f.loop_indices:
            s += pack_variant(loop_vert[li]+1)            

        # normal
        s += pack_vector(f.normal)
        
    return s

# model data
s = ""

# layers = lod
ln = 0
ls = ""
for i in range(2):
    lod_name = "lod{}".format(i)
    if lod_name in scene.collection.children:
        layer = scene.collection.children[lod_name]
        ln += 1
        # LOD visibility range
        ls += pack_variant(int(layer.get("lod_dist", 1024)))
        ls += export_layer(layer)
    else:
        # lod numbering discontinued
        break
# number of active lods
s += pack_variant(ln)
s += ls

#
with open(args.out, 'w') as f:
    f.write(s)

