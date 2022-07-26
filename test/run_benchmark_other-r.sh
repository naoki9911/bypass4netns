set -eux

HOST_IP="172.28.104.134"
ALPINE_IMAGE="alpine"
TEST_CONTAINER_NAME="test-4"

echo "===== Benchmark: netns -> host With bypass4netns ====="
(
 set -x

 sleep 1
 nerdctl run --label nerdctl/bypass4netns=true -d --name $TEST_CONTAINER_NAME "${ALPINE_IMAGE}" sleep infinity
 nerdctl exec $TEST_CONTAINER_NAME apk add --no-cache iperf3
 nerdctl exec $TEST_CONTAINER_NAME iperf3 -R -c $HOST_IP -t 60
 nerdctl rm -f $TEST_CONTAINER_NAME
 sleep 1
)

sleep 30

echo "===== Benchmark: netns -> host Without bypass4netns (for comparison) ====="
(
 set -x
 nerdctl run -d --name $TEST_CONTAINER_NAME "${ALPINE_IMAGE}" sleep infinity
 nerdctl exec $TEST_CONTAINER_NAME apk add --no-cache iperf3
 nerdctl exec $TEST_CONTAINER_NAME iperf3 -R -c $HOST_IP -t 60
 nerdctl rm -f $TEST_CONTAINER_NAME
 sleep 1
)

sleep 30

echo "===== Benchmark: netns -> host Rootful (for comparison) ====="
(
 set -x
 sudo nerdctl run -d --name $TEST_CONTAINER_NAME "${ALPINE_IMAGE}" sleep infinity
 sudo nerdctl exec $TEST_CONTAINER_NAME apk add --no-cache iperf3
 sudo nerdctl exec $TEST_CONTAINER_NAME iperf3 -R -c $HOST_IP -t 60
 sudo nerdctl rm -f $TEST_CONTAINER_NAME
 sleep 1
)

sleep 30

 echo "===== Benchmark: host -> netns With bypass4netns ====="
 (
  set -x
  nerdctl run --label nerdctl/bypass4netns=true -d --name $TEST_CONTAINER_NAME -p 8080:5201 "${ALPINE_IMAGE}" sleep infinity
  nerdctl exec $TEST_CONTAINER_NAME apk add --no-cache iperf3
  systemd-run --user --unit run-iperf3-netns nerdctl exec $TEST_CONTAINER_NAME iperf3 -s -4
  sleep 1 # waiting `iperf3 -s -4` becomes ready
  read
  nerdctl rm -f $TEST_CONTAINER_NAME
  systemctl --user stop run-iperf3-netns.service
  sleep 1
  systemctl --user reset-failed
 )

sleep 30

 echo "===== Benchmark: host -> netns Without bypass4netns (for comparison) ====="
 (
  set -x
  nerdctl run -d --name $TEST_CONTAINER_NAME -p 8080:5201 "${ALPINE_IMAGE}" sleep infinity
  nerdctl exec $TEST_CONTAINER_NAME apk add --no-cache iperf3
  systemd-run --user --unit run-iperf3-netns nerdctl exec $TEST_CONTAINER_NAME iperf3 -s -4
  sleep 1
  read
  nerdctl rm -f $TEST_CONTAINER_NAME
  systemctl --user stop run-iperf3-netns.service
  sleep 1
  #systemctl --user reset-failed
 )

sleep 30

 echo "===== Benchmark: host -> netns Rootful (for comparison) ====="
 (
  set -x
  sudo nerdctl run -d --name $TEST_CONTAINER_NAME -p 8080:5201 "${ALPINE_IMAGE}" sleep infinity
  sudo nerdctl exec $TEST_CONTAINER_NAME apk add --no-cache iperf3
  sudo systemd-run --unit run-iperf3-netns nerdctl exec $TEST_CONTAINER_NAME iperf3 -s -4
  sleep 1 # waiting `iperf3 -s -4` becomes ready
  read
  sudo nerdctl rm -f $TEST_CONTAINER_NAME
  sudo systemctl stop run-iperf3-netns.service
  sleep 1
  sudo systemctl reset-failed
 )