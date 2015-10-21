#|
 This file is a part of Radiance
 (c) 2014 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:modularize-user)
(define-module remote-auth
  (:use #:cl #:radiance)
  (:implements #:auth)
  (:domain "auth"))
(in-package #:remote-auth)

(defun auth:current (&optional (session *session*))
  (session:field session 'user))

(defun auth:associate (user &optional (session *session*))
  (v:info :auth "Associating ~a with ~a and prolonging for ~a"
          session user auth:*login-timeout*)
  (setf (session:field session 'user) user)
  (incf (session:timeout session)
        (case auth:*login-timeout*
          ((NIL) 0)
          ((T) (* 60 60 24 365 100))
          (otherwise auth:*login-timeout*)))
  (trigger 'auth:associate session))

(defun auth:login! (&optional (landing-page (referer *request*)) (session *session*))
  (setf (session:field session 'landing-page) landing-page)
  (redirect #@"auth/login"))

(defmacro with-south-vars ((&optional access-token access-secret) &body body)
  `(south:with-oauth-environment
       (:oauth/request-token (config-tree :remote-auth :request-token)
        :oauth/authenticate (config-tree :remote-auth :authenticate)
        :oauth/access-token (config-tree :remote-auth :access-token)
        :api-key (config-tree :remote-auth :api-key)
        :api-secret (config-tree :remote-auth :api-secret)
        :access-token ,access-token
        :access-secret ,access-secret)
     ,@body))

(define-api simple-auth/logout () ()
  (if (auth:current)
      (progn (session:end *session*)
             (api-output "Logged out."))
      (error 'api-error :message "You are not logged in.")))

(define-resource-locator page (module (eql (interface :auth))) (page &rest args)
  (cond ((string-equal page "login")
         (let ((landing (first args)))
           (make-uri :domains (list "auth")
                     :path "login"
                     :get `(("landing-page" ,(etypecase landing
                                               (null "")
                                               (string landing)
                                               (uri (uri-to-url landing :representation :external))))))))
        (T (call-next-method))))

(define-page logout #@"auth/logout" ()
  (session:end *session*)
  (redirect (or (session:field *session* 'landing-page) "/")))

(define-page login #@"auth/login" ()
  (with-south-vars ()
    (when (post/get "landing-page")
      (setf (session:field session 'landing-page) (post/get "landing-page")))
    (redirect (south:initiate-authentication :method (uri-to-url #@"/api/remote-auth/callback" :representation :external)))))

(define-api remote-auth/callback (oauth_verifier &optional oauth_token) ()
  (with-south-vars ()
    (south:complete-authentication oauth_verifier oauth_token)
    (let ((username (south:signed-request (config-tree :remote-auth :username))))
      (auth:associate (user:get username :if-does-not-exist (or (config-tree :remote-auth :if-user-does-not-exist)
                                                                :error)))
      (redirect (or (session:field *session* 'landing-page) #@"/")))))
