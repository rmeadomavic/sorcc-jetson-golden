// SORCC AI Kit: open the START HERE workflow when the launcher asks for it.
// The launcher opens ComfyUI at /?sorcc=start. Without that flag ComfyUI behaves normally.
import { app } from "../../scripts/app.js";
import { api } from "../../scripts/api.js";

const START_WORKFLOW = "SORCC-START-HERE.json";

app.registerExtension({
  name: "SORCC.StudentStartWorkflow",
  async setup() {
    const params = new URLSearchParams(window.location.search);
    if (params.get("sorcc") !== "start") return;
    try {
      const response = await api.fetchApi(
        "/userdata/" + encodeURIComponent("workflows/" + START_WORKFLOW),
      );
      if (!response.ok) throw new Error("HTTP " + response.status);
      await app.loadGraphData(await response.json(), true, true, START_WORKFLOW);
      // Drop the flag so a page refresh keeps the student's edits.
      params.delete("sorcc");
      const query = params.toString();
      window.history.replaceState(
        null, "", window.location.pathname + (query ? "?" + query : "") + window.location.hash,
      );
    } catch (error) {
      console.error("SORCC: could not open " + START_WORKFLOW, error);
    }
  },
});
