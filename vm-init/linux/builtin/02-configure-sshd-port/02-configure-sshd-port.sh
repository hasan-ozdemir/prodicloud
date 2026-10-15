set -euo pipefail
SSHD_CONFIG="/etc/ssh/sshd_config"
sudo sed -i -E 's/^#?Port .*/Port __SSH_PORT__/' "${SSHD_CONFIG}"
sudo sed -i -E 's/^#?PasswordAuthentication .*/PasswordAuthentication yes/' "${SSHD_CONFIG}"
sudo sed -i -E 's/^#?PubkeyAuthentication .*/PubkeyAuthentication no/' "${SSHD_CONFIG}"
sudo sed -i -E 's/^#?PermitRootLogin .*/PermitRootLogin yes/' "${SSHD_CONFIG}"
sudo sed -i -E 's/^#?AllowTcpForwarding .*/AllowTcpForwarding yes/' "${SSHD_CONFIG}"
sudo sed -i -E 's/^#?GatewayPorts .*/GatewayPorts yes/' "${SSHD_CONFIG}"
echo "linux-sshd-config-ready"

