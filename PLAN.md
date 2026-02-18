# Plan

**Pins:** k3s `v1.36.4+k3s1` (latest stable) · PostgreSQL `18.6` (PGDG apt repo)
**Roles:** jarvis `192.168.20.224` = server · friday `192.168.20.223` = agent + PostgreSQL

### 1. k3s server on jarvis

Stock install, no flags. The defaults already cover everything this cluster needs: Traefik and ServiceLB come enabled.

```sh
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.36.4+k3s1 sh -
```

### 2. k3s agent on friday

The token is root-only on jarvis; grab it with:

```sh
ssh julian-one@jarvis sudo cat /var/lib/rancher/k3s/server/node-token
```

Then on friday:

```sh
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.36.4+k3s1 \
  K3S_URL=https://192.168.20.224:6443 K3S_TOKEN=<token> sh -
```

### 3. Verify

`kubectl get nodes -o wide` → jarvis `control-plane,master`, friday `<none>`, both **Ready**.

### 4. Kubeconfig on the Mac

The kubeconfig stays root-only on jarvis (default mode `600`); pull it with sudo:

```sh
ssh julian-one@jarvis sudo cat /etc/rancher/k3s/k3s.yaml
```

Rewrite server to `https://192.168.20.224:6443`, rename cluster/user/context to `stark`, **merge** into `~/.kube/config` (existing contexts are preserved).

### 5. PostgreSQL 18 on friday, data on the SSD

Trixie main only carries 17, so add the PGDG repo first:

```sh
sudo apt install -y postgresql-common
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
sudo apt install -y postgresql-18
sudo pg_dropcluster --stop 18 main
sudo pg_createcluster -d /mnt/ssd/postgresql/18/main --start 18 main
```

Make the service wait for the SSD — the fstab entry is `nofail`, so boot continues even without the disk, and this drop-in keeps Postgres from starting without it:

```sh
sudo mkdir -p /etc/systemd/system/postgresql@18-main.service.d
printf '[Unit]\nRequiresMountsFor=/mnt/ssd\n' | \
  sudo tee /etc/systemd/system/postgresql@18-main.service.d/ssd.conf
sudo systemctl daemon-reload
```

Then in `/etc/postgresql/18/main/`: `listen_addresses = '*'`, and `pg_hba.conf` gets `scram-sha-256` for `10.42.0.0/16` and `192.168.20.0/24`; apply with `sudo systemctl restart postgresql@18-main`. Both lines carry pod traffic: flannel masquerades cross-node traffic to the node's LAN IP, so pods on jarvis reach Postgres as `192.168.20.224` and only pods on friday itself appear from the pod CIDR — the LAN line is not just for pgAdmin, don't drop it. App role/database on request.

### 6. postgres password via 1Password

On the Mac (desktop approval required, per [SSH](SSH.md)). The `letters,digits` recipe avoids shell/SQL quoting hazards; piping the SQL over stdin keeps the password out of `ps` output on friday:

```sh
op item create --category=login --title=stark-postgres \
  --generate-password='letters,digits,32' username=postgres \
  --url postgres://192.168.20.223:5432
echo "ALTER USER postgres PASSWORD '$(op item get stark-postgres --fields password --reveal)';" | \
  ssh julian-one@friday 'sudo -u postgres psql'
```

### 7. pgAdmin on the Mac

Brew cask, per the [Brewfile](~/dotfiles/Brewfile) rule — the file ends with the `# Apps` section, so a plain append lands in the right place:

```sh
echo 'cask "pgadmin4"' >> ~/dotfiles/Brewfile
brew bundle --file ~/dotfiles/Brewfile
```

Launch pgAdmin 4 → Object → Register → Server:

- **General:** name `stark`
- **Connection:** host `192.168.20.223`, port `5432`, maintenance DB `postgres`, username `postgres`

Password comes from 1Password rather than pgAdmin's saved-password store:

```sh
op item get stark-postgres --fields password --reveal | pbcopy
```

The Mac is on `192.168.20.0/24`, which step 5's `pg_hba.conf` LAN line already permits — no server-side change needed.
