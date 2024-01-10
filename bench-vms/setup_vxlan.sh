#!/bin/bash

cd $(dirname $0)
. ../util.sh


set -eux -o pipefail

OUTSIDE_PID=$1
INSIDE_PID=$2
INTERFACE=$3
LOCAL_VXLAN_MAC=$4
LOCAL_VXLAN_ADDR=$5
REMOTE_ADDR=$6
REMOTE_VXLAN_MAC=$7
REMOTE_VXLAN_ADDR=$8

set +e
PID=$OUTSIDE_PID exec_netns ip link del br-vxlan
PID=$OUTSIDE_PID exec_netns ip link del vxlan0
PID=$OUTSIDE_PID exec_netns ip link del vxlan-out
set -e

PID=$OUTSIDE_PID exec_netns ip link add br-vxlan type bridge
PID=$OUTSIDE_PID exec_netns ip link add vxlan0 type vxlan id 100 noproxy nolearning remote $REMOTE_ADDR dstport 4789 dev $INTERFACE
PID=$OUTSIDE_PID exec_netns ethtool -K vxlan0 tx-checksum-ip-generic off
PID=$OUTSIDE_PID exec_netns ip link add name vxlan-out type veth peer name vxlan-in
PID=$OUTSIDE_PID exec_netns ip link set vxlan-in netns $INSIDE_PID
PID=$OUTSIDE_PID exec_netns ip link set dev vxlan0 master br-vxlan
PID=$OUTSIDE_PID exec_netns ip link set dev vxlan-out master br-vxlan
PID=$OUTSIDE_PID exec_netns ip link set dev vxlan0 up
PID=$OUTSIDE_PID exec_netns ip link set dev vxlan-out up
PID=$OUTSIDE_PID exec_netns ip link set dev br-vxlan up
PID=$OUTSIDE_PID exec_netns bridge fdb add $REMOTE_VXLAN_MAC dev vxlan0 self dst $REMOTE_ADDR vni 100 port 4789

PID=$INSIDE_PID exec_netns ip a add $LOCAL_VXLAN_ADDR/24 dev vxlan-in
PID=$INSIDE_PID exec_netns ip link set dev vxlan-in address $LOCAL_VXLAN_MAC
PID=$INSIDE_PID exec_netns ip link set dev vxlan-in up
PID=$INSIDE_PID exec_netns ip neigh add $REMOTE_VXLAN_ADDR lladdr $REMOTE_VXLAN_MAC dev vxlan-in
