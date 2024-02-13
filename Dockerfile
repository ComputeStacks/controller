FROM ruby:3.3

LABEL maintainer="https://github.com/ComputeStacks"
LABEL org.opencontainers.image.authors="https://github.com/ComputeStacks"
LABEL org.opencontainers.image.source="https://github.com/ComputeStacks/controller"
LABEL org.opencontainers.image.url="https://github.com/ComputeStacks/controller"
LABEL org.opencontainers.image.title="ComputeStacks Controller"

ARG db_url="postgresql://cstacks:cstacks@localhost/cstacks?pool=30"
ARG redis_host=localhost

ENV DATABASE_URL=$db_url
ENV REDIS_HOST=$redis_host

ENV RACK_ENV=production
ENV RAILS_ENV=production
ENV SECRET_KEY_BASE=3a698257a1e32f1bb9b3fd861640c3b53cc9c57dd40b3fa360fed44d2e5da3fdb3351db2f8c881f2a04e6a7ca7e721de67d98061ffa7d394d3ad1c24ce9e09ec
ENV USER_AUTH_SECRET=3a698257a1e32f1bb9b3fd861640c3b53cc9c57dd40b3fa360fed44d2e5da3fdb3351db2f8c881f2a04e6a7ca7e721de67d98061ffa7d394d3ad1c24ce9e09ec
ENV LOCALE=en
ENV CURRENCY=USD
ENV RUBYOPT='-W:no-deprecated'
ENV APP_ID=build

RUN set -ex; \
    \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y \
            ca-certificates \
            wget \
            lsb-release \
            iputils-ping \
            vim \
            git \
            supervisor \
            nginx-light \
            libjemalloc2 \
            patchelf \
    ; \
    # Patch Ruby to use jemalloc
      patchelf --add-needed libjemalloc.so.2 /usr/local/bin/ruby; \
    # Discard patchelf after use
      apt-get purge -y \
        patchelf \
    ; \
    echo "set_real_ip_from 127.0.0.1;" > /etc/nginx/conf.d/restore_ip.conf \
    ; \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    ; \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
    ; \
    apt-get update && apt-get install -y nodejs \
      && corepack enable \
    ; \
    gem install -N puma sassc nokogiri \
    ; \
    mkdir -p /usr/src/app/vendor; \
    apt-get clean \
      && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /usr/src/app

ADD Gemfile* /usr/src/app/
ADD engines/ /usr/src/app/engines/

RUN bundle config set without 'test development' \
      ; \
      cd /usr/src/app \
        && if [ ! -f Gemfile ]; then mv Gemfile.common Gemfile; fi \
        && bundle install

COPY lib/build/nginx.conf /etc/nginx/sites-enabled/default
COPY lib/build/supervisord.conf /etc/supervisord.conf
COPY . /usr/src/app

RUN echo "$(cat VERSION)-$(git rev-parse --short --verify HEAD)" > VERSION \
        && bundle exec rails db:schema:load \
        && bundle exec rake generate_changelog \
        && bundle exec rake assets:precompile \
        && mkdir -p /usr/src/app/tmp/pids

EXPOSE 3000

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
