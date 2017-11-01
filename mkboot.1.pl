#!/usr/bin/env perl

use strict;
use warnings;
use Getopt::Std;
use File::Temp;
use File::Copy;
use Cwd;

# useropts
my %options=();
my $action = "none";
my $verbose=0;
my $bootimg = "";
my $unpackdir = "";

# internal
my $tempdir;
my $status;
my $pwd = getcwd;

sub clean {
	if ($action eq "unpack") {
		system("rm -rf /tmp/mkboot.*");
	}
}

sub is_read {
	my $f = shift;
	return ((-e $f) and (-r $f));
}

sub is_readf {
	my $f = shift;
	return (is_read($f) and (-f $f) and (-s $f));
}

sub is_readd {
	my $f = shift;
	return (is_read($f) and (-d $f));
}

sub _readf {
	my $file = shift;
	local $/ = undef;
	open FILE, "$file" or die "Couldn't open file: $!\n";
	binmode FILE;
	my $string = <FILE>;
	close FILE;
	return $string;
}

# sigint
$SIG{'INT'} = sub {
	clean();
	die "sigint\n";
};

# getopts
getopts("cxvf:", \%options);

# determine action
$action = "pack" if defined $options{c};
$action = "unpack" if defined $options{x};

if ($action eq "none") {
	print STDERR "missing -c|x\n";
	exit 1;
}

# verbose?
$verbose = 1 if defined $options{v};

# bootimg
if (! defined $options{f}) {
	print STDERR "missing -f [FILE]\n";
	exit 1;
}
$bootimg = $options{f};

# filename
if (! $ARGV[0]) {
	print STDERR "missing [DIR]\n";
	exit 1;
}
$unpackdir = $ARGV[0];

if ($verbose) {
	print "action : " . $action . "\n";
	print "verbose: " . $verbose . "\n";
	print "bootimg: " . $bootimg . "\n";
	print "unpackd: " . $unpackdir . "\n";
}

