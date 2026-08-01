"""
glbgen.py — zero-dependency procedural GLB generator.

Builds binary glTF (.glb) files that Godot 4 imports natively.
No numpy, no trimesh, no Blender required — just the stdlib.

Concept:
  - A "Part" is a mesh (positions, normals, indices) + a base color.
  - You compose Parts (box, cylinder, cone, sphere) with offsets/scales.
  - export_glb() writes everything as ONE GLB with per-part materials.

Run `python3 tools/glbgen.py` to emit a demo low-poly tree.
"""
import struct, json, math


# ---------- geometry primitives (return positions, indices) ----------

def box(sx=1.0, sy=1.0, sz=1.0):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    # 24 verts (4 per face) so each face gets flat normals
    faces = [
        # (normal, 4 corners ccw)
        ((0, 0, 1),  [(-hx,-hy, hz),( hx,-hy, hz),( hx, hy, hz),(-hx, hy, hz)]),
        ((0, 0,-1),  [( hx,-hy,-hz),(-hx,-hy,-hz),(-hx, hy,-hz),( hx, hy,-hz)]),
        ((1, 0, 0),  [( hx,-hy, hz),( hx,-hy,-hz),( hx, hy,-hz),( hx, hy, hz)]),
        ((-1,0, 0),  [(-hx,-hy,-hz),(-hx,-hy, hz),(-hx, hy, hz),(-hx, hy,-hz)]),
        ((0, 1, 0),  [(-hx, hy, hz),( hx, hy, hz),( hx, hy,-hz),(-hx, hy,-hz)]),
        ((0,-1, 0),  [(-hx,-hy,-hz),( hx,-hy,-hz),( hx,-hy, hz),(-hx,-hy, hz)]),
    ]
    pos, nrm, idx = [], [], []
    for n, corners in faces:
        base = len(pos)
        for c in corners:
            pos.append(c); nrm.append(n)
        idx += [base, base+1, base+2, base, base+2, base+3]
    return pos, nrm, idx


def cylinder(radius=0.5, height=1.0, segments=12, cap=True):
    pos, nrm, idx = [], [], []
    hh = height / 2
    # side wall
    for i in range(segments):
        a0 = 2*math.pi*i/segments
        a1 = 2*math.pi*(i+1)/segments
        x0, z0 = math.cos(a0)*radius, math.sin(a0)*radius
        x1, z1 = math.cos(a1)*radius, math.sin(a1)*radius
        n0 = (math.cos(a0), 0, math.sin(a0))
        n1 = (math.cos(a1), 0, math.sin(a1))
        b = len(pos)
        pos += [(x0,-hh,z0),(x1,-hh,z1),(x1,hh,z1),(x0,hh,z0)]
        nrm += [n0,n1,n1,n0]
        idx += [b,b+1,b+2,b,b+2,b+3]
    if cap:
        for sign, ny in ((hh,1),(-hh,-1)):
            c = len(pos); pos.append((0,sign,0)); nrm.append((0,ny,0))
            ring_start = len(pos)
            for i in range(segments):
                a = 2*math.pi*i/segments
                pos.append((math.cos(a)*radius, sign, math.sin(a)*radius))
                nrm.append((0,ny,0))
            for i in range(segments):
                a, bb = ring_start+i, ring_start+(i+1)%segments
                if ny > 0: idx += [c, a, bb]
                else:      idx += [c, bb, a]
    return pos, nrm, idx


def cone(radius=0.5, height=1.0, segments=12):
    pos, nrm, idx = [], [], []
    apex = (0, height/2, 0)
    for i in range(segments):
        a0 = 2*math.pi*i/segments
        a1 = 2*math.pi*(i+1)/segments
        p0 = (math.cos(a0)*radius, -height/2, math.sin(a0)*radius)
        p1 = (math.cos(a1)*radius, -height/2, math.sin(a1)*radius)
        nx, nz = math.cos((a0+a1)/2), math.sin((a0+a1)/2)
        n = (nx, radius/max(height,1e-5), nz)
        ln = math.sqrt(sum(v*v for v in n)); n = tuple(v/ln for v in n)
        b = len(pos); pos += [p0,p1,apex]; nrm += [n,n,n]
        idx += [b,b+1,b+2]
    # base
    c = len(pos); pos.append((0,-height/2,0)); nrm.append((0,-1,0))
    rs = len(pos)
    for i in range(segments):
        a = 2*math.pi*i/segments
        pos.append((math.cos(a)*radius,-height/2,math.sin(a)*radius)); nrm.append((0,-1,0))
    for i in range(segments):
        idx += [c, rs+(i+1)%segments, rs+i]
    return pos, nrm, idx


