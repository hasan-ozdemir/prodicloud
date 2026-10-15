set -euo pipefail
VM_ADMIN_USER="__VM_ADMIN_USER__"
VM_ADMIN_PASS="__VM_ADMIN_PASS__"
ASSISTANT_USER="__ASSISTANT_USER__"
ASSISTANT_PASS="__ASSISTANT_PASS__"
if ! id -u "${VM_ADMIN_USER}" >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash "${VM_ADMIN_USER}"
fi
if ! id -u "${ASSISTANT_USER}" >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash "${ASSISTANT_USER}"
fi
echo "${VM_ADMIN_USER}:${VM_ADMIN_PASS}" | sudo chpasswd
echo "${ASSISTANT_USER}:${ASSISTANT_PASS}" | sudo chpasswd
echo "root:${VM_ADMIN_PASS}" | sudo chpasswd
sudo passwd -u "${VM_ADMIN_USER}" || true
sudo passwd -u "${ASSISTANT_USER}" || true
sudo passwd -u root || true
sudo chage -E -1 "${VM_ADMIN_USER}" || true
sudo chage -E -1 "${ASSISTANT_USER}" || true
sudo chage -E -1 root || true
for ADMIN_USER in "${VM_ADMIN_USER}" "${ASSISTANT_USER}"; do
  sudo usermod -aG sudo "${ADMIN_USER}" || true
  echo "${ADMIN_USER} ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/90-${ADMIN_USER}-nopasswd" >/dev/null
  sudo chmod 440 "/etc/sudoers.d/90-${ADMIN_USER}-nopasswd"
done
echo "linux-user-passwords-ready"

