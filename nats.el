;;; nats.el --- Emacs Lisp NATS Client 

;; Copyright 2020 The NATS Authors
;; Author: Waldemar Quevedo, based on eredis.el

;; This file is not part of GNU Emacs

;; Licensed under the Apache License, Version 2.0 (the "License");
;;
;; you may not use this file except in compliance with the License.
;; You may obtain a copy of the License at
;;
;;  http://www.apache.org/licenses/LICENSE-2.0
;;
;; Unless required by applicable law or agreed to in writing, software
;; distributed under the License is distributed on an "AS IS" BASIS,
;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;; See the License for the specific language governing permissions and
;; limitations under the License.

;;; Code:

(defun nats-sentinel(process event)
  "Sentinel function for NATS client"
  (message (format "sentinel event %s" event))
  (when (eq 'closed (process-status process))
    (when (eq process nats--current-process)
      (setq nats--current-process nil))
    (delete-process process)))

(defun nats--generate-buffer(host port)
  (generate-new-buffer (format "nats-%s-%d" host port)))

(defun nats-connect(host port &optional nowait)
  "Connect to NATS on HOST PORT. `NOWAIT' can be set to non-nil to make the connection asynchronously."
  (interactive (list (read-string "Host: " "localhost") (read-number "Port: " 4222)))

  ;; TODO: if not nil just return the process

  (let ((buffer (nats--generate-buffer host port)))
    (prog1
        ;; TODO: auto inc on subs
	;; TODO: implement subs...
        (setq nats-ssid 0)

	;; TODO: Use defvar
	(setq nats--current-process
              (make-network-process :name (buffer-name buffer)
				    :host host
				    :service port
				    :type nil
				    :nowait nowait
				    :keepalive t
				    :linger t
				    :sentinel #'nats-sentinel
				    :buffer buffer))

      ;; connect-init
      (process-send-string nats--current-process
        (format "CONNECT {\"name\":\"Emacs\",\"lang\":\"elisp\",\"version\":\"0.1\",\"verbose\":false,\"pedantic\":false}\r\n"))

	;; ping interval
	(run-with-timer 0 (* 2 60)
		      'nats-ping)

         ;; TODO: need to keep track of this as state from the client
	 (with-current-buffer buffer
	   (process-put nats--current-process 'response-start (point-max))
	 )
      )))

(defun nats-ping ()
  (process-send-string
   nats--current-process
   (format "PING\r\n")))

(defun nats-command-returning (command &rest args)
  "Send a command that has the status code return type.
  If the last argument is a process then that is the process used,
  otherwise it will use the value of `nats--current-process'"
  (let* ((last-arg (car (last args)))
	 (process (if (processp last-arg)
		      last-arg
		    nats--current-process))
	 (command-args
	  (if (or
	       (null last-arg)
	       (processp last-arg))
	      (-butlast args)
	    args)))
    (if (and process (eq (process-status process) 'open))
	(progn
          (process-send-string process "PING\n")
          (let ((ret-val (nats-get-response process)))
            (when (called-interactively-p 'any)
              (message ret-val))
            ret-val))
      (error "nats not connected"))))

;; TODO: Improve inbox generation
(defun random-alnum ()
  (let* ((alnum "abcdefghijklmnopqrstuvwxyz0123456789")
         (i (% (abs (random)) (length alnum))))
    (substring alnum i (1+ i))))

(defun nats:inbox ()
  (concat 
    (random-alnum)
    (random-alnum)
    (random-alnum)
    (random-alnum)
    (random-alnum)
    (random-alnum)
    (random-alnum)
    (random-alnum)
    (random-alnum)
    (random-alnum)
    (random-alnum)
    (random-alnum)
  ))

(defun nats-pub (subject payload &optional reply)
  (let* ((payload-size (string-width payload))
        (process nats--current-process))

      (if reply
        (prog1 
	  (process-send-string process (format "PUB %s %s %d\r\n%s\r\n" subject reply payload-size payload)))
        (process-send-string process (format "PUB %s %d\r\n%s\r\n" subject payload-size payload))
      )))

(defun nats-sub (subject cb)
  ;; TODO
)

(defun nats-req (subject payload)
  (let* ((inbox (format "_INBOX.%s" (nats:inbox)))
         (process nats--current-process)
	 (resp nil))

    ;; Update the ssid for the 1:1 request
    (setq nats-ssid (1+ nats-ssid))

    ;; SUB
    (process-send-string process (format "SUB %s %d\r\n" inbox nats-ssid))

    ;; UNSUB
    (process-send-string process (format "UNSUB %d 1\r\n" nats-ssid))

    ;; Publish the request
    (nats-pub subject payload inbox)

    ;; Mark the current state of the parser
    ;; TODO: clean up the buffer periodically?
    (with-current-buffer (process-buffer process)
      (process-put nats--current-process 'response-start (point-max)))

    ;; Wait for the response...
    (prog1
        (let ((buffer (process-buffer process))

	      ;; Get current state of the parser
              (response-start (process-get process 'response-start))
              (done nil))
	  
          (with-current-buffer buffer
            (while (not done)
              (accept-process-output process 4 nil 1)
              (setf done t)

              (let* ((proto-line
                      (buffer-substring response-start (point-max)))
		      (payload-size nil))
		(prog1
		    ;; TODO: Assuming have already received the payload
		    (if (string-match "MSG\s+\\([^\s]+\\)\s+\\([^\s]+\\)\s+\\([^\s]+\\)\r\n" proto-line)
		        (let* ((payload-size (string-to-number (match-string 3 proto-line)))
			       (payload-start (+ 2 (match-end 3)))
			       (payload-end   (+ payload-start payload-size)))

			       (setf resp (substring proto-line payload-start payload-end))))
		  ))))
            ))
    ;; Finally, return the response...
    resp))

(provide 'nats)
