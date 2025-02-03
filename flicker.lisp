(in-package #:org.shirakumo.fraf.trial)

(defvar *flicker-patterns* (make-hash-table :test 'eql))

(defun (setf flicker-pattern) (func name)
  (etypecase func
    (function (setf (gethash name *flicker-patterns*) func))
    (null (remhash name *flicker-patterns*))))

(defun flicker-pattern (name &optional (errorp T))
  (or (gethash name *flicker-patterns*)
      (when errorp (error "No flicker pattern with name ~s" name))))

(defun evaluate-flicker (name tt)
  (let ((func (or (gethash name *flicker-patterns*)
                  (error "No flicker pattern named ~s" name))))
    (declare (type (function (single-float) single-float) func))
    (funcall func (float tt 0f0))))

(define-compiler-macro evaluate-flicker (&whole whole name tt &environment env)
  (if (constantp name env)
      `(funcall (the (function (single-float) single-float)
                     (load-time-value (or (gethash ,name *flicker-patterns*)
                                          (error "No flicker pattern named ~s" ,name))))
                (float ,tt 0f0))
      whole))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun flicker-char-to-intensity (c)
    (assert (char<= #\a c #\z))
    (let ((i (- (char-code c) (char-code #\a))))
      (* 2.0 (/ i (- (char-code #\z) (char-code #\a)))))))

(defun compile-flicker-pattern (pattern &key (dt 1/10))
  (values
   `(lambda (tt)
      (declare (type single-float tt))
      (declare (optimize speed))
      (multiple-value-bind (i rest) (truncate (mod tt ,(float (* dt (length pattern)) 0f0)) ,dt)
        (declare (type (unsigned-byte 16) i))
        (let* ((a ,(map '(simple-array (single-float) (*)) #'flicker-char-to-intensity pattern))
               (l (aref a i))
               (r (aref a (mod (1+ i) ,(length pattern)))))
          (lerp l r (* rest ,(/ dt))))))
   (* (length pattern) dt)))

(defmacro define-flicker-pattern (name pattern &key (dt 1/10))
  `(setf (flicker-pattern ',name) (compile-flicker-pattern ,pattern :dt ,dt)))

;; Original Quake flicker patterns
(define-flicker-pattern normal "m")
(define-flicker-pattern flicker "mmnmmommommnonmmonqnmmo")
(define-flicker-pattern strong-pulse "abcdefghijklmnopqrstuvwxyzyxwvutsrqponmlkjihgfedcba")
(define-flicker-pattern candle "mmmmmaaaaammmmmaaaaaabcdefgabcdefg")
(define-flicker-pattern fast-strobe "mamamamamama")
(define-flicker-pattern gentle-pulse "jklmnopqrstuvwxyzyxwvutsrqponmlkj")
(define-flicker-pattern flicker-2 "nmonqnmomnmomomno")
(define-flicker-pattern candle-2 "mmmaaaabcdefgmmmmaaaammmaamm")
(define-flicker-pattern candle-3 "mmmaaammmaaammmabcdefaaaammmmabcdefmmmaaaa")
(define-flicker-pattern slow-strobe "aaaaaaaazzzzzzzz")
(define-flicker-pattern fluorescent-flicker "mmamammmmammamamaaamammma")
(define-flicker-pattern slow-pulse "abcdefghijklmnopqrrqponmlkjihgfedcba")
(define-flicker-pattern lightning "ccccccdcdcddcccccccccccddcdcccccceazzazyxvmmhgfecccccccccccdccccccccccc")
