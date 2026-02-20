# stark

> "Good evening, sir."

Kubernetes manifests for **jroberts.info**, running on a Raspberry Pi 4 (Jarvis) with k3s.

## Suit Up

Apply in order — faceplate goes on last.

```
kubectl apply -f namespace.yaml
kubectl apply -f cert-manager/
kubectl apply -f citadel/
kubectl apply -f shire/
```

### Run a Diagnostic

```
kubectl get pods -n industries
kubectl get certificates -n industries
kubectl get ingress -n industries
```

## Operations

### Restart a Deployment

Percussive maintenance, but for pods.

```
kubectl rollout restart deployment citadel -n industries
kubectl rollout status deployment citadel -n industries
```

### Debugging

For when things go sideways. Even the Mark I had rough patches.

```
# pod status and recent events
kubectl describe pod -l app=citadel -n industries

# application logs
kubectl logs -l app=citadel -n industries

# follow logs in real time
kubectl logs -f -l app=citadel -n industries

# shell into a running pod
kubectl exec -it deployment/citadel -n industries -- sh

# check all resources in the namespace
kubectl get all -n industries

# view events sorted by time
kubectl get events -n industries --sort-by='.lastTimestamp'
```

## Infrastructure

The arc reactor. Not miniaturized, but it fits on a desk.

- **Ingress controller**: Traefik
- **Load balancer**: ServiceLB
- **TLS**: cert-manager with Let's Encrypt

> "Will that be all, sir?"
