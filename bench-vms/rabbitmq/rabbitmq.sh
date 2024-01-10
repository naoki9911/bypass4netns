#!/bin/bash

set -eux

cd $(dirname $0)
. ./../param.bash

RABBITMQ_VERSION=3.12.10
RABBITMQ_IMAGE="rabbitmq:$RABBITMQ_VERSION"

PERF_VERSION="2.20.0"
PERF_IMAGE="pivotalrabbitmq/perf-test:$PERF_VERSION"

VM1_VXLAN_MAC="02:42:c0:a8:00:1"
VM1_VXLAN_ADDR="192.168.2.1"
VM2_VXLAN_MAC="02:42:c0:a8:00:2"
VM2_VXLAN_ADDR="192.168.2.2"

ssh $VM1 "sudo nerdctl pull --quiet $RABBITMQ_IMAGE"
ssh $VM1 "nerdctl pull --quiet $RABBITMQ_IMAGE"
ssh $VM1 "sudo nerdctl pull --quiet $PERF_IMAGE"
ssh $VM1 "nerdctl pull --quiet $PERF_IMAGE"
ssh $VM2 "sudo nerdctl pull --quiet $RABBITMQ_IMAGE"
ssh $VM2 "nerdctl pull --quiet $RABBITMQ_IMAGE"
ssh $VM2 "sudo nerdctl pull --quiet $PERF_IMAGE"
ssh $VM2 "nerdctl pull --quiet $PERF_IMAGE"

TIME=120
DATE=$(date +%Y%m%d-%H%M%S)

