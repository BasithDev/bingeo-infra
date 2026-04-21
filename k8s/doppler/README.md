# Doppler Secrets Integration

This directory contains DopplerSecret custom resources for syncing secrets from Doppler to Kubernetes.

## How It Works

1. **Doppler Operator** (installed in `doppler-operator-system` namespace) watches for `DopplerSecret` resources
2. Each `DopplerSecret` references:
   - A Kubernetes secret containing your Doppler Service Token
   - A Doppler project and config (dev/stg/prd)
   - A target Kubernetes secret to create/manage
3. The operator continuously syncs secrets from Doppler to the managed Kubernetes secret
4. Deployments using the managed secret can auto-reload when secrets change

## Setup Steps

### 1. Install Doppler Operator (done during `make setup`)

```bash
helm repo add doppler https://helm.doppler.com
helm upgrade --install doppler-operator doppler/doppler-kubernetes-operator \
  -n doppler-operator-system \
  --create-namespace
```

### 2. Create Doppler Service Token

1. Go to [Doppler Dashboard](https://dashboard.doppler.com)
2. Navigate to your workplace → Service Tokens
3. Create a token with access to your projects
4. Run the interactive setup:

```bash
make doppler-setup
# Select option 1) Setup Doppler Service Token
```

### 3. Create DopplerSecrets for Services

Option A: Use the interactive tool:
```bash
make doppler-setup
# Select option 2) Create DopplerSecret for a service
```

Option B: Apply templates directly:
```bash
# Edit the template first to set correct project names
kubectl apply -f k8s/doppler/templates/dopplersecret-identity.yaml
kubectl apply -f k8s/doppler/templates/dopplersecret-payment.yaml
kubectl apply -f k8s/doppler/templates/dopplersecret-content.yaml
kubectl apply -f k8s/doppler/templates/dopplersecret-streaming.yaml
```

### 4. Verify Sync

```bash
make doppler-status
# or
kubectl get secrets -n bingeo-app | grep secrets
kubectl get dopplersecrets -n doppler-operator-system
```

## Using Secrets in Deployments

### Method 1: envFrom (Recommended)

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: my-service
          envFrom:
            - secretRef:
                name: identity-service-secrets  # Managed by Doppler
```

### Method 2: valueFrom (Specific secrets)

```yaml
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: identity-service-secrets
        key: DATABASE_URL
```

### Method 3: Auto-reload on secret change

Add this annotation to enable automatic pod restart when secrets change:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    secrets.doppler.com/reload: 'true'
spec:
  template:
    spec:
      containers:
        - name: my-service
          envFrom:
            - secretRef:
                name: identity-service-secrets
```

## Project Structure in Doppler

Recommended Doppler project naming:

```
Workplace: Bingeo
├── Projects:
│   ├── bingeo-identity    (Identity Service secrets)
│   ├── bingeo-payment     (Payment Service secrets)
│   ├── bingeo-content     (Content Service secrets)
│   └── bingeo-streaming   (Streaming Service secrets)
│
└── Configs per project:
    ├── dev   (Development)
    ├── stg   (Staging)
    └── prd   (Production)
```

## Troubleshooting

### Secrets not syncing

1. Check Doppler operator logs:
   ```bash
   kubectl logs -n doppler-operator-system deployment/doppler-operator-controller-manager
   ```

2. Verify DopplerSecret status:
   ```bash
   kubectl get dopplersecrets -n doppler-operator-system -o yaml
   ```

3. Check if token is valid:
   ```bash
   # Test with Doppler CLI
   doppler configs get --project bingeo-identity --config dev
   ```

### Managed secret not updating

- Secrets sync every 60 seconds by default
- Check that the DopplerSecret `spec.managedSecret` namespace exists
- Verify the service token has access to the specified project and config

## Security Best Practices

1. **Service Token Scope**: Create separate service tokens per environment (dev/stg/prd) with minimal project access
2. **Namespace Isolation**: Managed secrets are namespaced; keep them in `bingeo-app`
3. **RBAC**: Restrict who can create DopplerSecrets and read managed secrets
4. **Rotation**: Rotate Doppler service tokens regularly; the operator will use the new token automatically
5. **Audit**: Monitor operator logs for unauthorized access attempts

## References

- [Doppler Kubernetes Operator Docs](https://docs.doppler.com/docs/kubernetes-operator)
- [Doppler CLI](https://docs.doppler.com/docs/cli)
