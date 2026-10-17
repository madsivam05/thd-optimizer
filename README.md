\# THD Optimizer: Simulation-Based Carrier Ratio Selection for a Single-Phase Inverter



This project selects the switching carrier ratio of a single-phase SPWM inverter to meet a target current THD (THD\_I). It combines a Simulink simulation sweep, a regression study, and a web app that returns the simulated results for a chosen operating point.



\## Project contents



| Path | Description |

|---|---|

| `app.py` | Flask web app. Looks up THD\_I from the simulation table and optionally sends the carrier ratio to an ESP32 over USB. |

| `thd\_lookup.csv` | Simulation results used by the app (m, mf, R, L, THD\_I). |

| `thd\_simulation\_data.csv` | Full simulation output, including voltage THD and fundamental amplitude. |

| `matlab/` | MATLAB scripts and the Simulink model: `build\_EV\_ML\_THD\_SPWM.m` (builds the model), `collect\_thd\_data.m` (runs the sweep), `thd\_regression.m` (regression comparison). |

| `notebook/THD\_regression\_colab.ipynb` | Python regression study with the same train/test approach as the MATLAB script. |

| `requirements.txt`, `Procfile` | Dependencies and start command for deployment on Render. |



\## Simulation setup



\- Single-phase full-bridge inverter, bipolar sinusoidal PWM (SPWM), ideal switches

\- DC bus 200 V; RL load

\- Modulation index m: 0.4 to 1.0

\- Carrier ratio mf (switching frequency / 50 Hz): 51, 101, 151, 201 (odd values)

\- Load resistance R: 1 to 100 ohm; load inductance L: 1 to 100 mH

\- THD computed over 5 steady-state fundamental cycles, harmonics 2 to 50 (IEEE 519 convention)

\- Combinations with L/R above 20 ms were skipped to limit simulation time



\## Running the app



Local (with an optional ESP32 on a USB port):



pip install flask pandas numpy pyserial

python app.py





Open http://127.0.0.1:5000. To send commands to an ESP32, set the port first, for example `set SERIAL\_PORT=COM5` in Windows Command Prompt, or `$env:SERIAL\_PORT = "COM5"` in PowerShell.



Hosted: the app is deployed on Render from this repository. Hosted use is simulation-only, since the cloud server has no connection to a physical board.



\## Key results



\- Carrier ratio raised from 51 to 101 or higher reduces THD\_I substantially at most operating points.

\- The app returns the lowest simulated carrier ratio that meets the target.

\- The regression models predict THD\_I on an unseen load with a test error of about 0.05 percentage points. They are shown as a comparison, not as the app's source.



\## Limits



\- Results are from an ideal-switch simulation. Dead time, device voltage drop and switching losses are not modelled, so hardware THD will be higher.

\- THD\_I depends on L/R in this model, so many (R, L) pairs give identical results.

\- The app returns only simulated values; it does not interpolate or predict outside the table.

\- THD is measured up to the 50th harmonic (2.5 kHz). Switching sidebands above this range are not included.

\- The ESP32 firmware has no dead-time insertion yet; do not connect a power stage until dead time is added.



\## Author



Pandisivam S

