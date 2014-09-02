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

sub exports
{

	# query the js context for the exported module (may only partially filled yet)
	$_[0]->eval('__core__.modules.loaded[' . $_[0]->{'cache'}->{$_[1]} . '].exports;');

}

####################################################################################################
# require is mainly called from js code
####################################################################################################

# load additional js module
# ***************************************************************************************
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

		# check if the module is already loaded (core module?)
		return $self->eval("__core__.$mod") if $self->eval("__core__.$mod");

		# look into include paths
		foreach my $path (@paths)
		{
			$path = rel2abs($path);
			my $file = $self->load_as_file($path, $mod);
			return $file if defined $file;
			my $dir = $self->load_as_directory($path, $mod);
			return $dir if defined $dir;
		}
		# EO each path

	}
	# EO is a module

}
# EO require

####################################################################################################
# pass to context
####################################################################################################

sub eval
{
	# get input arguments
	my ($self, $js, $orig) = @_;
	# assertion for valid context
	die "no context" unless $self->{'context'};
	# return whatever the result may be
	$self->{'context'}->eval($js, $orig || '[NA]');
}

####################################################################################################
# load and decode a json data file
####################################################################################################

sub load_json
{

	# get input arguments
	my ($self, $file) = @_;

	# assertion for a valid file
	die "undefined file" unless defined $file;

	my $cache = $self->{'cache'};
	my $context = $self->{'context'};

	# put a message to the console
	warn "JSONDATA ", abs2rel($file, $CWD), "\n";

	# read the json data file (use utf8 encoding)
	my $raw = read_file($file, { binmode => ':utf8' });

	# decode the json data (will do a strict check)
	my $json = decode_json($raw) if defined $raw;

	# return data
	return $json;

}
# EO load_json

####################################################################################################
# load a NodeJS module
####################################################################################################

sub load_module
{

	my ($self, $file) = @_;

	return undef unless defined $file;

	my $cache = $self->{'cache'};
	my $context = $self->{'context'};

	# local @paths = @paths;
	my $abs = rel2abs($file, $CWD);

	# return from cache
	if (exists $cache->{$abs})
	{
		return $self->exports($abs);
	}

	# read the nodejs module (use utf8 encoding)
	my $bin = read_file($file, { binmode => ':utf8' });

	# put a message to the console
	warn "REQUIRE ", abs2rel($file, $CWD), "\n";

	# XXX - retest how to handle this correctly
	$context->eval('throw("err");', $file) unless defined $bin;
	die "could not read $file" unless defined $bin;

	# add the directory to lookup paths
	push @paths, catfile dirname($file);

	# store the index of the javascript array (object is not synched)
	$cache->{$abs} = $context->eval('__core__.modules.loaded.length;');

	# create the module context
	my $js = '(function(module){
		var exports = module.exports;
		__core__.modules.loaded.push(module);
		' . $bin . ';
		return module.exports;
	})({ exports: function () {} });';

	# XXX - retest how to handle this correctly
	my $rv = $context->eval($js, $file);
	warn "error loading $file\n$@" if $@;
	$context->eval('throw("'.$@. '");', $file) if $@;
	die $@ if $@;

	# export javascript module
	return $self->exports($abs);

}
# EO load_module

####################################################################################################
# try to load path as a file
####################################################################################################

sub load_as_file
{

		my ($self, $cwd, $path) = @_;

		if (-f catfile $cwd, $path)
		{
			return $self->load_module(catfile($cwd, $path));
		}
		elsif (-f catfile $cwd, $path . '.js')
		{
			return $self->load_module(catfile($cwd, $path . '.js'));
		}
		elsif (-f catfile $cwd, $path . '.json')
		{
			return $self->load_json(catfile($cwd, $path . '.json'));
		}

		return undef;

}

####################################################################################################
# try to load module from directory
####################################################################################################

sub load_as_directory
{

		my $file;

		my ($self, $cwd, $path) = @_;

		my $cache = $self->{'cache'};
		my $context = $self->{'context'};

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
