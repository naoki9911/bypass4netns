#!/bin/bash

systemctl --user stop run-iperf3-netns.service
systemctl --user reset-failed
nerdctl rm -f test-4
