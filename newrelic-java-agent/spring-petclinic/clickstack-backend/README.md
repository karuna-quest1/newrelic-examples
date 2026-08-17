# ClickStack backend (Docker) — for docker-target migration testing

Runs **ClickHouse + MongoDB + HyperDX** as standalone Docker containers on a
network named **`clickstack`**. The OTel Collector is *not* here — it is generated
by shinro (`migrate --live --target docker`) and attaches to this network.

## 1. Start the backend (do this first)

```bash
cd clickstack-backend
docker compose up -d
docker compose ps                     # wait for clickhouse = healthy
docker network ls | grep clickstack   # confirm the network exists
```

- ClickHouse native TCP: `clickhouse:9000` (on the `clickstack` network) / `localhost:9000` (host)
- ClickHouse HTTP UI: http://localhost:8123
- HyperDX UI: http://localhost:8082

## 2. Run the docker-target live migration (from the shinro CLI)

```bash
shinro migrate --live --path /Users/karunanidhi/newrelic-examples/newrelic-java-agent/spring-petclinic \
  --mode dual_write \
  --target docker \
  --collector-endpoint <HOST_REACHABLE_FROM_PODS>:4318
```

The generator writes the collector compose to `docker/dual-write/` under the app
path. Bring the collector up:

```bash
cd docker/dual-write
cp .env.example .env        # set CLICKHOUSE_PASSWORD=password (matches backend)
docker compose up -d
```

Then apply the generated Kubernetes patch to the petclinic Deployment (it points
the app's OTel agent at `--collector-endpoint`).

## Teardown

```bash
cd clickstack-backend && docker compose down -v   # -v also removes CH/Mongo data
```
