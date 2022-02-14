FROM alpine:latest

RUN apk add make gcc g++
RUN wget -O multitime.tar.gz https://tratt.net/laurie/src/multitime/releases/multitime-1.4.tar.gz
RUN tar -xvf multitime.tar.gz
RUN cd multitime-1.4 && ./configure && make install
RUN rm -rf multitime-1.4 multitime.tar.gz

COPY . /tmp/

CMD ["/bin/sh" "-c" "sleep infinity"]
