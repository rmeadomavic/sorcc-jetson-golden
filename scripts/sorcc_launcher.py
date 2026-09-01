#!/usr/bin/env python3
"""SORCC AI Launcher for the student Jetson.

One always-on page (port 8090). Three launch buttons plus Stop All: Chat (LLM),
Image (ComfyUI), and Detection (Hydra). Enforces ONE-TOOL-AT-A-TIME on the 8 GB
kit: starting one stops the others, then opens that tool's UI. A built-in chat page talks to
Ollama so the LLM needs no terminal. Pure Python stdlib — no venv, no deps.

Service control via `sudo systemctl` (NOPASSWD sudoers rule installs the three
unit names). Status via sysfs (no sudo)."""
import json, subprocess, urllib.request, socket, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT = 8090
UNITS = {"chat": "ollama", "image": "comfyui", "detect": "hydra-detect"}
TOOL_PORT = {"chat": 8090, "image": 8188, "detect": 8080}  # chat is built-in here
TOOL_LABEL = {"chat": "Language (LLM)", "image": "Imagery (ComfyUI)", "detect": "Detection (Hydra)"}
TOOL_DESC = {
    "chat": "Use the local language model for summaries, checklists, comparisons, and "
            "draft reports. Verify every response before use.",
    "image": "Create synthetic images from text prompts. Start with the preset workflow, "
             "then compare prompts, checkpoints, and LoRAs.",
    "detect": "View live detections, confidence scores, and track IDs from the USB camera. "
              "The class configuration observes and reports. It does not act.",
}
OLLAMA = "http://127.0.0.1:11434"
MODEL = "qwen3:4b-instruct"  # swapped from llama3.2:3b 2026-08-03 (license); never the plain qwen3:4b thinking alias
OLLAMA_CONTEXT = 4096


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()


def svc_active(unit):
    return sh(f"systemctl is-active {unit}") == "active"


def stop_unit(unit):
    result = subprocess.run(
        ["sudo", "-n", "systemctl", "stop", unit],
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        subprocess.run(
            ["sudo", "-n", "systemctl", "reset-failed", unit],
            capture_output=True,
            text=True,
        )
    return result


def lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]; s.close(); return ip
    except Exception:
        return "127.0.0.1"


