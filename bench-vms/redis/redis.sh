#!/bin/bash

set -eux

cd $(dirname $0)
. ./../param.bash

REDIS_VERSION=7.2.3
REDIS_IMAGE="redis:${REDIS_VERSION}"

VM1_VXLAN_MAC="02:42:c0:a8:00:1"
VM1_VXLAN_ADDR="192.168.2.1"
VM2_VXLAN_MAC="02:42:c0:a8:00:2"
VM2_VXLAN_ADDR="192.168.2.2"

ssh $VM1 "sudo nerdctl pull --quiet $REDIS_IMAGE"
ssh $VM1 "nerdctl pull --quiet $REDIS_IMAGE"
ssh $VM2 "sudo nerdctl pull --quiet $REDIS_IMAGE"
ssh $VM2 "nerdctl pull --quiet $REDIS_IMAGE"

DATE=$(date +%Y%m%d-%H%M%S)

echo "===== Benchmark: redis rootful via port forwarding ====="
(
  function cleanup {
    ssh $VM1 "sudo nerdctl rm -f redis-server"
    ssh $VM2 "sudo nerdctl rm -f redis-client"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "sudo nerdctl run -d --name redis-server -p 6380:6379 $REDIS_IMAGE"
  ssh $VM2 "sudo nerdctl run -d --name redis-client $REDIS_IMAGE sleep infinity"
  sleep 5
  LOG_NAME="redis-rootful-pfd-$DATE.log"
  ssh $VM2 "sudo nerdctl exec redis-client redis-benchmark -q -h $VM1_ADDR -p 6380 --csv" > $LOG_NAME

  cleanup
  sleep 3
)

echo "===== Benchmark: redis client(w/o bypass4netns) server(w/o bypass4netns) via host ====="
(
  function cleanup {
    ssh $VM1 "nerdctl rm -f redis-server"
    ssh $VM2 "nerdctl rm -f redis-client"
  }

  set +e
  cleanup
  set -ex

  ssh $VM1 "nerdctl run -d --name redis-server -p 6381:6379 $REDIS_IMAGE"
  ssh $VM2 "nerdctl run -d --name redis-client $REDIS_IMAGE sleep infinity"
  sleep 5
  LOG_NAME="redis-rootless-pfd-$DATE.log"
  ssh $VM2 "nerdctl exec redis-client redis-benchmark -q -h $VM1_ADDR -p 6381 --csv" > $LOG_NAME

  cleanup
  sleep 3
)

echo "===== Benchmark: redis client(w/ bypass4netns) server(w/ bypass4netns) via host ====="
(
  function cleanup {
    ssh $VM1 "nerdctl rm -f redis-server"
    ssh $VM1 "systemctl --user stop run-bypass4netnsd"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "nerdctl rm -f redis-client"
    ssh $VM2 "systemctl --user stop run-bypass4netnsd"
    ssh $VM2 "systemctl --user reset-failed"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd"
  ssh $VM2 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd"

  ssh $VM1 "nerdctl run --label nerdctl/bypass4netns=true -d --name redis-server -p 6380:6379 $REDIS_IMAGE"
  ssh $VM2 "nerdctl run --label nerdctl/bypass4netns=true -d --name redis-client $REDIS_IMAGE sleep infinity"
  LOG_NAME="redis-b4ns-pfd-$DATE.log"
  sleep 5
  rm -f $LOG_NAME
  ssh $VM2 "nerdctl exec redis-client redis-benchmark -q -h $VM1_ADDR -p 6380 --csv" > $LOG_NAME

  cleanup
  sleep 3
)

echo "===== Benchmark: redis rootful via VXLAN ====="
(
  function cleanup () {
    ssh $VM1 "sudo nerdctl rm -f redis-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "sudo nerdctl rm -f redis-client"

    ssh $VM1 "sudo ip link del vxlan0"
    ssh $VM1 "sudo ip link del br-vxlan"
    ssh $VM2 "sudo ip link del vxlan0"
    ssh $VM2 "sudo ip link del br-vxlan"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "sudo nerdctl run -d --name redis-server $REDIS_IMAGE"
  ssh $VM2 "sudo nerdctl run -d --name redis-client $REDIS_IMAGE sleep infinity"

  CONTAINER_PID=$(ssh $VM1 "sudo nerdctl inspect redis-server | jq '.[0].State.Pid'")
  ssh $VM1 "sudo $B4NS_PATH/bench-vms/setup_vxlan.sh 1 $CONTAINER_PID enp2s0 $VM1_VXLAN_MAC $VM1_VXLAN_ADDR $VM2_ADDR $VM2_VXLAN_MAC $VM2_VXLAN_ADDR"
  CONTAINER_PID=$(ssh $VM2 "sudo nerdctl inspect redis-client | jq '.[0].State.Pid'")
  ssh $VM2 "sudo $B4NS_PATH/bench-vms/setup_vxlan.sh 1 $CONTAINER_PID enp2s0 $VM2_VXLAN_MAC $VM2_VXLAN_ADDR $VM1_ADDR $VM1_VXLAN_MAC $VM1_VXLAN_ADDR"
  sleep 5
  LOG_NAME="redis-rootful-vxlan-$DATE.log"
  ssh $VM2 "sudo nerdctl exec redis-client redis-benchmark -q -h $VM1_VXLAN_ADDR -p 6379 --csv" > $LOG_NAME

  cleanup
  sleep 3
)

echo "===== Benchmark: redis rootless via VXLAN ====="
(
  function cleanup () {
    ssh $VM1 "nerdctl rm -f redis-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "nerdctl rm -f redis-client"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "nerdctl run -p 4789:4789/udp --privileged -d --name redis-server $REDIS_IMAGE"
  ssh $VM2 "nerdctl run -p 4789:4789/udp --privileged -d --name redis-client $REDIS_IMAGE sleep infinity"

  CONTAINER_PID=$(ssh $VM1 "nerdctl inspect redis-server | jq '.[0].State.Pid'")
  ssh $VM1 "$B4NS_PATH/bench-vms/setup_vxlan.sh $CONTAINER_PID $CONTAINER_PID eth0 $VM1_VXLAN_MAC $VM1_VXLAN_ADDR $VM2_ADDR $VM2_VXLAN_MAC $VM2_VXLAN_ADDR"
  CONTAINER_PID=$(ssh $VM2 "nerdctl inspect redis-client | jq '.[0].State.Pid'")
  ssh $VM2 "$B4NS_PATH/bench-vms/setup_vxlan.sh $CONTAINER_PID $CONTAINER_PID eth0 $VM2_VXLAN_MAC $VM2_VXLAN_ADDR $VM1_ADDR $VM1_VXLAN_MAC $VM1_VXLAN_ADDR"
  sleep 5
  LOG_NAME="redis-rootless-vxlan-$DATE.log"
  ssh $VM2 "nerdctl exec redis-client redis-benchmark -q -h $VM1_VXLAN_ADDR -p 6379 --csv" > $LOG_NAME

  cleanup
  sleep 3
)

echo "===== Benchmark: iperf3 client(w/ bypass4netns) server(w/ bypass4netns) with multinode ====="
(
  function cleanup {
    ssh $VM1 "nerdctl rm -f redis-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM1 "systemctl --user stop run-bypass4netnsd"
    ssh $VM1 "systemctl --user stop etcd.service"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "nerdctl rm -f redis-client"
    ssh $VM2 "systemctl --user stop run-bypass4netnsd"
    ssh $VM2 "systemctl --user reset-failed"
  }

  set +e
  cleanup
  set -ex

  ssh $VM1 "systemd-run --user --unit etcd.service /usr/bin/etcd --listen-client-urls http://$VM1_ADDR:2379 --advertise-client-urls http://$VM1_ADDR:2379"
  ssh $VM1 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd --multinode=true --multinode-etcd-address=http://$VM1_ADDR:2379 --multinode-host-address=$VM1_ADDR"
  ssh $VM2 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd --multinode=true --multinode-etcd-address=http://$VM1_ADDR:2379 --multinode-host-address=$VM2_ADDR"
  ssh $VM1 "sleep 3 && nerdctl run --label nerdctl/bypass4netns=true -d -p 6380:6379 --name redis-server $REDIS_IMAGE"
  ssh $VM2 "sleep 3 && nerdctl run --label nerdctl/bypass4netns=true -d --name redis-client $REDIS_IMAGE sleep infinity"

  SERVER_IP=$(ssh $VM1 nerdctl exec redis-server hostname -i)
  LOG_NAME="redis-b4ns-multinode-$DATE.log"
  ssh $VM2 "nerdctl exec redis-client redis-benchmark -q -h $SERVER_IP -p 6379 --csv" > $LOG_NAME
  cleanup
)
