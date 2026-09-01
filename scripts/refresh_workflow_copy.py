#!/usr/bin/env python3
"""Apply the reviewed student-facing copy to the three shipped ComfyUI workflows."""
import json
import pathlib


ROOT = pathlib.Path(__file__).with_name("workflows")


COPY = {
    "SORCC-START-HERE.json": {
        100: """# SORCC Imagery | START HERE

This workflow is preset for the class Jetson.

1. Edit the **Positive prompt** node.
2. Select **Queue** at the top of the page.
3. Wait for the image in the **GENERATED output** node.

The file is also saved in the output folder. Any image that leaves this kit must be marked **GENERATED**.""",
        101: """# Fast preset

Keep these settings for the first exercise:

- DreamShaper 8
- LCM LoRA enabled
- 256 by 256
- Batch size 1
- 4 steps
- CFG 1.5
- Sampler `lcm`
- Scheduler `sgm_uniform`

The first image normally takes about 50 to 65 seconds after launch. Follow-on images take about 30 seconds while the model remains loaded.""",
        102: """# Higher-quality preset

Open the Workflows panel and load **SORCC-QUALITY-20-STEP** for a higher-quality comparison. It uses 20 sampling steps and normally takes about 50 to 70 seconds.

Keep the resolution at 256 by 256 on this 8 GB kit. If memory becomes fragmented, return to the SORCC AI Kit menu and start Imagery again.""",
    },
    "SORCC-QUALITY-20-STEP.json": {
        100: """# SORCC Imagery | QUALITY

This workflow uses the reliable 20-step preset.

1. Edit the **Positive prompt** node.
2. Select **Queue** at the top of the page.
3. Wait for the image in the **GENERATED output** node.

The file is also saved in the output folder. Any image that leaves this kit must be marked **GENERATED**.""",
        101: """# Quality preset

Keep these settings:

- DreamShaper 8
- LoRA bypassed
- 256 by 256
- Batch size 1
- 20 steps
- CFG 7.0
- Sampler `euler`
- Scheduler `normal`

The first image normally takes about 50 to 70 seconds on this kit.""",
        102: """# Compare models and LoRAs

Change one setting at a time. Select another installed checkpoint, or enable the LoRA node and select an installed SD 1.5 LoRA. Keep the resolution at 256 by 256.

For a clean reset, return to the SORCC AI Kit menu and start Imagery again.""",
    },
    "SORCC-cheat-sheet.json": {
        100: """# SORCC ComfyUI Cheat Sheet

This pre-wired SD 1.5 workflow is sized for the 8 GB class Jetson.

## Quick start
1. Edit the **Positive prompt** node below the checkpoint
2. Select **Queue**
3. Find the image at the bottom right and in `/opt/sorcc/comfyui/output/`

## Change the base model
Select DreamShaper, RevAnimated, or the SD 1.5 base checkpoint.

## Enable a LoRA
Right-click **Load LoRA**, clear **Bypass**, and select an installed SD 1.5 LoRA.

Any image that leaves this kit must be marked **GENERATED**.""",
        101: """# DreamShaper 8 preset

- Resolution: **256 by 256**
- Steps: **20 to 25**
- CFG: **6.5**
- Sampler: `dpmpp_2m`
- Scheduler: `karras`
- CLIP skip: **2**

The first image normally takes about 40 to 60 seconds. Keep the resolution at 256 by 256 on this shared-memory Jetson.""",
        102: """# RevAnimated 1.2.2 preset

Select `revAnimated_v122.safetensors` in the checkpoint node.

- Resolution: **256 by 256**
- Steps: **20 to 25**
- CFG: **7.0**
- Sampler: `dpmpp_sde`
- Scheduler: `karras`
- CLIP skip: **2**

Run the same prompt with DreamShaper and RevAnimated to isolate the effect of training data.""",
        103: """# SDXL is not installed

The class image includes SD 1.5 checkpoints and LoRAs. An SDXL model or a 1024-pixel latent can exhaust memory on this 8 GB kit.""",
        104: """# LCM four-step preset

Use `lcm-lora-sdv1-5.safetensors` with an SD 1.5 checkpoint.

1. Clear **Bypass** on **Load LoRA**
2. Set model and CLIP strength to **1.0**
3. Set KSampler steps to **4**
4. Set CFG to **1.5**
5. Set sampler to `lcm`
6. Set scheduler to `sgm_uniform`
7. Keep the resolution at **256 by 256**

LCM reduces the sampling steps. CPU VAE decode still sets a fixed time floor on this Jetson.""",
        105: """# Four LoRAs, four fine-tuning effects

Clear **Bypass** on the **Load LoRA** node and select one:

| LoRA | Effect | Strength | Trigger |
|---|---|---|---|
| `PixelArtRedmond...PIXARFK` | **Style:** 8-bit pixel art | 1.0 | `Pixel Art, PIXARFK` |
| `detail-tweaker` | **Quality:** detail up or down | +2 or -2 | none |
| `ghibli-style-sd15` | **Aesthetic:** hand-painted | 0.8 | `Studio Ghibli, StdGBRedmAF` |
| `lego-style-sd15` | **Concept:** LEGO bricks | 0.9 | none |

Keep the prompt and base model fixed, then change only the LoRA to compare its effect.""",
        106: """# CUDA out-of-memory recovery

1. Return to the SORCC AI Kit menu
2. Start Imagery again to restart the container and compact memory
3. Keep the resolution at **256 by 256**
4. Close unused browser tabs
5. Reboot only if a fresh Imagery session still fails

Run only one AI tool at a time.""",
        21: """# Optional model-cache recovery

This disconnected node clears the in-memory model cache after a generation. Enable it only when repeated checkpoint changes cause memory pressure. Each new image will take longer because the model must reload.

The normal recovery is simpler: return to the SORCC AI Kit menu and start Imagery again.""",
    },
}


TITLES = {
    2: "CLIP skip | keep preset",
    3: "Fast or optional LoRA",
    4: "2. Positive prompt | EDIT",
    5: "Negative prompt | keep preset",
    6: "Resolution | keep 256 by 256",
    7: "3. Sampler | keep preset",
    8: "CPU decode | automatic",
    9: "4. GENERATED output",
}


for filename, node_copy in COPY.items():
    path = ROOT / filename
    graph = json.loads(path.read_text(encoding="utf-8"))
    nodes = {int(node["id"]): node for node in graph["nodes"]}
    for node_id, text in node_copy.items():
        node = nodes[node_id]
        strings = [i for i, value in enumerate(node.get("widgets_values", [])) if isinstance(value, str)]
        if not strings:
            raise RuntimeError(f"{filename} node {node_id} has no text widget")
        node["widgets_values"][strings[0]] = text
    if filename != "SORCC-cheat-sheet.json":
        for node_id, title in TITLES.items():
            if node_id in nodes:
                nodes[node_id]["title"] = title
        nodes[3]["title"] = "Fast LoRA | keep enabled" if filename == "SORCC-START-HERE.json" else "Optional LoRA | bypassed"
    path.write_text(json.dumps(graph, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(path.name)
