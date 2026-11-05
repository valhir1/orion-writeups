#!/usr/bin/env bash
VDIR=${VALIDATE_DIR}
LOGS=$VDIR/logs
PRIV=$VDIR/private
SER=$PRIV/serials.txt
TMPD=$LOGS/.tmp
mkdir -p "$LOGS" "$PRIV" "$TMPD"
(umask 077; : > "$SER"; chmod 600 "$SER")
: > "$LOGS/.exit_codes"

mask() {
  local f=$1
  awk -v L="$f" -v S="$SER" '
  {
    line=$0
    if (tolower(line) ~ /serial|uuid/) {
      i=index(line,":")
      if (i>0) {
        val=substr(line,i+1)
        gsub(/^[ \t]+|[ \t]+$/,"",val)
        if (val!="Not Specified" && val!="Unknown" && val!="N/A" && val!="None" && val!="To Be Filled By O.E.M." && val!="") {
          masked="****" substr(val,length(val)-3)
          out=substr(line,1,i) " " masked
          print out
          print L ": " line >> S
          next
        }
      }
    }
    print line
  }'
}

rc() { echo "$1 $2" >> "$LOGS/.exit_codes"; }

hdr() { echo "# CMD: $2"; echo "# DATE: $(date -Is)"; }

is_sudo_denied() {
  local t=$1
  [ -f "$t" ] || return 1
  head -n1 "$t" | grep -q '^sudo: '
}

run() {
  local f=$1; shift
  local cmd="$*"
  local t=$TMPD/$(basename "$f").tmp
  hdr "$f" "$cmd" > "$f"
  eval "$cmd" > "$t" 2>&1
  local r=$?
  if is_sudo_denied "$t"; then
    echo "NEEDS_SUDO: $cmd" >> "$f"; cat "$t" >> "$f"
  else
    cat "$t" | mask "$f" >> "$f"
  fi
  rc "$f" "$r"
  rm -f "$t"
}

cpu_temp() {
  local m=0 d n v
  for d in /sys/class/hwmon/hwmon*; do
    [ -d "$d" ] || continue
    n=$(cat "$d/name" 2>/dev/null)
    case "$n" in k10temp|coretemp)
      for f in "$d"/temp*_input; do
        [ -f "$f" ] || continue
        v=$(( $(cat "$f" 2>/dev/null) / 1000 ))
        [ "$v" -gt "$m" ] && m=$v
      done;;
  esac
  done
  echo "$m"
}

run "$LOGS/lscpu.log" "lscpu"
run "$LOGS/free.log" "free -h"
run "$LOGS/dmidecode-memory.log" "sudo -n dmidecode -t memory"
run "$LOGS/dmidecode-processor.log" "sudo -n dmidecode -t processor"
run "$LOGS/dmidecode-baseboard.log" "sudo -n dmidecode -t baseboard"

g=0
while IFS= read -r l; do
  a=$(echo "$l" | awk '{print $1}')
  echo "$l" | grep -qE 'VGA|3D controller' || continue
  f=$LOGS/lspci-gpu${g}.log
  t=$TMPD/lspci-gpu${g}.tmp
  hdr "$f" "lspci -vv -s $a" > "$f"
  lspci -vv -s "$a" > "$t" 2>&1
  r=$?
  if ! grep -q "LnkCap" "$t" 2>/dev/null; then
    sudo -n lspci -vv -s "$a" > "$t" 2>&1; r=$?
    if is_sudo_denied "$t"; then
      echo "NEEDS_SUDO: sudo -n lspci -vv -s $a" >> "$f"; cat "$t" >> "$f"
    else cat "$t" | mask "$f" >> "$f"; fi
  else cat "$t" | mask "$f" >> "$f"; fi
  lc=$(grep "LnkCap" "$t" 2>/dev/null | head -n1)
  ls=$(grep "LnkSta" "$t" 2>/dev/null | head -n1)
  [ -n "$lc" ] && echo "LNKCAP_SUMMARY: $lc" >> "$f"
  [ -n "$ls" ] && echo "LNKSTA_SUMMARY: $ls" >> "$f"
  rc "$f" "$r"; rm -f "$t"; g=$((g+1))
