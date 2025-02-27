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
// - Origin: Ray origin
// - Direction: Ray direction
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
// - PackedData[0]: Combines IsLeaf (highest bit) and ChildPtr (lower 31 bits).
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
// - AABB: Bounding box
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
// Helper Functions for 64-bit Masks
//*****************************************************************************

// Returns true if the bit at position 'bitIndex' is set in the 64-bit mask.
bool IsBitSet(uvec2 mask, uint bitIndex)
{
    if (bitIndex < 32u)
        return ((mask.x >> bitIndex) & 1u) != 0u;
    else
        return ((mask.y >> (bitIndex - 32u)) & 1u) != 0u;
}

// Returns the number of set bits in 'mask' _below_ bit position 'bitIndex'.
uint Popcnt64Below(uvec2 mask, uint bitIndex)
{
    if (bitIndex < 32u)
    {
        uint lower = mask.x & ((1u << bitIndex) - 1u);
        return bitCount(lower);
    }
    else
    {
        uint lowerCount = bitCount(mask.x);
        uint upperBits = bitIndex - 32u;
        uint upper = mask.y & ((1u << upperBits) - 1u);
        return lowerCount + bitCount(upper);
    }
}

//*****************************************************************************
// Function Declarations
//*****************************************************************************

// Node Utility Functions
bool IsLeaf(in Node node);
uint ChildPtr(in Node node);
uvec2 ChildMask(in Node node);

// Tree Utility Functions
HitInfo RayCast(in Ray ray, in SparseVoxelTree tree);

// Tree Traversal Utility Functions (legacy; not used by our new RayCast)
int GetNodeCellIndex(vec3 pos, int scaleExp);
vec3 FloorScale(vec3 pos, int scaleExp);
uint Popcnt64(uvec2 mask);

// General Utility Functions
vec2 IntersectAABB(in Ray ray, in vec3 AABBMin, in vec3 AABBMax);
void GetPrimaryRay(out Ray ray);
vec3 GetSkyColor(in vec3 direction);
float GetScale(int scaleExp);

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

layout(std430, binding = 3) buffer PaletteBuffer {
    vec4 Palette[];
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
    // Highest bit (bit 31) is the leaf flag.
    return (node.PackedData[0] & 0x80000000u) != 0u;
}

//*************************************
// ChildPtr
// - node: Node to get child pointer from
// - Returns: Child pointer (lower 31 bits)
//
uint ChildPtr(in Node node)
{
    return node.PackedData[0] & 0x7FFFFFFFu;
}

//*************************************
// ChildMask
// - node: Node to get child mask from
// - Returns: Child mask as a 64-bit value stored in a uvec2
//
uvec2 ChildMask(in Node node)
{
    return uvec2(node.PackedData[1], node.PackedData[2]);
}

//*****************************************************************************
// RayCast
// Updated ray casting function that traverses the sparse voxel tree in integer voxel space.
// This version assumes that the tree was built with an initial scale of 6 (i.e. a 64x64x64 volume)
// and that the tree’s AABB.Min is at an integer position (e.g. (0,0,0)).
//*****************************************************************************

