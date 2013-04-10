#!/usr/bin/perl
###########################################################################
# Makefile for distdiff
# Install/remove the tool for GNU/Linux, FreeBSD and Mac OS X
#
# Copyright (C) 2011-2013 ROSA Laboratory
#
# Written by Andrey Ponomarenko
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
###########################################################################
use Getopt::Long;
Getopt::Long::Configure ("posix_default", "no_ignore_case");
use File::Path qw(mkpath rmtree);
use File::Copy qw(copy);
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use File::Find;
use strict;

my $TOOL_SNAME = "distdiff";
my $ARCHIVE_DIR = abs_path(dirname($0));

my $HELP_MSG = "
NAME:
  Makefile for distdiff

DESCRIPTION:
  Install $TOOL_SNAME command and private modules.

USAGE:
  sudo perl $0 -install -prefix=/usr
  sudo perl $0 -update -prefix=/usr
  sudo perl $0 -remove -prefix=/usr

OPTIONS:
  -h|-help
      Print this help.

  --prefix=PREFIX
      Install files in PREFIX [/usr/local].

  -install
      Command to install the tool.

  -update
      Command to update existing installation.

  -remove
      Command to remove the tool.

EXTRA OPTIONS:
  --destdir=DESTDIR
      This option is for maintainers to build
      RPM or DEB packages inside the build root.
      The environment variable DESTDIR is also
      supported.
\n";

if(not @ARGV) {
    print $HELP_MSG;
    exit(0);
}

my ($PREFIX, $DESTDIR, $Help, $Install, $Update, $Remove);

GetOptions(
    "h|help!" => \$Help,
    "prefix=s" => \$PREFIX,
    "destdir=s" => \$DESTDIR,
    "install!" => \$Install,
    "update!" => \$Update,
    "remove!" => \$Remove
) or exit(1);

sub scenario()
{
    if($Help)
    {
        print $HELP_MSG;
        exit(0);
    }
    if(not $Install and not $Update and not $Remove)
    {
        print STDERR "ERROR: command is not selected (-install, -update or -remove)\n";
        exit(1);
    }
    if($PREFIX ne "/") {
        $PREFIX=~s/[\/]+\Z//g;
    }
    if(not $PREFIX)
    { # default prefix
        $PREFIX = "/usr/local";
    }
    if(my $Var = $ENV{"DESTDIR"})
    {
        print "Using DESTDIR environment variable\n";
        $DESTDIR = $Var;
    }
    if($DESTDIR)
    {
        if($DESTDIR ne "/") {
            $DESTDIR=~s/[\/]+\Z//g;
        }
        if($DESTDIR!~/\A\//)
        {
            print STDERR "ERROR: destdir is not absolute path\n";
            exit(1);
        }
        if(not -d $DESTDIR)
        {
            print STDERR "ERROR: you should create destdir directory first\n";
            exit(1);
        }
        $PREFIX = $DESTDIR.$PREFIX;
        if(not -d $PREFIX)
        {
            print STDERR "ERROR: you should create installation directory first (destdir + prefix):\n  mkdir -p $PREFIX\n";
            exit(1);
        }
    }
    else
    {
        if($PREFIX!~/\A\//)
        {
            print STDERR "ERROR: prefix is not absolute path\n";
            exit(1);
        }
        if(not -d $PREFIX)
        {
            print STDERR "ERROR: you should create prefix directory first\n";
            exit(1);
        }
    }
    
    print "INSTALL PREFIX: $PREFIX\n";
    
    # paths
    my $EXE_PATH = "$PREFIX/bin";
    my $MODULES_PATH = "$PREFIX/share/$TOOL_SNAME";
    my $REL_PATH = "../share/$TOOL_SNAME";
    
    if(not -w $PREFIX)
    {
        print STDERR "ERROR: you should be root\n";
        exit(1);
    }
    if($Remove or $Update)
    {
        if(-e $EXE_PATH."/".$TOOL_SNAME)
        { # remove executable
            print "-- Removing $EXE_PATH/$TOOL_SNAME\n";
            unlink($EXE_PATH."/".$TOOL_SNAME);
        }
        
        if(-d $MODULES_PATH)
        { # remove modules
            print "-- Removing $MODULES_PATH\n";
            rmtree($MODULES_PATH);
        }
    }
    if($Install or $Update)
    {
        if(-e $EXE_PATH."/".$TOOL_SNAME or -e $MODULES_PATH)
        { # check installed
            if(not $Remove)
            {
                print STDERR "ERROR: you should remove old version first (`sudo perl $0 -remove --prefix=$PREFIX`)\n";
                exit(1);
            }
        }
        
        # configure
        my $Content = readFile($ARCHIVE_DIR."/".$TOOL_SNAME.".pl");
        if($DESTDIR) { # relative path
            $Content=~s/MODULES_INSTALL_PATH/$REL_PATH/;
        }
        else { # absolute path
            $Content=~s/MODULES_INSTALL_PATH/$MODULES_PATH/;
        }
        
        # copy executable
        print "-- Installing $EXE_PATH/$TOOL_SNAME\n";
        mkpath($EXE_PATH);
        writeFile($EXE_PATH."/".$TOOL_SNAME, $Content);
        chmod(0775, $EXE_PATH."/".$TOOL_SNAME);
        
        # copy modules
        if(-d $ARCHIVE_DIR."/modules")
        {
                print "-- Installing $MODULES_PATH\n";
                mkpath($MODULES_PATH);
                copyDir($ARCHIVE_DIR."/modules", $MODULES_PATH);
                my $TOOLS_PATH = $MODULES_PATH."/modules/Internals/Tools";
                my @Tools = listDir($TOOLS_PATH);
                foreach my $Tool (@Tools) {
                    chmod(0775, $TOOLS_PATH."/".$Tool);
                }
        }
        
        # check PATH
        if($ENV{"PATH"}!~/(\A|:)\Q$EXE_PATH\E[\/]?(\Z|:)/) {
            print "WARNING: your PATH variable doesn't include \'$EXE_PATH\'\n";
        }
    }
    exit(0);
}

sub listDir($)
{
    my $Path = $_[0];
    return () if(not $Path or not -d $Path);
    opendir(my $DH, $Path);
    return () if(not $DH);
    my @Contents = grep { $_ ne "." && $_ ne ".." } readdir($DH);
    return @Contents;
}

sub copyDir($$)
{
    my ($From, $To) = @_;
    my %Files;
    find(\&wanted, $From);
    sub wanted {
        $Files{$File::Find::dir."/$_"} = 1 if($_ ne ".");
    }
    foreach my $Path (sort keys(%Files))
    {
        my $Inst = $Path;
        $Inst=~s/\A\Q$ARCHIVE_DIR\E/$To/;
        if(-d $Path)
        { # directories
            mkpath($Inst);
        }
        else
        { # files
            mkpath(dirname($Inst));
            copy($Path, $Inst);
        }
    }
}

sub readFile($)
{
    my $Path = $_[0];
    return "" if(not $Path or not -f $Path);
    open(FILE, $Path) || die ("can't open file \'$Path\': $!\n");
    local $/ = undef;
    my $Content = <FILE>;
    close(FILE);
    return $Content;
}

sub writeFile($$)
{
    my ($Path, $Content) = @_;
    return if(not $Path);
    open(FILE, ">".$Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

scenario();