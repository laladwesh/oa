# oa

CCD OA environment checker: candidates run a one-line command that scans their
own laptop for prohibited remote-access/screen-share tools and shows a
PASS/FAIL banner for the invigilator. See `scripts/check.sh` and
`scripts/check.ps1`.

## Local dev

```
npm install
cp .env.example .env   # fill in ADMIN_KEY
npm start
```

Serves on http://localhost:4000 (needs a local MongoDB at `mongodb://localhost:27017/oa_checker`, or set `MONGO_URI`).

Candidate-facing routes (all under `/oa-check`):

```
curl -fsSL http://localhost:4000/oa-check/check | bash      # mac/linux
irm http://localhost:4000/oa-check/check | iex              # windows powershell
```

Admin-only (needs `x-admin-key: <ADMIN_KEY>` header): `GET /oa-check/stats`.

## Production (Docker)

This assumes MongoDB is already installed and running directly on the server
(not in Docker) — `docker-compose.yml` does not bundle a `mongo` container.
The app container reaches it via `host.docker.internal`, which
`extra_hosts: host-gateway` makes resolvable on Linux too (not just Docker
Desktop).

**Before running this**, make sure the host's `mongod` is listening on an
interface Docker's bridge network can reach, not just `127.0.0.1`. Check
`net.bindIp` in `/etc/mongod.conf` — if it's set to `127.0.0.1` only, the app
container will get "connection refused" even though Mongo is up. Either add
the Docker bridge IP (commonly `172.17.0.1`) to `bindIp`, or bind to
`0.0.0.0` if the server's firewall already restricts external access to
Mongo's port.

```
docker compose up -d --build
```

Runs the `app` service on `127.0.0.1:6021`. Point host Nginx at it with a
straight passthrough (no path rewriting, since the app's own routes already
live under `/oa-check`):

```
location /oa-check/ {
    proxy_pass http://127.0.0.1:6021;
    proxy_set_header Host $host;
}
```

Candidates then run:

```
curl -fsSL https://iitg.ac.in/oa-check/check | bash      # mac/linux
irm https://iitg.ac.in/oa-check/check | iex               # windows powershell
```

## Environment variables

| Var          | Where it's set              | Required?                                             |
|--------------|------------------------------|--------------------------------------------------------|
| `PORT`       | fixed in `docker-compose.yml` (6021); defaults to 4000 locally | No |
| `MONGO_URI`  | fixed in `docker-compose.yml` (`mongodb://host.docker.internal:27017/oa_checker`, the server's existing Mongo); defaults to local Mongo locally | No |
| `ADMIN_KEY`  | `.env` (`env_file`)          | Only if you want `GET /oa-check/stats` to work; app runs fine without it |
| `PUBLIC_URL` | fixed in `docker-compose.yml` (`https://iitg.ac.in`); defaults to `http://localhost:$PORT` locally | No — only matters so the deployed script reports to the right place instead of the candidate's own localhost |

`docker-compose.yml`'s `environment:` block always wins over `.env` for `PORT`/`MONGO_URI`/`PUBLIC_URL`.
