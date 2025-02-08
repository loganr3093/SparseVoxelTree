#include "sparse_voxel_tree.h"
#include <fstream>

inline int popcount64(uint64_t x)
{
    x = x - ((x >> 1) & 0x5555555555555555);
    x = (x & 0x3333333333333333) + ((x >> 2) & 0x3333333333333333);
    x = (x + (x >> 4)) & 0x0F0F0F0F0F0F0F0F;
    x = x + (x >> 8);
    x = x + (x >> 16);
    x = x + (x >> 32);
    return x & 0x7F;
}

SparseVoxelTree::SparseVoxelTree(const VoxelMap& voxelMap)
{
    // Initialize AABB to cover the entire voxel map
    AABBMin = glm::vec3(0.0f, 0.0f, 0.0f);
    AABBMax = glm::vec3(voxelMap.size_x, voxelMap.size_y, voxelMap.size_z);

    // Initialize transform to identity
    Transform = glm::mat4(1.0f);

    // Generate the tree
    GenerateTree(voxelMap);
}

void SparseVoxelTree::GenerateTree(const VoxelMap& voxelMap)
{
    // Clear existing data
    nodePool.clear();
    leafData.clear();

    // Start generating the tree from the root
    root = generateTree(voxelMap, 6, glm::ivec3(0, 0, 0));
}

// Function to count the total number of voxels in the tree
size_t SparseVoxelTree::GetTotalVoxels() const
{
    return leafData.size();
}

// Function to get the voxel data at a specific coordinate
uint8_t SparseVoxelTree::At(int32_t x, int32_t y, int32_t z) const
{
    return at(root, 6, glm::ivec3(0, 0, 0), x, y, z);
}

VoxelMap SparseVoxelTree::ToVoxelMap() const
{
    VoxelMap voxelMap;
    voxelMap.size_x = 64; // Replace with the actual size if known
    voxelMap.size_y = 64; // Replace with the actual size if known
    voxelMap.size_z = 64; // Replace with the actual size if known
    voxelMap.voxels.resize(voxelMap.size_x * voxelMap.size_y * voxelMap.size_z, 0);

    fillVoxelMap(voxelMap, root, 6, glm::ivec3(0, 0, 0));
    return voxelMap;
}

void SparseVoxelTree::PrintTree() const
{
    printTree(root, 6, glm::ivec3(0, 0, 0), 0);
}

SparseVoxelTreeNode SparseVoxelTree::generateTree(const VoxelMap& voxelMap, int32_t scale, glm::ivec3 pos)
{
    SparseVoxelTreeNode node = {};

    // Create leaf
    if (scale == 2)
    {
        assert((pos.x | pos.y | pos.z) % 4 == 0);

        // Repack voxels into 4x4x4 tile
        alignas(64) uint8_t temp[64] = { 0 };

        for (int32_t i = 0; i < 64; ++i)
        {
            int32_t x = pos.x + (i & 3);
            int32_t y = pos.y + ((i >> 2) & 3);
            int32_t z = pos.z + ((i >> 4) & 3);

            if (static_cast<uint32_t>(x) < voxelMap.size_x &&
                static_cast<uint32_t>(y) < voxelMap.size_y &&
                static_cast<uint32_t>(z) < voxelMap.size_z)
            {
                int32_t index = x + y * voxelMap.size_x + z * voxelMap.size_x * voxelMap.size_y;
                temp[i] = voxelMap.voxels[index];
            }
        }

        node.IsLeaf = 1;
        node.ChildMask = PackBits64(temp); // Generate bitmask of `temp[i] != 0`.

        LeftPack(temp, node.ChildMask); // "Remove" entries where respective mask bit is zero.
        node.ChildPtr = leafData.size();
        leafData.insert(leafData.end(), temp, temp + popcount64(node.ChildMask));

        return node;
    }

    // Descend
    scale -= 2;

    std::vector<SparseVoxelTreeNode> children;

    for (int32_t i = 0; i < 64; ++i)
    {
        glm::ivec3 childPos = glm::ivec3((i & 3), ((i >> 2) & 3), ((i >> 4) & 3));
        SparseVoxelTreeNode child = generateTree(voxelMap, scale, pos + (childPos << scale));

        if (child.ChildMask != 0)
        {
            node.ChildMask |= 1ull << i;
            children.push_back(child);
        }
    }

    node.ChildPtr = nodePool.size();
    nodePool.insert(nodePool.end(), children.begin(), children.end());

    return node;
}

uint64_t SparseVoxelTree::PackBits64(const uint8_t* data)
{
    uint64_t mask = 0;
    for (int i = 0; i < 64; ++i)
    {
        if (data[i] != 0)
        {
            mask |= 1ull << i;
        }
    }
    return mask;
}

void SparseVoxelTree::LeftPack(uint8_t* data, uint64_t mask)
{
    int writeIndex = 0;
    for (int i = 0; i < 64; ++i)
    {
        if (mask & (1ull << i))
        {
            data[writeIndex++] = data[i];
        }
    }
}

