#!/bin/sh
set -eu

case ${1:-} in
  dev) db=moria_dev ;;
  prod) db=moria ;;
  *) echo "usage: $0 dev|prod" >&2; exit 1 ;;
esac

username=$(op read 'op://Private/julian-one.com - admin/username')
password=$(op read 'op://Private/julian-one.com - admin/password')
email=$(op read 'op://Private/julian-one.com - admin/email')

hash=$(htpasswd -nbBC 12 '' "$password" | cut -d: -f2)

PGPASSWORD=$(op read "op://Private/moria_psql_$1/password") \
  psql -h 192.168.20.223 -U moria -d "$db" -v ON_ERROR_STOP=1 \
  -v user_id="$(uuidgen | tr '[:upper:]' '[:lower:]')" \
  -v username="$username" -v email="$email" -v hash="$hash" <<'SQL'
INSERT INTO users (user_id, username, email, password_hash, role)
VALUES (:'user_id', :'username', :'email', :'hash', 'admin')
ON CONFLICT DO NOTHING;
SQL
