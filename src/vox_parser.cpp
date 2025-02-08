#include "vox_parser.h"

#include <fstream>

#define OGT_VOX_IMPLEMENTATION
#include "ogt/vox.h"

VoxelMap VoxLoader::load(const char* file_path)
{
        std::ifstream file(file_path, std::ios::binary | std::ios::ate);
        if (!file)
        {
            throw std::runtime_error("Failed to open file.");
        }

        std::streamsize size = file.tellg();
        file.seekg(0, std::ios::beg);

        std::vector<char> buffer(size);
        if (!file.read(buffer.data(), size))
        {
            throw std::runtime_error("Failed to read file.");
        }

        const ogt_vox_scene* scene = ogt_vox_read_scene(reinterpret_cast<uint8_t*>(buffer.data()), buffer.size());
        if (!scene)
        {
            throw std::runtime_error("Failed to parse .vox file.");
        }

        const ogt_vox_model* model = scene->models[0];
        VoxelMap voxel_map;
        voxel_map.size_x = model->size_x;
        voxel_map.size_y = model->size_y;
        voxel_map.size_z = model->size_z;
        voxel_map.voxels.resize(voxel_map.size_x * voxel_map.size_y * voxel_map.size_z);

        std::copy(model->voxel_data, model->voxel_data + voxel_map.voxels.size(), voxel_map.voxels.begin());

        ogt_vox_destroy_scene(scene);
        return voxel_map;
    }