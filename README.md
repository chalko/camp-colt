# Camp Colt

Camp Colt is a local multi-agent development environment for [Suitcase AI](https://showmetheinference.com). It runs on local hardware to coordinate autonomous agents for software engineering, system maintenance, and benchmarking.

## Architecture

- **Inference Host (`colt-gpu-01`):** ASUS Ascent GX10 with an NVIDIA Grace Blackwell GB10 accelerator (128GB unified memory), running local models via containerized engines (`vLLM` / `Atlas Spark`).
- **Controller (`colt-hq`):** Runs [Gas City](https://github.com/gastownhall/gascity) with [Dolt](https://github.com/dolthub/dolt) to track tasks as version-controlled database records ("beads") and coordinate agents through asynchronous messaging (`gc mail`).
- **Roles:** Work is divided across functional roles:
  - `colt-cos`: Coordination and review.
  - `mayor`: Workspace plumbing and runtime configuration.
  - `s3-operations`: Task scheduling and dispatch.
  - `s6-signal`: Communications watch, message priority routing, and test verification.
  - `colt-sysadmin`: Platform maintenance and deployment.

## Repository Layout

```text
camp-colt/
├── AGENTS.md                  # Operational rules and role definitions
├── city.toml                  # Gas City topology and model provider endpoints
├── pack.toml / packs.lock     # Pack dependencies
├── LICENSE                    # Apache 2.0
├── agents/                    # Role definitions and agent prompts
├── commands/                  # Helper scripts and commands
├── docs/                      # Technical notes and architecture runbooks
├── orders/                    # Scheduled recurring jobs
└── scripts/                   # System maintenance scripts
```

## Documentation

- [`AGENTS.md`](AGENTS.md) — Operational guidelines and role definitions.
- [`docs/LOCAL_MODELS.md`](docs/LOCAL_MODELS.md) — Local model deployment notes.
- [`docs/LITELLM_GATEWAY_ARCHITECTURE.md`](docs/LITELLM_GATEWAY_ARCHITECTURE.md) — Gateway configuration.

## License

Copyright © 2026 Nick Chalko / Suitcase AI.
Licensed under the [Apache License, Version 2.0](LICENSE).
