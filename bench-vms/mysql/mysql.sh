#!/bin/bash

set -eux

cd $(dirname $0)
. ./../param.bash

MYSQL_VERSION=8.2.0
MYSQL_IMAGE="mysql:$MYSQL_VERSION"
BENCH_IMAGE="mysql-bench"

VM1_VXLAN_MAC="02:42:c0:a8:00:1"
VM1_VXLAN_ADDR="192.168.2.1"
VM2_VXLAN_MAC="02:42:c0:a8:00:2"
VM2_VXLAN_ADDR="192.168.2.2"

ssh $VM1 "sudo nerdctl pull --quiet $MYSQL_IMAGE"
ssh $VM1 "nerdctl pull --quiet $MYSQL_IMAGE"
ssh $VM2 "sudo nerdctl pull --quiet $MYSQL_IMAGE"
ssh $VM2 "nerdctl pull --quiet $MYSQL_IMAGE"

MYSQL_PATH=$B4NS_PATH/benchmark/mysql
ssh $VM1 "sudo nerdctl build -f $MYSQL_PATH/Dockerfile -t $BENCH_IMAGE $MYSQL_PATH"
ssh $VM1 "nerdctl build -f $MYSQL_PATH/Dockerfile -t $BENCH_IMAGE $MYSQL_PATH"
ssh $VM2 "sudo nerdctl build -f $MYSQL_PATH/Dockerfile -t $BENCH_IMAGE $MYSQL_PATH"
ssh $VM2 "nerdctl build -f $MYSQL_PATH/Dockerfile -t $BENCH_IMAGE $MYSQL_PATH"

TIME=120
DATE=$(date +%Y%m%d-%H%M%S)

#echo "===== Benchmark: mysql rootful via port forwarding ====="
#(
#  function cleanup {
#    ssh $VM1 "sudo nerdctl rm -f mysql-server"
#    ssh $VM2 "sudo nerdctl rm -f mysql-client"
#  }
#  set +e
#  cleanup
#  set -ex
#
#  ssh $VM1 "sudo nerdctl run -d -p 13306:3306 --name mysql-server -e MYSQL_ROOT_PASSWORD=pass -e MYSQL_DATABASE=bench $MYSQL_IMAGE"
#  ssh $VM2 "sudo nerdctl run -d --name mysql-client $BENCH_IMAGE sleep infinity"
#  sleep 40
#  LOG_NAME="mysql-rootful-pfd-$DATE.log"
#  ssh $VM2 "sudo nerdctl exec mysql-client sysbench --threads=4 --time=60 --mysql-host=$VM1_ADDR --mysql-port=13306 --mysql-db=bench --mysql-user=root --mysql-password=pass --db-driver=mysql oltp_common prepare"
#  ssh $VM2 "sudo nerdctl exec mysql-client sysbench --threads=4 --time=$TIME --mysql-host=$VM1_ADDR --mysql-port=13306 --mysql-db=bench --mysql-user=root --mysql-password=pass --db-driver=mysql oltp_read_write run" > $LOG_NAME
#
#  cleanup
#  sleep 3
#)

