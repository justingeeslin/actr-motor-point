;;; Load motor-reach.lisp before this model. Coordinates and widths are in cm.
#+:packaged-actr (in-package :act-r)

(clear-all)

(define-model reaching-controls
  (sgp :v t :esc t :randomize-time nil)
  (chunk-type reach-task step)
  (define-chunks (start isa reach-task step hand)
                 (hand) (foot) (done))
  (goal-focus start)

  (p reach-panel
    =goal> isa reach-task step hand
    ?manual> state free
    ==>
    +manual> isa reach limb right-hand
             target-x 30 target-y 40 target-z 0 target-width 5
    =goal> step foot)

  (p reach-pedal
    =goal> isa reach-task step foot
    ?manual> state free
    ==>
    +manual> isa reach limb left-foot
             target-x -10 target-y 50 target-z -60 target-width 10
    =goal> step done))

(defun run-reaching-controls ()
  (reset)
  (configure-reach-limb 'right-hand :position '(0 0 0) :a 0.05 :b 0.10)
  (configure-reach-limb 'left-foot :position '(-10 0 -60) :a 0.08 :b 0.15)
  (run 5))

;;; (run-reaching-controls)
