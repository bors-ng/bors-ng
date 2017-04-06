FROM ubuntu:trusty
ADD https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb /tmp/dockerfile/erlang-solutions.deb
ADD https://deb.nodesource.com/gpgkey/nodesource.gpg.key /tmp/dockerfile/nodesource.gpg.key
WORKDIR /tmp/dockerfile
RUN dpkg -i erlang-solutions.deb && \
    echo "deb http://deb.nodesource.com/node_6.x trusty main" | sudo tee /etc/apt/sources.list.d/nodesource.list && \
    apt-key add nodesource.gpg.key && \
    apt-get update && \
    apt-get install -y esl-erlang nodejs elixir build-essential libtool autoconf git && \
    mix local.hex --force && \
    mix local.rebar --force
WORKDIR /srv
ENV MIX_ENV=dev
CMD mix phoenix.server
