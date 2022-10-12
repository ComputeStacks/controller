FROM ruby:3.1

ARG github_user
ARG github_token

RUN set -ex; \
    \
    apt-get update; \
    apt-get install -y \
            redis \
    ; \
    redis-cli -h localhost PING
