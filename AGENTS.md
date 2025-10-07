# Repository Guidelines

## Project Structure & Module Organization
- `start.sh` orchestrates container startup: it validates GPU access, hydrates `models_config.json`, and launches the log viewer on port 8189.
- Python sources live in `utils/`, `workers/`, `constants/`, and `dto/` for log formatting, download orchestration, and DTOs.
- Web assets supporting the log dashboard are under `templates/` and `static/`.
- Docker assets (`Dockerfile`, `build_and_run.sh`, `deploy.sh`) define how ComfyUI ships; `models_config*.json` files drive downloads.

## Build, Test, and Development Commands
- `./build_and_run.sh` builds `tonycerq/comfyui:latest` and runs it with the ports expected by ComfyUI (`8188`, `8189`, `8888`, `18822`).
- `./start.sh` is the entrypoint inside the container; run it to initialize env vars (`MODELS_CONFIG_URL`, `SKIP_MODEL_DOWNLOAD`, `LOG_PATH`) and spawn services.
- `python download_models.py` (from the container workspace) reads `models_config.json` and fetches missing checkpoint assets via `aria2c`.
- `./deploy.sh <dockerhub-user> <tag>` rebuilds the image from `Dockerfile` and pushes both the versioned tag and `latest`.

## Coding Style & Naming Conventions
- Python adheres to PEP 8: four-space indentation, snake_case modules (`download_models.py`) and CamelCase data classes; keep structured logging with `logger.info(...)`.
- Shell scripts are bash with `set -e`; prefer functions for reuse (`check_gpu`, `install_uv`) and document required env vars with inline comments.
- JSON manifests stay lowercase with underscores for keys and are checked into the repo for reproducible environments.

## Testing Guidelines
- There is no dedicated automated suite yet; rely on container smoke tests. After changes, run `./build_and_run.sh` locally and confirm ComfyUI loads on `http://localhost:8188`.
- Validate model provisioning by running `python download_models.py` and inspecting `/workspace/logs/comfyui.log` or `tail -f LOG_PATH`.
- When adding Python logic, favor lightweight `pytest` modules in a future `tests/` directory; mirror filenames (`utils/test_getInstalledModels.py`) to keep imports simple.

## Commit & Pull Request Guidelines
- Recent history uses emoji-prefixed lowercase summaries (`🚧 wip: ... [skip ci]`). Follow that format with a clear scope (`✨ feat: add log filtering`) and optional CI hints.
- Keep commits focused and document any new env vars or ports.
- Pull requests should link tracking issues, describe functional validation steps (e.g., build output, ComfyUI screenshot), and call out required model downloads or manual setup.

## Configuration & Security Tips
- Default env vars live in `start.sh`; override via RunPod template or `docker run -e KEY=VALUE` and mirror changes in documentation.
- Avoid committing model binaries or secrets; use `MODELS_CONFIG_URL` to point to private manifests when needed.
