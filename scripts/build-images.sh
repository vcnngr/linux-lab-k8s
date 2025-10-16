#!/bin/bash

# Script per build e push delle immagini Docker
# Da usare SOLO se vuoi ricompilare le immagini personalizzate
# Gestisce tag multipli per versioning completo

set -e

# ========================================
# CONFIGURAZIONE
# ========================================

REGISTRY="${REGISTRY:-docker.io/vcnngr}"
IMAGE_BASE_NAME="${IMAGE_BASE_NAME:-linux-lab-k8s}"
SUDO_MODE="${SUDO_MODE:-limited}"

# Versione progetto (semantic versioning)
PROJECT_VERSION="${PROJECT_VERSION:-1.0.0}"

# Data build (per tag temporali)
BUILD_DATE=$(date +%Y%m%d)
BUILD_DATETIME=$(date +%Y%m%d-%H%M%S)

# ========================================
# DEFINIZIONE TAG PER DISTRO
# ========================================

# Ubuntu 24.04 LTS (Noble Numbat)
declare -a UBUNTU_TAGS=(
    "latest"
    "ubuntu"
    "ubuntu-latest"
    "ubuntu-24.04"
    "ubuntu-noble"
    "noble"
    "ubuntu-${PROJECT_VERSION}"
    "ubuntu-24.04-${BUILD_DATE}"
    "ubuntu-24.04-${PROJECT_VERSION}"
)

# Debian 13 (Trixie)
declare -a DEBIAN_TAGS=(
    "latest"
    "debian"
    "debian-latest"
    "debian-13"
    "debian-trixie"
    "trixie"
    "debian-${PROJECT_VERSION}"
    "debian-13-${BUILD_DATE}"
    "debian-13-${PROJECT_VERSION}"
)

# Rocky Linux 10
declare -a ROCKY_TAGS=(
    "latest"
    "rocky"
    "rocky-latest"
    "rocky-10"
    "rocky-10.0"
    "rocky-${PROJECT_VERSION}"
    "rocky-10-${BUILD_DATE}"
    "rocky-10-${PROJECT_VERSION}"
    "rocky-10.0-${BUILD_DATE}"
)

# ========================================
# COLORI
# ========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ========================================
# FUNZIONI
# ========================================

print_header() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo -e "  $1"
    echo -e "==========================================${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[ℹ]${NC} $1"
}

# ========================================
# GET TAGS PER DISTRO
# ========================================

get_tags_for_distro() {
    local distro=$1
    
    case "$distro" in
        ubuntu)
            echo "${UBUNTU_TAGS[@]}"
            ;;
        debian)
            echo "${DEBIAN_TAGS[@]}"
            ;;
        rocky)
            echo "${ROCKY_TAGS[@]}"
            ;;
        *)
            echo ""
            ;;
    esac
}

# ========================================
# BUILD SINGOLA IMMAGINE CON TAG MULTIPLI
# ========================================

build_image() {
    local distro=$1
    local dockerfile="docker/Dockerfile-${distro}"
    local primary_image="${REGISTRY}/${IMAGE_BASE_NAME}-${distro}:latest"
    
    if [ ! -f "$dockerfile" ]; then
        print_error "Dockerfile not found: $dockerfile"
        return 1
    fi
    
    print_info "Building $distro image..."
    print_info "Dockerfile: $dockerfile"
    echo ""
    
    # Build con tag primario
    if ! docker build -f "$dockerfile" \
                    -t "$primary_image" \
                    --build-arg SUDO_MODE="$SUDO_MODE" \
                    --build-arg BUILD_DATE="$BUILD_DATE" \
                    docker/; then
        print_error "Build failed for $distro"
        return 1
    fi
    
    print_step "Image built: $primary_image"
    
    # Aggiungi tag multipli
    local tags=($(get_tags_for_distro "$distro"))
    
    print_info "Tagging with ${#tags[@]} additional tags..."
    
    for tag in "${tags[@]}"; do
        if [ "$tag" != "latest" ]; then  # latest già fatto nel build
            local full_tag="${REGISTRY}/${IMAGE_BASE_NAME}-${distro}:${tag}"
            docker tag "$primary_image" "$full_tag"
            echo "  • $full_tag"
        fi
    done
    
    print_step "Tagging completed for $distro"
    return 0
}

# ========================================
# PUSH SINGOLA IMMAGINE CON TUTTI I TAG
# ========================================

