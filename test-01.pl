

use strict;
use warnings;

unshift @INC, "./lib";

use NodeJS::Context;

my $context = new NodeJS::Context;

my $rv = $context->eval("var autoprefixer = require('autoprefixer');", 'stdin');

die "error loading $@" if $@;
# die "could not" unless $rv;

$rv = $context->eval('var rv = autoprefixer.process("a { display: flex; }", { browsers: ["> 1%", "ie 10"] });');

die "error loading $@" if $@;

die $context->eval('rv.css');


