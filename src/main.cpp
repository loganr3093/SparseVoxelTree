#include <glad/glad.h>
#include <GLFW/glfw3.h>
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <glm/gtx/string_cast.hpp>

#include "shader.h"
#include "compute_shader.h"
#include "camera.h"
#include "texture.h"
#include "vox_parser.h"
#include "sparse_voxel_tree.h"
#include "voxel_tree_memory_allocator.h"

#include <iostream>

void framebuffer_size_callback(GLFWwindow* window, int width, int height);
void processInput(GLFWwindow *window);
void renderQuad();

// settings
constexpr int SCR_WIDTH = 960;
constexpr int SCR_HEIGHT = 540;

// texture size
const unsigned int TEXTURE_WIDTH = 960, TEXTURE_HEIGHT = 540;

const int WORKGROUP_SIZE_X = 16;
const int WORKGROUP_SIZE_Y = 16;

const int DISPATCH_X = (TEXTURE_WIDTH + WORKGROUP_SIZE_X - 1) / WORKGROUP_SIZE_X;
const int DISPATCH_Y = (TEXTURE_HEIGHT + WORKGROUP_SIZE_Y - 1) / WORKGROUP_SIZE_Y;

// camera
Camera camera(glm::vec3(0.0f, 0.0f, -5.0f), SCR_WIDTH, SCR_HEIGHT);
float lastX = SCR_WIDTH / 2.0f;
float lastY = SCR_HEIGHT / 2.0f;
bool firstMouse = true;

// timing
float deltaTime = 0.0f;
float lastFrame = 0.0f;

int main()
{
    // glfw: initialize and configure
    // ------------------------------
    glfwInit();
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 6);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    // glfw window creation
    // --------------------
    GLFWwindow* window = glfwCreateWindow(SCR_WIDTH, SCR_HEIGHT, "RayTracerGL", NULL, NULL);
    if (window == NULL)
    {
        std::cout << "Failed to create GLFW window" << std::endl;
        glfwTerminate();
        return -1;
    }
    glfwMakeContextCurrent(window);
    glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);
    glfwSwapInterval(0);

    // glad: load all OpenGL function pointers
    // ---------------------------------------
    if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress))
    {
        std::cout << "Failed to initialize GLAD" << std::endl;
        return -1;
    }

    // build and compile shaders
    // -------------------------
    Shader screenQuad("resources/shaders/default_vert.glsl", "resources/shaders/default_frag.glsl");
    ComputeShader computeShader("resources/shaders/default_compute.glsl");

    screenQuad.use();
    screenQuad.setInt("tex", 0);

    // Create texture for OpenGL operation
    // -----------------------------------
    Texture texture;
    texture.bind();
    texture.setParameters();
    texture.initializeStorage(GL_RGBA32F, TEXTURE_WIDTH, TEXTURE_HEIGHT, GL_RGBA, GL_FLOAT);
    texture.bindAsImage(0, 0, GL_FALSE, GL_READ_WRITE, GL_RGBA32F);

    // Vox stuff
    // Load a voxel model
    VoxelMap deer_voxel_map = VoxLoader::load("resources/models/deer.vox");
    VoxelMap horse_voxel_map = VoxLoader::load("resources/models/horse.vox");

    // Create a SparseVoxelTree from the voxel map
    SparseVoxelTree deer_tree(deer_voxel_map);
    SparseVoxelTree horse_tree(horse_voxel_map);

    std::vector<SparseVoxelTree> trees = { deer_tree };

    VoxelTreeMemoryAllocator allocator;
    allocator.Allocate(trees);

    // Upload data to GPU
    allocator.UploadToGPU();

    // Bind buffers to compute shader
    GLuint treeBuffer = allocator.GetTreeBuffer();
    GLuint nodePoolBuffer = allocator.GetNodePoolBuffer();
    GLuint leafDataBuffer = allocator.GetLeafDataBuffer();

    allocator.PrintMemory();

    if (allocator.CompareTree(deer_tree, 0))
    {
        std::cout << "Tree comparison successful!" << std::endl;
    }
    else
    {
        std::cout << "Tree comparison failed!" << std::endl;
    }

    // render loop
    // -----------
    int width, height;
    while (!glfwWindowShouldClose(window))
    {
        // Set frame time
        float currentFrame = glfwGetTime();
        deltaTime = currentFrame - lastFrame;
        lastFrame = currentFrame;

        // Get input
        processInput(window);

        // Use compute shader
        computeShader.use();

        // Set uniforms
        glfwGetFramebufferSize(window, &width, &height);
        glm::vec2 screenSize = glm::vec2(width, height);
        computeShader.setVec2("ScreenSize", screenSize);

        float deg2rad = 3.1415926535897931 / 180.0;
        float planeHeight = camera.NearClipPlane * tan(camera.Fov * 0.5f * deg2rad) * 2;
        float planeWidth = planeHeight * camera.Aspect;

        computeShader.setVec3("ViewParams", glm::vec3(planeWidth, planeHeight, camera.NearClipPlane));
        computeShader.setMat4("CamWorldMatrix", camera.GetCameraToWorldMatrix());

        // Bind buffers
        glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, treeBuffer);
        glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, nodePoolBuffer);
        glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, leafDataBuffer);

        // Bind texture as image
        texture.bindAsImage(0, 0, GL_FALSE, GL_READ_WRITE, GL_RGBA32F);

        // Dispatch compute shader
        glDispatchCompute((width + 15) / 16, (height + 15) / 16, 1);

        // Make sure writing to image has finished before read
        glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);

        // Render image to quad
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        screenQuad.use();
        glActiveTexture(GL_TEXTURE0);
        texture.bind();
        renderQuad();

        // glfw: swap buffers and poll IO events (keys pressed/released, mouse moved etc.)
        // -------------------------------------------------------------------------------
        glfwSwapBuffers(window);
        glfwPollEvents();
    }

    // Cleanup
    allocator.FreeGPUResources();
    glfwTerminate();

    return 0;
}

