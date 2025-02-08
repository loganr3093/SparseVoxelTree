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

//*************************************
// IsSolidVoxelAt
// - voxelPos: Voxel position to test
// - tree: Tree to test against
// - Returns: True if the voxel is solid
//
bool IsSolidVoxelAt(ivec3 voxelPos, in SparseVoxelTree tree);

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
    vec3 invDir = 1.0 / ray.Direction;
    vec3 pos = ray.Origin;
    float tmax = 0.0;

    for (int i = 0; i < 256; i++)
    {
        ivec3 voxelPos = ivec3(floor(pos));

        if (IsSolidVoxelAt(voxelPos, tree))
        {
            return HitInfo(true, vec3(1.0, 1.0, 1.0));
        }

        vec3 cellMin = voxelPos;
        vec3 cellMax = cellMin + 1.0;
        vec2 time = IntersectAABB(ray, cellMin, cellMax);

        tmax = time.y + 0.0001;
        pos = ray.Origin + tmax * ray.Direction;
    }

    return HitInfo(false, vec3(0.0));
}

// General Utility Functions

//*************************************
// IntersectAABB
// - ray: Ray to test intersection with
// - AABBMin: Minimum bounds of the AABB (for a cell, this is floor(pos))
// - AABBMax: Maximum bounds of the AABB (for a cell, AABBMin + vec3(1.0))
// - Returns: A vec2 containing tmin (always 0.0 here) and tmax (exit distance)
//
vec2 IntersectAABB(in Ray ray, in vec3 AABBMin, in vec3 AABBMax)
{
    // For a unit cell, the cell size is:
    vec3 cellSize = AABBMax - AABBMin;
    // Choose, for each axis, the side (min or max) based on the ray direction.
    // If ray.Direction < 0.0, step() returns 0.0 so we use AABBMin; otherwise, we use AABBMin + cellSize.
    vec3 sidePos = AABBMin + step(0.0, ray.Direction) * cellSize;
    vec3 invDir = 1.0 / ray.Direction;
    vec3 sideDist = (sidePos - ray.Origin) * invDir;
    // The exit distance is the minimum of the three side distances.
    float tExit = min(min(sideDist.x, sideDist.y), sideDist.z) + 0.0001;
    return vec2(0.0, tExit);
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
// - voxelPos: Voxel position to test (in integer cell coordinates)
// - tree: Tree to test against
// - Returns: True if the voxel is solid
//
bool IsSolidVoxelAt(ivec3 voxelPos, in SparseVoxelTree tree)
{
    // Start at the root; we assume the tree was built with a "scale" of 6.
    int scale = 6;
    ivec3 nodePos = ivec3(0);  // The origin (in voxel space) of the current node.
    Node currentNode = tree.Root;

    // Traverse the tree without recursion.
    while (true)
    {
        // If the current node is a leaf...
        if (IsLeaf(currentNode))
        {
            // A leaf covers a 4x4x4 block.
            // Compute the local coordinates (0..3) within this block.
            ivec3 local = voxelPos - nodePos;
            int index = local.x + local.y * 4 + local.z * 16; // index in [0,63]

            // Get the leaf's 64-bit child mask (packed as two 32-bit uints)
            uvec2 mask = ChildMask(currentNode);
            // Test the bit corresponding to 'index'.
            if (index < 32)
                return (((mask.x >> uint(index)) & 1u) != 0u);
            else
                return (((mask.y >> uint(index - 32)) & 1u) != 0u);
        }
        else
        {
            // Non-leaf node: the 64 children subdivide the current block.
            // Each level subdivides by 2 bits, so a child covers a block of size (1 << (scale-2)).
            int shift = scale - 2;
            ivec3 local = voxelPos - nodePos;
            // Compute child index within a 4x4x4 layout:
            int childIndex = (local.x >> shift)
                           + ((local.y >> shift) << 2)
                           + ((local.z >> shift) << 4);

            // Get the current node's child mask.
            uvec2 mask = ChildMask(currentNode);
            bool exists;
            if (childIndex < 32)
                exists = (((mask.x >> uint(childIndex)) & 1u) != 0u);
            else
                exists = (((mask.y >> uint(childIndex - 32)) & 1u) != 0u);

            // If this child does not exist, then the voxel is not solid.
            if (!exists)
                return false;

            // Compute the offset (number of set bits before our childIndex) to index into the NodePool.
            uint childOffset;
            if (childIndex < 32)
            {
                uint bits = mask.x & ((1u << uint(childIndex)) - 1u);
                childOffset = uint(bitCount(bits));
            }
            else
            {
                uint countLow = uint(bitCount(mask.x));
                int subIndex = childIndex - 32;
                uint bits = mask.y & ((1u << uint(subIndex)) - 1u);
                childOffset = countLow + uint(bitCount(bits));
            }

            // Get the base child pointer from the current node.
            uint childPtr = ChildPtr(currentNode);
            uint nextNodeIndex = childPtr + childOffset;
            // Fetch the child node from the global NodePool buffer.
            currentNode = NodePool[nextNodeIndex];

            // Update the origin for the next level.
            int offsetX = (childIndex & 3) << shift;
            int offsetY = ((childIndex >> 2) & 3) << shift;
            int offsetZ = ((childIndex >> 4) & 3) << shift;
            nodePos += ivec3(offsetX, offsetY, offsetZ);

            // Descend one level.
            scale -= 2;
        }
    }
}
