use JavaScript::V8;

use strict;
use warnings;

use File::Slurp;
use File::chdir;
use File::Basename;
use File::Basename;

our @paths = ('node_modules');

our %cache;

use JSON qw(decode_json);

# my $bin = read_file('autoprefixer.js', { binmode => ':raw' }) or die "no read";

my $context = JavaScript::V8::Context->new();

use File::Spec::Functions;
use File::Spec::Functions qw(rel2abs);
use File::Spec::Functions qw(abs2rel);

$context->bind_function(debug => sub
{

	use Data::Dumper;

	warn Dumper ([@_]);

});

$context->bind('__core__' => {
	'fs' => bless({}, 'NODE::FS'),
	'path' => bless({}, 'NODE::PATH'),
	'buffer' => bless({}, 'NODE::BUFFER'),
	'modules' => bless({}, 'NODE::MODULES'),
});

sub fni
{
	return 'var module = { exports: function(){} }; (function(module){ var exports = module.exports; ' . "\n" . $_[0] . '; return module.exports; })(module);';
}

$context->bind_function(require => sub
{

	local @paths = @paths;

	my $file;

	my ($mod) = @_;

	my $load_as_file = sub
	{

		my $file;

		my ($cwd, $path) = @_;

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
			# local %cache = %cache;
			my $abs = rel2abs($file, $CWD);
			return $context->eval('__core__.modules.loaded['.$cache{$abs}.'].exports;') if $cache{$abs};
			my $bin = read_file($file, { binmode => ':utf8' });


			if (exists $cache{$abs})
			{
				warn "====", $context->eval('__core__.modules.loaded['.$cache{$abs}.'].exports;');
				return $context->eval('__core__.modules.loaded['.$cache{$abs}.'].exports;');
			}

			warn "LOAD2 ", abs2rel($file, $CWD), "\n";
			$context->eval('throw("err");', $file) unless defined $bin;
			die "could not read $file" unless defined $bin;
			push @paths, catfile dirname($file);

			$cache{$abs} = {};

			$context->eval('var module = {};');

			$cache{$abs} = $context->eval('__core__.modules.loaded.length;');

			$bin = '(function(module){ var exports = module.exports; __core__.modules.loaded.push(module); ' . "\n" . $bin . '; return module.exports; })({ exports: function () {} });';
			my $rv = $context->eval($bin, $file);
			warn "error loading $file\n$@" if $@;
			$context->eval('throw("'.$@. '");', $file) if $@;
			die $@ if $@;
			# warn " -- ", $context->eval('__core__.modules.loaded['.$cache{$abs}.'].exports;');
			return $context->eval('__core__.modules.loaded['.$cache{$abs}.'].exports;');
		}

		return undef;
	};

	my $load_as_directory = sub
	{
		my $file;

		my ($cwd, $path) = @_;
#		warn "try $CWD ", catfile($cwd, $path, 'index.js'), "\n";

		if (-f catfile $cwd, $path, 'package.json')
		{
			my $file = catfile $cwd, $path, 'package.json';
			my $bin = read_file($file, { binmode => ':utf8' });
			die "could not read $file" unless defined $bin;
			my $json = decode_json $bin or die "could not load $file";
			push @paths, catfile $cwd, $path, 'node_modules';
			return $load_as_file->(catfile($cwd, $path), catfile $json->{'main'}) if defined $json->{'main'};
		}

		if (!$file && -f catfile $cwd, $path, 'index.js')
		{
			push @paths, catfile $cwd, $path, 'node_modules';
			return $load_as_file->(catfile($cwd, $path), 'index.js');
		}
		if (!$file && -f catfile $cwd, $path, 'index.node')
		{
			die catfile $cwd, $path, 'index.node';
		}
		return $file;
	};

	# must be a file
	if ($mod =~ m/\A(?:\.\.?)\//)
	{
		foreach my $path (reverse @paths)
		{
			$file = $load_as_file->($path, $mod);
			return $file if defined $file;
		}
	}
	# can be a module
	else
	{

		return $context->eval("__core__.$mod") if $context->eval("__core__.$mod");


		foreach my $path (@paths)
		{
			$path = rel2abs($path);
			$file = $load_as_file->($path, $mod);
			return $file if defined $file;
			$file = $load_as_directory->($path, $mod);
			return $file if defined $file;
		}
	}
	my $stack = $context->eval("var err = new Error('ERROR LOADING <$mod>'); err.stack;");
	die "ERROR LOADING <$mod>\n" . $stack;
	return {};
});

$context->set_flags_from_string("--builtins-in-stack-traces");
$context->set_flags_from_string("--stack-trace-limit 99");

# $context->name_global( 'module' );
$context->name_global( 'window' );

$context->eval("var autoprefixer;");

$context->eval("__core__.modules.loaded = [];");

my $rv = $context->eval("autoprefixer = require('autoprefixer');", 'stdin');

die "error loading $@" if $@;
# die "could not" unless $rv;

my $rv = $context->eval('var rv = autoprefixer.process("a { display: flex; }", { browsers: ["> 1%", "ie 10"] });');

die "error loading $@" if $@;

die $context->eval('rv.css');

use Data::Dumper;

# warn $@ if $@;

# warn Dumper vim $rv;

# die Dumper $rv;

# warn $rv->{'css'};

package NODE::FS;

package NODE::PATH;

use File::chdir;
use File::Basename qw();
use File::Spec::Functions qw(rel2abs);
use File::Spec::Functions qw(abs2rel);

use Data::Dumper;

sub dirname
{

	my ($self, $file) = @_;

	my $path = File::Basename::dirname $file;

#	$path =~ tr/\\/\//if $^O = "MsWin32";

	return $path;

}

sub relative
{

	my ($self, $from, $to) = @_;

	my $path = abs2rel($from, $to);

	# $path =~ tr/\\/\//if $^O = "MsWin32";

	return $path;

}

sub resolve
{

	my ($self) = shift;

warn "asd @_";

	my $path = pop;

	while (my $part = pop)
	{
		last if file_name_is_absolute $path;
		$path = catfile $part, $path;
	}

	$path = rel2abs($path, $CWD);

#	$path =~ tr/\\/\//if $^O = "MsWin32";

warn "return $path";

	return $path;

}

package NODE::BUFFER;

package NODE::MODULES;
