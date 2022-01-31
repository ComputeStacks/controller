# ComputeStacks Vagrantfile

1. Copy `envrc.sample` to `.envrc` and update values appropriately.
2. Copy `lib/dev/vagrant/Vagrantfile.sample` (or specific version such as digital ocean or parallels) to `Vagrantfile` (In your project root) and update settings to match your environment. This could include using a different provider than the default Virtualbox.
3. Bring up with `vagrant up`. This will take a few minutes depending on your computer -- compiling ruby takes a bit.
4. Once up, enter the VM with `vagrant ssh` and `cd ~/controller` and run:
    a. `direnv allow .`
    b. `bundle` -- if you did not setup your `.envrc` correctly, you will get an authorization error. Our provision script will automatically take the credentials in your `.envrc` file and authenticate with Github, but please also reference this document if you run into issues: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-rubygems-registry

5. Once all the gems have been installed, bootstrap your database with:
    a. `bundle exec rails db:create`
    b. `bundle exec rails db:schema:load`
    c. `bundle exec rails db:seed`
6. (optional) Run our test suite with: `bundle exec rails test`

You may now launch ComputeStacks by running `overmind s` from the ~/controller directory within the vagrant vm.

Next, proceed to your browser and visit http://localhost:3005 -- the default credentials are `admin@cstacks.local` / `changeme!`
