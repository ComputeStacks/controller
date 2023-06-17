# ComputeStacks Plugins via Rails Engines

## Generate Plugin

```shell
./bin/rails plugin new engines/my_plugin --mountable
```

## Configure Plugin

Edit `engines/my_plugin/lib/my_plugin/engine.rb` and configure any view overrides.

_Example_

```ruby
ENGINE_VIEW_OVERRIDES[:service_dashboard] = 'my_plugin/container_services/show'
```

## Load Plugin

### Routes

```shell
cp config/routes/engines.rb.sample config/routes/engines.rb
```

Modify for your engines.

### Gemfile

Create `Gemfile` in the root of the application, and add your plugin as follows:

```ruby
eval_gemfile "Gemfile.common"
##
# List any engines below this section (ComputeStacks Plugins)
# !! DON'T FORGET TO RUN bundle install AFTER MAKING CHANGES !!
gem 'my_plugin', path: 'engines/my_plugin'
```

Edit `.envrc` and change `BUNDLE_GEMFILE=` to `Gemfile`.

Run `bundle` to install.
