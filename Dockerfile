FROM cm2network/steamcmd:root

LABEL org.opencontainers.image.source=https://github.com/Auhrus/pvn-theisle-server
LABEL maintainer="https://github.com/dinhquocmanh"

ENV GAME_DIR="/home/ubuntu/Steam/steamapps/common/The Isle Dedicated Server" \
    TZ=Asia/Ho_Chi_Minh

RUN apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates curl procps python3 tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p "$GAME_DIR" /home/ubuntu \
    && chown -R 1000:1000 /home/ubuntu

COPY --chown=1000:1000 configs/DefaultGame.ini /opt/theisle/DefaultGame.ini
COPY --chown=1000:1000 scripts/ /opt/theisle/scripts/
RUN chmod 0755 /opt/theisle/scripts/entry.sh /opt/theisle/scripts/backup.sh /opt/theisle/scripts/ram-monitor.sh

EXPOSE 7777/tcp 7777/udp 7778/udp 8888/tcp 10000/tcp

USER 1000:1000
WORKDIR /home/ubuntu
CMD ["/opt/theisle/scripts/entry.sh"]
