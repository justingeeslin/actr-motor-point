# ACT-R spatial motor reaching

An ACT-R 7 Common Lisp extension for pointing/reaching to controls in 3D with
`left-hand`, `right-hand`, `left-foot`, or `right-foot`. It adds the `reach`
command to the existing **manual buffer**, preserving ACT-R's motor preparation,
initiation, execution, and queuing. A small companion module keeps each model's
limb positions and timing coefficients separate.

Stock ACT-R supports keyboard actions and mouse/cursor pointing. This extension
adds a physical spatial coordinate system, including depth and feet; it does not
replace the stock motor module or require changes to ACT-R source.

## Include in another project

Use the official [ACT-R 7 distribution](https://act-r.psy.cmu.edu/software/)
and a supported Common Lisp implementation. No additional Lisp libraries are
needed beyond those included/required by ACT-R itself.

1. Copy `motor-reach.lisp` into your project's vendor/extensions directory.
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
runtime: **95 checks passed** in Lisp-only and threaded configurations. Other
ACT-R versions and Lisp implementations have not been tested. Run the two
configurations sequentially when sharing an ACT-R source directory because
ACT-R rebuilds its compiled files when switching configurations.

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