echo "===== Benchmark: rabbitmq rootful via port forwarding ====="
(
  function cleanup {
    ssh $VM1 "sudo nerdctl rm -f rabbitmq-server"
    ssh $VM2 "sudo nerdctl rm -f rabbitmq-client"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "sudo nerdctl run -d --name rabbitmq-server -p 5673:5672 $RABBITMQ_IMAGE"
  sleep 20
  LOG_NAME="rabbitmq-rootful-pfd-$DATE.log"
  ssh $VM2 "sudo nerdctl run --name rabbitmq-client --rm $PERF_IMAGE --uri amqp://$VM1_ADDR:5673 --producers 2 --consumers 2 --time $TIME" > $LOG_NAME

  cleanup
  sleep 3
)

echo "===== Benchmark: rabbitmq client(w/o bypass4netns) server(w/o bypass4netns) via host ====="
(
  function cleanup {
    ssh $VM1 "nerdctl rm -f rabbitmq-server"
    ssh $VM2 "nerdctl rm -f rabbitmq-client"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "nerdctl run -d --name rabbitmq-server -p 5674:5672 $RABBITMQ_IMAGE"
  sleep 20
  LOG_NAME="rabbitmq-rootless-pfd-$DATE.log"
  ssh $VM2 "nerdctl run --name rabbitmq-client --rm $PERF_IMAGE --uri amqp://$VM1_ADDR:5674 --producers 2 --consumers 2 --time $TIME" > $LOG_NAME

  cleanup
  sleep 3
)

echo "===== Benchmark: rabbitmq client(w/ bypass4netns) server(w/ bypass4netns) via host ====="
(
  function cleanup {
    ssh $VM1 "nerdctl rm -f rabbitmq-server"
    ssh $VM1 "systemctl --user stop run-bypass4netnsd"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "nerdctl rm -f rabbitmq-client"
    ssh $VM2 "systemctl --user stop run-bypass4netnsd"
    ssh $VM2 "systemctl --user reset-failed"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd"
  ssh $VM2 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd"

  ssh $VM1 "nerdctl run --label nerdctl/bypass4netns=true -d --name rabbitmq-server -p 5673:5672 $RABBITMQ_IMAGE"
  sleep 20
  LOG_NAME="rabbitmq-b4ns-pfd-$DATE.log"
  ssh $VM2 "nerdctl run --label nerdctl/bypass4netns=true --name rabbitmq-client --rm $PERF_IMAGE --uri amqp://$VM1_ADDR:5673 --producers 2 --consumers 2 --time $TIME" > $LOG_NAME

  cleanup
  sleep 3
)

echo "===== Benchmark: rabbitmq rootful via VXLAN ====="
(
  function cleanup () {
    ssh $VM1 "sudo nerdctl rm -f rabbitmq-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "sudo nerdctl rm -f rabbitmq-client"

    ssh $VM1 "sudo ip link del vxlan0"
    ssh $VM1 "sudo ip link del br-vxlan"
    ssh $VM2 "sudo ip link del vxlan0"
    ssh $VM2 "sudo ip link del br-vxlan"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "sudo nerdctl run --name rabbitmq-server -d $RABBITMQ_IMAGE"
  ssh $VM2 "sudo nerdctl run --name rabbitmq-client -d --entrypoint '' $PERF_IMAGE /bin/sh -c 'sleep infinity'"
  sleep 20

  CONTAINER_PID=$(ssh $VM1 "sudo nerdctl inspect rabbitmq-server | jq '.[0].State.Pid'")
  ssh $VM1 "sudo $B4NS_PATH/bench-vms/setup_vxlan.sh 1 $CONTAINER_PID enp2s0 $VM1_VXLAN_MAC $VM1_VXLAN_ADDR $VM2_ADDR $VM2_VXLAN_MAC $VM2_VXLAN_ADDR"
  CONTAINER_PID=$(ssh $VM2 "sudo nerdctl inspect rabbitmq-client | jq '.[0].State.Pid'")
  ssh $VM2 "sudo $B4NS_PATH/bench-vms/setup_vxlan.sh 1 $CONTAINER_PID enp2s0 $VM2_VXLAN_MAC $VM2_VXLAN_ADDR $VM1_ADDR $VM1_VXLAN_MAC $VM1_VXLAN_ADDR"
  LOG_NAME="rabbitmq-rootful-vxlan-$DATE.log"
  ssh $VM2 "sudo nerdctl exec rabbitmq-client java -jar /perf_test/perf-test.jar --uri amqp://$VM1_VXLAN_ADDR --producers 2 --consumers 2 --time $TIME" > $LOG_NAME

  cleanup
  sleep 3
)

echo "===== Benchmark: rabbitmq rootless via VXLAN ====="
(
  function cleanup () {
    ssh $VM1 "nerdctl rm -f rabbitmq-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "nerdctl rm -f rabbitmq-client"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "nerdctl run -p 4789:4789/udp --privileged --name rabbitmq-server -d $RABBITMQ_IMAGE"
  ssh $VM2 "nerdctl run -p 4789:4789/udp --privileged --name rabbitmq-client -d --entrypoint '' $PERF_IMAGE /bin/sh -c 'sleep infinity'"
  sleep 20

  CONTAINER_PID=$(ssh $VM1 "nerdctl inspect rabbitmq-server | jq '.[0].State.Pid'")
  ssh $VM1 "$B4NS_PATH/bench-vms/setup_vxlan.sh $CONTAINER_PID $CONTAINER_PID eth0 $VM1_VXLAN_MAC $VM1_VXLAN_ADDR $VM2_ADDR $VM2_VXLAN_MAC $VM2_VXLAN_ADDR"
  CONTAINER_PID=$(ssh $VM2 "nerdctl inspect rabbitmq-client | jq '.[0].State.Pid'")
  ssh $VM2 "$B4NS_PATH/bench-vms/setup_vxlan.sh $CONTAINER_PID $CONTAINER_PID eth0 $VM2_VXLAN_MAC $VM2_VXLAN_ADDR $VM1_ADDR $VM1_VXLAN_MAC $VM1_VXLAN_ADDR"
  sleep 5
  LOG_NAME="rabbitmq-rootless-vxlan-$DATE.log"
  ssh $VM2 "nerdctl exec rabbitmq-client java -jar /perf_test/perf-test.jar --uri amqp://$VM1_VXLAN_ADDR --producers 2 --consumers 2 --time $TIME" > $LOG_NAME

  cleanup
  sleep 3
)

echo "===== Benchmark: iperf3 client(w/ bypass4netns) server(w/ bypass4netns) with multinode ====="
(
  function cleanup {
    ssh $VM1 "nerdctl rm -f rabbitmq-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM1 "systemctl --user stop run-bypass4netnsd"
    ssh $VM1 "systemctl --user stop etcd.service"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "nerdctl rm -f rabbitmq-client"
    ssh $VM2 "systemctl --user stop run-bypass4netnsd"
    ssh $VM2 "systemctl --user reset-failed"
  }

  set +e
  cleanup
  set -ex

  ssh $VM1 "systemd-run --user --unit etcd.service /usr/bin/etcd --listen-client-urls http://$VM1_ADDR:2379 --advertise-client-urls http://$VM1_ADDR:2379"
  ssh $VM1 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd --multinode=true --multinode-etcd-address=http://$VM1_ADDR:2379 --multinode-host-address=$VM1_ADDR"
  ssh $VM2 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd --multinode=true --multinode-etcd-address=http://$VM1_ADDR:2379 --multinode-host-address=$VM2_ADDR"
  ssh $VM1 "nerdctl run --label nerdctl/bypass4netns=true -p 5673:5672 --name rabbitmq-server -d $RABBITMQ_IMAGE"
  ssh $VM2 "nerdctl run --label nerdctl/bypass4netns=true --name rabbitmq-client -d --entrypoint '' $PERF_IMAGE /bin/sh -c 'sleep infinity'"
  sleep 20

  SERVER_IP=$(ssh $VM1 nerdctl exec rabbitmq-server hostname -i)
  LOG_NAME="rabbitmq-b4ns-multinode-$DATE.log"
  ssh $VM2 "nerdctl exec rabbitmq-client java -jar /perf_test/perf-test.jar --uri amqp://$SERVER_IP --producers 2 --consumers 2 --time $TIME" > $LOG_NAME

  cleanup
)