push_image() {
    local distro=$1
    local tags=($(get_tags_for_distro "$distro"))
    
    # Aggiungi "latest" se non presente
    if [[ ! " ${tags[@]} " =~ " latest " ]]; then
        tags+=("latest")
    fi
    
    print_info "Pushing $distro image with ${#tags[@]} tags..."
    echo ""
    
    local success=0
    local failed=0
    
    for tag in "${tags[@]}"; do
        local full_tag="${REGISTRY}/${IMAGE_BASE_NAME}-${distro}:${tag}"
        
        echo -n "  Pushing ${tag}... "
        
        if docker push "$full_tag" &> /dev/null; then
            echo -e "${GREEN}✓${NC}"
            ((success++))
        else
            echo -e "${RED}✗${NC}"
            ((failed++))
        fi
    done
    
    echo ""
    if [ $failed -eq 0 ]; then
        print_step "All tags pushed successfully for $distro ($success/$((success+failed)))"
        return 0
    else
        print_warning "Some tags failed for $distro ($success/$((success+failed)) succeeded)"
        return 1
    fi
}

# ========================================
# BUILD TUTTE LE IMMAGINI
# ========================================

build_all() {
    print_header "BUILDING ALL IMAGES"
    
    local success=0
    local failed=0
    
    for distro in ubuntu debian rocky; do
        echo -e "${CYAN}═══════════════════════════════${NC}"
        echo -e "${CYAN}Building ${distro}...${NC}"
        echo -e "${CYAN}═══════════════════════════════${NC}"
        echo ""
        
        if build_image "$distro"; then
            ((success++))
        else
            ((failed++))
        fi
        echo ""
    done
    
    echo ""
    print_info "Build summary: ${success} succeeded, ${failed} failed"
    
    if [ $failed -gt 0 ]; then
        return 1
    fi
    return 0
}

# ========================================
# PUSH TUTTE LE IMMAGINI
# ========================================

push_all() {
    print_header "PUSHING ALL IMAGES"
    
    local success=0
    local failed=0
    
    for distro in ubuntu debian rocky; do
        echo -e "${CYAN}═══════════════════════════════${NC}"
        echo -e "${CYAN}Pushing ${distro}...${NC}"
        echo -e "${CYAN}═══════════════════════════════${NC}"
        echo ""
        
        if push_image "$distro"; then
            ((success++))
        else
            ((failed++))
        fi
        echo ""
    done
    
    echo ""
    print_info "Push summary: ${success} succeeded, ${failed} failed"
    
    if [ $failed -gt 0 ]; then
        return 1
    fi
    return 0
}

# ========================================
# LIST TAGS
# ========================================

list_tags() {
    local distro=${1:-all}
    
    print_header "IMAGE TAGS"
    
    if [ "$distro" = "all" ]; then
        for d in ubuntu debian rocky; do
            list_tags_for_distro "$d"
            echo ""
        done
    else
        list_tags_for_distro "$distro"
    fi
}

list_tags_for_distro() {
    local distro=$1
    local tags=($(get_tags_for_distro "$distro"))
    
    echo -e "${CYAN}${distro^^}:${NC}"
    for tag in "${tags[@]}"; do
        echo "  ${REGISTRY}/${IMAGE_BASE_NAME}-${distro}:${tag}"
    done
}

# ========================================
# HELP
# ========================================

