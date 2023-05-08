import { easepick, RangePlugin } from '@easepick/bundle';

window.addEventListener('load', (event) => {

  const datePickerFields = document.querySelectorAll('.datetimefilter');

  datePickerFields.forEach(function (pickerField) {

    const picker = new easepick.create({
      element: pickerField,
      css: [
        'https://cdn.jsdelivr.net/npm/@easepick/core@1.2.1/dist/index.css',
        'https://cdn.jsdelivr.net/npm/@easepick/range-plugin@1.2.1/dist/index.css',
      ],
      plugins: [RangePlugin],
    });

  });




});
