#!/bin/bash

# --- Configuration ---
REPO_NAME="comfyui" 
DOCKERFILE_PATH="./Dockerfile"

# Check for required arguments
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Missing arguments."
    echo "Usage: $0 <your-dockerhub-username> <tag-version>"
    echo "Example: $0 tonycerq v3.7.0-dev-tools"
    exit 1
fi

USERNAME=$1
TAG_VERSION=$2
FULL_IMAGE_NAME="${USERNAME}/${REPO_NAME}:${TAG_VERSION}"
LATEST_IMAGE_NAME="${USERNAME}/${REPO_NAME}:latest"

# --- 1. Docker Login Check ---
if ! docker info | grep "Username:" > /dev/null; then
    echo "--- LOG IN TO DOCKER HUB ---"
    echo "Please log in to Docker Hub now."
    docker login
    if [ $? -ne 0 ]; then
        echo "Docker login failed. Exiting."
        exit 1
    fi
fi

# --- 2. Build the Image ---
echo ""
echo "--- 1/3: BUILDING IMAGE: ${FULL_IMAGE_NAME} ---"
# Building with no-cache is often good practice for development images
docker build -t "${FULL_IMAGE_NAME}" -f "${DOCKERFILE_PATH}" .

if [ $? -ne 0 ]; then
    echo "Docker build failed. Exiting."
    exit 1
fi

# --- 3. Tag as Latest ---
echo ""
echo "--- 2/3: TAGGING IMAGE: ${LATEST_IMAGE_NAME} ---"
docker tag "${FULL_IMAGE_NAME}" "${LATEST_IMAGE_NAME}"

# --- 4. Push to Docker Hub ---
echo ""
echo "--- 3/3: PUSHING IMAGES TO DOCKER HUB ---"
# Push the specific version tag
docker push "${FULL_IMAGE_NAME}"

# Push the latest tag
docker push "${LATEST_IMAGE_NAME}"

echo ""
echo "--- SUCCESS! ---"
echo "Image successfully built and pushed to Docker Hub:"
echo "- ${FULL_IMAGE_NAME}"
echo "- ${LATEST_IMAGE_NAME}"
echo ""

# Cleanup local images after successful push to save disk space
# Uncomment the following lines if you want to automatically remove the local images:
echo "Cleaning up local images..."
docker rmi "${FULL_IMAGE_NAME}"
docker rmi "${LATEST_IMAGE_NAME}"

exit 0
