#!/usr/bin/env bash
set -euo pipefail

ACTION='__PRODICLOUD_RESIZE_ACTION__'
KIND='__PRODICLOUD_RESIZE_KIND__'
LUN='__PRODICLOUD_RESIZE_LUN__'

fail() { echo "Resize guest operation failed: $*" >&2; exit 1; }
result() {
  local payload="$1"
  printf 'PRODICLOUD_RESIZE_RESULT:%s\n' "$payload"
}
resolve_disk() {
  if [[ "$KIND" == "os" ]]; then
    local root_part parent
    root_part="$(readlink -f "$(findmnt -n -o SOURCE /)")"
    parent="$(lsblk -n -o PKNAME "$root_part" | head -n 1 | tr -d ' ')"
    [[ -n "$parent" ]] || fail 'Could not resolve the parent disk for the root filesystem.'
    printf '/dev/%s\n' "$parent"
    return
  fi
  local path="/dev/disk/azure/scsi1/lun${LUN}"
  [[ -e "$path" ]] || fail "Azure data disk LUN ${LUN} was not found at ${path}."
  readlink -f "$path"
}
disk="$(resolve_disk)"
[[ -b "$disk" ]] || fail "Resolved device '$disk' is not a block device."
bytes="$(sudo -n blockdev --getsize64 "$disk")"
[[ "$bytes" =~ ^[0-9]+$ ]] || fail "Could not read capacity for '$disk'."
json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  printf '%s' "$value"
}
pair_value() {
  local record="$1" key="$2" value
  value="${record#*${key}=\"}"
  value="${value%%\"*}"
  printf '%s' "$value"
}
resolve_partition_mountpoint() {
  local partition="$1" resolved_source resolved_partition mountpoint
  resolved_partition="$(readlink -f "$partition" 2>/dev/null || printf '%s' "$partition")"
  while read -r resolved_source mountpoint; do
    [[ -n "$resolved_source" && -n "$mountpoint" ]] || continue
    resolved_source="$(readlink -f "$resolved_source" 2>/dev/null || printf '%s' "$resolved_source")"
    if [[ "$resolved_source" == "$resolved_partition" ]]; then printf '%s\n' "$mountpoint"; return 0; fi
  done < <(findmnt -rn -o SOURCE,TARGET)
  return 0
}
used_bytes=0
free_bytes=0
volume_size_bytes=0
filesystem_bytes=0
filesystem=""
mountpoint="/"
if [[ "$KIND" != "os" ]]; then mountpoint=""; fi
partitioned_bytes=0
nonfilesystem_partition_bytes=0
partition_count=0
partition_details='['
volume_details='['
first_partition=true
first_volume=true
while IFS= read -r partition_record; do
  partition_type="$(pair_value "$partition_record" TYPE)"
  [[ "$partition_type" == 'part' ]] || continue
  partition_name="$(pair_value "$partition_record" NAME)"
  partition_filesystem="$(pair_value "$partition_record" FSTYPE)"
  partition_size="$(pair_value "$partition_record" SIZE)"
  [[ "$partition_size" =~ ^[0-9]+$ ]] || fail "Could not read the byte size for partition '$partition_name'."
  partition_count=$((partition_count + 1))
  partitioned_bytes=$((partitioned_bytes + partition_size))
  partition_mountpoint="$(resolve_partition_mountpoint "$partition_name")"
  partition_used=0
  partition_free=0
  volume_size=0
  if [[ -z "$partition_filesystem" ]]; then
    nonfilesystem_partition_bytes=$((nonfilesystem_partition_bytes + partition_size))
  fi
  if [[ -n "$partition_mountpoint" ]]; then
    read -r volume_size partition_used partition_free < <(df -B1 --output=size,used,avail -- "$partition_mountpoint" | tail -n 1)
    [[ "$volume_size" =~ ^[0-9]+$ && "$partition_used" =~ ^[0-9]+$ && "$partition_free" =~ ^[0-9]+$ ]] || fail "Could not measure mounted partition '$partition_name'."
    if [[ -z "$mountpoint" ]]; then mountpoint="$partition_mountpoint"; fi
    used_bytes=$((used_bytes + partition_used))
    free_bytes=$((free_bytes + partition_free))
    volume_size_bytes=$((volume_size_bytes + volume_size))
    if [[ "$partition_mountpoint" == "$mountpoint" ]]; then
      filesystem_bytes="$volume_size"
      filesystem="$(findmnt -n -o FSTYPE --target "$partition_mountpoint")"
    fi
  fi
  if [[ "$first_partition" == false ]]; then partition_details+=','; fi
  first_partition=false
  escaped_name="$(json_escape "$partition_name")"
  escaped_fs="$(json_escape "$partition_filesystem")"
  escaped_mountpoint="$(json_escape "$partition_mountpoint")"
  partition_details+="{\"number\":$partition_count,\"device\":\"$escaped_name\",\"fileSystem\":\"$escaped_fs\",\"mountPoint\":\"$escaped_mountpoint\",\"partitionSizeBytes\":$partition_size,\"volumeSizeBytes\":$volume_size,\"usedBytes\":$partition_used,\"freeBytes\":$partition_free}"
  if [[ -n "$partition_filesystem" ]]; then
    if [[ "$first_volume" == false ]]; then volume_details+=','; fi
    first_volume=false
    volume_details+="{\"partitionNumber\":$partition_count,\"device\":\"$escaped_name\",\"fileSystem\":\"$escaped_fs\",\"mountPoint\":\"$escaped_mountpoint\",\"sizeBytes\":$volume_size,\"usedBytes\":$partition_used,\"freeBytes\":$partition_free}"
  fi
