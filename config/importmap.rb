# Pin npm packages by running ./bin/importmap

pin "application", preload: true
pin "@github/webauthn-json", to: "https://ga.jspm.io/npm:@github/webauthn-json@2.1.1/dist/esm/webauthn-json.js"
pin "sortablejs", to: "https://ga.jspm.io/npm:sortablejs@1.15.0/modular/sortable.esm.js"
pin "process" # @2.0.1
pin "chosen-js", preload: true # @1.8.7
pin "js-cookie", to: "https://ga.jspm.io/npm:js-cookie@3.0.5/dist/js.cookie.mjs"
pin "chartkick", to: "chartkick.js"
pin "Chart.bundle", to: "Chart.bundle.js"
pin_all_from "app/javascript/legacy", under: "legacy"
pin_all_from "app/javascript/src", under: "src"
pin "jstz", preload: true # @2.1.1
pin "bootstrap-sass", preload: true # @3.4.3
pin "@rails/ujs", to: "https://ga.jspm.io/npm:@rails/ujs@7.0.4-3/lib/assets/compiled/rails-ujs.js"
pin "trix", to: "https://ga.jspm.io/npm:trix@2.0.4/dist/trix.esm.min.js"
pin "jquery", to: "https://code.jquery.com/jquery-3.6.4.min.js", preload: true
pin "@easepick/bundle", to: "https://ga.jspm.io/npm:@easepick/bundle@1.2.1/dist/index.esm.js"
