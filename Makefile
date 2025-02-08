# Compiler
CXX = g++

# Compiler flags
CXXFLAGS = -Wall

# Directories
INCLUDE_DIR = include
SRC_DIR = src
BUILD_DIR = build
LIB_DIR = lib
RESOURCES_DIR = resources

# Source files
SRCS := $(wildcard $(SRC_DIR)/**/*.cpp) $(wildcard $(SRC_DIR)/*.cpp) $(wildcard $(INCLUDE_DIR)/imgui/*.cpp) $(INCLUDE_DIR)/glad/glad.c
OBJS := $(patsubst $(SRC_DIR)/%.cpp, $(BUILD_DIR)/%.o, $(SRCS))

# Extract directories from object file list
BUILD_DIRS := $(sort $(dir $(OBJS)))

# Executable name
RAYTRACE_EXEC = raytrace.exe

# Libraries
LIBS = -lglfw3dll

# Include directories
INC_DIRS = -I$(INCLUDE_DIR)

# Targets
.PHONY: all clean rebuild remake debug optimized br

# Default target
all: $(BUILD_DIRS) $(RAYTRACE_EXEC)

# Linking executable
$(RAYTRACE_EXEC): $(OBJS)
	$(CXX) $(CXXFLAGS) $(OBJS) -o $@ -L$(LIB_DIR) $(LIBS)

# Compiling object files
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.cpp | $(BUILD_DIRS)
	$(CXX) $(CXXFLAGS) $(INC_DIRS) -c $< -o $@

# Create object directories
$(BUILD_DIRS):
	mkdir -p $@

# Clean target
clean:
	rm -rf $(BUILD_DIR) $(RAYTRACE_EXEC)

# Rebuild target
rebuild: clean all

# Remake target
remake: clean all

# Debugging target
debug: CXXFLAGS += -g
debug: rebuild

# Optimization target
optimized: CXXFLAGS += -O2
optimized: rebuild

# Build and run target
br: all
	$(RAYTRACE_EXEC)