done < <(sudo -n lsblk -b -n -p -r -P -o NAME,TYPE,FSTYPE,SIZE "$disk")
partition_details+=']'
volume_details+=']'
[[ -n "$mountpoint" && "$filesystem_bytes" =~ ^[0-9]+$ ]] || fail 'Could not measure the selected guest filesystem.'
unallocated_bytes=$((bytes - partitioned_bytes))
if (( unallocated_bytes < 0 )); then unallocated_bytes=0; fi

if [[ "$ACTION" == "inspect" ]]; then
  shrink_capable=false
  partition_style="$(sudo -n parted -sm "$disk" print 2>/dev/null | awk -F: 'NR == 2 {print $6}')"
  lvm=false
  if sudo -n lsblk -n -o FSTYPE "$disk" | grep -qi 'LVM2_member'; then lvm=true; fi
  expand_capable=false
  if [[ ( "$filesystem" == "ext4" || "$filesystem" == "xfs" ) && "$lvm" == false ]] && command -v growpart >/dev/null 2>&1; then expand_capable=true; fi
  uuid=""
  root_part="$(readlink -f "$(findmnt -n -o SOURCE --target "$mountpoint" 2>/dev/null || true)")"
  if [[ -b "$root_part" ]]; then uuid="$(sudo -n blkid -o value -s UUID "$root_part" 2>/dev/null || true)"; fi
  if [[ "$KIND" == "os" && "$filesystem" == "ext4" && "$partition_style" == "gpt" && "$partition_count" -eq 2 && "$lvm" == false ]]; then shrink_capable=true; fi
  if [[ "$KIND" == "data" && ( "$filesystem" == "ext4" || "$filesystem" == "xfs" ) && "$partition_count" -eq 1 && "$lvm" == false ]]; then shrink_capable=true; fi
  printf 'PRODICLOUD_RESIZE_RESULT:{"status":"ok","action":"inspect","kind":"%s","diskSizeBytes":%s,"usedBytes":%s,"freeBytes":%s,"volumeSizeBytes":%s,"partitionedBytes":%s,"unallocatedBytes":%s,"nonFilesystemPartitionBytes":%s,"filesystemSizeBytes":%s,"fileSystem":"%s","volumes":%s,"partitions":%s,"uuid":"%s","partitionStyle":"%s","partitionCount":%s,"lvm":%s,"shrinkCapable":%s,"expandCapable":%s}\n' "$KIND" "$bytes" "$used_bytes" "$free_bytes" "$volume_size_bytes" "$partitioned_bytes" "$unallocated_bytes" "$nonfilesystem_partition_bytes" "$filesystem_bytes" "$filesystem" "$volume_details" "$partition_details" "$uuid" "$partition_style" "$partition_count" "$lvm" "$shrink_capable" "$expand_capable"
  exit 0
