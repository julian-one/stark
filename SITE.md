# Site

**Goal:** `https://julian-one.com` serving a static "coming soon" page from the cluster.
**Pins:** cert-manager `v1.21.1` · nginx `1.29-alpine`

### Current state

| Piece   | Finding                                                                                                     |
| ------- | ----------------------------------------------------------------------------------------------------------- |
| DNS     | Porkbun ALIAS `julian-one.com` → `sauron-ddns.duckdns.org` → WAN IP `174.29.207.232`, TTL 600               |
| DuckDNS | Cron on sauron (`192.168.20.2`) runs `~/duckdns/duck.sh` every 5 min, last update OK                        |
| janus   | OpenWrt `25.12.5`, Pi 4, `root@192.168.20.1`. WAN is DHCP holding the real public IP directly — no CGNAT. Named UCI redirect `Forward-443-jarvis`: WAN:443 → `192.168.20.224:443`. No WAN:80 rule; wan zone input is REJECT, so public 80 is currently dead |
| Cluster | Traefik + ServiceLB hold 80/443 on both nodes (`192.168.20.223`, `192.168.20.224`)                          |
| sauron  | Pi-hole owns 80/443 locally — never point a WAN forward at sauron                                           |
| www     | Falls through the wildcard `*.julian-one.com` → `uixie.porkbun.com` parking                                 |

A WAN IP change means up to ~15 min of downtime (5-min cron + 600 TTL) — inherent to the DuckDNS setup, fine for this.

fw4 enables NAT reflection per redirect by default — that's why hairpin 443 already works from the LAN, and 80 will behave the same once forwarded. LuCI listens on `0.0.0.0:80/443` but stays LAN-only: the wan zone rejects input, and the new DNAT only captures wan-zone and reflected traffic, not `192.168.20.1` admin access.

### 1. janus: forward WAN:80 → jarvis

Automated over SSH, mirroring the existing 443 rule. A named section keeps it idempotent — re-running re-sets the same values instead of stacking duplicates. Do this first — cert issuance retries but fails until 80 is open.

```sh
ssh root@192.168.20.1 "
uci set firewall.forward_80_jarvis=redirect
uci set firewall.forward_80_jarvis.name='Forward-80-jarvis'
uci set firewall.forward_80_jarvis.src='wan'
uci set firewall.forward_80_jarvis.src_dport='80'
uci set firewall.forward_80_jarvis.dest='lan'
uci set firewall.forward_80_jarvis.dest_ip='192.168.20.224'
uci set firewall.forward_80_jarvis.dest_port='80'
uci set firewall.forward_80_jarvis.proto='tcp'
uci set firewall.forward_80_jarvis.target='DNAT'
uci commit firewall
service firewall reload
"
```

Verify — Traefik's 404 replacing the router's 403 proves the DNAT took:

```sh
curl -sm5 -D- -o /dev/null http://174.29.207.232/
```

Rollback, if ever needed:

```sh
ssh root@192.168.20.1 "uci delete firewall.forward_80_jarvis && uci commit firewall && service firewall reload"
```

### 2. DNS: www (optional)

Add ALIAS `www.julian-one.com` → `sauron-ddns.duckdns.org` at Porkbun, then add the host to the Ingress and its `tls` block. Skipped in the manifests below to keep the first cert simple; the wildcard parking record stays untouched either way.

### 3. cert-manager

```sh
kubectl --context stark apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.21.1/cert-manager.yaml
kubectl --context stark -n cert-manager wait --for=condition=Available deploy --all --timeout=180s
```

arm64 images are published; nothing special for the Pis.

### 4. Manifests

New `site/` directory in this repo, applied with plain `kubectl apply -f site/`.

`site/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: web
```

`site/issuer.yaml` — one ClusterIssuer, production Let's Encrypt. One cert won't hit rate limits; if debugging is ever needed, clone it with the staging URL.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: julian.roberts.one@gmail.com
    privateKeySecretRef:
      name: letsencrypt-account
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik
```

`site/web.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: julian-one-html
  namespace: web
data:
  index.html: |
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>julian-one.com</title>
    <style>
      body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #111; color: #eee; font-family: system-ui, sans-serif; }
      p { color: #888; }
    </style>
    </head>
    <body>
    <main>
    <h1>julian-one.com</h1>
    <p>coming soon</p>
    </main>
    </body>
    </html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: julian-one
  namespace: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: julian-one
  template:
    metadata:
      labels:
        app: julian-one
    spec:
      containers:
        - name: nginx
          image: nginx:1.29-alpine
          ports:
            - containerPort: 80
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              memory: 64Mi
      volumes:
        - name: html
          configMap:
            name: julian-one-html
---
apiVersion: v1
kind: Service
metadata:
  name: julian-one
  namespace: web
spec:
  selector:
    app: julian-one
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: redirect-https
  namespace: web
spec:
  redirectScheme:
    scheme: https
    permanent: true
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: julian-one
  namespace: web
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
    traefik.ingress.kubernetes.io/router.middlewares: web-redirect-https@kubernetescrd
spec:
  rules:
    - host: julian-one.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: julian-one
                port:
                  number: 80
  tls:
    - hosts:
        - julian-one.com
      secretName: julian-one-tls
```

The redirect middleware only rides the annotated router; cert-manager's HTTP-01 solver creates its own unannotated Ingress, so the challenge on port 80 is not redirected.

Single replica is enough for a placeholder — a node reboot means brief downtime. Bump to 2 with a pod anti-affinity when it matters.

### 5. Apply and verify

```sh
kubectl --context stark apply -f site/
kubectl --context stark -n web get certificate
```

Certificate goes `Ready True` within a minute or two once WAN:80 is forwarded. Then:

```sh
curl -I https://julian-one.com
curl -I http://julian-one.com
```

Expect `200` with a Let's Encrypt cert, and `308` on plain HTTP. Hairpin NAT worked for 443 during review, so this is testable from the LAN; a phone on cellular confirms the outside view.

### 6. Document

Fold the result into [CLUSTER](CLUSTER.md): cert-manager version, `web` namespace, both janus forwards, and a pointer here.
