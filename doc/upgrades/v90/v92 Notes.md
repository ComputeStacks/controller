# v9.2 Update Notes

Starting with v9.2, we added yjit and jemalloc for reduce memory usage in our controller. To fully enable this, you'll need to add the following to the `/etc/default/computestacks` file on the controller:

```
MALLOC_CONF=dirty_decay_ms:1000,narenas:2,background_thread:true,stats_print:false
RUBY_YJIT_ENABLE=1
```

_Here is a helper script to add those to your environments file_:

```bash
cat << 'EOF' >> /etc/default/computestacks

MALLOC_CONF=dirty_decay_ms:1000,narenas:2,background_thread:true,stats_print:false
RUBY_YJIT_ENABLE=1

EOF
```

You will also need to download our latest helper script with:

```bash
wget -O /usr/local/bin/cstacks https://raw.githubusercontent.com/ComputeStacks/ansible-install/main/roles/controller/files/cstacks.sh \
  && chmod +x /usr/local/bin/cstacks
```
