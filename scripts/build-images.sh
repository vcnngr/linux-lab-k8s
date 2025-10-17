#!/usr/bin/env bash

# Script per build e push delle immagini Docker
# Con supporto autenticazione via token

set -e

# ========================================
# CONFIGURAZIONE
# ========================================

REGISTRY="${REGISTRY:-docker.io/vcnngr}"
IMAGE_BASE_NAME="${IMAGE_BASE_NAME:-linux-lab-k8s}"
SUDO_MODE="${SUDO_MODE:-limited}"

# AUTENTICAZIONE
DOCKER_USERNAME="${DOCKER_USERNAME:-}"
DOCKER_TOKEN="${DOCKER_TOKEN:-}"

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
# GET TAGS PER DISTRO - FIX #1: USA NAMEREF
# ========================================

get_tags_for_distro() {
    local distro=$1
    local -n tags_ref=$2  # CORREZIONE: nameref invece di echo
    
    case "$distro" in
        ubuntu)
            tags_ref=("${UBUNTU_TAGS[@]}")
            ;;
        debian)
            tags_ref=("${DEBIAN_TAGS[@]}")
            ;;
        rocky)
            tags_ref=("${ROCKY_TAGS[@]}")
            ;;
        *)
            tags_ref=()
            ;;
    esac
}

# ========================================
# AUTENTICAZIONE DOCKER
# ========================================

docker_login() {
    local registry_host=$(echo "$REGISTRY" | cut -d'/' -f1)
    
    print_info "Authenticating to registry: ${registry_host}"
    
    # Se token fornito, usa quello
    if [ -n "$DOCKER_TOKEN" ] && [ -n "$DOCKER_USERNAME" ]; then
        print_info "Using provided credentials..."
        
        if echo "$DOCKER_TOKEN" | docker login "$registry_host" -u "$DOCKER_USERNAME" --password-stdin 2>/dev/null; then
            print_step "Successfully authenticated with token"
            return 0
        else
            print_error "Authentication failed with provided credentials"
            return 1
        fi
    fi
    
    # Altrimenti verifica se già loggato
    if verify_registry_access "$registry_host"; then
        print_step "Already authenticated to ${registry_host}"
        return 0
    fi
    
    # Chiedi login interattivo
    print_warning "Not authenticated. Please login:"
    if docker login "$registry_host"; then
        print_step "Authentication successful"
        return 0
    else
        print_error "Authentication failed"
        return 1
    fi
}

# ========================================
# VERIFICA ACCESSO AL REGISTRY
# ========================================

