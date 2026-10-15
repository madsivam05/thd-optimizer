import os
from flask import Flask, request, jsonify, render_template_string
import pandas as pd
import numpy as np
import threading

try:
    import serial          # pip install pyserial
except ImportError:
    serial = None

# ---------- Settings ----------
LOOKUP_PATH = "thd_lookup.csv"
SERIAL_PORT = os.environ.get("SERIAL_PORT")   # set on your PC only; empty on Render
BAUD = 115200
F0 = 50                    # fundamental frequency (Hz)

# ---------- Load simulated data ----------
df = pd.read_csv(LOOKUP_PATH)
df["m"] = df["m"].round(3)
df["L_mH"] = df["L_mH"].round(3)

M_VALUES = sorted(df["m"].unique().tolist())
R_VALUES = sorted(df["R_ohm"].unique().tolist())
L_VALUES = sorted(df["L_mH"].unique().tolist())
MF_VALUES = sorted(df["mf"].unique().tolist())

app = Flask(__name__)
lock = threading.Lock()

ser = None
if SERIAL_PORT and serial:
    ser = serial.Serial(SERIAL_PORT, BAUD, timeout=2)

# ---------- Lookup from simulation ----------
def optimize(m, R, L, target):
    rows = df[np.isclose(df["m"], m) & np.isclose(df["R_ohm"], R) & np.isclose(df["L_mH"], L)]
    rows = rows.sort_values("mf")
    if rows.empty:
        raise ValueError("No simulated data for this m, R and L combination.")

    feasible = rows[rows["THD_I"] <= target]
    if not feasible.empty:
        pick = feasible.iloc[0]          # lowest carrier ratio that meets the target
        note = "Target met at the lowest simulated carrier ratio that meets it."
    else:
        pick = rows.loc[rows["THD_I"].idxmin()]
        note = "Target not reachable with the simulated carrier ratios. Showing the lowest simulated THD."

    base = rows[rows["mf"] == 51]["THD_I"]
    mf = int(pick["mf"])
    return {
        "mf": mf,
        "fsw_hz": mf * F0,
        "thd_i": round(float(pick["THD_I"]), 4),
        "baseline_mf51": round(float(base.iloc[0]), 4) if not base.empty else None,
        "note": note,
    }

# ---------- Send the chosen carrier ratio to the controller ----------
def send_to_controller(mf):
    if ser is None:
        return "Simulation only: no serial port configured."
    with lock:
        ser.write(f"MF {mf}\n".encode())
        ack = ser.readline().decode(errors="ignore").strip()
    return ack or "No acknowledgment from controller."

# ---------- Web page ----------
PAGE = """
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>THD Optimizer</title>
  <style>
    body { font-family: Arial, sans-serif; max-width: 560px; margin: 40px auto; padding: 0 16px; }
    label { display: block; margin-top: 16px; font-weight: bold; }
    select, input[type=number] { width: 140px; padding: 6px; }
    button { margin-top: 20px; padding: 8px 16px; margin-right: 8px; }
    #out { margin-top: 24px; padding: 12px; background: #f3f3f3; border-radius: 6px; white-space: pre-line; }
  </style>
</head>
<body>
  <h2>Closed-loop THD Optimizer</h2>

  <label>Modulation index (m)</label>
  <select id="m">
    {% for v in m_values %}<option value="{{ v }}" {% if v == 0.8 %}selected{% endif %}>{{ v }}</option>{% endfor %}
  </select>

  <label>Load resistance (ohm)</label>
  <select id="R">
    {% for v in R_values %}<option value="{{ v }}" {% if v == 10 %}selected{% endif %}>{{ v }}</option>{% endfor %}
  </select>

  <label>Load inductance (mH)</label>
  <select id="L">
    {% for v in L_values %}<option value="{{ v }}" {% if v == 10 %}selected{% endif %}>{{ v }}</option>{% endfor %}
  </select>

  <label>Target THD_I (%)</label>
  <input id="target" type="number" step="0.001" min="0" value="0.1">

  <div>
    <button onclick="optimize()">Optimize</button>
    <button onclick="apply()">Apply to controller</button>
  </div>

  <div id="out">Choose values and click Optimize.</div>

<script>
let lastMf = null;

async function optimize() {
  const body = {
    m: parseFloat(document.getElementById("m").value),
    R: parseFloat(document.getElementById("R").value),
    L: parseFloat(document.getElementById("L").value),
    target: parseFloat(document.getElementById("target").value)
  };
  const r = await fetch("/api/optimize", {
    method: "POST", headers: {"Content-Type": "application/json"},
    body: JSON.stringify(body)
  });
  const d = await r.json();
  if (d.error) { document.getElementById("out").textContent = d.error; lastMf = null; return; }
  lastMf = d.mf;
  let text = "Carrier ratio: " + d.mf + "\\n" +
             "Switching frequency: " + d.fsw_hz + " Hz\\n" +
             "Simulated THD_I: " + d.thd_i + " %\\n";
  if (d.baseline_mf51 !== null) text += "THD_I at mf = 51: " + d.baseline_mf51 + " %\\n";
  text += d.note;
  document.getElementById("out").textContent = text;
}

async function apply() {
  if (lastMf === null) { alert("Run Optimize first."); return; }
  const r = await fetch("/api/apply", {
    method: "POST", headers: {"Content-Type": "application/json"},
    body: JSON.stringify({mf: lastMf})
  });
  const d = await r.json();
  document.getElementById("out").textContent += "\\n\\nController: " + (d.message || d.error);
}
</script>
</body>
</html>
"""

@app.route("/")
def index():
    return render_template_string(PAGE, m_values=M_VALUES, R_values=R_VALUES, L_values=L_VALUES)

@app.route("/api/optimize", methods=["POST"])
def api_optimize():
    data = request.get_json(force=True)
    try:
        m = float(data["m"])
        R = float(data["R"])
        L = float(data["L"])
        target = float(data["target"])
    except (KeyError, TypeError, ValueError):
        return jsonify({"error": "Missing or invalid input."}), 400

    if target < 0:
        return jsonify({"error": "Target THD_I must be zero or positive."}), 400
    if not any(np.isclose(m, v) for v in M_VALUES):
        return jsonify({"error": "Modulation index is not in the simulated set."}), 400
    if not any(np.isclose(R, v) for v in R_VALUES):
        return jsonify({"error": "Load resistance is not in the simulated set."}), 400
    if not any(np.isclose(L, v) for v in L_VALUES):
        return jsonify({"error": "Load inductance is not in the simulated set."}), 400

    try:
        return jsonify(optimize(m, R, L, target))
    except ValueError as e:
        return jsonify({"error": str(e)}), 400

@app.route("/api/apply", methods=["POST"])
def api_apply():
    data = request.get_json(force=True)
    mf = int(data["mf"])
    if mf not in MF_VALUES:
        return jsonify({"error": "Carrier ratio is not in the simulated set."}), 400
    return jsonify({"message": send_to_controller(mf)})

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=False)