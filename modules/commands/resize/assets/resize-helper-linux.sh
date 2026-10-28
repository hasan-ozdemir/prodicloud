#!/usr/bin/env bash
set -euo pipefail

KIND='__PRODICLOUD_RESIZE_KIND__'
TARGET_GB='__PRODICLOUD_RESIZE_TARGET_GB__'
EXPECTED_SOURCE_USED_BYTES='__PRODICLOUD_RESIZE_EXPECTED_SOURCE_USED_BYTES__'
MINIMUM_FREE_BYTES='__PRODICLOUD_RESIZE_MINIMUM_FREE_BYTES__'
SOURCE_LUN=10
TARGET_LUN=11
fail() { echo "Disk clone preparation failed: $*" >&2; exit 1; }
[[ "$EXPECTED_SOURCE_USED_BYTES" =~ ^[0-9]+$ ]] || fail 'The initial source-disk usage measurement is invalid.'
[[ "$MINIMUM_FREE_BYTES" =~ ^[0-9]+$ ]] || fail 'The configured shrink headroom is invalid.'
df_usage() { df -B1 --output=size,used,avail -- "$1" | tail -n 1; }
wait_for_lun() {
  local lun="$1" path="/dev/disk/azure/scsi1/lun$1" attempt resolved elapsed last_report=-30
  for attempt in $(seq 1 12); do
    if [[ -e "$path" ]]; then
      resolved="$(readlink -f "$path" 2>/dev/null || true)"
      if [[ -n "$resolved" && -b "$resolved" ]]; then printf '%s\n' "$resolved"; return 0; fi
    fi
    elapsed=$((attempt * 5))
    if (( elapsed - last_report >= 30 )); then
      last_report=$elapsed
      printf 'PRODICLOUD_RESIZE_PHASE:{"phase":"wait-for-lun-%s","elapsedSeconds":%s,"timeoutSeconds":60}\n' "$lun" "$elapsed" >&2
    fi
    sleep 5
  done
  fail "Azure data disk LUN ${lun} did not become a block device at ${path} within 60 seconds."
}
source_disk="$(wait_for_lun "$SOURCE_LUN")"
target_disk="$(wait_for_lun "$TARGET_LUN")"
[[ -b "$source_disk" && -b "$target_disk" ]] || fail 'The source clone and replacement disk were not attached at the expected LUNs.'

