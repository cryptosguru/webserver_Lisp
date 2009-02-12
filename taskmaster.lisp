;;; -*- Mode: LISP; Syntax: COMMON-LISP; Base: 10 -*-
;;; $Header$

;;; Copyright (c) 2004-2009, Dr. Edmund Weitz.  All rights reserved.

;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions
;;; are met:

;;;   * Redistributions of source code must retain the above copyright
;;;     notice, this list of conditions and the following disclaimer.

;;;   * Redistributions in binary form must reproduce the above
;;;     copyright notice, this list of conditions and the following
;;;     disclaimer in the documentation and/or other materials
;;;     provided with the distribution.

;;; THIS SOFTWARE IS PROVIDED BY THE AUTHOR 'AS IS' AND ANY EXPRESSED
;;; OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
;;; WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
;;; DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
;;; DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
;;; GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
;;; WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;;; NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;;; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

(in-package :hunchentoot)

(defclass taskmaster ()
  ((acceptor :accessor taskmaster-acceptor
             :documentation "The acceptor instance that this
taskmaster works for."))
  (:documentation "Base class for all taskmaster classes.  Its purpose
is to carry the back pointer to the acceptor instance."))

(defgeneric execute-acceptor (taskmaster)
  (:documentation
   "This function is called once Hunchentoot has performed all initial
processing to start listening for incoming connections.  It does so by
calling the ACCEPT-CONNECTIONS functions of the acceptor, taken from
the ACCEPTOR slot of the taskmaster instance.

In a multi-threaded environment, the taskmaster starts a new
thread and calls THUNK in that thread.  In a single-threaded
environment, the thunk will be called directly."))

(defgeneric handle-incoming-connection (taskmaster socket)
  (:documentation
   "This function is called by Hunchentoot to start processing of
requests on a new incoming connection.  SOCKET is the usocket instance
that represents the new connection \(or a socket handle on LispWorks).
The taskmaster starts processing requests on the incoming
connection by calling the START-REQUEST-PROCESSING function of the
acceptor instance, taken from the ACCEPTOR slot in the taskmaster
instance.  The SOCKET argument is passed to START-REQUEST-PROCESSING
as argument.

In a multi-threaded environment, the taskmaster runs this function
in a separate thread.  In a single-threaded environment, this function
is called directly."))

(defgeneric shutdown (taskmaster)
  (:documentation "Terminate all threads that are currently associated
with the taskmaster, if any."))

(defclass single-threaded-taskmaster (taskmaster)
  ()
  (:documentation "Taskmaster that runs synchronously in the
thread that invoked the START-SERVER function."))

(defmethod execute-acceptor ((taskmaster single-threaded-taskmaster))
  (accept-connections (taskmaster-acceptor taskmaster)))

(defmethod handle-incoming-connection ((taskmaster single-threaded-taskmaster) socket)
  (process-connection (taskmaster-acceptor taskmaster) socket))

(defclass one-thread-per-taskmaster (taskmaster)
  ((acceptor-process :accessor acceptor-process
                     :documentation "Process that accepts incoming
connections and hands them off to new processes for request
handling."))
  (:documentation "Taskmaster that starts one thread for
listening to incoming requests and one thread for each incoming
connection."))

;; usocket implementation

#-:lispworks
(defmethod shutdown ((taskmaster taskmaster)))

#-:lispworks
(defmethod shutdown ((taskmaster one-thread-per-taskmaster))
  ;; just wait until the acceptor process has finished, then return
  (loop
   (unless (bt:thread-alive-p (acceptor-process taskmaster))
     (return))
   (sleep 1)))

#-:lispworks
(defmethod execute-acceptor ((taskmaster one-thread-per-taskmaster))
  (setf (acceptor-process taskmaster)
        (bt:make-thread (lambda ()
                          (accept-connections (taskmaster-acceptor taskmaster)))
                        :name (format nil "Hunchentoot acceptor \(~A:~A)"
                                      (or (acceptor-address (taskmaster-acceptor taskmaster)) "*")
                                      (acceptor-port (taskmaster-acceptor taskmaster))))))

#-:lispworks
(defun client-as-string (socket)
  (let ((address (usocket:get-peer-address socket))
        (port (usocket:get-peer-port socket)))
    (when (and address port)
      (format nil "~A:~A"
              (usocket:vector-quad-to-dotted-quad address)
              port))))

#-:lispworks
(defmethod handle-incoming-connection ((taskmaster one-thread-per-taskmaster) socket)
  (bt:make-thread (lambda ()
                    (process-connection (taskmaster-acceptor taskmaster) socket))
                  :name (format nil "Hunchentoot worker \(client: ~A)" (client-as-string socket))))

;; LispWorks implementation

#+:lispworks
(defmethod shutdown ((taskmaster taskmaster))
  (when-let (process (acceptor-process (taskmaster-acceptor taskmaster)))
    ;; kill the main acceptor process, see LW documentation for
    ;; COMM:START-UP-SERVER
    (mp:process-kill process)))

#+:lispworks
(defmethod execute-acceptor ((taskmaster one-thread-per-taskmaster))
  (accept-connections (taskmaster-acceptor taskmaster)))

#+:lispworks
(defmethod handle-incoming-connection ((taskmaster one-thread-per-taskmaster) handle)
  (incf *worker-counter*)
  ;; check if we need to perform a global GC
  (when (and *cleanup-interval*
             (zerop (mod *worker-counter* *cleanup-interval*)))
    (when *cleanup-function*
      (funcall *cleanup-function*)))
  (mp:process-run-function (format nil "Hunchentoot worker \(client: ~{~A:~A~})"
                                   (multiple-value-list
                                    (get-peer-address-and-port handle)))
                           nil #'process-connection
                           (taskmaster-acceptor taskmaster) handle))