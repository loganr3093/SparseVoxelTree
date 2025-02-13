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
// Axis-aligned bounding box structure
// - Min: Minimum bounds
// - Max: Maximum bounds
struct AABB
{
    vec4 Min;
    vec4 Max;
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

    uint _padding[3];

    AABB Bounds;
    mat4 Transform;
};

//*****************************************************************************
// Function Declarations
//*****************************************************************************

// Node Utility Functions
bool IsLeaf(in Node node);
uint ChildPtr(in Node node);
uvec2 ChildMask(in Node node);

// Tree Utility Functions
HitInfo RayCast(in Ray ray, in SparseVoxelTree tree);

// Tree Traversal Utility Functions
int GetNodeCellIndex(vec3 pos, int scaleExp);
vec3 FloorScale(vec3 pos, int scaleExp);
uint Popcnt64(uvec2 mask);

// General Utility Functions
vec2 IntersectAABB(in Ray ray, in vec3 AABBMin, in vec3 AABBMax);
void GetPrimaryRay(out Ray ray);
vec3 GetSkyColor(in vec3 direction);
float GetScale(int scaleExp);
bool IsSolidVoxelAt(in vec3 pos, in SparseVoxelTree tree);

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

    HitInfo hit = RayCast(ray, tree);

    vec3 albedo;

    if (hit.Hit)
    {
        albedo = hit.Color;
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
    return (node.PackedData[0] & 1u) != 0u;
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
    vec3 invDir = 1.0 / ray.Direction;
    vec3 pos = ray.Origin;
    vec3 dirSign = step(0.0, ray.Direction); // 1 if direction >= 0, else 0

    for (int i = 0; i < 256; i++)
    {
        vec3 voxelPos = floor(pos);
        if (IsSolidVoxelAt(voxelPos, tree))
        {
            return HitInfo(true, vec3(1.0, 1.0, 1.0));
        }

        vec3 cellMin = voxelPos;
        // Calculate exit planes based on direction
        vec3 sidePos = cellMin + dirSign * 1.0;
        // Compute distances to exit planes
        vec3 sideDist = (sidePos - ray.Origin) * invDir;
        // Find the nearest exit (tmax)
        float tmax = min(min(sideDist.x, sideDist.y), sideDist.z) + 0.0001;
        pos = ray.Origin + tmax * ray.Direction;
    }

    return HitInfo(false, vec3(0.0));
}

// Tree Traversal Utility Functions

//*************************************
// Returns the cell index within the 4x4x4 node for a given position.
// It works by interpreting the float's bit pattern and extracting 2 bits
// per axis using a right-shift by scaleExp and a mask of 3.
//
// - pos: Position to get cell index for
// - scaleExp: Current scale exponent
// - Returns: Cell index
//
int GetNodeCellIndex(vec3 pos, int scaleExp)
{
    // Convert each float to its unsigned int bit representation.
    uvec3 cellPos = (floatBitsToUint(pos) >> uint(scaleExp)) & uvec3(3u);
    return int(cellPos.x + cellPos.z * 4u + cellPos.y * 16u);
}

//*************************************
// Floors the coordinate to the current scale by zeroing out the lower
// scaleExp bits in the mantissa. This gives the minimum corner of the
// cell at the current depth.
//
// - pos: Position to floor
// - scaleExp: Current scale exponent
// - Returns: Floored position
//
vec3 FloorScale(vec3 pos, int scaleExp)
{
    uvec3 mask = uvec3(~0u) << uint(scaleExp);
    return uintBitsToFloat(floatBitsToUint(pos) & mask);
}

//*************************************
// GetScale computes the size of the cell at the current level.
// The cell size is given by: scale = 2^(scaleExp - 23), computed by constructing
// the float from its exponent bits.
//
// - scaleExp: Current scale exponent
// - Returns: Cell scale
//
float GetScale(int scaleExp)
{
    uint exponent = uint(scaleExp - 23 + 127);
    return uintBitsToFloat(exponent << 23);
}

//*************************************
// Popcnt64
// - mask: Mask to count bits in
// - Returns: Number of set bits in the mask
//
uint Popcnt64(uvec2 mask)
{
    return bitCount(mask.x) + bitCount(mask.y);
}

// General Utility Functions

//*************************************
// IntersectAABB
// - ray: Ray to test intersection with
// - AABBMin: Minimum bounds of the AABB (for a cell, this is floor(pos))
// - AABBMax: Maximum bounds of the AABB (for a cell, AABBMin + vec3(1.0))
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

//*************************************
// IsSolidVoxelAt
// This function traverses the tree by using the fractional representation of pos,
// which is assumed to lie in [1.0, 2.0). The initial scale exponent is set to 21,
// and at each level we extract 2 bits from the float's mantissa to select a child cell.
// The traversal continues until an empty cell or a leaf is encountered.
//
// - voxelPos: Voxel position to test (in integer cell coordinates)
// - tree: Tree to test against
// - Returns: True if the voxel is solid
//
bool IsSolidVoxelAt(in vec3 pos, in SparseVoxelTree tree)
{
    if (any(lessThan(pos, tree.Bounds.Min.xyz)) || any(greaterThan(pos, tree.Bounds.Max.xyz)))
    {
        // If any coordinate is below the minimum or above the maximum, return false.
        return false;
    }

    // Voxel grid with alternating values
    bool grid[256];
    for (int i = 0; i < 256; i++)
    {
        grid[i] = (i % 31 == 0) || (i % 31 == 1) || (i % 31 == 2);
    }

    // Compute an index based on the voxel position
    int index = int(mod(pos.x + pos.y * 16.0 + pos.z * 16.0 * 16.0, 256.0));

    return grid[index];
}