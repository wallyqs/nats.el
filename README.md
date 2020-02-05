# nats.el

NATS Client for Emacs Lisp

## Usage

```lisp
(require 'nats)

(nats-connect "127.0.0.1" 4222)

(nats-pub "hello" "world")

(message (nats-req "ngs.echo" "Hello World!"))
```

## License

Unless otherwise noted, the NATS source files are distributed under the Apache Version 2.0 license found in the LICENSE file.
