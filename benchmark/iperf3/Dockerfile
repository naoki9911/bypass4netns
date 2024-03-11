FROM ubuntu:22.04 as iperf3-builder

RUN apt update
RUN apt install -y build-essential wget
RUN wget https://github.com/esnet/iperf/releases/download/3.16/iperf-3.16.tar.gz -O iperf-3.16.tar.gz
RUN tar -xvf iperf-3.16.tar.gz -C /
COPY <<EOF /iperf3.patch
--- src/iperf_client_api.c      2023-11-30 04:46:13.000000000 +0900
+++ iperf_client_api.c  2024-01-31 21:20:54.183694039 +0900
@@ -786,6 +792,7 @@
     /* Cancel all outstanding threads */
     i_errno_save = i_errno;
     SLIST_FOREACH(sp, &test->streams, streams) {
+       if (!sp->done) {
         sp->done = 1;
         int rc;
         rc = pthread_cancel(sp->thr);
@@ -803,6 +810,7 @@
         if (test->debug_level >= DEBUG_LEVEL_INFO) {
             iperf_printf(test, "Thread FD %d stopped\n", sp->socket);
         }
+       }
     }
     if (test->debug_level >= DEBUG_LEVEL_INFO) {
         iperf_printf(test, "All threads stopped\n");
EOF

WORKDIR /iperf-3.16
RUN cd src && patch --ignore-whitespace < /iperf3.patch
RUN ./configure
RUN make

FROM ubuntu:22.04

COPY --from=iperf3-builder /iperf-3.16/src/.libs/libiperf.so.0.0.0 /lib/x86_64-linux-gnu/.
COPY --from=iperf3-builder /iperf-3.16/src/.libs/libiperf.so /lib/x86_64-linux-gnu/.
COPY --from=iperf3-builder /iperf-3.16/src/.libs/libiperf.so.0 /lib/x86_64-linux-gnu/.
COPY --from=iperf3-builder /iperf-3.16/src/.libs/iperf3 /usr/bin/iperf3

CMD ["/bin/bash", "-c", "sleep infinity"]