import Cookies from 'js-cookie'
import jstz from 'jstz'

window.addEventListener('load', (event) => {

  Cookies.set('browser.timezone', jstz.determine().name(), {
    expires: 365,
    path: '/'
  });

});
