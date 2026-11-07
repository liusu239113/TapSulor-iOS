// 桥接契约测试：在 Node 里加载 ios-bridge.js + 页面自带的 android-bridge.js，
// 检查 window.electronAPI（main.js 实际调用的接口）是否能正确收发 iOS 原生消息。
// 运行：node Tests/bridge-contract-test.mjs
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import assert from "node:assert/strict";

const here = dirname(fileURLToPath(import.meta.url));
const web = join(here, "..", "TapSulor", "Web");
const read = (name) => readFileSync(join(web, name), "utf8");

const posted = [];
const sandbox = {
  console,
  JSON,
  Object,
  Array,
  String,
  Number,
  Promise,
  Math,
  Date,
  setTimeout,
  clearTimeout,
  CustomEvent: class {
    constructor(type) {
      this.type = type;
    }
  },
};
sandbox.window = sandbox;
sandbox.dispatchEvent = () => true;
sandbox.webkit = {
  messageHandlers: {
    tapsulor: { postMessage: (m) => posted.push(JSON.parse(JSON.stringify(m))) },
  },
};
// 与 Swift 在文档开始时注入的初始状态形状一致
sandbox.__nativeState = {
  current: "acc-1",
  accounts: [{ id: "acc-1", name: "A", developerId: "381509" }],
  studios: [{ id: "381509", name: "A", logo: "" }],
  activeDeveloperId: "381509",
  appVersion: "1.0.5",
};

const ctx = vm.createContext(sandbox);
vm.runInContext(read("ios-bridge.js"), ctx, { filename: "ios-bridge.js" });
vm.runInContext(read("android-bridge.js"), ctx, { filename: "android-bridge.js" });

const api = ctx.electronAPI;
const tests = [];
const check = (name, fn) => tests.push({ name, fn });
const lastOp = () => posted[posted.length - 1];
// vm 上下文里创建的对象与宿主 Object 原型不同，断言前转成普通对象
const plain = (v) => JSON.parse(JSON.stringify(v));

check("electronAPI 已安装，版本号来自原生状态", () => {
  assert.equal(api.isElectron, true);
  assert.equal(api.getAppVersion(), "1.0.5");
});

check("同步读取走原生状态缓存，并能被推送更新", async () => {
  assert.equal(await api.getDeveloperId(), "381509");
  assert.equal(JSON.parse(ctx.AndroidBridge.getAccounts()).current, "acc-1");
  assert.equal((await api.getStudios()).length, 1);
  ctx.__setNativeState({ activeDeveloperId: "999" });
  assert.equal(await api.getDeveloperId(), "999");
});

check("fetch 发出 fetch 消息，并由 __pendingFetchResolve 完成", async () => {
  posted.length = 0;
  const p = api.fetch("https://developer.taptap.cn/api/app/v2/list?developer_id=381509");
  assert.equal(lastOp().op, "fetch");
  assert.equal(typeof lastOp().seq, "number");
  ctx.__pendingFetchResolve(lastOp().seq, JSON.stringify({ ok: true, status: 200, body: '{"success":true}', error: null }));
  const r = await p;
  assert.equal(r.status, 200);
  assert.equal(JSON.parse(r.body).success, true);
});

check("checkLogin 每次请求都有且只有一次回应（FIFO 队列）", async () => {
  posted.length = 0;
  const p1 = api.checkLogin();
  const p2 = api.checkLogin();
  assert.equal(posted.filter((m) => m.op === "checkLogin").length, 2);
  ctx.__pendingLoginResolve(JSON.stringify({ status: "ready", developerId: "381509" }));
  ctx.__pendingLoginResolve(JSON.stringify({ status: "unauthenticated" }));
  assert.equal((await p1).status, "ready");
  assert.equal((await p2).status, "unauthenticated");
});

check("replayApi / replayKeyApis 走各自的回调", async () => {
  posted.length = 0;
  const p = api.replayApi("https://developer.taptap.cn/api/x");
  assert.equal(lastOp().op, "replayApi");
  ctx.__pendingReplayResolve(lastOp().seq, JSON.stringify({ ok: false, error: "not_available" }));
  assert.equal((await p).error, "not_available");

  const k = api.replayKeyApis();
  assert.equal(lastOp().op, "replayKeyApis");
  ctx.__pendingReplayKeyResolve(JSON.stringify({ count: 0, saved: false }));
  assert.equal((await k).count, 0);
});

check("openLogin / switchStudio / openGameBackend / checkUpdate 发出正确的 op", () => {
  posted.length = 0;
  api.openLogin("add");
  api.openLogin();
  assert.deepEqual(posted, [
    { op: "openLogin", mode: "add" },
    { op: "openLogin", mode: null },
  ]);
  assert.equal(api.switchStudio("123"), true);
  assert.deepEqual(lastOp(), { op: "switchStudio", developerId: "123" });
  api.openGameBackend("9001", "Demo");
  assert.deepEqual(lastOp(), { op: "openGameBackend", appId: "9001", name: "Demo" });
  api.checkUpdate();
  assert.equal(lastOp().op, "checkUpdate");
});

check("removeAccount 乐观更新缓存并发出消息", () => {
  ctx.__setNativeState({
    accounts: [
      { id: "acc-1", developerId: "381509" },
      { id: "acc-2", developerId: "7" },
    ],
  });
  posted.length = 0;
  assert.deepEqual(plain(api.removeAccount("acc-2")), { ok: true });
  assert.equal(JSON.parse(ctx.AndroidBridge.getAccounts()).accounts.length, 1);
  assert.deepEqual(lastOp(), { op: "removeAccount", id: "acc-2" });
  assert.deepEqual(plain(api.removeAccount("missing")), { ok: false });
});

check("原生回调（__onXxx）能触发页面注册的回调", () => {
  const hits = [];
  api.onLoginSuccess(() => hits.push("success"));
  api.onAccountUpdated((r) => hits.push(r.developerId));
  ctx.__onLoginSuccess();
  ctx.__onAccountUpdated({ developerId: "381509", switched: true });
  assert.deepEqual(hits, ["success", "381509"]);
});

check("采集类接口返回空列表（页面未使用）", () => {
  assert.deepEqual(plain(api.getCapturedApis()), []);
  api.clearCapturedApis();
});

(async () => {
  let failed = 0;
  for (const { name, fn } of tests) {
    try {
      await fn();
      console.log("PASS", name);
    } catch (e) {
      failed++;
      console.log("FAIL", name, "\n     ", e && e.message);
    }
  }
  console.log(failed ? `${failed} 项失败` : `全部 ${tests.length} 项桥接契约检查通过`);
  process.exit(failed ? 1 : 0);
})();
