set -euo pipefail
sudo systemctl daemon-reload
sudo systemctl disable --now ssh.socket || true
sudo systemctl unmask ssh.service || true
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh.service
echo "linux-sshd-service-ready"

