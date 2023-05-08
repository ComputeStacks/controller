# v8.0 to v8.1 Developer Changes

* Yarn, NPM, and WebPack are no longer used. All external dependencies are handled through importmaps.
* Passenger is no longer the application server used, we're using puma now.
* The Docker image now includes nginx along with puma. Previously passenger included a bundled version of nginx.
