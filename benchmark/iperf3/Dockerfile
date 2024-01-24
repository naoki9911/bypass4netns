FROM ubuntu:22.04 as iperf3-builder

RUN apt update
RUN apt install -y build-essential wget
RUN wget https://github.com/esnet/iperf/releases/download/3.16/iperf-3.16.tar.gz -O iperf-3.16.tar.gz
RUN tar -xvf iperf-3.16.tar.gz -C /
WORKDIR /iperf-3.16
RUN ./configure
RUN make

FROM ubuntu:22.04

COPY --from=iperf3-builder /iperf-3.16/src/.libs/libiperf.so.0.0.0 /lib/x86_64-linux-gnu/.
COPY --from=iperf3-builder /iperf-3.16/src/.libs/libiperf.so /lib/x86_64-linux-gnu/.
COPY --from=iperf3-builder /iperf-3.16/src/.libs/libiperf.so.0 /lib/x86_64-linux-gnu/.
COPY --from=iperf3-builder /iperf-3.16/src/.libs/iperf3 /usr/bin/iperf3

CMD ["/bin/bash", "-c", "sleep infinity"]