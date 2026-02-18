# Cluster

Installed 2026-08-29 via [PLAN](PLAN.md). Two Raspberry Pis, Debian 13 (trixie), arm64, SSH per [SSH](SSH.md).

| Node   | IP               | Role                 | Extras                          |
| ------ | ---------------- | -------------------- | ------------------------------- |
| jarvis | `192.168.20.224` | k3s server (control-plane) | 439 G SSD at `/mnt/ssd` (unused) |
| friday | `192.168.20.223` | k3s agent            | PostgreSQL 18, data on 1 TB SSD |

## k3s

`v1.36.4+k3s1`, stock install — no flags. Traefik and ServiceLB enabled, flannel pod CIDR `10.42.0.0/16`.
Both Pis run RPi OS trixie's default 2 G zram swap; k3s tolerates it (`--fail-swap-on=false` is its default).
Memory cgroup flags were already present in `/boot/firmware/cmdline.txt`.

- Kubeconfig: context `stark` in `~/.kube/config` on the Mac, server `https://192.168.20.224:6443`
- Join token: `/var/lib/rancher/k3s/server/node-token` on jarvis, root-only
- Uninstall scripts: `k3s-uninstall.sh` on jarvis, `k3s-agent-uninstall.sh` on friday

```sh
kubectl --context stark get nodes -o wide
```

## PostgreSQL

`18.6` from PGDG on friday, listening on `*:5432`.

| What        | Where                                                       |
| ----------- | ----------------------------------------------------------- |
| Data        | `/mnt/ssd/postgresql/18/main` (WD Blue SA510 1 TB, USB)     |
| Config      | `/etc/postgresql/18/main/` (`listen_addresses` in `conf.d/stark.conf`) |
| Logs        | `/var/log/postgresql/postgresql-18-main.log`                |
| Service     | `postgresql@18-main`, drop-in `RequiresMountsFor=/mnt/ssd`  |
| Password    | 1Password item `stark-postgres`                             |

The mount drop-in matters: fstab mounts `/mnt/ssd` with `nofail`, so without it a boot with the SSD missing would happily continue and Postgres would start broken.

`pg_hba.conf` allows `scram-sha-256` from `10.42.0.0/16` and `192.168.20.0/24`.
Both lines carry pod traffic — flannel masquerades cross-node traffic to the node's LAN IP, so pods on jarvis arrive as `192.168.20.224`;
only pods on friday appear from the pod CIDR. Don't drop the LAN line.

initdb defaults picked up from friday: locale `en_GB.UTF-8`, timezone `America/Denver` — the timezone was since overridden to `UTC` (`ALTER SYSTEM SET timezone/log_timezone`, lives in `postgresql.auto.conf`), and both Pis' OS clocks are `Etc/UTC` via `timedatectl`.

App role `moria` (`LOGIN CREATEDB` — its test suite creates and drops throwaway databases) owns `moria` (prod) and `moria_dev` (local dev), password in 1Password item `moria-postgres`.

```sh
op item get stark-postgres --fields password --reveal | pbcopy
psql -h 192.168.20.223 -U postgres
```

## Web

`https://julian-one.com` — SvelteKit site (sibling repo `shire`), replacing the original "coming soon" page from [SITE](SITE.md).

| What         | Where                                                                        |
| ------------ | ---------------------------------------------------------------------------- |
| Manifests    | `shire/shire.yaml` — Deployment/Service/Ingress; `site/` keeps namespace `web`, ClusterIssuer, redirect + hsts middlewares |
| Image        | Docker Hub `julianone/shire:<utc-date-tag>`, linux/arm64, node:26-alpine     |
| TLS          | cert-manager `v1.21.1`, ClusterIssuer `letsencrypt` (HTTP-01), secret `julian-one-tls` |
| Ingress path | janus (OpenWrt, `root@192.168.20.1`) DNATs WAN 80/443 → jarvis → Traefik    |
| DNS          | Porkbun ALIAS → `sauron-ddns.duckdns.org`, cron on sauron updates every 5 min |

Redeploy: in the shire repo `docker build --platform linux/arm64 -t julianone/shire:$(date -u +%Y%m%d-%H%M%S) --push .`, set that tag in `shire/shire.yaml`, `kubectl --context stark apply -f shire/`.
Probes hit `/healthz` (self-only, no upstream calls); `ADDRESS_HEADER`/`XFF_DEPTH` are baked into the image for Traefik's `X-Forwarded-For`.

janus firewall: `Forward-443-jarvis` (pre-existing anonymous section), `forward_80_jarvis` (named, added for the ACME challenge and redirect).
HTTP 301s to HTTPS via Traefik middleware `web/redirect-https`, and `web/hsts` stamps `Strict-Transport-Security`;
cert-manager's solver ingress is unannotated so challenges bypass it.

`moria` — auth API (Go, sibling repo `moria`), deployed 2026-08-29. In-cluster only since 2026-08-30: shire reaches
it at `http://moria`, direct access is `kubectl --context stark -n web port-forward svc/moria 8081:80` (the public
ingress was deleted to keep `/login` off the internet; the `moria-tls` secret and `moria.julian-one.com` Porkbun
ALIAS linger but route nowhere). Memory limit is 128Mi and must stay ≥128Mi: scrypt allocates 32MiB per login
derivation, and the old 64Mi limit OOMKilled the pod on every real login.

| What      | Where                                                                        |
| --------- | ---------------------------------------------------------------------------- |
| Manifests | `moria/moria.yaml` — Deployment/Service, namespace `web`                     |
| Image     | Docker Hub `julianone/moria:<utc-date-tag>`, linux/arm64, distroless         |
| Database  | `moria` on friday, DSN via Secret `moria-database` key `database-url` — created imperatively from 1Password, never committed |

Redeploy: in the moria repo `docker build --platform linux/arm64 -t julianone/moria:$(date -u +%Y%m%d-%H%M%S) --push .`, set that tag in `moria/moria.yaml`, `kubectl --context stark apply -f moria/`.
First admin in a fresh database via `moria create-user` (`POST /users` is admin-gated); API admin credentials in 1Password item `moria-admin`.

```sh
kubectl --context stark -n web get certificate,pods,ingress
```

