# deepclaude overlay — extends devbox-base with claude-code-router (ccr).
# ccr reroutes Claude Code through a free OpenRouter backend. No keys baked in;
# OPENROUTER_API_KEY is supplied at runtime via `op run --env-file=...`.

FROM devbox-base:latest

USER dev

# Install claude-code-router globally. Node + npm are already in devbox-base.
RUN npm install -g @musistudio/claude-code-router

# Pre-seed the ccr config (key is a 1Password reference, not a real value).
COPY --chown=dev:dev config.json /home/dev/.claude-code-router/config.json

# Port 3456 is the ccr proxy. forwardPorts in devcontainer.json exposes it to host.
EXPOSE 3456
