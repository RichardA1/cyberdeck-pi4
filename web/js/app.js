// CyberDeck — app.js
// MQTT Dashboard: connect, subscribe, publish, live message feed.
// Uses vendored Paho.Client / Paho.Message (NOT Paho.MQTT.Client).

var client = null;
var subscriptions = {};
var msgCount = 0;
var MAX_MESSAGES = 200;

function now() {
  var d = new Date();
  return d.toTimeString().split(' ')[0];
}

function addMsg(html) {
  var feed = document.getElementById('msg-feed');
  var div = document.createElement('div');
  div.className = 'msg';
  div.innerHTML = html;

  // Insert at top (newest first)
  if (feed.firstChild) {
    feed.insertBefore(div, feed.firstChild);
  } else {
    feed.appendChild(div);
  }

  msgCount++;
  document.getElementById('msg-count').textContent = msgCount + ' messages';

  // Trim old messages
  while (feed.children.length > MAX_MESSAGES) {
    feed.removeChild(feed.lastChild);
  }

  // Auto-scroll to top
  if (document.getElementById('auto-scroll').checked) {
    feed.scrollTop = 0;
  }
}

function sysMsg(text) {
  addMsg('<span class="msg-time">' + now() + ' </span><span class="msg-system">' + text + '</span>');
}

function setConnState(connected) {
  var badge = document.getElementById('conn-badge');
  var info = document.getElementById('conn-info');
  var btnC = document.getElementById('btn-connect');
  var btnD = document.getElementById('btn-disconnect');

  if (connected) {
    badge.textContent = 'Connected';
    badge.className = 'badge badge-green';
    info.textContent = 'ws://' + (window.location.hostname || '192.168.4.1') + ':9001/mqtt';
    btnC.disabled = true;
    btnD.disabled = false;
  } else {
    badge.textContent = 'Disconnected';
    badge.className = 'badge badge-red';
    info.textContent = '';
    btnC.disabled = false;
    btnD.disabled = true;
  }
}

function mqttConnect() {
  var host = window.location.hostname || '192.168.4.1';
  var clientId = 'cyberdeck-' + Math.random().toString(16).substr(2, 8);

  client = new Paho.Client(host, 9001, '/mqtt', clientId);

  client.onConnectionLost = function(resp) {
    setConnState(false);
    sysMsg('Connection lost: ' + (resp.errorMessage || 'unknown'));
    subscriptions = {};
    renderSubList();
  };

  client.onMessageArrived = function(msg) {
    var payload = msg.payloadString;
    // Truncate long payloads in display
    var display = payload.length > 200 ? payload.substring(0, 200) + '...' : payload;
    addMsg(
      '<span class="msg-time">' + now() + ' </span>' +
      '<span class="msg-topic">' + msg.destinationName + '</span><br>' +
      '<span class="msg-payload">' + escapeHtml(display) + '</span>'
    );
  };

  sysMsg('Connecting to ws://' + host + ':9001/mqtt ...');

  client.connect({
    onSuccess: function() {
      setConnState(true);
      sysMsg('Connected as ' + clientId);
    },
    onFailure: function(err) {
      setConnState(false);
      sysMsg('Connection failed: ' + (err.errorMessage || 'unknown'));
    },
    timeout: 10
  });
}

function mqttDisconnect() {
  if (client && client.isConnected()) {
    client.disconnect();
    sysMsg('Disconnected');
  }
  setConnState(false);
  subscriptions = {};
  renderSubList();
}

function doSubscribe() {
  if (!client || !client.isConnected()) {
    sysMsg('Not connected');
    return;
  }
  var topic = document.getElementById('sub-topic').value.trim();
  if (!topic) return;
  if (subscriptions[topic]) {
    sysMsg('Already subscribed to ' + topic);
    return;
  }
  client.subscribe(topic, {
    onSuccess: function() {
      subscriptions[topic] = true;
      sysMsg('Subscribed to ' + topic);
      renderSubList();
    },
    onFailure: function() {
      sysMsg('Failed to subscribe to ' + topic);
    }
  });
}

function doUnsubscribe() {
  if (!client || !client.isConnected()) {
    sysMsg('Not connected');
    return;
  }
  var topic = document.getElementById('sub-topic').value.trim();
  if (!topic) return;
  if (!subscriptions[topic]) {
    sysMsg('Not subscribed to ' + topic);
    return;
  }
  client.unsubscribe(topic, {
    onSuccess: function() {
      delete subscriptions[topic];
      sysMsg('Unsubscribed from ' + topic);
      renderSubList();
    },
    onFailure: function() {
      sysMsg('Failed to unsubscribe from ' + topic);
    }
  });
}

function renderSubList() {
  var el = document.getElementById('sub-list');
  var keys = Object.keys(subscriptions);
  if (keys.length === 0) {
    el.textContent = 'No active subscriptions';
    return;
  }
  el.innerHTML = 'Active: ' + keys.map(function(t) {
    return '<span style="color:var(--accent-cyan)">' + t + '</span>';
  }).join(', ');
}

function doPublish() {
  if (!client || !client.isConnected()) {
    sysMsg('Not connected');
    return;
  }
  var topic = document.getElementById('pub-topic').value.trim();
  var payload = document.getElementById('pub-payload').value;
  var qos = parseInt(document.getElementById('pub-qos').value, 10);
  var retain = document.getElementById('pub-retain').checked;

  if (!topic) {
    sysMsg('Publish topic is required');
    return;
  }

  var message = new Paho.Message(payload);
  message.destinationName = topic;
  message.qos = qos;
  message.retained = retain;
  client.send(message);

  sysMsg('Published to ' + topic + ' (QoS ' + qos + (retain ? ', retained' : '') + ')');
}

function clearFeed() {
  document.getElementById('msg-feed').innerHTML = '';
  msgCount = 0;
  document.getElementById('msg-count').textContent = '0 messages';
  sysMsg('Feed cleared');
}

function escapeHtml(str) {
  var div = document.createElement('div');
  div.appendChild(document.createTextNode(str));
  return div.innerHTML;
}

// Init
setConnState(false);
renderSubList();
