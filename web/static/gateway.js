async function command(path) {
  const status = document.querySelector('#status');
  try {
    const response = await fetch(path, {method: 'POST', headers: {'X-Nultra-Request': '1'}});
    if (!response.ok || (await response.json()).status !== 'OK') throw Error('The gateway rejected the request.');
    status.textContent = 'Request accepted.';
    if (path.startsWith('/schedule/') || path.startsWith('/timer/')) location.reload();
  } catch (error) {
    status.textContent = error.message;
  }
}

document.addEventListener('click', event => {
  const button = event.target.closest('[data-command]');
  if (button) command(button.dataset.command);
});

document.addEventListener('submit', event => {
  event.preventDefault();
  const form = event.target;
  const data = new FormData(form);
  const values = form.dataset.fields.split(',').map(field => data.getAll(field).join(','));
  if (values.some(value => !value)) {
    document.querySelector('#status').textContent = 'Complete each field and choose at least one day.';
    return;
  }
  command([form.dataset.route, ...values.map(encodeURIComponent)].join('/'));
});

async function refresh() {
  if (document.hidden) return;
  try {
    const response = await fetch('/devices');
    if (!response.ok) return;
    const devices = await response.json();
    const detail = document.querySelector('[data-detail]');
    const cards = [...document.querySelectorAll('[data-switch]')];
    if (!detail && (cards.length !== devices.length || cards.some(card =>
      !devices.some(device => device.address === card.dataset.switch)))) {
      location.reload();
      return;
    }
    for (const device of devices) {
      const reading = (device.switch_state ? 'On' : 'Off') + ' · Battery ' + device.battery + '%';
      if (detail && detail.dataset.detail === device.address) {
        detail.textContent = reading + ' · ' + device.rssi + ' dBm';
        document.querySelector('h1').textContent = device.display_name;
      }
      const card = cards.find(item => item.dataset.switch === device.address);
      if (card) {
        card.querySelector('h2 a').textContent = device.display_name;
        card.querySelector('[data-reading]').textContent = reading + (device.seen_recently === 1 ? ' · Nearby' : ' · Last seen earlier');
      }
    }
    const progress = await fetch('/progress');
    if (progress.ok) document.querySelector('#progress').textContent = (await progress.json()).message || '';
  } catch {
    document.querySelector('#progress').textContent = 'Gateway unavailable.';
  }
}

async function poll() {
  await refresh();
  window.setTimeout(poll, 5000);
}
poll();