if ($action eq "unpack") {
	# prelim checks
	# bootimg: readable non-zero file
	# unpackd: folder readable
	unless (mkdir $unpackdir) {
		if (is_read($unpackdir)) {
			die "unpack dir \"$unpackdir\" already exists!\n";
		} else {
			die "unable to create directory $unpackdir\n";
		}
	}

	if (!is_readf($bootimg) ){
		print STDERR "file $bootimg is not readable\n";
		exit 1;
	}

	# make temp directory
	$tempdir = File::Temp::tempdir("/tmp/mkboot.XXXX");
	if ( ! symlink("$pwd/$bootimg","$tempdir/boot") eq 1) {
		die "unable to process $bootimg\n";
	}

	# call unpackbootimg
	$status = system("unpackbootimg -i $tempdir/boot -o $pwd/$unpackdir");
	if ( ! $status eq 0 ) {
		die "unable to process $bootimg; unpackbootimg failed! ($status)\n";
	}

	# extract ramdisk (supported; gzip, lz4)
	if (is_readf("$unpackdir/boot-ramdisk.gz")) {
		unless(mkdir "$unpackdir/ramdisk") {
			die "unable to create folder \"$unpackdir/ramdisk\" for unpacking ramdisk!\n";
		}
		chdir("$unpackdir/ramdisk") or die "cannot switch to ramdisk dir: $!\n";
		$status = system("gzip -n -d -c $pwd/$unpackdir/boot-ramdisk.gz | cpio -i -d -m  --no-absolute-filenames");
		if (! $status eq 0) {
			die "ramdisk extract (gzip) failed! ($status)\n";
		}
	} elsif (is_readf("$unpackdir/boot-ramdisk.lz4")) {
		unless(mkdir "$unpackdir/ramdisk") {
			die "unable to create folder \"$unpackdir/ramdisk\" for unpacking ramdisk!\n";
		}
		chdir("$unpackdir/ramdisk") or die "cannot switch to ramdisk dir: $!\n";
		$status = system("bsdtar xvf $pwd/$unpackdir/boot-ramdisk.lz4 2>/dev/null");
		if (! $status eq 0) {
			die "ramdisk extract (lz4) failed! ($status)";
		}
	} else {
		die "ramdisk missing/unknown!\n";
	}
	chdir("$pwd") or die "cannot switch back to cwd: $!\n";

} elsif ($action eq "pack") {
	# prelim checks
	# bootimg: not exist
	# unpackd: folder readable
	if (!is_readd($unpackdir)) {
		die "folder $unpackdir not readable!\n";
	}
	if (is_read($bootimg)) {
		die "file \"$bootimg\" already exists!\n";
	} else {
		# if the user gives something wonky, like a "-" and complains;
		# he is shooting himself in the foot with a shotgun
		# and asks why it hurts
		# we cannot really deal with this here (for now)
	}

	# args
	my @args = ('mkbootimg');

	# basic
	my @boot_files = ('zImage', 'cmdline', 'base', 'kernel_offset', 'ramdisk_offset', 'tags_offset', 'pagesize');
	foreach my $f (@boot_files) {
		my $fp = "$unpackdir/boot-$f";
		if (!is_readf($fp)) {
			die "unable to read $fp";
		}
	}

	push @args, ('--kernel', "$unpackdir/boot-zImage");
	if (is_readf("$unpackdir/boot-dt")) {
		push @args, ('--dt', "$unpackdir/boot-dt");
	}

	# deal with ramdisk
	my $ramdisk = "none";
	my $ramdisk_new = "/dev/null";
	my $zc_args = "";
	if (is_readf("$unpackdir/boot-ramdisk.gz")) {
		$ramdisk = "$unpackdir/boot-ramdisk.gz";
		$ramdisk_new = "$unpackdir/boot-ramdisk.new.gz";
		$zc_args = "gzip -n -f";
	} elsif (is_readf("$unpackdir/boot-ramdisk.lz4")) {
		$ramdisk = "$unpackdir/boot-ramdisk.lz4";
		$ramdisk_new = "$unpackdir/boot-ramdisk.new.lz4";
		$zc_args = "lzma";
	} else {
		die "ramdisk missing/unknown!\n";
	}
	if (is_readd("$unpackdir/ramdisk")) {
		$status = system("mkbootfs $unpackdir/ramdisk | $zc_args > $ramdisk_new");
		if ($status eq 0) {
			push @args, ('--ramdisk', "$ramdisk_new");
		} else {
			die "failed to pack new ramdisk! ($status)\n";
		}
	} else {
		push @args, ('--ramdisk', "$ramdisk");
	}

	my $_cmdline        = _readf("$unpackdir/boot-cmdline");
	my $_base           = _readf("$unpackdir/boot-base");
	my $_kernel_offset  = _readf("$unpackdir/boot-kernel_offset");
	my $_ramdisk_offset = _readf("$unpackdir/boot-ramdisk_offset");
	my $_tags_offset    = _readf("$unpackdir/boot-tags_offset");
	my $_pagesize       = _readf("$unpackdir/boot-pagesize");

	push @args, ('--cmdline', "$_cmdline");
	push @args, ('--base', "0x$_base");
	push @args, ('--kernel_offset', "0x$_kernel_offset");
	push @args, ('--ramdisk_offset', "0x$_ramdisk_offset");
	push @args, ('--tags_offset', "0x$_tags_offset");
	push @args, ('--pagesize', "$_pagesize");

	# extends
	if (is_readf("$unpackdir/boot-second")) {
		push @args, ('--second', "$unpackdir/boot-second");
		my $_second_offset = _readf("$unpackdir/boot-second_offset");
		push @args, ('--second_offset', "0x$_second_offset");
	}

	if (is_readf("$unpackdir/boot-os_version")) {
		my $_os_version = _readf("$unpackdir/boot-os_version");
		push @args, ('--os_version', "$_os_version");
	}

	if (is_readf("$unpackdir/boot-os_patch_level")) {
		my $_os_patch_level = _readf("$unpackdir/boot-os_patch_level");
		push @args, ('--os_patch_level', "$_os_patch_level");
	}

	# output
	push @args, ('-o', "$bootimg");

	# :fingers-crossed:
	my $status = system(@args);
	if ($status eq 0) {
		print "$bootimg\n"
	} else {
		die "mkbootimg failed! ($status)";
	}
} else {
	die "something is horribly wrong. how did you get here?";
}

END {
	clean();
}
