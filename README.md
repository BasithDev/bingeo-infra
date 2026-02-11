# Bingeo Infrastructure

Infrastructure repository for the Bingeo OTT Platform.

## Quick Start

```bash
# Initialize submodules (first time only)
make submodules-init

# Run a single service
make identity

# Run full stack
make full

# Run full stack with observability
make full-obs
```

## Available Commands

```bash
make help
```

## Structure

```
├── services/          # Git submodules to service repos
├── client/            # Git submodule to client repo
├── k8s/               # K8s manifests (gateway, base)
├── observability/     # Prometheus, Loki, Tempo, Grafana
└── terraform/         # AWS resources
```
