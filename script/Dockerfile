FROM notriddle/docker-phoenix-elixir-test@sha256:7d246544ba92515f5e691ad30bee6abfd05392b1b9c6c90de45111d6891cd48a
MAINTAINER "Michael Howell <michael@notriddle.com>"
EXPOSE 8000
ENV BORS_WITHIN_DOCKER 1
ENV WORKSPACE /home/user/bors-ng
ENV PORT 8000

USER user
WORKDIR /home/user
RUN git clone https://github.com/bors-ng/bors-ng
WORKDIR /home/user/bors-ng
RUN (sudo runuser -u postgres -- /usr/lib/postgresql/12/bin/postgres -D /etc/postgresql/12/main/ 2>&1 > /dev/null &) && \
    sleep 1 && \
    mix do deps.get, ecto.create, ecto.migrate, compile && \
    npm install && \
    cp /home/user/bors-ng/script/janitor.json /home/user/janitor.json