show_help() {
    cat << EOF
${BLUE}Linux Lab K8s - Image Builder${NC}

Usage: $0 [COMMAND] [DISTRO]

Commands:
  build <distro>    Build image for specific distro (ubuntu|debian|rocky)
  build-all         Build all images
  push <distro>     Push image for specific distro with all tags
  push-all          Push all images with all tags
  build-and-push    Build and push all images
  list-tags [dist]  List all tags that will be created
  help              Show this help

Environment Variables:
  REGISTRY          Docker registry (default: docker.io/vcnngr)
  IMAGE_BASE_NAME   Base image name (default: linux-lab-k8s)
  PROJECT_VERSION   Project version (default: 1.0.0)
  SUDO_MODE         Sudo mode: strict|limited|full (default: limited)

Examples:
  # Build only Ubuntu image with all tags
  $0 build ubuntu

  # Build all images
  $0 build-all

  # List all tags that will be created
  $0 list-tags

  # Build and push all to custom registry with version
  export REGISTRY="myregistry.io/myuser"
  export PROJECT_VERSION="2.1.0"
  $0 build-and-push

  # Push only Debian with all tags
  $0 push debian

Tag Strategy:
  Each image gets multiple tags for flexibility:
  
  Ubuntu 24.04:
    - latest, ubuntu, ubuntu-latest
    - ubuntu-24.04, ubuntu-noble, noble
    - ubuntu-${PROJECT_VERSION}
    - ubuntu-24.04-${BUILD_DATE}
    - ubuntu-24.04-${PROJECT_VERSION}
  
  Debian 13:
    - latest, debian, debian-latest
    - debian-13, debian-trixie, trixie
    - debian-${PROJECT_VERSION}
    - debian-13-${BUILD_DATE}
    - debian-13-${PROJECT_VERSION}
  
  Rocky 9:
    - latest, rocky, rocky-latest
    - rocky-9, rocky-9.5
    - rocky-${PROJECT_VERSION}
    - rocky-9-${BUILD_DATE}
    - rocky-9-${PROJECT_VERSION}
    - rocky-9.5-${BUILD_DATE}

Current Configuration:
  Registry: ${REGISTRY}
  Base name: ${IMAGE_BASE_NAME}
  Project version: ${PROJECT_VERSION}
  Build date: ${BUILD_DATE}
  Sudo mode: ${SUDO_MODE}

EOF
}

# ========================================
# CHECKS
# ========================================

check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker not found. Please install Docker first."
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker daemon not running or no permissions."
        exit 1
    fi
}

check_dockerfile() {
    local distro=$1
    local dockerfile="docker/Dockerfile-${distro}"
    
    if [ ! -f "$dockerfile" ]; then
        print_error "Dockerfile not found: $dockerfile"
        exit 1
    fi
}

check_registry_login() {
    print_info "Checking registry authentication..."
    
    # Estrai hostname dal registry
    local registry_host=$(echo "$REGISTRY" | cut -d'/' -f1)
    
    # Test push di un'immagine vuota (non fa nulla, solo verifica auth)
    if docker info 2>&1 | grep -q "Username:"; then
        print_step "Authenticated to registry"
    else
        print_warning "Not authenticated to registry. You may need to run:"
        echo "  docker login ${registry_host}"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
}

# ========================================
# MAIN
# ========================================

main() {
    local command=${1:-help}
    local distro=${2:-}
    
    print_header "LINUX LAB K8S - IMAGE BUILDER"
    
    echo -e "${CYAN}Configuration:${NC}"
    echo "  Registry: $REGISTRY"
    echo "  Base name: $IMAGE_BASE_NAME"
    echo "  Project version: $PROJECT_VERSION"
    echo "  Build date: $BUILD_DATE"
    echo "  Sudo mode: $SUDO_MODE"
    echo ""
    
    check_docker
    
    case "$command" in
        build)
            if [ -z "$distro" ]; then
                print_error "Please specify distro: ubuntu, debian, or rocky"
                echo "Usage: $0 build <distro>"
                exit 1
            fi
            
            if [[ ! "$distro" =~ ^(ubuntu|debian|rocky)$ ]]; then
                print_error "Invalid distro. Choose: ubuntu, debian, rocky"
                exit 1
            fi
            
            check_dockerfile "$distro"
            build_image "$distro"
            
            echo ""
            print_info "Tags created:"
            list_tags_for_distro "$distro"
            ;;
            
        build-all)
            build_all
            
            echo ""
            print_info "All tags created. Run with 'list-tags' to see them."
            ;;
            
        push)
            if [ -z "$distro" ]; then
                print_error "Please specify distro: ubuntu, debian, or rocky"
                echo "Usage: $0 push <distro>"
                exit 1
            fi
            
            if [[ ! "$distro" =~ ^(ubuntu|debian|rocky)$ ]]; then
                print_error "Invalid distro. Choose: ubuntu, debian, rocky"
                exit 1
            fi
            
            check_registry_login
            push_image "$distro"
            ;;
            
        push-all)
            check_registry_login
            push_all
            ;;
            
        build-and-push)
            if build_all; then
                check_registry_login
                push_all
            else
                print_error "Build failed, skipping push"
                exit 1
            fi
            ;;
        
        list-tags)
            list_tags "$distro"
            ;;
            
        help|--help|-h)
            show_help
            ;;
            
        *)
            print_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
    
    echo ""
    print_step "Done!"
}

# Run
main "$@"
