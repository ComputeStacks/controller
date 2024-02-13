set dotenv-load

# help
default:
    @just --list --justfile {{ justfile() }}

# build
build:
    docker pull ruby:3.2
    docker run -it -d --rm \
      --name cstacks-build-pg \
      -e POSTGRES_USER=cstacks \
      -e POSTGRES_DB=cstacks \
      -e POSTGRES_PASSWORD=cstacks \
      --health-cmd pg_isready \
      --health-interval 10s \
      --health-timeout 5s \
      --health-retries 5 \
      postgres:16-alpine
    until [ "`docker inspect -f {{{{.State.Health.Status}}}} cstacks-build-pg`"=="healthy" ]; do sleep 0.1; done;
    docker run -it -d --rm --network "container:cstacks-build-pg" --name cstacks-build-redis --health-cmd "redis-cli ping" --health-interval 10s --health-timeout 5s --health-retries 5 redis:alpine
    until [ "`docker inspect -f {{{{.State.Health.Status}}}} cstacks-build-redis`"=="healthy" ]; do sleep 0.1; done;
    DOCKER_BUILDKIT=0 docker build -t computestacks:dev --build-arg="github_user=$GITHUB_GEM_PULL_USER" --build-arg="github_token=$GITHUB_GEM_PULL_TOKEN" --network="container:cstacks-build-pg" .
    @docker stop cstacks-build-redis cstacks-build-pg

# If build failed, stop and remove dependencies.
clean:
  @docker stop cstacks-build-redis cstacks-build-pg
