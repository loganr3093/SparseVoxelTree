#include "voxel_tree_memory_allocator.h"

VoxelTreeMemoryAllocator::VoxelTreeMemoryAllocator()
    : treeBuffer(0), nodePoolBuffer(0), leafDataBuffer(0) {}

VoxelTreeMemoryAllocator::~VoxelTreeMemoryAllocator()
{
    FreeGPUResources();
}

void VoxelTreeMemoryAllocator::Allocate(const std::vector<SparseVoxelTree>& voxelTrees)
{
    gpuTrees.clear();
    gpuNodePool.clear();
    gpuLeafData.clear();

    uint32_t nodeOffset = 0;
    uint32_t leafOffset = 0;

    for (const auto& tree : voxelTrees)
    {
        PackVoxelTree(tree, nodeOffset, leafOffset);
    }
}

void VoxelTreeMemoryAllocator::PackVoxelTree(const SparseVoxelTree& tree, uint32_t& nodeOffset, uint32_t& leafOffset)
{
    GPUSparseVoxelTree gpuTree;

    // Convert Root Node
    GPUSparseVoxelTreeNode gpuRoot;
    gpuRoot.PackedData[0] = (tree.root.IsLeaf << 31) | tree.root.ChildPtr;
    gpuRoot.PackedData[1] = static_cast<uint32_t>(tree.root.ChildMask);
    gpuRoot.PackedData[2] = static_cast<uint32_t>(tree.root.ChildMask >> 32);
    gpuTree.Root = gpuRoot;

    // Set AABB and Transform
    gpuTree.AABBMin = tree.AABBMin;
    gpuTree.AABBMax = tree.AABBMax;
    gpuTree.Transform = tree.Transform;

    // Set NodePool and LeafData pointers
    gpuTree.NodePoolPtr = nodeOffset;
    gpuTree.LeafDataPtr = leafOffset;

    // Append to GPU Trees
    gpuTrees.push_back(gpuTree);

    // Append Nodes to GPU Pool
    for (const auto& node : tree.nodePool)
    {
        GPUSparseVoxelTreeNode gpuNode;
        gpuNode.PackedData[0] = (node.IsLeaf << 31) | node.ChildPtr;
        gpuNode.PackedData[1] = static_cast<uint32_t>(node.ChildMask);
        gpuNode.PackedData[2] = static_cast<uint32_t>(node.ChildMask >> 32);
        gpuNodePool.push_back(gpuNode);
    }

    // Append Leaf Data
    gpuLeafData.insert(gpuLeafData.end(), tree.leafData.begin(), tree.leafData.end());

    // Update offsets
    nodeOffset += tree.nodePool.size();
    leafOffset += tree.leafData.size();
}

void VoxelTreeMemoryAllocator::UploadToGPU()
{
    // Upload Trees
    glGenBuffers(1, &treeBuffer);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, treeBuffer);
    glBufferData(GL_SHADER_STORAGE_BUFFER, gpuTrees.size() * sizeof(GPUSparseVoxelTree), gpuTrees.data(), GL_STATIC_DRAW);

    // Upload Node Pool
    glGenBuffers(1, &nodePoolBuffer);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, nodePoolBuffer);
    glBufferData(GL_SHADER_STORAGE_BUFFER, gpuNodePool.size() * sizeof(GPUSparseVoxelTreeNode), gpuNodePool.data(), GL_STATIC_DRAW);

    // Upload Leaf Data
    glGenBuffers(1, &leafDataBuffer);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, leafDataBuffer);
    glBufferData(GL_SHADER_STORAGE_BUFFER, gpuLeafData.size(), gpuLeafData.data(), GL_STATIC_DRAW);

    glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
}

void VoxelTreeMemoryAllocator::FreeGPUResources()
{
    if (treeBuffer) glDeleteBuffers(1, &treeBuffer);
    if (nodePoolBuffer) glDeleteBuffers(1, &nodePoolBuffer);
    if (leafDataBuffer) glDeleteBuffers(1, &leafDataBuffer);

    treeBuffer = nodePoolBuffer = leafDataBuffer = 0;
}
