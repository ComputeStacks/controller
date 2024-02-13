# Setup your Developer Environment

Ensure your local machine has the following installed and working:

  - docker & docker compose
    - For MacOS, we have tested this against [colima](https://github.com/abiosoft/colima). Make sure you start it with `--network-address`.
  - Ruby 3.2
    - Using `rbenv`: `rbenv install`. (from the root of the controller directory)
  - NodeJS 20-LTS
    - Using `nodenv`: `nodenv install`
  - Overmind process manager: [Overmind](https://github.com/DarthSim/overmind)


## Setup Containers and Node VM

First, create your `Vagrantfile` by `cp Vagrantfile.sample Vagrantfile` and make the necessary changes for your environment.

 - For Linux, we recommend using `libvirt`. You'll need to have a working installation of kvm, qemu, and libvirtd.
 - For Mac, we recommend vmware fusion and the vmware desktop plugin for vagrant. They offer a free non-commercial license.

```bash
docker compose up -d
vagrant up
```

## Environmental Variables

```bash
cp envrc.sample .envrc
```

Modify the values to match your needs. Once you're done with that, you can configure your GitHub authentication with something like:

```bash
bundle config https://rubygems.pkg.github.com/computestacks $GITHUB_GEM_PULL_USER:$GITHUB_GEM_PULL_TOKEN
```

Then install all the gems with: `bundle install`

## Bootstrap Application

```bash
./bin/rails db:setup
./bin/rake setup_dev
```

After all that, you should be able to run the test suite: `./bin/rails test`.

## Running

Run the controller with: `./bin/dev`.


