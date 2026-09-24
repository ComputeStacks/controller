# ComputeStacks Controller

## Local Setup

Full walkthrough (workstation bootstrap, the separate node VM, and the
enrollment loop between them): [`doc/development.md`](doc/development.md).

Quick version, once `lib/dev/workstation.sh` has been run on the workstation
VM and `lib/dev/single-node.sh` has been run on the node VM (in that order —
`workstation.sh` generates the SSH keypair `single-node.sh` needs to trust):

1. Clone and set up local environment variables

```bash
git clone https://github.com/ComputeStacks/controller.git
cd controller
cp envrc.sample .envrc
```

Merge in the values `workstation.sh` generated into `~/computestacks-dev.env`
(`SECRET_KEY_BASE`, `USER_AUTH_SECRET`, `NODE_ENROLLMENT_TOKEN`, `CS_SSH_KEY`),
plus `DEV_VM_IP` (the node VM's address). Environment variables are loaded by
**mise** — `.mise.toml`'s `[env] _.file = '.envrc'` picks them up automatically
once you `cd` into the repo; there is no `direnv` step. `.mise.toml` is tracked
in git, so a fresh clone's copy is untrusted:

```bash
mise trust && mise install
```

2. Run local required containers

```bash
docker compose up -d
```

3. Bootstrap app

```bash
cp config/database.sample.yml config/database.yml
bundle install
./bin/rails db:setup
bundle exec rake setup_dev
```

4. Enroll the node

```bash
ssh root@<node-vm-ip> "bash single-node.sh --enroll-only --controller-ip <this-workstation-ip> \
  --vm-ip <node-vm-ip> --token '<the same NODE_ENROLLMENT_TOKEN>'"
```

5. Complete

```bash
./bin/dev
```

You should now be able to login locally to: `http://localhost:3005`
