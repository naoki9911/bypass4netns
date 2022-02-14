#!/bin/bash

# Arguments
# $0: destination IP address (Host IP)
# $1: destination port

set -eu -o pipefail

SCRIPT_DIR=$(cd $(dirname $0); pwd)
cd $SCRIPT_DIR

cd client
go build -a -tags "netgo" -installsuffix netgo -ldflags="-s -w -extldflags \"-static\"" .
cd ../

HOST_IP=$1
HOST_PORT=$2

TRY_NUM=100000

ALPINE_IMAGE="alpine:benchmark"
CONTAINER_NAME="test-benchmark"
nerdctl image build -t $ALPINE_IMAGE .

systemd-run --user --unit run-b4nnd bypass4netnsd

nerdctl run -d --name $CONTAINER_NAME ${ALPINE_IMAGE} sleep infinity
nerdctl exec $CONTAINER_NAME multitime -n 10 /tmp/client/client --dst-ip $HOST_IP --dst-port $HOST_PORT  --try-num $TRY_NUM
nerdctl rm -f $CONTAINER_NAME

nerdctl run -d --label nerdctl/bypass4netns=true --name $CONTAINER_NAME ${ALPINE_IMAGE} sleep infinity
nerdctl exec $CONTAINER_NAME multitime -n 10 /tmp/client/client --dst-ip $HOST_IP --dst-port $HOST_PORT  --try-num $TRY_NUM
nerdctl rm -f $CONTAINER_NAME

systemctl stop --user run-b4nnd
