###################################################################################################
# Copyright 2014 by Marcel Greter
# This file is part of OCBNET-NodeJS (GPL3)
####################################################################################################
package NodeJS::Context;
####################################################################################################
our $VERSION = '0.0.1';
####################################################################################################

use strict;
use warnings;

use JSON;
use File::Slurp;
use File::chdir;
use File::Basename;
use File::Spec::Functions;
use File::Spec::Functions qw(rel2abs);
use File::Spec::Functions qw(abs2rel);
use JavaScript::V8;

####################################################################################################
our @paths = ('node_modules');
####################################################################################################

my $count = 0;

# create a new object
# ***************************************************************************************
sub new
{

	# package name
	my ($pckg) = shift;

	# create a new V8 context
	my $context = JavaScript::V8::Context->new();
	die "could not create V8 context" unless $context;

	$context->bind('__core__' => {
		'fs' => bless({}, 'NodeJS::Core::FS'),
		'path' => bless({}, 'NodeJS::Core::Path'),
		'buffer' => bless({}, 'NodeJS::Core::Buffer'),
		'modules' => bless({}, 'NodeJS::Core::Modules'),
	});

	$context->eval("__core__.modules.loaded = [];");

	# create a new instance
	my $self = {

		'cache' => {},
		'count' => $count ++,
		'context' => $context,

	};

	# bless instance into package
	$self = bless $self, $pckg;

	# bind require function to load NodeJS modules
	$context->bind_function(require => sub { $self->require(@_) });

	# return object
	return $self;

}
# EO constructor


sub require
{

	# get input arguments
	my ($self, $mod) = @_;

	# check if we have a file
	if ($mod =~ m/\A(?:\.\.?)\//)
	{
		foreach my $path (reverse @paths)
		{
			my $file = $self->load_as_file($path, $mod);
			return $file if defined $file;
		}
	}
	# can be a module
	else
	{

		return $self->eval("__core__.$mod") if $self->eval("__core__.$mod");

		foreach my $path (@paths)
		{
			$path = rel2abs($path);
			my $file = $self->load_as_file($path, $mod);
			return $file if defined $file;
			my $dir = $self->load_as_directory($path, $mod);
			return $dir if defined $dir;
		}
	}


#	local @paths = @paths;


}

sub eval
{
	# get input arguments
	my ($self, $js, $orig) = @_;
die "no js" unless $js;
$orig = 'NA' unless defined $orig;
die "no orig" unless $orig;

	# return whatever the result may be
	die unless $self->{'context'};
	$self->{'context'}->eval($js, $orig);
}

sub load_as_file
{

		my $file;

		my ($self, $cwd, $path) = @_;

		my $cache = $self->{'cache'};
		my $context = $self->{'context'};

		if (-f catfile $cwd, $path)
		{
			$file = catfile $cwd, $path;
		}
		elsif (-f catfile $cwd, $path . '.js')
		{
			$file = catfile $cwd, $path . '.js';
		}
		elsif (-f catfile $cwd, $path . '.json')
		{
			$file = catfile $cwd, $path . '.json';
			my $bin = read_file($file, { binmode => ':utf8' });
			my $json = decode_json($bin);
			return $json;
		}

		if (defined $file)
		{
			# local @paths = @paths;
			my $abs = rel2abs($file, $CWD);
			return $context->eval('__core__.modules.loaded['.$cache->{$abs}.'].exports;') if $cache->{$abs};
			my $bin = read_file($file, { binmode => ':utf8' });


			if (exists $cache->{$abs})
			{
				warn "====", $context->eval('__core__.modules.loaded['.$cache->{$abs}.'].exports;');
				return $context->eval('__core__.modules.loaded['.$cache->{$abs}.'].exports;');
			}

			warn "LOAD2 ", abs2rel($file, $CWD), "\n";
			$context->eval('throw("err");', $file) unless defined $bin;
			die "could not read $file" unless defined $bin;

			push @paths, catfile dirname($file);

			$cache->{$abs} = {};

			$context->eval('var module = {};');

			$cache->{$abs} = $context->eval('__core__.modules.loaded.length;');

			$bin = '(function(module){ var exports = module.exports; __core__.modules.loaded.push(module); ' . "\n" . $bin . '; return module.exports; })({ exports: function () {} });';
			my $rv = $context->eval($bin, $file);
			warn "error loading $file\n$@" if $@;
			$context->eval('throw("'.$@. '");', $file) if $@;
			die $@ if $@;
			# warn " -- ", $context->eval('__core__.modules.loaded['.$cache->{$abs}.'].exports;');
			return $context->eval('__core__.modules.loaded['.$cache->{$abs}.'].exports;');
		}

		return undef;


}

sub load_as_directory
{

		my $file;

		my ($self, $cwd, $path) = @_;

		my $cache = $self->{'cache'};
		my $context = $self->{'context'};

#		warn "try $CWD ", catfile($cwd, $path, 'index.js'), "\n";

		if (-f catfile $cwd, $path, 'package.json')
		{
			my $file = catfile $cwd, $path, 'package.json';
			my $bin = read_file($file, { binmode => ':utf8' });
			die "could not read $file" unless defined $bin;
			my $json = decode_json $bin or die "could not load $file";
			push @paths, catfile $cwd, $path, 'node_modules';
			return $self->load_as_file(catfile($cwd, $path), catfile $json->{'main'}) if defined $json->{'main'};
		}

		if (!$file && -f catfile $cwd, $path, 'index.js')
		{
			push @paths, catfile $cwd, $path, 'node_modules';
			return $self->load_as_file(catfile($cwd, $path), 'index.js');
		}
		if (!$file && -f catfile $cwd, $path, 'index.node')
		{
			die catfile $cwd, $path, 'index.node';
		}
		return $file;

}

####################################################################################################
####################################################################################################
1;
