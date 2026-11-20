// The LiveView socket and four hooks. phoenix.min.js and
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

  // One audio context for the page. iOS starts it only in a user gesture,
  // so the first press of the talk button makes it.
  var Sound = {
    context: null,
    analyser: null,
    next: 0,
    sources: [],
    ensure: function () {
      if (!this.context) {
        this.context = new (window.AudioContext || window.webkitAudioContext)();
        this.analyser = this.context.createAnalyser();
        this.analyser.fftSize = 512;
        this.analyser.connect(this.context.destination);
      }
      if (this.context.state === "suspended") this.context.resume();
      return this.context;
    },
    // Three earcons only. Refer to finding 7 of the interface review.
    earcon: function (kind) {
      if (!this.context) return;
      var tones = { listen: [660, 880], got: [520], error: [330, 220] }[kind] || [];
      var context = this.context;
      tones.forEach(function (frequency, i) {
        var start = context.currentTime + i * 0.09;
        var osc = context.createOscillator();
        var gain = context.createGain();
        osc.frequency.value = frequency;
        gain.gain.setValueAtTime(0.0001, start);
        gain.gain.exponentialRampToValueAtTime(0.15, start + 0.02);
        gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.12);
        osc.connect(gain).connect(context.destination);
        osc.start(start);
        osc.stop(start + 0.14);
      });
    },
    // Plays one sentence of 16-bit mono PCM after the sentence before it.
    play: function (base64, rate, onEnd) {
      var context = this.ensure();
      var bytes = Uint8Array.from(atob(base64), function (c) { return c.charCodeAt(0); });
      var samples = new Int16Array(bytes.buffer, 0, bytes.length >> 1);
      var buffer = context.createBuffer(1, samples.length, rate);
      var channel = buffer.getChannelData(0);
      for (var i = 0; i < samples.length; i++) channel[i] = samples[i] / 0x8000;
      var source = context.createBufferSource();
      source.buffer = buffer;
      source.connect(this.analyser);
      var start = Math.max(context.currentTime + 0.05, this.next);
      source.start(start);
      this.next = start + buffer.duration;
      this.sources.push(source);
      var sound = this;
      source.onended = function () {
        sound.sources = sound.sources.filter(function (s) { return s !== source; });
        if (onEnd) onEnd(sound.sources.length === 0);
      };
    },
    stop: function () {
      this.sources.forEach(function (s) { s.onended = null; try { s.stop(); } catch (e) {} });
      this.sources = [];
      this.next = 0;
    },
    // The loudness of the voice of LUNA, from 0 to 1.
    level: function () {
      if (!this.analyser || this.sources.length === 0) return 0;
      var data = new Uint8Array(this.analyser.fftSize);
      this.analyser.getByteTimeDomainData(data);
      var sum = 0;
      for (var i = 0; i < data.length; i++) { var v = (data[i] - 128) / 128; sum += v * v; }
      return Math.min(1, Math.sqrt(sum / data.length) * 4);
    }
  };

  // The presence element: orb or ring. It plays the voice of LUNA, so speech
  // continues when you change the panel. Each device keeps its own style.
  var Presence = {
    mounted: function () {
      var hook = this;
      this.turn = null;
      this.ended = false;
      try {
        var saved = window.localStorage.getItem("luna-presence-style");
        if (saved && saved !== this.el.dataset.style) this.pushEvent("presence-style", { style: saved });
      } catch (e) {}
      this.handleEvent("voice-audio", function (event) {
        if (hook.turn !== event.turn) { Sound.stop(); hook.turn = event.turn; hook.ended = false; }
        Sound.play(event.data, event.rate, function (last) {
          if (last && hook.ended) hook.pushEvent("voice-done", { turn: hook.turn });
        });
      });
      this.handleEvent("voice-end", function (event) {
        hook.ended = true;
        if (Sound.sources.length === 0) hook.pushEvent("voice-done", { turn: event.turn });
      });
      this.handleEvent("voice-error", function () { Sound.earcon("error"); });
      this.handleEvent("voice-stop-audio", function () { Sound.stop(); });
      var frame = function () {
        var level = hook.el.dataset.state === "listening" ? (window.lunaMicLevel || 0) : Sound.level();
        hook.el.style.setProperty("--level", level.toFixed(3));
        hook.frame = window.requestAnimationFrame(frame);
      };
      frame();
    },
    updated: function () {
      try { window.localStorage.setItem("luna-presence-style", this.el.dataset.style); } catch (e) {}
    },
    destroyed: function () { window.cancelAnimationFrame(this.frame); }
  };

  // Push-to-talk. Hold the button, or hold Space when the message box is not
  // in focus. A press stops the voice of LUNA at once.
  var Talk = {
    mounted: function () {
      var hook = this;
      var button = this.el;
      this.active = false;

      var start = function (event) {
        if (event) event.preventDefault();
        if (hook.active) return;
        hook.active = true;
        var context = Sound.ensure();
        Sound.stop();
        hook.pushEvent("voice-start", {});
        Sound.earcon("listen");
        var media = navigator.mediaDevices.getUserMedia({
          audio: { echoCancellation: true, noiseSuppression: true, channelCount: 1 }
        });
        var worklet = context.audioWorklet.addModule("/mic-worklet.js");
        Promise.all([media, worklet]).then(function (results) {
          if (!hook.active) { results[0].getTracks().forEach(function (t) { t.stop(); }); return; }
          hook.stream = results[0];
          hook.source = context.createMediaStreamSource(hook.stream);
          hook.node = new AudioWorkletNode(context, "luna-mic");
          hook.node.port.onmessage = function (message) {
            var samples = message.data;
            var sum = 0;
            for (var i = 0; i < samples.length; i++) sum += Math.abs(samples[i]);
            window.lunaMicLevel = Math.min(1, (sum / samples.length / 0x8000) * 8);
            var bytes = new Uint8Array(samples.buffer);
            var text = "";
            for (var j = 0; j < bytes.length; j += 0x8000) {
              text += String.fromCharCode.apply(null, bytes.subarray(j, j + 0x8000));
            }
            hook.pushEvent("voice-chunk", { data: btoa(text) });
          };
          hook.source.connect(hook.node);
        }).catch(function (error) {
          hook.active = false;
          Sound.earcon("error");
          hook.pushEvent("camera-error", { message: "Microphone: " + (error.message || error) });
        });
      };

      var stop = function (event) {
        if (event) event.preventDefault();
        if (!hook.active) return;
        hook.active = false;
        window.lunaMicLevel = 0;
        // Wait for the last 200 ms chunk from the worklet.
        window.setTimeout(function () {
          if (hook.source) hook.source.disconnect();
          if (hook.node) hook.node.port.onmessage = null;
          if (hook.stream) hook.stream.getTracks().forEach(function (t) { t.stop(); });
          hook.source = hook.node = hook.stream = null;
          hook.pushEvent("voice-stop", {});
          Sound.earcon("got");
        }, 250);
      };

      button.addEventListener("pointerdown", start);
      button.addEventListener("pointerup", stop);
      button.addEventListener("pointercancel", stop);
      button.addEventListener("pointerleave", stop);
      button.addEventListener("contextmenu", function (e) { e.preventDefault(); });
      this.keydown = function (event) {
        var typing = document.activeElement && /^(TEXTAREA|INPUT|SELECT)$/.test(document.activeElement.tagName);
        if (event.code === "Space" && !typing && !event.repeat) start(event);
      };
      this.keyup = function (event) { if (event.code === "Space" && hook.active) stop(event); };
      window.addEventListener("keydown", this.keydown);
      window.addEventListener("keyup", this.keyup);
    },
    destroyed: function () {
      window.removeEventListener("keydown", this.keydown);
      window.removeEventListener("keyup", this.keyup);
      if (this.stream) this.stream.getTracks().forEach(function (t) { t.stop(); });
    }
  };

  var token = document.querySelector("meta[name='csrf-token']").getAttribute("content");
  var socket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
    params: { _csrf_token: token },
    hooks: { Composer: Composer, Camera: Camera, Presence: Presence, Talk: Talk }
  });
  socket.connect();
})();
