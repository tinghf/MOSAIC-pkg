#!/bin/bash

# ============================================================================
# MOSAIC Container Build and Deploy Script
# ============================================================================
#
# This script automates building and deploying MOSAIC container to HPC cluster
#
# Usage:
#   bash build_and_deploy.sh                    # Interactive mode
#   bash build_and_deploy.sh build              # Build only
#   bash build_and_deploy.sh deploy CLUSTER     # Deploy only
#
# ============================================================================

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONTAINER_NAME="mosaic_latest.sif"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo ""
    echo "========================================================================"
    echo "$1"
    echo "========================================================================"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Build Container
# ============================================================================

build_container() {
    print_header "Building MOSAIC Container"

    # Check for Singularity/Apptainer
    if check_command singularity; then
        CONTAINER_CMD="singularity"
    elif check_command apptainer; then
        CONTAINER_CMD="apptainer"
    else
        print_error "Neither Singularity nor Apptainer found"
        echo "Install from: https://docs.sylabs.io/guides/latest/user-guide/"
        exit 1
    fi

    print_success "Found $CONTAINER_CMD"

    # Check if running as root or with --fakeroot
    if [ "$EUID" -ne 0 ]; then
        print_warning "Not running as root, will use --fakeroot"
        BUILD_FLAGS="--fakeroot"
    else
        BUILD_FLAGS=""
    fi

    # Build container
    cd "$REPO_ROOT/.."
    DEF_FILE="$SCRIPT_DIR/mosaic.def"

    if [ ! -f "$DEF_FILE" ]; then
        print_error "Definition file not found: $DEF_FILE"
        exit 1
    fi

    print_success "Definition file: $(basename $DEF_FILE)"
    echo "Building container (this takes 30-40 minutes)..."
    echo ""

    $CONTAINER_CMD build $BUILD_FLAGS "$CONTAINER_NAME" "$DEF_FILE"

    if [ $? -eq 0 ]; then
        print_success "Container built successfully: $CONTAINER_NAME"
        ls -lh "$CONTAINER_NAME"
    else
        print_error "Container build failed"
        exit 1
    fi

    # Test container
    echo ""
    echo "Testing container..."
    $CONTAINER_CMD exec "$CONTAINER_NAME" Rscript -e "library(MOSAIC); print('OK')"

    if [ $? -eq 0 ]; then
        print_success "Container test passed"
    else
        print_error "Container test failed"
        exit 1
    fi
}

# ============================================================================
# Deploy to Cluster
# ============================================================================

deploy_container() {
    print_header "Deploying Container to Cluster"

    # Get cluster address
    if [ -z "$1" ]; then
        echo "Enter cluster address (e.g., username@cluster.edu):"
        read CLUSTER_ADDR
    else
        CLUSTER_ADDR="$1"
    fi

    # Check if container exists locally
    if [ ! -f "$CONTAINER_NAME" ]; then
        print_error "Container not found: $CONTAINER_NAME"
        echo "Run: bash build_and_deploy.sh build"
        exit 1
    fi

    print_success "Found container: $CONTAINER_NAME ($(du -h $CONTAINER_NAME | cut -f1))"

    # Copy to cluster
    echo ""
    echo "Copying container to cluster..."
    echo "Destination: $CLUSTER_ADDR:~/containers/"
    echo ""

    ssh "$CLUSTER_ADDR" "mkdir -p ~/containers"
    scp "$CONTAINER_NAME" "$CLUSTER_ADDR:~/containers/"

    if [ $? -eq 0 ]; then
        print_success "Container deployed successfully"
    else
        print_error "Deployment failed"
        exit 1
    fi

    # Test on cluster
    echo ""
    echo "Testing container on cluster..."
    ssh "$CLUSTER_ADDR" "singularity exec ~/containers/$CONTAINER_NAME Rscript -e \"library(MOSAIC); print('OK')\""

    if [ $? -eq 0 ]; then
        print_success "Remote container test passed"
    else
        print_warning "Remote test failed (container may still work for batch jobs)"
    fi

    # Print next steps
    echo ""
    print_header "Deployment Complete"
    echo "Container location: $CLUSTER_ADDR:~/containers/$CONTAINER_NAME"
    echo ""
    echo "Next steps:"
    echo "  1. SSH to cluster: ssh $CLUSTER_ADDR"
    echo "  2. Test interactively:"
    echo "     singularity exec ~/containers/$CONTAINER_NAME R"
    echo "  3. Run MOSAIC:"
    echo "     Rscript examples/run_mosaic_container.R"
    echo ""
}

# ============================================================================
# Interactive Mode
# ============================================================================

interactive_mode() {
    print_header "MOSAIC Container Build & Deploy"

    echo "What would you like to do?"
    echo "  1) Build container locally"
    echo "  2) Deploy container to cluster"
    echo "  3) Build and deploy"
    echo "  4) Exit"
    echo ""
    read -p "Enter choice [1-4]: " choice

    case $choice in
        1)
            build_container
            ;;
        2)
            deploy_container
            ;;
        3)
            build_container
            deploy_container
            ;;
        4)
            echo "Exiting"
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
}

# ============================================================================
# Main
# ============================================================================

if [ $# -eq 0 ]; then
    # No arguments - interactive mode
    interactive_mode
elif [ "$1" = "build" ]; then
    build_container
elif [ "$1" = "deploy" ]; then
    deploy_container "$2"
elif [ "$1" = "all" ]; then
    build_container
    deploy_container "$2"
else
    echo "Usage: $0 [build|deploy|all] [cluster-address]"
    exit 1
fi

print_success "Done!"
