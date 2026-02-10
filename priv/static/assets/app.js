(() => {
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __esm = (fn2, res) => function __init() {
    return fn2 && (res = (0, fn2[__getOwnPropNames(fn2)[0]])(fn2 = 0)), res;
  };
  var __commonJS = (cb, mod) => function __require() {
    return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
    // If the importer is in node compatibility mode or this is not an ESM
    // file that has been converted to a CommonJS file using a Babel-
    // compatible transform (i.e. "__esModule" has not been set), then set
    // "default" to the CommonJS "module.exports" for node compatibility.
    isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
    mod
  ));

  // ../deps/phoenix_html/priv/static/phoenix_html.js
  var init_phoenix_html = __esm({
    "../deps/phoenix_html/priv/static/phoenix_html.js"() {
      "use strict";
      (function() {
        var PolyfillEvent = eventConstructor();
        function eventConstructor() {
          if (typeof window.CustomEvent === "function") return window.CustomEvent;
          function CustomEvent2(event, params) {
            params = params || { bubbles: false, cancelable: false, detail: void 0 };
            var evt = document.createEvent("CustomEvent");
            evt.initCustomEvent(event, params.bubbles, params.cancelable, params.detail);
            return evt;
          }
          CustomEvent2.prototype = window.Event.prototype;
          return CustomEvent2;
        }
        function buildHiddenInput(name, value) {
          var input = document.createElement("input");
          input.type = "hidden";
          input.name = name;
          input.value = value;
          return input;
        }
        function handleClick(element, targetModifierKey) {
          var to = element.getAttribute("data-to"), method = buildHiddenInput("_method", element.getAttribute("data-method")), csrf = buildHiddenInput("_csrf_token", element.getAttribute("data-csrf")), form = document.createElement("form"), submit = document.createElement("input"), target = element.getAttribute("target");
          form.method = element.getAttribute("data-method") === "get" ? "get" : "post";
          form.action = to;
          form.style.display = "none";
          if (target) form.target = target;
          else if (targetModifierKey) form.target = "_blank";
          form.appendChild(csrf);
          form.appendChild(method);
          document.body.appendChild(form);
          submit.type = "submit";
          form.appendChild(submit);
          submit.click();
        }
        window.addEventListener("click", function(e) {
          var element = e.target;
          if (e.defaultPrevented) return;
          while (element && element.getAttribute) {
            var phoenixLinkEvent = new PolyfillEvent("phoenix.link.click", {
              "bubbles": true,
              "cancelable": true
            });
            if (!element.dispatchEvent(phoenixLinkEvent)) {
              e.preventDefault();
              e.stopImmediatePropagation();
              return false;
            }
            if (element.getAttribute("data-method") && element.getAttribute("data-to")) {
              handleClick(element, e.metaKey || e.shiftKey);
              e.preventDefault();
              return false;
            } else {
              element = element.parentNode;
            }
          }
        }, false);
        window.addEventListener("phoenix.link.click", function(e) {
          var message = e.target.getAttribute("data-confirm");
          if (message && !window.confirm(message)) {
            e.preventDefault();
          }
        }, false);
      })();
    }
  });

  // ../deps/phoenix/priv/static/phoenix.cjs.js
  var require_phoenix_cjs = __commonJS({
    "../deps/phoenix/priv/static/phoenix.cjs.js"(exports, module) {
      var __defProp2 = Object.defineProperty;
      var __getOwnPropDesc2 = Object.getOwnPropertyDescriptor;
      var __getOwnPropNames2 = Object.getOwnPropertyNames;
      var __hasOwnProp2 = Object.prototype.hasOwnProperty;
      var __export = (target, all) => {
        for (var name in all)
          __defProp2(target, name, { get: all[name], enumerable: true });
      };
      var __copyProps2 = (to, from, except, desc) => {
        if (from && typeof from === "object" || typeof from === "function") {
          for (let key of __getOwnPropNames2(from))
            if (!__hasOwnProp2.call(to, key) && key !== except)
              __defProp2(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc2(from, key)) || desc.enumerable });
        }
        return to;
      };
      var __toCommonJS = (mod) => __copyProps2(__defProp2({}, "__esModule", { value: true }), mod);
      var phoenix_exports = {};
      __export(phoenix_exports, {
        Channel: () => Channel,
        LongPoll: () => LongPoll,
        Presence: () => Presence,
        Serializer: () => serializer_default,
        Socket: () => Socket
      });
      module.exports = __toCommonJS(phoenix_exports);
      var closure2 = (value) => {
        if (typeof value === "function") {
          return value;
        } else {
          let closure22 = function() {
            return value;
          };
          return closure22;
        }
      };
      var globalSelf = typeof self !== "undefined" ? self : null;
      var phxWindow = typeof window !== "undefined" ? window : null;
      var global = globalSelf || phxWindow || globalThis;
      var DEFAULT_VSN = "2.0.0";
      var SOCKET_STATES = { connecting: 0, open: 1, closing: 2, closed: 3 };
      var DEFAULT_TIMEOUT = 1e4;
      var WS_CLOSE_NORMAL = 1e3;
      var CHANNEL_STATES = {
        closed: "closed",
        errored: "errored",
        joined: "joined",
        joining: "joining",
        leaving: "leaving"
      };
      var CHANNEL_EVENTS = {
        close: "phx_close",
        error: "phx_error",
        join: "phx_join",
        reply: "phx_reply",
        leave: "phx_leave"
      };
      var TRANSPORTS = {
        longpoll: "longpoll",
        websocket: "websocket"
      };
      var XHR_STATES = {
        complete: 4
      };
      var AUTH_TOKEN_PREFIX = "base64url.bearer.phx.";
      var Push = class {
        constructor(channel, event, payload, timeout) {
          this.channel = channel;
          this.event = event;
          this.payload = payload || function() {
            return {};
          };
          this.receivedResp = null;
          this.timeout = timeout;
          this.timeoutTimer = null;
          this.recHooks = [];
          this.sent = false;
        }
        /**
         *
         * @param {number} timeout
         */
        resend(timeout) {
          this.timeout = timeout;
          this.reset();
          this.send();
        }
        /**
         *
         */
        send() {
          if (this.hasReceived("timeout")) {
            return;
          }
          this.startTimeout();
          this.sent = true;
          this.channel.socket.push({
            topic: this.channel.topic,
            event: this.event,
            payload: this.payload(),
            ref: this.ref,
            join_ref: this.channel.joinRef()
          });
        }
        /**
         *
         * @param {*} status
         * @param {*} callback
         */
        receive(status, callback) {
          if (this.hasReceived(status)) {
            callback(this.receivedResp.response);
          }
          this.recHooks.push({ status, callback });
          return this;
        }
        /**
         * @private
         */
        reset() {
          this.cancelRefEvent();
          this.ref = null;
          this.refEvent = null;
          this.receivedResp = null;
          this.sent = false;
        }
        /**
         * @private
         */
        matchReceive({ status, response, _ref }) {
          this.recHooks.filter((h2) => h2.status === status).forEach((h2) => h2.callback(response));
        }
        /**
         * @private
         */
        cancelRefEvent() {
          if (!this.refEvent) {
            return;
          }
          this.channel.off(this.refEvent);
        }
        /**
         * @private
         */
        cancelTimeout() {
          clearTimeout(this.timeoutTimer);
          this.timeoutTimer = null;
        }
        /**
         * @private
         */
        startTimeout() {
          if (this.timeoutTimer) {
            this.cancelTimeout();
          }
          this.ref = this.channel.socket.makeRef();
          this.refEvent = this.channel.replyEventName(this.ref);
          this.channel.on(this.refEvent, (payload) => {
            this.cancelRefEvent();
            this.cancelTimeout();
            this.receivedResp = payload;
            this.matchReceive(payload);
          });
          this.timeoutTimer = setTimeout(() => {
            this.trigger("timeout", {});
          }, this.timeout);
        }
        /**
         * @private
         */
        hasReceived(status) {
          return this.receivedResp && this.receivedResp.status === status;
        }
        /**
         * @private
         */
        trigger(status, response) {
          this.channel.trigger(this.refEvent, { status, response });
        }
      };
      var Timer = class {
        constructor(callback, timerCalc) {
          this.callback = callback;
          this.timerCalc = timerCalc;
          this.timer = null;
          this.tries = 0;
        }
        reset() {
          this.tries = 0;
          clearTimeout(this.timer);
        }
        /**
         * Cancels any previous scheduleTimeout and schedules callback
         */
        scheduleTimeout() {
          clearTimeout(this.timer);
          this.timer = setTimeout(() => {
            this.tries = this.tries + 1;
            this.callback();
          }, this.timerCalc(this.tries + 1));
        }
      };
      var Channel = class {
        constructor(topic, params, socket) {
          this.state = CHANNEL_STATES.closed;
          this.topic = topic;
          this.params = closure2(params || {});
          this.socket = socket;
          this.bindings = [];
          this.bindingRef = 0;
          this.timeout = this.socket.timeout;
          this.joinedOnce = false;
          this.joinPush = new Push(this, CHANNEL_EVENTS.join, this.params, this.timeout);
          this.pushBuffer = [];
          this.stateChangeRefs = [];
          this.rejoinTimer = new Timer(() => {
            if (this.socket.isConnected()) {
              this.rejoin();
            }
          }, this.socket.rejoinAfterMs);
          this.stateChangeRefs.push(this.socket.onError(() => this.rejoinTimer.reset()));
          this.stateChangeRefs.push(
            this.socket.onOpen(() => {
              this.rejoinTimer.reset();
              if (this.isErrored()) {
                this.rejoin();
              }
            })
          );
          this.joinPush.receive("ok", () => {
            this.state = CHANNEL_STATES.joined;
            this.rejoinTimer.reset();
            this.pushBuffer.forEach((pushEvent) => pushEvent.send());
            this.pushBuffer = [];
          });
          this.joinPush.receive("error", () => {
            this.state = CHANNEL_STATES.errored;
            if (this.socket.isConnected()) {
              this.rejoinTimer.scheduleTimeout();
            }
          });
          this.onClose(() => {
            this.rejoinTimer.reset();
            if (this.socket.hasLogger()) this.socket.log("channel", `close ${this.topic} ${this.joinRef()}`);
            this.state = CHANNEL_STATES.closed;
            this.socket.remove(this);
          });
          this.onError((reason) => {
            if (this.socket.hasLogger()) this.socket.log("channel", `error ${this.topic}`, reason);
            if (this.isJoining()) {
              this.joinPush.reset();
            }
            this.state = CHANNEL_STATES.errored;
            if (this.socket.isConnected()) {
              this.rejoinTimer.scheduleTimeout();
            }
          });
          this.joinPush.receive("timeout", () => {
            if (this.socket.hasLogger()) this.socket.log("channel", `timeout ${this.topic} (${this.joinRef()})`, this.joinPush.timeout);
            let leavePush = new Push(this, CHANNEL_EVENTS.leave, closure2({}), this.timeout);
            leavePush.send();
            this.state = CHANNEL_STATES.errored;
            this.joinPush.reset();
            if (this.socket.isConnected()) {
              this.rejoinTimer.scheduleTimeout();
            }
          });
          this.on(CHANNEL_EVENTS.reply, (payload, ref) => {
            this.trigger(this.replyEventName(ref), payload);
          });
        }
        /**
         * Join the channel
         * @param {integer} timeout
         * @returns {Push}
         */
        join(timeout = this.timeout) {
          if (this.joinedOnce) {
            throw new Error("tried to join multiple times. 'join' can only be called a single time per channel instance");
          } else {
            this.timeout = timeout;
            this.joinedOnce = true;
            this.rejoin();
            return this.joinPush;
          }
        }
        /**
         * Hook into channel close
         * @param {Function} callback
         */
        onClose(callback) {
          this.on(CHANNEL_EVENTS.close, callback);
        }
        /**
         * Hook into channel errors
         * @param {Function} callback
         */
        onError(callback) {
          return this.on(CHANNEL_EVENTS.error, (reason) => callback(reason));
        }
        /**
         * Subscribes on channel events
         *
         * Subscription returns a ref counter, which can be used later to
         * unsubscribe the exact event listener
         *
         * @example
         * const ref1 = channel.on("event", do_stuff)
         * const ref2 = channel.on("event", do_other_stuff)
         * channel.off("event", ref1)
         * // Since unsubscription, do_stuff won't fire,
         * // while do_other_stuff will keep firing on the "event"
         *
         * @param {string} event
         * @param {Function} callback
         * @returns {integer} ref
         */
        on(event, callback) {
          let ref = this.bindingRef++;
          this.bindings.push({ event, ref, callback });
          return ref;
        }
        /**
         * Unsubscribes off of channel events
         *
         * Use the ref returned from a channel.on() to unsubscribe one
         * handler, or pass nothing for the ref to unsubscribe all
         * handlers for the given event.
         *
         * @example
         * // Unsubscribe the do_stuff handler
         * const ref1 = channel.on("event", do_stuff)
         * channel.off("event", ref1)
         *
         * // Unsubscribe all handlers from event
         * channel.off("event")
         *
         * @param {string} event
         * @param {integer} ref
         */
        off(event, ref) {
          this.bindings = this.bindings.filter((bind) => {
            return !(bind.event === event && (typeof ref === "undefined" || ref === bind.ref));
          });
        }
        /**
         * @private
         */
        canPush() {
          return this.socket.isConnected() && this.isJoined();
        }
        /**
         * Sends a message `event` to phoenix with the payload `payload`.
         * Phoenix receives this in the `handle_in(event, payload, socket)`
         * function. if phoenix replies or it times out (default 10000ms),
         * then optionally the reply can be received.
         *
         * @example
         * channel.push("event")
         *   .receive("ok", payload => console.log("phoenix replied:", payload))
         *   .receive("error", err => console.log("phoenix errored", err))
         *   .receive("timeout", () => console.log("timed out pushing"))
         * @param {string} event
         * @param {Object} payload
         * @param {number} [timeout]
         * @returns {Push}
         */
        push(event, payload, timeout = this.timeout) {
          payload = payload || {};
          if (!this.joinedOnce) {
            throw new Error(`tried to push '${event}' to '${this.topic}' before joining. Use channel.join() before pushing events`);
          }
          let pushEvent = new Push(this, event, function() {
            return payload;
          }, timeout);
          if (this.canPush()) {
            pushEvent.send();
          } else {
            pushEvent.startTimeout();
            this.pushBuffer.push(pushEvent);
          }
          return pushEvent;
        }
        /** Leaves the channel
         *
         * Unsubscribes from server events, and
         * instructs channel to terminate on server
         *
         * Triggers onClose() hooks
         *
         * To receive leave acknowledgements, use the `receive`
         * hook to bind to the server ack, ie:
         *
         * @example
         * channel.leave().receive("ok", () => alert("left!") )
         *
         * @param {integer} timeout
         * @returns {Push}
         */
        leave(timeout = this.timeout) {
          this.rejoinTimer.reset();
          this.joinPush.cancelTimeout();
          this.state = CHANNEL_STATES.leaving;
          let onClose = () => {
            if (this.socket.hasLogger()) this.socket.log("channel", `leave ${this.topic}`);
            this.trigger(CHANNEL_EVENTS.close, "leave");
          };
          let leavePush = new Push(this, CHANNEL_EVENTS.leave, closure2({}), timeout);
          leavePush.receive("ok", () => onClose()).receive("timeout", () => onClose());
          leavePush.send();
          if (!this.canPush()) {
            leavePush.trigger("ok", {});
          }
          return leavePush;
        }
        /**
         * Overridable message hook
         *
         * Receives all events for specialized message handling
         * before dispatching to the channel callbacks.
         *
         * Must return the payload, modified or unmodified
         * @param {string} event
         * @param {Object} payload
         * @param {integer} ref
         * @returns {Object}
         */
        onMessage(_event, payload, _ref) {
          return payload;
        }
        /**
         * @private
         */
        isMember(topic, event, payload, joinRef) {
          if (this.topic !== topic) {
            return false;
          }
          if (joinRef && joinRef !== this.joinRef()) {
            if (this.socket.hasLogger()) this.socket.log("channel", "dropping outdated message", { topic, event, payload, joinRef });
            return false;
          } else {
            return true;
          }
        }
        /**
         * @private
         */
        joinRef() {
          return this.joinPush.ref;
        }
        /**
         * @private
         */
        rejoin(timeout = this.timeout) {
          if (this.isLeaving()) {
            return;
          }
          this.socket.leaveOpenTopic(this.topic);
          this.state = CHANNEL_STATES.joining;
          this.joinPush.resend(timeout);
        }
        /**
         * @private
         */
        trigger(event, payload, ref, joinRef) {
          let handledPayload = this.onMessage(event, payload, ref, joinRef);
          if (payload && !handledPayload) {
            throw new Error("channel onMessage callbacks must return the payload, modified or unmodified");
          }
          let eventBindings = this.bindings.filter((bind) => bind.event === event);
          for (let i = 0; i < eventBindings.length; i++) {
            let bind = eventBindings[i];
            bind.callback(handledPayload, ref, joinRef || this.joinRef());
          }
        }
        /**
         * @private
         */
        replyEventName(ref) {
          return `chan_reply_${ref}`;
        }
        /**
         * @private
         */
        isClosed() {
          return this.state === CHANNEL_STATES.closed;
        }
        /**
         * @private
         */
        isErrored() {
          return this.state === CHANNEL_STATES.errored;
        }
        /**
         * @private
         */
        isJoined() {
          return this.state === CHANNEL_STATES.joined;
        }
        /**
         * @private
         */
        isJoining() {
          return this.state === CHANNEL_STATES.joining;
        }
        /**
         * @private
         */
        isLeaving() {
          return this.state === CHANNEL_STATES.leaving;
        }
      };
      var Ajax = class {
        static request(method, endPoint, headers, body, timeout, ontimeout, callback) {
          if (global.XDomainRequest) {
            let req = new global.XDomainRequest();
            return this.xdomainRequest(req, method, endPoint, body, timeout, ontimeout, callback);
          } else if (global.XMLHttpRequest) {
            let req = new global.XMLHttpRequest();
            return this.xhrRequest(req, method, endPoint, headers, body, timeout, ontimeout, callback);
          } else if (global.fetch && global.AbortController) {
            return this.fetchRequest(method, endPoint, headers, body, timeout, ontimeout, callback);
          } else {
            throw new Error("No suitable XMLHttpRequest implementation found");
          }
        }
        static fetchRequest(method, endPoint, headers, body, timeout, ontimeout, callback) {
          let options = {
            method,
            headers,
            body
          };
          let controller = null;
          if (timeout) {
            controller = new AbortController();
            const _timeoutId = setTimeout(() => controller.abort(), timeout);
            options.signal = controller.signal;
          }
          global.fetch(endPoint, options).then((response) => response.text()).then((data) => this.parseJSON(data)).then((data) => callback && callback(data)).catch((err) => {
            if (err.name === "AbortError" && ontimeout) {
              ontimeout();
            } else {
              callback && callback(null);
            }
          });
          return controller;
        }
        static xdomainRequest(req, method, endPoint, body, timeout, ontimeout, callback) {
          req.timeout = timeout;
          req.open(method, endPoint);
          req.onload = () => {
            let response = this.parseJSON(req.responseText);
            callback && callback(response);
          };
          if (ontimeout) {
            req.ontimeout = ontimeout;
          }
          req.onprogress = () => {
          };
          req.send(body);
          return req;
        }
        static xhrRequest(req, method, endPoint, headers, body, timeout, ontimeout, callback) {
          req.open(method, endPoint, true);
          req.timeout = timeout;
          for (let [key, value] of Object.entries(headers)) {
            req.setRequestHeader(key, value);
          }
          req.onerror = () => callback && callback(null);
          req.onreadystatechange = () => {
            if (req.readyState === XHR_STATES.complete && callback) {
              let response = this.parseJSON(req.responseText);
              callback(response);
            }
          };
          if (ontimeout) {
            req.ontimeout = ontimeout;
          }
          req.send(body);
          return req;
        }
        static parseJSON(resp) {
          if (!resp || resp === "") {
            return null;
          }
          try {
            return JSON.parse(resp);
          } catch {
            console && console.log("failed to parse JSON response", resp);
            return null;
          }
        }
        static serialize(obj, parentKey) {
          let queryStr = [];
          for (var key in obj) {
            if (!Object.prototype.hasOwnProperty.call(obj, key)) {
              continue;
            }
            let paramKey = parentKey ? `${parentKey}[${key}]` : key;
            let paramVal = obj[key];
            if (typeof paramVal === "object") {
              queryStr.push(this.serialize(paramVal, paramKey));
            } else {
              queryStr.push(encodeURIComponent(paramKey) + "=" + encodeURIComponent(paramVal));
            }
          }
          return queryStr.join("&");
        }
        static appendParams(url, params) {
          if (Object.keys(params).length === 0) {
            return url;
          }
          let prefix = url.match(/\?/) ? "&" : "?";
          return `${url}${prefix}${this.serialize(params)}`;
        }
      };
      var arrayBufferToBase64 = (buffer) => {
        let binary = "";
        let bytes = new Uint8Array(buffer);
        let len = bytes.byteLength;
        for (let i = 0; i < len; i++) {
          binary += String.fromCharCode(bytes[i]);
        }
        return btoa(binary);
      };
      var LongPoll = class {
        constructor(endPoint, protocols) {
          if (protocols && protocols.length === 2 && protocols[1].startsWith(AUTH_TOKEN_PREFIX)) {
            this.authToken = atob(protocols[1].slice(AUTH_TOKEN_PREFIX.length));
          }
          this.endPoint = null;
          this.token = null;
          this.skipHeartbeat = true;
          this.reqs = /* @__PURE__ */ new Set();
          this.awaitingBatchAck = false;
          this.currentBatch = null;
          this.currentBatchTimer = null;
          this.batchBuffer = [];
          this.onopen = function() {
          };
          this.onerror = function() {
          };
          this.onmessage = function() {
          };
          this.onclose = function() {
          };
          this.pollEndpoint = this.normalizeEndpoint(endPoint);
          this.readyState = SOCKET_STATES.connecting;
          setTimeout(() => this.poll(), 0);
        }
        normalizeEndpoint(endPoint) {
          return endPoint.replace("ws://", "http://").replace("wss://", "https://").replace(new RegExp("(.*)/" + TRANSPORTS.websocket), "$1/" + TRANSPORTS.longpoll);
        }
        endpointURL() {
          return Ajax.appendParams(this.pollEndpoint, { token: this.token });
        }
        closeAndRetry(code, reason, wasClean) {
          this.close(code, reason, wasClean);
          this.readyState = SOCKET_STATES.connecting;
        }
        ontimeout() {
          this.onerror("timeout");
          this.closeAndRetry(1005, "timeout", false);
        }
        isActive() {
          return this.readyState === SOCKET_STATES.open || this.readyState === SOCKET_STATES.connecting;
        }
        poll() {
          const headers = { "Accept": "application/json" };
          if (this.authToken) {
            headers["X-Phoenix-AuthToken"] = this.authToken;
          }
          this.ajax("GET", headers, null, () => this.ontimeout(), (resp) => {
            if (resp) {
              var { status, token, messages } = resp;
              if (status === 410 && this.token !== null) {
                this.onerror(410);
                this.closeAndRetry(3410, "session_gone", false);
                return;
              }
              this.token = token;
            } else {
              status = 0;
            }
            switch (status) {
              case 200:
                messages.forEach((msg) => {
                  setTimeout(() => this.onmessage({ data: msg }), 0);
                });
                this.poll();
                break;
              case 204:
                this.poll();
                break;
              case 410:
                this.readyState = SOCKET_STATES.open;
                this.onopen({});
                this.poll();
                break;
              case 403:
                this.onerror(403);
                this.close(1008, "forbidden", false);
                break;
              case 0:
              case 500:
                this.onerror(500);
                this.closeAndRetry(1011, "internal server error", 500);
                break;
              default:
                throw new Error(`unhandled poll status ${status}`);
            }
          });
        }
        // we collect all pushes within the current event loop by
        // setTimeout 0, which optimizes back-to-back procedural
        // pushes against an empty buffer
        send(body) {
          if (typeof body !== "string") {
            body = arrayBufferToBase64(body);
          }
          if (this.currentBatch) {
            this.currentBatch.push(body);
          } else if (this.awaitingBatchAck) {
            this.batchBuffer.push(body);
          } else {
            this.currentBatch = [body];
            this.currentBatchTimer = setTimeout(() => {
              this.batchSend(this.currentBatch);
              this.currentBatch = null;
            }, 0);
          }
        }
        batchSend(messages) {
          this.awaitingBatchAck = true;
          this.ajax("POST", { "Content-Type": "application/x-ndjson" }, messages.join("\n"), () => this.onerror("timeout"), (resp) => {
            this.awaitingBatchAck = false;
            if (!resp || resp.status !== 200) {
              this.onerror(resp && resp.status);
              this.closeAndRetry(1011, "internal server error", false);
            } else if (this.batchBuffer.length > 0) {
              this.batchSend(this.batchBuffer);
              this.batchBuffer = [];
            }
          });
        }
        close(code, reason, wasClean) {
          for (let req of this.reqs) {
            req.abort();
          }
          this.readyState = SOCKET_STATES.closed;
          let opts = Object.assign({ code: 1e3, reason: void 0, wasClean: true }, { code, reason, wasClean });
          this.batchBuffer = [];
          clearTimeout(this.currentBatchTimer);
          this.currentBatchTimer = null;
          if (typeof CloseEvent !== "undefined") {
            this.onclose(new CloseEvent("close", opts));
          } else {
            this.onclose(opts);
          }
        }
        ajax(method, headers, body, onCallerTimeout, callback) {
          let req;
          let ontimeout = () => {
            this.reqs.delete(req);
            onCallerTimeout();
          };
          req = Ajax.request(method, this.endpointURL(), headers, body, this.timeout, ontimeout, (resp) => {
            this.reqs.delete(req);
            if (this.isActive()) {
              callback(resp);
            }
          });
          this.reqs.add(req);
        }
      };
      var Presence = class _Presence {
        constructor(channel, opts = {}) {
          let events = opts.events || { state: "presence_state", diff: "presence_diff" };
          this.state = {};
          this.pendingDiffs = [];
          this.channel = channel;
          this.joinRef = null;
          this.caller = {
            onJoin: function() {
            },
            onLeave: function() {
            },
            onSync: function() {
            }
          };
          this.channel.on(events.state, (newState) => {
            let { onJoin, onLeave, onSync } = this.caller;
            this.joinRef = this.channel.joinRef();
            this.state = _Presence.syncState(this.state, newState, onJoin, onLeave);
            this.pendingDiffs.forEach((diff) => {
              this.state = _Presence.syncDiff(this.state, diff, onJoin, onLeave);
            });
            this.pendingDiffs = [];
            onSync();
          });
          this.channel.on(events.diff, (diff) => {
            let { onJoin, onLeave, onSync } = this.caller;
            if (this.inPendingSyncState()) {
              this.pendingDiffs.push(diff);
            } else {
              this.state = _Presence.syncDiff(this.state, diff, onJoin, onLeave);
              onSync();
            }
          });
        }
        onJoin(callback) {
          this.caller.onJoin = callback;
        }
        onLeave(callback) {
          this.caller.onLeave = callback;
        }
        onSync(callback) {
          this.caller.onSync = callback;
        }
        list(by) {
          return _Presence.list(this.state, by);
        }
        inPendingSyncState() {
          return !this.joinRef || this.joinRef !== this.channel.joinRef();
        }
        // lower-level public static API
        /**
         * Used to sync the list of presences on the server
         * with the client's state. An optional `onJoin` and `onLeave` callback can
         * be provided to react to changes in the client's local presences across
         * disconnects and reconnects with the server.
         *
         * @returns {Presence}
         */
        static syncState(currentState, newState, onJoin, onLeave) {
          let state = this.clone(currentState);
          let joins = {};
          let leaves = {};
          this.map(state, (key, presence) => {
            if (!newState[key]) {
              leaves[key] = presence;
            }
          });
          this.map(newState, (key, newPresence) => {
            let currentPresence = state[key];
            if (currentPresence) {
              let newRefs = newPresence.metas.map((m) => m.phx_ref);
              let curRefs = currentPresence.metas.map((m) => m.phx_ref);
              let joinedMetas = newPresence.metas.filter((m) => curRefs.indexOf(m.phx_ref) < 0);
              let leftMetas = currentPresence.metas.filter((m) => newRefs.indexOf(m.phx_ref) < 0);
              if (joinedMetas.length > 0) {
                joins[key] = newPresence;
                joins[key].metas = joinedMetas;
              }
              if (leftMetas.length > 0) {
                leaves[key] = this.clone(currentPresence);
                leaves[key].metas = leftMetas;
              }
            } else {
              joins[key] = newPresence;
            }
          });
          return this.syncDiff(state, { joins, leaves }, onJoin, onLeave);
        }
        /**
         *
         * Used to sync a diff of presence join and leave
         * events from the server, as they happen. Like `syncState`, `syncDiff`
         * accepts optional `onJoin` and `onLeave` callbacks to react to a user
         * joining or leaving from a device.
         *
         * @returns {Presence}
         */
        static syncDiff(state, diff, onJoin, onLeave) {
          let { joins, leaves } = this.clone(diff);
          if (!onJoin) {
            onJoin = function() {
            };
          }
          if (!onLeave) {
            onLeave = function() {
            };
          }
          this.map(joins, (key, newPresence) => {
            let currentPresence = state[key];
            state[key] = this.clone(newPresence);
            if (currentPresence) {
              let joinedRefs = state[key].metas.map((m) => m.phx_ref);
              let curMetas = currentPresence.metas.filter((m) => joinedRefs.indexOf(m.phx_ref) < 0);
              state[key].metas.unshift(...curMetas);
            }
            onJoin(key, currentPresence, newPresence);
          });
          this.map(leaves, (key, leftPresence) => {
            let currentPresence = state[key];
            if (!currentPresence) {
              return;
            }
            let refsToRemove = leftPresence.metas.map((m) => m.phx_ref);
            currentPresence.metas = currentPresence.metas.filter((p) => {
              return refsToRemove.indexOf(p.phx_ref) < 0;
            });
            onLeave(key, currentPresence, leftPresence);
            if (currentPresence.metas.length === 0) {
              delete state[key];
            }
          });
          return state;
        }
        /**
         * Returns the array of presences, with selected metadata.
         *
         * @param {Object} presences
         * @param {Function} chooser
         *
         * @returns {Presence}
         */
        static list(presences, chooser) {
          if (!chooser) {
            chooser = function(key, pres) {
              return pres;
            };
          }
          return this.map(presences, (key, presence) => {
            return chooser(key, presence);
          });
        }
        // private
        static map(obj, func) {
          return Object.getOwnPropertyNames(obj).map((key) => func(key, obj[key]));
        }
        static clone(obj) {
          return JSON.parse(JSON.stringify(obj));
        }
      };
      var serializer_default = {
        HEADER_LENGTH: 1,
        META_LENGTH: 4,
        KINDS: { push: 0, reply: 1, broadcast: 2 },
        encode(msg, callback) {
          if (msg.payload.constructor === ArrayBuffer) {
            return callback(this.binaryEncode(msg));
          } else {
            let payload = [msg.join_ref, msg.ref, msg.topic, msg.event, msg.payload];
            return callback(JSON.stringify(payload));
          }
        },
        decode(rawPayload, callback) {
          if (rawPayload.constructor === ArrayBuffer) {
            return callback(this.binaryDecode(rawPayload));
          } else {
            let [join_ref, ref, topic, event, payload] = JSON.parse(rawPayload);
            return callback({ join_ref, ref, topic, event, payload });
          }
        },
        // private
        binaryEncode(message) {
          let { join_ref, ref, event, topic, payload } = message;
          let metaLength = this.META_LENGTH + join_ref.length + ref.length + topic.length + event.length;
          let header = new ArrayBuffer(this.HEADER_LENGTH + metaLength);
          let view = new DataView(header);
          let offset = 0;
          view.setUint8(offset++, this.KINDS.push);
          view.setUint8(offset++, join_ref.length);
          view.setUint8(offset++, ref.length);
          view.setUint8(offset++, topic.length);
          view.setUint8(offset++, event.length);
          Array.from(join_ref, (char) => view.setUint8(offset++, char.charCodeAt(0)));
          Array.from(ref, (char) => view.setUint8(offset++, char.charCodeAt(0)));
          Array.from(topic, (char) => view.setUint8(offset++, char.charCodeAt(0)));
          Array.from(event, (char) => view.setUint8(offset++, char.charCodeAt(0)));
          var combined = new Uint8Array(header.byteLength + payload.byteLength);
          combined.set(new Uint8Array(header), 0);
          combined.set(new Uint8Array(payload), header.byteLength);
          return combined.buffer;
        },
        binaryDecode(buffer) {
          let view = new DataView(buffer);
          let kind = view.getUint8(0);
          let decoder = new TextDecoder();
          switch (kind) {
            case this.KINDS.push:
              return this.decodePush(buffer, view, decoder);
            case this.KINDS.reply:
              return this.decodeReply(buffer, view, decoder);
            case this.KINDS.broadcast:
              return this.decodeBroadcast(buffer, view, decoder);
          }
        },
        decodePush(buffer, view, decoder) {
          let joinRefSize = view.getUint8(1);
          let topicSize = view.getUint8(2);
          let eventSize = view.getUint8(3);
          let offset = this.HEADER_LENGTH + this.META_LENGTH - 1;
          let joinRef = decoder.decode(buffer.slice(offset, offset + joinRefSize));
          offset = offset + joinRefSize;
          let topic = decoder.decode(buffer.slice(offset, offset + topicSize));
          offset = offset + topicSize;
          let event = decoder.decode(buffer.slice(offset, offset + eventSize));
          offset = offset + eventSize;
          let data = buffer.slice(offset, buffer.byteLength);
          return { join_ref: joinRef, ref: null, topic, event, payload: data };
        },
        decodeReply(buffer, view, decoder) {
          let joinRefSize = view.getUint8(1);
          let refSize = view.getUint8(2);
          let topicSize = view.getUint8(3);
          let eventSize = view.getUint8(4);
          let offset = this.HEADER_LENGTH + this.META_LENGTH;
          let joinRef = decoder.decode(buffer.slice(offset, offset + joinRefSize));
          offset = offset + joinRefSize;
          let ref = decoder.decode(buffer.slice(offset, offset + refSize));
          offset = offset + refSize;
          let topic = decoder.decode(buffer.slice(offset, offset + topicSize));
          offset = offset + topicSize;
          let event = decoder.decode(buffer.slice(offset, offset + eventSize));
          offset = offset + eventSize;
          let data = buffer.slice(offset, buffer.byteLength);
          let payload = { status: event, response: data };
          return { join_ref: joinRef, ref, topic, event: CHANNEL_EVENTS.reply, payload };
        },
        decodeBroadcast(buffer, view, decoder) {
          let topicSize = view.getUint8(1);
          let eventSize = view.getUint8(2);
          let offset = this.HEADER_LENGTH + 2;
          let topic = decoder.decode(buffer.slice(offset, offset + topicSize));
          offset = offset + topicSize;
          let event = decoder.decode(buffer.slice(offset, offset + eventSize));
          offset = offset + eventSize;
          let data = buffer.slice(offset, buffer.byteLength);
          return { join_ref: null, ref: null, topic, event, payload: data };
        }
      };
      var Socket = class {
        constructor(endPoint, opts = {}) {
          this.stateChangeCallbacks = { open: [], close: [], error: [], message: [] };
          this.channels = [];
          this.sendBuffer = [];
          this.ref = 0;
          this.fallbackRef = null;
          this.timeout = opts.timeout || DEFAULT_TIMEOUT;
          this.transport = opts.transport || global.WebSocket || LongPoll;
          this.primaryPassedHealthCheck = false;
          this.longPollFallbackMs = opts.longPollFallbackMs;
          this.fallbackTimer = null;
          this.sessionStore = opts.sessionStorage || global && global.sessionStorage;
          this.establishedConnections = 0;
          this.defaultEncoder = serializer_default.encode.bind(serializer_default);
          this.defaultDecoder = serializer_default.decode.bind(serializer_default);
          this.closeWasClean = false;
          this.disconnecting = false;
          this.binaryType = opts.binaryType || "arraybuffer";
          this.connectClock = 1;
          this.pageHidden = false;
          if (this.transport !== LongPoll) {
            this.encode = opts.encode || this.defaultEncoder;
            this.decode = opts.decode || this.defaultDecoder;
          } else {
            this.encode = this.defaultEncoder;
            this.decode = this.defaultDecoder;
          }
          let awaitingConnectionOnPageShow = null;
          if (phxWindow && phxWindow.addEventListener) {
            phxWindow.addEventListener("pagehide", (_e3) => {
              if (this.conn) {
                this.disconnect();
                awaitingConnectionOnPageShow = this.connectClock;
              }
            });
            phxWindow.addEventListener("pageshow", (_e3) => {
              if (awaitingConnectionOnPageShow === this.connectClock) {
                awaitingConnectionOnPageShow = null;
                this.connect();
              }
            });
            phxWindow.addEventListener("visibilitychange", () => {
              if (document.visibilityState === "hidden") {
                this.pageHidden = true;
              } else {
                this.pageHidden = false;
                if (!this.isConnected()) {
                  this.teardown(() => this.connect());
                }
              }
            });
          }
          this.heartbeatIntervalMs = opts.heartbeatIntervalMs || 3e4;
          this.rejoinAfterMs = (tries) => {
            if (opts.rejoinAfterMs) {
              return opts.rejoinAfterMs(tries);
            } else {
              return [1e3, 2e3, 5e3][tries - 1] || 1e4;
            }
          };
          this.reconnectAfterMs = (tries) => {
            if (opts.reconnectAfterMs) {
              return opts.reconnectAfterMs(tries);
            } else {
              return [10, 50, 100, 150, 200, 250, 500, 1e3, 2e3][tries - 1] || 5e3;
            }
          };
          this.logger = opts.logger || null;
          if (!this.logger && opts.debug) {
            this.logger = (kind, msg, data) => {
              console.log(`${kind}: ${msg}`, data);
            };
          }
          this.longpollerTimeout = opts.longpollerTimeout || 2e4;
          this.params = closure2(opts.params || {});
          this.endPoint = `${endPoint}/${TRANSPORTS.websocket}`;
          this.vsn = opts.vsn || DEFAULT_VSN;
          this.heartbeatTimeoutTimer = null;
          this.heartbeatTimer = null;
          this.pendingHeartbeatRef = null;
          this.reconnectTimer = new Timer(() => {
            if (this.pageHidden) {
              this.log("Not reconnecting as page is hidden!");
              this.teardown();
              return;
            }
            this.teardown(() => this.connect());
          }, this.reconnectAfterMs);
          this.authToken = opts.authToken;
        }
        /**
         * Returns the LongPoll transport reference
         */
        getLongPollTransport() {
          return LongPoll;
        }
        /**
         * Disconnects and replaces the active transport
         *
         * @param {Function} newTransport - The new transport class to instantiate
         *
         */
        replaceTransport(newTransport) {
          this.connectClock++;
          this.closeWasClean = true;
          clearTimeout(this.fallbackTimer);
          this.reconnectTimer.reset();
          if (this.conn) {
            this.conn.close();
            this.conn = null;
          }
          this.transport = newTransport;
        }
        /**
         * Returns the socket protocol
         *
         * @returns {string}
         */
        protocol() {
          return location.protocol.match(/^https/) ? "wss" : "ws";
        }
        /**
         * The fully qualified socket url
         *
         * @returns {string}
         */
        endPointURL() {
          let uri = Ajax.appendParams(
            Ajax.appendParams(this.endPoint, this.params()),
            { vsn: this.vsn }
          );
          if (uri.charAt(0) !== "/") {
            return uri;
          }
          if (uri.charAt(1) === "/") {
            return `${this.protocol()}:${uri}`;
          }
          return `${this.protocol()}://${location.host}${uri}`;
        }
        /**
         * Disconnects the socket
         *
         * See https://developer.mozilla.org/en-US/docs/Web/API/CloseEvent#Status_codes for valid status codes.
         *
         * @param {Function} callback - Optional callback which is called after socket is disconnected.
         * @param {integer} code - A status code for disconnection (Optional).
         * @param {string} reason - A textual description of the reason to disconnect. (Optional)
         */
        disconnect(callback, code, reason) {
          this.connectClock++;
          this.disconnecting = true;
          this.closeWasClean = true;
          clearTimeout(this.fallbackTimer);
          this.reconnectTimer.reset();
          this.teardown(() => {
            this.disconnecting = false;
            callback && callback();
          }, code, reason);
        }
        /**
         *
         * @param {Object} params - The params to send when connecting, for example `{user_id: userToken}`
         *
         * Passing params to connect is deprecated; pass them in the Socket constructor instead:
         * `new Socket("/socket", {params: {user_id: userToken}})`.
         */
        connect(params) {
          if (params) {
            console && console.log("passing params to connect is deprecated. Instead pass :params to the Socket constructor");
            this.params = closure2(params);
          }
          if (this.conn && !this.disconnecting) {
            return;
          }
          if (this.longPollFallbackMs && this.transport !== LongPoll) {
            this.connectWithFallback(LongPoll, this.longPollFallbackMs);
          } else {
            this.transportConnect();
          }
        }
        /**
         * Logs the message. Override `this.logger` for specialized logging. noops by default
         * @param {string} kind
         * @param {string} msg
         * @param {Object} data
         */
        log(kind, msg, data) {
          this.logger && this.logger(kind, msg, data);
        }
        /**
         * Returns true if a logger has been set on this socket.
         */
        hasLogger() {
          return this.logger !== null;
        }
        /**
         * Registers callbacks for connection open events
         *
         * @example socket.onOpen(function(){ console.info("the socket was opened") })
         *
         * @param {Function} callback
         */
        onOpen(callback) {
          let ref = this.makeRef();
          this.stateChangeCallbacks.open.push([ref, callback]);
          return ref;
        }
        /**
         * Registers callbacks for connection close events
         * @param {Function} callback
         */
        onClose(callback) {
          let ref = this.makeRef();
          this.stateChangeCallbacks.close.push([ref, callback]);
          return ref;
        }
        /**
         * Registers callbacks for connection error events
         *
         * @example socket.onError(function(error){ alert("An error occurred") })
         *
         * @param {Function} callback
         */
        onError(callback) {
          let ref = this.makeRef();
          this.stateChangeCallbacks.error.push([ref, callback]);
          return ref;
        }
        /**
         * Registers callbacks for connection message events
         * @param {Function} callback
         */
        onMessage(callback) {
          let ref = this.makeRef();
          this.stateChangeCallbacks.message.push([ref, callback]);
          return ref;
        }
        /**
         * Pings the server and invokes the callback with the RTT in milliseconds
         * @param {Function} callback
         *
         * Returns true if the ping was pushed or false if unable to be pushed.
         */
        ping(callback) {
          if (!this.isConnected()) {
            return false;
          }
          let ref = this.makeRef();
          let startTime = Date.now();
          this.push({ topic: "phoenix", event: "heartbeat", payload: {}, ref });
          let onMsgRef = this.onMessage((msg) => {
            if (msg.ref === ref) {
              this.off([onMsgRef]);
              callback(Date.now() - startTime);
            }
          });
          return true;
        }
        /**
         * @private
         */
        transportConnect() {
          this.connectClock++;
          this.closeWasClean = false;
          let protocols = void 0;
          if (this.authToken) {
            protocols = ["phoenix", `${AUTH_TOKEN_PREFIX}${btoa(this.authToken).replace(/=/g, "")}`];
          }
          this.conn = new this.transport(this.endPointURL(), protocols);
          this.conn.binaryType = this.binaryType;
          this.conn.timeout = this.longpollerTimeout;
          this.conn.onopen = () => this.onConnOpen();
          this.conn.onerror = (error) => this.onConnError(error);
          this.conn.onmessage = (event) => this.onConnMessage(event);
          this.conn.onclose = (event) => this.onConnClose(event);
        }
        getSession(key) {
          return this.sessionStore && this.sessionStore.getItem(key);
        }
        storeSession(key, val) {
          this.sessionStore && this.sessionStore.setItem(key, val);
        }
        connectWithFallback(fallbackTransport, fallbackThreshold = 2500) {
          clearTimeout(this.fallbackTimer);
          let established = false;
          let primaryTransport = true;
          let openRef, errorRef;
          let fallback = (reason) => {
            this.log("transport", `falling back to ${fallbackTransport.name}...`, reason);
            this.off([openRef, errorRef]);
            primaryTransport = false;
            this.replaceTransport(fallbackTransport);
            this.transportConnect();
          };
          if (this.getSession(`phx:fallback:${fallbackTransport.name}`)) {
            return fallback("memorized");
          }
          this.fallbackTimer = setTimeout(fallback, fallbackThreshold);
          errorRef = this.onError((reason) => {
            this.log("transport", "error", reason);
            if (primaryTransport && !established) {
              clearTimeout(this.fallbackTimer);
              fallback(reason);
            }
          });
          if (this.fallbackRef) {
            this.off([this.fallbackRef]);
          }
          this.fallbackRef = this.onOpen(() => {
            established = true;
            if (!primaryTransport) {
              if (!this.primaryPassedHealthCheck) {
                this.storeSession(`phx:fallback:${fallbackTransport.name}`, "true");
              }
              return this.log("transport", `established ${fallbackTransport.name} fallback`);
            }
            clearTimeout(this.fallbackTimer);
            this.fallbackTimer = setTimeout(fallback, fallbackThreshold);
            this.ping((rtt) => {
              this.log("transport", "connected to primary after", rtt);
              this.primaryPassedHealthCheck = true;
              clearTimeout(this.fallbackTimer);
            });
          });
          this.transportConnect();
        }
        clearHeartbeats() {
          clearTimeout(this.heartbeatTimer);
          clearTimeout(this.heartbeatTimeoutTimer);
        }
        onConnOpen() {
          if (this.hasLogger()) this.log("transport", `${this.transport.name} connected to ${this.endPointURL()}`);
          this.closeWasClean = false;
          this.disconnecting = false;
          this.establishedConnections++;
          this.flushSendBuffer();
          this.reconnectTimer.reset();
          this.resetHeartbeat();
          this.stateChangeCallbacks.open.forEach(([, callback]) => callback());
        }
        /**
         * @private
         */
        heartbeatTimeout() {
          if (this.pendingHeartbeatRef) {
            this.pendingHeartbeatRef = null;
            if (this.hasLogger()) {
              this.log("transport", "heartbeat timeout. Attempting to re-establish connection");
            }
            this.triggerChanError();
            this.closeWasClean = false;
            this.teardown(() => this.reconnectTimer.scheduleTimeout(), WS_CLOSE_NORMAL, "heartbeat timeout");
          }
        }
        resetHeartbeat() {
          if (this.conn && this.conn.skipHeartbeat) {
            return;
          }
          this.pendingHeartbeatRef = null;
          this.clearHeartbeats();
          this.heartbeatTimer = setTimeout(() => this.sendHeartbeat(), this.heartbeatIntervalMs);
        }
        teardown(callback, code, reason) {
          if (!this.conn) {
            return callback && callback();
          }
          let connectClock = this.connectClock;
          this.waitForBufferDone(() => {
            if (connectClock !== this.connectClock) {
              return;
            }
            if (this.conn) {
              if (code) {
                this.conn.close(code, reason || "");
              } else {
                this.conn.close();
              }
            }
            this.waitForSocketClosed(() => {
              if (connectClock !== this.connectClock) {
                return;
              }
              if (this.conn) {
                this.conn.onopen = function() {
                };
                this.conn.onerror = function() {
                };
                this.conn.onmessage = function() {
                };
                this.conn.onclose = function() {
                };
                this.conn = null;
              }
              callback && callback();
            });
          });
        }
        waitForBufferDone(callback, tries = 1) {
          if (tries === 5 || !this.conn || !this.conn.bufferedAmount) {
            callback();
            return;
          }
          setTimeout(() => {
            this.waitForBufferDone(callback, tries + 1);
          }, 150 * tries);
        }
        waitForSocketClosed(callback, tries = 1) {
          if (tries === 5 || !this.conn || this.conn.readyState === SOCKET_STATES.closed) {
            callback();
            return;
          }
          setTimeout(() => {
            this.waitForSocketClosed(callback, tries + 1);
          }, 150 * tries);
        }
        onConnClose(event) {
          if (this.conn) this.conn.onclose = () => {
          };
          let closeCode = event && event.code;
          if (this.hasLogger()) this.log("transport", "close", event);
          this.triggerChanError();
          this.clearHeartbeats();
          if (!this.closeWasClean && closeCode !== 1e3) {
            this.reconnectTimer.scheduleTimeout();
          }
          this.stateChangeCallbacks.close.forEach(([, callback]) => callback(event));
        }
        /**
         * @private
         */
        onConnError(error) {
          if (this.hasLogger()) this.log("transport", error);
          let transportBefore = this.transport;
          let establishedBefore = this.establishedConnections;
          this.stateChangeCallbacks.error.forEach(([, callback]) => {
            callback(error, transportBefore, establishedBefore);
          });
          if (transportBefore === this.transport || establishedBefore > 0) {
            this.triggerChanError();
          }
        }
        /**
         * @private
         */
        triggerChanError() {
          this.channels.forEach((channel) => {
            if (!(channel.isErrored() || channel.isLeaving() || channel.isClosed())) {
              channel.trigger(CHANNEL_EVENTS.error);
            }
          });
        }
        /**
         * @returns {string}
         */
        connectionState() {
          switch (this.conn && this.conn.readyState) {
            case SOCKET_STATES.connecting:
              return "connecting";
            case SOCKET_STATES.open:
              return "open";
            case SOCKET_STATES.closing:
              return "closing";
            default:
              return "closed";
          }
        }
        /**
         * @returns {boolean}
         */
        isConnected() {
          return this.connectionState() === "open";
        }
        /**
         * @private
         *
         * @param {Channel}
         */
        remove(channel) {
          this.off(channel.stateChangeRefs);
          this.channels = this.channels.filter((c) => c !== channel);
        }
        /**
         * Removes `onOpen`, `onClose`, `onError,` and `onMessage` registrations.
         *
         * @param {refs} - list of refs returned by calls to
         *                 `onOpen`, `onClose`, `onError,` and `onMessage`
         */
        off(refs) {
          for (let key in this.stateChangeCallbacks) {
            this.stateChangeCallbacks[key] = this.stateChangeCallbacks[key].filter(([ref]) => {
              return refs.indexOf(ref) === -1;
            });
          }
        }
        /**
         * Initiates a new channel for the given topic
         *
         * @param {string} topic
         * @param {Object} chanParams - Parameters for the channel
         * @returns {Channel}
         */
        channel(topic, chanParams = {}) {
          let chan = new Channel(topic, chanParams, this);
          this.channels.push(chan);
          return chan;
        }
        /**
         * @param {Object} data
         */
        push(data) {
          if (this.hasLogger()) {
            let { topic, event, payload, ref, join_ref } = data;
            this.log("push", `${topic} ${event} (${join_ref}, ${ref})`, payload);
          }
          if (this.isConnected()) {
            this.encode(data, (result) => this.conn.send(result));
          } else {
            this.sendBuffer.push(() => this.encode(data, (result) => this.conn.send(result)));
          }
        }
        /**
         * Return the next message ref, accounting for overflows
         * @returns {string}
         */
        makeRef() {
          let newRef = this.ref + 1;
          if (newRef === this.ref) {
            this.ref = 0;
          } else {
            this.ref = newRef;
          }
          return this.ref.toString();
        }
        sendHeartbeat() {
          if (this.pendingHeartbeatRef && !this.isConnected()) {
            return;
          }
          this.pendingHeartbeatRef = this.makeRef();
          this.push({ topic: "phoenix", event: "heartbeat", payload: {}, ref: this.pendingHeartbeatRef });
          this.heartbeatTimeoutTimer = setTimeout(() => this.heartbeatTimeout(), this.heartbeatIntervalMs);
        }
        flushSendBuffer() {
          if (this.isConnected() && this.sendBuffer.length > 0) {
            this.sendBuffer.forEach((callback) => callback());
            this.sendBuffer = [];
          }
        }
        onConnMessage(rawMessage) {
          this.decode(rawMessage.data, (msg) => {
            let { topic, event, payload, ref, join_ref } = msg;
            if (ref && ref === this.pendingHeartbeatRef) {
              this.clearHeartbeats();
              this.pendingHeartbeatRef = null;
              this.heartbeatTimer = setTimeout(() => this.sendHeartbeat(), this.heartbeatIntervalMs);
            }
            if (this.hasLogger()) this.log("receive", `${payload.status || ""} ${topic} ${event} ${ref && "(" + ref + ")" || ""}`, payload);
            for (let i = 0; i < this.channels.length; i++) {
              const channel = this.channels[i];
              if (!channel.isMember(topic, event, payload, join_ref)) {
                continue;
              }
              channel.trigger(event, payload, ref, join_ref);
            }
            for (let i = 0; i < this.stateChangeCallbacks.message.length; i++) {
              let [, callback] = this.stateChangeCallbacks.message[i];
              callback(msg);
            }
          });
        }
        leaveOpenTopic(topic) {
          let dupChannel = this.channels.find((c) => c.topic === topic && (c.isJoined() || c.isJoining()));
          if (dupChannel) {
            if (this.hasLogger()) this.log("transport", `leaving duplicate topic "${topic}"`);
            dupChannel.leave();
          }
        }
      };
    }
  });

  // ../deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js
  function detectDuplicateIds() {
    const ids = /* @__PURE__ */ new Set();
    const elems = document.querySelectorAll("*[id]");
    for (let i = 0, len = elems.length; i < len; i++) {
      if (ids.has(elems[i].id)) {
        console.error(
          `Multiple IDs detected: ${elems[i].id}. Ensure unique element ids.`
        );
      } else {
        ids.add(elems[i].id);
      }
    }
  }
  function detectInvalidStreamInserts(inserts) {
    const errors = /* @__PURE__ */ new Set();
    Object.keys(inserts).forEach((id) => {
      const streamEl = document.getElementById(id);
      if (streamEl && streamEl.parentElement && streamEl.parentElement.getAttribute("phx-update") !== "stream") {
        errors.add(
          `The stream container with id "${streamEl.parentElement.id}" is missing the phx-update="stream" attribute. Ensure it is set for streams to work properly.`
        );
      }
    });
    errors.forEach((error) => console.error(error));
  }
  function morphAttrs(fromNode, toNode) {
    var toNodeAttrs = toNode.attributes;
    var attr;
    var attrName;
    var attrNamespaceURI;
    var attrValue;
    var fromValue;
    if (toNode.nodeType === DOCUMENT_FRAGMENT_NODE || fromNode.nodeType === DOCUMENT_FRAGMENT_NODE) {
      return;
    }
    for (var i = toNodeAttrs.length - 1; i >= 0; i--) {
      attr = toNodeAttrs[i];
      attrName = attr.name;
      attrNamespaceURI = attr.namespaceURI;
      attrValue = attr.value;
      if (attrNamespaceURI) {
        attrName = attr.localName || attrName;
        fromValue = fromNode.getAttributeNS(attrNamespaceURI, attrName);
        if (fromValue !== attrValue) {
          if (attr.prefix === "xmlns") {
            attrName = attr.name;
          }
          fromNode.setAttributeNS(attrNamespaceURI, attrName, attrValue);
        }
      } else {
        fromValue = fromNode.getAttribute(attrName);
        if (fromValue !== attrValue) {
          fromNode.setAttribute(attrName, attrValue);
        }
      }
    }
    var fromNodeAttrs = fromNode.attributes;
    for (var d = fromNodeAttrs.length - 1; d >= 0; d--) {
      attr = fromNodeAttrs[d];
      attrName = attr.name;
      attrNamespaceURI = attr.namespaceURI;
      if (attrNamespaceURI) {
        attrName = attr.localName || attrName;
        if (!toNode.hasAttributeNS(attrNamespaceURI, attrName)) {
          fromNode.removeAttributeNS(attrNamespaceURI, attrName);
        }
      } else {
        if (!toNode.hasAttribute(attrName)) {
          fromNode.removeAttribute(attrName);
        }
      }
    }
  }
  function createFragmentFromTemplate(str) {
    var template = doc.createElement("template");
    template.innerHTML = str;
    return template.content.childNodes[0];
  }
  function createFragmentFromRange(str) {
    if (!range) {
      range = doc.createRange();
      range.selectNode(doc.body);
    }
    var fragment = range.createContextualFragment(str);
    return fragment.childNodes[0];
  }
  function createFragmentFromWrap(str) {
    var fragment = doc.createElement("body");
    fragment.innerHTML = str;
    return fragment.childNodes[0];
  }
  function toElement(str) {
    str = str.trim();
    if (HAS_TEMPLATE_SUPPORT) {
      return createFragmentFromTemplate(str);
    } else if (HAS_RANGE_SUPPORT) {
      return createFragmentFromRange(str);
    }
    return createFragmentFromWrap(str);
  }
  function compareNodeNames(fromEl, toEl) {
    var fromNodeName = fromEl.nodeName;
    var toNodeName = toEl.nodeName;
    var fromCodeStart, toCodeStart;
    if (fromNodeName === toNodeName) {
      return true;
    }
    fromCodeStart = fromNodeName.charCodeAt(0);
    toCodeStart = toNodeName.charCodeAt(0);
    if (fromCodeStart <= 90 && toCodeStart >= 97) {
      return fromNodeName === toNodeName.toUpperCase();
    } else if (toCodeStart <= 90 && fromCodeStart >= 97) {
      return toNodeName === fromNodeName.toUpperCase();
    } else {
      return false;
    }
  }
  function createElementNS(name, namespaceURI) {
    return !namespaceURI || namespaceURI === NS_XHTML ? doc.createElement(name) : doc.createElementNS(namespaceURI, name);
  }
  function moveChildren(fromEl, toEl) {
    var curChild = fromEl.firstChild;
    while (curChild) {
      var nextChild = curChild.nextSibling;
      toEl.appendChild(curChild);
      curChild = nextChild;
    }
    return toEl;
  }
  function syncBooleanAttrProp(fromEl, toEl, name) {
    if (fromEl[name] !== toEl[name]) {
      fromEl[name] = toEl[name];
      if (fromEl[name]) {
        fromEl.setAttribute(name, "");
      } else {
        fromEl.removeAttribute(name);
      }
    }
  }
  function noop() {
  }
  function defaultGetNodeKey(node) {
    if (node) {
      return node.getAttribute && node.getAttribute("id") || node.id;
    }
  }
  function morphdomFactory(morphAttrs2) {
    return function morphdom2(fromNode, toNode, options) {
      if (!options) {
        options = {};
      }
      if (typeof toNode === "string") {
        if (fromNode.nodeName === "#document" || fromNode.nodeName === "HTML") {
          var toNodeHtml = toNode;
          toNode = doc.createElement("html");
          toNode.innerHTML = toNodeHtml;
        } else if (fromNode.nodeName === "BODY") {
          var toNodeBody = toNode;
          toNode = doc.createElement("html");
          toNode.innerHTML = toNodeBody;
          var bodyElement = toNode.querySelector("body");
          if (bodyElement) {
            toNode = bodyElement;
          }
        } else {
          toNode = toElement(toNode);
        }
      } else if (toNode.nodeType === DOCUMENT_FRAGMENT_NODE$1) {
        toNode = toNode.firstElementChild;
      }
      var getNodeKey = options.getNodeKey || defaultGetNodeKey;
      var onBeforeNodeAdded = options.onBeforeNodeAdded || noop;
      var onNodeAdded = options.onNodeAdded || noop;
      var onBeforeElUpdated = options.onBeforeElUpdated || noop;
      var onElUpdated = options.onElUpdated || noop;
      var onBeforeNodeDiscarded = options.onBeforeNodeDiscarded || noop;
      var onNodeDiscarded = options.onNodeDiscarded || noop;
      var onBeforeElChildrenUpdated = options.onBeforeElChildrenUpdated || noop;
      var skipFromChildren = options.skipFromChildren || noop;
      var addChild = options.addChild || function(parent, child) {
        return parent.appendChild(child);
      };
      var childrenOnly = options.childrenOnly === true;
      var fromNodesLookup = /* @__PURE__ */ Object.create(null);
      var keyedRemovalList = [];
      function addKeyedRemoval(key) {
        keyedRemovalList.push(key);
      }
      function walkDiscardedChildNodes(node, skipKeyedNodes) {
        if (node.nodeType === ELEMENT_NODE) {
          var curChild = node.firstChild;
          while (curChild) {
            var key = void 0;
            if (skipKeyedNodes && (key = getNodeKey(curChild))) {
              addKeyedRemoval(key);
            } else {
              onNodeDiscarded(curChild);
              if (curChild.firstChild) {
                walkDiscardedChildNodes(curChild, skipKeyedNodes);
              }
            }
            curChild = curChild.nextSibling;
          }
        }
      }
      function removeNode(node, parentNode, skipKeyedNodes) {
        if (onBeforeNodeDiscarded(node) === false) {
          return;
        }
        if (parentNode) {
          parentNode.removeChild(node);
        }
        onNodeDiscarded(node);
        walkDiscardedChildNodes(node, skipKeyedNodes);
      }
      function indexTree(node) {
        if (node.nodeType === ELEMENT_NODE || node.nodeType === DOCUMENT_FRAGMENT_NODE$1) {
          var curChild = node.firstChild;
          while (curChild) {
            var key = getNodeKey(curChild);
            if (key) {
              fromNodesLookup[key] = curChild;
            }
            indexTree(curChild);
            curChild = curChild.nextSibling;
          }
        }
      }
      indexTree(fromNode);
      function handleNodeAdded(el2) {
        onNodeAdded(el2);
        var curChild = el2.firstChild;
        while (curChild) {
          var nextSibling = curChild.nextSibling;
          var key = getNodeKey(curChild);
          if (key) {
            var unmatchedFromEl = fromNodesLookup[key];
            if (unmatchedFromEl && compareNodeNames(curChild, unmatchedFromEl)) {
              curChild.parentNode.replaceChild(unmatchedFromEl, curChild);
              morphEl(unmatchedFromEl, curChild);
            } else {
              handleNodeAdded(curChild);
            }
          } else {
            handleNodeAdded(curChild);
          }
          curChild = nextSibling;
        }
      }
      function cleanupFromEl(fromEl, curFromNodeChild, curFromNodeKey) {
        while (curFromNodeChild) {
          var fromNextSibling = curFromNodeChild.nextSibling;
          if (curFromNodeKey = getNodeKey(curFromNodeChild)) {
            addKeyedRemoval(curFromNodeKey);
          } else {
            removeNode(
              curFromNodeChild,
              fromEl,
              true
              /* skip keyed nodes */
            );
          }
          curFromNodeChild = fromNextSibling;
        }
      }
      function morphEl(fromEl, toEl, childrenOnly2) {
        var toElKey = getNodeKey(toEl);
        if (toElKey) {
          delete fromNodesLookup[toElKey];
        }
        if (!childrenOnly2) {
          var beforeUpdateResult = onBeforeElUpdated(fromEl, toEl);
          if (beforeUpdateResult === false) {
            return;
          } else if (beforeUpdateResult instanceof HTMLElement) {
            fromEl = beforeUpdateResult;
            indexTree(fromEl);
          }
          morphAttrs2(fromEl, toEl);
          onElUpdated(fromEl);
          if (onBeforeElChildrenUpdated(fromEl, toEl) === false) {
            return;
          }
        }
        if (fromEl.nodeName !== "TEXTAREA") {
          morphChildren(fromEl, toEl);
        } else {
          specialElHandlers.TEXTAREA(fromEl, toEl);
        }
      }
      function morphChildren(fromEl, toEl) {
        var skipFrom = skipFromChildren(fromEl, toEl);
        var curToNodeChild = toEl.firstChild;
        var curFromNodeChild = fromEl.firstChild;
        var curToNodeKey;
        var curFromNodeKey;
        var fromNextSibling;
        var toNextSibling;
        var matchingFromEl;
        outer:
          while (curToNodeChild) {
            toNextSibling = curToNodeChild.nextSibling;
            curToNodeKey = getNodeKey(curToNodeChild);
            while (!skipFrom && curFromNodeChild) {
              fromNextSibling = curFromNodeChild.nextSibling;
              if (curToNodeChild.isSameNode && curToNodeChild.isSameNode(curFromNodeChild)) {
                curToNodeChild = toNextSibling;
                curFromNodeChild = fromNextSibling;
                continue outer;
              }
              curFromNodeKey = getNodeKey(curFromNodeChild);
              var curFromNodeType = curFromNodeChild.nodeType;
              var isCompatible = void 0;
              if (curFromNodeType === curToNodeChild.nodeType) {
                if (curFromNodeType === ELEMENT_NODE) {
                  if (curToNodeKey) {
                    if (curToNodeKey !== curFromNodeKey) {
                      if (matchingFromEl = fromNodesLookup[curToNodeKey]) {
                        if (fromNextSibling === matchingFromEl) {
                          isCompatible = false;
                        } else {
                          fromEl.insertBefore(matchingFromEl, curFromNodeChild);
                          if (curFromNodeKey) {
                            addKeyedRemoval(curFromNodeKey);
                          } else {
                            removeNode(
                              curFromNodeChild,
                              fromEl,
                              true
                              /* skip keyed nodes */
                            );
                          }
                          curFromNodeChild = matchingFromEl;
                          curFromNodeKey = getNodeKey(curFromNodeChild);
                        }
                      } else {
                        isCompatible = false;
                      }
                    }
                  } else if (curFromNodeKey) {
                    isCompatible = false;
                  }
                  isCompatible = isCompatible !== false && compareNodeNames(curFromNodeChild, curToNodeChild);
                  if (isCompatible) {
                    morphEl(curFromNodeChild, curToNodeChild);
                  }
                } else if (curFromNodeType === TEXT_NODE || curFromNodeType == COMMENT_NODE) {
                  isCompatible = true;
                  if (curFromNodeChild.nodeValue !== curToNodeChild.nodeValue) {
                    curFromNodeChild.nodeValue = curToNodeChild.nodeValue;
                  }
                }
              }
              if (isCompatible) {
                curToNodeChild = toNextSibling;
                curFromNodeChild = fromNextSibling;
                continue outer;
              }
              if (curFromNodeKey) {
                addKeyedRemoval(curFromNodeKey);
              } else {
                removeNode(
                  curFromNodeChild,
                  fromEl,
                  true
                  /* skip keyed nodes */
                );
              }
              curFromNodeChild = fromNextSibling;
            }
            if (curToNodeKey && (matchingFromEl = fromNodesLookup[curToNodeKey]) && compareNodeNames(matchingFromEl, curToNodeChild)) {
              if (!skipFrom) {
                addChild(fromEl, matchingFromEl);
              }
              morphEl(matchingFromEl, curToNodeChild);
            } else {
              var onBeforeNodeAddedResult = onBeforeNodeAdded(curToNodeChild);
              if (onBeforeNodeAddedResult !== false) {
                if (onBeforeNodeAddedResult) {
                  curToNodeChild = onBeforeNodeAddedResult;
                }
                if (curToNodeChild.actualize) {
                  curToNodeChild = curToNodeChild.actualize(fromEl.ownerDocument || doc);
                }
                addChild(fromEl, curToNodeChild);
                handleNodeAdded(curToNodeChild);
              }
            }
            curToNodeChild = toNextSibling;
            curFromNodeChild = fromNextSibling;
          }
        cleanupFromEl(fromEl, curFromNodeChild, curFromNodeKey);
        var specialElHandler = specialElHandlers[fromEl.nodeName];
        if (specialElHandler) {
          specialElHandler(fromEl, toEl);
        }
      }
      var morphedNode = fromNode;
      var morphedNodeType = morphedNode.nodeType;
      var toNodeType = toNode.nodeType;
      if (!childrenOnly) {
        if (morphedNodeType === ELEMENT_NODE) {
          if (toNodeType === ELEMENT_NODE) {
            if (!compareNodeNames(fromNode, toNode)) {
              onNodeDiscarded(fromNode);
              morphedNode = moveChildren(fromNode, createElementNS(toNode.nodeName, toNode.namespaceURI));
            }
          } else {
            morphedNode = toNode;
          }
        } else if (morphedNodeType === TEXT_NODE || morphedNodeType === COMMENT_NODE) {
          if (toNodeType === morphedNodeType) {
            if (morphedNode.nodeValue !== toNode.nodeValue) {
              morphedNode.nodeValue = toNode.nodeValue;
            }
            return morphedNode;
          } else {
            morphedNode = toNode;
          }
        }
      }
      if (morphedNode === toNode) {
        onNodeDiscarded(fromNode);
      } else {
        if (toNode.isSameNode && toNode.isSameNode(morphedNode)) {
          return;
        }
        morphEl(morphedNode, toNode, childrenOnly);
        if (keyedRemovalList) {
          for (var i = 0, len = keyedRemovalList.length; i < len; i++) {
            var elToRemove = fromNodesLookup[keyedRemovalList[i]];
            if (elToRemove) {
              removeNode(elToRemove, elToRemove.parentNode, false);
            }
          }
        }
      }
      if (!childrenOnly && morphedNode !== fromNode && fromNode.parentNode) {
        if (morphedNode.actualize) {
          morphedNode = morphedNode.actualize(fromNode.ownerDocument || doc);
        }
        fromNode.parentNode.replaceChild(morphedNode, fromNode);
      }
      return morphedNode;
    };
  }
  var CONSECUTIVE_RELOADS, MAX_RELOADS, RELOAD_JITTER_MIN, RELOAD_JITTER_MAX, FAILSAFE_JITTER, PHX_EVENT_CLASSES, PHX_DROP_TARGET_ACTIVE_CLASS, PHX_COMPONENT, PHX_VIEW_REF, PHX_LIVE_LINK, PHX_TRACK_STATIC, PHX_LINK_STATE, PHX_REF_LOADING, PHX_REF_SRC, PHX_REF_LOCK, PHX_PENDING_REFS, PHX_TRACK_UPLOADS, PHX_UPLOAD_REF, PHX_PREFLIGHTED_REFS, PHX_DONE_REFS, PHX_DROP_TARGET, PHX_ACTIVE_ENTRY_REFS, PHX_LIVE_FILE_UPDATED, PHX_SKIP, PHX_MAGIC_ID, PHX_PRUNE, PHX_CONNECTED_CLASS, PHX_LOADING_CLASS, PHX_ERROR_CLASS, PHX_CLIENT_ERROR_CLASS, PHX_SERVER_ERROR_CLASS, PHX_PARENT_ID, PHX_MAIN, PHX_ROOT_ID, PHX_VIEWPORT_TOP, PHX_VIEWPORT_BOTTOM, PHX_VIEWPORT_OVERRUN_TARGET, PHX_TRIGGER_ACTION, PHX_HAS_FOCUSED, FOCUSABLE_INPUTS, CHECKABLE_INPUTS, PHX_HAS_SUBMITTED, PHX_SESSION, PHX_VIEW_SELECTOR, PHX_STICKY, PHX_STATIC, PHX_READONLY, PHX_DISABLED, PHX_DISABLE_WITH, PHX_DISABLE_WITH_RESTORE, PHX_HOOK, PHX_DEBOUNCE, PHX_THROTTLE, PHX_UPDATE, PHX_STREAM, PHX_STREAM_REF, PHX_PORTAL, PHX_TELEPORTED_REF, PHX_TELEPORTED_SRC, PHX_RUNTIME_HOOK, PHX_LV_PID, PHX_KEY, PHX_PRIVATE, PHX_AUTO_RECOVER, PHX_LV_DEBUG, PHX_LV_PROFILE, PHX_LV_LATENCY_SIM, PHX_LV_HISTORY_POSITION, PHX_PROGRESS, PHX_MOUNTED, PHX_RELOAD_STATUS, LOADER_TIMEOUT, MAX_CHILD_JOIN_ATTEMPTS, BEFORE_UNLOAD_LOADER_TIMEOUT, DISCONNECTED_TIMEOUT, BINDING_PREFIX, PUSH_TIMEOUT, DEBOUNCE_TRIGGER, THROTTLED, DEBOUNCE_PREV_KEY, DEFAULTS, PHX_PENDING_ATTRS, STATIC, ROOT, COMPONENTS, KEYED, KEYED_COUNT, EVENTS, REPLY, TITLE, TEMPLATES, STREAM, EntryUploader, logError, isCid, debug, closure, clone, closestPhxBinding, isObject, isEqualObj, isEmpty, maybe, channelUploader, eventContainsFiles, Browser, browser_default, DOM, dom_default, UploadEntry, liveUploaderFileRef, LiveUploader, ARIA, aria_default, Hooks, findScrollContainer, scrollTop, bottom, top, isAtViewportTop, isAtViewportBottom, isWithinViewport, hooks_default, ElementRef, DOMPostMorphRestorer, DOCUMENT_FRAGMENT_NODE, range, NS_XHTML, doc, HAS_TEMPLATE_SUPPORT, HAS_RANGE_SUPPORT, specialElHandlers, ELEMENT_NODE, DOCUMENT_FRAGMENT_NODE$1, TEXT_NODE, COMMENT_NODE, morphdom, morphdom_esm_default, DOMPatch, VOID_TAGS, quoteChars, modifyRoot, Rendered, focusStack, default_transition_time, JS, js_default, js_commands_default, HOOK_ID, viewHookID, ViewHook, prependFormDataKey, serializeForm, View, LiveSocket, TransitionSet, LiveSocket2;
  var init_phoenix_live_view_esm = __esm({
    "../deps/phoenix_live_view/priv/static/phoenix_live_view.esm.js"() {
      CONSECUTIVE_RELOADS = "consecutive-reloads";
      MAX_RELOADS = 10;
      RELOAD_JITTER_MIN = 5e3;
      RELOAD_JITTER_MAX = 1e4;
      FAILSAFE_JITTER = 3e4;
      PHX_EVENT_CLASSES = [
        "phx-click-loading",
        "phx-change-loading",
        "phx-submit-loading",
        "phx-keydown-loading",
        "phx-keyup-loading",
        "phx-blur-loading",
        "phx-focus-loading",
        "phx-hook-loading"
      ];
      PHX_DROP_TARGET_ACTIVE_CLASS = "phx-drop-target-active";
      PHX_COMPONENT = "data-phx-component";
      PHX_VIEW_REF = "data-phx-view";
      PHX_LIVE_LINK = "data-phx-link";
      PHX_TRACK_STATIC = "track-static";
      PHX_LINK_STATE = "data-phx-link-state";
      PHX_REF_LOADING = "data-phx-ref-loading";
      PHX_REF_SRC = "data-phx-ref-src";
      PHX_REF_LOCK = "data-phx-ref-lock";
      PHX_PENDING_REFS = "phx-pending-refs";
      PHX_TRACK_UPLOADS = "track-uploads";
      PHX_UPLOAD_REF = "data-phx-upload-ref";
      PHX_PREFLIGHTED_REFS = "data-phx-preflighted-refs";
      PHX_DONE_REFS = "data-phx-done-refs";
      PHX_DROP_TARGET = "drop-target";
      PHX_ACTIVE_ENTRY_REFS = "data-phx-active-refs";
      PHX_LIVE_FILE_UPDATED = "phx:live-file:updated";
      PHX_SKIP = "data-phx-skip";
      PHX_MAGIC_ID = "data-phx-id";
      PHX_PRUNE = "data-phx-prune";
      PHX_CONNECTED_CLASS = "phx-connected";
      PHX_LOADING_CLASS = "phx-loading";
      PHX_ERROR_CLASS = "phx-error";
      PHX_CLIENT_ERROR_CLASS = "phx-client-error";
      PHX_SERVER_ERROR_CLASS = "phx-server-error";
      PHX_PARENT_ID = "data-phx-parent-id";
      PHX_MAIN = "data-phx-main";
      PHX_ROOT_ID = "data-phx-root-id";
      PHX_VIEWPORT_TOP = "viewport-top";
      PHX_VIEWPORT_BOTTOM = "viewport-bottom";
      PHX_VIEWPORT_OVERRUN_TARGET = "viewport-overrun-target";
      PHX_TRIGGER_ACTION = "trigger-action";
      PHX_HAS_FOCUSED = "phx-has-focused";
      FOCUSABLE_INPUTS = [
        "text",
        "textarea",
        "number",
        "email",
        "password",
        "search",
        "tel",
        "url",
        "date",
        "time",
        "datetime-local",
        "color",
        "range"
      ];
      CHECKABLE_INPUTS = ["checkbox", "radio"];
      PHX_HAS_SUBMITTED = "phx-has-submitted";
      PHX_SESSION = "data-phx-session";
      PHX_VIEW_SELECTOR = `[${PHX_SESSION}]`;
      PHX_STICKY = "data-phx-sticky";
      PHX_STATIC = "data-phx-static";
      PHX_READONLY = "data-phx-readonly";
      PHX_DISABLED = "data-phx-disabled";
      PHX_DISABLE_WITH = "disable-with";
      PHX_DISABLE_WITH_RESTORE = "data-phx-disable-with-restore";
      PHX_HOOK = "hook";
      PHX_DEBOUNCE = "debounce";
      PHX_THROTTLE = "throttle";
      PHX_UPDATE = "update";
      PHX_STREAM = "stream";
      PHX_STREAM_REF = "data-phx-stream";
      PHX_PORTAL = "data-phx-portal";
      PHX_TELEPORTED_REF = "data-phx-teleported";
      PHX_TELEPORTED_SRC = "data-phx-teleported-src";
      PHX_RUNTIME_HOOK = "data-phx-runtime-hook";
      PHX_LV_PID = "data-phx-pid";
      PHX_KEY = "key";
      PHX_PRIVATE = "phxPrivate";
      PHX_AUTO_RECOVER = "auto-recover";
      PHX_LV_DEBUG = "phx:live-socket:debug";
      PHX_LV_PROFILE = "phx:live-socket:profiling";
      PHX_LV_LATENCY_SIM = "phx:live-socket:latency-sim";
      PHX_LV_HISTORY_POSITION = "phx:nav-history-position";
      PHX_PROGRESS = "progress";
      PHX_MOUNTED = "mounted";
      PHX_RELOAD_STATUS = "__phoenix_reload_status__";
      LOADER_TIMEOUT = 1;
      MAX_CHILD_JOIN_ATTEMPTS = 3;
      BEFORE_UNLOAD_LOADER_TIMEOUT = 200;
      DISCONNECTED_TIMEOUT = 500;
      BINDING_PREFIX = "phx-";
      PUSH_TIMEOUT = 3e4;
      DEBOUNCE_TRIGGER = "debounce-trigger";
      THROTTLED = "throttled";
      DEBOUNCE_PREV_KEY = "debounce-prev-key";
      DEFAULTS = {
        debounce: 300,
        throttle: 300
      };
      PHX_PENDING_ATTRS = [PHX_REF_LOADING, PHX_REF_SRC, PHX_REF_LOCK];
      STATIC = "s";
      ROOT = "r";
      COMPONENTS = "c";
      KEYED = "k";
      KEYED_COUNT = "kc";
      EVENTS = "e";
      REPLY = "r";
      TITLE = "t";
      TEMPLATES = "p";
      STREAM = "stream";
      EntryUploader = class {
        constructor(entry, config, liveSocket) {
          const { chunk_size, chunk_timeout } = config;
          this.liveSocket = liveSocket;
          this.entry = entry;
          this.offset = 0;
          this.chunkSize = chunk_size;
          this.chunkTimeout = chunk_timeout;
          this.chunkTimer = null;
          this.errored = false;
          this.uploadChannel = liveSocket.channel(`lvu:${entry.ref}`, {
            token: entry.metadata()
          });
        }
        error(reason) {
          if (this.errored) {
            return;
          }
          this.uploadChannel.leave();
          this.errored = true;
          clearTimeout(this.chunkTimer);
          this.entry.error(reason);
        }
        upload() {
          this.uploadChannel.onError((reason) => this.error(reason));
          this.uploadChannel.join().receive("ok", (_data) => this.readNextChunk()).receive("error", (reason) => this.error(reason));
        }
        isDone() {
          return this.offset >= this.entry.file.size;
        }
        readNextChunk() {
          const reader = new window.FileReader();
          const blob = this.entry.file.slice(
            this.offset,
            this.chunkSize + this.offset
          );
          reader.onload = (e) => {
            if (e.target.error === null) {
              this.offset += /** @type {ArrayBuffer} */
              e.target.result.byteLength;
              this.pushChunk(
                /** @type {ArrayBuffer} */
                e.target.result
              );
            } else {
              return logError("Read error: " + e.target.error);
            }
          };
          reader.readAsArrayBuffer(blob);
        }
        pushChunk(chunk) {
          if (!this.uploadChannel.isJoined()) {
            return;
          }
          this.uploadChannel.push("chunk", chunk, this.chunkTimeout).receive("ok", () => {
            this.entry.progress(this.offset / this.entry.file.size * 100);
            if (!this.isDone()) {
              this.chunkTimer = setTimeout(
                () => this.readNextChunk(),
                this.liveSocket.getLatencySim() || 0
              );
            }
          }).receive("error", ({ reason }) => this.error(reason));
        }
      };
      logError = (msg, obj) => console.error && console.error(msg, obj);
      isCid = (cid) => {
        const type = typeof cid;
        return type === "number" || type === "string" && /^(0|[1-9]\d*)$/.test(cid);
      };
      debug = (view, kind, msg, obj) => {
        if (view.liveSocket.isDebugEnabled()) {
          console.log(`${view.id} ${kind}: ${msg} - `, obj);
        }
      };
      closure = (val) => typeof val === "function" ? val : function() {
        return val;
      };
      clone = (obj) => {
        return JSON.parse(JSON.stringify(obj));
      };
      closestPhxBinding = (el2, binding, borderEl) => {
        do {
          if (el2.matches(`[${binding}]`) && !el2.disabled) {
            return el2;
          }
          el2 = el2.parentElement || el2.parentNode;
        } while (el2 !== null && el2.nodeType === 1 && !(borderEl && borderEl.isSameNode(el2) || el2.matches(PHX_VIEW_SELECTOR)));
        return null;
      };
      isObject = (obj) => {
        return obj !== null && typeof obj === "object" && !(obj instanceof Array);
      };
      isEqualObj = (obj1, obj2) => JSON.stringify(obj1) === JSON.stringify(obj2);
      isEmpty = (obj) => {
        for (const x in obj) {
          return false;
        }
        return true;
      };
      maybe = (el2, callback) => el2 && callback(el2);
      channelUploader = function(entries, onError, resp, liveSocket) {
        entries.forEach((entry) => {
          const entryUploader = new EntryUploader(entry, resp.config, liveSocket);
          entryUploader.upload();
        });
      };
      eventContainsFiles = (e) => {
        if (e.dataTransfer.types) {
          for (let i = 0; i < e.dataTransfer.types.length; i++) {
            if (e.dataTransfer.types[i] === "Files") {
              return true;
            }
          }
        }
        return false;
      };
      Browser = {
        canPushState() {
          return typeof history.pushState !== "undefined";
        },
        dropLocal(localStorage, namespace, subkey) {
          return localStorage.removeItem(this.localKey(namespace, subkey));
        },
        updateLocal(localStorage, namespace, subkey, initial, func) {
          const current = this.getLocal(localStorage, namespace, subkey);
          const key = this.localKey(namespace, subkey);
          const newVal = current === null ? initial : func(current);
          localStorage.setItem(key, JSON.stringify(newVal));
          return newVal;
        },
        getLocal(localStorage, namespace, subkey) {
          return JSON.parse(localStorage.getItem(this.localKey(namespace, subkey)));
        },
        updateCurrentState(callback) {
          if (!this.canPushState()) {
            return;
          }
          history.replaceState(
            callback(history.state || {}),
            "",
            window.location.href
          );
        },
        pushState(kind, meta, to) {
          if (this.canPushState()) {
            if (to !== window.location.href) {
              if (meta.type == "redirect" && meta.scroll) {
                const currentState = history.state || {};
                currentState.scroll = meta.scroll;
                history.replaceState(currentState, "", window.location.href);
              }
              delete meta.scroll;
              history[kind + "State"](meta, "", to || null);
              window.requestAnimationFrame(() => {
                const hashEl = this.getHashTargetEl(window.location.hash);
                if (hashEl) {
                  hashEl.scrollIntoView();
                } else if (meta.type === "redirect") {
                  window.scroll(0, 0);
                }
              });
            }
          } else {
            this.redirect(to);
          }
        },
        setCookie(name, value, maxAgeSeconds) {
          const expires = typeof maxAgeSeconds === "number" ? ` max-age=${maxAgeSeconds};` : "";
          document.cookie = `${name}=${value};${expires} path=/`;
        },
        getCookie(name) {
          return document.cookie.replace(
            new RegExp(`(?:(?:^|.*;s*)${name}s*=s*([^;]*).*$)|^.*$`),
            "$1"
          );
        },
        deleteCookie(name) {
          document.cookie = `${name}=; max-age=-1; path=/`;
        },
        redirect(toURL, flash, navigate = (url) => {
          window.location.href = url;
        }) {
          if (flash) {
            this.setCookie("__phoenix_flash__", flash, 60);
          }
          navigate(toURL);
        },
        localKey(namespace, subkey) {
          return `${namespace}-${subkey}`;
        },
        getHashTargetEl(maybeHash) {
          const hash = maybeHash.toString().substring(1);
          if (hash === "") {
            return;
          }
          return document.getElementById(hash) || document.querySelector(`a[name="${hash}"]`);
        }
      };
      browser_default = Browser;
      DOM = {
        byId(id) {
          return document.getElementById(id) || logError(`no id found for ${id}`);
        },
        removeClass(el2, className) {
          el2.classList.remove(className);
          if (el2.classList.length === 0) {
            el2.removeAttribute("class");
          }
        },
        all(node, query, callback) {
          if (!node) {
            return [];
          }
          const array = Array.from(node.querySelectorAll(query));
          if (callback) {
            array.forEach(callback);
          }
          return array;
        },
        childNodeLength(html) {
          const template = document.createElement("template");
          template.innerHTML = html;
          return template.content.childElementCount;
        },
        isUploadInput(el2) {
          return el2.type === "file" && el2.getAttribute(PHX_UPLOAD_REF) !== null;
        },
        isAutoUpload(inputEl) {
          return inputEl.hasAttribute("data-phx-auto-upload");
        },
        findUploadInputs(node) {
          const formId = node.id;
          const inputsOutsideForm = this.all(
            document,
            `input[type="file"][${PHX_UPLOAD_REF}][form="${formId}"]`
          );
          return this.all(node, `input[type="file"][${PHX_UPLOAD_REF}]`).concat(
            inputsOutsideForm
          );
        },
        findComponentNodeList(viewId, cid, doc2 = document) {
          return this.all(
            doc2,
            `[${PHX_VIEW_REF}="${viewId}"][${PHX_COMPONENT}="${cid}"]`
          );
        },
        isPhxDestroyed(node) {
          return node.id && DOM.private(node, "destroyed") ? true : false;
        },
        wantsNewTab(e) {
          const wantsNewTab = e.ctrlKey || e.shiftKey || e.metaKey || e.button && e.button === 1;
          const isDownload = e.target instanceof HTMLAnchorElement && e.target.hasAttribute("download");
          const isTargetBlank = e.target.hasAttribute("target") && e.target.getAttribute("target").toLowerCase() === "_blank";
          const isTargetNamedTab = e.target.hasAttribute("target") && !e.target.getAttribute("target").startsWith("_");
          return wantsNewTab || isTargetBlank || isDownload || isTargetNamedTab;
        },
        isUnloadableFormSubmit(e) {
          const isDialogSubmit = e.target && e.target.getAttribute("method") === "dialog" || e.submitter && e.submitter.getAttribute("formmethod") === "dialog";
          if (isDialogSubmit) {
            return false;
          } else {
            return !e.defaultPrevented && !this.wantsNewTab(e);
          }
        },
        isNewPageClick(e, currentLocation) {
          const href = e.target instanceof HTMLAnchorElement ? e.target.getAttribute("href") : null;
          let url;
          if (e.defaultPrevented || href === null || this.wantsNewTab(e)) {
            return false;
          }
          if (href.startsWith("mailto:") || href.startsWith("tel:")) {
            return false;
          }
          if (e.target.isContentEditable) {
            return false;
          }
          try {
            url = new URL(href);
          } catch {
            try {
              url = new URL(href, currentLocation);
            } catch {
              return true;
            }
          }
          if (url.host === currentLocation.host && url.protocol === currentLocation.protocol) {
            if (url.pathname === currentLocation.pathname && url.search === currentLocation.search) {
              return url.hash === "" && !url.href.endsWith("#");
            }
          }
          return url.protocol.startsWith("http");
        },
        markPhxChildDestroyed(el2) {
          if (this.isPhxChild(el2)) {
            el2.setAttribute(PHX_SESSION, "");
          }
          this.putPrivate(el2, "destroyed", true);
        },
        findPhxChildrenInFragment(html, parentId) {
          const template = document.createElement("template");
          template.innerHTML = html;
          return this.findPhxChildren(template.content, parentId);
        },
        isIgnored(el2, phxUpdate) {
          return (el2.getAttribute(phxUpdate) || el2.getAttribute("data-phx-update")) === "ignore";
        },
        isPhxUpdate(el2, phxUpdate, updateTypes) {
          return el2.getAttribute && updateTypes.indexOf(el2.getAttribute(phxUpdate)) >= 0;
        },
        findPhxSticky(el2) {
          return this.all(el2, `[${PHX_STICKY}]`);
        },
        findPhxChildren(el2, parentId) {
          return this.all(el2, `${PHX_VIEW_SELECTOR}[${PHX_PARENT_ID}="${parentId}"]`);
        },
        findExistingParentCIDs(viewId, cids) {
          const parentCids = /* @__PURE__ */ new Set();
          const childrenCids = /* @__PURE__ */ new Set();
          cids.forEach((cid) => {
            this.all(
              document,
              `[${PHX_VIEW_REF}="${viewId}"][${PHX_COMPONENT}="${cid}"]`
            ).forEach((parent) => {
              parentCids.add(cid);
              this.all(parent, `[${PHX_VIEW_REF}="${viewId}"][${PHX_COMPONENT}]`).map((el2) => parseInt(el2.getAttribute(PHX_COMPONENT))).forEach((childCID) => childrenCids.add(childCID));
            });
          });
          childrenCids.forEach((childCid) => parentCids.delete(childCid));
          return parentCids;
        },
        private(el2, key) {
          return el2[PHX_PRIVATE] && el2[PHX_PRIVATE][key];
        },
        deletePrivate(el2, key) {
          el2[PHX_PRIVATE] && delete el2[PHX_PRIVATE][key];
        },
        putPrivate(el2, key, value) {
          if (!el2[PHX_PRIVATE]) {
            el2[PHX_PRIVATE] = {};
          }
          el2[PHX_PRIVATE][key] = value;
        },
        updatePrivate(el2, key, defaultVal, updateFunc) {
          const existing = this.private(el2, key);
          if (existing === void 0) {
            this.putPrivate(el2, key, updateFunc(defaultVal));
          } else {
            this.putPrivate(el2, key, updateFunc(existing));
          }
        },
        syncPendingAttrs(fromEl, toEl) {
          if (!fromEl.hasAttribute(PHX_REF_SRC)) {
            return;
          }
          PHX_EVENT_CLASSES.forEach((className) => {
            fromEl.classList.contains(className) && toEl.classList.add(className);
          });
          PHX_PENDING_ATTRS.filter((attr) => fromEl.hasAttribute(attr)).forEach(
            (attr) => {
              toEl.setAttribute(attr, fromEl.getAttribute(attr));
            }
          );
        },
        copyPrivates(target, source) {
          if (source[PHX_PRIVATE]) {
            target[PHX_PRIVATE] = source[PHX_PRIVATE];
          }
        },
        putTitle(str) {
          const titleEl = document.querySelector("title");
          if (titleEl) {
            const { prefix, suffix, default: defaultTitle } = titleEl.dataset;
            const isEmpty2 = typeof str !== "string" || str.trim() === "";
            if (isEmpty2 && typeof defaultTitle !== "string") {
              return;
            }
            const inner = isEmpty2 ? defaultTitle : str;
            document.title = `${prefix || ""}${inner || ""}${suffix || ""}`;
          } else {
            document.title = str;
          }
        },
        debounce(el2, event, phxDebounce, defaultDebounce, phxThrottle, defaultThrottle, asyncFilter, callback) {
          let debounce = el2.getAttribute(phxDebounce);
          let throttle = el2.getAttribute(phxThrottle);
          if (debounce === "") {
            debounce = defaultDebounce;
          }
          if (throttle === "") {
            throttle = defaultThrottle;
          }
          const value = debounce || throttle;
          switch (value) {
            case null:
              return callback();
            case "blur":
              this.incCycle(el2, "debounce-blur-cycle", () => {
                if (asyncFilter()) {
                  callback();
                }
              });
              if (this.once(el2, "debounce-blur")) {
                el2.addEventListener(
                  "blur",
                  () => this.triggerCycle(el2, "debounce-blur-cycle")
                );
              }
              return;
            default:
              const timeout = parseInt(value);
              const trigger = () => throttle ? this.deletePrivate(el2, THROTTLED) : callback();
              const currentCycle = this.incCycle(el2, DEBOUNCE_TRIGGER, trigger);
              if (isNaN(timeout)) {
                return logError(`invalid throttle/debounce value: ${value}`);
              }
              if (throttle) {
                let newKeyDown = false;
                if (event.type === "keydown") {
                  const prevKey = this.private(el2, DEBOUNCE_PREV_KEY);
                  this.putPrivate(el2, DEBOUNCE_PREV_KEY, event.key);
                  newKeyDown = prevKey !== event.key;
                }
                if (!newKeyDown && this.private(el2, THROTTLED)) {
                  return false;
                } else {
                  callback();
                  const t = setTimeout(() => {
                    if (asyncFilter()) {
                      this.triggerCycle(el2, DEBOUNCE_TRIGGER);
                    }
                  }, timeout);
                  this.putPrivate(el2, THROTTLED, t);
                }
              } else {
                setTimeout(() => {
                  if (asyncFilter()) {
                    this.triggerCycle(el2, DEBOUNCE_TRIGGER, currentCycle);
                  }
                }, timeout);
              }
              const form = el2.form;
              if (form && this.once(form, "bind-debounce")) {
                form.addEventListener("submit", () => {
                  Array.from(new FormData(form).entries(), ([name]) => {
                    const namedItem = form.elements.namedItem(name);
                    const input = namedItem instanceof RadioNodeList ? namedItem[0] : namedItem;
                    if (input) {
                      this.incCycle(input, DEBOUNCE_TRIGGER);
                      this.deletePrivate(input, THROTTLED);
                    }
                  });
                });
              }
              if (this.once(el2, "bind-debounce")) {
                el2.addEventListener("blur", () => {
                  clearTimeout(this.private(el2, THROTTLED));
                  this.triggerCycle(el2, DEBOUNCE_TRIGGER);
                });
              }
          }
        },
        triggerCycle(el2, key, currentCycle) {
          const [cycle, trigger] = this.private(el2, key);
          if (!currentCycle) {
            currentCycle = cycle;
          }
          if (currentCycle === cycle) {
            this.incCycle(el2, key);
            trigger();
          }
        },
        once(el2, key) {
          if (this.private(el2, key) === true) {
            return false;
          }
          this.putPrivate(el2, key, true);
          return true;
        },
        incCycle(el2, key, trigger = function() {
        }) {
          let [currentCycle] = this.private(el2, key) || [0, trigger];
          currentCycle++;
          this.putPrivate(el2, key, [currentCycle, trigger]);
          return currentCycle;
        },
        // maintains or adds privately used hook information
        // fromEl and toEl can be the same element in the case of a newly added node
        // fromEl and toEl can be any HTML node type, so we need to check if it's an element node
        maintainPrivateHooks(fromEl, toEl, phxViewportTop, phxViewportBottom) {
          if (fromEl.hasAttribute && fromEl.hasAttribute("data-phx-hook") && !toEl.hasAttribute("data-phx-hook")) {
            toEl.setAttribute("data-phx-hook", fromEl.getAttribute("data-phx-hook"));
          }
          if (toEl.hasAttribute && (toEl.hasAttribute(phxViewportTop) || toEl.hasAttribute(phxViewportBottom))) {
            toEl.setAttribute("data-phx-hook", "Phoenix.InfiniteScroll");
          }
        },
        putCustomElHook(el2, hook) {
          if (el2.isConnected) {
            el2.setAttribute("data-phx-hook", "");
          } else {
            console.error(`
        hook attached to non-connected DOM element
        ensure you are calling createHook within your connectedCallback. ${el2.outerHTML}
      `);
          }
          this.putPrivate(el2, "custom-el-hook", hook);
        },
        getCustomElHook(el2) {
          return this.private(el2, "custom-el-hook");
        },
        isUsedInput(el2) {
          return el2.nodeType === Node.ELEMENT_NODE && (this.private(el2, PHX_HAS_FOCUSED) || this.private(el2, PHX_HAS_SUBMITTED));
        },
        resetForm(form) {
          Array.from(form.elements).forEach((input) => {
            this.deletePrivate(input, PHX_HAS_FOCUSED);
            this.deletePrivate(input, PHX_HAS_SUBMITTED);
          });
        },
        isPhxChild(node) {
          return node.getAttribute && node.getAttribute(PHX_PARENT_ID);
        },
        isPhxSticky(node) {
          return node.getAttribute && node.getAttribute(PHX_STICKY) !== null;
        },
        isChildOfAny(el2, parents) {
          return !!parents.find((parent) => parent.contains(el2));
        },
        firstPhxChild(el2) {
          return this.isPhxChild(el2) ? el2 : this.all(el2, `[${PHX_PARENT_ID}]`)[0];
        },
        isPortalTemplate(el2) {
          return el2.tagName === "TEMPLATE" && el2.hasAttribute(PHX_PORTAL);
        },
        closestViewEl(el2) {
          const portalOrViewEl = el2.closest(
            `[${PHX_TELEPORTED_REF}],${PHX_VIEW_SELECTOR}`
          );
          if (!portalOrViewEl) {
            return null;
          }
          if (portalOrViewEl.hasAttribute(PHX_TELEPORTED_REF)) {
            return this.byId(portalOrViewEl.getAttribute(PHX_TELEPORTED_REF));
          } else if (portalOrViewEl.hasAttribute(PHX_SESSION)) {
            return portalOrViewEl;
          }
          return null;
        },
        dispatchEvent(target, name, opts = {}) {
          let defaultBubble = true;
          const isUploadTarget = target.nodeName === "INPUT" && target.type === "file";
          if (isUploadTarget && name === "click") {
            defaultBubble = false;
          }
          const bubbles = opts.bubbles === void 0 ? defaultBubble : !!opts.bubbles;
          const eventOpts = {
            bubbles,
            cancelable: true,
            detail: opts.detail || {}
          };
          const event = name === "click" ? new MouseEvent("click", eventOpts) : new CustomEvent(name, eventOpts);
          target.dispatchEvent(event);
        },
        cloneNode(node, html) {
          if (typeof html === "undefined") {
            return node.cloneNode(true);
          } else {
            const cloned = node.cloneNode(false);
            cloned.innerHTML = html;
            return cloned;
          }
        },
        // merge attributes from source to target
        // if an element is ignored, we only merge data attributes
        // including removing data attributes that are no longer in the source
        mergeAttrs(target, source, opts = {}) {
          const exclude = new Set(opts.exclude || []);
          const isIgnored = opts.isIgnored;
          const sourceAttrs = source.attributes;
          for (let i = sourceAttrs.length - 1; i >= 0; i--) {
            const name = sourceAttrs[i].name;
            if (!exclude.has(name)) {
              const sourceValue = source.getAttribute(name);
              if (target.getAttribute(name) !== sourceValue && (!isIgnored || isIgnored && name.startsWith("data-"))) {
                target.setAttribute(name, sourceValue);
              }
            } else {
              if (name === "value") {
                const sourceValue = source.value ?? source.getAttribute(name);
                if (target.value === sourceValue) {
                  target.setAttribute("value", source.getAttribute(name));
                }
              }
            }
          }
          const targetAttrs = target.attributes;
          for (let i = targetAttrs.length - 1; i >= 0; i--) {
            const name = targetAttrs[i].name;
            if (isIgnored) {
              if (name.startsWith("data-") && !source.hasAttribute(name) && !PHX_PENDING_ATTRS.includes(name)) {
                target.removeAttribute(name);
              }
            } else {
              if (!source.hasAttribute(name)) {
                target.removeAttribute(name);
              }
            }
          }
        },
        mergeFocusedInput(target, source) {
          if (!(target instanceof HTMLSelectElement)) {
            DOM.mergeAttrs(target, source, { exclude: ["value"] });
          }
          if (source.readOnly) {
            target.setAttribute("readonly", true);
          } else {
            target.removeAttribute("readonly");
          }
        },
        hasSelectionRange(el2) {
          return el2.setSelectionRange && (el2.type === "text" || el2.type === "textarea");
        },
        restoreFocus(focused, selectionStart, selectionEnd) {
          if (focused instanceof HTMLSelectElement) {
            focused.focus();
          }
          if (!DOM.isTextualInput(focused)) {
            return;
          }
          const wasFocused = focused.matches(":focus");
          if (!wasFocused) {
            focused.focus();
          }
          if (this.hasSelectionRange(focused)) {
            focused.setSelectionRange(selectionStart, selectionEnd);
          }
        },
        isFormInput(el2) {
          if (el2.localName && customElements.get(el2.localName)) {
            return customElements.get(el2.localName)[`formAssociated`];
          }
          return /^(?:input|select|textarea)$/i.test(el2.tagName) && el2.type !== "button";
        },
        syncAttrsToProps(el2) {
          if (el2 instanceof HTMLInputElement && CHECKABLE_INPUTS.indexOf(el2.type.toLocaleLowerCase()) >= 0) {
            el2.checked = el2.getAttribute("checked") !== null;
          }
        },
        isTextualInput(el2) {
          return FOCUSABLE_INPUTS.indexOf(el2.type) >= 0;
        },
        isNowTriggerFormExternal(el2, phxTriggerExternal) {
          return el2.getAttribute && el2.getAttribute(phxTriggerExternal) !== null && document.body.contains(el2);
        },
        cleanChildNodes(container, phxUpdate) {
          if (DOM.isPhxUpdate(container, phxUpdate, ["append", "prepend", PHX_STREAM])) {
            const toRemove = [];
            container.childNodes.forEach((childNode) => {
              if (!childNode.id) {
                const isEmptyTextNode = childNode.nodeType === Node.TEXT_NODE && childNode.nodeValue.trim() === "";
                if (!isEmptyTextNode && childNode.nodeType !== Node.COMMENT_NODE) {
                  logError(
                    `only HTML element tags with an id are allowed inside containers with phx-update.

removing illegal node: "${(childNode.outerHTML || childNode.nodeValue).trim()}"

`
                  );
                }
                toRemove.push(childNode);
              }
            });
            toRemove.forEach((childNode) => childNode.remove());
          }
        },
        replaceRootContainer(container, tagName, attrs) {
          const retainedAttrs = /* @__PURE__ */ new Set([
            "id",
            PHX_SESSION,
            PHX_STATIC,
            PHX_MAIN,
            PHX_ROOT_ID
          ]);
          if (container.tagName.toLowerCase() === tagName.toLowerCase()) {
            Array.from(container.attributes).filter((attr) => !retainedAttrs.has(attr.name.toLowerCase())).forEach((attr) => container.removeAttribute(attr.name));
            Object.keys(attrs).filter((name) => !retainedAttrs.has(name.toLowerCase())).forEach((attr) => container.setAttribute(attr, attrs[attr]));
            return container;
          } else {
            const newContainer = document.createElement(tagName);
            Object.keys(attrs).forEach(
              (attr) => newContainer.setAttribute(attr, attrs[attr])
            );
            retainedAttrs.forEach(
              (attr) => newContainer.setAttribute(attr, container.getAttribute(attr))
            );
            newContainer.innerHTML = container.innerHTML;
            container.replaceWith(newContainer);
            return newContainer;
          }
        },
        getSticky(el2, name, defaultVal) {
          const op = (DOM.private(el2, "sticky") || []).find(
            ([existingName]) => name === existingName
          );
          if (op) {
            const [_name, _op, stashedResult] = op;
            return stashedResult;
          } else {
            return typeof defaultVal === "function" ? defaultVal() : defaultVal;
          }
        },
        deleteSticky(el2, name) {
          this.updatePrivate(el2, "sticky", [], (ops) => {
            return ops.filter(([existingName, _3]) => existingName !== name);
          });
        },
        putSticky(el2, name, op) {
          const stashedResult = op(el2);
          this.updatePrivate(el2, "sticky", [], (ops) => {
            const existingIndex = ops.findIndex(
              ([existingName]) => name === existingName
            );
            if (existingIndex >= 0) {
              ops[existingIndex] = [name, op, stashedResult];
            } else {
              ops.push([name, op, stashedResult]);
            }
            return ops;
          });
        },
        applyStickyOperations(el2) {
          const ops = DOM.private(el2, "sticky");
          if (!ops) {
            return;
          }
          ops.forEach(([name, op, _stashed]) => this.putSticky(el2, name, op));
        },
        isLocked(el2) {
          return el2.hasAttribute && el2.hasAttribute(PHX_REF_LOCK);
        },
        attributeIgnored(attribute, ignoredAttributes) {
          return ignoredAttributes.some(
            (toIgnore) => attribute.name == toIgnore || toIgnore === "*" || toIgnore.includes("*") && attribute.name.match(toIgnore) != null
          );
        }
      };
      dom_default = DOM;
      UploadEntry = class {
        static isActive(fileEl, file) {
          const isNew = file._phxRef === void 0;
          const activeRefs = fileEl.getAttribute(PHX_ACTIVE_ENTRY_REFS).split(",");
          const isActive = activeRefs.indexOf(LiveUploader.genFileRef(file)) >= 0;
          return file.size > 0 && (isNew || isActive);
        }
        static isPreflighted(fileEl, file) {
          const preflightedRefs = fileEl.getAttribute(PHX_PREFLIGHTED_REFS).split(",");
          const isPreflighted = preflightedRefs.indexOf(LiveUploader.genFileRef(file)) >= 0;
          return isPreflighted && this.isActive(fileEl, file);
        }
        static isPreflightInProgress(file) {
          return file._preflightInProgress === true;
        }
        static markPreflightInProgress(file) {
          file._preflightInProgress = true;
        }
        constructor(fileEl, file, view, autoUpload) {
          this.ref = LiveUploader.genFileRef(file);
          this.fileEl = fileEl;
          this.file = file;
          this.view = view;
          this.meta = null;
          this._isCancelled = false;
          this._isDone = false;
          this._progress = 0;
          this._lastProgressSent = -1;
          this._onDone = function() {
          };
          this._onElUpdated = this.onElUpdated.bind(this);
          this.fileEl.addEventListener(PHX_LIVE_FILE_UPDATED, this._onElUpdated);
          this.autoUpload = autoUpload;
        }
        metadata() {
          return this.meta;
        }
        progress(progress) {
          this._progress = Math.floor(progress);
          if (this._progress > this._lastProgressSent) {
            if (this._progress >= 100) {
              this._progress = 100;
              this._lastProgressSent = 100;
              this._isDone = true;
              this.view.pushFileProgress(this.fileEl, this.ref, 100, () => {
                LiveUploader.untrackFile(this.fileEl, this.file);
                this._onDone();
              });
            } else {
              this._lastProgressSent = this._progress;
              this.view.pushFileProgress(this.fileEl, this.ref, this._progress);
            }
          }
        }
        isCancelled() {
          return this._isCancelled;
        }
        cancel() {
          this.file._preflightInProgress = false;
          this._isCancelled = true;
          this._isDone = true;
          this._onDone();
        }
        isDone() {
          return this._isDone;
        }
        error(reason = "failed") {
          this.fileEl.removeEventListener(PHX_LIVE_FILE_UPDATED, this._onElUpdated);
          this.view.pushFileProgress(this.fileEl, this.ref, { error: reason });
          if (!this.isAutoUpload()) {
            LiveUploader.clearFiles(this.fileEl);
          }
        }
        isAutoUpload() {
          return this.autoUpload;
        }
        //private
        onDone(callback) {
          this._onDone = () => {
            this.fileEl.removeEventListener(PHX_LIVE_FILE_UPDATED, this._onElUpdated);
            callback();
          };
        }
        onElUpdated() {
          const activeRefs = this.fileEl.getAttribute(PHX_ACTIVE_ENTRY_REFS).split(",");
          if (activeRefs.indexOf(this.ref) === -1) {
            LiveUploader.untrackFile(this.fileEl, this.file);
            this.cancel();
          }
        }
        toPreflightPayload() {
          return {
            last_modified: this.file.lastModified,
            name: this.file.name,
            relative_path: this.file.webkitRelativePath,
            size: this.file.size,
            type: this.file.type,
            ref: this.ref,
            meta: typeof this.file.meta === "function" ? this.file.meta() : void 0
          };
        }
        uploader(uploaders) {
          if (this.meta.uploader) {
            const callback = uploaders[this.meta.uploader] || logError(`no uploader configured for ${this.meta.uploader}`);
            return { name: this.meta.uploader, callback };
          } else {
            return { name: "channel", callback: channelUploader };
          }
        }
        zipPostFlight(resp) {
          this.meta = resp.entries[this.ref];
          if (!this.meta) {
            logError(`no preflight upload response returned with ref ${this.ref}`, {
              input: this.fileEl,
              response: resp
            });
          }
        }
      };
      liveUploaderFileRef = 0;
      LiveUploader = class _LiveUploader {
        static genFileRef(file) {
          const ref = file._phxRef;
          if (ref !== void 0) {
            return ref;
          } else {
            file._phxRef = (liveUploaderFileRef++).toString();
            return file._phxRef;
          }
        }
        static getEntryDataURL(inputEl, ref, callback) {
          const file = this.activeFiles(inputEl).find(
            (file2) => this.genFileRef(file2) === ref
          );
          callback(URL.createObjectURL(file));
        }
        static hasUploadsInProgress(formEl) {
          let active = 0;
          dom_default.findUploadInputs(formEl).forEach((input) => {
            if (input.getAttribute(PHX_PREFLIGHTED_REFS) !== input.getAttribute(PHX_DONE_REFS)) {
              active++;
            }
          });
          return active > 0;
        }
        static serializeUploads(inputEl) {
          const files = this.activeFiles(inputEl);
          const fileData = {};
          files.forEach((file) => {
            const entry = { path: inputEl.name };
            const uploadRef = inputEl.getAttribute(PHX_UPLOAD_REF);
            fileData[uploadRef] = fileData[uploadRef] || [];
            entry.ref = this.genFileRef(file);
            entry.last_modified = file.lastModified;
            entry.name = file.name || entry.ref;
            entry.relative_path = file.webkitRelativePath;
            entry.type = file.type;
            entry.size = file.size;
            if (typeof file.meta === "function") {
              entry.meta = file.meta();
            }
            fileData[uploadRef].push(entry);
          });
          return fileData;
        }
        static clearFiles(inputEl) {
          inputEl.value = null;
          inputEl.removeAttribute(PHX_UPLOAD_REF);
          dom_default.putPrivate(inputEl, "files", []);
        }
        static untrackFile(inputEl, file) {
          dom_default.putPrivate(
            inputEl,
            "files",
            dom_default.private(inputEl, "files").filter((f) => !Object.is(f, file))
          );
        }
        /**
         * @param {HTMLInputElement} inputEl
         * @param {Array<File|Blob>} files
         * @param {DataTransfer} [dataTransfer]
         */
        static trackFiles(inputEl, files, dataTransfer) {
          if (inputEl.getAttribute("multiple") !== null) {
            const newFiles = files.filter(
              (file) => !this.activeFiles(inputEl).find((f) => Object.is(f, file))
            );
            dom_default.updatePrivate(
              inputEl,
              "files",
              [],
              (existing) => existing.concat(newFiles)
            );
            inputEl.value = null;
          } else {
            if (dataTransfer && dataTransfer.files.length > 0) {
              inputEl.files = dataTransfer.files;
            }
            dom_default.putPrivate(inputEl, "files", files);
          }
        }
        static activeFileInputs(formEl) {
          const fileInputs = dom_default.findUploadInputs(formEl);
          return Array.from(fileInputs).filter(
            (el2) => el2.files && this.activeFiles(el2).length > 0
          );
        }
        static activeFiles(input) {
          return (dom_default.private(input, "files") || []).filter(
            (f) => UploadEntry.isActive(input, f)
          );
        }
        static inputsAwaitingPreflight(formEl) {
          const fileInputs = dom_default.findUploadInputs(formEl);
          return Array.from(fileInputs).filter(
            (input) => this.filesAwaitingPreflight(input).length > 0
          );
        }
        static filesAwaitingPreflight(input) {
          return this.activeFiles(input).filter(
            (f) => !UploadEntry.isPreflighted(input, f) && !UploadEntry.isPreflightInProgress(f)
          );
        }
        static markPreflightInProgress(entries) {
          entries.forEach((entry) => UploadEntry.markPreflightInProgress(entry.file));
        }
        constructor(inputEl, view, onComplete) {
          this.autoUpload = dom_default.isAutoUpload(inputEl);
          this.view = view;
          this.onComplete = onComplete;
          this._entries = Array.from(
            _LiveUploader.filesAwaitingPreflight(inputEl) || []
          ).map((file) => new UploadEntry(inputEl, file, view, this.autoUpload));
          _LiveUploader.markPreflightInProgress(this._entries);
          this.numEntriesInProgress = this._entries.length;
        }
        isAutoUpload() {
          return this.autoUpload;
        }
        entries() {
          return this._entries;
        }
        initAdapterUpload(resp, onError, liveSocket) {
          this._entries = this._entries.map((entry) => {
            if (entry.isCancelled()) {
              this.numEntriesInProgress--;
              if (this.numEntriesInProgress === 0) {
                this.onComplete();
              }
            } else {
              entry.zipPostFlight(resp);
              entry.onDone(() => {
                this.numEntriesInProgress--;
                if (this.numEntriesInProgress === 0) {
                  this.onComplete();
                }
              });
            }
            return entry;
          });
          const groupedEntries = this._entries.reduce((acc, entry) => {
            if (!entry.meta) {
              return acc;
            }
            const { name, callback } = entry.uploader(liveSocket.uploaders);
            acc[name] = acc[name] || { callback, entries: [] };
            acc[name].entries.push(entry);
            return acc;
          }, {});
          for (const name in groupedEntries) {
            const { callback, entries } = groupedEntries[name];
            callback(entries, onError, resp, liveSocket);
          }
        }
      };
      ARIA = {
        anyOf(instance, classes) {
          return classes.find((name) => instance instanceof name);
        },
        isFocusable(el2, interactiveOnly) {
          return el2 instanceof HTMLAnchorElement && el2.rel !== "ignore" || el2 instanceof HTMLAreaElement && el2.href !== void 0 || !el2.disabled && this.anyOf(el2, [
            HTMLInputElement,
            HTMLSelectElement,
            HTMLTextAreaElement,
            HTMLButtonElement
          ]) || el2 instanceof HTMLIFrameElement || el2.tabIndex >= 0 && el2.getAttribute("aria-hidden") !== "true" || !interactiveOnly && el2.getAttribute("tabindex") !== null && el2.getAttribute("aria-hidden") !== "true";
        },
        attemptFocus(el2, interactiveOnly) {
          if (this.isFocusable(el2, interactiveOnly)) {
            try {
              el2.focus();
            } catch {
            }
          }
          return !!document.activeElement && document.activeElement.isSameNode(el2);
        },
        focusFirstInteractive(el2) {
          let child = el2.firstElementChild;
          while (child) {
            if (this.attemptFocus(child, true) || this.focusFirstInteractive(child)) {
              return true;
            }
            child = child.nextElementSibling;
          }
        },
        focusFirst(el2) {
          let child = el2.firstElementChild;
          while (child) {
            if (this.attemptFocus(child) || this.focusFirst(child)) {
              return true;
            }
            child = child.nextElementSibling;
          }
        },
        focusLast(el2) {
          let child = el2.lastElementChild;
          while (child) {
            if (this.attemptFocus(child) || this.focusLast(child)) {
              return true;
            }
            child = child.previousElementSibling;
          }
        }
      };
      aria_default = ARIA;
      Hooks = {
        LiveFileUpload: {
          activeRefs() {
            return this.el.getAttribute(PHX_ACTIVE_ENTRY_REFS);
          },
          preflightedRefs() {
            return this.el.getAttribute(PHX_PREFLIGHTED_REFS);
          },
          mounted() {
            this.js().ignoreAttributes(this.el, ["value"]);
            this.preflightedWas = this.preflightedRefs();
          },
          updated() {
            const newPreflights = this.preflightedRefs();
            if (this.preflightedWas !== newPreflights) {
              this.preflightedWas = newPreflights;
              if (newPreflights === "") {
                this.__view().cancelSubmit(this.el.form);
              }
            }
            if (this.activeRefs() === "") {
              this.el.value = null;
            }
            this.el.dispatchEvent(new CustomEvent(PHX_LIVE_FILE_UPDATED));
          }
        },
        LiveImgPreview: {
          mounted() {
            this.ref = this.el.getAttribute("data-phx-entry-ref");
            this.inputEl = document.getElementById(
              this.el.getAttribute(PHX_UPLOAD_REF)
            );
            LiveUploader.getEntryDataURL(this.inputEl, this.ref, (url) => {
              this.url = url;
              this.el.src = url;
            });
          },
          destroyed() {
            URL.revokeObjectURL(this.url);
          }
        },
        FocusWrap: {
          mounted() {
            this.focusStart = this.el.firstElementChild;
            this.focusEnd = this.el.lastElementChild;
            this.focusStart.addEventListener("focus", (e) => {
              if (!e.relatedTarget || !this.el.contains(e.relatedTarget)) {
                const nextFocus = e.target.nextElementSibling;
                aria_default.attemptFocus(nextFocus) || aria_default.focusFirst(nextFocus);
              } else {
                aria_default.focusLast(this.el);
              }
            });
            this.focusEnd.addEventListener("focus", (e) => {
              if (!e.relatedTarget || !this.el.contains(e.relatedTarget)) {
                const nextFocus = e.target.previousElementSibling;
                aria_default.attemptFocus(nextFocus) || aria_default.focusLast(nextFocus);
              } else {
                aria_default.focusFirst(this.el);
              }
            });
            if (!this.el.contains(document.activeElement)) {
              this.el.addEventListener("phx:show-end", () => this.el.focus());
              if (window.getComputedStyle(this.el).display !== "none") {
                aria_default.focusFirst(this.el);
              }
            }
          }
        }
      };
      findScrollContainer = (el2) => {
        if (["HTML", "BODY"].indexOf(el2.nodeName.toUpperCase()) >= 0)
          return null;
        if (["scroll", "auto"].indexOf(getComputedStyle(el2).overflowY) >= 0)
          return el2;
        return findScrollContainer(el2.parentElement);
      };
      scrollTop = (scrollContainer) => {
        if (scrollContainer) {
          return scrollContainer.scrollTop;
        } else {
          return document.documentElement.scrollTop || document.body.scrollTop;
        }
      };
      bottom = (scrollContainer) => {
        if (scrollContainer) {
          return scrollContainer.getBoundingClientRect().bottom;
        } else {
          return window.innerHeight || document.documentElement.clientHeight;
        }
      };
      top = (scrollContainer) => {
        if (scrollContainer) {
          return scrollContainer.getBoundingClientRect().top;
        } else {
          return 0;
        }
      };
      isAtViewportTop = (el2, scrollContainer) => {
        const rect = el2.getBoundingClientRect();
        return Math.ceil(rect.top) >= top(scrollContainer) && Math.ceil(rect.left) >= 0 && Math.floor(rect.top) <= bottom(scrollContainer);
      };
      isAtViewportBottom = (el2, scrollContainer) => {
        const rect = el2.getBoundingClientRect();
        return Math.ceil(rect.bottom) >= top(scrollContainer) && Math.ceil(rect.left) >= 0 && Math.floor(rect.bottom) <= bottom(scrollContainer);
      };
      isWithinViewport = (el2, scrollContainer) => {
        const rect = el2.getBoundingClientRect();
        return Math.ceil(rect.top) >= top(scrollContainer) && Math.ceil(rect.left) >= 0 && Math.floor(rect.top) <= bottom(scrollContainer);
      };
      Hooks.InfiniteScroll = {
        mounted() {
          this.scrollContainer = findScrollContainer(this.el);
          let scrollBefore = scrollTop(this.scrollContainer);
          let topOverran = false;
          const throttleInterval = 500;
          let pendingOp = null;
          const onTopOverrun = this.throttle(
            throttleInterval,
            (topEvent, firstChild) => {
              pendingOp = () => true;
              this.liveSocket.js().push(this.el, topEvent, {
                value: { id: firstChild.id, _overran: true },
                callback: () => {
                  pendingOp = null;
                }
              });
            }
          );
          const onFirstChildAtTop = this.throttle(
            throttleInterval,
            (topEvent, firstChild) => {
              pendingOp = () => firstChild.scrollIntoView({ block: "start" });
              this.liveSocket.js().push(this.el, topEvent, {
                value: { id: firstChild.id },
                callback: () => {
                  pendingOp = null;
                  window.requestAnimationFrame(() => {
                    if (!isWithinViewport(firstChild, this.scrollContainer)) {
                      firstChild.scrollIntoView({ block: "start" });
                    }
                  });
                }
              });
            }
          );
          const onLastChildAtBottom = this.throttle(
            throttleInterval,
            (bottomEvent, lastChild) => {
              pendingOp = () => lastChild.scrollIntoView({ block: "end" });
              this.liveSocket.js().push(this.el, bottomEvent, {
                value: { id: lastChild.id },
                callback: () => {
                  pendingOp = null;
                  window.requestAnimationFrame(() => {
                    if (!isWithinViewport(lastChild, this.scrollContainer)) {
                      lastChild.scrollIntoView({ block: "end" });
                    }
                  });
                }
              });
            }
          );
          this.onScroll = (_e3) => {
            const scrollNow = scrollTop(this.scrollContainer);
            if (pendingOp) {
              scrollBefore = scrollNow;
              return pendingOp();
            }
            const rect = this.findOverrunTarget();
            const topEvent = this.el.getAttribute(
              this.liveSocket.binding("viewport-top")
            );
            const bottomEvent = this.el.getAttribute(
              this.liveSocket.binding("viewport-bottom")
            );
            const lastChild = this.el.lastElementChild;
            const firstChild = this.el.firstElementChild;
            const isScrollingUp = scrollNow < scrollBefore;
            const isScrollingDown = scrollNow > scrollBefore;
            if (isScrollingUp && topEvent && !topOverran && rect.top >= 0) {
              topOverran = true;
              onTopOverrun(topEvent, firstChild);
            } else if (isScrollingDown && topOverran && rect.top <= 0) {
              topOverran = false;
            }
            if (topEvent && isScrollingUp && isAtViewportTop(firstChild, this.scrollContainer)) {
              onFirstChildAtTop(topEvent, firstChild);
            } else if (bottomEvent && isScrollingDown && isAtViewportBottom(lastChild, this.scrollContainer)) {
              onLastChildAtBottom(bottomEvent, lastChild);
            }
            scrollBefore = scrollNow;
          };
          if (this.scrollContainer) {
            this.scrollContainer.addEventListener("scroll", this.onScroll);
          } else {
            window.addEventListener("scroll", this.onScroll);
          }
        },
        destroyed() {
          if (this.scrollContainer) {
            this.scrollContainer.removeEventListener("scroll", this.onScroll);
          } else {
            window.removeEventListener("scroll", this.onScroll);
          }
        },
        throttle(interval, callback) {
          let lastCallAt = 0;
          let timer;
          return (...args) => {
            const now = Date.now();
            const remainingTime = interval - (now - lastCallAt);
            if (remainingTime <= 0 || remainingTime > interval) {
              if (timer) {
                clearTimeout(timer);
                timer = null;
              }
              lastCallAt = now;
              callback(...args);
            } else if (!timer) {
              timer = setTimeout(() => {
                lastCallAt = Date.now();
                timer = null;
                callback(...args);
              }, remainingTime);
            }
          };
        },
        findOverrunTarget() {
          let rect;
          const overrunTarget = this.el.getAttribute(
            this.liveSocket.binding(PHX_VIEWPORT_OVERRUN_TARGET)
          );
          if (overrunTarget) {
            const overrunEl = document.getElementById(overrunTarget);
            if (overrunEl) {
              rect = overrunEl.getBoundingClientRect();
            } else {
              throw new Error("did not find element with id " + overrunTarget);
            }
          } else {
            rect = this.el.getBoundingClientRect();
          }
          return rect;
        }
      };
      hooks_default = Hooks;
      ElementRef = class {
        static onUnlock(el2, callback) {
          if (!dom_default.isLocked(el2) && !el2.closest(`[${PHX_REF_LOCK}]`)) {
            return callback();
          }
          const closestLock = el2.closest(`[${PHX_REF_LOCK}]`);
          const ref = closestLock.closest(`[${PHX_REF_LOCK}]`).getAttribute(PHX_REF_LOCK);
          closestLock.addEventListener(
            `phx:undo-lock:${ref}`,
            () => {
              callback();
            },
            { once: true }
          );
        }
        constructor(el2) {
          this.el = el2;
          this.loadingRef = el2.hasAttribute(PHX_REF_LOADING) ? parseInt(el2.getAttribute(PHX_REF_LOADING), 10) : null;
          this.lockRef = el2.hasAttribute(PHX_REF_LOCK) ? parseInt(el2.getAttribute(PHX_REF_LOCK), 10) : null;
        }
        // public
        maybeUndo(ref, phxEvent, eachCloneCallback) {
          if (!this.isWithin(ref)) {
            dom_default.updatePrivate(this.el, PHX_PENDING_REFS, [], (pendingRefs) => {
              pendingRefs.push(ref);
              return pendingRefs;
            });
            return;
          }
          this.undoLocks(ref, phxEvent, eachCloneCallback);
          this.undoLoading(ref, phxEvent);
          dom_default.updatePrivate(this.el, PHX_PENDING_REFS, [], (pendingRefs) => {
            return pendingRefs.filter((pendingRef) => {
              let opts = {
                detail: { ref: pendingRef, event: phxEvent },
                bubbles: true,
                cancelable: false
              };
              if (this.loadingRef && this.loadingRef > pendingRef) {
                this.el.dispatchEvent(
                  new CustomEvent(`phx:undo-loading:${pendingRef}`, opts)
                );
              }
              if (this.lockRef && this.lockRef > pendingRef) {
                this.el.dispatchEvent(
                  new CustomEvent(`phx:undo-lock:${pendingRef}`, opts)
                );
              }
              return pendingRef > ref;
            });
          });
          if (this.isFullyResolvedBy(ref)) {
            this.el.removeAttribute(PHX_REF_SRC);
          }
        }
        // private
        isWithin(ref) {
          return !(this.loadingRef !== null && this.loadingRef > ref && this.lockRef !== null && this.lockRef > ref);
        }
        // Check for cloned PHX_REF_LOCK element that has been morphed behind
        // the scenes while this element was locked in the DOM.
        // When we apply the cloned tree to the active DOM element, we must
        //
        //   1. execute pending mounted hooks for nodes now in the DOM
        //   2. undo any ref inside the cloned tree that has since been ack'd
        undoLocks(ref, phxEvent, eachCloneCallback) {
          if (!this.isLockUndoneBy(ref)) {
            return;
          }
          const clonedTree = dom_default.private(this.el, PHX_REF_LOCK);
          if (clonedTree) {
            eachCloneCallback(clonedTree);
            dom_default.deletePrivate(this.el, PHX_REF_LOCK);
          }
          this.el.removeAttribute(PHX_REF_LOCK);
          const opts = {
            detail: { ref, event: phxEvent },
            bubbles: true,
            cancelable: false
          };
          this.el.dispatchEvent(
            new CustomEvent(`phx:undo-lock:${this.lockRef}`, opts)
          );
        }
        undoLoading(ref, phxEvent) {
          if (!this.isLoadingUndoneBy(ref)) {
            if (this.canUndoLoading(ref) && this.el.classList.contains("phx-submit-loading")) {
              this.el.classList.remove("phx-change-loading");
            }
            return;
          }
          if (this.canUndoLoading(ref)) {
            this.el.removeAttribute(PHX_REF_LOADING);
            const disabledVal = this.el.getAttribute(PHX_DISABLED);
            const readOnlyVal = this.el.getAttribute(PHX_READONLY);
            if (readOnlyVal !== null) {
              this.el.readOnly = readOnlyVal === "true" ? true : false;
              this.el.removeAttribute(PHX_READONLY);
            }
            if (disabledVal !== null) {
              this.el.disabled = disabledVal === "true" ? true : false;
              this.el.removeAttribute(PHX_DISABLED);
            }
            const disableRestore = this.el.getAttribute(PHX_DISABLE_WITH_RESTORE);
            if (disableRestore !== null) {
              this.el.textContent = disableRestore;
              this.el.removeAttribute(PHX_DISABLE_WITH_RESTORE);
            }
            const opts = {
              detail: { ref, event: phxEvent },
              bubbles: true,
              cancelable: false
            };
            this.el.dispatchEvent(
              new CustomEvent(`phx:undo-loading:${this.loadingRef}`, opts)
            );
          }
          PHX_EVENT_CLASSES.forEach((name) => {
            if (name !== "phx-submit-loading" || this.canUndoLoading(ref)) {
              dom_default.removeClass(this.el, name);
            }
          });
        }
        isLoadingUndoneBy(ref) {
          return this.loadingRef === null ? false : this.loadingRef <= ref;
        }
        isLockUndoneBy(ref) {
          return this.lockRef === null ? false : this.lockRef <= ref;
        }
        isFullyResolvedBy(ref) {
          return (this.loadingRef === null || this.loadingRef <= ref) && (this.lockRef === null || this.lockRef <= ref);
        }
        // only remove the phx-submit-loading class if we are not locked
        canUndoLoading(ref) {
          return this.lockRef === null || this.lockRef <= ref;
        }
      };
      DOMPostMorphRestorer = class {
        constructor(containerBefore, containerAfter, updateType) {
          const idsBefore = /* @__PURE__ */ new Set();
          const idsAfter = new Set(
            [...containerAfter.children].map((child) => child.id)
          );
          const elementsToModify = [];
          Array.from(containerBefore.children).forEach((child) => {
            if (child.id) {
              idsBefore.add(child.id);
              if (idsAfter.has(child.id)) {
                const previousElementId = child.previousElementSibling && child.previousElementSibling.id;
                elementsToModify.push({
                  elementId: child.id,
                  previousElementId
                });
              }
            }
          });
          this.containerId = containerAfter.id;
          this.updateType = updateType;
          this.elementsToModify = elementsToModify;
          this.elementIdsToAdd = [...idsAfter].filter((id) => !idsBefore.has(id));
        }
        // We do the following to optimize append/prepend operations:
        //   1) Track ids of modified elements & of new elements
        //   2) All the modified elements are put back in the correct position in the DOM tree
        //      by storing the id of their previous sibling
        //   3) New elements are going to be put in the right place by morphdom during append.
        //      For prepend, we move them to the first position in the container
        perform() {
          const container = dom_default.byId(this.containerId);
          if (!container) {
            return;
          }
          this.elementsToModify.forEach((elementToModify) => {
            if (elementToModify.previousElementId) {
              maybe(
                document.getElementById(elementToModify.previousElementId),
                (previousElem) => {
                  maybe(
                    document.getElementById(elementToModify.elementId),
                    (elem) => {
                      const isInRightPlace = elem.previousElementSibling && elem.previousElementSibling.id == previousElem.id;
                      if (!isInRightPlace) {
                        previousElem.insertAdjacentElement("afterend", elem);
                      }
                    }
                  );
                }
              );
            } else {
              maybe(document.getElementById(elementToModify.elementId), (elem) => {
                const isInRightPlace = elem.previousElementSibling == null;
                if (!isInRightPlace) {
                  container.insertAdjacentElement("afterbegin", elem);
                }
              });
            }
          });
          if (this.updateType == "prepend") {
            this.elementIdsToAdd.reverse().forEach((elemId) => {
              maybe(
                document.getElementById(elemId),
                (elem) => container.insertAdjacentElement("afterbegin", elem)
              );
            });
          }
        }
      };
      DOCUMENT_FRAGMENT_NODE = 11;
      NS_XHTML = "http://www.w3.org/1999/xhtml";
      doc = typeof document === "undefined" ? void 0 : document;
      HAS_TEMPLATE_SUPPORT = !!doc && "content" in doc.createElement("template");
      HAS_RANGE_SUPPORT = !!doc && doc.createRange && "createContextualFragment" in doc.createRange();
      specialElHandlers = {
        OPTION: function(fromEl, toEl) {
          var parentNode = fromEl.parentNode;
          if (parentNode) {
            var parentName = parentNode.nodeName.toUpperCase();
            if (parentName === "OPTGROUP") {
              parentNode = parentNode.parentNode;
              parentName = parentNode && parentNode.nodeName.toUpperCase();
            }
            if (parentName === "SELECT" && !parentNode.hasAttribute("multiple")) {
              if (fromEl.hasAttribute("selected") && !toEl.selected) {
                fromEl.setAttribute("selected", "selected");
                fromEl.removeAttribute("selected");
              }
              parentNode.selectedIndex = -1;
            }
          }
          syncBooleanAttrProp(fromEl, toEl, "selected");
        },
        /**
         * The "value" attribute is special for the <input> element since it sets
         * the initial value. Changing the "value" attribute without changing the
         * "value" property will have no effect since it is only used to the set the
         * initial value.  Similar for the "checked" attribute, and "disabled".
         */
        INPUT: function(fromEl, toEl) {
          syncBooleanAttrProp(fromEl, toEl, "checked");
          syncBooleanAttrProp(fromEl, toEl, "disabled");
          if (fromEl.value !== toEl.value) {
            fromEl.value = toEl.value;
          }
          if (!toEl.hasAttribute("value")) {
            fromEl.removeAttribute("value");
          }
        },
        TEXTAREA: function(fromEl, toEl) {
          var newValue = toEl.value;
          if (fromEl.value !== newValue) {
            fromEl.value = newValue;
          }
          var firstChild = fromEl.firstChild;
          if (firstChild) {
            var oldValue = firstChild.nodeValue;
            if (oldValue == newValue || !newValue && oldValue == fromEl.placeholder) {
              return;
            }
            firstChild.nodeValue = newValue;
          }
        },
        SELECT: function(fromEl, toEl) {
          if (!toEl.hasAttribute("multiple")) {
            var selectedIndex = -1;
            var i = 0;
            var curChild = fromEl.firstChild;
            var optgroup;
            var nodeName;
            while (curChild) {
              nodeName = curChild.nodeName && curChild.nodeName.toUpperCase();
              if (nodeName === "OPTGROUP") {
                optgroup = curChild;
                curChild = optgroup.firstChild;
                if (!curChild) {
                  curChild = optgroup.nextSibling;
                  optgroup = null;
                }
              } else {
                if (nodeName === "OPTION") {
                  if (curChild.hasAttribute("selected")) {
                    selectedIndex = i;
                    break;
                  }
                  i++;
                }
                curChild = curChild.nextSibling;
                if (!curChild && optgroup) {
                  curChild = optgroup.nextSibling;
                  optgroup = null;
                }
              }
            }
            fromEl.selectedIndex = selectedIndex;
          }
        }
      };
      ELEMENT_NODE = 1;
      DOCUMENT_FRAGMENT_NODE$1 = 11;
      TEXT_NODE = 3;
      COMMENT_NODE = 8;
      morphdom = morphdomFactory(morphAttrs);
      morphdom_esm_default = morphdom;
      DOMPatch = class {
        constructor(view, container, id, html, streams, targetCID, opts = {}) {
          this.view = view;
          this.liveSocket = view.liveSocket;
          this.container = container;
          this.id = id;
          this.rootID = view.root.id;
          this.html = html;
          this.streams = streams;
          this.streamInserts = {};
          this.streamComponentRestore = {};
          this.targetCID = targetCID;
          this.cidPatch = isCid(this.targetCID);
          this.pendingRemoves = [];
          this.phxRemove = this.liveSocket.binding("remove");
          this.targetContainer = this.isCIDPatch() ? this.targetCIDContainer(html) : container;
          this.callbacks = {
            beforeadded: [],
            beforeupdated: [],
            beforephxChildAdded: [],
            afteradded: [],
            afterupdated: [],
            afterdiscarded: [],
            afterphxChildAdded: [],
            aftertransitionsDiscarded: []
          };
          this.withChildren = opts.withChildren || opts.undoRef || false;
          this.undoRef = opts.undoRef;
        }
        before(kind, callback) {
          this.callbacks[`before${kind}`].push(callback);
        }
        after(kind, callback) {
          this.callbacks[`after${kind}`].push(callback);
        }
        trackBefore(kind, ...args) {
          this.callbacks[`before${kind}`].forEach((callback) => callback(...args));
        }
        trackAfter(kind, ...args) {
          this.callbacks[`after${kind}`].forEach((callback) => callback(...args));
        }
        markPrunableContentForRemoval() {
          const phxUpdate = this.liveSocket.binding(PHX_UPDATE);
          dom_default.all(
            this.container,
            `[${phxUpdate}=append] > *, [${phxUpdate}=prepend] > *`,
            (el2) => {
              el2.setAttribute(PHX_PRUNE, "");
            }
          );
        }
        perform(isJoinPatch) {
          const { view, liveSocket, html, container } = this;
          let targetContainer = this.targetContainer;
          if (this.isCIDPatch() && !this.targetContainer) {
            return;
          }
          if (this.isCIDPatch()) {
            const closestLock = targetContainer.closest(`[${PHX_REF_LOCK}]`);
            if (closestLock && !closestLock.isSameNode(targetContainer)) {
              const clonedTree = dom_default.private(closestLock, PHX_REF_LOCK);
              if (clonedTree) {
                targetContainer = clonedTree.querySelector(
                  `[data-phx-component="${this.targetCID}"]`
                );
              }
            }
          }
          const focused = liveSocket.getActiveElement();
          const { selectionStart, selectionEnd } = focused && dom_default.hasSelectionRange(focused) ? focused : {};
          const phxUpdate = liveSocket.binding(PHX_UPDATE);
          const phxViewportTop = liveSocket.binding(PHX_VIEWPORT_TOP);
          const phxViewportBottom = liveSocket.binding(PHX_VIEWPORT_BOTTOM);
          const phxTriggerExternal = liveSocket.binding(PHX_TRIGGER_ACTION);
          const added = [];
          const updates = [];
          const appendPrependUpdates = [];
          let portalCallbacks = [];
          let externalFormTriggered = null;
          const morph = (targetContainer2, source, withChildren = this.withChildren) => {
            const morphCallbacks = {
              // normally, we are running with childrenOnly, as the patch HTML for a LV
              // does not include the LV attrs (data-phx-session, etc.)
              // when we are patching a live component, we do want to patch the root element as well;
              // another case is the recursive patch of a stream item that was kept on reset (-> onBeforeNodeAdded)
              childrenOnly: targetContainer2.getAttribute(PHX_COMPONENT) === null && !withChildren,
              getNodeKey: (node) => {
                if (dom_default.isPhxDestroyed(node)) {
                  return null;
                }
                if (isJoinPatch) {
                  return node.id;
                }
                return node.id || node.getAttribute && node.getAttribute(PHX_MAGIC_ID);
              },
              // skip indexing from children when container is stream
              skipFromChildren: (from) => {
                return from.getAttribute(phxUpdate) === PHX_STREAM;
              },
              // tell morphdom how to add a child
              addChild: (parent, child) => {
                const { ref, streamAt } = this.getStreamInsert(child);
                if (ref === void 0) {
                  return parent.appendChild(child);
                }
                this.setStreamRef(child, ref);
                if (streamAt === 0) {
                  parent.insertAdjacentElement("afterbegin", child);
                } else if (streamAt === -1) {
                  const lastChild = parent.lastElementChild;
                  if (lastChild && !lastChild.hasAttribute(PHX_STREAM_REF)) {
                    const nonStreamChild = Array.from(parent.children).find(
                      (c) => !c.hasAttribute(PHX_STREAM_REF)
                    );
                    parent.insertBefore(child, nonStreamChild);
                  } else {
                    parent.appendChild(child);
                  }
                } else if (streamAt > 0) {
                  const sibling = Array.from(parent.children)[streamAt];
                  parent.insertBefore(child, sibling);
                }
              },
              onBeforeNodeAdded: (el2) => {
                if (this.getStreamInsert(el2)?.updateOnly && !this.streamComponentRestore[el2.id]) {
                  return false;
                }
                dom_default.maintainPrivateHooks(el2, el2, phxViewportTop, phxViewportBottom);
                this.trackBefore("added", el2);
                let morphedEl = el2;
                if (this.streamComponentRestore[el2.id]) {
                  morphedEl = this.streamComponentRestore[el2.id];
                  delete this.streamComponentRestore[el2.id];
                  morph(morphedEl, el2, true);
                }
                return morphedEl;
              },
              onNodeAdded: (el2) => {
                if (el2.getAttribute) {
                  this.maybeReOrderStream(el2, true);
                }
                if (dom_default.isPortalTemplate(el2)) {
                  portalCallbacks.push(() => this.teleport(el2, morph));
                }
                if (el2 instanceof HTMLImageElement && el2.srcset) {
                  el2.srcset = el2.srcset;
                } else if (el2 instanceof HTMLVideoElement && el2.autoplay) {
                  el2.play();
                }
                if (dom_default.isNowTriggerFormExternal(el2, phxTriggerExternal)) {
                  externalFormTriggered = el2;
                }
                if (dom_default.isPhxChild(el2) && view.ownsElement(el2) || dom_default.isPhxSticky(el2) && view.ownsElement(el2.parentNode)) {
                  this.trackAfter("phxChildAdded", el2);
                }
                if (el2.nodeName === "SCRIPT" && el2.hasAttribute(PHX_RUNTIME_HOOK)) {
                  this.handleRuntimeHook(el2, source);
                }
                added.push(el2);
              },
              onNodeDiscarded: (el2) => this.onNodeDiscarded(el2),
              onBeforeNodeDiscarded: (el2) => {
                if (el2.getAttribute && el2.getAttribute(PHX_PRUNE) !== null) {
                  return true;
                }
                if (el2.parentElement !== null && el2.id && dom_default.isPhxUpdate(el2.parentElement, phxUpdate, [
                  PHX_STREAM,
                  "append",
                  "prepend"
                ])) {
                  return false;
                }
                if (el2.getAttribute && el2.getAttribute(PHX_TELEPORTED_REF)) {
                  return false;
                }
                if (this.maybePendingRemove(el2)) {
                  return false;
                }
                if (this.skipCIDSibling(el2)) {
                  return false;
                }
                if (dom_default.isPortalTemplate(el2)) {
                  const teleportedEl = document.getElementById(
                    el2.content.firstElementChild.id
                  );
                  if (teleportedEl) {
                    teleportedEl.remove();
                    morphCallbacks.onNodeDiscarded(teleportedEl);
                    this.view.dropPortalElementId(teleportedEl.id);
                  }
                }
                return true;
              },
              onElUpdated: (el2) => {
                if (dom_default.isNowTriggerFormExternal(el2, phxTriggerExternal)) {
                  externalFormTriggered = el2;
                }
                updates.push(el2);
                this.maybeReOrderStream(el2, false);
              },
              onBeforeElUpdated: (fromEl, toEl) => {
                if (fromEl.id && fromEl.isSameNode(targetContainer2) && fromEl.id !== toEl.id) {
                  morphCallbacks.onNodeDiscarded(fromEl);
                  fromEl.replaceWith(toEl);
                  return morphCallbacks.onNodeAdded(toEl);
                }
                dom_default.syncPendingAttrs(fromEl, toEl);
                dom_default.maintainPrivateHooks(
                  fromEl,
                  toEl,
                  phxViewportTop,
                  phxViewportBottom
                );
                dom_default.cleanChildNodes(toEl, phxUpdate);
                if (this.skipCIDSibling(toEl)) {
                  this.maybeReOrderStream(fromEl);
                  return false;
                }
                if (dom_default.isPhxSticky(fromEl)) {
                  [PHX_SESSION, PHX_STATIC, PHX_ROOT_ID].map((attr) => [
                    attr,
                    fromEl.getAttribute(attr),
                    toEl.getAttribute(attr)
                  ]).forEach(([attr, fromVal, toVal]) => {
                    if (toVal && fromVal !== toVal) {
                      fromEl.setAttribute(attr, toVal);
                    }
                  });
                  return false;
                }
                if (dom_default.isIgnored(fromEl, phxUpdate) || fromEl.form && fromEl.form.isSameNode(externalFormTriggered)) {
                  this.trackBefore("updated", fromEl, toEl);
                  dom_default.mergeAttrs(fromEl, toEl, {
                    isIgnored: dom_default.isIgnored(fromEl, phxUpdate)
                  });
                  updates.push(fromEl);
                  dom_default.applyStickyOperations(fromEl);
                  return false;
                }
                if (fromEl.type === "number" && fromEl.validity && fromEl.validity.badInput) {
                  return false;
                }
                const isFocusedFormEl = focused && fromEl.isSameNode(focused) && dom_default.isFormInput(fromEl);
                const focusedSelectChanged = isFocusedFormEl && this.isChangedSelect(fromEl, toEl);
                if (fromEl.hasAttribute(PHX_REF_SRC)) {
                  const ref = new ElementRef(fromEl);
                  if (ref.lockRef && (!this.undoRef || !ref.isLockUndoneBy(this.undoRef))) {
                    dom_default.applyStickyOperations(fromEl);
                    const isLocked = fromEl.hasAttribute(PHX_REF_LOCK);
                    const clone2 = isLocked ? dom_default.private(fromEl, PHX_REF_LOCK) || fromEl.cloneNode(true) : null;
                    if (clone2) {
                      dom_default.putPrivate(fromEl, PHX_REF_LOCK, clone2);
                      if (!isFocusedFormEl) {
                        fromEl = clone2;
                      }
                    }
                  }
                }
                if (dom_default.isPhxChild(toEl)) {
                  const prevSession = fromEl.getAttribute(PHX_SESSION);
                  dom_default.mergeAttrs(fromEl, toEl, { exclude: [PHX_STATIC] });
                  if (prevSession !== "") {
                    fromEl.setAttribute(PHX_SESSION, prevSession);
                  }
                  fromEl.setAttribute(PHX_ROOT_ID, this.rootID);
                  dom_default.applyStickyOperations(fromEl);
                  return false;
                }
                if (this.undoRef && dom_default.private(toEl, PHX_REF_LOCK)) {
                  dom_default.putPrivate(
                    fromEl,
                    PHX_REF_LOCK,
                    dom_default.private(toEl, PHX_REF_LOCK)
                  );
                }
                dom_default.copyPrivates(toEl, fromEl);
                if (dom_default.isPortalTemplate(toEl)) {
                  portalCallbacks.push(() => this.teleport(toEl, morph));
                  fromEl.innerHTML = toEl.innerHTML;
                  return false;
                }
                if (isFocusedFormEl && fromEl.type !== "hidden" && !focusedSelectChanged) {
                  this.trackBefore("updated", fromEl, toEl);
                  dom_default.mergeFocusedInput(fromEl, toEl);
                  dom_default.syncAttrsToProps(fromEl);
                  updates.push(fromEl);
                  dom_default.applyStickyOperations(fromEl);
                  return false;
                } else {
                  if (focusedSelectChanged) {
                    fromEl.blur();
                  }
                  if (dom_default.isPhxUpdate(toEl, phxUpdate, ["append", "prepend"])) {
                    appendPrependUpdates.push(
                      new DOMPostMorphRestorer(
                        fromEl,
                        toEl,
                        toEl.getAttribute(phxUpdate)
                      )
                    );
                  }
                  dom_default.syncAttrsToProps(toEl);
                  dom_default.applyStickyOperations(toEl);
                  this.trackBefore("updated", fromEl, toEl);
                  return fromEl;
                }
              }
            };
            morphdom_esm_default(targetContainer2, source, morphCallbacks);
          };
          this.trackBefore("added", container);
          this.trackBefore("updated", container, container);
          liveSocket.time("morphdom", () => {
            this.streams.forEach(([ref, inserts, deleteIds, reset]) => {
              inserts.forEach(([key, streamAt, limit, updateOnly]) => {
                this.streamInserts[key] = { ref, streamAt, limit, reset, updateOnly };
              });
              if (reset !== void 0) {
                dom_default.all(document, `[${PHX_STREAM_REF}="${ref}"]`, (child) => {
                  this.removeStreamChildElement(child);
                });
              }
              deleteIds.forEach((id) => {
                const child = document.getElementById(id);
                if (child) {
                  this.removeStreamChildElement(child);
                }
              });
            });
            if (isJoinPatch) {
              dom_default.all(this.container, `[${phxUpdate}=${PHX_STREAM}]`).filter((el2) => this.view.ownsElement(el2)).forEach((el2) => {
                Array.from(el2.children).forEach((child) => {
                  this.removeStreamChildElement(child, true);
                });
              });
            }
            morph(targetContainer, html);
            let teleportCount = 0;
            while (portalCallbacks.length > 0 && teleportCount < 5) {
              const copy = portalCallbacks.slice();
              portalCallbacks = [];
              copy.forEach((callback) => callback());
              teleportCount++;
            }
            this.view.portalElementIds.forEach((id) => {
              const el2 = document.getElementById(id);
              if (el2) {
                const source = document.getElementById(
                  el2.getAttribute(PHX_TELEPORTED_SRC)
                );
                if (!source) {
                  el2.remove();
                  this.onNodeDiscarded(el2);
                  this.view.dropPortalElementId(id);
                }
              }
            });
          });
          if (liveSocket.isDebugEnabled()) {
            detectDuplicateIds();
            detectInvalidStreamInserts(this.streamInserts);
            Array.from(document.querySelectorAll("input[name=id]")).forEach(
              (node) => {
                if (node instanceof HTMLInputElement && node.form) {
                  console.error(
                    'Detected an input with name="id" inside a form! This will cause problems when patching the DOM.\n',
                    node
                  );
                }
              }
            );
          }
          if (appendPrependUpdates.length > 0) {
            liveSocket.time("post-morph append/prepend restoration", () => {
              appendPrependUpdates.forEach((update) => update.perform());
            });
          }
          liveSocket.silenceEvents(
            () => dom_default.restoreFocus(focused, selectionStart, selectionEnd)
          );
          dom_default.dispatchEvent(document, "phx:update");
          added.forEach((el2) => this.trackAfter("added", el2));
          updates.forEach((el2) => this.trackAfter("updated", el2));
          this.transitionPendingRemoves();
          if (externalFormTriggered) {
            liveSocket.unload();
            const submitter = dom_default.private(externalFormTriggered, "submitter");
            if (submitter && submitter.name && targetContainer.contains(submitter)) {
              const input = document.createElement("input");
              input.type = "hidden";
              const formId = submitter.getAttribute("form");
              if (formId) {
                input.setAttribute("form", formId);
              }
              input.name = submitter.name;
              input.value = submitter.value;
              submitter.parentElement.insertBefore(input, submitter);
            }
            Object.getPrototypeOf(externalFormTriggered).submit.call(
              externalFormTriggered
            );
          }
          return true;
        }
        onNodeDiscarded(el2) {
          if (dom_default.isPhxChild(el2) || dom_default.isPhxSticky(el2)) {
            this.liveSocket.destroyViewByEl(el2);
          }
          this.trackAfter("discarded", el2);
        }
        maybePendingRemove(node) {
          if (node.getAttribute && node.getAttribute(this.phxRemove) !== null) {
            this.pendingRemoves.push(node);
            return true;
          } else {
            return false;
          }
        }
        removeStreamChildElement(child, force = false) {
          if (!force && !this.view.ownsElement(child)) {
            return;
          }
          if (this.streamInserts[child.id]) {
            this.streamComponentRestore[child.id] = child;
            child.remove();
          } else {
            if (!this.maybePendingRemove(child)) {
              child.remove();
              this.onNodeDiscarded(child);
            }
          }
        }
        getStreamInsert(el2) {
          const insert = el2.id ? this.streamInserts[el2.id] : {};
          return insert || {};
        }
        setStreamRef(el2, ref) {
          dom_default.putSticky(
            el2,
            PHX_STREAM_REF,
            (el22) => el22.setAttribute(PHX_STREAM_REF, ref)
          );
        }
        maybeReOrderStream(el2, isNew) {
          const { ref, streamAt, reset } = this.getStreamInsert(el2);
          if (streamAt === void 0) {
            return;
          }
          this.setStreamRef(el2, ref);
          if (!reset && !isNew) {
            return;
          }
          if (!el2.parentElement) {
            return;
          }
          if (streamAt === 0) {
            el2.parentElement.insertBefore(el2, el2.parentElement.firstElementChild);
          } else if (streamAt > 0) {
            const children = Array.from(el2.parentElement.children);
            const oldIndex = children.indexOf(el2);
            if (streamAt >= children.length - 1) {
              el2.parentElement.appendChild(el2);
            } else {
              const sibling = children[streamAt];
              if (oldIndex > streamAt) {
                el2.parentElement.insertBefore(el2, sibling);
              } else {
                el2.parentElement.insertBefore(el2, sibling.nextElementSibling);
              }
            }
          }
          this.maybeLimitStream(el2);
        }
        maybeLimitStream(el2) {
          const { limit } = this.getStreamInsert(el2);
          const children = limit !== null && Array.from(el2.parentElement.children);
          if (limit && limit < 0 && children.length > limit * -1) {
            children.slice(0, children.length + limit).forEach((child) => this.removeStreamChildElement(child));
          } else if (limit && limit >= 0 && children.length > limit) {
            children.slice(limit).forEach((child) => this.removeStreamChildElement(child));
          }
        }
        transitionPendingRemoves() {
          const { pendingRemoves, liveSocket } = this;
          if (pendingRemoves.length > 0) {
            liveSocket.transitionRemoves(pendingRemoves, () => {
              pendingRemoves.forEach((el2) => {
                const child = dom_default.firstPhxChild(el2);
                if (child) {
                  liveSocket.destroyViewByEl(child);
                }
                el2.remove();
              });
              this.trackAfter("transitionsDiscarded", pendingRemoves);
            });
          }
        }
        isChangedSelect(fromEl, toEl) {
          if (!(fromEl instanceof HTMLSelectElement) || fromEl.multiple) {
            return false;
          }
          if (fromEl.options.length !== toEl.options.length) {
            return true;
          }
          toEl.value = fromEl.value;
          return !fromEl.isEqualNode(toEl);
        }
        isCIDPatch() {
          return this.cidPatch;
        }
        skipCIDSibling(el2) {
          return el2.nodeType === Node.ELEMENT_NODE && el2.hasAttribute(PHX_SKIP);
        }
        targetCIDContainer(html) {
          if (!this.isCIDPatch()) {
            return;
          }
          const [first, ...rest] = dom_default.findComponentNodeList(
            this.view.id,
            this.targetCID
          );
          if (rest.length === 0 && dom_default.childNodeLength(html) === 1) {
            return first;
          } else {
            return first && first.parentNode;
          }
        }
        indexOf(parent, child) {
          return Array.from(parent.children).indexOf(child);
        }
        teleport(el2, morph) {
          const targetSelector = el2.getAttribute(PHX_PORTAL);
          const portalContainer = document.querySelector(targetSelector);
          if (!portalContainer) {
            throw new Error(
              "portal target with selector " + targetSelector + " not found"
            );
          }
          const toTeleport = el2.content.firstElementChild;
          if (this.skipCIDSibling(toTeleport)) {
            return;
          }
          if (!toTeleport?.id) {
            throw new Error(
              "phx-portal template must have a single root element with ID!"
            );
          }
          const existing = document.getElementById(toTeleport.id);
          let portalTarget;
          if (existing) {
            if (!portalContainer.contains(existing)) {
              portalContainer.appendChild(existing);
            }
            portalTarget = existing;
          } else {
            portalTarget = document.createElement(toTeleport.tagName);
            portalContainer.appendChild(portalTarget);
          }
          toTeleport.setAttribute(PHX_TELEPORTED_REF, this.view.id);
          toTeleport.setAttribute(PHX_TELEPORTED_SRC, el2.id);
          morph(portalTarget, toTeleport, true);
          toTeleport.removeAttribute(PHX_TELEPORTED_REF);
          toTeleport.removeAttribute(PHX_TELEPORTED_SRC);
          this.view.pushPortalElementId(toTeleport.id);
        }
        handleRuntimeHook(el2, source) {
          const name = el2.getAttribute(PHX_RUNTIME_HOOK);
          let nonce = el2.hasAttribute("nonce") ? el2.getAttribute("nonce") : null;
          if (el2.hasAttribute("nonce")) {
            const template = document.createElement("template");
            template.innerHTML = source;
            nonce = template.content.querySelector(`script[${PHX_RUNTIME_HOOK}="${CSS.escape(name)}"]`).getAttribute("nonce");
          }
          const script = document.createElement("script");
          script.textContent = el2.textContent;
          dom_default.mergeAttrs(script, el2, { isIgnored: false });
          if (nonce) {
            script.nonce = nonce;
          }
          el2.replaceWith(script);
          el2 = script;
        }
      };
      VOID_TAGS = /* @__PURE__ */ new Set([
        "area",
        "base",
        "br",
        "col",
        "command",
        "embed",
        "hr",
        "img",
        "input",
        "keygen",
        "link",
        "meta",
        "param",
        "source",
        "track",
        "wbr"
      ]);
      quoteChars = /* @__PURE__ */ new Set(["'", '"']);
      modifyRoot = (html, attrs, clearInnerHTML) => {
        let i = 0;
        let insideComment = false;
        let beforeTag, afterTag, tag, tagNameEndsAt, id, newHTML;
        const lookahead = html.match(/^(\s*(?:<!--.*?-->\s*)*)<([^\s\/>]+)/);
        if (lookahead === null) {
          throw new Error(`malformed html ${html}`);
        }
        i = lookahead[0].length;
        beforeTag = lookahead[1];
        tag = lookahead[2];
        tagNameEndsAt = i;
        for (i; i < html.length; i++) {
          if (html.charAt(i) === ">") {
            break;
          }
          if (html.charAt(i) === "=") {
            const isId = html.slice(i - 3, i) === " id";
            i++;
            const char = html.charAt(i);
            if (quoteChars.has(char)) {
              const attrStartsAt = i;
              i++;
              for (i; i < html.length; i++) {
                if (html.charAt(i) === char) {
                  break;
                }
              }
              if (isId) {
                id = html.slice(attrStartsAt + 1, i);
                break;
              }
            }
          }
        }
        let closeAt = html.length - 1;
        insideComment = false;
        while (closeAt >= beforeTag.length + tag.length) {
          const char = html.charAt(closeAt);
          if (insideComment) {
            if (char === "-" && html.slice(closeAt - 3, closeAt) === "<!-") {
              insideComment = false;
              closeAt -= 4;
            } else {
              closeAt -= 1;
            }
          } else if (char === ">" && html.slice(closeAt - 2, closeAt) === "--") {
            insideComment = true;
            closeAt -= 3;
          } else if (char === ">") {
            break;
          } else {
            closeAt -= 1;
          }
        }
        afterTag = html.slice(closeAt + 1, html.length);
        const attrsStr = Object.keys(attrs).map((attr) => attrs[attr] === true ? attr : `${attr}="${attrs[attr]}"`).join(" ");
        if (clearInnerHTML) {
          const idAttrStr = id ? ` id="${id}"` : "";
          if (VOID_TAGS.has(tag)) {
            newHTML = `<${tag}${idAttrStr}${attrsStr === "" ? "" : " "}${attrsStr}/>`;
          } else {
            newHTML = `<${tag}${idAttrStr}${attrsStr === "" ? "" : " "}${attrsStr}></${tag}>`;
          }
        } else {
          const rest = html.slice(tagNameEndsAt, closeAt + 1);
          newHTML = `<${tag}${attrsStr === "" ? "" : " "}${attrsStr}${rest}`;
        }
        return [newHTML, beforeTag, afterTag];
      };
      Rendered = class {
        static extract(diff) {
          const { [REPLY]: reply, [EVENTS]: events, [TITLE]: title } = diff;
          delete diff[REPLY];
          delete diff[EVENTS];
          delete diff[TITLE];
          return { diff, title, reply: reply || null, events: events || [] };
        }
        constructor(viewId, rendered) {
          this.viewId = viewId;
          this.rendered = {};
          this.magicId = 0;
          this.mergeDiff(rendered);
        }
        parentViewId() {
          return this.viewId;
        }
        toString(onlyCids) {
          const { buffer: str, streams } = this.recursiveToString(
            this.rendered,
            this.rendered[COMPONENTS],
            onlyCids,
            true,
            {}
          );
          return { buffer: str, streams };
        }
        recursiveToString(rendered, components = rendered[COMPONENTS], onlyCids, changeTracking, rootAttrs) {
          onlyCids = onlyCids ? new Set(onlyCids) : null;
          const output = {
            buffer: "",
            components,
            onlyCids,
            streams: /* @__PURE__ */ new Set()
          };
          this.toOutputBuffer(rendered, null, output, changeTracking, rootAttrs);
          return { buffer: output.buffer, streams: output.streams };
        }
        componentCIDs(diff) {
          return Object.keys(diff[COMPONENTS] || {}).map((i) => parseInt(i));
        }
        isComponentOnlyDiff(diff) {
          if (!diff[COMPONENTS]) {
            return false;
          }
          return Object.keys(diff).length === 1;
        }
        getComponent(diff, cid) {
          return diff[COMPONENTS][cid];
        }
        resetRender(cid) {
          if (this.rendered[COMPONENTS][cid]) {
            this.rendered[COMPONENTS][cid].reset = true;
          }
        }
        mergeDiff(diff) {
          const newc = diff[COMPONENTS];
          const cache = {};
          delete diff[COMPONENTS];
          this.rendered = this.mutableMerge(this.rendered, diff);
          this.rendered[COMPONENTS] = this.rendered[COMPONENTS] || {};
          if (newc) {
            const oldc = this.rendered[COMPONENTS];
            for (const cid in newc) {
              newc[cid] = this.cachedFindComponent(cid, newc[cid], oldc, newc, cache);
            }
            for (const cid in newc) {
              oldc[cid] = newc[cid];
            }
            diff[COMPONENTS] = newc;
          }
        }
        cachedFindComponent(cid, cdiff, oldc, newc, cache) {
          if (cache[cid]) {
            return cache[cid];
          } else {
            let ndiff, stat, scid = cdiff[STATIC];
            if (isCid(scid)) {
              let tdiff;
              if (scid > 0) {
                tdiff = this.cachedFindComponent(scid, newc[scid], oldc, newc, cache);
              } else {
                tdiff = oldc[-scid];
              }
              stat = tdiff[STATIC];
              ndiff = this.cloneMerge(tdiff, cdiff, true);
              ndiff[STATIC] = stat;
            } else {
              ndiff = cdiff[STATIC] !== void 0 || oldc[cid] === void 0 ? cdiff : this.cloneMerge(oldc[cid], cdiff, false);
            }
            cache[cid] = ndiff;
            return ndiff;
          }
        }
        mutableMerge(target, source) {
          if (source[STATIC] !== void 0) {
            return source;
          } else {
            this.doMutableMerge(target, source);
            return target;
          }
        }
        doMutableMerge(target, source) {
          if (source[KEYED]) {
            this.mergeKeyed(target, source);
          } else {
            for (const key in source) {
              const val = source[key];
              const targetVal = target[key];
              const isObjVal = isObject(val);
              if (isObjVal && val[STATIC] === void 0 && isObject(targetVal)) {
                this.doMutableMerge(targetVal, val);
              } else {
                target[key] = val;
              }
            }
          }
          if (target[ROOT]) {
            target.newRender = true;
          }
        }
        clone(diff) {
          if ("structuredClone" in window) {
            return structuredClone(diff);
          } else {
            return JSON.parse(JSON.stringify(diff));
          }
        }
        // keyed comprehensions
        mergeKeyed(target, source) {
          const clonedTarget = this.clone(target);
          Object.entries(source[KEYED]).forEach(([i, entry]) => {
            if (i === KEYED_COUNT) {
              return;
            }
            if (Array.isArray(entry)) {
              const [old_idx, diff] = entry;
              target[KEYED][i] = clonedTarget[KEYED][old_idx];
              this.doMutableMerge(target[KEYED][i], diff);
            } else if (typeof entry === "number") {
              const old_idx = entry;
              target[KEYED][i] = clonedTarget[KEYED][old_idx];
            } else if (typeof entry === "object") {
              if (!target[KEYED][i]) {
                target[KEYED][i] = {};
              }
              this.doMutableMerge(target[KEYED][i], entry);
            }
          });
          if (source[KEYED][KEYED_COUNT] < target[KEYED][KEYED_COUNT]) {
            for (let i = source[KEYED][KEYED_COUNT]; i < target[KEYED][KEYED_COUNT]; i++) {
              delete target[KEYED][i];
            }
          }
          target[KEYED][KEYED_COUNT] = source[KEYED][KEYED_COUNT];
          if (source[STREAM]) {
            target[STREAM] = source[STREAM];
          }
          if (source[TEMPLATES]) {
            target[TEMPLATES] = source[TEMPLATES];
          }
        }
        // Merges cid trees together, copying statics from source tree.
        //
        // The `pruneMagicId` is passed to control pruning the magicId of the
        // target. We must always prune the magicId when we are sharing statics
        // from another component. If not pruning, we replicate the logic from
        // mutableMerge, where we set newRender to true if there is a root
        // (effectively forcing the new version to be rendered instead of skipped)
        //
        cloneMerge(target, source, pruneMagicId) {
          let merged;
          if (source[KEYED]) {
            merged = this.clone(target);
            this.mergeKeyed(merged, source);
          } else {
            merged = { ...target, ...source };
            for (const key in merged) {
              const val = source[key];
              const targetVal = target[key];
              if (isObject(val) && val[STATIC] === void 0 && isObject(targetVal)) {
                merged[key] = this.cloneMerge(targetVal, val, pruneMagicId);
              } else if (val === void 0 && isObject(targetVal)) {
                merged[key] = this.cloneMerge(targetVal, {}, pruneMagicId);
              }
            }
          }
          if (pruneMagicId) {
            delete merged.magicId;
            delete merged.newRender;
          } else if (target[ROOT]) {
            merged.newRender = true;
          }
          return merged;
        }
        componentToString(cid) {
          const { buffer: str, streams } = this.recursiveCIDToString(
            this.rendered[COMPONENTS],
            cid,
            null
          );
          const [strippedHTML, _before, _after] = modifyRoot(str, {});
          return { buffer: strippedHTML, streams };
        }
        pruneCIDs(cids) {
          cids.forEach((cid) => delete this.rendered[COMPONENTS][cid]);
        }
        // private
        get() {
          return this.rendered;
        }
        isNewFingerprint(diff = {}) {
          return !!diff[STATIC];
        }
        templateStatic(part, templates) {
          if (typeof part === "number") {
            return templates[part];
          } else {
            return part;
          }
        }
        nextMagicID() {
          this.magicId++;
          return `m${this.magicId}-${this.parentViewId()}`;
        }
        // Converts rendered tree to output buffer.
        //
        // changeTracking controls if we can apply the PHX_SKIP optimization.
        toOutputBuffer(rendered, templates, output, changeTracking, rootAttrs = {}) {
          if (rendered[KEYED]) {
            return this.comprehensionToBuffer(
              rendered,
              templates,
              output,
              changeTracking
            );
          }
          if (rendered[TEMPLATES]) {
            templates = rendered[TEMPLATES];
            delete rendered[TEMPLATES];
          }
          let { [STATIC]: statics } = rendered;
          statics = this.templateStatic(statics, templates);
          rendered[STATIC] = statics;
          const isRoot = rendered[ROOT];
          const prevBuffer = output.buffer;
          if (isRoot) {
            output.buffer = "";
          }
          if (changeTracking && isRoot && !rendered.magicId) {
            rendered.newRender = true;
            rendered.magicId = this.nextMagicID();
          }
          output.buffer += statics[0];
          for (let i = 1; i < statics.length; i++) {
            this.dynamicToBuffer(rendered[i - 1], templates, output, changeTracking);
            output.buffer += statics[i];
          }
          if (isRoot) {
            let skip = false;
            let attrs;
            if (changeTracking || rendered.magicId) {
              skip = changeTracking && !rendered.newRender;
              attrs = { [PHX_MAGIC_ID]: rendered.magicId, ...rootAttrs };
            } else {
              attrs = rootAttrs;
            }
            if (skip) {
              attrs[PHX_SKIP] = true;
            }
            const [newRoot, commentBefore, commentAfter] = modifyRoot(
              output.buffer,
              attrs,
              skip
            );
            rendered.newRender = false;
            output.buffer = prevBuffer + commentBefore + newRoot + commentAfter;
          }
        }
        comprehensionToBuffer(rendered, templates, output, changeTracking) {
          const keyedTemplates = templates || rendered[TEMPLATES];
          const statics = this.templateStatic(rendered[STATIC], templates);
          rendered[STATIC] = statics;
          delete rendered[TEMPLATES];
          for (let i = 0; i < rendered[KEYED][KEYED_COUNT]; i++) {
            output.buffer += statics[0];
            for (let j2 = 1; j2 < statics.length; j2++) {
              this.dynamicToBuffer(
                rendered[KEYED][i][j2 - 1],
                keyedTemplates,
                output,
                changeTracking
              );
              output.buffer += statics[j2];
            }
          }
          if (rendered[STREAM]) {
            const stream = rendered[STREAM];
            const [_ref, _inserts, deleteIds, reset] = stream || [null, {}, [], null];
            if (stream !== void 0 && (rendered[KEYED][KEYED_COUNT] > 0 || deleteIds.length > 0 || reset)) {
              delete rendered[STREAM];
              rendered[KEYED] = {
                [KEYED_COUNT]: 0
              };
              output.streams.add(stream);
            }
          }
        }
        dynamicToBuffer(rendered, templates, output, changeTracking) {
          if (typeof rendered === "number") {
            const { buffer: str, streams } = this.recursiveCIDToString(
              output.components,
              rendered,
              output.onlyCids
            );
            output.buffer += str;
            output.streams = /* @__PURE__ */ new Set([...output.streams, ...streams]);
          } else if (isObject(rendered)) {
            this.toOutputBuffer(rendered, templates, output, changeTracking, {});
          } else {
            output.buffer += rendered;
          }
        }
        recursiveCIDToString(components, cid, onlyCids) {
          const component = components[cid] || logError(`no component for CID ${cid}`, components);
          const attrs = { [PHX_COMPONENT]: cid, [PHX_VIEW_REF]: this.viewId };
          const skip = onlyCids && !onlyCids.has(cid);
          component.newRender = !skip;
          component.magicId = `c${cid}-${this.parentViewId()}`;
          const changeTracking = !component.reset;
          const { buffer: html, streams } = this.recursiveToString(
            component,
            components,
            onlyCids,
            changeTracking,
            attrs
          );
          delete component.reset;
          return { buffer: html, streams };
        }
      };
      focusStack = [];
      default_transition_time = 200;
      JS = {
        // private
        exec(e, eventType, phxEvent, view, sourceEl, defaults) {
          const [defaultKind, defaultArgs] = defaults || [
            null,
            { callback: defaults && defaults.callback }
          ];
          const commands = phxEvent.charAt(0) === "[" ? JSON.parse(phxEvent) : [[defaultKind, defaultArgs]];
          commands.forEach(([kind, args]) => {
            if (kind === defaultKind) {
              args = { ...defaultArgs, ...args };
              args.callback = args.callback || defaultArgs.callback;
            }
            this.filterToEls(view.liveSocket, sourceEl, args).forEach((el2) => {
              this[`exec_${kind}`](e, eventType, phxEvent, view, sourceEl, el2, args);
            });
          });
        },
        isVisible(el2) {
          return !!(el2.offsetWidth || el2.offsetHeight || el2.getClientRects().length > 0);
        },
        // returns true if any part of the element is inside the viewport
        isInViewport(el2) {
          const rect = el2.getBoundingClientRect();
          const windowHeight = window.innerHeight || document.documentElement.clientHeight;
          const windowWidth = window.innerWidth || document.documentElement.clientWidth;
          return rect.right > 0 && rect.bottom > 0 && rect.left < windowWidth && rect.top < windowHeight;
        },
        // private
        // commands
        exec_exec(e, eventType, phxEvent, view, sourceEl, el2, { attr, to }) {
          const encodedJS = el2.getAttribute(attr);
          if (!encodedJS) {
            throw new Error(`expected ${attr} to contain JS command on "${to}"`);
          }
          view.liveSocket.execJS(el2, encodedJS, eventType);
        },
        exec_dispatch(e, eventType, phxEvent, view, sourceEl, el2, { event, detail, bubbles, blocking }) {
          detail = detail || {};
          detail.dispatcher = sourceEl;
          if (blocking) {
            const promise = new Promise((resolve, _reject) => {
              detail.done = resolve;
            });
            view.liveSocket.asyncTransition(promise);
          }
          dom_default.dispatchEvent(el2, event, { detail, bubbles });
        },
        exec_push(e, eventType, phxEvent, view, sourceEl, el2, args) {
          const {
            event,
            data,
            target,
            page_loading,
            loading,
            value,
            dispatcher,
            callback
          } = args;
          const pushOpts = {
            loading,
            value,
            target,
            page_loading: !!page_loading,
            originalEvent: e
          };
          const targetSrc = eventType === "change" && dispatcher ? dispatcher : sourceEl;
          const phxTarget = target || targetSrc.getAttribute(view.binding("target")) || targetSrc;
          const handler = (targetView, targetCtx) => {
            if (!targetView.isConnected()) {
              return;
            }
            if (eventType === "change") {
              let { newCid, _target } = args;
              _target = _target || (dom_default.isFormInput(sourceEl) ? sourceEl.name : void 0);
              if (_target) {
                pushOpts._target = _target;
              }
              targetView.pushInput(
                sourceEl,
                targetCtx,
                newCid,
                event || phxEvent,
                pushOpts,
                callback
              );
            } else if (eventType === "submit") {
              const { submitter } = args;
              targetView.submitForm(
                sourceEl,
                targetCtx,
                event || phxEvent,
                submitter,
                pushOpts,
                callback
              );
            } else {
              targetView.pushEvent(
                eventType,
                sourceEl,
                targetCtx,
                event || phxEvent,
                data,
                pushOpts,
                callback
              );
            }
          };
          if (args.targetView && args.targetCtx) {
            handler(args.targetView, args.targetCtx);
          } else {
            view.withinTargets(phxTarget, handler);
          }
        },
        exec_navigate(e, eventType, phxEvent, view, sourceEl, el2, { href, replace }) {
          view.liveSocket.historyRedirect(
            e,
            href,
            replace ? "replace" : "push",
            null,
            sourceEl
          );
        },
        exec_patch(e, eventType, phxEvent, view, sourceEl, el2, { href, replace }) {
          view.liveSocket.pushHistoryPatch(
            e,
            href,
            replace ? "replace" : "push",
            sourceEl
          );
        },
        exec_focus(e, eventType, phxEvent, view, sourceEl, el2) {
          aria_default.attemptFocus(el2);
          window.requestAnimationFrame(() => {
            window.requestAnimationFrame(() => aria_default.attemptFocus(el2));
          });
        },
        exec_focus_first(e, eventType, phxEvent, view, sourceEl, el2) {
          aria_default.focusFirstInteractive(el2) || aria_default.focusFirst(el2);
          window.requestAnimationFrame(() => {
            window.requestAnimationFrame(
              () => aria_default.focusFirstInteractive(el2) || aria_default.focusFirst(el2)
            );
          });
        },
        exec_push_focus(e, eventType, phxEvent, view, sourceEl, el2) {
          focusStack.push(el2 || sourceEl);
        },
        exec_pop_focus(_e3, _eventType, _phxEvent, _view, _sourceEl, _el) {
          const el2 = focusStack.pop();
          if (el2) {
            el2.focus();
            window.requestAnimationFrame(() => {
              window.requestAnimationFrame(() => el2.focus());
            });
          }
        },
        exec_add_class(e, eventType, phxEvent, view, sourceEl, el2, { names, transition, time, blocking }) {
          this.addOrRemoveClasses(el2, names, [], transition, time, view, blocking);
        },
        exec_remove_class(e, eventType, phxEvent, view, sourceEl, el2, { names, transition, time, blocking }) {
          this.addOrRemoveClasses(el2, [], names, transition, time, view, blocking);
        },
        exec_toggle_class(e, eventType, phxEvent, view, sourceEl, el2, { names, transition, time, blocking }) {
          this.toggleClasses(el2, names, transition, time, view, blocking);
        },
        exec_toggle_attr(e, eventType, phxEvent, view, sourceEl, el2, { attr: [attr, val1, val2] }) {
          this.toggleAttr(el2, attr, val1, val2);
        },
        exec_ignore_attrs(e, eventType, phxEvent, view, sourceEl, el2, { attrs }) {
          this.ignoreAttrs(el2, attrs);
        },
        exec_transition(e, eventType, phxEvent, view, sourceEl, el2, { time, transition, blocking }) {
          this.addOrRemoveClasses(el2, [], [], transition, time, view, blocking);
        },
        exec_toggle(e, eventType, phxEvent, view, sourceEl, el2, { display, ins, outs, time, blocking }) {
          this.toggle(eventType, view, el2, display, ins, outs, time, blocking);
        },
        exec_show(e, eventType, phxEvent, view, sourceEl, el2, { display, transition, time, blocking }) {
          this.show(eventType, view, el2, display, transition, time, blocking);
        },
        exec_hide(e, eventType, phxEvent, view, sourceEl, el2, { display, transition, time, blocking }) {
          this.hide(eventType, view, el2, display, transition, time, blocking);
        },
        exec_set_attr(e, eventType, phxEvent, view, sourceEl, el2, { attr: [attr, val] }) {
          this.setOrRemoveAttrs(el2, [[attr, val]], []);
        },
        exec_remove_attr(e, eventType, phxEvent, view, sourceEl, el2, { attr }) {
          this.setOrRemoveAttrs(el2, [], [attr]);
        },
        ignoreAttrs(el2, attrs) {
          dom_default.putPrivate(el2, "JS:ignore_attrs", {
            apply: (fromEl, toEl) => {
              let fromAttributes = Array.from(fromEl.attributes);
              let fromAttributeNames = fromAttributes.map((attr) => attr.name);
              Array.from(toEl.attributes).filter((attr) => {
                return !fromAttributeNames.includes(attr.name);
              }).forEach((attr) => {
                if (dom_default.attributeIgnored(attr, attrs)) {
                  toEl.removeAttribute(attr.name);
                }
              });
              fromAttributes.forEach((attr) => {
                if (dom_default.attributeIgnored(attr, attrs)) {
                  toEl.setAttribute(attr.name, attr.value);
                }
              });
            }
          });
        },
        onBeforeElUpdated(fromEl, toEl) {
          const ignoreAttrs = dom_default.private(fromEl, "JS:ignore_attrs");
          if (ignoreAttrs) {
            ignoreAttrs.apply(fromEl, toEl);
          }
        },
        // utils for commands
        show(eventType, view, el2, display, transition, time, blocking) {
          if (!this.isVisible(el2)) {
            this.toggle(
              eventType,
              view,
              el2,
              display,
              transition,
              null,
              time,
              blocking
            );
          }
        },
        hide(eventType, view, el2, display, transition, time, blocking) {
          if (this.isVisible(el2)) {
            this.toggle(
              eventType,
              view,
              el2,
              display,
              null,
              transition,
              time,
              blocking
            );
          }
        },
        toggle(eventType, view, el2, display, ins, outs, time, blocking) {
          time = time || default_transition_time;
          const [inClasses, inStartClasses, inEndClasses] = ins || [[], [], []];
          const [outClasses, outStartClasses, outEndClasses] = outs || [[], [], []];
          if (inClasses.length > 0 || outClasses.length > 0) {
            if (this.isVisible(el2)) {
              const onStart = () => {
                this.addOrRemoveClasses(
                  el2,
                  outStartClasses,
                  inClasses.concat(inStartClasses).concat(inEndClasses)
                );
                window.requestAnimationFrame(() => {
                  this.addOrRemoveClasses(el2, outClasses, []);
                  window.requestAnimationFrame(
                    () => this.addOrRemoveClasses(el2, outEndClasses, outStartClasses)
                  );
                });
              };
              const onEnd = () => {
                this.addOrRemoveClasses(el2, [], outClasses.concat(outEndClasses));
                dom_default.putSticky(
                  el2,
                  "toggle",
                  (currentEl) => currentEl.style.display = "none"
                );
                el2.dispatchEvent(new Event("phx:hide-end"));
              };
              el2.dispatchEvent(new Event("phx:hide-start"));
              if (blocking === false) {
                onStart();
                setTimeout(onEnd, time);
              } else {
                view.transition(time, onStart, onEnd);
              }
            } else {
              if (eventType === "remove") {
                return;
              }
              const onStart = () => {
                this.addOrRemoveClasses(
                  el2,
                  inStartClasses,
                  outClasses.concat(outStartClasses).concat(outEndClasses)
                );
                const stickyDisplay = display || this.defaultDisplay(el2);
                window.requestAnimationFrame(() => {
                  this.addOrRemoveClasses(el2, inClasses, []);
                  window.requestAnimationFrame(() => {
                    dom_default.putSticky(
                      el2,
                      "toggle",
                      (currentEl) => currentEl.style.display = stickyDisplay
                    );
                    this.addOrRemoveClasses(el2, inEndClasses, inStartClasses);
                  });
                });
              };
              const onEnd = () => {
                this.addOrRemoveClasses(el2, [], inClasses.concat(inEndClasses));
                el2.dispatchEvent(new Event("phx:show-end"));
              };
              el2.dispatchEvent(new Event("phx:show-start"));
              if (blocking === false) {
                onStart();
                setTimeout(onEnd, time);
              } else {
                view.transition(time, onStart, onEnd);
              }
            }
          } else {
            if (this.isVisible(el2)) {
              window.requestAnimationFrame(() => {
                el2.dispatchEvent(new Event("phx:hide-start"));
                dom_default.putSticky(
                  el2,
                  "toggle",
                  (currentEl) => currentEl.style.display = "none"
                );
                el2.dispatchEvent(new Event("phx:hide-end"));
              });
            } else {
              window.requestAnimationFrame(() => {
                el2.dispatchEvent(new Event("phx:show-start"));
                const stickyDisplay = display || this.defaultDisplay(el2);
                dom_default.putSticky(
                  el2,
                  "toggle",
                  (currentEl) => currentEl.style.display = stickyDisplay
                );
                el2.dispatchEvent(new Event("phx:show-end"));
              });
            }
          }
        },
        toggleClasses(el2, classes, transition, time, view, blocking) {
          window.requestAnimationFrame(() => {
            const [prevAdds, prevRemoves] = dom_default.getSticky(el2, "classes", [[], []]);
            const newAdds = classes.filter(
              (name) => prevAdds.indexOf(name) < 0 && !el2.classList.contains(name)
            );
            const newRemoves = classes.filter(
              (name) => prevRemoves.indexOf(name) < 0 && el2.classList.contains(name)
            );
            this.addOrRemoveClasses(
              el2,
              newAdds,
              newRemoves,
              transition,
              time,
              view,
              blocking
            );
          });
        },
        toggleAttr(el2, attr, val1, val2) {
          if (el2.hasAttribute(attr)) {
            if (val2 !== void 0) {
              if (el2.getAttribute(attr) === val1) {
                this.setOrRemoveAttrs(el2, [[attr, val2]], []);
              } else {
                this.setOrRemoveAttrs(el2, [[attr, val1]], []);
              }
            } else {
              this.setOrRemoveAttrs(el2, [], [attr]);
            }
          } else {
            this.setOrRemoveAttrs(el2, [[attr, val1]], []);
          }
        },
        addOrRemoveClasses(el2, adds, removes, transition, time, view, blocking) {
          time = time || default_transition_time;
          const [transitionRun, transitionStart, transitionEnd] = transition || [
            [],
            [],
            []
          ];
          if (transitionRun.length > 0) {
            const onStart = () => {
              this.addOrRemoveClasses(
                el2,
                transitionStart,
                [].concat(transitionRun).concat(transitionEnd)
              );
              window.requestAnimationFrame(() => {
                this.addOrRemoveClasses(el2, transitionRun, []);
                window.requestAnimationFrame(
                  () => this.addOrRemoveClasses(el2, transitionEnd, transitionStart)
                );
              });
            };
            const onDone = () => this.addOrRemoveClasses(
              el2,
              adds.concat(transitionEnd),
              removes.concat(transitionRun).concat(transitionStart)
            );
            if (blocking === false) {
              onStart();
              setTimeout(onDone, time);
            } else {
              view.transition(time, onStart, onDone);
            }
            return;
          }
          window.requestAnimationFrame(() => {
            const [prevAdds, prevRemoves] = dom_default.getSticky(el2, "classes", [[], []]);
            const keepAdds = adds.filter(
              (name) => prevAdds.indexOf(name) < 0 && !el2.classList.contains(name)
            );
            const keepRemoves = removes.filter(
              (name) => prevRemoves.indexOf(name) < 0 && el2.classList.contains(name)
            );
            const newAdds = prevAdds.filter((name) => removes.indexOf(name) < 0).concat(keepAdds);
            const newRemoves = prevRemoves.filter((name) => adds.indexOf(name) < 0).concat(keepRemoves);
            dom_default.putSticky(el2, "classes", (currentEl) => {
              currentEl.classList.remove(...newRemoves);
              currentEl.classList.add(...newAdds);
              return [newAdds, newRemoves];
            });
          });
        },
        setOrRemoveAttrs(el2, sets, removes) {
          const [prevSets, prevRemoves] = dom_default.getSticky(el2, "attrs", [[], []]);
          const alteredAttrs = sets.map(([attr, _val]) => attr).concat(removes);
          const newSets = prevSets.filter(([attr, _val]) => !alteredAttrs.includes(attr)).concat(sets);
          const newRemoves = prevRemoves.filter((attr) => !alteredAttrs.includes(attr)).concat(removes);
          dom_default.putSticky(el2, "attrs", (currentEl) => {
            newRemoves.forEach((attr) => currentEl.removeAttribute(attr));
            newSets.forEach(([attr, val]) => currentEl.setAttribute(attr, val));
            return [newSets, newRemoves];
          });
        },
        hasAllClasses(el2, classes) {
          return classes.every((name) => el2.classList.contains(name));
        },
        isToggledOut(el2, outClasses) {
          return !this.isVisible(el2) || this.hasAllClasses(el2, outClasses);
        },
        filterToEls(liveSocket, sourceEl, { to }) {
          const defaultQuery = () => {
            if (typeof to === "string") {
              return document.querySelectorAll(to);
            } else if (to.closest) {
              const toEl = sourceEl.closest(to.closest);
              return toEl ? [toEl] : [];
            } else if (to.inner) {
              return sourceEl.querySelectorAll(to.inner);
            }
          };
          return to ? liveSocket.jsQuerySelectorAll(sourceEl, to, defaultQuery) : [sourceEl];
        },
        defaultDisplay(el2) {
          return { tr: "table-row", td: "table-cell" }[el2.tagName.toLowerCase()] || "block";
        },
        transitionClasses(val) {
          if (!val) {
            return null;
          }
          let [trans, tStart, tEnd] = Array.isArray(val) ? val : [val.split(" "), [], []];
          trans = Array.isArray(trans) ? trans : trans.split(" ");
          tStart = Array.isArray(tStart) ? tStart : tStart.split(" ");
          tEnd = Array.isArray(tEnd) ? tEnd : tEnd.split(" ");
          return [trans, tStart, tEnd];
        }
      };
      js_default = JS;
      js_commands_default = (liveSocket, eventType) => {
        return {
          exec(el2, encodedJS) {
            liveSocket.execJS(el2, encodedJS, eventType);
          },
          show(el2, opts = {}) {
            const owner = liveSocket.owner(el2);
            js_default.show(
              eventType,
              owner,
              el2,
              opts.display,
              js_default.transitionClasses(opts.transition),
              opts.time,
              opts.blocking
            );
          },
          hide(el2, opts = {}) {
            const owner = liveSocket.owner(el2);
            js_default.hide(
              eventType,
              owner,
              el2,
              null,
              js_default.transitionClasses(opts.transition),
              opts.time,
              opts.blocking
            );
          },
          toggle(el2, opts = {}) {
            const owner = liveSocket.owner(el2);
            const inTransition = js_default.transitionClasses(opts.in);
            const outTransition = js_default.transitionClasses(opts.out);
            js_default.toggle(
              eventType,
              owner,
              el2,
              opts.display,
              inTransition,
              outTransition,
              opts.time,
              opts.blocking
            );
          },
          addClass(el2, names, opts = {}) {
            const classNames = Array.isArray(names) ? names : names.split(" ");
            const owner = liveSocket.owner(el2);
            js_default.addOrRemoveClasses(
              el2,
              classNames,
              [],
              js_default.transitionClasses(opts.transition),
              opts.time,
              owner,
              opts.blocking
            );
          },
          removeClass(el2, names, opts = {}) {
            const classNames = Array.isArray(names) ? names : names.split(" ");
            const owner = liveSocket.owner(el2);
            js_default.addOrRemoveClasses(
              el2,
              [],
              classNames,
              js_default.transitionClasses(opts.transition),
              opts.time,
              owner,
              opts.blocking
            );
          },
          toggleClass(el2, names, opts = {}) {
            const classNames = Array.isArray(names) ? names : names.split(" ");
            const owner = liveSocket.owner(el2);
            js_default.toggleClasses(
              el2,
              classNames,
              js_default.transitionClasses(opts.transition),
              opts.time,
              owner,
              opts.blocking
            );
          },
          transition(el2, transition, opts = {}) {
            const owner = liveSocket.owner(el2);
            js_default.addOrRemoveClasses(
              el2,
              [],
              [],
              js_default.transitionClasses(transition),
              opts.time,
              owner,
              opts.blocking
            );
          },
          setAttribute(el2, attr, val) {
            js_default.setOrRemoveAttrs(el2, [[attr, val]], []);
          },
          removeAttribute(el2, attr) {
            js_default.setOrRemoveAttrs(el2, [], [attr]);
          },
          toggleAttribute(el2, attr, val1, val2) {
            js_default.toggleAttr(el2, attr, val1, val2);
          },
          push(el2, type, opts = {}) {
            liveSocket.withinOwners(el2, (view) => {
              const data = opts.value || {};
              delete opts.value;
              let e = new CustomEvent("phx:exec", { detail: { sourceElement: el2 } });
              js_default.exec(e, eventType, type, view, el2, ["push", { data, ...opts }]);
            });
          },
          navigate(href, opts = {}) {
            const customEvent = new CustomEvent("phx:exec");
            liveSocket.historyRedirect(
              customEvent,
              href,
              opts.replace ? "replace" : "push",
              null,
              null
            );
          },
          patch(href, opts = {}) {
            const customEvent = new CustomEvent("phx:exec");
            liveSocket.pushHistoryPatch(
              customEvent,
              href,
              opts.replace ? "replace" : "push",
              null
            );
          },
          ignoreAttributes(el2, attrs) {
            js_default.ignoreAttrs(el2, Array.isArray(attrs) ? attrs : [attrs]);
          }
        };
      };
      HOOK_ID = "hookId";
      viewHookID = 1;
      ViewHook = class _ViewHook {
        get liveSocket() {
          return this.__liveSocket();
        }
        static makeID() {
          return viewHookID++;
        }
        static elementID(el2) {
          return dom_default.private(el2, HOOK_ID);
        }
        constructor(view, el2, callbacks) {
          this.el = el2;
          this.__attachView(view);
          this.__listeners = /* @__PURE__ */ new Set();
          this.__isDisconnected = false;
          dom_default.putPrivate(this.el, HOOK_ID, _ViewHook.makeID());
          if (callbacks) {
            const protectedProps = /* @__PURE__ */ new Set([
              "el",
              "liveSocket",
              "__view",
              "__listeners",
              "__isDisconnected",
              "constructor",
              // Standard object properties
              // Core ViewHook API methods
              "js",
              "pushEvent",
              "pushEventTo",
              "handleEvent",
              "removeHandleEvent",
              "upload",
              "uploadTo",
              // Internal lifecycle callers
              "__mounted",
              "__updated",
              "__beforeUpdate",
              "__destroyed",
              "__reconnected",
              "__disconnected",
              "__cleanup__"
            ]);
            for (const key in callbacks) {
              if (Object.prototype.hasOwnProperty.call(callbacks, key)) {
                this[key] = callbacks[key];
                if (protectedProps.has(key)) {
                  console.warn(
                    `Hook object for element #${el2.id} overwrites core property '${key}'!`
                  );
                }
              }
            }
            const lifecycleMethods = [
              "mounted",
              "beforeUpdate",
              "updated",
              "destroyed",
              "disconnected",
              "reconnected"
            ];
            lifecycleMethods.forEach((methodName) => {
              if (callbacks[methodName] && typeof callbacks[methodName] === "function") {
                this[methodName] = callbacks[methodName];
              }
            });
          }
        }
        /** @internal */
        __attachView(view) {
          if (view) {
            this.__view = () => view;
            this.__liveSocket = () => view.liveSocket;
          } else {
            this.__view = () => {
              throw new Error(
                `hook not yet attached to a live view: ${this.el.outerHTML}`
              );
            };
            this.__liveSocket = () => {
              throw new Error(
                `hook not yet attached to a live view: ${this.el.outerHTML}`
              );
            };
          }
        }
        // Default lifecycle methods
        mounted() {
        }
        beforeUpdate() {
        }
        updated() {
        }
        destroyed() {
        }
        disconnected() {
        }
        reconnected() {
        }
        // Internal lifecycle callers - called by the View
        /** @internal */
        __mounted() {
          this.mounted();
        }
        /** @internal */
        __updated() {
          this.updated();
        }
        /** @internal */
        __beforeUpdate() {
          this.beforeUpdate();
        }
        /** @internal */
        __destroyed() {
          this.destroyed();
          dom_default.deletePrivate(this.el, HOOK_ID);
        }
        /** @internal */
        __reconnected() {
          if (this.__isDisconnected) {
            this.__isDisconnected = false;
            this.reconnected();
          }
        }
        /** @internal */
        __disconnected() {
          this.__isDisconnected = true;
          this.disconnected();
        }
        js() {
          return {
            ...js_commands_default(this.__view().liveSocket, "hook"),
            exec: (encodedJS) => {
              this.__view().liveSocket.execJS(this.el, encodedJS, "hook");
            }
          };
        }
        pushEvent(event, payload, onReply) {
          const promise = this.__view().pushHookEvent(
            this.el,
            null,
            event,
            payload || {}
          );
          if (onReply === void 0) {
            return promise.then(({ reply }) => reply);
          }
          promise.then(
            ({ reply, ref }) => onReply(reply, ref)
          ).catch(() => {
          });
        }
        pushEventTo(selectorOrTarget, event, payload, onReply) {
          if (onReply === void 0) {
            const targetPair = [];
            this.__view().withinTargets(
              selectorOrTarget,
              (view, targetCtx) => {
                targetPair.push({ view, targetCtx });
              }
            );
            const promises = targetPair.map(({ view, targetCtx }) => {
              return view.pushHookEvent(this.el, targetCtx, event, payload || {});
            });
            return Promise.allSettled(promises);
          }
          this.__view().withinTargets(
            selectorOrTarget,
            (view, targetCtx) => {
              view.pushHookEvent(this.el, targetCtx, event, payload || {}).then(
                ({ reply, ref }) => onReply(reply, ref)
              ).catch(() => {
              });
            }
          );
        }
        handleEvent(event, callback) {
          const callbackRef = {
            event,
            callback: (customEvent) => callback(customEvent.detail)
          };
          window.addEventListener(
            `phx:${event}`,
            callbackRef.callback
          );
          this.__listeners.add(callbackRef);
          return callbackRef;
        }
        removeHandleEvent(ref) {
          window.removeEventListener(
            `phx:${ref.event}`,
            ref.callback
          );
          this.__listeners.delete(ref);
        }
        upload(name, files) {
          return this.__view().dispatchUploads(null, name, files);
        }
        uploadTo(selectorOrTarget, name, files) {
          return this.__view().withinTargets(
            selectorOrTarget,
            (view, targetCtx) => {
              view.dispatchUploads(targetCtx, name, files);
            }
          );
        }
        /** @internal */
        __cleanup__() {
          this.__listeners.forEach(
            (callbackRef) => this.removeHandleEvent(callbackRef)
          );
        }
      };
      prependFormDataKey = (key, prefix) => {
        const isArray = key.endsWith("[]");
        let baseKey = isArray ? key.slice(0, -2) : key;
        baseKey = baseKey.replace(/([^\[\]]+)(\]?$)/, `${prefix}$1$2`);
        if (isArray) {
          baseKey += "[]";
        }
        return baseKey;
      };
      serializeForm = (form, opts, onlyNames = []) => {
        const { submitter } = opts;
        let injectedElement;
        if (submitter && submitter.name) {
          const input = document.createElement("input");
          input.type = "hidden";
          const formId = submitter.getAttribute("form");
          if (formId) {
            input.setAttribute("form", formId);
          }
          input.name = submitter.name;
          input.value = submitter.value;
          submitter.parentElement.insertBefore(input, submitter);
          injectedElement = input;
        }
        const formData = new FormData(form);
        const toRemove = [];
        formData.forEach((val, key, _index) => {
          if (val instanceof File) {
            toRemove.push(key);
          }
        });
        toRemove.forEach((key) => formData.delete(key));
        const params = new URLSearchParams();
        const { inputsUnused, onlyHiddenInputs } = Array.from(form.elements).reduce(
          (acc, input) => {
            const { inputsUnused: inputsUnused2, onlyHiddenInputs: onlyHiddenInputs2 } = acc;
            const key = input.name;
            if (!key) {
              return acc;
            }
            if (inputsUnused2[key] === void 0) {
              inputsUnused2[key] = true;
            }
            if (onlyHiddenInputs2[key] === void 0) {
              onlyHiddenInputs2[key] = true;
            }
            const isUsed = dom_default.private(input, PHX_HAS_FOCUSED) || dom_default.private(input, PHX_HAS_SUBMITTED);
            const isHidden = input.type === "hidden";
            inputsUnused2[key] = inputsUnused2[key] && !isUsed;
            onlyHiddenInputs2[key] = onlyHiddenInputs2[key] && isHidden;
            return acc;
          },
          { inputsUnused: {}, onlyHiddenInputs: {} }
        );
        for (const [key, val] of formData.entries()) {
          if (onlyNames.length === 0 || onlyNames.indexOf(key) >= 0) {
            const isUnused = inputsUnused[key];
            const hidden = onlyHiddenInputs[key];
            if (isUnused && !(submitter && submitter.name == key) && !hidden) {
              params.append(prependFormDataKey(key, "_unused_"), "");
            }
            if (typeof val === "string") {
              params.append(key, val);
            }
          }
        }
        if (submitter && injectedElement) {
          submitter.parentElement.removeChild(injectedElement);
        }
        return params.toString();
      };
      View = class _View {
        static closestView(el2) {
          const liveViewEl = el2.closest(PHX_VIEW_SELECTOR);
          return liveViewEl ? dom_default.private(liveViewEl, "view") : null;
        }
        constructor(el2, liveSocket, parentView, flash, liveReferer) {
          this.isDead = false;
          this.liveSocket = liveSocket;
          this.flash = flash;
          this.parent = parentView;
          this.root = parentView ? parentView.root : this;
          this.el = el2;
          const boundView = dom_default.private(this.el, "view");
          if (boundView !== void 0 && boundView.isDead !== true) {
            logError(
              `The DOM element for this view has already been bound to a view.

        An element can only ever be associated with a single view!
        Please ensure that you are not trying to initialize multiple LiveSockets on the same page.
        This could happen if you're accidentally trying to render your root layout more than once.
        Ensure that the template set on the LiveView is different than the root layout.
      `,
              { view: boundView }
            );
            throw new Error("Cannot bind multiple views to the same DOM element.");
          }
          dom_default.putPrivate(this.el, "view", this);
          this.id = this.el.id;
          this.ref = 0;
          this.lastAckRef = null;
          this.childJoins = 0;
          this.loaderTimer = null;
          this.disconnectedTimer = null;
          this.pendingDiffs = [];
          this.pendingForms = /* @__PURE__ */ new Set();
          this.redirect = false;
          this.href = null;
          this.joinCount = this.parent ? this.parent.joinCount - 1 : 0;
          this.joinAttempts = 0;
          this.joinPending = true;
          this.destroyed = false;
          this.joinCallback = function(onDone) {
            onDone && onDone();
          };
          this.stopCallback = function() {
          };
          this.pendingJoinOps = [];
          this.viewHooks = {};
          this.formSubmits = [];
          this.children = this.parent ? null : {};
          this.root.children[this.id] = {};
          this.formsForRecovery = {};
          this.channel = this.liveSocket.channel(`lv:${this.id}`, () => {
            const url = this.href && this.expandURL(this.href);
            return {
              redirect: this.redirect ? url : void 0,
              url: this.redirect ? void 0 : url || void 0,
              params: this.connectParams(liveReferer),
              session: this.getSession(),
              static: this.getStatic(),
              flash: this.flash,
              sticky: this.el.hasAttribute(PHX_STICKY)
            };
          });
          this.portalElementIds = /* @__PURE__ */ new Set();
        }
        setHref(href) {
          this.href = href;
        }
        setRedirect(href) {
          this.redirect = true;
          this.href = href;
        }
        isMain() {
          return this.el.hasAttribute(PHX_MAIN);
        }
        connectParams(liveReferer) {
          const params = this.liveSocket.params(this.el);
          const manifest = dom_default.all(document, `[${this.binding(PHX_TRACK_STATIC)}]`).map((node) => node.src || node.href).filter((url) => typeof url === "string");
          if (manifest.length > 0) {
            params["_track_static"] = manifest;
          }
          params["_mounts"] = this.joinCount;
          params["_mount_attempts"] = this.joinAttempts;
          params["_live_referer"] = liveReferer;
          this.joinAttempts++;
          return params;
        }
        isConnected() {
          return this.channel.canPush();
        }
        getSession() {
          return this.el.getAttribute(PHX_SESSION);
        }
        getStatic() {
          const val = this.el.getAttribute(PHX_STATIC);
          return val === "" ? null : val;
        }
        destroy(callback = function() {
        }) {
          this.destroyAllChildren();
          this.destroyPortalElements();
          this.destroyed = true;
          dom_default.deletePrivate(this.el, "view");
          delete this.root.children[this.id];
          if (this.parent) {
            delete this.root.children[this.parent.id][this.id];
          }
          clearTimeout(this.loaderTimer);
          const onFinished = () => {
            callback();
            for (const id in this.viewHooks) {
              this.destroyHook(this.viewHooks[id]);
            }
          };
          dom_default.markPhxChildDestroyed(this.el);
          this.log("destroyed", () => ["the child has been removed from the parent"]);
          this.channel.leave().receive("ok", onFinished).receive("error", onFinished).receive("timeout", onFinished);
        }
        setContainerClasses(...classes) {
          this.el.classList.remove(
            PHX_CONNECTED_CLASS,
            PHX_LOADING_CLASS,
            PHX_ERROR_CLASS,
            PHX_CLIENT_ERROR_CLASS,
            PHX_SERVER_ERROR_CLASS
          );
          this.el.classList.add(...classes);
        }
        showLoader(timeout) {
          clearTimeout(this.loaderTimer);
          if (timeout) {
            this.loaderTimer = setTimeout(() => this.showLoader(), timeout);
          } else {
            for (const id in this.viewHooks) {
              this.viewHooks[id].__disconnected();
            }
            this.setContainerClasses(PHX_LOADING_CLASS);
          }
        }
        execAll(binding) {
          dom_default.all(
            this.el,
            `[${binding}]`,
            (el2) => this.liveSocket.execJS(el2, el2.getAttribute(binding))
          );
        }
        hideLoader() {
          clearTimeout(this.loaderTimer);
          clearTimeout(this.disconnectedTimer);
          this.setContainerClasses(PHX_CONNECTED_CLASS);
          this.execAll(this.binding("connected"));
        }
        triggerReconnected() {
          for (const id in this.viewHooks) {
            this.viewHooks[id].__reconnected();
          }
        }
        log(kind, msgCallback) {
          this.liveSocket.log(this, kind, msgCallback);
        }
        transition(time, onStart, onDone = function() {
        }) {
          this.liveSocket.transition(time, onStart, onDone);
        }
        // calls the callback with the view and target element for the given phxTarget
        // targets can be:
        //  * an element itself, then it is simply passed to liveSocket.owner;
        //  * a CID (Component ID), then we first search the component's element in the DOM
        //  * a selector, then we search the selector in the DOM and call the callback
        //    for each element found with the corresponding owner view
        withinTargets(phxTarget, callback, dom = document) {
          if (phxTarget instanceof HTMLElement || phxTarget instanceof SVGElement) {
            return this.liveSocket.owner(
              phxTarget,
              (view) => callback(view, phxTarget)
            );
          }
          if (isCid(phxTarget)) {
            const targets = dom_default.findComponentNodeList(this.id, phxTarget, dom);
            if (targets.length === 0) {
              logError(`no component found matching phx-target of ${phxTarget}`);
            } else {
              callback(this, parseInt(phxTarget));
            }
          } else {
            const targets = Array.from(dom.querySelectorAll(phxTarget));
            if (targets.length === 0) {
              logError(
                `nothing found matching the phx-target selector "${phxTarget}"`
              );
            }
            targets.forEach(
              (target) => this.liveSocket.owner(target, (view) => callback(view, target))
            );
          }
        }
        applyDiff(type, rawDiff, callback) {
          this.log(type, () => ["", clone(rawDiff)]);
          const { diff, reply, events, title } = Rendered.extract(rawDiff);
          const ev = events.reduce(
            (acc, args) => {
              if (args.length === 3 && args[2] == true) {
                acc.pre.push(args.slice(0, -1));
              } else {
                acc.post.push(args);
              }
              return acc;
            },
            { pre: [], post: [] }
          );
          this.liveSocket.dispatchEvents(ev.pre);
          const update = () => {
            callback({ diff, reply, events: ev.post });
            if (typeof title === "string" || type == "mount" && this.isMain()) {
              window.requestAnimationFrame(() => dom_default.putTitle(title));
            }
          };
          if ("onDocumentPatch" in this.liveSocket.domCallbacks) {
            this.liveSocket.triggerDOM("onDocumentPatch", [update]);
          } else {
            update();
          }
        }
        onJoin(resp) {
          const { rendered, container, liveview_version, pid } = resp;
          if (container) {
            const [tag, attrs] = container;
            this.el = dom_default.replaceRootContainer(this.el, tag, attrs);
          }
          this.childJoins = 0;
          this.joinPending = true;
          this.flash = null;
          if (this.root === this) {
            this.formsForRecovery = this.getFormsForRecovery();
          }
          if (this.isMain() && window.history.state === null) {
            browser_default.pushState("replace", {
              type: "patch",
              id: this.id,
              position: this.liveSocket.currentHistoryPosition
            });
          }
          if (liveview_version !== this.liveSocket.version()) {
            console.warn(
              `LiveView asset version mismatch. JavaScript version ${this.liveSocket.version()} vs. server ${liveview_version}. To avoid issues, please ensure that your assets use the same version as the server.`
            );
          }
          if (pid) {
            this.el.setAttribute(PHX_LV_PID, pid);
          }
          browser_default.dropLocal(
            this.liveSocket.localStorage,
            window.location.pathname,
            CONSECUTIVE_RELOADS
          );
          this.applyDiff("mount", rendered, ({ diff, events }) => {
            this.rendered = new Rendered(this.id, diff);
            const [html, streams] = this.renderContainer(null, "join");
            this.dropPendingRefs();
            this.joinCount++;
            this.joinAttempts = 0;
            this.maybeRecoverForms(html, () => {
              this.onJoinComplete(resp, html, streams, events);
            });
          });
        }
        dropPendingRefs() {
          dom_default.all(document, `[${PHX_REF_SRC}="${this.refSrc()}"]`, (el2) => {
            el2.removeAttribute(PHX_REF_LOADING);
            el2.removeAttribute(PHX_REF_SRC);
            el2.removeAttribute(PHX_REF_LOCK);
          });
        }
        onJoinComplete({ live_patch }, html, streams, events) {
          if (this.joinCount > 1 || this.parent && !this.parent.isJoinPending()) {
            return this.applyJoinPatch(live_patch, html, streams, events);
          }
          const newChildren = dom_default.findPhxChildrenInFragment(html, this.id).filter(
            (toEl) => {
              const fromEl = toEl.id && this.el.querySelector(`[id="${toEl.id}"]`);
              const phxStatic = fromEl && fromEl.getAttribute(PHX_STATIC);
              if (phxStatic) {
                toEl.setAttribute(PHX_STATIC, phxStatic);
              }
              if (fromEl) {
                fromEl.setAttribute(PHX_ROOT_ID, this.root.id);
              }
              return this.joinChild(toEl);
            }
          );
          if (newChildren.length === 0) {
            if (this.parent) {
              this.root.pendingJoinOps.push([
                this,
                () => this.applyJoinPatch(live_patch, html, streams, events)
              ]);
              this.parent.ackJoin(this);
            } else {
              this.onAllChildJoinsComplete();
              this.applyJoinPatch(live_patch, html, streams, events);
            }
          } else {
            this.root.pendingJoinOps.push([
              this,
              () => this.applyJoinPatch(live_patch, html, streams, events)
            ]);
          }
        }
        attachTrueDocEl() {
          this.el = dom_default.byId(this.id);
          this.el.setAttribute(PHX_ROOT_ID, this.root.id);
        }
        // this is invoked for dead and live views, so we must filter by
        // by owner to ensure we aren't duplicating hooks across disconnect
        // and connected states. This also handles cases where hooks exist
        // in a root layout with a LV in the body
        execNewMounted(parent = document) {
          let phxViewportTop = this.binding(PHX_VIEWPORT_TOP);
          let phxViewportBottom = this.binding(PHX_VIEWPORT_BOTTOM);
          this.all(
            parent,
            `[${phxViewportTop}], [${phxViewportBottom}]`,
            (hookEl) => {
              dom_default.maintainPrivateHooks(
                hookEl,
                hookEl,
                phxViewportTop,
                phxViewportBottom
              );
              this.maybeAddNewHook(hookEl);
            }
          );
          this.all(
            parent,
            `[${this.binding(PHX_HOOK)}], [data-phx-${PHX_HOOK}]`,
            (hookEl) => {
              this.maybeAddNewHook(hookEl);
            }
          );
          this.all(parent, `[${this.binding(PHX_MOUNTED)}]`, (el2) => {
            this.maybeMounted(el2);
          });
        }
        all(parent, selector, callback) {
          dom_default.all(parent, selector, (el2) => {
            if (this.ownsElement(el2)) {
              callback(el2);
            }
          });
        }
        applyJoinPatch(live_patch, html, streams, events) {
          if (this.joinCount > 1) {
            if (this.pendingJoinOps.length) {
              this.pendingJoinOps.forEach((cb) => typeof cb === "function" && cb());
              this.pendingJoinOps = [];
            }
          }
          this.attachTrueDocEl();
          const patch = new DOMPatch(this, this.el, this.id, html, streams, null);
          patch.markPrunableContentForRemoval();
          this.performPatch(patch, false, true);
          this.joinNewChildren();
          this.execNewMounted();
          this.joinPending = false;
          this.liveSocket.dispatchEvents(events);
          this.applyPendingUpdates();
          if (live_patch) {
            const { kind, to } = live_patch;
            this.liveSocket.historyPatch(to, kind);
          }
          this.hideLoader();
          if (this.joinCount > 1) {
            this.triggerReconnected();
          }
          this.stopCallback();
        }
        triggerBeforeUpdateHook(fromEl, toEl) {
          this.liveSocket.triggerDOM("onBeforeElUpdated", [fromEl, toEl]);
          const hook = this.getHook(fromEl);
          const isIgnored = hook && dom_default.isIgnored(fromEl, this.binding(PHX_UPDATE));
          if (hook && !fromEl.isEqualNode(toEl) && !(isIgnored && isEqualObj(fromEl.dataset, toEl.dataset))) {
            hook.__beforeUpdate();
            return hook;
          }
        }
        maybeMounted(el2) {
          const phxMounted = el2.getAttribute(this.binding(PHX_MOUNTED));
          const hasBeenInvoked = phxMounted && dom_default.private(el2, "mounted");
          if (phxMounted && !hasBeenInvoked) {
            this.liveSocket.execJS(el2, phxMounted);
            dom_default.putPrivate(el2, "mounted", true);
          }
        }
        maybeAddNewHook(el2) {
          const newHook = this.addHook(el2);
          if (newHook) {
            newHook.__mounted();
          }
        }
        performPatch(patch, pruneCids, isJoinPatch = false) {
          const removedEls = [];
          let phxChildrenAdded = false;
          const updatedHookIds = /* @__PURE__ */ new Set();
          this.liveSocket.triggerDOM("onPatchStart", [patch.targetContainer]);
          patch.after("added", (el2) => {
            this.liveSocket.triggerDOM("onNodeAdded", [el2]);
            const phxViewportTop = this.binding(PHX_VIEWPORT_TOP);
            const phxViewportBottom = this.binding(PHX_VIEWPORT_BOTTOM);
            dom_default.maintainPrivateHooks(el2, el2, phxViewportTop, phxViewportBottom);
            this.maybeAddNewHook(el2);
            if (el2.getAttribute) {
              this.maybeMounted(el2);
            }
          });
          patch.after("phxChildAdded", (el2) => {
            if (dom_default.isPhxSticky(el2)) {
              this.liveSocket.joinRootViews();
            } else {
              phxChildrenAdded = true;
            }
          });
          patch.before("updated", (fromEl, toEl) => {
            const hook = this.triggerBeforeUpdateHook(fromEl, toEl);
            if (hook) {
              updatedHookIds.add(fromEl.id);
            }
            js_default.onBeforeElUpdated(fromEl, toEl);
          });
          patch.after("updated", (el2) => {
            if (updatedHookIds.has(el2.id)) {
              this.getHook(el2).__updated();
            }
          });
          patch.after("discarded", (el2) => {
            if (el2.nodeType === Node.ELEMENT_NODE) {
              removedEls.push(el2);
            }
          });
          patch.after(
            "transitionsDiscarded",
            (els) => this.afterElementsRemoved(els, pruneCids)
          );
          patch.perform(isJoinPatch);
          this.afterElementsRemoved(removedEls, pruneCids);
          this.liveSocket.triggerDOM("onPatchEnd", [patch.targetContainer]);
          return phxChildrenAdded;
        }
        afterElementsRemoved(elements, pruneCids) {
          const destroyedCIDs = [];
          elements.forEach((parent) => {
            const components = dom_default.all(
              parent,
              `[${PHX_VIEW_REF}="${this.id}"][${PHX_COMPONENT}]`
            );
            const hooks = dom_default.all(
              parent,
              `[${this.binding(PHX_HOOK)}], [data-phx-hook]`
            );
            components.concat(parent).forEach((el2) => {
              const cid = this.componentID(el2);
              if (isCid(cid) && destroyedCIDs.indexOf(cid) === -1 && el2.getAttribute(PHX_VIEW_REF) === this.id) {
                destroyedCIDs.push(cid);
              }
            });
            hooks.concat(parent).forEach((hookEl) => {
              const hook = this.getHook(hookEl);
              hook && this.destroyHook(hook);
            });
          });
          if (pruneCids) {
            this.maybePushComponentsDestroyed(destroyedCIDs);
          }
        }
        joinNewChildren() {
          dom_default.findPhxChildren(document, this.id).forEach((el2) => this.joinChild(el2));
        }
        maybeRecoverForms(html, callback) {
          const phxChange = this.binding("change");
          const oldForms = this.root.formsForRecovery;
          const template = document.createElement("template");
          template.innerHTML = html;
          dom_default.all(template.content, `[${PHX_PORTAL}]`).forEach((portalTemplate) => {
            template.content.firstElementChild.appendChild(
              portalTemplate.content.firstElementChild
            );
          });
          const rootEl = template.content.firstElementChild;
          rootEl.id = this.id;
          rootEl.setAttribute(PHX_ROOT_ID, this.root.id);
          rootEl.setAttribute(PHX_SESSION, this.getSession());
          rootEl.setAttribute(PHX_STATIC, this.getStatic());
          rootEl.setAttribute(PHX_PARENT_ID, this.parent ? this.parent.id : null);
          const formsToRecover = (
            // we go over all forms in the new DOM; because this is only the HTML for the current
            // view, we can be sure that all forms are owned by this view:
            dom_default.all(template.content, "form").filter((newForm) => newForm.id && oldForms[newForm.id]).filter((newForm) => !this.pendingForms.has(newForm.id)).filter(
              (newForm) => oldForms[newForm.id].getAttribute(phxChange) === newForm.getAttribute(phxChange)
            ).map((newForm) => {
              return [oldForms[newForm.id], newForm];
            })
          );
          if (formsToRecover.length === 0) {
            return callback();
          }
          formsToRecover.forEach(([oldForm, newForm], i) => {
            this.pendingForms.add(newForm.id);
            this.pushFormRecovery(
              oldForm,
              newForm,
              template.content.firstElementChild,
              () => {
                this.pendingForms.delete(newForm.id);
                if (i === formsToRecover.length - 1) {
                  callback();
                }
              }
            );
          });
        }
        getChildById(id) {
          return this.root.children[this.id][id];
        }
        getDescendentByEl(el2) {
          if (el2.id === this.id) {
            return this;
          } else {
            return this.children[el2.getAttribute(PHX_PARENT_ID)]?.[el2.id];
          }
        }
        destroyDescendent(id) {
          for (const parentId in this.root.children) {
            for (const childId in this.root.children[parentId]) {
              if (childId === id) {
                return this.root.children[parentId][childId].destroy();
              }
            }
          }
        }
        joinChild(el2) {
          const child = this.getChildById(el2.id);
          if (!child) {
            const view = new _View(el2, this.liveSocket, this);
            this.root.children[this.id][view.id] = view;
            view.join();
            this.childJoins++;
            return true;
          }
        }
        isJoinPending() {
          return this.joinPending;
        }
        ackJoin(_child) {
          this.childJoins--;
          if (this.childJoins === 0) {
            if (this.parent) {
              this.parent.ackJoin(this);
            } else {
              this.onAllChildJoinsComplete();
            }
          }
        }
        onAllChildJoinsComplete() {
          this.pendingForms.clear();
          this.formsForRecovery = {};
          this.joinCallback(() => {
            this.pendingJoinOps.forEach(([view, op]) => {
              if (!view.isDestroyed()) {
                op();
              }
            });
            this.pendingJoinOps = [];
          });
        }
        update(diff, events, isPending = false) {
          if (this.isJoinPending() || this.liveSocket.hasPendingLink() && this.root.isMain()) {
            if (!isPending) {
              this.pendingDiffs.push({ diff, events });
            }
            return false;
          }
          this.rendered.mergeDiff(diff);
          let phxChildrenAdded = false;
          if (this.rendered.isComponentOnlyDiff(diff)) {
            this.liveSocket.time("component patch complete", () => {
              const parentCids = dom_default.findExistingParentCIDs(
                this.id,
                this.rendered.componentCIDs(diff)
              );
              parentCids.forEach((parentCID) => {
                if (this.componentPatch(
                  this.rendered.getComponent(diff, parentCID),
                  parentCID
                )) {
                  phxChildrenAdded = true;
                }
              });
            });
          } else if (!isEmpty(diff)) {
            this.liveSocket.time("full patch complete", () => {
              const [html, streams] = this.renderContainer(diff, "update");
              const patch = new DOMPatch(this, this.el, this.id, html, streams, null);
              phxChildrenAdded = this.performPatch(patch, true);
            });
          }
          this.liveSocket.dispatchEvents(events);
          if (phxChildrenAdded) {
            this.joinNewChildren();
          }
          return true;
        }
        renderContainer(diff, kind) {
          return this.liveSocket.time(`toString diff (${kind})`, () => {
            const tag = this.el.tagName;
            const cids = diff ? this.rendered.componentCIDs(diff) : null;
            const { buffer: html, streams } = this.rendered.toString(cids);
            return [`<${tag}>${html}</${tag}>`, streams];
          });
        }
        componentPatch(diff, cid) {
          if (isEmpty(diff))
            return false;
          const { buffer: html, streams } = this.rendered.componentToString(cid);
          const patch = new DOMPatch(this, this.el, this.id, html, streams, cid);
          const childrenAdded = this.performPatch(patch, true);
          return childrenAdded;
        }
        getHook(el2) {
          return this.viewHooks[ViewHook.elementID(el2)];
        }
        addHook(el2) {
          const hookElId = ViewHook.elementID(el2);
          if (el2.getAttribute && !this.ownsElement(el2)) {
            return;
          }
          if (hookElId && !this.viewHooks[hookElId]) {
            const hook = dom_default.getCustomElHook(el2) || logError(`no hook found for custom element: ${el2.id}`);
            this.viewHooks[hookElId] = hook;
            hook.__attachView(this);
            return hook;
          } else if (hookElId || !el2.getAttribute) {
            return;
          } else {
            const hookName = el2.getAttribute(`data-phx-${PHX_HOOK}`) || el2.getAttribute(this.binding(PHX_HOOK));
            if (!hookName) {
              return;
            }
            const hookDefinition = this.liveSocket.getHookDefinition(hookName);
            if (hookDefinition) {
              if (!el2.id) {
                logError(
                  `no DOM ID for hook "${hookName}". Hooks require a unique ID on each element.`,
                  el2
                );
                return;
              }
              let hookInstance;
              try {
                if (typeof hookDefinition === "function" && hookDefinition.prototype instanceof ViewHook) {
                  hookInstance = new hookDefinition(this, el2);
                } else if (typeof hookDefinition === "object" && hookDefinition !== null) {
                  hookInstance = new ViewHook(this, el2, hookDefinition);
                } else {
                  logError(
                    `Invalid hook definition for "${hookName}". Expected a class extending ViewHook or an object definition.`,
                    el2
                  );
                  return;
                }
              } catch (e) {
                const errorMessage = e instanceof Error ? e.message : String(e);
                logError(`Failed to create hook "${hookName}": ${errorMessage}`, el2);
                return;
              }
              this.viewHooks[ViewHook.elementID(hookInstance.el)] = hookInstance;
              return hookInstance;
            } else if (hookName !== null) {
              logError(`unknown hook found for "${hookName}"`, el2);
            }
          }
        }
        destroyHook(hook) {
          const hookId = ViewHook.elementID(hook.el);
          hook.__destroyed();
          hook.__cleanup__();
          delete this.viewHooks[hookId];
        }
        applyPendingUpdates() {
          this.pendingDiffs = this.pendingDiffs.filter(
            ({ diff, events }) => !this.update(diff, events, true)
          );
          this.eachChild((child) => child.applyPendingUpdates());
        }
        eachChild(callback) {
          const children = this.root.children[this.id] || {};
          for (const id in children) {
            callback(this.getChildById(id));
          }
        }
        onChannel(event, cb) {
          this.liveSocket.onChannel(this.channel, event, (resp) => {
            if (this.isJoinPending()) {
              if (this.joinCount > 1) {
                this.pendingJoinOps.push(() => cb(resp));
              } else {
                this.root.pendingJoinOps.push([this, () => cb(resp)]);
              }
            } else {
              this.liveSocket.requestDOMUpdate(() => cb(resp));
            }
          });
        }
        bindChannel() {
          this.liveSocket.onChannel(this.channel, "diff", (rawDiff) => {
            this.liveSocket.requestDOMUpdate(() => {
              this.applyDiff(
                "update",
                rawDiff,
                ({ diff, events }) => this.update(diff, events)
              );
            });
          });
          this.onChannel(
            "redirect",
            ({ to, flash }) => this.onRedirect({ to, flash })
          );
          this.onChannel("live_patch", (redir) => this.onLivePatch(redir));
          this.onChannel("live_redirect", (redir) => this.onLiveRedirect(redir));
          this.channel.onError((reason) => this.onError(reason));
          this.channel.onClose((reason) => this.onClose(reason));
        }
        destroyAllChildren() {
          this.eachChild((child) => child.destroy());
        }
        onLiveRedirect(redir) {
          const { to, kind, flash } = redir;
          const url = this.expandURL(to);
          const e = new CustomEvent("phx:server-navigate", {
            detail: { to, kind, flash }
          });
          this.liveSocket.historyRedirect(e, url, kind, flash);
        }
        onLivePatch(redir) {
          const { to, kind } = redir;
          this.href = this.expandURL(to);
          this.liveSocket.historyPatch(to, kind);
        }
        expandURL(to) {
          return to.startsWith("/") ? `${window.location.protocol}//${window.location.host}${to}` : to;
        }
        /**
         * @param {{to: string, flash?: string, reloadToken?: string}} redirect
         */
        onRedirect({ to, flash, reloadToken }) {
          this.liveSocket.redirect(to, flash, reloadToken);
        }
        isDestroyed() {
          return this.destroyed;
        }
        joinDead() {
          this.isDead = true;
        }
        joinPush() {
          this.joinPush = this.joinPush || this.channel.join();
          return this.joinPush;
        }
        join(callback) {
          this.showLoader(this.liveSocket.loaderTimeout);
          this.bindChannel();
          if (this.isMain()) {
            this.stopCallback = this.liveSocket.withPageLoading({
              to: this.href,
              kind: "initial"
            });
          }
          this.joinCallback = (onDone) => {
            onDone = onDone || function() {
            };
            callback ? callback(this.joinCount, onDone) : onDone();
          };
          this.wrapPush(() => this.channel.join(), {
            ok: (resp) => this.liveSocket.requestDOMUpdate(() => this.onJoin(resp)),
            error: (error) => this.onJoinError(error),
            timeout: () => this.onJoinError({ reason: "timeout" })
          });
        }
        onJoinError(resp) {
          if (resp.reason === "reload") {
            this.log("error", () => [
              `failed mount with ${resp.status}. Falling back to page reload`,
              resp
            ]);
            this.onRedirect({
              to: this.liveSocket.main.href,
              reloadToken: resp.token
            });
            return;
          } else if (resp.reason === "unauthorized" || resp.reason === "stale") {
            this.log("error", () => [
              "unauthorized live_redirect. Falling back to page request",
              resp
            ]);
            this.onRedirect({ to: this.liveSocket.main.href, flash: this.flash });
            return;
          }
          if (resp.redirect || resp.live_redirect) {
            this.joinPending = false;
            this.channel.leave();
          }
          if (resp.redirect) {
            return this.onRedirect(resp.redirect);
          }
          if (resp.live_redirect) {
            return this.onLiveRedirect(resp.live_redirect);
          }
          this.log("error", () => ["unable to join", resp]);
          if (this.isMain()) {
            this.displayError(
              [PHX_LOADING_CLASS, PHX_ERROR_CLASS, PHX_SERVER_ERROR_CLASS],
              { unstructuredError: resp, errorKind: "server" }
            );
            if (this.liveSocket.isConnected()) {
              this.liveSocket.reloadWithJitter(this);
            }
          } else {
            if (this.joinAttempts >= MAX_CHILD_JOIN_ATTEMPTS) {
              this.root.displayError(
                [PHX_LOADING_CLASS, PHX_ERROR_CLASS, PHX_SERVER_ERROR_CLASS],
                { unstructuredError: resp, errorKind: "server" }
              );
              this.log("error", () => [
                `giving up trying to mount after ${MAX_CHILD_JOIN_ATTEMPTS} tries`,
                resp
              ]);
              this.destroy();
            }
            const trueChildEl = dom_default.byId(this.el.id);
            if (trueChildEl) {
              dom_default.mergeAttrs(trueChildEl, this.el);
              this.displayError(
                [PHX_LOADING_CLASS, PHX_ERROR_CLASS, PHX_SERVER_ERROR_CLASS],
                { unstructuredError: resp, errorKind: "server" }
              );
              this.el = trueChildEl;
            } else {
              this.destroy();
            }
          }
        }
        onClose(reason) {
          if (this.isDestroyed()) {
            return;
          }
          if (this.isMain() && this.liveSocket.hasPendingLink() && reason !== "leave") {
            return this.liveSocket.reloadWithJitter(this);
          }
          this.destroyAllChildren();
          this.liveSocket.dropActiveElement(this);
          if (this.liveSocket.isUnloaded()) {
            this.showLoader(BEFORE_UNLOAD_LOADER_TIMEOUT);
          }
        }
        onError(reason) {
          this.onClose(reason);
          if (this.liveSocket.isConnected()) {
            this.log("error", () => ["view crashed", reason]);
          }
          if (!this.liveSocket.isUnloaded()) {
            if (this.liveSocket.isConnected()) {
              this.displayError(
                [PHX_LOADING_CLASS, PHX_ERROR_CLASS, PHX_SERVER_ERROR_CLASS],
                { unstructuredError: reason, errorKind: "server" }
              );
            } else {
              this.displayError(
                [PHX_LOADING_CLASS, PHX_ERROR_CLASS, PHX_CLIENT_ERROR_CLASS],
                { unstructuredError: reason, errorKind: "client" }
              );
            }
          }
        }
        displayError(classes, details = {}) {
          if (this.isMain()) {
            dom_default.dispatchEvent(window, "phx:page-loading-start", {
              detail: { to: this.href, kind: "error", ...details }
            });
          }
          this.showLoader();
          this.setContainerClasses(...classes);
          this.delayedDisconnected();
        }
        delayedDisconnected() {
          this.disconnectedTimer = setTimeout(() => {
            this.execAll(this.binding("disconnected"));
          }, this.liveSocket.disconnectedTimeout);
        }
        wrapPush(callerPush, receives) {
          const latency = this.liveSocket.getLatencySim();
          const withLatency = latency ? (cb) => setTimeout(() => !this.isDestroyed() && cb(), latency) : (cb) => !this.isDestroyed() && cb();
          withLatency(() => {
            callerPush().receive(
              "ok",
              (resp) => withLatency(() => receives.ok && receives.ok(resp))
            ).receive(
              "error",
              (reason) => withLatency(() => receives.error && receives.error(reason))
            ).receive(
              "timeout",
              () => withLatency(() => receives.timeout && receives.timeout())
            );
          });
        }
        pushWithReply(refGenerator, event, payload) {
          if (!this.isConnected()) {
            return Promise.reject(new Error("no connection"));
          }
          const [ref, [el2], opts] = refGenerator ? refGenerator({ payload }) : [null, [], {}];
          const oldJoinCount = this.joinCount;
          let onLoadingDone = function() {
          };
          if (opts.page_loading) {
            onLoadingDone = this.liveSocket.withPageLoading({
              kind: "element",
              target: el2
            });
          }
          if (typeof payload.cid !== "number") {
            delete payload.cid;
          }
          return new Promise((resolve, reject) => {
            this.wrapPush(() => this.channel.push(event, payload, PUSH_TIMEOUT), {
              ok: (resp) => {
                if (ref !== null) {
                  this.lastAckRef = ref;
                }
                const finish = (hookReply) => {
                  if (resp.redirect) {
                    this.onRedirect(resp.redirect);
                  }
                  if (resp.live_patch) {
                    this.onLivePatch(resp.live_patch);
                  }
                  if (resp.live_redirect) {
                    this.onLiveRedirect(resp.live_redirect);
                  }
                  onLoadingDone();
                  resolve({ resp, reply: hookReply, ref });
                };
                if (resp.diff) {
                  this.liveSocket.requestDOMUpdate(() => {
                    this.applyDiff("update", resp.diff, ({ diff, reply, events }) => {
                      if (ref !== null) {
                        this.undoRefs(ref, payload.event);
                      }
                      this.update(diff, events);
                      finish(reply);
                    });
                  });
                } else {
                  if (ref !== null) {
                    this.undoRefs(ref, payload.event);
                  }
                  finish(null);
                }
              },
              error: (reason) => reject(new Error(`failed with reason: ${JSON.stringify(reason)}`)),
              timeout: () => {
                reject(new Error("timeout"));
                if (this.joinCount === oldJoinCount) {
                  this.liveSocket.reloadWithJitter(this, () => {
                    this.log("timeout", () => [
                      "received timeout while communicating with server. Falling back to hard refresh for recovery"
                    ]);
                  });
                }
              }
            });
          });
        }
        undoRefs(ref, phxEvent, onlyEls) {
          if (!this.isConnected()) {
            return;
          }
          const selector = `[${PHX_REF_SRC}="${this.refSrc()}"]`;
          if (onlyEls) {
            onlyEls = new Set(onlyEls);
            dom_default.all(document, selector, (parent) => {
              if (onlyEls && !onlyEls.has(parent)) {
                return;
              }
              dom_default.all(
                parent,
                selector,
                (child) => this.undoElRef(child, ref, phxEvent)
              );
              this.undoElRef(parent, ref, phxEvent);
            });
          } else {
            dom_default.all(document, selector, (el2) => this.undoElRef(el2, ref, phxEvent));
          }
        }
        undoElRef(el2, ref, phxEvent) {
          const elRef = new ElementRef(el2);
          elRef.maybeUndo(ref, phxEvent, (clonedTree) => {
            const patch = new DOMPatch(this, el2, this.id, clonedTree, [], null, {
              undoRef: ref
            });
            const phxChildrenAdded = this.performPatch(patch, true);
            dom_default.all(
              el2,
              `[${PHX_REF_SRC}="${this.refSrc()}"]`,
              (child) => this.undoElRef(child, ref, phxEvent)
            );
            if (phxChildrenAdded) {
              this.joinNewChildren();
            }
          });
        }
        refSrc() {
          return this.el.id;
        }
        putRef(elements, phxEvent, eventType, opts = {}) {
          const newRef = this.ref++;
          const disableWith = this.binding(PHX_DISABLE_WITH);
          if (opts.loading) {
            const loadingEls = dom_default.all(document, opts.loading).map((el2) => {
              return { el: el2, lock: true, loading: true };
            });
            elements = elements.concat(loadingEls);
          }
          for (const { el: el2, lock, loading } of elements) {
            if (!lock && !loading) {
              throw new Error("putRef requires lock or loading");
            }
            el2.setAttribute(PHX_REF_SRC, this.refSrc());
            if (loading) {
              el2.setAttribute(PHX_REF_LOADING, newRef);
            }
            if (lock) {
              el2.setAttribute(PHX_REF_LOCK, newRef);
            }
            if (!loading || opts.submitter && !(el2 === opts.submitter || el2 === opts.form)) {
              continue;
            }
            const lockCompletePromise = new Promise((resolve) => {
              el2.addEventListener(`phx:undo-lock:${newRef}`, () => resolve(detail), {
                once: true
              });
            });
            const loadingCompletePromise = new Promise((resolve) => {
              el2.addEventListener(
                `phx:undo-loading:${newRef}`,
                () => resolve(detail),
                { once: true }
              );
            });
            el2.classList.add(`phx-${eventType}-loading`);
            const disableText = el2.getAttribute(disableWith);
            if (disableText !== null) {
              if (!el2.getAttribute(PHX_DISABLE_WITH_RESTORE)) {
                el2.setAttribute(PHX_DISABLE_WITH_RESTORE, el2.textContent);
              }
              if (disableText !== "") {
                el2.textContent = disableText;
              }
              el2.setAttribute(
                PHX_DISABLED,
                el2.getAttribute(PHX_DISABLED) || el2.disabled
              );
              el2.setAttribute("disabled", "");
            }
            const detail = {
              event: phxEvent,
              eventType,
              ref: newRef,
              isLoading: loading,
              isLocked: lock,
              lockElements: elements.filter(({ lock: lock2 }) => lock2).map(({ el: el22 }) => el22),
              loadingElements: elements.filter(({ loading: loading2 }) => loading2).map(({ el: el22 }) => el22),
              unlock: (els) => {
                els = Array.isArray(els) ? els : [els];
                this.undoRefs(newRef, phxEvent, els);
              },
              lockComplete: lockCompletePromise,
              loadingComplete: loadingCompletePromise,
              lock: (lockEl) => {
                return new Promise((resolve) => {
                  if (this.isAcked(newRef)) {
                    return resolve(detail);
                  }
                  lockEl.setAttribute(PHX_REF_LOCK, newRef);
                  lockEl.setAttribute(PHX_REF_SRC, this.refSrc());
                  lockEl.addEventListener(
                    `phx:lock-stop:${newRef}`,
                    () => resolve(detail),
                    { once: true }
                  );
                });
              }
            };
            if (opts.payload) {
              detail["payload"] = opts.payload;
            }
            if (opts.target) {
              detail["target"] = opts.target;
            }
            if (opts.originalEvent) {
              detail["originalEvent"] = opts.originalEvent;
            }
            el2.dispatchEvent(
              new CustomEvent("phx:push", {
                detail,
                bubbles: true,
                cancelable: false
              })
            );
            if (phxEvent) {
              el2.dispatchEvent(
                new CustomEvent(`phx:push:${phxEvent}`, {
                  detail,
                  bubbles: true,
                  cancelable: false
                })
              );
            }
          }
          return [newRef, elements.map(({ el: el2 }) => el2), opts];
        }
        isAcked(ref) {
          return this.lastAckRef !== null && this.lastAckRef >= ref;
        }
        componentID(el2) {
          const cid = el2.getAttribute && el2.getAttribute(PHX_COMPONENT);
          return cid ? parseInt(cid) : null;
        }
        targetComponentID(target, targetCtx, opts = {}) {
          if (isCid(targetCtx)) {
            return targetCtx;
          }
          const cidOrSelector = opts.target || target.getAttribute(this.binding("target"));
          if (isCid(cidOrSelector)) {
            return parseInt(cidOrSelector);
          } else if (targetCtx && (cidOrSelector !== null || opts.target)) {
            return this.closestComponentID(targetCtx);
          } else {
            return null;
          }
        }
        closestComponentID(targetCtx) {
          if (isCid(targetCtx)) {
            return targetCtx;
          } else if (targetCtx) {
            return maybe(
              // We either use the closest data-phx-component binding, or -
              // in case of portals - continue with the portal source.
              // This is necessary if teleporting an element outside of its LiveComponent.
              targetCtx.closest(`[${PHX_COMPONENT}],[${PHX_TELEPORTED_SRC}]`),
              (el2) => {
                if (el2.hasAttribute(PHX_COMPONENT)) {
                  return this.ownsElement(el2) && this.componentID(el2);
                }
                if (el2.hasAttribute(PHX_TELEPORTED_SRC)) {
                  const portalParent = dom_default.byId(el2.getAttribute(PHX_TELEPORTED_SRC));
                  return this.closestComponentID(portalParent);
                }
              }
            );
          } else {
            return null;
          }
        }
        pushHookEvent(el2, targetCtx, event, payload) {
          if (!this.isConnected()) {
            this.log("hook", () => [
              "unable to push hook event. LiveView not connected",
              event,
              payload
            ]);
            return Promise.reject(
              new Error("unable to push hook event. LiveView not connected")
            );
          }
          const refGenerator = () => this.putRef([{ el: el2, loading: true, lock: true }], event, "hook", {
            payload,
            target: targetCtx
          });
          return this.pushWithReply(refGenerator, "event", {
            type: "hook",
            event,
            value: payload,
            cid: this.closestComponentID(targetCtx)
          }).then(({ resp: _resp, reply, ref }) => ({ reply, ref }));
        }
        extractMeta(el2, meta, value) {
          const prefix = this.binding("value-");
          for (let i = 0; i < el2.attributes.length; i++) {
            if (!meta) {
              meta = {};
            }
            const name = el2.attributes[i].name;
            if (name.startsWith(prefix)) {
              meta[name.replace(prefix, "")] = el2.getAttribute(name);
            }
          }
          if (el2.value !== void 0 && !(el2 instanceof HTMLFormElement)) {
            if (!meta) {
              meta = {};
            }
            meta.value = el2.value;
            if (el2.tagName === "INPUT" && CHECKABLE_INPUTS.indexOf(el2.type) >= 0 && !el2.checked) {
              delete meta.value;
            }
          }
          if (value) {
            if (!meta) {
              meta = {};
            }
            for (const key in value) {
              meta[key] = value[key];
            }
          }
          return meta;
        }
        pushEvent(type, el2, targetCtx, phxEvent, meta, opts = {}, onReply) {
          this.pushWithReply(
            (maybePayload) => this.putRef([{ el: el2, loading: true, lock: true }], phxEvent, type, {
              ...opts,
              payload: maybePayload?.payload
            }),
            "event",
            {
              type,
              event: phxEvent,
              value: this.extractMeta(el2, meta, opts.value),
              cid: this.targetComponentID(el2, targetCtx, opts)
            }
          ).then(({ reply }) => onReply && onReply(reply)).catch((error) => logError("Failed to push event", error));
        }
        pushFileProgress(fileEl, entryRef, progress, onReply = function() {
        }) {
          this.liveSocket.withinOwners(fileEl.form, (view, targetCtx) => {
            view.pushWithReply(null, "progress", {
              event: fileEl.getAttribute(view.binding(PHX_PROGRESS)),
              ref: fileEl.getAttribute(PHX_UPLOAD_REF),
              entry_ref: entryRef,
              progress,
              cid: view.targetComponentID(fileEl.form, targetCtx)
            }).then(() => onReply()).catch((error) => logError("Failed to push file progress", error));
          });
        }
        pushInput(inputEl, targetCtx, forceCid, phxEvent, opts, callback) {
          if (!inputEl.form) {
            throw new Error("form events require the input to be inside a form");
          }
          let uploads;
          const cid = isCid(forceCid) ? forceCid : this.targetComponentID(inputEl.form, targetCtx, opts);
          const refGenerator = (maybePayload) => {
            return this.putRef(
              [
                { el: inputEl, loading: true, lock: true },
                { el: inputEl.form, loading: true, lock: true }
              ],
              phxEvent,
              "change",
              { ...opts, payload: maybePayload?.payload }
            );
          };
          let formData;
          const meta = this.extractMeta(inputEl.form, {}, opts.value);
          const serializeOpts = {};
          if (inputEl instanceof HTMLButtonElement) {
            serializeOpts.submitter = inputEl;
          }
          if (inputEl.getAttribute(this.binding("change"))) {
            formData = serializeForm(inputEl.form, serializeOpts, [inputEl.name]);
          } else {
            formData = serializeForm(inputEl.form, serializeOpts);
          }
          if (dom_default.isUploadInput(inputEl) && inputEl.files && inputEl.files.length > 0) {
            LiveUploader.trackFiles(inputEl, Array.from(inputEl.files));
          }
          uploads = LiveUploader.serializeUploads(inputEl);
          const event = {
            type: "form",
            event: phxEvent,
            value: formData,
            meta: {
              // no target was implicitly sent as "undefined" in LV <= 1.0.5, therefore
              // we have to keep it. In 1.0.6 we switched from passing meta as URL encoded data
              // to passing it directly in the event, but the JSON encode would drop keys with
              // undefined values.
              _target: opts._target || "undefined",
              ...meta
            },
            uploads,
            cid
          };
          this.pushWithReply(refGenerator, "event", event).then(({ resp }) => {
            if (dom_default.isUploadInput(inputEl) && dom_default.isAutoUpload(inputEl)) {
              ElementRef.onUnlock(inputEl, () => {
                if (LiveUploader.filesAwaitingPreflight(inputEl).length > 0) {
                  const [ref, _els] = refGenerator();
                  this.undoRefs(ref, phxEvent, [inputEl.form]);
                  this.uploadFiles(
                    inputEl.form,
                    phxEvent,
                    targetCtx,
                    ref,
                    cid,
                    (_uploads) => {
                      callback && callback(resp);
                      this.triggerAwaitingSubmit(inputEl.form, phxEvent);
                      this.undoRefs(ref, phxEvent);
                    }
                  );
                }
              });
            } else {
              callback && callback(resp);
            }
          }).catch((error) => logError("Failed to push input event", error));
        }
        triggerAwaitingSubmit(formEl, phxEvent) {
          const awaitingSubmit = this.getScheduledSubmit(formEl);
          if (awaitingSubmit) {
            const [_el, _ref, _opts, callback] = awaitingSubmit;
            this.cancelSubmit(formEl, phxEvent);
            callback();
          }
        }
        getScheduledSubmit(formEl) {
          return this.formSubmits.find(
            ([el2, _ref, _opts, _callback]) => el2.isSameNode(formEl)
          );
        }
        scheduleSubmit(formEl, ref, opts, callback) {
          if (this.getScheduledSubmit(formEl)) {
            return true;
          }
          this.formSubmits.push([formEl, ref, opts, callback]);
        }
        cancelSubmit(formEl, phxEvent) {
          this.formSubmits = this.formSubmits.filter(
            ([el2, ref, _opts, _callback]) => {
              if (el2.isSameNode(formEl)) {
                this.undoRefs(ref, phxEvent);
                return false;
              } else {
                return true;
              }
            }
          );
        }
        disableForm(formEl, phxEvent, opts = {}) {
          const filterIgnored = (el2) => {
            const userIgnored = closestPhxBinding(
              el2,
              `${this.binding(PHX_UPDATE)}=ignore`,
              el2.form
            );
            return !(userIgnored || closestPhxBinding(el2, "data-phx-update=ignore", el2.form));
          };
          const filterDisables = (el2) => {
            return el2.hasAttribute(this.binding(PHX_DISABLE_WITH));
          };
          const filterButton = (el2) => el2.tagName == "BUTTON";
          const filterInput = (el2) => ["INPUT", "TEXTAREA", "SELECT"].includes(el2.tagName);
          const formElements = Array.from(formEl.elements);
          const disables = formElements.filter(filterDisables);
          const buttons = formElements.filter(filterButton).filter(filterIgnored);
          const inputs = formElements.filter(filterInput).filter(filterIgnored);
          buttons.forEach((button) => {
            button.setAttribute(PHX_DISABLED, button.disabled);
            button.disabled = true;
          });
          inputs.forEach((input) => {
            input.setAttribute(PHX_READONLY, input.readOnly);
            input.readOnly = true;
            if (input.files) {
              input.setAttribute(PHX_DISABLED, input.disabled);
              input.disabled = true;
            }
          });
          const formEls = disables.concat(buttons).concat(inputs).map((el2) => {
            return { el: el2, loading: true, lock: true };
          });
          const els = [{ el: formEl, loading: true, lock: false }].concat(formEls).reverse();
          return this.putRef(els, phxEvent, "submit", opts);
        }
        pushFormSubmit(formEl, targetCtx, phxEvent, submitter, opts, onReply) {
          const refGenerator = (maybePayload) => this.disableForm(formEl, phxEvent, {
            ...opts,
            form: formEl,
            payload: maybePayload?.payload,
            submitter
          });
          dom_default.putPrivate(formEl, "submitter", submitter);
          const cid = this.targetComponentID(formEl, targetCtx);
          if (LiveUploader.hasUploadsInProgress(formEl)) {
            const [ref, _els] = refGenerator();
            const push = () => this.pushFormSubmit(
              formEl,
              targetCtx,
              phxEvent,
              submitter,
              opts,
              onReply
            );
            return this.scheduleSubmit(formEl, ref, opts, push);
          } else if (LiveUploader.inputsAwaitingPreflight(formEl).length > 0) {
            const [ref, els] = refGenerator();
            const proxyRefGen = () => [ref, els, opts];
            this.uploadFiles(formEl, phxEvent, targetCtx, ref, cid, (_uploads) => {
              if (LiveUploader.inputsAwaitingPreflight(formEl).length > 0) {
                return this.undoRefs(ref, phxEvent);
              }
              const meta = this.extractMeta(formEl, {}, opts.value);
              const formData = serializeForm(formEl, { submitter });
              this.pushWithReply(proxyRefGen, "event", {
                type: "form",
                event: phxEvent,
                value: formData,
                meta,
                cid
              }).then(({ resp }) => onReply(resp)).catch((error) => logError("Failed to push form submit", error));
            });
          } else if (!(formEl.hasAttribute(PHX_REF_SRC) && formEl.classList.contains("phx-submit-loading"))) {
            const meta = this.extractMeta(formEl, {}, opts.value);
            const formData = serializeForm(formEl, { submitter });
            this.pushWithReply(refGenerator, "event", {
              type: "form",
              event: phxEvent,
              value: formData,
              meta,
              cid
            }).then(({ resp }) => onReply(resp)).catch((error) => logError("Failed to push form submit", error));
          }
        }
        uploadFiles(formEl, phxEvent, targetCtx, ref, cid, onComplete) {
          const joinCountAtUpload = this.joinCount;
          const inputEls = LiveUploader.activeFileInputs(formEl);
          let numFileInputsInProgress = inputEls.length;
          inputEls.forEach((inputEl) => {
            const uploader = new LiveUploader(inputEl, this, () => {
              numFileInputsInProgress--;
              if (numFileInputsInProgress === 0) {
                onComplete();
              }
            });
            const entries = uploader.entries().map((entry) => entry.toPreflightPayload());
            if (entries.length === 0) {
              numFileInputsInProgress--;
              return;
            }
            const payload = {
              ref: inputEl.getAttribute(PHX_UPLOAD_REF),
              entries,
              cid: this.targetComponentID(inputEl.form, targetCtx)
            };
            this.log("upload", () => ["sending preflight request", payload]);
            this.pushWithReply(null, "allow_upload", payload).then(({ resp }) => {
              this.log("upload", () => ["got preflight response", resp]);
              uploader.entries().forEach((entry) => {
                if (resp.entries && !resp.entries[entry.ref]) {
                  this.handleFailedEntryPreflight(
                    entry.ref,
                    "failed preflight",
                    uploader
                  );
                }
              });
              if (resp.error || Object.keys(resp.entries).length === 0) {
                this.undoRefs(ref, phxEvent);
                const errors = resp.error || [];
                errors.map(([entry_ref, reason]) => {
                  this.handleFailedEntryPreflight(entry_ref, reason, uploader);
                });
              } else {
                const onError = (callback) => {
                  this.channel.onError(() => {
                    if (this.joinCount === joinCountAtUpload) {
                      callback();
                    }
                  });
                };
                uploader.initAdapterUpload(resp, onError, this.liveSocket);
              }
            }).catch((error) => logError("Failed to push upload", error));
          });
        }
        handleFailedEntryPreflight(uploadRef, reason, uploader) {
          if (uploader.isAutoUpload()) {
            const entry = uploader.entries().find((entry2) => entry2.ref === uploadRef.toString());
            if (entry) {
              entry.cancel();
            }
          } else {
            uploader.entries().map((entry) => entry.cancel());
          }
          this.log("upload", () => [`error for entry ${uploadRef}`, reason]);
        }
        dispatchUploads(targetCtx, name, filesOrBlobs) {
          const targetElement = this.targetCtxElement(targetCtx) || this.el;
          const inputs = dom_default.findUploadInputs(targetElement).filter(
            (el2) => el2.name === name
          );
          if (inputs.length === 0) {
            logError(`no live file inputs found matching the name "${name}"`);
          } else if (inputs.length > 1) {
            logError(`duplicate live file inputs found matching the name "${name}"`);
          } else {
            dom_default.dispatchEvent(inputs[0], PHX_TRACK_UPLOADS, {
              detail: { files: filesOrBlobs }
            });
          }
        }
        targetCtxElement(targetCtx) {
          if (isCid(targetCtx)) {
            const [target] = dom_default.findComponentNodeList(this.id, targetCtx);
            return target;
          } else if (targetCtx) {
            return targetCtx;
          } else {
            return null;
          }
        }
        pushFormRecovery(oldForm, newForm, templateDom, callback) {
          const phxChange = this.binding("change");
          const phxTarget = newForm.getAttribute(this.binding("target")) || newForm;
          const phxEvent = newForm.getAttribute(this.binding(PHX_AUTO_RECOVER)) || newForm.getAttribute(this.binding("change"));
          const inputs = Array.from(oldForm.elements).filter(
            (el2) => dom_default.isFormInput(el2) && el2.name && !el2.hasAttribute(phxChange)
          );
          if (inputs.length === 0) {
            callback();
            return;
          }
          inputs.forEach(
            (input2) => input2.hasAttribute(PHX_UPLOAD_REF) && LiveUploader.clearFiles(input2)
          );
          const input = inputs.find((el2) => el2.type !== "hidden") || inputs[0];
          let pending = 0;
          this.withinTargets(
            phxTarget,
            (targetView, targetCtx) => {
              const cid = this.targetComponentID(newForm, targetCtx);
              pending++;
              let e = new CustomEvent("phx:form-recovery", {
                detail: { sourceElement: oldForm }
              });
              js_default.exec(e, "change", phxEvent, this, input, [
                "push",
                {
                  _target: input.name,
                  targetView,
                  targetCtx,
                  newCid: cid,
                  callback: () => {
                    pending--;
                    if (pending === 0) {
                      callback();
                    }
                  }
                }
              ]);
            },
            templateDom
          );
        }
        pushLinkPatch(e, href, targetEl, callback) {
          const linkRef = this.liveSocket.setPendingLink(href);
          const loading = e.isTrusted && e.type !== "popstate";
          const refGen = targetEl ? () => this.putRef(
            [{ el: targetEl, loading, lock: true }],
            null,
            "click"
          ) : null;
          const fallback = () => this.liveSocket.redirect(window.location.href);
          const url = href.startsWith("/") ? `${location.protocol}//${location.host}${href}` : href;
          this.pushWithReply(refGen, "live_patch", { url }).then(
            ({ resp }) => {
              this.liveSocket.requestDOMUpdate(() => {
                if (resp.link_redirect) {
                  this.liveSocket.replaceMain(href, null, callback, linkRef);
                } else if (resp.redirect) {
                  return;
                } else {
                  if (this.liveSocket.commitPendingLink(linkRef)) {
                    this.href = href;
                  }
                  this.applyPendingUpdates();
                  callback && callback(linkRef);
                }
              });
            },
            ({ error: _error, timeout: _timeout }) => fallback()
          );
        }
        getFormsForRecovery() {
          if (this.joinCount === 0) {
            return {};
          }
          const phxChange = this.binding("change");
          return dom_default.all(
            document,
            `#${CSS.escape(this.id)} form[${phxChange}], [${PHX_TELEPORTED_REF}="${CSS.escape(this.id)}"] form[${phxChange}]`
          ).filter((form) => form.id).filter((form) => form.elements.length > 0).filter(
            (form) => form.getAttribute(this.binding(PHX_AUTO_RECOVER)) !== "ignore"
          ).map((form) => {
            const clonedForm = form.cloneNode(true);
            morphdom_esm_default(clonedForm, form, {
              onBeforeElUpdated: (fromEl, toEl) => {
                dom_default.copyPrivates(fromEl, toEl);
                if (fromEl.getAttribute("form") === form.id) {
                  fromEl.parentNode.removeChild(fromEl);
                  return false;
                }
                return true;
              }
            });
            const externalElements = document.querySelectorAll(
              `[form="${CSS.escape(form.id)}"]`
            );
            Array.from(externalElements).forEach((el2) => {
              const clonedEl = (
                /** @type {HTMLElement} */
                el2.cloneNode(true)
              );
              morphdom_esm_default(clonedEl, el2);
              dom_default.copyPrivates(clonedEl, el2);
              clonedEl.removeAttribute("form");
              clonedForm.appendChild(clonedEl);
            });
            return clonedForm;
          }).reduce((acc, form) => {
            acc[form.id] = form;
            return acc;
          }, {});
        }
        maybePushComponentsDestroyed(destroyedCIDs) {
          let willDestroyCIDs = destroyedCIDs.filter((cid) => {
            return dom_default.findComponentNodeList(this.id, cid).length === 0;
          });
          const onError = (error) => {
            if (!this.isDestroyed()) {
              logError("Failed to push components destroyed", error);
            }
          };
          if (willDestroyCIDs.length > 0) {
            willDestroyCIDs.forEach((cid) => this.rendered.resetRender(cid));
            this.pushWithReply(null, "cids_will_destroy", { cids: willDestroyCIDs }).then(() => {
              this.liveSocket.requestDOMUpdate(() => {
                let completelyDestroyCIDs = willDestroyCIDs.filter((cid) => {
                  return dom_default.findComponentNodeList(this.id, cid).length === 0;
                });
                if (completelyDestroyCIDs.length > 0) {
                  this.pushWithReply(null, "cids_destroyed", {
                    cids: completelyDestroyCIDs
                  }).then(({ resp }) => {
                    this.rendered.pruneCIDs(resp.cids);
                  }).catch(onError);
                }
              });
            }).catch(onError);
          }
        }
        ownsElement(el2) {
          let parentViewEl = dom_default.closestViewEl(el2);
          return el2.getAttribute(PHX_PARENT_ID) === this.id || parentViewEl && parentViewEl.id === this.id || !parentViewEl && this.isDead;
        }
        submitForm(form, targetCtx, phxEvent, submitter, opts = {}) {
          dom_default.putPrivate(form, PHX_HAS_SUBMITTED, true);
          const inputs = Array.from(form.elements);
          inputs.forEach((input) => dom_default.putPrivate(input, PHX_HAS_SUBMITTED, true));
          this.liveSocket.blurActiveElement(this);
          this.pushFormSubmit(form, targetCtx, phxEvent, submitter, opts, () => {
            this.liveSocket.restorePreviouslyActiveFocus();
          });
        }
        binding(kind) {
          return this.liveSocket.binding(kind);
        }
        // phx-portal
        pushPortalElementId(id) {
          this.portalElementIds.add(id);
        }
        dropPortalElementId(id) {
          this.portalElementIds.delete(id);
        }
        destroyPortalElements() {
          if (!this.liveSocket.unloaded) {
            this.portalElementIds.forEach((id) => {
              const el2 = document.getElementById(id);
              if (el2) {
                el2.remove();
              }
            });
          }
        }
      };
      LiveSocket = class {
        constructor(url, phxSocket, opts = {}) {
          this.unloaded = false;
          if (!phxSocket || phxSocket.constructor.name === "Object") {
            throw new Error(`
      a phoenix Socket must be provided as the second argument to the LiveSocket constructor. For example:

          import {Socket} from "phoenix"
          import {LiveSocket} from "phoenix_live_view"
          let liveSocket = new LiveSocket("/live", Socket, {...})
      `);
          }
          this.socket = new phxSocket(url, opts);
          this.bindingPrefix = opts.bindingPrefix || BINDING_PREFIX;
          this.opts = opts;
          this.params = closure(opts.params || {});
          this.viewLogger = opts.viewLogger;
          this.metadataCallbacks = opts.metadata || {};
          this.defaults = Object.assign(clone(DEFAULTS), opts.defaults || {});
          this.prevActive = null;
          this.silenced = false;
          this.main = null;
          this.outgoingMainEl = null;
          this.clickStartedAtTarget = null;
          this.linkRef = 1;
          this.roots = {};
          this.href = window.location.href;
          this.pendingLink = null;
          this.currentLocation = clone(window.location);
          this.hooks = opts.hooks || {};
          this.uploaders = opts.uploaders || {};
          this.loaderTimeout = opts.loaderTimeout || LOADER_TIMEOUT;
          this.disconnectedTimeout = opts.disconnectedTimeout || DISCONNECTED_TIMEOUT;
          this.reloadWithJitterTimer = null;
          this.maxReloads = opts.maxReloads || MAX_RELOADS;
          this.reloadJitterMin = opts.reloadJitterMin || RELOAD_JITTER_MIN;
          this.reloadJitterMax = opts.reloadJitterMax || RELOAD_JITTER_MAX;
          this.failsafeJitter = opts.failsafeJitter || FAILSAFE_JITTER;
          this.localStorage = opts.localStorage || window.localStorage;
          this.sessionStorage = opts.sessionStorage || window.sessionStorage;
          this.boundTopLevelEvents = false;
          this.boundEventNames = /* @__PURE__ */ new Set();
          this.blockPhxChangeWhileComposing = opts.blockPhxChangeWhileComposing || false;
          this.serverCloseRef = null;
          this.domCallbacks = Object.assign(
            {
              jsQuerySelectorAll: null,
              onPatchStart: closure(),
              onPatchEnd: closure(),
              onNodeAdded: closure(),
              onBeforeElUpdated: closure()
            },
            opts.dom || {}
          );
          this.transitions = new TransitionSet();
          this.currentHistoryPosition = parseInt(this.sessionStorage.getItem(PHX_LV_HISTORY_POSITION)) || 0;
          window.addEventListener("pagehide", (_e3) => {
            this.unloaded = true;
          });
          this.socket.onOpen(() => {
            if (this.isUnloaded()) {
              window.location.reload();
            }
          });
        }
        // public
        version() {
          return "1.1.22";
        }
        isProfileEnabled() {
          return this.sessionStorage.getItem(PHX_LV_PROFILE) === "true";
        }
        isDebugEnabled() {
          return this.sessionStorage.getItem(PHX_LV_DEBUG) === "true";
        }
        isDebugDisabled() {
          return this.sessionStorage.getItem(PHX_LV_DEBUG) === "false";
        }
        enableDebug() {
          this.sessionStorage.setItem(PHX_LV_DEBUG, "true");
        }
        enableProfiling() {
          this.sessionStorage.setItem(PHX_LV_PROFILE, "true");
        }
        disableDebug() {
          this.sessionStorage.setItem(PHX_LV_DEBUG, "false");
        }
        disableProfiling() {
          this.sessionStorage.removeItem(PHX_LV_PROFILE);
        }
        enableLatencySim(upperBoundMs) {
          this.enableDebug();
          console.log(
            "latency simulator enabled for the duration of this browser session. Call disableLatencySim() to disable"
          );
          this.sessionStorage.setItem(PHX_LV_LATENCY_SIM, upperBoundMs);
        }
        disableLatencySim() {
          this.sessionStorage.removeItem(PHX_LV_LATENCY_SIM);
        }
        getLatencySim() {
          const str = this.sessionStorage.getItem(PHX_LV_LATENCY_SIM);
          return str ? parseInt(str) : null;
        }
        getSocket() {
          return this.socket;
        }
        connect() {
          if (window.location.hostname === "localhost" && !this.isDebugDisabled()) {
            this.enableDebug();
          }
          const doConnect = () => {
            this.resetReloadStatus();
            if (this.joinRootViews()) {
              this.bindTopLevelEvents();
              this.socket.connect();
            } else if (this.main) {
              this.socket.connect();
            } else {
              this.bindTopLevelEvents({ dead: true });
            }
            this.joinDeadView();
          };
          if (["complete", "loaded", "interactive"].indexOf(document.readyState) >= 0) {
            doConnect();
          } else {
            document.addEventListener("DOMContentLoaded", () => doConnect());
          }
        }
        disconnect(callback) {
          clearTimeout(this.reloadWithJitterTimer);
          if (this.serverCloseRef) {
            this.socket.off(this.serverCloseRef);
            this.serverCloseRef = null;
          }
          this.socket.disconnect(callback);
        }
        replaceTransport(transport) {
          clearTimeout(this.reloadWithJitterTimer);
          this.socket.replaceTransport(transport);
          this.connect();
        }
        /**
         * @param {HTMLElement} el
         * @param {string} encodedJS
         * @param {string | null} [eventType]
         */
        execJS(el2, encodedJS, eventType = null) {
          const e = new CustomEvent("phx:exec", { detail: { sourceElement: el2 } });
          this.owner(el2, (view) => js_default.exec(e, eventType, encodedJS, view, el2));
        }
        /**
         * Returns an object with methods to manipulate the DOM and execute JavaScript.
         * The applied changes integrate with server DOM patching.
         *
         * @returns {import("./js_commands").LiveSocketJSCommands}
         */
        js() {
          return js_commands_default(this, "js");
        }
        // private
        unload() {
          if (this.unloaded) {
            return;
          }
          if (this.main && this.isConnected()) {
            this.log(this.main, "socket", () => ["disconnect for page nav"]);
          }
          this.unloaded = true;
          this.destroyAllViews();
          this.disconnect();
        }
        triggerDOM(kind, args) {
          this.domCallbacks[kind](...args);
        }
        time(name, func) {
          if (!this.isProfileEnabled() || !console.time) {
            return func();
          }
          console.time(name);
          const result = func();
          console.timeEnd(name);
          return result;
        }
        log(view, kind, msgCallback) {
          if (this.viewLogger) {
            const [msg, obj] = msgCallback();
            this.viewLogger(view, kind, msg, obj);
          } else if (this.isDebugEnabled()) {
            const [msg, obj] = msgCallback();
            debug(view, kind, msg, obj);
          }
        }
        requestDOMUpdate(callback) {
          this.transitions.after(callback);
        }
        asyncTransition(promise) {
          this.transitions.addAsyncTransition(promise);
        }
        transition(time, onStart, onDone = function() {
        }) {
          this.transitions.addTransition(time, onStart, onDone);
        }
        onChannel(channel, event, cb) {
          channel.on(event, (data) => {
            const latency = this.getLatencySim();
            if (!latency) {
              cb(data);
            } else {
              setTimeout(() => cb(data), latency);
            }
          });
        }
        reloadWithJitter(view, log) {
          clearTimeout(this.reloadWithJitterTimer);
          this.disconnect();
          const minMs = this.reloadJitterMin;
          const maxMs = this.reloadJitterMax;
          let afterMs = Math.floor(Math.random() * (maxMs - minMs + 1)) + minMs;
          const tries = browser_default.updateLocal(
            this.localStorage,
            window.location.pathname,
            CONSECUTIVE_RELOADS,
            0,
            (count) => count + 1
          );
          if (tries >= this.maxReloads) {
            afterMs = this.failsafeJitter;
          }
          this.reloadWithJitterTimer = setTimeout(() => {
            if (view.isDestroyed() || view.isConnected()) {
              return;
            }
            view.destroy();
            log ? log() : this.log(view, "join", () => [
              `encountered ${tries} consecutive reloads`
            ]);
            if (tries >= this.maxReloads) {
              this.log(view, "join", () => [
                `exceeded ${this.maxReloads} consecutive reloads. Entering failsafe mode`
              ]);
            }
            if (this.hasPendingLink()) {
              window.location = this.pendingLink;
            } else {
              window.location.reload();
            }
          }, afterMs);
        }
        getHookDefinition(name) {
          if (!name) {
            return;
          }
          return this.maybeInternalHook(name) || this.hooks[name] || this.maybeRuntimeHook(name);
        }
        maybeInternalHook(name) {
          return name && name.startsWith("Phoenix.") && hooks_default[name.split(".")[1]];
        }
        maybeRuntimeHook(name) {
          const runtimeHook = document.querySelector(
            `script[${PHX_RUNTIME_HOOK}="${CSS.escape(name)}"]`
          );
          if (!runtimeHook) {
            return;
          }
          let callbacks = window[`phx_hook_${name}`];
          if (!callbacks || typeof callbacks !== "function") {
            logError("a runtime hook must be a function", runtimeHook);
            return;
          }
          const hookDefiniton = callbacks();
          if (hookDefiniton && (typeof hookDefiniton === "object" || typeof hookDefiniton === "function")) {
            return hookDefiniton;
          }
          logError(
            "runtime hook must return an object with hook callbacks or an instance of ViewHook",
            runtimeHook
          );
        }
        isUnloaded() {
          return this.unloaded;
        }
        isConnected() {
          return this.socket.isConnected();
        }
        getBindingPrefix() {
          return this.bindingPrefix;
        }
        binding(kind) {
          return `${this.getBindingPrefix()}${kind}`;
        }
        channel(topic, params) {
          return this.socket.channel(topic, params);
        }
        joinDeadView() {
          const body = document.body;
          if (body && !this.isPhxView(body) && !this.isPhxView(document.firstElementChild)) {
            const view = this.newRootView(body);
            view.setHref(this.getHref());
            view.joinDead();
            if (!this.main) {
              this.main = view;
            }
            window.requestAnimationFrame(() => {
              view.execNewMounted();
              this.maybeScroll(history.state?.scroll);
            });
          }
        }
        joinRootViews() {
          let rootsFound = false;
          dom_default.all(
            document,
            `${PHX_VIEW_SELECTOR}:not([${PHX_PARENT_ID}])`,
            (rootEl) => {
              if (!this.getRootById(rootEl.id)) {
                const view = this.newRootView(rootEl);
                if (!dom_default.isPhxSticky(rootEl)) {
                  view.setHref(this.getHref());
                }
                view.join();
                if (rootEl.hasAttribute(PHX_MAIN)) {
                  this.main = view;
                }
              }
              rootsFound = true;
            }
          );
          return rootsFound;
        }
        redirect(to, flash, reloadToken) {
          if (reloadToken) {
            browser_default.setCookie(PHX_RELOAD_STATUS, reloadToken, 60);
          }
          this.unload();
          browser_default.redirect(to, flash);
        }
        replaceMain(href, flash, callback = null, linkRef = this.setPendingLink(href)) {
          const liveReferer = this.currentLocation.href;
          this.outgoingMainEl = this.outgoingMainEl || this.main.el;
          const stickies = dom_default.findPhxSticky(document) || [];
          const removeEls = dom_default.all(
            this.outgoingMainEl,
            `[${this.binding("remove")}]`
          ).filter((el2) => !dom_default.isChildOfAny(el2, stickies));
          const newMainEl = dom_default.cloneNode(this.outgoingMainEl, "");
          this.main.showLoader(this.loaderTimeout);
          this.main.destroy();
          this.main = this.newRootView(newMainEl, flash, liveReferer);
          this.main.setRedirect(href);
          this.transitionRemoves(removeEls);
          this.main.join((joinCount, onDone) => {
            if (joinCount === 1 && this.commitPendingLink(linkRef)) {
              this.requestDOMUpdate(() => {
                removeEls.forEach((el2) => el2.remove());
                stickies.forEach((el2) => newMainEl.appendChild(el2));
                this.outgoingMainEl.replaceWith(newMainEl);
                this.outgoingMainEl = null;
                callback && callback(linkRef);
                onDone();
              });
            }
          });
        }
        transitionRemoves(elements, callback) {
          const removeAttr = this.binding("remove");
          const silenceEvents = (e) => {
            e.preventDefault();
            e.stopImmediatePropagation();
          };
          elements.forEach((el2) => {
            for (const event of this.boundEventNames) {
              el2.addEventListener(event, silenceEvents, true);
            }
            this.execJS(el2, el2.getAttribute(removeAttr), "remove");
          });
          this.requestDOMUpdate(() => {
            elements.forEach((el2) => {
              for (const event of this.boundEventNames) {
                el2.removeEventListener(event, silenceEvents, true);
              }
            });
            callback && callback();
          });
        }
        isPhxView(el2) {
          return el2.getAttribute && el2.getAttribute(PHX_SESSION) !== null;
        }
        newRootView(el2, flash, liveReferer) {
          const view = new View(el2, this, null, flash, liveReferer);
          this.roots[view.id] = view;
          return view;
        }
        owner(childEl, callback) {
          let view;
          const viewEl = dom_default.closestViewEl(childEl);
          if (viewEl) {
            view = this.getViewByEl(viewEl);
          } else {
            if (!childEl.isConnected) {
              return null;
            }
            view = this.main;
          }
          return view && callback ? callback(view) : view;
        }
        withinOwners(childEl, callback) {
          this.owner(childEl, (view) => callback(view, childEl));
        }
        getViewByEl(el2) {
          const rootId = el2.getAttribute(PHX_ROOT_ID);
          return maybe(
            this.getRootById(rootId),
            (root) => root.getDescendentByEl(el2)
          );
        }
        getRootById(id) {
          return this.roots[id];
        }
        destroyAllViews() {
          for (const id in this.roots) {
            this.roots[id].destroy();
            delete this.roots[id];
          }
          this.main = null;
        }
        destroyViewByEl(el2) {
          const root = this.getRootById(el2.getAttribute(PHX_ROOT_ID));
          if (root && root.id === el2.id) {
            root.destroy();
            delete this.roots[root.id];
          } else if (root) {
            root.destroyDescendent(el2.id);
          }
        }
        getActiveElement() {
          return document.activeElement;
        }
        dropActiveElement(view) {
          if (this.prevActive && view.ownsElement(this.prevActive)) {
            this.prevActive = null;
          }
        }
        restorePreviouslyActiveFocus() {
          if (this.prevActive && this.prevActive !== document.body && this.prevActive instanceof HTMLElement) {
            this.prevActive.focus();
          }
        }
        blurActiveElement() {
          this.prevActive = this.getActiveElement();
          if (this.prevActive !== document.body && this.prevActive instanceof HTMLElement) {
            this.prevActive.blur();
          }
        }
        /**
         * @param {{dead?: boolean}} [options={}]
         */
        bindTopLevelEvents({ dead } = {}) {
          if (this.boundTopLevelEvents) {
            return;
          }
          this.boundTopLevelEvents = true;
          this.serverCloseRef = this.socket.onClose((event) => {
            if (event && event.code === 1e3 && this.main) {
              return this.reloadWithJitter(this.main);
            }
          });
          document.body.addEventListener("click", function() {
          });
          window.addEventListener(
            "pageshow",
            (e) => {
              if (e.persisted) {
                this.getSocket().disconnect();
                this.withPageLoading({ to: window.location.href, kind: "redirect" });
                window.location.reload();
              }
            },
            true
          );
          if (!dead) {
            this.bindNav();
          }
          this.bindClicks();
          if (!dead) {
            this.bindForms();
          }
          this.bind(
            { keyup: "keyup", keydown: "keydown" },
            (e, type, view, targetEl, phxEvent, _phxTarget) => {
              const matchKey = targetEl.getAttribute(this.binding(PHX_KEY));
              const pressedKey = e.key && e.key.toLowerCase();
              if (matchKey && matchKey.toLowerCase() !== pressedKey) {
                return;
              }
              const data = { key: e.key, ...this.eventMeta(type, e, targetEl) };
              js_default.exec(e, type, phxEvent, view, targetEl, ["push", { data }]);
            }
          );
          this.bind(
            { blur: "focusout", focus: "focusin" },
            (e, type, view, targetEl, phxEvent, phxTarget) => {
              if (!phxTarget) {
                const data = { key: e.key, ...this.eventMeta(type, e, targetEl) };
                js_default.exec(e, type, phxEvent, view, targetEl, ["push", { data }]);
              }
            }
          );
          this.bind(
            { blur: "blur", focus: "focus" },
            (e, type, view, targetEl, phxEvent, phxTarget) => {
              if (phxTarget === "window") {
                const data = this.eventMeta(type, e, targetEl);
                js_default.exec(e, type, phxEvent, view, targetEl, ["push", { data }]);
              }
            }
          );
          this.on("dragover", (e) => e.preventDefault());
          this.on("dragenter", (e) => {
            const dropzone = closestPhxBinding(
              e.target,
              this.binding(PHX_DROP_TARGET)
            );
            if (!dropzone || !(dropzone instanceof HTMLElement)) {
              return;
            }
            if (eventContainsFiles(e)) {
              this.js().addClass(dropzone, PHX_DROP_TARGET_ACTIVE_CLASS);
            }
          });
          this.on("dragleave", (e) => {
            const dropzone = closestPhxBinding(
              e.target,
              this.binding(PHX_DROP_TARGET)
            );
            if (!dropzone || !(dropzone instanceof HTMLElement)) {
              return;
            }
            const rect = dropzone.getBoundingClientRect();
            if (e.clientX <= rect.left || e.clientX >= rect.right || e.clientY <= rect.top || e.clientY >= rect.bottom) {
              this.js().removeClass(dropzone, PHX_DROP_TARGET_ACTIVE_CLASS);
            }
          });
          this.on("drop", (e) => {
            e.preventDefault();
            const dropzone = closestPhxBinding(
              e.target,
              this.binding(PHX_DROP_TARGET)
            );
            if (!dropzone || !(dropzone instanceof HTMLElement)) {
              return;
            }
            this.js().removeClass(dropzone, PHX_DROP_TARGET_ACTIVE_CLASS);
            const dropTargetId = dropzone.getAttribute(this.binding(PHX_DROP_TARGET));
            const dropTarget = dropTargetId && document.getElementById(dropTargetId);
            const files = Array.from(e.dataTransfer.files || []);
            if (!dropTarget || !(dropTarget instanceof HTMLInputElement) || dropTarget.disabled || files.length === 0 || !(dropTarget.files instanceof FileList)) {
              return;
            }
            LiveUploader.trackFiles(dropTarget, files, e.dataTransfer);
            dropTarget.dispatchEvent(new Event("input", { bubbles: true }));
          });
          this.on(PHX_TRACK_UPLOADS, (e) => {
            const uploadTarget = e.target;
            if (!dom_default.isUploadInput(uploadTarget)) {
              return;
            }
            const files = Array.from(e.detail.files || []).filter(
              (f) => f instanceof File || f instanceof Blob
            );
            LiveUploader.trackFiles(uploadTarget, files);
            uploadTarget.dispatchEvent(new Event("input", { bubbles: true }));
          });
        }
        eventMeta(eventName, e, targetEl) {
          const callback = this.metadataCallbacks[eventName];
          return callback ? callback(e, targetEl) : {};
        }
        setPendingLink(href) {
          this.linkRef++;
          this.pendingLink = href;
          this.resetReloadStatus();
          return this.linkRef;
        }
        // anytime we are navigating or connecting, drop reload cookie in case
        // we issue the cookie but the next request was interrupted and the server never dropped it
        resetReloadStatus() {
          browser_default.deleteCookie(PHX_RELOAD_STATUS);
        }
        commitPendingLink(linkRef) {
          if (this.linkRef !== linkRef) {
            return false;
          } else {
            this.href = this.pendingLink;
            this.pendingLink = null;
            return true;
          }
        }
        getHref() {
          return this.href;
        }
        hasPendingLink() {
          return !!this.pendingLink;
        }
        bind(events, callback) {
          for (const event in events) {
            const browserEventName = events[event];
            this.on(browserEventName, (e) => {
              const binding = this.binding(event);
              const windowBinding = this.binding(`window-${event}`);
              const targetPhxEvent = e.target.getAttribute && e.target.getAttribute(binding);
              if (targetPhxEvent) {
                this.debounce(e.target, e, browserEventName, () => {
                  this.withinOwners(e.target, (view) => {
                    callback(e, event, view, e.target, targetPhxEvent, null);
                  });
                });
              } else {
                dom_default.all(document, `[${windowBinding}]`, (el2) => {
                  const phxEvent = el2.getAttribute(windowBinding);
                  this.debounce(el2, e, browserEventName, () => {
                    this.withinOwners(el2, (view) => {
                      callback(e, event, view, el2, phxEvent, "window");
                    });
                  });
                });
              }
            });
          }
        }
        bindClicks() {
          this.on("mousedown", (e) => this.clickStartedAtTarget = e.target);
          this.bindClick("click", "click");
        }
        bindClick(eventName, bindingName) {
          const click = this.binding(bindingName);
          window.addEventListener(
            eventName,
            (e) => {
              let target = null;
              if (e.detail === 0)
                this.clickStartedAtTarget = e.target;
              const clickStartedAtTarget = this.clickStartedAtTarget || e.target;
              target = closestPhxBinding(e.target, click);
              this.dispatchClickAway(e, clickStartedAtTarget);
              this.clickStartedAtTarget = null;
              const phxEvent = target && target.getAttribute(click);
              if (!phxEvent) {
                if (dom_default.isNewPageClick(e, window.location)) {
                  this.unload();
                }
                return;
              }
              if (target.getAttribute("href") === "#") {
                e.preventDefault();
              }
              if (target.hasAttribute(PHX_REF_SRC)) {
                return;
              }
              this.debounce(target, e, "click", () => {
                this.withinOwners(target, (view) => {
                  js_default.exec(e, "click", phxEvent, view, target, [
                    "push",
                    { data: this.eventMeta("click", e, target) }
                  ]);
                });
              });
            },
            false
          );
        }
        dispatchClickAway(e, clickStartedAt) {
          const phxClickAway = this.binding("click-away");
          dom_default.all(document, `[${phxClickAway}]`, (el2) => {
            if (!(el2.isSameNode(clickStartedAt) || el2.contains(clickStartedAt) || // When clicking a link with custom method,
            // phoenix_html triggers a click on a submit button
            // of a hidden form appended to the body. For such cases
            // where the clicked target is hidden, we skip click-away.
            !js_default.isVisible(clickStartedAt))) {
              this.withinOwners(el2, (view) => {
                const phxEvent = el2.getAttribute(phxClickAway);
                if (js_default.isVisible(el2) && js_default.isInViewport(el2)) {
                  js_default.exec(e, "click", phxEvent, view, el2, [
                    "push",
                    { data: this.eventMeta("click", e, e.target) }
                  ]);
                }
              });
            }
          });
        }
        bindNav() {
          if (!browser_default.canPushState()) {
            return;
          }
          if (history.scrollRestoration) {
            history.scrollRestoration = "manual";
          }
          let scrollTimer = null;
          window.addEventListener("scroll", (_e3) => {
            clearTimeout(scrollTimer);
            scrollTimer = setTimeout(() => {
              browser_default.updateCurrentState(
                (state) => Object.assign(state, { scroll: window.scrollY })
              );
            }, 100);
          });
          window.addEventListener(
            "popstate",
            (event) => {
              if (!this.registerNewLocation(window.location)) {
                return;
              }
              const { type, backType, id, scroll, position } = event.state || {};
              const href = window.location.href;
              const isForward = position > this.currentHistoryPosition;
              const navType = isForward ? type : backType || type;
              this.currentHistoryPosition = position || 0;
              this.sessionStorage.setItem(
                PHX_LV_HISTORY_POSITION,
                this.currentHistoryPosition.toString()
              );
              dom_default.dispatchEvent(window, "phx:navigate", {
                detail: {
                  href,
                  patch: navType === "patch",
                  pop: true,
                  direction: isForward ? "forward" : "backward"
                }
              });
              this.requestDOMUpdate(() => {
                const callback = () => {
                  this.maybeScroll(scroll);
                };
                if (this.main.isConnected() && navType === "patch" && id === this.main.id) {
                  this.main.pushLinkPatch(event, href, null, callback);
                } else {
                  this.replaceMain(href, null, callback);
                }
              });
            },
            false
          );
          window.addEventListener(
            "click",
            (e) => {
              const target = closestPhxBinding(e.target, PHX_LIVE_LINK);
              const type = target && target.getAttribute(PHX_LIVE_LINK);
              if (!type || !this.isConnected() || !this.main || dom_default.wantsNewTab(e)) {
                return;
              }
              const href = target.href instanceof SVGAnimatedString ? target.href.baseVal : target.href;
              const linkState = target.getAttribute(PHX_LINK_STATE);
              e.preventDefault();
              e.stopImmediatePropagation();
              if (this.pendingLink === href) {
                return;
              }
              this.requestDOMUpdate(() => {
                if (type === "patch") {
                  this.pushHistoryPatch(e, href, linkState, target);
                } else if (type === "redirect") {
                  this.historyRedirect(e, href, linkState, null, target);
                } else {
                  throw new Error(
                    `expected ${PHX_LIVE_LINK} to be "patch" or "redirect", got: ${type}`
                  );
                }
                const phxClick = target.getAttribute(this.binding("click"));
                if (phxClick) {
                  this.requestDOMUpdate(() => this.execJS(target, phxClick, "click"));
                }
              });
            },
            false
          );
        }
        maybeScroll(scroll) {
          if (typeof scroll === "number") {
            requestAnimationFrame(() => {
              window.scrollTo(0, scroll);
            });
          }
        }
        dispatchEvent(event, payload = {}) {
          dom_default.dispatchEvent(window, `phx:${event}`, { detail: payload });
        }
        dispatchEvents(events) {
          events.forEach(([event, payload]) => this.dispatchEvent(event, payload));
        }
        withPageLoading(info, callback) {
          dom_default.dispatchEvent(window, "phx:page-loading-start", { detail: info });
          const done = () => dom_default.dispatchEvent(window, "phx:page-loading-stop", { detail: info });
          return callback ? callback(done) : done;
        }
        pushHistoryPatch(e, href, linkState, targetEl) {
          if (!this.isConnected() || !this.main.isMain()) {
            return browser_default.redirect(href);
          }
          this.withPageLoading({ to: href, kind: "patch" }, (done) => {
            this.main.pushLinkPatch(e, href, targetEl, (linkRef) => {
              this.historyPatch(href, linkState, linkRef);
              done();
            });
          });
        }
        historyPatch(href, linkState, linkRef = this.setPendingLink(href)) {
          if (!this.commitPendingLink(linkRef)) {
            return;
          }
          this.currentHistoryPosition++;
          this.sessionStorage.setItem(
            PHX_LV_HISTORY_POSITION,
            this.currentHistoryPosition.toString()
          );
          browser_default.updateCurrentState((state) => ({ ...state, backType: "patch" }));
          browser_default.pushState(
            linkState,
            {
              type: "patch",
              id: this.main.id,
              position: this.currentHistoryPosition
            },
            href
          );
          dom_default.dispatchEvent(window, "phx:navigate", {
            detail: { patch: true, href, pop: false, direction: "forward" }
          });
          this.registerNewLocation(window.location);
        }
        historyRedirect(e, href, linkState, flash, targetEl) {
          const clickLoading = targetEl && e.isTrusted && e.type !== "popstate";
          if (clickLoading) {
            targetEl.classList.add("phx-click-loading");
          }
          if (!this.isConnected() || !this.main.isMain()) {
            return browser_default.redirect(href, flash);
          }
          if (/^\/$|^\/[^\/]+.*$/.test(href)) {
            const { protocol, host } = window.location;
            href = `${protocol}//${host}${href}`;
          }
          const scroll = window.scrollY;
          this.withPageLoading({ to: href, kind: "redirect" }, (done) => {
            this.replaceMain(href, flash, (linkRef) => {
              if (linkRef === this.linkRef) {
                this.currentHistoryPosition++;
                this.sessionStorage.setItem(
                  PHX_LV_HISTORY_POSITION,
                  this.currentHistoryPosition.toString()
                );
                browser_default.updateCurrentState((state) => ({
                  ...state,
                  backType: "redirect"
                }));
                browser_default.pushState(
                  linkState,
                  {
                    type: "redirect",
                    id: this.main.id,
                    scroll,
                    position: this.currentHistoryPosition
                  },
                  href
                );
                dom_default.dispatchEvent(window, "phx:navigate", {
                  detail: { href, patch: false, pop: false, direction: "forward" }
                });
                this.registerNewLocation(window.location);
              }
              if (clickLoading) {
                targetEl.classList.remove("phx-click-loading");
              }
              done();
            });
          });
        }
        registerNewLocation(newLocation) {
          const { pathname, search } = this.currentLocation;
          if (pathname + search === newLocation.pathname + newLocation.search) {
            return false;
          } else {
            this.currentLocation = clone(newLocation);
            return true;
          }
        }
        bindForms() {
          let iterations = 0;
          let externalFormSubmitted = false;
          this.on("submit", (e) => {
            const phxSubmit = e.target.getAttribute(this.binding("submit"));
            const phxChange = e.target.getAttribute(this.binding("change"));
            if (!externalFormSubmitted && phxChange && !phxSubmit) {
              externalFormSubmitted = true;
              e.preventDefault();
              this.withinOwners(e.target, (view) => {
                view.disableForm(e.target);
                window.requestAnimationFrame(() => {
                  if (dom_default.isUnloadableFormSubmit(e)) {
                    this.unload();
                  }
                  e.target.submit();
                });
              });
            }
          });
          this.on("submit", (e) => {
            const phxEvent = e.target.getAttribute(this.binding("submit"));
            if (!phxEvent) {
              if (dom_default.isUnloadableFormSubmit(e)) {
                this.unload();
              }
              return;
            }
            e.preventDefault();
            e.target.disabled = true;
            this.withinOwners(e.target, (view) => {
              js_default.exec(e, "submit", phxEvent, view, e.target, [
                "push",
                { submitter: e.submitter }
              ]);
            });
          });
          for (const type of ["change", "input"]) {
            this.on(type, (e) => {
              if (e instanceof CustomEvent && (e.target instanceof HTMLInputElement || e.target instanceof HTMLSelectElement || e.target instanceof HTMLTextAreaElement) && e.target.form === void 0) {
                if (e.detail && e.detail.dispatcher) {
                  throw new Error(
                    `dispatching a custom ${type} event is only supported on input elements inside a form`
                  );
                }
                return;
              }
              const phxChange = this.binding("change");
              const input = e.target;
              if (this.blockPhxChangeWhileComposing && e.isComposing) {
                const key = `composition-listener-${type}`;
                if (!dom_default.private(input, key)) {
                  dom_default.putPrivate(input, key, true);
                  input.addEventListener(
                    "compositionend",
                    () => {
                      input.dispatchEvent(new Event(type, { bubbles: true }));
                      dom_default.deletePrivate(input, key);
                    },
                    { once: true }
                  );
                }
                return;
              }
              const inputEvent = input.getAttribute(phxChange);
              const formEvent = input.form && input.form.getAttribute(phxChange);
              const phxEvent = inputEvent || formEvent;
              if (!phxEvent) {
                return;
              }
              if (input.type === "number" && input.validity && input.validity.badInput) {
                return;
              }
              const dispatcher = inputEvent ? input : input.form;
              const currentIterations = iterations;
              iterations++;
              const { at: at2, type: lastType } = dom_default.private(input, "prev-iteration") || {};
              if (at2 === currentIterations - 1 && type === "change" && lastType === "input") {
                return;
              }
              dom_default.putPrivate(input, "prev-iteration", {
                at: currentIterations,
                type
              });
              this.debounce(input, e, type, () => {
                this.withinOwners(dispatcher, (view) => {
                  dom_default.putPrivate(input, PHX_HAS_FOCUSED, true);
                  js_default.exec(e, "change", phxEvent, view, input, [
                    "push",
                    { _target: e.target.name, dispatcher }
                  ]);
                });
              });
            });
          }
          this.on("reset", (e) => {
            const form = e.target;
            dom_default.resetForm(form);
            const input = Array.from(form.elements).find((el2) => el2.type === "reset");
            if (input) {
              window.requestAnimationFrame(() => {
                input.dispatchEvent(
                  new Event("input", { bubbles: true, cancelable: false })
                );
              });
            }
          });
        }
        debounce(el2, event, eventType, callback) {
          if (eventType === "blur" || eventType === "focusout") {
            return callback();
          }
          const phxDebounce = this.binding(PHX_DEBOUNCE);
          const phxThrottle = this.binding(PHX_THROTTLE);
          const defaultDebounce = this.defaults.debounce.toString();
          const defaultThrottle = this.defaults.throttle.toString();
          this.withinOwners(el2, (view) => {
            const asyncFilter = () => !view.isDestroyed() && document.body.contains(el2);
            dom_default.debounce(
              el2,
              event,
              phxDebounce,
              defaultDebounce,
              phxThrottle,
              defaultThrottle,
              asyncFilter,
              () => {
                callback();
              }
            );
          });
        }
        silenceEvents(callback) {
          this.silenced = true;
          callback();
          this.silenced = false;
        }
        on(event, callback) {
          this.boundEventNames.add(event);
          window.addEventListener(event, (e) => {
            if (!this.silenced) {
              callback(e);
            }
          });
        }
        jsQuerySelectorAll(sourceEl, query, defaultQuery) {
          const all = this.domCallbacks.jsQuerySelectorAll;
          return all ? all(sourceEl, query, defaultQuery) : defaultQuery();
        }
      };
      TransitionSet = class {
        constructor() {
          this.transitions = /* @__PURE__ */ new Set();
          this.promises = /* @__PURE__ */ new Set();
          this.pendingOps = [];
        }
        reset() {
          this.transitions.forEach((timer) => {
            clearTimeout(timer);
            this.transitions.delete(timer);
          });
          this.promises.clear();
          this.flushPendingOps();
        }
        after(callback) {
          if (this.size() === 0) {
            callback();
          } else {
            this.pushPendingOp(callback);
          }
        }
        addTransition(time, onStart, onDone) {
          onStart();
          const timer = setTimeout(() => {
            this.transitions.delete(timer);
            onDone();
            this.flushPendingOps();
          }, time);
          this.transitions.add(timer);
        }
        addAsyncTransition(promise) {
          this.promises.add(promise);
          promise.then(() => {
            this.promises.delete(promise);
            this.flushPendingOps();
          });
        }
        pushPendingOp(op) {
          this.pendingOps.push(op);
        }
        size() {
          return this.transitions.size + this.promises.size;
        }
        flushPendingOps() {
          if (this.size() > 0) {
            return;
          }
          const op = this.pendingOps.shift();
          if (op) {
            op();
            this.flushPendingOps();
          }
        }
      };
      LiveSocket2 = LiveSocket;
    }
  });

  // node_modules/@xterm/xterm/lib/xterm.mjs
  function Al(s15) {
    return s15.replace(/\r?\n/g, "\r");
  }
  function kl(s15, t) {
    return t ? "\x1B[200~" + s15 + "\x1B[201~" : s15;
  }
  function Vs(s15, t) {
    s15.clipboardData && s15.clipboardData.setData("text/plain", t.selectionText), s15.preventDefault();
  }
  function qs(s15, t, e, i) {
    if (s15.stopPropagation(), s15.clipboardData) {
      let r = s15.clipboardData.getData("text/plain");
      Cn(r, t, e, i);
    }
  }
  function Cn(s15, t, e, i) {
    s15 = Al(s15), s15 = kl(s15, e.decPrivateModes.bracketedPasteMode && i.rawOptions.ignoreBracketedPasteMode !== true), e.triggerDataEvent(s15, true), t.value = "";
  }
  function Mn(s15, t, e) {
    let i = e.getBoundingClientRect(), r = s15.clientX - i.left - 10, n = s15.clientY - i.top - 10;
    t.style.width = "20px", t.style.height = "20px", t.style.left = `${r}px`, t.style.top = `${n}px`, t.style.zIndex = "1000", t.focus();
  }
  function Pn(s15, t, e, i, r) {
    Mn(s15, t, e), r && i.rightClickSelect(s15), t.value = i.selectionText, t.select();
  }
  function Ce(s15) {
    return s15 > 65535 ? (s15 -= 65536, String.fromCharCode((s15 >> 10) + 55296) + String.fromCharCode(s15 % 1024 + 56320)) : String.fromCharCode(s15);
  }
  function It(s15, t = 0, e = s15.length) {
    let i = "";
    for (let r = t; r < e; ++r) {
      let n = s15[r];
      n > 65535 ? (n -= 65536, i += String.fromCharCode((n >> 10) + 55296) + String.fromCharCode(n % 1024 + 56320)) : i += String.fromCharCode(n);
    }
    return i;
  }
  function Xs(s15) {
    return s15[Hn] || [];
  }
  function ie(s15) {
    if (Fn.has(s15)) return Fn.get(s15);
    let t = function(e, i, r) {
      if (arguments.length !== 3) throw new Error("@IServiceName-decorator can only be used to decorate a parameter");
      Pl(t, e, r);
    };
    return t._id = s15, Fn.set(s15, t), t;
  }
  function Pl(s15, t, e) {
    t[js] === t ? t[Hn].push({ id: s15, index: e }) : (t[Hn] = [{ id: s15, index: e }], t[js] = t);
  }
  function Ol(s15, t) {
    if (confirm(`Do you want to navigate to ${t}?

WARNING: This link could potentially be dangerous`)) {
      let i = window.open();
      if (i) {
        try {
          i.opener = null;
        } catch {
        }
        i.location.href = t;
      } else console.warn("Opening link blocked as opener could not be cleared");
    }
  }
  function Lt(s15) {
    Nl(s15) || Bl.onUnexpectedError(s15);
  }
  function Nl(s15) {
    return s15 instanceof bi ? true : s15 instanceof Error && s15.name === Un && s15.message === Un;
  }
  function eo(s15) {
    return s15 ? new Error(`Illegal argument: ${s15}`) : new Error("Illegal argument");
  }
  function Fl(s15, t, e = 0, i = s15.length) {
    let r = e, n = i;
    for (; r < n; ) {
      let o2 = Math.floor((r + n) / 2);
      t(s15[o2]) ? r = o2 + 1 : n = o2;
    }
    return r - 1;
  }
  function Se(s15, t = 0) {
    return s15[s15.length - (1 + t)];
  }
  function no(s15, t) {
    return (e, i) => t(s15(e), s15(i));
  }
  function co(s15, t) {
    let e = /* @__PURE__ */ Object.create(null);
    for (let i of s15) {
      let r = t(i), n = e[r];
      n || (n = e[r] = []), n.push(i);
    }
    return e;
  }
  function Kn(s15, t) {
    let e = this, i = false, r;
    return function() {
      if (i) return r;
      if (i = true, t) try {
        r = s15.apply(e, arguments);
      } finally {
        t();
      }
      else r = s15.apply(e, arguments);
      return r;
    };
  }
  function Ul(s15) {
    dt = s15;
  }
  function fr(s15) {
    return dt?.trackDisposable(s15), s15;
  }
  function pr(s15) {
    dt?.markAsDisposed(s15);
  }
  function vi(s15, t) {
    dt?.setParent(s15, t);
  }
  function Kl(s15, t) {
    if (dt) for (let e of s15) dt.setParent(e, t);
  }
  function Gn(s15) {
    return dt?.markAsSingleton(s15), s15;
  }
  function Ne(s15) {
    if (zn.is(s15)) {
      let t = [];
      for (let e of s15) if (e) try {
        e.dispose();
      } catch (i) {
        t.push(i);
      }
      if (t.length === 1) throw t[0];
      if (t.length > 1) throw new AggregateError(t, "Encountered errors while disposing of store");
      return Array.isArray(s15) ? [] : s15;
    } else if (s15) return s15.dispose(), s15;
  }
  function ho(...s15) {
    let t = C(() => Ne(s15));
    return Kl(s15, t), t;
  }
  function C(s15) {
    let t = fr({ dispose: Kn(() => {
      pr(t), s15();
    }) });
    return t;
  }
  function Xl(s15, t, e) {
    typeof t == "string" && (t = s15.matchMedia(t)), t.addEventListener("change", e);
  }
  function mo(s15) {
    return Si.INSTANCE.getZoomFactor(s15);
  }
  function _o() {
    return vr;
  }
  function ca(s15) {
    if (s15.charCode) {
      let e = String.fromCharCode(s15.charCode).toUpperCase();
      return Qn.fromString(e);
    }
    let t = s15.keyCode;
    if (t === 3) return 7;
    if (Ei) switch (t) {
      case 59:
        return 85;
      case 60:
        if (Zn) return 97;
        break;
      case 61:
        return 86;
      case 107:
        return 109;
      case 109:
        return 111;
      case 173:
        return 88;
      case 224:
        if (Te) return 57;
        break;
    }
    else if (Bt) {
      if (Te && t === 93) return 57;
      if (!Te && t === 92) return 57;
    }
    return yo[t] || 0;
  }
  function pa(s15) {
    if (!s15.parent || s15.parent === s15) return null;
    try {
      let t = s15.location, e = s15.parent.location;
      if (t.origin !== "null" && e.origin !== "null" && t.origin !== e.origin) return null;
    } catch {
      return null;
    }
    return s15.parent;
  }
  function Lo(s15) {
    return 55296 <= s15 && s15 <= 56319;
  }
  function is(s15) {
    return 56320 <= s15 && s15 <= 57343;
  }
  function Ao(s15, t) {
    return (s15 - 55296 << 10) + (t - 56320) + 65536;
  }
  function Mo(s15) {
    return ns(s15, 0);
  }
  function ns(s15, t) {
    switch (typeof s15) {
      case "object":
        return s15 === null ? je(349, t) : Array.isArray(s15) ? Ea(s15, t) : Ta(s15, t);
      case "string":
        return Po(s15, t);
      case "boolean":
        return Sa(s15, t);
      case "number":
        return je(s15, t);
      case "undefined":
        return je(937, t);
      default:
        return je(617, t);
    }
  }
  function je(s15, t) {
    return (t << 5) - t + s15 | 0;
  }
  function Sa(s15, t) {
    return je(s15 ? 433 : 863, t);
  }
  function Po(s15, t) {
    t = je(149417, t);
    for (let e = 0, i = s15.length; e < i; e++) t = je(s15.charCodeAt(e), t);
    return t;
  }
  function Ea(s15, t) {
    return t = je(104579, t), s15.reduce((e, i) => ns(i, e), t);
  }
  function Ta(s15, t) {
    return t = je(181387, t), Object.keys(s15).sort().reduce((e, i) => (e = Po(i, e), ns(s15[i], e)), t);
  }
  function rs(s15, t, e = 32) {
    let i = e - t, r = ~((1 << i) - 1);
    return (s15 << t | (r & s15) >>> i) >>> 0;
  }
  function ko(s15, t = 0, e = s15.byteLength, i = 0) {
    for (let r = 0; r < e; r++) s15[t + r] = i;
  }
  function Ia(s15, t, e = "0") {
    for (; s15.length < t; ) s15 = e + s15;
    return s15;
  }
  function wi(s15, t = 32) {
    return s15 instanceof ArrayBuffer ? Array.from(new Uint8Array(s15)).map((e) => e.toString(16).padStart(2, "0")).join("") : Ia((s15 >>> 0).toString(16), t / 4);
  }
  function L(s15, t, e, i) {
    return new ss(s15, t, e, i);
  }
  function ya(s15, t) {
    return function(e) {
      return t(new qe(s15, e));
    };
  }
  function xa(s15) {
    return function(t) {
      return s15(new ft(t));
    };
  }
  function Fo(s15) {
    let t = s15.getBoundingClientRect(), e = be(s15);
    return { left: t.left + e.scrollX, top: t.top + e.scrollY, width: t.width, height: t.height };
  }
  function Ho(s15, t, e, ...i) {
    let r = Da.exec(t);
    if (!r) throw new Error("Bad use of emmet");
    let n = r[1] || "div", o2;
    return s15 !== "http://www.w3.org/1999/xhtml" ? o2 = document.createElementNS(s15, n) : o2 = document.createElement(n), r[3] && (o2.id = r[3]), r[4] && (o2.className = r[4].replace(/\./g, " ").trim()), e && Object.entries(e).forEach(([l2, a]) => {
      typeof a > "u" || (/^on\w+$/.test(l2) ? o2[l2] = a : l2 === "selected" ? a && o2.setAttribute(l2, "true") : o2.setAttribute(l2, a));
    }), o2.append(...i), o2;
  }
  function Ra(s15, t, ...e) {
    return Ho("http://www.w3.org/1999/xhtml", s15, t, ...e);
  }
  function Ie(s15) {
    return typeof s15 == "number" ? `${s15}px` : s15;
  }
  function _t(s15) {
    return new ls(s15);
  }
  function Wo(s15, t, e) {
    let i = null, r = null;
    if (typeof e.value == "function" ? (i = "value", r = e.value, r.length !== 0 && console.warn("Memoize should only be used in functions with zero parameters")) : typeof e.get == "function" && (i = "get", r = e.get), !r) throw new Error("not supported");
    let n = `$memoize$${t}`;
    e[i] = function(...o2) {
      return this.hasOwnProperty(n) || Object.defineProperty(this, n, { configurable: false, enumerable: false, writable: false, value: r.apply(this, o2) }), this[n];
    };
  }
  function as(s15, t) {
    let e = t - s15;
    return function(i) {
      return s15 + e * ka(i);
    };
  }
  function La(s15, t, e) {
    return function(i) {
      return i < e ? s15(i / e) : t((i - e) / (1 - e));
    };
  }
  function Aa(s15) {
    return Math.pow(s15, 3);
  }
  function ka(s15) {
    return 1 - Aa(1 - s15);
  }
  function Pa(s15) {
    let t = { lazyRender: typeof s15.lazyRender < "u" ? s15.lazyRender : false, className: typeof s15.className < "u" ? s15.className : "", useShadows: typeof s15.useShadows < "u" ? s15.useShadows : true, handleMouseWheel: typeof s15.handleMouseWheel < "u" ? s15.handleMouseWheel : true, flipAxes: typeof s15.flipAxes < "u" ? s15.flipAxes : false, consumeMouseWheelIfScrollbarIsNeeded: typeof s15.consumeMouseWheelIfScrollbarIsNeeded < "u" ? s15.consumeMouseWheelIfScrollbarIsNeeded : false, alwaysConsumeMouseWheel: typeof s15.alwaysConsumeMouseWheel < "u" ? s15.alwaysConsumeMouseWheel : false, scrollYToX: typeof s15.scrollYToX < "u" ? s15.scrollYToX : false, mouseWheelScrollSensitivity: typeof s15.mouseWheelScrollSensitivity < "u" ? s15.mouseWheelScrollSensitivity : 1, fastScrollSensitivity: typeof s15.fastScrollSensitivity < "u" ? s15.fastScrollSensitivity : 5, scrollPredominantAxis: typeof s15.scrollPredominantAxis < "u" ? s15.scrollPredominantAxis : true, mouseWheelSmoothScroll: typeof s15.mouseWheelSmoothScroll < "u" ? s15.mouseWheelSmoothScroll : true, arrowSize: typeof s15.arrowSize < "u" ? s15.arrowSize : 11, listenOnDomNode: typeof s15.listenOnDomNode < "u" ? s15.listenOnDomNode : null, horizontal: typeof s15.horizontal < "u" ? s15.horizontal : 1, horizontalScrollbarSize: typeof s15.horizontalScrollbarSize < "u" ? s15.horizontalScrollbarSize : 10, horizontalSliderSize: typeof s15.horizontalSliderSize < "u" ? s15.horizontalSliderSize : 0, horizontalHasArrows: typeof s15.horizontalHasArrows < "u" ? s15.horizontalHasArrows : false, vertical: typeof s15.vertical < "u" ? s15.vertical : 1, verticalScrollbarSize: typeof s15.verticalScrollbarSize < "u" ? s15.verticalScrollbarSize : 10, verticalHasArrows: typeof s15.verticalHasArrows < "u" ? s15.verticalHasArrows : false, verticalSliderSize: typeof s15.verticalSliderSize < "u" ? s15.verticalSliderSize : 0, scrollByPage: typeof s15.scrollByPage < "u" ? s15.scrollByPage : false };
    return t.horizontalSliderSize = typeof s15.horizontalSliderSize < "u" ? s15.horizontalSliderSize : t.horizontalScrollbarSize, t.verticalSliderSize = typeof s15.verticalSliderSize < "u" ? s15.verticalSliderSize : t.verticalScrollbarSize, Te && (t.className += " mac"), t;
  }
  function vt(s15) {
    let t = s15.toString(16);
    return t.length < 2 ? "0" + t : t;
  }
  function Xe(s15, t) {
    return s15 < t ? (t + 0.05) / (s15 + 0.05) : (s15 + 0.05) / (t + 0.05);
  }
  function Oa(s15) {
    return 57508 <= s15 && s15 <= 57558;
  }
  function Ba(s15) {
    return 9472 <= s15 && s15 <= 9631;
  }
  function $o(s15) {
    return Oa(s15) || Ba(s15);
  }
  function Vo() {
    return { css: { canvas: qr(), cell: qr() }, device: { canvas: qr(), cell: qr(), char: { width: 0, height: 0, left: 0, top: 0 } } };
  }
  function qr() {
    return { width: 0, height: 0 };
  }
  function qo(s15, t, e) {
    for (; s15.length < e; ) s15 = t + s15;
    return s15;
  }
  function Yo() {
    return new ms();
  }
  function Ci(s15, t, e) {
    let i = e.getBoundingClientRect(), r = s15.getComputedStyle(e), n = parseInt(r.getPropertyValue("padding-left")), o2 = parseInt(r.getPropertyValue("padding-top"));
    return [t.clientX - i.left - n, t.clientY - i.top - o2];
  }
  function Xo(s15, t, e, i, r, n, o2, l2, a) {
    if (!n) return;
    let u = Ci(s15, t, e);
    if (u) return u[0] = Math.ceil((u[0] + (a ? o2 / 2 : 0)) / o2), u[1] = Math.ceil(u[1] / l2), u[0] = Math.min(Math.max(u[0], 1), i + (a ? 1 : 0)), u[1] = Math.min(Math.max(u[1], 1), r), u;
  }
  function Ha() {
    if (!Zo) return 0;
    let s15 = Pi.match(/Version\/(\d+)/);
    return s15 === null || s15.length < 2 ? 0 : parseInt(s15[1]);
  }
  function Jo(s15, t, e, i) {
    let r = e.buffer.x, n = e.buffer.y;
    if (!e.buffer.hasScrollback) return Ga(r, n, s15, t, e, i) + sn(n, t, e, i) + $a(r, n, s15, t, e, i);
    let o2;
    if (n === t) return o2 = r > s15 ? "D" : "C", Fi(Math.abs(r - s15), Ni(o2, i));
    o2 = n > t ? "D" : "C";
    let l2 = Math.abs(n - t), a = za(n > t ? s15 : r, e) + (l2 - 1) * e.cols + 1 + Ka(n > t ? r : s15, e);
    return Fi(a, Ni(o2, i));
  }
  function Ka(s15, t) {
    return s15 - 1;
  }
  function za(s15, t) {
    return t.cols - s15;
  }
  function Ga(s15, t, e, i, r, n) {
    return sn(t, i, r, n).length === 0 ? "" : Fi(el(s15, t, s15, t - gt(t, r), false, r).length, Ni("D", n));
  }
  function sn(s15, t, e, i) {
    let r = s15 - gt(s15, e), n = t - gt(t, e), o2 = Math.abs(r - n) - Va(s15, t, e);
    return Fi(o2, Ni(Qo(s15, t), i));
  }
  function $a(s15, t, e, i, r, n) {
    let o2;
    sn(t, i, r, n).length > 0 ? o2 = i - gt(i, r) : o2 = t;
    let l2 = i, a = qa(s15, t, e, i, r, n);
    return Fi(el(s15, o2, e, l2, a === "C", r).length, Ni(a, n));
  }
  function Va(s15, t, e) {
    let i = 0, r = s15 - gt(s15, e), n = t - gt(t, e);
    for (let o2 = 0; o2 < Math.abs(r - n); o2++) {
      let l2 = Qo(s15, t) === "A" ? -1 : 1;
      e.buffer.lines.get(r + l2 * o2)?.isWrapped && i++;
    }
    return i;
  }
  function gt(s15, t) {
    let e = 0, i = t.buffer.lines.get(s15), r = i?.isWrapped;
    for (; r && s15 >= 0 && s15 < t.rows; ) e++, i = t.buffer.lines.get(--s15), r = i?.isWrapped;
    return e;
  }
  function qa(s15, t, e, i, r, n) {
    let o2;
    return sn(e, i, r, n).length > 0 ? o2 = i - gt(i, r) : o2 = t, s15 < e && o2 <= i || s15 >= e && o2 < i ? "C" : "D";
  }
  function Qo(s15, t) {
    return s15 > t ? "A" : "B";
  }
  function el(s15, t, e, i, r, n) {
    let o2 = s15, l2 = t, a = "";
    for (; (o2 !== e || l2 !== i) && l2 >= 0 && l2 < n.buffer.lines.length; ) o2 += r ? 1 : -1, r && o2 > n.cols - 1 ? (a += n.buffer.translateBufferLineToString(l2, false, s15, o2), o2 = 0, s15 = 0, l2++) : !r && o2 < 0 && (a += n.buffer.translateBufferLineToString(l2, false, 0, s15 + 1), o2 = n.cols - 1, s15 = o2, l2--);
    return a + n.buffer.translateBufferLineToString(l2, false, s15, o2);
  }
  function Ni(s15, t) {
    let e = t ? "O" : "[";
    return b.ESC + e + s15;
  }
  function Fi(s15, t) {
    s15 = Math.floor(s15);
    let e = "";
    for (let i = 0; i < s15; i++) e += t;
    return e;
  }
  function ws(s15, t) {
    if (s15.start.y > s15.end.y) throw new Error(`Buffer range end (${s15.end.x}, ${s15.end.y}) cannot be before start (${s15.start.x}, ${s15.start.y})`);
    return t * (s15.end.y - s15.start.y) + (s15.end.x - s15.start.x + 1);
  }
  function K(s15, t) {
    if (s15 !== void 0) try {
      return z.toColor(s15);
    } catch {
    }
    return t;
  }
  function sl(s15, t, e, i, r, n) {
    let o2 = [];
    for (let l2 = 0; l2 < s15.length - 1; l2++) {
      let a = l2, u = s15.get(++a);
      if (!u.isWrapped) continue;
      let h2 = [s15.get(l2)];
      for (; a < s15.length && u.isWrapped; ) h2.push(u), u = s15.get(++a);
      if (!n && i >= l2 && i < a) {
        l2 += h2.length - 1;
        continue;
      }
      let c = 0, d = ri(h2, c, t), _3 = 1, p = 0;
      for (; _3 < h2.length; ) {
        let f = ri(h2, _3, t), A = f - p, R = e - d, O = Math.min(A, R);
        h2[c].copyCellsFrom(h2[_3], p, d, O, false), d += O, d === e && (c++, d = 0), p += O, p === f && (_3++, p = 0), d === 0 && c !== 0 && h2[c - 1].getWidth(e - 1) === 2 && (h2[c].copyCellsFrom(h2[c - 1], e - 1, d++, 1, false), h2[c - 1].setCell(e - 1, r));
      }
      h2[c].replaceCells(d, e, r);
      let m = 0;
      for (let f = h2.length - 1; f > 0 && (f > c || h2[f].getTrimmedLength() === 0); f--) m++;
      m > 0 && (o2.push(l2 + h2.length - m), o2.push(m)), l2 += h2.length - 1;
    }
    return o2;
  }
  function ol(s15, t) {
    let e = [], i = 0, r = t[i], n = 0;
    for (let o2 = 0; o2 < s15.length; o2++) if (r === o2) {
      let l2 = t[++i];
      s15.onDeleteEmitter.fire({ index: o2 - n, amount: l2 }), o2 += l2 - 1, n += l2, r = t[++i];
    } else e.push(o2);
    return { layout: e, countRemoved: n };
  }
  function ll(s15, t) {
    let e = [];
    for (let i = 0; i < t.length; i++) e.push(s15.get(t[i]));
    for (let i = 0; i < e.length; i++) s15.set(i, e[i]);
    s15.length = t.length;
  }
  function al(s15, t, e) {
    let i = [], r = s15.map((a, u) => ri(s15, u, t)).reduce((a, u) => a + u), n = 0, o2 = 0, l2 = 0;
    for (; l2 < r; ) {
      if (r - l2 < e) {
        i.push(r - l2);
        break;
      }
      n += e;
      let a = ri(s15, o2, t);
      n > a && (n -= a, o2++);
      let u = s15[o2].getWidth(n - 1) === 2;
      u && n--;
      let h2 = u ? e - 1 : e;
      i.push(h2), l2 += h2;
    }
    return i;
  }
  function ri(s15, t, e) {
    if (t === s15.length - 1) return s15[t].getTrimmedLength();
    let i = !s15[t].hasContent(e - 1) && s15[t].getWidth(e - 1) === 1, r = s15[t + 1].getWidth(0) === 2;
    return i && r ? e - 1 : e;
  }
  function sc(s15) {
    return s15 === "block" || s15 === "underline" || s15 === "bar";
  }
  function oi(s15, t = 5) {
    if (typeof s15 != "object") return s15;
    let e = Array.isArray(s15) ? [] : {};
    for (let i in s15) e[i] = t <= 1 ? s15[i] : s15[i] && oi(s15[i], t - 1);
    return e;
  }
  function Ms(s15, t) {
    let e = (s15.ctrl ? 16 : 0) | (s15.shift ? 4 : 0) | (s15.alt ? 8 : 0);
    return s15.button === 4 ? (e |= 64, e |= s15.action) : (e |= s15.button & 3, s15.button & 4 && (e |= 64), s15.button & 8 && (e |= 128), s15.action === 32 ? e |= 32 : s15.action === 0 && !t && (e |= 3)), e;
  }
  function cc(s15, t) {
    let e = 0, i = t.length - 1, r;
    if (s15 < t[0][0] || s15 > t[i][1]) return false;
    for (; i >= e; ) if (r = e + i >> 1, s15 > t[r][1]) e = r + 1;
    else if (s15 < t[r][0]) i = r - 1;
    else return true;
    return false;
  }
  function Bs(s15) {
    let e = s15.buffer.lines.get(s15.buffer.ybase + s15.buffer.y - 1)?.get(s15.cols - 1), i = s15.buffer.lines.get(s15.buffer.ybase + s15.buffer.y);
    i && e && (i.isWrapped = e[3] !== 0 && e[3] !== 32);
  }
  function Ws(s15) {
    if (!s15) return;
    let t = s15.toLowerCase();
    if (t.indexOf("rgb:") === 0) {
      t = t.slice(4);
      let e = dc.exec(t);
      if (e) {
        let i = e[1] ? 15 : e[4] ? 255 : e[7] ? 4095 : 65535;
        return [Math.round(parseInt(e[1] || e[4] || e[7] || e[10], 16) / i * 255), Math.round(parseInt(e[2] || e[5] || e[8] || e[11], 16) / i * 255), Math.round(parseInt(e[3] || e[6] || e[9] || e[12], 16) / i * 255)];
      }
    } else if (t.indexOf("#") === 0 && (t = t.slice(1), fc.exec(t) && [3, 6, 9, 12].includes(t.length))) {
      let e = t.length / 3, i = [0, 0, 0];
      for (let r = 0; r < 3; ++r) {
        let n = parseInt(t.slice(e * r, e * r + e), 16);
        i[r] = e === 1 ? n << 4 : e === 2 ? n : e === 3 ? n >> 4 : n >> 8;
      }
      return i;
    }
  }
  function Hs(s15, t) {
    let e = s15.toString(16), i = e.length < 2 ? "0" + e : e;
    switch (t) {
      case 4:
        return e[0];
      case 8:
        return i;
      case 12:
        return (i + i).slice(0, 3);
      default:
        return i + i;
    }
  }
  function ml(s15, t = 16) {
    let [e, i, r] = s15;
    return `rgb:${Hs(e, t)}/${Hs(i, t)}/${Hs(r, t)}`;
  }
  function bl(s15, t) {
    if (s15 > 24) return t.setWinLines || false;
    switch (s15) {
      case 1:
        return !!t.restoreWin;
      case 2:
        return !!t.minimizeWin;
      case 3:
        return !!t.setWinPosition;
      case 4:
        return !!t.setWinSizePixels;
      case 5:
        return !!t.raiseWin;
      case 6:
        return !!t.lowerWin;
      case 7:
        return !!t.refreshWin;
      case 8:
        return !!t.setWinSizeChars;
      case 9:
        return !!t.maximizeWin;
      case 10:
        return !!t.fullscreenWin;
      case 11:
        return !!t.getWinState;
      case 13:
        return !!t.getWinPosition;
      case 14:
        return !!t.getWinSizePixels;
      case 15:
        return !!t.getScreenSizePixels;
      case 16:
        return !!t.getCellSizePixels;
      case 18:
        return !!t.getWinSizeChars;
      case 19:
        return !!t.getScreenSizeChars;
      case 20:
        return !!t.getIconTitle;
      case 21:
        return !!t.getWinTitle;
      case 22:
        return !!t.pushTitle;
      case 23:
        return !!t.popTitle;
      case 24:
        return !!t.setWinLines;
    }
    return false;
  }
  function Sl(s15) {
    return 0 <= s15 && s15 < 256;
  }
  function Il(s15, t, e, i) {
    let r = { type: 0, cancel: false, key: void 0 }, n = (s15.shiftKey ? 1 : 0) | (s15.altKey ? 2 : 0) | (s15.ctrlKey ? 4 : 0) | (s15.metaKey ? 8 : 0);
    switch (s15.keyCode) {
      case 0:
        s15.key === "UIKeyInputUpArrow" ? t ? r.key = b.ESC + "OA" : r.key = b.ESC + "[A" : s15.key === "UIKeyInputLeftArrow" ? t ? r.key = b.ESC + "OD" : r.key = b.ESC + "[D" : s15.key === "UIKeyInputRightArrow" ? t ? r.key = b.ESC + "OC" : r.key = b.ESC + "[C" : s15.key === "UIKeyInputDownArrow" && (t ? r.key = b.ESC + "OB" : r.key = b.ESC + "[B");
        break;
      case 8:
        r.key = s15.ctrlKey ? "\b" : b.DEL, s15.altKey && (r.key = b.ESC + r.key);
        break;
      case 9:
        if (s15.shiftKey) {
          r.key = b.ESC + "[Z";
          break;
        }
        r.key = b.HT, r.cancel = true;
        break;
      case 13:
        r.key = s15.altKey ? b.ESC + b.CR : b.CR, r.cancel = true;
        break;
      case 27:
        r.key = b.ESC, s15.altKey && (r.key = b.ESC + b.ESC), r.cancel = true;
        break;
      case 37:
        if (s15.metaKey) break;
        n ? r.key = b.ESC + "[1;" + (n + 1) + "D" : t ? r.key = b.ESC + "OD" : r.key = b.ESC + "[D";
        break;
      case 39:
        if (s15.metaKey) break;
        n ? r.key = b.ESC + "[1;" + (n + 1) + "C" : t ? r.key = b.ESC + "OC" : r.key = b.ESC + "[C";
        break;
      case 38:
        if (s15.metaKey) break;
        n ? r.key = b.ESC + "[1;" + (n + 1) + "A" : t ? r.key = b.ESC + "OA" : r.key = b.ESC + "[A";
        break;
      case 40:
        if (s15.metaKey) break;
        n ? r.key = b.ESC + "[1;" + (n + 1) + "B" : t ? r.key = b.ESC + "OB" : r.key = b.ESC + "[B";
        break;
      case 45:
        !s15.shiftKey && !s15.ctrlKey && (r.key = b.ESC + "[2~");
        break;
      case 46:
        n ? r.key = b.ESC + "[3;" + (n + 1) + "~" : r.key = b.ESC + "[3~";
        break;
      case 36:
        n ? r.key = b.ESC + "[1;" + (n + 1) + "H" : t ? r.key = b.ESC + "OH" : r.key = b.ESC + "[H";
        break;
      case 35:
        n ? r.key = b.ESC + "[1;" + (n + 1) + "F" : t ? r.key = b.ESC + "OF" : r.key = b.ESC + "[F";
        break;
      case 33:
        s15.shiftKey ? r.type = 2 : s15.ctrlKey ? r.key = b.ESC + "[5;" + (n + 1) + "~" : r.key = b.ESC + "[5~";
        break;
      case 34:
        s15.shiftKey ? r.type = 3 : s15.ctrlKey ? r.key = b.ESC + "[6;" + (n + 1) + "~" : r.key = b.ESC + "[6~";
        break;
      case 112:
        n ? r.key = b.ESC + "[1;" + (n + 1) + "P" : r.key = b.ESC + "OP";
        break;
      case 113:
        n ? r.key = b.ESC + "[1;" + (n + 1) + "Q" : r.key = b.ESC + "OQ";
        break;
      case 114:
        n ? r.key = b.ESC + "[1;" + (n + 1) + "R" : r.key = b.ESC + "OR";
        break;
      case 115:
        n ? r.key = b.ESC + "[1;" + (n + 1) + "S" : r.key = b.ESC + "OS";
        break;
      case 116:
        n ? r.key = b.ESC + "[15;" + (n + 1) + "~" : r.key = b.ESC + "[15~";
        break;
      case 117:
        n ? r.key = b.ESC + "[17;" + (n + 1) + "~" : r.key = b.ESC + "[17~";
        break;
      case 118:
        n ? r.key = b.ESC + "[18;" + (n + 1) + "~" : r.key = b.ESC + "[18~";
        break;
      case 119:
        n ? r.key = b.ESC + "[19;" + (n + 1) + "~" : r.key = b.ESC + "[19~";
        break;
      case 120:
        n ? r.key = b.ESC + "[20;" + (n + 1) + "~" : r.key = b.ESC + "[20~";
        break;
      case 121:
        n ? r.key = b.ESC + "[21;" + (n + 1) + "~" : r.key = b.ESC + "[21~";
        break;
      case 122:
        n ? r.key = b.ESC + "[23;" + (n + 1) + "~" : r.key = b.ESC + "[23~";
        break;
      case 123:
        n ? r.key = b.ESC + "[24;" + (n + 1) + "~" : r.key = b.ESC + "[24~";
        break;
      default:
        if (s15.ctrlKey && !s15.shiftKey && !s15.altKey && !s15.metaKey) s15.keyCode >= 65 && s15.keyCode <= 90 ? r.key = String.fromCharCode(s15.keyCode - 64) : s15.keyCode === 32 ? r.key = b.NUL : s15.keyCode >= 51 && s15.keyCode <= 55 ? r.key = String.fromCharCode(s15.keyCode - 51 + 27) : s15.keyCode === 56 ? r.key = b.DEL : s15.keyCode === 219 ? r.key = b.ESC : s15.keyCode === 220 ? r.key = b.FS : s15.keyCode === 221 && (r.key = b.GS);
        else if ((!e || i) && s15.altKey && !s15.metaKey) {
          let l2 = gc[s15.keyCode]?.[s15.shiftKey ? 1 : 0];
          if (l2) r.key = b.ESC + l2;
          else if (s15.keyCode >= 65 && s15.keyCode <= 90) {
            let a = s15.ctrlKey ? s15.keyCode - 64 : s15.keyCode + 32, u = String.fromCharCode(a);
            s15.shiftKey && (u = u.toUpperCase()), r.key = b.ESC + u;
          } else if (s15.keyCode === 32) r.key = b.ESC + (s15.ctrlKey ? b.NUL : " ");
          else if (s15.key === "Dead" && s15.code.startsWith("Key")) {
            let a = s15.code.slice(3, 4);
            s15.shiftKey || (a = a.toLowerCase()), r.key = b.ESC + a, r.cancel = true;
          }
        } else e && !s15.altKey && !s15.ctrlKey && !s15.shiftKey && s15.metaKey ? s15.keyCode === 65 && (r.type = 1) : s15.key && !s15.ctrlKey && !s15.altKey && !s15.metaKey && s15.keyCode >= 48 && s15.key.length === 1 ? r.key = s15.key : s15.key && s15.ctrlKey && (s15.key === "_" && (r.key = b.US), s15.key === "@" && (r.key = b.NUL));
        break;
    }
    return r;
  }
  function Ec(s15, t) {
    return s15.text === t.text && s15.range.start.x === t.range.start.x && s15.range.start.y === t.range.start.y && s15.range.end.x === t.range.end.x && s15.range.end.y === t.range.end.y;
  }
  function Tc(s15) {
    return s15.keyCode === 16 || s15.keyCode === 17 || s15.keyCode === 18;
  }
  var zs, Rl, Ll, M, S, Gs, mi, $s, _i, er, tr, ir, we, De, rt, q, js, Hn, Fn, F, rr, ge, Zs, xt, nr, H, sr, Js, Be, wt, nt, ae, Dt, ce, Qs, or, Re, lr, Wn, Bl, Un, bi, ar, Rt, cr, ro, so, At, lo, ao, oo, ur, zn, Wl, dt, hr, dr, Ee, D, ye, fe, kt, G, Ct, zl, mr, Gl, fo, $l, $, Mt, $n, po, br, Vn, gi, qn, Yn, Vl, Pt, ql, Yl, _r, v, jn, gr, Si, Eu, Tu, Ot, Ei, Bt, Ti, Sr, Iu, yu, vr, Nt, yr, xr, Ii, Zl, vo, go, Jl, Ql, ea, ta, Tr, Ir, bo, ia, $e, Ve, xe, So, ra, Xn, wr, Te, Zn, Dr, na, xu, Fe, st, sa, oa, Eo, la, wu, Du, Ru, Lu, ot, aa, yi, Jn, To, Io, yo, Qn, Rr, es, ua, ha, da, fa, ft, wo, Lr, qe, xi, Do, ma, ts, Ye, kr, ba, Ar, va, _e, Cr, Bh, be, Nh, Fh, Hh, Oo, Wh, Uh, No, Kh, zh, ss, os, wa, mt, Mr, Di, pt, Gh, Y, Da, ls, Wt, He, Q, Pr, lt, Uo, Or, cs, Ri, Br, Nr, Fr, Ca, Ut, Kt, Wr, Ur, Ma, Ko, zo, us, zr, hs, ds, Kr, zt, Gt, Gr, We, at, Li, bt, b, Ai, fs, $t, ue, he, de, J, ps, j, U, z, ve, $r, Vr, ct, Vt, Yr, ms, _s, Le, jr, jo, ki, Xr, Na, Yt, jt, Zr, bs, vs, Jr, gs, Qr, Xt, en, tn, Mi, Pi, Oi, Ss, Fa, Zo, Zt, Wa, Ua, Es, Bi, Ts, rn, Is, ys, Jt, nn, Qt, xs, on, Ds, Ya, ja, Xa, Za, Ja, ei, Hi, Wi, re, St, Ki, tl, il, Ui, Qa, ti, Rs, ln, ec, tc, ii, ic, zi, B, X, an, Ls, Ze, un, cn, ne, Je, cl, $i, hn, ks, Cs, ni, si, nc, dn, ul, hl, li, dl, Ps, fl, ai, Os, ac, se, fn, Ae, pn, Vi, uc, ci, qi, mn, pe, Yi, _n, ji, Xi, Fs, ke, hc, bn, dc, fc, mc, ut, _l, vl, gl, vn, Zi, _c, El, bc, gn, ui, Tl, Sn, gc, ee, En, Us, yl, Tn, Ks, Sc, In, xl, wl, Tt, hi, yn, xn, wn, Ji, Dn, Rn, Ln, Ic, Ue, Dl;
  var init_xterm = __esm({
    "node_modules/@xterm/xterm/lib/xterm.mjs"() {
      zs = Object.defineProperty;
      Rl = Object.getOwnPropertyDescriptor;
      Ll = (s15, t) => {
        for (var e in t) zs(s15, e, { get: t[e], enumerable: true });
      };
      M = (s15, t, e, i) => {
        for (var r = i > 1 ? void 0 : i ? Rl(t, e) : t, n = s15.length - 1, o2; n >= 0; n--) (o2 = s15[n]) && (r = (i ? o2(t, e, r) : o2(r)) || r);
        return i && r && zs(t, e, r), r;
      };
      S = (s15, t) => (e, i) => t(e, i, s15);
      Gs = "Terminal input";
      mi = { get: () => Gs, set: (s15) => Gs = s15 };
      $s = "Too much output to announce, navigate to rows manually to read";
      _i = { get: () => $s, set: (s15) => $s = s15 };
      er = class {
        constructor() {
          this._interim = 0;
        }
        clear() {
          this._interim = 0;
        }
        decode(t, e) {
          let i = t.length;
          if (!i) return 0;
          let r = 0, n = 0;
          if (this._interim) {
            let o2 = t.charCodeAt(n++);
            56320 <= o2 && o2 <= 57343 ? e[r++] = (this._interim - 55296) * 1024 + o2 - 56320 + 65536 : (e[r++] = this._interim, e[r++] = o2), this._interim = 0;
          }
          for (let o2 = n; o2 < i; ++o2) {
            let l2 = t.charCodeAt(o2);
            if (55296 <= l2 && l2 <= 56319) {
              if (++o2 >= i) return this._interim = l2, r;
              let a = t.charCodeAt(o2);
              56320 <= a && a <= 57343 ? e[r++] = (l2 - 55296) * 1024 + a - 56320 + 65536 : (e[r++] = l2, e[r++] = a);
              continue;
            }
            l2 !== 65279 && (e[r++] = l2);
          }
          return r;
        }
      };
      tr = class {
        constructor() {
          this.interim = new Uint8Array(3);
        }
        clear() {
          this.interim.fill(0);
        }
        decode(t, e) {
          let i = t.length;
          if (!i) return 0;
          let r = 0, n, o2, l2, a, u = 0, h2 = 0;
          if (this.interim[0]) {
            let _3 = false, p = this.interim[0];
            p &= (p & 224) === 192 ? 31 : (p & 240) === 224 ? 15 : 7;
            let m = 0, f;
            for (; (f = this.interim[++m] & 63) && m < 4; ) p <<= 6, p |= f;
            let A = (this.interim[0] & 224) === 192 ? 2 : (this.interim[0] & 240) === 224 ? 3 : 4, R = A - m;
            for (; h2 < R; ) {
              if (h2 >= i) return 0;
              if (f = t[h2++], (f & 192) !== 128) {
                h2--, _3 = true;
                break;
              } else this.interim[m++] = f, p <<= 6, p |= f & 63;
            }
            _3 || (A === 2 ? p < 128 ? h2-- : e[r++] = p : A === 3 ? p < 2048 || p >= 55296 && p <= 57343 || p === 65279 || (e[r++] = p) : p < 65536 || p > 1114111 || (e[r++] = p)), this.interim.fill(0);
          }
          let c = i - 4, d = h2;
          for (; d < i; ) {
            for (; d < c && !((n = t[d]) & 128) && !((o2 = t[d + 1]) & 128) && !((l2 = t[d + 2]) & 128) && !((a = t[d + 3]) & 128); ) e[r++] = n, e[r++] = o2, e[r++] = l2, e[r++] = a, d += 4;
            if (n = t[d++], n < 128) e[r++] = n;
            else if ((n & 224) === 192) {
              if (d >= i) return this.interim[0] = n, r;
              if (o2 = t[d++], (o2 & 192) !== 128) {
                d--;
                continue;
              }
              if (u = (n & 31) << 6 | o2 & 63, u < 128) {
                d--;
                continue;
              }
              e[r++] = u;
            } else if ((n & 240) === 224) {
              if (d >= i) return this.interim[0] = n, r;
              if (o2 = t[d++], (o2 & 192) !== 128) {
                d--;
                continue;
              }
              if (d >= i) return this.interim[0] = n, this.interim[1] = o2, r;
              if (l2 = t[d++], (l2 & 192) !== 128) {
                d--;
                continue;
              }
              if (u = (n & 15) << 12 | (o2 & 63) << 6 | l2 & 63, u < 2048 || u >= 55296 && u <= 57343 || u === 65279) continue;
              e[r++] = u;
            } else if ((n & 248) === 240) {
              if (d >= i) return this.interim[0] = n, r;
              if (o2 = t[d++], (o2 & 192) !== 128) {
                d--;
                continue;
              }
              if (d >= i) return this.interim[0] = n, this.interim[1] = o2, r;
              if (l2 = t[d++], (l2 & 192) !== 128) {
                d--;
                continue;
              }
              if (d >= i) return this.interim[0] = n, this.interim[1] = o2, this.interim[2] = l2, r;
              if (a = t[d++], (a & 192) !== 128) {
                d--;
                continue;
              }
              if (u = (n & 7) << 18 | (o2 & 63) << 12 | (l2 & 63) << 6 | a & 63, u < 65536 || u > 1114111) continue;
              e[r++] = u;
            }
          }
          return r;
        }
      };
      ir = "";
      we = " ";
      De = class s {
        constructor() {
          this.fg = 0;
          this.bg = 0;
          this.extended = new rt();
        }
        static toColorRGB(t) {
          return [t >>> 16 & 255, t >>> 8 & 255, t & 255];
        }
        static fromColorRGB(t) {
          return (t[0] & 255) << 16 | (t[1] & 255) << 8 | t[2] & 255;
        }
        clone() {
          let t = new s();
          return t.fg = this.fg, t.bg = this.bg, t.extended = this.extended.clone(), t;
        }
        isInverse() {
          return this.fg & 67108864;
        }
        isBold() {
          return this.fg & 134217728;
        }
        isUnderline() {
          return this.hasExtendedAttrs() && this.extended.underlineStyle !== 0 ? 1 : this.fg & 268435456;
        }
        isBlink() {
          return this.fg & 536870912;
        }
        isInvisible() {
          return this.fg & 1073741824;
        }
        isItalic() {
          return this.bg & 67108864;
        }
        isDim() {
          return this.bg & 134217728;
        }
        isStrikethrough() {
          return this.fg & 2147483648;
        }
        isProtected() {
          return this.bg & 536870912;
        }
        isOverline() {
          return this.bg & 1073741824;
        }
        getFgColorMode() {
          return this.fg & 50331648;
        }
        getBgColorMode() {
          return this.bg & 50331648;
        }
        isFgRGB() {
          return (this.fg & 50331648) === 50331648;
        }
        isBgRGB() {
          return (this.bg & 50331648) === 50331648;
        }
        isFgPalette() {
          return (this.fg & 50331648) === 16777216 || (this.fg & 50331648) === 33554432;
        }
        isBgPalette() {
          return (this.bg & 50331648) === 16777216 || (this.bg & 50331648) === 33554432;
        }
        isFgDefault() {
          return (this.fg & 50331648) === 0;
        }
        isBgDefault() {
          return (this.bg & 50331648) === 0;
        }
        isAttributeDefault() {
          return this.fg === 0 && this.bg === 0;
        }
        getFgColor() {
          switch (this.fg & 50331648) {
            case 16777216:
            case 33554432:
              return this.fg & 255;
            case 50331648:
              return this.fg & 16777215;
            default:
              return -1;
          }
        }
        getBgColor() {
          switch (this.bg & 50331648) {
            case 16777216:
            case 33554432:
              return this.bg & 255;
            case 50331648:
              return this.bg & 16777215;
            default:
              return -1;
          }
        }
        hasExtendedAttrs() {
          return this.bg & 268435456;
        }
        updateExtended() {
          this.extended.isEmpty() ? this.bg &= -268435457 : this.bg |= 268435456;
        }
        getUnderlineColor() {
          if (this.bg & 268435456 && ~this.extended.underlineColor) switch (this.extended.underlineColor & 50331648) {
            case 16777216:
            case 33554432:
              return this.extended.underlineColor & 255;
            case 50331648:
              return this.extended.underlineColor & 16777215;
            default:
              return this.getFgColor();
          }
          return this.getFgColor();
        }
        getUnderlineColorMode() {
          return this.bg & 268435456 && ~this.extended.underlineColor ? this.extended.underlineColor & 50331648 : this.getFgColorMode();
        }
        isUnderlineColorRGB() {
          return this.bg & 268435456 && ~this.extended.underlineColor ? (this.extended.underlineColor & 50331648) === 50331648 : this.isFgRGB();
        }
        isUnderlineColorPalette() {
          return this.bg & 268435456 && ~this.extended.underlineColor ? (this.extended.underlineColor & 50331648) === 16777216 || (this.extended.underlineColor & 50331648) === 33554432 : this.isFgPalette();
        }
        isUnderlineColorDefault() {
          return this.bg & 268435456 && ~this.extended.underlineColor ? (this.extended.underlineColor & 50331648) === 0 : this.isFgDefault();
        }
        getUnderlineStyle() {
          return this.fg & 268435456 ? this.bg & 268435456 ? this.extended.underlineStyle : 1 : 0;
        }
        getUnderlineVariantOffset() {
          return this.extended.underlineVariantOffset;
        }
      };
      rt = class s2 {
        constructor(t = 0, e = 0) {
          this._ext = 0;
          this._urlId = 0;
          this._ext = t, this._urlId = e;
        }
        get ext() {
          return this._urlId ? this._ext & -469762049 | this.underlineStyle << 26 : this._ext;
        }
        set ext(t) {
          this._ext = t;
        }
        get underlineStyle() {
          return this._urlId ? 5 : (this._ext & 469762048) >> 26;
        }
        set underlineStyle(t) {
          this._ext &= -469762049, this._ext |= t << 26 & 469762048;
        }
        get underlineColor() {
          return this._ext & 67108863;
        }
        set underlineColor(t) {
          this._ext &= -67108864, this._ext |= t & 67108863;
        }
        get urlId() {
          return this._urlId;
        }
        set urlId(t) {
          this._urlId = t;
        }
        get underlineVariantOffset() {
          let t = (this._ext & 3758096384) >> 29;
          return t < 0 ? t ^ 4294967288 : t;
        }
        set underlineVariantOffset(t) {
          this._ext &= 536870911, this._ext |= t << 29 & 3758096384;
        }
        clone() {
          return new s2(this._ext, this._urlId);
        }
        isEmpty() {
          return this.underlineStyle === 0 && this._urlId === 0;
        }
      };
      q = class s3 extends De {
        constructor() {
          super(...arguments);
          this.content = 0;
          this.fg = 0;
          this.bg = 0;
          this.extended = new rt();
          this.combinedData = "";
        }
        static fromCharData(e) {
          let i = new s3();
          return i.setFromCharData(e), i;
        }
        isCombined() {
          return this.content & 2097152;
        }
        getWidth() {
          return this.content >> 22;
        }
        getChars() {
          return this.content & 2097152 ? this.combinedData : this.content & 2097151 ? Ce(this.content & 2097151) : "";
        }
        getCode() {
          return this.isCombined() ? this.combinedData.charCodeAt(this.combinedData.length - 1) : this.content & 2097151;
        }
        setFromCharData(e) {
          this.fg = e[0], this.bg = 0;
          let i = false;
          if (e[1].length > 2) i = true;
          else if (e[1].length === 2) {
            let r = e[1].charCodeAt(0);
            if (55296 <= r && r <= 56319) {
              let n = e[1].charCodeAt(1);
              56320 <= n && n <= 57343 ? this.content = (r - 55296) * 1024 + n - 56320 + 65536 | e[2] << 22 : i = true;
            } else i = true;
          } else this.content = e[1].charCodeAt(0) | e[2] << 22;
          i && (this.combinedData = e[1], this.content = 2097152 | e[2] << 22);
        }
        getAsCharData() {
          return [this.fg, this.getChars(), this.getWidth(), this.getCode()];
        }
      };
      js = "di$target";
      Hn = "di$dependencies";
      Fn = /* @__PURE__ */ new Map();
      F = ie("BufferService");
      rr = ie("CoreMouseService");
      ge = ie("CoreService");
      Zs = ie("CharsetService");
      xt = ie("InstantiationService");
      nr = ie("LogService");
      H = ie("OptionsService");
      sr = ie("OscLinkService");
      Js = ie("UnicodeService");
      Be = ie("DecorationService");
      wt = class {
        constructor(t, e, i) {
          this._bufferService = t;
          this._optionsService = e;
          this._oscLinkService = i;
        }
        provideLinks(t, e) {
          let i = this._bufferService.buffer.lines.get(t - 1);
          if (!i) {
            e(void 0);
            return;
          }
          let r = [], n = this._optionsService.rawOptions.linkHandler, o2 = new q(), l2 = i.getTrimmedLength(), a = -1, u = -1, h2 = false;
          for (let c = 0; c < l2; c++) if (!(u === -1 && !i.hasContent(c))) {
            if (i.loadCell(c, o2), o2.hasExtendedAttrs() && o2.extended.urlId) if (u === -1) {
              u = c, a = o2.extended.urlId;
              continue;
            } else h2 = o2.extended.urlId !== a;
            else u !== -1 && (h2 = true);
            if (h2 || u !== -1 && c === l2 - 1) {
              let d = this._oscLinkService.getLinkData(a)?.uri;
              if (d) {
                let _3 = { start: { x: u + 1, y: t }, end: { x: c + (!h2 && c === l2 - 1 ? 1 : 0), y: t } }, p = false;
                if (!n?.allowNonHttpProtocols) try {
                  let m = new URL(d);
                  ["http:", "https:"].includes(m.protocol) || (p = true);
                } catch {
                  p = true;
                }
                p || r.push({ text: d, range: _3, activate: (m, f) => n ? n.activate(m, f, _3) : Ol(m, f), hover: (m, f) => n?.hover?.(m, f, _3), leave: (m, f) => n?.leave?.(m, f, _3) });
              }
              h2 = false, o2.hasExtendedAttrs() && o2.extended.urlId ? (u = c, a = o2.extended.urlId) : (u = -1, a = -1);
            }
          }
          e(r);
        }
      };
      wt = M([S(0, F), S(1, H), S(2, sr)], wt);
      nt = ie("CharSizeService");
      ae = ie("CoreBrowserService");
      Dt = ie("MouseService");
      ce = ie("RenderService");
      Qs = ie("SelectionService");
      or = ie("CharacterJoinerService");
      Re = ie("ThemeService");
      lr = ie("LinkProviderService");
      Wn = class {
        constructor() {
          this.listeners = [], this.unexpectedErrorHandler = function(t) {
            setTimeout(() => {
              throw t.stack ? ar.isErrorNoTelemetry(t) ? new ar(t.message + `

` + t.stack) : new Error(t.message + `

` + t.stack) : t;
            }, 0);
          };
        }
        addListener(t) {
          return this.listeners.push(t), () => {
            this._removeListener(t);
          };
        }
        emit(t) {
          this.listeners.forEach((e) => {
            e(t);
          });
        }
        _removeListener(t) {
          this.listeners.splice(this.listeners.indexOf(t), 1);
        }
        setUnexpectedErrorHandler(t) {
          this.unexpectedErrorHandler = t;
        }
        getUnexpectedErrorHandler() {
          return this.unexpectedErrorHandler;
        }
        onUnexpectedError(t) {
          this.unexpectedErrorHandler(t), this.emit(t);
        }
        onUnexpectedExternalError(t) {
          this.unexpectedErrorHandler(t);
        }
      };
      Bl = new Wn();
      Un = "Canceled";
      bi = class extends Error {
        constructor() {
          super(Un), this.name = this.message;
        }
      };
      ar = class s4 extends Error {
        constructor(t) {
          super(t), this.name = "CodeExpectedError";
        }
        static fromError(t) {
          if (t instanceof s4) return t;
          let e = new s4();
          return e.message = t.message, e.stack = t.stack, e;
        }
        static isErrorNoTelemetry(t) {
          return t.name === "CodeExpectedError";
        }
      };
      Rt = class s5 extends Error {
        constructor(t) {
          super(t || "An unexpected bug occurred."), Object.setPrototypeOf(this, s5.prototype);
        }
      };
      cr = class cr2 {
        constructor(t) {
          this._array = t;
          this._findLastMonotonousLastIdx = 0;
        }
        findLastMonotonous(t) {
          if (cr2.assertInvariants) {
            if (this._prevFindLastPredicate) {
              for (let i of this._array) if (this._prevFindLastPredicate(i) && !t(i)) throw new Error("MonotonousArray: current predicate must be weaker than (or equal to) the previous predicate.");
            }
            this._prevFindLastPredicate = t;
          }
          let e = Fl(this._array, t, this._findLastMonotonousLastIdx);
          return this._findLastMonotonousLastIdx = e + 1, e === -1 ? void 0 : this._array[e];
        }
      };
      cr.assertInvariants = false;
      ((l2) => {
        function s15(a) {
          return a < 0;
        }
        l2.isLessThan = s15;
        function t(a) {
          return a <= 0;
        }
        l2.isLessThanOrEqual = t;
        function e(a) {
          return a > 0;
        }
        l2.isGreaterThan = e;
        function i(a) {
          return a === 0;
        }
        l2.isNeitherLessOrGreaterThan = i, l2.greaterThan = 1, l2.lessThan = -1, l2.neitherLessOrGreaterThan = 0;
      })(ro ||= {});
      so = (s15, t) => s15 - t;
      At = class At2 {
        constructor(t) {
          this.iterate = t;
        }
        forEach(t) {
          this.iterate((e) => (t(e), true));
        }
        toArray() {
          let t = [];
          return this.iterate((e) => (t.push(e), true)), t;
        }
        filter(t) {
          return new At2((e) => this.iterate((i) => t(i) ? e(i) : true));
        }
        map(t) {
          return new At2((e) => this.iterate((i) => e(t(i))));
        }
        some(t) {
          let e = false;
          return this.iterate((i) => (e = t(i), !e)), e;
        }
        findFirst(t) {
          let e;
          return this.iterate((i) => t(i) ? (e = i, false) : true), e;
        }
        findLast(t) {
          let e;
          return this.iterate((i) => (t(i) && (e = i), true)), e;
        }
        findLastMaxBy(t) {
          let e, i = true;
          return this.iterate((r) => ((i || ro.isGreaterThan(t(r, e))) && (i = false, e = r), true)), e;
        }
      };
      At.empty = new At((t) => {
      });
      oo = class {
        constructor(t, e) {
          this.toKey = e;
          this._map = /* @__PURE__ */ new Map();
          this[lo] = "SetWithKey";
          for (let i of t) this.add(i);
        }
        get size() {
          return this._map.size;
        }
        add(t) {
          let e = this.toKey(t);
          return this._map.set(e, t), this;
        }
        delete(t) {
          return this._map.delete(this.toKey(t));
        }
        has(t) {
          return this._map.has(this.toKey(t));
        }
        *entries() {
          for (let t of this._map.values()) yield [t, t];
        }
        keys() {
          return this.values();
        }
        *values() {
          for (let t of this._map.values()) yield t;
        }
        clear() {
          this._map.clear();
        }
        forEach(t, e) {
          this._map.forEach((i) => t.call(e, i, i, this));
        }
        [(ao = Symbol.iterator, lo = Symbol.toStringTag, ao)]() {
          return this.values();
        }
      };
      ur = class {
        constructor() {
          this.map = /* @__PURE__ */ new Map();
        }
        add(t, e) {
          let i = this.map.get(t);
          i || (i = /* @__PURE__ */ new Set(), this.map.set(t, i)), i.add(e);
        }
        delete(t, e) {
          let i = this.map.get(t);
          i && (i.delete(e), i.size === 0 && this.map.delete(t));
        }
        forEach(t, e) {
          let i = this.map.get(t);
          i && i.forEach(e);
        }
        get(t) {
          let e = this.map.get(t);
          return e || /* @__PURE__ */ new Set();
        }
      };
      ((O) => {
        function s15(I) {
          return I && typeof I == "object" && typeof I[Symbol.iterator] == "function";
        }
        O.is = s15;
        let t = Object.freeze([]);
        function e() {
          return t;
        }
        O.empty = e;
        function* i(I) {
          yield I;
        }
        O.single = i;
        function r(I) {
          return s15(I) ? I : i(I);
        }
        O.wrap = r;
        function n(I) {
          return I || t;
        }
        O.from = n;
        function* o2(I) {
          for (let k2 = I.length - 1; k2 >= 0; k2--) yield I[k2];
        }
        O.reverse = o2;
        function l2(I) {
          return !I || I[Symbol.iterator]().next().done === true;
        }
        O.isEmpty = l2;
        function a(I) {
          return I[Symbol.iterator]().next().value;
        }
        O.first = a;
        function u(I, k2) {
          let P = 0;
          for (let oe of I) if (k2(oe, P++)) return true;
          return false;
        }
        O.some = u;
        function h2(I, k2) {
          for (let P of I) if (k2(P)) return P;
        }
        O.find = h2;
        function* c(I, k2) {
          for (let P of I) k2(P) && (yield P);
        }
        O.filter = c;
        function* d(I, k2) {
          let P = 0;
          for (let oe of I) yield k2(oe, P++);
        }
        O.map = d;
        function* _3(I, k2) {
          let P = 0;
          for (let oe of I) yield* k2(oe, P++);
        }
        O.flatMap = _3;
        function* p(...I) {
          for (let k2 of I) yield* k2;
        }
        O.concat = p;
        function m(I, k2, P) {
          let oe = P;
          for (let Me of I) oe = k2(oe, Me);
          return oe;
        }
        O.reduce = m;
        function* f(I, k2, P = I.length) {
          for (k2 < 0 && (k2 += I.length), P < 0 ? P += I.length : P > I.length && (P = I.length); k2 < P; k2++) yield I[k2];
        }
        O.slice = f;
        function A(I, k2 = Number.POSITIVE_INFINITY) {
          let P = [];
          if (k2 === 0) return [P, I];
          let oe = I[Symbol.iterator]();
          for (let Me = 0; Me < k2; Me++) {
            let Pe = oe.next();
            if (Pe.done) return [P, O.empty()];
            P.push(Pe.value);
          }
          return [P, { [Symbol.iterator]() {
            return oe;
          } }];
        }
        O.consume = A;
        async function R(I) {
          let k2 = [];
          for await (let P of I) k2.push(P);
          return Promise.resolve(k2);
        }
        O.asyncToArray = R;
      })(zn ||= {});
      Wl = false;
      dt = null;
      hr = class hr2 {
        constructor() {
          this.livingDisposables = /* @__PURE__ */ new Map();
        }
        getDisposableData(t) {
          let e = this.livingDisposables.get(t);
          return e || (e = { parent: null, source: null, isSingleton: false, value: t, idx: hr2.idx++ }, this.livingDisposables.set(t, e)), e;
        }
        trackDisposable(t) {
          let e = this.getDisposableData(t);
          e.source || (e.source = new Error().stack);
        }
        setParent(t, e) {
          let i = this.getDisposableData(t);
          i.parent = e;
        }
        markAsDisposed(t) {
          this.livingDisposables.delete(t);
        }
        markAsSingleton(t) {
          this.getDisposableData(t).isSingleton = true;
        }
        getRootParent(t, e) {
          let i = e.get(t);
          if (i) return i;
          let r = t.parent ? this.getRootParent(this.getDisposableData(t.parent), e) : t;
          return e.set(t, r), r;
        }
        getTrackedDisposables() {
          let t = /* @__PURE__ */ new Map();
          return [...this.livingDisposables.entries()].filter(([, i]) => i.source !== null && !this.getRootParent(i, t).isSingleton).flatMap(([i]) => i);
        }
        computeLeakingDisposables(t = 10, e) {
          let i;
          if (e) i = e;
          else {
            let a = /* @__PURE__ */ new Map(), u = [...this.livingDisposables.values()].filter((c) => c.source !== null && !this.getRootParent(c, a).isSingleton);
            if (u.length === 0) return;
            let h2 = new Set(u.map((c) => c.value));
            if (i = u.filter((c) => !(c.parent && h2.has(c.parent))), i.length === 0) throw new Error("There are cyclic diposable chains!");
          }
          if (!i) return;
          function r(a) {
            function u(c, d) {
              for (; c.length > 0 && d.some((_3) => typeof _3 == "string" ? _3 === c[0] : c[0].match(_3)); ) c.shift();
            }
            let h2 = a.source.split(`
`).map((c) => c.trim().replace("at ", "")).filter((c) => c !== "");
            return u(h2, ["Error", /^trackDisposable \(.*\)$/, /^DisposableTracker.trackDisposable \(.*\)$/]), h2.reverse();
          }
          let n = new ur();
          for (let a of i) {
            let u = r(a);
            for (let h2 = 0; h2 <= u.length; h2++) n.add(u.slice(0, h2).join(`
`), a);
          }
          i.sort(no((a) => a.idx, so));
          let o2 = "", l2 = 0;
          for (let a of i.slice(0, t)) {
            l2++;
            let u = r(a), h2 = [];
            for (let c = 0; c < u.length; c++) {
              let d = u[c];
              d = `(shared with ${n.get(u.slice(0, c + 1).join(`
`)).size}/${i.length} leaks) at ${d}`;
              let p = n.get(u.slice(0, c).join(`
`)), m = co([...p].map((f) => r(f)[c]), (f) => f);
              delete m[u[c]];
              for (let [f, A] of Object.entries(m)) h2.unshift(`    - stacktraces of ${A.length} other leaks continue with ${f}`);
              h2.unshift(d);
            }
            o2 += `


==================== Leaking disposable ${l2}/${i.length}: ${a.value.constructor.name} ====================
${h2.join(`
`)}
============================================================

`;
          }
          return i.length > t && (o2 += `


... and ${i.length - t} more leaking disposables

`), { leaks: i, details: o2 };
        }
      };
      hr.idx = 0;
      if (Wl) {
        let s15 = "__is_disposable_tracked__";
        Ul(new class {
          trackDisposable(t) {
            let e = new Error("Potentially leaked disposable").stack;
            setTimeout(() => {
              t[s15] || console.log(e);
            }, 3e3);
          }
          setParent(t, e) {
            if (t && t !== D.None) try {
              t[s15] = true;
            } catch {
            }
          }
          markAsDisposed(t) {
            if (t && t !== D.None) try {
              t[s15] = true;
            } catch {
            }
          }
          markAsSingleton(t) {
          }
        }());
      }
      dr = class dr2 {
        constructor() {
          this._toDispose = /* @__PURE__ */ new Set();
          this._isDisposed = false;
          fr(this);
        }
        dispose() {
          this._isDisposed || (pr(this), this._isDisposed = true, this.clear());
        }
        get isDisposed() {
          return this._isDisposed;
        }
        clear() {
          if (this._toDispose.size !== 0) try {
            Ne(this._toDispose);
          } finally {
            this._toDispose.clear();
          }
        }
        add(t) {
          if (!t) return t;
          if (t === this) throw new Error("Cannot register a disposable on itself!");
          return vi(t, this), this._isDisposed ? dr2.DISABLE_DISPOSED_WARNING || console.warn(new Error("Trying to add a disposable to a DisposableStore that has already been disposed of. The added object will be leaked!").stack) : this._toDispose.add(t), t;
        }
        delete(t) {
          if (t) {
            if (t === this) throw new Error("Cannot dispose a disposable on itself!");
            this._toDispose.delete(t), t.dispose();
          }
        }
        deleteAndLeak(t) {
          t && this._toDispose.has(t) && (this._toDispose.delete(t), vi(t, null));
        }
      };
      dr.DISABLE_DISPOSED_WARNING = false;
      Ee = dr;
      D = class {
        constructor() {
          this._store = new Ee();
          fr(this), vi(this._store, this);
        }
        dispose() {
          pr(this), this._store.dispose();
        }
        _register(t) {
          if (t === this) throw new Error("Cannot register a disposable on itself!");
          return this._store.add(t);
        }
      };
      D.None = Object.freeze({ dispose() {
      } });
      ye = class {
        constructor() {
          this._isDisposed = false;
          fr(this);
        }
        get value() {
          return this._isDisposed ? void 0 : this._value;
        }
        set value(t) {
          this._isDisposed || t === this._value || (this._value?.dispose(), t && vi(t, this), this._value = t);
        }
        clear() {
          this.value = void 0;
        }
        dispose() {
          this._isDisposed = true, pr(this), this._value?.dispose(), this._value = void 0;
        }
        clearAndLeak() {
          let t = this._value;
          return this._value = void 0, t && vi(t, null), t;
        }
      };
      fe = typeof window == "object" ? window : globalThis;
      kt = class kt2 {
        constructor(t) {
          this.element = t, this.next = kt2.Undefined, this.prev = kt2.Undefined;
        }
      };
      kt.Undefined = new kt(void 0);
      G = kt;
      Ct = class {
        constructor() {
          this._first = G.Undefined;
          this._last = G.Undefined;
          this._size = 0;
        }
        get size() {
          return this._size;
        }
        isEmpty() {
          return this._first === G.Undefined;
        }
        clear() {
          let t = this._first;
          for (; t !== G.Undefined; ) {
            let e = t.next;
            t.prev = G.Undefined, t.next = G.Undefined, t = e;
          }
          this._first = G.Undefined, this._last = G.Undefined, this._size = 0;
        }
        unshift(t) {
          return this._insert(t, false);
        }
        push(t) {
          return this._insert(t, true);
        }
        _insert(t, e) {
          let i = new G(t);
          if (this._first === G.Undefined) this._first = i, this._last = i;
          else if (e) {
            let n = this._last;
            this._last = i, i.prev = n, n.next = i;
          } else {
            let n = this._first;
            this._first = i, i.next = n, n.prev = i;
          }
          this._size += 1;
          let r = false;
          return () => {
            r || (r = true, this._remove(i));
          };
        }
        shift() {
          if (this._first !== G.Undefined) {
            let t = this._first.element;
            return this._remove(this._first), t;
          }
        }
        pop() {
          if (this._last !== G.Undefined) {
            let t = this._last.element;
            return this._remove(this._last), t;
          }
        }
        _remove(t) {
          if (t.prev !== G.Undefined && t.next !== G.Undefined) {
            let e = t.prev;
            e.next = t.next, t.next.prev = e;
          } else t.prev === G.Undefined && t.next === G.Undefined ? (this._first = G.Undefined, this._last = G.Undefined) : t.next === G.Undefined ? (this._last = this._last.prev, this._last.next = G.Undefined) : t.prev === G.Undefined && (this._first = this._first.next, this._first.prev = G.Undefined);
          this._size -= 1;
        }
        *[Symbol.iterator]() {
          let t = this._first;
          for (; t !== G.Undefined; ) yield t.element, t = t.next;
        }
      };
      zl = globalThis.performance && typeof globalThis.performance.now == "function";
      mr = class s6 {
        static create(t) {
          return new s6(t);
        }
        constructor(t) {
          this._now = zl && t === false ? Date.now : globalThis.performance.now.bind(globalThis.performance), this._startTime = this._now(), this._stopTime = -1;
        }
        stop() {
          this._stopTime = this._now();
        }
        reset() {
          this._startTime = this._now(), this._stopTime = -1;
        }
        elapsed() {
          return this._stopTime !== -1 ? this._stopTime - this._startTime : this._now() - this._startTime;
        }
      };
      Gl = false;
      fo = false;
      $l = false;
      ((Qe) => {
        Qe.None = () => D.None;
        function t(y) {
          if ($l) {
            let { onDidAddListener: T } = y, g2 = gi.create(), w2 = 0;
            y.onDidAddListener = () => {
              ++w2 === 2 && (console.warn("snapshotted emitter LIKELY used public and SHOULD HAVE BEEN created with DisposableStore. snapshotted here"), g2.print()), T?.();
            };
          }
        }
        function e(y, T) {
          return d(y, () => {
          }, 0, void 0, true, void 0, T);
        }
        Qe.defer = e;
        function i(y) {
          return (T, g2 = null, w2) => {
            let E = false, x;
            return x = y((N) => {
              if (!E) return x ? x.dispose() : E = true, T.call(g2, N);
            }, null, w2), E && x.dispose(), x;
          };
        }
        Qe.once = i;
        function r(y, T, g2) {
          return h2((w2, E = null, x) => y((N) => w2.call(E, T(N)), null, x), g2);
        }
        Qe.map = r;
        function n(y, T, g2) {
          return h2((w2, E = null, x) => y((N) => {
            T(N), w2.call(E, N);
          }, null, x), g2);
        }
        Qe.forEach = n;
        function o2(y, T, g2) {
          return h2((w2, E = null, x) => y((N) => T(N) && w2.call(E, N), null, x), g2);
        }
        Qe.filter = o2;
        function l2(y) {
          return y;
        }
        Qe.signal = l2;
        function a(...y) {
          return (T, g2 = null, w2) => {
            let E = ho(...y.map((x) => x((N) => T.call(g2, N))));
            return c(E, w2);
          };
        }
        Qe.any = a;
        function u(y, T, g2, w2) {
          let E = g2;
          return r(y, (x) => (E = T(E, x), E), w2);
        }
        Qe.reduce = u;
        function h2(y, T) {
          let g2, w2 = { onWillAddFirstListener() {
            g2 = y(E.fire, E);
          }, onDidRemoveLastListener() {
            g2?.dispose();
          } };
          T || t(w2);
          let E = new v(w2);
          return T?.add(E), E.event;
        }
        function c(y, T) {
          return T instanceof Array ? T.push(y) : T && T.add(y), y;
        }
        function d(y, T, g2 = 100, w2 = false, E = false, x, N) {
          let Z, te, Oe, ze = 0, le, et = { leakWarningThreshold: x, onWillAddFirstListener() {
            Z = y((ht) => {
              ze++, te = T(te, ht), w2 && !Oe && (me.fire(te), te = void 0), le = () => {
                let fi = te;
                te = void 0, Oe = void 0, (!w2 || ze > 1) && me.fire(fi), ze = 0;
              }, typeof g2 == "number" ? (clearTimeout(Oe), Oe = setTimeout(le, g2)) : Oe === void 0 && (Oe = 0, queueMicrotask(le));
            });
          }, onWillRemoveListener() {
            E && ze > 0 && le?.();
          }, onDidRemoveLastListener() {
            le = void 0, Z.dispose();
          } };
          N || t(et);
          let me = new v(et);
          return N?.add(me), me.event;
        }
        Qe.debounce = d;
        function _3(y, T = 0, g2) {
          return Qe.debounce(y, (w2, E) => w2 ? (w2.push(E), w2) : [E], T, void 0, true, void 0, g2);
        }
        Qe.accumulate = _3;
        function p(y, T = (w2, E) => w2 === E, g2) {
          let w2 = true, E;
          return o2(y, (x) => {
            let N = w2 || !T(x, E);
            return w2 = false, E = x, N;
          }, g2);
        }
        Qe.latch = p;
        function m(y, T, g2) {
          return [Qe.filter(y, T, g2), Qe.filter(y, (w2) => !T(w2), g2)];
        }
        Qe.split = m;
        function f(y, T = false, g2 = [], w2) {
          let E = g2.slice(), x = y((te) => {
            E ? E.push(te) : Z.fire(te);
          });
          w2 && w2.add(x);
          let N = () => {
            E?.forEach((te) => Z.fire(te)), E = null;
          }, Z = new v({ onWillAddFirstListener() {
            x || (x = y((te) => Z.fire(te)), w2 && w2.add(x));
          }, onDidAddFirstListener() {
            E && (T ? setTimeout(N) : N());
          }, onDidRemoveLastListener() {
            x && x.dispose(), x = null;
          } });
          return w2 && w2.add(Z), Z.event;
        }
        Qe.buffer = f;
        function A(y, T) {
          return (w2, E, x) => {
            let N = T(new O());
            return y(function(Z) {
              let te = N.evaluate(Z);
              te !== R && w2.call(E, te);
            }, void 0, x);
          };
        }
        Qe.chain = A;
        let R = /* @__PURE__ */ Symbol("HaltChainable");
        class O {
          constructor() {
            this.steps = [];
          }
          map(T) {
            return this.steps.push(T), this;
          }
          forEach(T) {
            return this.steps.push((g2) => (T(g2), g2)), this;
          }
          filter(T) {
            return this.steps.push((g2) => T(g2) ? g2 : R), this;
          }
          reduce(T, g2) {
            let w2 = g2;
            return this.steps.push((E) => (w2 = T(w2, E), w2)), this;
          }
          latch(T = (g2, w2) => g2 === w2) {
            let g2 = true, w2;
            return this.steps.push((E) => {
              let x = g2 || !T(E, w2);
              return g2 = false, w2 = E, x ? E : R;
            }), this;
          }
          evaluate(T) {
            for (let g2 of this.steps) if (T = g2(T), T === R) break;
            return T;
          }
        }
        function I(y, T, g2 = (w2) => w2) {
          let w2 = (...Z) => N.fire(g2(...Z)), E = () => y.on(T, w2), x = () => y.removeListener(T, w2), N = new v({ onWillAddFirstListener: E, onDidRemoveLastListener: x });
          return N.event;
        }
        Qe.fromNodeEventEmitter = I;
        function k2(y, T, g2 = (w2) => w2) {
          let w2 = (...Z) => N.fire(g2(...Z)), E = () => y.addEventListener(T, w2), x = () => y.removeEventListener(T, w2), N = new v({ onWillAddFirstListener: E, onDidRemoveLastListener: x });
          return N.event;
        }
        Qe.fromDOMEventEmitter = k2;
        function P(y) {
          return new Promise((T) => i(y)(T));
        }
        Qe.toPromise = P;
        function oe(y) {
          let T = new v();
          return y.then((g2) => {
            T.fire(g2);
          }, () => {
            T.fire(void 0);
          }).finally(() => {
            T.dispose();
          }), T.event;
        }
        Qe.fromPromise = oe;
        function Me(y, T) {
          return y((g2) => T.fire(g2));
        }
        Qe.forward = Me;
        function Pe(y, T, g2) {
          return T(g2), y((w2) => T(w2));
        }
        Qe.runAndSubscribe = Pe;
        class Ke {
          constructor(T, g2) {
            this._observable = T;
            this._counter = 0;
            this._hasChanged = false;
            let w2 = { onWillAddFirstListener: () => {
              T.addObserver(this);
            }, onDidRemoveLastListener: () => {
              T.removeObserver(this);
            } };
            g2 || t(w2), this.emitter = new v(w2), g2 && g2.add(this.emitter);
          }
          beginUpdate(T) {
            this._counter++;
          }
          handlePossibleChange(T) {
          }
          handleChange(T, g2) {
            this._hasChanged = true;
          }
          endUpdate(T) {
            this._counter--, this._counter === 0 && (this._observable.reportChanges(), this._hasChanged && (this._hasChanged = false, this.emitter.fire(this._observable.get())));
          }
        }
        function di(y, T) {
          return new Ke(y, T).emitter.event;
        }
        Qe.fromObservable = di;
        function V(y) {
          return (T, g2, w2) => {
            let E = 0, x = false, N = { beginUpdate() {
              E++;
            }, endUpdate() {
              E--, E === 0 && (y.reportChanges(), x && (x = false, T.call(g2)));
            }, handlePossibleChange() {
            }, handleChange() {
              x = true;
            } };
            y.addObserver(N), y.reportChanges();
            let Z = { dispose() {
              y.removeObserver(N);
            } };
            return w2 instanceof Ee ? w2.add(Z) : Array.isArray(w2) && w2.push(Z), Z;
          };
        }
        Qe.fromObservableLight = V;
      })($ ||= {});
      Mt = class Mt2 {
        constructor(t) {
          this.listenerCount = 0;
          this.invocationCount = 0;
          this.elapsedOverall = 0;
          this.durations = [];
          this.name = `${t}_${Mt2._idPool++}`, Mt2.all.add(this);
        }
        start(t) {
          this._stopWatch = new mr(), this.listenerCount = t;
        }
        stop() {
          if (this._stopWatch) {
            let t = this._stopWatch.elapsed();
            this.durations.push(t), this.elapsedOverall += t, this.invocationCount += 1, this._stopWatch = void 0;
          }
        }
      };
      Mt.all = /* @__PURE__ */ new Set(), Mt._idPool = 0;
      $n = Mt;
      po = -1;
      br = class br2 {
        constructor(t, e, i = (br2._idPool++).toString(16).padStart(3, "0")) {
          this._errorHandler = t;
          this.threshold = e;
          this.name = i;
          this._warnCountdown = 0;
        }
        dispose() {
          this._stacks?.clear();
        }
        check(t, e) {
          let i = this.threshold;
          if (i <= 0 || e < i) return;
          this._stacks || (this._stacks = /* @__PURE__ */ new Map());
          let r = this._stacks.get(t.value) || 0;
          if (this._stacks.set(t.value, r + 1), this._warnCountdown -= 1, this._warnCountdown <= 0) {
            this._warnCountdown = i * 0.5;
            let [n, o2] = this.getMostFrequentStack(), l2 = `[${this.name}] potential listener LEAK detected, having ${e} listeners already. MOST frequent listener (${o2}):`;
            console.warn(l2), console.warn(n);
            let a = new qn(l2, n);
            this._errorHandler(a);
          }
          return () => {
            let n = this._stacks.get(t.value) || 0;
            this._stacks.set(t.value, n - 1);
          };
        }
        getMostFrequentStack() {
          if (!this._stacks) return;
          let t, e = 0;
          for (let [i, r] of this._stacks) (!t || e < r) && (t = [i, r], e = r);
          return t;
        }
      };
      br._idPool = 1;
      Vn = br;
      gi = class s7 {
        constructor(t) {
          this.value = t;
        }
        static create() {
          let t = new Error();
          return new s7(t.stack ?? "");
        }
        print() {
          console.warn(this.value.split(`
`).slice(2).join(`
`));
        }
      };
      qn = class extends Error {
        constructor(t, e) {
          super(t), this.name = "ListenerLeakError", this.stack = e;
        }
      };
      Yn = class extends Error {
        constructor(t, e) {
          super(t), this.name = "ListenerRefusalError", this.stack = e;
        }
      };
      Vl = 0;
      Pt = class {
        constructor(t) {
          this.value = t;
          this.id = Vl++;
        }
      };
      ql = 2;
      Yl = (s15, t) => {
        if (s15 instanceof Pt) t(s15);
        else for (let e = 0; e < s15.length; e++) {
          let i = s15[e];
          i && t(i);
        }
      };
      if (Gl) {
        let s15 = [];
        setInterval(() => {
          s15.length !== 0 && (console.warn("[LEAKING LISTENERS] GC'ed these listeners that were NOT yet disposed:"), console.warn(s15.join(`
`)), s15.length = 0);
        }, 3e3), _r = new FinalizationRegistry((t) => {
          typeof t == "string" && s15.push(t);
        });
      }
      v = class {
        constructor(t) {
          this._size = 0;
          this._options = t, this._leakageMon = po > 0 || this._options?.leakWarningThreshold ? new Vn(t?.onListenerError ?? Lt, this._options?.leakWarningThreshold ?? po) : void 0, this._perfMon = this._options?._profName ? new $n(this._options._profName) : void 0, this._deliveryQueue = this._options?.deliveryQueue;
        }
        dispose() {
          if (!this._disposed) {
            if (this._disposed = true, this._deliveryQueue?.current === this && this._deliveryQueue.reset(), this._listeners) {
              if (fo) {
                let t = this._listeners;
                queueMicrotask(() => {
                  Yl(t, (e) => e.stack?.print());
                });
              }
              this._listeners = void 0, this._size = 0;
            }
            this._options?.onDidRemoveLastListener?.(), this._leakageMon?.dispose();
          }
        }
        get event() {
          return this._event ??= (t, e, i) => {
            if (this._leakageMon && this._size > this._leakageMon.threshold ** 2) {
              let a = `[${this._leakageMon.name}] REFUSES to accept new listeners because it exceeded its threshold by far (${this._size} vs ${this._leakageMon.threshold})`;
              console.warn(a);
              let u = this._leakageMon.getMostFrequentStack() ?? ["UNKNOWN stack", -1], h2 = new Yn(`${a}. HINT: Stack shows most frequent listener (${u[1]}-times)`, u[0]);
              return (this._options?.onListenerError || Lt)(h2), D.None;
            }
            if (this._disposed) return D.None;
            e && (t = t.bind(e));
            let r = new Pt(t), n, o2;
            this._leakageMon && this._size >= Math.ceil(this._leakageMon.threshold * 0.2) && (r.stack = gi.create(), n = this._leakageMon.check(r.stack, this._size + 1)), fo && (r.stack = o2 ?? gi.create()), this._listeners ? this._listeners instanceof Pt ? (this._deliveryQueue ??= new jn(), this._listeners = [this._listeners, r]) : this._listeners.push(r) : (this._options?.onWillAddFirstListener?.(this), this._listeners = r, this._options?.onDidAddFirstListener?.(this)), this._size++;
            let l2 = C(() => {
              _r?.unregister(l2), n?.(), this._removeListener(r);
            });
            if (i instanceof Ee ? i.add(l2) : Array.isArray(i) && i.push(l2), _r) {
              let a = new Error().stack.split(`
`).slice(2, 3).join(`
`).trim(), u = /(file:|vscode-file:\/\/vscode-app)?(\/[^:]*:\d+:\d+)/.exec(a);
              _r.register(l2, u?.[2] ?? a, l2);
            }
            return l2;
          }, this._event;
        }
        _removeListener(t) {
          if (this._options?.onWillRemoveListener?.(this), !this._listeners) return;
          if (this._size === 1) {
            this._listeners = void 0, this._options?.onDidRemoveLastListener?.(this), this._size = 0;
            return;
          }
          let e = this._listeners, i = e.indexOf(t);
          if (i === -1) throw console.log("disposed?", this._disposed), console.log("size?", this._size), console.log("arr?", JSON.stringify(this._listeners)), new Error("Attempted to dispose unknown listener");
          this._size--, e[i] = void 0;
          let r = this._deliveryQueue.current === this;
          if (this._size * ql <= e.length) {
            let n = 0;
            for (let o2 = 0; o2 < e.length; o2++) e[o2] ? e[n++] = e[o2] : r && (this._deliveryQueue.end--, n < this._deliveryQueue.i && this._deliveryQueue.i--);
            e.length = n;
          }
        }
        _deliver(t, e) {
          if (!t) return;
          let i = this._options?.onListenerError || Lt;
          if (!i) {
            t.value(e);
            return;
          }
          try {
            t.value(e);
          } catch (r) {
            i(r);
          }
        }
        _deliverQueue(t) {
          let e = t.current._listeners;
          for (; t.i < t.end; ) this._deliver(e[t.i++], t.value);
          t.reset();
        }
        fire(t) {
          if (this._deliveryQueue?.current && (this._deliverQueue(this._deliveryQueue), this._perfMon?.stop()), this._perfMon?.start(this._size), this._listeners) if (this._listeners instanceof Pt) this._deliver(this._listeners, t);
          else {
            let e = this._deliveryQueue;
            e.enqueue(this, t, this._listeners.length), this._deliverQueue(e);
          }
          this._perfMon?.stop();
        }
        hasListeners() {
          return this._size > 0;
        }
      };
      jn = class {
        constructor() {
          this.i = -1;
          this.end = 0;
        }
        enqueue(t, e, i) {
          this.i = 0, this.end = i, this.current = t, this.value = e;
        }
        reset() {
          this.i = this.end, this.current = void 0, this.value = void 0;
        }
      };
      gr = class gr2 {
        constructor() {
          this.mapWindowIdToZoomLevel = /* @__PURE__ */ new Map();
          this._onDidChangeZoomLevel = new v();
          this.onDidChangeZoomLevel = this._onDidChangeZoomLevel.event;
          this.mapWindowIdToZoomFactor = /* @__PURE__ */ new Map();
          this._onDidChangeFullscreen = new v();
          this.onDidChangeFullscreen = this._onDidChangeFullscreen.event;
          this.mapWindowIdToFullScreen = /* @__PURE__ */ new Map();
        }
        getZoomLevel(t) {
          return this.mapWindowIdToZoomLevel.get(this.getWindowId(t)) ?? 0;
        }
        setZoomLevel(t, e) {
          if (this.getZoomLevel(e) === t) return;
          let i = this.getWindowId(e);
          this.mapWindowIdToZoomLevel.set(i, t), this._onDidChangeZoomLevel.fire(i);
        }
        getZoomFactor(t) {
          return this.mapWindowIdToZoomFactor.get(this.getWindowId(t)) ?? 1;
        }
        setZoomFactor(t, e) {
          this.mapWindowIdToZoomFactor.set(this.getWindowId(e), t);
        }
        setFullscreen(t, e) {
          if (this.isFullscreen(e) === t) return;
          let i = this.getWindowId(e);
          this.mapWindowIdToFullScreen.set(i, t), this._onDidChangeFullscreen.fire(i);
        }
        isFullscreen(t) {
          return !!this.mapWindowIdToFullScreen.get(this.getWindowId(t));
        }
        getWindowId(t) {
          return t.vscodeWindowId;
        }
      };
      gr.INSTANCE = new gr();
      Si = gr;
      Eu = Si.INSTANCE.onDidChangeZoomLevel;
      Tu = Si.INSTANCE.onDidChangeFullscreen;
      Ot = typeof navigator == "object" ? navigator.userAgent : "";
      Ei = Ot.indexOf("Firefox") >= 0;
      Bt = Ot.indexOf("AppleWebKit") >= 0;
      Ti = Ot.indexOf("Chrome") >= 0;
      Sr = !Ti && Ot.indexOf("Safari") >= 0;
      Iu = Ot.indexOf("Electron/") >= 0;
      yu = Ot.indexOf("Android") >= 0;
      vr = false;
      if (typeof fe.matchMedia == "function") {
        let s15 = fe.matchMedia("(display-mode: standalone) or (display-mode: window-controls-overlay)"), t = fe.matchMedia("(display-mode: fullscreen)");
        vr = s15.matches, Xl(fe, s15, ({ matches: e }) => {
          vr && t.matches || (vr = e);
        });
      }
      Nt = "en";
      yr = false;
      xr = false;
      Ii = false;
      Zl = false;
      vo = false;
      go = false;
      Jl = false;
      Ql = false;
      ea = false;
      ta = false;
      Ir = Nt;
      bo = Nt;
      Ve = globalThis;
      typeof Ve.vscode < "u" && typeof Ve.vscode.process < "u" ? xe = Ve.vscode.process : typeof process < "u" && typeof process?.versions?.node == "string" && (xe = process);
      So = typeof xe?.versions?.electron == "string";
      ra = So && xe?.type === "renderer";
      if (typeof xe == "object") {
        yr = xe.platform === "win32", xr = xe.platform === "darwin", Ii = xe.platform === "linux", Zl = Ii && !!xe.env.SNAP && !!xe.env.SNAP_REVISION, Jl = So, ea = !!xe.env.CI || !!xe.env.BUILD_ARTIFACTSTAGINGDIRECTORY, Tr = Nt, Ir = Nt;
        let s15 = xe.env.VSCODE_NLS_CONFIG;
        if (s15) try {
          let t = JSON.parse(s15);
          Tr = t.userLocale, bo = t.osLocale, Ir = t.resolvedLanguage || Nt, ia = t.languagePack?.translationsConfigFile;
        } catch {
        }
        vo = true;
      } else typeof navigator == "object" && !ra ? ($e = navigator.userAgent, yr = $e.indexOf("Windows") >= 0, xr = $e.indexOf("Macintosh") >= 0, Ql = ($e.indexOf("Macintosh") >= 0 || $e.indexOf("iPad") >= 0 || $e.indexOf("iPhone") >= 0) && !!navigator.maxTouchPoints && navigator.maxTouchPoints > 0, Ii = $e.indexOf("Linux") >= 0, ta = $e?.indexOf("Mobi") >= 0, go = true, Ir = globalThis._VSCODE_NLS_LANGUAGE || Nt, Tr = navigator.language.toLowerCase(), bo = Tr) : console.error("Unable to resolve platform.");
      Xn = 0;
      xr ? Xn = 1 : yr ? Xn = 3 : Ii && (Xn = 2);
      wr = yr;
      Te = xr;
      Zn = Ii;
      Dr = vo;
      na = go && typeof Ve.importScripts == "function";
      xu = na ? Ve.origin : void 0;
      Fe = $e;
      st = Ir;
      ((i) => {
        function s15() {
          return st;
        }
        i.value = s15;
        function t() {
          return st.length === 2 ? st === "en" : st.length >= 3 ? st[0] === "e" && st[1] === "n" && st[2] === "-" : false;
        }
        i.isDefaultVariant = t;
        function e() {
          return st === "en";
        }
        i.isDefault = e;
      })(sa ||= {});
      oa = typeof Ve.postMessage == "function" && !Ve.importScripts;
      Eo = (() => {
        if (oa) {
          let s15 = [];
          Ve.addEventListener("message", (e) => {
            if (e.data && e.data.vscodeScheduleAsyncWork) for (let i = 0, r = s15.length; i < r; i++) {
              let n = s15[i];
              if (n.id === e.data.vscodeScheduleAsyncWork) {
                s15.splice(i, 1), n.callback();
                return;
              }
            }
          });
          let t = 0;
          return (e) => {
            let i = ++t;
            s15.push({ id: i, callback: e }), Ve.postMessage({ vscodeScheduleAsyncWork: i }, "*");
          };
        }
        return (s15) => setTimeout(s15);
      })();
      la = !!(Fe && Fe.indexOf("Chrome") >= 0);
      wu = !!(Fe && Fe.indexOf("Firefox") >= 0);
      Du = !!(!la && Fe && Fe.indexOf("Safari") >= 0);
      Ru = !!(Fe && Fe.indexOf("Edg/") >= 0);
      Lu = !!(Fe && Fe.indexOf("Android") >= 0);
      ot = typeof navigator == "object" ? navigator : {};
      aa = { clipboard: { writeText: Dr || document.queryCommandSupported && document.queryCommandSupported("copy") || !!(ot && ot.clipboard && ot.clipboard.writeText), readText: Dr || !!(ot && ot.clipboard && ot.clipboard.readText) }, keyboard: Dr || _o() ? 0 : ot.keyboard || Sr ? 1 : 2, touch: "ontouchstart" in fe || ot.maxTouchPoints > 0, pointerEvents: fe.PointerEvent && ("ontouchstart" in fe || navigator.maxTouchPoints > 0) };
      yi = class {
        constructor() {
          this._keyCodeToStr = [], this._strToKeyCode = /* @__PURE__ */ Object.create(null);
        }
        define(t, e) {
          this._keyCodeToStr[t] = e, this._strToKeyCode[e.toLowerCase()] = t;
        }
        keyCodeToStr(t) {
          return this._keyCodeToStr[t];
        }
        strToKeyCode(t) {
          return this._strToKeyCode[t.toLowerCase()] || 0;
        }
      };
      Jn = new yi();
      To = new yi();
      Io = new yi();
      yo = new Array(230);
      ((o2) => {
        function s15(l2) {
          return Jn.keyCodeToStr(l2);
        }
        o2.toString = s15;
        function t(l2) {
          return Jn.strToKeyCode(l2);
        }
        o2.fromString = t;
        function e(l2) {
          return To.keyCodeToStr(l2);
        }
        o2.toUserSettingsUS = e;
        function i(l2) {
          return Io.keyCodeToStr(l2);
        }
        o2.toUserSettingsGeneral = i;
        function r(l2) {
          return To.strToKeyCode(l2) || Io.strToKeyCode(l2);
        }
        o2.fromUserSettings = r;
        function n(l2) {
          if (l2 >= 98 && l2 <= 113) return null;
          switch (l2) {
            case 16:
              return "Up";
            case 18:
              return "Down";
            case 15:
              return "Left";
            case 17:
              return "Right";
          }
          return Jn.keyCodeToStr(l2);
        }
        o2.toElectronAccelerator = n;
      })(Qn ||= {});
      Rr = class s8 {
        constructor(t, e, i, r, n) {
          this.ctrlKey = t;
          this.shiftKey = e;
          this.altKey = i;
          this.metaKey = r;
          this.keyCode = n;
        }
        equals(t) {
          return t instanceof s8 && this.ctrlKey === t.ctrlKey && this.shiftKey === t.shiftKey && this.altKey === t.altKey && this.metaKey === t.metaKey && this.keyCode === t.keyCode;
        }
        getHashCode() {
          let t = this.ctrlKey ? "1" : "0", e = this.shiftKey ? "1" : "0", i = this.altKey ? "1" : "0", r = this.metaKey ? "1" : "0";
          return `K${t}${e}${i}${r}${this.keyCode}`;
        }
        isModifierKey() {
          return this.keyCode === 0 || this.keyCode === 5 || this.keyCode === 57 || this.keyCode === 6 || this.keyCode === 4;
        }
        toKeybinding() {
          return new es([this]);
        }
        isDuplicateModifierCase() {
          return this.ctrlKey && this.keyCode === 5 || this.shiftKey && this.keyCode === 4 || this.altKey && this.keyCode === 6 || this.metaKey && this.keyCode === 57;
        }
      };
      es = class {
        constructor(t) {
          if (t.length === 0) throw eo("chords");
          this.chords = t;
        }
        getHashCode() {
          let t = "";
          for (let e = 0, i = this.chords.length; e < i; e++) e !== 0 && (t += ";"), t += this.chords[e].getHashCode();
          return t;
        }
        equals(t) {
          if (t === null || this.chords.length !== t.chords.length) return false;
          for (let e = 0; e < this.chords.length; e++) if (!this.chords[e].equals(t.chords[e])) return false;
          return true;
        }
      };
      ua = Te ? 256 : 2048;
      ha = 512;
      da = 1024;
      fa = Te ? 2048 : 256;
      ft = class {
        constructor(t) {
          this._standardKeyboardEventBrand = true;
          let e = t;
          this.browserEvent = e, this.target = e.target, this.ctrlKey = e.ctrlKey, this.shiftKey = e.shiftKey, this.altKey = e.altKey, this.metaKey = e.metaKey, this.altGraphKey = e.getModifierState?.("AltGraph"), this.keyCode = ca(e), this.code = e.code, this.ctrlKey = this.ctrlKey || this.keyCode === 5, this.altKey = this.altKey || this.keyCode === 6, this.shiftKey = this.shiftKey || this.keyCode === 4, this.metaKey = this.metaKey || this.keyCode === 57, this._asKeybinding = this._computeKeybinding(), this._asKeyCodeChord = this._computeKeyCodeChord();
        }
        preventDefault() {
          this.browserEvent && this.browserEvent.preventDefault && this.browserEvent.preventDefault();
        }
        stopPropagation() {
          this.browserEvent && this.browserEvent.stopPropagation && this.browserEvent.stopPropagation();
        }
        toKeyCodeChord() {
          return this._asKeyCodeChord;
        }
        equals(t) {
          return this._asKeybinding === t;
        }
        _computeKeybinding() {
          let t = 0;
          this.keyCode !== 5 && this.keyCode !== 4 && this.keyCode !== 6 && this.keyCode !== 57 && (t = this.keyCode);
          let e = 0;
          return this.ctrlKey && (e |= ua), this.altKey && (e |= ha), this.shiftKey && (e |= da), this.metaKey && (e |= fa), e |= t, e;
        }
        _computeKeyCodeChord() {
          let t = 0;
          return this.keyCode !== 5 && this.keyCode !== 4 && this.keyCode !== 6 && this.keyCode !== 57 && (t = this.keyCode), new Rr(this.ctrlKey, this.shiftKey, this.altKey, this.metaKey, t);
        }
      };
      wo = /* @__PURE__ */ new WeakMap();
      Lr = class {
        static getSameOriginWindowChain(t) {
          let e = wo.get(t);
          if (!e) {
            e = [], wo.set(t, e);
            let i = t, r;
            do
              r = pa(i), r ? e.push({ window: new WeakRef(i), iframeElement: i.frameElement || null }) : e.push({ window: new WeakRef(i), iframeElement: null }), i = r;
            while (i);
          }
          return e.slice(0);
        }
        static getPositionOfChildWindowRelativeToAncestorWindow(t, e) {
          if (!e || t === e) return { top: 0, left: 0 };
          let i = 0, r = 0, n = this.getSameOriginWindowChain(t);
          for (let o2 of n) {
            let l2 = o2.window.deref();
            if (i += l2?.scrollY ?? 0, r += l2?.scrollX ?? 0, l2 === e || !o2.iframeElement) break;
            let a = o2.iframeElement.getBoundingClientRect();
            i += a.top, r += a.left;
          }
          return { top: i, left: r };
        }
      };
      qe = class {
        constructor(t, e) {
          this.timestamp = Date.now(), this.browserEvent = e, this.leftButton = e.button === 0, this.middleButton = e.button === 1, this.rightButton = e.button === 2, this.buttons = e.buttons, this.target = e.target, this.detail = e.detail || 1, e.type === "dblclick" && (this.detail = 2), this.ctrlKey = e.ctrlKey, this.shiftKey = e.shiftKey, this.altKey = e.altKey, this.metaKey = e.metaKey, typeof e.pageX == "number" ? (this.posx = e.pageX, this.posy = e.pageY) : (this.posx = e.clientX + this.target.ownerDocument.body.scrollLeft + this.target.ownerDocument.documentElement.scrollLeft, this.posy = e.clientY + this.target.ownerDocument.body.scrollTop + this.target.ownerDocument.documentElement.scrollTop);
          let i = Lr.getPositionOfChildWindowRelativeToAncestorWindow(t, e.view);
          this.posx -= i.left, this.posy -= i.top;
        }
        preventDefault() {
          this.browserEvent.preventDefault();
        }
        stopPropagation() {
          this.browserEvent.stopPropagation();
        }
      };
      xi = class {
        constructor(t, e = 0, i = 0) {
          this.browserEvent = t || null, this.target = t ? t.target || t.targetNode || t.srcElement : null, this.deltaY = i, this.deltaX = e;
          let r = false;
          if (Ti) {
            let n = navigator.userAgent.match(/Chrome\/(\d+)/);
            r = (n ? parseInt(n[1]) : 123) <= 122;
          }
          if (t) {
            let n = t, o2 = t, l2 = t.view?.devicePixelRatio || 1;
            if (typeof n.wheelDeltaY < "u") r ? this.deltaY = n.wheelDeltaY / (120 * l2) : this.deltaY = n.wheelDeltaY / 120;
            else if (typeof o2.VERTICAL_AXIS < "u" && o2.axis === o2.VERTICAL_AXIS) this.deltaY = -o2.detail / 3;
            else if (t.type === "wheel") {
              let a = t;
              a.deltaMode === a.DOM_DELTA_LINE ? Ei && !Te ? this.deltaY = -t.deltaY / 3 : this.deltaY = -t.deltaY : this.deltaY = -t.deltaY / 40;
            }
            if (typeof n.wheelDeltaX < "u") Sr && wr ? this.deltaX = -(n.wheelDeltaX / 120) : r ? this.deltaX = n.wheelDeltaX / (120 * l2) : this.deltaX = n.wheelDeltaX / 120;
            else if (typeof o2.HORIZONTAL_AXIS < "u" && o2.axis === o2.HORIZONTAL_AXIS) this.deltaX = -t.detail / 3;
            else if (t.type === "wheel") {
              let a = t;
              a.deltaMode === a.DOM_DELTA_LINE ? Ei && !Te ? this.deltaX = -t.deltaX / 3 : this.deltaX = -t.deltaX : this.deltaX = -t.deltaX / 40;
            }
            this.deltaY === 0 && this.deltaX === 0 && t.wheelDelta && (r ? this.deltaY = t.wheelDelta / (120 * l2) : this.deltaY = t.wheelDelta / 120);
          }
        }
        preventDefault() {
          this.browserEvent?.preventDefault();
        }
        stopPropagation() {
          this.browserEvent?.stopPropagation();
        }
      };
      Do = Object.freeze(function(s15, t) {
        let e = setTimeout(s15.bind(t), 0);
        return { dispose() {
          clearTimeout(e);
        } };
      });
      ((i) => {
        function s15(r) {
          return r === i.None || r === i.Cancelled || r instanceof ts ? true : !r || typeof r != "object" ? false : typeof r.isCancellationRequested == "boolean" && typeof r.onCancellationRequested == "function";
        }
        i.isCancellationToken = s15, i.None = Object.freeze({ isCancellationRequested: false, onCancellationRequested: $.None }), i.Cancelled = Object.freeze({ isCancellationRequested: true, onCancellationRequested: Do });
      })(ma ||= {});
      ts = class {
        constructor() {
          this._isCancelled = false;
          this._emitter = null;
        }
        cancel() {
          this._isCancelled || (this._isCancelled = true, this._emitter && (this._emitter.fire(void 0), this.dispose()));
        }
        get isCancellationRequested() {
          return this._isCancelled;
        }
        get onCancellationRequested() {
          return this._isCancelled ? Do : (this._emitter || (this._emitter = new v()), this._emitter.event);
        }
        dispose() {
          this._emitter && (this._emitter.dispose(), this._emitter = null);
        }
      };
      Ye = class {
        constructor(t, e) {
          this._isDisposed = false;
          this._token = -1, typeof t == "function" && typeof e == "number" && this.setIfNotSet(t, e);
        }
        dispose() {
          this.cancel(), this._isDisposed = true;
        }
        cancel() {
          this._token !== -1 && (clearTimeout(this._token), this._token = -1);
        }
        cancelAndSet(t, e) {
          if (this._isDisposed) throw new Rt("Calling 'cancelAndSet' on a disposed TimeoutTimer");
          this.cancel(), this._token = setTimeout(() => {
            this._token = -1, t();
          }, e);
        }
        setIfNotSet(t, e) {
          if (this._isDisposed) throw new Rt("Calling 'setIfNotSet' on a disposed TimeoutTimer");
          this._token === -1 && (this._token = setTimeout(() => {
            this._token = -1, t();
          }, e));
        }
      };
      kr = class {
        constructor() {
          this.disposable = void 0;
          this.isDisposed = false;
        }
        cancel() {
          this.disposable?.dispose(), this.disposable = void 0;
        }
        cancelAndSet(t, e, i = globalThis) {
          if (this.isDisposed) throw new Rt("Calling 'cancelAndSet' on a disposed IntervalTimer");
          this.cancel();
          let r = i.setInterval(() => {
            t();
          }, e);
          this.disposable = C(() => {
            i.clearInterval(r), this.disposable = void 0;
          });
        }
        dispose() {
          this.cancel(), this.isDisposed = true;
        }
      };
      (function() {
        typeof globalThis.requestIdleCallback != "function" || typeof globalThis.cancelIdleCallback != "function" ? Ar = (s15, t) => {
          Eo(() => {
            if (e) return;
            let i = Date.now() + 15;
            t(Object.freeze({ didTimeout: true, timeRemaining() {
              return Math.max(0, i - Date.now());
            } }));
          });
          let e = false;
          return { dispose() {
            e || (e = true);
          } };
        } : Ar = (s15, t, e) => {
          let i = s15.requestIdleCallback(t, typeof e == "number" ? { timeout: e } : void 0), r = false;
          return { dispose() {
            r || (r = true, s15.cancelIdleCallback(i));
          } };
        }, ba = (s15) => Ar(globalThis, s15);
      })();
      ((e) => {
        async function s15(i) {
          let r, n = await Promise.all(i.map((o2) => o2.then((l2) => l2, (l2) => {
            r || (r = l2);
          })));
          if (typeof r < "u") throw r;
          return n;
        }
        e.settled = s15;
        function t(i) {
          return new Promise(async (r, n) => {
            try {
              await i(r, n);
            } catch (o2) {
              n(o2);
            }
          });
        }
        e.withAsyncBody = t;
      })(va ||= {});
      _e = class _e2 {
        static fromArray(t) {
          return new _e2((e) => {
            e.emitMany(t);
          });
        }
        static fromPromise(t) {
          return new _e2(async (e) => {
            e.emitMany(await t);
          });
        }
        static fromPromises(t) {
          return new _e2(async (e) => {
            await Promise.all(t.map(async (i) => e.emitOne(await i)));
          });
        }
        static merge(t) {
          return new _e2(async (e) => {
            await Promise.all(t.map(async (i) => {
              for await (let r of i) e.emitOne(r);
            }));
          });
        }
        constructor(t, e) {
          this._state = 0, this._results = [], this._error = null, this._onReturn = e, this._onStateChanged = new v(), queueMicrotask(async () => {
            let i = { emitOne: (r) => this.emitOne(r), emitMany: (r) => this.emitMany(r), reject: (r) => this.reject(r) };
            try {
              await Promise.resolve(t(i)), this.resolve();
            } catch (r) {
              this.reject(r);
            } finally {
              i.emitOne = void 0, i.emitMany = void 0, i.reject = void 0;
            }
          });
        }
        [Symbol.asyncIterator]() {
          let t = 0;
          return { next: async () => {
            do {
              if (this._state === 2) throw this._error;
              if (t < this._results.length) return { done: false, value: this._results[t++] };
              if (this._state === 1) return { done: true, value: void 0 };
              await $.toPromise(this._onStateChanged.event);
            } while (true);
          }, return: async () => (this._onReturn?.(), { done: true, value: void 0 }) };
        }
        static map(t, e) {
          return new _e2(async (i) => {
            for await (let r of t) i.emitOne(e(r));
          });
        }
        map(t) {
          return _e2.map(this, t);
        }
        static filter(t, e) {
          return new _e2(async (i) => {
            for await (let r of t) e(r) && i.emitOne(r);
          });
        }
        filter(t) {
          return _e2.filter(this, t);
        }
        static coalesce(t) {
          return _e2.filter(t, (e) => !!e);
        }
        coalesce() {
          return _e2.coalesce(this);
        }
        static async toPromise(t) {
          let e = [];
          for await (let i of t) e.push(i);
          return e;
        }
        toPromise() {
          return _e2.toPromise(this);
        }
        emitOne(t) {
          this._state === 0 && (this._results.push(t), this._onStateChanged.fire());
        }
        emitMany(t) {
          this._state === 0 && (this._results = this._results.concat(t), this._onStateChanged.fire());
        }
        resolve() {
          this._state === 0 && (this._state = 1, this._onStateChanged.fire());
        }
        reject(t) {
          this._state === 0 && (this._state = 2, this._error = t, this._onStateChanged.fire());
        }
      };
      _e.EMPTY = _e.fromArray([]);
      Cr = class Cr2 {
        constructor() {
          this._h0 = 1732584193;
          this._h1 = 4023233417;
          this._h2 = 2562383102;
          this._h3 = 271733878;
          this._h4 = 3285377520;
          this._buff = new Uint8Array(67), this._buffDV = new DataView(this._buff.buffer), this._buffLen = 0, this._totalLen = 0, this._leftoverHighSurrogate = 0, this._finished = false;
        }
        update(t) {
          let e = t.length;
          if (e === 0) return;
          let i = this._buff, r = this._buffLen, n = this._leftoverHighSurrogate, o2, l2;
          for (n !== 0 ? (o2 = n, l2 = -1, n = 0) : (o2 = t.charCodeAt(0), l2 = 0); ; ) {
            let a = o2;
            if (Lo(o2)) if (l2 + 1 < e) {
              let u = t.charCodeAt(l2 + 1);
              is(u) ? (l2++, a = Ao(o2, u)) : a = 65533;
            } else {
              n = o2;
              break;
            }
            else is(o2) && (a = 65533);
            if (r = this._push(i, r, a), l2++, l2 < e) o2 = t.charCodeAt(l2);
            else break;
          }
          this._buffLen = r, this._leftoverHighSurrogate = n;
        }
        _push(t, e, i) {
          return i < 128 ? t[e++] = i : i < 2048 ? (t[e++] = 192 | (i & 1984) >>> 6, t[e++] = 128 | (i & 63) >>> 0) : i < 65536 ? (t[e++] = 224 | (i & 61440) >>> 12, t[e++] = 128 | (i & 4032) >>> 6, t[e++] = 128 | (i & 63) >>> 0) : (t[e++] = 240 | (i & 1835008) >>> 18, t[e++] = 128 | (i & 258048) >>> 12, t[e++] = 128 | (i & 4032) >>> 6, t[e++] = 128 | (i & 63) >>> 0), e >= 64 && (this._step(), e -= 64, this._totalLen += 64, t[0] = t[64], t[1] = t[65], t[2] = t[66]), e;
        }
        digest() {
          return this._finished || (this._finished = true, this._leftoverHighSurrogate && (this._leftoverHighSurrogate = 0, this._buffLen = this._push(this._buff, this._buffLen, 65533)), this._totalLen += this._buffLen, this._wrapUp()), wi(this._h0) + wi(this._h1) + wi(this._h2) + wi(this._h3) + wi(this._h4);
        }
        _wrapUp() {
          this._buff[this._buffLen++] = 128, ko(this._buff, this._buffLen), this._buffLen > 56 && (this._step(), ko(this._buff));
          let t = 8 * this._totalLen;
          this._buffDV.setUint32(56, Math.floor(t / 4294967296), false), this._buffDV.setUint32(60, t % 4294967296, false), this._step();
        }
        _step() {
          let t = Cr2._bigBlock32, e = this._buffDV;
          for (let c = 0; c < 64; c += 4) t.setUint32(c, e.getUint32(c, false), false);
          for (let c = 64; c < 320; c += 4) t.setUint32(c, rs(t.getUint32(c - 12, false) ^ t.getUint32(c - 32, false) ^ t.getUint32(c - 56, false) ^ t.getUint32(c - 64, false), 1), false);
          let i = this._h0, r = this._h1, n = this._h2, o2 = this._h3, l2 = this._h4, a, u, h2;
          for (let c = 0; c < 80; c++) c < 20 ? (a = r & n | ~r & o2, u = 1518500249) : c < 40 ? (a = r ^ n ^ o2, u = 1859775393) : c < 60 ? (a = r & n | r & o2 | n & o2, u = 2400959708) : (a = r ^ n ^ o2, u = 3395469782), h2 = rs(i, 5) + a + l2 + u + t.getUint32(c * 4, false) & 4294967295, l2 = o2, o2 = n, n = rs(r, 30), r = i, i = h2;
          this._h0 = this._h0 + i & 4294967295, this._h1 = this._h1 + r & 4294967295, this._h2 = this._h2 + n & 4294967295, this._h3 = this._h3 + o2 & 4294967295, this._h4 = this._h4 + l2 & 4294967295;
        }
      };
      Cr._bigBlock32 = new DataView(new ArrayBuffer(320));
      ({ registerWindow: Bh, getWindow: be, getDocument: Nh, getWindows: Fh, getWindowsCount: Hh, getWindowId: Oo, getWindowById: Wh, hasWindow: Uh, onDidRegisterWindow: No, onWillUnregisterWindow: Kh, onDidUnregisterWindow: zh } = (function() {
        let s15 = /* @__PURE__ */ new Map();
        fe;
        let t = { window: fe, disposables: new Ee() };
        s15.set(fe.vscodeWindowId, t);
        let e = new v(), i = new v(), r = new v();
        function n(o2, l2) {
          return (typeof o2 == "number" ? s15.get(o2) : void 0) ?? (l2 ? t : void 0);
        }
        return { onDidRegisterWindow: e.event, onWillUnregisterWindow: r.event, onDidUnregisterWindow: i.event, registerWindow(o2) {
          if (s15.has(o2.vscodeWindowId)) return D.None;
          let l2 = new Ee(), a = { window: o2, disposables: l2.add(new Ee()) };
          return s15.set(o2.vscodeWindowId, a), l2.add(C(() => {
            s15.delete(o2.vscodeWindowId), i.fire(o2);
          })), l2.add(L(o2, Y.BEFORE_UNLOAD, () => {
            r.fire(o2);
          })), e.fire(a), l2;
        }, getWindows() {
          return s15.values();
        }, getWindowsCount() {
          return s15.size;
        }, getWindowId(o2) {
          return o2.vscodeWindowId;
        }, hasWindow(o2) {
          return s15.has(o2);
        }, getWindowById: n, getWindow(o2) {
          let l2 = o2;
          if (l2?.ownerDocument?.defaultView) return l2.ownerDocument.defaultView.window;
          let a = o2;
          return a?.view ? a.view.window : fe;
        }, getDocument(o2) {
          return be(o2).document;
        } };
      })());
      ss = class {
        constructor(t, e, i, r) {
          this._node = t, this._type = e, this._handler = i, this._options = r || false, this._node.addEventListener(this._type, this._handler, this._options);
        }
        dispose() {
          this._handler && (this._node.removeEventListener(this._type, this._handler, this._options), this._node = null, this._handler = null);
        }
      };
      os = function(t, e, i, r) {
        let n = i;
        return e === "click" || e === "mousedown" || e === "contextmenu" ? n = ya(be(t), i) : (e === "keydown" || e === "keypress" || e === "keyup") && (n = xa(i)), L(t, e, n, r);
      };
      Mr = class extends kr {
        constructor(t) {
          super(), this.defaultTarget = t && be(t);
        }
        cancelAndSet(t, e, i) {
          return super.cancelAndSet(t, e, i ?? this.defaultTarget);
        }
      };
      Di = class {
        constructor(t, e = 0) {
          this._runner = t, this.priority = e, this._canceled = false;
        }
        dispose() {
          this._canceled = true;
        }
        execute() {
          if (!this._canceled) try {
            this._runner();
          } catch (t) {
            Lt(t);
          }
        }
        static sort(t, e) {
          return e.priority - t.priority;
        }
      };
      (function() {
        let s15 = /* @__PURE__ */ new Map(), t = /* @__PURE__ */ new Map(), e = /* @__PURE__ */ new Map(), i = /* @__PURE__ */ new Map(), r = (n) => {
          e.set(n, false);
          let o2 = s15.get(n) ?? [];
          for (t.set(n, o2), s15.set(n, []), i.set(n, true); o2.length > 0; ) o2.sort(Di.sort), o2.shift().execute();
          i.set(n, false);
        };
        mt = (n, o2, l2 = 0) => {
          let a = Oo(n), u = new Di(o2, l2), h2 = s15.get(a);
          return h2 || (h2 = [], s15.set(a, h2)), h2.push(u), e.get(a) || (e.set(a, true), n.requestAnimationFrame(() => r(a))), u;
        }, wa = (n, o2, l2) => {
          let a = Oo(n);
          if (i.get(a)) {
            let u = new Di(o2, l2), h2 = t.get(a);
            return h2 || (h2 = [], t.set(a, h2)), h2.push(u), u;
          } else return mt(n, o2, l2);
        };
      })();
      pt = class pt2 {
        constructor(t, e) {
          this.width = t;
          this.height = e;
        }
        with(t = this.width, e = this.height) {
          return t !== this.width || e !== this.height ? new pt2(t, e) : this;
        }
        static is(t) {
          return typeof t == "object" && typeof t.height == "number" && typeof t.width == "number";
        }
        static lift(t) {
          return t instanceof pt2 ? t : new pt2(t.width, t.height);
        }
        static equals(t, e) {
          return t === e ? true : !t || !e ? false : t.width === e.width && t.height === e.height;
        }
      };
      pt.None = new pt(0, 0);
      Gh = new class {
        constructor() {
          this.mutationObservers = /* @__PURE__ */ new Map();
        }
        observe(s15, t, e) {
          let i = this.mutationObservers.get(s15);
          i || (i = /* @__PURE__ */ new Map(), this.mutationObservers.set(s15, i));
          let r = Mo(e), n = i.get(r);
          if (n) n.users += 1;
          else {
            let o2 = new v(), l2 = new MutationObserver((u) => o2.fire(u));
            l2.observe(s15, e);
            let a = n = { users: 1, observer: l2, onDidMutate: o2.event };
            t.add(C(() => {
              a.users -= 1, a.users === 0 && (o2.dispose(), l2.disconnect(), i?.delete(r), i?.size === 0 && this.mutationObservers.delete(s15));
            })), i.set(r, n);
          }
          return n.onDidMutate;
        }
      }();
      Y = { CLICK: "click", AUXCLICK: "auxclick", DBLCLICK: "dblclick", MOUSE_UP: "mouseup", MOUSE_DOWN: "mousedown", MOUSE_OVER: "mouseover", MOUSE_MOVE: "mousemove", MOUSE_OUT: "mouseout", MOUSE_ENTER: "mouseenter", MOUSE_LEAVE: "mouseleave", MOUSE_WHEEL: "wheel", POINTER_UP: "pointerup", POINTER_DOWN: "pointerdown", POINTER_MOVE: "pointermove", POINTER_LEAVE: "pointerleave", CONTEXT_MENU: "contextmenu", WHEEL: "wheel", KEY_DOWN: "keydown", KEY_PRESS: "keypress", KEY_UP: "keyup", LOAD: "load", BEFORE_UNLOAD: "beforeunload", UNLOAD: "unload", PAGE_SHOW: "pageshow", PAGE_HIDE: "pagehide", PASTE: "paste", ABORT: "abort", ERROR: "error", RESIZE: "resize", SCROLL: "scroll", FULLSCREEN_CHANGE: "fullscreenchange", WK_FULLSCREEN_CHANGE: "webkitfullscreenchange", SELECT: "select", CHANGE: "change", SUBMIT: "submit", RESET: "reset", FOCUS: "focus", FOCUS_IN: "focusin", FOCUS_OUT: "focusout", BLUR: "blur", INPUT: "input", STORAGE: "storage", DRAG_START: "dragstart", DRAG: "drag", DRAG_ENTER: "dragenter", DRAG_LEAVE: "dragleave", DRAG_OVER: "dragover", DROP: "drop", DRAG_END: "dragend", ANIMATION_START: Bt ? "webkitAnimationStart" : "animationstart", ANIMATION_END: Bt ? "webkitAnimationEnd" : "animationend", ANIMATION_ITERATION: Bt ? "webkitAnimationIteration" : "animationiteration" };
      Da = /([\w\-]+)?(#([\w\-]+))?((\.([\w\-]+))*)/;
      Ra.SVG = function(s15, t, ...e) {
        return Ho("http://www.w3.org/2000/svg", s15, t, ...e);
      };
      ls = class {
        constructor(t) {
          this.domNode = t;
          this._maxWidth = "";
          this._width = "";
          this._height = "";
          this._top = "";
          this._left = "";
          this._bottom = "";
          this._right = "";
          this._paddingTop = "";
          this._paddingLeft = "";
          this._paddingBottom = "";
          this._paddingRight = "";
          this._fontFamily = "";
          this._fontWeight = "";
          this._fontSize = "";
          this._fontStyle = "";
          this._fontFeatureSettings = "";
          this._fontVariationSettings = "";
          this._textDecoration = "";
          this._lineHeight = "";
          this._letterSpacing = "";
          this._className = "";
          this._display = "";
          this._position = "";
          this._visibility = "";
          this._color = "";
          this._backgroundColor = "";
          this._layerHint = false;
          this._contain = "none";
          this._boxShadow = "";
        }
        setMaxWidth(t) {
          let e = Ie(t);
          this._maxWidth !== e && (this._maxWidth = e, this.domNode.style.maxWidth = this._maxWidth);
        }
        setWidth(t) {
          let e = Ie(t);
          this._width !== e && (this._width = e, this.domNode.style.width = this._width);
        }
        setHeight(t) {
          let e = Ie(t);
          this._height !== e && (this._height = e, this.domNode.style.height = this._height);
        }
        setTop(t) {
          let e = Ie(t);
          this._top !== e && (this._top = e, this.domNode.style.top = this._top);
        }
        setLeft(t) {
          let e = Ie(t);
          this._left !== e && (this._left = e, this.domNode.style.left = this._left);
        }
        setBottom(t) {
          let e = Ie(t);
          this._bottom !== e && (this._bottom = e, this.domNode.style.bottom = this._bottom);
        }
        setRight(t) {
          let e = Ie(t);
          this._right !== e && (this._right = e, this.domNode.style.right = this._right);
        }
        setPaddingTop(t) {
          let e = Ie(t);
          this._paddingTop !== e && (this._paddingTop = e, this.domNode.style.paddingTop = this._paddingTop);
        }
        setPaddingLeft(t) {
          let e = Ie(t);
          this._paddingLeft !== e && (this._paddingLeft = e, this.domNode.style.paddingLeft = this._paddingLeft);
        }
        setPaddingBottom(t) {
          let e = Ie(t);
          this._paddingBottom !== e && (this._paddingBottom = e, this.domNode.style.paddingBottom = this._paddingBottom);
        }
        setPaddingRight(t) {
          let e = Ie(t);
          this._paddingRight !== e && (this._paddingRight = e, this.domNode.style.paddingRight = this._paddingRight);
        }
        setFontFamily(t) {
          this._fontFamily !== t && (this._fontFamily = t, this.domNode.style.fontFamily = this._fontFamily);
        }
        setFontWeight(t) {
          this._fontWeight !== t && (this._fontWeight = t, this.domNode.style.fontWeight = this._fontWeight);
        }
        setFontSize(t) {
          let e = Ie(t);
          this._fontSize !== e && (this._fontSize = e, this.domNode.style.fontSize = this._fontSize);
        }
        setFontStyle(t) {
          this._fontStyle !== t && (this._fontStyle = t, this.domNode.style.fontStyle = this._fontStyle);
        }
        setFontFeatureSettings(t) {
          this._fontFeatureSettings !== t && (this._fontFeatureSettings = t, this.domNode.style.fontFeatureSettings = this._fontFeatureSettings);
        }
        setFontVariationSettings(t) {
          this._fontVariationSettings !== t && (this._fontVariationSettings = t, this.domNode.style.fontVariationSettings = this._fontVariationSettings);
        }
        setTextDecoration(t) {
          this._textDecoration !== t && (this._textDecoration = t, this.domNode.style.textDecoration = this._textDecoration);
        }
        setLineHeight(t) {
          let e = Ie(t);
          this._lineHeight !== e && (this._lineHeight = e, this.domNode.style.lineHeight = this._lineHeight);
        }
        setLetterSpacing(t) {
          let e = Ie(t);
          this._letterSpacing !== e && (this._letterSpacing = e, this.domNode.style.letterSpacing = this._letterSpacing);
        }
        setClassName(t) {
          this._className !== t && (this._className = t, this.domNode.className = this._className);
        }
        toggleClassName(t, e) {
          this.domNode.classList.toggle(t, e), this._className = this.domNode.className;
        }
        setDisplay(t) {
          this._display !== t && (this._display = t, this.domNode.style.display = this._display);
        }
        setPosition(t) {
          this._position !== t && (this._position = t, this.domNode.style.position = this._position);
        }
        setVisibility(t) {
          this._visibility !== t && (this._visibility = t, this.domNode.style.visibility = this._visibility);
        }
        setColor(t) {
          this._color !== t && (this._color = t, this.domNode.style.color = this._color);
        }
        setBackgroundColor(t) {
          this._backgroundColor !== t && (this._backgroundColor = t, this.domNode.style.backgroundColor = this._backgroundColor);
        }
        setLayerHinting(t) {
          this._layerHint !== t && (this._layerHint = t, this.domNode.style.transform = this._layerHint ? "translate3d(0px, 0px, 0px)" : "");
        }
        setBoxShadow(t) {
          this._boxShadow !== t && (this._boxShadow = t, this.domNode.style.boxShadow = t);
        }
        setContain(t) {
          this._contain !== t && (this._contain = t, this.domNode.style.contain = this._contain);
        }
        setAttribute(t, e) {
          this.domNode.setAttribute(t, e);
        }
        removeAttribute(t) {
          this.domNode.removeAttribute(t);
        }
        appendChild(t) {
          this.domNode.appendChild(t.domNode);
        }
        removeChild(t) {
          this.domNode.removeChild(t.domNode);
        }
      };
      Wt = class {
        constructor() {
          this._hooks = new Ee();
          this._pointerMoveCallback = null;
          this._onStopCallback = null;
        }
        dispose() {
          this.stopMonitoring(false), this._hooks.dispose();
        }
        stopMonitoring(t, e) {
          if (!this.isMonitoring()) return;
          this._hooks.clear(), this._pointerMoveCallback = null;
          let i = this._onStopCallback;
          this._onStopCallback = null, t && i && i(e);
        }
        isMonitoring() {
          return !!this._pointerMoveCallback;
        }
        startMonitoring(t, e, i, r, n) {
          this.isMonitoring() && this.stopMonitoring(false), this._pointerMoveCallback = r, this._onStopCallback = n;
          let o2 = t;
          try {
            t.setPointerCapture(e), this._hooks.add(C(() => {
              try {
                t.releasePointerCapture(e);
              } catch {
              }
            }));
          } catch {
            o2 = be(t);
          }
          this._hooks.add(L(o2, Y.POINTER_MOVE, (l2) => {
            if (l2.buttons !== i) {
              this.stopMonitoring(true);
              return;
            }
            l2.preventDefault(), this._pointerMoveCallback(l2);
          })), this._hooks.add(L(o2, Y.POINTER_UP, (l2) => this.stopMonitoring(true)));
        }
      };
      ((n) => (n.Tap = "-xterm-gesturetap", n.Change = "-xterm-gesturechange", n.Start = "-xterm-gesturestart", n.End = "-xterm-gesturesend", n.Contextmenu = "-xterm-gesturecontextmenu"))(He ||= {});
      Q = class Q2 extends D {
        constructor() {
          super();
          this.dispatched = false;
          this.targets = new Ct();
          this.ignoreTargets = new Ct();
          this.activeTouches = {}, this.handle = null, this._lastSetTapCountTime = 0, this._register($.runAndSubscribe(No, ({ window: e, disposables: i }) => {
            i.add(L(e.document, "touchstart", (r) => this.onTouchStart(r), { passive: false })), i.add(L(e.document, "touchend", (r) => this.onTouchEnd(e, r))), i.add(L(e.document, "touchmove", (r) => this.onTouchMove(r), { passive: false }));
          }, { window: fe, disposables: this._store }));
        }
        static addTarget(e) {
          if (!Q2.isTouchDevice()) return D.None;
          Q2.INSTANCE || (Q2.INSTANCE = Gn(new Q2()));
          let i = Q2.INSTANCE.targets.push(e);
          return C(i);
        }
        static ignoreTarget(e) {
          if (!Q2.isTouchDevice()) return D.None;
          Q2.INSTANCE || (Q2.INSTANCE = Gn(new Q2()));
          let i = Q2.INSTANCE.ignoreTargets.push(e);
          return C(i);
        }
        static isTouchDevice() {
          return "ontouchstart" in fe || navigator.maxTouchPoints > 0;
        }
        dispose() {
          this.handle && (this.handle.dispose(), this.handle = null), super.dispose();
        }
        onTouchStart(e) {
          let i = Date.now();
          this.handle && (this.handle.dispose(), this.handle = null);
          for (let r = 0, n = e.targetTouches.length; r < n; r++) {
            let o2 = e.targetTouches.item(r);
            this.activeTouches[o2.identifier] = { id: o2.identifier, initialTarget: o2.target, initialTimeStamp: i, initialPageX: o2.pageX, initialPageY: o2.pageY, rollingTimestamps: [i], rollingPageX: [o2.pageX], rollingPageY: [o2.pageY] };
            let l2 = this.newGestureEvent(He.Start, o2.target);
            l2.pageX = o2.pageX, l2.pageY = o2.pageY, this.dispatchEvent(l2);
          }
          this.dispatched && (e.preventDefault(), e.stopPropagation(), this.dispatched = false);
        }
        onTouchEnd(e, i) {
          let r = Date.now(), n = Object.keys(this.activeTouches).length;
          for (let o2 = 0, l2 = i.changedTouches.length; o2 < l2; o2++) {
            let a = i.changedTouches.item(o2);
            if (!this.activeTouches.hasOwnProperty(String(a.identifier))) {
              console.warn("move of an UNKNOWN touch", a);
              continue;
            }
            let u = this.activeTouches[a.identifier], h2 = Date.now() - u.initialTimeStamp;
            if (h2 < Q2.HOLD_DELAY && Math.abs(u.initialPageX - Se(u.rollingPageX)) < 30 && Math.abs(u.initialPageY - Se(u.rollingPageY)) < 30) {
              let c = this.newGestureEvent(He.Tap, u.initialTarget);
              c.pageX = Se(u.rollingPageX), c.pageY = Se(u.rollingPageY), this.dispatchEvent(c);
            } else if (h2 >= Q2.HOLD_DELAY && Math.abs(u.initialPageX - Se(u.rollingPageX)) < 30 && Math.abs(u.initialPageY - Se(u.rollingPageY)) < 30) {
              let c = this.newGestureEvent(He.Contextmenu, u.initialTarget);
              c.pageX = Se(u.rollingPageX), c.pageY = Se(u.rollingPageY), this.dispatchEvent(c);
            } else if (n === 1) {
              let c = Se(u.rollingPageX), d = Se(u.rollingPageY), _3 = Se(u.rollingTimestamps) - u.rollingTimestamps[0], p = c - u.rollingPageX[0], m = d - u.rollingPageY[0], f = [...this.targets].filter((A) => u.initialTarget instanceof Node && A.contains(u.initialTarget));
              this.inertia(e, f, r, Math.abs(p) / _3, p > 0 ? 1 : -1, c, Math.abs(m) / _3, m > 0 ? 1 : -1, d);
            }
            this.dispatchEvent(this.newGestureEvent(He.End, u.initialTarget)), delete this.activeTouches[a.identifier];
          }
          this.dispatched && (i.preventDefault(), i.stopPropagation(), this.dispatched = false);
        }
        newGestureEvent(e, i) {
          let r = document.createEvent("CustomEvent");
          return r.initEvent(e, false, true), r.initialTarget = i, r.tapCount = 0, r;
        }
        dispatchEvent(e) {
          if (e.type === He.Tap) {
            let i = (/* @__PURE__ */ new Date()).getTime(), r = 0;
            i - this._lastSetTapCountTime > Q2.CLEAR_TAP_COUNT_TIME ? r = 1 : r = 2, this._lastSetTapCountTime = i, e.tapCount = r;
          } else (e.type === He.Change || e.type === He.Contextmenu) && (this._lastSetTapCountTime = 0);
          if (e.initialTarget instanceof Node) {
            for (let r of this.ignoreTargets) if (r.contains(e.initialTarget)) return;
            let i = [];
            for (let r of this.targets) if (r.contains(e.initialTarget)) {
              let n = 0, o2 = e.initialTarget;
              for (; o2 && o2 !== r; ) n++, o2 = o2.parentElement;
              i.push([n, r]);
            }
            i.sort((r, n) => r[0] - n[0]);
            for (let [r, n] of i) n.dispatchEvent(e), this.dispatched = true;
          }
        }
        inertia(e, i, r, n, o2, l2, a, u, h2) {
          this.handle = mt(e, () => {
            let c = Date.now(), d = c - r, _3 = 0, p = 0, m = true;
            n += Q2.SCROLL_FRICTION * d, a += Q2.SCROLL_FRICTION * d, n > 0 && (m = false, _3 = o2 * n * d), a > 0 && (m = false, p = u * a * d);
            let f = this.newGestureEvent(He.Change);
            f.translationX = _3, f.translationY = p, i.forEach((A) => A.dispatchEvent(f)), m || this.inertia(e, i, c, n, o2, l2 + _3, a, u, h2 + p);
          });
        }
        onTouchMove(e) {
          let i = Date.now();
          for (let r = 0, n = e.changedTouches.length; r < n; r++) {
            let o2 = e.changedTouches.item(r);
            if (!this.activeTouches.hasOwnProperty(String(o2.identifier))) {
              console.warn("end of an UNKNOWN touch", o2);
              continue;
            }
            let l2 = this.activeTouches[o2.identifier], a = this.newGestureEvent(He.Change, l2.initialTarget);
            a.translationX = o2.pageX - Se(l2.rollingPageX), a.translationY = o2.pageY - Se(l2.rollingPageY), a.pageX = o2.pageX, a.pageY = o2.pageY, this.dispatchEvent(a), l2.rollingPageX.length > 3 && (l2.rollingPageX.shift(), l2.rollingPageY.shift(), l2.rollingTimestamps.shift()), l2.rollingPageX.push(o2.pageX), l2.rollingPageY.push(o2.pageY), l2.rollingTimestamps.push(i);
          }
          this.dispatched && (e.preventDefault(), e.stopPropagation(), this.dispatched = false);
        }
      };
      Q.SCROLL_FRICTION = -5e-3, Q.HOLD_DELAY = 700, Q.CLEAR_TAP_COUNT_TIME = 400, M([Wo], Q, "isTouchDevice", 1);
      Pr = Q;
      lt = class extends D {
        onclick(t, e) {
          this._register(L(t, Y.CLICK, (i) => e(new qe(be(t), i))));
        }
        onmousedown(t, e) {
          this._register(L(t, Y.MOUSE_DOWN, (i) => e(new qe(be(t), i))));
        }
        onmouseover(t, e) {
          this._register(L(t, Y.MOUSE_OVER, (i) => e(new qe(be(t), i))));
        }
        onmouseleave(t, e) {
          this._register(L(t, Y.MOUSE_LEAVE, (i) => e(new qe(be(t), i))));
        }
        onkeydown(t, e) {
          this._register(L(t, Y.KEY_DOWN, (i) => e(new ft(i))));
        }
        onkeyup(t, e) {
          this._register(L(t, Y.KEY_UP, (i) => e(new ft(i))));
        }
        oninput(t, e) {
          this._register(L(t, Y.INPUT, e));
        }
        onblur(t, e) {
          this._register(L(t, Y.BLUR, e));
        }
        onfocus(t, e) {
          this._register(L(t, Y.FOCUS, e));
        }
        onchange(t, e) {
          this._register(L(t, Y.CHANGE, e));
        }
        ignoreGesture(t) {
          return Pr.ignoreTarget(t);
        }
      };
      Uo = 11;
      Or = class extends lt {
        constructor(t) {
          super(), this._onActivate = t.onActivate, this.bgDomNode = document.createElement("div"), this.bgDomNode.className = "arrow-background", this.bgDomNode.style.position = "absolute", this.bgDomNode.style.width = t.bgWidth + "px", this.bgDomNode.style.height = t.bgHeight + "px", typeof t.top < "u" && (this.bgDomNode.style.top = "0px"), typeof t.left < "u" && (this.bgDomNode.style.left = "0px"), typeof t.bottom < "u" && (this.bgDomNode.style.bottom = "0px"), typeof t.right < "u" && (this.bgDomNode.style.right = "0px"), this.domNode = document.createElement("div"), this.domNode.className = t.className, this.domNode.style.position = "absolute", this.domNode.style.width = Uo + "px", this.domNode.style.height = Uo + "px", typeof t.top < "u" && (this.domNode.style.top = t.top + "px"), typeof t.left < "u" && (this.domNode.style.left = t.left + "px"), typeof t.bottom < "u" && (this.domNode.style.bottom = t.bottom + "px"), typeof t.right < "u" && (this.domNode.style.right = t.right + "px"), this._pointerMoveMonitor = this._register(new Wt()), this._register(os(this.bgDomNode, Y.POINTER_DOWN, (e) => this._arrowPointerDown(e))), this._register(os(this.domNode, Y.POINTER_DOWN, (e) => this._arrowPointerDown(e))), this._pointerdownRepeatTimer = this._register(new Mr()), this._pointerdownScheduleRepeatTimer = this._register(new Ye());
        }
        _arrowPointerDown(t) {
          if (!t.target || !(t.target instanceof Element)) return;
          let e = () => {
            this._pointerdownRepeatTimer.cancelAndSet(() => this._onActivate(), 1e3 / 24, be(t));
          };
          this._onActivate(), this._pointerdownRepeatTimer.cancel(), this._pointerdownScheduleRepeatTimer.cancelAndSet(e, 200), this._pointerMoveMonitor.startMonitoring(t.target, t.pointerId, t.buttons, (i) => {
          }, () => {
            this._pointerdownRepeatTimer.cancel(), this._pointerdownScheduleRepeatTimer.cancel();
          }), t.preventDefault();
        }
      };
      cs = class s9 {
        constructor(t, e, i, r, n, o2, l2) {
          this._forceIntegerValues = t;
          this._scrollStateBrand = void 0;
          this._forceIntegerValues && (e = e | 0, i = i | 0, r = r | 0, n = n | 0, o2 = o2 | 0, l2 = l2 | 0), this.rawScrollLeft = r, this.rawScrollTop = l2, e < 0 && (e = 0), r + e > i && (r = i - e), r < 0 && (r = 0), n < 0 && (n = 0), l2 + n > o2 && (l2 = o2 - n), l2 < 0 && (l2 = 0), this.width = e, this.scrollWidth = i, this.scrollLeft = r, this.height = n, this.scrollHeight = o2, this.scrollTop = l2;
        }
        equals(t) {
          return this.rawScrollLeft === t.rawScrollLeft && this.rawScrollTop === t.rawScrollTop && this.width === t.width && this.scrollWidth === t.scrollWidth && this.scrollLeft === t.scrollLeft && this.height === t.height && this.scrollHeight === t.scrollHeight && this.scrollTop === t.scrollTop;
        }
        withScrollDimensions(t, e) {
          return new s9(this._forceIntegerValues, typeof t.width < "u" ? t.width : this.width, typeof t.scrollWidth < "u" ? t.scrollWidth : this.scrollWidth, e ? this.rawScrollLeft : this.scrollLeft, typeof t.height < "u" ? t.height : this.height, typeof t.scrollHeight < "u" ? t.scrollHeight : this.scrollHeight, e ? this.rawScrollTop : this.scrollTop);
        }
        withScrollPosition(t) {
          return new s9(this._forceIntegerValues, this.width, this.scrollWidth, typeof t.scrollLeft < "u" ? t.scrollLeft : this.rawScrollLeft, this.height, this.scrollHeight, typeof t.scrollTop < "u" ? t.scrollTop : this.rawScrollTop);
        }
        createScrollEvent(t, e) {
          let i = this.width !== t.width, r = this.scrollWidth !== t.scrollWidth, n = this.scrollLeft !== t.scrollLeft, o2 = this.height !== t.height, l2 = this.scrollHeight !== t.scrollHeight, a = this.scrollTop !== t.scrollTop;
          return { inSmoothScrolling: e, oldWidth: t.width, oldScrollWidth: t.scrollWidth, oldScrollLeft: t.scrollLeft, width: this.width, scrollWidth: this.scrollWidth, scrollLeft: this.scrollLeft, oldHeight: t.height, oldScrollHeight: t.scrollHeight, oldScrollTop: t.scrollTop, height: this.height, scrollHeight: this.scrollHeight, scrollTop: this.scrollTop, widthChanged: i, scrollWidthChanged: r, scrollLeftChanged: n, heightChanged: o2, scrollHeightChanged: l2, scrollTopChanged: a };
        }
      };
      Ri = class extends D {
        constructor(e) {
          super();
          this._scrollableBrand = void 0;
          this._onScroll = this._register(new v());
          this.onScroll = this._onScroll.event;
          this._smoothScrollDuration = e.smoothScrollDuration, this._scheduleAtNextAnimationFrame = e.scheduleAtNextAnimationFrame, this._state = new cs(e.forceIntegerValues, 0, 0, 0, 0, 0, 0), this._smoothScrolling = null;
        }
        dispose() {
          this._smoothScrolling && (this._smoothScrolling.dispose(), this._smoothScrolling = null), super.dispose();
        }
        setSmoothScrollDuration(e) {
          this._smoothScrollDuration = e;
        }
        validateScrollPosition(e) {
          return this._state.withScrollPosition(e);
        }
        getScrollDimensions() {
          return this._state;
        }
        setScrollDimensions(e, i) {
          let r = this._state.withScrollDimensions(e, i);
          this._setState(r, !!this._smoothScrolling), this._smoothScrolling?.acceptScrollDimensions(this._state);
        }
        getFutureScrollPosition() {
          return this._smoothScrolling ? this._smoothScrolling.to : this._state;
        }
        getCurrentScrollPosition() {
          return this._state;
        }
        setScrollPositionNow(e) {
          let i = this._state.withScrollPosition(e);
          this._smoothScrolling && (this._smoothScrolling.dispose(), this._smoothScrolling = null), this._setState(i, false);
        }
        setScrollPositionSmooth(e, i) {
          if (this._smoothScrollDuration === 0) return this.setScrollPositionNow(e);
          if (this._smoothScrolling) {
            e = { scrollLeft: typeof e.scrollLeft > "u" ? this._smoothScrolling.to.scrollLeft : e.scrollLeft, scrollTop: typeof e.scrollTop > "u" ? this._smoothScrolling.to.scrollTop : e.scrollTop };
            let r = this._state.withScrollPosition(e);
            if (this._smoothScrolling.to.scrollLeft === r.scrollLeft && this._smoothScrolling.to.scrollTop === r.scrollTop) return;
            let n;
            i ? n = new Nr(this._smoothScrolling.from, r, this._smoothScrolling.startTime, this._smoothScrolling.duration) : n = this._smoothScrolling.combine(this._state, r, this._smoothScrollDuration), this._smoothScrolling.dispose(), this._smoothScrolling = n;
          } else {
            let r = this._state.withScrollPosition(e);
            this._smoothScrolling = Nr.start(this._state, r, this._smoothScrollDuration);
          }
          this._smoothScrolling.animationFrameDisposable = this._scheduleAtNextAnimationFrame(() => {
            this._smoothScrolling && (this._smoothScrolling.animationFrameDisposable = null, this._performSmoothScrolling());
          });
        }
        hasPendingScrollAnimation() {
          return !!this._smoothScrolling;
        }
        _performSmoothScrolling() {
          if (!this._smoothScrolling) return;
          let e = this._smoothScrolling.tick(), i = this._state.withScrollPosition(e);
          if (this._setState(i, true), !!this._smoothScrolling) {
            if (e.isDone) {
              this._smoothScrolling.dispose(), this._smoothScrolling = null;
              return;
            }
            this._smoothScrolling.animationFrameDisposable = this._scheduleAtNextAnimationFrame(() => {
              this._smoothScrolling && (this._smoothScrolling.animationFrameDisposable = null, this._performSmoothScrolling());
            });
          }
        }
        _setState(e, i) {
          let r = this._state;
          r.equals(e) || (this._state = e, this._onScroll.fire(this._state.createScrollEvent(r, i)));
        }
      };
      Br = class {
        constructor(t, e, i) {
          this.scrollLeft = t, this.scrollTop = e, this.isDone = i;
        }
      };
      Nr = class s10 {
        constructor(t, e, i, r) {
          this.from = t, this.to = e, this.duration = r, this.startTime = i, this.animationFrameDisposable = null, this._initAnimations();
        }
        _initAnimations() {
          this.scrollLeft = this._initAnimation(this.from.scrollLeft, this.to.scrollLeft, this.to.width), this.scrollTop = this._initAnimation(this.from.scrollTop, this.to.scrollTop, this.to.height);
        }
        _initAnimation(t, e, i) {
          if (Math.abs(t - e) > 2.5 * i) {
            let n, o2;
            return t < e ? (n = t + 0.75 * i, o2 = e - 0.75 * i) : (n = t - 0.75 * i, o2 = e + 0.75 * i), La(as(t, n), as(o2, e), 0.33);
          }
          return as(t, e);
        }
        dispose() {
          this.animationFrameDisposable !== null && (this.animationFrameDisposable.dispose(), this.animationFrameDisposable = null);
        }
        acceptScrollDimensions(t) {
          this.to = t.withScrollPosition(this.to), this._initAnimations();
        }
        tick() {
          return this._tick(Date.now());
        }
        _tick(t) {
          let e = (t - this.startTime) / this.duration;
          if (e < 1) {
            let i = this.scrollLeft(e), r = this.scrollTop(e);
            return new Br(i, r, false);
          }
          return new Br(this.to.scrollLeft, this.to.scrollTop, true);
        }
        combine(t, e, i) {
          return s10.start(t, e, i);
        }
        static start(t, e, i) {
          i = i + 10;
          let r = Date.now() - 10;
          return new s10(t, e, r, i);
        }
      };
      Fr = class extends D {
        constructor(t, e, i) {
          super(), this._visibility = t, this._visibleClassName = e, this._invisibleClassName = i, this._domNode = null, this._isVisible = false, this._isNeeded = false, this._rawShouldBeVisible = false, this._shouldBeVisible = false, this._revealTimer = this._register(new Ye());
        }
        setVisibility(t) {
          this._visibility !== t && (this._visibility = t, this._updateShouldBeVisible());
        }
        setShouldBeVisible(t) {
          this._rawShouldBeVisible = t, this._updateShouldBeVisible();
        }
        _applyVisibilitySetting() {
          return this._visibility === 2 ? false : this._visibility === 3 ? true : this._rawShouldBeVisible;
        }
        _updateShouldBeVisible() {
          let t = this._applyVisibilitySetting();
          this._shouldBeVisible !== t && (this._shouldBeVisible = t, this.ensureVisibility());
        }
        setIsNeeded(t) {
          this._isNeeded !== t && (this._isNeeded = t, this.ensureVisibility());
        }
        setDomNode(t) {
          this._domNode = t, this._domNode.setClassName(this._invisibleClassName), this.setShouldBeVisible(false);
        }
        ensureVisibility() {
          if (!this._isNeeded) {
            this._hide(false);
            return;
          }
          this._shouldBeVisible ? this._reveal() : this._hide(true);
        }
        _reveal() {
          this._isVisible || (this._isVisible = true, this._revealTimer.setIfNotSet(() => {
            this._domNode?.setClassName(this._visibleClassName);
          }, 0));
        }
        _hide(t) {
          this._revealTimer.cancel(), this._isVisible && (this._isVisible = false, this._domNode?.setClassName(this._invisibleClassName + (t ? " fade" : "")));
        }
      };
      Ca = 140;
      Ut = class extends lt {
        constructor(t) {
          super(), this._lazyRender = t.lazyRender, this._host = t.host, this._scrollable = t.scrollable, this._scrollByPage = t.scrollByPage, this._scrollbarState = t.scrollbarState, this._visibilityController = this._register(new Fr(t.visibility, "visible scrollbar " + t.extraScrollbarClassName, "invisible scrollbar " + t.extraScrollbarClassName)), this._visibilityController.setIsNeeded(this._scrollbarState.isNeeded()), this._pointerMoveMonitor = this._register(new Wt()), this._shouldRender = true, this.domNode = _t(document.createElement("div")), this.domNode.setAttribute("role", "presentation"), this.domNode.setAttribute("aria-hidden", "true"), this._visibilityController.setDomNode(this.domNode), this.domNode.setPosition("absolute"), this._register(L(this.domNode.domNode, Y.POINTER_DOWN, (e) => this._domNodePointerDown(e)));
        }
        _createArrow(t) {
          let e = this._register(new Or(t));
          this.domNode.domNode.appendChild(e.bgDomNode), this.domNode.domNode.appendChild(e.domNode);
        }
        _createSlider(t, e, i, r) {
          this.slider = _t(document.createElement("div")), this.slider.setClassName("slider"), this.slider.setPosition("absolute"), this.slider.setTop(t), this.slider.setLeft(e), typeof i == "number" && this.slider.setWidth(i), typeof r == "number" && this.slider.setHeight(r), this.slider.setLayerHinting(true), this.slider.setContain("strict"), this.domNode.domNode.appendChild(this.slider.domNode), this._register(L(this.slider.domNode, Y.POINTER_DOWN, (n) => {
            n.button === 0 && (n.preventDefault(), this._sliderPointerDown(n));
          })), this.onclick(this.slider.domNode, (n) => {
            n.leftButton && n.stopPropagation();
          });
        }
        _onElementSize(t) {
          return this._scrollbarState.setVisibleSize(t) && (this._visibilityController.setIsNeeded(this._scrollbarState.isNeeded()), this._shouldRender = true, this._lazyRender || this.render()), this._shouldRender;
        }
        _onElementScrollSize(t) {
          return this._scrollbarState.setScrollSize(t) && (this._visibilityController.setIsNeeded(this._scrollbarState.isNeeded()), this._shouldRender = true, this._lazyRender || this.render()), this._shouldRender;
        }
        _onElementScrollPosition(t) {
          return this._scrollbarState.setScrollPosition(t) && (this._visibilityController.setIsNeeded(this._scrollbarState.isNeeded()), this._shouldRender = true, this._lazyRender || this.render()), this._shouldRender;
        }
        beginReveal() {
          this._visibilityController.setShouldBeVisible(true);
        }
        beginHide() {
          this._visibilityController.setShouldBeVisible(false);
        }
        render() {
          this._shouldRender && (this._shouldRender = false, this._renderDomNode(this._scrollbarState.getRectangleLargeSize(), this._scrollbarState.getRectangleSmallSize()), this._updateSlider(this._scrollbarState.getSliderSize(), this._scrollbarState.getArrowSize() + this._scrollbarState.getSliderPosition()));
        }
        _domNodePointerDown(t) {
          t.target === this.domNode.domNode && this._onPointerDown(t);
        }
        delegatePointerDown(t) {
          let e = this.domNode.domNode.getClientRects()[0].top, i = e + this._scrollbarState.getSliderPosition(), r = e + this._scrollbarState.getSliderPosition() + this._scrollbarState.getSliderSize(), n = this._sliderPointerPosition(t);
          i <= n && n <= r ? t.button === 0 && (t.preventDefault(), this._sliderPointerDown(t)) : this._onPointerDown(t);
        }
        _onPointerDown(t) {
          let e, i;
          if (t.target === this.domNode.domNode && typeof t.offsetX == "number" && typeof t.offsetY == "number") e = t.offsetX, i = t.offsetY;
          else {
            let n = Fo(this.domNode.domNode);
            e = t.pageX - n.left, i = t.pageY - n.top;
          }
          let r = this._pointerDownRelativePosition(e, i);
          this._setDesiredScrollPositionNow(this._scrollByPage ? this._scrollbarState.getDesiredScrollPositionFromOffsetPaged(r) : this._scrollbarState.getDesiredScrollPositionFromOffset(r)), t.button === 0 && (t.preventDefault(), this._sliderPointerDown(t));
        }
        _sliderPointerDown(t) {
          if (!t.target || !(t.target instanceof Element)) return;
          let e = this._sliderPointerPosition(t), i = this._sliderOrthogonalPointerPosition(t), r = this._scrollbarState.clone();
          this.slider.toggleClassName("active", true), this._pointerMoveMonitor.startMonitoring(t.target, t.pointerId, t.buttons, (n) => {
            let o2 = this._sliderOrthogonalPointerPosition(n), l2 = Math.abs(o2 - i);
            if (wr && l2 > Ca) {
              this._setDesiredScrollPositionNow(r.getScrollPosition());
              return;
            }
            let u = this._sliderPointerPosition(n) - e;
            this._setDesiredScrollPositionNow(r.getDesiredScrollPositionFromDelta(u));
          }, () => {
            this.slider.toggleClassName("active", false), this._host.onDragEnd();
          }), this._host.onDragStart();
        }
        _setDesiredScrollPositionNow(t) {
          let e = {};
          this.writeScrollPosition(e, t), this._scrollable.setScrollPositionNow(e);
        }
        updateScrollbarSize(t) {
          this._updateScrollbarSize(t), this._scrollbarState.setScrollbarSize(t), this._shouldRender = true, this._lazyRender || this.render();
        }
        isNeeded() {
          return this._scrollbarState.isNeeded();
        }
      };
      Kt = class s11 {
        constructor(t, e, i, r, n, o2) {
          this._scrollbarSize = Math.round(e), this._oppositeScrollbarSize = Math.round(i), this._arrowSize = Math.round(t), this._visibleSize = r, this._scrollSize = n, this._scrollPosition = o2, this._computedAvailableSize = 0, this._computedIsNeeded = false, this._computedSliderSize = 0, this._computedSliderRatio = 0, this._computedSliderPosition = 0, this._refreshComputedValues();
        }
        clone() {
          return new s11(this._arrowSize, this._scrollbarSize, this._oppositeScrollbarSize, this._visibleSize, this._scrollSize, this._scrollPosition);
        }
        setVisibleSize(t) {
          let e = Math.round(t);
          return this._visibleSize !== e ? (this._visibleSize = e, this._refreshComputedValues(), true) : false;
        }
        setScrollSize(t) {
          let e = Math.round(t);
          return this._scrollSize !== e ? (this._scrollSize = e, this._refreshComputedValues(), true) : false;
        }
        setScrollPosition(t) {
          let e = Math.round(t);
          return this._scrollPosition !== e ? (this._scrollPosition = e, this._refreshComputedValues(), true) : false;
        }
        setScrollbarSize(t) {
          this._scrollbarSize = Math.round(t);
        }
        setOppositeScrollbarSize(t) {
          this._oppositeScrollbarSize = Math.round(t);
        }
        static _computeValues(t, e, i, r, n) {
          let o2 = Math.max(0, i - t), l2 = Math.max(0, o2 - 2 * e), a = r > 0 && r > i;
          if (!a) return { computedAvailableSize: Math.round(o2), computedIsNeeded: a, computedSliderSize: Math.round(l2), computedSliderRatio: 0, computedSliderPosition: 0 };
          let u = Math.round(Math.max(20, Math.floor(i * l2 / r))), h2 = (l2 - u) / (r - i), c = n * h2;
          return { computedAvailableSize: Math.round(o2), computedIsNeeded: a, computedSliderSize: Math.round(u), computedSliderRatio: h2, computedSliderPosition: Math.round(c) };
        }
        _refreshComputedValues() {
          let t = s11._computeValues(this._oppositeScrollbarSize, this._arrowSize, this._visibleSize, this._scrollSize, this._scrollPosition);
          this._computedAvailableSize = t.computedAvailableSize, this._computedIsNeeded = t.computedIsNeeded, this._computedSliderSize = t.computedSliderSize, this._computedSliderRatio = t.computedSliderRatio, this._computedSliderPosition = t.computedSliderPosition;
        }
        getArrowSize() {
          return this._arrowSize;
        }
        getScrollPosition() {
          return this._scrollPosition;
        }
        getRectangleLargeSize() {
          return this._computedAvailableSize;
        }
        getRectangleSmallSize() {
          return this._scrollbarSize;
        }
        isNeeded() {
          return this._computedIsNeeded;
        }
        getSliderSize() {
          return this._computedSliderSize;
        }
        getSliderPosition() {
          return this._computedSliderPosition;
        }
        getDesiredScrollPositionFromOffset(t) {
          if (!this._computedIsNeeded) return 0;
          let e = t - this._arrowSize - this._computedSliderSize / 2;
          return Math.round(e / this._computedSliderRatio);
        }
        getDesiredScrollPositionFromOffsetPaged(t) {
          if (!this._computedIsNeeded) return 0;
          let e = t - this._arrowSize, i = this._scrollPosition;
          return e < this._computedSliderPosition ? i -= this._visibleSize : i += this._visibleSize, i;
        }
        getDesiredScrollPositionFromDelta(t) {
          if (!this._computedIsNeeded) return 0;
          let e = this._computedSliderPosition + t;
          return Math.round(e / this._computedSliderRatio);
        }
      };
      Wr = class extends Ut {
        constructor(t, e, i) {
          let r = t.getScrollDimensions(), n = t.getCurrentScrollPosition();
          if (super({ lazyRender: e.lazyRender, host: i, scrollbarState: new Kt(e.horizontalHasArrows ? e.arrowSize : 0, e.horizontal === 2 ? 0 : e.horizontalScrollbarSize, e.vertical === 2 ? 0 : e.verticalScrollbarSize, r.width, r.scrollWidth, n.scrollLeft), visibility: e.horizontal, extraScrollbarClassName: "horizontal", scrollable: t, scrollByPage: e.scrollByPage }), e.horizontalHasArrows) throw new Error("horizontalHasArrows is not supported in xterm.js");
          this._createSlider(Math.floor((e.horizontalScrollbarSize - e.horizontalSliderSize) / 2), 0, void 0, e.horizontalSliderSize);
        }
        _updateSlider(t, e) {
          this.slider.setWidth(t), this.slider.setLeft(e);
        }
        _renderDomNode(t, e) {
          this.domNode.setWidth(t), this.domNode.setHeight(e), this.domNode.setLeft(0), this.domNode.setBottom(0);
        }
        onDidScroll(t) {
          return this._shouldRender = this._onElementScrollSize(t.scrollWidth) || this._shouldRender, this._shouldRender = this._onElementScrollPosition(t.scrollLeft) || this._shouldRender, this._shouldRender = this._onElementSize(t.width) || this._shouldRender, this._shouldRender;
        }
        _pointerDownRelativePosition(t, e) {
          return t;
        }
        _sliderPointerPosition(t) {
          return t.pageX;
        }
        _sliderOrthogonalPointerPosition(t) {
          return t.pageY;
        }
        _updateScrollbarSize(t) {
          this.slider.setHeight(t);
        }
        writeScrollPosition(t, e) {
          t.scrollLeft = e;
        }
        updateOptions(t) {
          this.updateScrollbarSize(t.horizontal === 2 ? 0 : t.horizontalScrollbarSize), this._scrollbarState.setOppositeScrollbarSize(t.vertical === 2 ? 0 : t.verticalScrollbarSize), this._visibilityController.setVisibility(t.horizontal), this._scrollByPage = t.scrollByPage;
        }
      };
      Ur = class extends Ut {
        constructor(t, e, i) {
          let r = t.getScrollDimensions(), n = t.getCurrentScrollPosition();
          if (super({ lazyRender: e.lazyRender, host: i, scrollbarState: new Kt(e.verticalHasArrows ? e.arrowSize : 0, e.vertical === 2 ? 0 : e.verticalScrollbarSize, 0, r.height, r.scrollHeight, n.scrollTop), visibility: e.vertical, extraScrollbarClassName: "vertical", scrollable: t, scrollByPage: e.scrollByPage }), e.verticalHasArrows) throw new Error("horizontalHasArrows is not supported in xterm.js");
          this._createSlider(0, Math.floor((e.verticalScrollbarSize - e.verticalSliderSize) / 2), e.verticalSliderSize, void 0);
        }
        _updateSlider(t, e) {
          this.slider.setHeight(t), this.slider.setTop(e);
        }
        _renderDomNode(t, e) {
          this.domNode.setWidth(e), this.domNode.setHeight(t), this.domNode.setRight(0), this.domNode.setTop(0);
        }
        onDidScroll(t) {
          return this._shouldRender = this._onElementScrollSize(t.scrollHeight) || this._shouldRender, this._shouldRender = this._onElementScrollPosition(t.scrollTop) || this._shouldRender, this._shouldRender = this._onElementSize(t.height) || this._shouldRender, this._shouldRender;
        }
        _pointerDownRelativePosition(t, e) {
          return e;
        }
        _sliderPointerPosition(t) {
          return t.pageY;
        }
        _sliderOrthogonalPointerPosition(t) {
          return t.pageX;
        }
        _updateScrollbarSize(t) {
          this.slider.setWidth(t);
        }
        writeScrollPosition(t, e) {
          t.scrollTop = e;
        }
        updateOptions(t) {
          this.updateScrollbarSize(t.vertical === 2 ? 0 : t.verticalScrollbarSize), this._scrollbarState.setOppositeScrollbarSize(0), this._visibilityController.setVisibility(t.vertical), this._scrollByPage = t.scrollByPage;
        }
      };
      Ma = 500;
      Ko = 50;
      zo = true;
      us = class {
        constructor(t, e, i) {
          this.timestamp = t, this.deltaX = e, this.deltaY = i, this.score = 0;
        }
      };
      zr = class zr2 {
        constructor() {
          this._capacity = 5, this._memory = [], this._front = -1, this._rear = -1;
        }
        isPhysicalMouseWheel() {
          if (this._front === -1 && this._rear === -1) return false;
          let t = 1, e = 0, i = 1, r = this._rear;
          do {
            let n = r === this._front ? t : Math.pow(2, -i);
            if (t -= n, e += this._memory[r].score * n, r === this._front) break;
            r = (this._capacity + r - 1) % this._capacity, i++;
          } while (true);
          return e <= 0.5;
        }
        acceptStandardWheelEvent(t) {
          if (Ti) {
            let e = be(t.browserEvent), i = mo(e);
            this.accept(Date.now(), t.deltaX * i, t.deltaY * i);
          } else this.accept(Date.now(), t.deltaX, t.deltaY);
        }
        accept(t, e, i) {
          let r = null, n = new us(t, e, i);
          this._front === -1 && this._rear === -1 ? (this._memory[0] = n, this._front = 0, this._rear = 0) : (r = this._memory[this._rear], this._rear = (this._rear + 1) % this._capacity, this._rear === this._front && (this._front = (this._front + 1) % this._capacity), this._memory[this._rear] = n), n.score = this._computeScore(n, r);
        }
        _computeScore(t, e) {
          if (Math.abs(t.deltaX) > 0 && Math.abs(t.deltaY) > 0) return 1;
          let i = 0.5;
          if ((!this._isAlmostInt(t.deltaX) || !this._isAlmostInt(t.deltaY)) && (i += 0.25), e) {
            let r = Math.abs(t.deltaX), n = Math.abs(t.deltaY), o2 = Math.abs(e.deltaX), l2 = Math.abs(e.deltaY), a = Math.max(Math.min(r, o2), 1), u = Math.max(Math.min(n, l2), 1), h2 = Math.max(r, o2), c = Math.max(n, l2);
            h2 % a === 0 && c % u === 0 && (i -= 0.5);
          }
          return Math.min(Math.max(i, 0), 1);
        }
        _isAlmostInt(t) {
          return Math.abs(Math.round(t) - t) < 0.01;
        }
      };
      zr.INSTANCE = new zr();
      hs = zr;
      ds = class extends lt {
        constructor(e, i, r) {
          super();
          this._onScroll = this._register(new v());
          this.onScroll = this._onScroll.event;
          this._onWillScroll = this._register(new v());
          this.onWillScroll = this._onWillScroll.event;
          this._options = Pa(i), this._scrollable = r, this._register(this._scrollable.onScroll((o2) => {
            this._onWillScroll.fire(o2), this._onDidScroll(o2), this._onScroll.fire(o2);
          }));
          let n = { onMouseWheel: (o2) => this._onMouseWheel(o2), onDragStart: () => this._onDragStart(), onDragEnd: () => this._onDragEnd() };
          this._verticalScrollbar = this._register(new Ur(this._scrollable, this._options, n)), this._horizontalScrollbar = this._register(new Wr(this._scrollable, this._options, n)), this._domNode = document.createElement("div"), this._domNode.className = "xterm-scrollable-element " + this._options.className, this._domNode.setAttribute("role", "presentation"), this._domNode.style.position = "relative", this._domNode.appendChild(e), this._domNode.appendChild(this._horizontalScrollbar.domNode.domNode), this._domNode.appendChild(this._verticalScrollbar.domNode.domNode), this._options.useShadows ? (this._leftShadowDomNode = _t(document.createElement("div")), this._leftShadowDomNode.setClassName("shadow"), this._domNode.appendChild(this._leftShadowDomNode.domNode), this._topShadowDomNode = _t(document.createElement("div")), this._topShadowDomNode.setClassName("shadow"), this._domNode.appendChild(this._topShadowDomNode.domNode), this._topLeftShadowDomNode = _t(document.createElement("div")), this._topLeftShadowDomNode.setClassName("shadow"), this._domNode.appendChild(this._topLeftShadowDomNode.domNode)) : (this._leftShadowDomNode = null, this._topShadowDomNode = null, this._topLeftShadowDomNode = null), this._listenOnDomNode = this._options.listenOnDomNode || this._domNode, this._mouseWheelToDispose = [], this._setListeningToMouseWheel(this._options.handleMouseWheel), this.onmouseover(this._listenOnDomNode, (o2) => this._onMouseOver(o2)), this.onmouseleave(this._listenOnDomNode, (o2) => this._onMouseLeave(o2)), this._hideTimeout = this._register(new Ye()), this._isDragging = false, this._mouseIsOver = false, this._shouldRender = true, this._revealOnScroll = true;
        }
        get options() {
          return this._options;
        }
        dispose() {
          this._mouseWheelToDispose = Ne(this._mouseWheelToDispose), super.dispose();
        }
        getDomNode() {
          return this._domNode;
        }
        getOverviewRulerLayoutInfo() {
          return { parent: this._domNode, insertBefore: this._verticalScrollbar.domNode.domNode };
        }
        delegateVerticalScrollbarPointerDown(e) {
          this._verticalScrollbar.delegatePointerDown(e);
        }
        getScrollDimensions() {
          return this._scrollable.getScrollDimensions();
        }
        setScrollDimensions(e) {
          this._scrollable.setScrollDimensions(e, false);
        }
        updateClassName(e) {
          this._options.className = e, Te && (this._options.className += " mac"), this._domNode.className = "xterm-scrollable-element " + this._options.className;
        }
        updateOptions(e) {
          typeof e.handleMouseWheel < "u" && (this._options.handleMouseWheel = e.handleMouseWheel, this._setListeningToMouseWheel(this._options.handleMouseWheel)), typeof e.mouseWheelScrollSensitivity < "u" && (this._options.mouseWheelScrollSensitivity = e.mouseWheelScrollSensitivity), typeof e.fastScrollSensitivity < "u" && (this._options.fastScrollSensitivity = e.fastScrollSensitivity), typeof e.scrollPredominantAxis < "u" && (this._options.scrollPredominantAxis = e.scrollPredominantAxis), typeof e.horizontal < "u" && (this._options.horizontal = e.horizontal), typeof e.vertical < "u" && (this._options.vertical = e.vertical), typeof e.horizontalScrollbarSize < "u" && (this._options.horizontalScrollbarSize = e.horizontalScrollbarSize), typeof e.verticalScrollbarSize < "u" && (this._options.verticalScrollbarSize = e.verticalScrollbarSize), typeof e.scrollByPage < "u" && (this._options.scrollByPage = e.scrollByPage), this._horizontalScrollbar.updateOptions(this._options), this._verticalScrollbar.updateOptions(this._options), this._options.lazyRender || this._render();
        }
        setRevealOnScroll(e) {
          this._revealOnScroll = e;
        }
        delegateScrollFromMouseWheelEvent(e) {
          this._onMouseWheel(new xi(e));
        }
        _setListeningToMouseWheel(e) {
          if (this._mouseWheelToDispose.length > 0 !== e && (this._mouseWheelToDispose = Ne(this._mouseWheelToDispose), e)) {
            let r = (n) => {
              this._onMouseWheel(new xi(n));
            };
            this._mouseWheelToDispose.push(L(this._listenOnDomNode, Y.MOUSE_WHEEL, r, { passive: false }));
          }
        }
        _onMouseWheel(e) {
          if (e.browserEvent?.defaultPrevented) return;
          let i = hs.INSTANCE;
          zo && i.acceptStandardWheelEvent(e);
          let r = false;
          if (e.deltaY || e.deltaX) {
            let o2 = e.deltaY * this._options.mouseWheelScrollSensitivity, l2 = e.deltaX * this._options.mouseWheelScrollSensitivity;
            this._options.scrollPredominantAxis && (this._options.scrollYToX && l2 + o2 === 0 ? l2 = o2 = 0 : Math.abs(o2) >= Math.abs(l2) ? l2 = 0 : o2 = 0), this._options.flipAxes && ([o2, l2] = [l2, o2]);
            let a = !Te && e.browserEvent && e.browserEvent.shiftKey;
            (this._options.scrollYToX || a) && !l2 && (l2 = o2, o2 = 0), e.browserEvent && e.browserEvent.altKey && (l2 = l2 * this._options.fastScrollSensitivity, o2 = o2 * this._options.fastScrollSensitivity);
            let u = this._scrollable.getFutureScrollPosition(), h2 = {};
            if (o2) {
              let c = Ko * o2, d = u.scrollTop - (c < 0 ? Math.floor(c) : Math.ceil(c));
              this._verticalScrollbar.writeScrollPosition(h2, d);
            }
            if (l2) {
              let c = Ko * l2, d = u.scrollLeft - (c < 0 ? Math.floor(c) : Math.ceil(c));
              this._horizontalScrollbar.writeScrollPosition(h2, d);
            }
            h2 = this._scrollable.validateScrollPosition(h2), (u.scrollLeft !== h2.scrollLeft || u.scrollTop !== h2.scrollTop) && (zo && this._options.mouseWheelSmoothScroll && i.isPhysicalMouseWheel() ? this._scrollable.setScrollPositionSmooth(h2) : this._scrollable.setScrollPositionNow(h2), r = true);
          }
          let n = r;
          !n && this._options.alwaysConsumeMouseWheel && (n = true), !n && this._options.consumeMouseWheelIfScrollbarIsNeeded && (this._verticalScrollbar.isNeeded() || this._horizontalScrollbar.isNeeded()) && (n = true), n && (e.preventDefault(), e.stopPropagation());
        }
        _onDidScroll(e) {
          this._shouldRender = this._horizontalScrollbar.onDidScroll(e) || this._shouldRender, this._shouldRender = this._verticalScrollbar.onDidScroll(e) || this._shouldRender, this._options.useShadows && (this._shouldRender = true), this._revealOnScroll && this._reveal(), this._options.lazyRender || this._render();
        }
        renderNow() {
          if (!this._options.lazyRender) throw new Error("Please use `lazyRender` together with `renderNow`!");
          this._render();
        }
        _render() {
          if (this._shouldRender && (this._shouldRender = false, this._horizontalScrollbar.render(), this._verticalScrollbar.render(), this._options.useShadows)) {
            let e = this._scrollable.getCurrentScrollPosition(), i = e.scrollTop > 0, r = e.scrollLeft > 0, n = r ? " left" : "", o2 = i ? " top" : "", l2 = r || i ? " top-left-corner" : "";
            this._leftShadowDomNode.setClassName(`shadow${n}`), this._topShadowDomNode.setClassName(`shadow${o2}`), this._topLeftShadowDomNode.setClassName(`shadow${l2}${o2}${n}`);
          }
        }
        _onDragStart() {
          this._isDragging = true, this._reveal();
        }
        _onDragEnd() {
          this._isDragging = false, this._hide();
        }
        _onMouseLeave(e) {
          this._mouseIsOver = false, this._hide();
        }
        _onMouseOver(e) {
          this._mouseIsOver = true, this._reveal();
        }
        _reveal() {
          this._verticalScrollbar.beginReveal(), this._horizontalScrollbar.beginReveal(), this._scheduleHide();
        }
        _hide() {
          !this._mouseIsOver && !this._isDragging && (this._verticalScrollbar.beginHide(), this._horizontalScrollbar.beginHide());
        }
        _scheduleHide() {
          !this._mouseIsOver && !this._isDragging && this._hideTimeout.cancelAndSet(() => this._hide(), Ma);
        }
      };
      Kr = class extends ds {
        constructor(t, e, i) {
          super(t, e, i);
        }
        setScrollPosition(t) {
          t.reuseAnimation ? this._scrollable.setScrollPositionSmooth(t, t.reuseAnimation) : this._scrollable.setScrollPositionNow(t);
        }
        getScrollPosition() {
          return this._scrollable.getCurrentScrollPosition();
        }
      };
      zt = class extends D {
        constructor(e, i, r, n, o2, l2, a, u) {
          super();
          this._bufferService = r;
          this._optionsService = a;
          this._renderService = u;
          this._onRequestScrollLines = this._register(new v());
          this.onRequestScrollLines = this._onRequestScrollLines.event;
          this._isSyncing = false;
          this._isHandlingScroll = false;
          this._suppressOnScrollHandler = false;
          let h2 = this._register(new Ri({ forceIntegerValues: false, smoothScrollDuration: this._optionsService.rawOptions.smoothScrollDuration, scheduleAtNextAnimationFrame: (c) => mt(n.window, c) }));
          this._register(this._optionsService.onSpecificOptionChange("smoothScrollDuration", () => {
            h2.setSmoothScrollDuration(this._optionsService.rawOptions.smoothScrollDuration);
          })), this._scrollableElement = this._register(new Kr(i, { vertical: 1, horizontal: 2, useShadows: false, mouseWheelSmoothScroll: true, ...this._getChangeOptions() }, h2)), this._register(this._optionsService.onMultipleOptionChange(["scrollSensitivity", "fastScrollSensitivity", "overviewRuler"], () => this._scrollableElement.updateOptions(this._getChangeOptions()))), this._register(o2.onProtocolChange((c) => {
            this._scrollableElement.updateOptions({ handleMouseWheel: !(c & 16) });
          })), this._scrollableElement.setScrollDimensions({ height: 0, scrollHeight: 0 }), this._register($.runAndSubscribe(l2.onChangeColors, () => {
            this._scrollableElement.getDomNode().style.backgroundColor = l2.colors.background.css;
          })), e.appendChild(this._scrollableElement.getDomNode()), this._register(C(() => this._scrollableElement.getDomNode().remove())), this._styleElement = n.mainDocument.createElement("style"), i.appendChild(this._styleElement), this._register(C(() => this._styleElement.remove())), this._register($.runAndSubscribe(l2.onChangeColors, () => {
            this._styleElement.textContent = [".xterm .xterm-scrollable-element > .scrollbar > .slider {", `  background: ${l2.colors.scrollbarSliderBackground.css};`, "}", ".xterm .xterm-scrollable-element > .scrollbar > .slider:hover {", `  background: ${l2.colors.scrollbarSliderHoverBackground.css};`, "}", ".xterm .xterm-scrollable-element > .scrollbar > .slider.active {", `  background: ${l2.colors.scrollbarSliderActiveBackground.css};`, "}"].join(`
`);
          })), this._register(this._bufferService.onResize(() => this.queueSync())), this._register(this._bufferService.buffers.onBufferActivate(() => {
            this._latestYDisp = void 0, this.queueSync();
          })), this._register(this._bufferService.onScroll(() => this._sync())), this._register(this._scrollableElement.onScroll((c) => this._handleScroll(c)));
        }
        scrollLines(e) {
          let i = this._scrollableElement.getScrollPosition();
          this._scrollableElement.setScrollPosition({ reuseAnimation: true, scrollTop: i.scrollTop + e * this._renderService.dimensions.css.cell.height });
        }
        scrollToLine(e, i) {
          i && (this._latestYDisp = e), this._scrollableElement.setScrollPosition({ reuseAnimation: !i, scrollTop: e * this._renderService.dimensions.css.cell.height });
        }
        _getChangeOptions() {
          return { mouseWheelScrollSensitivity: this._optionsService.rawOptions.scrollSensitivity, fastScrollSensitivity: this._optionsService.rawOptions.fastScrollSensitivity, verticalScrollbarSize: this._optionsService.rawOptions.overviewRuler?.width || 14 };
        }
        queueSync(e) {
          e !== void 0 && (this._latestYDisp = e), this._queuedAnimationFrame === void 0 && (this._queuedAnimationFrame = this._renderService.addRefreshCallback(() => {
            this._queuedAnimationFrame = void 0, this._sync(this._latestYDisp);
          }));
        }
        _sync(e = this._bufferService.buffer.ydisp) {
          !this._renderService || this._isSyncing || (this._isSyncing = true, this._suppressOnScrollHandler = true, this._scrollableElement.setScrollDimensions({ height: this._renderService.dimensions.css.canvas.height, scrollHeight: this._renderService.dimensions.css.cell.height * this._bufferService.buffer.lines.length }), this._suppressOnScrollHandler = false, e !== this._latestYDisp && this._scrollableElement.setScrollPosition({ scrollTop: e * this._renderService.dimensions.css.cell.height }), this._isSyncing = false);
        }
        _handleScroll(e) {
          if (!this._renderService || this._isHandlingScroll || this._suppressOnScrollHandler) return;
          this._isHandlingScroll = true;
          let i = Math.round(e.scrollTop / this._renderService.dimensions.css.cell.height), r = i - this._bufferService.buffer.ydisp;
          r !== 0 && (this._latestYDisp = i, this._onRequestScrollLines.fire(r)), this._isHandlingScroll = false;
        }
      };
      zt = M([S(2, F), S(3, ae), S(4, rr), S(5, Re), S(6, H), S(7, ce)], zt);
      Gt = class extends D {
        constructor(e, i, r, n, o2) {
          super();
          this._screenElement = e;
          this._bufferService = i;
          this._coreBrowserService = r;
          this._decorationService = n;
          this._renderService = o2;
          this._decorationElements = /* @__PURE__ */ new Map();
          this._altBufferIsActive = false;
          this._dimensionsChanged = false;
          this._container = document.createElement("div"), this._container.classList.add("xterm-decoration-container"), this._screenElement.appendChild(this._container), this._register(this._renderService.onRenderedViewportChange(() => this._doRefreshDecorations())), this._register(this._renderService.onDimensionsChange(() => {
            this._dimensionsChanged = true, this._queueRefresh();
          })), this._register(this._coreBrowserService.onDprChange(() => this._queueRefresh())), this._register(this._bufferService.buffers.onBufferActivate(() => {
            this._altBufferIsActive = this._bufferService.buffer === this._bufferService.buffers.alt;
          })), this._register(this._decorationService.onDecorationRegistered(() => this._queueRefresh())), this._register(this._decorationService.onDecorationRemoved((l2) => this._removeDecoration(l2))), this._register(C(() => {
            this._container.remove(), this._decorationElements.clear();
          }));
        }
        _queueRefresh() {
          this._animationFrame === void 0 && (this._animationFrame = this._renderService.addRefreshCallback(() => {
            this._doRefreshDecorations(), this._animationFrame = void 0;
          }));
        }
        _doRefreshDecorations() {
          for (let e of this._decorationService.decorations) this._renderDecoration(e);
          this._dimensionsChanged = false;
        }
        _renderDecoration(e) {
          this._refreshStyle(e), this._dimensionsChanged && this._refreshXPosition(e);
        }
        _createElement(e) {
          let i = this._coreBrowserService.mainDocument.createElement("div");
          i.classList.add("xterm-decoration"), i.classList.toggle("xterm-decoration-top-layer", e?.options?.layer === "top"), i.style.width = `${Math.round((e.options.width || 1) * this._renderService.dimensions.css.cell.width)}px`, i.style.height = `${(e.options.height || 1) * this._renderService.dimensions.css.cell.height}px`, i.style.top = `${(e.marker.line - this._bufferService.buffers.active.ydisp) * this._renderService.dimensions.css.cell.height}px`, i.style.lineHeight = `${this._renderService.dimensions.css.cell.height}px`;
          let r = e.options.x ?? 0;
          return r && r > this._bufferService.cols && (i.style.display = "none"), this._refreshXPosition(e, i), i;
        }
        _refreshStyle(e) {
          let i = e.marker.line - this._bufferService.buffers.active.ydisp;
          if (i < 0 || i >= this._bufferService.rows) e.element && (e.element.style.display = "none", e.onRenderEmitter.fire(e.element));
          else {
            let r = this._decorationElements.get(e);
            r || (r = this._createElement(e), e.element = r, this._decorationElements.set(e, r), this._container.appendChild(r), e.onDispose(() => {
              this._decorationElements.delete(e), r.remove();
            })), r.style.display = this._altBufferIsActive ? "none" : "block", this._altBufferIsActive || (r.style.width = `${Math.round((e.options.width || 1) * this._renderService.dimensions.css.cell.width)}px`, r.style.height = `${(e.options.height || 1) * this._renderService.dimensions.css.cell.height}px`, r.style.top = `${i * this._renderService.dimensions.css.cell.height}px`, r.style.lineHeight = `${this._renderService.dimensions.css.cell.height}px`), e.onRenderEmitter.fire(r);
          }
        }
        _refreshXPosition(e, i = e.element) {
          if (!i) return;
          let r = e.options.x ?? 0;
          (e.options.anchor || "left") === "right" ? i.style.right = r ? `${r * this._renderService.dimensions.css.cell.width}px` : "" : i.style.left = r ? `${r * this._renderService.dimensions.css.cell.width}px` : "";
        }
        _removeDecoration(e) {
          this._decorationElements.get(e)?.remove(), this._decorationElements.delete(e), e.dispose();
        }
      };
      Gt = M([S(1, F), S(2, ae), S(3, Be), S(4, ce)], Gt);
      Gr = class {
        constructor() {
          this._zones = [];
          this._zonePool = [];
          this._zonePoolIndex = 0;
          this._linePadding = { full: 0, left: 0, center: 0, right: 0 };
        }
        get zones() {
          return this._zonePool.length = Math.min(this._zonePool.length, this._zones.length), this._zones;
        }
        clear() {
          this._zones.length = 0, this._zonePoolIndex = 0;
        }
        addDecoration(t) {
          if (t.options.overviewRulerOptions) {
            for (let e of this._zones) if (e.color === t.options.overviewRulerOptions.color && e.position === t.options.overviewRulerOptions.position) {
              if (this._lineIntersectsZone(e, t.marker.line)) return;
              if (this._lineAdjacentToZone(e, t.marker.line, t.options.overviewRulerOptions.position)) {
                this._addLineToZone(e, t.marker.line);
                return;
              }
            }
            if (this._zonePoolIndex < this._zonePool.length) {
              this._zonePool[this._zonePoolIndex].color = t.options.overviewRulerOptions.color, this._zonePool[this._zonePoolIndex].position = t.options.overviewRulerOptions.position, this._zonePool[this._zonePoolIndex].startBufferLine = t.marker.line, this._zonePool[this._zonePoolIndex].endBufferLine = t.marker.line, this._zones.push(this._zonePool[this._zonePoolIndex++]);
              return;
            }
            this._zones.push({ color: t.options.overviewRulerOptions.color, position: t.options.overviewRulerOptions.position, startBufferLine: t.marker.line, endBufferLine: t.marker.line }), this._zonePool.push(this._zones[this._zones.length - 1]), this._zonePoolIndex++;
          }
        }
        setPadding(t) {
          this._linePadding = t;
        }
        _lineIntersectsZone(t, e) {
          return e >= t.startBufferLine && e <= t.endBufferLine;
        }
        _lineAdjacentToZone(t, e, i) {
          return e >= t.startBufferLine - this._linePadding[i || "full"] && e <= t.endBufferLine + this._linePadding[i || "full"];
        }
        _addLineToZone(t, e) {
          t.startBufferLine = Math.min(t.startBufferLine, e), t.endBufferLine = Math.max(t.endBufferLine, e);
        }
      };
      We = { full: 0, left: 0, center: 0, right: 0 };
      at = { full: 0, left: 0, center: 0, right: 0 };
      Li = { full: 0, left: 0, center: 0, right: 0 };
      bt = class extends D {
        constructor(e, i, r, n, o2, l2, a, u) {
          super();
          this._viewportElement = e;
          this._screenElement = i;
          this._bufferService = r;
          this._decorationService = n;
          this._renderService = o2;
          this._optionsService = l2;
          this._themeService = a;
          this._coreBrowserService = u;
          this._colorZoneStore = new Gr();
          this._shouldUpdateDimensions = true;
          this._shouldUpdateAnchor = true;
          this._lastKnownBufferLength = 0;
          this._canvas = this._coreBrowserService.mainDocument.createElement("canvas"), this._canvas.classList.add("xterm-decoration-overview-ruler"), this._refreshCanvasDimensions(), this._viewportElement.parentElement?.insertBefore(this._canvas, this._viewportElement), this._register(C(() => this._canvas?.remove()));
          let h2 = this._canvas.getContext("2d");
          if (h2) this._ctx = h2;
          else throw new Error("Ctx cannot be null");
          this._register(this._decorationService.onDecorationRegistered(() => this._queueRefresh(void 0, true))), this._register(this._decorationService.onDecorationRemoved(() => this._queueRefresh(void 0, true))), this._register(this._renderService.onRenderedViewportChange(() => this._queueRefresh())), this._register(this._bufferService.buffers.onBufferActivate(() => {
            this._canvas.style.display = this._bufferService.buffer === this._bufferService.buffers.alt ? "none" : "block";
          })), this._register(this._bufferService.onScroll(() => {
            this._lastKnownBufferLength !== this._bufferService.buffers.normal.lines.length && (this._refreshDrawHeightConstants(), this._refreshColorZonePadding());
          })), this._register(this._renderService.onRender(() => {
            (!this._containerHeight || this._containerHeight !== this._screenElement.clientHeight) && (this._queueRefresh(true), this._containerHeight = this._screenElement.clientHeight);
          })), this._register(this._coreBrowserService.onDprChange(() => this._queueRefresh(true))), this._register(this._optionsService.onSpecificOptionChange("overviewRuler", () => this._queueRefresh(true))), this._register(this._themeService.onChangeColors(() => this._queueRefresh())), this._queueRefresh(true);
        }
        get _width() {
          return this._optionsService.options.overviewRuler?.width || 0;
        }
        _refreshDrawConstants() {
          let e = Math.floor((this._canvas.width - 1) / 3), i = Math.ceil((this._canvas.width - 1) / 3);
          at.full = this._canvas.width, at.left = e, at.center = i, at.right = e, this._refreshDrawHeightConstants(), Li.full = 1, Li.left = 1, Li.center = 1 + at.left, Li.right = 1 + at.left + at.center;
        }
        _refreshDrawHeightConstants() {
          We.full = Math.round(2 * this._coreBrowserService.dpr);
          let e = this._canvas.height / this._bufferService.buffer.lines.length, i = Math.round(Math.max(Math.min(e, 12), 6) * this._coreBrowserService.dpr);
          We.left = i, We.center = i, We.right = i;
        }
        _refreshColorZonePadding() {
          this._colorZoneStore.setPadding({ full: Math.floor(this._bufferService.buffers.active.lines.length / (this._canvas.height - 1) * We.full), left: Math.floor(this._bufferService.buffers.active.lines.length / (this._canvas.height - 1) * We.left), center: Math.floor(this._bufferService.buffers.active.lines.length / (this._canvas.height - 1) * We.center), right: Math.floor(this._bufferService.buffers.active.lines.length / (this._canvas.height - 1) * We.right) }), this._lastKnownBufferLength = this._bufferService.buffers.normal.lines.length;
        }
        _refreshCanvasDimensions() {
          this._canvas.style.width = `${this._width}px`, this._canvas.width = Math.round(this._width * this._coreBrowserService.dpr), this._canvas.style.height = `${this._screenElement.clientHeight}px`, this._canvas.height = Math.round(this._screenElement.clientHeight * this._coreBrowserService.dpr), this._refreshDrawConstants(), this._refreshColorZonePadding();
        }
        _refreshDecorations() {
          this._shouldUpdateDimensions && this._refreshCanvasDimensions(), this._ctx.clearRect(0, 0, this._canvas.width, this._canvas.height), this._colorZoneStore.clear();
          for (let i of this._decorationService.decorations) this._colorZoneStore.addDecoration(i);
          this._ctx.lineWidth = 1, this._renderRulerOutline();
          let e = this._colorZoneStore.zones;
          for (let i of e) i.position !== "full" && this._renderColorZone(i);
          for (let i of e) i.position === "full" && this._renderColorZone(i);
          this._shouldUpdateDimensions = false, this._shouldUpdateAnchor = false;
        }
        _renderRulerOutline() {
          this._ctx.fillStyle = this._themeService.colors.overviewRulerBorder.css, this._ctx.fillRect(0, 0, 1, this._canvas.height), this._optionsService.rawOptions.overviewRuler.showTopBorder && this._ctx.fillRect(1, 0, this._canvas.width - 1, 1), this._optionsService.rawOptions.overviewRuler.showBottomBorder && this._ctx.fillRect(1, this._canvas.height - 1, this._canvas.width - 1, this._canvas.height);
        }
        _renderColorZone(e) {
          this._ctx.fillStyle = e.color, this._ctx.fillRect(Li[e.position || "full"], Math.round((this._canvas.height - 1) * (e.startBufferLine / this._bufferService.buffers.active.lines.length) - We[e.position || "full"] / 2), at[e.position || "full"], Math.round((this._canvas.height - 1) * ((e.endBufferLine - e.startBufferLine) / this._bufferService.buffers.active.lines.length) + We[e.position || "full"]));
        }
        _queueRefresh(e, i) {
          this._shouldUpdateDimensions = e || this._shouldUpdateDimensions, this._shouldUpdateAnchor = i || this._shouldUpdateAnchor, this._animationFrame === void 0 && (this._animationFrame = this._coreBrowserService.window.requestAnimationFrame(() => {
            this._refreshDecorations(), this._animationFrame = void 0;
          }));
        }
      };
      bt = M([S(2, F), S(3, Be), S(4, ce), S(5, H), S(6, Re), S(7, ae)], bt);
      ((E) => (E.NUL = "\0", E.SOH = "", E.STX = "", E.ETX = "", E.EOT = "", E.ENQ = "", E.ACK = "", E.BEL = "\x07", E.BS = "\b", E.HT = "	", E.LF = `
`, E.VT = "\v", E.FF = "\f", E.CR = "\r", E.SO = "", E.SI = "", E.DLE = "", E.DC1 = "", E.DC2 = "", E.DC3 = "", E.DC4 = "", E.NAK = "", E.SYN = "", E.ETB = "", E.CAN = "", E.EM = "", E.SUB = "", E.ESC = "\x1B", E.FS = "", E.GS = "", E.RS = "", E.US = "", E.SP = " ", E.DEL = "\x7F"))(b ||= {});
      ((g2) => (g2.PAD = "\x80", g2.HOP = "\x81", g2.BPH = "\x82", g2.NBH = "\x83", g2.IND = "\x84", g2.NEL = "\x85", g2.SSA = "\x86", g2.ESA = "\x87", g2.HTS = "\x88", g2.HTJ = "\x89", g2.VTS = "\x8A", g2.PLD = "\x8B", g2.PLU = "\x8C", g2.RI = "\x8D", g2.SS2 = "\x8E", g2.SS3 = "\x8F", g2.DCS = "\x90", g2.PU1 = "\x91", g2.PU2 = "\x92", g2.STS = "\x93", g2.CCH = "\x94", g2.MW = "\x95", g2.SPA = "\x96", g2.EPA = "\x97", g2.SOS = "\x98", g2.SGCI = "\x99", g2.SCI = "\x9A", g2.CSI = "\x9B", g2.ST = "\x9C", g2.OSC = "\x9D", g2.PM = "\x9E", g2.APC = "\x9F"))(Ai ||= {});
      ((t) => t.ST = `${b.ESC}\\`)(fs ||= {});
      $t = class {
        constructor(t, e, i, r, n, o2) {
          this._textarea = t;
          this._compositionView = e;
          this._bufferService = i;
          this._optionsService = r;
          this._coreService = n;
          this._renderService = o2;
          this._isComposing = false, this._isSendingComposition = false, this._compositionPosition = { start: 0, end: 0 }, this._dataAlreadySent = "";
        }
        get isComposing() {
          return this._isComposing;
        }
        compositionstart() {
          this._isComposing = true, this._compositionPosition.start = this._textarea.value.length, this._compositionView.textContent = "", this._dataAlreadySent = "", this._compositionView.classList.add("active");
        }
        compositionupdate(t) {
          this._compositionView.textContent = t.data, this.updateCompositionElements(), setTimeout(() => {
            this._compositionPosition.end = this._textarea.value.length;
          }, 0);
        }
        compositionend() {
          this._finalizeComposition(true);
        }
        keydown(t) {
          if (this._isComposing || this._isSendingComposition) {
            if (t.keyCode === 20 || t.keyCode === 229 || t.keyCode === 16 || t.keyCode === 17 || t.keyCode === 18) return false;
            this._finalizeComposition(false);
          }
          return t.keyCode === 229 ? (this._handleAnyTextareaChanges(), false) : true;
        }
        _finalizeComposition(t) {
          if (this._compositionView.classList.remove("active"), this._isComposing = false, t) {
            let e = { start: this._compositionPosition.start, end: this._compositionPosition.end };
            this._isSendingComposition = true, setTimeout(() => {
              if (this._isSendingComposition) {
                this._isSendingComposition = false;
                let i;
                e.start += this._dataAlreadySent.length, this._isComposing ? i = this._textarea.value.substring(e.start, this._compositionPosition.start) : i = this._textarea.value.substring(e.start), i.length > 0 && this._coreService.triggerDataEvent(i, true);
              }
            }, 0);
          } else {
            this._isSendingComposition = false;
            let e = this._textarea.value.substring(this._compositionPosition.start, this._compositionPosition.end);
            this._coreService.triggerDataEvent(e, true);
          }
        }
        _handleAnyTextareaChanges() {
          let t = this._textarea.value;
          setTimeout(() => {
            if (!this._isComposing) {
              let e = this._textarea.value, i = e.replace(t, "");
              this._dataAlreadySent = i, e.length > t.length ? this._coreService.triggerDataEvent(i, true) : e.length < t.length ? this._coreService.triggerDataEvent(`${b.DEL}`, true) : e.length === t.length && e !== t && this._coreService.triggerDataEvent(e, true);
            }
          }, 0);
        }
        updateCompositionElements(t) {
          if (this._isComposing) {
            if (this._bufferService.buffer.isCursorInViewport) {
              let e = Math.min(this._bufferService.buffer.x, this._bufferService.cols - 1), i = this._renderService.dimensions.css.cell.height, r = this._bufferService.buffer.y * this._renderService.dimensions.css.cell.height, n = e * this._renderService.dimensions.css.cell.width;
              this._compositionView.style.left = n + "px", this._compositionView.style.top = r + "px", this._compositionView.style.height = i + "px", this._compositionView.style.lineHeight = i + "px", this._compositionView.style.fontFamily = this._optionsService.rawOptions.fontFamily, this._compositionView.style.fontSize = this._optionsService.rawOptions.fontSize + "px";
              let o2 = this._compositionView.getBoundingClientRect();
              this._textarea.style.left = n + "px", this._textarea.style.top = r + "px", this._textarea.style.width = Math.max(o2.width, 1) + "px", this._textarea.style.height = Math.max(o2.height, 1) + "px", this._textarea.style.lineHeight = o2.height + "px";
            }
            t || setTimeout(() => this.updateCompositionElements(true), 0);
          }
        }
      };
      $t = M([S(2, F), S(3, H), S(4, ge), S(5, ce)], $t);
      ue = 0;
      he = 0;
      de = 0;
      J = 0;
      ps = { css: "#00000000", rgba: 0 };
      ((i) => {
        function s15(r, n, o2, l2) {
          return l2 !== void 0 ? `#${vt(r)}${vt(n)}${vt(o2)}${vt(l2)}` : `#${vt(r)}${vt(n)}${vt(o2)}`;
        }
        i.toCss = s15;
        function t(r, n, o2, l2 = 255) {
          return (r << 24 | n << 16 | o2 << 8 | l2) >>> 0;
        }
        i.toRgba = t;
        function e(r, n, o2, l2) {
          return { css: i.toCss(r, n, o2, l2), rgba: i.toRgba(r, n, o2, l2) };
        }
        i.toColor = e;
      })(j ||= {});
      ((l2) => {
        function s15(a, u) {
          if (J = (u.rgba & 255) / 255, J === 1) return { css: u.css, rgba: u.rgba };
          let h2 = u.rgba >> 24 & 255, c = u.rgba >> 16 & 255, d = u.rgba >> 8 & 255, _3 = a.rgba >> 24 & 255, p = a.rgba >> 16 & 255, m = a.rgba >> 8 & 255;
          ue = _3 + Math.round((h2 - _3) * J), he = p + Math.round((c - p) * J), de = m + Math.round((d - m) * J);
          let f = j.toCss(ue, he, de), A = j.toRgba(ue, he, de);
          return { css: f, rgba: A };
        }
        l2.blend = s15;
        function t(a) {
          return (a.rgba & 255) === 255;
        }
        l2.isOpaque = t;
        function e(a, u, h2) {
          let c = $r.ensureContrastRatio(a.rgba, u.rgba, h2);
          if (c) return j.toColor(c >> 24 & 255, c >> 16 & 255, c >> 8 & 255);
        }
        l2.ensureContrastRatio = e;
        function i(a) {
          let u = (a.rgba | 255) >>> 0;
          return [ue, he, de] = $r.toChannels(u), { css: j.toCss(ue, he, de), rgba: u };
        }
        l2.opaque = i;
        function r(a, u) {
          return J = Math.round(u * 255), [ue, he, de] = $r.toChannels(a.rgba), { css: j.toCss(ue, he, de, J), rgba: j.toRgba(ue, he, de, J) };
        }
        l2.opacity = r;
        function n(a, u) {
          return J = a.rgba & 255, r(a, J * u / 255);
        }
        l2.multiplyOpacity = n;
        function o2(a) {
          return [a.rgba >> 24 & 255, a.rgba >> 16 & 255, a.rgba >> 8 & 255];
        }
        l2.toColorRGB = o2;
      })(U ||= {});
      ((i) => {
        let s15, t;
        try {
          let r = document.createElement("canvas");
          r.width = 1, r.height = 1;
          let n = r.getContext("2d", { willReadFrequently: true });
          n && (s15 = n, s15.globalCompositeOperation = "copy", t = s15.createLinearGradient(0, 0, 1, 1));
        } catch {
        }
        function e(r) {
          if (r.match(/#[\da-f]{3,8}/i)) switch (r.length) {
            case 4:
              return ue = parseInt(r.slice(1, 2).repeat(2), 16), he = parseInt(r.slice(2, 3).repeat(2), 16), de = parseInt(r.slice(3, 4).repeat(2), 16), j.toColor(ue, he, de);
            case 5:
              return ue = parseInt(r.slice(1, 2).repeat(2), 16), he = parseInt(r.slice(2, 3).repeat(2), 16), de = parseInt(r.slice(3, 4).repeat(2), 16), J = parseInt(r.slice(4, 5).repeat(2), 16), j.toColor(ue, he, de, J);
            case 7:
              return { css: r, rgba: (parseInt(r.slice(1), 16) << 8 | 255) >>> 0 };
            case 9:
              return { css: r, rgba: parseInt(r.slice(1), 16) >>> 0 };
          }
          let n = r.match(/rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(,\s*(0|1|\d?\.(\d+))\s*)?\)/);
          if (n) return ue = parseInt(n[1]), he = parseInt(n[2]), de = parseInt(n[3]), J = Math.round((n[5] === void 0 ? 1 : parseFloat(n[5])) * 255), j.toColor(ue, he, de, J);
          if (!s15 || !t) throw new Error("css.toColor: Unsupported css format");
          if (s15.fillStyle = t, s15.fillStyle = r, typeof s15.fillStyle != "string") throw new Error("css.toColor: Unsupported css format");
          if (s15.fillRect(0, 0, 1, 1), [ue, he, de, J] = s15.getImageData(0, 0, 1, 1).data, J !== 255) throw new Error("css.toColor: Unsupported css format");
          return { rgba: j.toRgba(ue, he, de, J), css: r };
        }
        i.toColor = e;
      })(z ||= {});
      ((e) => {
        function s15(i) {
          return t(i >> 16 & 255, i >> 8 & 255, i & 255);
        }
        e.relativeLuminance = s15;
        function t(i, r, n) {
          let o2 = i / 255, l2 = r / 255, a = n / 255, u = o2 <= 0.03928 ? o2 / 12.92 : Math.pow((o2 + 0.055) / 1.055, 2.4), h2 = l2 <= 0.03928 ? l2 / 12.92 : Math.pow((l2 + 0.055) / 1.055, 2.4), c = a <= 0.03928 ? a / 12.92 : Math.pow((a + 0.055) / 1.055, 2.4);
          return u * 0.2126 + h2 * 0.7152 + c * 0.0722;
        }
        e.relativeLuminance2 = t;
      })(ve ||= {});
      ((n) => {
        function s15(o2, l2) {
          if (J = (l2 & 255) / 255, J === 1) return l2;
          let a = l2 >> 24 & 255, u = l2 >> 16 & 255, h2 = l2 >> 8 & 255, c = o2 >> 24 & 255, d = o2 >> 16 & 255, _3 = o2 >> 8 & 255;
          return ue = c + Math.round((a - c) * J), he = d + Math.round((u - d) * J), de = _3 + Math.round((h2 - _3) * J), j.toRgba(ue, he, de);
        }
        n.blend = s15;
        function t(o2, l2, a) {
          let u = ve.relativeLuminance(o2 >> 8), h2 = ve.relativeLuminance(l2 >> 8);
          if (Xe(u, h2) < a) {
            if (h2 < u) {
              let p = e(o2, l2, a), m = Xe(u, ve.relativeLuminance(p >> 8));
              if (m < a) {
                let f = i(o2, l2, a), A = Xe(u, ve.relativeLuminance(f >> 8));
                return m > A ? p : f;
              }
              return p;
            }
            let d = i(o2, l2, a), _3 = Xe(u, ve.relativeLuminance(d >> 8));
            if (_3 < a) {
              let p = e(o2, l2, a), m = Xe(u, ve.relativeLuminance(p >> 8));
              return _3 > m ? d : p;
            }
            return d;
          }
        }
        n.ensureContrastRatio = t;
        function e(o2, l2, a) {
          let u = o2 >> 24 & 255, h2 = o2 >> 16 & 255, c = o2 >> 8 & 255, d = l2 >> 24 & 255, _3 = l2 >> 16 & 255, p = l2 >> 8 & 255, m = Xe(ve.relativeLuminance2(d, _3, p), ve.relativeLuminance2(u, h2, c));
          for (; m < a && (d > 0 || _3 > 0 || p > 0); ) d -= Math.max(0, Math.ceil(d * 0.1)), _3 -= Math.max(0, Math.ceil(_3 * 0.1)), p -= Math.max(0, Math.ceil(p * 0.1)), m = Xe(ve.relativeLuminance2(d, _3, p), ve.relativeLuminance2(u, h2, c));
          return (d << 24 | _3 << 16 | p << 8 | 255) >>> 0;
        }
        n.reduceLuminance = e;
        function i(o2, l2, a) {
          let u = o2 >> 24 & 255, h2 = o2 >> 16 & 255, c = o2 >> 8 & 255, d = l2 >> 24 & 255, _3 = l2 >> 16 & 255, p = l2 >> 8 & 255, m = Xe(ve.relativeLuminance2(d, _3, p), ve.relativeLuminance2(u, h2, c));
          for (; m < a && (d < 255 || _3 < 255 || p < 255); ) d = Math.min(255, d + Math.ceil((255 - d) * 0.1)), _3 = Math.min(255, _3 + Math.ceil((255 - _3) * 0.1)), p = Math.min(255, p + Math.ceil((255 - p) * 0.1)), m = Xe(ve.relativeLuminance2(d, _3, p), ve.relativeLuminance2(u, h2, c));
          return (d << 24 | _3 << 16 | p << 8 | 255) >>> 0;
        }
        n.increaseLuminance = i;
        function r(o2) {
          return [o2 >> 24 & 255, o2 >> 16 & 255, o2 >> 8 & 255, o2 & 255];
        }
        n.toChannels = r;
      })($r ||= {});
      Vr = class extends De {
        constructor(e, i, r) {
          super();
          this.content = 0;
          this.combinedData = "";
          this.fg = e.fg, this.bg = e.bg, this.combinedData = i, this._width = r;
        }
        isCombined() {
          return 2097152;
        }
        getWidth() {
          return this._width;
        }
        getChars() {
          return this.combinedData;
        }
        getCode() {
          return 2097151;
        }
        setFromCharData(e) {
          throw new Error("not implemented");
        }
        getAsCharData() {
          return [this.fg, this.getChars(), this.getWidth(), this.getCode()];
        }
      };
      ct = class {
        constructor(t) {
          this._bufferService = t;
          this._characterJoiners = [];
          this._nextCharacterJoinerId = 0;
          this._workCell = new q();
        }
        register(t) {
          let e = { id: this._nextCharacterJoinerId++, handler: t };
          return this._characterJoiners.push(e), e.id;
        }
        deregister(t) {
          for (let e = 0; e < this._characterJoiners.length; e++) if (this._characterJoiners[e].id === t) return this._characterJoiners.splice(e, 1), true;
          return false;
        }
        getJoinedCharacters(t) {
          if (this._characterJoiners.length === 0) return [];
          let e = this._bufferService.buffer.lines.get(t);
          if (!e || e.length === 0) return [];
          let i = [], r = e.translateToString(true), n = 0, o2 = 0, l2 = 0, a = e.getFg(0), u = e.getBg(0);
          for (let h2 = 0; h2 < e.getTrimmedLength(); h2++) if (e.loadCell(h2, this._workCell), this._workCell.getWidth() !== 0) {
            if (this._workCell.fg !== a || this._workCell.bg !== u) {
              if (h2 - n > 1) {
                let c = this._getJoinedRanges(r, l2, o2, e, n);
                for (let d = 0; d < c.length; d++) i.push(c[d]);
              }
              n = h2, l2 = o2, a = this._workCell.fg, u = this._workCell.bg;
            }
            o2 += this._workCell.getChars().length || we.length;
          }
          if (this._bufferService.cols - n > 1) {
            let h2 = this._getJoinedRanges(r, l2, o2, e, n);
            for (let c = 0; c < h2.length; c++) i.push(h2[c]);
          }
          return i;
        }
        _getJoinedRanges(t, e, i, r, n) {
          let o2 = t.substring(e, i), l2 = [];
          try {
            l2 = this._characterJoiners[0].handler(o2);
          } catch (a) {
            console.error(a);
          }
          for (let a = 1; a < this._characterJoiners.length; a++) try {
            let u = this._characterJoiners[a].handler(o2);
            for (let h2 = 0; h2 < u.length; h2++) ct._mergeRanges(l2, u[h2]);
          } catch (u) {
            console.error(u);
          }
          return this._stringRangesToCellRanges(l2, r, n), l2;
        }
        _stringRangesToCellRanges(t, e, i) {
          let r = 0, n = false, o2 = 0, l2 = t[r];
          if (l2) {
            for (let a = i; a < this._bufferService.cols; a++) {
              let u = e.getWidth(a), h2 = e.getString(a).length || we.length;
              if (u !== 0) {
                if (!n && l2[0] <= o2 && (l2[0] = a, n = true), l2[1] <= o2) {
                  if (l2[1] = a, l2 = t[++r], !l2) break;
                  l2[0] <= o2 ? (l2[0] = a, n = true) : n = false;
                }
                o2 += h2;
              }
            }
            l2 && (l2[1] = this._bufferService.cols);
          }
        }
        static _mergeRanges(t, e) {
          let i = false;
          for (let r = 0; r < t.length; r++) {
            let n = t[r];
            if (i) {
              if (e[1] <= n[0]) return t[r - 1][1] = e[1], t;
              if (e[1] <= n[1]) return t[r - 1][1] = Math.max(e[1], n[1]), t.splice(r, 1), t;
              t.splice(r, 1), r--;
            } else {
              if (e[1] <= n[0]) return t.splice(r, 0, e), t;
              if (e[1] <= n[1]) return n[0] = Math.min(e[0], n[0]), t;
              e[0] < n[1] && (n[0] = Math.min(e[0], n[0]), i = true);
              continue;
            }
          }
          return i ? t[t.length - 1][1] = e[1] : t.push(e), t;
        }
      };
      ct = M([S(0, F)], ct);
      Vt = class {
        constructor(t, e, i, r, n, o2, l2) {
          this._document = t;
          this._characterJoinerService = e;
          this._optionsService = i;
          this._coreBrowserService = r;
          this._coreService = n;
          this._decorationService = o2;
          this._themeService = l2;
          this._workCell = new q();
          this._columnSelectMode = false;
          this.defaultSpacing = 0;
        }
        handleSelectionChanged(t, e, i) {
          this._selectionStart = t, this._selectionEnd = e, this._columnSelectMode = i;
        }
        createRow(t, e, i, r, n, o2, l2, a, u, h2, c) {
          let d = [], _3 = this._characterJoinerService.getJoinedCharacters(e), p = this._themeService.colors, m = t.getNoBgTrimmedLength();
          i && m < o2 + 1 && (m = o2 + 1);
          let f, A = 0, R = "", O = 0, I = 0, k2 = 0, P = 0, oe = false, Me = 0, Pe = false, Ke = 0, di = 0, V = [], Qe = h2 !== -1 && c !== -1;
          for (let y = 0; y < m; y++) {
            t.loadCell(y, this._workCell);
            let T = this._workCell.getWidth();
            if (T === 0) continue;
            let g2 = false, w2 = y >= di, E = y, x = this._workCell;
            if (_3.length > 0 && y === _3[0][0] && w2) {
              let W = _3.shift(), An = this._isCellInSelection(W[0], e);
              for (O = W[0] + 1; O < W[1]; O++) w2 &&= An === this._isCellInSelection(O, e);
              w2 &&= !i || o2 < W[0] || o2 >= W[1], w2 ? (g2 = true, x = new Vr(this._workCell, t.translateToString(true, W[0], W[1]), W[1] - W[0]), E = W[1] - 1, T = x.getWidth()) : di = W[1];
            }
            let N = this._isCellInSelection(y, e), Z = i && y === o2, te = Qe && y >= h2 && y <= c, Oe = false;
            this._decorationService.forEachDecorationAtCell(y, e, void 0, (W) => {
              Oe = true;
            });
            let ze = x.getChars() || we;
            if (ze === " " && (x.isUnderline() || x.isOverline()) && (ze = "\xA0"), Ke = T * a - u.get(ze, x.isBold(), x.isItalic()), !f) f = this._document.createElement("span");
            else if (A && (N && Pe || !N && !Pe && x.bg === I) && (N && Pe && p.selectionForeground || x.fg === k2) && x.extended.ext === P && te === oe && Ke === Me && !Z && !g2 && !Oe && w2) {
              x.isInvisible() ? R += we : R += ze, A++;
              continue;
            } else A && (f.textContent = R), f = this._document.createElement("span"), A = 0, R = "";
            if (I = x.bg, k2 = x.fg, P = x.extended.ext, oe = te, Me = Ke, Pe = N, g2 && o2 >= y && o2 <= E && (o2 = y), !this._coreService.isCursorHidden && Z && this._coreService.isCursorInitialized) {
              if (V.push("xterm-cursor"), this._coreBrowserService.isFocused) l2 && V.push("xterm-cursor-blink"), V.push(r === "bar" ? "xterm-cursor-bar" : r === "underline" ? "xterm-cursor-underline" : "xterm-cursor-block");
              else if (n) switch (n) {
                case "outline":
                  V.push("xterm-cursor-outline");
                  break;
                case "block":
                  V.push("xterm-cursor-block");
                  break;
                case "bar":
                  V.push("xterm-cursor-bar");
                  break;
                case "underline":
                  V.push("xterm-cursor-underline");
                  break;
                default:
                  break;
              }
            }
            if (x.isBold() && V.push("xterm-bold"), x.isItalic() && V.push("xterm-italic"), x.isDim() && V.push("xterm-dim"), x.isInvisible() ? R = we : R = x.getChars() || we, x.isUnderline() && (V.push(`xterm-underline-${x.extended.underlineStyle}`), R === " " && (R = "\xA0"), !x.isUnderlineColorDefault())) if (x.isUnderlineColorRGB()) f.style.textDecorationColor = `rgb(${De.toColorRGB(x.getUnderlineColor()).join(",")})`;
            else {
              let W = x.getUnderlineColor();
              this._optionsService.rawOptions.drawBoldTextInBrightColors && x.isBold() && W < 8 && (W += 8), f.style.textDecorationColor = p.ansi[W].css;
            }
            x.isOverline() && (V.push("xterm-overline"), R === " " && (R = "\xA0")), x.isStrikethrough() && V.push("xterm-strikethrough"), te && (f.style.textDecoration = "underline");
            let le = x.getFgColor(), et = x.getFgColorMode(), me = x.getBgColor(), ht = x.getBgColorMode(), fi = !!x.isInverse();
            if (fi) {
              let W = le;
              le = me, me = W;
              let An = et;
              et = ht, ht = An;
            }
            let tt, Qi, pi = false;
            this._decorationService.forEachDecorationAtCell(y, e, void 0, (W) => {
              W.options.layer !== "top" && pi || (W.backgroundColorRGB && (ht = 50331648, me = W.backgroundColorRGB.rgba >> 8 & 16777215, tt = W.backgroundColorRGB), W.foregroundColorRGB && (et = 50331648, le = W.foregroundColorRGB.rgba >> 8 & 16777215, Qi = W.foregroundColorRGB), pi = W.options.layer === "top");
            }), !pi && N && (tt = this._coreBrowserService.isFocused ? p.selectionBackgroundOpaque : p.selectionInactiveBackgroundOpaque, me = tt.rgba >> 8 & 16777215, ht = 50331648, pi = true, p.selectionForeground && (et = 50331648, le = p.selectionForeground.rgba >> 8 & 16777215, Qi = p.selectionForeground)), pi && V.push("xterm-decoration-top");
            let it;
            switch (ht) {
              case 16777216:
              case 33554432:
                it = p.ansi[me], V.push(`xterm-bg-${me}`);
                break;
              case 50331648:
                it = j.toColor(me >> 16, me >> 8 & 255, me & 255), this._addStyle(f, `background-color:#${qo((me >>> 0).toString(16), "0", 6)}`);
                break;
              case 0:
              default:
                fi ? (it = p.foreground, V.push(`xterm-bg-${257}`)) : it = p.background;
            }
            switch (tt || x.isDim() && (tt = U.multiplyOpacity(it, 0.5)), et) {
              case 16777216:
              case 33554432:
                x.isBold() && le < 8 && this._optionsService.rawOptions.drawBoldTextInBrightColors && (le += 8), this._applyMinimumContrast(f, it, p.ansi[le], x, tt, void 0) || V.push(`xterm-fg-${le}`);
                break;
              case 50331648:
                let W = j.toColor(le >> 16 & 255, le >> 8 & 255, le & 255);
                this._applyMinimumContrast(f, it, W, x, tt, Qi) || this._addStyle(f, `color:#${qo(le.toString(16), "0", 6)}`);
                break;
              case 0:
              default:
                this._applyMinimumContrast(f, it, p.foreground, x, tt, Qi) || fi && V.push(`xterm-fg-${257}`);
            }
            V.length && (f.className = V.join(" "), V.length = 0), !Z && !g2 && !Oe && w2 ? A++ : f.textContent = R, Ke !== this.defaultSpacing && (f.style.letterSpacing = `${Ke}px`), d.push(f), y = E;
          }
          return f && A && (f.textContent = R), d;
        }
        _applyMinimumContrast(t, e, i, r, n, o2) {
          if (this._optionsService.rawOptions.minimumContrastRatio === 1 || $o(r.getCode())) return false;
          let l2 = this._getContrastCache(r), a;
          if (!n && !o2 && (a = l2.getColor(e.rgba, i.rgba)), a === void 0) {
            let u = this._optionsService.rawOptions.minimumContrastRatio / (r.isDim() ? 2 : 1);
            a = U.ensureContrastRatio(n || e, o2 || i, u), l2.setColor((n || e).rgba, (o2 || i).rgba, a ?? null);
          }
          return a ? (this._addStyle(t, `color:${a.css}`), true) : false;
        }
        _getContrastCache(t) {
          return t.isDim() ? this._themeService.colors.halfContrastCache : this._themeService.colors.contrastCache;
        }
        _addStyle(t, e) {
          t.setAttribute("style", `${t.getAttribute("style") || ""}${e};`);
        }
        _isCellInSelection(t, e) {
          let i = this._selectionStart, r = this._selectionEnd;
          return !i || !r ? false : this._columnSelectMode ? i[0] <= r[0] ? t >= i[0] && e >= i[1] && t < r[0] && e <= r[1] : t < i[0] && e >= i[1] && t >= r[0] && e <= r[1] : e > i[1] && e < r[1] || i[1] === r[1] && e === i[1] && t >= i[0] && t < r[0] || i[1] < r[1] && e === r[1] && t < r[0] || i[1] < r[1] && e === i[1] && t >= i[0];
        }
      };
      Vt = M([S(1, or), S(2, H), S(3, ae), S(4, ge), S(5, Be), S(6, Re)], Vt);
      Yr = class {
        constructor(t, e) {
          this._flat = new Float32Array(256);
          this._font = "";
          this._fontSize = 0;
          this._weight = "normal";
          this._weightBold = "bold";
          this._measureElements = [];
          this._container = t.createElement("div"), this._container.classList.add("xterm-width-cache-measure-container"), this._container.setAttribute("aria-hidden", "true"), this._container.style.whiteSpace = "pre", this._container.style.fontKerning = "none";
          let i = t.createElement("span");
          i.classList.add("xterm-char-measure-element");
          let r = t.createElement("span");
          r.classList.add("xterm-char-measure-element"), r.style.fontWeight = "bold";
          let n = t.createElement("span");
          n.classList.add("xterm-char-measure-element"), n.style.fontStyle = "italic";
          let o2 = t.createElement("span");
          o2.classList.add("xterm-char-measure-element"), o2.style.fontWeight = "bold", o2.style.fontStyle = "italic", this._measureElements = [i, r, n, o2], this._container.appendChild(i), this._container.appendChild(r), this._container.appendChild(n), this._container.appendChild(o2), e.appendChild(this._container), this.clear();
        }
        dispose() {
          this._container.remove(), this._measureElements.length = 0, this._holey = void 0;
        }
        clear() {
          this._flat.fill(-9999), this._holey = /* @__PURE__ */ new Map();
        }
        setFont(t, e, i, r) {
          t === this._font && e === this._fontSize && i === this._weight && r === this._weightBold || (this._font = t, this._fontSize = e, this._weight = i, this._weightBold = r, this._container.style.fontFamily = this._font, this._container.style.fontSize = `${this._fontSize}px`, this._measureElements[0].style.fontWeight = `${i}`, this._measureElements[1].style.fontWeight = `${r}`, this._measureElements[2].style.fontWeight = `${i}`, this._measureElements[3].style.fontWeight = `${r}`, this.clear());
        }
        get(t, e, i) {
          let r = 0;
          if (!e && !i && t.length === 1 && (r = t.charCodeAt(0)) < 256) {
            if (this._flat[r] !== -9999) return this._flat[r];
            let l2 = this._measure(t, 0);
            return l2 > 0 && (this._flat[r] = l2), l2;
          }
          let n = t;
          e && (n += "B"), i && (n += "I");
          let o2 = this._holey.get(n);
          if (o2 === void 0) {
            let l2 = 0;
            e && (l2 |= 1), i && (l2 |= 2), o2 = this._measure(t, l2), o2 > 0 && this._holey.set(n, o2);
          }
          return o2;
        }
        _measure(t, e) {
          let i = this._measureElements[e];
          return i.textContent = t.repeat(32), i.offsetWidth / 32;
        }
      };
      ms = class {
        constructor() {
          this.clear();
        }
        clear() {
          this.hasSelection = false, this.columnSelectMode = false, this.viewportStartRow = 0, this.viewportEndRow = 0, this.viewportCappedStartRow = 0, this.viewportCappedEndRow = 0, this.startCol = 0, this.endCol = 0, this.selectionStart = void 0, this.selectionEnd = void 0;
        }
        update(t, e, i, r = false) {
          if (this.selectionStart = e, this.selectionEnd = i, !e || !i || e[0] === i[0] && e[1] === i[1]) {
            this.clear();
            return;
          }
          let n = t.buffers.active.ydisp, o2 = e[1] - n, l2 = i[1] - n, a = Math.max(o2, 0), u = Math.min(l2, t.rows - 1);
          if (a >= t.rows || u < 0) {
            this.clear();
            return;
          }
          this.hasSelection = true, this.columnSelectMode = r, this.viewportStartRow = o2, this.viewportEndRow = l2, this.viewportCappedStartRow = a, this.viewportCappedEndRow = u, this.startCol = e[0], this.endCol = i[0];
        }
        isCellSelected(t, e, i) {
          return this.hasSelection ? (i -= t.buffer.active.viewportY, this.columnSelectMode ? this.startCol <= this.endCol ? e >= this.startCol && i >= this.viewportCappedStartRow && e < this.endCol && i <= this.viewportCappedEndRow : e < this.startCol && i >= this.viewportCappedStartRow && e >= this.endCol && i <= this.viewportCappedEndRow : i > this.viewportStartRow && i < this.viewportEndRow || this.viewportStartRow === this.viewportEndRow && i === this.viewportStartRow && e >= this.startCol && e < this.endCol || this.viewportStartRow < this.viewportEndRow && i === this.viewportEndRow && e < this.endCol || this.viewportStartRow < this.viewportEndRow && i === this.viewportStartRow && e >= this.startCol) : false;
        }
      };
      _s = "xterm-dom-renderer-owner-";
      Le = "xterm-rows";
      jr = "xterm-fg-";
      jo = "xterm-bg-";
      ki = "xterm-focus";
      Xr = "xterm-selection";
      Na = 1;
      Yt = class extends D {
        constructor(e, i, r, n, o2, l2, a, u, h2, c, d, _3, p, m) {
          super();
          this._terminal = e;
          this._document = i;
          this._element = r;
          this._screenElement = n;
          this._viewportElement = o2;
          this._helperContainer = l2;
          this._linkifier2 = a;
          this._charSizeService = h2;
          this._optionsService = c;
          this._bufferService = d;
          this._coreService = _3;
          this._coreBrowserService = p;
          this._themeService = m;
          this._terminalClass = Na++;
          this._rowElements = [];
          this._selectionRenderModel = Yo();
          this.onRequestRedraw = this._register(new v()).event;
          this._rowContainer = this._document.createElement("div"), this._rowContainer.classList.add(Le), this._rowContainer.style.lineHeight = "normal", this._rowContainer.setAttribute("aria-hidden", "true"), this._refreshRowElements(this._bufferService.cols, this._bufferService.rows), this._selectionContainer = this._document.createElement("div"), this._selectionContainer.classList.add(Xr), this._selectionContainer.setAttribute("aria-hidden", "true"), this.dimensions = Vo(), this._updateDimensions(), this._register(this._optionsService.onOptionChange(() => this._handleOptionsChanged())), this._register(this._themeService.onChangeColors((f) => this._injectCss(f))), this._injectCss(this._themeService.colors), this._rowFactory = u.createInstance(Vt, document), this._element.classList.add(_s + this._terminalClass), this._screenElement.appendChild(this._rowContainer), this._screenElement.appendChild(this._selectionContainer), this._register(this._linkifier2.onShowLinkUnderline((f) => this._handleLinkHover(f))), this._register(this._linkifier2.onHideLinkUnderline((f) => this._handleLinkLeave(f))), this._register(C(() => {
            this._element.classList.remove(_s + this._terminalClass), this._rowContainer.remove(), this._selectionContainer.remove(), this._widthCache.dispose(), this._themeStyleElement.remove(), this._dimensionsStyleElement.remove();
          })), this._widthCache = new Yr(this._document, this._helperContainer), this._widthCache.setFont(this._optionsService.rawOptions.fontFamily, this._optionsService.rawOptions.fontSize, this._optionsService.rawOptions.fontWeight, this._optionsService.rawOptions.fontWeightBold), this._setDefaultSpacing();
        }
        _updateDimensions() {
          let e = this._coreBrowserService.dpr;
          this.dimensions.device.char.width = this._charSizeService.width * e, this.dimensions.device.char.height = Math.ceil(this._charSizeService.height * e), this.dimensions.device.cell.width = this.dimensions.device.char.width + Math.round(this._optionsService.rawOptions.letterSpacing), this.dimensions.device.cell.height = Math.floor(this.dimensions.device.char.height * this._optionsService.rawOptions.lineHeight), this.dimensions.device.char.left = 0, this.dimensions.device.char.top = 0, this.dimensions.device.canvas.width = this.dimensions.device.cell.width * this._bufferService.cols, this.dimensions.device.canvas.height = this.dimensions.device.cell.height * this._bufferService.rows, this.dimensions.css.canvas.width = Math.round(this.dimensions.device.canvas.width / e), this.dimensions.css.canvas.height = Math.round(this.dimensions.device.canvas.height / e), this.dimensions.css.cell.width = this.dimensions.css.canvas.width / this._bufferService.cols, this.dimensions.css.cell.height = this.dimensions.css.canvas.height / this._bufferService.rows;
          for (let r of this._rowElements) r.style.width = `${this.dimensions.css.canvas.width}px`, r.style.height = `${this.dimensions.css.cell.height}px`, r.style.lineHeight = `${this.dimensions.css.cell.height}px`, r.style.overflow = "hidden";
          this._dimensionsStyleElement || (this._dimensionsStyleElement = this._document.createElement("style"), this._screenElement.appendChild(this._dimensionsStyleElement));
          let i = `${this._terminalSelector} .${Le} span { display: inline-block; height: 100%; vertical-align: top;}`;
          this._dimensionsStyleElement.textContent = i, this._selectionContainer.style.height = this._viewportElement.style.height, this._screenElement.style.width = `${this.dimensions.css.canvas.width}px`, this._screenElement.style.height = `${this.dimensions.css.canvas.height}px`;
        }
        _injectCss(e) {
          this._themeStyleElement || (this._themeStyleElement = this._document.createElement("style"), this._screenElement.appendChild(this._themeStyleElement));
          let i = `${this._terminalSelector} .${Le} { pointer-events: none; color: ${e.foreground.css}; font-family: ${this._optionsService.rawOptions.fontFamily}; font-size: ${this._optionsService.rawOptions.fontSize}px; font-kerning: none; white-space: pre}`;
          i += `${this._terminalSelector} .${Le} .xterm-dim { color: ${U.multiplyOpacity(e.foreground, 0.5).css};}`, i += `${this._terminalSelector} span:not(.xterm-bold) { font-weight: ${this._optionsService.rawOptions.fontWeight};}${this._terminalSelector} span.xterm-bold { font-weight: ${this._optionsService.rawOptions.fontWeightBold};}${this._terminalSelector} span.xterm-italic { font-style: italic;}`;
          let r = `blink_underline_${this._terminalClass}`, n = `blink_bar_${this._terminalClass}`, o2 = `blink_block_${this._terminalClass}`;
          i += `@keyframes ${r} { 50% {  border-bottom-style: hidden; }}`, i += `@keyframes ${n} { 50% {  box-shadow: none; }}`, i += `@keyframes ${o2} { 0% {  background-color: ${e.cursor.css};  color: ${e.cursorAccent.css}; } 50% {  background-color: inherit;  color: ${e.cursor.css}; }}`, i += `${this._terminalSelector} .${Le}.${ki} .xterm-cursor.xterm-cursor-blink.xterm-cursor-underline { animation: ${r} 1s step-end infinite;}${this._terminalSelector} .${Le}.${ki} .xterm-cursor.xterm-cursor-blink.xterm-cursor-bar { animation: ${n} 1s step-end infinite;}${this._terminalSelector} .${Le}.${ki} .xterm-cursor.xterm-cursor-blink.xterm-cursor-block { animation: ${o2} 1s step-end infinite;}${this._terminalSelector} .${Le} .xterm-cursor.xterm-cursor-block { background-color: ${e.cursor.css}; color: ${e.cursorAccent.css};}${this._terminalSelector} .${Le} .xterm-cursor.xterm-cursor-block:not(.xterm-cursor-blink) { background-color: ${e.cursor.css} !important; color: ${e.cursorAccent.css} !important;}${this._terminalSelector} .${Le} .xterm-cursor.xterm-cursor-outline { outline: 1px solid ${e.cursor.css}; outline-offset: -1px;}${this._terminalSelector} .${Le} .xterm-cursor.xterm-cursor-bar { box-shadow: ${this._optionsService.rawOptions.cursorWidth}px 0 0 ${e.cursor.css} inset;}${this._terminalSelector} .${Le} .xterm-cursor.xterm-cursor-underline { border-bottom: 1px ${e.cursor.css}; border-bottom-style: solid; height: calc(100% - 1px);}`, i += `${this._terminalSelector} .${Xr} { position: absolute; top: 0; left: 0; z-index: 1; pointer-events: none;}${this._terminalSelector}.focus .${Xr} div { position: absolute; background-color: ${e.selectionBackgroundOpaque.css};}${this._terminalSelector} .${Xr} div { position: absolute; background-color: ${e.selectionInactiveBackgroundOpaque.css};}`;
          for (let [l2, a] of e.ansi.entries()) i += `${this._terminalSelector} .${jr}${l2} { color: ${a.css}; }${this._terminalSelector} .${jr}${l2}.xterm-dim { color: ${U.multiplyOpacity(a, 0.5).css}; }${this._terminalSelector} .${jo}${l2} { background-color: ${a.css}; }`;
          i += `${this._terminalSelector} .${jr}${257} { color: ${U.opaque(e.background).css}; }${this._terminalSelector} .${jr}${257}.xterm-dim { color: ${U.multiplyOpacity(U.opaque(e.background), 0.5).css}; }${this._terminalSelector} .${jo}${257} { background-color: ${e.foreground.css}; }`, this._themeStyleElement.textContent = i;
        }
        _setDefaultSpacing() {
          let e = this.dimensions.css.cell.width - this._widthCache.get("W", false, false);
          this._rowContainer.style.letterSpacing = `${e}px`, this._rowFactory.defaultSpacing = e;
        }
        handleDevicePixelRatioChange() {
          this._updateDimensions(), this._widthCache.clear(), this._setDefaultSpacing();
        }
        _refreshRowElements(e, i) {
          for (let r = this._rowElements.length; r <= i; r++) {
            let n = this._document.createElement("div");
            this._rowContainer.appendChild(n), this._rowElements.push(n);
          }
          for (; this._rowElements.length > i; ) this._rowContainer.removeChild(this._rowElements.pop());
        }
        handleResize(e, i) {
          this._refreshRowElements(e, i), this._updateDimensions(), this.handleSelectionChanged(this._selectionRenderModel.selectionStart, this._selectionRenderModel.selectionEnd, this._selectionRenderModel.columnSelectMode);
        }
        handleCharSizeChanged() {
          this._updateDimensions(), this._widthCache.clear(), this._setDefaultSpacing();
        }
        handleBlur() {
          this._rowContainer.classList.remove(ki), this.renderRows(0, this._bufferService.rows - 1);
        }
        handleFocus() {
          this._rowContainer.classList.add(ki), this.renderRows(this._bufferService.buffer.y, this._bufferService.buffer.y);
        }
        handleSelectionChanged(e, i, r) {
          if (this._selectionContainer.replaceChildren(), this._rowFactory.handleSelectionChanged(e, i, r), this.renderRows(0, this._bufferService.rows - 1), !e || !i || (this._selectionRenderModel.update(this._terminal, e, i, r), !this._selectionRenderModel.hasSelection)) return;
          let n = this._selectionRenderModel.viewportStartRow, o2 = this._selectionRenderModel.viewportEndRow, l2 = this._selectionRenderModel.viewportCappedStartRow, a = this._selectionRenderModel.viewportCappedEndRow, u = this._document.createDocumentFragment();
          if (r) {
            let h2 = e[0] > i[0];
            u.appendChild(this._createSelectionElement(l2, h2 ? i[0] : e[0], h2 ? e[0] : i[0], a - l2 + 1));
          } else {
            let h2 = n === l2 ? e[0] : 0, c = l2 === o2 ? i[0] : this._bufferService.cols;
            u.appendChild(this._createSelectionElement(l2, h2, c));
            let d = a - l2 - 1;
            if (u.appendChild(this._createSelectionElement(l2 + 1, 0, this._bufferService.cols, d)), l2 !== a) {
              let _3 = o2 === a ? i[0] : this._bufferService.cols;
              u.appendChild(this._createSelectionElement(a, 0, _3));
            }
          }
          this._selectionContainer.appendChild(u);
        }
        _createSelectionElement(e, i, r, n = 1) {
          let o2 = this._document.createElement("div"), l2 = i * this.dimensions.css.cell.width, a = this.dimensions.css.cell.width * (r - i);
          return l2 + a > this.dimensions.css.canvas.width && (a = this.dimensions.css.canvas.width - l2), o2.style.height = `${n * this.dimensions.css.cell.height}px`, o2.style.top = `${e * this.dimensions.css.cell.height}px`, o2.style.left = `${l2}px`, o2.style.width = `${a}px`, o2;
        }
        handleCursorMove() {
        }
        _handleOptionsChanged() {
          this._updateDimensions(), this._injectCss(this._themeService.colors), this._widthCache.setFont(this._optionsService.rawOptions.fontFamily, this._optionsService.rawOptions.fontSize, this._optionsService.rawOptions.fontWeight, this._optionsService.rawOptions.fontWeightBold), this._setDefaultSpacing();
        }
        clear() {
          for (let e of this._rowElements) e.replaceChildren();
        }
        renderRows(e, i) {
          let r = this._bufferService.buffer, n = r.ybase + r.y, o2 = Math.min(r.x, this._bufferService.cols - 1), l2 = this._coreService.decPrivateModes.cursorBlink ?? this._optionsService.rawOptions.cursorBlink, a = this._coreService.decPrivateModes.cursorStyle ?? this._optionsService.rawOptions.cursorStyle, u = this._optionsService.rawOptions.cursorInactiveStyle;
          for (let h2 = e; h2 <= i; h2++) {
            let c = h2 + r.ydisp, d = this._rowElements[h2], _3 = r.lines.get(c);
            if (!d || !_3) break;
            d.replaceChildren(...this._rowFactory.createRow(_3, c, c === n, a, u, o2, l2, this.dimensions.css.cell.width, this._widthCache, -1, -1));
          }
        }
        get _terminalSelector() {
          return `.${_s}${this._terminalClass}`;
        }
        _handleLinkHover(e) {
          this._setCellUnderline(e.x1, e.x2, e.y1, e.y2, e.cols, true);
        }
        _handleLinkLeave(e) {
          this._setCellUnderline(e.x1, e.x2, e.y1, e.y2, e.cols, false);
        }
        _setCellUnderline(e, i, r, n, o2, l2) {
          r < 0 && (e = 0), n < 0 && (i = 0);
          let a = this._bufferService.rows - 1;
          r = Math.max(Math.min(r, a), 0), n = Math.max(Math.min(n, a), 0), o2 = Math.min(o2, this._bufferService.cols);
          let u = this._bufferService.buffer, h2 = u.ybase + u.y, c = Math.min(u.x, o2 - 1), d = this._optionsService.rawOptions.cursorBlink, _3 = this._optionsService.rawOptions.cursorStyle, p = this._optionsService.rawOptions.cursorInactiveStyle;
          for (let m = r; m <= n; ++m) {
            let f = m + u.ydisp, A = this._rowElements[m], R = u.lines.get(f);
            if (!A || !R) break;
            A.replaceChildren(...this._rowFactory.createRow(R, f, f === h2, _3, p, c, d, this.dimensions.css.cell.width, this._widthCache, l2 ? m === r ? e : 0 : -1, l2 ? (m === n ? i : o2) - 1 : -1));
          }
        }
      };
      Yt = M([S(7, xt), S(8, nt), S(9, H), S(10, F), S(11, ge), S(12, ae), S(13, Re)], Yt);
      jt = class extends D {
        constructor(e, i, r) {
          super();
          this._optionsService = r;
          this.width = 0;
          this.height = 0;
          this._onCharSizeChange = this._register(new v());
          this.onCharSizeChange = this._onCharSizeChange.event;
          try {
            this._measureStrategy = this._register(new vs(this._optionsService));
          } catch {
            this._measureStrategy = this._register(new bs(e, i, this._optionsService));
          }
          this._register(this._optionsService.onMultipleOptionChange(["fontFamily", "fontSize"], () => this.measure()));
        }
        get hasValidSize() {
          return this.width > 0 && this.height > 0;
        }
        measure() {
          let e = this._measureStrategy.measure();
          (e.width !== this.width || e.height !== this.height) && (this.width = e.width, this.height = e.height, this._onCharSizeChange.fire());
        }
      };
      jt = M([S(2, H)], jt);
      Zr = class extends D {
        constructor() {
          super(...arguments);
          this._result = { width: 0, height: 0 };
        }
        _validateAndSet(e, i) {
          e !== void 0 && e > 0 && i !== void 0 && i > 0 && (this._result.width = e, this._result.height = i);
        }
      };
      bs = class extends Zr {
        constructor(e, i, r) {
          super();
          this._document = e;
          this._parentElement = i;
          this._optionsService = r;
          this._measureElement = this._document.createElement("span"), this._measureElement.classList.add("xterm-char-measure-element"), this._measureElement.textContent = "W".repeat(32), this._measureElement.setAttribute("aria-hidden", "true"), this._measureElement.style.whiteSpace = "pre", this._measureElement.style.fontKerning = "none", this._parentElement.appendChild(this._measureElement);
        }
        measure() {
          return this._measureElement.style.fontFamily = this._optionsService.rawOptions.fontFamily, this._measureElement.style.fontSize = `${this._optionsService.rawOptions.fontSize}px`, this._validateAndSet(Number(this._measureElement.offsetWidth) / 32, Number(this._measureElement.offsetHeight)), this._result;
        }
      };
      vs = class extends Zr {
        constructor(e) {
          super();
          this._optionsService = e;
          this._canvas = new OffscreenCanvas(100, 100), this._ctx = this._canvas.getContext("2d");
          let i = this._ctx.measureText("W");
          if (!("width" in i && "fontBoundingBoxAscent" in i && "fontBoundingBoxDescent" in i)) throw new Error("Required font metrics not supported");
        }
        measure() {
          this._ctx.font = `${this._optionsService.rawOptions.fontSize}px ${this._optionsService.rawOptions.fontFamily}`;
          let e = this._ctx.measureText("W");
          return this._validateAndSet(e.width, e.fontBoundingBoxAscent + e.fontBoundingBoxDescent), this._result;
        }
      };
      Jr = class extends D {
        constructor(e, i, r) {
          super();
          this._textarea = e;
          this._window = i;
          this.mainDocument = r;
          this._isFocused = false;
          this._cachedIsFocused = void 0;
          this._screenDprMonitor = this._register(new gs(this._window));
          this._onDprChange = this._register(new v());
          this.onDprChange = this._onDprChange.event;
          this._onWindowChange = this._register(new v());
          this.onWindowChange = this._onWindowChange.event;
          this._register(this.onWindowChange((n) => this._screenDprMonitor.setWindow(n))), this._register($.forward(this._screenDprMonitor.onDprChange, this._onDprChange)), this._register(L(this._textarea, "focus", () => this._isFocused = true)), this._register(L(this._textarea, "blur", () => this._isFocused = false));
        }
        get window() {
          return this._window;
        }
        set window(e) {
          this._window !== e && (this._window = e, this._onWindowChange.fire(this._window));
        }
        get dpr() {
          return this.window.devicePixelRatio;
        }
        get isFocused() {
          return this._cachedIsFocused === void 0 && (this._cachedIsFocused = this._isFocused && this._textarea.ownerDocument.hasFocus(), queueMicrotask(() => this._cachedIsFocused = void 0)), this._cachedIsFocused;
        }
      };
      gs = class extends D {
        constructor(e) {
          super();
          this._parentWindow = e;
          this._windowResizeListener = this._register(new ye());
          this._onDprChange = this._register(new v());
          this.onDprChange = this._onDprChange.event;
          this._outerListener = () => this._setDprAndFireIfDiffers(), this._currentDevicePixelRatio = this._parentWindow.devicePixelRatio, this._updateDpr(), this._setWindowResizeListener(), this._register(C(() => this.clearListener()));
        }
        setWindow(e) {
          this._parentWindow = e, this._setWindowResizeListener(), this._setDprAndFireIfDiffers();
        }
        _setWindowResizeListener() {
          this._windowResizeListener.value = L(this._parentWindow, "resize", () => this._setDprAndFireIfDiffers());
        }
        _setDprAndFireIfDiffers() {
          this._parentWindow.devicePixelRatio !== this._currentDevicePixelRatio && this._onDprChange.fire(this._parentWindow.devicePixelRatio), this._updateDpr();
        }
        _updateDpr() {
          this._outerListener && (this._resolutionMediaMatchList?.removeListener(this._outerListener), this._currentDevicePixelRatio = this._parentWindow.devicePixelRatio, this._resolutionMediaMatchList = this._parentWindow.matchMedia(`screen and (resolution: ${this._parentWindow.devicePixelRatio}dppx)`), this._resolutionMediaMatchList.addListener(this._outerListener));
        }
        clearListener() {
          !this._resolutionMediaMatchList || !this._outerListener || (this._resolutionMediaMatchList.removeListener(this._outerListener), this._resolutionMediaMatchList = void 0, this._outerListener = void 0);
        }
      };
      Qr = class extends D {
        constructor() {
          super();
          this.linkProviders = [];
          this._register(C(() => this.linkProviders.length = 0));
        }
        registerLinkProvider(e) {
          return this.linkProviders.push(e), { dispose: () => {
            let i = this.linkProviders.indexOf(e);
            i !== -1 && this.linkProviders.splice(i, 1);
          } };
        }
      };
      Xt = class {
        constructor(t, e) {
          this._renderService = t;
          this._charSizeService = e;
        }
        getCoords(t, e, i, r, n) {
          return Xo(window, t, e, i, r, this._charSizeService.hasValidSize, this._renderService.dimensions.css.cell.width, this._renderService.dimensions.css.cell.height, n);
        }
        getMouseReportCoords(t, e) {
          let i = Ci(window, t, e);
          if (this._charSizeService.hasValidSize) return i[0] = Math.min(Math.max(i[0], 0), this._renderService.dimensions.css.canvas.width - 1), i[1] = Math.min(Math.max(i[1], 0), this._renderService.dimensions.css.canvas.height - 1), { col: Math.floor(i[0] / this._renderService.dimensions.css.cell.width), row: Math.floor(i[1] / this._renderService.dimensions.css.cell.height), x: Math.floor(i[0]), y: Math.floor(i[1]) };
        }
      };
      Xt = M([S(0, ce), S(1, nt)], Xt);
      en = class {
        constructor(t, e) {
          this._renderCallback = t;
          this._coreBrowserService = e;
          this._refreshCallbacks = [];
        }
        dispose() {
          this._animationFrame && (this._coreBrowserService.window.cancelAnimationFrame(this._animationFrame), this._animationFrame = void 0);
        }
        addRefreshCallback(t) {
          return this._refreshCallbacks.push(t), this._animationFrame || (this._animationFrame = this._coreBrowserService.window.requestAnimationFrame(() => this._innerRefresh())), this._animationFrame;
        }
        refresh(t, e, i) {
          this._rowCount = i, t = t !== void 0 ? t : 0, e = e !== void 0 ? e : this._rowCount - 1, this._rowStart = this._rowStart !== void 0 ? Math.min(this._rowStart, t) : t, this._rowEnd = this._rowEnd !== void 0 ? Math.max(this._rowEnd, e) : e, !this._animationFrame && (this._animationFrame = this._coreBrowserService.window.requestAnimationFrame(() => this._innerRefresh()));
        }
        _innerRefresh() {
          if (this._animationFrame = void 0, this._rowStart === void 0 || this._rowEnd === void 0 || this._rowCount === void 0) {
            this._runRefreshCallbacks();
            return;
          }
          let t = Math.max(this._rowStart, 0), e = Math.min(this._rowEnd, this._rowCount - 1);
          this._rowStart = void 0, this._rowEnd = void 0, this._renderCallback(t, e), this._runRefreshCallbacks();
        }
        _runRefreshCallbacks() {
          for (let t of this._refreshCallbacks) t(0);
          this._refreshCallbacks = [];
        }
      };
      tn = {};
      Ll(tn, { getSafariVersion: () => Ha, isChromeOS: () => Ts, isFirefox: () => Ss, isIpad: () => Wa, isIphone: () => Ua, isLegacyEdge: () => Fa, isLinux: () => Bi, isMac: () => Zt, isNode: () => Mi, isSafari: () => Zo, isWindows: () => Es });
      Mi = typeof process < "u" && "title" in process;
      Pi = Mi ? "node" : navigator.userAgent;
      Oi = Mi ? "node" : navigator.platform;
      Ss = Pi.includes("Firefox");
      Fa = Pi.includes("Edge");
      Zo = /^((?!chrome|android).)*safari/i.test(Pi);
      Zt = ["Macintosh", "MacIntel", "MacPPC", "Mac68K"].includes(Oi);
      Wa = Oi === "iPad";
      Ua = Oi === "iPhone";
      Es = ["Windows", "Win16", "Win32", "WinCE"].includes(Oi);
      Bi = Oi.indexOf("Linux") >= 0;
      Ts = /\bCrOS\b/.test(Pi);
      rn = class {
        constructor() {
          this._tasks = [];
          this._i = 0;
        }
        enqueue(t) {
          this._tasks.push(t), this._start();
        }
        flush() {
          for (; this._i < this._tasks.length; ) this._tasks[this._i]() || this._i++;
          this.clear();
        }
        clear() {
          this._idleCallback && (this._cancelCallback(this._idleCallback), this._idleCallback = void 0), this._i = 0, this._tasks.length = 0;
        }
        _start() {
          this._idleCallback || (this._idleCallback = this._requestCallback(this._process.bind(this)));
        }
        _process(t) {
          this._idleCallback = void 0;
          let e = 0, i = 0, r = t.timeRemaining(), n = 0;
          for (; this._i < this._tasks.length; ) {
            if (e = performance.now(), this._tasks[this._i]() || this._i++, e = Math.max(1, performance.now() - e), i = Math.max(e, i), n = t.timeRemaining(), i * 1.5 > n) {
              r - e < -20 && console.warn(`task queue exceeded allotted deadline by ${Math.abs(Math.round(r - e))}ms`), this._start();
              return;
            }
            r = n;
          }
          this.clear();
        }
      };
      Is = class extends rn {
        _requestCallback(t) {
          return setTimeout(() => t(this._createDeadline(16)));
        }
        _cancelCallback(t) {
          clearTimeout(t);
        }
        _createDeadline(t) {
          let e = performance.now() + t;
          return { timeRemaining: () => Math.max(0, e - performance.now()) };
        }
      };
      ys = class extends rn {
        _requestCallback(t) {
          return requestIdleCallback(t);
        }
        _cancelCallback(t) {
          cancelIdleCallback(t);
        }
      };
      Jt = !Mi && "requestIdleCallback" in window ? ys : Is;
      nn = class {
        constructor() {
          this._queue = new Jt();
        }
        set(t) {
          this._queue.clear(), this._queue.enqueue(t);
        }
        flush() {
          this._queue.flush();
        }
      };
      Qt = class extends D {
        constructor(e, i, r, n, o2, l2, a, u, h2) {
          super();
          this._rowCount = e;
          this._optionsService = r;
          this._charSizeService = n;
          this._coreService = o2;
          this._coreBrowserService = u;
          this._renderer = this._register(new ye());
          this._pausedResizeTask = new nn();
          this._observerDisposable = this._register(new ye());
          this._isPaused = false;
          this._needsFullRefresh = false;
          this._isNextRenderRedrawOnly = true;
          this._needsSelectionRefresh = false;
          this._canvasWidth = 0;
          this._canvasHeight = 0;
          this._selectionState = { start: void 0, end: void 0, columnSelectMode: false };
          this._onDimensionsChange = this._register(new v());
          this.onDimensionsChange = this._onDimensionsChange.event;
          this._onRenderedViewportChange = this._register(new v());
          this.onRenderedViewportChange = this._onRenderedViewportChange.event;
          this._onRender = this._register(new v());
          this.onRender = this._onRender.event;
          this._onRefreshRequest = this._register(new v());
          this.onRefreshRequest = this._onRefreshRequest.event;
          this._renderDebouncer = new en((c, d) => this._renderRows(c, d), this._coreBrowserService), this._register(this._renderDebouncer), this._syncOutputHandler = new xs(this._coreBrowserService, this._coreService, () => this._fullRefresh()), this._register(C(() => this._syncOutputHandler.dispose())), this._register(this._coreBrowserService.onDprChange(() => this.handleDevicePixelRatioChange())), this._register(a.onResize(() => this._fullRefresh())), this._register(a.buffers.onBufferActivate(() => this._renderer.value?.clear())), this._register(this._optionsService.onOptionChange(() => this._handleOptionsChanged())), this._register(this._charSizeService.onCharSizeChange(() => this.handleCharSizeChanged())), this._register(l2.onDecorationRegistered(() => this._fullRefresh())), this._register(l2.onDecorationRemoved(() => this._fullRefresh())), this._register(this._optionsService.onMultipleOptionChange(["customGlyphs", "drawBoldTextInBrightColors", "letterSpacing", "lineHeight", "fontFamily", "fontSize", "fontWeight", "fontWeightBold", "minimumContrastRatio", "rescaleOverlappingGlyphs"], () => {
            this.clear(), this.handleResize(a.cols, a.rows), this._fullRefresh();
          })), this._register(this._optionsService.onMultipleOptionChange(["cursorBlink", "cursorStyle"], () => this.refreshRows(a.buffer.y, a.buffer.y, true))), this._register(h2.onChangeColors(() => this._fullRefresh())), this._registerIntersectionObserver(this._coreBrowserService.window, i), this._register(this._coreBrowserService.onWindowChange((c) => this._registerIntersectionObserver(c, i)));
        }
        get dimensions() {
          return this._renderer.value.dimensions;
        }
        _registerIntersectionObserver(e, i) {
          if ("IntersectionObserver" in e) {
            let r = new e.IntersectionObserver((n) => this._handleIntersectionChange(n[n.length - 1]), { threshold: 0 });
            r.observe(i), this._observerDisposable.value = C(() => r.disconnect());
          }
        }
        _handleIntersectionChange(e) {
          this._isPaused = e.isIntersecting === void 0 ? e.intersectionRatio === 0 : !e.isIntersecting, !this._isPaused && !this._charSizeService.hasValidSize && this._charSizeService.measure(), !this._isPaused && this._needsFullRefresh && (this._pausedResizeTask.flush(), this.refreshRows(0, this._rowCount - 1), this._needsFullRefresh = false);
        }
        refreshRows(e, i, r = false) {
          if (this._isPaused) {
            this._needsFullRefresh = true;
            return;
          }
          if (this._coreService.decPrivateModes.synchronizedOutput) {
            this._syncOutputHandler.bufferRows(e, i);
            return;
          }
          let n = this._syncOutputHandler.flush();
          n && (e = Math.min(e, n.start), i = Math.max(i, n.end)), r || (this._isNextRenderRedrawOnly = false), this._renderDebouncer.refresh(e, i, this._rowCount);
        }
        _renderRows(e, i) {
          if (this._renderer.value) {
            if (this._coreService.decPrivateModes.synchronizedOutput) {
              this._syncOutputHandler.bufferRows(e, i);
              return;
            }
            e = Math.min(e, this._rowCount - 1), i = Math.min(i, this._rowCount - 1), this._renderer.value.renderRows(e, i), this._needsSelectionRefresh && (this._renderer.value.handleSelectionChanged(this._selectionState.start, this._selectionState.end, this._selectionState.columnSelectMode), this._needsSelectionRefresh = false), this._isNextRenderRedrawOnly || this._onRenderedViewportChange.fire({ start: e, end: i }), this._onRender.fire({ start: e, end: i }), this._isNextRenderRedrawOnly = true;
          }
        }
        resize(e, i) {
          this._rowCount = i, this._fireOnCanvasResize();
        }
        _handleOptionsChanged() {
          this._renderer.value && (this.refreshRows(0, this._rowCount - 1), this._fireOnCanvasResize());
        }
        _fireOnCanvasResize() {
          this._renderer.value && (this._renderer.value.dimensions.css.canvas.width === this._canvasWidth && this._renderer.value.dimensions.css.canvas.height === this._canvasHeight || this._onDimensionsChange.fire(this._renderer.value.dimensions));
        }
        hasRenderer() {
          return !!this._renderer.value;
        }
        setRenderer(e) {
          this._renderer.value = e, this._renderer.value && (this._renderer.value.onRequestRedraw((i) => this.refreshRows(i.start, i.end, true)), this._needsSelectionRefresh = true, this._fullRefresh());
        }
        addRefreshCallback(e) {
          return this._renderDebouncer.addRefreshCallback(e);
        }
        _fullRefresh() {
          this._isPaused ? this._needsFullRefresh = true : this.refreshRows(0, this._rowCount - 1);
        }
        clearTextureAtlas() {
          this._renderer.value && (this._renderer.value.clearTextureAtlas?.(), this._fullRefresh());
        }
        handleDevicePixelRatioChange() {
          this._charSizeService.measure(), this._renderer.value && (this._renderer.value.handleDevicePixelRatioChange(), this.refreshRows(0, this._rowCount - 1));
        }
        handleResize(e, i) {
          this._renderer.value && (this._isPaused ? this._pausedResizeTask.set(() => this._renderer.value?.handleResize(e, i)) : this._renderer.value.handleResize(e, i), this._fullRefresh());
        }
        handleCharSizeChanged() {
          this._renderer.value?.handleCharSizeChanged();
        }
        handleBlur() {
          this._renderer.value?.handleBlur();
        }
        handleFocus() {
          this._renderer.value?.handleFocus();
        }
        handleSelectionChanged(e, i, r) {
          this._selectionState.start = e, this._selectionState.end = i, this._selectionState.columnSelectMode = r, this._renderer.value?.handleSelectionChanged(e, i, r);
        }
        handleCursorMove() {
          this._renderer.value?.handleCursorMove();
        }
        clear() {
          this._renderer.value?.clear();
        }
      };
      Qt = M([S(2, H), S(3, nt), S(4, ge), S(5, Be), S(6, F), S(7, ae), S(8, Re)], Qt);
      xs = class {
        constructor(t, e, i) {
          this._coreBrowserService = t;
          this._coreService = e;
          this._onTimeout = i;
          this._start = 0;
          this._end = 0;
          this._isBuffering = false;
        }
        bufferRows(t, e) {
          this._isBuffering ? (this._start = Math.min(this._start, t), this._end = Math.max(this._end, e)) : (this._start = t, this._end = e, this._isBuffering = true), this._timeout === void 0 && (this._timeout = this._coreBrowserService.window.setTimeout(() => {
            this._timeout = void 0, this._coreService.decPrivateModes.synchronizedOutput = false, this._onTimeout();
          }, 1e3));
        }
        flush() {
          if (this._timeout !== void 0 && (this._coreBrowserService.window.clearTimeout(this._timeout), this._timeout = void 0), !this._isBuffering) return;
          let t = { start: this._start, end: this._end };
          return this._isBuffering = false, t;
        }
        dispose() {
          this._timeout !== void 0 && (this._coreBrowserService.window.clearTimeout(this._timeout), this._timeout = void 0);
        }
      };
      on = class {
        constructor(t) {
          this._bufferService = t;
          this.isSelectAllActive = false;
          this.selectionStartLength = 0;
        }
        clearSelection() {
          this.selectionStart = void 0, this.selectionEnd = void 0, this.isSelectAllActive = false, this.selectionStartLength = 0;
        }
        get finalSelectionStart() {
          return this.isSelectAllActive ? [0, 0] : !this.selectionEnd || !this.selectionStart ? this.selectionStart : this.areSelectionValuesReversed() ? this.selectionEnd : this.selectionStart;
        }
        get finalSelectionEnd() {
          if (this.isSelectAllActive) return [this._bufferService.cols, this._bufferService.buffer.ybase + this._bufferService.rows - 1];
          if (this.selectionStart) {
            if (!this.selectionEnd || this.areSelectionValuesReversed()) {
              let t = this.selectionStart[0] + this.selectionStartLength;
              return t > this._bufferService.cols ? t % this._bufferService.cols === 0 ? [this._bufferService.cols, this.selectionStart[1] + Math.floor(t / this._bufferService.cols) - 1] : [t % this._bufferService.cols, this.selectionStart[1] + Math.floor(t / this._bufferService.cols)] : [t, this.selectionStart[1]];
            }
            if (this.selectionStartLength && this.selectionEnd[1] === this.selectionStart[1]) {
              let t = this.selectionStart[0] + this.selectionStartLength;
              return t > this._bufferService.cols ? [t % this._bufferService.cols, this.selectionStart[1] + Math.floor(t / this._bufferService.cols)] : [Math.max(t, this.selectionEnd[0]), this.selectionEnd[1]];
            }
            return this.selectionEnd;
          }
        }
        areSelectionValuesReversed() {
          let t = this.selectionStart, e = this.selectionEnd;
          return !t || !e ? false : t[1] > e[1] || t[1] === e[1] && t[0] > e[0];
        }
        handleTrim(t) {
          return this.selectionStart && (this.selectionStart[1] -= t), this.selectionEnd && (this.selectionEnd[1] -= t), this.selectionEnd && this.selectionEnd[1] < 0 ? (this.clearSelection(), true) : (this.selectionStart && this.selectionStart[1] < 0 && (this.selectionStart[1] = 0), false);
        }
      };
      Ds = 50;
      Ya = 15;
      ja = 50;
      Xa = 500;
      Za = "\xA0";
      Ja = new RegExp(Za, "g");
      ei = class extends D {
        constructor(e, i, r, n, o2, l2, a, u, h2) {
          super();
          this._element = e;
          this._screenElement = i;
          this._linkifier = r;
          this._bufferService = n;
          this._coreService = o2;
          this._mouseService = l2;
          this._optionsService = a;
          this._renderService = u;
          this._coreBrowserService = h2;
          this._dragScrollAmount = 0;
          this._enabled = true;
          this._workCell = new q();
          this._mouseDownTimeStamp = 0;
          this._oldHasSelection = false;
          this._oldSelectionStart = void 0;
          this._oldSelectionEnd = void 0;
          this._onLinuxMouseSelection = this._register(new v());
          this.onLinuxMouseSelection = this._onLinuxMouseSelection.event;
          this._onRedrawRequest = this._register(new v());
          this.onRequestRedraw = this._onRedrawRequest.event;
          this._onSelectionChange = this._register(new v());
          this.onSelectionChange = this._onSelectionChange.event;
          this._onRequestScrollLines = this._register(new v());
          this.onRequestScrollLines = this._onRequestScrollLines.event;
          this._mouseMoveListener = (c) => this._handleMouseMove(c), this._mouseUpListener = (c) => this._handleMouseUp(c), this._coreService.onUserInput(() => {
            this.hasSelection && this.clearSelection();
          }), this._trimListener = this._bufferService.buffer.lines.onTrim((c) => this._handleTrim(c)), this._register(this._bufferService.buffers.onBufferActivate((c) => this._handleBufferActivate(c))), this.enable(), this._model = new on(this._bufferService), this._activeSelectionMode = 0, this._register(C(() => {
            this._removeMouseDownListeners();
          })), this._register(this._bufferService.onResize((c) => {
            c.rowsChanged && this.clearSelection();
          }));
        }
        reset() {
          this.clearSelection();
        }
        disable() {
          this.clearSelection(), this._enabled = false;
        }
        enable() {
          this._enabled = true;
        }
        get selectionStart() {
          return this._model.finalSelectionStart;
        }
        get selectionEnd() {
          return this._model.finalSelectionEnd;
        }
        get hasSelection() {
          let e = this._model.finalSelectionStart, i = this._model.finalSelectionEnd;
          return !e || !i ? false : e[0] !== i[0] || e[1] !== i[1];
        }
        get selectionText() {
          let e = this._model.finalSelectionStart, i = this._model.finalSelectionEnd;
          if (!e || !i) return "";
          let r = this._bufferService.buffer, n = [];
          if (this._activeSelectionMode === 3) {
            if (e[0] === i[0]) return "";
            let l2 = e[0] < i[0] ? e[0] : i[0], a = e[0] < i[0] ? i[0] : e[0];
            for (let u = e[1]; u <= i[1]; u++) {
              let h2 = r.translateBufferLineToString(u, true, l2, a);
              n.push(h2);
            }
          } else {
            let l2 = e[1] === i[1] ? i[0] : void 0;
            n.push(r.translateBufferLineToString(e[1], true, e[0], l2));
            for (let a = e[1] + 1; a <= i[1] - 1; a++) {
              let u = r.lines.get(a), h2 = r.translateBufferLineToString(a, true);
              u?.isWrapped ? n[n.length - 1] += h2 : n.push(h2);
            }
            if (e[1] !== i[1]) {
              let a = r.lines.get(i[1]), u = r.translateBufferLineToString(i[1], true, 0, i[0]);
              a && a.isWrapped ? n[n.length - 1] += u : n.push(u);
            }
          }
          return n.map((l2) => l2.replace(Ja, " ")).join(Es ? `\r
` : `
`);
        }
        clearSelection() {
          this._model.clearSelection(), this._removeMouseDownListeners(), this.refresh(), this._onSelectionChange.fire();
        }
        refresh(e) {
          this._refreshAnimationFrame || (this._refreshAnimationFrame = this._coreBrowserService.window.requestAnimationFrame(() => this._refresh())), Bi && e && this.selectionText.length && this._onLinuxMouseSelection.fire(this.selectionText);
        }
        _refresh() {
          this._refreshAnimationFrame = void 0, this._onRedrawRequest.fire({ start: this._model.finalSelectionStart, end: this._model.finalSelectionEnd, columnSelectMode: this._activeSelectionMode === 3 });
        }
        _isClickInSelection(e) {
          let i = this._getMouseBufferCoords(e), r = this._model.finalSelectionStart, n = this._model.finalSelectionEnd;
          return !r || !n || !i ? false : this._areCoordsInSelection(i, r, n);
        }
        isCellInSelection(e, i) {
          let r = this._model.finalSelectionStart, n = this._model.finalSelectionEnd;
          return !r || !n ? false : this._areCoordsInSelection([e, i], r, n);
        }
        _areCoordsInSelection(e, i, r) {
          return e[1] > i[1] && e[1] < r[1] || i[1] === r[1] && e[1] === i[1] && e[0] >= i[0] && e[0] < r[0] || i[1] < r[1] && e[1] === r[1] && e[0] < r[0] || i[1] < r[1] && e[1] === i[1] && e[0] >= i[0];
        }
        _selectWordAtCursor(e, i) {
          let r = this._linkifier.currentLink?.link?.range;
          if (r) return this._model.selectionStart = [r.start.x - 1, r.start.y - 1], this._model.selectionStartLength = ws(r, this._bufferService.cols), this._model.selectionEnd = void 0, true;
          let n = this._getMouseBufferCoords(e);
          return n ? (this._selectWordAt(n, i), this._model.selectionEnd = void 0, true) : false;
        }
        selectAll() {
          this._model.isSelectAllActive = true, this.refresh(), this._onSelectionChange.fire();
        }
        selectLines(e, i) {
          this._model.clearSelection(), e = Math.max(e, 0), i = Math.min(i, this._bufferService.buffer.lines.length - 1), this._model.selectionStart = [0, e], this._model.selectionEnd = [this._bufferService.cols, i], this.refresh(), this._onSelectionChange.fire();
        }
        _handleTrim(e) {
          this._model.handleTrim(e) && this.refresh();
        }
        _getMouseBufferCoords(e) {
          let i = this._mouseService.getCoords(e, this._screenElement, this._bufferService.cols, this._bufferService.rows, true);
          if (i) return i[0]--, i[1]--, i[1] += this._bufferService.buffer.ydisp, i;
        }
        _getMouseEventScrollAmount(e) {
          let i = Ci(this._coreBrowserService.window, e, this._screenElement)[1], r = this._renderService.dimensions.css.canvas.height;
          return i >= 0 && i <= r ? 0 : (i > r && (i -= r), i = Math.min(Math.max(i, -Ds), Ds), i /= Ds, i / Math.abs(i) + Math.round(i * (Ya - 1)));
        }
        shouldForceSelection(e) {
          return Zt ? e.altKey && this._optionsService.rawOptions.macOptionClickForcesSelection : e.shiftKey;
        }
        handleMouseDown(e) {
          if (this._mouseDownTimeStamp = e.timeStamp, !(e.button === 2 && this.hasSelection) && e.button === 0) {
            if (!this._enabled) {
              if (!this.shouldForceSelection(e)) return;
              e.stopPropagation();
            }
            e.preventDefault(), this._dragScrollAmount = 0, this._enabled && e.shiftKey ? this._handleIncrementalClick(e) : e.detail === 1 ? this._handleSingleClick(e) : e.detail === 2 ? this._handleDoubleClick(e) : e.detail === 3 && this._handleTripleClick(e), this._addMouseDownListeners(), this.refresh(true);
          }
        }
        _addMouseDownListeners() {
          this._screenElement.ownerDocument && (this._screenElement.ownerDocument.addEventListener("mousemove", this._mouseMoveListener), this._screenElement.ownerDocument.addEventListener("mouseup", this._mouseUpListener)), this._dragScrollIntervalTimer = this._coreBrowserService.window.setInterval(() => this._dragScroll(), ja);
        }
        _removeMouseDownListeners() {
          this._screenElement.ownerDocument && (this._screenElement.ownerDocument.removeEventListener("mousemove", this._mouseMoveListener), this._screenElement.ownerDocument.removeEventListener("mouseup", this._mouseUpListener)), this._coreBrowserService.window.clearInterval(this._dragScrollIntervalTimer), this._dragScrollIntervalTimer = void 0;
        }
        _handleIncrementalClick(e) {
          this._model.selectionStart && (this._model.selectionEnd = this._getMouseBufferCoords(e));
        }
        _handleSingleClick(e) {
          if (this._model.selectionStartLength = 0, this._model.isSelectAllActive = false, this._activeSelectionMode = this.shouldColumnSelect(e) ? 3 : 0, this._model.selectionStart = this._getMouseBufferCoords(e), !this._model.selectionStart) return;
          this._model.selectionEnd = void 0;
          let i = this._bufferService.buffer.lines.get(this._model.selectionStart[1]);
          i && i.length !== this._model.selectionStart[0] && i.hasWidth(this._model.selectionStart[0]) === 0 && this._model.selectionStart[0]++;
        }
        _handleDoubleClick(e) {
          this._selectWordAtCursor(e, true) && (this._activeSelectionMode = 1);
        }
        _handleTripleClick(e) {
          let i = this._getMouseBufferCoords(e);
          i && (this._activeSelectionMode = 2, this._selectLineAt(i[1]));
        }
        shouldColumnSelect(e) {
          return e.altKey && !(Zt && this._optionsService.rawOptions.macOptionClickForcesSelection);
        }
        _handleMouseMove(e) {
          if (e.stopImmediatePropagation(), !this._model.selectionStart) return;
          let i = this._model.selectionEnd ? [this._model.selectionEnd[0], this._model.selectionEnd[1]] : null;
          if (this._model.selectionEnd = this._getMouseBufferCoords(e), !this._model.selectionEnd) {
            this.refresh(true);
            return;
          }
          this._activeSelectionMode === 2 ? this._model.selectionEnd[1] < this._model.selectionStart[1] ? this._model.selectionEnd[0] = 0 : this._model.selectionEnd[0] = this._bufferService.cols : this._activeSelectionMode === 1 && this._selectToWordAt(this._model.selectionEnd), this._dragScrollAmount = this._getMouseEventScrollAmount(e), this._activeSelectionMode !== 3 && (this._dragScrollAmount > 0 ? this._model.selectionEnd[0] = this._bufferService.cols : this._dragScrollAmount < 0 && (this._model.selectionEnd[0] = 0));
          let r = this._bufferService.buffer;
          if (this._model.selectionEnd[1] < r.lines.length) {
            let n = r.lines.get(this._model.selectionEnd[1]);
            n && n.hasWidth(this._model.selectionEnd[0]) === 0 && this._model.selectionEnd[0] < this._bufferService.cols && this._model.selectionEnd[0]++;
          }
          (!i || i[0] !== this._model.selectionEnd[0] || i[1] !== this._model.selectionEnd[1]) && this.refresh(true);
        }
        _dragScroll() {
          if (!(!this._model.selectionEnd || !this._model.selectionStart) && this._dragScrollAmount) {
            this._onRequestScrollLines.fire({ amount: this._dragScrollAmount, suppressScrollEvent: false });
            let e = this._bufferService.buffer;
            this._dragScrollAmount > 0 ? (this._activeSelectionMode !== 3 && (this._model.selectionEnd[0] = this._bufferService.cols), this._model.selectionEnd[1] = Math.min(e.ydisp + this._bufferService.rows, e.lines.length - 1)) : (this._activeSelectionMode !== 3 && (this._model.selectionEnd[0] = 0), this._model.selectionEnd[1] = e.ydisp), this.refresh();
          }
        }
        _handleMouseUp(e) {
          let i = e.timeStamp - this._mouseDownTimeStamp;
          if (this._removeMouseDownListeners(), this.selectionText.length <= 1 && i < Xa && e.altKey && this._optionsService.rawOptions.altClickMovesCursor) {
            if (this._bufferService.buffer.ybase === this._bufferService.buffer.ydisp) {
              let r = this._mouseService.getCoords(e, this._element, this._bufferService.cols, this._bufferService.rows, false);
              if (r && r[0] !== void 0 && r[1] !== void 0) {
                let n = Jo(r[0] - 1, r[1] - 1, this._bufferService, this._coreService.decPrivateModes.applicationCursorKeys);
                this._coreService.triggerDataEvent(n, true);
              }
            }
          } else this._fireEventIfSelectionChanged();
        }
        _fireEventIfSelectionChanged() {
          let e = this._model.finalSelectionStart, i = this._model.finalSelectionEnd, r = !!e && !!i && (e[0] !== i[0] || e[1] !== i[1]);
          if (!r) {
            this._oldHasSelection && this._fireOnSelectionChange(e, i, r);
            return;
          }
          !e || !i || (!this._oldSelectionStart || !this._oldSelectionEnd || e[0] !== this._oldSelectionStart[0] || e[1] !== this._oldSelectionStart[1] || i[0] !== this._oldSelectionEnd[0] || i[1] !== this._oldSelectionEnd[1]) && this._fireOnSelectionChange(e, i, r);
        }
        _fireOnSelectionChange(e, i, r) {
          this._oldSelectionStart = e, this._oldSelectionEnd = i, this._oldHasSelection = r, this._onSelectionChange.fire();
        }
        _handleBufferActivate(e) {
          this.clearSelection(), this._trimListener.dispose(), this._trimListener = e.activeBuffer.lines.onTrim((i) => this._handleTrim(i));
        }
        _convertViewportColToCharacterIndex(e, i) {
          let r = i;
          for (let n = 0; i >= n; n++) {
            let o2 = e.loadCell(n, this._workCell).getChars().length;
            this._workCell.getWidth() === 0 ? r-- : o2 > 1 && i !== n && (r += o2 - 1);
          }
          return r;
        }
        setSelection(e, i, r) {
          this._model.clearSelection(), this._removeMouseDownListeners(), this._model.selectionStart = [e, i], this._model.selectionStartLength = r, this.refresh(), this._fireEventIfSelectionChanged();
        }
        rightClickSelect(e) {
          this._isClickInSelection(e) || (this._selectWordAtCursor(e, false) && this.refresh(true), this._fireEventIfSelectionChanged());
        }
        _getWordAt(e, i, r = true, n = true) {
          if (e[0] >= this._bufferService.cols) return;
          let o2 = this._bufferService.buffer, l2 = o2.lines.get(e[1]);
          if (!l2) return;
          let a = o2.translateBufferLineToString(e[1], false), u = this._convertViewportColToCharacterIndex(l2, e[0]), h2 = u, c = e[0] - u, d = 0, _3 = 0, p = 0, m = 0;
          if (a.charAt(u) === " ") {
            for (; u > 0 && a.charAt(u - 1) === " "; ) u--;
            for (; h2 < a.length && a.charAt(h2 + 1) === " "; ) h2++;
          } else {
            let R = e[0], O = e[0];
            l2.getWidth(R) === 0 && (d++, R--), l2.getWidth(O) === 2 && (_3++, O++);
            let I = l2.getString(O).length;
            for (I > 1 && (m += I - 1, h2 += I - 1); R > 0 && u > 0 && !this._isCharWordSeparator(l2.loadCell(R - 1, this._workCell)); ) {
              l2.loadCell(R - 1, this._workCell);
              let k2 = this._workCell.getChars().length;
              this._workCell.getWidth() === 0 ? (d++, R--) : k2 > 1 && (p += k2 - 1, u -= k2 - 1), u--, R--;
            }
            for (; O < l2.length && h2 + 1 < a.length && !this._isCharWordSeparator(l2.loadCell(O + 1, this._workCell)); ) {
              l2.loadCell(O + 1, this._workCell);
              let k2 = this._workCell.getChars().length;
              this._workCell.getWidth() === 2 ? (_3++, O++) : k2 > 1 && (m += k2 - 1, h2 += k2 - 1), h2++, O++;
            }
          }
          h2++;
          let f = u + c - d + p, A = Math.min(this._bufferService.cols, h2 - u + d + _3 - p - m);
          if (!(!i && a.slice(u, h2).trim() === "")) {
            if (r && f === 0 && l2.getCodePoint(0) !== 32) {
              let R = o2.lines.get(e[1] - 1);
              if (R && l2.isWrapped && R.getCodePoint(this._bufferService.cols - 1) !== 32) {
                let O = this._getWordAt([this._bufferService.cols - 1, e[1] - 1], false, true, false);
                if (O) {
                  let I = this._bufferService.cols - O.start;
                  f -= I, A += I;
                }
              }
            }
            if (n && f + A === this._bufferService.cols && l2.getCodePoint(this._bufferService.cols - 1) !== 32) {
              let R = o2.lines.get(e[1] + 1);
              if (R?.isWrapped && R.getCodePoint(0) !== 32) {
                let O = this._getWordAt([0, e[1] + 1], false, false, true);
                O && (A += O.length);
              }
            }
            return { start: f, length: A };
          }
        }
        _selectWordAt(e, i) {
          let r = this._getWordAt(e, i);
          if (r) {
            for (; r.start < 0; ) r.start += this._bufferService.cols, e[1]--;
            this._model.selectionStart = [r.start, e[1]], this._model.selectionStartLength = r.length;
          }
        }
        _selectToWordAt(e) {
          let i = this._getWordAt(e, true);
          if (i) {
            let r = e[1];
            for (; i.start < 0; ) i.start += this._bufferService.cols, r--;
            if (!this._model.areSelectionValuesReversed()) for (; i.start + i.length > this._bufferService.cols; ) i.length -= this._bufferService.cols, r++;
            this._model.selectionEnd = [this._model.areSelectionValuesReversed() ? i.start : i.start + i.length, r];
          }
        }
        _isCharWordSeparator(e) {
          return e.getWidth() === 0 ? false : this._optionsService.rawOptions.wordSeparator.indexOf(e.getChars()) >= 0;
        }
        _selectLineAt(e) {
          let i = this._bufferService.buffer.getWrappedRangeForLine(e), r = { start: { x: 0, y: i.first }, end: { x: this._bufferService.cols - 1, y: i.last } };
          this._model.selectionStart = [0, i.first], this._model.selectionEnd = void 0, this._model.selectionStartLength = ws(r, this._bufferService.cols);
        }
      };
      ei = M([S(3, F), S(4, ge), S(5, Dt), S(6, H), S(7, ce), S(8, ae)], ei);
      Hi = class {
        constructor() {
          this._data = {};
        }
        set(t, e, i) {
          this._data[t] || (this._data[t] = {}), this._data[t][e] = i;
        }
        get(t, e) {
          return this._data[t] ? this._data[t][e] : void 0;
        }
        clear() {
          this._data = {};
        }
      };
      Wi = class {
        constructor() {
          this._color = new Hi();
          this._css = new Hi();
        }
        setCss(t, e, i) {
          this._css.set(t, e, i);
        }
        getCss(t, e) {
          return this._css.get(t, e);
        }
        setColor(t, e, i) {
          this._color.set(t, e, i);
        }
        getColor(t, e) {
          return this._color.get(t, e);
        }
        clear() {
          this._color.clear(), this._css.clear();
        }
      };
      re = Object.freeze((() => {
        let s15 = [z.toColor("#2e3436"), z.toColor("#cc0000"), z.toColor("#4e9a06"), z.toColor("#c4a000"), z.toColor("#3465a4"), z.toColor("#75507b"), z.toColor("#06989a"), z.toColor("#d3d7cf"), z.toColor("#555753"), z.toColor("#ef2929"), z.toColor("#8ae234"), z.toColor("#fce94f"), z.toColor("#729fcf"), z.toColor("#ad7fa8"), z.toColor("#34e2e2"), z.toColor("#eeeeec")], t = [0, 95, 135, 175, 215, 255];
        for (let e = 0; e < 216; e++) {
          let i = t[e / 36 % 6 | 0], r = t[e / 6 % 6 | 0], n = t[e % 6];
          s15.push({ css: j.toCss(i, r, n), rgba: j.toRgba(i, r, n) });
        }
        for (let e = 0; e < 24; e++) {
          let i = 8 + e * 10;
          s15.push({ css: j.toCss(i, i, i), rgba: j.toRgba(i, i, i) });
        }
        return s15;
      })());
      St = z.toColor("#ffffff");
      Ki = z.toColor("#000000");
      tl = z.toColor("#ffffff");
      il = Ki;
      Ui = { css: "rgba(255, 255, 255, 0.3)", rgba: 4294967117 };
      Qa = St;
      ti = class extends D {
        constructor(e) {
          super();
          this._optionsService = e;
          this._contrastCache = new Wi();
          this._halfContrastCache = new Wi();
          this._onChangeColors = this._register(new v());
          this.onChangeColors = this._onChangeColors.event;
          this._colors = { foreground: St, background: Ki, cursor: tl, cursorAccent: il, selectionForeground: void 0, selectionBackgroundTransparent: Ui, selectionBackgroundOpaque: U.blend(Ki, Ui), selectionInactiveBackgroundTransparent: Ui, selectionInactiveBackgroundOpaque: U.blend(Ki, Ui), scrollbarSliderBackground: U.opacity(St, 0.2), scrollbarSliderHoverBackground: U.opacity(St, 0.4), scrollbarSliderActiveBackground: U.opacity(St, 0.5), overviewRulerBorder: St, ansi: re.slice(), contrastCache: this._contrastCache, halfContrastCache: this._halfContrastCache }, this._updateRestoreColors(), this._setTheme(this._optionsService.rawOptions.theme), this._register(this._optionsService.onSpecificOptionChange("minimumContrastRatio", () => this._contrastCache.clear())), this._register(this._optionsService.onSpecificOptionChange("theme", () => this._setTheme(this._optionsService.rawOptions.theme)));
        }
        get colors() {
          return this._colors;
        }
        _setTheme(e = {}) {
          let i = this._colors;
          if (i.foreground = K(e.foreground, St), i.background = K(e.background, Ki), i.cursor = U.blend(i.background, K(e.cursor, tl)), i.cursorAccent = U.blend(i.background, K(e.cursorAccent, il)), i.selectionBackgroundTransparent = K(e.selectionBackground, Ui), i.selectionBackgroundOpaque = U.blend(i.background, i.selectionBackgroundTransparent), i.selectionInactiveBackgroundTransparent = K(e.selectionInactiveBackground, i.selectionBackgroundTransparent), i.selectionInactiveBackgroundOpaque = U.blend(i.background, i.selectionInactiveBackgroundTransparent), i.selectionForeground = e.selectionForeground ? K(e.selectionForeground, ps) : void 0, i.selectionForeground === ps && (i.selectionForeground = void 0), U.isOpaque(i.selectionBackgroundTransparent) && (i.selectionBackgroundTransparent = U.opacity(i.selectionBackgroundTransparent, 0.3)), U.isOpaque(i.selectionInactiveBackgroundTransparent) && (i.selectionInactiveBackgroundTransparent = U.opacity(i.selectionInactiveBackgroundTransparent, 0.3)), i.scrollbarSliderBackground = K(e.scrollbarSliderBackground, U.opacity(i.foreground, 0.2)), i.scrollbarSliderHoverBackground = K(e.scrollbarSliderHoverBackground, U.opacity(i.foreground, 0.4)), i.scrollbarSliderActiveBackground = K(e.scrollbarSliderActiveBackground, U.opacity(i.foreground, 0.5)), i.overviewRulerBorder = K(e.overviewRulerBorder, Qa), i.ansi = re.slice(), i.ansi[0] = K(e.black, re[0]), i.ansi[1] = K(e.red, re[1]), i.ansi[2] = K(e.green, re[2]), i.ansi[3] = K(e.yellow, re[3]), i.ansi[4] = K(e.blue, re[4]), i.ansi[5] = K(e.magenta, re[5]), i.ansi[6] = K(e.cyan, re[6]), i.ansi[7] = K(e.white, re[7]), i.ansi[8] = K(e.brightBlack, re[8]), i.ansi[9] = K(e.brightRed, re[9]), i.ansi[10] = K(e.brightGreen, re[10]), i.ansi[11] = K(e.brightYellow, re[11]), i.ansi[12] = K(e.brightBlue, re[12]), i.ansi[13] = K(e.brightMagenta, re[13]), i.ansi[14] = K(e.brightCyan, re[14]), i.ansi[15] = K(e.brightWhite, re[15]), e.extendedAnsi) {
            let r = Math.min(i.ansi.length - 16, e.extendedAnsi.length);
            for (let n = 0; n < r; n++) i.ansi[n + 16] = K(e.extendedAnsi[n], re[n + 16]);
          }
          this._contrastCache.clear(), this._halfContrastCache.clear(), this._updateRestoreColors(), this._onChangeColors.fire(this.colors);
        }
        restoreColor(e) {
          this._restoreColor(e), this._onChangeColors.fire(this.colors);
        }
        _restoreColor(e) {
          if (e === void 0) {
            for (let i = 0; i < this._restoreColors.ansi.length; ++i) this._colors.ansi[i] = this._restoreColors.ansi[i];
            return;
          }
          switch (e) {
            case 256:
              this._colors.foreground = this._restoreColors.foreground;
              break;
            case 257:
              this._colors.background = this._restoreColors.background;
              break;
            case 258:
              this._colors.cursor = this._restoreColors.cursor;
              break;
            default:
              this._colors.ansi[e] = this._restoreColors.ansi[e];
          }
        }
        modifyColors(e) {
          e(this._colors), this._onChangeColors.fire(this.colors);
        }
        _updateRestoreColors() {
          this._restoreColors = { foreground: this._colors.foreground, background: this._colors.background, cursor: this._colors.cursor, ansi: this._colors.ansi.slice() };
        }
      };
      ti = M([S(0, H)], ti);
      Rs = class {
        constructor(...t) {
          this._entries = /* @__PURE__ */ new Map();
          for (let [e, i] of t) this.set(e, i);
        }
        set(t, e) {
          let i = this._entries.get(t);
          return this._entries.set(t, e), i;
        }
        forEach(t) {
          for (let [e, i] of this._entries.entries()) t(e, i);
        }
        has(t) {
          return this._entries.has(t);
        }
        get(t) {
          return this._entries.get(t);
        }
      };
      ln = class {
        constructor() {
          this._services = new Rs();
          this._services.set(xt, this);
        }
        setService(t, e) {
          this._services.set(t, e);
        }
        getService(t) {
          return this._services.get(t);
        }
        createInstance(t, ...e) {
          let i = Xs(t).sort((o2, l2) => o2.index - l2.index), r = [];
          for (let o2 of i) {
            let l2 = this._services.get(o2.id);
            if (!l2) throw new Error(`[createInstance] ${t.name} depends on UNKNOWN service ${o2.id._id}.`);
            r.push(l2);
          }
          let n = i.length > 0 ? i[0].index : e.length;
          if (e.length !== n) throw new Error(`[createInstance] First service dependency of ${t.name} at position ${n + 1} conflicts with ${e.length} static arguments`);
          return new t(...e, ...r);
        }
      };
      ec = { trace: 0, debug: 1, info: 2, warn: 3, error: 4, off: 5 };
      tc = "xterm.js: ";
      ii = class extends D {
        constructor(e) {
          super();
          this._optionsService = e;
          this._logLevel = 5;
          this._updateLogLevel(), this._register(this._optionsService.onSpecificOptionChange("logLevel", () => this._updateLogLevel())), ic = this;
        }
        get logLevel() {
          return this._logLevel;
        }
        _updateLogLevel() {
          this._logLevel = ec[this._optionsService.rawOptions.logLevel];
        }
        _evalLazyOptionalParams(e) {
          for (let i = 0; i < e.length; i++) typeof e[i] == "function" && (e[i] = e[i]());
        }
        _log(e, i, r) {
          this._evalLazyOptionalParams(r), e.call(console, (this._optionsService.options.logger ? "" : tc) + i, ...r);
        }
        trace(e, ...i) {
          this._logLevel <= 0 && this._log(this._optionsService.options.logger?.trace.bind(this._optionsService.options.logger) ?? console.log, e, i);
        }
        debug(e, ...i) {
          this._logLevel <= 1 && this._log(this._optionsService.options.logger?.debug.bind(this._optionsService.options.logger) ?? console.log, e, i);
        }
        info(e, ...i) {
          this._logLevel <= 2 && this._log(this._optionsService.options.logger?.info.bind(this._optionsService.options.logger) ?? console.info, e, i);
        }
        warn(e, ...i) {
          this._logLevel <= 3 && this._log(this._optionsService.options.logger?.warn.bind(this._optionsService.options.logger) ?? console.warn, e, i);
        }
        error(e, ...i) {
          this._logLevel <= 4 && this._log(this._optionsService.options.logger?.error.bind(this._optionsService.options.logger) ?? console.error, e, i);
        }
      };
      ii = M([S(0, H)], ii);
      zi = class extends D {
        constructor(e) {
          super();
          this._maxLength = e;
          this.onDeleteEmitter = this._register(new v());
          this.onDelete = this.onDeleteEmitter.event;
          this.onInsertEmitter = this._register(new v());
          this.onInsert = this.onInsertEmitter.event;
          this.onTrimEmitter = this._register(new v());
          this.onTrim = this.onTrimEmitter.event;
          this._array = new Array(this._maxLength), this._startIndex = 0, this._length = 0;
        }
        get maxLength() {
          return this._maxLength;
        }
        set maxLength(e) {
          if (this._maxLength === e) return;
          let i = new Array(e);
          for (let r = 0; r < Math.min(e, this.length); r++) i[r] = this._array[this._getCyclicIndex(r)];
          this._array = i, this._maxLength = e, this._startIndex = 0;
        }
        get length() {
          return this._length;
        }
        set length(e) {
          if (e > this._length) for (let i = this._length; i < e; i++) this._array[i] = void 0;
          this._length = e;
        }
        get(e) {
          return this._array[this._getCyclicIndex(e)];
        }
        set(e, i) {
          this._array[this._getCyclicIndex(e)] = i;
        }
        push(e) {
          this._array[this._getCyclicIndex(this._length)] = e, this._length === this._maxLength ? (this._startIndex = ++this._startIndex % this._maxLength, this.onTrimEmitter.fire(1)) : this._length++;
        }
        recycle() {
          if (this._length !== this._maxLength) throw new Error("Can only recycle when the buffer is full");
          return this._startIndex = ++this._startIndex % this._maxLength, this.onTrimEmitter.fire(1), this._array[this._getCyclicIndex(this._length - 1)];
        }
        get isFull() {
          return this._length === this._maxLength;
        }
        pop() {
          return this._array[this._getCyclicIndex(this._length-- - 1)];
        }
        splice(e, i, ...r) {
          if (i) {
            for (let n = e; n < this._length - i; n++) this._array[this._getCyclicIndex(n)] = this._array[this._getCyclicIndex(n + i)];
            this._length -= i, this.onDeleteEmitter.fire({ index: e, amount: i });
          }
          for (let n = this._length - 1; n >= e; n--) this._array[this._getCyclicIndex(n + r.length)] = this._array[this._getCyclicIndex(n)];
          for (let n = 0; n < r.length; n++) this._array[this._getCyclicIndex(e + n)] = r[n];
          if (r.length && this.onInsertEmitter.fire({ index: e, amount: r.length }), this._length + r.length > this._maxLength) {
            let n = this._length + r.length - this._maxLength;
            this._startIndex += n, this._length = this._maxLength, this.onTrimEmitter.fire(n);
          } else this._length += r.length;
        }
        trimStart(e) {
          e > this._length && (e = this._length), this._startIndex += e, this._length -= e, this.onTrimEmitter.fire(e);
        }
        shiftElements(e, i, r) {
          if (!(i <= 0)) {
            if (e < 0 || e >= this._length) throw new Error("start argument out of range");
            if (e + r < 0) throw new Error("Cannot shift elements in list beyond index 0");
            if (r > 0) {
              for (let o2 = i - 1; o2 >= 0; o2--) this.set(e + o2 + r, this.get(e + o2));
              let n = e + i + r - this._length;
              if (n > 0) for (this._length += n; this._length > this._maxLength; ) this._length--, this._startIndex++, this.onTrimEmitter.fire(1);
            } else for (let n = 0; n < i; n++) this.set(e + n + r, this.get(e + n));
          }
        }
        _getCyclicIndex(e) {
          return (this._startIndex + e) % this._maxLength;
        }
      };
      B = 3;
      X = Object.freeze(new De());
      an = 0;
      Ls = 2;
      Ze = class s12 {
        constructor(t, e, i = false) {
          this.isWrapped = i;
          this._combined = {};
          this._extendedAttrs = {};
          this._data = new Uint32Array(t * B);
          let r = e || q.fromCharData([0, ir, 1, 0]);
          for (let n = 0; n < t; ++n) this.setCell(n, r);
          this.length = t;
        }
        get(t) {
          let e = this._data[t * B + 0], i = e & 2097151;
          return [this._data[t * B + 1], e & 2097152 ? this._combined[t] : i ? Ce(i) : "", e >> 22, e & 2097152 ? this._combined[t].charCodeAt(this._combined[t].length - 1) : i];
        }
        set(t, e) {
          this._data[t * B + 1] = e[0], e[1].length > 1 ? (this._combined[t] = e[1], this._data[t * B + 0] = t | 2097152 | e[2] << 22) : this._data[t * B + 0] = e[1].charCodeAt(0) | e[2] << 22;
        }
        getWidth(t) {
          return this._data[t * B + 0] >> 22;
        }
        hasWidth(t) {
          return this._data[t * B + 0] & 12582912;
        }
        getFg(t) {
          return this._data[t * B + 1];
        }
        getBg(t) {
          return this._data[t * B + 2];
        }
        hasContent(t) {
          return this._data[t * B + 0] & 4194303;
        }
        getCodePoint(t) {
          let e = this._data[t * B + 0];
          return e & 2097152 ? this._combined[t].charCodeAt(this._combined[t].length - 1) : e & 2097151;
        }
        isCombined(t) {
          return this._data[t * B + 0] & 2097152;
        }
        getString(t) {
          let e = this._data[t * B + 0];
          return e & 2097152 ? this._combined[t] : e & 2097151 ? Ce(e & 2097151) : "";
        }
        isProtected(t) {
          return this._data[t * B + 2] & 536870912;
        }
        loadCell(t, e) {
          return an = t * B, e.content = this._data[an + 0], e.fg = this._data[an + 1], e.bg = this._data[an + 2], e.content & 2097152 && (e.combinedData = this._combined[t]), e.bg & 268435456 && (e.extended = this._extendedAttrs[t]), e;
        }
        setCell(t, e) {
          e.content & 2097152 && (this._combined[t] = e.combinedData), e.bg & 268435456 && (this._extendedAttrs[t] = e.extended), this._data[t * B + 0] = e.content, this._data[t * B + 1] = e.fg, this._data[t * B + 2] = e.bg;
        }
        setCellFromCodepoint(t, e, i, r) {
          r.bg & 268435456 && (this._extendedAttrs[t] = r.extended), this._data[t * B + 0] = e | i << 22, this._data[t * B + 1] = r.fg, this._data[t * B + 2] = r.bg;
        }
        addCodepointToCell(t, e, i) {
          let r = this._data[t * B + 0];
          r & 2097152 ? this._combined[t] += Ce(e) : r & 2097151 ? (this._combined[t] = Ce(r & 2097151) + Ce(e), r &= -2097152, r |= 2097152) : r = e | 1 << 22, i && (r &= -12582913, r |= i << 22), this._data[t * B + 0] = r;
        }
        insertCells(t, e, i) {
          if (t %= this.length, t && this.getWidth(t - 1) === 2 && this.setCellFromCodepoint(t - 1, 0, 1, i), e < this.length - t) {
            let r = new q();
            for (let n = this.length - t - e - 1; n >= 0; --n) this.setCell(t + e + n, this.loadCell(t + n, r));
            for (let n = 0; n < e; ++n) this.setCell(t + n, i);
          } else for (let r = t; r < this.length; ++r) this.setCell(r, i);
          this.getWidth(this.length - 1) === 2 && this.setCellFromCodepoint(this.length - 1, 0, 1, i);
        }
        deleteCells(t, e, i) {
          if (t %= this.length, e < this.length - t) {
            let r = new q();
            for (let n = 0; n < this.length - t - e; ++n) this.setCell(t + n, this.loadCell(t + e + n, r));
            for (let n = this.length - e; n < this.length; ++n) this.setCell(n, i);
          } else for (let r = t; r < this.length; ++r) this.setCell(r, i);
          t && this.getWidth(t - 1) === 2 && this.setCellFromCodepoint(t - 1, 0, 1, i), this.getWidth(t) === 0 && !this.hasContent(t) && this.setCellFromCodepoint(t, 0, 1, i);
        }
        replaceCells(t, e, i, r = false) {
          if (r) {
            for (t && this.getWidth(t - 1) === 2 && !this.isProtected(t - 1) && this.setCellFromCodepoint(t - 1, 0, 1, i), e < this.length && this.getWidth(e - 1) === 2 && !this.isProtected(e) && this.setCellFromCodepoint(e, 0, 1, i); t < e && t < this.length; ) this.isProtected(t) || this.setCell(t, i), t++;
            return;
          }
          for (t && this.getWidth(t - 1) === 2 && this.setCellFromCodepoint(t - 1, 0, 1, i), e < this.length && this.getWidth(e - 1) === 2 && this.setCellFromCodepoint(e, 0, 1, i); t < e && t < this.length; ) this.setCell(t++, i);
        }
        resize(t, e) {
          if (t === this.length) return this._data.length * 4 * Ls < this._data.buffer.byteLength;
          let i = t * B;
          if (t > this.length) {
            if (this._data.buffer.byteLength >= i * 4) this._data = new Uint32Array(this._data.buffer, 0, i);
            else {
              let r = new Uint32Array(i);
              r.set(this._data), this._data = r;
            }
            for (let r = this.length; r < t; ++r) this.setCell(r, e);
          } else {
            this._data = this._data.subarray(0, i);
            let r = Object.keys(this._combined);
            for (let o2 = 0; o2 < r.length; o2++) {
              let l2 = parseInt(r[o2], 10);
              l2 >= t && delete this._combined[l2];
            }
            let n = Object.keys(this._extendedAttrs);
            for (let o2 = 0; o2 < n.length; o2++) {
              let l2 = parseInt(n[o2], 10);
              l2 >= t && delete this._extendedAttrs[l2];
            }
          }
          return this.length = t, i * 4 * Ls < this._data.buffer.byteLength;
        }
        cleanupMemory() {
          if (this._data.length * 4 * Ls < this._data.buffer.byteLength) {
            let t = new Uint32Array(this._data.length);
            return t.set(this._data), this._data = t, 1;
          }
          return 0;
        }
        fill(t, e = false) {
          if (e) {
            for (let i = 0; i < this.length; ++i) this.isProtected(i) || this.setCell(i, t);
            return;
          }
          this._combined = {}, this._extendedAttrs = {};
          for (let i = 0; i < this.length; ++i) this.setCell(i, t);
        }
        copyFrom(t) {
          this.length !== t.length ? this._data = new Uint32Array(t._data) : this._data.set(t._data), this.length = t.length, this._combined = {};
          for (let e in t._combined) this._combined[e] = t._combined[e];
          this._extendedAttrs = {};
          for (let e in t._extendedAttrs) this._extendedAttrs[e] = t._extendedAttrs[e];
          this.isWrapped = t.isWrapped;
        }
        clone() {
          let t = new s12(0);
          t._data = new Uint32Array(this._data), t.length = this.length;
          for (let e in this._combined) t._combined[e] = this._combined[e];
          for (let e in this._extendedAttrs) t._extendedAttrs[e] = this._extendedAttrs[e];
          return t.isWrapped = this.isWrapped, t;
        }
        getTrimmedLength() {
          for (let t = this.length - 1; t >= 0; --t) if (this._data[t * B + 0] & 4194303) return t + (this._data[t * B + 0] >> 22);
          return 0;
        }
        getNoBgTrimmedLength() {
          for (let t = this.length - 1; t >= 0; --t) if (this._data[t * B + 0] & 4194303 || this._data[t * B + 2] & 50331648) return t + (this._data[t * B + 0] >> 22);
          return 0;
        }
        copyCellsFrom(t, e, i, r, n) {
          let o2 = t._data;
          if (n) for (let a = r - 1; a >= 0; a--) {
            for (let u = 0; u < B; u++) this._data[(i + a) * B + u] = o2[(e + a) * B + u];
            o2[(e + a) * B + 2] & 268435456 && (this._extendedAttrs[i + a] = t._extendedAttrs[e + a]);
          }
          else for (let a = 0; a < r; a++) {
            for (let u = 0; u < B; u++) this._data[(i + a) * B + u] = o2[(e + a) * B + u];
            o2[(e + a) * B + 2] & 268435456 && (this._extendedAttrs[i + a] = t._extendedAttrs[e + a]);
          }
          let l2 = Object.keys(t._combined);
          for (let a = 0; a < l2.length; a++) {
            let u = parseInt(l2[a], 10);
            u >= e && (this._combined[u - e + i] = t._combined[u]);
          }
        }
        translateToString(t, e, i, r) {
          e = e ?? 0, i = i ?? this.length, t && (i = Math.min(i, this.getTrimmedLength())), r && (r.length = 0);
          let n = "";
          for (; e < i; ) {
            let o2 = this._data[e * B + 0], l2 = o2 & 2097151, a = o2 & 2097152 ? this._combined[e] : l2 ? Ce(l2) : we;
            if (n += a, r) for (let u = 0; u < a.length; ++u) r.push(e);
            e += o2 >> 22 || 1;
          }
          return r && r.push(e), n;
        }
      };
      un = class un2 {
        constructor(t) {
          this.line = t;
          this.isDisposed = false;
          this._disposables = [];
          this._id = un2._nextId++;
          this._onDispose = this.register(new v());
          this.onDispose = this._onDispose.event;
        }
        get id() {
          return this._id;
        }
        dispose() {
          this.isDisposed || (this.isDisposed = true, this.line = -1, this._onDispose.fire(), Ne(this._disposables), this._disposables.length = 0);
        }
        register(t) {
          return this._disposables.push(t), t;
        }
      };
      un._nextId = 1;
      cn = un;
      ne = {};
      Je = ne.B;
      ne[0] = { "`": "\u25C6", a: "\u2592", b: "\u2409", c: "\u240C", d: "\u240D", e: "\u240A", f: "\xB0", g: "\xB1", h: "\u2424", i: "\u240B", j: "\u2518", k: "\u2510", l: "\u250C", m: "\u2514", n: "\u253C", o: "\u23BA", p: "\u23BB", q: "\u2500", r: "\u23BC", s: "\u23BD", t: "\u251C", u: "\u2524", v: "\u2534", w: "\u252C", x: "\u2502", y: "\u2264", z: "\u2265", "{": "\u03C0", "|": "\u2260", "}": "\xA3", "~": "\xB7" };
      ne.A = { "#": "\xA3" };
      ne.B = void 0;
      ne[4] = { "#": "\xA3", "@": "\xBE", "[": "ij", "\\": "\xBD", "]": "|", "{": "\xA8", "|": "f", "}": "\xBC", "~": "\xB4" };
      ne.C = ne[5] = { "[": "\xC4", "\\": "\xD6", "]": "\xC5", "^": "\xDC", "`": "\xE9", "{": "\xE4", "|": "\xF6", "}": "\xE5", "~": "\xFC" };
      ne.R = { "#": "\xA3", "@": "\xE0", "[": "\xB0", "\\": "\xE7", "]": "\xA7", "{": "\xE9", "|": "\xF9", "}": "\xE8", "~": "\xA8" };
      ne.Q = { "@": "\xE0", "[": "\xE2", "\\": "\xE7", "]": "\xEA", "^": "\xEE", "`": "\xF4", "{": "\xE9", "|": "\xF9", "}": "\xE8", "~": "\xFB" };
      ne.K = { "@": "\xA7", "[": "\xC4", "\\": "\xD6", "]": "\xDC", "{": "\xE4", "|": "\xF6", "}": "\xFC", "~": "\xDF" };
      ne.Y = { "#": "\xA3", "@": "\xA7", "[": "\xB0", "\\": "\xE7", "]": "\xE9", "`": "\xF9", "{": "\xE0", "|": "\xF2", "}": "\xE8", "~": "\xEC" };
      ne.E = ne[6] = { "@": "\xC4", "[": "\xC6", "\\": "\xD8", "]": "\xC5", "^": "\xDC", "`": "\xE4", "{": "\xE6", "|": "\xF8", "}": "\xE5", "~": "\xFC" };
      ne.Z = { "#": "\xA3", "@": "\xA7", "[": "\xA1", "\\": "\xD1", "]": "\xBF", "{": "\xB0", "|": "\xF1", "}": "\xE7" };
      ne.H = ne[7] = { "@": "\xC9", "[": "\xC4", "\\": "\xD6", "]": "\xC5", "^": "\xDC", "`": "\xE9", "{": "\xE4", "|": "\xF6", "}": "\xE5", "~": "\xFC" };
      ne["="] = { "#": "\xF9", "@": "\xE0", "[": "\xE9", "\\": "\xE7", "]": "\xEA", "^": "\xEE", _: "\xE8", "`": "\xF4", "{": "\xE4", "|": "\xF6", "}": "\xFC", "~": "\xFB" };
      cl = 4294967295;
      $i = class {
        constructor(t, e, i) {
          this._hasScrollback = t;
          this._optionsService = e;
          this._bufferService = i;
          this.ydisp = 0;
          this.ybase = 0;
          this.y = 0;
          this.x = 0;
          this.tabs = {};
          this.savedY = 0;
          this.savedX = 0;
          this.savedCurAttrData = X.clone();
          this.savedCharset = Je;
          this.markers = [];
          this._nullCell = q.fromCharData([0, ir, 1, 0]);
          this._whitespaceCell = q.fromCharData([0, we, 1, 32]);
          this._isClearing = false;
          this._memoryCleanupQueue = new Jt();
          this._memoryCleanupPosition = 0;
          this._cols = this._bufferService.cols, this._rows = this._bufferService.rows, this.lines = new zi(this._getCorrectBufferLength(this._rows)), this.scrollTop = 0, this.scrollBottom = this._rows - 1, this.setupTabStops();
        }
        getNullCell(t) {
          return t ? (this._nullCell.fg = t.fg, this._nullCell.bg = t.bg, this._nullCell.extended = t.extended) : (this._nullCell.fg = 0, this._nullCell.bg = 0, this._nullCell.extended = new rt()), this._nullCell;
        }
        getWhitespaceCell(t) {
          return t ? (this._whitespaceCell.fg = t.fg, this._whitespaceCell.bg = t.bg, this._whitespaceCell.extended = t.extended) : (this._whitespaceCell.fg = 0, this._whitespaceCell.bg = 0, this._whitespaceCell.extended = new rt()), this._whitespaceCell;
        }
        getBlankLine(t, e) {
          return new Ze(this._bufferService.cols, this.getNullCell(t), e);
        }
        get hasScrollback() {
          return this._hasScrollback && this.lines.maxLength > this._rows;
        }
        get isCursorInViewport() {
          let e = this.ybase + this.y - this.ydisp;
          return e >= 0 && e < this._rows;
        }
        _getCorrectBufferLength(t) {
          if (!this._hasScrollback) return t;
          let e = t + this._optionsService.rawOptions.scrollback;
          return e > cl ? cl : e;
        }
        fillViewportRows(t) {
          if (this.lines.length === 0) {
            t === void 0 && (t = X);
            let e = this._rows;
            for (; e--; ) this.lines.push(this.getBlankLine(t));
          }
        }
        clear() {
          this.ydisp = 0, this.ybase = 0, this.y = 0, this.x = 0, this.lines = new zi(this._getCorrectBufferLength(this._rows)), this.scrollTop = 0, this.scrollBottom = this._rows - 1, this.setupTabStops();
        }
        resize(t, e) {
          let i = this.getNullCell(X), r = 0, n = this._getCorrectBufferLength(e);
          if (n > this.lines.maxLength && (this.lines.maxLength = n), this.lines.length > 0) {
            if (this._cols < t) for (let l2 = 0; l2 < this.lines.length; l2++) r += +this.lines.get(l2).resize(t, i);
            let o2 = 0;
            if (this._rows < e) for (let l2 = this._rows; l2 < e; l2++) this.lines.length < e + this.ybase && (this._optionsService.rawOptions.windowsMode || this._optionsService.rawOptions.windowsPty.backend !== void 0 || this._optionsService.rawOptions.windowsPty.buildNumber !== void 0 ? this.lines.push(new Ze(t, i)) : this.ybase > 0 && this.lines.length <= this.ybase + this.y + o2 + 1 ? (this.ybase--, o2++, this.ydisp > 0 && this.ydisp--) : this.lines.push(new Ze(t, i)));
            else for (let l2 = this._rows; l2 > e; l2--) this.lines.length > e + this.ybase && (this.lines.length > this.ybase + this.y + 1 ? this.lines.pop() : (this.ybase++, this.ydisp++));
            if (n < this.lines.maxLength) {
              let l2 = this.lines.length - n;
              l2 > 0 && (this.lines.trimStart(l2), this.ybase = Math.max(this.ybase - l2, 0), this.ydisp = Math.max(this.ydisp - l2, 0), this.savedY = Math.max(this.savedY - l2, 0)), this.lines.maxLength = n;
            }
            this.x = Math.min(this.x, t - 1), this.y = Math.min(this.y, e - 1), o2 && (this.y += o2), this.savedX = Math.min(this.savedX, t - 1), this.scrollTop = 0;
          }
          if (this.scrollBottom = e - 1, this._isReflowEnabled && (this._reflow(t, e), this._cols > t)) for (let o2 = 0; o2 < this.lines.length; o2++) r += +this.lines.get(o2).resize(t, i);
          this._cols = t, this._rows = e, this._memoryCleanupQueue.clear(), r > 0.1 * this.lines.length && (this._memoryCleanupPosition = 0, this._memoryCleanupQueue.enqueue(() => this._batchedMemoryCleanup()));
        }
        _batchedMemoryCleanup() {
          let t = true;
          this._memoryCleanupPosition >= this.lines.length && (this._memoryCleanupPosition = 0, t = false);
          let e = 0;
          for (; this._memoryCleanupPosition < this.lines.length; ) if (e += this.lines.get(this._memoryCleanupPosition++).cleanupMemory(), e > 100) return true;
          return t;
        }
        get _isReflowEnabled() {
          let t = this._optionsService.rawOptions.windowsPty;
          return t && t.buildNumber ? this._hasScrollback && t.backend === "conpty" && t.buildNumber >= 21376 : this._hasScrollback && !this._optionsService.rawOptions.windowsMode;
        }
        _reflow(t, e) {
          this._cols !== t && (t > this._cols ? this._reflowLarger(t, e) : this._reflowSmaller(t, e));
        }
        _reflowLarger(t, e) {
          let i = this._optionsService.rawOptions.reflowCursorLine, r = sl(this.lines, this._cols, t, this.ybase + this.y, this.getNullCell(X), i);
          if (r.length > 0) {
            let n = ol(this.lines, r);
            ll(this.lines, n.layout), this._reflowLargerAdjustViewport(t, e, n.countRemoved);
          }
        }
        _reflowLargerAdjustViewport(t, e, i) {
          let r = this.getNullCell(X), n = i;
          for (; n-- > 0; ) this.ybase === 0 ? (this.y > 0 && this.y--, this.lines.length < e && this.lines.push(new Ze(t, r))) : (this.ydisp === this.ybase && this.ydisp--, this.ybase--);
          this.savedY = Math.max(this.savedY - i, 0);
        }
        _reflowSmaller(t, e) {
          let i = this._optionsService.rawOptions.reflowCursorLine, r = this.getNullCell(X), n = [], o2 = 0;
          for (let l2 = this.lines.length - 1; l2 >= 0; l2--) {
            let a = this.lines.get(l2);
            if (!a || !a.isWrapped && a.getTrimmedLength() <= t) continue;
            let u = [a];
            for (; a.isWrapped && l2 > 0; ) a = this.lines.get(--l2), u.unshift(a);
            if (!i) {
              let I = this.ybase + this.y;
              if (I >= l2 && I < l2 + u.length) continue;
            }
            let h2 = u[u.length - 1].getTrimmedLength(), c = al(u, this._cols, t), d = c.length - u.length, _3;
            this.ybase === 0 && this.y !== this.lines.length - 1 ? _3 = Math.max(0, this.y - this.lines.maxLength + d) : _3 = Math.max(0, this.lines.length - this.lines.maxLength + d);
            let p = [];
            for (let I = 0; I < d; I++) {
              let k2 = this.getBlankLine(X, true);
              p.push(k2);
            }
            p.length > 0 && (n.push({ start: l2 + u.length + o2, newLines: p }), o2 += p.length), u.push(...p);
            let m = c.length - 1, f = c[m];
            f === 0 && (m--, f = c[m]);
            let A = u.length - d - 1, R = h2;
            for (; A >= 0; ) {
              let I = Math.min(R, f);
              if (u[m] === void 0) break;
              if (u[m].copyCellsFrom(u[A], R - I, f - I, I, true), f -= I, f === 0 && (m--, f = c[m]), R -= I, R === 0) {
                A--;
                let k2 = Math.max(A, 0);
                R = ri(u, k2, this._cols);
              }
            }
            for (let I = 0; I < u.length; I++) c[I] < t && u[I].setCell(c[I], r);
            let O = d - _3;
            for (; O-- > 0; ) this.ybase === 0 ? this.y < e - 1 ? (this.y++, this.lines.pop()) : (this.ybase++, this.ydisp++) : this.ybase < Math.min(this.lines.maxLength, this.lines.length + o2) - e && (this.ybase === this.ydisp && this.ydisp++, this.ybase++);
            this.savedY = Math.min(this.savedY + d, this.ybase + e - 1);
          }
          if (n.length > 0) {
            let l2 = [], a = [];
            for (let f = 0; f < this.lines.length; f++) a.push(this.lines.get(f));
            let u = this.lines.length, h2 = u - 1, c = 0, d = n[c];
            this.lines.length = Math.min(this.lines.maxLength, this.lines.length + o2);
            let _3 = 0;
            for (let f = Math.min(this.lines.maxLength - 1, u + o2 - 1); f >= 0; f--) if (d && d.start > h2 + _3) {
              for (let A = d.newLines.length - 1; A >= 0; A--) this.lines.set(f--, d.newLines[A]);
              f++, l2.push({ index: h2 + 1, amount: d.newLines.length }), _3 += d.newLines.length, d = n[++c];
            } else this.lines.set(f, a[h2--]);
            let p = 0;
            for (let f = l2.length - 1; f >= 0; f--) l2[f].index += p, this.lines.onInsertEmitter.fire(l2[f]), p += l2[f].amount;
            let m = Math.max(0, u + o2 - this.lines.maxLength);
            m > 0 && this.lines.onTrimEmitter.fire(m);
          }
        }
        translateBufferLineToString(t, e, i = 0, r) {
          let n = this.lines.get(t);
          return n ? n.translateToString(e, i, r) : "";
        }
        getWrappedRangeForLine(t) {
          let e = t, i = t;
          for (; e > 0 && this.lines.get(e).isWrapped; ) e--;
          for (; i + 1 < this.lines.length && this.lines.get(i + 1).isWrapped; ) i++;
          return { first: e, last: i };
        }
        setupTabStops(t) {
          for (t != null ? this.tabs[t] || (t = this.prevStop(t)) : (this.tabs = {}, t = 0); t < this._cols; t += this._optionsService.rawOptions.tabStopWidth) this.tabs[t] = true;
        }
        prevStop(t) {
          for (t == null && (t = this.x); !this.tabs[--t] && t > 0; ) ;
          return t >= this._cols ? this._cols - 1 : t < 0 ? 0 : t;
        }
        nextStop(t) {
          for (t == null && (t = this.x); !this.tabs[++t] && t < this._cols; ) ;
          return t >= this._cols ? this._cols - 1 : t < 0 ? 0 : t;
        }
        clearMarkers(t) {
          this._isClearing = true;
          for (let e = 0; e < this.markers.length; e++) this.markers[e].line === t && (this.markers[e].dispose(), this.markers.splice(e--, 1));
          this._isClearing = false;
        }
        clearAllMarkers() {
          this._isClearing = true;
          for (let t = 0; t < this.markers.length; t++) this.markers[t].dispose();
          this.markers.length = 0, this._isClearing = false;
        }
        addMarker(t) {
          let e = new cn(t);
          return this.markers.push(e), e.register(this.lines.onTrim((i) => {
            e.line -= i, e.line < 0 && e.dispose();
          })), e.register(this.lines.onInsert((i) => {
            e.line >= i.index && (e.line += i.amount);
          })), e.register(this.lines.onDelete((i) => {
            e.line >= i.index && e.line < i.index + i.amount && e.dispose(), e.line > i.index && (e.line -= i.amount);
          })), e.register(e.onDispose(() => this._removeMarker(e))), e;
        }
        _removeMarker(t) {
          this._isClearing || this.markers.splice(this.markers.indexOf(t), 1);
        }
      };
      hn = class extends D {
        constructor(e, i) {
          super();
          this._optionsService = e;
          this._bufferService = i;
          this._onBufferActivate = this._register(new v());
          this.onBufferActivate = this._onBufferActivate.event;
          this.reset(), this._register(this._optionsService.onSpecificOptionChange("scrollback", () => this.resize(this._bufferService.cols, this._bufferService.rows))), this._register(this._optionsService.onSpecificOptionChange("tabStopWidth", () => this.setupTabStops()));
        }
        reset() {
          this._normal = new $i(true, this._optionsService, this._bufferService), this._normal.fillViewportRows(), this._alt = new $i(false, this._optionsService, this._bufferService), this._activeBuffer = this._normal, this._onBufferActivate.fire({ activeBuffer: this._normal, inactiveBuffer: this._alt }), this.setupTabStops();
        }
        get alt() {
          return this._alt;
        }
        get active() {
          return this._activeBuffer;
        }
        get normal() {
          return this._normal;
        }
        activateNormalBuffer() {
          this._activeBuffer !== this._normal && (this._normal.x = this._alt.x, this._normal.y = this._alt.y, this._alt.clearAllMarkers(), this._alt.clear(), this._activeBuffer = this._normal, this._onBufferActivate.fire({ activeBuffer: this._normal, inactiveBuffer: this._alt }));
        }
        activateAltBuffer(e) {
          this._activeBuffer !== this._alt && (this._alt.fillViewportRows(e), this._alt.x = this._normal.x, this._alt.y = this._normal.y, this._activeBuffer = this._alt, this._onBufferActivate.fire({ activeBuffer: this._alt, inactiveBuffer: this._normal }));
        }
        resize(e, i) {
          this._normal.resize(e, i), this._alt.resize(e, i), this.setupTabStops(e);
        }
        setupTabStops(e) {
          this._normal.setupTabStops(e), this._alt.setupTabStops(e);
        }
      };
      ks = 2;
      Cs = 1;
      ni = class extends D {
        constructor(e) {
          super();
          this.isUserScrolling = false;
          this._onResize = this._register(new v());
          this.onResize = this._onResize.event;
          this._onScroll = this._register(new v());
          this.onScroll = this._onScroll.event;
          this.cols = Math.max(e.rawOptions.cols || 0, ks), this.rows = Math.max(e.rawOptions.rows || 0, Cs), this.buffers = this._register(new hn(e, this)), this._register(this.buffers.onBufferActivate((i) => {
            this._onScroll.fire(i.activeBuffer.ydisp);
          }));
        }
        get buffer() {
          return this.buffers.active;
        }
        resize(e, i) {
          let r = this.cols !== e, n = this.rows !== i;
          this.cols = e, this.rows = i, this.buffers.resize(e, i), this._onResize.fire({ cols: e, rows: i, colsChanged: r, rowsChanged: n });
        }
        reset() {
          this.buffers.reset(), this.isUserScrolling = false;
        }
        scroll(e, i = false) {
          let r = this.buffer, n;
          n = this._cachedBlankLine, (!n || n.length !== this.cols || n.getFg(0) !== e.fg || n.getBg(0) !== e.bg) && (n = r.getBlankLine(e, i), this._cachedBlankLine = n), n.isWrapped = i;
          let o2 = r.ybase + r.scrollTop, l2 = r.ybase + r.scrollBottom;
          if (r.scrollTop === 0) {
            let a = r.lines.isFull;
            l2 === r.lines.length - 1 ? a ? r.lines.recycle().copyFrom(n) : r.lines.push(n.clone()) : r.lines.splice(l2 + 1, 0, n.clone()), a ? this.isUserScrolling && (r.ydisp = Math.max(r.ydisp - 1, 0)) : (r.ybase++, this.isUserScrolling || r.ydisp++);
          } else {
            let a = l2 - o2 + 1;
            r.lines.shiftElements(o2 + 1, a - 1, -1), r.lines.set(l2, n.clone());
          }
          this.isUserScrolling || (r.ydisp = r.ybase), this._onScroll.fire(r.ydisp);
        }
        scrollLines(e, i) {
          let r = this.buffer;
          if (e < 0) {
            if (r.ydisp === 0) return;
            this.isUserScrolling = true;
          } else e + r.ydisp >= r.ybase && (this.isUserScrolling = false);
          let n = r.ydisp;
          r.ydisp = Math.max(Math.min(r.ydisp + e, r.ybase), 0), n !== r.ydisp && (i || this._onScroll.fire(r.ydisp));
        }
      };
      ni = M([S(0, H)], ni);
      si = { cols: 80, rows: 24, cursorBlink: false, cursorStyle: "block", cursorWidth: 1, cursorInactiveStyle: "outline", customGlyphs: true, drawBoldTextInBrightColors: true, documentOverride: null, fastScrollModifier: "alt", fastScrollSensitivity: 5, fontFamily: "monospace", fontSize: 15, fontWeight: "normal", fontWeightBold: "bold", ignoreBracketedPasteMode: false, lineHeight: 1, letterSpacing: 0, linkHandler: null, logLevel: "info", logger: null, scrollback: 1e3, scrollOnEraseInDisplay: false, scrollOnUserInput: true, scrollSensitivity: 1, screenReaderMode: false, smoothScrollDuration: 0, macOptionIsMeta: false, macOptionClickForcesSelection: false, minimumContrastRatio: 1, disableStdin: false, allowProposedApi: false, allowTransparency: false, tabStopWidth: 8, theme: {}, reflowCursorLine: false, rescaleOverlappingGlyphs: false, rightClickSelectsWord: Zt, windowOptions: {}, windowsMode: false, windowsPty: {}, wordSeparator: " ()[]{}',\"`", altClickMovesCursor: true, convertEol: false, termName: "xterm", cancelEvents: false, overviewRuler: {} };
      nc = ["normal", "bold", "100", "200", "300", "400", "500", "600", "700", "800", "900"];
      dn = class extends D {
        constructor(e) {
          super();
          this._onOptionChange = this._register(new v());
          this.onOptionChange = this._onOptionChange.event;
          let i = { ...si };
          for (let r in e) if (r in i) try {
            let n = e[r];
            i[r] = this._sanitizeAndValidateOption(r, n);
          } catch (n) {
            console.error(n);
          }
          this.rawOptions = i, this.options = { ...i }, this._setupOptions(), this._register(C(() => {
            this.rawOptions.linkHandler = null, this.rawOptions.documentOverride = null;
          }));
        }
        onSpecificOptionChange(e, i) {
          return this.onOptionChange((r) => {
            r === e && i(this.rawOptions[e]);
          });
        }
        onMultipleOptionChange(e, i) {
          return this.onOptionChange((r) => {
            e.indexOf(r) !== -1 && i();
          });
        }
        _setupOptions() {
          let e = (r) => {
            if (!(r in si)) throw new Error(`No option with key "${r}"`);
            return this.rawOptions[r];
          }, i = (r, n) => {
            if (!(r in si)) throw new Error(`No option with key "${r}"`);
            n = this._sanitizeAndValidateOption(r, n), this.rawOptions[r] !== n && (this.rawOptions[r] = n, this._onOptionChange.fire(r));
          };
          for (let r in this.rawOptions) {
            let n = { get: e.bind(this, r), set: i.bind(this, r) };
            Object.defineProperty(this.options, r, n);
          }
        }
        _sanitizeAndValidateOption(e, i) {
          switch (e) {
            case "cursorStyle":
              if (i || (i = si[e]), !sc(i)) throw new Error(`"${i}" is not a valid value for ${e}`);
              break;
            case "wordSeparator":
              i || (i = si[e]);
              break;
            case "fontWeight":
            case "fontWeightBold":
              if (typeof i == "number" && 1 <= i && i <= 1e3) break;
              i = nc.includes(i) ? i : si[e];
              break;
            case "cursorWidth":
              i = Math.floor(i);
            case "lineHeight":
            case "tabStopWidth":
              if (i < 1) throw new Error(`${e} cannot be less than 1, value: ${i}`);
              break;
            case "minimumContrastRatio":
              i = Math.max(1, Math.min(21, Math.round(i * 10) / 10));
              break;
            case "scrollback":
              if (i = Math.min(i, 4294967295), i < 0) throw new Error(`${e} cannot be less than 0, value: ${i}`);
              break;
            case "fastScrollSensitivity":
            case "scrollSensitivity":
              if (i <= 0) throw new Error(`${e} cannot be less than or equal to 0, value: ${i}`);
              break;
            case "rows":
            case "cols":
              if (!i && i !== 0) throw new Error(`${e} must be numeric, value: ${i}`);
              break;
            case "windowsPty":
              i = i ?? {};
              break;
          }
          return i;
        }
      };
      ul = Object.freeze({ insertMode: false });
      hl = Object.freeze({ applicationCursorKeys: false, applicationKeypad: false, bracketedPasteMode: false, cursorBlink: void 0, cursorStyle: void 0, origin: false, reverseWraparound: false, sendFocus: false, synchronizedOutput: false, wraparound: true });
      li = class extends D {
        constructor(e, i, r) {
          super();
          this._bufferService = e;
          this._logService = i;
          this._optionsService = r;
          this.isCursorInitialized = false;
          this.isCursorHidden = false;
          this._onData = this._register(new v());
          this.onData = this._onData.event;
          this._onUserInput = this._register(new v());
          this.onUserInput = this._onUserInput.event;
          this._onBinary = this._register(new v());
          this.onBinary = this._onBinary.event;
          this._onRequestScrollToBottom = this._register(new v());
          this.onRequestScrollToBottom = this._onRequestScrollToBottom.event;
          this.modes = oi(ul), this.decPrivateModes = oi(hl);
        }
        reset() {
          this.modes = oi(ul), this.decPrivateModes = oi(hl);
        }
        triggerDataEvent(e, i = false) {
          if (this._optionsService.rawOptions.disableStdin) return;
          let r = this._bufferService.buffer;
          i && this._optionsService.rawOptions.scrollOnUserInput && r.ybase !== r.ydisp && this._onRequestScrollToBottom.fire(), i && this._onUserInput.fire(), this._logService.debug(`sending data "${e}"`), this._logService.trace("sending data (codes)", () => e.split("").map((n) => n.charCodeAt(0))), this._onData.fire(e);
        }
        triggerBinaryEvent(e) {
          this._optionsService.rawOptions.disableStdin || (this._logService.debug(`sending binary "${e}"`), this._logService.trace("sending binary (codes)", () => e.split("").map((i) => i.charCodeAt(0))), this._onBinary.fire(e));
        }
      };
      li = M([S(0, F), S(1, nr), S(2, H)], li);
      dl = { NONE: { events: 0, restrict: () => false }, X10: { events: 1, restrict: (s15) => s15.button === 4 || s15.action !== 1 ? false : (s15.ctrl = false, s15.alt = false, s15.shift = false, true) }, VT200: { events: 19, restrict: (s15) => s15.action !== 32 }, DRAG: { events: 23, restrict: (s15) => !(s15.action === 32 && s15.button === 3) }, ANY: { events: 31, restrict: (s15) => true } };
      Ps = String.fromCharCode;
      fl = { DEFAULT: (s15) => {
        let t = [Ms(s15, false) + 32, s15.col + 32, s15.row + 32];
        return t[0] > 255 || t[1] > 255 || t[2] > 255 ? "" : `\x1B[M${Ps(t[0])}${Ps(t[1])}${Ps(t[2])}`;
      }, SGR: (s15) => {
        let t = s15.action === 0 && s15.button !== 4 ? "m" : "M";
        return `\x1B[<${Ms(s15, true)};${s15.col};${s15.row}${t}`;
      }, SGR_PIXELS: (s15) => {
        let t = s15.action === 0 && s15.button !== 4 ? "m" : "M";
        return `\x1B[<${Ms(s15, true)};${s15.x};${s15.y}${t}`;
      } };
      ai = class extends D {
        constructor(e, i, r) {
          super();
          this._bufferService = e;
          this._coreService = i;
          this._optionsService = r;
          this._protocols = {};
          this._encodings = {};
          this._activeProtocol = "";
          this._activeEncoding = "";
          this._lastEvent = null;
          this._wheelPartialScroll = 0;
          this._onProtocolChange = this._register(new v());
          this.onProtocolChange = this._onProtocolChange.event;
          for (let n of Object.keys(dl)) this.addProtocol(n, dl[n]);
          for (let n of Object.keys(fl)) this.addEncoding(n, fl[n]);
          this.reset();
        }
        addProtocol(e, i) {
          this._protocols[e] = i;
        }
        addEncoding(e, i) {
          this._encodings[e] = i;
        }
        get activeProtocol() {
          return this._activeProtocol;
        }
        get areMouseEventsActive() {
          return this._protocols[this._activeProtocol].events !== 0;
        }
        set activeProtocol(e) {
          if (!this._protocols[e]) throw new Error(`unknown protocol "${e}"`);
          this._activeProtocol = e, this._onProtocolChange.fire(this._protocols[e].events);
        }
        get activeEncoding() {
          return this._activeEncoding;
        }
        set activeEncoding(e) {
          if (!this._encodings[e]) throw new Error(`unknown encoding "${e}"`);
          this._activeEncoding = e;
        }
        reset() {
          this.activeProtocol = "NONE", this.activeEncoding = "DEFAULT", this._lastEvent = null, this._wheelPartialScroll = 0;
        }
        consumeWheelEvent(e, i, r) {
          if (e.deltaY === 0 || e.shiftKey || i === void 0 || r === void 0) return 0;
          let n = i / r, o2 = this._applyScrollModifier(e.deltaY, e);
          return e.deltaMode === WheelEvent.DOM_DELTA_PIXEL ? (o2 /= n + 0, Math.abs(e.deltaY) < 50 && (o2 *= 0.3), this._wheelPartialScroll += o2, o2 = Math.floor(Math.abs(this._wheelPartialScroll)) * (this._wheelPartialScroll > 0 ? 1 : -1), this._wheelPartialScroll %= 1) : e.deltaMode === WheelEvent.DOM_DELTA_PAGE && (o2 *= this._bufferService.rows), o2;
        }
        _applyScrollModifier(e, i) {
          return i.altKey || i.ctrlKey || i.shiftKey ? e * this._optionsService.rawOptions.fastScrollSensitivity * this._optionsService.rawOptions.scrollSensitivity : e * this._optionsService.rawOptions.scrollSensitivity;
        }
        triggerMouseEvent(e) {
          if (e.col < 0 || e.col >= this._bufferService.cols || e.row < 0 || e.row >= this._bufferService.rows || e.button === 4 && e.action === 32 || e.button === 3 && e.action !== 32 || e.button !== 4 && (e.action === 2 || e.action === 3) || (e.col++, e.row++, e.action === 32 && this._lastEvent && this._equalEvents(this._lastEvent, e, this._activeEncoding === "SGR_PIXELS")) || !this._protocols[this._activeProtocol].restrict(e)) return false;
          let i = this._encodings[this._activeEncoding](e);
          return i && (this._activeEncoding === "DEFAULT" ? this._coreService.triggerBinaryEvent(i) : this._coreService.triggerDataEvent(i, true)), this._lastEvent = e, true;
        }
        explainEvents(e) {
          return { down: !!(e & 1), up: !!(e & 2), drag: !!(e & 4), move: !!(e & 8), wheel: !!(e & 16) };
        }
        _equalEvents(e, i, r) {
          if (r) {
            if (e.x !== i.x || e.y !== i.y) return false;
          } else if (e.col !== i.col || e.row !== i.row) return false;
          return !(e.button !== i.button || e.action !== i.action || e.ctrl !== i.ctrl || e.alt !== i.alt || e.shift !== i.shift);
        }
      };
      ai = M([S(0, F), S(1, ge), S(2, H)], ai);
      Os = [[768, 879], [1155, 1158], [1160, 1161], [1425, 1469], [1471, 1471], [1473, 1474], [1476, 1477], [1479, 1479], [1536, 1539], [1552, 1557], [1611, 1630], [1648, 1648], [1750, 1764], [1767, 1768], [1770, 1773], [1807, 1807], [1809, 1809], [1840, 1866], [1958, 1968], [2027, 2035], [2305, 2306], [2364, 2364], [2369, 2376], [2381, 2381], [2385, 2388], [2402, 2403], [2433, 2433], [2492, 2492], [2497, 2500], [2509, 2509], [2530, 2531], [2561, 2562], [2620, 2620], [2625, 2626], [2631, 2632], [2635, 2637], [2672, 2673], [2689, 2690], [2748, 2748], [2753, 2757], [2759, 2760], [2765, 2765], [2786, 2787], [2817, 2817], [2876, 2876], [2879, 2879], [2881, 2883], [2893, 2893], [2902, 2902], [2946, 2946], [3008, 3008], [3021, 3021], [3134, 3136], [3142, 3144], [3146, 3149], [3157, 3158], [3260, 3260], [3263, 3263], [3270, 3270], [3276, 3277], [3298, 3299], [3393, 3395], [3405, 3405], [3530, 3530], [3538, 3540], [3542, 3542], [3633, 3633], [3636, 3642], [3655, 3662], [3761, 3761], [3764, 3769], [3771, 3772], [3784, 3789], [3864, 3865], [3893, 3893], [3895, 3895], [3897, 3897], [3953, 3966], [3968, 3972], [3974, 3975], [3984, 3991], [3993, 4028], [4038, 4038], [4141, 4144], [4146, 4146], [4150, 4151], [4153, 4153], [4184, 4185], [4448, 4607], [4959, 4959], [5906, 5908], [5938, 5940], [5970, 5971], [6002, 6003], [6068, 6069], [6071, 6077], [6086, 6086], [6089, 6099], [6109, 6109], [6155, 6157], [6313, 6313], [6432, 6434], [6439, 6440], [6450, 6450], [6457, 6459], [6679, 6680], [6912, 6915], [6964, 6964], [6966, 6970], [6972, 6972], [6978, 6978], [7019, 7027], [7616, 7626], [7678, 7679], [8203, 8207], [8234, 8238], [8288, 8291], [8298, 8303], [8400, 8431], [12330, 12335], [12441, 12442], [43014, 43014], [43019, 43019], [43045, 43046], [64286, 64286], [65024, 65039], [65056, 65059], [65279, 65279], [65529, 65531]];
      ac = [[68097, 68099], [68101, 68102], [68108, 68111], [68152, 68154], [68159, 68159], [119143, 119145], [119155, 119170], [119173, 119179], [119210, 119213], [119362, 119364], [917505, 917505], [917536, 917631], [917760, 917999]];
      fn = class {
        constructor() {
          this.version = "6";
          if (!se) {
            se = new Uint8Array(65536), se.fill(1), se[0] = 0, se.fill(0, 1, 32), se.fill(0, 127, 160), se.fill(2, 4352, 4448), se[9001] = 2, se[9002] = 2, se.fill(2, 11904, 42192), se[12351] = 1, se.fill(2, 44032, 55204), se.fill(2, 63744, 64256), se.fill(2, 65040, 65050), se.fill(2, 65072, 65136), se.fill(2, 65280, 65377), se.fill(2, 65504, 65511);
            for (let t = 0; t < Os.length; ++t) se.fill(0, Os[t][0], Os[t][1] + 1);
          }
        }
        wcwidth(t) {
          return t < 32 ? 0 : t < 127 ? 1 : t < 65536 ? se[t] : cc(t, ac) ? 0 : t >= 131072 && t <= 196605 || t >= 196608 && t <= 262141 ? 2 : 1;
        }
        charProperties(t, e) {
          let i = this.wcwidth(t), r = i === 0 && e !== 0;
          if (r) {
            let n = Ae.extractWidth(e);
            n === 0 ? r = false : n > i && (i = n);
          }
          return Ae.createPropertyValue(0, i, r);
        }
      };
      Ae = class s13 {
        constructor() {
          this._providers = /* @__PURE__ */ Object.create(null);
          this._active = "";
          this._onChange = new v();
          this.onChange = this._onChange.event;
          let t = new fn();
          this.register(t), this._active = t.version, this._activeProvider = t;
        }
        static extractShouldJoin(t) {
          return (t & 1) !== 0;
        }
        static extractWidth(t) {
          return t >> 1 & 3;
        }
        static extractCharKind(t) {
          return t >> 3;
        }
        static createPropertyValue(t, e, i = false) {
          return (t & 16777215) << 3 | (e & 3) << 1 | (i ? 1 : 0);
        }
        dispose() {
          this._onChange.dispose();
        }
        get versions() {
          return Object.keys(this._providers);
        }
        get activeVersion() {
          return this._active;
        }
        set activeVersion(t) {
          if (!this._providers[t]) throw new Error(`unknown Unicode version "${t}"`);
          this._active = t, this._activeProvider = this._providers[t], this._onChange.fire(t);
        }
        register(t) {
          this._providers[t.version] = t;
        }
        wcwidth(t) {
          return this._activeProvider.wcwidth(t);
        }
        getStringCellWidth(t) {
          let e = 0, i = 0, r = t.length;
          for (let n = 0; n < r; ++n) {
            let o2 = t.charCodeAt(n);
            if (55296 <= o2 && o2 <= 56319) {
              if (++n >= r) return e + this.wcwidth(o2);
              let u = t.charCodeAt(n);
              56320 <= u && u <= 57343 ? o2 = (o2 - 55296) * 1024 + u - 56320 + 65536 : e += this.wcwidth(u);
            }
            let l2 = this.charProperties(o2, i), a = s13.extractWidth(l2);
            s13.extractShouldJoin(l2) && (a -= s13.extractWidth(i)), e += a, i = l2;
          }
          return e;
        }
        charProperties(t, e) {
          return this._activeProvider.charProperties(t, e);
        }
      };
      pn = class {
        constructor() {
          this.glevel = 0;
          this._charsets = [];
        }
        reset() {
          this.charset = void 0, this._charsets = [], this.glevel = 0;
        }
        setgLevel(t) {
          this.glevel = t, this.charset = this._charsets[t];
        }
        setgCharset(t, e) {
          this._charsets[t] = e, this.glevel === t && (this.charset = e);
        }
      };
      Vi = 2147483647;
      uc = 256;
      ci = class s14 {
        constructor(t = 32, e = 32) {
          this.maxLength = t;
          this.maxSubParamsLength = e;
          if (e > uc) throw new Error("maxSubParamsLength must not be greater than 256");
          this.params = new Int32Array(t), this.length = 0, this._subParams = new Int32Array(e), this._subParamsLength = 0, this._subParamsIdx = new Uint16Array(t), this._rejectDigits = false, this._rejectSubDigits = false, this._digitIsSub = false;
        }
        static fromArray(t) {
          let e = new s14();
          if (!t.length) return e;
          for (let i = Array.isArray(t[0]) ? 1 : 0; i < t.length; ++i) {
            let r = t[i];
            if (Array.isArray(r)) for (let n = 0; n < r.length; ++n) e.addSubParam(r[n]);
            else e.addParam(r);
          }
          return e;
        }
        clone() {
          let t = new s14(this.maxLength, this.maxSubParamsLength);
          return t.params.set(this.params), t.length = this.length, t._subParams.set(this._subParams), t._subParamsLength = this._subParamsLength, t._subParamsIdx.set(this._subParamsIdx), t._rejectDigits = this._rejectDigits, t._rejectSubDigits = this._rejectSubDigits, t._digitIsSub = this._digitIsSub, t;
        }
        toArray() {
          let t = [];
          for (let e = 0; e < this.length; ++e) {
            t.push(this.params[e]);
            let i = this._subParamsIdx[e] >> 8, r = this._subParamsIdx[e] & 255;
            r - i > 0 && t.push(Array.prototype.slice.call(this._subParams, i, r));
          }
          return t;
        }
        reset() {
          this.length = 0, this._subParamsLength = 0, this._rejectDigits = false, this._rejectSubDigits = false, this._digitIsSub = false;
        }
        addParam(t) {
          if (this._digitIsSub = false, this.length >= this.maxLength) {
            this._rejectDigits = true;
            return;
          }
          if (t < -1) throw new Error("values lesser than -1 are not allowed");
          this._subParamsIdx[this.length] = this._subParamsLength << 8 | this._subParamsLength, this.params[this.length++] = t > Vi ? Vi : t;
        }
        addSubParam(t) {
          if (this._digitIsSub = true, !!this.length) {
            if (this._rejectDigits || this._subParamsLength >= this.maxSubParamsLength) {
              this._rejectSubDigits = true;
              return;
            }
            if (t < -1) throw new Error("values lesser than -1 are not allowed");
            this._subParams[this._subParamsLength++] = t > Vi ? Vi : t, this._subParamsIdx[this.length - 1]++;
          }
        }
        hasSubParams(t) {
          return (this._subParamsIdx[t] & 255) - (this._subParamsIdx[t] >> 8) > 0;
        }
        getSubParams(t) {
          let e = this._subParamsIdx[t] >> 8, i = this._subParamsIdx[t] & 255;
          return i - e > 0 ? this._subParams.subarray(e, i) : null;
        }
        getSubParamsAll() {
          let t = {};
          for (let e = 0; e < this.length; ++e) {
            let i = this._subParamsIdx[e] >> 8, r = this._subParamsIdx[e] & 255;
            r - i > 0 && (t[e] = this._subParams.slice(i, r));
          }
          return t;
        }
        addDigit(t) {
          let e;
          if (this._rejectDigits || !(e = this._digitIsSub ? this._subParamsLength : this.length) || this._digitIsSub && this._rejectSubDigits) return;
          let i = this._digitIsSub ? this._subParams : this.params, r = i[e - 1];
          i[e - 1] = ~r ? Math.min(r * 10 + t, Vi) : t;
        }
      };
      qi = [];
      mn = class {
        constructor() {
          this._state = 0;
          this._active = qi;
          this._id = -1;
          this._handlers = /* @__PURE__ */ Object.create(null);
          this._handlerFb = () => {
          };
          this._stack = { paused: false, loopPosition: 0, fallThrough: false };
        }
        registerHandler(t, e) {
          this._handlers[t] === void 0 && (this._handlers[t] = []);
          let i = this._handlers[t];
          return i.push(e), { dispose: () => {
            let r = i.indexOf(e);
            r !== -1 && i.splice(r, 1);
          } };
        }
        clearHandler(t) {
          this._handlers[t] && delete this._handlers[t];
        }
        setHandlerFallback(t) {
          this._handlerFb = t;
        }
        dispose() {
          this._handlers = /* @__PURE__ */ Object.create(null), this._handlerFb = () => {
          }, this._active = qi;
        }
        reset() {
          if (this._state === 2) for (let t = this._stack.paused ? this._stack.loopPosition - 1 : this._active.length - 1; t >= 0; --t) this._active[t].end(false);
          this._stack.paused = false, this._active = qi, this._id = -1, this._state = 0;
        }
        _start() {
          if (this._active = this._handlers[this._id] || qi, !this._active.length) this._handlerFb(this._id, "START");
          else for (let t = this._active.length - 1; t >= 0; t--) this._active[t].start();
        }
        _put(t, e, i) {
          if (!this._active.length) this._handlerFb(this._id, "PUT", It(t, e, i));
          else for (let r = this._active.length - 1; r >= 0; r--) this._active[r].put(t, e, i);
        }
        start() {
          this.reset(), this._state = 1;
        }
        put(t, e, i) {
          if (this._state !== 3) {
            if (this._state === 1) for (; e < i; ) {
              let r = t[e++];
              if (r === 59) {
                this._state = 2, this._start();
                break;
              }
              if (r < 48 || 57 < r) {
                this._state = 3;
                return;
              }
              this._id === -1 && (this._id = 0), this._id = this._id * 10 + r - 48;
            }
            this._state === 2 && i - e > 0 && this._put(t, e, i);
          }
        }
        end(t, e = true) {
          if (this._state !== 0) {
            if (this._state !== 3) if (this._state === 1 && this._start(), !this._active.length) this._handlerFb(this._id, "END", t);
            else {
              let i = false, r = this._active.length - 1, n = false;
              if (this._stack.paused && (r = this._stack.loopPosition - 1, i = e, n = this._stack.fallThrough, this._stack.paused = false), !n && i === false) {
                for (; r >= 0 && (i = this._active[r].end(t), i !== true); r--) if (i instanceof Promise) return this._stack.paused = true, this._stack.loopPosition = r, this._stack.fallThrough = false, i;
                r--;
              }
              for (; r >= 0; r--) if (i = this._active[r].end(false), i instanceof Promise) return this._stack.paused = true, this._stack.loopPosition = r, this._stack.fallThrough = true, i;
            }
            this._active = qi, this._id = -1, this._state = 0;
          }
        }
      };
      pe = class {
        constructor(t) {
          this._handler = t;
          this._data = "";
          this._hitLimit = false;
        }
        start() {
          this._data = "", this._hitLimit = false;
        }
        put(t, e, i) {
          this._hitLimit || (this._data += It(t, e, i), this._data.length > 1e7 && (this._data = "", this._hitLimit = true));
        }
        end(t) {
          let e = false;
          if (this._hitLimit) e = false;
          else if (t && (e = this._handler(this._data), e instanceof Promise)) return e.then((i) => (this._data = "", this._hitLimit = false, i));
          return this._data = "", this._hitLimit = false, e;
        }
      };
      Yi = [];
      _n = class {
        constructor() {
          this._handlers = /* @__PURE__ */ Object.create(null);
          this._active = Yi;
          this._ident = 0;
          this._handlerFb = () => {
          };
          this._stack = { paused: false, loopPosition: 0, fallThrough: false };
        }
        dispose() {
          this._handlers = /* @__PURE__ */ Object.create(null), this._handlerFb = () => {
          }, this._active = Yi;
        }
        registerHandler(t, e) {
          this._handlers[t] === void 0 && (this._handlers[t] = []);
          let i = this._handlers[t];
          return i.push(e), { dispose: () => {
            let r = i.indexOf(e);
            r !== -1 && i.splice(r, 1);
          } };
        }
        clearHandler(t) {
          this._handlers[t] && delete this._handlers[t];
        }
        setHandlerFallback(t) {
          this._handlerFb = t;
        }
        reset() {
          if (this._active.length) for (let t = this._stack.paused ? this._stack.loopPosition - 1 : this._active.length - 1; t >= 0; --t) this._active[t].unhook(false);
          this._stack.paused = false, this._active = Yi, this._ident = 0;
        }
        hook(t, e) {
          if (this.reset(), this._ident = t, this._active = this._handlers[t] || Yi, !this._active.length) this._handlerFb(this._ident, "HOOK", e);
          else for (let i = this._active.length - 1; i >= 0; i--) this._active[i].hook(e);
        }
        put(t, e, i) {
          if (!this._active.length) this._handlerFb(this._ident, "PUT", It(t, e, i));
          else for (let r = this._active.length - 1; r >= 0; r--) this._active[r].put(t, e, i);
        }
        unhook(t, e = true) {
          if (!this._active.length) this._handlerFb(this._ident, "UNHOOK", t);
          else {
            let i = false, r = this._active.length - 1, n = false;
            if (this._stack.paused && (r = this._stack.loopPosition - 1, i = e, n = this._stack.fallThrough, this._stack.paused = false), !n && i === false) {
              for (; r >= 0 && (i = this._active[r].unhook(t), i !== true); r--) if (i instanceof Promise) return this._stack.paused = true, this._stack.loopPosition = r, this._stack.fallThrough = false, i;
              r--;
            }
            for (; r >= 0; r--) if (i = this._active[r].unhook(false), i instanceof Promise) return this._stack.paused = true, this._stack.loopPosition = r, this._stack.fallThrough = true, i;
          }
          this._active = Yi, this._ident = 0;
        }
      };
      ji = new ci();
      ji.addParam(0);
      Xi = class {
        constructor(t) {
          this._handler = t;
          this._data = "";
          this._params = ji;
          this._hitLimit = false;
        }
        hook(t) {
          this._params = t.length > 1 || t.params[0] ? t.clone() : ji, this._data = "", this._hitLimit = false;
        }
        put(t, e, i) {
          this._hitLimit || (this._data += It(t, e, i), this._data.length > 1e7 && (this._data = "", this._hitLimit = true));
        }
        unhook(t) {
          let e = false;
          if (this._hitLimit) e = false;
          else if (t && (e = this._handler(this._data, this._params), e instanceof Promise)) return e.then((i) => (this._params = ji, this._data = "", this._hitLimit = false, i));
          return this._params = ji, this._data = "", this._hitLimit = false, e;
        }
      };
      Fs = class {
        constructor(t) {
          this.table = new Uint8Array(t);
        }
        setDefault(t, e) {
          this.table.fill(t << 4 | e);
        }
        add(t, e, i, r) {
          this.table[e << 8 | t] = i << 4 | r;
        }
        addMany(t, e, i, r) {
          for (let n = 0; n < t.length; n++) this.table[e << 8 | t[n]] = i << 4 | r;
        }
      };
      ke = 160;
      hc = (function() {
        let s15 = new Fs(4095), e = Array.apply(null, Array(256)).map((a, u) => u), i = (a, u) => e.slice(a, u), r = i(32, 127), n = i(0, 24);
        n.push(25), n.push.apply(n, i(28, 32));
        let o2 = i(0, 14), l2;
        s15.setDefault(1, 0), s15.addMany(r, 0, 2, 0);
        for (l2 in o2) s15.addMany([24, 26, 153, 154], l2, 3, 0), s15.addMany(i(128, 144), l2, 3, 0), s15.addMany(i(144, 152), l2, 3, 0), s15.add(156, l2, 0, 0), s15.add(27, l2, 11, 1), s15.add(157, l2, 4, 8), s15.addMany([152, 158, 159], l2, 0, 7), s15.add(155, l2, 11, 3), s15.add(144, l2, 11, 9);
        return s15.addMany(n, 0, 3, 0), s15.addMany(n, 1, 3, 1), s15.add(127, 1, 0, 1), s15.addMany(n, 8, 0, 8), s15.addMany(n, 3, 3, 3), s15.add(127, 3, 0, 3), s15.addMany(n, 4, 3, 4), s15.add(127, 4, 0, 4), s15.addMany(n, 6, 3, 6), s15.addMany(n, 5, 3, 5), s15.add(127, 5, 0, 5), s15.addMany(n, 2, 3, 2), s15.add(127, 2, 0, 2), s15.add(93, 1, 4, 8), s15.addMany(r, 8, 5, 8), s15.add(127, 8, 5, 8), s15.addMany([156, 27, 24, 26, 7], 8, 6, 0), s15.addMany(i(28, 32), 8, 0, 8), s15.addMany([88, 94, 95], 1, 0, 7), s15.addMany(r, 7, 0, 7), s15.addMany(n, 7, 0, 7), s15.add(156, 7, 0, 0), s15.add(127, 7, 0, 7), s15.add(91, 1, 11, 3), s15.addMany(i(64, 127), 3, 7, 0), s15.addMany(i(48, 60), 3, 8, 4), s15.addMany([60, 61, 62, 63], 3, 9, 4), s15.addMany(i(48, 60), 4, 8, 4), s15.addMany(i(64, 127), 4, 7, 0), s15.addMany([60, 61, 62, 63], 4, 0, 6), s15.addMany(i(32, 64), 6, 0, 6), s15.add(127, 6, 0, 6), s15.addMany(i(64, 127), 6, 0, 0), s15.addMany(i(32, 48), 3, 9, 5), s15.addMany(i(32, 48), 5, 9, 5), s15.addMany(i(48, 64), 5, 0, 6), s15.addMany(i(64, 127), 5, 7, 0), s15.addMany(i(32, 48), 4, 9, 5), s15.addMany(i(32, 48), 1, 9, 2), s15.addMany(i(32, 48), 2, 9, 2), s15.addMany(i(48, 127), 2, 10, 0), s15.addMany(i(48, 80), 1, 10, 0), s15.addMany(i(81, 88), 1, 10, 0), s15.addMany([89, 90, 92], 1, 10, 0), s15.addMany(i(96, 127), 1, 10, 0), s15.add(80, 1, 11, 9), s15.addMany(n, 9, 0, 9), s15.add(127, 9, 0, 9), s15.addMany(i(28, 32), 9, 0, 9), s15.addMany(i(32, 48), 9, 9, 12), s15.addMany(i(48, 60), 9, 8, 10), s15.addMany([60, 61, 62, 63], 9, 9, 10), s15.addMany(n, 11, 0, 11), s15.addMany(i(32, 128), 11, 0, 11), s15.addMany(i(28, 32), 11, 0, 11), s15.addMany(n, 10, 0, 10), s15.add(127, 10, 0, 10), s15.addMany(i(28, 32), 10, 0, 10), s15.addMany(i(48, 60), 10, 8, 10), s15.addMany([60, 61, 62, 63], 10, 0, 11), s15.addMany(i(32, 48), 10, 9, 12), s15.addMany(n, 12, 0, 12), s15.add(127, 12, 0, 12), s15.addMany(i(28, 32), 12, 0, 12), s15.addMany(i(32, 48), 12, 9, 12), s15.addMany(i(48, 64), 12, 0, 11), s15.addMany(i(64, 127), 12, 12, 13), s15.addMany(i(64, 127), 10, 12, 13), s15.addMany(i(64, 127), 9, 12, 13), s15.addMany(n, 13, 13, 13), s15.addMany(r, 13, 13, 13), s15.add(127, 13, 0, 13), s15.addMany([27, 156, 24, 26], 13, 14, 0), s15.add(ke, 0, 2, 0), s15.add(ke, 8, 5, 8), s15.add(ke, 6, 0, 6), s15.add(ke, 11, 0, 11), s15.add(ke, 13, 13, 13), s15;
      })();
      bn = class extends D {
        constructor(e = hc) {
          super();
          this._transitions = e;
          this._parseStack = { state: 0, handlers: [], handlerPos: 0, transition: 0, chunkPos: 0 };
          this.initialState = 0, this.currentState = this.initialState, this._params = new ci(), this._params.addParam(0), this._collect = 0, this.precedingJoinState = 0, this._printHandlerFb = (i, r, n) => {
          }, this._executeHandlerFb = (i) => {
          }, this._csiHandlerFb = (i, r) => {
          }, this._escHandlerFb = (i) => {
          }, this._errorHandlerFb = (i) => i, this._printHandler = this._printHandlerFb, this._executeHandlers = /* @__PURE__ */ Object.create(null), this._csiHandlers = /* @__PURE__ */ Object.create(null), this._escHandlers = /* @__PURE__ */ Object.create(null), this._register(C(() => {
            this._csiHandlers = /* @__PURE__ */ Object.create(null), this._executeHandlers = /* @__PURE__ */ Object.create(null), this._escHandlers = /* @__PURE__ */ Object.create(null);
          })), this._oscParser = this._register(new mn()), this._dcsParser = this._register(new _n()), this._errorHandler = this._errorHandlerFb, this.registerEscHandler({ final: "\\" }, () => true);
        }
        _identifier(e, i = [64, 126]) {
          let r = 0;
          if (e.prefix) {
            if (e.prefix.length > 1) throw new Error("only one byte as prefix supported");
            if (r = e.prefix.charCodeAt(0), r && 60 > r || r > 63) throw new Error("prefix must be in range 0x3c .. 0x3f");
          }
          if (e.intermediates) {
            if (e.intermediates.length > 2) throw new Error("only two bytes as intermediates are supported");
            for (let o2 = 0; o2 < e.intermediates.length; ++o2) {
              let l2 = e.intermediates.charCodeAt(o2);
              if (32 > l2 || l2 > 47) throw new Error("intermediate must be in range 0x20 .. 0x2f");
              r <<= 8, r |= l2;
            }
          }
          if (e.final.length !== 1) throw new Error("final must be a single byte");
          let n = e.final.charCodeAt(0);
          if (i[0] > n || n > i[1]) throw new Error(`final must be in range ${i[0]} .. ${i[1]}`);
          return r <<= 8, r |= n, r;
        }
        identToString(e) {
          let i = [];
          for (; e; ) i.push(String.fromCharCode(e & 255)), e >>= 8;
          return i.reverse().join("");
        }
        setPrintHandler(e) {
          this._printHandler = e;
        }
        clearPrintHandler() {
          this._printHandler = this._printHandlerFb;
        }
        registerEscHandler(e, i) {
          let r = this._identifier(e, [48, 126]);
          this._escHandlers[r] === void 0 && (this._escHandlers[r] = []);
          let n = this._escHandlers[r];
          return n.push(i), { dispose: () => {
            let o2 = n.indexOf(i);
            o2 !== -1 && n.splice(o2, 1);
          } };
        }
        clearEscHandler(e) {
          this._escHandlers[this._identifier(e, [48, 126])] && delete this._escHandlers[this._identifier(e, [48, 126])];
        }
        setEscHandlerFallback(e) {
          this._escHandlerFb = e;
        }
        setExecuteHandler(e, i) {
          this._executeHandlers[e.charCodeAt(0)] = i;
        }
        clearExecuteHandler(e) {
          this._executeHandlers[e.charCodeAt(0)] && delete this._executeHandlers[e.charCodeAt(0)];
        }
        setExecuteHandlerFallback(e) {
          this._executeHandlerFb = e;
        }
        registerCsiHandler(e, i) {
          let r = this._identifier(e);
          this._csiHandlers[r] === void 0 && (this._csiHandlers[r] = []);
          let n = this._csiHandlers[r];
          return n.push(i), { dispose: () => {
            let o2 = n.indexOf(i);
            o2 !== -1 && n.splice(o2, 1);
          } };
        }
        clearCsiHandler(e) {
          this._csiHandlers[this._identifier(e)] && delete this._csiHandlers[this._identifier(e)];
        }
        setCsiHandlerFallback(e) {
          this._csiHandlerFb = e;
        }
        registerDcsHandler(e, i) {
          return this._dcsParser.registerHandler(this._identifier(e), i);
        }
        clearDcsHandler(e) {
          this._dcsParser.clearHandler(this._identifier(e));
        }
        setDcsHandlerFallback(e) {
          this._dcsParser.setHandlerFallback(e);
        }
        registerOscHandler(e, i) {
          return this._oscParser.registerHandler(e, i);
        }
        clearOscHandler(e) {
          this._oscParser.clearHandler(e);
        }
        setOscHandlerFallback(e) {
          this._oscParser.setHandlerFallback(e);
        }
        setErrorHandler(e) {
          this._errorHandler = e;
        }
        clearErrorHandler() {
          this._errorHandler = this._errorHandlerFb;
        }
        reset() {
          this.currentState = this.initialState, this._oscParser.reset(), this._dcsParser.reset(), this._params.reset(), this._params.addParam(0), this._collect = 0, this.precedingJoinState = 0, this._parseStack.state !== 0 && (this._parseStack.state = 2, this._parseStack.handlers = []);
        }
        _preserveStack(e, i, r, n, o2) {
          this._parseStack.state = e, this._parseStack.handlers = i, this._parseStack.handlerPos = r, this._parseStack.transition = n, this._parseStack.chunkPos = o2;
        }
        parse(e, i, r) {
          let n = 0, o2 = 0, l2 = 0, a;
          if (this._parseStack.state) if (this._parseStack.state === 2) this._parseStack.state = 0, l2 = this._parseStack.chunkPos + 1;
          else {
            if (r === void 0 || this._parseStack.state === 1) throw this._parseStack.state = 1, new Error("improper continuation due to previous async handler, giving up parsing");
            let u = this._parseStack.handlers, h2 = this._parseStack.handlerPos - 1;
            switch (this._parseStack.state) {
              case 3:
                if (r === false && h2 > -1) {
                  for (; h2 >= 0 && (a = u[h2](this._params), a !== true); h2--) if (a instanceof Promise) return this._parseStack.handlerPos = h2, a;
                }
                this._parseStack.handlers = [];
                break;
              case 4:
                if (r === false && h2 > -1) {
                  for (; h2 >= 0 && (a = u[h2](), a !== true); h2--) if (a instanceof Promise) return this._parseStack.handlerPos = h2, a;
                }
                this._parseStack.handlers = [];
                break;
              case 6:
                if (n = e[this._parseStack.chunkPos], a = this._dcsParser.unhook(n !== 24 && n !== 26, r), a) return a;
                n === 27 && (this._parseStack.transition |= 1), this._params.reset(), this._params.addParam(0), this._collect = 0;
                break;
              case 5:
                if (n = e[this._parseStack.chunkPos], a = this._oscParser.end(n !== 24 && n !== 26, r), a) return a;
                n === 27 && (this._parseStack.transition |= 1), this._params.reset(), this._params.addParam(0), this._collect = 0;
                break;
            }
            this._parseStack.state = 0, l2 = this._parseStack.chunkPos + 1, this.precedingJoinState = 0, this.currentState = this._parseStack.transition & 15;
          }
          for (let u = l2; u < i; ++u) {
            switch (n = e[u], o2 = this._transitions.table[this.currentState << 8 | (n < 160 ? n : ke)], o2 >> 4) {
              case 2:
                for (let m = u + 1; ; ++m) {
                  if (m >= i || (n = e[m]) < 32 || n > 126 && n < ke) {
                    this._printHandler(e, u, m), u = m - 1;
                    break;
                  }
                  if (++m >= i || (n = e[m]) < 32 || n > 126 && n < ke) {
                    this._printHandler(e, u, m), u = m - 1;
                    break;
                  }
                  if (++m >= i || (n = e[m]) < 32 || n > 126 && n < ke) {
                    this._printHandler(e, u, m), u = m - 1;
                    break;
                  }
                  if (++m >= i || (n = e[m]) < 32 || n > 126 && n < ke) {
                    this._printHandler(e, u, m), u = m - 1;
                    break;
                  }
                }
                break;
              case 3:
                this._executeHandlers[n] ? this._executeHandlers[n]() : this._executeHandlerFb(n), this.precedingJoinState = 0;
                break;
              case 0:
                break;
              case 1:
                if (this._errorHandler({ position: u, code: n, currentState: this.currentState, collect: this._collect, params: this._params, abort: false }).abort) return;
                break;
              case 7:
                let c = this._csiHandlers[this._collect << 8 | n], d = c ? c.length - 1 : -1;
                for (; d >= 0 && (a = c[d](this._params), a !== true); d--) if (a instanceof Promise) return this._preserveStack(3, c, d, o2, u), a;
                d < 0 && this._csiHandlerFb(this._collect << 8 | n, this._params), this.precedingJoinState = 0;
                break;
              case 8:
                do
                  switch (n) {
                    case 59:
                      this._params.addParam(0);
                      break;
                    case 58:
                      this._params.addSubParam(-1);
                      break;
                    default:
                      this._params.addDigit(n - 48);
                  }
                while (++u < i && (n = e[u]) > 47 && n < 60);
                u--;
                break;
              case 9:
                this._collect <<= 8, this._collect |= n;
                break;
              case 10:
                let _3 = this._escHandlers[this._collect << 8 | n], p = _3 ? _3.length - 1 : -1;
                for (; p >= 0 && (a = _3[p](), a !== true); p--) if (a instanceof Promise) return this._preserveStack(4, _3, p, o2, u), a;
                p < 0 && this._escHandlerFb(this._collect << 8 | n), this.precedingJoinState = 0;
                break;
              case 11:
                this._params.reset(), this._params.addParam(0), this._collect = 0;
                break;
              case 12:
                this._dcsParser.hook(this._collect << 8 | n, this._params);
                break;
              case 13:
                for (let m = u + 1; ; ++m) if (m >= i || (n = e[m]) === 24 || n === 26 || n === 27 || n > 127 && n < ke) {
                  this._dcsParser.put(e, u, m), u = m - 1;
                  break;
                }
                break;
              case 14:
                if (a = this._dcsParser.unhook(n !== 24 && n !== 26), a) return this._preserveStack(6, [], 0, o2, u), a;
                n === 27 && (o2 |= 1), this._params.reset(), this._params.addParam(0), this._collect = 0, this.precedingJoinState = 0;
                break;
              case 4:
                this._oscParser.start();
                break;
              case 5:
                for (let m = u + 1; ; m++) if (m >= i || (n = e[m]) < 32 || n > 127 && n < ke) {
                  this._oscParser.put(e, u, m), u = m - 1;
                  break;
                }
                break;
              case 6:
                if (a = this._oscParser.end(n !== 24 && n !== 26), a) return this._preserveStack(5, [], 0, o2, u), a;
                n === 27 && (o2 |= 1), this._params.reset(), this._params.addParam(0), this._collect = 0, this.precedingJoinState = 0;
                break;
            }
            this.currentState = o2 & 15;
          }
        }
      };
      dc = /^([\da-f])\/([\da-f])\/([\da-f])$|^([\da-f]{2})\/([\da-f]{2})\/([\da-f]{2})$|^([\da-f]{3})\/([\da-f]{3})\/([\da-f]{3})$|^([\da-f]{4})\/([\da-f]{4})\/([\da-f]{4})$/;
      fc = /^[\da-f]+$/;
      mc = { "(": 0, ")": 1, "*": 2, "+": 3, "-": 1, ".": 2 };
      ut = 131072;
      _l = 10;
      vl = 5e3;
      gl = 0;
      vn = class extends D {
        constructor(e, i, r, n, o2, l2, a, u, h2 = new bn()) {
          super();
          this._bufferService = e;
          this._charsetService = i;
          this._coreService = r;
          this._logService = n;
          this._optionsService = o2;
          this._oscLinkService = l2;
          this._coreMouseService = a;
          this._unicodeService = u;
          this._parser = h2;
          this._parseBuffer = new Uint32Array(4096);
          this._stringDecoder = new er();
          this._utf8Decoder = new tr();
          this._windowTitle = "";
          this._iconName = "";
          this._windowTitleStack = [];
          this._iconNameStack = [];
          this._curAttrData = X.clone();
          this._eraseAttrDataInternal = X.clone();
          this._onRequestBell = this._register(new v());
          this.onRequestBell = this._onRequestBell.event;
          this._onRequestRefreshRows = this._register(new v());
          this.onRequestRefreshRows = this._onRequestRefreshRows.event;
          this._onRequestReset = this._register(new v());
          this.onRequestReset = this._onRequestReset.event;
          this._onRequestSendFocus = this._register(new v());
          this.onRequestSendFocus = this._onRequestSendFocus.event;
          this._onRequestSyncScrollBar = this._register(new v());
          this.onRequestSyncScrollBar = this._onRequestSyncScrollBar.event;
          this._onRequestWindowsOptionsReport = this._register(new v());
          this.onRequestWindowsOptionsReport = this._onRequestWindowsOptionsReport.event;
          this._onA11yChar = this._register(new v());
          this.onA11yChar = this._onA11yChar.event;
          this._onA11yTab = this._register(new v());
          this.onA11yTab = this._onA11yTab.event;
          this._onCursorMove = this._register(new v());
          this.onCursorMove = this._onCursorMove.event;
          this._onLineFeed = this._register(new v());
          this.onLineFeed = this._onLineFeed.event;
          this._onScroll = this._register(new v());
          this.onScroll = this._onScroll.event;
          this._onTitleChange = this._register(new v());
          this.onTitleChange = this._onTitleChange.event;
          this._onColor = this._register(new v());
          this.onColor = this._onColor.event;
          this._parseStack = { paused: false, cursorStartX: 0, cursorStartY: 0, decodedLength: 0, position: 0 };
          this._specialColors = [256, 257, 258];
          this._register(this._parser), this._dirtyRowTracker = new Zi(this._bufferService), this._activeBuffer = this._bufferService.buffer, this._register(this._bufferService.buffers.onBufferActivate((c) => this._activeBuffer = c.activeBuffer)), this._parser.setCsiHandlerFallback((c, d) => {
            this._logService.debug("Unknown CSI code: ", { identifier: this._parser.identToString(c), params: d.toArray() });
          }), this._parser.setEscHandlerFallback((c) => {
            this._logService.debug("Unknown ESC code: ", { identifier: this._parser.identToString(c) });
          }), this._parser.setExecuteHandlerFallback((c) => {
            this._logService.debug("Unknown EXECUTE code: ", { code: c });
          }), this._parser.setOscHandlerFallback((c, d, _3) => {
            this._logService.debug("Unknown OSC code: ", { identifier: c, action: d, data: _3 });
          }), this._parser.setDcsHandlerFallback((c, d, _3) => {
            d === "HOOK" && (_3 = _3.toArray()), this._logService.debug("Unknown DCS code: ", { identifier: this._parser.identToString(c), action: d, payload: _3 });
          }), this._parser.setPrintHandler((c, d, _3) => this.print(c, d, _3)), this._parser.registerCsiHandler({ final: "@" }, (c) => this.insertChars(c)), this._parser.registerCsiHandler({ intermediates: " ", final: "@" }, (c) => this.scrollLeft(c)), this._parser.registerCsiHandler({ final: "A" }, (c) => this.cursorUp(c)), this._parser.registerCsiHandler({ intermediates: " ", final: "A" }, (c) => this.scrollRight(c)), this._parser.registerCsiHandler({ final: "B" }, (c) => this.cursorDown(c)), this._parser.registerCsiHandler({ final: "C" }, (c) => this.cursorForward(c)), this._parser.registerCsiHandler({ final: "D" }, (c) => this.cursorBackward(c)), this._parser.registerCsiHandler({ final: "E" }, (c) => this.cursorNextLine(c)), this._parser.registerCsiHandler({ final: "F" }, (c) => this.cursorPrecedingLine(c)), this._parser.registerCsiHandler({ final: "G" }, (c) => this.cursorCharAbsolute(c)), this._parser.registerCsiHandler({ final: "H" }, (c) => this.cursorPosition(c)), this._parser.registerCsiHandler({ final: "I" }, (c) => this.cursorForwardTab(c)), this._parser.registerCsiHandler({ final: "J" }, (c) => this.eraseInDisplay(c, false)), this._parser.registerCsiHandler({ prefix: "?", final: "J" }, (c) => this.eraseInDisplay(c, true)), this._parser.registerCsiHandler({ final: "K" }, (c) => this.eraseInLine(c, false)), this._parser.registerCsiHandler({ prefix: "?", final: "K" }, (c) => this.eraseInLine(c, true)), this._parser.registerCsiHandler({ final: "L" }, (c) => this.insertLines(c)), this._parser.registerCsiHandler({ final: "M" }, (c) => this.deleteLines(c)), this._parser.registerCsiHandler({ final: "P" }, (c) => this.deleteChars(c)), this._parser.registerCsiHandler({ final: "S" }, (c) => this.scrollUp(c)), this._parser.registerCsiHandler({ final: "T" }, (c) => this.scrollDown(c)), this._parser.registerCsiHandler({ final: "X" }, (c) => this.eraseChars(c)), this._parser.registerCsiHandler({ final: "Z" }, (c) => this.cursorBackwardTab(c)), this._parser.registerCsiHandler({ final: "`" }, (c) => this.charPosAbsolute(c)), this._parser.registerCsiHandler({ final: "a" }, (c) => this.hPositionRelative(c)), this._parser.registerCsiHandler({ final: "b" }, (c) => this.repeatPrecedingCharacter(c)), this._parser.registerCsiHandler({ final: "c" }, (c) => this.sendDeviceAttributesPrimary(c)), this._parser.registerCsiHandler({ prefix: ">", final: "c" }, (c) => this.sendDeviceAttributesSecondary(c)), this._parser.registerCsiHandler({ final: "d" }, (c) => this.linePosAbsolute(c)), this._parser.registerCsiHandler({ final: "e" }, (c) => this.vPositionRelative(c)), this._parser.registerCsiHandler({ final: "f" }, (c) => this.hVPosition(c)), this._parser.registerCsiHandler({ final: "g" }, (c) => this.tabClear(c)), this._parser.registerCsiHandler({ final: "h" }, (c) => this.setMode(c)), this._parser.registerCsiHandler({ prefix: "?", final: "h" }, (c) => this.setModePrivate(c)), this._parser.registerCsiHandler({ final: "l" }, (c) => this.resetMode(c)), this._parser.registerCsiHandler({ prefix: "?", final: "l" }, (c) => this.resetModePrivate(c)), this._parser.registerCsiHandler({ final: "m" }, (c) => this.charAttributes(c)), this._parser.registerCsiHandler({ final: "n" }, (c) => this.deviceStatus(c)), this._parser.registerCsiHandler({ prefix: "?", final: "n" }, (c) => this.deviceStatusPrivate(c)), this._parser.registerCsiHandler({ intermediates: "!", final: "p" }, (c) => this.softReset(c)), this._parser.registerCsiHandler({ intermediates: " ", final: "q" }, (c) => this.setCursorStyle(c)), this._parser.registerCsiHandler({ final: "r" }, (c) => this.setScrollRegion(c)), this._parser.registerCsiHandler({ final: "s" }, (c) => this.saveCursor(c)), this._parser.registerCsiHandler({ final: "t" }, (c) => this.windowOptions(c)), this._parser.registerCsiHandler({ final: "u" }, (c) => this.restoreCursor(c)), this._parser.registerCsiHandler({ intermediates: "'", final: "}" }, (c) => this.insertColumns(c)), this._parser.registerCsiHandler({ intermediates: "'", final: "~" }, (c) => this.deleteColumns(c)), this._parser.registerCsiHandler({ intermediates: '"', final: "q" }, (c) => this.selectProtected(c)), this._parser.registerCsiHandler({ intermediates: "$", final: "p" }, (c) => this.requestMode(c, true)), this._parser.registerCsiHandler({ prefix: "?", intermediates: "$", final: "p" }, (c) => this.requestMode(c, false)), this._parser.setExecuteHandler(b.BEL, () => this.bell()), this._parser.setExecuteHandler(b.LF, () => this.lineFeed()), this._parser.setExecuteHandler(b.VT, () => this.lineFeed()), this._parser.setExecuteHandler(b.FF, () => this.lineFeed()), this._parser.setExecuteHandler(b.CR, () => this.carriageReturn()), this._parser.setExecuteHandler(b.BS, () => this.backspace()), this._parser.setExecuteHandler(b.HT, () => this.tab()), this._parser.setExecuteHandler(b.SO, () => this.shiftOut()), this._parser.setExecuteHandler(b.SI, () => this.shiftIn()), this._parser.setExecuteHandler(Ai.IND, () => this.index()), this._parser.setExecuteHandler(Ai.NEL, () => this.nextLine()), this._parser.setExecuteHandler(Ai.HTS, () => this.tabSet()), this._parser.registerOscHandler(0, new pe((c) => (this.setTitle(c), this.setIconName(c), true))), this._parser.registerOscHandler(1, new pe((c) => this.setIconName(c))), this._parser.registerOscHandler(2, new pe((c) => this.setTitle(c))), this._parser.registerOscHandler(4, new pe((c) => this.setOrReportIndexedColor(c))), this._parser.registerOscHandler(8, new pe((c) => this.setHyperlink(c))), this._parser.registerOscHandler(10, new pe((c) => this.setOrReportFgColor(c))), this._parser.registerOscHandler(11, new pe((c) => this.setOrReportBgColor(c))), this._parser.registerOscHandler(12, new pe((c) => this.setOrReportCursorColor(c))), this._parser.registerOscHandler(104, new pe((c) => this.restoreIndexedColor(c))), this._parser.registerOscHandler(110, new pe((c) => this.restoreFgColor(c))), this._parser.registerOscHandler(111, new pe((c) => this.restoreBgColor(c))), this._parser.registerOscHandler(112, new pe((c) => this.restoreCursorColor(c))), this._parser.registerEscHandler({ final: "7" }, () => this.saveCursor()), this._parser.registerEscHandler({ final: "8" }, () => this.restoreCursor()), this._parser.registerEscHandler({ final: "D" }, () => this.index()), this._parser.registerEscHandler({ final: "E" }, () => this.nextLine()), this._parser.registerEscHandler({ final: "H" }, () => this.tabSet()), this._parser.registerEscHandler({ final: "M" }, () => this.reverseIndex()), this._parser.registerEscHandler({ final: "=" }, () => this.keypadApplicationMode()), this._parser.registerEscHandler({ final: ">" }, () => this.keypadNumericMode()), this._parser.registerEscHandler({ final: "c" }, () => this.fullReset()), this._parser.registerEscHandler({ final: "n" }, () => this.setgLevel(2)), this._parser.registerEscHandler({ final: "o" }, () => this.setgLevel(3)), this._parser.registerEscHandler({ final: "|" }, () => this.setgLevel(3)), this._parser.registerEscHandler({ final: "}" }, () => this.setgLevel(2)), this._parser.registerEscHandler({ final: "~" }, () => this.setgLevel(1)), this._parser.registerEscHandler({ intermediates: "%", final: "@" }, () => this.selectDefaultCharset()), this._parser.registerEscHandler({ intermediates: "%", final: "G" }, () => this.selectDefaultCharset());
          for (let c in ne) this._parser.registerEscHandler({ intermediates: "(", final: c }, () => this.selectCharset("(" + c)), this._parser.registerEscHandler({ intermediates: ")", final: c }, () => this.selectCharset(")" + c)), this._parser.registerEscHandler({ intermediates: "*", final: c }, () => this.selectCharset("*" + c)), this._parser.registerEscHandler({ intermediates: "+", final: c }, () => this.selectCharset("+" + c)), this._parser.registerEscHandler({ intermediates: "-", final: c }, () => this.selectCharset("-" + c)), this._parser.registerEscHandler({ intermediates: ".", final: c }, () => this.selectCharset("." + c)), this._parser.registerEscHandler({ intermediates: "/", final: c }, () => this.selectCharset("/" + c));
          this._parser.registerEscHandler({ intermediates: "#", final: "8" }, () => this.screenAlignmentPattern()), this._parser.setErrorHandler((c) => (this._logService.error("Parsing error: ", c), c)), this._parser.registerDcsHandler({ intermediates: "$", final: "q" }, new Xi((c, d) => this.requestStatusString(c, d)));
        }
        getAttrData() {
          return this._curAttrData;
        }
        _preserveStack(e, i, r, n) {
          this._parseStack.paused = true, this._parseStack.cursorStartX = e, this._parseStack.cursorStartY = i, this._parseStack.decodedLength = r, this._parseStack.position = n;
        }
        _logSlowResolvingAsync(e) {
          this._logService.logLevel <= 3 && Promise.race([e, new Promise((i, r) => setTimeout(() => r("#SLOW_TIMEOUT"), vl))]).catch((i) => {
            if (i !== "#SLOW_TIMEOUT") throw i;
            console.warn(`async parser handler taking longer than ${vl} ms`);
          });
        }
        _getCurrentLinkId() {
          return this._curAttrData.extended.urlId;
        }
        parse(e, i) {
          let r, n = this._activeBuffer.x, o2 = this._activeBuffer.y, l2 = 0, a = this._parseStack.paused;
          if (a) {
            if (r = this._parser.parse(this._parseBuffer, this._parseStack.decodedLength, i)) return this._logSlowResolvingAsync(r), r;
            n = this._parseStack.cursorStartX, o2 = this._parseStack.cursorStartY, this._parseStack.paused = false, e.length > ut && (l2 = this._parseStack.position + ut);
          }
          if (this._logService.logLevel <= 1 && this._logService.debug(`parsing data ${typeof e == "string" ? ` "${e}"` : ` "${Array.prototype.map.call(e, (c) => String.fromCharCode(c)).join("")}"`}`), this._logService.logLevel === 0 && this._logService.trace("parsing data (codes)", typeof e == "string" ? e.split("").map((c) => c.charCodeAt(0)) : e), this._parseBuffer.length < e.length && this._parseBuffer.length < ut && (this._parseBuffer = new Uint32Array(Math.min(e.length, ut))), a || this._dirtyRowTracker.clearRange(), e.length > ut) for (let c = l2; c < e.length; c += ut) {
            let d = c + ut < e.length ? c + ut : e.length, _3 = typeof e == "string" ? this._stringDecoder.decode(e.substring(c, d), this._parseBuffer) : this._utf8Decoder.decode(e.subarray(c, d), this._parseBuffer);
            if (r = this._parser.parse(this._parseBuffer, _3)) return this._preserveStack(n, o2, _3, c), this._logSlowResolvingAsync(r), r;
          }
          else if (!a) {
            let c = typeof e == "string" ? this._stringDecoder.decode(e, this._parseBuffer) : this._utf8Decoder.decode(e, this._parseBuffer);
            if (r = this._parser.parse(this._parseBuffer, c)) return this._preserveStack(n, o2, c, 0), this._logSlowResolvingAsync(r), r;
          }
          (this._activeBuffer.x !== n || this._activeBuffer.y !== o2) && this._onCursorMove.fire();
          let u = this._dirtyRowTracker.end + (this._bufferService.buffer.ybase - this._bufferService.buffer.ydisp), h2 = this._dirtyRowTracker.start + (this._bufferService.buffer.ybase - this._bufferService.buffer.ydisp);
          h2 < this._bufferService.rows && this._onRequestRefreshRows.fire({ start: Math.min(h2, this._bufferService.rows - 1), end: Math.min(u, this._bufferService.rows - 1) });
        }
        print(e, i, r) {
          let n, o2, l2 = this._charsetService.charset, a = this._optionsService.rawOptions.screenReaderMode, u = this._bufferService.cols, h2 = this._coreService.decPrivateModes.wraparound, c = this._coreService.modes.insertMode, d = this._curAttrData, _3 = this._activeBuffer.lines.get(this._activeBuffer.ybase + this._activeBuffer.y);
          this._dirtyRowTracker.markDirty(this._activeBuffer.y), this._activeBuffer.x && r - i > 0 && _3.getWidth(this._activeBuffer.x - 1) === 2 && _3.setCellFromCodepoint(this._activeBuffer.x - 1, 0, 1, d);
          let p = this._parser.precedingJoinState;
          for (let m = i; m < r; ++m) {
            if (n = e[m], n < 127 && l2) {
              let O = l2[String.fromCharCode(n)];
              O && (n = O.charCodeAt(0));
            }
            let f = this._unicodeService.charProperties(n, p);
            o2 = Ae.extractWidth(f);
            let A = Ae.extractShouldJoin(f), R = A ? Ae.extractWidth(p) : 0;
            if (p = f, a && this._onA11yChar.fire(Ce(n)), this._getCurrentLinkId() && this._oscLinkService.addLineToLink(this._getCurrentLinkId(), this._activeBuffer.ybase + this._activeBuffer.y), this._activeBuffer.x + o2 - R > u) {
              if (h2) {
                let O = _3, I = this._activeBuffer.x - R;
                for (this._activeBuffer.x = R, this._activeBuffer.y++, this._activeBuffer.y === this._activeBuffer.scrollBottom + 1 ? (this._activeBuffer.y--, this._bufferService.scroll(this._eraseAttrData(), true)) : (this._activeBuffer.y >= this._bufferService.rows && (this._activeBuffer.y = this._bufferService.rows - 1), this._activeBuffer.lines.get(this._activeBuffer.ybase + this._activeBuffer.y).isWrapped = true), _3 = this._activeBuffer.lines.get(this._activeBuffer.ybase + this._activeBuffer.y), R > 0 && _3 instanceof Ze && _3.copyCellsFrom(O, I, 0, R, false); I < u; ) O.setCellFromCodepoint(I++, 0, 1, d);
              } else if (this._activeBuffer.x = u - 1, o2 === 2) continue;
            }
            if (A && this._activeBuffer.x) {
              let O = _3.getWidth(this._activeBuffer.x - 1) ? 1 : 2;
              _3.addCodepointToCell(this._activeBuffer.x - O, n, o2);
              for (let I = o2 - R; --I >= 0; ) _3.setCellFromCodepoint(this._activeBuffer.x++, 0, 0, d);
              continue;
            }
            if (c && (_3.insertCells(this._activeBuffer.x, o2 - R, this._activeBuffer.getNullCell(d)), _3.getWidth(u - 1) === 2 && _3.setCellFromCodepoint(u - 1, 0, 1, d)), _3.setCellFromCodepoint(this._activeBuffer.x++, n, o2, d), o2 > 0) for (; --o2; ) _3.setCellFromCodepoint(this._activeBuffer.x++, 0, 0, d);
          }
          this._parser.precedingJoinState = p, this._activeBuffer.x < u && r - i > 0 && _3.getWidth(this._activeBuffer.x) === 0 && !_3.hasContent(this._activeBuffer.x) && _3.setCellFromCodepoint(this._activeBuffer.x, 0, 1, d), this._dirtyRowTracker.markDirty(this._activeBuffer.y);
        }
        registerCsiHandler(e, i) {
          return e.final === "t" && !e.prefix && !e.intermediates ? this._parser.registerCsiHandler(e, (r) => bl(r.params[0], this._optionsService.rawOptions.windowOptions) ? i(r) : true) : this._parser.registerCsiHandler(e, i);
        }
        registerDcsHandler(e, i) {
          return this._parser.registerDcsHandler(e, new Xi(i));
        }
        registerEscHandler(e, i) {
          return this._parser.registerEscHandler(e, i);
        }
        registerOscHandler(e, i) {
          return this._parser.registerOscHandler(e, new pe(i));
        }
        bell() {
          return this._onRequestBell.fire(), true;
        }
        lineFeed() {
          return this._dirtyRowTracker.markDirty(this._activeBuffer.y), this._optionsService.rawOptions.convertEol && (this._activeBuffer.x = 0), this._activeBuffer.y++, this._activeBuffer.y === this._activeBuffer.scrollBottom + 1 ? (this._activeBuffer.y--, this._bufferService.scroll(this._eraseAttrData())) : this._activeBuffer.y >= this._bufferService.rows ? this._activeBuffer.y = this._bufferService.rows - 1 : this._activeBuffer.lines.get(this._activeBuffer.ybase + this._activeBuffer.y).isWrapped = false, this._activeBuffer.x >= this._bufferService.cols && this._activeBuffer.x--, this._dirtyRowTracker.markDirty(this._activeBuffer.y), this._onLineFeed.fire(), true;
        }
        carriageReturn() {
          return this._activeBuffer.x = 0, true;
        }
        backspace() {
          if (!this._coreService.decPrivateModes.reverseWraparound) return this._restrictCursor(), this._activeBuffer.x > 0 && this._activeBuffer.x--, true;
          if (this._restrictCursor(this._bufferService.cols), this._activeBuffer.x > 0) this._activeBuffer.x--;
          else if (this._activeBuffer.x === 0 && this._activeBuffer.y > this._activeBuffer.scrollTop && this._activeBuffer.y <= this._activeBuffer.scrollBottom && this._activeBuffer.lines.get(this._activeBuffer.ybase + this._activeBuffer.y)?.isWrapped) {
            this._activeBuffer.lines.get(this._activeBuffer.ybase + this._activeBuffer.y).isWrapped = false, this._activeBuffer.y--, this._activeBuffer.x = this._bufferService.cols - 1;
            let e = this._activeBuffer.lines.get(this._activeBuffer.ybase + this._activeBuffer.y);
            e.hasWidth(this._activeBuffer.x) && !e.hasContent(this._activeBuffer.x) && this._activeBuffer.x--;
          }
          return this._restrictCursor(), true;
        }
        tab() {
          if (this._activeBuffer.x >= this._bufferService.cols) return true;
          let e = this._activeBuffer.x;
          return this._activeBuffer.x = this._activeBuffer.nextStop(), this._optionsService.rawOptions.screenReaderMode && this._onA11yTab.fire(this._activeBuffer.x - e), true;
        }
        shiftOut() {
          return this._charsetService.setgLevel(1), true;
        }
        shiftIn() {
          return this._charsetService.setgLevel(0), true;
        }
        _restrictCursor(e = this._bufferService.cols - 1) {
          this._activeBuffer.x = Math.min(e, Math.max(0, this._activeBuffer.x)), this._activeBuffer.y = this._coreService.decPrivateModes.origin ? Math.min(this._activeBuffer.scrollBottom, Math.max(this._activeBuffer.scrollTop, this._activeBuffer.y)) : Math.min(this._bufferService.rows - 1, Math.max(0, this._activeBuffer.y)), this._dirtyRowTracker.markDirty(this._activeBuffer.y);
        }
        _setCursor(e, i) {
          this._dirtyRowTracker.markDirty(this._activeBuffer.y), this._coreService.decPrivateModes.origin ? (this._activeBuffer.x = e, this._activeBuffer.y = this._activeBuffer.scrollTop + i) : (this._activeBuffer.x = e, this._activeBuffer.y = i), this._restrictCursor(), this._dirtyRowTracker.markDirty(this._activeBuffer.y);
        }
        _moveCursor(e, i) {
          this._restrictCursor(), this._setCursor(this._activeBuffer.x + e, this._activeBuffer.y + i);
        }
        cursorUp(e) {
          let i = this._activeBuffer.y - this._activeBuffer.scrollTop;
          return i >= 0 ? this._moveCursor(0, -Math.min(i, e.params[0] || 1)) : this._moveCursor(0, -(e.params[0] || 1)), true;
        }
        cursorDown(e) {
          let i = this._activeBuffer.scrollBottom - this._activeBuffer.y;
          return i >= 0 ? this._moveCursor(0, Math.min(i, e.params[0] || 1)) : this._moveCursor(0, e.params[0] || 1), true;
        }
        cursorForward(e) {
          return this._moveCursor(e.params[0] || 1, 0), true;
        }
        cursorBackward(e) {
          return this._moveCursor(-(e.params[0] || 1), 0), true;
        }
        cursorNextLine(e) {
          return this.cursorDown(e), this._activeBuffer.x = 0, true;
        }
        cursorPrecedingLine(e) {
          return this.cursorUp(e), this._activeBuffer.x = 0, true;
        }
        cursorCharAbsolute(e) {
          return this._setCursor((e.params[0] || 1) - 1, this._activeBuffer.y), true;
        }
        cursorPosition(e) {
          return this._setCursor(e.length >= 2 ? (e.params[1] || 1) - 1 : 0, (e.params[0] || 1) - 1), true;
        }
        charPosAbsolute(e) {
          return this._setCursor((e.params[0] || 1) - 1, this._activeBuffer.y), true;
        }
        hPositionRelative(e) {
          return this._moveCursor(e.params[0] || 1, 0), true;
        }
        linePosAbsolute(e) {
          return this._setCursor(this._activeBuffer.x, (e.params[0] || 1) - 1), true;
        }
        vPositionRelative(e) {
          return this._moveCursor(0, e.params[0] || 1), true;
        }
        hVPosition(e) {
          return this.cursorPosition(e), true;
        }
        tabClear(e) {
          let i = e.params[0];
          return i === 0 ? delete this._activeBuffer.tabs[this._activeBuffer.x] : i === 3 && (this._activeBuffer.tabs = {}), true;
        }
        cursorForwardTab(e) {
          if (this._activeBuffer.x >= this._bufferService.cols) return true;
          let i = e.params[0] || 1;
          for (; i--; ) this._activeBuffer.x = this._activeBuffer.nextStop();
          return true;
        }
        cursorBackwardTab(e) {
          if (this._activeBuffer.x >= this._bufferService.cols) return true;
          let i = e.params[0] || 1;
          for (; i--; ) this._activeBuffer.x = this._activeBuffer.prevStop();
          return true;
        }
        selectProtected(e) {
          let i = e.params[0];
          return i === 1 && (this._curAttrData.bg |= 536870912), (i === 2 || i === 0) && (this._curAttrData.bg &= -536870913), true;
        }
        _eraseInBufferLine(e, i, r, n = false, o2 = false) {
          let l2 = this._activeBuffer.lines.get(this._activeBuffer.ybase + e);
          l2.replaceCells(i, r, this._activeBuffer.getNullCell(this._eraseAttrData()), o2), n && (l2.isWrapped = false);
        }
        _resetBufferLine(e, i = false) {
          let r = this._activeBuffer.lines.get(this._activeBuffer.ybase + e);
          r && (r.fill(this._activeBuffer.getNullCell(this._eraseAttrData()), i), this._bufferService.buffer.clearMarkers(this._activeBuffer.ybase + e), r.isWrapped = false);
        }
        eraseInDisplay(e, i = false) {
          this._restrictCursor(this._bufferService.cols);
          let r;
          switch (e.params[0]) {
            case 0:
              for (r = this._activeBuffer.y, this._dirtyRowTracker.markDirty(r), this._eraseInBufferLine(r++, this._activeBuffer.x, this._bufferService.cols, this._activeBuffer.x === 0, i); r < this._bufferService.rows; r++) this._resetBufferLine(r, i);
              this._dirtyRowTracker.markDirty(r);
              break;
            case 1:
              for (r = this._activeBuffer.y, this._dirtyRowTracker.markDirty(r), this._eraseInBufferLine(r, 0, this._activeBuffer.x + 1, true, i), this._activeBuffer.x + 1 >= this._bufferService.cols && (this._activeBuffer.lines.get(r + 1).isWrapped = false); r--; ) this._resetBufferLine(r, i);
              this._dirtyRowTracker.markDirty(0);
              break;
            case 2:
              if (this._optionsService.rawOptions.scrollOnEraseInDisplay) {
                for (r = this._bufferService.rows, this._dirtyRowTracker.markRangeDirty(0, r - 1); r-- && !this._activeBuffer.lines.get(this._activeBuffer.ybase + r)?.getTrimmedLength(); ) ;
                for (; r >= 0; r--) this._bufferService.scroll(this._eraseAttrData());
              } else {
                for (r = this._bufferService.rows, this._dirtyRowTracker.markDirty(r - 1); r--; ) this._resetBufferLine(r, i);
                this._dirtyRowTracker.markDirty(0);
              }
              break;
            case 3:
              let n = this._activeBuffer.lines.length - this._bufferService.rows;
              n > 0 && (this._activeBuffer.lines.trimStart(n), this._activeBuffer.ybase = Math.max(this._activeBuffer.ybase - n, 0), this._activeBuffer.ydisp = Math.max(this._activeBuffer.ydisp - n, 0), this._onScroll.fire(0));
              break;
          }
          return true;
        }
        eraseInLine(e, i = false) {
          switch (this._restrictCursor(this._bufferService.cols), e.params[0]) {
            case 0:
              this._eraseInBufferLine(this._activeBuffer.y, this._activeBuffer.x, this._bufferService.cols, this._activeBuffer.x === 0, i);
              break;
            case 1:
              this._eraseInBufferLine(this._activeBuffer.y, 0, this._activeBuffer.x + 1, false, i);
              break;
            case 2:
              this._eraseInBufferLine(this._activeBuffer.y, 0, this._bufferService.cols, true, i);
              break;
          }
          return this._dirtyRowTracker.markDirty(this._activeBuffer.y), true;
        }
        insertLines(e) {
          this._restrictCursor();
          let i = e.params[0] || 1;
          if (this._activeBuffer.y > this._activeBuffer.scrollBottom || this._activeBuffer.y < this._activeBuffer.scrollTop) return true;
          let r = this._activeBuffer.ybase + this._activeBuffer.y, n = this._bufferService.rows - 1 - this._activeBuffer.scrollBottom, o2 = this._bufferService.rows - 1 + this._activeBuffer.ybase - n + 1;
          for (; i--; ) this._activeBuffer.lines.splice(o2 - 1, 1), this._activeBuffer.lines.splice(r, 0, this._activeBuffer.getBlankLine(this._eraseAttrData()));
          return this._dirtyRowTracker.markRangeDirty(this._activeBuffer.y, this._activeBuffer.scrollBottom), this._activeBuffer.x = 0, true;
        }
        deleteLines(e) {
          this._restrictCursor();
          let i = e.params[0] || 1;
          if (this._activeBuffer.y > this._activeBuffer.scrollBottom || this._activeBuffer.y < this._activeBuffer.scrollTop) return true;
          let r = this._activeBuffer.ybase + this._activeBuffer.y, n;
          for (n = this._bufferService.rows - 1 - this._activeBuffer.scrollBottom, n = this._bufferService.rows - 1 + this._activeBuffer.ybase - n; i--; ) this._activeBuffer.lines.splice(r, 1), this._activeBuffer.lines.splice(n, 0, this._activeBuffer.getBlankLine(this._eraseAttrData()));
          return this._dirtyRowTracker.markRangeDirty(this._activeBuffer.y, this._activeBuffer.scrollBottom), this._activeBuffer.x = 0, true;
        }
        insertChars(e) {
          this._restrictCursor();
          let i = this._activeBuffer.lines.get(this._activeBuffer.ybase + this._activeBuffer.y);
          return i && (i.insertCells(this._activeBuffer.x, e.params[0] || 1, this._activeBuffer.getNullCell(this._eraseAttrData())), this._dirtyRowTracker.markDirty(this._activeBuffer.y)), true;
        }
        deleteChars(e) {
          this._restrictCursor();
          let i = this._activeBuffer.lines.get(this._activeBuffer.ybase + this._activeBuffer.y);
          return i && (i.deleteCells(this._activeBuffer.x, e.params[0] || 1, this._activeBuffer.getNullCell(this._eraseAttrData())), this._dirtyRowTracker.markDirty(this._activeBuffer.y)), true;
        }
        scrollUp(e) {
          let i = e.params[0] || 1;
          for (; i--; ) this._activeBuffer.lines.splice(this._activeBuffer.ybase + this._activeBuffer.scrollTop, 1), this._activeBuffer.lines.splice(this._activeBuffer.ybase + this._activeBuffer.scrollBottom, 0, this._activeBuffer.getBlankLine(this._eraseAttrData()));
          return this._dirtyRowTracker.markRangeDirty(this._activeBuffer.scrollTop, this._activeBuffer.scrollBottom), true;
        }
        scrollDown(e) {
          let i = e.params[0] || 1;
          for (; i--; ) this._activeBuffer.lines.splice(this._activeBuffer.ybase + this._activeBuffer.scrollBottom, 1), this._activeBuffer.lines.splice(this._activeBuffer.ybase + this._activeBuffer.scrollTop, 0, this._activeBuffer.getBlankLine(X));
          return this._dirtyRowTracker.markRangeDirty(this._activeBuffer.scrollTop, this._activeBuffer.scrollBottom), true;
        }
        scrollLeft(e) {
          if (this._activeBuffer.y > this._activeBuffer.scrollBottom || this._activeBuffer.y < this._activeBuffer.scrollTop) return true;
          let i = e.params[0] || 1;
          for (let r = this._activeBuffer.scrollTop; r <= this._activeBuffer.scrollBottom; ++r) {
            let n = this._activeBuffer.lines.get(this._activeBuffer.ybase + r);
            n.deleteCells(0, i, this._activeBuffer.getNullCell(this._eraseAttrData())), n.isWrapped = false;
          }
          return this._dirtyRowTracker.markRangeDirty(this._activeBuffer.scrollTop, this._activeBuffer.scrollBottom), true;
        }
        scrollRight(e) {
          if (this._activeBuffer.y > this._activeBuffer.scrollBottom || this._activeBuffer.y < this._activeBuffer.scrollTop) return true;
          let i = e.params[0] || 1;
          for (let r = this._activeBuffer.scrollTop; r <= this._activeBuffer.scrollBottom; ++r) {
            let n = this._activeBuffer.lines.get(this._activeBuffer.ybase + r);
            n.insertCells(0, i, this._activeBuffer.getNullCell(this._eraseAttrData())), n.isWrapped = false;
          }
          return this._dirtyRowTracker.markRangeDirty(this._activeBuffer.scrollTop, this._activeBuffer.scrollBottom), true;
        }
        insertColumns(e) {
          if (this._activeBuffer.y > this._activeBuffer.scrollBottom || this._activeBuffer.y < this._activeBuffer.scrollTop) return true;
          let i = e.params[0] || 1;
          for (let r = this._activeBuffer.scrollTop; r <= this._activeBuffer.scrollBottom; ++r) {
            let n = this._activeBuffer.lines.get(this._activeBuffer.ybase + r);
            n.insertCells(this._activeBuffer.x, i, this._activeBuffer.getNullCell(this._eraseAttrData())), n.isWrapped = false;
          }
          return this._dirtyRowTracker.markRangeDirty(this._activeBuffer.scrollTop, this._activeBuffer.scrollBottom), true;
        }
        deleteColumns(e) {
          if (this._activeBuffer.y > this._activeBuffer.scrollBottom || this._activeBuffer.y < this._activeBuffer.scrollTop) return true;
          let i = e.params[0] || 1;
          for (let r = this._activeBuffer.scrollTop; r <= this._activeBuffer.scrollBottom; ++r) {
            let n = this._activeBuffer.lines.get(this._activeBuffer.ybase + r);
            n.deleteCells(this._activeBuffer.x, i, this._activeBuffer.getNullCell(this._eraseAttrData())), n.isWrapped = false;
          }
          return this._dirtyRowTracker.markRangeDirty(this._activeBuffer.scrollTop, this._activeBuffer.scrollBottom), true;
        }
        eraseChars(e) {
          this._restrictCursor();
          let i = this._activeBuffer.lines.get(this._activeBuffer.ybase + this._activeBuffer.y);
          return i && (i.replaceCells(this._activeBuffer.x, this._activeBuffer.x + (e.params[0] || 1), this._activeBuffer.getNullCell(this._eraseAttrData())), this._dirtyRowTracker.markDirty(this._activeBuffer.y)), true;
        }
        repeatPrecedingCharacter(e) {
          let i = this._parser.precedingJoinState;
          if (!i) return true;
          let r = e.params[0] || 1, n = Ae.extractWidth(i), o2 = this._activeBuffer.x - n, a = this._activeBuffer.lines.get(this._activeBuffer.ybase + this._activeBuffer.y).getString(o2), u = new Uint32Array(a.length * r), h2 = 0;
          for (let d = 0; d < a.length; ) {
            let _3 = a.codePointAt(d) || 0;
            u[h2++] = _3, d += _3 > 65535 ? 2 : 1;
          }
          let c = h2;
          for (let d = 1; d < r; ++d) u.copyWithin(c, 0, h2), c += h2;
          return this.print(u, 0, c), true;
        }
        sendDeviceAttributesPrimary(e) {
          return e.params[0] > 0 || (this._is("xterm") || this._is("rxvt-unicode") || this._is("screen") ? this._coreService.triggerDataEvent(b.ESC + "[?1;2c") : this._is("linux") && this._coreService.triggerDataEvent(b.ESC + "[?6c")), true;
        }
        sendDeviceAttributesSecondary(e) {
          return e.params[0] > 0 || (this._is("xterm") ? this._coreService.triggerDataEvent(b.ESC + "[>0;276;0c") : this._is("rxvt-unicode") ? this._coreService.triggerDataEvent(b.ESC + "[>85;95;0c") : this._is("linux") ? this._coreService.triggerDataEvent(e.params[0] + "c") : this._is("screen") && this._coreService.triggerDataEvent(b.ESC + "[>83;40003;0c")), true;
        }
        _is(e) {
          return (this._optionsService.rawOptions.termName + "").indexOf(e) === 0;
        }
        setMode(e) {
          for (let i = 0; i < e.length; i++) switch (e.params[i]) {
            case 4:
              this._coreService.modes.insertMode = true;
              break;
            case 20:
              this._optionsService.options.convertEol = true;
              break;
          }
          return true;
        }
        setModePrivate(e) {
          for (let i = 0; i < e.length; i++) switch (e.params[i]) {
            case 1:
              this._coreService.decPrivateModes.applicationCursorKeys = true;
              break;
            case 2:
              this._charsetService.setgCharset(0, Je), this._charsetService.setgCharset(1, Je), this._charsetService.setgCharset(2, Je), this._charsetService.setgCharset(3, Je);
              break;
            case 3:
              this._optionsService.rawOptions.windowOptions.setWinLines && (this._bufferService.resize(132, this._bufferService.rows), this._onRequestReset.fire());
              break;
            case 6:
              this._coreService.decPrivateModes.origin = true, this._setCursor(0, 0);
              break;
            case 7:
              this._coreService.decPrivateModes.wraparound = true;
              break;
            case 12:
              this._optionsService.options.cursorBlink = true;
              break;
            case 45:
              this._coreService.decPrivateModes.reverseWraparound = true;
              break;
            case 66:
              this._logService.debug("Serial port requested application keypad."), this._coreService.decPrivateModes.applicationKeypad = true, this._onRequestSyncScrollBar.fire();
              break;
            case 9:
              this._coreMouseService.activeProtocol = "X10";
              break;
            case 1e3:
              this._coreMouseService.activeProtocol = "VT200";
              break;
            case 1002:
              this._coreMouseService.activeProtocol = "DRAG";
              break;
            case 1003:
              this._coreMouseService.activeProtocol = "ANY";
              break;
            case 1004:
              this._coreService.decPrivateModes.sendFocus = true, this._onRequestSendFocus.fire();
              break;
            case 1005:
              this._logService.debug("DECSET 1005 not supported (see #2507)");
              break;
            case 1006:
              this._coreMouseService.activeEncoding = "SGR";
              break;
            case 1015:
              this._logService.debug("DECSET 1015 not supported (see #2507)");
              break;
            case 1016:
              this._coreMouseService.activeEncoding = "SGR_PIXELS";
              break;
            case 25:
              this._coreService.isCursorHidden = false;
              break;
            case 1048:
              this.saveCursor();
              break;
            case 1049:
              this.saveCursor();
            case 47:
            case 1047:
              this._bufferService.buffers.activateAltBuffer(this._eraseAttrData()), this._coreService.isCursorInitialized = true, this._onRequestRefreshRows.fire(void 0), this._onRequestSyncScrollBar.fire();
              break;
            case 2004:
              this._coreService.decPrivateModes.bracketedPasteMode = true;
              break;
            case 2026:
              this._coreService.decPrivateModes.synchronizedOutput = true;
              break;
          }
          return true;
        }
        resetMode(e) {
          for (let i = 0; i < e.length; i++) switch (e.params[i]) {
            case 4:
              this._coreService.modes.insertMode = false;
              break;
            case 20:
              this._optionsService.options.convertEol = false;
              break;
          }
          return true;
        }
        resetModePrivate(e) {
          for (let i = 0; i < e.length; i++) switch (e.params[i]) {
            case 1:
              this._coreService.decPrivateModes.applicationCursorKeys = false;
              break;
            case 3:
              this._optionsService.rawOptions.windowOptions.setWinLines && (this._bufferService.resize(80, this._bufferService.rows), this._onRequestReset.fire());
              break;
            case 6:
              this._coreService.decPrivateModes.origin = false, this._setCursor(0, 0);
              break;
            case 7:
              this._coreService.decPrivateModes.wraparound = false;
              break;
            case 12:
              this._optionsService.options.cursorBlink = false;
              break;
            case 45:
              this._coreService.decPrivateModes.reverseWraparound = false;
              break;
            case 66:
              this._logService.debug("Switching back to normal keypad."), this._coreService.decPrivateModes.applicationKeypad = false, this._onRequestSyncScrollBar.fire();
              break;
            case 9:
            case 1e3:
            case 1002:
            case 1003:
              this._coreMouseService.activeProtocol = "NONE";
              break;
            case 1004:
              this._coreService.decPrivateModes.sendFocus = false;
              break;
            case 1005:
              this._logService.debug("DECRST 1005 not supported (see #2507)");
              break;
            case 1006:
              this._coreMouseService.activeEncoding = "DEFAULT";
              break;
            case 1015:
              this._logService.debug("DECRST 1015 not supported (see #2507)");
              break;
            case 1016:
              this._coreMouseService.activeEncoding = "DEFAULT";
              break;
            case 25:
              this._coreService.isCursorHidden = true;
              break;
            case 1048:
              this.restoreCursor();
              break;
            case 1049:
            case 47:
            case 1047:
              this._bufferService.buffers.activateNormalBuffer(), e.params[i] === 1049 && this.restoreCursor(), this._coreService.isCursorInitialized = true, this._onRequestRefreshRows.fire(void 0), this._onRequestSyncScrollBar.fire();
              break;
            case 2004:
              this._coreService.decPrivateModes.bracketedPasteMode = false;
              break;
            case 2026:
              this._coreService.decPrivateModes.synchronizedOutput = false, this._onRequestRefreshRows.fire(void 0);
              break;
          }
          return true;
        }
        requestMode(e, i) {
          let r;
          ((P) => (P[P.NOT_RECOGNIZED = 0] = "NOT_RECOGNIZED", P[P.SET = 1] = "SET", P[P.RESET = 2] = "RESET", P[P.PERMANENTLY_SET = 3] = "PERMANENTLY_SET", P[P.PERMANENTLY_RESET = 4] = "PERMANENTLY_RESET"))(r ||= {});
          let n = this._coreService.decPrivateModes, { activeProtocol: o2, activeEncoding: l2 } = this._coreMouseService, a = this._coreService, { buffers: u, cols: h2 } = this._bufferService, { active: c, alt: d } = u, _3 = this._optionsService.rawOptions, p = (A, R) => (a.triggerDataEvent(`${b.ESC}[${i ? "" : "?"}${A};${R}$y`), true), m = (A) => A ? 1 : 2, f = e.params[0];
          return i ? f === 2 ? p(f, 4) : f === 4 ? p(f, m(a.modes.insertMode)) : f === 12 ? p(f, 3) : f === 20 ? p(f, m(_3.convertEol)) : p(f, 0) : f === 1 ? p(f, m(n.applicationCursorKeys)) : f === 3 ? p(f, _3.windowOptions.setWinLines ? h2 === 80 ? 2 : h2 === 132 ? 1 : 0 : 0) : f === 6 ? p(f, m(n.origin)) : f === 7 ? p(f, m(n.wraparound)) : f === 8 ? p(f, 3) : f === 9 ? p(f, m(o2 === "X10")) : f === 12 ? p(f, m(_3.cursorBlink)) : f === 25 ? p(f, m(!a.isCursorHidden)) : f === 45 ? p(f, m(n.reverseWraparound)) : f === 66 ? p(f, m(n.applicationKeypad)) : f === 67 ? p(f, 4) : f === 1e3 ? p(f, m(o2 === "VT200")) : f === 1002 ? p(f, m(o2 === "DRAG")) : f === 1003 ? p(f, m(o2 === "ANY")) : f === 1004 ? p(f, m(n.sendFocus)) : f === 1005 ? p(f, 4) : f === 1006 ? p(f, m(l2 === "SGR")) : f === 1015 ? p(f, 4) : f === 1016 ? p(f, m(l2 === "SGR_PIXELS")) : f === 1048 ? p(f, 1) : f === 47 || f === 1047 || f === 1049 ? p(f, m(c === d)) : f === 2004 ? p(f, m(n.bracketedPasteMode)) : f === 2026 ? p(f, m(n.synchronizedOutput)) : p(f, 0);
        }
        _updateAttrColor(e, i, r, n, o2) {
          return i === 2 ? (e |= 50331648, e &= -16777216, e |= De.fromColorRGB([r, n, o2])) : i === 5 && (e &= -50331904, e |= 33554432 | r & 255), e;
        }
        _extractColor(e, i, r) {
          let n = [0, 0, -1, 0, 0, 0], o2 = 0, l2 = 0;
          do {
            if (n[l2 + o2] = e.params[i + l2], e.hasSubParams(i + l2)) {
              let a = e.getSubParams(i + l2), u = 0;
              do
                n[1] === 5 && (o2 = 1), n[l2 + u + 1 + o2] = a[u];
              while (++u < a.length && u + l2 + 1 + o2 < n.length);
              break;
            }
            if (n[1] === 5 && l2 + o2 >= 2 || n[1] === 2 && l2 + o2 >= 5) break;
            n[1] && (o2 = 1);
          } while (++l2 + i < e.length && l2 + o2 < n.length);
          for (let a = 2; a < n.length; ++a) n[a] === -1 && (n[a] = 0);
          switch (n[0]) {
            case 38:
              r.fg = this._updateAttrColor(r.fg, n[1], n[3], n[4], n[5]);
              break;
            case 48:
              r.bg = this._updateAttrColor(r.bg, n[1], n[3], n[4], n[5]);
              break;
            case 58:
              r.extended = r.extended.clone(), r.extended.underlineColor = this._updateAttrColor(r.extended.underlineColor, n[1], n[3], n[4], n[5]);
          }
          return l2;
        }
        _processUnderline(e, i) {
          i.extended = i.extended.clone(), (!~e || e > 5) && (e = 1), i.extended.underlineStyle = e, i.fg |= 268435456, e === 0 && (i.fg &= -268435457), i.updateExtended();
        }
        _processSGR0(e) {
          e.fg = X.fg, e.bg = X.bg, e.extended = e.extended.clone(), e.extended.underlineStyle = 0, e.extended.underlineColor &= -67108864, e.updateExtended();
        }
        charAttributes(e) {
          if (e.length === 1 && e.params[0] === 0) return this._processSGR0(this._curAttrData), true;
          let i = e.length, r, n = this._curAttrData;
          for (let o2 = 0; o2 < i; o2++) r = e.params[o2], r >= 30 && r <= 37 ? (n.fg &= -50331904, n.fg |= 16777216 | r - 30) : r >= 40 && r <= 47 ? (n.bg &= -50331904, n.bg |= 16777216 | r - 40) : r >= 90 && r <= 97 ? (n.fg &= -50331904, n.fg |= 16777216 | r - 90 | 8) : r >= 100 && r <= 107 ? (n.bg &= -50331904, n.bg |= 16777216 | r - 100 | 8) : r === 0 ? this._processSGR0(n) : r === 1 ? n.fg |= 134217728 : r === 3 ? n.bg |= 67108864 : r === 4 ? (n.fg |= 268435456, this._processUnderline(e.hasSubParams(o2) ? e.getSubParams(o2)[0] : 1, n)) : r === 5 ? n.fg |= 536870912 : r === 7 ? n.fg |= 67108864 : r === 8 ? n.fg |= 1073741824 : r === 9 ? n.fg |= 2147483648 : r === 2 ? n.bg |= 134217728 : r === 21 ? this._processUnderline(2, n) : r === 22 ? (n.fg &= -134217729, n.bg &= -134217729) : r === 23 ? n.bg &= -67108865 : r === 24 ? (n.fg &= -268435457, this._processUnderline(0, n)) : r === 25 ? n.fg &= -536870913 : r === 27 ? n.fg &= -67108865 : r === 28 ? n.fg &= -1073741825 : r === 29 ? n.fg &= 2147483647 : r === 39 ? (n.fg &= -67108864, n.fg |= X.fg & 16777215) : r === 49 ? (n.bg &= -67108864, n.bg |= X.bg & 16777215) : r === 38 || r === 48 || r === 58 ? o2 += this._extractColor(e, o2, n) : r === 53 ? n.bg |= 1073741824 : r === 55 ? n.bg &= -1073741825 : r === 59 ? (n.extended = n.extended.clone(), n.extended.underlineColor = -1, n.updateExtended()) : r === 100 ? (n.fg &= -67108864, n.fg |= X.fg & 16777215, n.bg &= -67108864, n.bg |= X.bg & 16777215) : this._logService.debug("Unknown SGR attribute: %d.", r);
          return true;
        }
        deviceStatus(e) {
          switch (e.params[0]) {
            case 5:
              this._coreService.triggerDataEvent(`${b.ESC}[0n`);
              break;
            case 6:
              let i = this._activeBuffer.y + 1, r = this._activeBuffer.x + 1;
              this._coreService.triggerDataEvent(`${b.ESC}[${i};${r}R`);
              break;
          }
          return true;
        }
        deviceStatusPrivate(e) {
          switch (e.params[0]) {
            case 6:
              let i = this._activeBuffer.y + 1, r = this._activeBuffer.x + 1;
              this._coreService.triggerDataEvent(`${b.ESC}[?${i};${r}R`);
              break;
            case 15:
              break;
            case 25:
              break;
            case 26:
              break;
            case 53:
              break;
          }
          return true;
        }
        softReset(e) {
          return this._coreService.isCursorHidden = false, this._onRequestSyncScrollBar.fire(), this._activeBuffer.scrollTop = 0, this._activeBuffer.scrollBottom = this._bufferService.rows - 1, this._curAttrData = X.clone(), this._coreService.reset(), this._charsetService.reset(), this._activeBuffer.savedX = 0, this._activeBuffer.savedY = this._activeBuffer.ybase, this._activeBuffer.savedCurAttrData.fg = this._curAttrData.fg, this._activeBuffer.savedCurAttrData.bg = this._curAttrData.bg, this._activeBuffer.savedCharset = this._charsetService.charset, this._coreService.decPrivateModes.origin = false, true;
        }
        setCursorStyle(e) {
          let i = e.length === 0 ? 1 : e.params[0];
          if (i === 0) this._coreService.decPrivateModes.cursorStyle = void 0, this._coreService.decPrivateModes.cursorBlink = void 0;
          else {
            switch (i) {
              case 1:
              case 2:
                this._coreService.decPrivateModes.cursorStyle = "block";
                break;
              case 3:
              case 4:
                this._coreService.decPrivateModes.cursorStyle = "underline";
                break;
              case 5:
              case 6:
                this._coreService.decPrivateModes.cursorStyle = "bar";
                break;
            }
            let r = i % 2 === 1;
            this._coreService.decPrivateModes.cursorBlink = r;
          }
          return true;
        }
        setScrollRegion(e) {
          let i = e.params[0] || 1, r;
          return (e.length < 2 || (r = e.params[1]) > this._bufferService.rows || r === 0) && (r = this._bufferService.rows), r > i && (this._activeBuffer.scrollTop = i - 1, this._activeBuffer.scrollBottom = r - 1, this._setCursor(0, 0)), true;
        }
        windowOptions(e) {
          if (!bl(e.params[0], this._optionsService.rawOptions.windowOptions)) return true;
          let i = e.length > 1 ? e.params[1] : 0;
          switch (e.params[0]) {
            case 14:
              i !== 2 && this._onRequestWindowsOptionsReport.fire(0);
              break;
            case 16:
              this._onRequestWindowsOptionsReport.fire(1);
              break;
            case 18:
              this._bufferService && this._coreService.triggerDataEvent(`${b.ESC}[8;${this._bufferService.rows};${this._bufferService.cols}t`);
              break;
            case 22:
              (i === 0 || i === 2) && (this._windowTitleStack.push(this._windowTitle), this._windowTitleStack.length > _l && this._windowTitleStack.shift()), (i === 0 || i === 1) && (this._iconNameStack.push(this._iconName), this._iconNameStack.length > _l && this._iconNameStack.shift());
              break;
            case 23:
              (i === 0 || i === 2) && this._windowTitleStack.length && this.setTitle(this._windowTitleStack.pop()), (i === 0 || i === 1) && this._iconNameStack.length && this.setIconName(this._iconNameStack.pop());
              break;
          }
          return true;
        }
        saveCursor(e) {
          return this._activeBuffer.savedX = this._activeBuffer.x, this._activeBuffer.savedY = this._activeBuffer.ybase + this._activeBuffer.y, this._activeBuffer.savedCurAttrData.fg = this._curAttrData.fg, this._activeBuffer.savedCurAttrData.bg = this._curAttrData.bg, this._activeBuffer.savedCharset = this._charsetService.charset, true;
        }
        restoreCursor(e) {
          return this._activeBuffer.x = this._activeBuffer.savedX || 0, this._activeBuffer.y = Math.max(this._activeBuffer.savedY - this._activeBuffer.ybase, 0), this._curAttrData.fg = this._activeBuffer.savedCurAttrData.fg, this._curAttrData.bg = this._activeBuffer.savedCurAttrData.bg, this._charsetService.charset = this._savedCharset, this._activeBuffer.savedCharset && (this._charsetService.charset = this._activeBuffer.savedCharset), this._restrictCursor(), true;
        }
        setTitle(e) {
          return this._windowTitle = e, this._onTitleChange.fire(e), true;
        }
        setIconName(e) {
          return this._iconName = e, true;
        }
        setOrReportIndexedColor(e) {
          let i = [], r = e.split(";");
          for (; r.length > 1; ) {
            let n = r.shift(), o2 = r.shift();
            if (/^\d+$/.exec(n)) {
              let l2 = parseInt(n);
              if (Sl(l2)) if (o2 === "?") i.push({ type: 0, index: l2 });
              else {
                let a = Ws(o2);
                a && i.push({ type: 1, index: l2, color: a });
              }
            }
          }
          return i.length && this._onColor.fire(i), true;
        }
        setHyperlink(e) {
          let i = e.indexOf(";");
          if (i === -1) return true;
          let r = e.slice(0, i).trim(), n = e.slice(i + 1);
          return n ? this._createHyperlink(r, n) : r.trim() ? false : this._finishHyperlink();
        }
        _createHyperlink(e, i) {
          this._getCurrentLinkId() && this._finishHyperlink();
          let r = e.split(":"), n, o2 = r.findIndex((l2) => l2.startsWith("id="));
          return o2 !== -1 && (n = r[o2].slice(3) || void 0), this._curAttrData.extended = this._curAttrData.extended.clone(), this._curAttrData.extended.urlId = this._oscLinkService.registerLink({ id: n, uri: i }), this._curAttrData.updateExtended(), true;
        }
        _finishHyperlink() {
          return this._curAttrData.extended = this._curAttrData.extended.clone(), this._curAttrData.extended.urlId = 0, this._curAttrData.updateExtended(), true;
        }
        _setOrReportSpecialColor(e, i) {
          let r = e.split(";");
          for (let n = 0; n < r.length && !(i >= this._specialColors.length); ++n, ++i) if (r[n] === "?") this._onColor.fire([{ type: 0, index: this._specialColors[i] }]);
          else {
            let o2 = Ws(r[n]);
            o2 && this._onColor.fire([{ type: 1, index: this._specialColors[i], color: o2 }]);
          }
          return true;
        }
        setOrReportFgColor(e) {
          return this._setOrReportSpecialColor(e, 0);
        }
        setOrReportBgColor(e) {
          return this._setOrReportSpecialColor(e, 1);
        }
        setOrReportCursorColor(e) {
          return this._setOrReportSpecialColor(e, 2);
        }
        restoreIndexedColor(e) {
          if (!e) return this._onColor.fire([{ type: 2 }]), true;
          let i = [], r = e.split(";");
          for (let n = 0; n < r.length; ++n) if (/^\d+$/.exec(r[n])) {
            let o2 = parseInt(r[n]);
            Sl(o2) && i.push({ type: 2, index: o2 });
          }
          return i.length && this._onColor.fire(i), true;
        }
        restoreFgColor(e) {
          return this._onColor.fire([{ type: 2, index: 256 }]), true;
        }
        restoreBgColor(e) {
          return this._onColor.fire([{ type: 2, index: 257 }]), true;
        }
        restoreCursorColor(e) {
          return this._onColor.fire([{ type: 2, index: 258 }]), true;
        }
        nextLine() {
          return this._activeBuffer.x = 0, this.index(), true;
        }
        keypadApplicationMode() {
          return this._logService.debug("Serial port requested application keypad."), this._coreService.decPrivateModes.applicationKeypad = true, this._onRequestSyncScrollBar.fire(), true;
        }
        keypadNumericMode() {
          return this._logService.debug("Switching back to normal keypad."), this._coreService.decPrivateModes.applicationKeypad = false, this._onRequestSyncScrollBar.fire(), true;
        }
        selectDefaultCharset() {
          return this._charsetService.setgLevel(0), this._charsetService.setgCharset(0, Je), true;
        }
        selectCharset(e) {
          return e.length !== 2 ? (this.selectDefaultCharset(), true) : (e[0] === "/" || this._charsetService.setgCharset(mc[e[0]], ne[e[1]] || Je), true);
        }
        index() {
          return this._restrictCursor(), this._activeBuffer.y++, this._activeBuffer.y === this._activeBuffer.scrollBottom + 1 ? (this._activeBuffer.y--, this._bufferService.scroll(this._eraseAttrData())) : this._activeBuffer.y >= this._bufferService.rows && (this._activeBuffer.y = this._bufferService.rows - 1), this._restrictCursor(), true;
        }
        tabSet() {
          return this._activeBuffer.tabs[this._activeBuffer.x] = true, true;
        }
        reverseIndex() {
          if (this._restrictCursor(), this._activeBuffer.y === this._activeBuffer.scrollTop) {
            let e = this._activeBuffer.scrollBottom - this._activeBuffer.scrollTop;
            this._activeBuffer.lines.shiftElements(this._activeBuffer.ybase + this._activeBuffer.y, e, 1), this._activeBuffer.lines.set(this._activeBuffer.ybase + this._activeBuffer.y, this._activeBuffer.getBlankLine(this._eraseAttrData())), this._dirtyRowTracker.markRangeDirty(this._activeBuffer.scrollTop, this._activeBuffer.scrollBottom);
          } else this._activeBuffer.y--, this._restrictCursor();
          return true;
        }
        fullReset() {
          return this._parser.reset(), this._onRequestReset.fire(), true;
        }
        reset() {
          this._curAttrData = X.clone(), this._eraseAttrDataInternal = X.clone();
        }
        _eraseAttrData() {
          return this._eraseAttrDataInternal.bg &= -67108864, this._eraseAttrDataInternal.bg |= this._curAttrData.bg & 67108863, this._eraseAttrDataInternal;
        }
        setgLevel(e) {
          return this._charsetService.setgLevel(e), true;
        }
        screenAlignmentPattern() {
          let e = new q();
          e.content = 1 << 22 | 69, e.fg = this._curAttrData.fg, e.bg = this._curAttrData.bg, this._setCursor(0, 0);
          for (let i = 0; i < this._bufferService.rows; ++i) {
            let r = this._activeBuffer.ybase + this._activeBuffer.y + i, n = this._activeBuffer.lines.get(r);
            n && (n.fill(e), n.isWrapped = false);
          }
          return this._dirtyRowTracker.markAllDirty(), this._setCursor(0, 0), true;
        }
        requestStatusString(e, i) {
          let r = (a) => (this._coreService.triggerDataEvent(`${b.ESC}${a}${b.ESC}\\`), true), n = this._bufferService.buffer, o2 = this._optionsService.rawOptions, l2 = { block: 2, underline: 4, bar: 6 };
          return r(e === '"q' ? `P1$r${this._curAttrData.isProtected() ? 1 : 0}"q` : e === '"p' ? 'P1$r61;1"p' : e === "r" ? `P1$r${n.scrollTop + 1};${n.scrollBottom + 1}r` : e === "m" ? "P1$r0m" : e === " q" ? `P1$r${l2[o2.cursorStyle] - (o2.cursorBlink ? 1 : 0)} q` : "P0$r");
        }
        markRangeDirty(e, i) {
          this._dirtyRowTracker.markRangeDirty(e, i);
        }
      };
      Zi = class {
        constructor(t) {
          this._bufferService = t;
          this.clearRange();
        }
        clearRange() {
          this.start = this._bufferService.buffer.y, this.end = this._bufferService.buffer.y;
        }
        markDirty(t) {
          t < this.start ? this.start = t : t > this.end && (this.end = t);
        }
        markRangeDirty(t, e) {
          t > e && (gl = t, t = e, e = gl), t < this.start && (this.start = t), e > this.end && (this.end = e);
        }
        markAllDirty() {
          this.markRangeDirty(0, this._bufferService.rows - 1);
        }
      };
      Zi = M([S(0, F)], Zi);
      _c = 5e7;
      El = 12;
      bc = 50;
      gn = class extends D {
        constructor(e) {
          super();
          this._action = e;
          this._writeBuffer = [];
          this._callbacks = [];
          this._pendingData = 0;
          this._bufferOffset = 0;
          this._isSyncWriting = false;
          this._syncCalls = 0;
          this._didUserInput = false;
          this._onWriteParsed = this._register(new v());
          this.onWriteParsed = this._onWriteParsed.event;
        }
        handleUserInput() {
          this._didUserInput = true;
        }
        writeSync(e, i) {
          if (i !== void 0 && this._syncCalls > i) {
            this._syncCalls = 0;
            return;
          }
          if (this._pendingData += e.length, this._writeBuffer.push(e), this._callbacks.push(void 0), this._syncCalls++, this._isSyncWriting) return;
          this._isSyncWriting = true;
          let r;
          for (; r = this._writeBuffer.shift(); ) {
            this._action(r);
            let n = this._callbacks.shift();
            n && n();
          }
          this._pendingData = 0, this._bufferOffset = 2147483647, this._isSyncWriting = false, this._syncCalls = 0;
        }
        write(e, i) {
          if (this._pendingData > _c) throw new Error("write data discarded, use flow control to avoid losing data");
          if (!this._writeBuffer.length) {
            if (this._bufferOffset = 0, this._didUserInput) {
              this._didUserInput = false, this._pendingData += e.length, this._writeBuffer.push(e), this._callbacks.push(i), this._innerWrite();
              return;
            }
            setTimeout(() => this._innerWrite());
          }
          this._pendingData += e.length, this._writeBuffer.push(e), this._callbacks.push(i);
        }
        _innerWrite(e = 0, i = true) {
          let r = e || performance.now();
          for (; this._writeBuffer.length > this._bufferOffset; ) {
            let n = this._writeBuffer[this._bufferOffset], o2 = this._action(n, i);
            if (o2) {
              let a = (u) => performance.now() - r >= El ? setTimeout(() => this._innerWrite(0, u)) : this._innerWrite(r, u);
              o2.catch((u) => (queueMicrotask(() => {
                throw u;
              }), Promise.resolve(false))).then(a);
              return;
            }
            let l2 = this._callbacks[this._bufferOffset];
            if (l2 && l2(), this._bufferOffset++, this._pendingData -= n.length, performance.now() - r >= El) break;
          }
          this._writeBuffer.length > this._bufferOffset ? (this._bufferOffset > bc && (this._writeBuffer = this._writeBuffer.slice(this._bufferOffset), this._callbacks = this._callbacks.slice(this._bufferOffset), this._bufferOffset = 0), setTimeout(() => this._innerWrite())) : (this._writeBuffer.length = 0, this._callbacks.length = 0, this._pendingData = 0, this._bufferOffset = 0), this._onWriteParsed.fire();
        }
      };
      ui = class {
        constructor(t) {
          this._bufferService = t;
          this._nextId = 1;
          this._entriesWithId = /* @__PURE__ */ new Map();
          this._dataByLinkId = /* @__PURE__ */ new Map();
        }
        registerLink(t) {
          let e = this._bufferService.buffer;
          if (t.id === void 0) {
            let a = e.addMarker(e.ybase + e.y), u = { data: t, id: this._nextId++, lines: [a] };
            return a.onDispose(() => this._removeMarkerFromLink(u, a)), this._dataByLinkId.set(u.id, u), u.id;
          }
          let i = t, r = this._getEntryIdKey(i), n = this._entriesWithId.get(r);
          if (n) return this.addLineToLink(n.id, e.ybase + e.y), n.id;
          let o2 = e.addMarker(e.ybase + e.y), l2 = { id: this._nextId++, key: this._getEntryIdKey(i), data: i, lines: [o2] };
          return o2.onDispose(() => this._removeMarkerFromLink(l2, o2)), this._entriesWithId.set(l2.key, l2), this._dataByLinkId.set(l2.id, l2), l2.id;
        }
        addLineToLink(t, e) {
          let i = this._dataByLinkId.get(t);
          if (i && i.lines.every((r) => r.line !== e)) {
            let r = this._bufferService.buffer.addMarker(e);
            i.lines.push(r), r.onDispose(() => this._removeMarkerFromLink(i, r));
          }
        }
        getLinkData(t) {
          return this._dataByLinkId.get(t)?.data;
        }
        _getEntryIdKey(t) {
          return `${t.id};;${t.uri}`;
        }
        _removeMarkerFromLink(t, e) {
          let i = t.lines.indexOf(e);
          i !== -1 && (t.lines.splice(i, 1), t.lines.length === 0 && (t.data.id !== void 0 && this._entriesWithId.delete(t.key), this._dataByLinkId.delete(t.id)));
        }
      };
      ui = M([S(0, F)], ui);
      Tl = false;
      Sn = class extends D {
        constructor(e) {
          super();
          this._windowsWrappingHeuristics = this._register(new ye());
          this._onBinary = this._register(new v());
          this.onBinary = this._onBinary.event;
          this._onData = this._register(new v());
          this.onData = this._onData.event;
          this._onLineFeed = this._register(new v());
          this.onLineFeed = this._onLineFeed.event;
          this._onResize = this._register(new v());
          this.onResize = this._onResize.event;
          this._onWriteParsed = this._register(new v());
          this.onWriteParsed = this._onWriteParsed.event;
          this._onScroll = this._register(new v());
          this._instantiationService = new ln(), this.optionsService = this._register(new dn(e)), this._instantiationService.setService(H, this.optionsService), this._bufferService = this._register(this._instantiationService.createInstance(ni)), this._instantiationService.setService(F, this._bufferService), this._logService = this._register(this._instantiationService.createInstance(ii)), this._instantiationService.setService(nr, this._logService), this.coreService = this._register(this._instantiationService.createInstance(li)), this._instantiationService.setService(ge, this.coreService), this.coreMouseService = this._register(this._instantiationService.createInstance(ai)), this._instantiationService.setService(rr, this.coreMouseService), this.unicodeService = this._register(this._instantiationService.createInstance(Ae)), this._instantiationService.setService(Js, this.unicodeService), this._charsetService = this._instantiationService.createInstance(pn), this._instantiationService.setService(Zs, this._charsetService), this._oscLinkService = this._instantiationService.createInstance(ui), this._instantiationService.setService(sr, this._oscLinkService), this._inputHandler = this._register(new vn(this._bufferService, this._charsetService, this.coreService, this._logService, this.optionsService, this._oscLinkService, this.coreMouseService, this.unicodeService)), this._register($.forward(this._inputHandler.onLineFeed, this._onLineFeed)), this._register(this._inputHandler), this._register($.forward(this._bufferService.onResize, this._onResize)), this._register($.forward(this.coreService.onData, this._onData)), this._register($.forward(this.coreService.onBinary, this._onBinary)), this._register(this.coreService.onRequestScrollToBottom(() => this.scrollToBottom(true))), this._register(this.coreService.onUserInput(() => this._writeBuffer.handleUserInput())), this._register(this.optionsService.onMultipleOptionChange(["windowsMode", "windowsPty"], () => this._handleWindowsPtyOptionChange())), this._register(this._bufferService.onScroll(() => {
            this._onScroll.fire({ position: this._bufferService.buffer.ydisp }), this._inputHandler.markRangeDirty(this._bufferService.buffer.scrollTop, this._bufferService.buffer.scrollBottom);
          })), this._writeBuffer = this._register(new gn((i, r) => this._inputHandler.parse(i, r))), this._register($.forward(this._writeBuffer.onWriteParsed, this._onWriteParsed));
        }
        get onScroll() {
          return this._onScrollApi || (this._onScrollApi = this._register(new v()), this._onScroll.event((e) => {
            this._onScrollApi?.fire(e.position);
          })), this._onScrollApi.event;
        }
        get cols() {
          return this._bufferService.cols;
        }
        get rows() {
          return this._bufferService.rows;
        }
        get buffers() {
          return this._bufferService.buffers;
        }
        get options() {
          return this.optionsService.options;
        }
        set options(e) {
          for (let i in e) this.optionsService.options[i] = e[i];
        }
        write(e, i) {
          this._writeBuffer.write(e, i);
        }
        writeSync(e, i) {
          this._logService.logLevel <= 3 && !Tl && (this._logService.warn("writeSync is unreliable and will be removed soon."), Tl = true), this._writeBuffer.writeSync(e, i);
        }
        input(e, i = true) {
          this.coreService.triggerDataEvent(e, i);
        }
        resize(e, i) {
          isNaN(e) || isNaN(i) || (e = Math.max(e, ks), i = Math.max(i, Cs), this._bufferService.resize(e, i));
        }
        scroll(e, i = false) {
          this._bufferService.scroll(e, i);
        }
        scrollLines(e, i) {
          this._bufferService.scrollLines(e, i);
        }
        scrollPages(e) {
          this.scrollLines(e * (this.rows - 1));
        }
        scrollToTop() {
          this.scrollLines(-this._bufferService.buffer.ydisp);
        }
        scrollToBottom(e) {
          this.scrollLines(this._bufferService.buffer.ybase - this._bufferService.buffer.ydisp);
        }
        scrollToLine(e) {
          let i = e - this._bufferService.buffer.ydisp;
          i !== 0 && this.scrollLines(i);
        }
        registerEscHandler(e, i) {
          return this._inputHandler.registerEscHandler(e, i);
        }
        registerDcsHandler(e, i) {
          return this._inputHandler.registerDcsHandler(e, i);
        }
        registerCsiHandler(e, i) {
          return this._inputHandler.registerCsiHandler(e, i);
        }
        registerOscHandler(e, i) {
          return this._inputHandler.registerOscHandler(e, i);
        }
        _setup() {
          this._handleWindowsPtyOptionChange();
        }
        reset() {
          this._inputHandler.reset(), this._bufferService.reset(), this._charsetService.reset(), this.coreService.reset(), this.coreMouseService.reset();
        }
        _handleWindowsPtyOptionChange() {
          let e = false, i = this.optionsService.rawOptions.windowsPty;
          i && i.buildNumber !== void 0 && i.buildNumber !== void 0 ? e = i.backend === "conpty" && i.buildNumber < 21376 : this.optionsService.rawOptions.windowsMode && (e = true), e ? this._enableWindowsWrappingHeuristics() : this._windowsWrappingHeuristics.clear();
        }
        _enableWindowsWrappingHeuristics() {
          if (!this._windowsWrappingHeuristics.value) {
            let e = [];
            e.push(this.onLineFeed(Bs.bind(null, this._bufferService))), e.push(this.registerCsiHandler({ final: "H" }, () => (Bs(this._bufferService), false))), this._windowsWrappingHeuristics.value = C(() => {
              for (let i of e) i.dispose();
            });
          }
        }
      };
      gc = { 48: ["0", ")"], 49: ["1", "!"], 50: ["2", "@"], 51: ["3", "#"], 52: ["4", "$"], 53: ["5", "%"], 54: ["6", "^"], 55: ["7", "&"], 56: ["8", "*"], 57: ["9", "("], 186: [";", ":"], 187: ["=", "+"], 188: [",", "<"], 189: ["-", "_"], 190: [".", ">"], 191: ["/", "?"], 192: ["`", "~"], 219: ["[", "{"], 220: ["\\", "|"], 221: ["]", "}"], 222: ["'", '"'] };
      ee = 0;
      En = class {
        constructor(t) {
          this._getKey = t;
          this._array = [];
          this._insertedValues = [];
          this._flushInsertedTask = new Jt();
          this._isFlushingInserted = false;
          this._deletedIndices = [];
          this._flushDeletedTask = new Jt();
          this._isFlushingDeleted = false;
        }
        clear() {
          this._array.length = 0, this._insertedValues.length = 0, this._flushInsertedTask.clear(), this._isFlushingInserted = false, this._deletedIndices.length = 0, this._flushDeletedTask.clear(), this._isFlushingDeleted = false;
        }
        insert(t) {
          this._flushCleanupDeleted(), this._insertedValues.length === 0 && this._flushInsertedTask.enqueue(() => this._flushInserted()), this._insertedValues.push(t);
        }
        _flushInserted() {
          let t = this._insertedValues.sort((n, o2) => this._getKey(n) - this._getKey(o2)), e = 0, i = 0, r = new Array(this._array.length + this._insertedValues.length);
          for (let n = 0; n < r.length; n++) i >= this._array.length || this._getKey(t[e]) <= this._getKey(this._array[i]) ? (r[n] = t[e], e++) : r[n] = this._array[i++];
          this._array = r, this._insertedValues.length = 0;
        }
        _flushCleanupInserted() {
          !this._isFlushingInserted && this._insertedValues.length > 0 && this._flushInsertedTask.flush();
        }
        delete(t) {
          if (this._flushCleanupInserted(), this._array.length === 0) return false;
          let e = this._getKey(t);
          if (e === void 0 || (ee = this._search(e), ee === -1) || this._getKey(this._array[ee]) !== e) return false;
          do
            if (this._array[ee] === t) return this._deletedIndices.length === 0 && this._flushDeletedTask.enqueue(() => this._flushDeleted()), this._deletedIndices.push(ee), true;
          while (++ee < this._array.length && this._getKey(this._array[ee]) === e);
          return false;
        }
        _flushDeleted() {
          this._isFlushingDeleted = true;
          let t = this._deletedIndices.sort((n, o2) => n - o2), e = 0, i = new Array(this._array.length - t.length), r = 0;
          for (let n = 0; n < this._array.length; n++) t[e] === n ? e++ : i[r++] = this._array[n];
          this._array = i, this._deletedIndices.length = 0, this._isFlushingDeleted = false;
        }
        _flushCleanupDeleted() {
          !this._isFlushingDeleted && this._deletedIndices.length > 0 && this._flushDeletedTask.flush();
        }
        *getKeyIterator(t) {
          if (this._flushCleanupInserted(), this._flushCleanupDeleted(), this._array.length !== 0 && (ee = this._search(t), !(ee < 0 || ee >= this._array.length) && this._getKey(this._array[ee]) === t)) do
            yield this._array[ee];
          while (++ee < this._array.length && this._getKey(this._array[ee]) === t);
        }
        forEachByKey(t, e) {
          if (this._flushCleanupInserted(), this._flushCleanupDeleted(), this._array.length !== 0 && (ee = this._search(t), !(ee < 0 || ee >= this._array.length) && this._getKey(this._array[ee]) === t)) do
            e(this._array[ee]);
          while (++ee < this._array.length && this._getKey(this._array[ee]) === t);
        }
        values() {
          return this._flushCleanupInserted(), this._flushCleanupDeleted(), [...this._array].values();
        }
        _search(t) {
          let e = 0, i = this._array.length - 1;
          for (; i >= e; ) {
            let r = e + i >> 1, n = this._getKey(this._array[r]);
            if (n > t) i = r - 1;
            else if (n < t) e = r + 1;
            else {
              for (; r > 0 && this._getKey(this._array[r - 1]) === t; ) r--;
              return r;
            }
          }
          return e;
        }
      };
      Us = 0;
      yl = 0;
      Tn = class extends D {
        constructor() {
          super();
          this._decorations = new En((e) => e?.marker.line);
          this._onDecorationRegistered = this._register(new v());
          this.onDecorationRegistered = this._onDecorationRegistered.event;
          this._onDecorationRemoved = this._register(new v());
          this.onDecorationRemoved = this._onDecorationRemoved.event;
          this._register(C(() => this.reset()));
        }
        get decorations() {
          return this._decorations.values();
        }
        registerDecoration(e) {
          if (e.marker.isDisposed) return;
          let i = new Ks(e);
          if (i) {
            let r = i.marker.onDispose(() => i.dispose()), n = i.onDispose(() => {
              n.dispose(), i && (this._decorations.delete(i) && this._onDecorationRemoved.fire(i), r.dispose());
            });
            this._decorations.insert(i), this._onDecorationRegistered.fire(i);
          }
          return i;
        }
        reset() {
          for (let e of this._decorations.values()) e.dispose();
          this._decorations.clear();
        }
        *getDecorationsAtCell(e, i, r) {
          let n = 0, o2 = 0;
          for (let l2 of this._decorations.getKeyIterator(i)) n = l2.options.x ?? 0, o2 = n + (l2.options.width ?? 1), e >= n && e < o2 && (!r || (l2.options.layer ?? "bottom") === r) && (yield l2);
        }
        forEachDecorationAtCell(e, i, r, n) {
          this._decorations.forEachByKey(i, (o2) => {
            Us = o2.options.x ?? 0, yl = Us + (o2.options.width ?? 1), e >= Us && e < yl && (!r || (o2.options.layer ?? "bottom") === r) && n(o2);
          });
        }
      };
      Ks = class extends Ee {
        constructor(e) {
          super();
          this.options = e;
          this.onRenderEmitter = this.add(new v());
          this.onRender = this.onRenderEmitter.event;
          this._onDispose = this.add(new v());
          this.onDispose = this._onDispose.event;
          this._cachedBg = null;
          this._cachedFg = null;
          this.marker = e.marker, this.options.overviewRulerOptions && !this.options.overviewRulerOptions.position && (this.options.overviewRulerOptions.position = "full");
        }
        get backgroundColorRGB() {
          return this._cachedBg === null && (this.options.backgroundColor ? this._cachedBg = z.toColor(this.options.backgroundColor) : this._cachedBg = void 0), this._cachedBg;
        }
        get foregroundColorRGB() {
          return this._cachedFg === null && (this.options.foregroundColor ? this._cachedFg = z.toColor(this.options.foregroundColor) : this._cachedFg = void 0), this._cachedFg;
        }
        dispose() {
          this._onDispose.fire(), super.dispose();
        }
      };
      Sc = 1e3;
      In = class {
        constructor(t, e = Sc) {
          this._renderCallback = t;
          this._debounceThresholdMS = e;
          this._lastRefreshMs = 0;
          this._additionalRefreshRequested = false;
        }
        dispose() {
          this._refreshTimeoutID && clearTimeout(this._refreshTimeoutID);
        }
        refresh(t, e, i) {
          this._rowCount = i, t = t !== void 0 ? t : 0, e = e !== void 0 ? e : this._rowCount - 1, this._rowStart = this._rowStart !== void 0 ? Math.min(this._rowStart, t) : t, this._rowEnd = this._rowEnd !== void 0 ? Math.max(this._rowEnd, e) : e;
          let r = performance.now();
          if (r - this._lastRefreshMs >= this._debounceThresholdMS) this._lastRefreshMs = r, this._innerRefresh();
          else if (!this._additionalRefreshRequested) {
            let n = r - this._lastRefreshMs, o2 = this._debounceThresholdMS - n;
            this._additionalRefreshRequested = true, this._refreshTimeoutID = window.setTimeout(() => {
              this._lastRefreshMs = performance.now(), this._innerRefresh(), this._additionalRefreshRequested = false, this._refreshTimeoutID = void 0;
            }, o2);
          }
        }
        _innerRefresh() {
          if (this._rowStart === void 0 || this._rowEnd === void 0 || this._rowCount === void 0) return;
          let t = Math.max(this._rowStart, 0), e = Math.min(this._rowEnd, this._rowCount - 1);
          this._rowStart = void 0, this._rowEnd = void 0, this._renderCallback(t, e);
        }
      };
      xl = 20;
      wl = false;
      Tt = class extends D {
        constructor(e, i, r, n) {
          super();
          this._terminal = e;
          this._coreBrowserService = r;
          this._renderService = n;
          this._rowColumns = /* @__PURE__ */ new WeakMap();
          this._liveRegionLineCount = 0;
          this._charsToConsume = [];
          this._charsToAnnounce = "";
          let o2 = this._coreBrowserService.mainDocument;
          this._accessibilityContainer = o2.createElement("div"), this._accessibilityContainer.classList.add("xterm-accessibility"), this._rowContainer = o2.createElement("div"), this._rowContainer.setAttribute("role", "list"), this._rowContainer.classList.add("xterm-accessibility-tree"), this._rowElements = [];
          for (let l2 = 0; l2 < this._terminal.rows; l2++) this._rowElements[l2] = this._createAccessibilityTreeNode(), this._rowContainer.appendChild(this._rowElements[l2]);
          if (this._topBoundaryFocusListener = (l2) => this._handleBoundaryFocus(l2, 0), this._bottomBoundaryFocusListener = (l2) => this._handleBoundaryFocus(l2, 1), this._rowElements[0].addEventListener("focus", this._topBoundaryFocusListener), this._rowElements[this._rowElements.length - 1].addEventListener("focus", this._bottomBoundaryFocusListener), this._accessibilityContainer.appendChild(this._rowContainer), this._liveRegion = o2.createElement("div"), this._liveRegion.classList.add("live-region"), this._liveRegion.setAttribute("aria-live", "assertive"), this._accessibilityContainer.appendChild(this._liveRegion), this._liveRegionDebouncer = this._register(new In(this._renderRows.bind(this))), !this._terminal.element) throw new Error("Cannot enable accessibility before Terminal.open");
          wl ? (this._accessibilityContainer.classList.add("debug"), this._rowContainer.classList.add("debug"), this._debugRootContainer = o2.createElement("div"), this._debugRootContainer.classList.add("xterm"), this._debugRootContainer.appendChild(o2.createTextNode("------start a11y------")), this._debugRootContainer.appendChild(this._accessibilityContainer), this._debugRootContainer.appendChild(o2.createTextNode("------end a11y------")), this._terminal.element.insertAdjacentElement("afterend", this._debugRootContainer)) : this._terminal.element.insertAdjacentElement("afterbegin", this._accessibilityContainer), this._register(this._terminal.onResize((l2) => this._handleResize(l2.rows))), this._register(this._terminal.onRender((l2) => this._refreshRows(l2.start, l2.end))), this._register(this._terminal.onScroll(() => this._refreshRows())), this._register(this._terminal.onA11yChar((l2) => this._handleChar(l2))), this._register(this._terminal.onLineFeed(() => this._handleChar(`
`))), this._register(this._terminal.onA11yTab((l2) => this._handleTab(l2))), this._register(this._terminal.onKey((l2) => this._handleKey(l2.key))), this._register(this._terminal.onBlur(() => this._clearLiveRegion())), this._register(this._renderService.onDimensionsChange(() => this._refreshRowsDimensions())), this._register(L(o2, "selectionchange", () => this._handleSelectionChange())), this._register(this._coreBrowserService.onDprChange(() => this._refreshRowsDimensions())), this._refreshRowsDimensions(), this._refreshRows(), this._register(C(() => {
            wl ? this._debugRootContainer.remove() : this._accessibilityContainer.remove(), this._rowElements.length = 0;
          }));
        }
        _handleTab(e) {
          for (let i = 0; i < e; i++) this._handleChar(" ");
        }
        _handleChar(e) {
          this._liveRegionLineCount < xl + 1 && (this._charsToConsume.length > 0 ? this._charsToConsume.shift() !== e && (this._charsToAnnounce += e) : this._charsToAnnounce += e, e === `
` && (this._liveRegionLineCount++, this._liveRegionLineCount === xl + 1 && (this._liveRegion.textContent += _i.get())));
        }
        _clearLiveRegion() {
          this._liveRegion.textContent = "", this._liveRegionLineCount = 0;
        }
        _handleKey(e) {
          this._clearLiveRegion(), /\p{Control}/u.test(e) || this._charsToConsume.push(e);
        }
        _refreshRows(e, i) {
          this._liveRegionDebouncer.refresh(e, i, this._terminal.rows);
        }
        _renderRows(e, i) {
          let r = this._terminal.buffer, n = r.lines.length.toString();
          for (let o2 = e; o2 <= i; o2++) {
            let l2 = r.lines.get(r.ydisp + o2), a = [], u = l2?.translateToString(true, void 0, void 0, a) || "", h2 = (r.ydisp + o2 + 1).toString(), c = this._rowElements[o2];
            c && (u.length === 0 ? (c.textContent = "\xA0", this._rowColumns.set(c, [0, 1])) : (c.textContent = u, this._rowColumns.set(c, a)), c.setAttribute("aria-posinset", h2), c.setAttribute("aria-setsize", n), this._alignRowWidth(c));
          }
          this._announceCharacters();
        }
        _announceCharacters() {
          this._charsToAnnounce.length !== 0 && (this._liveRegion.textContent += this._charsToAnnounce, this._charsToAnnounce = "");
        }
        _handleBoundaryFocus(e, i) {
          let r = e.target, n = this._rowElements[i === 0 ? 1 : this._rowElements.length - 2], o2 = r.getAttribute("aria-posinset"), l2 = i === 0 ? "1" : `${this._terminal.buffer.lines.length}`;
          if (o2 === l2 || e.relatedTarget !== n) return;
          let a, u;
          if (i === 0 ? (a = r, u = this._rowElements.pop(), this._rowContainer.removeChild(u)) : (a = this._rowElements.shift(), u = r, this._rowContainer.removeChild(a)), a.removeEventListener("focus", this._topBoundaryFocusListener), u.removeEventListener("focus", this._bottomBoundaryFocusListener), i === 0) {
            let h2 = this._createAccessibilityTreeNode();
            this._rowElements.unshift(h2), this._rowContainer.insertAdjacentElement("afterbegin", h2);
          } else {
            let h2 = this._createAccessibilityTreeNode();
            this._rowElements.push(h2), this._rowContainer.appendChild(h2);
          }
          this._rowElements[0].addEventListener("focus", this._topBoundaryFocusListener), this._rowElements[this._rowElements.length - 1].addEventListener("focus", this._bottomBoundaryFocusListener), this._terminal.scrollLines(i === 0 ? -1 : 1), this._rowElements[i === 0 ? 1 : this._rowElements.length - 2].focus(), e.preventDefault(), e.stopImmediatePropagation();
        }
        _handleSelectionChange() {
          if (this._rowElements.length === 0) return;
          let e = this._coreBrowserService.mainDocument.getSelection();
          if (!e) return;
          if (e.isCollapsed) {
            this._rowContainer.contains(e.anchorNode) && this._terminal.clearSelection();
            return;
          }
          if (!e.anchorNode || !e.focusNode) {
            console.error("anchorNode and/or focusNode are null");
            return;
          }
          let i = { node: e.anchorNode, offset: e.anchorOffset }, r = { node: e.focusNode, offset: e.focusOffset };
          if ((i.node.compareDocumentPosition(r.node) & Node.DOCUMENT_POSITION_PRECEDING || i.node === r.node && i.offset > r.offset) && ([i, r] = [r, i]), i.node.compareDocumentPosition(this._rowElements[0]) & (Node.DOCUMENT_POSITION_CONTAINED_BY | Node.DOCUMENT_POSITION_FOLLOWING) && (i = { node: this._rowElements[0].childNodes[0], offset: 0 }), !this._rowContainer.contains(i.node)) return;
          let n = this._rowElements.slice(-1)[0];
          if (r.node.compareDocumentPosition(n) & (Node.DOCUMENT_POSITION_CONTAINED_BY | Node.DOCUMENT_POSITION_PRECEDING) && (r = { node: n, offset: n.textContent?.length ?? 0 }), !this._rowContainer.contains(r.node)) return;
          let o2 = ({ node: u, offset: h2 }) => {
            let c = u instanceof Text ? u.parentNode : u, d = parseInt(c?.getAttribute("aria-posinset"), 10) - 1;
            if (isNaN(d)) return console.warn("row is invalid. Race condition?"), null;
            let _3 = this._rowColumns.get(c);
            if (!_3) return console.warn("columns is null. Race condition?"), null;
            let p = h2 < _3.length ? _3[h2] : _3.slice(-1)[0] + 1;
            return p >= this._terminal.cols && (++d, p = 0), { row: d, column: p };
          }, l2 = o2(i), a = o2(r);
          if (!(!l2 || !a)) {
            if (l2.row > a.row || l2.row === a.row && l2.column >= a.column) throw new Error("invalid range");
            this._terminal.select(l2.column, l2.row, (a.row - l2.row) * this._terminal.cols - l2.column + a.column);
          }
        }
        _handleResize(e) {
          this._rowElements[this._rowElements.length - 1].removeEventListener("focus", this._bottomBoundaryFocusListener);
          for (let i = this._rowContainer.children.length; i < this._terminal.rows; i++) this._rowElements[i] = this._createAccessibilityTreeNode(), this._rowContainer.appendChild(this._rowElements[i]);
          for (; this._rowElements.length > e; ) this._rowContainer.removeChild(this._rowElements.pop());
          this._rowElements[this._rowElements.length - 1].addEventListener("focus", this._bottomBoundaryFocusListener), this._refreshRowsDimensions();
        }
        _createAccessibilityTreeNode() {
          let e = this._coreBrowserService.mainDocument.createElement("div");
          return e.setAttribute("role", "listitem"), e.tabIndex = -1, this._refreshRowDimensions(e), e;
        }
        _refreshRowsDimensions() {
          if (this._renderService.dimensions.css.cell.height) {
            Object.assign(this._accessibilityContainer.style, { width: `${this._renderService.dimensions.css.canvas.width}px`, fontSize: `${this._terminal.options.fontSize}px` }), this._rowElements.length !== this._terminal.rows && this._handleResize(this._terminal.rows);
            for (let e = 0; e < this._terminal.rows; e++) this._refreshRowDimensions(this._rowElements[e]), this._alignRowWidth(this._rowElements[e]);
          }
        }
        _refreshRowDimensions(e) {
          e.style.height = `${this._renderService.dimensions.css.cell.height}px`;
        }
        _alignRowWidth(e) {
          e.style.transform = "";
          let i = e.getBoundingClientRect().width, r = this._rowColumns.get(e)?.slice(-1)?.[0];
          if (!r) return;
          let n = r * this._renderService.dimensions.css.cell.width;
          e.style.transform = `scaleX(${n / i})`;
        }
      };
      Tt = M([S(1, xt), S(2, ae), S(3, ce)], Tt);
      hi = class extends D {
        constructor(e, i, r, n, o2) {
          super();
          this._element = e;
          this._mouseService = i;
          this._renderService = r;
          this._bufferService = n;
          this._linkProviderService = o2;
          this._linkCacheDisposables = [];
          this._isMouseOut = true;
          this._wasResized = false;
          this._activeLine = -1;
          this._onShowLinkUnderline = this._register(new v());
          this.onShowLinkUnderline = this._onShowLinkUnderline.event;
          this._onHideLinkUnderline = this._register(new v());
          this.onHideLinkUnderline = this._onHideLinkUnderline.event;
          this._register(C(() => {
            Ne(this._linkCacheDisposables), this._linkCacheDisposables.length = 0, this._lastMouseEvent = void 0, this._activeProviderReplies?.clear();
          })), this._register(this._bufferService.onResize(() => {
            this._clearCurrentLink(), this._wasResized = true;
          })), this._register(L(this._element, "mouseleave", () => {
            this._isMouseOut = true, this._clearCurrentLink();
          })), this._register(L(this._element, "mousemove", this._handleMouseMove.bind(this))), this._register(L(this._element, "mousedown", this._handleMouseDown.bind(this))), this._register(L(this._element, "mouseup", this._handleMouseUp.bind(this)));
        }
        get currentLink() {
          return this._currentLink;
        }
        _handleMouseMove(e) {
          this._lastMouseEvent = e;
          let i = this._positionFromMouseEvent(e, this._element, this._mouseService);
          if (!i) return;
          this._isMouseOut = false;
          let r = e.composedPath();
          for (let n = 0; n < r.length; n++) {
            let o2 = r[n];
            if (o2.classList.contains("xterm")) break;
            if (o2.classList.contains("xterm-hover")) return;
          }
          (!this._lastBufferCell || i.x !== this._lastBufferCell.x || i.y !== this._lastBufferCell.y) && (this._handleHover(i), this._lastBufferCell = i);
        }
        _handleHover(e) {
          if (this._activeLine !== e.y || this._wasResized) {
            this._clearCurrentLink(), this._askForLink(e, false), this._wasResized = false;
            return;
          }
          this._currentLink && this._linkAtPosition(this._currentLink.link, e) || (this._clearCurrentLink(), this._askForLink(e, true));
        }
        _askForLink(e, i) {
          (!this._activeProviderReplies || !i) && (this._activeProviderReplies?.forEach((n) => {
            n?.forEach((o2) => {
              o2.link.dispose && o2.link.dispose();
            });
          }), this._activeProviderReplies = /* @__PURE__ */ new Map(), this._activeLine = e.y);
          let r = false;
          for (let [n, o2] of this._linkProviderService.linkProviders.entries()) i ? this._activeProviderReplies?.get(n) && (r = this._checkLinkProviderResult(n, e, r)) : o2.provideLinks(e.y, (l2) => {
            if (this._isMouseOut) return;
            let a = l2?.map((u) => ({ link: u }));
            this._activeProviderReplies?.set(n, a), r = this._checkLinkProviderResult(n, e, r), this._activeProviderReplies?.size === this._linkProviderService.linkProviders.length && this._removeIntersectingLinks(e.y, this._activeProviderReplies);
          });
        }
        _removeIntersectingLinks(e, i) {
          let r = /* @__PURE__ */ new Set();
          for (let n = 0; n < i.size; n++) {
            let o2 = i.get(n);
            if (o2) for (let l2 = 0; l2 < o2.length; l2++) {
              let a = o2[l2], u = a.link.range.start.y < e ? 0 : a.link.range.start.x, h2 = a.link.range.end.y > e ? this._bufferService.cols : a.link.range.end.x;
              for (let c = u; c <= h2; c++) {
                if (r.has(c)) {
                  o2.splice(l2--, 1);
                  break;
                }
                r.add(c);
              }
            }
          }
        }
        _checkLinkProviderResult(e, i, r) {
          if (!this._activeProviderReplies) return r;
          let n = this._activeProviderReplies.get(e), o2 = false;
          for (let l2 = 0; l2 < e; l2++) (!this._activeProviderReplies.has(l2) || this._activeProviderReplies.get(l2)) && (o2 = true);
          if (!o2 && n) {
            let l2 = n.find((a) => this._linkAtPosition(a.link, i));
            l2 && (r = true, this._handleNewLink(l2));
          }
          if (this._activeProviderReplies.size === this._linkProviderService.linkProviders.length && !r) for (let l2 = 0; l2 < this._activeProviderReplies.size; l2++) {
            let a = this._activeProviderReplies.get(l2)?.find((u) => this._linkAtPosition(u.link, i));
            if (a) {
              r = true, this._handleNewLink(a);
              break;
            }
          }
          return r;
        }
        _handleMouseDown() {
          this._mouseDownLink = this._currentLink;
        }
        _handleMouseUp(e) {
          if (!this._currentLink) return;
          let i = this._positionFromMouseEvent(e, this._element, this._mouseService);
          i && this._mouseDownLink && Ec(this._mouseDownLink.link, this._currentLink.link) && this._linkAtPosition(this._currentLink.link, i) && this._currentLink.link.activate(e, this._currentLink.link.text);
        }
        _clearCurrentLink(e, i) {
          !this._currentLink || !this._lastMouseEvent || (!e || !i || this._currentLink.link.range.start.y >= e && this._currentLink.link.range.end.y <= i) && (this._linkLeave(this._element, this._currentLink.link, this._lastMouseEvent), this._currentLink = void 0, Ne(this._linkCacheDisposables), this._linkCacheDisposables.length = 0);
        }
        _handleNewLink(e) {
          if (!this._lastMouseEvent) return;
          let i = this._positionFromMouseEvent(this._lastMouseEvent, this._element, this._mouseService);
          i && this._linkAtPosition(e.link, i) && (this._currentLink = e, this._currentLink.state = { decorations: { underline: e.link.decorations === void 0 ? true : e.link.decorations.underline, pointerCursor: e.link.decorations === void 0 ? true : e.link.decorations.pointerCursor }, isHovered: true }, this._linkHover(this._element, e.link, this._lastMouseEvent), e.link.decorations = {}, Object.defineProperties(e.link.decorations, { pointerCursor: { get: () => this._currentLink?.state?.decorations.pointerCursor, set: (r) => {
            this._currentLink?.state && this._currentLink.state.decorations.pointerCursor !== r && (this._currentLink.state.decorations.pointerCursor = r, this._currentLink.state.isHovered && this._element.classList.toggle("xterm-cursor-pointer", r));
          } }, underline: { get: () => this._currentLink?.state?.decorations.underline, set: (r) => {
            this._currentLink?.state && this._currentLink?.state?.decorations.underline !== r && (this._currentLink.state.decorations.underline = r, this._currentLink.state.isHovered && this._fireUnderlineEvent(e.link, r));
          } } }), this._linkCacheDisposables.push(this._renderService.onRenderedViewportChange((r) => {
            if (!this._currentLink) return;
            let n = r.start === 0 ? 0 : r.start + 1 + this._bufferService.buffer.ydisp, o2 = this._bufferService.buffer.ydisp + 1 + r.end;
            if (this._currentLink.link.range.start.y >= n && this._currentLink.link.range.end.y <= o2 && (this._clearCurrentLink(n, o2), this._lastMouseEvent)) {
              let l2 = this._positionFromMouseEvent(this._lastMouseEvent, this._element, this._mouseService);
              l2 && this._askForLink(l2, false);
            }
          })));
        }
        _linkHover(e, i, r) {
          this._currentLink?.state && (this._currentLink.state.isHovered = true, this._currentLink.state.decorations.underline && this._fireUnderlineEvent(i, true), this._currentLink.state.decorations.pointerCursor && e.classList.add("xterm-cursor-pointer")), i.hover && i.hover(r, i.text);
        }
        _fireUnderlineEvent(e, i) {
          let r = e.range, n = this._bufferService.buffer.ydisp, o2 = this._createLinkUnderlineEvent(r.start.x - 1, r.start.y - n - 1, r.end.x, r.end.y - n - 1, void 0);
          (i ? this._onShowLinkUnderline : this._onHideLinkUnderline).fire(o2);
        }
        _linkLeave(e, i, r) {
          this._currentLink?.state && (this._currentLink.state.isHovered = false, this._currentLink.state.decorations.underline && this._fireUnderlineEvent(i, false), this._currentLink.state.decorations.pointerCursor && e.classList.remove("xterm-cursor-pointer")), i.leave && i.leave(r, i.text);
        }
        _linkAtPosition(e, i) {
          let r = e.range.start.y * this._bufferService.cols + e.range.start.x, n = e.range.end.y * this._bufferService.cols + e.range.end.x, o2 = i.y * this._bufferService.cols + i.x;
          return r <= o2 && o2 <= n;
        }
        _positionFromMouseEvent(e, i, r) {
          let n = r.getCoords(e, i, this._bufferService.cols, this._bufferService.rows);
          if (n) return { x: n[0], y: n[1] + this._bufferService.buffer.ydisp };
        }
        _createLinkUnderlineEvent(e, i, r, n, o2) {
          return { x1: e, y1: i, x2: r, y2: n, cols: this._bufferService.cols, fg: o2 };
        }
      };
      hi = M([S(1, Dt), S(2, ce), S(3, F), S(4, lr)], hi);
      yn = class extends Sn {
        constructor(e = {}) {
          super(e);
          this._linkifier = this._register(new ye());
          this.browser = tn;
          this._keyDownHandled = false;
          this._keyDownSeen = false;
          this._keyPressHandled = false;
          this._unprocessedDeadKey = false;
          this._accessibilityManager = this._register(new ye());
          this._onCursorMove = this._register(new v());
          this.onCursorMove = this._onCursorMove.event;
          this._onKey = this._register(new v());
          this.onKey = this._onKey.event;
          this._onRender = this._register(new v());
          this.onRender = this._onRender.event;
          this._onSelectionChange = this._register(new v());
          this.onSelectionChange = this._onSelectionChange.event;
          this._onTitleChange = this._register(new v());
          this.onTitleChange = this._onTitleChange.event;
          this._onBell = this._register(new v());
          this.onBell = this._onBell.event;
          this._onFocus = this._register(new v());
          this._onBlur = this._register(new v());
          this._onA11yCharEmitter = this._register(new v());
          this._onA11yTabEmitter = this._register(new v());
          this._onWillOpen = this._register(new v());
          this._setup(), this._decorationService = this._instantiationService.createInstance(Tn), this._instantiationService.setService(Be, this._decorationService), this._linkProviderService = this._instantiationService.createInstance(Qr), this._instantiationService.setService(lr, this._linkProviderService), this._linkProviderService.registerLinkProvider(this._instantiationService.createInstance(wt)), this._register(this._inputHandler.onRequestBell(() => this._onBell.fire())), this._register(this._inputHandler.onRequestRefreshRows((i) => this.refresh(i?.start ?? 0, i?.end ?? this.rows - 1))), this._register(this._inputHandler.onRequestSendFocus(() => this._reportFocus())), this._register(this._inputHandler.onRequestReset(() => this.reset())), this._register(this._inputHandler.onRequestWindowsOptionsReport((i) => this._reportWindowsOptions(i))), this._register(this._inputHandler.onColor((i) => this._handleColorEvent(i))), this._register($.forward(this._inputHandler.onCursorMove, this._onCursorMove)), this._register($.forward(this._inputHandler.onTitleChange, this._onTitleChange)), this._register($.forward(this._inputHandler.onA11yChar, this._onA11yCharEmitter)), this._register($.forward(this._inputHandler.onA11yTab, this._onA11yTabEmitter)), this._register(this._bufferService.onResize((i) => this._afterResize(i.cols, i.rows))), this._register(C(() => {
            this._customKeyEventHandler = void 0, this.element?.parentNode?.removeChild(this.element);
          }));
        }
        get linkifier() {
          return this._linkifier.value;
        }
        get onFocus() {
          return this._onFocus.event;
        }
        get onBlur() {
          return this._onBlur.event;
        }
        get onA11yChar() {
          return this._onA11yCharEmitter.event;
        }
        get onA11yTab() {
          return this._onA11yTabEmitter.event;
        }
        get onWillOpen() {
          return this._onWillOpen.event;
        }
        _handleColorEvent(e) {
          if (this._themeService) for (let i of e) {
            let r, n = "";
            switch (i.index) {
              case 256:
                r = "foreground", n = "10";
                break;
              case 257:
                r = "background", n = "11";
                break;
              case 258:
                r = "cursor", n = "12";
                break;
              default:
                r = "ansi", n = "4;" + i.index;
            }
            switch (i.type) {
              case 0:
                let o2 = U.toColorRGB(r === "ansi" ? this._themeService.colors.ansi[i.index] : this._themeService.colors[r]);
                this.coreService.triggerDataEvent(`${b.ESC}]${n};${ml(o2)}${fs.ST}`);
                break;
              case 1:
                if (r === "ansi") this._themeService.modifyColors((l2) => l2.ansi[i.index] = j.toColor(...i.color));
                else {
                  let l2 = r;
                  this._themeService.modifyColors((a) => a[l2] = j.toColor(...i.color));
                }
                break;
              case 2:
                this._themeService.restoreColor(i.index);
                break;
            }
          }
        }
        _setup() {
          super._setup(), this._customKeyEventHandler = void 0;
        }
        get buffer() {
          return this.buffers.active;
        }
        focus() {
          this.textarea && this.textarea.focus({ preventScroll: true });
        }
        _handleScreenReaderModeOptionChange(e) {
          e ? !this._accessibilityManager.value && this._renderService && (this._accessibilityManager.value = this._instantiationService.createInstance(Tt, this)) : this._accessibilityManager.clear();
        }
        _handleTextAreaFocus(e) {
          this.coreService.decPrivateModes.sendFocus && this.coreService.triggerDataEvent(b.ESC + "[I"), this.element.classList.add("focus"), this._showCursor(), this._onFocus.fire();
        }
        blur() {
          return this.textarea?.blur();
        }
        _handleTextAreaBlur() {
          this.textarea.value = "", this.refresh(this.buffer.y, this.buffer.y), this.coreService.decPrivateModes.sendFocus && this.coreService.triggerDataEvent(b.ESC + "[O"), this.element.classList.remove("focus"), this._onBlur.fire();
        }
        _syncTextArea() {
          if (!this.textarea || !this.buffer.isCursorInViewport || this._compositionHelper.isComposing || !this._renderService) return;
          let e = this.buffer.ybase + this.buffer.y, i = this.buffer.lines.get(e);
          if (!i) return;
          let r = Math.min(this.buffer.x, this.cols - 1), n = this._renderService.dimensions.css.cell.height, o2 = i.getWidth(r), l2 = this._renderService.dimensions.css.cell.width * o2, a = this.buffer.y * this._renderService.dimensions.css.cell.height, u = r * this._renderService.dimensions.css.cell.width;
          this.textarea.style.left = u + "px", this.textarea.style.top = a + "px", this.textarea.style.width = l2 + "px", this.textarea.style.height = n + "px", this.textarea.style.lineHeight = n + "px", this.textarea.style.zIndex = "-5";
        }
        _initGlobal() {
          this._bindKeys(), this._register(L(this.element, "copy", (i) => {
            this.hasSelection() && Vs(i, this._selectionService);
          }));
          let e = (i) => qs(i, this.textarea, this.coreService, this.optionsService);
          this._register(L(this.textarea, "paste", e)), this._register(L(this.element, "paste", e)), Ss ? this._register(L(this.element, "mousedown", (i) => {
            i.button === 2 && Pn(i, this.textarea, this.screenElement, this._selectionService, this.options.rightClickSelectsWord);
          })) : this._register(L(this.element, "contextmenu", (i) => {
            Pn(i, this.textarea, this.screenElement, this._selectionService, this.options.rightClickSelectsWord);
          })), Bi && this._register(L(this.element, "auxclick", (i) => {
            i.button === 1 && Mn(i, this.textarea, this.screenElement);
          }));
        }
        _bindKeys() {
          this._register(L(this.textarea, "keyup", (e) => this._keyUp(e), true)), this._register(L(this.textarea, "keydown", (e) => this._keyDown(e), true)), this._register(L(this.textarea, "keypress", (e) => this._keyPress(e), true)), this._register(L(this.textarea, "compositionstart", () => this._compositionHelper.compositionstart())), this._register(L(this.textarea, "compositionupdate", (e) => this._compositionHelper.compositionupdate(e))), this._register(L(this.textarea, "compositionend", () => this._compositionHelper.compositionend())), this._register(L(this.textarea, "input", (e) => this._inputEvent(e), true)), this._register(this.onRender(() => this._compositionHelper.updateCompositionElements()));
        }
        open(e) {
          if (!e) throw new Error("Terminal requires a parent element.");
          if (e.isConnected || this._logService.debug("Terminal.open was called on an element that was not attached to the DOM"), this.element?.ownerDocument.defaultView && this._coreBrowserService) {
            this.element.ownerDocument.defaultView !== this._coreBrowserService.window && (this._coreBrowserService.window = this.element.ownerDocument.defaultView);
            return;
          }
          this._document = e.ownerDocument, this.options.documentOverride && this.options.documentOverride instanceof Document && (this._document = this.optionsService.rawOptions.documentOverride), this.element = this._document.createElement("div"), this.element.dir = "ltr", this.element.classList.add("terminal"), this.element.classList.add("xterm"), e.appendChild(this.element);
          let i = this._document.createDocumentFragment();
          this._viewportElement = this._document.createElement("div"), this._viewportElement.classList.add("xterm-viewport"), i.appendChild(this._viewportElement), this.screenElement = this._document.createElement("div"), this.screenElement.classList.add("xterm-screen"), this._register(L(this.screenElement, "mousemove", (o2) => this.updateCursorStyle(o2))), this._helperContainer = this._document.createElement("div"), this._helperContainer.classList.add("xterm-helpers"), this.screenElement.appendChild(this._helperContainer), i.appendChild(this.screenElement);
          let r = this.textarea = this._document.createElement("textarea");
          this.textarea.classList.add("xterm-helper-textarea"), this.textarea.setAttribute("aria-label", mi.get()), Ts || this.textarea.setAttribute("aria-multiline", "false"), this.textarea.setAttribute("autocorrect", "off"), this.textarea.setAttribute("autocapitalize", "off"), this.textarea.setAttribute("spellcheck", "false"), this.textarea.tabIndex = 0, this._register(this.optionsService.onSpecificOptionChange("disableStdin", () => r.readOnly = this.optionsService.rawOptions.disableStdin)), this.textarea.readOnly = this.optionsService.rawOptions.disableStdin, this._coreBrowserService = this._register(this._instantiationService.createInstance(Jr, this.textarea, e.ownerDocument.defaultView ?? window, this._document ?? typeof window < "u" ? window.document : null)), this._instantiationService.setService(ae, this._coreBrowserService), this._register(L(this.textarea, "focus", (o2) => this._handleTextAreaFocus(o2))), this._register(L(this.textarea, "blur", () => this._handleTextAreaBlur())), this._helperContainer.appendChild(this.textarea), this._charSizeService = this._instantiationService.createInstance(jt, this._document, this._helperContainer), this._instantiationService.setService(nt, this._charSizeService), this._themeService = this._instantiationService.createInstance(ti), this._instantiationService.setService(Re, this._themeService), this._characterJoinerService = this._instantiationService.createInstance(ct), this._instantiationService.setService(or, this._characterJoinerService), this._renderService = this._register(this._instantiationService.createInstance(Qt, this.rows, this.screenElement)), this._instantiationService.setService(ce, this._renderService), this._register(this._renderService.onRenderedViewportChange((o2) => this._onRender.fire(o2))), this.onResize((o2) => this._renderService.resize(o2.cols, o2.rows)), this._compositionView = this._document.createElement("div"), this._compositionView.classList.add("composition-view"), this._compositionHelper = this._instantiationService.createInstance($t, this.textarea, this._compositionView), this._helperContainer.appendChild(this._compositionView), this._mouseService = this._instantiationService.createInstance(Xt), this._instantiationService.setService(Dt, this._mouseService);
          let n = this._linkifier.value = this._register(this._instantiationService.createInstance(hi, this.screenElement));
          this.element.appendChild(i);
          try {
            this._onWillOpen.fire(this.element);
          } catch {
          }
          this._renderService.hasRenderer() || this._renderService.setRenderer(this._createRenderer()), this._register(this.onCursorMove(() => {
            this._renderService.handleCursorMove(), this._syncTextArea();
          })), this._register(this.onResize(() => this._renderService.handleResize(this.cols, this.rows))), this._register(this.onBlur(() => this._renderService.handleBlur())), this._register(this.onFocus(() => this._renderService.handleFocus())), this._viewport = this._register(this._instantiationService.createInstance(zt, this.element, this.screenElement)), this._register(this._viewport.onRequestScrollLines((o2) => {
            super.scrollLines(o2, false), this.refresh(0, this.rows - 1);
          })), this._selectionService = this._register(this._instantiationService.createInstance(ei, this.element, this.screenElement, n)), this._instantiationService.setService(Qs, this._selectionService), this._register(this._selectionService.onRequestScrollLines((o2) => this.scrollLines(o2.amount, o2.suppressScrollEvent))), this._register(this._selectionService.onSelectionChange(() => this._onSelectionChange.fire())), this._register(this._selectionService.onRequestRedraw((o2) => this._renderService.handleSelectionChanged(o2.start, o2.end, o2.columnSelectMode))), this._register(this._selectionService.onLinuxMouseSelection((o2) => {
            this.textarea.value = o2, this.textarea.focus(), this.textarea.select();
          })), this._register($.any(this._onScroll.event, this._inputHandler.onScroll)(() => {
            this._selectionService.refresh(), this._viewport?.queueSync();
          })), this._register(this._instantiationService.createInstance(Gt, this.screenElement)), this._register(L(this.element, "mousedown", (o2) => this._selectionService.handleMouseDown(o2))), this.coreMouseService.areMouseEventsActive ? (this._selectionService.disable(), this.element.classList.add("enable-mouse-events")) : this._selectionService.enable(), this.options.screenReaderMode && (this._accessibilityManager.value = this._instantiationService.createInstance(Tt, this)), this._register(this.optionsService.onSpecificOptionChange("screenReaderMode", (o2) => this._handleScreenReaderModeOptionChange(o2))), this.options.overviewRuler.width && (this._overviewRulerRenderer = this._register(this._instantiationService.createInstance(bt, this._viewportElement, this.screenElement))), this.optionsService.onSpecificOptionChange("overviewRuler", (o2) => {
            !this._overviewRulerRenderer && o2 && this._viewportElement && this.screenElement && (this._overviewRulerRenderer = this._register(this._instantiationService.createInstance(bt, this._viewportElement, this.screenElement)));
          }), this._charSizeService.measure(), this.refresh(0, this.rows - 1), this._initGlobal(), this.bindMouse();
        }
        _createRenderer() {
          return this._instantiationService.createInstance(Yt, this, this._document, this.element, this.screenElement, this._viewportElement, this._helperContainer, this.linkifier);
        }
        bindMouse() {
          let e = this, i = this.element;
          function r(l2) {
            let a = e._mouseService.getMouseReportCoords(l2, e.screenElement);
            if (!a) return false;
            let u, h2;
            switch (l2.overrideType || l2.type) {
              case "mousemove":
                h2 = 32, l2.buttons === void 0 ? (u = 3, l2.button !== void 0 && (u = l2.button < 3 ? l2.button : 3)) : u = l2.buttons & 1 ? 0 : l2.buttons & 4 ? 1 : l2.buttons & 2 ? 2 : 3;
                break;
              case "mouseup":
                h2 = 0, u = l2.button < 3 ? l2.button : 3;
                break;
              case "mousedown":
                h2 = 1, u = l2.button < 3 ? l2.button : 3;
                break;
              case "wheel":
                if (e._customWheelEventHandler && e._customWheelEventHandler(l2) === false) return false;
                let c = l2.deltaY;
                if (c === 0 || e.coreMouseService.consumeWheelEvent(l2, e._renderService?.dimensions?.device?.cell?.height, e._coreBrowserService?.dpr) === 0) return false;
                h2 = c < 0 ? 0 : 1, u = 4;
                break;
              default:
                return false;
            }
            return h2 === void 0 || u === void 0 || u > 4 ? false : e.coreMouseService.triggerMouseEvent({ col: a.col, row: a.row, x: a.x, y: a.y, button: u, action: h2, ctrl: l2.ctrlKey, alt: l2.altKey, shift: l2.shiftKey });
          }
          let n = { mouseup: null, wheel: null, mousedrag: null, mousemove: null }, o2 = { mouseup: (l2) => (r(l2), l2.buttons || (this._document.removeEventListener("mouseup", n.mouseup), n.mousedrag && this._document.removeEventListener("mousemove", n.mousedrag)), this.cancel(l2)), wheel: (l2) => (r(l2), this.cancel(l2, true)), mousedrag: (l2) => {
            l2.buttons && r(l2);
          }, mousemove: (l2) => {
            l2.buttons || r(l2);
          } };
          this._register(this.coreMouseService.onProtocolChange((l2) => {
            l2 ? (this.optionsService.rawOptions.logLevel === "debug" && this._logService.debug("Binding to mouse events:", this.coreMouseService.explainEvents(l2)), this.element.classList.add("enable-mouse-events"), this._selectionService.disable()) : (this._logService.debug("Unbinding from mouse events."), this.element.classList.remove("enable-mouse-events"), this._selectionService.enable()), l2 & 8 ? n.mousemove || (i.addEventListener("mousemove", o2.mousemove), n.mousemove = o2.mousemove) : (i.removeEventListener("mousemove", n.mousemove), n.mousemove = null), l2 & 16 ? n.wheel || (i.addEventListener("wheel", o2.wheel, { passive: false }), n.wheel = o2.wheel) : (i.removeEventListener("wheel", n.wheel), n.wheel = null), l2 & 2 ? n.mouseup || (n.mouseup = o2.mouseup) : (this._document.removeEventListener("mouseup", n.mouseup), n.mouseup = null), l2 & 4 ? n.mousedrag || (n.mousedrag = o2.mousedrag) : (this._document.removeEventListener("mousemove", n.mousedrag), n.mousedrag = null);
          })), this.coreMouseService.activeProtocol = this.coreMouseService.activeProtocol, this._register(L(i, "mousedown", (l2) => {
            if (l2.preventDefault(), this.focus(), !(!this.coreMouseService.areMouseEventsActive || this._selectionService.shouldForceSelection(l2))) return r(l2), n.mouseup && this._document.addEventListener("mouseup", n.mouseup), n.mousedrag && this._document.addEventListener("mousemove", n.mousedrag), this.cancel(l2);
          })), this._register(L(i, "wheel", (l2) => {
            if (!n.wheel) {
              if (this._customWheelEventHandler && this._customWheelEventHandler(l2) === false) return false;
              if (!this.buffer.hasScrollback) {
                if (l2.deltaY === 0) return false;
                if (e.coreMouseService.consumeWheelEvent(l2, e._renderService?.dimensions?.device?.cell?.height, e._coreBrowserService?.dpr) === 0) return this.cancel(l2, true);
                let h2 = b.ESC + (this.coreService.decPrivateModes.applicationCursorKeys ? "O" : "[") + (l2.deltaY < 0 ? "A" : "B");
                return this.coreService.triggerDataEvent(h2, true), this.cancel(l2, true);
              }
            }
          }, { passive: false }));
        }
        refresh(e, i) {
          this._renderService?.refreshRows(e, i);
        }
        updateCursorStyle(e) {
          this._selectionService?.shouldColumnSelect(e) ? this.element.classList.add("column-select") : this.element.classList.remove("column-select");
        }
        _showCursor() {
          this.coreService.isCursorInitialized || (this.coreService.isCursorInitialized = true, this.refresh(this.buffer.y, this.buffer.y));
        }
        scrollLines(e, i) {
          this._viewport ? this._viewport.scrollLines(e) : super.scrollLines(e, i), this.refresh(0, this.rows - 1);
        }
        scrollPages(e) {
          this.scrollLines(e * (this.rows - 1));
        }
        scrollToTop() {
          this.scrollLines(-this._bufferService.buffer.ydisp);
        }
        scrollToBottom(e) {
          e && this._viewport ? this._viewport.scrollToLine(this.buffer.ybase, true) : this.scrollLines(this._bufferService.buffer.ybase - this._bufferService.buffer.ydisp);
        }
        scrollToLine(e) {
          let i = e - this._bufferService.buffer.ydisp;
          i !== 0 && this.scrollLines(i);
        }
        paste(e) {
          Cn(e, this.textarea, this.coreService, this.optionsService);
        }
        attachCustomKeyEventHandler(e) {
          this._customKeyEventHandler = e;
        }
        attachCustomWheelEventHandler(e) {
          this._customWheelEventHandler = e;
        }
        registerLinkProvider(e) {
          return this._linkProviderService.registerLinkProvider(e);
        }
        registerCharacterJoiner(e) {
          if (!this._characterJoinerService) throw new Error("Terminal must be opened first");
          let i = this._characterJoinerService.register(e);
          return this.refresh(0, this.rows - 1), i;
        }
        deregisterCharacterJoiner(e) {
          if (!this._characterJoinerService) throw new Error("Terminal must be opened first");
          this._characterJoinerService.deregister(e) && this.refresh(0, this.rows - 1);
        }
        get markers() {
          return this.buffer.markers;
        }
        registerMarker(e) {
          return this.buffer.addMarker(this.buffer.ybase + this.buffer.y + e);
        }
        registerDecoration(e) {
          return this._decorationService.registerDecoration(e);
        }
        hasSelection() {
          return this._selectionService ? this._selectionService.hasSelection : false;
        }
        select(e, i, r) {
          this._selectionService.setSelection(e, i, r);
        }
        getSelection() {
          return this._selectionService ? this._selectionService.selectionText : "";
        }
        getSelectionPosition() {
          if (!(!this._selectionService || !this._selectionService.hasSelection)) return { start: { x: this._selectionService.selectionStart[0], y: this._selectionService.selectionStart[1] }, end: { x: this._selectionService.selectionEnd[0], y: this._selectionService.selectionEnd[1] } };
        }
        clearSelection() {
          this._selectionService?.clearSelection();
        }
        selectAll() {
          this._selectionService?.selectAll();
        }
        selectLines(e, i) {
          this._selectionService?.selectLines(e, i);
        }
        _keyDown(e) {
          if (this._keyDownHandled = false, this._keyDownSeen = true, this._customKeyEventHandler && this._customKeyEventHandler(e) === false) return false;
          let i = this.browser.isMac && this.options.macOptionIsMeta && e.altKey;
          if (!i && !this._compositionHelper.keydown(e)) return this.options.scrollOnUserInput && this.buffer.ybase !== this.buffer.ydisp && this.scrollToBottom(true), false;
          !i && (e.key === "Dead" || e.key === "AltGraph") && (this._unprocessedDeadKey = true);
          let r = Il(e, this.coreService.decPrivateModes.applicationCursorKeys, this.browser.isMac, this.options.macOptionIsMeta);
          if (this.updateCursorStyle(e), r.type === 3 || r.type === 2) {
            let n = this.rows - 1;
            return this.scrollLines(r.type === 2 ? -n : n), this.cancel(e, true);
          }
          if (r.type === 1 && this.selectAll(), this._isThirdLevelShift(this.browser, e) || (r.cancel && this.cancel(e, true), !r.key) || e.key && !e.ctrlKey && !e.altKey && !e.metaKey && e.key.length === 1 && e.key.charCodeAt(0) >= 65 && e.key.charCodeAt(0) <= 90) return true;
          if (this._unprocessedDeadKey) return this._unprocessedDeadKey = false, true;
          if ((r.key === b.ETX || r.key === b.CR) && (this.textarea.value = ""), this._onKey.fire({ key: r.key, domEvent: e }), this._showCursor(), this.coreService.triggerDataEvent(r.key, true), !this.optionsService.rawOptions.screenReaderMode || e.altKey || e.ctrlKey) return this.cancel(e, true);
          this._keyDownHandled = true;
        }
        _isThirdLevelShift(e, i) {
          let r = e.isMac && !this.options.macOptionIsMeta && i.altKey && !i.ctrlKey && !i.metaKey || e.isWindows && i.altKey && i.ctrlKey && !i.metaKey || e.isWindows && i.getModifierState("AltGraph");
          return i.type === "keypress" ? r : r && (!i.keyCode || i.keyCode > 47);
        }
        _keyUp(e) {
          this._keyDownSeen = false, !(this._customKeyEventHandler && this._customKeyEventHandler(e) === false) && (Tc(e) || this.focus(), this.updateCursorStyle(e), this._keyPressHandled = false);
        }
        _keyPress(e) {
          let i;
          if (this._keyPressHandled = false, this._keyDownHandled || this._customKeyEventHandler && this._customKeyEventHandler(e) === false) return false;
          if (this.cancel(e), e.charCode) i = e.charCode;
          else if (e.which === null || e.which === void 0) i = e.keyCode;
          else if (e.which !== 0 && e.charCode !== 0) i = e.which;
          else return false;
          return !i || (e.altKey || e.ctrlKey || e.metaKey) && !this._isThirdLevelShift(this.browser, e) ? false : (i = String.fromCharCode(i), this._onKey.fire({ key: i, domEvent: e }), this._showCursor(), this.coreService.triggerDataEvent(i, true), this._keyPressHandled = true, this._unprocessedDeadKey = false, true);
        }
        _inputEvent(e) {
          if (e.data && e.inputType === "insertText" && (!e.composed || !this._keyDownSeen) && !this.optionsService.rawOptions.screenReaderMode) {
            if (this._keyPressHandled) return false;
            this._unprocessedDeadKey = false;
            let i = e.data;
            return this.coreService.triggerDataEvent(i, true), this.cancel(e), true;
          }
          return false;
        }
        resize(e, i) {
          if (e === this.cols && i === this.rows) {
            this._charSizeService && !this._charSizeService.hasValidSize && this._charSizeService.measure();
            return;
          }
          super.resize(e, i);
        }
        _afterResize(e, i) {
          this._charSizeService?.measure();
        }
        clear() {
          if (!(this.buffer.ybase === 0 && this.buffer.y === 0)) {
            this.buffer.clearAllMarkers(), this.buffer.lines.set(0, this.buffer.lines.get(this.buffer.ybase + this.buffer.y)), this.buffer.lines.length = 1, this.buffer.ydisp = 0, this.buffer.ybase = 0, this.buffer.y = 0;
            for (let e = 1; e < this.rows; e++) this.buffer.lines.push(this.buffer.getBlankLine(X));
            this._onScroll.fire({ position: this.buffer.ydisp }), this.refresh(0, this.rows - 1);
          }
        }
        reset() {
          this.options.rows = this.rows, this.options.cols = this.cols;
          let e = this._customKeyEventHandler;
          this._setup(), super.reset(), this._selectionService?.reset(), this._decorationService.reset(), this._customKeyEventHandler = e, this.refresh(0, this.rows - 1);
        }
        clearTextureAtlas() {
          this._renderService?.clearTextureAtlas();
        }
        _reportFocus() {
          this.element?.classList.contains("focus") ? this.coreService.triggerDataEvent(b.ESC + "[I") : this.coreService.triggerDataEvent(b.ESC + "[O");
        }
        _reportWindowsOptions(e) {
          if (this._renderService) switch (e) {
            case 0:
              let i = this._renderService.dimensions.css.canvas.width.toFixed(0), r = this._renderService.dimensions.css.canvas.height.toFixed(0);
              this.coreService.triggerDataEvent(`${b.ESC}[4;${r};${i}t`);
              break;
            case 1:
              let n = this._renderService.dimensions.css.cell.width.toFixed(0), o2 = this._renderService.dimensions.css.cell.height.toFixed(0);
              this.coreService.triggerDataEvent(`${b.ESC}[6;${o2};${n}t`);
              break;
          }
        }
        cancel(e, i) {
          if (!(!this.options.cancelEvents && !i)) return e.preventDefault(), e.stopPropagation(), false;
        }
      };
      xn = class {
        constructor() {
          this._addons = [];
        }
        dispose() {
          for (let t = this._addons.length - 1; t >= 0; t--) this._addons[t].instance.dispose();
        }
        loadAddon(t, e) {
          let i = { instance: e, dispose: e.dispose, isDisposed: false };
          this._addons.push(i), e.dispose = () => this._wrappedAddonDispose(i), e.activate(t);
        }
        _wrappedAddonDispose(t) {
          if (t.isDisposed) return;
          let e = -1;
          for (let i = 0; i < this._addons.length; i++) if (this._addons[i] === t) {
            e = i;
            break;
          }
          if (e === -1) throw new Error("Could not dispose an addon that has not been loaded");
          t.isDisposed = true, t.dispose.apply(t.instance), this._addons.splice(e, 1);
        }
      };
      wn = class {
        constructor(t) {
          this._line = t;
        }
        get isWrapped() {
          return this._line.isWrapped;
        }
        get length() {
          return this._line.length;
        }
        getCell(t, e) {
          if (!(t < 0 || t >= this._line.length)) return e ? (this._line.loadCell(t, e), e) : this._line.loadCell(t, new q());
        }
        translateToString(t, e, i) {
          return this._line.translateToString(t, e, i);
        }
      };
      Ji = class {
        constructor(t, e) {
          this._buffer = t;
          this.type = e;
        }
        init(t) {
          return this._buffer = t, this;
        }
        get cursorY() {
          return this._buffer.y;
        }
        get cursorX() {
          return this._buffer.x;
        }
        get viewportY() {
          return this._buffer.ydisp;
        }
        get baseY() {
          return this._buffer.ybase;
        }
        get length() {
          return this._buffer.lines.length;
        }
        getLine(t) {
          let e = this._buffer.lines.get(t);
          if (e) return new wn(e);
        }
        getNullCell() {
          return new q();
        }
      };
      Dn = class extends D {
        constructor(e) {
          super();
          this._core = e;
          this._onBufferChange = this._register(new v());
          this.onBufferChange = this._onBufferChange.event;
          this._normal = new Ji(this._core.buffers.normal, "normal"), this._alternate = new Ji(this._core.buffers.alt, "alternate"), this._core.buffers.onBufferActivate(() => this._onBufferChange.fire(this.active));
        }
        get active() {
          if (this._core.buffers.active === this._core.buffers.normal) return this.normal;
          if (this._core.buffers.active === this._core.buffers.alt) return this.alternate;
          throw new Error("Active buffer is neither normal nor alternate");
        }
        get normal() {
          return this._normal.init(this._core.buffers.normal);
        }
        get alternate() {
          return this._alternate.init(this._core.buffers.alt);
        }
      };
      Rn = class {
        constructor(t) {
          this._core = t;
        }
        registerCsiHandler(t, e) {
          return this._core.registerCsiHandler(t, (i) => e(i.toArray()));
        }
        addCsiHandler(t, e) {
          return this.registerCsiHandler(t, e);
        }
        registerDcsHandler(t, e) {
          return this._core.registerDcsHandler(t, (i, r) => e(i, r.toArray()));
        }
        addDcsHandler(t, e) {
          return this.registerDcsHandler(t, e);
        }
        registerEscHandler(t, e) {
          return this._core.registerEscHandler(t, e);
        }
        addEscHandler(t, e) {
          return this.registerEscHandler(t, e);
        }
        registerOscHandler(t, e) {
          return this._core.registerOscHandler(t, e);
        }
        addOscHandler(t, e) {
          return this.registerOscHandler(t, e);
        }
      };
      Ln = class {
        constructor(t) {
          this._core = t;
        }
        register(t) {
          this._core.unicodeService.register(t);
        }
        get versions() {
          return this._core.unicodeService.versions;
        }
        get activeVersion() {
          return this._core.unicodeService.activeVersion;
        }
        set activeVersion(t) {
          this._core.unicodeService.activeVersion = t;
        }
      };
      Ic = ["cols", "rows"];
      Ue = 0;
      Dl = class extends D {
        constructor(t) {
          super(), this._core = this._register(new yn(t)), this._addonManager = this._register(new xn()), this._publicOptions = { ...this._core.options };
          let e = (r) => this._core.options[r], i = (r, n) => {
            this._checkReadonlyOptions(r), this._core.options[r] = n;
          };
          for (let r in this._core.options) {
            let n = { get: e.bind(this, r), set: i.bind(this, r) };
            Object.defineProperty(this._publicOptions, r, n);
          }
        }
        _checkReadonlyOptions(t) {
          if (Ic.includes(t)) throw new Error(`Option "${t}" can only be set in the constructor`);
        }
        _checkProposedApi() {
          if (!this._core.optionsService.rawOptions.allowProposedApi) throw new Error("You must set the allowProposedApi option to true to use proposed API");
        }
        get onBell() {
          return this._core.onBell;
        }
        get onBinary() {
          return this._core.onBinary;
        }
        get onCursorMove() {
          return this._core.onCursorMove;
        }
        get onData() {
          return this._core.onData;
        }
        get onKey() {
          return this._core.onKey;
        }
        get onLineFeed() {
          return this._core.onLineFeed;
        }
        get onRender() {
          return this._core.onRender;
        }
        get onResize() {
          return this._core.onResize;
        }
        get onScroll() {
          return this._core.onScroll;
        }
        get onSelectionChange() {
          return this._core.onSelectionChange;
        }
        get onTitleChange() {
          return this._core.onTitleChange;
        }
        get onWriteParsed() {
          return this._core.onWriteParsed;
        }
        get element() {
          return this._core.element;
        }
        get parser() {
          return this._parser || (this._parser = new Rn(this._core)), this._parser;
        }
        get unicode() {
          return this._checkProposedApi(), new Ln(this._core);
        }
        get textarea() {
          return this._core.textarea;
        }
        get rows() {
          return this._core.rows;
        }
        get cols() {
          return this._core.cols;
        }
        get buffer() {
          return this._buffer || (this._buffer = this._register(new Dn(this._core))), this._buffer;
        }
        get markers() {
          return this._checkProposedApi(), this._core.markers;
        }
        get modes() {
          let t = this._core.coreService.decPrivateModes, e = "none";
          switch (this._core.coreMouseService.activeProtocol) {
            case "X10":
              e = "x10";
              break;
            case "VT200":
              e = "vt200";
              break;
            case "DRAG":
              e = "drag";
              break;
            case "ANY":
              e = "any";
              break;
          }
          return { applicationCursorKeysMode: t.applicationCursorKeys, applicationKeypadMode: t.applicationKeypad, bracketedPasteMode: t.bracketedPasteMode, insertMode: this._core.coreService.modes.insertMode, mouseTrackingMode: e, originMode: t.origin, reverseWraparoundMode: t.reverseWraparound, sendFocusMode: t.sendFocus, synchronizedOutputMode: t.synchronizedOutput, wraparoundMode: t.wraparound };
        }
        get options() {
          return this._publicOptions;
        }
        set options(t) {
          for (let e in t) this._publicOptions[e] = t[e];
        }
        blur() {
          this._core.blur();
        }
        focus() {
          this._core.focus();
        }
        input(t, e = true) {
          this._core.input(t, e);
        }
        resize(t, e) {
          this._verifyIntegers(t, e), this._core.resize(t, e);
        }
        open(t) {
          this._core.open(t);
        }
        attachCustomKeyEventHandler(t) {
          this._core.attachCustomKeyEventHandler(t);
        }
        attachCustomWheelEventHandler(t) {
          this._core.attachCustomWheelEventHandler(t);
        }
        registerLinkProvider(t) {
          return this._core.registerLinkProvider(t);
        }
        registerCharacterJoiner(t) {
          return this._checkProposedApi(), this._core.registerCharacterJoiner(t);
        }
        deregisterCharacterJoiner(t) {
          this._checkProposedApi(), this._core.deregisterCharacterJoiner(t);
        }
        registerMarker(t = 0) {
          return this._verifyIntegers(t), this._core.registerMarker(t);
        }
        registerDecoration(t) {
          return this._checkProposedApi(), this._verifyPositiveIntegers(t.x ?? 0, t.width ?? 0, t.height ?? 0), this._core.registerDecoration(t);
        }
        hasSelection() {
          return this._core.hasSelection();
        }
        select(t, e, i) {
          this._verifyIntegers(t, e, i), this._core.select(t, e, i);
        }
        getSelection() {
          return this._core.getSelection();
        }
        getSelectionPosition() {
          return this._core.getSelectionPosition();
        }
        clearSelection() {
          this._core.clearSelection();
        }
        selectAll() {
          this._core.selectAll();
        }
        selectLines(t, e) {
          this._verifyIntegers(t, e), this._core.selectLines(t, e);
        }
        dispose() {
          super.dispose();
        }
        scrollLines(t) {
          this._verifyIntegers(t), this._core.scrollLines(t);
        }
        scrollPages(t) {
          this._verifyIntegers(t), this._core.scrollPages(t);
        }
        scrollToTop() {
          this._core.scrollToTop();
        }
        scrollToBottom() {
          this._core.scrollToBottom();
        }
        scrollToLine(t) {
          this._verifyIntegers(t), this._core.scrollToLine(t);
        }
        clear() {
          this._core.clear();
        }
        write(t, e) {
          this._core.write(t, e);
        }
        writeln(t, e) {
          this._core.write(t), this._core.write(`\r
`, e);
        }
        paste(t) {
          this._core.paste(t);
        }
        refresh(t, e) {
          this._verifyIntegers(t, e), this._core.refresh(t, e);
        }
        reset() {
          this._core.reset();
        }
        clearTextureAtlas() {
          this._core.clearTextureAtlas();
        }
        loadAddon(t) {
          this._addonManager.loadAddon(this, t);
        }
        static get strings() {
          return { get promptLabel() {
            return mi.get();
          }, set promptLabel(t) {
            mi.set(t);
          }, get tooMuchOutput() {
            return _i.get();
          }, set tooMuchOutput(t) {
            _i.set(t);
          } };
        }
        _verifyIntegers(...t) {
          for (Ue of t) if (Ue === 1 / 0 || isNaN(Ue) || Ue % 1 !== 0) throw new Error("This API only accepts integers");
        }
        _verifyPositiveIntegers(...t) {
          for (Ue of t) if (Ue && (Ue === 1 / 0 || isNaN(Ue) || Ue % 1 !== 0 || Ue < 0)) throw new Error("This API only accepts positive integers");
        }
      };
    }
  });

  // node_modules/@xterm/addon-fit/lib/addon-fit.mjs
  var h, _, o;
  var init_addon_fit = __esm({
    "node_modules/@xterm/addon-fit/lib/addon-fit.mjs"() {
      h = 2;
      _ = 1;
      o = class {
        activate(e) {
          this._terminal = e;
        }
        dispose() {
        }
        fit() {
          let e = this.proposeDimensions();
          if (!e || !this._terminal || isNaN(e.cols) || isNaN(e.rows)) return;
          let t = this._terminal._core;
          (this._terminal.rows !== e.rows || this._terminal.cols !== e.cols) && (t._renderService.clear(), this._terminal.resize(e.cols, e.rows));
        }
        proposeDimensions() {
          if (!this._terminal || !this._terminal.element || !this._terminal.element.parentElement) return;
          let t = this._terminal._core._renderService.dimensions;
          if (t.css.cell.width === 0 || t.css.cell.height === 0) return;
          let s15 = this._terminal.options.scrollback === 0 ? 0 : this._terminal.options.overviewRuler?.width || 14, r = window.getComputedStyle(this._terminal.element.parentElement), l2 = parseInt(r.getPropertyValue("height")), a = Math.max(0, parseInt(r.getPropertyValue("width"))), i = window.getComputedStyle(this._terminal.element), n = { top: parseInt(i.getPropertyValue("padding-top")), bottom: parseInt(i.getPropertyValue("padding-bottom")), right: parseInt(i.getPropertyValue("padding-right")), left: parseInt(i.getPropertyValue("padding-left")) }, m = n.top + n.bottom, d = n.right + n.left, c = l2 - m, p = a - d - s15;
          return { cols: Math.max(h, Math.floor(p / t.css.cell.width)), rows: Math.max(_, Math.floor(c / t.css.cell.height)) };
        }
      };
    }
  });

  // node_modules/@xterm/addon-web-links/lib/addon-web-links.mjs
  function k(l2) {
    try {
      let e = new URL(l2), t = e.password && e.username ? `${e.protocol}//${e.username}:${e.password}@${e.host}` : e.username ? `${e.protocol}//${e.username}@${e.host}` : `${e.protocol}//${e.host}`;
      return l2.toLocaleLowerCase().startsWith(t.toLocaleLowerCase());
    } catch {
      return false;
    }
  }
  function w(l2, e) {
    let t = window.open();
    if (t) {
      try {
        t.opener = null;
      } catch {
      }
      t.location.href = e;
    } else console.warn("Opening link blocked as opener could not be cleared");
  }
  var v2, g, _2, L2;
  var init_addon_web_links = __esm({
    "node_modules/@xterm/addon-web-links/lib/addon-web-links.mjs"() {
      v2 = class {
        constructor(e, t, n, o2 = {}) {
          this._terminal = e;
          this._regex = t;
          this._handler = n;
          this._options = o2;
        }
        provideLinks(e, t) {
          let n = g.computeLink(e, this._regex, this._terminal, this._handler);
          t(this._addCallbacks(n));
        }
        _addCallbacks(e) {
          return e.map((t) => (t.leave = this._options.leave, t.hover = (n, o2) => {
            if (this._options.hover) {
              let { range: p } = t;
              this._options.hover(n, o2, p);
            }
          }, t));
        }
      };
      g = class l {
        static computeLink(e, t, n, o2) {
          let p = new RegExp(t.source, (t.flags || "") + "g"), [i, r] = l._getWindowedLineStrings(e - 1, n), s15 = i.join(""), a, d = [];
          for (; a = p.exec(s15); ) {
            let u = a[0];
            if (!k(u)) continue;
            let [c, h2] = l._mapStrIdx(n, r, 0, a.index), [m, f] = l._mapStrIdx(n, c, h2, u.length);
            if (c === -1 || h2 === -1 || m === -1 || f === -1) continue;
            let b2 = { start: { x: h2 + 1, y: c + 1 }, end: { x: f, y: m + 1 } };
            d.push({ range: b2, text: u, activate: o2 });
          }
          return d;
        }
        static _getWindowedLineStrings(e, t) {
          let n, o2 = e, p = e, i = 0, r = "", s15 = [];
          if (n = t.buffer.active.getLine(e)) {
            let a = n.translateToString(true);
            if (n.isWrapped && a[0] !== " ") {
              for (i = 0; (n = t.buffer.active.getLine(--o2)) && i < 2048 && (r = n.translateToString(true), i += r.length, s15.push(r), !(!n.isWrapped || r.indexOf(" ") !== -1)); ) ;
              s15.reverse();
            }
            for (s15.push(a), i = 0; (n = t.buffer.active.getLine(++p)) && n.isWrapped && i < 2048 && (r = n.translateToString(true), i += r.length, s15.push(r), r.indexOf(" ") === -1); ) ;
          }
          return [s15, o2];
        }
        static _mapStrIdx(e, t, n, o2) {
          let p = e.buffer.active, i = p.getNullCell(), r = n;
          for (; o2; ) {
            let s15 = p.getLine(t);
            if (!s15) return [-1, -1];
            for (let a = r; a < s15.length; ++a) {
              s15.getCell(a, i);
              let d = i.getChars();
              if (i.getWidth() && (o2 -= d.length || 1, a === s15.length - 1 && d === "")) {
                let c = p.getLine(t + 1);
                c && c.isWrapped && (c.getCell(0, i), i.getWidth() === 2 && (o2 += 1));
              }
              if (o2 < 0) return [t, a];
            }
            t++, r = 0;
          }
          return [t, r];
        }
      };
      _2 = /(https?|HTTPS?):[/]{2}[^\s"'!*(){}|\\\^<>`]*[^\s"':,.!?{}|\\\^~\[\]`()<>]/;
      L2 = class {
        constructor(e = w, t = {}) {
          this._handler = e;
          this._options = t;
        }
        activate(e) {
          this._terminal = e;
          let t = this._options, n = t.urlRegex || _2;
          this._linkProvider = this._terminal.registerLinkProvider(new v2(this._terminal, n, this._handler, t));
        }
        dispose() {
          this._linkProvider?.dispose();
        }
      };
    }
  });

  // js/app.js
  var require_app = __commonJS({
    "js/app.js"() {
      init_phoenix_html();
      var import_phoenix = __toESM(require_phoenix_cjs());
      init_phoenix_live_view_esm();
      init_xterm();
      init_addon_fit();
      init_addon_web_links();
      var Hooks2 = {};
      Hooks2.Terminal = {
        mounted() {
          const paneId = this.el.dataset.paneId;
          const term = new Dl({
            cursorBlink: true,
            fontSize: 14,
            fontFamily: "'JetBrains Mono', 'Fira Code', 'Cascadia Code', monospace",
            theme: {
              background: "#1a1a2e",
              foreground: "#e0e0e0",
              cursor: "#64b5f6"
            }
          });
          const fitAddon = new o();
          term.loadAddon(fitAddon);
          term.loadAddon(new L2());
          term.open(this.el);
          fitAddon.fit();
          const socket = new import_phoenix.Socket("/socket", {});
          socket.connect();
          const channel = socket.channel(`terminal:${paneId}`, {});
          channel.on("output", ({ data }) => {
            term.write(data);
          });
          channel.join().receive("ok", ({ initial_content }) => {
            if (initial_content) {
              term.write(initial_content);
            }
          }).receive("error", (resp) => {
            term.write(`\r
\x1B[31mError connecting to pane: ${JSON.stringify(resp)}\x1B[0m\r
`);
          });
          term.onData((data) => {
            channel.push("input", { data });
          });
          term.onResize(({ cols, rows }) => {
            channel.push("resize", { cols, rows });
          });
          window.addEventListener("resize", () => fitAddon.fit());
          this._term = term;
          this._channel = channel;
          this._socket = socket;
          this._fitAddon = fitAddon;
        },
        destroyed() {
          if (this._channel) this._channel.leave();
          if (this._socket) this._socket.disconnect();
          if (this._term) this._term.dispose();
        }
      };
      var csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
      var liveSocket = new LiveSocket2("/live", import_phoenix.Socket, {
        hooks: Hooks2,
        params: { _csrf_token: csrfToken }
      });
      liveSocket.connect();
      window.liveSocket = liveSocket;
    }
  });
  require_app();
})();
/*! Bundled license information:

@xterm/xterm/lib/xterm.mjs:
@xterm/addon-fit/lib/addon-fit.mjs:
@xterm/addon-web-links/lib/addon-web-links.mjs:
  (**
   * Copyright (c) 2014-2024 The xterm.js authors. All rights reserved.
   * @license MIT
   *
   * Copyright (c) 2012-2013, Christopher Jeffrey (MIT License)
   * @license MIT
   *
   * Originally forked from (with the author's permission):
   *   Fabrice Bellard's javascript vt100 for jslinux:
   *   http://bellard.org/jslinux/
   *   Copyright (c) 2011 Fabrice Bellard
   *)
*/
