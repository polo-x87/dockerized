# example-project overlay

Reference `.devcontainer/` you can copy into any of your repos. It extends `devbox-base` with one or two project-specific tools (here: `postgresql-client`, `redis-tools`) and declares the VS Code / Cursor extensions that should auto-install inside the container.

## Use it

1. Build the base image once: `cd ../../base && docker compose build`.
2. Copy `.devcontainer/` into your project's repo root.
3. In Cursor: `Cmd+Shift+P → Dev Containers: Reopen in Container`.

Cursor's UI runs on your Mac; language servers, terminals, and AI agent calls run inside the container.
