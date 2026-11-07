/*
 * TapSulor iOS — 原生桥（WKWebView 版）
 *
 * 在 WKWebView 文档开始时注入，提供与 Android 版（GeckoView）签名完全一致的 window.AndroidBridge。
 * 随后页面里的 android-bridge.js 会把它包装成 window.electronAPI，
 * 因此 js/main.js、js/detail.js 不需要任何改动。
 *
 * 通道约定
 *   JS -> Swift：window.webkit.messageHandlers.tapsulor.postMessage({ op, ...参数 })
 *   Swift -> JS：
 *     window.__pendingFetchResolve(seq, json)     fetch 的结果
 *     window.__pendingReplayResolve(seq, json)    replayApi 的结果
 *     window.__pendingLoginResolve(json)          checkLogin 的结果（每次请求只回一次）
 *     window.__pendingReplayKeyResolve(json)      replayKeyApis 的结果
 *     window.__setNativeState(obj)                账号 / 工作室 / 版本号的缓存
 *     window.__onLoginSuccess() / __onLoginCheck() / __onAccountUpdated(obj)
 *     window.__onStudioSwitched(id) / __onAppResume() / __onAppBackgroundTick()
 *
 * Android 上这些同步方法会直接返回值；WKWebView 无法同步取值，
 * 因此同步方法读取 Swift 推送过来的 window.__nativeState 缓存。
 */
(function () {
  "use strict";
  if (window.AndroidBridge) return;

  window.__iosBridgeVersion = "1.0.5-ios";

  var defaults = { current: null, accounts: [], studios: [], activeDeveloperId: null, appVersion: "" };
  window.__nativeState = window.__nativeState || {};
  for (var key in defaults) {
    if (!(key in window.__nativeState)) window.__nativeState[key] = defaults[key];
  }

  function state() {
    return window.__nativeState;
  }

  // Swift 调用：合并推送过来的状态
  window.__setNativeState = function (partial) {
    if (!partial || typeof partial !== "object") return;
    for (var k in partial) {
      if (Object.prototype.hasOwnProperty.call(partial, k)) state()[k] = partial[k];
    }
  };

  function post(op, payload) {
    var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tapsulor;
    if (!handler) {
      console.warn("[ios-bridge] 没有原生消息通道，已忽略：" + op);
      return;
    }
    var msg = { op: op };
    if (payload) {
      for (var k in payload) {
        if (Object.prototype.hasOwnProperty.call(payload, k)) msg[k] = payload[k];
      }
    }
    handler.postMessage(msg);
  }

  window.AndroidBridge = {
    isIOS: true,

    // ---- 网络（异步，结果经 __pending*Resolve 返回）----
    fetch: function (seq, url) {
      post("fetch", { seq: seq, url: String(url) });
    },
    replayApi: function (seq, url) {
      post("replayApi", { seq: seq, url: String(url) });
    },
    replayKeyApis: function () {
      post("replayKeyApis");
    },

    // ---- 登录与账号 ----
    checkLogin: function () {
      post("checkLogin");
    },
    openLogin: function (mode) {
      post("openLogin", { mode: mode || null });
    },
    getDeveloperId: function () {
      return state().activeDeveloperId || null;
    },
    getActiveDeveloperId: function () {
      return state().activeDeveloperId || null;
    },
    getStudios: function () {
      return JSON.stringify(state().studios || []);
    },
    switchStudio: function (developerId) {
      post("switchStudio", { developerId: String(developerId) });
      return true;
    },
    getAccounts: function () {
      return JSON.stringify({ current: state().current || null, accounts: state().accounts || [] });
    },
    switchAccount: function (id) {
      post("switchAccount", { id: String(id) });
      return true;
    },
    addAccount: function (name, developerId) {
      post("addAccount", { name: String(name || ""), developerId: String(developerId || "") });
    },
    removeAccount: function (id) {
      // 先乐观更新缓存（页面紧接着会重绘账号列表），Swift 随后推送权威状态
      var list = (state().accounts || []).slice();
      var idx = -1;
      for (var i = 0; i < list.length; i++) {
        if (list[i].id === id) {
          idx = i;
          break;
        }
      }
      if (idx < 0) return false;
      list.splice(idx, 1);
      state().accounts = list;
      post("removeAccount", { id: String(id) });
      return true;
    },

    // ---- 其它 ----
    openExplorer: function () {
      // iOS 没有对应的文件管理器入口，保持空实现
    },
    openGameBackend: function (appId, name) {
      post("openGameBackend", { appId: String(appId || ""), name: String(name || "") });
    },
    getCapturedApis: function () {
      return "[]";
    },
    clearCapturedApis: function () {},
    checkUpdate: function () {
      post("checkUpdate");
    },
    getAppVersion: function () {
      return String(state().appVersion || "");
    },
    syncPreferences: function (mode, accent, font) {
      post("syncPreferences", { mode: mode || "light", accent: accent || "cyan", font: font || "default" });
    }
  };
})();
