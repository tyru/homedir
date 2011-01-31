#!/usr/bin/env perl

# from http://mt.endeworks.jp/d-6/2009/02/extlib.html
# - CPAN����Ͽ����Ƥʤ��⥸�塼���CPAN::Shell->expandany()�����Ȥ�undef�ˤʤ뤳�Ȥ��б�
# - File::Temp������Ǥ���褦�˥����ȥǥ��쥯�ȥ�����褦�ˤ���
# - �����åפ����⥸�塼���Ǹ��ɽ��
# TODO
# - �⥸�塼�뤬���󥹥ȡ��뤵��Ƥ�ʤ�CPAN�˼��ˤ����ʤ��褦�ˤ���


use strict;
use warnings;
use CPAN;
use Module::CoreList;
use Module::ScanDeps;
use File::Find::Rule;
use File::Spec;
use File::Temp qw(tempdir);
use Cwd qw(getcwd);

if (scalar @ARGV != 2) {
    print <<EOM;
Usage: deps2extlib.pl target [extlib]

target - the directory or script that you want to compile 
         dependencies against.
extlib - the path where you want to install your dependecies.

EOM
    exit 1;
}

my $target = $ARGV[0];
my $dir = File::Spec->rel2abs($ARGV[1] || 'extlib');

unshift @INC, $dir;

my @files;
if (-d $target) {
    @files = File::Find::Rule
        ->file()
        ->or(
            File::Find::Rule->name('*.pl'),
            File::Find::Rule->name('*.pm')
        )
        ->in($target);
} else {
    @files = ($target);
}

my $h = scan_deps_runtime(
    compile => 1,
    files => \@files,
    recurse => 1,
);

my %seen;
my $corelist = $Module::CoreList::version{ $] };

CPAN::HandleConfig->load unless $CPAN::Config_loaded++;
my $home = tempdir(CLEANUP => 1);
local $CPAN::Config->{cpan_home} = $home;
local $CPAN::Config->{keep_source_where} = File::Spec->catdir($home, 'sources');
local $CPAN::Config->{build_dir} = File::Spec->catdir($home, 'build');
local $CPAN::Config->{prerequisites_policy} = 'follow';
local $CPAN::Config->{makepl_arg} = "INSTALL_BASE=$dir";
local $CPAN::Config->{mbuild_arg} = "--install_base=$dir";
local $CPAN::Config->{mbuild_install_arg} = "--install_base=$dir";

my $cwd = getcwd;
my @skipped;

foreach my $key (sort keys %$h) {
    next if $key =~ /^unicore/;
    next if $key =~ /^auto/;

    $key =~ s/\//::/g;
    $key =~ s/\.pm$//;

    # �����⥸�塼��Ǥ���Х����å�
    next if exists $corelist->{$key};

    my $mod = CPAN::Shell->expandany($key);
    unless (defined $mod) {
        # ��ʬ�Ѥ˺�ä�CPAN�ˤʤ��⥸�塼��ʤ�
        push @skipped, $key;
        print "skipped $key...\n";
        sleep 1;
        next;
    }

    my $dist = $mod->cpan_file;
    if ($dist =~ /\/perl-/) {
        warn "won't try to install perl, but we found dependency on $dist";
        next;
    }
    next if $seen{ $dist }++;

    CPAN::Shell->install($dist);
}


chdir $cwd or warn "can't chdir to $cwd: $!";

print "\n\n\ninstalled all dependency files of $target to $dir.\n";

if (@skipped) {
    warn sprintf "skipped to install %s\n", join ', ', @skipped;
}
