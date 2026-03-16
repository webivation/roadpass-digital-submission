# Deploying An Application

This directory contains a templated Helm chart that deploys an **nginx** server with an
Ingress resource, along with a GitHub Actions workflow that uses GitHub's OpenID Connect
(OIDC) provider to authenticate with AWS and deploy the chart to a staging EKS cluster.

---

## Directory Layout

```
deploying-an-application/
├── README.md                          ← this file
└── helm/
    └── nginx-app/
        ├── Chart.yaml                 ← chart metadata
        ├── values.yaml                ← default values (also used as the values file)
        └── templates/
            ├── _helpers.tpl           ← shared template helpers
            ├── deployment.yaml        ← nginx Deployment
            ├── service.yaml           ← ClusterIP Service
            ├── ingress.yaml           ← Ingress (NGINX or AWS Load Balancer Controller)
            ├── serviceaccount.yaml    ← ServiceAccount
            └── hpa.yaml               ← HorizontalPodAutoscaler (disabled by default)

.github/
└── workflows/
    └── deploy-staging.yml             ← GitHub Actions OIDC deploy workflow
```

---

## Helm Chart

### Key Features

| Feature | Default |
|---|---|
| nginx image | `nginx:1.27.0` |
| Replicas | `2` |
| Ingress class | `nginx` (NGINX Ingress Controller) |
| Service type | `ClusterIP` |
| HPA | disabled (configurable) |

The ingress template supports **both** the NGINX Ingress Controller and the AWS Load
Balancer Controller. Switch between them by changing `ingress.className` and adding the
appropriate annotations in `values.yaml`:

```yaml
# NGINX Ingress Controller (default)
ingress:
  className: "nginx"
  annotations: {}

# AWS Load Balancer Controller
ingress:
  className: "alb"
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
```

---

## Dumping the Generated Templates

Run the following command from the **repository root** to render and inspect all
Kubernetes manifests that would be applied:

```bash
helm template nginx-app deploying-an-application/helm/nginx-app \
  --namespace staging
```

To override specific values inline:

```bash
helm template nginx-app deploying-an-application/helm/nginx-app \
  --namespace staging \
  --set image.tag=1.27.3 \
  --set ingress.hosts[0].host=my-app.example.com
```

To use a custom values file:

```bash
helm template nginx-app deploying-an-application/helm/nginx-app \
  --namespace staging \
  --values my-custom-values.yaml
```

---

## Deploying Manually

### Prerequisites

- [Helm](https://helm.sh/docs/intro/install/) >= 3.17
- `kubectl` configured to talk to your EKS cluster
- NGINX Ingress Controller **or** AWS Load Balancer Controller installed in the cluster

### Install / Upgrade

```bash
# First install
helm upgrade --install nginx-app deploying-an-application/helm/nginx-app \
  --namespace staging \
  --create-namespace \
  --atomic \
  --timeout 5m

# Uninstall
helm uninstall nginx-app --namespace staging
```

---

## GitHub Actions – OIDC Deploy Workflow

The workflow at [`.github/workflows/deploy-staging.yml`](../.github/workflows/deploy-staging.yml)
automatically deploys the Helm chart to the staging EKS cluster on every push to `main`
that touches `deploying-an-application/helm/**`. It can also be triggered manually via
`workflow_dispatch` with an optional `image_tag` input.

### How OIDC Authentication Works

```
GitHub Actions runner
        │
        │  1. Requests a short-lived OIDC JWT token from GitHub's OIDC provider
        │     (https://token.actions.githubusercontent.com)
        ▼
AWS STS AssumeRoleWithWebIdentity
        │
        │  2. AWS validates the JWT against GitHub's public JWKS endpoint and checks the
        │     trust policy conditions (repo, branch, workflow, etc.)
        │
        │  3. AWS returns temporary credentials (no long-lived keys stored anywhere)
        ▼
aws eks update-kubeconfig  →  helm upgrade --install
```

### One-time AWS Setup

#### 1. Create the OIDC Identity Provider in IAM

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

#### 2. Create the IAM Role with a Trust Policy

Save the following as `trust-policy.json` (replace `YOUR_ORG/YOUR_REPO` with your
GitHub org and repository name):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:webivation/roadpass:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

```bash
aws iam create-role \
  --role-name github-actions-roadpass-staging \
  --assume-role-policy-document file://trust-policy.json

# The role needs eks:DescribeCluster so that aws eks update-kubeconfig can fetch the
# cluster endpoint and CA data. Kubernetes RBAC (via aws-auth) handles what the role
# can do inside the cluster — not IAM policies.
# Create and attach a minimal inline policy instead of AmazonEKSClusterPolicy
# (which is the cluster service-role policy and is not appropriate here).
aws iam put-role-policy \
  --role-name github-actions-roadpass-staging \
  --policy-name eks-describe-cluster \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "eks:DescribeCluster",
      "Resource": "arn:aws:eks:us-east-1:<ACCOUNT_ID>:cluster/roadpass-staging"
    }]
  }'
```

#### 3. Store the Role ARN as a GitHub Secret

```bash
# Get the ARN
aws iam get-role --role-name github-actions-roadpass-staging \
  --query Role.Arn --output text
```

Add it as a repository secret named **`AWS_OIDC_ROLE_ARN`** in
**Settings → Secrets and variables → Actions → New repository secret**.

#### 4. Grant the IAM Role Access to the EKS Cluster

```bash
# Add the role to the aws-auth ConfigMap
eksctl create iamidentitymapping \
  --cluster roadpass-staging \
  --region us-east-1 \
  --arn arn:aws:iam::<ACCOUNT_ID>:role/github-actions-roadpass-staging \
  --group system:masters \
  --username github-actions
```

> **Tip**: Replace `system:masters` with a more restrictive ClusterRole binding
> (`edit` or a custom role) for production use.
