up:
	cd wazuh-docker/single-node && docker compose up -d
	docker compose -f docker/suricata/docker-compose.yml --env-file .env up -d

down:
	docker compose -f docker/suricata/docker-compose.yml down
	cd wazuh-docker/single-node && docker compose down

rules:
	docker exec suricata suricata-update
	docker restart suricata

health:
	bash scripts/health-check.sh

audit:
	bash hardening/01-audit-ports.sh
