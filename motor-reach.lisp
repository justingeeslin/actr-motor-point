;;; Compatibility loader for existing Lisp projects using this repository.
;;; The canonical implementation is also bundled in the Python distribution.
(load (merge-pathnames "src/actr_motor_point/motor-reach.lisp" *load-truename*))
