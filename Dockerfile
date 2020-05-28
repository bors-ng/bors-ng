ARG ELIXIR_VERSION=1.7.3
ARG SOURCE_COMMIT

FROM elixir:${ELIXIR_VERSION} as builder

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

RUN apt-get update -q && apt-get --no-install-recommends install -y apt-utils ca-certificates build-essential libtool autoconf curl git

RUN DEBIAN_CODENAME=$(sed -n 's/VERSION=.*(\(.*\)).*/\1/p' /etc/os-release) && \
    curl -q https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - && \
    echo "deb http://deb.nodesource.com/node_12.x $DEBIAN_CODENAME main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-get update -q && \
    apt-get --no-install-recommends install -y nodejs

RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix hex.info

WORKDIR /src
ADD ./ /src/

# Set default environment for building
ENV ALLOW_PRIVATE_REPOS=true
ENV MIX_ENV=prod

RUN mix deps.get
RUN cd /src/ && npm install && npm run deploy
RUN mix phx.digest
RUN mix distillery.release --env=$MIX_ENV

# Make the git HEAD available to the released app
RUN if [ -d .git ]; then \
        mkdir /src/_build/prod/rel/bors/.git && \
        git rev-parse --short HEAD > /src/_build/prod/rel/bors/.git/HEAD; \
    elif [ -n ${SOURCE_COMMIT} ]; then \
        mkdir /src/_build/prod/rel/bors/.git && \
        echo ${SOURCE_COMMIT} > /src/_build/prod/rel/bors/.git/HEAD; \
    fi

####

FROM debian:stretch-slim
RUN apt-get update -q && apt-get --no-install-recommends install -y git-core libssl1.1 curl apt-utils ca-certificates

ENV DOCKERIZE_VERSION=v0.6.0
RUN curl -Ls https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz | \
    tar xzv -C /usr/local/bin

ADD ./script/docker-entrypoint /usr/local/bin/bors-ng-entrypoint
COPY --from=builder /src/_build/prod/rel/ /app/

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV PORT=4000
ENV DATABASE_AUTO_MIGRATE=true
ENV ALLOW_PRIVATE_REPOS=true

WORKDIR /app
ENTRYPOINT ["/usr/local/bin/bors-ng-entrypoint"]
CMD ["./bors/bin/bors", "foreground"]

EXPOSE 4000
