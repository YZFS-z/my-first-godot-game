#!/usr/bin/env python3
"""Parse glb file to extract node tree structure."""
import json
import struct
import sys

def parse_glb(path):
    with open(path, 'rb') as f:
        magic = f.read(4)
        if magic != b'glTF':
            print("Not a glb file")
            return None
        version = struct.unpack('<I', f.read(4))[0]
        total_length = struct.unpack('<I', f.read(4))[0]
        
        chunks = []
        while f.tell() < total_length:
            chunk_length = struct.unpack('<I', f.read(4))[0]
            chunk_type = f.read(4)
            chunk_data = f.read(chunk_length)
            chunks.append((chunk_type, chunk_data))
        
        # First chunk is JSON
        json_data = json.loads(chunks[0][1].decode('utf-8'))
        return json_data

def print_node_tree(gltf, depth=0, node_idx=None):
    nodes = gltf.get('nodes', [])
    if node_idx is None:
        # Print root nodes (scenes[0].nodes)
        scene = gltf.get('scenes', [{}])[0]
        roots = scene.get('nodes', [])
        for r in roots:
            print_node_tree(gltf, 0, r)
        return
    
    node = nodes[node_idx]
    prefix = "  " * depth
    name = node.get('name', f'node_{node_idx}')
    info = f"{prefix}{name}"
    
    if 'translation' in node:
        info += f" pos={node['translation']}"
    if 'rotation' in node:
        info += f" rot={node['rotation']}"
    if 'scale' in node:
        info += f" scale={node['scale']}"
    if 'mesh' in node:
        mesh_idx = node['mesh']
        meshes = gltf.get('meshes', [])
        if mesh_idx < len(meshes):
            mesh = meshes[mesh_idx]
            # Get AABB from accessors
            prims = mesh.get('primitives', [])
            if prims:
                pos_acc_idx = prims[0].get('attributes', {}).get('POSITION')
                if pos_acc_idx is not None:
                    accessors = gltf.get('accessors', [])
                    if pos_acc_idx < len(accessors):
                        acc = accessors[pos_acc_idx]
                        mins = acc.get('min', [])
                        maxs = acc.get('max', [])
                        if mins and maxs:
                            center = [(mins[i]+maxs[i])/2 for i in range(min(3, len(mins)))]
                            size = [(maxs[i]-mins[i]) for i in range(min(3, len(mins)))]
                            info += f"\n{prefix}  -> AABB min={mins[:3]} max={maxs[:3]}"
                            info += f"\n{prefix}  -> center={center} size={size}"
    
    print(info)
    for child_idx in node.get('children', []):
        print_node_tree(gltf, depth + 1, child_idx)

if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else 'assets/models/ah64_helicopter.glb'
    gltf = parse_glb(path)
    if gltf:
        print("=== AH-64 glb Node Tree ===")
        print_node_tree(gltf)
        
        # Search for specific nodes
        nodes = gltf.get('nodes', [])
        print("\n=== Key Node Search ===")
        for i, node in enumerate(nodes):
            name = node.get('name', '')
            if any(k in name for k in ['Rotor', 'Turret', 'Gun', 'Fuselage', 'Main', 'Tail']):
                parent = None
                for j, pnode in enumerate(nodes):
                    if i in pnode.get('children', []):
                        parent = nodes[j].get('name', f'node_{j}')
                        break
                print(f"  [{i}] {name} parent={parent}")
