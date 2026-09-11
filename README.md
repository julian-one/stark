# stark

Two-Pi k3s homelab serving `https://julian-one.com`. Manifests live here; **shire** (SvelteKit site) and **moria** (Go auth API) are sibling repos.

## Machines

| Host   | IP               | What                                                                                            |
| ------ | ---------------- | ----------------------------------------------------------------------------------------------- |
| jarvis | `192.168.20.224` | k3s server; WAN 80/443 lands here                                                               |
| friday | `192.168.20.223` | k3s agent; PostgreSQL 18 on 1 TB SSD                                                            |
| janus  | `192.168.20.1`   | OpenWrt router (`root@`); DNATs WAN 80/443 → jarvis (`Forward-443-jarvis`, `forward_80_jarvis`) |
| sauron | `192.168.20.2`   | Pi-hole + DuckDNS cron; never point a WAN forward here                                          |

SSH `julian-one@<host>` via the 1Password agent (desktop approval). DNS: Porkbun ALIAS → `sauron-ddns.duckdns.org`, DuckDNS cron on sauron every 5 min.

## kubectl

k3s `v1.36.4+k3s1`, stock install (Traefik, ServiceLB, flannel `10.42.0.0/16`). Refetch the kubeconfig after any reinstall — the CAs regenerate, and the API cert covers `jarvis`, not `jarvis.local`:

```sh
ssh julian-one@jarvis 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/.kube/config
kubectl config set-cluster default --server=https://jarvis:6443
kubectl config rename-context default stark
```

## PostgreSQL

`18.6` (PGDG) on friday, data at `/mnt/ssd/postgresql/18/main`, service `postgresql@18-main` with `RequiresMountsFor=/mnt/ssd` — fstab mounts the SSD `nofail`, so without the drop-in Postgres starts broken when the disk is missing. `pg_hba.conf` allows `scram-sha-256` from `10.42.0.0/16` and `192.168.20.0/24`; flannel masquerades cross-node pod traffic to node LAN IPs, so both lines carry pods — don't drop the LAN line. Role `moria` (`LOGIN CREATEDB`) owns `moria` and `moria_dev`. Passwords in 1Password: `psql_superuser`, `moria_psql_dev`, `moria_psql_prod`.

```sh
psql -h 192.168.20.223 -U postgres
```

## Deploy

Everything runs in the `default` namespace.

```sh
./deploy.sh
./deploy.sh shire
```

Applies the manifests, then builds and pushes `julianone/<app>:latest` for each named app (both when none given), restarts its deployment, and waits for the rollout.

TLS: cert-manager `v1.21.1`, ClusterIssuer `letsencrypt` (production ACME, HTTP-01), secret `julian-one-tls`. The ACME email is the iCloud relay in `issuer.yaml` — expiry notices land there.

- **shire** — the public site.
- **moria** — in-cluster only: shire uses `http://moria`, direct access via `kubectl --context stark port-forward svc/moria 8081:80`. Passwords are bcrypt (cost 12). DSN via Secret `moria-database` (created imperatively, never committed). First admin: `./create-admin.sh dev|prod` — idempotent insert straight into Postgres, creds read from the 1Password `julian-one.com - admin` item.

## Status

```sh
kubectl --context stark get certificate,pods,ingress
```
