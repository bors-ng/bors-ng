FROM elixir:1.4.5
ENV LC_ALL=C.UTF-8
ENV MIX_ENV=dev
ADD https://deb.nodesource.com/gpgkey/nodesource.gpg.key /tmp/dockerfile/nodesource.gpg.key
WORKDIR /tmp/dockerfile
RUN echo "deb http://deb.nodesource.com/node_6.x jessie main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-key add nodesource.gpg.key && \
    apt-get update && \
    apt-get install -y nodejs build-essential libtool autoconf git inotify-tools
WORKDIR /srv
RUN mix local.hex --force && mix local.rebar --force
CMD mix phoenix.server
