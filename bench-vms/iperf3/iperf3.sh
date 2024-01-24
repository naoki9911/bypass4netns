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

IMAGE_NAME="iperf3"
IPERF_PATH=$B4NS_PATH/benchmark/iperf3
PARALLEL_NUM=${1:-1}

ssh $VM1 "sudo nerdctl build -f $IPERF_PATH/Dockerfile -t $IMAGE_NAME $IPERF_PATH"
ssh $VM1 "nerdctl build -f $IPERF_PATH/Dockerfile -t $IMAGE_NAME $IPERF_PATH"
ssh $VM2 "sudo nerdctl build -f $IPERF_PATH/Dockerfile -t $IMAGE_NAME $IPERF_PATH"
ssh $VM2 "nerdctl build -f $IPERF_PATH/Dockerfile -t $IMAGE_NAME $IPERF_PATH"

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

  ssh $VM1 "sudo nerdctl run -d --name iperf3-server -p 5202:5201 $IMAGE_NAME"
  ssh $VM2 "sudo nerdctl run -d --name iperf3-client $IMAGE_NAME"

  ssh $VM1 "systemd-run --user --unit iperf3-server sudo nerdctl exec iperf3-server iperf3 -s"

  sleep 1
  set +e
  ssh $VM2 "sudo nerdctl exec iperf3-client iperf3 -c $VM1_ADDR -p 5202 -i 0 -t $TIME --connect-timeout 1000 -P $PARALLEL_NUM -J" > iperf3-rootful-pfd-p$PARALLEL_NUM-$DATE.log
  if [ $? -ne 0 ]; then
    echo "FAIL" > iperf3-rootful-pfd-p$PARALLEL_NUM-$DATE.log
  fi
  set -e

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

  ssh $VM1 "nerdctl run -d --name iperf3-server -p 5203:5201 $IMAGE_NAME"
  ssh $VM2 "nerdctl run -d --name iperf3-client $IMAGE_NAME"

  ssh $VM1 "systemd-run --user --unit iperf3-server nerdctl exec iperf3-server iperf3 -s"

  sleep 1
  set +e
  ssh $VM2 "nerdctl exec iperf3-client iperf3 -c $VM1_ADDR -p 5203 -i 0 -t $TIME --connect-timeout 1000 -P $PARALLEL_NUM -J" > iperf3-rootless-pfd-p$PARALLEL_NUM-$DATE.log
  if [ $? -ne 0 ]; then
    echo "FAIL" > iperf3-rootless-pfd-p$PARALLEL_NUM-$DATE.log
  fi
  set -e

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

  ssh $VM1 "nerdctl run --label nerdctl/bypass4netns=true -d --name iperf3-server -p 5202:5201 $IMAGE_NAME"
  ssh $VM2 "nerdctl run --label nerdctl/bypass4netns=true -d --name iperf3-client $IMAGE_NAME"

  ssh $VM1 "systemd-run --user --unit iperf3-server nerdctl exec iperf3-server iperf3 -s"

  sleep 1
  set +e
  ssh $VM2 "nerdctl exec iperf3-client iperf3 -c $VM1_ADDR -p 5202 -i 0 -t $TIME --connect-timeout 1000 -P $PARALLEL_NUM -J" > iperf3-b4ns-pfd-p$PARALLEL_NUM-$DATE.log
  if [ $? -ne 0 ]; then
    echo "FAIL" > iperf3-b4ns-pfd-p$PARALLEL_NUM-$DATE.log
  fi
  set -e

  cleanup
)

