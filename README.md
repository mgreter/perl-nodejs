perl-nodejs
===========

NodeJS natively in perl running on V8

Proof of concept! Main goal was to be able to use pure JS libraries,
which turned out to be fairly easy (implementing require on to of V8).

I only have implement one or two NodeJS lib functions, but it should
be pretty straight forward to implement the rest. Not sure how hard
it would be to support the full asynch IO of NodeJS.

This has only been tested on strawberry perl (windows)

https://github.com/mgreter/javascript-v8/tree/master/build/win