;;; ACT-R 7 spatial reaching extension. Load after ACT-R, before defining models.
;;; See README.md for units, assumptions, and integration.

#+:packaged-actr (in-package :act-r)
#+(and :clean-actr (not :packaged-actr) :allegro-ide) (in-package :cg-user)
#-(or (not :clean-actr) :packaged-actr :allegro-ide) (in-package :cl-user)

(defmacro with-reach-lock ((lock) &body body)
  ;; ACT-R's Lisp-only loader removes its temporary BT package after loading.
  #+:single-threaded-act-r (declare (ignore lock))
  #+:single-threaded-act-r `(progn ,@body)
  #-:single-threaded-act-r `(bt:with-recursive-lock-held (,lock) ,@body))

(defparameter *reach-limbs* '(left-hand right-hand left-foot right-foot))

(defun reach-real-p (value)
  ;; Reject NaN and infinities as well as complex numbers.
  (and (realp value)
       (handler-case (<= (- most-positive-double-float) value
                        most-positive-double-float)
         (arithmetic-error () nil))))

(defun reach-check-limb (limb)
  (unless (member limb *reach-limbs*)
    (error "Unknown reaching limb ~S; use one of ~S." limb *reach-limbs*))
  limb)

(defun reach-check-point (point)
  (unless (and (listp point) (= (length point) 3)
               (every #'reach-real-p point))
    (error "A reach position must be a list of three finite real numbers: ~S." point))
  (mapcar (lambda (x) (coerce x 'double-float)) point))

(defun reach-fitts-time (distance width &key (a 0.05d0) (b 0.10d0))
  "Shannon Fitts movement time in seconds. DISTANCE and WIDTH share units."
  (unless (and (every #'reach-real-p (list distance width a b))
               (>= distance 0) (> width 0) (>= a 0) (> b 0))
    (error "Fitts requires finite D >= 0, W > 0, a >= 0, and b > 0."))
  (+ (coerce a 'double-float)
     (* b (log (+ 1d0 (/ (coerce distance 'double-float) width)) 2d0))))

(defstruct reach-state
  (positions (make-hash-table))
  (profiles (make-hash-table))
  (lock #-:single-threaded-act-r (bt:make-recursive-lock "spatial-reaching")
        #+:single-threaded-act-r nil))

(defun reset-reach-state (state)
  (with-reach-lock ((reach-state-lock state))
    (clrhash (reach-state-positions state))
    (clrhash (reach-state-profiles state))
    (dolist (limb *reach-limbs*)
      ;; Illustrative defaults, deliberately identical across limbs.
      (setf (gethash limb (reach-state-positions state)) (list 0d0 0d0 0d0)
            (gethash limb (reach-state-profiles state)) (list 0.05d0 0.10d0))))
  state)

(defun create-reach-state (model-name)
  (declare (ignore model-name))
  (dolist (limb *reach-limbs*)
    (unless (chunk-p-fct limb)
      (define-chunks-fct (list (list limb 'name limb)))))
  (reset-reach-state (make-reach-state)))

(defun current-reach-state ()
  (or (get-module :spatial-reaching)
      (error "No reaching state. Select an ACT-R model created after loading motor-reach.lisp.")))

(defun reach-position (limb)
  "Return a copy of LIMB's last completed 3D position in the current model."
  (reach-check-limb limb)
  (let ((state (current-reach-state)))
    (with-reach-lock ((reach-state-lock state))
      (copy-list (gethash limb (reach-state-positions state))))))

(defun configure-reach-limb (limb &key (position nil position-p)
                                       (a nil a-p) (b nil b-p))
  "Set a model's initial limb position and/or Fitts coefficients while manual is free.
Settings return to defaults on ACT-R reset; configure again after resetting."
  (reach-check-limb limb)
  (when position-p (setf position (reach-check-point position)))
  (when (and a-p (not (and (reach-real-p a) (>= a 0))))
    (error "Reach coefficient a must be finite and nonnegative."))
  (when (and b-p (not (and (reach-real-p b) (> b 0))))
    (error "Reach coefficient b must be finite and positive."))
  (let ((motor (get-module :motor))
        (state (current-reach-state)))
    (with-reach-lock ((state-lock motor))
      (unless (eq (mode-s motor) 'free)
        (error "Configure reaching only while the manual module is free."))
      (with-reach-lock ((reach-state-lock state))
        (let ((old (gethash limb (reach-state-profiles state))))
          (setf (gethash limb (reach-state-profiles state))
                (list (if a-p (coerce a 'double-float) (first old))
                      (if b-p (coerce b 'double-float) (second old)))))
        (when position-p
          (setf (gethash limb (reach-state-positions state)) position)))))
  limb)

;; Companion state is owned by each model and participates in ACT-R reset/delete.
;; Movement scheduling remains entirely in the stock motor module.
(define-module-fct :spatial-reaching nil nil
  :version "1.0.0"
  :documentation "Per-model 3D positions and Fitts parameters for manual reaches."
  :creation 'create-reach-state :reset 'reset-reach-state)

(defclass reach (movement-style)
  ((limb :accessor reach-limb :initarg :limb :initform nil)
   (target-x :accessor reach-x :initarg :target-x :initform nil)
   (target-y :accessor reach-y :initarg :target-y :initform nil)
   (target-z :accessor reach-z :initarg :target-z :initform nil)
   (target-width :accessor reach-width :initarg :target-width :initform nil)
   (distance :accessor reach-distance :initform nil)
   (movement-time :accessor reach-movement-time :initform nil))
  (:default-initargs :style-name :reach
    :feature-slots '(limb target-x target-y target-z target-width)))

(defmethod reach ((motor motor-module) &key limb target-x target-y target-z
                                           target-width request-spec)
  ;; Validate before prepare-movement can set any motor states to BUSY.
  (handler-case
      (progn
        (reach-check-limb limb)
        (reach-check-point (list target-x target-y target-z))
        (unless (and (reach-real-p target-width) (> target-width 0))
          (error "Reach target-width must be finite and positive.")))
    (error (condition)
      (model-warning "Reach request rejected: ~A" condition)
      (return-from reach nil)))
  (unless (check-jam motor)
    (prepare-movement motor
      (make-instance 'reach :limb limb :target-x target-x :target-y target-y
        :target-z target-z :target-width target-width :request-spec request-spec))))

(defmethod feat-differences ((one reach) (two reach))
  (loop for slot in (feature-slots one)
        count (not (equalp (slot-value one slot) (slot-value two slot)))))

(defmethod compute-exec-time ((motor motor-module) (movement reach))
  ;; Compute at execution, not preparation: another reach may still be in flight
  ;; when this movement is prepared. No predicted-position reservations are needed.
  (let* ((state (current-reach-state))
         (target (reach-check-point
                  (list (reach-x movement) (reach-y movement) (reach-z movement)))))
    (with-reach-lock ((reach-state-lock state))
      (let* ((origin (gethash (reach-limb movement) (reach-state-positions state)))
             (profile (gethash (reach-limb movement) (reach-state-profiles state)))
             (distance (sqrt (loop for x in origin for y in target
                                   sum (expt (- y x) 2)))))
        (setf (updated-pos movement) target
              (reach-distance movement) distance
              (reach-movement-time movement)
              (reach-fitts-time distance (reach-width movement)
                                :a (first profile) :b (second profile)))))
    ;; ACT-R's initiation is separate from physical travel time.
    (with-reach-lock ((param-lock motor))
      (+ (init-time motor) (reach-movement-time movement)))))

(defmethod compute-finish-time ((motor motor-module) (movement reach))
  (declare (ignore motor))
  ;; Contact frees execution; there is no implicit recoil or return home.
  (exec-time movement))

(defun reach-complete-signal (model limb position width distance movement-time)
  (declare (ignore model limb position width distance movement-time))
  nil)

(add-act-r-command "reach-complete" 'reach-complete-signal
  "Reach contact notification. Monitor this; do not call it to move a limb. Params: model limb (x y z) width distance movement-time-seconds.")

(defun complete-spatial-reach (movement)
  (let ((state (current-reach-state)))
    (with-reach-lock ((reach-state-lock state))
      (setf (gethash (reach-limb movement) (reach-state-positions state))
            (copy-list (updated-pos movement)))))
  (evaluate-act-r-command "reach-complete" (current-model) (reach-limb movement)
    (copy-list (updated-pos movement)) (reach-width movement)
    (reach-distance movement) (reach-movement-time movement)))

(defmethod queue-output-events ((motor motor-module) (movement reach))
  (declare (ignore motor))
  ;; This event is inserted before the standard finish event at the same time,
  ;; so observers and any following queued movement see the completed position.
  (schedule-event-relative (seconds->ms (exec-time movement))
    'complete-spatial-reach :time-in-ms t :module :motor :output 'medium
    :params (list movement) :details "REACH-CONTACT"))

(extend-manual-requests (reach limb target-x target-y target-z target-width)
                        handle-style-request)

(provide "ACTR-MOTOR-REACH")
