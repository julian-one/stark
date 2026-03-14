# Monitoring Stack (PLG)

Centralized logging for the k3s cluster using the **Promtail → Loki → Grafana** pipeline. All pod logs across every namespace are collected, stored, and queryable from a single interface.

## Architecture

```
┌──────────┐     ┌──────────┐     ┌──────────┐
│ Promtail │────>│   Loki   │<────│ Grafana  │
│ DaemonSet│     │StatefulSet│    │Deployment│
│ (all nodes)    │ (friday) │     │ (friday) │
└──────────┘     └──────────┘     └──────────┘
```

**Promtail** runs as a DaemonSet on every node (jarvis + friday). It tails pod log files from `/var/log/pods/` on each node, parses the CRI log format, attaches Kubernetes metadata labels (namespace, pod, container, node), and pushes log entries to Loki.

**Loki** runs as a single-replica StatefulSet pinned to friday. It receives log streams from Promtail, indexes them using TSDB, and stores chunks on the filesystem. Storage is backed by a 10Gi PersistentVolume on friday's SSD at `/mnt/ssd/loki`. Retention is set to 7 days. Loki exposes a ClusterIP service on port 3100 — internal only, no external access.

**Grafana** runs as a single-replica Deployment pinned to friday. It's pre-configured with Loki as the default datasource via a provisioning ConfigMap. Grafana is exposed via NodePort on port 30030, accessible at `http://<any-node-ip>:30030`.

## Namespace

All monitoring resources live in the `monitoring` namespace, defined in `stark/namespace.yaml`.

## File Layout

```
stark/
├── namespace.yaml              # includes monitoring namespace
├── loki/
│   ├── pv.yaml                 # PV (hostPath /mnt/ssd/loki on friday) + PVC
│   ├── configmap.yaml          # Loki config: single-binary mode, TSDB index, 7d retention
│   ├── rbac.yaml               # ServiceAccount
│   ├── statefulset.yaml        # StatefulSet pinned to friday
│   └── service.yaml            # ClusterIP on port 3100
├── promtail/
│   ├── configmap.yaml          # Scrape config: kubernetes-pods SD, CRI parsing, label extraction
│   ├── daemonset.yaml          # DaemonSet on all nodes, mounts /var/log/pods (read-only)
│   └── rbac.yaml               # ServiceAccount + ClusterRole + ClusterRoleBinding
└── grafana/
    ├── configmap.yaml          # Datasource provisioning (Loki as default)
    ├── deployment.yaml         # Deployment pinned to friday
    └── service.yaml            # NodePort on 30030
```

## Deployment

Apply in order after `namespace.yaml`:

```bash
kubectl apply -f stark/loki/
kubectl apply -f stark/promtail/
kubectl apply -f stark/grafana/
```

## Verification

```bash
# all pods should be Running (1 loki, 2 promtail, 1 grafana)
kubectl -n monitoring get pods -o wide

# check Loki is ready
kubectl -n monitoring logs statefulset/loki --tail=10

# check Promtail is discovering targets
kubectl -n monitoring logs daemonset/promtail --tail=10

# check all resources
kubectl -n monitoring get all
```

## Querying Logs

Access Grafana at `http://<node-ip>:30030` (default login: `admin` / `admin`).

Navigate to **Explore** and select the **Loki** datasource. Example LogQL queries:

```logql
# all logs from the industries namespace
{namespace="industries"}

# citadel logs only
{namespace="industries", container="citadel"}

# shire logs only
{namespace="industries", container="shire"}

# logs from a specific node
{node="jarvis"}

# filter by log content
{namespace="industries"} |= "error"

# JSON-aware filtering (citadel uses structured logging)
{namespace="industries", container="citadel"} | json | status >= 400
```

## Key Details

- **Promtail node filtering**: Each Promtail pod uses the downward API to set `HOSTNAME` to `spec.nodeName`, ensuring it only tails logs from pods on its own node.
- **Positions file**: Stored at `/run/promtail` via hostPath, so Promtail remembers which log lines it has already shipped across pod restarts.
- **Storage**: Loki data lives on friday's SSD at `/mnt/ssd/loki`. The PV uses `nodeAffinity` to ensure it only binds on friday.
- **Retention**: 7 days (`limits_config.retention_period: 168h`), enforced by Loki's compactor.
- **Resource limits**: Conservative for Pi hardware — Loki (128Mi–512Mi), Promtail (32Mi–128Mi), Grafana (64Mi–256Mi).
- **Images**: Loki 3.4.2, Promtail 3.4.2, Grafana 11.5.2 — all multi-arch with arm64 support.
