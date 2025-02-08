#ifndef TEXTURE_H
#define TEXTURE_H

#include <glad/glad.h>
#include <string>
#include <iostream>

class Texture {
public:
    unsigned int ID; // Texture ID

    // Constructor
    Texture(GLenum textureType = GL_TEXTURE_2D)
        : textureType(textureType) {
        glGenTextures(1, &ID);
    }

    // Destructor
    ~Texture() {
        glDeleteTextures(1, &ID);
    }

    // Bind the texture
    void bind(GLuint unit = 0) const {
        glActiveTexture(GL_TEXTURE0 + unit);
        glBindTexture(textureType, ID);
    }

    // Unbind the texture
    void unbind() const {
        glBindTexture(textureType, 0);
    }

    // Configure the texture parameters
    void setParameters(GLint wrapS = GL_CLAMP_TO_EDGE, GLint wrapT = GL_CLAMP_TO_EDGE, 
                       GLint minFilter = GL_LINEAR, GLint magFilter = GL_LINEAR) const {
        glTexParameteri(textureType, GL_TEXTURE_WRAP_S, wrapS);
        glTexParameteri(textureType, GL_TEXTURE_WRAP_T, wrapT);
        glTexParameteri(textureType, GL_TEXTURE_MIN_FILTER, minFilter);
        glTexParameteri(textureType, GL_TEXTURE_MAG_FILTER, magFilter);
    }

    // Initialize the texture storage
    void initializeStorage(GLint internalFormat, GLsizei width, GLsizei height, 
                           GLenum format, GLenum type, const void* data = nullptr) const {
        glTexImage2D(textureType, 0, internalFormat, width, height, 0, format, type, data);
    }

    // Bind as image texture for compute shaders
    void bindAsImage(GLuint unit, GLint level, GLboolean layered, GLenum access, GLenum format) const {
        glBindImageTexture(unit, ID, level, layered, 0, access, format);
    }

private:
    GLenum textureType; // Texture type (default GL_TEXTURE_2D)
};

#endif // TEXTURE_H