done < <(lspci -D -d 10de: 2>/dev/null)

if command -v nvidia-smi &>/dev/null; then
  run "$LOGS/nvidia-smi-q.log" "nvidia-smi -q"
  run "$LOGS/nvidia-smi-csv.log" "nvidia-smi --query-gpu=index,name,clocks.sm,clocks.mem,pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max,temperature.gpu,power.draw,memory.used,memory.total --format=csv"
else
  for f in nvidia-smi-q nvidia-smi-csv; do
    hdr "$LOGS/$f.log" "nvidia-smi" > "$LOGS/$f.log"
    echo "NOT_INSTALLED: nvidia-smi" >> "$LOGS/$f.log"
    rc "$LOGS/$f.log" 127
  done
fi

for dev in nvme0n1 nvme1n1 nvme2n1; do
  f=$LOGS/smart-${dev}.log
  hdr "$f" "sudo -n nvme smart-log /dev/${dev}; sudo -n smartctl -a /dev/${dev}" > "$f"
  r=0
  if command -v nvme &>/dev/null; then
    t=$TMPD/nvme-${dev}.tmp
    sudo -n nvme smart-log "/dev/$dev" > "$t" 2>&1; r=$?
    if is_sudo_denied "$t"; then
      echo "NEEDS_SUDO: sudo -n nvme smart-log /dev/$dev" >> "$f"; cat "$t" >> "$f"
    else cat "$t" | mask "$f" >> "$f"; fi
    rm -f "$t"
  else echo "NOT_INSTALLED: nvme" >> "$f"; fi
  if command -v smartctl &>/dev/null; then
    t=$TMPD/smart-${dev}.tmp
    sudo -n smartctl -a "/dev/$dev" > "$t" 2>&1; r2=$?
    if is_sudo_denied "$t"; then
      echo "NEEDS_SUDO: sudo -n smartctl -a /dev/$dev" >> "$f"; cat "$t" >> "$f"
    else cat "$t" | mask "$f" >> "$f"; fi
    rm -f "$t"
    [ "$r2" -ne 0 ] && r=$r2
  else echo "NOT_INSTALLED: smartctl" >> "$f"; fi
  { echo "--- sysfs evidence ---"
    echo "model: $(cat /sys/block/${dev}/device/model 2>/dev/null || echo N/A)"
    echo "firmware_rev: $(cat /sys/block/${dev}/device/firmware_rev 2>/dev/null || echo N/A)"
    echo "size_sectors: $(cat /sys/block/${dev}/size 2>/dev/null || echo N/A)"
  } >> "$f"
  rc "$f" "$r"
done

if command -v sensors &>/dev/null; then
  run "$LOGS/sensors.log" "sensors"
else
  hdr "$LOGS/sensors.log" "sensors" > "$LOGS/sensors.log"
  echo "NOT_INSTALLED: sensors" >> "$LOGS/sensors.log"
  rc "$LOGS/sensors.log" 127
fi

hdr "$LOGS/hwmon.log" "cat /sys/class/hwmon/hwmon*/name + temp*_input + temp*_label" > "$LOGS/hwmon.log"
for d in /sys/class/hwmon/hwmon*; do
  [ -d "$d" ] || continue
  echo "hwmon: $(cat "$d/name" 2>/dev/null)" >> "$LOGS/hwmon.log"
  for tf in "$d"/temp*_input; do
    [ -f "$tf" ] || continue
    echo "  $(cat "${tf%_input}_label" 2>/dev/null || echo unknown): $(cat "$tf" 2>/dev/null)" >> "$LOGS/hwmon.log"
  done
done
rc "$LOGS/hwmon.log" 0

f=$LOGS/edac.log
hdr "$f" "edac-util --report=full OR dmesg | grep -iE 'edac|ecc|mce'" > "$f"
r=0
denied=0
if command -v edac-util &>/dev/null; then
  edac-util --report=full >> "$f" 2>&1; r=$?
