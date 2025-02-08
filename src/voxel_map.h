#pragma once

#include <vector>
#include <cstdint>
#include <string>

struct VoxelMap
{
    std::vector<uint8_t> voxels;
    uint32_t size_x;
    uint32_t size_y;
    uint32_t size_z;
};

void PrintVoxelMap(const VoxelMap& voxelMap, const std::string& name);
void CompareVoxelMaps(const VoxelMap& original, const VoxelMap& reconstructed);
