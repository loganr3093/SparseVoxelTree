#pragma once

#include "sparse_voxel_tree.h"
#include <bitset>
#include <vector>
#include <unordered_map>
#include <glad/glad.h>

class VoxelTreeMemoryAllocator
{
public:
    VoxelTreeMemoryAllocator();
    ~VoxelTreeMemoryAllocator();

    // Allocates GPU buffers for a collection of SparseVoxelTrees
    void Allocate(const std::vector<SparseVoxelTree>& voxelTrees);

    // Uploads data to OpenGL buffers
    void UploadToGPU();

    // Cleans up OpenGL buffers
    void FreeGPUResources();

    // Get OpenGL buffer handles
    GLuint GetTreeBuffer() const { return treeBuffer; }
    GLuint GetNodePoolBuffer() const { return nodePoolBuffer; }
    GLuint GetLeafDataBuffer() const { return leafDataBuffer; }

    // Get Data
    const std::vector<GPUSparseVoxelTree> GetTreeBufferData() const { return gpuTrees; }
    const std::vector<GPUSparseVoxelTreeNode> GetNodePoolBufferData() const { return gpuNodePool; }
    const std::vector<uint8_t> GetLeafDataBufferData() const { return gpuLeafData; }

    void PrintStats()
    {
        std::cout << "GPU Sparse Voxel Trees: " << gpuTrees.size() * sizeof(GPUSparseVoxelTree) << std::endl;
        std::cout << "GPU Node Pool: " << gpuNodePool.size() * sizeof(GPUSparseVoxelTreeNode) << std::endl;
        std::cout << "GPU Leaf Data: " << gpuLeafData.size() * sizeof(uint8_t) << std::endl;
    }

    void PrintMemory() const
    {
        std::cout << "===== Voxel Tree Memory Allocation =====" << std::endl;

        std::cout << "\nGPU Sparse Voxel Trees (" << gpuTrees.size() << " entries):" << std::endl;
        for (size_t i = 0; i < gpuTrees.size(); ++i)
        {
            const auto& tree = gpuTrees[i];
            std::cout << "Tree " << i << ":\n";
            std::cout << "  NodePoolPtr: " << tree.NodePoolPtr << "\n";
            std::cout << "  LeafDataPtr: " << tree.LeafDataPtr << "\n";
            std::cout << "  AABBMin: (" << tree.AABBMin.x << ", " << tree.AABBMin.y << ", " << tree.AABBMin.z << ")\n";
            std::cout << "  AABBMax: (" << tree.AABBMax.x << ", " << tree.AABBMax.y << ", " << tree.AABBMax.z << ")\n";
        }

        std::cout << "\nGPU Node Pool (" << gpuNodePool.size() << " entries):" << std::endl;
        for (size_t i = 0; i < gpuNodePool.size(); ++i)
        {
            const auto& node = gpuNodePool[i];
            std::cout << "Node " << i << ": ";
            std::cout << "PackedData[0]: " << std::bitset<32>(node.PackedData[0]) << " ";
            std::cout << "PackedData[1]: " << std::bitset<32>(node.PackedData[1]) << " ";
            std::cout << "PackedData[2]: " << std::bitset<32>(node.PackedData[2]) << std::endl;
        }

        std::cout << "\nGPU Leaf Data (" << gpuLeafData.size() << " bytes):" << std::endl;
        for (size_t i = 0; i < gpuLeafData.size(); ++i)
        {
            if (i % 16 == 0) std::cout << "\n" << i << ": ";
            std::cout << static_cast<int>(gpuLeafData[i]) << " ";
        }
        std::cout << "\n======================================\n";
    }

    bool CompareTree(const SparseVoxelTree& tree, size_t index) const
    {
        if (index >= gpuTrees.size()) return false;

        const auto& gpuTree = gpuTrees[index];

        if (gpuTree.AABBMin != tree.GetAABBMin() || gpuTree.AABBMax != tree.GetAABBMax() || gpuTree.Transform != tree.GetTransform())
            return false;

        if (gpuTree.NodePoolPtr >= gpuNodePool.size() || gpuTree.LeafDataPtr >= gpuLeafData.size())
            return false;

        for (size_t i = 0; i < tree.nodePool.size(); ++i)
        {
            if (i >= gpuNodePool.size()) return false;

            const auto& gpuNode = gpuNodePool[gpuTree.NodePoolPtr + i];
            const auto& treeNode = tree.nodePool[i];

            uint32_t packedData0 = (treeNode.IsLeaf << 31) | treeNode.ChildPtr;
            uint32_t packedData1 = static_cast<uint32_t>(treeNode.ChildMask);
            uint32_t packedData2 = static_cast<uint32_t>(treeNode.ChildMask >> 32);

            if (gpuNode.PackedData[0] != packedData0 || gpuNode.PackedData[1] != packedData1 || gpuNode.PackedData[2] != packedData2)
                return false;
        }

        for (size_t i = 0; i < tree.leafData.size(); ++i)
        {
            if (gpuTree.LeafDataPtr + i >= gpuLeafData.size() || gpuLeafData[gpuTree.LeafDataPtr + i] != tree.leafData[i])
                return false;
        }

        return true;
    }

private:
    GLuint treeBuffer;      // GPU buffer for GPUSparseVoxelTrees
    GLuint nodePoolBuffer;  // GPU buffer for node pools
    GLuint leafDataBuffer;  // GPU buffer for leaf data

    std::vector<GPUSparseVoxelTree> gpuTrees;
    std::vector<GPUSparseVoxelTreeNode> gpuNodePool;
    std::vector<uint8_t> gpuLeafData;

    void PackVoxelTree(const SparseVoxelTree& tree, uint32_t& nodeOffset, uint32_t& leafOffset);
};