def status():
    # RAM
    mem = {}
    for ln in open("/proc/meminfo"):
        k, v = ln.split(":"); mem[k] = int(v.strip().split()[0])
    ram_used = (mem["MemTotal"] - mem["MemAvailable"]) // 1024
    ram_tot = mem["MemTotal"] // 1024
    # temp (max thermal zone in C)
    temp = 0
    import glob
    for f in glob.glob("/sys/devices/virtual/thermal/thermal_zone*/temp"):
        try: temp = max(temp, int(open(f).read().strip()) // 1000)
        except Exception: pass
    # gpu load (Orin sysfs, 0..1000)
    gpu = None
    for f in ("/sys/devices/platform/gpu.0/load", "/sys/devices/gpu.0/load"):
        try: gpu = int(open(f).read().strip()) / 10.0; break
        except Exception: pass
    active = next((t for t, u in UNITS.items() if svc_active(u)), None)
    return {"active": active, "ram_used_mb": ram_used, "ram_total_mb": ram_tot,
            "temp_c": temp, "gpu_pct": gpu,
            "services": {t: svc_active(u) for t, u in UNITS.items()}}


def start_tool(tool):
    # one-tool-at-a-time: stop the other two, start the chosen one
    for t, u in UNITS.items():
        if t != tool:
            stop_unit(u)
    sh(f"sudo -n systemctl start {UNITS[tool]}")


def stop_all():
    failures = {}
    for tool, unit in UNITS.items():
        result = stop_unit(unit)
        if result.returncode:
            failures[tool] = (result.stderr or result.stdout).strip() or "stop failed"
    return failures


def ollama_json(path, payload=None, timeout=15):
    data = None if payload is None else json.dumps(payload).encode()
    headers = {} if payload is None else {"Content-Type": "application/json"}
    req = urllib.request.Request(OLLAMA + path, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return json.loads(response.read())


def ollama_meta():
    show = ollama_json("/api/show", {"model": MODEL})
    version = ollama_json("/api/version").get("version", "unknown")
    details = show.get("details", {})
    capabilities = show.get("capabilities", [])
    return {
        "model": MODEL,
        "version": version,
        "parameter_size": details.get("parameter_size", "unknown"),
        "quantization": details.get("quantization_level", "unknown"),
        "family": details.get("family", "unknown"),
        "context": OLLAMA_CONTEXT,
        "capabilities": capabilities,
        "thinking_supported": "thinking" in capabilities,
    }


def clean_messages(payload):
    source = payload.get("messages")
    if not isinstance(source, list):
        source = [{"role": "user", "content": payload.get("msg", "")}]
    messages = []
    total = 0
    for item in source[-16:]:
        if not isinstance(item, dict) or item.get("role") not in ("user", "assistant"):
            continue
        content = str(item.get("content", "")).strip()[:12000]
        if not content:
            continue
        total += len(content)
        if total > 30000:
            break
        messages.append({"role": item["role"], "content": content})
    if not messages or messages[-1]["role"] != "user":
        raise ValueError("A user message is required.")
    return messages


PAGE = """<!doctype html><html><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>SORCC AI Kit</title><style>
*{{box-sizing:border-box}}body{{margin:0;font-family:system-ui,Segoe UI,Roboto,sans-serif;
background:#0f1512;color:#e8ede9}}
header{{padding:22px 28px;border-bottom:1px solid #24352b;background:#0b100d;display:flex;
align-items:center;justify-content:space-between}}
h1{{margin:0;font-size:20px;letter-spacing:2px;color:#8fce9b;font-weight:700}}
.sub{{color:#6f8577;font-size:12px;letter-spacing:1px}}
.wrap{{max-width:980px;margin:0 auto;padding:26px}}
.cards{{display:grid;grid-template-columns:repeat(3,1fr);gap:18px}}
@media(max-width:760px){{.cards{{grid-template-columns:1fr}}}}
.card{{background:#141d18;border:1px solid #24352b;border-radius:14px;padding:22px;display:flex;
flex-direction:column;min-height:230px}}
.card h2{{margin:.2em 0;font-size:17px;color:#cfe6d4}}
.card p{{color:#9db3a4;font-size:13px;line-height:1.5;flex:1}}
.badge{{font-size:11px;padding:3px 9px;border-radius:20px;align-self:flex-start;margin-bottom:8px}}
.on{{background:#173a24;color:#7ee29a;border:1px solid #2b6b40}}
.off{{background:#241a1a;color:#c98b8b;border:1px solid #5b2f2f}}
button{{margin-top:14px;padding:13px;font-size:15px;font-weight:600;border:0;border-radius:10px;
background:#2b6b40;color:#eafff0;cursor:pointer}}
button:hover{{background:#348050}}button:disabled{{background:#3a463f;color:#8aa;cursor:wait}}
.bar{{display:flex;align-items:center;flex-wrap:wrap;gap:22px;margin-top:22px;padding:14px 18px;background:#0b100d;border:1px solid #24352b;
border-radius:12px;font-size:13px;color:#9db3a4}}
.bar b{{color:#cfe6d4}}
.stopall{{margin:0 0 0 auto;padding:8px 14px;font-size:13px;background:#472727;color:#f2caca;border:1px solid #764242}}
.stopall:hover{{background:#5b3030}}.stopall:disabled{{background:#252b27;color:#657168;border-color:#343d37;cursor:not-allowed}}
.note{{margin-top:16px;color:#6f8577;font-size:12px;line-height:1.6}}
</style></head><body>
<header><h1>SORCC&nbsp;&nbsp;AI&nbsp;KIT</h1><span class=sub id=host></span></header>
<div class=wrap>
<div class=cards>
{cards}
</div>
<div class=bar>
<span>Active tool: <b id=active>-</b></span>
<span>RAM <b id=ram>-</b></span>
<span>GPU <b id=gpu>-</b></span>
<span>Temp <b id=temp>-</b></span>
<span class=sub>One tool at a time &middot; 8&nbsp;GB kit</span>
<button class=stopall id=stopall onclick=stopAll()>Stop All</button>
</div>
<p class=note>Choose one tool at a time. Starting a tool stops the other two. Initial startup
may take about a minute, and the first image takes about one minute. Stop All releases
the camera and model memory. All processing stays on this kit.</p>
</div>
<script>
function card(t,label,desc){{return `<div class=card><span class="badge off" id="b_${{t}}">stopped</span>
<h2>${{label}}</h2><p>${{desc}}</p>
<button id="btn_${{t}}" onclick="go('${{t}}')">Launch</button></div>`}}
async function refresh(){{
 let s=await (await fetch('/status')).json();
 document.getElementById('active').textContent=s.active?({{chat:'Language',image:'Imagery',detect:'Detection'}})[s.active]:'none';
 document.getElementById('ram').textContent=s.ram_used_mb+' / '+s.ram_total_mb+' MB';
 document.getElementById('gpu').textContent=(s.gpu_pct==null?'-':s.gpu_pct.toFixed(0)+'%');
 document.getElementById('temp').textContent=s.temp_c+' C';
 for(const t of ['chat','image','detect']){{
   let on=s.services[t];let b=document.getElementById('b_'+t);
   b.textContent=on?'running':'stopped';b.className='badge '+(on?'on':'off');
 }}
 let stopBtn=document.getElementById('stopall');
 if(stopBtn.dataset.busy!=='1'){{stopBtn.disabled=!Object.values(s.services).some(Boolean);stopBtn.textContent='Stop All'}}
}}
async function go(t){{
 let btn=document.getElementById('btn_'+t);btn.disabled=true;btn.textContent='Starting...';
 let r=await (await fetch('/start?tool='+t,{{method:'POST'}})).json();
 if(t==='chat'){{location.href='/chat';return}}
 // poll the tool's port then redirect
 btn.textContent='Opening...';
 setTimeout(()=>{{location.href=r.url}}, t==='image'?9000:7000);
}}
async function stopAll(){{
 let btn=document.getElementById('stopall');btn.dataset.busy='1';btn.disabled=true;btn.textContent='Stopping...';
 try{{let response=await fetch('/stop',{{method:'POST'}});let result=await response.json();if(!response.ok||!result.ok)throw new Error('stop failed');
  await refresh();btn.textContent='All Stopped';setTimeout(()=>{{delete btn.dataset.busy;refresh()}},1200);
 }}catch(e){{btn.textContent='Try Again';delete btn.dataset.busy;btn.disabled=false}}
}}
document.getElementById('host').textContent=location.host;
document.body.insertAdjacentHTML('beforeend','');
document.querySelector('.cards').innerHTML=[
 card('chat','{chat_label}','{chat_desc}'),
 card('image','{image_label}','{image_desc}'),
 card('detect','{detect_label}','{detect_desc}')].join('');
refresh();setInterval(refresh,4000);
</script></body></html>"""

CHAT = """<!doctype html><html><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>SORCC Language</title><style>
:root{--bg:#0f1512;--panel:#141d18;--panel2:#0b100d;--line:#24352b;--text:#e8ede9;
--muted:#8fa397;--green:#8fce9b;--green2:#2b6b40;--amber:#d6b86f;--red:#d38c8c}
*{box-sizing:border-box}body{margin:0;font-family:system-ui,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--text)}
header{padding:15px 22px;border-bottom:1px solid var(--line);background:var(--panel2);display:flex;align-items:center;gap:14px}
a{color:var(--green);text-decoration:none;font-size:13px}h1{font-size:17px;margin:0;color:#cfe6d4;flex:1}
.chip{font-size:11px;padding:4px 9px;border:1px solid var(--line);border-radius:20px;color:var(--muted);background:var(--panel)}
.chip.live{color:#8ee8a6;border-color:#2b6b40}.wrap{max-width:900px;margin:0 auto;padding:18px 18px 30px}
.telemetry{background:var(--panel);border:1px solid var(--line);border-radius:13px;padding:16px;margin-bottom:16px}
.meta{display:flex;gap:7px;flex-wrap:wrap;align-items:center}.meta .title{font-size:13px;font-weight:700;color:#cfe6d4;margin-right:4px}
.lesson{margin:11px 0 13px;color:var(--muted);font-size:12px;line-height:1.5}
.steps{display:grid;grid-template-columns:repeat(4,1fr);gap:7px}.step{height:38px;border:1px solid var(--line);border-radius:9px;
display:flex;align-items:center;gap:8px;padding:0 10px;color:#66776d;font-size:11px;background:var(--panel2)}
.step .dot{width:8px;height:8px;border-radius:50%;background:#425249}.step.active{border-color:#447d55;color:#cfe6d4}
.step.active .dot{background:#79d991;box-shadow:0 0 0 4px #21452d;animation:pulse 1.2s infinite}.step.done{color:#8fce9b}
.step.done .dot{background:#5eb978;box-shadow:none;animation:none}@keyframes pulse{50%{opacity:.45}}
.runline{display:flex;justify-content:space-between;gap:12px;margin-top:11px;color:var(--muted);font-size:12px}.runline b{color:#cfe6d4}
.stats{display:none;grid-template-columns:repeat(5,1fr);gap:7px;margin-top:11px}.stats.show{display:grid}.stat{background:var(--panel2);
border:1px solid var(--line);border-radius:8px;padding:8px}.stat span{display:block;color:#65776c;font-size:10px;text-transform:uppercase;letter-spacing:.5px}.stat b{font-size:13px;color:#cfe6d4}
#log{min-height:140px}.msg{border-radius:11px;margin:10px 0;padding:13px 15px;line-height:1.55;white-space:pre-wrap;font-size:14px}
.u{background:#173a24;border:1px solid #2b6b40;margin-left:12%}.a{background:var(--panel);border:1px solid var(--line);margin-right:5%}
.label{font-size:10px;text-transform:uppercase;letter-spacing:1px;color:#6f8577;margin-bottom:6px}.answer:empty:after{content:'Waiting for response...';color:#64766b}
details.reason{display:none;margin:0 0 11px;background:#171811;border:1px solid #514a2b;border-radius:9px;padding:8px 10px;color:#c9bd91}
details.reason.show{display:block}details.reason summary{cursor:pointer;font-size:11px;font-weight:700;color:var(--amber);letter-spacing:.5px}
.thought{white-space:pre-wrap;font-size:12px;line-height:1.5;margin-top:8px;color:#b8ad82}.direct{font-size:11px;color:#65776c;margin:4px 0 8px}
.composer{display:flex;gap:8px;margin-top:15px}.composer textarea{flex:1;background:var(--panel2);color:var(--text);border:1px solid var(--line);
border-radius:10px;padding:12px;font:inherit;resize:vertical;min-height:58px}.composer button{padding:0 20px;border:0;border-radius:10px;
background:var(--green2);color:#effff3;font-weight:650;cursor:pointer}.composer button:disabled{background:#3a463f;color:#819087;cursor:wait}
.under{display:flex;justify-content:space-between;gap:12px;margin-top:8px;color:#66776d;font-size:11px}.under button{border:0;background:none;color:#8fce9b;cursor:pointer;padding:0}
@media(max-width:650px){.steps{grid-template-columns:1fr 1fr}.stats{grid-template-columns:1fr 1fr}.u{margin-left:4%}}
</style></head><body>
<header><a href="/">&larr; AI Kit menu</a><h1>SORCC Language</h1><span class="chip live">LOCAL</span><span class=chip>OFFLINE</span></header>
<div class=wrap>
<section class=telemetry>
 <div class=meta><span class=title id=model>qwen3:4b-instruct</span><span class=chip id=size>4B</span><span class=chip id=quant>Q4</span><span class=chip id=context>4K context</span><span class=chip id=thinkcap>Checking model</span></div>
 <p class=lesson>This page shows how the local model handles a prompt: prepare the model, read the prompt, then generate a response. Model responses and reasoning traces can be wrong. Verify them before use.</p>
 <div class=steps><div class=step id=s0><span class=dot></span>Prepare</div><div class=step id=s1><span class=dot></span>Read prompt</div><div class=step id=s2><span class=dot></span>Generate</div><div class=step id=s3><span class=dot></span>Done</div></div>
 <div class=runline><span id=phase>Enter a prompt</span><span>Elapsed <b id=elapsed>0.0 s</b></span></div>
 <div class=stats id=stats><div class=stat><span>Load time</span><b id=loadtime>-</b></div><div class=stat><span>Input tokens</span><b id=intokens>-</b></div><div class=stat><span>Output tokens</span><b id=outtokens>-</b></div><div class=stat><span>Generation speed</span><b id=rate>-</b></div><div class=stat><span>Total time</span><b id=total>-</b></div></div>
</section>
<div id=log></div>
<div class=composer><textarea id=t placeholder="Ask a question or request a summary, checklist, comparison, or draft."></textarea><button id=send onclick=sendMessage()>Send</button></div>
<div class=under><span>Enter to send. Shift + Enter for a new line.</span><button onclick=clearChat()>Clear conversation</button></div>
</div><script>
const log=document.getElementById('log'), box=document.getElementById('t'), sendBtn=document.getElementById('send');
let conversation=[], running=false, timer=null, started=0, thinkingSupported=false;
const ns=n=>n?`${(n/1e9).toFixed(2)} s`:'0.00 s';
function scrollDown(){window.scrollTo({top:document.body.scrollHeight,behavior:'smooth'})}
function setStage(index,label){for(let i=0;i<4;i++){let e=document.getElementById('s'+i);e.className='step'+(i<index?' done':i===index?' active':'')}document.getElementById('phase').textContent=label}
function beginTimer(){started=performance.now();clearInterval(timer);timer=setInterval(()=>document.getElementById('elapsed').textContent=((performance.now()-started)/1000).toFixed(1)+' s',100)}
function stopTimer(){clearInterval(timer);timer=null}
function addUser(text){let d=document.createElement('div');d.className='msg u';let l=document.createElement('div');l.className='label';l.textContent='You';let c=document.createElement('div');c.textContent=text;d.append(l,c);log.appendChild(d)}
function addAssistant(){let d=document.createElement('div');d.className='msg a';let l=document.createElement('div');l.className='label';l.textContent='AI response';let direct=document.createElement('div');direct.className='direct';direct.textContent=thinkingSupported?'A reasoning trace appears before the response when the model provides one.':'This model responds without a separate reasoning trace.';let details=document.createElement('details');details.className='reason';let summary=document.createElement('summary');summary.textContent='Reasoning trace';let thought=document.createElement('div');thought.className='thought';details.append(summary,thought);let answer=document.createElement('div');answer.className='answer';d.append(l,direct,details,answer);log.appendChild(d);return{root:d,direct,details,thought,answer}}
async function loadMeta(){try{let m=await(await fetch('/api/model')).json();document.getElementById('model').textContent=m.model;document.getElementById('size').textContent=m.parameter_size;document.getElementById('quant').textContent=m.quantization;document.getElementById('context').textContent=(m.context/1024).toFixed(0)+'K context';thinkingSupported=!!m.thinking_supported;document.getElementById('thinkcap').textContent=thinkingSupported?'Reasoning trace available':'Direct-response model'}catch(e){document.getElementById('thinkcap').textContent='Model details unavailable'}}
function showStats(e){document.getElementById('stats').classList.add('show');document.getElementById('loadtime').textContent=ns(e.load_duration);document.getElementById('intokens').textContent=e.prompt_eval_count??'-';document.getElementById('outtokens').textContent=e.eval_count??'-';let r=e.eval_duration?e.eval_count/(e.eval_duration/1e9):0;document.getElementById('rate').textContent=r?r.toFixed(1)+' tok/s':'-';document.getElementById('total').textContent=ns(e.total_duration)}
async function sendMessage(){let text=box.value.trim();if(!text||running)return;running=true;sendBtn.disabled=true;sendBtn.textContent='Generating...';box.value='';document.getElementById('stats').classList.remove('show');conversation.push({role:'user',content:text});addUser(text);let ui=addAssistant();setStage(0,'Preparing request');beginTimer();scrollDown();let answer='',thought='';
 try{let response=await fetch('/api/chat',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({messages:conversation})});if(!response.ok)throw new Error('HTTP '+response.status);let reader=response.body.getReader(),decoder=new TextDecoder(),buffer='';
  while(true){let part=await reader.read();buffer+=decoder.decode(part.value||new Uint8Array(),{stream:!part.done});let lines=buffer.split('\\n');buffer=lines.pop();for(let line of lines){if(!line.trim())continue;let e=JSON.parse(line);if(e.event==='start'){thinkingSupported=!!e.thinking_supported;ui.direct.textContent=thinkingSupported?'A reasoning trace appears before the response when the model provides one.':'This model responds without a separate reasoning trace.'}else if(e.event==='phase'){setStage(1,'Loading model and reading prompt')}else if(e.event==='thinking'){setStage(2,'Generating reasoning trace');thought+=e.text;ui.details.classList.add('show');ui.details.open=true;ui.thought.textContent=thought;ui.direct.style.display='none'}else if(e.event==='content'){setStage(2,'Generating response');answer+=e.text;ui.answer.textContent=answer}else if(e.event==='done'){setStage(3,'Response complete');showStats(e)}else if(e.event==='error'){throw new Error(e.message)}scrollDown()}if(part.done)break}
  if(!answer)ui.answer.textContent='No response was generated.';else conversation.push({role:'assistant',content:answer});
 }catch(e){setStage(3,'Generation failed');ui.answer.textContent='Could not generate a response: '+e.message;ui.answer.style.color='var(--red)'}finally{stopTimer();running=false;sendBtn.disabled=false;sendBtn.textContent='Send';box.focus()}}
function clearChat(){if(running)return;conversation=[];log.innerHTML='';document.getElementById('stats').classList.remove('show');document.getElementById('elapsed').textContent='0.0 s';setStage(-1,'Enter a prompt');box.focus()}
box.addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();sendMessage()}});loadMeta();box.focus();
</script></body></html>"""


class H(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="text/html"):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)

    def _stream_headers(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True

    def _event(self, event):
        self.wfile.write((json.dumps(event) + "\n").encode())
        self.wfile.flush()

    def _chat_stream(self, payload):
        messages = clean_messages(payload)
        self._stream_headers()
        wall_start = time.monotonic()
        try:
            meta = ollama_meta()
            self._event({"event": "start", **meta})
            self._event({"event": "phase", "phase": "loading"})
            body = {"model": MODEL, "messages": messages, "stream": True, "keep_alive": "10m"}
            if meta["thinking_supported"]:
                body["think"] = True
            req = urllib.request.Request(
                OLLAMA + "/api/chat", data=json.dumps(body).encode(),
                headers={"Content-Type": "application/json"})
            saw_done = False
            with urllib.request.urlopen(req, timeout=300) as response:
                for raw in response:
                    if not raw.strip():
                        continue
                    chunk = json.loads(raw)
                    message = chunk.get("message", {})
                    thinking = message.get("thinking", "")
                    content = message.get("content", "")
                    if thinking:
                        self._event({"event": "thinking", "text": thinking})
                    if content:
                        self._event({"event": "content", "text": content})
                    if chunk.get("done"):
                        saw_done = True
                        self._event({
                            "event": "done",
                            "done_reason": chunk.get("done_reason"),
                            "total_duration": chunk.get("total_duration", 0),
                            "load_duration": chunk.get("load_duration", 0),
                            "prompt_eval_count": chunk.get("prompt_eval_count", 0),
                            "prompt_eval_duration": chunk.get("prompt_eval_duration", 0),
                            "eval_count": chunk.get("eval_count", 0),
                            "eval_duration": chunk.get("eval_duration", 0),
                            "wall_duration": time.monotonic() - wall_start,
                        })
            if not saw_done:
                self._event({"event": "error", "message": "The model stream ended before completion."})
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as exc:
            try:
                self._event({"event": "error", "message": str(exc)})
            except Exception:
                pass

    def log_message(self, *a): pass

    def do_GET(self):
        p = urlparse(self.path).path
        if p == "/":
            page = PAGE.format(cards="",
                chat_label=TOOL_LABEL["chat"], chat_desc=TOOL_DESC["chat"],
                image_label=TOOL_LABEL["image"], image_desc=TOOL_DESC["image"],
                detect_label=TOOL_LABEL["detect"], detect_desc=TOOL_DESC["detect"])
            self._send(200, page)
        elif p == "/chat":
            self._send(200, CHAT)
        elif p == "/status":
            self._send(200, json.dumps(status()), "application/json")
        elif p == "/api/model":
            try:
                self._send(200, json.dumps(ollama_meta()), "application/json")
            except Exception as exc:
                self._send(503, json.dumps({"error": str(exc)}), "application/json")
        else:
            self._send(404, "not found")

    def do_POST(self):
        p = urlparse(self.path)
        if p.path == "/start":
            tool = parse_qs(p.query).get("tool", [""])[0]
            if tool in UNITS:
                start_tool(tool)
                suffix = "?sorcc=start" if tool == "image" else ""
                url = f"http://{lan_ip()}:{TOOL_PORT[tool]}/{suffix}"
                self._send(200, json.dumps({"ok": True, "url": url}), "application/json")
            else:
                self._send(400, json.dumps({"ok": False}), "application/json")
        elif p.path == "/stop":
            failures = stop_all()
            code = 200 if not failures else 500
            self._send(code, json.dumps({
                "ok": not failures,
                "failures": failures,
                "status": status(),
            }), "application/json")
        elif p.path == "/api/chat":
            n = int(self.headers.get("Content-Length", 0))
            try:
                payload = json.loads(self.rfile.read(n))
                clean_messages(payload)
            except Exception as exc:
                self._send(400, json.dumps({"error": str(exc)}), "application/json")
                return
            self._chat_stream(payload)
        else:
            self._send(404, "not found")


if __name__ == "__main__":
    print(f"SORCC launcher on :{PORT}  (LAN http://{lan_ip()}:{PORT}/)")
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
