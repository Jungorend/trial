(in-package #:org.shirakumo.fraf.trial)

(define-action-set system-action)

(define-action reload-scene (system-action))
(define-action quit-game (system-action))
(define-action toggle-overlay (system-action))

(defclass controller (entity listener)
  ((handlers :initform NIL :accessor handlers)
   (name :initform :controller)))

(defmethod handle ((ev quit-game) (controller controller))
  (quit *context*))

(defmethod handle ((ev event) (controller controller))
  (dolist (handler (handlers controller))
    (handle ev handler))
  (map-event ev (scene +main+)))

(defmethod handle ((ev lose-focus) (controller controller))
  (clear-retained))

(defmethod handle ((ev reload-scene) (controller controller))
  (let ((old (scene +main+)))
    (change-scene +main+ (make-instance (type-of old)))))

(defclass load-request (event)
  ((thing :initarg :thing)))

(define-handler (controller load-request) (thing)
  (typecase thing
    (asset
     (if (loaded-p thing)
         (reload thing)
         (load thing)))
    (resource
     (unless (allocated-p thing)
       (allocate thing)))
    (T
     (commit thing (loader +main+) :unload NIL))))

(defun maybe-reload-scene (&optional (main +main+))
  (when main
    (issue (scene main) 'reload-scene)))

(defclass eval-request (event)
  ((func :initarg :func)
   (return-values :accessor return-values)))

(define-handler (controller eval-request) (func)
  (let ((vals (multiple-value-list (funcall func))))
    (setf (return-values eval-request) vals)))

(defun call-in-render-loop (function scene &key block)
  (let ((event (issue scene 'eval-request :func function)))
    (when block
      (loop until (slot-boundp event 'return-values)
            do (sleep 0.01))
      (values-list (return-values event)))))

(defmacro with-eval-in-render-loop ((&optional (scene '(scene +main+)) &rest args) &body body)
  `(call-in-render-loop (lambda () ,@body) ,scene ,@args))

(define-shader-entity display-controller (controller debug-text)
  ((fps-buffer :initform (make-array 100 :fill-pointer T :initial-element 1) :reader fps-buffer)
   (observers :initform (make-array 0 :adjustable T :fill-pointer T) :accessor observers)
   (background :initform (vec4 1 1 1 0.3))
   (show-overlay :initform T :accessor show-overlay)))

(defmethod handle ((ev toggle-overlay) (controller display-controller))
  (setf (show-overlay controller) (not (show-overlay controller))))

(defmethod handle ((ev resize) (controller display-controller))
  (setf (font-size controller) (if (< 1920 (width ev)) 32 17)))

(defun compute-fps-buffer-fps (fps-buffer)
  (/ (loop for i from 0 below (array-total-size fps-buffer)
           sum (aref fps-buffer i))
     (array-total-size fps-buffer)))

(defmethod observe ((func function) &key title)
  (let ((observers (ignore-errors (observers (node :controller T)))))
    (when observers
      (let* ((title (or title (format NIL "~d" (length observers))))
             (position (position title observers :key #'car :test #'equal)))
        (if position
            (setf (aref observers position) (cons title func))
            (vector-push-extend (cons title func) observers))
        func))))

(defmethod observe (thing &rest args &key &allow-other-keys)
  (let ((func (compile NIL `(lambda (ev)
                              (declare (ignorable ev))
                              ,thing))))
    (apply #'observe func args)))

(defmacro observe! (form &rest args)
  (let ((ev (gensym "EV")))
    `(observe (lambda (,ev) (declare (ignore ,ev)) ,form) ,@args)))

(defmethod stop-observing (&optional title)
  (let ((observers (ignore-errors (observers (node :controller T)))))
    (when observers
      (if title
          (let ((pos (position title observers :key #'car :test #'equal)))
            (when pos (array-utils:vector-pop-position observers pos)))
          (loop for i from 0 below (array-total-size observers)
                do (setf (aref observers i) NIL)
                finally (setf (fill-pointer observers) 0))))))

(defparameter *controller-pprint*
  (let ((table (copy-pprint-dispatch)))
    (set-pprint-dispatch 'float (lambda (s o) (format s "~,3@f" o))
                         10 table)
    table))

(defun compose-controller-debug-text (controller ev)
  (multiple-value-bind (gfree gtotal) (gpu-room)
    (multiple-value-bind (cfree ctotal) (cpu-room)
      (with-output-to-string (stream)
        (format stream "FPS  [Hz]: ~8,2f~%~
                        RAM  [KB]: ~8d (~2d%)~%~
                        VRAM [KB]: ~8d (~2d%)~%~
                        RESOURCES: ~8d"
                (compute-fps-buffer-fps (fps-buffer controller))
                (- ctotal cfree) (floor (/ (- ctotal cfree) ctotal 0.01))
                (- gtotal gfree) (floor (/ (- gtotal gfree) gtotal 0.01))
                (hash-table-count (loaded (loader +main+))))
        (let ((*print-pprint-dispatch* *controller-pprint*))
          (loop with observers = (observers controller)
                for i from 0 below (length observers)
                for (title . func) = (aref observers i)
                when func
                do (restart-case (format stream "~%~a:~12t~a" title (funcall func ev))
                     (remove-observer ()
                       :report "Remove the offending observer."
                       (setf (aref observers i) NIL)))))))))

(defmethod handle ((ev tick) (controller display-controller))
  (when (and (show-overlay controller)
             *context*)
    (setf (text controller) (compose-controller-debug-text controller ev))
    (setf (vy (location controller)) (- (vy (size controller)) (font-size controller)))
    (setf (vx (location controller)) 5)))

(defmethod apply-transforms progn ((controller display-controller))
  )

(defmethod render :around ((controller display-controller) (program shader-program))
  (when (show-overlay controller)
    (with-pushed-matrix ((view-matrix :identity)
                         (projection-matrix :identity))
      (orthographic-projection 0 (width *context*)
                               0 (height *context*)
                               0 10)
      (translate-by 2 (- (height *context*) 14) 0)
      (let ((fps-buffer (fps-buffer controller)))
        (when (= (array-total-size fps-buffer) (fill-pointer fps-buffer))
          (setf (fill-pointer fps-buffer) 0))
        (vector-push (if (= 0 (frame-time +main+))
                         1
                         (/ (frame-time +main+)))
                     fps-buffer))
      (call-next-method))))
