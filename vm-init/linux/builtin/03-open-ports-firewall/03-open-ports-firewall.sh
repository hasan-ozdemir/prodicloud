set -euo pipefail
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
TCP_PORTS=(__TCP_PORTS_BASH__)
for PORT in "${TCP_PORTS[@]}"; do
  sudo ufw allow "${PORT}/tcp"
done
sudo ufw --force enable
echo "linux-firewall-ready"

