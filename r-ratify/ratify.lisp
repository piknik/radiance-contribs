#|
 This file is a part of Radiance
 (c) 2014 TymoonNET/NexT http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:modularize-user)
(define-module #:r-ratify
  (:use #:cl #:radiance)
  (:export
   #:session-var
   #:with-form
   #:define-form-parser
   #:define-form-getter
   #:verify-nonce))
(in-package #:r-ratify)

(defun session-var (var &optional (session *session*))
  (session:field session var))

(ratify:define-test user (name)
  (unless (user:get name :if-does-not-exist NIL)
    (ratify:ratification-error name "No user with name ~a found." name)))

(ratify:define-parser user (name)
  (user:get name))

;; spec
;; parse-form ::= (type var*)
;; type       ::= name | (name arg*)
;; var        ::= name | (func name arg*)
(defvar *form-parsers* (make-hash-table))
(defvar *form-getters* (make-hash-table))

(defmacro with-form (parse-forms &body body)
  (flet ((parser (type getter-form)
           (destructuring-bind (type &rest args) (if (listp type) type (list type))
             (let ((parser (gethash type *form-parsers*)))
               (if parser
                   (apply parser getter-form args)
                   `(ratify:parse ,type ,getter-form)))))
         (getter (var)
           (destructuring-bind (func var &rest args) (if (listp var) var (list :post/get var))
             (let ((getter (gethash func *form-getters*)))
               (if getter
                   (apply getter (string var) args)
                   `(funcall ,func ,(string var) ,@args))))))
    (let* ((enumerated-forms
             (loop for (type . vars) in parse-forms
                   appending (loop for var in vars
                                   collect `(,type ,var)))))
      `(progv ',(loop for (type var) in enumerated-forms
                      collect (if (listp var) (second var) var))
           (ratify:with-errors-combined
             (list
              ,@(loop for (type var) in enumerated-forms
                      collect (parser type (getter var)))))
         ,@body))))

(defmacro define-form-getter (name args &body body)
  `(setf (gethash ,(intern (string name) "KEYWORD") *form-getters*)
         #'(lambda ,args ,@body))))

(defmacro define-form-parser (name args &body body)
  `(setf (gethash ,(intern (string name) "KEYWORD") *form-parsers*)
         #'(lambda ,args ,@body)))

(define-form-getter get (var &optional (request '*request*))
  `(get-var ,var ,request))

(define-form-getter post (var &optional (request '*request*))
  `(post-var ,var ,request))

(define-form-getter post/get (var &optional (request '*request*))
  `(post/get ,var ,request))

(define-form-getter session (var &optional (session '*session*))
  `(session:field ,session ,var))

(defun verify-nonce (nonce &key (hash (session-var "nonce-salt")) (salt (session-var "nonce-hash")))
  (if (string= hash (cryptos:pbkdf2-hash nonce salt))
      nonce
      (ratify:ratification-error nonce "Invalid nonce.")))

(define-form-parser nonce (getter &optional hash salt)
  `(verify-nonce ,getter ,@(when salt `(:salt ,salt)) ,@(when hash `(:hash ,hash))))