else
  t=$TMPD/edac-dmesg.tmp
  dmesg > "$t" 2>&1; r=$?
  if [ $r -ne 0 ]; then
    sudo -n dmesg > "$t" 2>&1; r=$?
    if is_sudo_denied "$t"; then
      denied=1
    fi
  fi
  if [ $denied -eq 1 ]; then
    echo "NEEDS_SUDO: sudo -n dmesg" >> "$f"
    cat "$t" >> "$f"
  else
    if grep -qiE 'edac|ecc|mce' "$t"; then
      grep -iE 'edac|ecc|mce' "$t" >> "$f"
    else
      echo "NO_MATCHES: edac|ecc|mce" >> "$f"
    fi
  fi
  rm -f "$t"
fi
for mc in /sys/devices/system/edac/mc/mc*; do
  [ -d "$mc" ] || continue
  echo "EDAC sysfs: $mc ce_count=$(cat "$mc/ce_count" 2>/dev/null || echo N/A) ue_count=$(cat "$mc/ue_count" 2>/dev/null || echo N/A)" >> "$f"
done
rc "$f" "$r"

if [ -f /proc/mdstat ]; then
  run "$LOGS/mdstat.log" "cat /proc/mdstat"
else
  hdr "$LOGS/mdstat.log" "cat /proc/mdstat" > "$LOGS/mdstat.log"
  echo "NOT_PRESENT: /proc/mdstat" >> "$LOGS/mdstat.log"
  rc "$LOGS/mdstat.log" 0
fi

run "$LOGS/uptime.log" "uptime"

f=$LOGS/cpu-stress.log
hdr "$f" "CPU stress test (stress-ng or python3)" > "$f"
tb=$(cpu_temp)
echo "TEMP_BEFORE_C: $tb" >> "$f"
if command -v stress-ng &>/dev/null; then
  stress-ng --cpu 0 --timeout 60 --metrics-brief >> "$f" 2>&1; r=$?
  ta=$(cpu_temp)
  echo "TEMP_AFTER_C: $ta" >> "$f"
else
  if command -v python3 &>/dev/null; then
    python3 - <<'PY' >> "$f" 2>&1
import multiprocessing, time, os
def w():
    c=0; e=time.time()+60
    while time.time()<e: c+=1
    return c
if __name__=="__main__":
    n=multiprocessing.cpu_count()
    p=multiprocessing.Pool(n)
    rs=[p.apply_async(w) for _ in range(n)]
    temps=[]
    for _ in range(12):
        time.sleep(5)
        mt=0
        for d in os.listdir('/sys/class/hwmon'):
            pa=f'/sys/class/hwmon/{d}'
            try: nm=open(f'{pa}/name').read().strip()
            except: continue
            if nm in ('k10temp','coretemp'):
                for tf in os.listdir(pa):
                    if tf.startswith('temp') and tf.endswith('_input'):
                        try: v=int(open(f'{pa}/{tf}').read())//1000
                        except: continue
                        if v>mt: mt=v
        temps.append(mt)
    tot=0
    for x in rs: tot+=x.get()
    p.close(); p.join()
    print(f"PY_STRESS_ITERATIONS_TOTAL: {tot}")
    print(f"PY_STRESS_WORKERS: {n}")
    print(f"PY_STRESS_EXIT: 0")
    if temps: print(f"TEMP_MAX_DURING_C: {max(temps)}")
PY
    r=$?
  else
    echo "NOT_INSTALLED: stress-ng and python3" >> "$f"; r=127
  fi
  ta=$(cpu_temp)
  echo "TEMP_AFTER_C: $ta" >> "$f"
fi
rc "$f" "$r"

if command -v memtester &>/dev/null; then
  run "$LOGS/memtester.log" "memtester 1G 1"
else
  hdr "$LOGS/memtester.log" "memtester 1G 1" > "$LOGS/memtester.log"
  echo "NOT_INSTALLED: memtester (skipped)" >> "$LOGS/memtester.log"
  rc "$LOGS/memtester.log" 127
fi

{
  echo "# CMD: collect-summary"
  echo "# DATE: $(date -Is)"
  while IFS=' ' read -r lf lr; do
    echo "$lf exit=$lr"
  done < "$LOGS/.exit_codes"
} > "$LOGS/collect-summary.log"

rm -rf "$TMPD"
