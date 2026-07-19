# OSAC UI

OSAC UI is the web console for the [Open Sovereign AI Cloud (OSAC)](https://github.com/osac-project/) project — a self-service platform for deploying OpenShift clusters, virtual machines, and bare metal hosts. It is a pnpm monorepo consisting of a React 19 + PatternFly 6 single-page application and a Go chi reverse proxy that handles OIDC authentication and forwards requests to the upstream [fulfillment-service](https://github.com/osac-project/fulfillment-service).

## Repository layout

| Path | Purpose |
|------|---------|
| `apps/app-frontend/` | React SPA (Vite, React 19, TanStack Query, react-router-dom 7) |
| `libs/api-contracts/` | Shared TypeScript types and wire normalizers |
| `libs/types/` | Generated protobuf types (do not edit) |
| `libs/ui-components/` | Shared PatternFly 6 component library |
| `proxy/` | Go chi reverse proxy — OIDC auth + API forwarding |
| `deploy/chart/` | Helm chart for Kubernetes/OpenShift deployment |
| `scripts/` | Developer helper scripts |
| `docs/` | Architecture and deployment documentation |

## Quick start

Prerequisites: Node.js 20+, pnpm 9+, Go 1.23+

```bash
pnpm install
```

Start the Go proxy (requires a running fulfillment API) and Vite dev server:

```bash
FULFILLMENT_API_URL=https://fulfillment.your-env.example.com pnpm dev
```

## Local development with Keycloak (dev mode)

When running the UI locally with `pnpm dev`, OIDC login will fail unless the Keycloak `osac-ui` client is configured to accept `localhost` redirect URIs. Run the following script against your target cluster to add the necessary redirect URIs:

```bash
export KUBECONFIG=~/envs/<your-env>/kubeconfig
./scripts/enable-local-ui-redirect-uri.sh --namespace <osac-namespace>
```

The script auto-detects the Keycloak route and patches the `osac-ui` client to allow `http://localhost:5173` and `http://127.0.0.1:5173` callbacks. It tries `admin/admin` credentials first, then falls back to the `keycloak-initial-admin` Kubernetes secret. You can also pass credentials explicitly:

```bash
./scripts/enable-local-ui-redirect-uri.sh --namespace osac-devel \
  --keycloak-username admin --keycloak-password <password>
```

Use `--dry-run` to preview changes or `--verify-only` to check if the redirect URIs are already configured. Run `./scripts/enable-local-ui-redirect-uri.sh --help` for all options.

## Documentation

| Document | Description |
|----------|-------------|
| [OpenShift deployment guide](docs/deployment-openshift-guide.md) | Step-by-step guide for deploying on OpenShift with Keycloak and fulfillment-service |
| [API query architecture](docs/api-query-arch.md) | How the API layer is split between `ui-components` and the app |
| [AGENTS.md](AGENTS.md) | Dev environment setup, scripts reference, and coding conventions |
