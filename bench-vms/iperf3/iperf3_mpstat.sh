#!/bin/bash

set -eux

cd $(dirname $0)
. ./../param.bash

ALPINE_IMAGE="public.ecr.aws/docker/library/alpine:3.16"

VM1_VXLAN_MAC="02:42:c0:a8:00:1"
VM1_VXLAN_ADDR="192.168.2.1"
VM2_VXLAN_MAC="02:42:c0:a8:00:2"
VM2_VXLAN_ADDR="192.168.2.2"

DATE=$(date +%Y%m%d-%H%M%S)
TIME=120
RATE=1G

echo "===== Benchmark: iperf3 rootful via port fowarding ====="
(
  function cleanup () {
    ssh $VM1 "sudo nerdctl rm -f iperf3-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "sudo nerdctl rm -f iperf3-client"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "sudo nerdctl run -d --name iperf3-server -p 5202:5201 $ALPINE_IMAGE sleep infinity"
  ssh $VM1 "sudo nerdctl exec iperf3-server apk add --no-cache iperf3"
  ssh $VM2 "sudo nerdctl run -d --name iperf3-client $ALPINE_IMAGE sleep infinity"
  ssh $VM2 "sudo nerdctl exec iperf3-client apk add --no-cache iperf3"

  ssh $VM1 "systemd-run --user --unit iperf3-server sudo nerdctl exec iperf3-server iperf3 -s"

  sleep 1
  date
  ssh $VM2 "sudo nerdctl exec iperf3-client iperf3 -c $VM1_ADDR -p 5202 -i 0 -t $TIME -b $RATE --connect-timeout 1000 -J"

  cleanup
)

echo "===== Benchmark: iperf3 client(w/o bypass4netns) server(w/o bypass4netns) via host ====="
(
  function cleanup () {
    ssh $VM1 "nerdctl rm -f iperf3-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "nerdctl rm -f iperf3-client"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "nerdctl run -d --name iperf3-server -p 5203:5201 $ALPINE_IMAGE sleep infinity"
  ssh $VM1 "nerdctl exec iperf3-server apk add --no-cache iperf3"
  ssh $VM2 "nerdctl run -d --name iperf3-client $ALPINE_IMAGE sleep infinity"
  ssh $VM2 "nerdctl exec iperf3-client apk add --no-cache iperf3"

  ssh $VM1 "systemd-run --user --unit iperf3-server nerdctl exec iperf3-server iperf3 -s"

  sleep 1
  date
  ssh $VM2 "nerdctl exec iperf3-client iperf3 -c $VM1_ADDR -p 5203 -i 0 -t $TIME -b $RATE --connect-timeout 1000 -J"

  cleanup
)

echo "===== Benchmark: iperf3 client(w/ bypass4netns) server(w/ bypass4netns) via host ====="
(
  function cleanup () {
    ssh $VM1 "nerdctl rm -f iperf3-server"
    ssh $VM1 "systemctl --user stop run-bypass4netnsd"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "nerdctl rm -f iperf3-client"
    ssh $VM2 "systemctl --user stop run-bypass4netnsd"
    ssh $VM2 "systemctl --user reset-failed"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd"
  ssh $VM2 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd"

  ssh $VM1 "nerdctl run --label nerdctl/bypass4netns=true -d --name iperf3-server -p 5202:5201 $ALPINE_IMAGE sleep infinity"
  ssh $VM1 "nerdctl exec iperf3-server apk add --no-cache iperf3"
  ssh $VM2 "nerdctl run --label nerdctl/bypass4netns=true -d --name iperf3-client $ALPINE_IMAGE sleep infinity"
  ssh $VM2 "nerdctl exec iperf3-client apk add --no-cache iperf3"

  ssh $VM1 "systemd-run --user --unit iperf3-server nerdctl exec iperf3-server iperf3 -s"

  sleep 1
  date
  ssh $VM2 "nerdctl exec iperf3-client iperf3 -c $VM1_ADDR -p 5202 -i 0 -t $TIME -b $RATE --connect-timeout 1000 -J"

  cleanup
)
