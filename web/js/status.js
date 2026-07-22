// CyberDeck — status.js
// Fetches /status.json every 10s and renders the Server Overview page.

function gaugeColor(pct) {
  if (pct >= 90) return '#ff3366';
  if (pct >= 70) return '#ffaa00';
  return '#00ff41';
}

function setGauge(id, pct, label) {
  var fill = document.getElementById(id);
  var val = document.getElementById(id + '-val');
  if (!fill || !val) return;
  pct = Math.max(0, Math.min(100, pct));
  fill.style.width = pct + '%';
  fill.style.background = gaugeColor(pct);
  fill.style.boxShadow = '0 0 4px ' + gaugeColor(pct);
  val.textContent = label;
  val.style.color = gaugeColor(pct);
}

function formatUptime(sec) {
  var d = Math.floor(sec / 86400);
  var h = Math.floor((sec % 86400) / 3600);
  var m = Math.floor((sec % 3600) / 60);
  if (d > 0) return d + 'd ' + h + 'h';
  if (h > 0) return h + 'h ' + m + 'm';
  return m + 'm';
}

function renderServices(svcs) {
  var grid = document.getElementById('service-grid');
  if (!grid) return;
  var html = '';
  var names = {
    hostapd: 'hostapd',
    dnsmasq: 'dnsmasq',
    mosquitto: 'mosquitto',
    nginx: 'nginx',
    smbd: 'smbd',
    status_timer: 'status timer',
    shutdown_handler: 'shutdown api'
  };
  var upCount = 0;
  for (var key in names) {
    if (!svcs.hasOwnProperty(key)) continue;
    var state = svcs[key];
    var isUp = (state === 'active');
    if (isUp) upCount++;
    html += '<div class="service-item' + (isUp ? '' : ' down') + '">' +
      '<span class="service-name">' + names[key] + '</span>' +
      '<span class="service-status ' + (isUp ? 'active' : 'inactive') + '">● ' + state + '</span>' +
      '</div>';
  }
  grid.innerHTML = html;
  return upCount;
}

function loadStatus() {
  fetch('/status.json?t=' + Date.now())
    .then(function(r) { return r.json(); })
    .then(function(d) {
      // Header
      document.getElementById('header-status').textContent = 'ONLINE';

      // Subtitle
      var age = Math.round(Date.now() / 1000) - d.timestamp;
      document.getElementById('subtitle').textContent =
        d.hostname + ' · 192.168.4.1 · auto-refreshes every 10s · updated ' + age + 's ago';

      // Stat tiles
      document.getElementById('s-clients').textContent = d.ap_clients;
      document.getElementById('s-temp').textContent = d.cpu_temp + '°';
      document.getElementById('s-uptime').textContent = formatUptime(d.uptime_sec);

      // Info card
      document.getElementById('i-hostname').textContent = d.hostname;
      document.getElementById('i-uptime').textContent = d.uptime_human;

      // Gauges
      var tempPct = Math.min(100, (d.cpu_temp / 85) * 100);
      setGauge('g-temp', tempPct, d.cpu_temp + '°C');

      var loadPct = Math.min(100, (d.load / 4) * 100); // Pi4 = 4 cores
      setGauge('g-load', loadPct, d.load);

      var memPct = (d.mem_used_mb / d.mem_total_mb) * 100;
      setGauge('g-mem', memPct, d.mem_used_mb + ' / ' + d.mem_total_mb + ' MB');

      setGauge('g-disk', d.disk_pct, d.disk_pct + '%');

      // Services
      var upCount = renderServices(d.services);
      document.getElementById('s-services').textContent = upCount + '/7';
    })
    .catch(function() {
      document.getElementById('header-status').textContent = 'OFFLINE';
      document.getElementById('subtitle').textContent = 'Failed to load status.json';
    });
}

loadStatus();
setInterval(loadStatus, 10000);

// --- Shutdown button ---
function showShutdownConfirm() {
  document.getElementById('shutdown-confirm').classList.add('visible');
}

function hideShutdownConfirm() {
  document.getElementById('shutdown-confirm').classList.remove('visible');
}

function doShutdown() {
  var btn = document.getElementById('shutdown-btn');
  btn.textContent = 'SHUTTING DOWN...';
  btn.disabled = true;
  hideShutdownConfirm();

  fetch('/api/shutdown', { method: 'POST' })
    .then(function() {
      btn.textContent = 'SHUTDOWN SENT — POWERING OFF';
      btn.style.borderColor = '#ffaa00';
      btn.style.color = '#ffaa00';
    })
    .catch(function() {
      btn.textContent = 'SHUTDOWN SENT — POWERING OFF';
      btn.style.borderColor = '#ffaa00';
      btn.style.color = '#ffaa00';
    });
}
