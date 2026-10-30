#!/bin/bash
# Smoke test of one built image in the container shape that Wings uses: read-only root, no-new-privileges, the
# Wings cap drops, /tmp as a 100M tmpfs, a non-root uid and the volume at /home/container.
# usage: test/smoke.sh <image> <java -version text> [crac]
# Checks: tini is PID 1, tini and entrypoint.sh hashes, java -version, STARTUP eval with "{{VAR}}" and the
# "$( [[ ! -f unix_args.txt ]] ... )" form, /opt/java/openjdk, en_US.UTF-8, libnuma.
# With "crac": a warp checkpoint and a warp restore of test/Crac.java.
set -u
IMAGE=$1 EXPECT=$2 CRAC=${3:-}
cd "$(dirname "$0")" || exit 1
VOL=$PWD/../.smoke/$(echo "$IMAGE" | tr -c 'A-Za-z0-9._-' _)
rm -rf "$VOL" && mkdir -p "$VOL" && cp Crac.java "$VOL/" || exit 1
WINGS=(--read-only --security-opt no-new-privileges --tmpfs /tmp:rw,exec,nosuid,size=100M
  --cap-drop setpcap --cap-drop mknod --cap-drop audit_write --cap-drop net_raw --cap-drop dac_override
  --cap-drop fowner --cap-drop fsetid --cap-drop net_bind_service --cap-drop sys_chroot --cap-drop setfcap
  --user "$(id -u):$(id -g)" -v "$VOL:/home/container" -e SERVER_JARFILE=server.jar)
FAIL=0
check() { # name, grep -E pattern, text
  if grep -Eq -- "$2" <<<"$3"; then echo "PASS $1"; else echo "FAIL $1"; FAIL=1; fi
}

out=$(docker run --rm "${WINGS[@]}" -e STARTUP='echo "pid1=$(cat /proc/1/comm)"; sha256sum /usr/bin/tini /entrypoint.sh; echo "home=$(readlink -f /opt/java/openjdk) java=$(readlink -f "$(command -v java)")"; echo "args=$( [[ ! -f unix_args.txt ]] && printf %s "-jar {{SERVER_JARFILE}}" || printf %s "@unix_args.txt" )"; locale | head -1; echo "numa=$(ldconfig -p | grep -c libnuma.so.1)"' "$IMAGE" 2>&1)
echo "$out"
check "tini is PID 1" '^pid1=tini$' "$out"
check "tini hash" '^274f2bed211788a4fcb52d14f93ab6e7c44528493b56af5812a1cfe8ae1d2064  /usr/bin/tini$' "$out"
check "entrypoint hash" '^ed1c41275861bcfe704bf18754f5fd087e125b9672e8eca563486c3312099578  /entrypoint.sh$' "$out"
check "java -version" "$(printf %s "$EXPECT" | sed 's/[][\.*^$+?(){}|]/\\&/g')" "$out"
check "STARTUP eval" '^args=-jar server\.jar$' "$out"
check "java under /opt/java/openjdk" '^home=(/[^ ]+) java=\1/' "$out"
check "locale" '^LANG=en_US\.UTF-8$' "$out"
check "libnuma" '^numa=[1-9]' "$out"

if [ "$CRAC" = crac ]; then
  out=$(docker run --rm "${WINGS[@]}" -e STARTUP='java -XX:CRaCEngine=warp -XX:CRaCCheckpointTo=/home/container/cr Crac.java; echo "exit=$?"' "$IMAGE" 2>&1)
  echo "$out" | tail -3
  check "warp checkpoint" 'warp: Checkpoint successful!' "$out"
  out=$(docker run --rm "${WINGS[@]}" -e STARTUP='java -XX:CRaCEngine=warp -XX:CRaCRestoreFrom=/home/container/cr; echo "exit=$?"' "$IMAGE" 2>&1)
  echo "$out" | tail -3
  check "warp restore" '^restored pid=' "$out"
fi
rm -rf "$VOL"
exit $FAIL
