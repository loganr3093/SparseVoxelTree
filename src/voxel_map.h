#pragma once

#include <vector>
#include <cstdint>
#include <string>

// Include ogt/vox.h to get definitions for ogt_vox_rgba and ogt_vox_matl.
#include "ogt/vox.h"

struct VoxelMap
{
    std::vector<uint8_t> voxels;
    uint32_t size_x;
    uint32_t size_y;
    uint32_t size_z;

    // Extended material information for each palette index (usually 256 entries).
    std::vector<ogt_vox_matl> material_map;

    // The color palette: 256 colors (ogt_vox_rgba) that MagicaVoxel uses.
    std::vector<ogt_vox_rgba> palette;

    // Helper methods to get individual material properties by palette index.
    float getMetal(uint8_t index) const;
    float getRough(uint8_t index) const;
    float getSpec(uint8_t index) const;
    float getIOR(uint8_t index) const;
};

void PrintVoxelMap(const VoxelMap& voxelMap, const std::string& name);
void CompareVoxelMaps(const VoxelMap& original, const VoxelMap& reconstructed);
