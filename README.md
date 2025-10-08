# ComfyUI RunPod Template

## Custom ComfyUI Nodes
Add or update custom nodes by specifying their repositories in the following format:
```
"https://github.com/<author>/<repo>.git|<folder_name>"
```
Example nodes:
- "https://github.com/ltdrdata/ComfyUI-Manager.git|ComfyUI-Manager"
- "https://github.com/cubiq/ComfyUI_essentials.git|ComfyUI_essentials"
- "https://github.com/kijai/ComfyUI-KJNodes.git|ComfyUI-KJNodes"
- "https://github.com/city96/ComfyUI-GGUF.git|ComfyUI-GGUF"
- "https://github.com/rgthree/rgthree-comfy.git|rgthree-comfy"
- "https://github.com/justUmen/Bjornulf_custom_nodes.git|Bjornulf_custom_nodes"
- "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git|ComfyUI-Custom-Scripts"
- "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git|ComfyUI-Frame-Interpolation"

## Dashboard
- The FastAPI dashboard (`web/dashboard.py`) serves UI templates from `web/templates/` and static assets from `web/static/`.
- Start the container with `start.sh` to launch ComfyUI on port `8188` and the dashboard on port `8189`.
- The dashboard provides live log viewing, model management, and download utilities via `/api/*` endpoints.

## Quick Start
1. Build and run the container:  
    ```bash
    ./build_and_run.sh
    ```
2. Access ComfyUI at [http://localhost:8188](http://localhost:8188) and the dashboard at [http://localhost:8189](http://localhost:8189).
3. Hydrate models by running:
    ```bash
    python download_models.py
    ```
    from the `/notebooks` directory, using `models_config.json`.

## Deploy
Publish the container image to Docker Hub:
```bash
./deploy.sh <dockerhub-user> <tag>
```
This rebuilds the image and pushes both `<tag>` and `latest`.
