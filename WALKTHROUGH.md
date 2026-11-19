# Implementation Walkthrough

Step-by-step build of the home SOC: hardened Ubuntu host, Wazuh in Docker, Suricata in Docker, and a Wazuh agent that reads Suricata alerts.

> Replace placeholders before running anything:
> `<LAN_IP>` = your server's LAN address, `<TAILSCALE_IP>` = its Tailscale address, `<LAN_SUBNET>` = for example `10.0.0.0/24`, `<CAPTURE_IFACE>` = your interface name from `ip -br a`.
> Do not commit real IPs, passwords or keys to this repo.

## Before you start

- Keep a second SSH session open for the whole hardening phase.
- Do not enable the firewall until your SSH port is confirmed (Step 1) and allowed.
- Run each step in order and confirm the "Verify" line before moving on.

## Step 1: Identify the network and SSH port

```
ip -br a
sudo ss -tlnp | grep sshd
```
Note the interface names, the server's LAN IP, and the port sshd listens on (usually 22).

## Step 2: Update the system and install tools

```
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl ufw fail2ban lynis
```
Lynis is a system auditor used in Step 8.

## Step 3: Install Docker

```
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
```
Log out and back in so the group change applies.

Verify:
```
docker compose version
docker run --rm hello-world
```

## Step 4: Baseline and kernel setting

```
sudo ss -tulnp | tee ~/ports-before.txt
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-wazuh.conf
sudo sysctl --system
```
The baseline file lets you compare open ports later. Disable services you do not recognize or need with `sudo systemctl disable --now <service>`. The sysctl value is required by the Wazuh indexer.

## Step 5: Firewall (UFW)

Add the rules first, check them, then enable.

```
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow in on tailscale0 to any port 22 proto tcp
sudo ufw allow in on tailscale0 to any port 443 proto tcp
sudo ufw allow from <LAN_SUBNET> to any port 22 proto tcp
sudo ufw allow from <LAN_SUBNET> to any port 443 proto tcp
sudo ufw allow from <LAN_SUBNET> to any port 1514 proto tcp
sudo ufw allow from <LAN_SUBNET> to any port 1515 proto tcp
sudo ufw status numbered
```
Use your real SSH port in place of 22 if it differs. Ports 1514 and 1515 are for Wazuh agent traffic and enrollment; add `proto udp` rules only if you use UDP.

Before enabling, confirm from your second session that Tailscale or LAN access is covered by a rule. Then:
```
sudo ufw enable
```

Note: Docker-published ports can bypass UFW, which is why Step 10 binds ports to specific addresses.

## Step 6: Fail2ban

```
sudo nano /etc/fail2ban/jail.local
```
Contents:
```
[sshd]
enabled = true
maxretry = 3
findtime = 600
bantime = 1h
ignoreip = 127.0.0.1/8 ::1 <YOUR_TRUSTED_IP>
```
Save with Ctrl+O, Enter, then exit with Ctrl+X.

```
sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban
sudo fail2ban-client status sshd
```

## Step 7: SSH key-only login

Do this only after key login works from a new session.

```
sudo nano /etc/ssh/sshd_config
```
Set:
```
PasswordAuthentication no
PermitRootLogin no
```
Check and reload:
```
sudo sshd -t
sudo systemctl reload ssh
```
Open a new session to confirm you can still log in before closing the old one.

## Step 8: Audit with Lynis

```
sudo lynis audit system --quick
```
Reports are saved to `/var/log/lynis-report.dat` (machine readable) and `/var/log/lynis.log` (human readable).

## Step 9: Deploy Wazuh

```
git clone https://github.com/wazuh/wazuh-docker.git -b v4.14.10
cd wazuh-docker/single-node/
docker compose -f generate-indexer-certs.yml run --rm generator
```
Use the stable release tag you intend to run; check the Wazuh releases page for the current one. Certificates are created under `config/wazuh_indexer_ssl_certs`.

Default dashboard login is the Wazuh Docker default admin account. Change the default password using the official Wazuh Docker password-change procedure before exposing anything.

## Step 10: Close exposed ports

```
nano docker-compose.yml
```
Make these changes:

- Under the dashboard service, remove the original `443:5601` mapping and add one line per address you want to serve:
  `"<LAN_IP>:443:5601"` and `"<TAILSCALE_IP>:443:5601"`
- Under the indexer service, change `9200:9200` to `"127.0.0.1:9200:9200"`.
- Under the manager service, change `55000:55000` to `"<TAILSCALE_IP>:55000:55000"` for API access over Tailscale.

Validate and start:
```
docker compose config > /dev/null && echo OK
docker compose up -d
```
Wait 60 to 90 seconds, then:
```
docker compose ps -a
sudo ss -tulnp
```
Verify nothing private shows `0.0.0.0`. If you get "address already in use", run `docker compose down` and bring it up again after checking that port 443 is mapped only once.

## Step 11: Deploy Suricata

```
sudo mkdir -p /var/log/suricata ~/soc/suricata
nano ~/soc/suricata/docker-compose.yml
```
Contents:
```yaml
services:
  suricata:
    image: jasonish/suricata:latest
    container_name: suricata
    network_mode: host
    cap_add: [NET_ADMIN, NET_RAW, SYS_NICE]
    command: -i <CAPTURE_IFACE>
    restart: unless-stopped
    volumes:
      - /var/log/suricata:/var/log/suricata
      - suricata-rules:/var/lib/suricata
volumes:
  suricata-rules:
```
Start and check:
```
cd ~/soc/suricata && docker compose up -d
docker logs suricata --tail 30
```

If the log says no rules were loaded, download them:
```
docker exec -it suricata suricata-update
docker exec suricata ls -lh /var/lib/suricata/rules/
docker restart suricata
```
You should see `suricata.rules`.

Test an alert:
```
curl http://testmynids.org/uid/index.html
grep '"event_type":"alert"' /var/log/suricata/eve.json | tail -n 3
```
If the capture interface is Wi-Fi, Suricata sees only the server's own traffic. For wider visibility see `10-network-mirroring.md`.

## Step 12: Connect the Wazuh agent

1. In the Wazuh dashboard, click Deploy new agent.
2. Choose the package for your architecture.
3. Enter the server address and copy the generated command, then run it.
4. Start the agent:
```
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
```
5. Add the Suricata log:
```
sudo nano /var/ossec/etc/ossec.conf
```
Inside `<ossec_config>` add:
```xml
<localfile>
  <log_format>json</log_format>
  <location>/var/log/suricata/eve.json</location>
</localfile>
```
6. Restart:
```
sudo systemctl restart wazuh-agent
```
Verify the agent shows Active and Suricata alerts appear in Security Events.

## Final checklist

- [ ] SSH key login works from a new session
- [ ] UFW enabled and Tailscale/LAN access confirmed
- [ ] Wazuh default passwords changed
- [ ] Indexer bound to 127.0.0.1
- [ ] Suricata rules loaded and a test alert appears in `eve.json`
- [ ] Agent Active and Suricata alerts visible in the dashboard
- [ ] No real IPs, passwords or keys in the repo

## Screenshots

Add screenshots to `docs/images/` and link them here. Blur IP addresses and remove any visible passwords first.
