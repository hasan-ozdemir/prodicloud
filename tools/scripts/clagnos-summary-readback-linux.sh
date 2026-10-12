set -euo pipefail
SSHD_CONFIG="/etc/ssh/sshd_config"
echo "Version Info:"
lsb_release -a || true
echo "OPEN Ports:"
ss -tlnp | grep -E ':(__TCP_PORTS_REGEX__)\b' || true
echo "Firewall STATUS:"
sudo ufw status verbose
echo "SSHD CONFIG:"
grep -E "^(Port|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|AllowTcpForwarding|GatewayPorts)" "${SSHD_CONFIG}" || true

