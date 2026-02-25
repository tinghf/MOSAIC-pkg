#!/bin/bash
# ==============================================================================
# Build and Push MOSAIC Container to Azure Container Registry
# ==============================================================================
# Prerequisites:
#   - Docker installed and running
#   - Azure CLI installed (az login)
#   - Container registry created
#
# Usage:
#   bash build-and-push.sh [registry-name] [version-tag]
#
# ==============================================================================

set -e

REGISTRY_NAME="${1:-mosaicidm}"
VERSION_TAG="${2:-latest}"
IMAGE_NAME="mosaic"
FULL_TAG="${REGISTRY_NAME}.azurecr.io/${IMAGE_NAME}:${VERSION_TAG}"

echo "======================================"
echo "MOSAIC Container Build & Push"
echo "======================================"
echo "Registry: ${REGISTRY_NAME}.azurecr.io"
echo "Image: $IMAGE_NAME"
echo "Tag: $VERSION_TAG"
echo "Full tag: $FULL_TAG"
echo ""

# Navigate to repo root
cd "$(dirname "$0")/../.."

# Build container
echo "[1/4] Building Docker image..."
docker build \
  -t "$FULL_TAG" \
  -f azure/container/Dockerfile \
  --progress=plain \
  .

echo ""
echo "Build complete! Image size:"
docker images "$FULL_TAG" --format "{{.Size}}"

# Login to Azure Container Registry
echo ""
echo "[2/4] Logging into Azure Container Registry..."
az acr login --name "$REGISTRY_NAME"

# Tag with additional tags
echo ""
echo "[3/4] Creating additional tags..."
# Tag with Git commit SHA if available
if git rev-parse --git-dir > /dev/null 2>&1; then
  GIT_SHA=$(git rev-parse --short HEAD)
  docker tag "$FULL_TAG" "${REGISTRY_NAME}.azurecr.io/${IMAGE_NAME}:${GIT_SHA}"
  echo "Tagged with Git SHA: $GIT_SHA"
fi

# Tag with MOSAIC version from DESCRIPTION
if [ -f "DESCRIPTION" ]; then
  MOSAIC_VERSION=$(grep "^Version:" DESCRIPTION | awk '{print $2}')
  docker tag "$FULL_TAG" "${REGISTRY_NAME}.azurecr.io/${IMAGE_NAME}:v${MOSAIC_VERSION}"
  echo "Tagged with MOSAIC version: v${MOSAIC_VERSION}"
fi

# Push to registry
echo ""
echo "[4/4] Pushing image to Azure Container Registry..."
docker push "$FULL_TAG"

# Push additional tags
if [ -n "$GIT_SHA" ]; then
  docker push "${REGISTRY_NAME}.azurecr.io/${IMAGE_NAME}:${GIT_SHA}"
fi

if [ -n "$MOSAIC_VERSION" ]; then
  docker push "${REGISTRY_NAME}.azurecr.io/${IMAGE_NAME}:v${MOSAIC_VERSION}"
fi

echo ""
echo "======================================"
echo "Push complete!"
echo "======================================"
echo ""
echo "Available tags:"
az acr repository show-tags \
  --name "$REGISTRY_NAME" \
  --repository "$IMAGE_NAME" \
  --output table

echo ""
echo "Test locally:"
echo "  docker run --rm -e ISO_CODE=SOM ${FULL_TAG}"
echo ""
echo "Deploy to Azure Container Instances:"
echo "  az container create \\"
echo "    --resource-group mosaic-rg \\"
echo "    --name mosaic-som-run \\"
echo "    --image ${FULL_TAG} \\"
echo "    --cpu 120 --memory 456 \\"
echo "    --registry-login-server ${REGISTRY_NAME}.azurecr.io \\"
echo "    --registry-username <username> \\"
echo "    --registry-password <password>"
echo ""