fi

if [[ "$ACTION" == "expand" ]]; then
  [[ "$filesystem" == "ext4" || "$filesystem" == "xfs" ]] || fail "Unsupported Linux filesystem '$filesystem' for automatic expansion."
  command -v growpart >/dev/null 2>&1 || fail 'growpart is not installed; automatic Linux expansion is unavailable.'
  minimum_expanded_bytes=$(( bytes > 2147483648 ? bytes - 2147483648 : 0 ))
  if (( filesystem_bytes >= minimum_expanded_bytes )); then
    printf 'PRODICLOUD_RESIZE_RESULT:{"status":"ok","action":"expand","kind":"%s","filesystem":"%s","filesystemSizeBytes":%s,"alreadyExpanded":true}\n' "$KIND" "$filesystem" "$filesystem_bytes"
    exit 0
  fi
  partition="$(findmnt -n -o SOURCE --target "$mountpoint" | readlink -f)"
  [[ -b "$partition" ]] || fail 'Could not resolve the mounted partition.'
  part_number="$(lsblk -n -o PARTN "$partition" | tr -d ' ')"
  [[ "$part_number" =~ ^[0-9]+$ ]] || fail 'Could not resolve the partition number.'
  printf 'PRODICLOUD_RESIZE_PHASE:{"phase":"grow-partition","partition":%s,"diskBytes":%s,"filesystemBytes":%s}\n' "$part_number" "$bytes" "$filesystem_bytes"
  sudo -n growpart "$disk" "$part_number" || fail 'growpart could not extend the selected partition.'
  sudo -n udevadm settle --timeout=5 || true
  if [[ "$filesystem" == "ext4" ]]; then sudo -n resize2fs "$partition" || fail 'resize2fs failed.'; else sudo -n xfs_growfs "$mountpoint" || fail 'xfs_growfs failed.'; fi
  last_report=0
  new_bytes=0
  for attempt in $(seq 1 12); do
    new_bytes="$(df -B1 --output=size "$mountpoint" | tail -n 1 | tr -d ' ')"
    [[ "$new_bytes" =~ ^[0-9]+$ ]] || fail 'Could not read the Linux filesystem size after expansion.'
    if (( new_bytes >= minimum_expanded_bytes )); then
      printf 'PRODICLOUD_RESIZE_RESULT:{"status":"ok","action":"expand","kind":"%s","filesystem":"%s","filesystemSizeBytes":%s,"alreadyExpanded":false}\n' "$KIND" "$filesystem" "$new_bytes"
      exit 0
    fi
    elapsed=$((attempt * 5))
    if (( elapsed - last_report >= 30 )); then
      last_report=$elapsed
      printf 'PRODICLOUD_RESIZE_PHASE:{"phase":"wait-for-filesystem-capacity","elapsedSeconds":%s,"timeoutSeconds":60,"filesystemBytes":%s,"expectedMinimumBytes":%s}\n' "$elapsed" "$new_bytes" "$minimum_expanded_bytes"
    fi
    sleep 5
  done
  fail "Linux filesystem remained at ${new_bytes} bytes after 60 seconds of five-second capacity checks; expected at least ${minimum_expanded_bytes} bytes."
fi

fail "Unsupported Linux guest resize action '$ACTION'."