uint8_t SparseVoxelTree::at(const SparseVoxelTreeNode& node, int32_t scale, glm::ivec3 pos, int32_t x, int32_t y, int32_t z) const
{
    if (node.IsLeaf)
    {
        // Calculate the index within the 4x4x4 block
        int32_t localX = x - pos.x;
        int32_t localY = y - pos.y;
        int32_t localZ = z - pos.z;
        int32_t index = localX + localY * 4 + localZ * 16;

        // Check if the voxel exists
        if (node.ChildMask & (1ull << index))
        {
            // Calculate the index in the leafData array
            int32_t dataIndex = node.ChildPtr + popcount64(node.ChildMask & ((1ull << index) - 1));
            return leafData[dataIndex];
        }
        else
        {
            return 0;
        }
    }
    else
    {
        // Calculate the child index
        int32_t childIndex = ((x - pos.x) >> (scale - 2)) + ((y - pos.y) >> (scale - 2)) * 4 + ((z - pos.z) >> (scale - 2)) * 16;

        // Check if the child exists
        if (node.ChildMask & (1ull << childIndex))
        {
            // Calculate the index in the nodePool array
            int32_t childPtr = node.ChildPtr + popcount64(node.ChildMask & ((1ull << childIndex) - 1));
            return at(nodePool[childPtr], scale - 2, pos + glm::ivec3((childIndex & 3) << (scale - 2), ((childIndex >> 2) & 3) << (scale - 2), ((childIndex >> 4) & 3) << (scale - 2)), x, y, z);
        }
        else
        {
            return 0;
        }
    }
}

void SparseVoxelTree::fillVoxelMap(VoxelMap& voxelMap, const SparseVoxelTreeNode& node, int32_t scale, glm::ivec3 pos) const
{
    if (node.IsLeaf)
    {
        for (int32_t i = 0; i < 64; ++i)
        {
            if (node.ChildMask & (1ull << i))
            {
                int32_t localX = i & 3;          // x within the 4x4x4 block
                int32_t localY = (i >> 2) & 3;   // y within the 4x4x4 block
                int32_t localZ = (i >> 4) & 3;   // z within the 4x4x4 block
                int32_t x = pos.x + localX;      // global x
                int32_t y = pos.y + localY;      // global y
                int32_t z = pos.z + localZ;      // global z

                if (static_cast<uint32_t>(x) < voxelMap.size_x &&
                    static_cast<uint32_t>(y) < voxelMap.size_y &&
                    static_cast<uint32_t>(z) < voxelMap.size_z)
                {
                    int32_t index = x + y * voxelMap.size_x + z * voxelMap.size_x * voxelMap.size_y;
                    int32_t dataIndex = node.ChildPtr + popcount64(node.ChildMask & ((1ull << i) - 1));
                    voxelMap.voxels[index] = leafData[dataIndex];
                }
            }
        }
    }
    else
    {
        scale -= 2;
        for (int32_t i = 0; i < 64; ++i)
        {
            if (node.ChildMask & (1ull << i))
            {
                int32_t childPtr = node.ChildPtr + popcount64(node.ChildMask & ((1ull << i) - 1));
                glm::ivec3 childPos = pos + glm::ivec3((i & 3) << scale, ((i >> 2) & 3) << scale, ((i >> 4) & 3) << scale);
                fillVoxelMap(voxelMap, nodePool[childPtr], scale, childPos);
            }
        }
    }
}

void SparseVoxelTree::printTree(const SparseVoxelTreeNode& node, int32_t scale, glm::ivec3 pos, int depth) const
{
    // Print indentation based on depth
    for (int i = 0; i < depth; ++i)
    {
        std::cout << "  ";
    }

    // Print node information
    std::cout << "Node at depth " << depth << ", position (" << pos.x << ", " << pos.y << ", " << pos.z << "): ";
    std::cout << "IsLeaf: " << node.IsLeaf << ", ChildMask: ";

    // Print the child mask as a binary number
    for (int i = 63; i >= 0; --i)
    {
        std::cout << ((node.ChildMask >> i) & 1);
        if (i % 8 == 0) std::cout << " "; // Add a space every 8 bits for readability
    }

    if (node.IsLeaf)
    {
        std::cout << ", Voxel Data: ";
        for (int i = 0; i < 64; ++i)
        {
            if (node.ChildMask & (1ull << i))
            {
                int32_t dataIndex = node.ChildPtr + popcount64(node.ChildMask & ((1ull << i) - 1));
                std::cout << static_cast<int>(leafData[dataIndex]) << " ";
            }
        }
    }
    std::cout << std::endl;

    // If not a leaf, recursively print children
    if (!node.IsLeaf)
    {
        scale -= 2;
        for (int32_t i = 0; i < 64; ++i)
        {
            if (node.ChildMask & (1ull << i))
            {
                int32_t childPtr = node.ChildPtr + popcount64(node.ChildMask & ((1ull << i) - 1));
                glm::ivec3 childPos = pos + glm::ivec3((i & 3) << scale, ((i >> 2) & 3) << scale, ((i >> 4) & 3) << scale);
                printTree(nodePool[childPtr], scale, childPos, depth + 1);
            }
        }
    }
}