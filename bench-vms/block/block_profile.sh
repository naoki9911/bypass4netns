#!/bin/bash

set -eux

cd $(dirname $0)
. ./../param.bash

VM1_VXLAN_MAC="02:42:c0:a8:00:1"
VM1_VXLAN_ADDR="192.168.2.1"
VM2_VXLAN_MAC="02:42:c0:a8:00:2"
VM2_VXLAN_ADDR="192.168.2.2"

IMAGE_NAME="block"
COUNT="100"
THREAD_NUM="1"
BLOCK_SIZES=('1k' '32k' '128k' '512k' '1m' '32m' '128m' '512m' '1g')
DATE=$(date +%Y%m%d-%H%M%S)

BLOCK_PATH=$B4NS_PATH/benchmark/block
ssh $VM1 "$B4NS_PATH/benchmark/block/gen_blocks.sh"

ssh $VM1 "sudo nerdctl build -f $BLOCK_PATH/Dockerfile -t $IMAGE_NAME $BLOCK_PATH"
ssh $VM1 "nerdctl build -f $BLOCK_PATH/Dockerfile -t $IMAGE_NAME $BLOCK_PATH"
ssh $VM2 "sudo nerdctl build -f $BLOCK_PATH/Dockerfile -t $IMAGE_NAME $BLOCK_PATH"
ssh $VM2 "nerdctl build -f $BLOCK_PATH/Dockerfile -t $IMAGE_NAME $BLOCK_PATH"

