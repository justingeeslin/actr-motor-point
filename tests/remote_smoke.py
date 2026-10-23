"""Installed-wheel smoke test. Requires a fresh running ACT-R remote server.

Put ACT-R's tutorial/python directory on PYTHONPATH before running this script.
Pass the reaching-controls.lisp example's absolute path on the server filesystem.
"""

import sys

import actr
import actr_motor_point as reaching


reaching.load(actr=actr)
assert actr.load_act_r_model(sys.argv[1]), "example model failed to load"
actr.reset()
reaching.configure_limb("right-hand", position=[0, 0, 0], a=0, b=.1, actr=actr)
reaching.configure_limb("left-foot", position=[-10, 0, -60], a=.08, b=.15, actr=actr)
assert reaching.position("left-foot", actr=actr) == [-10, 0, -60]
actr.run(5)
assert reaching.position("right-hand", actr=actr) == [30, 40, 0]
assert reaching.position("left-foot", actr=actr) == [-10, 50, -60]
actr.reset()
assert reaching.position("left-foot", actr=actr) == [0, 0, 0]
print("PASS: installed wheel loads, configures, runs reaches, and reads/reset positions over ACT-R RPC")