partitions() { lsblk -lnpo NAME,TYPE "$1" | awk '$2 == "part" {print $1}'; }
wait_for_partition_count() {
  local device="$1" expected="$2" attempt count elapsed last_report=-30
  local parts=()
  for attempt in $(seq 1 12); do
    parts=( $(partitions "$device") )
    count=${#parts[@]}
    if (( count == expected )); then
      local all_ready=true part
      for part in "${parts[@]}"; do [[ -b "$part" ]] || all_ready=false; done
      if [[ "$all_ready" == true ]]; then printf 'PRODICLOUD_RESIZE_PHASE:{"phase":"replacement-partitions-ready","count":%s,"expected":%s}\n' "$count" "$expected" >&2; return 0; fi
    fi
    elapsed=$((attempt * 5))
    if (( elapsed - last_report >= 30 )); then
      last_report=$elapsed
      printf 'PRODICLOUD_RESIZE_PHASE:{"phase":"wait-for-replacement-partitions","count":%s,"expected":%s,"elapsedSeconds":%s,"timeoutSeconds":60}\n' "$count" "$expected" "$elapsed" >&2
    fi
    sleep 5
  done
  fail "Replacement disk '$device' did not expose $expected ready partition(s) within 60 seconds."
}
source_parts=( $(partitions "$source_disk") )
target_parts=( $(partitions "$target_disk") )
if [[ "$KIND" == "data" ]]; then
  [[ ${#source_parts[@]} -eq 1 && ${#target_parts[@]} -eq 0 ]] || fail 'Linux data-disk shrink supports a single source partition and an empty target disk.'
  source_part="${source_parts[0]}"
  fs="$(sudo -n blkid -o value -s TYPE "$source_part")"
  old_uuid="$(sudo -n blkid -o value -s UUID "$source_part")"
  [[ "$fs" == 'ext4' || "$fs" == 'xfs' ]] || fail "Unsupported Linux data-disk filesystem '$fs'."
  sudo -n parted -s "$target_disk" mklabel gpt
  sudo -n parted -s "$target_disk" mkpart primary "$fs" 1MiB 100%
  sudo -n partprobe "$target_disk"
  sudo -n udevadm settle --timeout=5 || true
  wait_for_partition_count "$target_disk" 1
  target_part="$(partitions "$target_disk" | head -n 1)"
  [[ -b "$target_part" ]] || fail 'The replacement data partition did not appear.'
  if [[ "$fs" == 'ext4' ]]; then sudo -n mkfs.ext4 -F "$target_part"; else sudo -n mkfs.xfs -f "$target_part"; fi
  sudo -n mkdir -p /mnt/prodicloud-source /mnt/prodicloud-target
  if [[ "$fs" == 'ext4' ]]; then sudo -n mount -o ro,noload "$source_part" /mnt/prodicloud-source; else sudo -n mount -o ro,norecovery "$source_part" /mnt/prodicloud-source; fi
  sudo -n mount "$target_part" /mnt/prodicloud-target
  source_disk_bytes="$(sudo -n blockdev --getsize64 "$source_disk")"
  target_disk_bytes="$(sudo -n blockdev --getsize64 "$target_disk")"
  read -r source_volume_bytes source_used_bytes source_free_bytes <<< "$(df_usage /mnt/prodicloud-source)"
  [[ "$source_disk_bytes" =~ ^[0-9]+$ && "$target_disk_bytes" =~ ^[0-9]+$ && "$source_used_bytes" =~ ^[0-9]+$ && "$source_free_bytes" =~ ^[0-9]+$ ]] || fail 'Could not remeasure source or candidate data-disk capacity.'
  source_delta_bytes=$((source_used_bytes - EXPECTED_SOURCE_USED_BYTES))
  (( source_used_bytes + MINIMUM_FREE_BYTES <= target_disk_bytes )) || fail "Source-clone remeasurement exceeds candidate capacity before copy: source used=$source_used_bytes bytes; candidate=$target_disk_bytes bytes; required headroom=$MINIMUM_FREE_BYTES bytes."
  command -v rsync >/dev/null 2>&1 || fail 'The helper image does not contain rsync; no target data was changed.'
  sudo -n rsync -aAXH --numeric-ids --delete /mnt/prodicloud-source/ /mnt/prodicloud-target/
  read -r replacement_volume_bytes replacement_used_bytes replacement_free_bytes <<< "$(df_usage /mnt/prodicloud-target)"
  [[ "$replacement_volume_bytes" =~ ^[0-9]+$ && "$replacement_used_bytes" =~ ^[0-9]+$ && "$replacement_free_bytes" =~ ^[0-9]+$ ]] || fail 'Could not verify the copied candidate data volume.'
  (( replacement_used_bytes + MINIMUM_FREE_BYTES <= target_disk_bytes && replacement_free_bytes >= MINIMUM_FREE_BYTES )) || fail "Replacement data disk failed the pre-cutover free-space check: used=$replacement_used_bytes bytes; free=$replacement_free_bytes bytes; disk=$target_disk_bytes bytes; required=$MINIMUM_FREE_BYTES bytes."
  sudo -n sync
  sudo -n umount /mnt/prodicloud-target
  sudo -n umount /mnt/prodicloud-source
  if [[ "$fs" == 'ext4' ]]; then sudo -n tune2fs -U "$old_uuid" "$target_part" >/dev/null; else sudo -n xfs_admin -U "$old_uuid" "$target_part" >/dev/null; fi
  sudo -n blockdev --flushbufs "$target_disk"
  target_bytes="$(sudo -n blockdev --getsize64 "$target_disk")"
  printf 'PRODICLOUD_RESIZE_RESULT:{"status":"ok","kind":"data","fileSystem":"%s","uuid":"%s","usedBytes":%s,"sourceUsedBytes":%s,"sourceFreeBytes":%s,"expectedSourceUsedBytes":%s,"sourceMeasurementDeltaBytes":%s,"replacementUsedBytes":%s,"replacementFreeBytes":%s,"replacementSizeBytes":%s,"replacementVolumeSizeBytes":%s,"minimumFreeBytes":%s}\n' "$fs" "$old_uuid" "$source_used_bytes" "$source_used_bytes" "$source_free_bytes" "$EXPECTED_SOURCE_USED_BYTES" "$source_delta_bytes" "$replacement_used_bytes" "$replacement_free_bytes" "$target_bytes" "$replacement_volume_bytes" "$MINIMUM_FREE_BYTES"
  exit 0
fi

[[ "$KIND" == 'os' ]] || fail "Unsupported Linux disk kind '$KIND'."
[[ ${#source_parts[@]} -eq 2 && ${#target_parts[@]} -eq 0 ]] || fail 'Linux OS shrink currently supports only a two-partition GPT UEFI disk (EFI plus root).'
partition_style="$(sudo -n parted -sm "$source_disk" print 2>/dev/null | awk -F: 'NR == 2 {print $6}')"
[[ "$partition_style" == 'gpt' ]] || fail "Linux OS shrink requires GPT; source partition style is '$partition_style'."
sudo -n lsblk -n -o FSTYPE "$source_disk" | grep -qi 'LVM2_member' && fail 'LVM OS disks are not in the supported shrink set.'
efi_source=''
root_source=''
for part in "${source_parts[@]}"; do
  fs="$(sudo -n blkid -o value -s TYPE "$part" || true)"
  if [[ "$fs" == 'vfat' ]]; then efi_source="$part"; elif [[ "$fs" == 'ext4' ]]; then root_source="$part"; else fail "Unsupported Linux OS disk partition filesystem '$fs'."; fi
done
[[ -n "$efi_source" && -n "$root_source" ]] || fail 'The Linux OS disk must contain one FAT EFI partition and one ext4 root partition.'
efi_bytes="$(sudo -n blockdev --getsize64 "$efi_source")"
old_root_uuid="$(sudo -n blkid -o value -s UUID "$root_source")"
old_efi_uuid="$(sudo -n blkid -o value -s UUID "$efi_source")"
target_bytes="$(sudo -n blockdev --getsize64 "$target_disk")"
efi_mib=$(( (efi_bytes + 1048575) / 1048576 ))
root_start_mib=$((efi_mib + 2))
[[ $target_bytes -gt $(( (root_start_mib + 1) * 1048576 )) ]] || fail 'The replacement disk cannot contain the EFI and root partitions.'
sudo -n parted -s "$target_disk" mklabel gpt
sudo -n parted -s "$target_disk" mkpart ESP fat32 1MiB "${efi_mib}MiB"
sudo -n parted -s "$target_disk" set 1 esp on
sudo -n parted -s "$target_disk" mkpart primary ext4 "${root_start_mib}MiB" 100%
sudo -n partprobe "$target_disk"
sudo -n udevadm settle --timeout=5 || true
wait_for_partition_count "$target_disk" 2
target_parts=( $(partitions "$target_disk") )
[[ ${#target_parts[@]} -eq 2 ]] || fail 'The replacement OS disk partition layout did not verify.'
efi_target="${target_parts[0]}"
root_target="${target_parts[1]}"
sudo -n mkfs.vfat -F 32 "$efi_target"
sudo -n mkfs.ext4 -F "$root_target"
sudo -n mkdir -p /mnt/prodicloud-source /mnt/prodicloud-source-efi /mnt/prodicloud-target /mnt/prodicloud-target/boot/efi
sudo -n mount -o ro,noload "$root_source" /mnt/prodicloud-source
sudo -n mount -o ro "$efi_source" /mnt/prodicloud-source-efi
sudo -n mount "$root_target" /mnt/prodicloud-target
sudo -n mount "$efi_target" /mnt/prodicloud-target/boot/efi
read -r source_root_volume_bytes source_root_used_bytes source_root_free_bytes <<< "$(df_usage /mnt/prodicloud-source)"
read -r source_efi_volume_bytes source_efi_used_bytes source_efi_free_bytes <<< "$(df_usage /mnt/prodicloud-source-efi)"
source_used_bytes=$((source_root_used_bytes + source_efi_used_bytes))
source_free_bytes=$((source_root_free_bytes + source_efi_free_bytes))
source_delta_bytes=$((source_used_bytes - EXPECTED_SOURCE_USED_BYTES))
(( source_used_bytes + MINIMUM_FREE_BYTES <= target_bytes )) || fail "Source-clone remeasurement exceeds candidate capacity before copy: source used=$source_used_bytes bytes; candidate=$target_bytes bytes; required headroom=$MINIMUM_FREE_BYTES bytes."
command -v rsync >/dev/null 2>&1 || fail 'The helper image does not contain rsync; no target disk was attached to the VC.'
sudo -n rsync -aAXH --numeric-ids --delete --exclude=/dev/* --exclude=/proc/* --exclude=/sys/* --exclude=/run/* --exclude=/tmp/* --exclude=/mnt/* --exclude=/media/* --exclude=/lost+found /mnt/prodicloud-source/ /mnt/prodicloud-target/
sudo -n rsync -a --delete /mnt/prodicloud-source-efi/ /mnt/prodicloud-target/boot/efi/
new_root_uuid="$(sudo -n blkid -o value -s UUID "$root_target")"
new_efi_uuid="$(sudo -n blkid -o value -s UUID "$efi_target")"
sudo -n sed -i "s/${old_root_uuid}/${new_root_uuid}/g; s/${old_efi_uuid}/${new_efi_uuid}/g" /mnt/prodicloud-target/etc/fstab
for mount in dev dev/pts proc sys run; do sudo -n mount --bind "/$mount" "/mnt/prodicloud-target/$mount"; done
sudo -n chroot /mnt/prodicloud-target /bin/bash -lc 'command -v grub-install >/dev/null && grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --removable --no-nvram && update-grub'
read -r replacement_root_volume_bytes replacement_root_used_bytes replacement_root_free_bytes <<< "$(df_usage /mnt/prodicloud-target)"
read -r replacement_efi_volume_bytes replacement_efi_used_bytes replacement_efi_free_bytes <<< "$(df_usage /mnt/prodicloud-target/boot/efi)"
replacement_used_bytes=$((replacement_root_used_bytes + replacement_efi_used_bytes))
replacement_free_bytes=$((replacement_root_free_bytes + replacement_efi_free_bytes))
(( replacement_used_bytes + MINIMUM_FREE_BYTES <= target_bytes && replacement_free_bytes >= MINIMUM_FREE_BYTES )) || fail "Replacement OS disk failed the pre-cutover free-space check: used=$replacement_used_bytes bytes; free=$replacement_free_bytes bytes; disk=$target_bytes bytes; required=$MINIMUM_FREE_BYTES bytes."
for mount in run sys proc dev/pts dev; do sudo -n umount "/mnt/prodicloud-target/$mount"; done
sudo -n umount /mnt/prodicloud-target/boot/efi
sudo -n umount /mnt/prodicloud-target
sudo -n umount /mnt/prodicloud-source-efi
sudo -n umount /mnt/prodicloud-source
sudo -n sync
sudo -n blockdev --flushbufs "$target_disk"
root_size="$(sudo -n blockdev --getsize64 "$root_target")"
printf 'PRODICLOUD_RESIZE_RESULT:{"status":"ok","kind":"os","fileSystem":"ext4","rootUuid":"%s","efiUuid":"%s","usedBytes":%s,"sourceUsedBytes":%s,"sourceFreeBytes":%s,"expectedSourceUsedBytes":%s,"sourceMeasurementDeltaBytes":%s,"replacementUsedBytes":%s,"replacementFreeBytes":%s,"replacementSizeBytes":%s,"replacementVolumeSizeBytes":%s,"minimumFreeBytes":%s}\n' "$new_root_uuid" "$new_efi_uuid" "$source_used_bytes" "$source_used_bytes" "$source_free_bytes" "$EXPECTED_SOURCE_USED_BYTES" "$source_delta_bytes" "$replacement_used_bytes" "$replacement_free_bytes" "$target_bytes" "$root_size" "$MINIMUM_FREE_BYTES"
