#!/bin/bash

set -eux

cd $(dirname $0)
. ./param.bash

ssh b4ns-1 sudo ip a add 192.168.6.1/24 dev $INTERFACE
ssh b4ns-2 sudo ip a add 192.168.6.2/24 dev $INTERFACE

ssh b4ns-1 $B4NS_PATH/test/run_test.sh
