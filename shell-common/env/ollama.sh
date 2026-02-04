#!/bin/sh
# shell-common/env/ollama.sh
# Ollama environment configuration
# Recommended settings for Ollama runtime and dotfiles integration

# Runtime Configuration (recommended defaults)
# These can be overridden by setting them before sourcing this file
: "${OLLAMA_NUM_CTX:=65536}"           # 64K context length
: "${OLLAMA_NUM_GPU:=-1}"              # GPU auto-detect (-1 = all GPUs)
: "${OLLAMA_KEEP_ALIVE:=5m}"           # Memory efficiency (cache models for 5 min)

# Dotfiles-specific Configuration
# Backend selection: auto (default) | local (WSL) | docker (container)
: "${DOTFILES_OLLAMA_BACKEND:=auto}"

# Docker container name (if using Docker backend)
: "${DOTFILES_OLLAMA_DOCKER_CONTAINER:=ollama}"

# Export variables
export OLLAMA_NUM_CTX
export OLLAMA_NUM_GPU
export OLLAMA_KEEP_ALIVE
export DOTFILES_OLLAMA_BACKEND
export DOTFILES_OLLAMA_DOCKER_CONTAINER
