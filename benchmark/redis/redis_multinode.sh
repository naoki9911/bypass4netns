#!/bin/bash

cd $(dirname $0)
. ../../test/util.sh

set +e
NAME="test" exec_lxc sudo nerdctl rm -f redis-server
NAME="test" exec_lxc nerdctl rm -f redis-server
sudo lxc rm -f test2

TEST1_VXLAN_MAC="02:42:c0:a8:00:1"
TEST1_VXLAN_ADDR="192.168.2.1"
TEST2_VXLAN_MAC="02:42:c0:a8:00:2"
TEST2_VXLAN_ADDR="192.168.2.2"
REDIS_VERSION=7.2.3
REDIS_IMAGE="redis:${REDIS_VERSION}"

set -eux -o pipefail

NAME="test" exec_lxc sudo nerdctl pull --quiet $REDIS_IMAGE
NAME="test" exec_lxc nerdctl pull --quiet $REDIS_IMAGE

sudo lxc stop test
sudo lxc copy test test2
sudo lxc start test
sudo lxc start test2
sleep 5

TEST_ADDR=$(sudo lxc exec test -- hostname -I | sed 's/ //')
TEST2_ADDR=$(sudo lxc exec test2 -- hostname -I | sed 's/ //')

echo "===== Benchmark: redis rootful with multinode via VXLAN ====="
(
  NAME="test" exec_lxc /bin/bash -c "sleep 3 && sudo nerdctl run -p 4789:4789/udp --privileged --name redis-server -d $REDIS_IMAGE"
  NAME="test" exec_lxc sudo /home/ubuntu/bypass4netns/test/setup_vxlan.sh redis-server $TEST1_VXLAN_MAC $TEST1_VXLAN_ADDR $TEST2_ADDR $TEST2_VXLAN_MAC $TEST2_VXLAN_ADDR
  NAME="test2" exec_lxc /bin/bash -c "sleep 3 && sudo nerdctl run -p 4789:4789/udp --privileged --name redis-client -d $REDIS_IMAGE  sleep infinity"
  NAME="test2" exec_lxc sudo /home/ubuntu/bypass4netns/test/setup_vxlan.sh redis-client $TEST2_VXLAN_MAC $TEST2_VXLAN_ADDR $TEST_ADDR $TEST1_VXLAN_MAC $TEST1_VXLAN_ADDR
  NAME="test2" exec_lxc sudo nerdctl exec redis-client redis-benchmark -q -h $TEST1_VXLAN_ADDR --csv > redis-multinode-rootful.log
  
  NAME="test" exec_lxc sudo nerdctl rm -f redis-server
  NAME="test2" exec_lxc sudo nerdctl rm -f redis-client
)

echo "===== Benchmark: redis client(w/o bypass4netns) server(w/o bypass4netns) with multinode via VXLAN ====="
(
  NAME="test" exec_lxc /bin/bash -c "sleep 3 && nerdctl run -p 4789:4789/udp --privileged --name redis-server -d $REDIS_IMAGE"
  NAME="test" exec_lxc /home/ubuntu/bypass4netns/test/setup_vxlan.sh redis-server $TEST1_VXLAN_MAC $TEST1_VXLAN_ADDR $TEST2_ADDR $TEST2_VXLAN_MAC $TEST2_VXLAN_ADDR
  NAME="test2" exec_lxc /bin/bash -c "sleep 3 && nerdctl run -p 4789:4789/udp --privileged --name redis-client -d $REDIS_IMAGE  sleep infinity"
  NAME="test2" exec_lxc /home/ubuntu/bypass4netns/test/setup_vxlan.sh redis-client $TEST2_VXLAN_MAC $TEST2_VXLAN_ADDR $TEST_ADDR $TEST1_VXLAN_MAC $TEST1_VXLAN_ADDR
  NAME="test2" exec_lxc nerdctl exec redis-client redis-benchmark -q -h $TEST1_VXLAN_ADDR --csv > redis-multinode-wo-b4ns.log
  
  NAME="test" exec_lxc nerdctl rm -f redis-server
  NAME="test2" exec_lxc nerdctl rm -f redis-client
)

echo "===== Benchmark: redis client(w/ bypass4netns) server(w/ bypass4netns) with multinode ====="
(
  NAME="test" exec_lxc systemd-run --user --unit etcd.service /usr/bin/etcd --listen-client-urls http://$TEST_ADDR:2379 --advertise-client-urls http://$TEST_ADDR:2379
  NAME="test" exec_lxc systemd-run --user --unit run-bypass4netnsd bypass4netnsd --multinode=true --multinode-etcd-address=http://$TEST_ADDR:2379 --multinode-host-address=$TEST_ADDR
  NAME="test2" exec_lxc systemd-run --user --unit run-bypass4netnsd bypass4netnsd --multinode=true --multinode-etcd-address=http://$TEST_ADDR:2379 --multinode-host-address=$TEST2_ADDR
  NAME="test" exec_lxc /bin/bash -c "sleep 3 && nerdctl run --annotation nerdctl/bypass4netns=true -d -p 6380:6379 --name redis-server $REDIS_IMAGE"
  SERVER_IP=$(NAME="test" exec_lxc nerdctl exec redis-server hostname -i)
  NAME="test2" exec_lxc /bin/bash -c "sleep 3 && nerdctl run --annotation nerdctl/bypass4netns=true -d --name redis-client $REDIS_IMAGE sleep infinity"
  NAME="test2" exec_lxc nerdctl exec redis-client /bin/sh -c "sleep 1 && redis-benchmark -q -h $SERVER_IP --csv" > redis-multinode-w-b4ns.log

  NAME="test" exec_lxc nerdctl rm -f redis-server
  NAME="test2" exec_lxc nerdctl rm -f redis-client
)
