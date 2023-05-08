// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import Rails from '@rails/ujs';
import 'jquery'
import "bootstrap-sass"
import "chartkick"
import "Chart.bundle"

import "legacy/bootstrap"

import "legacy/admin/deployments/container_domains"
import "legacy/admin/search"
import "legacy/deployments/certificates"
import "legacy/deployments/containers"
import "legacy/deployments/order"
import "legacy/dns/forward"
import "legacy/users/remotes"
import "legacy/container_domains"
import "legacy/container_registry"
import "legacy/deployments"
import "legacy/notifications"
import "legacy/sessions"
import "legacy/volumes"

import "src/credentials"
import "src/container_images/image_variants"
import "src/orders/variants"
import "src/orders/volumes"

import "src/utils/chosen"
import "src/utils/date-picker"
import "src/utils/multi-checkboxes"
import "src/utils/range-slider"
import "src/utils/remote-resource"
import "src/utils/trix"


Rails.start();