echo "===== Benchmark: iperf3 rootful via VXLAN ====="
(
  function cleanup () {
    ssh $VM1 "sudo nerdctl rm -f iperf3-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "sudo nerdctl rm -f iperf3-client"

    ssh $VM1 "sudo ip link del vxlan0"
    ssh $VM1 "sudo ip link del br-vxlan"
    ssh $VM2 "sudo ip link del vxlan0"
    ssh $VM2 "sudo ip link del br-vxlan"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "sudo nerdctl run -d --name iperf3-server $IMAGE_NAME"
  ssh $VM2 "sudo nerdctl run -d --name iperf3-client $IMAGE_NAME"

  CONTAINER_PID=$(ssh $VM1 "sudo nerdctl inspect iperf3-server | jq '.[0].State.Pid'")
  ssh $VM1 "sudo $B4NS_PATH/bench-vms/setup_vxlan.sh 1 $CONTAINER_PID enp2s0 $VM1_VXLAN_MAC $VM1_VXLAN_ADDR $VM2_ADDR $VM2_VXLAN_MAC $VM2_VXLAN_ADDR"
  CONTAINER_PID=$(ssh $VM2 "sudo nerdctl inspect iperf3-client | jq '.[0].State.Pid'")
  ssh $VM2 "sudo $B4NS_PATH/bench-vms/setup_vxlan.sh 1 $CONTAINER_PID enp2s0 $VM2_VXLAN_MAC $VM2_VXLAN_ADDR $VM1_ADDR $VM1_VXLAN_MAC $VM1_VXLAN_ADDR"

  ssh $VM1 "systemd-run --user --unit iperf3-server sudo nerdctl exec iperf3-server iperf3 -s"

  sleep 1
  set +e
  ssh $VM2 "sudo nerdctl exec iperf3-client iperf3 -c $VM1_VXLAN_ADDR -i 0 -t $TIME --connect-timeout 1000 -P $PARALLEL_NUM -J" > iperf3-rootful-vxlan-p$PARALLEL_NUM-$DATE.log
  if [ $? -ne 0 ]; then
    echo "FAIL" > iperf3-rootful-vxlan-p$PARALLEL_NUM-$DATE.log
  fi
  set -e

  cleanup
)

echo "===== Benchmark: iperf3 rootless via VXLAN ====="
(
  function cleanup () {
    ssh $VM1 "nerdctl rm -f iperf3-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "nerdctl rm -f iperf3-client"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "nerdctl run -p 4789:4789/udp --privileged -d --name iperf3-server $IMAGE_NAME"
  ssh $VM2 "nerdctl run -p 4789:4789/udp --privileged -d --name iperf3-client $IMAGE_NAME"

  CONTAINER_PID=$(ssh $VM1 "nerdctl inspect iperf3-server | jq '.[0].State.Pid'")
  ssh $VM1 "$B4NS_PATH/bench-vms/setup_vxlan.sh $CONTAINER_PID $CONTAINER_PID eth0 $VM1_VXLAN_MAC $VM1_VXLAN_ADDR $VM2_ADDR $VM2_VXLAN_MAC $VM2_VXLAN_ADDR"
  CONTAINER_PID=$(ssh $VM2 "nerdctl inspect iperf3-client | jq '.[0].State.Pid'")
  ssh $VM2 "$B4NS_PATH/bench-vms/setup_vxlan.sh $CONTAINER_PID $CONTAINER_PID eth0 $VM2_VXLAN_MAC $VM2_VXLAN_ADDR $VM1_ADDR $VM1_VXLAN_MAC $VM1_VXLAN_ADDR"

  ssh $VM1 "systemd-run --user --unit iperf3-server nerdctl exec iperf3-server iperf3 -s"

  sleep 1
  set +e
  ssh $VM2 "nerdctl exec iperf3-client iperf3 -c $VM1_VXLAN_ADDR -i 0 -t $TIME --connect-timeout 1000 -P $PARALLEL_NUM -J" > iperf3-rootless-vxlan-p$PARALLEL_NUM-$DATE.log
  if [ $? -ne 0 ]; then
    echo "FAIL" > iperf3-rootless-vxlan-p$PARALLEL_NUM-$DATE.log
  fi
  set -e

  cleanup
)

echo "===== Benchmark: iperf3 client(w/ bypass4netns) server(w/ bypass4netns) with multinode ====="
(
  function cleanup {
    ssh $VM1 "nerdctl rm -f iperf3-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM1 "systemctl --user stop run-bypass4netnsd"
    ssh $VM1 "systemctl --user stop etcd.service"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "nerdctl rm -f iperf3-client"
    ssh $VM2 "systemctl --user stop run-bypass4netnsd"
    ssh $VM2 "systemctl --user reset-failed"
  }

  set +e
  cleanup
  set -ex

  ssh $VM1 "systemd-run --user --unit etcd.service /usr/bin/etcd --listen-client-urls http://$VM1_ADDR:2379 --advertise-client-urls http://$VM1_ADDR:2379"
  ssh $VM1 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd --multinode=true --multinode-etcd-address=http://$VM1_ADDR:2379 --multinode-host-address=$VM1_ADDR"
  ssh $VM2 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd --multinode=true --multinode-etcd-address=http://$VM1_ADDR:2379 --multinode-host-address=$VM2_ADDR"

  ssh $VM1 "sleep 3 && nerdctl run --label nerdctl/bypass4netns=true -d -p 5202:5201 --name iperf3-server $IMAGE_NAME"
  ssh $VM2 "sleep 3 && nerdctl run --label nerdctl/bypass4netns=true -d --name iperf3-client $IMAGE_NAME"

  SERVER_IP=$(ssh $VM1 nerdctl exec iperf3-server hostname -i)
  ssh $VM1 "systemd-run --user --unit iperf3-server nerdctl exec iperf3-server iperf3 -s"

  sleep 1
  set +e
  ssh $VM2 "nerdctl exec iperf3-client iperf3 -c $SERVER_IP -i 0 -t $TIME --connect-timeout 1000 -P $PARALLEL_NUM -J" > iperf3-b4ns-multinode-p$PARALLEL_NUM-$DATE.log
  if [ $? -ne 0 ]; then
    echo "FAIL" > iperf3-b4ns-multinode-p$PARALLEL_NUM-$DATE.log
  fi
  set -e

  cleanup
)
