import Foundation

enum WebAssets {
    static let indexHTML: String = #"""
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="theme-color" content="#08090d">
<title>PhotoNAS</title>
<style>
:root{
  --bg:#08090d;--panel:#111319;--panel2:#171a22;--text:#f2f4fa;--muted:#8a93a8;
  --line:rgba(255,255,255,.08);--header:rgba(8,9,13,.74);
  --accent:#6c8cff;--accent2:#a46bff;--ok:#35d07f;--warn:#ffb02e;--bad:#ff5c5c;
}
@media (prefers-color-scheme: light){
  :root{--bg:#f2f4f9;--panel:#ffffff;--panel2:#f5f7fc;--text:#12151f;--muted:#68708a;
  --line:rgba(15,23,42,.09);--header:rgba(242,244,249,.78);}
}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
html,body{margin:0;padding:0;min-height:100%}
body{background:var(--bg);color:var(--text);font:15px/1.5 -apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC","Helvetica Neue",Arial,sans-serif;-webkit-font-smoothing:antialiased;overscroll-behavior-y:contain}
body.locked{overflow:hidden}
button,a{font-family:inherit}
a{color:var(--accent);text-decoration:none}

.topbar{position:sticky;top:0;z-index:30;background:var(--header);backdrop-filter:saturate(180%) blur(18px);-webkit-backdrop-filter:saturate(180%) blur(18px);border-bottom:1px solid var(--line);padding-top:env(safe-area-inset-top)}
header{display:flex;align-items:center;gap:12px;padding:12px 16px 8px}
.logo{width:38px;height:38px;border-radius:12px;background:linear-gradient(135deg,var(--accent),var(--accent2));display:flex;align-items:center;justify-content:center;font-weight:800;font-size:18px;color:#fff;flex:0 0 auto;box-shadow:0 6px 18px rgba(108,140,255,.32)}
.titles{flex:1 1 auto;min-width:0}
.titles h1{margin:0;font-size:16px;font-weight:650;letter-spacing:.2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.titles p{margin:2px 0 0;font-size:12px;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.actions{display:flex;gap:8px;flex:0 0 auto}
.chip{border:1px solid var(--line);background:var(--panel2);color:var(--text);border-radius:999px;padding:7px 12px;font-size:12.5px;font-weight:550;display:inline-flex;align-items:center;gap:5px;cursor:pointer;transition:transform .16s ease,background .16s ease}
.chip:active{transform:scale(.96)}
.chip.primary{background:linear-gradient(135deg,var(--accent),var(--accent2));border-color:transparent;color:#fff}

.filters{display:flex;align-items:center;gap:10px;padding:4px 16px 12px;overflow-x:auto;scrollbar-width:none}
.filters::-webkit-scrollbar{display:none}
select{appearance:none;background:var(--panel2);color:var(--text);border:1px solid var(--line);border-radius:12px;padding:8px 30px 8px 12px;font-size:13px;font-weight:550;max-width:52vw;background-image:linear-gradient(45deg,transparent 50%,var(--muted) 50%),linear-gradient(135deg,var(--muted) 50%,transparent 50%);background-position:calc(100% - 16px) 52%,calc(100% - 11px) 52%;background-size:5px 5px,5px 5px;background-repeat:no-repeat}
.seg{display:inline-flex;background:var(--panel2);border:1px solid var(--line);border-radius:12px;padding:3px;gap:2px;flex:0 0 auto}
.seg button{border:0;background:transparent;color:var(--muted);font-size:13px;font-weight:600;padding:6px 13px;border-radius:9px;cursor:pointer;transition:background .18s ease,color .18s ease}
.seg button.on{background:var(--panel);color:var(--text);box-shadow:0 1px 6px rgba(0,0,0,.18)}

main{padding:10px 12px calc(28px + env(safe-area-inset-bottom))}
.meta{display:flex;align-items:center;justify-content:space-between;padding:2px 4px 10px;font-size:12px;color:var(--muted);gap:10px}
.meta .dot{width:6px;height:6px;border-radius:50%;background:var(--ok);display:inline-block;margin-right:6px;box-shadow:0 0 0 4px rgba(53,208,127,.12)}

.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(132px,1fr));gap:6px}
@media (max-width:400px){.grid{grid-template-columns:repeat(3,1fr);gap:4px}}
.tile{position:relative;aspect-ratio:1/1;border:0;padding:0;border-radius:12px;overflow:hidden;background:var(--panel2);cursor:pointer;isolation:isolate}
.tile img{width:100%;height:100%;object-fit:cover;display:block;opacity:0;transition:opacity .35s ease,transform .35s ease}
.tile img.ready{opacity:1}
.tile:active img{transform:scale(1.04)}
.tile.loading::after{content:"";position:absolute;inset:0;background:linear-gradient(100deg,transparent 20%,rgba(255,255,255,.07) 40%,transparent 60%);background-size:200% 100%;animation:shimmer 1.3s infinite linear}
@keyframes shimmer{0%{background-position:120% 0}100%{background-position:-60% 0}}
.badge{position:absolute;right:6px;bottom:6px;background:rgba(0,0,0,.62);color:#fff;font-size:11px;font-weight:600;padding:2px 6px;border-radius:6px;backdrop-filter:blur(6px)}
.tag{position:absolute;left:6px;top:6px;background:rgba(0,0,0,.55);color:#fff;font-size:10px;font-weight:700;letter-spacing:.6px;padding:2px 6px;border-radius:6px}
.tag.fav{left:auto;right:6px;top:6px;color:#ff7a9c}

.empty{padding:56px 16px;text-align:center;color:var(--muted);font-size:13.5px}
.spinner{width:26px;height:26px;border-radius:50%;border:2.5px solid var(--line);border-top-color:var(--accent);animation:spin .8s linear infinite;margin:0 auto 12px}
@keyframes spin{to{transform:rotate(360deg)}}

.viewer{position:fixed;inset:0;z-index:60;background:rgba(0,0,0,.94);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);display:flex;flex-direction:column;opacity:0;pointer-events:none;transition:opacity .22s ease}
.viewer.open{opacity:1;pointer-events:auto}
.viewer-top{display:flex;align-items:center;justify-content:space-between;padding:calc(12px + env(safe-area-inset-top)) 14px 8px;gap:10px}
.viewer .chip{background:rgba(255,255,255,.12);border-color:rgba(255,255,255,.18);color:#fff}
.viewer .chip.primary{background:linear-gradient(135deg,var(--accent),var(--accent2))}
.viewer-actions{display:flex;gap:8px}
.viewer-media{flex:1 1 auto;display:flex;align-items:center;justify-content:center;min-height:0;padding:0 8px}
.viewer-media img{max-width:100%;max-height:100%;object-fit:contain;border-radius:6px}
.viewer-media video{max-width:100%;max-height:100%;border-radius:10px;background:#000}
.caption{padding:10px 18px calc(18px + env(safe-area-inset-bottom));color:rgba(255,255,255,.72);font-size:12.5px;text-align:center}

.scrim{position:fixed;inset:0;background:rgba(0,0,0,.5);z-index:40;opacity:0;pointer-events:none;transition:opacity .2s ease}
.scrim.open{opacity:1;pointer-events:auto}
.sheet{position:fixed;left:0;right:0;bottom:0;z-index:50;background:var(--panel);border-radius:20px 20px 0 0;border-top:1px solid var(--line);max-height:80vh;display:flex;flex-direction:column;transform:translateY(102%);transition:transform .28s cubic-bezier(.22,1,.36,1);padding-bottom:env(safe-area-inset-bottom)}
.sheet.open{transform:translateY(0)}
.sheet-head{display:flex;align-items:center;justify-content:space-between;padding:16px 18px 10px}
.sheet-head h3{margin:0;font-size:15.5px;font-weight:650}
.log-list{overflow:auto;-webkit-overflow-scrolling:touch;padding:0 12px 16px}
.log-row{display:grid;grid-template-columns:1fr auto;gap:2px 10px;padding:10px 6px;border-bottom:1px solid var(--line);font-size:12.5px}
.log-row .line1{display:flex;align-items:center;gap:6px;min-width:0}
.log-row .dev{font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.log-row .ip{color:var(--muted);font-size:11.5px;font-variant-numeric:tabular-nums}
.log-row .path{grid-column:1 / -1;color:var(--muted);font-size:11.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.log-row .time{color:var(--muted);font-size:11px;text-align:right;white-space:nowrap}
.st{display:inline-block;padding:1px 6px;border-radius:5px;font-size:10.5px;font-weight:700}
.st.ok{background:rgba(53,208,127,.15);color:var(--ok)}
.st.warn{background:rgba(255,176,46,.15);color:var(--warn)}
.st.bad{background:rgba(255,92,92,.15);color:var(--bad)}

.toast{position:fixed;left:50%;bottom:calc(28px + env(safe-area-inset-bottom));transform:translate(-50%,20px);background:rgba(30,32,42,.95);color:#fff;font-size:13px;padding:10px 16px;border-radius:12px;z-index:70;opacity:0;pointer-events:none;transition:all .22s ease;max-width:86vw;text-align:center}
.toast.show{opacity:1;transform:translate(-50%,0)}
</style>
</head>
<body>
<div class="topbar">
  <header>
    <div class="logo">P</div>
    <div class="titles">
      <h1 id="srv-name">PhotoNAS</h1>
      <p id="srv-sub">正在连接…</p>
    </div>
    <div class="actions">
      <button class="chip" id="btn-logs">日志</button>
      <button class="chip" id="btn-refresh">刷新</button>
    </div>
  </header>
  <div class="filters">
    <select id="album"><option value="">所有相册</option></select>
    <div class="seg" id="kind-seg">
      <button data-kind="all" class="on">全部</button>
      <button data-kind="photos">照片</button>
      <button data-kind="videos">视频</button>
    </div>
  </div>
</div>

<main>
  <div class="meta">
    <span><i class="dot"></i><span id="counter">准备中</span></span>
    <span id="fmt-label"></span>
  </div>
  <div class="grid" id="grid"></div>
  <div id="sentinel" style="height:1px"></div>
  <div id="tail" class="empty" hidden>没有更多照片了</div>
</main>

<div class="viewer" id="viewer">
  <div class="viewer-top">
    <button class="chip" id="viewer-close">关闭</button>
    <div class="viewer-actions">
      <a class="chip" id="open-original" target="_blank" rel="noopener">原图</a>
      <a class="chip primary" id="dl" download>下载</a>
    </div>
  </div>
  <div class="viewer-media" id="viewer-media"></div>
  <div class="caption" id="caption"></div>
</div>

<div class="scrim" id="scrim"></div>
<div class="sheet" id="logs">
  <div class="sheet-head">
    <h3>访问日志</h3>
    <button class="chip" id="logs-close">关闭</button>
  </div>
  <div class="log-list" id="log-list"></div>
</div>

<div class="toast" id="toast"></div>

<script>
(function(){
  "use strict";
  var state = { page: 0, size: 40, kind: "all", album: "", total: 0, loading: false, done: false, format: "jpeg", reqId: 0 };
  var grid = document.getElementById("grid");
  var sentinel = document.getElementById("sentinel");
  var counter = document.getElementById("counter");
  var tail = document.getElementById("tail");
  var viewer = document.getElementById("viewer");
  var viewerMedia = document.getElementById("viewer-media");

  function thumbUrl(id, size) {
    return "/thumb?id=" + encodeURIComponent(id) + "&s=" + size + "&f=" + state.format;
  }
  function fmtDur(seconds) {
    seconds = Math.round(seconds || 0);
    var m = Math.floor(seconds / 60);
    var s = seconds % 60;
    return m + ":" + (s < 10 ? "0" + s : String(s));
  }
  function fmtBytes(n) {
    if (!n) return "0 B";
    var units = ["B", "KB", "MB", "GB"];
    var i = 0;
    var v = n;
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
    return (i === 0 ? v.toFixed(0) : v.toFixed(1)) + " " + units[i];
  }
  function toast(text) {
    var el = document.getElementById("toast");
    el.textContent = text;
    el.classList.add("show");
    clearTimeout(el._timer);
    el._timer = setTimeout(function(){ el.classList.remove("show"); }, 2400);
  }
  function updateCounter() {
    var loaded = grid.children.length;
    counter.textContent = loaded + " / " + state.total + " 项";
    tail.hidden = !state.done || loaded === 0;
  }

  function makeTile(item) {
    var tile = document.createElement("button");
    tile.type = "button";
    tile.className = "tile loading";
    var img = document.createElement("img");
    img.loading = "lazy";
    img.decoding = "async";
    img.alt = "";
    img.onload = function(){ img.classList.add("ready"); tile.classList.remove("loading"); };
    img.onerror = function(){ tile.classList.remove("loading"); };
    img.src = thumbUrl(item.id, "g");
    tile.appendChild(img);

    if (item.video) {
      var badge = document.createElement("span");
      badge.className = "badge";
      badge.textContent = fmtDur(item.duration);
      tile.appendChild(badge);
    }
    if (item.live) {
      var live = document.createElement("span");
      live.className = "tag";
      live.textContent = "LIVE";
      tile.appendChild(live);
    }
    if (item.fav) {
      var fav = document.createElement("span");
      fav.className = "tag fav";
      fav.textContent = "♥";
      tile.appendChild(fav);
    }
    tile.addEventListener("click", function(){ openViewer(item); });
    return tile;
  }

  function loadMore(reset) {
    if (state.loading) return;
    if (!reset && state.done) return;
    if (reset) {
      state.reqId++;
      state.page = 0;
      state.done = false;
      state.total = 0;
      grid.innerHTML = "";
      tail.hidden = true;
      var skeleton = document.createElement("div");
      skeleton.className = "empty";
      skeleton.innerHTML = '<div class="spinner"></div>正在读取相册…';
      grid.style.display = "none";
      document.querySelector("main").appendChild(skeleton);
      grid._skeleton = skeleton;
    }

    var reqId = state.reqId;
    state.loading = true;
    var params = new URLSearchParams();
    params.set("page", String(state.page));
    params.set("size", String(state.size));
    params.set("kind", state.kind);
    if (state.album) params.set("album", state.album);

    fetch("/api/photos?" + params.toString())
      .then(function(res){
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function(data){
        if (reqId !== state.reqId) return;
        var skeleton = grid._skeleton;
        if (skeleton) { skeleton.remove(); grid._skeleton = null; grid.style.display = ""; }
        state.total = data.total || 0;
        var frag = document.createDocumentFragment();
        (data.items || []).forEach(function(item){ frag.appendChild(makeTile(item)); });
        grid.appendChild(frag);
        state.page += 1;
        state.done = !data.hasMore;
        updateCounter();
        if (!state.total) {
          tail.hidden = true;
          grid.innerHTML = '<div class="empty">相册里还没有内容</div>';
        }
      })
      .catch(function(err){
        if (reqId !== state.reqId) return;
        toast("加载失败：" + err.message);
      })
      .finally(function(){
        state.loading = false;
        if (reqId === state.reqId && !state.done && grid.children.length < 12) {
          loadMore();
        }
      });
  }

  function openViewer(item) {
    viewerMedia.innerHTML = "";
    if (item.video) {
      var video = document.createElement("video");
      video.controls = true;
      video.autoplay = true;
      video.playsInline = true;
      video.preload = "metadata";
      video.src = "/media?id=" + encodeURIComponent(item.id);
      viewerMedia.appendChild(video);
    } else {
      var img = document.createElement("img");
      img.src = thumbUrl(item.id, "v");
      img.alt = "";
      viewerMedia.appendChild(img);
    }
    var path = "/original?id=" + encodeURIComponent(item.id);
    document.getElementById("open-original").href = path;
    document.getElementById("dl").href = path + "&dl=1";
    var date = item.date ? new Date(item.date * 1000) : null;
    var parts = [];
    if (date) parts.push(date.toLocaleString("zh-CN"));
    if (item.video) { parts.push("视频 " + fmtDur(item.duration)); }
    else { parts.push(item.w + "×" + item.h); }
    document.getElementById("caption").textContent = parts.join(" · ");
    viewer.classList.add("open");
    document.body.classList.add("locked");
  }

  function closeViewer() {
    var video = viewerMedia.querySelector("video");
    if (video) { video.pause(); video.src = ""; }
    viewerMedia.innerHTML = "";
    viewer.classList.remove("open");
    document.body.classList.remove("locked");
  }

  function loadAlbums() {
    fetch("/api/albums").then(function(r){ return r.json(); }).then(function(data){
      var select = document.getElementById("album");
      (data.albums || []).forEach(function(album){
        var option = document.createElement("option");
        option.value = album.id;
        option.textContent = album.name + " (" + album.count + ")";
        select.appendChild(option);
      });
    }).catch(function(){});
  }

  function openLogs() {
    document.getElementById("logs").classList.add("open");
    document.getElementById("scrim").classList.add("open");
    var list = document.getElementById("log-list");
    list.innerHTML = '<div class="empty"><div class="spinner"></div>读取中…</div>';
    fetch("/api/logs?limit=150").then(function(r){ return r.json(); }).then(function(data){
      var entries = data.entries || [];
      if (!entries.length) { list.innerHTML = '<div class="empty">还没有访问记录</div>'; return; }
      list.innerHTML = "";
      entries.forEach(function(e){
        var row = document.createElement("div");
        row.className = "log-row";
        var cls = e.status >= 500 ? "bad" : (e.status >= 400 ? "warn" : "ok");
        var time = new Date(e.timestamp * 1000);
        var hh = String(time.getHours()).padStart(2, "0");
        var mm = String(time.getMinutes()).padStart(2, "0");
        var ss = String(time.getSeconds()).padStart(2, "0");
        row.innerHTML =
          '<div class="line1"><span class="dev"></span><span class="st ' + cls + '">' + e.status + '</span><span class="ip"></span></div>' +
          '<div class="time">' + hh + ':' + mm + ':' + ss + '</div>' +
          '<div class="path"></div>';
        row.querySelector(".dev").textContent = e.device || "未知设备";
        row.querySelector(".ip").textContent = e.ip || "";
        row.querySelector(".path").textContent = (e.path || "") + (e.query ? "?" + e.query : "") + " · " + fmtBytes(e.bytes);
        list.appendChild(row);
      });
    }).catch(function(){
      list.innerHTML = '<div class="empty">日志读取失败</div>';
    });
  }

  function closeLogs() {
    document.getElementById("logs").classList.remove("open");
    document.getElementById("scrim").classList.remove("open");
  }

  document.getElementById("btn-logs").addEventListener("click", openLogs);
  document.getElementById("logs-close").addEventListener("click", closeLogs);
  document.getElementById("scrim").addEventListener("click", closeLogs);
  document.getElementById("viewer-close").addEventListener("click", closeViewer);
  document.getElementById("btn-refresh").addEventListener("click", function(){ loadMore(true); });

  document.getElementById("album").addEventListener("change", function(e){
    state.album = e.target.value;
    loadMore(true);
  });

  document.getElementById("kind-seg").addEventListener("click", function(e){
    var button = e.target.closest("button");
    if (!button) return;
    var siblings = this.querySelectorAll("button");
    for (var i = 0; i < siblings.length; i++) { siblings[i].classList.remove("on"); }
    button.classList.add("on");
    state.kind = button.getAttribute("data-kind");
    loadMore(true);
  });

  document.addEventListener("keydown", function(e){
    if (e.key === "Escape") { closeViewer(); closeLogs(); }
  });

  if ("IntersectionObserver" in window) {
    var observer = new IntersectionObserver(function(entries){
      entries.forEach(function(entry){
        if (entry.isIntersecting) loadMore();
      });
    }, { rootMargin: "900px 0px" });
    observer.observe(sentinel);
  }

  fetch("/api/info").then(function(r){ return r.json(); }).then(function(info){
    state.format = info.format || "jpeg";
    state.size = info.pageSize || 40;
    document.getElementById("srv-name").textContent = info.name || "PhotoNAS";
    document.getElementById("srv-sub").textContent =
      "共 " + info.total + " 项 · " + (info.ip || "") + ":" + info.port + " · " + (state.format || "").toUpperCase();
    document.getElementById("fmt-label").textContent = (state.format || "").toUpperCase() + " 缩略图";
    if (!info.authorized) {
      grid.innerHTML = '<div class="empty">未获得相册权限，请在 iPhone 上的 PhotoNAS 里授权后重试。</div>';
      return;
    }
    loadAlbums();
    loadMore(true);
  }).catch(function(){
    loadMore(true);
  });
})();
</script>
</body>
</html>
"""#
}
