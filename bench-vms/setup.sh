#!/bin/bash

function setup() {
    pushd ../../
    rsync -avh bypass4netns/ $1:$B4NS_PATH
    popd
    ssh $1 "source ~/.profile && cd $B4NS_PATH && make && sudo make install"
}

function restart_services() {
    ssh $1 "sudo loginctl enable-linger $2"
    ssh $1 "systemctl --user restart containerd"
    ssh $1 "sudo systemctl restart containerd"
    ssh $1 "systemctl --user restart buildkit"
    ssh $1 "sudo systemctl restart buildkit"
}

set -eux

cd $(dirname $0)
. ./param.bash

rm -rf ./block/blk-*

setup $VM1
setup $VM2

restart_services $VM1 $USER
restart_services $VM2 $USER