echo "===== Benchmark: block rootful via port forwarding ====="
(
  function cleanup {
    ssh $VM1 "sudo nerdctl rm -f block-server"
    ssh $VM2 "sudo nerdctl rm -f block-client"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "sudo nerdctl run -d --name block-server -p 8080:80 -v $BLOCK_PATH:/var/www/html:ro $IMAGE_NAME nginx -g \"daemon off;\""
  ssh $VM2 "sudo nerdctl run -d --name block-client $IMAGE_NAME sleep infinity"
  sleep 5
  PROFILE_NAME="block-rootful-pfd-$DATE.prof"
  rm -f $PROFILE_NAME
  ssh $VM2 "sudo nerdctl exec block-client /bench -count $COUNT -thread-num $THREAD_NUM -url http://$VM1_ADDR:8080/blk-1g -profile true"

  cleanup
  sleep 3
)

exit 0

echo "===== Benchmark: block client(w/o bypass4netns) server(w/o bypass4netns) via host ====="
(
  function cleanup {
    ssh $VM1 "nerdctl rm -f block-server"
    ssh $VM2 "nerdctl rm -f block-client"
  }

  set +e
  cleanup
  set -ex

  ssh $VM1 "nerdctl run -d --name block-server -p 8080:80 -v $BLOCK_PATH:/var/www/html:ro $IMAGE_NAME nginx -g \"daemon off;\""
  ssh $VM2 "nerdctl run -d --name block-client $IMAGE_NAME sleep infinity"
  sleep 5
  LOG_NAME="block-rootless-pfd-$DATE.log"
  rm -f $LOG_NAME
  for BLOCK_SIZE in ${BLOCK_SIZES[@]}
  do
    ssh $VM2 "nerdctl exec block-client /bench -count 1 -thread-num 1 -url http://$VM1_ADDR:8080/blk-$BLOCK_SIZE"
    ssh $VM2 "nerdctl exec block-client /bench -count $COUNT -thread-num $THREAD_NUM -url http://$VM1_ADDR:8080/blk-$BLOCK_SIZE" >> $LOG_NAME
  done

  cleanup
  sleep 3
)

echo "===== Benchmark: block client(w/ bypass4netns) server(w/ bypass4netns) via host ====="
(
  function cleanup {
    ssh $VM1 "nerdctl rm -f block-server"
    ssh $VM1 "systemctl --user stop run-bypass4netnsd"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "nerdctl rm -f block-client"
    ssh $VM2 "systemctl --user stop run-bypass4netnsd"
    ssh $VM2 "systemctl --user reset-failed"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd"
  ssh $VM2 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd"

  ssh $VM1 "nerdctl run --label nerdctl/bypass4netns=true -d --name block-server -p 8080:80 -v $BLOCK_PATH:/var/www/html:ro $IMAGE_NAME nginx -g \"daemon off;\""
  ssh $VM2 "nerdctl run --label nerdctl/bypass4netns=true -d --name block-client $IMAGE_NAME sleep infinity"
  LOG_NAME="block-b4ns-pfd-$DATE.log"
  sleep 5
  rm -f $LOG_NAME
  for BLOCK_SIZE in ${BLOCK_SIZES[@]}
  do
    ssh $VM2 "nerdctl exec block-client /bench -count 1 -thread-num 1 -url http://$VM1_ADDR:8080/blk-$BLOCK_SIZE"
    ssh $VM2 "nerdctl exec block-client /bench -count $COUNT -thread-num $THREAD_NUM -url http://$VM1_ADDR:8080/blk-$BLOCK_SIZE" >> $LOG_NAME
  done

  cleanup
  sleep 3
)

echo "===== Benchmark: block rootful via VXLAN ====="
(
  function cleanup () {
    ssh $VM1 "sudo nerdctl rm -f block-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "sudo nerdctl rm -f block-client"

    ssh $VM1 "sudo ip link del vxlan0"
    ssh $VM1 "sudo ip link del br-vxlan"
    ssh $VM2 "sudo ip link del vxlan0"
    ssh $VM2 "sudo ip link del br-vxlan"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "sudo nerdctl run -d --name block-server -v $BLOCK_PATH:/var/www/html:ro $IMAGE_NAME nginx -g \"daemon off;\""
  ssh $VM2 "sudo nerdctl run -d --name block-client $IMAGE_NAME sleep infinity"

  CONTAINER_PID=$(ssh $VM1 "sudo nerdctl inspect block-server | jq '.[0].State.Pid'")
  ssh $VM1 "sudo $B4NS_PATH/bench-vms/setup_vxlan.sh 1 $CONTAINER_PID enp2s0 $VM1_VXLAN_MAC $VM1_VXLAN_ADDR $VM2_ADDR $VM2_VXLAN_MAC $VM2_VXLAN_ADDR"
  CONTAINER_PID=$(ssh $VM2 "sudo nerdctl inspect block-client | jq '.[0].State.Pid'")
  ssh $VM2 "sudo $B4NS_PATH/bench-vms/setup_vxlan.sh 1 $CONTAINER_PID enp2s0 $VM2_VXLAN_MAC $VM2_VXLAN_ADDR $VM1_ADDR $VM1_VXLAN_MAC $VM1_VXLAN_ADDR"
  sleep 5
  LOG_NAME="block-rootful-vxlan-$DATE.log"
  rm -f $LOG_NAME
  for BLOCK_SIZE in ${BLOCK_SIZES[@]}
  do
    ssh $VM2 "sudo nerdctl exec block-client /bench -count 1 -thread-num 1 -url http://$VM1_VXLAN_ADDR:80/blk-$BLOCK_SIZE"
    ssh $VM2 "sudo nerdctl exec block-client /bench -count $COUNT -thread-num $THREAD_NUM -url http://$VM1_VXLAN_ADDR:80/blk-$BLOCK_SIZE" >> $LOG_NAME
  done

  cleanup
  sleep 3
)

echo "===== Benchmark: block rootless via VXLAN ====="
(
  function cleanup () {
    ssh $VM1 "nerdctl rm -f block-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "nerdctl rm -f block-client"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "nerdctl run -p 4789:4789/udp --privileged -d --name block-server -v $BLOCK_PATH:/var/www/html:ro $IMAGE_NAME nginx -g \"daemon off;\""
  ssh $VM2 "nerdctl run -p 4789:4789/udp --privileged -d --name block-client $IMAGE_NAME sleep infinity"

  CONTAINER_PID=$(ssh $VM1 "nerdctl inspect block-server | jq '.[0].State.Pid'")
  ssh $VM1 "$B4NS_PATH/bench-vms/setup_vxlan.sh $CONTAINER_PID $CONTAINER_PID eth0 $VM1_VXLAN_MAC $VM1_VXLAN_ADDR $VM2_ADDR $VM2_VXLAN_MAC $VM2_VXLAN_ADDR"
  CONTAINER_PID=$(ssh $VM2 "nerdctl inspect block-client | jq '.[0].State.Pid'")
  ssh $VM2 "$B4NS_PATH/bench-vms/setup_vxlan.sh $CONTAINER_PID $CONTAINER_PID eth0 $VM2_VXLAN_MAC $VM2_VXLAN_ADDR $VM1_ADDR $VM1_VXLAN_MAC $VM1_VXLAN_ADDR"
  sleep 5
  LOG_NAME="block-rootless-vxlan-$DATE.log"
  rm -f $LOG_NAME
  for BLOCK_SIZE in ${BLOCK_SIZES[@]}
  do
    ssh $VM2 "nerdctl exec block-client /bench -count 1 -thread-num 1 -url http://$VM1_VXLAN_ADDR:80/blk-$BLOCK_SIZE"
    ssh $VM2 "nerdctl exec block-client /bench -count $COUNT -thread-num $THREAD_NUM -url http://$VM1_VXLAN_ADDR:80/blk-$BLOCK_SIZE" >> $LOG_NAME
  done

  cleanup
  sleep 3
)

echo "===== Benchmark: iperf3 client(w/ bypass4netns) server(w/ bypass4netns) with multinode ====="
(
  function cleanup {
    ssh $VM1 "nerdctl rm -f block-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM1 "systemctl --user stop run-bypass4netnsd"
    ssh $VM1 "systemctl --user stop etcd.service"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "nerdctl rm -f block-client"
    ssh $VM2 "systemctl --user stop run-bypass4netnsd"
    ssh $VM2 "systemctl --user reset-failed"
  }

  set +e
  cleanup
  set -ex

  ssh $VM1 "systemd-run --user --unit etcd.service /usr/bin/etcd --listen-client-urls http://$VM1_ADDR:2379 --advertise-client-urls http://$VM1_ADDR:2379"
  ssh $VM1 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd --multinode=true --multinode-etcd-address=http://$VM1_ADDR:2379 --multinode-host-address=$VM1_ADDR"
  ssh $VM2 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd --multinode=true --multinode-etcd-address=http://$VM1_ADDR:2379 --multinode-host-address=$VM2_ADDR"
  ssh $VM1 "sleep 3 && nerdctl run --label nerdctl/bypass4netns=true -d -p 8080:80 --name block-server -v $BLOCK_PATH:/var/www/html:ro $IMAGE_NAME nginx -g \"daemon off;\""
  ssh $VM2 "sleep 3 && nerdctl run --label nerdctl/bypass4netns=true -d --name block-client $IMAGE_NAME sleep infinity"

  SERVER_IP=$(ssh $VM1 nerdctl exec block-server hostname -i)
  LOG_NAME="block-b4ns-multinode-$DATE.log"
  rm -f $LOG_NAME
  for BLOCK_SIZE in ${BLOCK_SIZES[@]}
  do
    ssh $VM2 "nerdctl exec block-client /bench -count 1 -thread-num 1 -url http://$SERVER_IP:80/blk-$BLOCK_SIZE"
    ssh $VM2 "nerdctl exec block-client /bench -count $COUNT -thread-num $THREAD_NUM -url http://$SERVER_IP:80/blk-$BLOCK_SIZE" >> $LOG_NAME
  done
  cleanup
)
