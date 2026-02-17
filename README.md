# stark

Kubernetes manifests for jroberts.info, running on a Raspberry Pi 4 with k3s.

## Usage

Apply _in order_:

```
kubectl apply -f namespace.yaml
kubectl apply -f cert-manager/
kubectl apply -f citadel/
kubectl apply -f shire/
```

Verify:

```
kubectl get pods -n industries
kubectl get certificates -n industries
kubectl get ingress -n industries
```

## Infrastructure

- **Ingress controller**: Traefik
- **Load balancer**: ServiceLB
- **TLS**: cert-manager with Let's Encrypt
