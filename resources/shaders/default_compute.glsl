// Type: Compute Shader
// Description: Default compute shader for ray tracing a sparse voxel 64-tree.

// References:
//  https://dubiousconst282.github.io/2024/10/03/voxel-ray-tracing/

#version 430 core

layout (local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// Output image (binding = 0)
layout(rgba32f, binding = 0) uniform image2D imgOutput;

//*****************************************************************************
// Structures
//*****************************************************************************

//*************************************
// Ray structure
// - origin: Ray origin
// - direction: Ray direction
//
struct Ray
{
    vec3 Origin;
    vec3 Direction;
};

//*************************************
// Hit information holder structure
// - Hit: True if hit
// - Color: Hit color
//
struct HitInfo
{
    bool Hit;
    vec3 Color;
};

//*************************************
// Sparse Voxel 64-Tree Node structure
// - PackedData[0]: Combines IsLeaf (1 bit) and ChildPtr (31 bits).
// - PackedData[1]: Lower 32 bits of ChildMask.
// - PackedData[2]: Upper 32 bits of ChildMask.
//
struct Node
{
    uint PackedData[3];
};

//*************************************
// Sparse Voxel 64-Tree structure
// - Root: Root node of the tree
// - NodePoolPtr: Offset into the NodePool buffer
// - LeafDataPtr: Offset into the LeafData buffer
// - AABBMin: Lower bounds
// - AABBMax: Upper bounds
// - Transform: Transform matrix
//
struct SparseVoxelTree
{
    Node Root;
    uint NodePoolPtr;
    uint LeafDataPtr;
    vec3 AABBMin;
    vec3 AABBMax;
    mat4 Transform;
};

//*****************************************************************************
// Function Declarations
//*****************************************************************************

// Node Utility Functions

//*************************************
// IsLeaf
// - node: Node to test
// - Returns: True if the node is a leaf
//
bool IsLeaf(in Node node);

//*************************************
// ChildPtr
// - node: Node to get child pointer from
// - Returns: Child pointer
//
uint ChildPtr(in Node node);

//*************************************
// ChildMask
// - node: Node to get child mask from
// - Returns: Child mask
//
uvec2 ChildMask(in Node node);

// Tree Utility Functions

//*************************************
// RayCast
// - ray: Ray to cast
// - tree: Tree to cast against
// - Returns: Hit information
//
HitInfo RayCast(in Ray ray, in SparseVoxelTree tree);

// General Utility Functions

//*************************************
// IntersectAABB
// - ray: Ray to test intersection with
// - AABBMin: Minimum bounds of the AABB
// - AABBMax: Maximum bounds of the AABB
// - Returns: tmin and tmax of intersection
//
vec2 IntersectAABB(in Ray ray, in vec3 AABBMin, in vec3 AABBMax);

//*************************************
// GetPrimaryRay
// - ray: Output primary ray
//
void GetPrimaryRay(out Ray ray);

//*************************************
// GetSkyColor
// - direction: Direction to get sky color for
// - Returns: Sky color in that direction
//
vec3 GetSkyColor(in vec3 direction);

//*****************************************************************************
// Uniforms
//*****************************************************************************

// Screen resolution (width, height)
layout (location = 0) uniform vec2 ScreenSize;
// Camera view parameters (planeWidth, planeHeight, camera.NearClipPlane)
layout (location = 1) uniform vec3 ViewParams;
// Camera world transformation matrix
layout (location = 2) uniform mat4 CamWorldMatrix;

//*****************************************************************************
// Buffers
//*****************************************************************************

// Tree buffer (binding = 0)
layout(std430, binding = 0) buffer TreeBuffer
{
    SparseVoxelTree Trees[];
};

// Node pool buffer (binding = 1)
layout(std430, binding = 1) buffer NodePoolBuffer
{
    Node NodePool[];
};

// Leaf data buffer (binding = 2)
layout(std430, binding = 2) buffer LeafDataBuffer
{
    uint LeafData[];
};

//*****************************************************************************
// Main
//*****************************************************************************
void main()
{
    // Compute pixel coordinates from the global invocation ID.
    ivec2 pixelCoords = ivec2(gl_GlobalInvocationID.xy);
    // Discard if the pixel is outside the screen bounds.
    if (pixelCoords.x >= int(ScreenSize.x) || pixelCoords.y >= int(ScreenSize.y))
    {
        return;
    }

    Ray ray;
    GetPrimaryRay(ray);

    // For now we only have one tree, so use Trees[0].
    SparseVoxelTree tree = Trees[0];

    // (If your tree.AABB is in local space, you could transform the ray into that space.
    // For now we assume the AABB is in world space.)
    float tmin, tmax;
    // Perform AABB intersection test.
    vec2 result = IntersectAABB(ray, tree.AABBMin, tree.AABBMax);

    HitInfo hit = RayCast(ray, tree);

    vec3 albedo;

    if (hit.Hit)
    {
        albedo = hit.Color;
        return;
    }
    else
    {
        albedo = GetSkyColor(ray.Direction);
    }

    // Write the pixel color to the output image.
    imageStore(imgOutput, pixelCoords, vec4(albedo, 1.0));
}

//*****************************************************************************
// Function Definitions
//*****************************************************************************

// Node Utility Functions

//*************************************
// IsLeaf
// - node: Node to test
// - Returns: True if the node is a leaf
//
bool IsLeaf(in Node node)
{
    return (node.PackedData[0] & 1) != 0;
}

//*************************************
// ChildPtr
// - node: Node to get child pointer from
// - Returns: Child pointer
//
uint ChildPtr(in Node node)
{
    return node.PackedData[0] >> 1;
}

//*************************************
// ChildMask
// - node: Node to get child mask from
// - Returns: Child mask
//
uvec2 ChildMask(in Node node)
{
    return uvec2(node.PackedData[1], node.PackedData[2]);
}

// Tree Utility Functions

//*************************************
// RayCast
// - ray: Ray to cast
// - tree: Tree to cast against
// - Returns: Hit information
//
HitInfo RayCast(in Ray ray, in SparseVoxelTree tree)
{
    return HitInfo(false, vec3(0.0));
}

// General Utility Functions

//*************************************
// IntersectAABB
// - ray: Ray to test intersection with
// - AABBMin: Minimum bounds of the AABB
// - AABBMax: Maximum bounds of the AABB
// - Returns: tmin and tmax of intersection
//
vec2 IntersectAABB(in Ray ray, in vec3 AABBMin, in vec3 AABBMax)
{
    vec3 invDir = 1.0 / ray.Direction;

    vec3 t0 = (AABBMin - ray.Origin) * invDir;
    vec3 t1 = (AABBMax - ray.Origin) * invDir;

    vec3 temp = t0;
    t0 = min(temp, t1), t1 = max(temp, t1);

    float tmin = max(max(t0.x, t0.y), t0.z);
    float tmax = min(min(t1.x, t1.y), t1.z);

    return vec2(tmin, tmax);
}

//*************************************
// GetPrimaryRay
// - ray: Output primary ray
//
void GetPrimaryRay(out Ray ray)
{
    // Compute the texture coordinates for the current invocation.
    vec2 TexCoords = vec2(float(gl_GlobalInvocationID.x) / ScreenSize.x,
                          float(gl_GlobalInvocationID.y) / ScreenSize.y);

    // Generate a view point in local (camera) space.
    vec3 viewPointLocal = vec3(TexCoords - 0.5, 1.0) * ViewParams;
    // Transform the view point into world space.
    vec3 viewPoint = (CamWorldMatrix * vec4(viewPointLocal, 1.0)).xyz;

    // Initialize our ray
    ray.Origin    = CamWorldMatrix[3].xyz;
    ray.Direction = normalize(viewPoint - ray.Origin);
}

//*************************************
// GetSkyColor
// - direction: Direction to get sky color for
// - Returns: Sky color in that direction
//
vec3 GetSkyColor(in vec3 direction)
{
    return vec3(0.25, 0.25, 0.4);
}