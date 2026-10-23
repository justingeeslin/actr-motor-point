# ACT-R spatial motor reaching

An ACT-R 7 Common Lisp extension for pointing/reaching to controls in 3D with
`left-hand`, `right-hand`, `left-foot`, or `right-foot`. It adds the `reach`
command to the existing **manual buffer**, preserving ACT-R's motor preparation,
initiation, execution, and queuing. A small companion module keeps each model's
limb positions and timing coefficients separate.

Stock ACT-R supports keyboard actions and mouse/cursor pointing. This extension
adds a physical spatial coordinate system, including depth and feet; it does not
replace the stock motor module or require changes to ACT-R source.

## Install as a Python dependency

Python 3.9+ is supported. The package bundles the Lisp implementation and a
small Python API; ACT-R itself and its official `actr.py` interface remain
external prerequisites. Installing or importing this package does not start or
connect to ACT-R. No unrelated PyPI package named `actr` is installed.

From this checkout:

```sh
python -m pip install /path/to/actr-motor-point
# Or, for development:
python -m pip install -e /path/to/actr-motor-point
```

Once these changes are committed and pushed to the repository, another project's
`requirements.txt` can contain:

```text
actr-motor-point @ git+https://github.com/justingeeslin/actr-motor-point.git@COMMIT_SHA
```

Replace `COMMIT_SHA` with a real commit containing the package. Pinning the commit
makes installation reproducible. In that project's `pyproject.toml`, use:

```toml
[project]
dependencies = [
  "actr-motor-point @ git+https://github.com/justingeeslin/actr-motor-point.git@COMMIT_SHA",
]
```

For a private repository, use your existing Git authentication. This package has
not been published to PyPI; `pip install actr-motor-point` alone is not yet an
installation route. You can also distribute the wheel directly:

```sh
python -m pip wheel . --no-deps --wheel-dir dist
python -m pip install /path/to/actr_motor_point-1.0.0-py3-none-any.whl
```

Use it with an already running ACT-R server and your existing Python interface:

```python
import actr  # official ACT-R tutorial/python/actr.py, already on your Python path
import actr_motor_point as reaching

# Once per ACT-R server startup, BEFORE loading/defining models:
reaching.load(actr=actr)
actr.load_act_r_model("/absolute/path/to/your-model.lisp")
actr.reset()
reaching.configure_limb(
    "right-hand", position=[0, 0, 0], a=0.05, b=0.10, actr=actr
)
actr.run(10)
print(reaching.position("right-hand", actr=actr))
```

Requests inside the model use `+manual> isa reach` as documented below. Reapply
configuration after every `actr.reset()`. With multiple models, select a model
through your ACT-R interface before configuring or reading a limb. You may omit
`actr=` to lazily import the official interface. Load once at server startup;
repeated loads redefine ACT-R modules and are not a safe per-run operation.

**Remote servers and Docker:** ACT-R resolves Lisp paths on its own filesystem.
The default loader works when Python and ACT-R share the package's filesystem.
For a separate host or container, copy the actual bundled source into a mounted
or remote directory and provide its path as seen by ACT-R:

```python
from pathlib import Path

Path("/local/shared/motor-reach.lisp").write_text(reaching.lisp_source(), encoding="utf-8")
# If /local/shared is mounted as /extensions in ACT-R's container:
reaching.load(actr=actr, server_path="/extensions/motor-reach.lisp")
```

The helper does not transfer files over the ACT-R connection. Configuration and
position access use the registered `configure-reach-limb` and `reach-position`
remote commands. Failed server calls raise `RuntimeError`; consult ACT-R's
warning trace for the detailed validation or connection error.

## Include in another project