// process all input: query GLFW whether relevant keys are pressed/released this frame and react accordingly
// ---------------------------------------------------------------------------------------------------------
void processInput(GLFWwindow *window)
{
    if (glfwGetKey(window, GLFW_KEY_ESCAPE) == GLFW_PRESS)
        glfwSetWindowShouldClose(window, true);

    if (glfwGetKey(window, GLFW_KEY_W) == GLFW_PRESS)
        camera.ProcessKeyboard(FORWARD, deltaTime);
    if (glfwGetKey(window, GLFW_KEY_S) == GLFW_PRESS)
        camera.ProcessKeyboard(BACKWARD, deltaTime);

    if (glfwGetKey(window, GLFW_KEY_A) == GLFW_PRESS)
        camera.ProcessKeyboard(LEFT, deltaTime);
    if (glfwGetKey(window, GLFW_KEY_D) == GLFW_PRESS)
        camera.ProcessKeyboard(RIGHT, deltaTime);

    if (glfwGetKey(window, GLFW_KEY_SPACE) == GLFW_PRESS)
        camera.ProcessKeyboard(UP, deltaTime);
    if (glfwGetKey(window, GLFW_KEY_LEFT_SHIFT) == GLFW_PRESS)
        camera.ProcessKeyboard(DOWN, deltaTime);

    if (glfwGetKey(window, GLFW_KEY_UP) == GLFW_PRESS)
        camera.ProcessMouseMovement(0.0f, -1.0f, deltaTime);
    if (glfwGetKey(window, GLFW_KEY_DOWN) == GLFW_PRESS)
        camera.ProcessMouseMovement(0.0f, 1.0f, deltaTime);

    if (glfwGetKey(window, GLFW_KEY_LEFT) == GLFW_PRESS)
        camera.ProcessMouseMovement(1.0f, 0.0f, deltaTime);
    if (glfwGetKey(window, GLFW_KEY_RIGHT) == GLFW_PRESS)
        camera.ProcessMouseMovement(-1.0f, 0.0f, deltaTime);
}

// glfw: whenever the window size changed (by OS or user resize) this callback function executes
// ---------------------------------------------------------------------------------------------
void framebuffer_size_callback(GLFWwindow* window, int width, int height)
{
    camera.ScreenWidth = width;
    camera.ScreenHeight = height;
    camera.Aspect = width/height;
    glViewport(0, 0, width, height);
}

// renderQuad() renders a 1x1 XY quad in NDC
// -----------------------------------------
unsigned int quadVAO = 0;
unsigned int quadVBO;
void renderQuad()
{
	if (quadVAO == 0)
	{
		float quadVertices[] =
        {
			// positions  	// texture Coords
			-1.0f,  1.0f, 	0.0f, 0.0f, 1.0f,
			-1.0f, -1.0f, 	0.0f, 0.0f, 0.0f,
			 1.0f,  1.0f, 	0.0f, 1.0f, 1.0f,
			 1.0f, -1.0f, 	0.0f, 1.0f, 0.0f,
		};

		// setup plane VAO
		glGenVertexArrays(1, &quadVAO);
		glGenBuffers(1, &quadVBO);
		glBindVertexArray(quadVAO);
		glBindBuffer(GL_ARRAY_BUFFER, quadVBO);
		glBufferData(GL_ARRAY_BUFFER, sizeof(quadVertices), &quadVertices, GL_STATIC_DRAW);
		glEnableVertexAttribArray(0);
		glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)0);
		glEnableVertexAttribArray(1);
		glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)(3 * sizeof(float)));
	}

	glBindVertexArray(quadVAO);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	glBindVertexArray(0);
}