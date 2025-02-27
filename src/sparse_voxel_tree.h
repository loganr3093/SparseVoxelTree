#pragma once
#include <cstdint>
#include <vector>
#include <glad/glad.h>
#include <glm/glm.hpp>
#include "voxel_map.h"
#include <iostream>

class VoxelTreeMemoryAllocator;

struct [[gnu::packed]] SparseVoxelTreeNode
{
    uint32_t IsLeaf : 1;     // Indicates if this node is a leaf containing plain voxels.
    uint32_t ChildPtr : 31;  // Absolute offset to array of existing child nodes/voxels.
    uint64_t ChildMask;      // Indicates which children/voxels are present in array.
};

class SparseVoxelTree
{
public:
    SparseVoxelTree(const VoxelMap& voxelMap);

    /**
     * @brief Recursively generates a Sparse Voxel Tree from a given voxel map.
     *
     * This function constructs a sparse voxel tree by subdividing the voxel map into a 4x4x4 grid at each level.
     * The algorithm operates in two main cases:
     *
     * 1. Leaf Node Creation (Base Case):
     *    - When the scale is equal to 2, the function treats the current region as a leaf node, representing a 4x4x4 tile.
     *    - It first asserts that the starting position is aligned on a 4-voxel grid.
     *    - It then repacks the voxels within this 4x4x4 region into a temporary array.
     *    - A bitmask is generated using the helper function PackBits64, where each bit corresponds to a voxel and is set
     *      if that voxel is non-zero.
     *    - The LeftPack function is used to "compress" the temporary array by removing entries for which the corresponding
     *      bit in the bitmask is zero.
     *    - The non-empty voxel data is then appended to a global container (leafData), and the node is marked as a leaf.
     *
     * 2. Internal Node Creation (Recursive Case):
     *    - For scales greater than 2, the function subdivides the current region into 64 smaller regions (a 4x4x4 grid).
     *    - It computes the relative position of each child region and calls generateTree recursively with a reduced scale.
     *    - If a child node contains any non-empty voxel data (indicated by a non-zero ChildMask), the corresponding bit
     *      in the parent's ChildMask is set.
     *    - All valid child nodes are collected in a temporary vector and then appended to a global node pool (nodePool).
     *    - The parent's ChildPtr is updated to reference the starting index of its children in the nodePool.
     *
     * Parameters:
     * - voxelMap: The voxel map containing voxel data and its dimensions.
     * - scale: The current scale level. When scale == 2, the region is treated as a leaf node (4x4x4 voxel tile).
     * - pos: The starting 3D position (origin) in the voxel map for the current region.
     *
     * Returns:
     * - A SparseVoxelTreeNode representing the current region in the voxel tree.
    */
    void GenerateTree(const VoxelMap& voxelMap);

    size_t GetTotalVoxels() const;

    uint8_t At(int32_t x, int32_t y, int32_t z) const;

    VoxelMap ToVoxelMap() const;

    void PrintTree() const;

    // Get AABB and Transform
    const glm::vec3& GetAABBMin() const { return AABBMin; }
    const glm::vec3& GetAABBMax() const { return AABBMax; }
    const glm::mat4& GetTransform() const { return Transform; }

private:
    SparseVoxelTreeNode generateTree(const VoxelMap& voxelMap, int32_t scale, glm::ivec3 pos);
    uint8_t at(const SparseVoxelTreeNode& node, int32_t scale, glm::ivec3 pos, int32_t x, int32_t y, int32_t z) const;
    void fillVoxelMap(VoxelMap& voxelMap, const SparseVoxelTreeNode& node, int32_t scale, glm::ivec3 pos) const;

    uint64_t PackBits64(const uint8_t* data);
    void LeftPack(uint8_t* data, uint64_t mask);

    void printTree(const SparseVoxelTreeNode& node, int32_t scale, glm::ivec3 pos, int depth) const;

private:
    SparseVoxelTreeNode root;
    std::vector<SparseVoxelTreeNode> nodePool;
    std::vector<uint8_t> leafData;

    // AABB and Transform
    glm::vec3 AABBMin;
    glm::vec3 AABBMax;
    glm::mat4 Transform;

private:
    friend VoxelTreeMemoryAllocator;
};

// GPU Sparse Voxel Tree

struct GPUSparseVoxelTreeNode
{
    // PackedData[0]: Combines IsLeaf (1 bit) and ChildPtr (31 bits).
    // PackedData[1]: Lower 32 bits of ChildMask.
    // PackedData[2]: Upper 32 bits of ChildMask.
    // 12 bytes
    uint32_t PackedData[3];
};

struct GPUAABB
{
    // Min bounds of the AABB
    // 16 bytes
    alignas(16) glm::vec4 Min;
    // Max bounds of the AABB
    // 16 bytes
    alignas(16) glm::vec4 Max;
};

struct GPUSparseVoxelTree
{
    // Root node of the tree
    GPUSparseVoxelTreeNode Root; // 12 bytes

    // Offset into the NodePool buffer
    alignas(4) uint32_t NodePoolPtr; // 4 bytes
    // Offset into the LeafData buffer
    alignas(4) uint32_t LeafDataPtr; // 4 bytes

    // Padding for 16-byte alignment of `bounds`
    alignas(4) uint32_t _padding[3]; // 12 bytes

    // Axis-aligned bounding box of the tree
    alignas(16) GPUAABB Bounds; // 32 bytes

    // Transform matrix
    alignas(16)  glm::mat4 Transform; // 64 bytes
};