Use the official [ACT-R 7 distribution](https://act-r.psy.cmu.edu/software/)
and a supported Common Lisp implementation. No additional Lisp libraries are
needed beyond those included/required by ACT-R itself.

1. Copy `src/actr_motor_point/motor-reach.lisp` into your project's
   vendor/extensions directory. The repository-root `motor-reach.lisp` is a
   compatibility loader that requires the checkout's `src/` directory.
2. Load ACT-R first, then this file **once, before defining/loading any models**.
3. Load your model. Configure limb starting positions and coefficients after
   each `reset`, before running it.

```lisp
;; Lisp-only execution; use load-act-r.lisp for the GUI/remote interface instead.
(load "/path/to/actr7.x/load-single-threaded-act-r.lisp")
(load "/path/to/your-project/extensions/motor-reach.lisp")
(load "/path/to/your-project/model.lisp")
(reset)
(configure-reach-limb 'right-hand :position '(0 0 0) :a 0.05 :b 0.10)
(configure-reach-limb 'left-foot :position '(-10 0 -60) :a 0.08 :b 0.15)
(run 10)
```

For a project-relative loader, resolve the extension against the loader's own
pathname, rather than the process working directory:

```lisp
;; In your project's load-project.lisp, after loading ACT-R:
(load (merge-pathnames "extensions/motor-reach.lisp" *load-truename*))
(load (merge-pathnames "model.lisp" *load-truename*))
```

Alternatively, place the file in ACT-R's `user-loads/` directory for automatic
loading. Do not also load a second copy manually. If models already existed when
the extension loaded, clear and redefine them; resetting alone does not add new
manual request chunk types. With packaged ACT-R, use these functions/symbols from
the `ACT-R` package, consistent with your other model code.

## Request a reach

Inside a production:

```lisp
?manual>
  state free
==>
+manual>
  isa reach
  limb right-hand
  target-x 30
  target-y 40
  target-z 0
  target-width 5
```

All five feature slots are required. Limb values are exactly `left-hand`,
`right-hand`, `left-foot`, and `right-foot`. Coordinates must be finite real
numbers and width must be positive. Invalid requests issue a model warning and
do not start a movement. Query `?manual> state free` before ordinary requests;
for deliberate preparation/execution overlap, `preparation free` allows the
stock motor scheduler to queue another reach. Movements execute serially across
all four limbs, sharing the stock motor execution resource.

Represent an object's center and usable width in your task/goal or retrieved
chunk, then bind those values into the request. For example, if the goal chunk
has `control-x`, `control-y`, `control-z`, and `control-width`:

```lisp
(p reach-known-control
  =goal>
    isa control-task
    control-x =x control-y =y control-z =z control-width =w
    step point
  ?manual> state free
  ==>
  +manual> isa reach limb left-hand
           target-x =x target-y =y target-z =z target-width =w
  =goal> step wait-for-contact)
```

Define `control-task` and the `point`/`wait-for-contact` state chunks in your model.
The extension does not automatically infer an object's physical depth from the
visual module's screen coordinates.

## Geometry and time

Choose any consistent length unit, such as centimeters. Use a shared, fixed
coordinate frame for the user, all limb starting positions, and all targets. For
example, origin at the user's torso, x to the right, y forward, z upward. An
object's distance from the torso influences its coordinates; **movement distance
is measured from the selected limb's previous endpoint**:

```text
D  = sqrt((target-x - limb-x)^2 + (target-y - limb-y)^2 + (target-z - limb-z)^2)
ID = log2(1 + D / W)
MT = a + b * ID
```

`W` is the usable target extent along the approach direction, expressed in the
same units as `D`. For a spherical target it can be its diameter; for a panel
control or pedal, provide an appropriate effective acquisition width for the
task. The modeler supplies this scalar width; no surface projection is inferred.
This is the Shannon formulation of Fitts' law, applied to 3D straight-line
distance. See [MacKenzie (1992), *Fitts' Law as a Research and Design Tool in
Human–Computer Interaction*](https://www.yorku.ca/mack/hci1992.html).

Coefficients are in seconds: `a >= 0`, `b > 0`. Defaults are **illustrative**
`a = 0.05`, `b = 0.10` for every limb, not fitted hand/foot predictions. Fit each
limb's coefficients to data from your population, posture, and control geometry.
`reach-fitts-time` exposes the equation for analysis:

```lisp
(reach-fitts-time 50 5 :a 0.05 :b 0.10) ; approximately 0.396 seconds
```

Physical movement time is separate from ACT-R's feature preparation and motor
initiation time. With default ACT-R settings, the first reach prepares six
features (style plus five slots), taking 0.300 s, then initiates for 0.050 s,
then travels for `MT`. A 50-unit reach to a 5-unit target therefore contacts at
approximately 0.746 s after the request, excluding production firing latency and
any queue wait. Repeated reaches reuse unchanged features through ACT-R's style
mechanism. `:randomize-time` can affect preparation through ACT-R; the extension's
Fitts travel time is deterministic. Stock `:min-fitts-time`, cursor noise, and
cursor Fitts coefficients do not change reaches.

At zero distance, travel takes `a`. There is no automatic recoil, return home,
or added motor burst after contact. Position is updated only at contact and is
retained for the next reach. For queued movements, distance is calculated when
execution starts, so a preceding reach can finish while the next one prepares.

## Configure and inspect limbs

```lisp
(configure-reach-limb 'right-foot :position '(10 0 -60) :a 0.08 :b 0.15)
(configure-reach-limb 'left-hand :b 0.12) ; leave other values unchanged
(reach-position 'right-foot)            ; returns a fresh (x y z) list
```

All limbs initially start at `(0 0 0)`. Set realistic starting positions for your
task. Configuration is permitted only while the manual module is free; it is an
initialization operation, not a movement. Configuration errors signal Lisp errors.
`reset` cancels scheduled reaches and restores all positions and coefficients to
defaults. Reapply project setup after each reset, as the example runner does.
`clear-all` removes model state; loading the model again creates fresh state.

## Connect to a task or simulator

Monitor the ACT-R command `reach-complete`. It fires once at contact, after the
position is updated. Its arguments are:

```text
model-name limb (x y z) target-width distance movement-time-seconds
```

Lisp example:

```lisp
(defun my-control-contact (model limb position width distance movement-time)
  (declare (ignore width distance movement-time))
  (format t "~A: ~A contacted ~S at ~,3F s~%" model limb position (mp-time))
  ;; Update your task/simulator here, or schedule a perceptual consequence.
  )
(add-act-r-command "my-control-contact" 'my-control-contact "Handle spatial contact.")
(monitor-act-r-command "reach-complete" "my-control-contact")
;; When finished:
;; (remove-act-r-command-monitor "reach-complete" "my-control-contact")
;; (remove-act-r-command "my-control-contact")
```

The same signal can be monitored with ACT-R's Python remote interface after the
Lisp extension and model are loaded in the server:

```python
import actr

def contact(model, limb, position, width, distance, movement_time):
    print(model, limb, position, movement_time)

actr.add_command("python-contact", contact, "Handle spatial contact")
actr.monitor_command("reach-complete", "python-contact")
# ... run the model ...
actr.remove_command_monitor("reach-complete", "python-contact")
actr.remove_command("python-contact")
```

Reaching produces contact only; it does not press a keyboard key, click a mouse,
grasp an object, or depress a pedal automatically. Your task adapter determines
the contacted control from its geometry and defines what contact does. Models
can use manual state becoming free to sequence actions; sensory feedback should
be supplied by the task adapter as appropriate.

## Example and tests

```lisp
(load "/path/to/actr-motor-point/examples/reaching-controls.lisp")
(run-reaching-controls)
```

The example reaches a panel with the right hand and a pedal with the left foot.
Swap `limb` to use the other hand or foot. Loading the example calls `clear-all`,
so run it in a session where replacing existing models is intended.

Run integration tests with SBCL and the ACT-R source distribution:

```sh
sbcl --script tests/run.lisp /path/to/actr7.x/load-single-threaded-act-r.lisp
```

Tests exercise real buffer requests, scheduled contacts, all four limbs, 3D and
successive distances, pipelined reaches, input rejection, reset during flight,
model isolation, coexistence with stock motor actions, and the example model.

For the threaded runtime, load your Quicklisp setup before the script and pass
`load-act-r.lisp` instead:

```sh
sbcl --load /path/to/quicklisp/setup.lisp --script tests/run.lisp /path/to/actr7.x/load-act-r.lisp
```

Validated with ACT-R **7.31.4-<3489:2026-06-10>** using SBCL in a local Docker
runtime: **98 checks passed** in Lisp-only and threaded configurations. Other
ACT-R versions and Lisp implementations have not been tested. Run the two
configurations sequentially when sharing an ACT-R source directory because
ACT-R rebuilds its compiled files when switching configurations.

Python packaging tests (run after installing the wheel):

```sh
python -m unittest discover -s tests -p 'test_*.py'
```

Eight Python tests cover bundled resources, server paths, argument forwarding,
lazy imports, and failed server calls. The installed wheel has also been tested
against a fresh ACT-R server using the official Python interface, including
loading the bundled source, configuring limbs, running the example, reading
positions, and reset. To repeat that smoke test with your server:

```sh
python tests/remote_smoke.py /absolute/server/path/to/examples/reaching-controls.lisp
```

Use a fresh server for the smoke test; it loads the extension and replaces
existing models with the example.

## Scope and compatibility

This is a straight-line acquisition timing model. It does not implement inverse
kinematics, posture, obstacles, reach limits, fatigue, trajectories, misses, or
simultaneous limb execution. Coordinates are independent of ACT-R's keyboard
and mouse hand coordinates: stock typing/cursor actions do not update the 3D
positions. Supply explicit task transitions/starting positions when switching
between those representations. A manual `clear` retains ACT-R's native behavior
(it is not a cancellation of an already executing movement); use `reset` when
discarding a run. Explicit `prepare style reach` requests are unsupported; use
`isa reach` requests.

Implementation follows the official distribution's
`examples/extend-manual-requests/using-a-style/new-style.lisp`,
`core-modules/motor.lisp`, and `support/general-pm.lisp`. It uses the supported
`extend-manual-requests` mechanism plus CLOS motor/style internals, which may
change across ACT-R releases. See the official [reference manual and release
downloads](https://act-r.psy.cmu.edu/software/) and [source-loading
instructions](https://act-r.psy.cmu.edu/actr7.x/QuickStart.txt).