verify_registry_access() {
    local registry_host=$1
    
    print_info "Verifying access to ${registry_host}..."
    
    # Controlla le credenziali salvate
    local config_file="${HOME}/.docker/config.json"
    if [ -f "$config_file" ]; then
        if grep -q "\"${registry_host}\"" "$config_file" 2>/dev/null; then
            return 0
        fi
    fi
    
    return 1
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
    
    # Build con il context corretto (docker/ perché contiene tutti i file necessari)
    if ! docker build -f "$dockerfile" \
                    -t "$primary_image" \
                    --build-arg SUDO_MODE="$SUDO_MODE" \
                    --build-arg BUILD_DATE="$BUILD_DATE" \
                    docker/; then
        print_error "Build failed for $distro"
        return 1
    fi
    
    print_step "Image built: $primary_image"
    
    # Aggiungi tag multipli - USA NAMEREF
    local -a tags
    get_tags_for_distro "$distro" tags
    
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
    local -a tags
    get_tags_for_distro "$distro" tags
    
    print_info "Pushing $distro image with ${#tags[@]} tags..."
    echo ""
    
    local success=0
    local failed=0
    
    for tag in "${tags[@]}"; do
        local full_tag="${REGISTRY}/${IMAGE_BASE_NAME}-${distro}:${tag}"
        
        echo -n "  Pushing ${tag}... "
        
        # Prova a fare il push
        local push_output
        local push_exit_code
        
        push_output=$(docker push "$full_tag" 2>&1)
        push_exit_code=$?
        
        if echo "$push_output" | grep -q "denied\|unauthorized"; then
            echo -e "${RED}✗${NC} (authentication failed)"
            ((failed++))
            print_error "Push failed due to authentication. Please check credentials."
            print_error "Error: $push_output"
            return 1
        elif [ $push_exit_code -eq 0 ]; then
            echo -e "${GREEN}✓${NC}"
            ((success++))
        else
            echo -e "${RED}✗${NC}"
            ((failed++))
            print_warning "Push error: $push_output"
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
    local -a failed_distros
    
    for distro in ubuntu debian rocky; do
        echo -e "${CYAN}═══════════════════════════════${NC}"
        echo -e "${CYAN}Pushing ${distro}...${NC}"
        echo -e "${CYAN}═══════════════════════════════${NC}"
        echo ""
        
        # Force flush
        sync
        sleep 1
        
        if push_image "$distro"; then
            ((success++))
            print_step "${distro} push completed successfully"
        else
            ((failed++))
            failed_distros+=("$distro")
            print_error "${distro} push FAILED - continuing with next distro"
        fi
        
        echo ""
        echo "DEBUG: Finished pushing $distro (success=$success, failed=$failed)"
        echo ""
    done
    
    echo ""
    echo -e "${BLUE}=========================================="
    echo -e "  PUSH SUMMARY"
    echo -e "==========================================${NC}"
    echo -e "Success: ${GREEN}${success}${NC}"
    echo -e "Failed:  ${RED}${failed}${NC}"
    
    if [ ${#failed_distros[@]} -gt 0 ]; then
        echo ""
        print_error "Failed distributions:"
        for distro in "${failed_distros[@]}"; do
            echo "  • $distro"
        done
    fi
    echo ""
    
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
    local -a tags
    get_tags_for_distro "$distro" tags
    local distro_upper=$(echo "$distro" | tr '[:lower:]' '[:upper:]')
    
    echo -e "${CYAN}${distro_upper}:${NC}"
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
  login             Login to Docker registry
  help              Show this help

Environment Variables:
  REGISTRY          Docker registry (default: docker.io/vcnngr)
  IMAGE_BASE_NAME   Base image name (default: linux-lab-k8s)
  PROJECT_VERSION   Project version (default: 1.0.0)
  SUDO_MODE         Sudo mode: strict|limited|full (default: limited)
  DOCKER_USERNAME   Docker Hub username (for automatic login)
  DOCKER_TOKEN      Docker Hub access token (for automatic login)

Examples:
  # Login interactively
  $0 login

  # Login with token (secure method)
  export DOCKER_USERNAME="your-username"
  export DOCKER_TOKEN="your-access-token"
  $0 push-all

  # Build only Ubuntu image with all tags
  $0 build ubuntu

  # Build all images
  $0 build-all

  # Build and push with custom configuration
  export REGISTRY="myregistry.io/myuser"
  export PROJECT_VERSION="2.1.0"
  export DOCKER_USERNAME="myuser"
  export DOCKER_TOKEN="dckr_pat_xxxxx"
  $0 build-and-push

Security Notes:
  - Never hardcode tokens in scripts
  - Use environment variables or secret management
  - Docker tokens can be created at: https://hub.docker.com/settings/security
  - Tokens are safer than passwords (can be revoked individually)

Current Configuration:
  Registry: ${REGISTRY}
  Base name: ${IMAGE_BASE_NAME}
  Project version: ${PROJECT_VERSION}
  Build date: ${BUILD_DATE}
  Sudo mode: ${SUDO_MODE}
  Username: ${DOCKER_USERNAME:-<not set>}
  Token: ${DOCKER_TOKEN:+<set>}${DOCKER_TOKEN:-<not set>}

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
    if [ -n "$DOCKER_USERNAME" ]; then
        echo "  Username: $DOCKER_USERNAME"
        echo "  Token: ${DOCKER_TOKEN:+***configured***}"
    fi
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
            
        login)
            docker_login
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
            
            if ! docker_login; then
                print_error "Authentication required before push"
                exit 1
            fi
            
            push_image "$distro"
            ;;
            
        push-all)
            if ! docker_login; then
                print_error "Authentication required before push"
                exit 1
            fi
            
            # IMPORTANTE: Non uscire, esegui la funzione push_all che gestisce il loop
            if push_all; then
                echo ""
                print_step "All images pushed successfully!"
                exit 0
            else
                exit 1
            fi
            ;;
            
        build-and-push)
            if build_all; then
                if ! docker_login; then
                    print_error "Authentication required before push"
                    exit 1
                fi
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
