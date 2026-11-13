#!/bin/sh
# gpuscale.sh <ENVSTRING> <freq...> : scroll continuously at fixed GPU frequencies; print fps and GPU job times
E=$(echo "$1" | tr '+' ' '); shift
G=/sys/class/devfreq/5000000.gpu; P0=/sys/devices/system/cpu/cpufreq/policy0; P1=/sys/devices/system/cpu/cpufreq/policy1; T=/sys/kernel/tracing
UENV="XDG_RUNTIME_DIR=/run/user/10000 WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/10000/bus"
reset() { echo 0 > $G/min_freq; echo 588000000 > $G/max_freq; echo simple_ondemand > $G/governor; echo schedutil > $P0/scaling_governor; echo schedutil > $P1/scaling_governor; }
GS="sudo -u user env $UENV gsettings"; IDLE=$($GS get org.gnome.desktop.session idle-delay); $GS set org.gnome.desktop.session idle-delay "uint32 0"
trap 'reset; $GS set org.gnome.desktop.session idle-delay "$IDLE"' EXIT
lock=$(sudo -u user env $UENV gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.GetActive 2>&1)
case "$lock" in *false*) ;; *) echo "screen is locked: stopping"; exit 1;; esac
echo performance > $P0/scaling_governor; echo performance > $P1/scaling_governor
EV="drm_msm_gpu/msm_gpu_submit drm_msm_gpu/msm_gpu_submit_retired dpu/dpu_crtc_complete_flip"
for F in "$@"; do
  echo 0 > $G/min_freq; echo 588000000 > $G/max_freq; echo ${F}000000 > $G/max_freq; echo ${F}000000 > $G/min_freq
  sudo -u user env $UENV $E timeout 60 python3 /tmp/bench.py 1 "gpu$F" 8 > /tmp/bench-out.txt 2>/dev/null &
  sleep 5
  echo 0 > $T/tracing_on; echo > $T/trace; for e in $EV; do echo 1 > $T/events/$e/enable; done
  echo 1 > $T/tracing_on; sleep 3; echo 0 > $T/tracing_on; cur=$(cat $G/cur_freq)
  for e in $EV; do echo 0 > $T/events/$e/enable; done
  cp $T/trace /tmp/trace3.txt; echo > $T/trace; echo 1 > $T/tracing_on
  wait
  APP=$(grep -m1 -o 'pid=[0-9]*' /tmp/trace3.txt >/dev/null; pgrep -x phoc | head -1)
  awk -v phoc=$APP '{ t=0; for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+:$/) { t=substr($i,1,length($i)-1)+0; break } }
    /msm_gpu_submit:/ { for(i=1;i<=NF;i++){ if($i~/^id=/)id=substr($i,4); if($i~/^pid=/)p=substr($i,5) } sub(/,/,"",id); sub(/,/,"",p); st[id]=t; pid[id]=p }
    /msm_gpu_submit_retired/ { for(i=1;i<=NF;i++) if($i~/^id=/)id=substr($i,4); if (id in st) { s=st[id]; if (last > s) s=last; d=(t-s)*1000; k=(pid[id]==phoc)?"phoc":"app"; n[k]++; sum[k]+=d; if (d>mx[k]) mx[k]=d; w=(t-st[id])*1000; ws[k]+=w } last=t }
    /dpu_crtc_complete_flip/ { fl++ }
    END { printf "   flips/s=%.1f | app jobs=%d gpu-time mean=%.1f max=%.1f ms (submit->retire %.1f) | phoc jobs=%d gpu-time mean=%.1f max=%.1f ms (submit->retire %.1f)\n", fl/3, n["app"], sum["app"]/n["app"], mx["app"], ws["app"]/n["app"], n["phoc"], sum["phoc"]/n["phoc"], mx["phoc"], ws["phoc"]/n["phoc"] }' /tmp/trace3.txt > /tmp/gs.txt
  echo "GPU ${F} MHz (cur_freq $cur): $(sed 's/.*"frames": \([0-9]*\).*"mean_ms": \([0-9.]*\).*"p95_ms": \([0-9.]*\).*/app frames=\1 mean=\2 ms p95=\3 ms/' /tmp/bench-out.txt)"; cat /tmp/gs.txt
done
