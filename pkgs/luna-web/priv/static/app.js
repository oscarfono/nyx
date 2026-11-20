// The LiveView socket and five hooks. phoenix.min.js and
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
        document.documentElement.style.setProperty("--level", level.toFixed(3));
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

  // The long-term memory: a force graph, or a mind map around one note.
  // Our own code: the page loads no graph library, and no file from the internet.
  var MemoryGraph = {
    mounted: function () {
      var hook = this;
      var root = this.el;
      var canvas = root.querySelector("canvas");
      var search = root.querySelector("input");
      var label = root.querySelector(".memory-title");
      var ctx = canvas.getContext("2d");
      var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      var nodes = [], links = [], byId = {}, near = {};
      var view = root.dataset.view || "graph";
      var focus = null, hover = null, match = "";
      var cam = { x: 0, y: 0, k: 1 };
      var alpha = 0, frame = null, drag = null, pointers = {};

      var css = function (name, fallback) {
        return getComputedStyle(document.documentElement).getPropertyValue(name).trim() || fallback;
      };
      var hue = function (tag) {
        var h = 0;
        for (var i = 0; i < tag.length; i++) h = (h * 31 + tag.charCodeAt(i)) % 360;
        return h;
      };
      var colour = function (n) {
        return n.tags && n.tags.length ? "hsl(" + hue(n.tags[0]) + ", 55%, 55%)" : css("--muted", "#888");
      };

      var size = function () {
        var ratio = window.devicePixelRatio || 1;
        var w = root.clientWidth, h = Math.max(320, Math.round(window.innerHeight * 0.65));
        canvas.style.width = w + "px";
        canvas.style.height = h + "px";
        canvas.width = Math.round(w * ratio);
        canvas.height = Math.round(h * ratio);
        ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
        hook.w = w;
        hook.h = h;
      };

      var setData = function (data) {
        var old = byId;
        byId = {};
        near = {};
        nodes = (data.nodes || []).map(function (n, i) {
          var o = old[n.id];
          var a = i * 2.399963;
          var node = { id: n.id, title: n.title, tags: n.tags || [], owner: n.owner,
                       x: o ? o.x : Math.cos(a) * 12 * Math.sqrt(i + 1), y: o ? o.y : Math.sin(a) * 12 * Math.sqrt(i + 1),
                       vx: 0, vy: 0, tx: null, ty: null };
          byId[n.id] = node;
          near[n.id] = [];
          return node;
        });
        links = (data.links || []).filter(function (l) { return byId[l.source] && byId[l.target]; })
          .map(function (l) {
            near[l.source].push(l.target);
            near[l.target].push(l.source);
            return { s: byId[l.source], t: byId[l.target] };
          });
        if (!focus || !byId[focus]) focus = nodes.length ? busiest() : null;
        layout();
      };

      var busiest = function () {
        var best = nodes[0];
        nodes.forEach(function (n) { if (near[n.id].length > near[best.id].length) best = n; });
        return best.id;
      };

      // The force graph: nodes push apart, links pull together, all pull to the centre.
      var tick = function () {
        var i, j, a, b, dx, dy, d2, f;
        for (i = 0; i < nodes.length; i++) {
          a = nodes[i];
          for (j = i + 1; j < nodes.length; j++) {
            b = nodes[j];
            dx = a.x - b.x; dy = a.y - b.y; d2 = dx * dx + dy * dy;
            // A floor on the distance stops a very large push between near nodes.
            if (d2 < 100) d2 = 100;
            f = 600 / d2;
            a.vx += dx * f; a.vy += dy * f; b.vx -= dx * f; b.vy -= dy * f;
          }
        }
        links.forEach(function (l) {
          dx = l.t.x - l.s.x; dy = l.t.y - l.s.y;
          var d = Math.sqrt(dx * dx + dy * dy) || 1;
          f = (d - 70) * 0.02 / d;
          l.s.vx += dx * f; l.s.vy += dy * f; l.t.vx -= dx * f; l.t.vy -= dy * f;
        });
        nodes.forEach(function (n) {
          n.vx -= n.x * 0.01; n.vy -= n.y * 0.01;
          if (drag && drag.node === n) { n.vx = 0; n.vy = 0; return; }
          n.vx *= 0.6; n.vy *= 0.6;
          // A speed limit keeps the graph stable.
          var speed = Math.sqrt(n.vx * n.vx + n.vy * n.vy);
          if (speed > 12) { n.vx *= 12 / speed; n.vy *= 12 / speed; }
          n.x += n.vx * alpha; n.y += n.vy * alpha;
        });
        alpha *= 0.985;
      };

      // The mind map: the focus in the centre, its neighbours on ring 1, theirs on ring 2.
      var mindMap = function () {
        nodes.forEach(function (n) { n.tx = null; n.ring = null; });
        if (!focus) return;
        var centre = byId[focus];
        centre.tx = 0; centre.ty = 0; centre.ring = 0;
        var ring1 = near[focus].filter(function (id, i, all) { return all.indexOf(id) === i && id !== focus; });
        var seen = {};
        seen[focus] = true;
        ring1.forEach(function (id) { seen[id] = true; });
        var step = (Math.PI * 2) / Math.max(ring1.length, 1);
        ring1.forEach(function (id, i) {
          var a = i * step - Math.PI / 2;
          var n = byId[id];
          n.tx = Math.cos(a) * 150; n.ty = Math.sin(a) * 150; n.ring = 1;
          var kids = near[id].filter(function (k) { if (seen[k]) return false; seen[k] = true; return true; });
          kids.forEach(function (k, j) {
            var spread = step * 0.8;
            var b = a - spread / 2 + spread * (kids.length === 1 ? 0.5 : j / (kids.length - 1));
            var c = byId[k];
            c.tx = Math.cos(b) * 290; c.ty = Math.sin(b) * 290; c.ring = 2;
          });
        });
      };

      var layout = function () {
        fitted = true;
        if (view === "map") {
          mindMap();
          if (reduce) nodes.forEach(function (n) { if (n.tx !== null) { n.x = n.tx; n.y = n.ty; } });
        } else {
          alpha = 1;
          if (reduce) { for (var i = 0; i < 300; i++) tick(); alpha = 0; }
        }
        run();
      };

      var shown = function (n) { return view === "graph" || n.ring !== null; };

      // Fit the camera to the shown nodes, until the owner pans or zooms.
      var fitted = true;
      var fit = function () {
        if (!fitted) return;
        var xs = [], ys = [];
        nodes.forEach(function (n) {
          if (!shown(n)) return;
          xs.push(view === "map" && n.tx !== null ? n.tx : n.x);
          ys.push(view === "map" && n.tx !== null ? n.ty : n.y);
        });
        if (!xs.length) return;
        var minX = Math.min.apply(null, xs), maxX = Math.max.apply(null, xs);
        var minY = Math.min.apply(null, ys), maxY = Math.max.apply(null, ys);
        var k = Math.min((hook.w - 80) / Math.max(maxX - minX, 1), (hook.h - 80) / Math.max(maxY - minY, 1));
        cam.k = Math.min(2, Math.max(0.2, k));
        cam.x = -((minX + maxX) / 2) * cam.k;
        cam.y = -((minY + maxY) / 2) * cam.k;
      };

      var draw = function () {
        var w = hook.w, h = hook.h;
        ctx.clearRect(0, 0, w, h);
        ctx.save();
        ctx.translate(w / 2 + cam.x, h / 2 + cam.y);
        ctx.scale(cam.k, cam.k);
        ctx.lineWidth = 1 / cam.k;
        ctx.strokeStyle = css("--line", "#444");
        links.forEach(function (l) {
          if (!shown(l.s) || !shown(l.t)) return;
          ctx.beginPath(); ctx.moveTo(l.s.x, l.s.y); ctx.lineTo(l.t.x, l.t.y); ctx.stroke();
        });
        var text = css("--text", "#eee"), accent = css("--accent", "#b392f0");
        ctx.font = (12 / cam.k) + "px system-ui, sans-serif";
        ctx.lineJoin = "round";
        ctx.textAlign = "center";
        nodes.forEach(function (n) {
          if (!shown(n)) return;
          var r = (view === "map" ? (n.ring === 0 ? 12 : n.ring === 1 ? 8 : 5) : 4 + Math.min(near[n.id].length, 8)) ;
          var hit = match && n.title.toLowerCase().indexOf(match) >= 0;
          ctx.beginPath(); ctx.arc(n.x, n.y, r, 0, Math.PI * 2);
          ctx.fillStyle = colour(n); ctx.fill();
          // LUNA notes have an accent ring. The notes of Coops have none.
          if (n.owner === "luna") { ctx.lineWidth = 2 / cam.k; ctx.strokeStyle = accent; ctx.stroke(); }
          if (hit || n === hover || n.id === focus) {
            ctx.lineWidth = 3 / cam.k; ctx.strokeStyle = text; ctx.stroke();
          }
          // In the graph, the hubs (3 links or more) always have a label.
          var label = view === "map" ? n.ring <= 1 || hit : cam.k > 1.2 || hit || n === hover || near[n.id].length >= 3;
          if (label) { ctx.fillStyle = text; ctx.fillText(n.title, n.x, n.y - r - 4 / cam.k); }
        });
        ctx.restore();
      };

      var run = function () {
        if (frame) return;
        var step = function () {
          frame = null;
          var moving = false;
          if (view === "graph" && alpha > 0.02) { tick(); moving = true; }
          if (view === "map") {
            nodes.forEach(function (n) {
              if (n.tx === null) return;
              var dx = n.tx - n.x, dy = n.ty - n.y;
              if (Math.abs(dx) + Math.abs(dy) > 0.5) { n.x += dx * 0.18; n.y += dy * 0.18; moving = true; }
            });
          }
          fit();
          draw();
          if (moving || drag) frame = window.requestAnimationFrame(step);
        };
        frame = window.requestAnimationFrame(step);
      };

      var world = function (event) {
        var box = canvas.getBoundingClientRect();
        return { x: (event.clientX - box.left - hook.w / 2 - cam.x) / cam.k,
                 y: (event.clientY - box.top - hook.h / 2 - cam.y) / cam.k };
      };
      var nodeAt = function (p) {
        var best = null, bestD = (14 / cam.k) * (14 / cam.k);
        nodes.forEach(function (n) {
          if (!shown(n)) return;
          var d = (n.x - p.x) * (n.x - p.x) + (n.y - p.y) * (n.y - p.y);
          if (d < bestD) { best = n; bestD = d; }
        });
        return best;
      };

      canvas.addEventListener("pointerdown", function (event) {
        canvas.setPointerCapture(event.pointerId);
        pointers[event.pointerId] = { x: event.clientX, y: event.clientY };
        var p = world(event);
        drag = { node: nodeAt(p), sx: event.clientX, sy: event.clientY, cx: cam.x, cy: cam.y, moved: false };
        run();
      });
      canvas.addEventListener("pointermove", function (event) {
        var ids = Object.keys(pointers);
        if (pointers[event.pointerId] && ids.length === 2) {
          // Two fingers: zoom by the change in the distance between them.
          var other = pointers[ids[0] == event.pointerId ? ids[1] : ids[0]];
          var before = Math.hypot(pointers[event.pointerId].x - other.x, pointers[event.pointerId].y - other.y);
          var after = Math.hypot(event.clientX - other.x, event.clientY - other.y);
          fitted = false;
          cam.k = Math.min(4, Math.max(0.2, cam.k * (after / (before || after))));
          pointers[event.pointerId] = { x: event.clientX, y: event.clientY };
          draw();
          return;
        }
        if (!drag) {
          var n = nodeAt(world(event));
          if (n !== hover) { hover = n; label.textContent = n ? n.title + (n.tags.length ? "  (" + n.tags.join(", ") + ")" : "") : ""; draw(); }
          return;
        }
        if (Math.abs(event.clientX - drag.sx) + Math.abs(event.clientY - drag.sy) > 4) drag.moved = true;
        if (drag.node && view === "graph") {
          var p = world(event);
          drag.node.x = p.x; drag.node.y = p.y;
          alpha = Math.max(alpha, 0.3);
        } else {
          fitted = false;
          cam.x = drag.cx + event.clientX - drag.sx;
          cam.y = drag.cy + event.clientY - drag.sy;
        }
        pointers[event.pointerId] = { x: event.clientX, y: event.clientY };
        run();
      });
      var release = function (event) {
        delete pointers[event.pointerId];
        if (drag && !drag.moved && drag.node) {
          focus = drag.node.id;
          if (view === "graph") hook.pushEvent("memory-focus", { id: focus });
          else layout();
        }
        drag = null;
        run();
      };
      canvas.addEventListener("pointerup", release);
      canvas.addEventListener("pointercancel", release);
      canvas.addEventListener("wheel", function (event) {
        event.preventDefault();
        fitted = false;
        cam.k = Math.min(4, Math.max(0.2, cam.k * (event.deltaY < 0 ? 1.12 : 1 / 1.12)));
        draw();
      }, { passive: false });

      search.addEventListener("input", function () { match = search.value.trim().toLowerCase(); draw(); });
      search.addEventListener("keydown", function (event) {
        if (event.key !== "Enter" || !match) return;
        var found = nodes.filter(function (n) { return n.title.toLowerCase().indexOf(match) >= 0; })[0];
        if (found) { focus = found.id; view = "map"; hook.pushEvent("memory-focus", { id: found.id }); }
      });

      this.handleEvent("memory-graph", function (data) {
        if (data.view) view = data.view;
        setData(data);
      });
      this.handleEvent("memory-view", function (data) {
        view = data.view;
        if (data.focus && byId[data.focus]) focus = data.focus;
        layout();
      });

      this.resize = function () { size(); draw(); };
      window.addEventListener("resize", this.resize);
      size();
      draw();
    },
    destroyed: function () {
      window.removeEventListener("resize", this.resize);
    }
  };

  var token = document.querySelector("meta[name='csrf-token']").getAttribute("content");
  var socket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
    params: { _csrf_token: token },
    hooks: { Composer: Composer, Camera: Camera, Presence: Presence, Talk: Talk, MemoryGraph: MemoryGraph }
  });
  socket.connect();
})();
