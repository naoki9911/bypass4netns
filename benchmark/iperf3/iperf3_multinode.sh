#!/bin/bash

cd $(dirname $0)
. ../../test/util.sh

set +e
NAME="test" exec_lxc sudo nerdctl rm -f iperf3-server
NAME="test" exec_lxc nerdctl rm -f iperf3-server
sudo lxc rm -f test2

TEST1_VXLAN_MAC="02:42:c0:a8:00:1"
TEST1_VXLAN_ADDR="192.168.2.1"
TEST2_VXLAN_MAC="02:42:c0:a8:00:2"
TEST2_VXLAN_ADDR="192.168.2.2"

set -eux -o pipefail

IMAGE_NAME="iperf3"

NAME="test" exec_lxc systemctl --user restart containerd
sleep 1
NAME="test" exec_lxc systemctl --user restart buildkit
sleep 3
NAME="test" exec_lxc systemctl --user status --no-pager containerd
NAME="test" exec_lxc systemctl --user status --no-pager buildkit
NAME="test" exec_lxc /bin/bash -c "cd /home/ubuntu/bypass4netns/benchmark/iperf3 && sudo nerdctl build -f ./Dockerfile -t $IMAGE_NAME ."
NAME="test" exec_lxc /bin/bash -c "cd /home/ubuntu/bypass4netns/benchmark/iperf3 && nerdctl build -f ./Dockerfile -t $IMAGE_NAME ."

sudo lxc stop test
sudo lxc copy test test2
sudo lxc start test
sudo lxc start test2
sleep 5

TEST_ADDR=$(sudo lxc exec test -- hostname -I | sed 's/ //')
TEST2_ADDR=$(sudo lxc exec test2 -- hostname -I | sed 's/ //')

echo "===== Benchmark: iperf3 rootful with multinode via VXLAN ====="
(
  NAME="test" exec_lxc /bin/bash -c "sleep 3 && sudo nerdctl run -p 4789:4789/udp --privileged -d --name iperf3-server $IMAGE_NAME"
  NAME="test" exec_lxc sudo /home/ubuntu/bypass4netns/test/setup_vxlan.sh iperf3-server $TEST1_VXLAN_MAC $TEST1_VXLAN_ADDR $TEST2_ADDR $TEST2_VXLAN_MAC $TEST2_VXLAN_ADDR
  NAME="test2" exec_lxc /bin/bash -c "sleep 3 && sudo nerdctl run -p 4789:4789/udp --privileged -d --name iperf3-client $IMAGE_NAME"
  NAME="test2" exec_lxc sudo /home/ubuntu/bypass4netns/test/setup_vxlan.sh iperf3-client $TEST2_VXLAN_MAC $TEST2_VXLAN_ADDR $TEST_ADDR $TEST1_VXLAN_MAC $TEST1_VXLAN_ADDR

  NAME="test" exec_lxc systemd-run --user --unit iperf3-server sudo nerdctl exec iperf3-server iperf3 -s
  NAME="test2" exec_lxc sudo nerdctl exec iperf3-client iperf3 -c $TEST1_VXLAN_ADDR -i 0 --connect-timeout 1000 -J > iperf3-multinode-rootful.log
  
  NAME="test" exec_lxc sudo nerdctl rm -f iperf3-server
  NAME="test" exec_lxc systemctl --user reset-failed
  NAME="test2" exec_lxc sudo nerdctl rm -f iperf3-client
)

echo "===== Benchmark: iperf3 client(w/o bypass4netns) server(w/o bypass4netns) with multinode via VXLAN ====="
(
  NAME="test" exec_lxc /bin/bash -c "sleep 3 && nerdctl run -p 4789:4789/udp --privileged -d --name iperf3-server $IMAGE_NAME"
  NAME="test" exec_lxc /home/ubuntu/bypass4netns/test/setup_vxlan.sh iperf3-server $TEST1_VXLAN_MAC $TEST1_VXLAN_ADDR $TEST2_ADDR $TEST2_VXLAN_MAC $TEST2_VXLAN_ADDR
  NAME="test2" exec_lxc /bin/bash -c "sleep 3 && nerdctl run -p 4789:4789/udp --privileged -d --name iperf3-client $IMAGE_NAME"
  NAME="test2" exec_lxc /home/ubuntu/bypass4netns/test/setup_vxlan.sh iperf3-client $TEST2_VXLAN_MAC $TEST2_VXLAN_ADDR $TEST_ADDR $TEST1_VXLAN_MAC $TEST1_VXLAN_ADDR

  NAME="test" exec_lxc systemd-run --user --unit iperf3-server nerdctl exec iperf3-server iperf3 -s
  NAME="test2" exec_lxc nerdctl exec iperf3-client iperf3 -c $TEST1_VXLAN_ADDR -i 0 --connect-timeout 1000 -J > iperf3-multinode-wo-b4ns.log
  
  NAME="test" exec_lxc nerdctl rm -f iperf3-server
  NAME="test" exec_lxc systemctl --user reset-failed
  NAME="test2" exec_lxc nerdctl rm -f iperf3-client
)

echo "===== Benchmark: iperf3 client(w/ bypass4netns) server(w/ bypass4netns) with multinode ====="
(
  NAME="test" exec_lxc systemd-run --user --unit etcd.service /usr/bin/etcd --listen-client-urls http://$TEST_ADDR:2379 --advertise-client-urls http://$TEST_ADDR:2379
  NAME="test" exec_lxc systemd-run --user --unit run-bypass4netnsd bypass4netnsd --multinode=true --multinode-etcd-address=http://$TEST_ADDR:2379 --multinode-host-address=$TEST_ADDR
  NAME="test2" exec_lxc systemd-run --user --unit run-bypass4netnsd bypass4netnsd --multinode=true --multinode-etcd-address=http://$TEST_ADDR:2379 --multinode-host-address=$TEST2_ADDR
  NAME="test" exec_lxc /bin/bash -c "sleep 3 && nerdctl run --label nerdctl/bypass4netns=true -d -p 5202:5201 --name iperf3-server $IMAGE_NAME sleep infinity"
  NAME="test2" exec_lxc /bin/bash -c "sleep 3 && nerdctl run --label nerdctl/bypass4netns=true -d --name iperf3-client $IMAGE_NAME sleep infinity"

  SERVER_IP=$(NAME="test" exec_lxc nerdctl exec iperf3-server hostname -i)
  NAME="test" exec_lxc systemd-run --user --unit iperf3-server nerdctl exec iperf3-server iperf3 -s
  NAME="test2" exec_lxc nerdctl exec iperf3-client iperf3 -c $SERVER_IP -i 0 --connect-timeout 1000 -J > iperf3-multinode-w-b4ns.log

  NAME="test" exec_lxc nerdctl rm -f iperf3-server
  NAME="test2" exec_lxc nerdctl rm -f iperf3-client
)