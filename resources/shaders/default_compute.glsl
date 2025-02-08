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
// - Color: Hit color
//
struct HitInfo
{
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

// Standard slab method for AABB intersection.
// Returns true if the ray (rayOrigin, rayDir) intersects the AABB defined by (boxMin, boxMax).

//*************************************
// IntersectAABB
// - ray: Ray to test
// - boxMin: Lower bounds of the AABB
// - boxMax: Upper bounds of the AABB
// - tmin: Minimum intersection distance
// - tmax: Maximum intersection distance
// Returns: True if the ray intersects the AABB
//
bool IntersectAABB(in Ray ray, in vec3 boxMin, in vec3 boxMax, out float tmin, out float tmax);

void GetPrimaryRay(out Ray ray);

HitInfo RayCast(in Ray ray, in SparseVoxelTree tree);

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
    bool hit = IntersectAABB(ray, tree.AABBMin, tree.AABBMax, tmin, tmax);

    HitInfo hit = RayCast()

    // Set pixel color: white if hit, black otherwise.
    vec3 color = hit ? vec3(1.0) : vec3(0.0);

    // Write the pixel color to the output image.
    imageStore(imgOutput, pixelCoords, vec4(color, 1.0));
}

//*****************************************************************************
// Function Definitions
//*****************************************************************************

bool IntersectAABB(in Ray ray, in vec3 boxMin, in vec3 boxMax, out float tmin, out float tmax)
{
    vec3 invDir = 1.0 / ray.Direction;
    vec3 t0 = (boxMin - ray.Origin) * invDir;
    vec3 t1 = (boxMax - ray.Origin) * invDir;
    vec3 tsmaller = min(t0, t1);
    vec3 tbigger  = max(t0, t1);
    tmin = max(max(tsmaller.x, tsmaller.y), tsmaller.z);
    tmax = min(min(tbigger.x,  tbigger.y),  tbigger.z);
    return tmax >= max(tmin, 0.0);
}

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

HitInfo RayCast(in Ray ray, in SparseVoxelTree tree)
{
    // Magic goes here
}