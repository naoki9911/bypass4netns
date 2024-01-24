#!/bin/bash

set -eu -o pipefail

cd $(dirname $0)

source ~/.profile
. ../param.bash

IMAGE_NAME="iperf3"
# sometimes fail to pull images
# this is workaround
# https://github.com/containerd/nerdctl/issues/622
systemctl --user restart containerd
sleep 1
systemctl --user restart buildkit
sleep 3
systemctl --user status --no-pager containerd
systemctl --user status --no-pager buildkit

sudo nerdctl build -f ./Dockerfile -t $IMAGE_NAME .
nerdctl build -f ./Dockerfile -t $IMAGE_NAME .

echo "===== Benchmark: iperf3 rootful via NetNS ====="
(
  set +e
  sudo nerdctl rm -f iperf3-server
  sudo nerdctl rm -f iperf3-client
  set -ex

  sudo nerdctl run -d --name iperf3-server $IMAGE_NAME iperf3 -s
  SERVER_IP=$(sudo nerdctl exec iperf3-server hostname -i)

  sleep 1
  sudo nerdctl run --name iperf3-client $IMAGE_NAME iperf3 -c $SERVER_IP -i 0 --connect-timeout 1000 -J > iperf3-rootful-direct.log

  sudo nerdctl rm -f iperf3-server
  sudo nerdctl rm -f iperf3-client
)

echo "===== Benchmark: iperf3 rootful via host ====="
(
  set +e
  sudo nerdctl rm -f iperf3-server
  sudo nerdctl rm -f iperf3-client
  set -ex

  sudo nerdctl run -d --name iperf3-server -p 5202:5201 $IMAGE_NAME iperf3 -s
  SERVER_IP=$(sudo nerdctl exec iperf3-server hostname -i)

  sleep 1
  sudo nerdctl run --name iperf3-client $IMAGE_NAME iperf3 -c $HOST_IP -p 5202 -i 0 --connect-timeout 1000 -J > iperf3-rootful-host.log

  sudo nerdctl rm -f iperf3-server
  sudo nerdctl rm -f iperf3-client
)

echo "===== Benchmark: iperf3 client(w/o bypass4netns) server(w/o bypass4netns) via intermediate NetNS ====="
(
  set +e
  nerdctl rm -f iperf3-server
  nerdctl rm -f iperf3-client
  set -ex

  nerdctl run -d --name iperf3-server $IMAGE_NAME iperf3 -s
  SERVER_IP=$(nerdctl exec iperf3-server hostname -i)

  sleep 1
  nerdctl run --name iperf3-client $IMAGE_NAME iperf3 -c $SERVER_IP -i 0 --connect-timeout 1000 -J > iperf3-wo-b4ns-direct.log

  nerdctl rm -f iperf3-server
  nerdctl rm -f iperf3-client
  systemctl --user reset-failed
)

echo "===== Benchmark: iperf3 client(w/o bypass4netns) server(w/o bypass4netns) via host ====="
(
  set +e
  nerdctl rm -f iperf3-server
  nerdctl rm -f iperf3-client
  set -ex

  nerdctl run -d --name iperf3-server -p 5202:5201 $IMAGE_NAME iperf3 -s

  sleep 1
  nerdctl run --name iperf3-client $IMAGE_NAME iperf3 -c $HOST_IP -p 5202 -i 0 --connect-timeout 1000 -J > iperf3-wo-b4ns-host.log

  nerdctl rm -f iperf3-server
  nerdctl rm -f iperf3-client
)

echo "===== Benchmark: iperf3 client(w/ bypass4netns) server(w/ bypass4netns) via host ====="
(
  set +e
  nerdctl rm -f iperf3-server
  nerdctl rm -f iperf3-client
  systemctl --user stop run-bypass4netnsd
  systemctl --user reset-failed
  set -ex

  systemd-run --user --unit run-bypass4netnsd bypass4netnsd 

  nerdctl run --label nerdctl/bypass4netns=true -d --name iperf3-server -p 5202:5201 $IMAGE_NAME iperf3 -s

  sleep 1
  nerdctl run --label nerdctl/bypass4netns=true --name iperf3-client $IMAGE_NAME iperf3 -c $HOST_IP -p 5202 -i 0 --connect-timeout 1000 -J > iperf3-w-b4ns.log

  nerdctl rm -f iperf3-server
  nerdctl rm -f iperf3-client
  systemctl --user stop run-bypass4netnsd
  systemctl --user reset-failed
)

echo "===== Benchmark: iperf3 client(w/ bypass4netns) server(w/ bypass4netns) with multinode ====="
(
  set +e
  nerdctl rm -f iperf3-server
  nerdctl rm -f iperf3-client
  systemctl --user stop run-bypass4netnsd
  systemctl --user stop etcd.service
  systemctl --user reset-failed
  set -ex

  systemd-run --user --unit etcd.service /usr/bin/etcd --listen-client-urls http://$HOST_IP:2379 --advertise-client-urls http://$HOST_IP:2379
  systemd-run --user --unit run-bypass4netnsd bypass4netnsd --multinode=true --multinode-etcd-address=http://$HOST_IP:2379 --multinode-host-address=$HOST_IP

  nerdctl run --label nerdctl/bypass4netns=true -d --name iperf3-server -p 5202:5201 $IMAGE_NAME iperf3 -s
  SERVER_IP=$(nerdctl exec iperf3-server hostname -i)

  sleep 1
  nerdctl run --label nerdctl/bypass4netns=true --name iperf3-client $IMAGE_NAME iperf3 -c $SERVER_IP -i 0 --connect-timeout 1000

  nerdctl rm -f iperf3-server
  nerdctl rm -f iperf3-client
  systemctl --user stop run-bypass4netnsd
  systemctl --user stop etcd.service
  systemctl --user reset-failed
)
