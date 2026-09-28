"""SORCC student helper for ComfyUI.

Adds no nodes. It serves web/sorcc_default.js, which opens the SORCC-START-HERE
workflow when the SORCC AI Kit launcher opens ComfyUI with ?sorcc=start.
"""

NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}
WEB_DIRECTORY = "./web"

__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS", "WEB_DIRECTORY"]
