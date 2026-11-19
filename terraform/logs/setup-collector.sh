#!/usr/bin/env bash
# Configures the log collector VM (ADR-005). Safe to re-run.
# Usage: ./setup-collector.sh <vm-ip>
# Needs Keychain items technitium-logs and proxmox-logs, and root ssh to 192.168.10.9.
set -euo pipefail
vm=${1:?vm ip}
pve=192.168.10.9
ssh_opts=(-o IdentityAgent="${SSH_AUTH_SOCK}")

dns_token=$(security find-generic-password -s technitium-logs -w)
pve_token=$(security find-generic-password -s proxmox-logs -w)

# Secrets and the cluster CA go over stdin, never on a command line.
printf 'DNS_TOKEN=%s\nPVE_TOKEN=%s\n' "$dns_token" "$pve_token" |
  ssh "${ssh_opts[@]}" "debian@$vm" 'sudo sh -c "umask 077; mkdir -p /etc/logs-backup; cat > /etc/logs-backup/env"'
ssh "${ssh_opts[@]}" "root@$pve" cat /etc/pve/pve-root-ca.pem |
  ssh "${ssh_opts[@]}" "debian@$vm" 'sudo tee /etc/logs-backup/pve-ca.pem >/dev/null'
unset dns_token pve_token

ssh "${ssh_opts[@]}" "debian@$vm" sudo bash -s <<'REMOTE'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# Match the Proxmox nodes, so 03:15 lands after dns-nightly and day files split at local midnight.
timedatectl set-timezone America/Los_Angeles
apt-get update -q
apt-get install -yq rsyslog nfs-common rsync curl jq

cat > /etc/rsyslog.d/10-remote.conf <<'EOF'
# Router syslog (UniFi SIEM) on UDP 514: one file per sender per day, kept out of /var/log/syslog.
# secpath-replace stops a spoofed hostname from writing outside /var/log/remote.
template(name="remoteDaily" type="string" string="/var/log/remote/%HOSTNAME:::secpath-replace%/%$now%.log")
# UniFi stamps the header with UTC digits but a -08:00 offset; use our receive time. UNIFIutcTime stays in the message.
template(name="received" type="string" string="%timegenerated:::date-rfc3339% %HOSTNAME% %syslogtag%%msg%\n")
ruleset(name="remote") {
  # Only the router (its Lab-VMs address); anyone else on the VLAN could fill the disk.
  if $fromhost-ip == "192.168.20.1" then {
    action(type="omfile" dynaFile="remoteDaily" template="received" dirCreateMode="0750" fileCreateMode="0640")
  }
  stop
}
module(load="imudp")
input(type="imudp" port="514" ruleset="remote")
EOF
systemctl restart rsyslog

mkdir -p /mnt/nas
grep -q ' /mnt/nas ' /etc/fstab ||
  echo '192.168.10.5:/volume1/lab-logs /mnt/nas nfs noauto,_netdev,x-systemd.automount,x-systemd.idle-timeout=10min 0 0' >> /etc/fstab
systemctl daemon-reload
systemctl start mnt-nas.automount   # otherwise it only arms at the next boot

cat > /usr/local/sbin/logs-nightly <<'EOF'
#!/usr/bin/env bash
# Pulls DNS and Proxmox logs for any missing day of the last week, ships router syslog, prunes. See ADR-005.
set -uo pipefail
. /etc/logs-backup/env
nas=/mnt/nas
today=$(date +%F)
fail=0
declare -A dns=([dns1]=192.168.20.2 [dns2]=192.168.20.3)

# Touch the automount; refuse to run if the share isn't really there, or logs would pile up on local disk.
ls "$nas" >/dev/null 2>&1
findmnt -t nfs,nfs4 "$nas" >/dev/null || { echo "snorlax not mounted at $nas" >&2; exit 1; }
mkdir -p "$nas/dns" "$nas/proxmox" "$nas/syslog"

# save <dest> <cmd...>: gzip the command's output to dest; leave nothing behind on failure.
save() {
  local dest=$1; shift
  mkdir -p "${dest%/*}" && "$@" | gzip > "$dest.tmp" && mv "$dest.tmp" "$dest" ||
    { rm -f "$dest.tmp"; echo "failed: $dest" >&2; fail=1; }
}

# get <url> [header]: URL and header go to curl through a config pipe, so tokens never show in ps.
# The Proxmox cert names the node, not its IP, hence --resolve.
get() {
  curl -fsS --compressed --connect-timeout 10 --max-time 600 \
    --cacert /etc/logs-backup/pve-ca.pem --resolve articuno:8006:192.168.10.9 \
    -K <(printf 'url = "%s"\n' "$1"; [[ -z ${2:-} ]] || printf 'header = "%s"\n' "$2")
}

pve_journal() {
  get "https://articuno:8006/api2/json/nodes/$1/journal?since=$2&until=$3" \
    "Authorization: PVEAPIToken=logs@pve!collector=$PVE_TOKEN" |
    jq -r '.data[1:-1][]'   # first and last entries are journal cursors
}

# Technitium: every finished day file it still holds (it keeps 7).
for name in "${!dns[@]}"; do
  api="http://${dns[$name]}:5380/api/logs"
  days=$(get "$api/list?token=$DNS_TOKEN" |
    jq -r 'if .status == "ok" then .response.logFiles[].fileName else error(.errorMessage // "api error") end') ||
    { echo "failed: $name log list" >&2; fail=1; continue; }
  for day in $days; do
    [[ $day < $today ]] || continue
    f=$nas/dns/$name/$day.log.gz
    [[ -e $f ]] || save "$f" get "$api/download?token=$DNS_TOKEN&fileName=$day"
  done
done

# Proxmox: one file per node per day, for any missing day of the last week.
for node in moltres zapdos articuno; do
  for i in 1 2 3 4 5 6 7; do
    day=$(date -d "$i days ago" +%F)
    f=$nas/proxmox/$node/$day.log.gz
    [[ -e $f ]] || save "$f" pve_journal "$node" "$(date -d "$day" +%s)" "$(($(date -d "$day + 1 day" +%s) - 1))"
  done
done

# Router syslog: compress finished days and move them; on failure they wait here for tomorrow.
find /var/log/remote -name '*.log' ! -name "$today.log" -exec gzip -f {} +
rsync -a --remove-source-files --include='*/' --include='*.gz' --exclude='*' /var/log/remote/ "$nas/syslog/" ||
  { echo "failed: syslog rsync" >&2; fail=1; }

# Retention: 365 days for syslog and Proxmox (matches CloudTrail), 90 for DNS queries.
find "$nas/syslog" "$nas/proxmox" -name '*.gz' -mtime +365 -delete
find "$nas/dns" -name '*.gz' -mtime +90 -delete

exit $fail
EOF
chmod 755 /usr/local/sbin/logs-nightly

cat > /etc/systemd/system/logs-nightly.service <<'EOF'
[Unit]
Description=Ship lab logs to snorlax
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/logs-nightly
EOF

cat > /etc/systemd/system/logs-nightly.timer <<'EOF'
[Unit]
Description=Ship lab logs to snorlax nightly, after dns-nightly

[Timer]
OnCalendar=*-*-* 03:15
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now logs-nightly.timer
echo "$(hostname): collector ready"
REMOTE
