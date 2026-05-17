# MCP Workflow: Docker Optimization for Research System

## Goal
Containerize the Python-based Research Routine with a focus on minimal image size, data persistence, and high portability.

## 1. Optimized Dockerfile (Multi-Stage)
This setup uses a `builder` stage to install dependencies and a `runner` stage to keep the final image clean.

```dockerfile
# --- Stage 1: Builder ---
FROM python:3.11-slim as builder

WORKDIR /app

# Environment setup
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Install build-time system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends gcc python3-dev

# Install Python dependencies
COPY research_system/requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# --- Stage 2: Runner ---
FROM python:3.11-slim as runner

WORKDIR /app

# Copy installed packages and application code
COPY --from=builder /root/.local /root/.local
COPY research_system/ .

# Ensure binary path is updated
ENV PATH=/root/.local/bin:$PATH

# Persistent data volume for SQLite
VOLUME ["/app/data"]

# Default start command (Master Controller)
CMD ["python", "master.py"]
```

## 2. Portability with Docker Compose
Ensures all components (Master, Agents, Volume) start with one command.

```yaml
version: '3.8'
services:
  master:
    build: .
    image: research-system:latest
    container_name: research_master
    volumes:
      - ./research_data:/app/data
    env_file:
      - .g_env
    restart: always

  agent-1:
    image: research-system:latest
    container_name: research_agent_1
    command: python agent.py 1
    volumes:
      - ./research_data:/app/data
    env_file:
      - .g_env
    depends_on:
      - master

  agent-2:
    image: research-system:latest
    container_name: research_agent_2
    command: python agent.py 2
    volumes:
      - ./research_data:/app/data
    env_file:
      - .g_env
    depends_on:
      - master
```

## 3. Pre-Deployment Optimization Tips
- **.dockerignore**: Crucial for small size. 
  - Add: `venv/`, `.git`, `*.db`, `*.log`, `__pycache__/`, `.g_env`.
- **Database Path**: Update `controller.py` and `check_results.py` to use `/app/data/master_source.db` when running in Docker.
- **Portability**: The `research_data` folder on the host will contain the SQLite DB, allowing you to move the entire project folder to any machine with Docker installed and resume immediately.

## 4. Execution Commands
```bash
# Build the image
docker compose build

# Start the entire system in background
docker compose up -d

# View logs
docker compose logs -f
```
