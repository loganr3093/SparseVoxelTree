#ifndef PROFILER_H
#define PROFILER_H

#include <imgui/imgui.h>
#include <imgui/imgui_impl_glfw.h>
#include <imgui/imgui_impl_opengl3.h>

#include <GLFW/glfw3.h>

#include "camera.h"

#include <string>

class Profiler
{
public:
    Profiler(GLFWwindow* window)
    {
        init(window);
    }

    void new_frame()
    {
        ImGui_ImplOpenGL3_NewFrame();
		ImGui_ImplGlfw_NewFrame();
		ImGui::NewFrame();
    }

    void make_window(float deltaTime, Camera camera)
    {
        ImGui::Begin("Profiler");
		std::string fps = "FPS: " + std::to_string(static_cast<int>(1 / deltaTime));
		ImGui::Text(fps.c_str());
        std::string camPos = "Camera Position: "
                            + std::to_string(camera.Position.x)
                            + "," + std::to_string(camera.Position.y)
                            + "," + std::to_string(camera.Position.z);
		ImGui::Text(camPos.c_str());
        std::string camRot = "Camera Rotation: "
                            + std::to_string(static_cast<int>(camera.Pitch))
                            + "," + std::to_string(static_cast<int>(camera.Yaw));
		ImGui::Text(camRot.c_str());
		ImGui::End();
    }

    void render()
    {
        ImGui::Render();
		ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
    }

    void shutdown()
    {
        ImGui_ImplOpenGL3_Shutdown();
	    ImGui_ImplGlfw_Shutdown();
    }

private:
    void init(GLFWwindow* window)
    {
        IMGUI_CHECKVERSION();
        ImGui::CreateContext();
        ImGuiIO& io = ImGui::GetIO(); (void)io;
        ImGui::StyleColorsDark();
        ImGui_ImplGlfw_InitForOpenGL(window, true);
        ImGui_ImplOpenGL3_Init("#version 460");
    }
};

#endif