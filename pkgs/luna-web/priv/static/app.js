// Connect the LiveView socket. phoenix.min.js and phoenix_live_view.min.js
// load first and set the globals Phoenix and LiveView.
(function () {
  "use strict";
  var token = document.querySelector("meta[name='csrf-token']").getAttribute("content");
  var socket = new LiveView.LiveSocket("/live", Phoenix.Socket, { params: { _csrf_token: token } });
  socket.connect();
})();