# ---------- part composition ----------

class Part:
    def __init__(self, geom, color=(0.8,0.8,0.8,1.0), offset=(0,0,0)):
        pos, nrm, idx = geom
        ox, oy, oz = offset
        self.pos = [(x+ox, y+oy, z+oz) for (x,y,z) in pos]
        self.nrm = nrm
        self.idx = idx
        self.color = color


# ---------- GLB writer ----------

def export_glb(parts, path):
    bin_blob = bytearray()
    accessors, bufferViews, meshes, materials, nodes = [], [], [], [], []

    def add_view(data, target):
        while len(bin_blob) % 4: bin_blob.append(0)
        off = len(bin_blob); bin_blob.extend(data)
        bufferViews.append({"buffer":0,"byteOffset":off,"byteLength":len(data),"target":target})
        return len(bufferViews)-1

    for pi, part in enumerate(parts):
        # positions
        flat = [c for v in part.pos for c in v]
        pv = add_view(struct.pack(f"<{len(flat)}f", *flat), 34962)
        mn = [min(v[i] for v in part.pos) for i in range(3)]
        mx = [max(v[i] for v in part.pos) for i in range(3)]
        a_pos = len(accessors)
        accessors.append({"bufferView":pv,"componentType":5126,"count":len(part.pos),
                          "type":"VEC3","min":mn,"max":mx})
        # normals
        flat = [c for v in part.nrm for c in v]
        nv = add_view(struct.pack(f"<{len(flat)}f", *flat), 34962)
        a_nrm = len(accessors)
        accessors.append({"bufferView":nv,"componentType":5126,"count":len(part.nrm),"type":"VEC3"})
        # indices
        iv = add_view(struct.pack(f"<{len(part.idx)}I", *part.idx), 34963)
        a_idx = len(accessors)
        accessors.append({"bufferView":iv,"componentType":5125,"count":len(part.idx),"type":"SCALAR"})
        # material
        materials.append({"pbrMetallicRoughness":{"baseColorFactor":list(part.color),
                          "metallicFactor":0.0,"roughnessFactor":0.85},"name":f"mat{pi}"})
        meshes.append({"primitives":[{"attributes":{"POSITION":a_pos,"NORMAL":a_nrm},
                       "indices":a_idx,"material":pi}]})
        nodes.append({"mesh":pi,"name":f"part{pi}"})

    gltf = {
        "asset":{"version":"2.0","generator":"glbgen.py"},
        "scene":0,"scenes":[{"nodes":list(range(len(nodes)))}],
        "nodes":nodes,"meshes":meshes,"materials":materials,
        "accessors":accessors,"bufferViews":bufferViews,
        "buffers":[{"byteLength":len(bin_blob)}],
    }

    json_bytes = json.dumps(gltf, separators=(",",":")).encode("utf-8")
    while len(json_bytes) % 4: json_bytes += b" "
    while len(bin_blob) % 4: bin_blob.append(0)

    total = 12 + 8 + len(json_bytes) + 8 + len(bin_blob)
    with open(path, "wb") as f:
        f.write(b"glTF"); f.write(struct.pack("<II", 2, total))
        f.write(struct.pack("<I", len(json_bytes))); f.write(b"JSON"); f.write(json_bytes)
        f.write(struct.pack("<I", len(bin_blob)));  f.write(b"BIN\x00"); f.write(bin_blob)
    return path


# ---------- demo: low-poly tree ----------

if __name__ == "__main__":
    import os
    out_dir = os.path.join(os.path.dirname(__file__), "..", "assets", "models")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "tree.glb")
    parts = [
        Part(cylinder(0.18, 1.2, 10), color=(0.40,0.26,0.13,1), offset=(0,0.6,0)),     # trunk
        Part(cone(0.95, 1.1, 12),     color=(0.16,0.55,0.22,1), offset=(0,1.5,0)),     # foliage 1
        Part(cone(0.75, 0.9, 12),     color=(0.20,0.62,0.26,1), offset=(0,2.1,0)),     # foliage 2
        Part(cone(0.50, 0.8, 12),     color=(0.24,0.68,0.30,1), offset=(0,2.7,0)),     # foliage 3
    ]
    export_glb(parts, out)
    sz = os.path.getsize(out)
    print(f"wrote {out} ({sz} bytes)")
