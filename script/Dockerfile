FROM notriddle/docker-phoenix-elixir-test@sha256:f3b3e932d2565135ac3d1efcb52f84ba72038228a6707638b533b1a0d9025e14
MAINTAINER "Michael Howell <michael@notriddle.com>"
EXPOSE 8000
ENV BORS_WITHIN_DOCKER 1
ENV WORKSPACE /home/user/bors-ng
ENV PORT 8000

USER user
WORKDIR /home/user
RUN git clone https://github.com/bors-ng/bors-ng
WORKDIR /home/user/bors-ng
RUN (sudo runuser -u postgres -- /usr/lib/postgresql/9.5/bin/postgres -D /etc/postgresql/9.5/main/ 2>&1 > /dev/null &) && \
    sleep 1 && \
    mix do deps.get, ecto.create, ecto.migrate, compile && \
    npm install && \
    cp /home/user/bors-ng/script/janitor.json /home/user/janitor.json
