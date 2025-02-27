#include "vox_parser.h"
#include <fstream>
#include <stdexcept>

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

    // Assume we're only interested in the first model.
    const ogt_vox_model* model = scene->models[0];
    VoxelMap voxel_map;
    voxel_map.size_x = model->size_x;
    voxel_map.size_y = model->size_y;
    voxel_map.size_z = model->size_z;
    voxel_map.voxels.resize(voxel_map.size_x * voxel_map.size_y * voxel_map.size_z);
    std::copy(model->voxel_data, model->voxel_data + voxel_map.voxels.size(), voxel_map.voxels.begin());

    // Initialize the material map.
    // The ogt_vox_scene contains a 'materials' member of type ogt_vox_matl_array.
    voxel_map.material_map.resize(256);
    for (uint32_t i = 0; i < 256; ++i)
    {
        voxel_map.material_map[i] = scene->materials.matl[i];
    }

    // Initialize the color palette.
    // The ogt_vox_scene has a palette member of type ogt_vox_palette.
    voxel_map.palette.resize(256);
    for (uint32_t i = 0; i < 256; ++i)
    {
        voxel_map.palette[i] = scene->palette.color[i];
    }

    ogt_vox_destroy_scene(scene);
    return voxel_map;
}
