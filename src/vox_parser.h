#pragma once

#include "voxel_map.h"

class VoxLoader
{
public:
    static VoxelMap load(const char* file_path);
};
