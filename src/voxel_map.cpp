#include "voxel_map.h"
#include <iostream>
#include <fstream>

void PrintVoxelMap(const VoxelMap& voxelMap, const std::string& name)
{
    std::ofstream file(name + ".txt");
    if (!file.is_open()) {
        std::cerr << "Error: Unable to open file " << name << ".txt for writing." << std::endl;
        return;
    }

    file << "Voxel Map: " << name << " (Size: " << voxelMap.size_x << "x" << voxelMap.size_y << "x" << voxelMap.size_z << ")\n";
    for (uint32_t z = 0; z < voxelMap.size_z; ++z)
    {
        file << "Z = " << z << ":\n";
        for (uint32_t y = 0; y < voxelMap.size_y; ++y)
        {
            for (uint32_t x = 0; x < voxelMap.size_x; ++x)
            {
                int32_t index = x + y * voxelMap.size_x + z * voxelMap.size_x * voxelMap.size_y;
                file << static_cast<int>(voxelMap.voxels[index]) << " ";
            }
            file << "\n";
        }
        file << "\n";
    }
    file.close();
}

void CompareVoxelMaps(const VoxelMap& original, const VoxelMap& reconstructed)
{
    uint32_t discrepancyCount = 0;

    for (uint32_t z = 0; z < original.size_z; ++z)
    {
        for (uint32_t y = 0; y < original.size_y; ++y)
        {
            for (uint32_t x = 0; x < original.size_x; ++x)
            {
                int32_t index = x + y * original.size_x + z * original.size_x * original.size_y;
                if (original.voxels[index] != reconstructed.voxels[index])
                {
                    std::cout << "Discrepancy at (" << x << ", " << y << ", " << z << "): "
                              << "Original = " << static_cast<int>(original.voxels[index]) << ", "
                              << "Reconstructed = " << static_cast<int>(reconstructed.voxels[index]) << "\n";
                    discrepancyCount++;
                }
            }
        }
    }

    std::cout << "Total discrepancies: " << discrepancyCount << "\n";
}
