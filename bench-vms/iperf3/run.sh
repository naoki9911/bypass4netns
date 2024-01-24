#!/bin/bash

set -eu

cd $(dirname $0)

#PARALLEL=(1 2 4 8)
PARALLEL=(4 8)
for i in ${PARALLEL[@]}; do 
	echo "benchmarking with -P=$i"
	for j in $(seq 0 9); do
		./iperf3.sh $i
	done
done
