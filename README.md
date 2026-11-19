# SOC Dashboard Lab

A home Security Operations Center built on a single Ubuntu server using Docker containers.
It watches the host and the network, stores logs, shows alerts on a dashboard, and includes
host-hardening steps (firewall, closed ports, SSH keys).

## What it does

| Component | Role |
|---|---|
| Wazuh manager, indexer, dashboard | SIEM: log analysis, host monitoring, alerting, web dashboard |
| Suricata (Docker, host networking) | Network intrusion detection using the Emerging Threats Open ruleset |
| Wazuh agent | Ships host logs and Suricata `eve.json` alerts to the manager |
| UFW, Fail2ban, SSH keys | Host hardening |
| Tailscale | Private remote access |
| TP-Link TL-SG108E (optional) | Port mirroring so Suricata can see LAN traffic |

## Architecture

```
Gateway/Router -> Switch port 1 (mirrored) -> Switch port 8 -> Server Ethernet (capture only, no IP)
Server Wi-Fi/LAN = management
Suricata (container) -> /var/log/suricata/eve.json -> Wazuh agent -> Wazuh manager -> indexer -> dashboard
```

## Quick start

```
git clone https://github.com/DonLawHanma/Soc-Dashboard.git
cd Soc-Dashboard
cp .env.example .env
```

1. `docs/01-prerequisites.md`
2. `docs/02-host-hardening.md`
3. `docs/03-deploy-wazuh.md`
4. `docs/04-deploy-suricata.md`
5. `docs/05-connect-agents.md`
6. `docs/06-alerting.md`
7. `docs/08-troubleshooting.md` if something breaks

## Security notes

- Never commit `.env`, certificates or real passwords. Change all Wazuh default credentials.
- Docker published ports can bypass UFW. Bind each port to a specific IP.
- Only monitor networks you own or are authorized to test.

## Status

Work in progress. Update this section with what you have verified (dashboard reachable, Suricata rules loaded, agent active, test alert seen).

## Sources

See `docs/09-sources.md`.

## License

MIT
