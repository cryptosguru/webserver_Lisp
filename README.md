----------------------------------------
Hunchentoot - The Common Lisp web server
----------------------------------------

Hunchentoot is a web server written in Common Lisp and at the same
time a toolkit for building dynamic websites.  As a stand-alone web
server, Hunchentoot is capable of HTTP/1.1 chunking (both directions),
persistent connections (keep-alive), and SSL.

Hunchentoot provides facilities like automatic session handling (with
and without cookies), logging, customizable error handling, and easy
access to GET and POST parameters sent by the client.

Hunchentoot talks with its front-end or with the client over TCP/IP
sockets and optionally uses multiprocessing to handle several requests
at the same time.
