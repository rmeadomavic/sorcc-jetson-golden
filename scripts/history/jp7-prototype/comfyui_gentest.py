#!/usr/bin/env python3
"""Benchmark ComfyUI on sorcc1: base SD1.5 txt2img, then LCM-LoRA fast recipe.
Proves generation + LoRA loading on the GPU, measures seconds/image.
Run inside ~/venvs/comfyui with the ComfyUI server up on :8188."""
import json, time, urllib.request, urllib.error, sys

HOST = "http://127.0.0.1:8188"
CKPT = "v1-5-pruned-emaonly.safetensors"
LORA = "lcm-lora-sdv15.safetensors"
POS  = "a rugged 6-wheeled ground robot on a desert road at dusk, cinematic, detailed"
NEG  = "blurry, low quality, watermark, text"

def post(path, obj):
    data = json.dumps(obj).encode()
    r = urllib.request.urlopen(urllib.request.Request(HOST+path, data=data,
        headers={"Content-Type":"application/json"}), timeout=30)
    return json.loads(r.read())

def get(path):
    return json.loads(urllib.request.urlopen(HOST+path, timeout=30).read())

def wait_server(timeout=120):
    t=time.time()
    while time.time()-t < timeout:
        try: get("/system_stats"); return True
        except Exception: time.sleep(2)
    return False

def base_wf(steps, cfg, sampler, sched, prefix, seed=42, lora=False):
    wf = {
      "4":{"class_type":"CheckpointLoaderSimple","inputs":{"ckpt_name":CKPT}},
      "6":{"class_type":"CLIPTextEncode","inputs":{"text":POS,"clip":["4",1]}},
      "7":{"class_type":"CLIPTextEncode","inputs":{"text":NEG,"clip":["4",1]}},
      "5":{"class_type":"EmptyLatentImage","inputs":{"width":512,"height":512,"batch_size":1}},
      "3":{"class_type":"KSampler","inputs":{"seed":seed,"steps":steps,"cfg":cfg,
            "sampler_name":sampler,"scheduler":sched,"denoise":1.0,
            "model":["4",0],"positive":["6",0],"negative":["7",0],"latent_image":["5",0]}},
      "8":{"class_type":"VAEDecode","inputs":{"samples":["3",0],"vae":["4",2]}},
      "9":{"class_type":"SaveImage","inputs":{"filename_prefix":prefix,"images":["8",0]}},
    }
    if lora:
        wf["10"]={"class_type":"LoraLoader","inputs":{"lora_name":LORA,
            "strength_model":1.0,"strength_clip":1.0,"model":["4",0],"clip":["4",1]}}
        wf["3"]["inputs"]["model"]=["10",0]
        wf["6"]["inputs"]["clip"]=["10",1]
        wf["7"]["inputs"]["clip"]=["10",1]
    return wf

def run(name, wf):
    t=time.time()
    pid = post("/prompt", {"prompt":wf})["prompt_id"]
    while True:
        h = get("/history/"+pid)
        if pid in h:
            status = h[pid].get("status",{})
            imgs = [i for n in h[pid]["outputs"].values() for i in n.get("images",[])]
            dt=time.time()-t
            ok = status.get("status_str")!="error"
            print(f"  {name}: {'OK' if ok else 'ERROR'} in {dt:.1f}s -> {[i['filename'] for i in imgs]}")
            if not ok: print("   ", json.dumps(status)[:300])
            return dt, imgs
        if time.time()-t>180: print(f"  {name}: TIMEOUT"); return None,[]
        time.sleep(1)

if not wait_server(): print("SERVER NOT UP"); sys.exit(1)
print("system_stats:", json.dumps(get("/system_stats").get("devices",[{}])[0].get("name","?")))
print("=== BASE SD1.5 (20 steps, euler, cfg7) — warmup+timed ===")
run("base-warmup", base_wf(20,7.0,"euler","normal","sorcc_base",seed=1))  # first = JIT warm
run("base",        base_wf(20,7.0,"euler","normal","sorcc_base",seed=42))
print("=== LCM-LoRA fast recipe (4 steps, cfg1.5, lcm) ===")
run("lcm-lora",    base_wf(4,1.5,"lcm","sgm_uniform","sorcc_lcm",seed=42,lora=True))
print("GENTEST_DONE")
