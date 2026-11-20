// The LiveView socket and two hooks. phoenix.min.js and
// phoenix_live_view.min.js load first and set the globals Phoenix and LiveView.
(function () {
  "use strict";

  // The message box. Enter sends, Shift+Enter is a new line.
  var Composer = {
    mounted: function () {
      var form = this.el;
      var input = form.querySelector("textarea");
      var hook = this;
      var send = function (event) {
        event.preventDefault();
        hook.pushEvent("send", { text: input.value.trim() }, function (reply) {
          if (reply && reply.sent) input.value = "";
        });
      };
      form.addEventListener("submit", send);
      input.addEventListener("keydown", function (event) {
        if (event.key === "Enter" && !event.shiftKey) send(event);
      });
    }
  };

  // The camera. "Show LUNA" takes one frame, 1280 pixels wide or less.
  // The frame goes to the server with the next message.
  var Camera = {
    mounted: function () {
      var root = this.el;
      var hook = this;
      var view = root.querySelector(".camera-view");
      var video = root.querySelector("video");
      var list = root.querySelector("select");
      var attachment = root.querySelector(".attachment");
      var preview = attachment.querySelector("img");
      this.stream = null;

      var cameras = function () {
        return navigator.mediaDevices.enumerateDevices().then(function (devices) {
          var current = list.value;
          list.replaceChildren();
          devices.filter(function (d) { return d.kind === "videoinput"; }).forEach(function (d, i) {
            list.appendChild(new Option(d.label || "Camera " + (i + 1), d.deviceId));
          });
          if (current) list.value = current;
        });
      };
      var stop = function () {
        if (hook.stream) hook.stream.getTracks().forEach(function (t) { t.stop(); });
        hook.stream = null;
      };
      var start = function (deviceId) {
        stop();
        var video_options = deviceId ? { deviceId: { exact: deviceId } } : true;
        return navigator.mediaDevices.getUserMedia({ video: video_options }).then(function (stream) {
          hook.stream = stream;
          video.srcObject = stream;
          // After the first permission, the browser gives the camera names.
          return cameras();
        });
      };
      var clear = function () {
        attachment.hidden = true;
        preview.removeAttribute("src");
      };
      this.stop = stop;

      root.addEventListener("click", function (event) {
        var action = event.target.dataset && event.target.dataset.action;
        if (action === "open") {
          view.hidden = false;
          cameras().then(function () { return start(list.value); }).catch(function (error) {
            view.hidden = true;
            hook.pushEvent("camera-error", { message: String(error.message || error) });
          });
        } else if (action === "close") {
          stop();
          view.hidden = true;
        } else if (action === "snap") {
          var scale = Math.min(1, 1280 / video.videoWidth);
          var canvas = document.createElement("canvas");
          canvas.width = Math.round(video.videoWidth * scale);
          canvas.height = Math.round(video.videoHeight * scale);
          canvas.getContext("2d").drawImage(video, 0, 0, canvas.width, canvas.height);
          var url = canvas.toDataURL("image/jpeg", 0.85);
          hook.pushEvent("attach", { media_type: "image/jpeg", data: url.split(",")[1] });
          preview.src = url;
          attachment.hidden = false;
          stop();
          view.hidden = true;
        } else if (action === "drop") {
          clear();
          hook.pushEvent("detach", {});
        }
      });
      list.addEventListener("change", function () { start(list.value); });
      this.handleEvent("image-cleared", clear);
    },
    destroyed: function () {
      if (this.stop) this.stop();
    }
  };

  var token = document.querySelector("meta[name='csrf-token']").getAttribute("content");
  var socket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
    params: { _csrf_token: token },
    hooks: { Composer: Composer, Camera: Camera }
  });
  socket.connect();
})();
