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
    uint32_t PackedData[3];
};

struct GPUSparseVoxelTree
{
    // Root node of the tree
    GPUSparseVoxelTreeNode Root;
    // Offset into the NodePool buffer
    uint32_t NodePoolPtr;
    // Offset into the LeafData buffer
    uint32_t LeafDataPtr;

    // Lower bounds
    glm::vec3 AABBMin;
    // Upper bounds
    glm::vec3 AABBMax;
    // Transform matrix
    glm::mat4 Transform;
};