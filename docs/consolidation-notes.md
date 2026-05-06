# Consolidation Notes

This repo is the consolidated bootstrap repo for GaScanner nodes.

## Kept From `gascanner-node-setup`

- Interactive node bootstrap script in `scripts/setup.sh`
- County defaults in `configs/<county>/system.conf`
- trunk-recorder Docker template in `templates/docker-compose.yml`
- Manual setup workflow for remote nodes
- Bootstrap scope: create and operate a remote trunk-recorder node

## Folded In From `GaScanner`

- Current high-level service architecture: Mosquitto, ThinLine Radio, tr-engine, tr-dashboard, Traefik, Cloudflared, Uptime Kuma, AutoKuma, Dashy, Dozzle
- Current MQTT broker/topic reference
- Current monitoring model and AutoKuma label conventions
- Clarification that ThinLine Radio and tr-engine are the primary path for new nodes
- Clarification that RDIO Scanner is still running as a Docker legacy/compatibility service

## Intentionally Not Folded In

- Application source repos:
  - `/home/adminlocal/trunk-reporter/tr-engine`
  - `/home/adminlocal/trunk-reporter/tr-dashboard`
  - `/home/adminlocal/ThinLineRadio`
- Live Docker deployment files under `/home/adminlocal/.docker/`
- Live secrets and `.env` files
- Nested local checkouts under this repo (`tr-engine/`, `tr-dashboard/`)
- Historical architecture references for SWAG, iCAD, Grafana, Telegraf, InfluxDB, Elasticsearch, DIUN, Trunk-Player NG, and static-image nginx

## Current Source Of Truth

- Bootstrap/node provisioning: this repo
- Live VPS deployment: `/home/adminlocal/.docker/`
- Application code:
  - `/home/adminlocal/trunk-reporter/tr-engine`
  - `/home/adminlocal/trunk-reporter/tr-dashboard`
  - `/home/adminlocal/ThinLineRadio`