echo "===== Benchmark: mysql client(w/o bypass4netns) server(w/o bypass4netns) via host ====="
(
  function cleanup {
    ssh $VM1 "nerdctl rm -f mysql-server"
    ssh $VM2 "nerdctl rm -f mysql-client"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "nerdctl run -d -p 13306:3306 --name mysql-server -e MYSQL_ROOT_PASSWORD=pass -e MYSQL_DATABASE=bench $MYSQL_IMAGE"
  ssh $VM2 "nerdctl run -d --name mysql-client $BENCH_IMAGE sleep infinity"
  sleep 40
  LOG_NAME="mysql-rootless-pfd-$DATE.log"
  ssh $VM2 "nerdctl exec mysql-client sysbench --threads=4 --time=60 --mysql-host=$VM1_ADDR --mysql-port=13306 --mysql-db=bench --mysql-user=root --mysql-password=pass --db-driver=mysql oltp_common prepare"
  ssh $VM2 "nerdctl exec mysql-client sysbench --threads=4 --time=$TIME --mysql-host=$VM1_ADDR --mysql-port=13306 --mysql-db=bench --mysql-user=root --mysql-password=pass --db-driver=mysql oltp_read_write run" > $LOG_NAME

  cleanup
  sleep 3
)

exit 0

echo "===== Benchmark: mysql client(w/ bypass4netns) server(w/ bypass4netns) via host ====="
(
  function cleanup {
    ssh $VM1 "nerdctl rm -f mysql-server"
    ssh $VM1 "systemctl --user stop run-bypass4netnsd"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "nerdctl rm -f mysql-client"
    ssh $VM2 "systemctl --user stop run-bypass4netnsd"
    ssh $VM2 "systemctl --user reset-failed"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd"
  ssh $VM2 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd"

  ssh $VM1 "nerdctl run --label nerdctl/bypass4netns=true -d -p 13306:3306 --name mysql-server -e MYSQL_ROOT_PASSWORD=pass -e MYSQL_DATABASE=bench $MYSQL_IMAGE"
  ssh $VM2 "nerdctl run --label nerdctl/bypass4netns=true -d --name mysql-client $BENCH_IMAGE sleep infinity"
  sleep 40
  LOG_NAME="mysql-b4ns-pfd-$DATE.log"
  ssh $VM2 "nerdctl exec mysql-client sysbench --threads=4 --time=60 --mysql-host=$VM1_ADDR --mysql-port=13306 --mysql-db=bench --mysql-user=root --mysql-password=pass --db-driver=mysql oltp_common prepare"
  ssh $VM2 "nerdctl exec mysql-client sysbench --threads=4 --time=$TIME --mysql-host=$VM1_ADDR --mysql-port=13306 --mysql-db=bench --mysql-user=root --mysql-password=pass --db-driver=mysql oltp_read_write run" > $LOG_NAME

  cleanup
  sleep 3
)

echo "===== Benchmark: mysql rootful via VXLAN ====="
(
  function cleanup () {
    ssh $VM1 "sudo nerdctl rm -f mysql-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "sudo nerdctl rm -f mysql-client"

    ssh $VM1 "sudo ip link del vxlan0"
    ssh $VM1 "sudo ip link del br-vxlan"
    ssh $VM2 "sudo ip link del vxlan0"
    ssh $VM2 "sudo ip link del br-vxlan"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "sudo nerdctl run -d --name mysql-server -e MYSQL_ROOT_PASSWORD=pass -e MYSQL_DATABASE=bench $MYSQL_IMAGE"
  ssh $VM2 "sudo nerdctl run -d --name mysql-client $BENCH_IMAGE sleep infinity"
  sleep 40

  CONTAINER_PID=$(ssh $VM1 "sudo nerdctl inspect mysql-server | jq '.[0].State.Pid'")
  ssh $VM1 "sudo $B4NS_PATH/bench-vms/setup_vxlan.sh 1 $CONTAINER_PID enp2s0 $VM1_VXLAN_MAC $VM1_VXLAN_ADDR $VM2_ADDR $VM2_VXLAN_MAC $VM2_VXLAN_ADDR"
  CONTAINER_PID=$(ssh $VM2 "sudo nerdctl inspect mysql-client | jq '.[0].State.Pid'")
  ssh $VM2 "sudo $B4NS_PATH/bench-vms/setup_vxlan.sh 1 $CONTAINER_PID enp2s0 $VM2_VXLAN_MAC $VM2_VXLAN_ADDR $VM1_ADDR $VM1_VXLAN_MAC $VM1_VXLAN_ADDR"
  LOG_NAME="mysql-rootful-vxlan-$DATE.log"
  ssh $VM2 "sudo nerdctl exec mysql-client sysbench --threads=4 --time=60 --mysql-host=$VM1_VXLAN_ADDR --mysql-port=3306 --mysql-db=bench --mysql-user=root --mysql-password=pass --db-driver=mysql oltp_common prepare"
  ssh $VM2 "sudo nerdctl exec mysql-client sysbench --threads=4 --time=$TIME --mysql-host=$VM1_VXLAN_ADDR --mysql-port=3306 --mysql-db=bench --mysql-user=root --mysql-password=pass --db-driver=mysql oltp_read_write run" > $LOG_NAME

  cleanup
  sleep 3
)

echo "===== Benchmark: mysql rootless via VXLAN ====="
(
  function cleanup () {
    ssh $VM1 "nerdctl rm -f mysql-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "nerdctl rm -f mysql-client"
  }
  set +e
  cleanup
  set -ex

  ssh $VM1 "nerdctl run -p 4789:4789/udp --privileged -d --name mysql-server -e MYSQL_ROOT_PASSWORD=pass -e MYSQL_DATABASE=bench $MYSQL_IMAGE"
  ssh $VM2 "nerdctl run -p 4789:4789/udp --privileged -d --name mysql-client $BENCH_IMAGE sleep infinity"
  sleep 40

  CONTAINER_PID=$(ssh $VM1 "nerdctl inspect mysql-server | jq '.[0].State.Pid'")
  ssh $VM1 "$B4NS_PATH/bench-vms/setup_vxlan.sh $CONTAINER_PID $CONTAINER_PID eth0 $VM1_VXLAN_MAC $VM1_VXLAN_ADDR $VM2_ADDR $VM2_VXLAN_MAC $VM2_VXLAN_ADDR"
  CONTAINER_PID=$(ssh $VM2 "nerdctl inspect mysql-client | jq '.[0].State.Pid'")
  ssh $VM2 "$B4NS_PATH/bench-vms/setup_vxlan.sh $CONTAINER_PID $CONTAINER_PID eth0 $VM2_VXLAN_MAC $VM2_VXLAN_ADDR $VM1_ADDR $VM1_VXLAN_MAC $VM1_VXLAN_ADDR"
  sleep 5
  LOG_NAME="mysql-rootless-vxlan-$DATE.log"
  ssh $VM2 "nerdctl exec mysql-client sysbench --threads=4 --time=60 --mysql-host=$VM1_VXLAN_ADDR --mysql-port=3306 --mysql-db=bench --mysql-user=root --mysql-password=pass --db-driver=mysql oltp_common prepare"
  ssh $VM2 "nerdctl exec mysql-client sysbench --threads=4 --time=$TIME --mysql-host=$VM1_VXLAN_ADDR --mysql-port=3306 --mysql-db=bench --mysql-user=root --mysql-password=pass --db-driver=mysql oltp_read_write run" > $LOG_NAME

  cleanup
  sleep 3
)

echo "===== Benchmark: mysql client(w/ bypass4netns) server(w/ bypass4netns) with multinode ====="
(
  function cleanup {
    ssh $VM1 "nerdctl rm -f mysql-server"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM1 "systemctl --user stop run-bypass4netnsd"
    ssh $VM1 "systemctl --user stop etcd.service"
    ssh $VM1 "systemctl --user reset-failed"
    ssh $VM2 "nerdctl rm -f mysql-client"
    ssh $VM2 "systemctl --user stop run-bypass4netnsd"
    ssh $VM2 "systemctl --user reset-failed"
  }

  set +e
  cleanup
  set -ex

  ssh $VM1 "systemd-run --user --unit etcd.service /usr/bin/etcd --listen-client-urls http://$VM1_ADDR:2379 --advertise-client-urls http://$VM1_ADDR:2379"
  ssh $VM1 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd --multinode=true --multinode-etcd-address=http://$VM1_ADDR:2379 --multinode-host-address=$VM1_ADDR"
  ssh $VM2 "systemd-run --user --unit run-bypass4netnsd bypass4netnsd --multinode=true --multinode-etcd-address=http://$VM1_ADDR:2379 --multinode-host-address=$VM2_ADDR"
  ssh $VM1 "nerdctl run --label nerdctl/bypass4netns=true -d -p 13306:3306 --name mysql-server -e MYSQL_ROOT_PASSWORD=pass -e MYSQL_DATABASE=bench $MYSQL_IMAGE"
  ssh $VM2 "nerdctl run --label nerdctl/bypass4netns=true -d --name mysql-client $BENCH_IMAGE sleep infinity"
  SERVER_IP=$(ssh $VM1 "nerdctl inspect mysql-server" | jq -r .[0].NetworkSettings.Networks.'"unknown-eth0"'.IPAddress)
  sleep 40

  LOG_NAME="mysql-b4ns-multinode-$DATE.log"
  ssh $VM2 "nerdctl exec mysql-client sysbench --threads=4 --time=60 --mysql-host=$SERVER_IP --mysql-port=3306 --mysql-db=bench --mysql-user=root --mysql-password=pass --db-driver=mysql oltp_common prepare"
  ssh $VM2 "nerdctl exec mysql-client sysbench --threads=4 --time=$TIME --mysql-host=$SERVER_IP --mysql-port=3306 --mysql-db=bench --mysql-user=root --mysql-password=pass --db-driver=mysql oltp_read_write run" > $LOG_NAME

  cleanup
)