HitInfo RayCast(in Ray ray, in SparseVoxelTree tree)
{
    // --- Compute intersection with the tree's AABB ---
    vec3 boundsMin = tree.Bounds.Min.xyz;
    vec3 boundsMax = tree.Bounds.Max.xyz;
    vec3 invDir = 1.0 / ray.Direction;
    vec3 t1 = (boundsMin - ray.Origin) * invDir;
    vec3 t2 = (boundsMax - ray.Origin) * invDir;
    vec3 tMinVec = min(t1, t2);
    vec3 tMaxVec = max(t1, t2);
    float tEntry = max(max(tMinVec.x, tMinVec.y), tMinVec.z);
    float tExit  = min(min(tMaxVec.x, tMaxVec.y), tMaxVec.z);
    if (tExit < 0.0 || tEntry > tExit)
        return HitInfo(false, vec3(0.0));

    // Start at the AABB entry point.
    float t = (tEntry > 0.0) ? tEntry : 0.0;
    vec3 rayPos = ray.Origin + t * ray.Direction;

    // --- Set up initial tree traversal parameters ---
    // currentScale is 6 because 2^6 = 64, matching the voxel map size.
    int currentScale = 6;
    // Assume the tree's AABB.Min is at an integer coordinate (e.g., (0,0,0)).
    ivec3 nodeOrigin = ivec3(boundsMin);
    Node node = tree.Root;

    // --- Traverse along the ray (up to 256 steps) ---
    for (int i = 0; i < 256; i++)
    {
        // Determine the size of the current node region.
        int nodeSize = 1 << currentScale; // region covers [nodeOrigin, nodeOrigin + nodeSize)
        ivec3 ipos = ivec3(floor(rayPos));
        // If the current voxel position is outside the current node region, reset to root.
        if (any(lessThan(ipos, nodeOrigin)) || any(greaterThanEqual(ipos, nodeOrigin + ivec3(nodeSize))))
        {
            node = tree.Root;
            currentScale = 6;
            nodeOrigin = ivec3(boundsMin);
        }

        // At the current level, each cell spans 2^(currentScale-2) voxels.
        int shift = currentScale - 2;
        ivec3 localCoord = ipos - nodeOrigin;
        int cell_x = (localCoord.x >> shift) & 3;
        int cell_y = (localCoord.y >> shift) & 3;
        int cell_z = (localCoord.z >> shift) & 3;
        // IMPORTANT: Use the same ordering as your CPU code: x + y*4 + z*16.
        uint cellIndex = uint(cell_x + cell_y * 4 + cell_z * 16);

        // Descend the tree while a child exists for this cell.
        while (!IsLeaf(node) && IsBitSet(ChildMask(node), cellIndex))
        {
            // Determine the child offset by counting the number of set bits below cellIndex.
            uint childSlot = Popcnt64Below(ChildMask(node), cellIndex);
            node = NodePool[ChildPtr(node) + childSlot];

            // Update nodeOrigin for the child.
            nodeOrigin += ivec3((int(cellIndex) & 3) << shift,
                                ((int(cellIndex) >> 2) & 3) << shift,
                                ((int(cellIndex) >> 4) & 3) << shift);
            currentScale -= 2;
            shift = currentScale - 2;

            // Recompute local coordinates and cell index at the new level.
            localCoord = ipos - nodeOrigin;
            cell_x = (localCoord.x >> shift) & 3;
            cell_y = (localCoord.y >> shift) & 3;
            cell_z = (localCoord.z >> shift) & 3;
            cellIndex = uint(cell_x + cell_y * 4 + cell_z * 16);
        }

        // Check for a hit: if we're at a leaf and the cell is set.
        if (IsLeaf(node) && IsBitSet(ChildMask(node), cellIndex))
        {
            // Return a white hit.
            return HitInfo(true, Palette[LeafData[ChildPtr(node) + Popcnt64Below(ChildMask(node), cellIndex)]].rgb);
        }

        // --- Advance the ray using a standard voxel DDA step ---
        vec3 cellMin = floor(rayPos);
        vec3 tCandidate;
        if (ray.Direction.x > 0.0)
            tCandidate.x = (cellMin.x + 1.0 - rayPos.x) / ray.Direction.x;
        else if (ray.Direction.x < 0.0)
            tCandidate.x = (rayPos.x - cellMin.x) / -ray.Direction.x;
        else
            tCandidate.x = 1e30;
        if (ray.Direction.y > 0.0)
            tCandidate.y = (cellMin.y + 1.0 - rayPos.y) / ray.Direction.y;
        else if (ray.Direction.y < 0.0)
            tCandidate.y = (rayPos.y - cellMin.y) / -ray.Direction.y;
        else
            tCandidate.y = 1e30;
        if (ray.Direction.z > 0.0)
            tCandidate.z = (cellMin.z + 1.0 - rayPos.z) / ray.Direction.z;
        else if (ray.Direction.z < 0.0)
            tCandidate.z = (rayPos.z - cellMin.z) / -ray.Direction.z;
        else
            tCandidate.z = 1e30;

        float dt = min(tCandidate.x, min(tCandidate.y, tCandidate.z));
        t += dt + 0.0001;
        if (t > tExit)
            break;
        rayPos = ray.Origin + t * ray.Direction;
    }

    return HitInfo(false, vec3(0.0));
}

//*****************************************************************************
// Tree Traversal Utility Functions (legacy)
//*****************************************************************************

//*************************************
// Returns the cell index within the 4x4x4 node for a given position.
// This legacy function extracts bits from the float representation.
// - pos: Position to get cell index for
// - scaleExp: Current scale exponent
// - Returns: Cell index
//
int GetNodeCellIndex(vec3 pos, int scaleExp)
{
    uvec3 cellPos = (floatBitsToUint(pos) >> uint(scaleExp)) & uvec3(3u);
    return int(cellPos.x + cellPos.z * 4u + cellPos.y * 16u);
}

//*************************************
// Floors the coordinate to the current scale by zeroing out the lower scaleExp bits.
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

//*****************************************************************************
// General Utility Functions
//*****************************************************************************

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
    t0 = min(temp, t1);
    t1 = max(temp, t1);
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
    vec2 TexCoords = vec2(float(gl_GlobalInvocationID.x) / ScreenSize.x,
                          float(gl_GlobalInvocationID.y) / ScreenSize.y);
    vec3 viewPointLocal = vec3(TexCoords - 0.5, 1.0) * ViewParams;
    vec3 viewPoint = (CamWorldMatrix * vec4(viewPointLocal, 1.0)).xyz;
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
