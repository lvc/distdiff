#!/usr/bin/perl
###########################################################################
# DistDiff - Distro Changes Analyzer 1.0
# A tool for analyzing changes in Linux distributions
#
# Copyright (C) 2012-2013 ROSA Laboratory
#
# Written by Andrey Ponomarenko
#
# PLATFORMS
# =========
#  GNU/Linux, FreeBSD, Mac OS X
#
# PACKAGE FORMATS
# ===============
#  RPM, DEB, TAR.GZ, etc.
#
# REQUIREMENTS
# ============
#  Perl 5 (5.8 or newer)
#  PkgDiff (1.5 or newer)
#  GNU Diff
#  GNU Wdiff
#  GNU Awk
#  GNU Binutils (readelf)
#  RPM (rpm, rpmbuild, rpm2cpio) for analysis of RPM-packages
#  DPKG (dpkg, dpkg-deb) for analysis of DEB-packages
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License or the GNU Lesser
# General Public License as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# and the GNU Lesser General Public License along with this program.
# If not, see <http://www.gnu.org/licenses/>.
###########################################################################
use Getopt::Long;
Getopt::Long::Configure ("posix_default", "no_ignore_case", "permute");
use File::Path qw(mkpath rmtree);
use File::Temp qw(tempdir);
use File::Compare;
use Cwd qw(abs_path cwd);
use Config;

my $TOOL_VERSION = "1.0";
my $OSgroup = get_OSgroup();
my $ORIG_DIR = cwd();
my $TMP_DIR = tempdir(CLEANUP=>1);

# Internal modules
my $MODULES_DIR = get_Modules();
push(@INC, get_dirname($MODULES_DIR));

my $PKGDIFF = "pkgdiff";
my $PKGDIFF_VERSION = "1.5";

my ($Help, $ShowVersion, $DumpVersion, %Descriptor,
$Browse, $OpenReport, $OutputReportPath, $Debug, $TargetName,
$TargetArch, $ShowAll);

my $CmdName = get_filename($0);

my %ERROR_CODE = (
    # No errors
    "Success"=>0,
    # Undifferentiated error code
    "Error"=>2,
    # System command is not found
    "Not_Found"=>3,
    # Cannot access input files
    "Access_Error"=>4,
    # Cannot find a module
    "Module_Error"=>9
);

my %HomePage = (
    "Dev"=>"http://lvc.github.com/distdiff/"
);

my %Contacts = (
    "Main"=>"aponomarenko\@rosalab.ru"
);

my $ShortUsage = "Distro Changes Analyzer (DistDiff) $TOOL_VERSION
A tool for analyzing changes in Linux distributions
Copyright (C) 2013 ROSA Laboratory
License: GNU GPL

Usage: $CmdName DIR1/ DIR2/ [options]

More info: $CmdName --help\n";

if($#ARGV==-1)
{
    printMsg("INFO", $ShortUsage);
    exit(0);
}

GetOptions("h|help!" => \$Help,
  "v|version!" => \$ShowVersion,
  "dumpversion!" => \$DumpVersion,
# arguments
  "old=s" => \$Descriptor{1}{"Path"},
  "new=s" => \$Descriptor{2}{"Path"},
# general options
  "report-path=s" => \$OutputReportPath,
  "name=s" => \$TargetName,
  "arch=s" => \$TargetArch,
  "all-files!" => \$ShowAll,
# other options
  "browse|b=s" => \$Browse,
  "open!" => \$OpenReport,
  "debug!" => \$Debug
) or ERR_MESSAGE();

if(@ARGV)
{ 
    if($#ARGV==1)
    { # distdiff OLD/ NEW/
        $Descriptor{1}{"Path"} = $ARGV[0];
        $Descriptor{2}{"Path"} = $ARGV[1];
    }
    else {
        ERR_MESSAGE();
    }
}


sub ERR_MESSAGE()
{
    printMsg("INFO", "\n".$ShortUsage);
    exit($ERROR_CODE{"Error"});
}

my $HelpMessage="
NAME:
  Distro Changes Analyzer
  A tool for analyzing changes in Linux distributions

DESCRIPTION:
  Distro Changes Analyzer (DistDiff) is a tool for analyzing
  differences between Linux distributions. The tool compares
  old and new packages of the distribution and creates visual
  HTML report.

  The tool is intended for Linux maintainers who are interested
  in ensuring compatibility of old and new version of the Linux
  distribution.

  This tool is free software: you can redistribute it and/or
  modify it under the terms of the GNU GPL.

USAGE:
  $CmdName DIR1/ DIR2/ [options]

ARGUMENTS:
   DIR1
      Directory with old packages (RPM, DEB, TAR.GZ, etc).
      
      You can also pass an XML-descriptor
      of the distribution (DISTR.xml file):

          <name>
            /* Distro Name */
          </name>
        
          <packages>
            /path1/to/package(s)
            /path2/to/package(s)
            ...
          </packages>

   DIR2
      Directory with new packages (RPM, DEB, TAR.GZ, etc).

INFORMATION OPTIONS:
  -h|-help
      Print this help.

  -v|-version
      Print version information.

  -dumpversion
      Print the tool version ($TOOL_VERSION) and don't do anything else.

GENERAL OPTIONS:
  -report-path PATH
      Path to the report.
      Default:
        distdiff_reports/<DIR1>_to_<DIR2>/changes_report.html
        
  -name NAME
      Select packages with NAME prefix only.
      
  -arch ARCH
      Select packages with ARCH architecture only.
      
  -all-files
      Check all files in packages.
      Default: only interface files (headers, libs, scripts, etc.)

OTHER OPTIONS:
  -b|-browse PROGRAM
      Open report(s) in the browser (firefox, opera, etc.).
      
  -open
      Open report(s) in the default browser.

  -debug
      Show debug info.

REPORT:
    Report will be generated to:
        distdiff_reports/<DIR1>_to_<DIR2>/changes_report.html

EXIT CODES:
    0 - The tool has run without any errors.
    non-zero - The tool has run with errors.

REPORT BUGS TO:
    Andrey Ponomarenko <".$Contacts{"Main"}.">

MORE INFORMATION:
    ".$HomePage{"Dev"}."\n";

sub HELP_MESSAGE() {
    printMsg("INFO", $HelpMessage."\n");
}

# Cache
my %Cache;

# Packages
my %PackageInfo;
my %Result;

# Report
my $REPORT_PATH;
my $REPORT_DIR;

# Other
my $MODE;
my $ARCH;

my %HeaderExt = map {$_=>1} (
    "h",
    "hh",
    "hp",
    "hxx",
    "hpp",
    "h++"
);

my %ConfigExt = map {$_=>1} (
    "cfg",
    "conf",
    "cf"
);

my %ModuleExt = map {$_=>1} (
    "pm",
    "py"
);

my %ArchiveFormats = (
    "TAR.GZ"   => ["tar.gz", "tgz", "tar.Z", "taz"],
    "TAR.XZ"   => ["tar.xz", "txz"],
    "TAR.BZ2"  => ["tar.bz2", "tbz2", "tbz", "tb2"],
    "TAR.LZMA" => ["tar.lzma", "tlzma"],
    "TAR.LZ"   => ["tar.lz", "tlz"]
);

# Utils

sub get_Modules()
{
    my $TOOL_DIR = get_dirname($0);
    if(not $TOOL_DIR) {
        $TOOL_DIR = ".";
    }
    my @SEARCH_DIRS = (
        # tool's directory
        abs_path($TOOL_DIR),
        # relative path to modules
        abs_path($TOOL_DIR)."/../share/distdiff",
        # system directory
        'MODULES_INSTALL_PATH'
    );
    foreach my $DIR (@SEARCH_DIRS)
    {
        if($DIR!~/\A\//)
        { # relative path
            $DIR = abs_path($TOOL_DIR)."/".$DIR;
        }
        if(-d $DIR."/modules") {
            return $DIR."/modules";
        }
    }
    exitStatus("Module_Error", "can't find modules");
}

sub readModule($$)
{
    my ($Module, $Name) = @_;
    my $Path = $MODULES_DIR."/Internals/$Module/".$Name;
    if(not -f $Path) {
        exitStatus("Module_Error", "can't access \'$Path\'");
    }
    return readFile($Path);
}

sub get_OSgroup()
{
    my $N = $Config{"osname"};
    if($N=~/macos|darwin|rhapsody/i) {
        return "macos";
    }
    elsif($N=~/freebsd|openbsd|netbsd/i) {
        return "bsd";
    }
    return $N;
}

sub exitStatus($$)
{
    my ($Code, $Msg) = @_;
    printMsg("ERROR", $Msg);
    exit($ERROR_CODE{$Code});
}

sub printMsg($$)
{
    my ($Type, $Msg) = @_;
    if($Type!~/\AINFO/) {
        $Msg = $Type.": ".$Msg;
    }
    if($Type!~/_C\Z/) {
        $Msg .= "\n";
    }
    if($Type eq "ERROR") {
        print STDERR $Msg;
    }
    else {
        print $Msg;
    }
}

sub check_Cmd($)
{
    my $Cmd = $_[0];
    return "" if(not $Cmd);
    if(defined $Cache{"check_Cmd"}{$Cmd}) {
        return $Cache{"check_Cmd"}{$Cmd};
    }
    foreach my $Path (sort {length($a)<=>length($b)} split(/:/, $ENV{"PATH"}))
    {
        if(-x $Path."/".$Cmd) {
            return ($Cache{"check_Cmd"}{$Cmd} = 1);
        }
    }
    return ($Cache{"check_Cmd"}{$Cmd} = 0);
}

sub appendFile($$)
{
    my ($Path, $Content) = @_;
    return if(not $Path);
    if(my $Dir = get_dirname($Path)) {
        mkpath($Dir);
    }
    open(FILE, ">>", $Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

sub writeFile($$)
{
    my ($Path, $Content) = @_;
    return if(not $Path);
    if(my $Dir = get_dirname($Path)) {
        mkpath($Dir);
    }
    open(FILE, ">", $Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

sub readFile($)
{
    my $Path = $_[0];
    return "" if(not $Path or not -f $Path);
    open(FILE, "<", $Path);
    local $/ = undef;
    my $Content = <FILE>;
    close(FILE);
    return $Content;
}

sub get_filename($)
{ # much faster than basename() from File::Basename module
    if($_[0]=~/([^\/\\]+)[\/\\]*\Z/) {
        return $1;
    }
    return "";
}

sub get_dirname($)
{ # much faster than dirname() from File::Basename module
    if($_[0]=~/\A(.*?)[\/\\]+[^\/\\]*[\/\\]*\Z/) {
        return $1;
    }
    return "";
}

sub separate_path($) {
    return (get_dirname($_[0]), get_filename($_[0]));
}

sub get_abs_path($)
{ # abs_path() should NOT be called for absolute inputs
  # because it can change them (symlinks)
    my $Path = $_[0];
    if($Path!~/\A\//) {
        $Path = abs_path($Path);
    }
    return $Path;
}

sub cmd_find($;$$$$)
{
    my ($Path, $Type, $Name, $MaxDepth, $UseRegex) = @_;
    return () if(not $Path or not -e $Path);
    if(not check_Cmd("find")) {
        exitStatus("Not_Found", "can't find a \"find\" command");
    }
    $Path = get_abs_path($Path);
    if(-d $Path and -l $Path
    and $Path!~/\/\Z/)
    { # for directories that are symlinks
        $Path.="/";
    }
    my $Cmd = "find \"$Path\"";
    if($MaxDepth) {
        $Cmd .= " -maxdepth $MaxDepth";
    }
    if($Type) {
        $Cmd .= " -type $Type";
    }
    if($Name and not $UseRegex)
    { # wildcards
        $Cmd .= " -name \"$Name\"";
    }
    my $Res = `$Cmd 2>\"$TMP_DIR/null\"`;
    if($?) {
        printMsg("ERROR", "problem with \'find\' utility ($?): $!");
    }
    my @Files = split(/\n/, $Res);
    if($Name and $UseRegex)
    { # regex
        @Files = grep { /\A$Name\Z/ } @Files;
    }
    return @Files;
}

sub openReport($)
{
    my $Path = $_[0];
    my $Cmd = "";
    if($Browse)
    { # user-defined browser
        $Cmd = $Browse." \"$Path\"";
    }
    if(not $Cmd)
    { # default browser
        if($OSgroup eq "macos") {
            $Cmd = "open \"$Path\"";
        }
        else
        { # linux, freebsd, solaris
            my @Browsers = (
                "x-www-browser",
                "sensible-browser",
                "firefox",
                "opera",
                "xdg-open",
                "lynx",
                "links"
            );
            foreach my $Br (@Browsers)
            {
                if(check_Cmd($Br))
                {
                    $Cmd = $Br." \"$Path\"";
                    last;
                }
            }
        }
    }
    if($Cmd)
    {
        if($Debug) {
            printMsg("INFO", "running $Cmd");
        }
        if($OSgroup ne "windows"
        and $OSgroup ne "macos")
        {
            if($Cmd!~/lynx|links/) {
                $Cmd .= "  >\"$TMP_DIR/null\" 2>&1 &";
            }
        }
        system($Cmd);
    }
    else {
        printMsg("ERROR", "cannot open report in browser");
    }
}

sub composeHTML_Head($$$$$)
{
    my ($Title, $Keywords, $Description, $Styles, $Scripts) = @_;
    return "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">
    <html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\">
    <head>
    <meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />
    <meta name=\"keywords\" content=\"$Keywords\" />
    <meta name=\"description\" content=\"$Description\" />
    <title>
        $Title
    </title>
    <style type=\"text/css\">
    $Styles
    </style>
    <script type=\"text/javascript\" language=\"JavaScript\">
    <!--
    $Scripts
    -->
    </script>
    </head>";
}

sub cmpVersions($$)
{ # compare two versions in dotted-numeric format
    my ($V1, $V2) = @_;
    return 0 if($V1 eq $V2);
    return undef if($V1!~/\A\d+[\.\d+]*\Z/);
    return undef if($V2!~/\A\d+[\.\d+]*\Z/);
    my @V1Parts = split(/\./, $V1);
    my @V2Parts = split(/\./, $V2);
    for (my $i = 0; $i <= $#V1Parts && $i <= $#V2Parts; $i++) {
        return -1 if(int($V1Parts[$i]) < int($V2Parts[$i]));
        return 1 if(int($V1Parts[$i]) > int($V2Parts[$i]));
    }
    return -1 if($#V1Parts < $#V2Parts);
    return 1 if($#V1Parts > $#V2Parts);
    return 0;
}

sub parseTag($$)
{
    my ($CodeRef, $Tag) = @_;
    return "" if(not $CodeRef or not ${$CodeRef} or not $Tag);
    if(${$CodeRef}=~s/\<\Q$Tag\E\>((.|\n)+?)\<\/\Q$Tag\E\>//)
    {
        my $Content = $1;
        $Content=~s/(\A\s+|\s+\Z)//g;
        return $Content;
    }
    return "";
}

sub cut_off_number($$$)
{
    my ($num, $digs_to_cut, $z) = @_;
    if($num!~/\./)
    {
        $num .= ".";
        foreach (1 .. $digs_to_cut-1) {
            $num .= "0";
        }
    }
    elsif($num=~/\.(.+)\Z/ and length($1)<$digs_to_cut-1)
    {
        foreach (1 .. $digs_to_cut - 1 - length($1)) {
            $num .= "0";
        }
    }
    elsif($num=~/\d+\.(\d){$digs_to_cut,}/) {
      $num=sprintf("%.".($digs_to_cut-1)."f", $num);
    }
    $num=~s/\.[0]+\Z//g;
    if($z) {
        $num=~s/(\.[1-9]+)[0]+\Z/$1/g;
    }
    return $num;
}

# Logic

sub queryRPM($$)
{
    my ($Path, $Query) = @_;
    return `rpm -qp $Query \"$Path\" 2>$TMP_DIR/null`;
}

sub queryDeb($$)
{
    my ($Path, $Query) = @_;
    return `dpkg-deb $Query \"$Path\" 2>$TMP_DIR/null`;
}

sub get_Format_P($)
{
    if($_[0]=~/\.(tar\.\w+)\Z/) {
        return uc($1);
    }
    elsif($_[0]=~/\.(src\.rpm)\Z/i)
    { # source rpm
        return uc($1);
    }
    elsif($_[0]=~/\.(rpm|deb)\Z/i)
    { # rpm, deb
        return uc($1);
    }
    return undef;
}

sub extractPkg($$)
{
    my ($Path, $Out) = @_;
    if(my $Format = get_Format_P($Path))
    {
        $Path = abs_path($Path);
        mkpath($Out);
        
        if($Format eq "RPM"
        or $Format eq "SRC.RPM")
        {
            chdir($Out);
            system("rpm2cpio \"$Path\" | cpio -id 2>\"$TMP_DIR/null\"");
            chdir($ORIG_DIR);
        }
        elsif($Format eq "DEB") {
            system("dpkg-deb --extract \"$Path\" \"$Out\"");
        }
        else {
            extractArchive($Path, $Out);
        }
    }
}

sub extractArchive($$)
{
    my ($Path, $Out) = @_;
    
    if(my $Format = get_Format_P($Path))
    {
        my $Cmd = undef;
        if($Format eq "TAR.GZ") {
            $Cmd = "tar -xzf";
        }
        elsif($Format eq "TAR.BZ2") {
            $Cmd = "tar -xjf";
        }
        elsif($Format eq "TAR.XZ") {
            $Cmd = "tar -Jxf";
        }
        elsif($Format eq "TAR.LZMA") {
            $Cmd = "tar -xf --lzma";
        }
        elsif($Format eq "TAR.LZ") {
            $Cmd = "tar -xf --lzip";
        }
        else
        { # unknown
            return "";
        }
        system("$Cmd \"$Path\" --directory=\"$Out\" >\"$TMP_DIR/null\" 2>&1");
    }
}

sub listArchive($)
{
    my $Path = $_[0];
    
    if(my $Format = get_Format_P($Path))
    {
        my $Cmd = undef;
        if($Format eq "TAR.GZ") {
            $Cmd = "tar -tzf";
        }
        elsif($Format eq "TAR.BZ2") {
            $Cmd = "tar -tjf";
        }
        elsif($Format eq "TAR.XZ") {
            $Cmd = "tar -Jtf";
        }
        elsif($Format eq "TAR.LZMA") {
            $Cmd = "tar -tf --lzma";
        }
        elsif($Format eq "TAR.LZ") {
            $Cmd = "tar -tf --lzip";
        }
        else
        { # unknown
            return "";
        }
        return `$Cmd \"$Path\" 2>\"$TMP_DIR/null\"`;
    }
}

sub readDescriptor($$)
{
    my ($Path, $Version) = @_;
    return if(not -f $Path);
    my $Content = readFile($Path);
    if(not $Content) {
        exitStatus("Error", "XML-descriptor is empty");
    }
    if($Content!~/\</) {
        exitStatus("Error", "XML-descriptor has a wrong format");
    }
    $Content=~s/\/\*(.|\n)+?\*\///g;
    $Content=~s/<\!--(.|\n)+?-->//g;
    if(my $Pkgs = parseTag(\$Content, "packages"))
    {
        foreach my $Path (split(/\s*\n\s*/, $Pkgs))
        {
            if(not -e $Path) {
                exitStatus("Access_Error", "can't access \'".$Path."\'");
            }
            if(-d $Path) {
                registerDir($Path, $Version);
            }
            else {
                registerPackage($Path, $Version);
            }
        }
    }
    else {
        exitStatus("Error", "packages in the XML-descriptor are not specified (<packages> section)");
    }
}

sub parseVersion($)
{
    my $Name = $_[0];
    if(my $Format = get_Format_P($Name)) {
        $Name=~s/\.(\Q$Format\E)\Z//;
    }
    if($Name=~/\A(.+[a-z])[\-\_](v|ver|)(\d.+?)\Z/i)
    { # libsample-N
      # libsample-vN
        return ($1, $3);
    }
    elsif($Name=~/\A(.+?)[\-\_]*(\d[\d\.\-]*)\Z/i)
    { # libsampleN
      # libsampleN-X.Y
        return ($1, $2);
    }
    elsif($Name=~/\A(.+)[\-\_](v|ver|)(.+?)\Z/i)
    { # libsample-N
      # libsample-vN
        return ($1, $3);
    }
    elsif($Name=~/\A([a-z_\-]+)(\d.+?)\Z/i)
    { # libsampleNb
        return ($1, $2);
    }
    return ();
}

sub registerDir($$)
{
    my ($Dir, $Version) = @_;
    
    my @Files = cmd_find($Dir, "f", "*.src.rpm"); # SRPMs
    if(not defined $ShowAll)
    { # all files
        $MODE = "ALL";
    }
    
    if(not @Files)
    { # search for RPMs
        @Files = (@Files, cmd_find($Dir, "f", "*.rpm"));
        if(not defined $ShowAll)
        { # interface files only
            $MODE = "INT";
        }
    }
    if(not @Files)
    { # search for DEBs
        @Files = (@Files, cmd_find($Dir, "f", "*.deb"));
        if(not defined $ShowAll)
        { # interface files only
            $MODE = "INT";
        }
    }
    if(not @Files)
    { # search for archives
        @Files = (@Files, cmd_find($Dir, "f"));
        if(not defined $ShowAll)
        { # all files
            $MODE = "ALL";
        }
    }
    if(not @Files)
    { # search for archives
        exitStatus("Error", "can't find packages in \'$Dir\'");
    }
    foreach my $Path (sort {lc($a) cmp lc($b)} @Files)
    {
        my $Name = get_filename($Path);
        
        if(defined $TargetName)
        {
            if(index($Name, $TargetName)!=0)
            { # filter by prefix
                next;
            }
        }
        
        registerPackage($Path, $Version);
    }
}

sub registerPackage($$)
{
    my ($Path, $Version) = @_;
    my $PkgName = get_filename($Path);
    if(my $Format = get_Format_P($PkgName))
    {
        if($Format eq "RPM"
        or $Format eq "SRC.RPM")
        {
            my $Info = queryRPM($Path, "--queryformat \%{name},\%{arch},\%{version},\%{release}");
            my ($Name, $Arch, $Ver, $Rel) = split(",", $Info);
            
            if($Arch and $Arch ne "noarch")
            {
                if(defined $ARCH)
                {
                    if($Arch ne $ARCH) {
                        return;
                    }
                }
                else
                { # select arch
                    $ARCH = $Arch;
                }
            }
            
            if($Debug) {
                printMsg("INFO", "  ".$PkgName);
            }
            
            my %Attr = ("Path"=>$Path, "Release"=>$Rel);
            
            foreach my $File (split(/\n/, queryRPM($Path, "--list")))
            { # register files
                if($MODE eq "ALL") {
                    $Attr{"Files"}{$File} = 1;
                }
                elsif(my $Format = get_Format($File)) {
                    $Attr{"Files"}{$File} = $Format;
                }
            }
            
            $PackageInfo{$Version}{$Name}{$Ver} = \%Attr;
        }
        elsif($Format eq "DEB")
        {
            my $Info = `dpkg -f $Path`;
            
            my $Name = undef;
            if($Info=~/Package\s*:\s*(.+)/) {
                $Name = $1;
            }
            else {
                next;
            }
            
            my ($Ver, $Arch) = ("", "");
            if($Info=~/Version\s*:\s*(.+)/) {
                $Ver = $1;
            }
            if($Info=~/Architecture\s*:\s*(.+)/) {
                $Arch = $1;
            }
            
            if($Arch and $Arch ne "noarch")
            {
                if(defined $ARCH)
                {
                    if($Arch ne $ARCH) {
                        return;
                    }
                }
                else
                { # select arch
                    $ARCH = $Arch;
                }
            }
            
            if($Debug) {
                printMsg("INFO", "  ".$PkgName);
            }
            
            my %Attr = ("Path"=>$Path);
            
            foreach (split(/\n/, queryDeb($Path, "-c")))
            { # register files
                my @R = split(/\s+/, $_);
                my $File = $R[5];
                $File=~s/\A\.\//\//;
                if($MODE eq "ALL") {
                    $Attr{"Files"}{$File} = 1;
                }
                elsif(my $Format = get_Format($File)) {
                    $Attr{"Files"}{$File} = $Format;
                }
            }
            delete($Attr{"Files"}{"./"});
            
            $PackageInfo{$Version}{$Name}{$Ver} = \%Attr;
        }
        elsif(defined $ArchiveFormats{$Format})
        {
            if($Debug) {
                printMsg("INFO", "  ".$PkgName);
            }
            
            my ($Name, $Ver) = parseVersion($PkgName);
            
            my %Attr = ("Path"=>$Path);
            foreach my $File (split(/\n/, listArchive($Path)))
            { # register files
                if($MODE eq "ALL") {
                    $Attr{"Files"}{$File} = 1;
                }
                elsif(my $Format = get_Format($File)) {
                    $Attr{"Files"}{$File} = $Format;
                }
            }
            
            $PackageInfo{$Version}{$Name}{$Ver} = \%Attr;
        }
    }
}

sub get_Format($)
{
    my $Name = get_filename($_[0]);
    if($Name=~/\.([a-z\+]+)\Z/i)
    {
        if(defined $HeaderExt{$1}) {
            return "HEADER";
        }
        elsif(defined $ModuleExt{$1}) {
            return "MODULE";
        }
        elsif(defined $ConfigExt{$1}) {
            return "CONFIG";
        }
        elsif($1 eq "so")
        {
            if(index($Name, "lib")==0) {
                return "SHARED_LIBRARY";
            }
        }
    }
    elsif(index($_[0],"/include/")!=-1)
    { # headers
        return "HEADER";
    }
    elsif(index($Name, "lib")==0)
    { # libs
        if($Name=~/\.so[\d\.\-]*\Z/) {
            return "SHARED_LIBRARY";
        }
    }
    return undef;
}

sub readSymbols($)
{
    my $Path = $_[0];
    my $Format = get_Format($Path);
    
    my %Symbols = ();
    
    if($Format eq "SHARED_LIBRARY")
    {
        open(LIB, "readelf -WhlSsdA \"$Path\" 2>\"$TMP_DIR/null\" |");
        my $symtab = undef; # indicates that we are processing 'symtab' section of 'readelf' output
        while(<LIB>)
        {
            if(defined $symtab)
            { # do nothing with symtab
                if(index($_, "'.dynsym'")!=-1)
                { # dynamic table
                    $symtab = undef;
                }
            }
            elsif(index($_, "'.symtab'")!=-1)
            { # symbol table
                $symtab = 1;
            }
            elsif(my @Info = readline_ELF($_))
            {
                my ($Bind, $Ndx, $Symbol) = ($Info[3], $Info[5], $Info[6]);
                if($Ndx ne "UND"
                and $Bind ne "WEAK")
                { # only imported symbols
                    $Symbols{$Symbol} = 1;
                }
            }
        }
        close(LIB);
    }
    
    return %Symbols;
}

my %ELF_BIND = map {$_=>1} (
    "WEAK",
    "GLOBAL"
);

my %ELF_TYPE = map {$_=>1} (
    "FUNC",
    "IFUNC",
    "OBJECT",
    "COMMON"
);

my %ELF_VIS = map {$_=>1} (
    "DEFAULT",
    "PROTECTED"
);

sub readline_ELF($)
{ # read the line of 'readelf' output corresponding to the symbol
    my @Info = split(/\s+/, $_[0]);
    #  Num:   Value      Size Type   Bind   Vis       Ndx  Name
    #  3629:  000b09c0   32   FUNC   GLOBAL DEFAULT   13   _ZNSt12__basic_fileIcED1Ev@@GLIBCXX_3.4
    shift(@Info); # spaces
    shift(@Info); # num
    if($#Info!=6)
    { # other lines
        return ();
    }
    return () if(not defined $ELF_TYPE{$Info[2]});
    return () if(not defined $ELF_BIND{$Info[3]});
    return () if(not defined $ELF_VIS{$Info[4]});
    if($Info[5] eq "ABS" and $Info[0]=~/\A0+\Z/)
    { # 1272: 00000000     0 OBJECT  GLOBAL DEFAULT  ABS CXXABI_1.3
        return ();
    }
    if(index($Info[2], "0x") == 0)
    { # size == 0x3d158
        $Info[2] = hex($Info[2]);
    }
    return @Info;
}

sub compareSymbols($$$)
{
    my ($Name, $P1, $P2) = @_;
    
    my %Symbols1 = readSymbols($P1);
    my %Symbols2 = readSymbols($P2);
    
    my $Changed = 0;
    
    foreach my $Symbol (keys(%Symbols1))
    {
        if(not defined $Symbols2{$Symbol})
        {
            $Changed = 1;
            if(defined $Result{$Name}{"Symbols"}{"Added"}{$Symbol})
            { # moved
                delete($Result{$Name}{"Symbols"}{"Added"}{$Symbol});
            }
            else
            { # removed
                $Result{$Name}{"Symbols"}{"Removed"}{$Symbol} = 1;
            }
        }
    }
    
    foreach my $Symbol (keys(%Symbols2))
    {
        if(not defined $Symbols1{$Symbol})
        {
            $Changed = 1;
            if(defined $Result{$Name}{"Symbols"}{"Removed"}{$Symbol})
            { # moved
                delete($Result{$Name}{"Symbols"}{"Removed"}{$Symbol})
            }
            else
            { # added
                $Result{$Name}{"Symbols"}{"Added"}{$Symbol} = 1;
            }
        }
    }
    
    return $Changed;
}

sub changedPkg($$$)
{
    my ($Name, $Ver1, $Ver2) = @_;
    
    my $Files1 = $PackageInfo{1}{$Name}{$Ver1}{"Files"};
    my $Files2 = $PackageInfo{2}{$Name}{$Ver2}{"Files"};
    
    my %Target = ();
    
    foreach my $File (keys(%{$Files1}))
    {
        if(defined $Files2->{$File}) {
            $Target{$File} = $Files2->{$File};
        }
        else
        { # removed
            $Result{$Name}{"Files"}{"Removed"}{$File} = 1;
        }
    }
    
    foreach my $File (keys(%{$Files2}))
    {
        if(not defined $Files1->{$File})
        { # added
            $Result{$Name}{"Files"}{"Added"}{$File} = 1;
        }
    }
    
    if(my @Target = keys(%Target))
    {
        my $Out1 = $TMP_DIR."/p1";
        my $Out2 = $TMP_DIR."/p2";
        
        my $Path1 = $PackageInfo{1}{$Name}{$Ver1}{"Path"};
        my $Path2 = $PackageInfo{2}{$Name}{$Ver2}{"Path"};
        
        extractPkg($Path1, $Out1);
        extractPkg($Path2, $Out2);
        
        foreach my $File (@Target)
        {
            my $Format = $Target{$File};
            
            my $FP1 = $Out1."/".$File;
            my $FP2 = $Out2."/".$File;
            
            if(-l $FP1 or -d $FP1)
            { # skip links and directories
                next;
            }
            
            if($Format eq "SHARED_LIBRARY")
            {
                if(compareSymbols($Name, $FP1, $FP2)) {
                    $Result{$Name}{"Files"}{"Changed"}{$File} = 1;
                }
            }
            elsif(-s $FP1 != -s $FP2)
            { # different size
                $Result{$Name}{"Files"}{"Changed"}{$File} = 1;
            }
            elsif(compare($FP1, $FP2)==1)
            { # different content
                $Result{$Name}{"Files"}{"Changed"}{$File} = 1;
            }
        }
        
        rmtree($Out1);
        rmtree($Out2);
    }
    
    foreach my $Tag ("Changed", "Added", "Removed")
    {
        if(defined $Result{$Name}{"Files"}{$Tag})
        {
            if(keys(%{$Result{$Name}{"Files"}{$Tag}}))
            {
                $Result{$Name}{"Changed"} = 1;
                last;
            }
        }
    }
    
    return $Result{$Name}{"Changed"};
}

sub pkgDiff($$$)
{
    my ($Name, $OldPath, $NewPath) = @_;
    
    my $ExtraDir = "$TMP_DIR/extra-info";
    my $ReportDir = "pkgdiff/$Name";
    my $Report = $ReportDir."/changes.html";
    
    my $Cmd = $PKGDIFF." \"$OldPath\" \"$NewPath\" --report-path=\"$REPORT_DIR/$Report\" --extra-info=\"$ExtraDir\"";
    if($Debug) {
        printMsg("INFO", "running ".$Cmd);
    }
    system($Cmd." >\"$TMP_DIR/log\"");
    
    my $Output = readFile("$TMP_DIR/log");
    my $Delta = "0%";
    if($Output=~/CHANGED \((.+?)\)/) {
        $Delta = $1;
    }
    $Result{$Name}{"Delta"} = $Delta;
    $Result{$Name}{"Report"} = $Report;
    
    if(my $Info = readFile($ExtraDir."/files.xml"))
    {
        foreach my $Tag ("Moved", "Renamed")
        {
            foreach (split(/\s*\n\s*/, parseTag(\$Info, lc($Tag))))
            {
                if(my ($From, $To) = split(";", $_)) {
                    $Result{$Name}{"Files"}{$Tag}{$From} = $To;
                }
            }
        }
        
        my @Tags = ("Changed");
        if($MODE eq "ALL") {
            push(@Tags, "Added", "Removed");
        }
        
        foreach my $Tag (@Tags)
        {
            foreach my $File (split(/\s*\n\s*/, parseTag(\$Info, lc($Tag)))) {
                $Result{$Name}{"Files"}{$Tag}{$File} = 1;
            }
        }
    }
    
    if($MODE eq "ALL")
    {
        if(my $Info = readFile($ExtraDir."/symbols.xml"))
        {
            foreach my $Tag ("Added", "Removed")
            {
                foreach my $File (split(/\s*\n\s*/, parseTag(\$Info, lc($Tag)))) {
                    $Result{$Name}{"Symbols"}{$Tag}{$File} = 1;
                }
            }
        }
    }
    
    if(my @Files = keys(%{$Result{$Name}{"Files"}{"Moved"}}))
    {
        foreach my $File (@Files)
        {
            delete($Result{$Name}{"Files"}{"Removed"}{$File});
            if(my $To = $Result{$Name}{"Files"}{"Moved"}{$File}) {
                delete($Result{$Name}{"Files"}{"Added"}{$To});
            }
        }
    }
    
    foreach my $File (keys(%{$Result{$Name}{"Files"}{"Changed"}}))
    { # temp fix for pkgdiff 1.5
      # renamed and moved files
        if(defined $Result{$Name}{"Files"}{"Removed"}{$File}) {
            delete($Result{$Name}{"Files"}{"Changed"}{$File});
        }
    }
    
    if($MODE ne "ALL")
    {
        foreach my $File (keys(%{$Result{$Name}{"Files"}{"Changed"}}))
        {
            if(not get_Format($File)) {
                delete($Result{$Name}{"Files"}{"Changed"}{$File});
            }
        }
    }
    
    $Result{$Name}{"Changed"} = 0;
    
    foreach my $Tag ("Changed", "Added", "Removed")
    {
        if(defined $Result{$Name}{"Files"}{$Tag})
        {
            if(keys(%{$Result{$Name}{"Files"}{$Tag}}))
            {
                $Result{$Name}{"Changed"} = 1;
                last;
            }
        }
    }
    
    rmtree($ExtraDir);
    unlink($TMP_DIR."/log");
    
    if(not $Result{$Name}{"Changed"}) {
        rmtree($REPORT_DIR."/".$ReportDir);
    }
}

sub comparePackages()
{
    printMsg("INFO", "");
    printMsg("INFO", "comparing packages ...");
    
    foreach my $Name (sort {lc($a) cmp lc($b)} keys(%{$PackageInfo{1}}))
    {
        if($Debug) {
            printMsg("INFO", "  ".$Name);
        }
        
        my @OldVers = keys(%{$PackageInfo{1}{$Name}});
        if($#OldVers>0) {
            @OldVers = sort {cmpVersions($b, $a)} @OldVers;
        }
        my $OldVer = $OldVers[0];
        
        if(not defined $PackageInfo{2}{$Name})
        { # removed
            $Result{$Name}{"Removed"} = $OldVer;
            next;
        }
        
        my @NewVers = keys(%{$PackageInfo{2}{$Name}});
        if($#NewVers>0) {
            @NewVers = sort {cmpVersions($b, $a)} @NewVers;
        }
        my $NewVer = $NewVers[0];
        
        $Result{$Name}{"Old"} = $OldVer;
        $Result{$Name}{"New"} = $NewVer;
        
        my $OldPath = $PackageInfo{1}{$Name}{$OldVer}{"Path"};
        my $NewPath = $PackageInfo{2}{$Name}{$NewVer}{"Path"};
        
        if($MODE eq "ALL"
        or changedPkg($Name, $OldVer, $NewVer))
        { # changed target group of files
            pkgDiff($Name, $OldPath, $NewPath);
        }
    }
    
    foreach my $Name (sort {lc($a) cmp lc($b)} keys(%{$PackageInfo{2}}))
    {
        my @NewVers = keys(%{$PackageInfo{2}{$Name}});
        if($#NewVers>0) {
            @NewVers = sort {cmpVersions($b, $a)} @NewVers;
        }
        my $NewVer = $NewVers[0];
        
        if(not defined $PackageInfo{1}{$Name})
        { # added
        
            if($Debug) {
                printMsg("INFO", "  ".$Name);
            }
            
            $Result{$Name}{"Added"} = $NewVer;
            next;
        }
    }
}

sub createTable()
{
    my $REPORT = "";
    
    my ($Added_P, $Removed_P, $Changed_P, $Unchanged_P) = (0, 0, 0, 0);
    my ($Added_F, $Removed_F, $Changed_F, $Unchanged_F) = (0, 0, 0, 0);
    
    my $Total_F = 0;
    
    foreach my $Name (sort {lc($a) cmp lc($b)} keys(%Result))
    {
        if($Result{$Name}{"Changed"})
        {
            $Changed_P += 1;
            
            # Files
            $Added_F += keys(%{$Result{$Name}{"Files"}{"Added"}});
            $Removed_F += keys(%{$Result{$Name}{"Files"}{"Removed"}});
            $Changed_F += keys(%{$Result{$Name}{"Files"}{"Changed"}});
            
            my $OldVer = $Result{$Name}{"Old"};
            $Total_F += keys(%{$PackageInfo{1}{$Name}{$OldVer}{"Files"}});
        }
        elsif(defined $Result{$Name}{"Added"})
        {
            $Added_P += 1;
        }
        elsif(defined $Result{$Name}{"Removed"})
        {
            $Removed_P += 1;
        }
        else
        {
            $Unchanged_P += 1;
            
            # Files
            my $OldVer = $Result{$Name}{"Old"};
            $Total_F += keys(%{$PackageInfo{1}{$Name}{$OldVer}{"Files"}});
        }
    }
    
    my $Total_P = keys(%Result);
    
    $REPORT .= "<h2>Packages</h2><hr/>\n";
    $REPORT .= "<table class='summary'>\n";
    $REPORT .= "<tr><th></th><th style='text-align:center;'>Count</th></tr>\n";
    $REPORT .= "<tr><th>Total</th><td>$Total_P</td></tr>\n";
    if($Total_P)
    {
        $REPORT .= "<tr><th>Changed</th><td>".$Changed_P." (<b>".cut_off_number($Changed_P*100/$Total_P, 2, 1)."%</b>)</td></tr>\n";
        $REPORT .= "<tr><th>Removed</th><td>".$Removed_P." (<b>".cut_off_number($Removed_P*100/$Total_P, 2, 1)."%</b>)</td></tr>\n";
        $REPORT .= "<tr><th>Added</th><td>".$Added_P." (<b>".cut_off_number($Added_P*100/$Total_P, 2, 1)."%</b>)</td></tr>\n";
    }
    else
    {
        $REPORT .= "<tr><th>Changed</th><td>0 (<b>0%</b>)</td></tr>\n";
        $REPORT .= "<tr><th>Removed</th><td>0 (<b>0%</b>)</td></tr>\n";
        $REPORT .= "<tr><th>Added</th><td>0 (<b>0%</b>)</td></tr>\n";
    }
    $REPORT .= "</table>\n";
    
    $REPORT .= "<h2>Files</h2><hr/>\n";
    $REPORT .= "<table class='summary'>\n";
    $REPORT .= "<tr><th></th><th style='text-align:center;'>Count</th></tr>\n";
    $REPORT .= "<tr><th>Total</th><td>$Total_F</td></tr>\n";
    if($Total_F)
    {
        $REPORT .= "<tr><th>Changed</th><td>".$Changed_F." (<b>".cut_off_number($Changed_F*100/$Total_F, 3, 1)."%</b>)</td></tr>\n";
        $REPORT .= "<tr><th>Removed</th><td>".$Removed_F." (<b>".cut_off_number($Removed_F*100/$Total_F, 3, 1)."%</b>)</td></tr>\n";
        $REPORT .= "<tr><th>Added</th><td>".$Added_F." (<b>".cut_off_number($Added_F*100/$Total_F, 3, 1)."%</b>)</td></tr>\n";
    }
    else
    {
        $REPORT .= "<tr><th>Changed</th><td>0 (<b>0%</b>)</td></tr>\n";
        $REPORT .= "<tr><th>Removed</th><td>0 (<b>0%</b>)</td></tr>\n";
        $REPORT .= "<tr><th>Added</th><td>0 (<b>0%</b>)</td></tr>\n";
    }
    $REPORT .= "</table>\n";
    
    # report
    $REPORT .= "<h2>Report</h2><hr/>\n";
    
    if($Changed_P or $Removed_P or $Added_P)
    {
        $REPORT .= "Show: <select style='width:90px' id='sfilt' onchange=\"javascript:applyFilter('Table')\">\n";
        $REPORT .= "<option value='all'>all</option>\n";
        if($Changed_P) {
            $REPORT .= "<option value='changed'>changed</option>\n";
        }
        if($Removed_P) {
            $REPORT .= "<option value='removed'>removed</option>\n";
        }
        if($Added_P) {
            $REPORT .= "<option value='added'>added</option>\n";
        }
        $REPORT .= "</select>\n";
        $REPORT .= "<br/><br/>\n";
    }
    
    my $JSort = "title='sort' onclick='javascript:sort(this, 1)' style='cursor:pointer'";
    
    $REPORT .= "<table class='report' id='Table'>\n";
    $REPORT .= "<tr id='topHeader'>";
    $REPORT .= "<th $JSort>Package</th><th $JSort>Status</th><th>Visual<br/>Diff</th>";
    if(defined $ShowAll) {
        $REPORT .= "<th>Changed/Removed<br/>Files</th>";
    }
    else {
        $REPORT .= "<th>Changed/Removed<br/>Interface Files (Headers, Libraries, etc.)</th>";
    }
    $REPORT .= "<th>Removed<br/>Symbols</th><th>Added<br/>Symbols</th>";
    if(defined $ShowAll) {
        $REPORT .= "<th>Added<br/>Files</th>";
    }
    else {
        $REPORT .= "<th>Added<br/>Interface Files</th>";
    }
    $REPORT .= "</tr>\n";
    
    foreach my $Name (sort {lc($a) cmp lc($b)} keys(%Result))
    {
        $REPORT .= "<tr>\n";
        
        $REPORT .= "<td>$Name</td>\n";
        
        if($Result{$Name}{"Changed"})
        {
            $REPORT .= "<td class='warning right'>changed</td>";
            
            $REPORT .= "<td title='Visual Diff' class='right'><a href='".$Result{$Name}{"Report"}."' target='_blank'>".$Result{$Name}{"Delta"}."</a></td>\n";
            
            my @Changed = ();
            
            if(defined $Result{$Name}{"Files"}{"Changed"}) {
                push(@Changed, keys(%{$Result{$Name}{"Files"}{"Changed"}}));
            }
            
            if(defined $Result{$Name}{"Files"}{"Removed"}) {
                push(@Changed, keys(%{$Result{$Name}{"Files"}{"Removed"}}));
            }
            
            if(@Changed)
            {
                $REPORT .= "<td title='Changed/Removed Files' class='f_path'>\n";
                foreach my $File (sort {lc($a) cmp lc($b)} @Changed)
                {
                    if(defined $Result{$Name}{"Files"}{"Removed"}{$File}) {
                        $REPORT .= "<span style='color:Red;'>".$File."</span><br/>\n";
                    }
                    else {
                        $REPORT .= $File."<br/>\n";
                    }
                }
                $REPORT .= "</td>\n";
            }
            else {
                $REPORT .= "<td></td>\n";
            }
            
            if(my @Syms = sort {lc($a) cmp lc($b)} keys(%{$Result{$Name}{"Symbols"}{"Removed"}}))
            {
                my $RPath = "symbols/$Name/removed.txt";
                writeFile($REPORT_DIR."/".$RPath, join("\n", @Syms));
                
                $REPORT .= "<td title='Removed Symbols' class='failed right'>";
                $REPORT .= "<a href='".$RPath."' target='_blank'>".($#Syms+1)."</a>";
                $REPORT .= "</td>\n";
            }
            else {
                $REPORT .= "<td></td>\n";
            }
            
            if(my @Syms = sort {lc($a) cmp lc($b)} keys(%{$Result{$Name}{"Symbols"}{"Added"}}))
            {
                my $RPath = "symbols/$Name/added.txt";
                writeFile($REPORT_DIR."/".$RPath, join("\n", @Syms));
                
                $REPORT .= "<td title='Added Symbols' class='new right'>";
                $REPORT .= "<a href='".$RPath."' target='_blank'>".($#Syms+1)."</a>";
                $REPORT .= "</td>\n";
            }
            else {
                $REPORT .= "<td></td>\n";
            }
            
            my @Added = ();
            
            if(defined $Result{$Name}{"Files"}{"Added"}) {
                push(@Added, keys(%{$Result{$Name}{"Files"}{"Added"}}));
            }
            
            if(@Added)
            {
                $REPORT .= "<td title='Added Files' class='f_path'>\n";
                foreach my $File (sort {lc($a) cmp lc($b)} @Added) {
                    $REPORT .= $File."<br/>\n";
                }
                $REPORT .= "</td>\n";
            }
            else {
                $REPORT .= "<td></td>\n";
            }
        }
        else
        {
            if(defined $Result{$Name}{"Added"}) {
                $REPORT .= "<td class='new right'>added</td>\n";
            }
            elsif(defined $Result{$Name}{"Removed"}) {
                $REPORT .= "<td class='failed right'>removed</td>\n";
            }
            else {
                $REPORT .= "<td class='passed right'>unchanged</td>\n";
            }
            $REPORT .= "<td></td><td></td><td></td><td></td><td></td>\n";
        }
        
        $REPORT .= "</tr>\n";
    }
    
    $REPORT .= "</table>\n";
    
    return $REPORT;
}

sub createReport($)
{
    my $Path = $_[0];
    
    my $CssStyles = readModule("Styles", "Index.css");
    my $JScripts = readModule("Scripts", "Sort.js");
    $JScripts .= "\n".readModule("Scripts", "Filter.js");
    
    my $Title = "Changes report between ".$Descriptor{1}{"Distr"}." and ".$Descriptor{2}{"Distr"};
    my $Keywords = $Descriptor{1}{"Distr"}.", ".$Descriptor{2}{"Distr"}.", changes, report";
    my $Description = $Title;
    
    my $REPORT = composeHTML_Head($Title, $Keywords, $Description, $CssStyles, $JScripts);
    $REPORT .= "<body>\n<div><a name='Top'></a>\n";
    
    my $Header = "Changes report between <span style='color:Red;'>".$Descriptor{1}{"Distr"}."</span> and <span style='color:Red;'>".$Descriptor{2}{"Distr"}."</span>";
    if($ARCH) {
        $Header .= " on <span style='color:Blue;'>".$ARCH."</span>";
    }
    $REPORT .= "<h1>$Header</h1>\n";
    
    $REPORT .= "<h2>Test Info</h2><hr/>\n";
    $REPORT .= "<table class='summary'>\n";
    $REPORT .= "<tr><th>Distro #1</th><td>".$Descriptor{1}{"Distr"}."</td></tr>\n";
    $REPORT .= "<tr><th>Distro #2</th><td>".$Descriptor{2}{"Distr"}."</td></tr>\n";
    if($ARCH) {
        $REPORT .= "<tr><th>CPU Type</th><td>".$ARCH."</td></tr>\n";
    }
    if($MODE ne "ALL") {
        $REPORT .= "<tr><th>Subject</th><td>Interface files</td></tr>\n";
    }
    $REPORT .= "</table>\n";
    
    $REPORT .= createTable();
    
    $REPORT .= "\n</div>\n<br/><br/><br/><hr/>\n";
    
    # footer
    $REPORT .= "<div style='width:100%;font-size:11px;' align='right'><i>Generated on ".(localtime time);
    $REPORT .= " by <a href='".$HomePage{"Dev"}."' target='_blank'>Distro Changes Analyzer</a> - DistDiff";
    $REPORT .= " $TOOL_VERSION &#160;<br/>A tool for analyzing changes in Linux distributions&#160;&#160;</i></div>";
    
    $REPORT .= "\n<div style='height:999px;'></div>\n</body></html>";
    writeFile($Path, $REPORT);
    
    printMsg("INFO", "");
    printMsg("INFO", "see detailed report:\n  $Path");
    
    if($Browse or $OpenReport)
    { # open in browser
        openReport($Path);
    }
}

sub scenario()
{
    if($Help)
    {
        HELP_MESSAGE();
        exit(0);
    }
    if($ShowVersion)
    {
        printMsg("INFO", "Distro Changes Analyzer (DistDiff) $TOOL_VERSION\nCopyright (C) 2013 ROSA Laboratory\nLicense: GNU GPL <http://www.gnu.org/licenses/>\nThis program is free software: you can redistribute it and/or modify it.\n\nWritten by Andrey Ponomarenko.");
        exit(0);
    }
    if($DumpVersion)
    {
        printMsg("INFO", $TOOL_VERSION);
        exit(0);
    }
    
    # check PkgDiff
    if(my $Version = `$PKGDIFF -dumpversion`)
    {
        if(cmpVersions($Version, $PKGDIFF_VERSION)<0) {
            exitStatus("Module_Error", "the version of PkgDiff should be $PKGDIFF_VERSION or newer");
        }
    }
    else {
        exitStatus("Module_Error", "cannot find \'$PKGDIFF\'");
    }
    
    if(defined $TargetArch) {
        $ARCH = $TargetArch;
    }
    
    if(defined $ShowAll) {
        $MODE = "ALL";
    }
    
    if(not $Descriptor{1}{"Path"}) {
        exitStatus("Error", "-old option is not specified");
    }
    if(not -e $Descriptor{1}{"Path"}) {
        exitStatus("Access_Error", "can't access \'".$Descriptor{1}."\'");
    }
    if(not $Descriptor{2}{"Path"}) {
        exitStatus("Error", "-new option is not specified");
    }
    if(not -e $Descriptor{2}{"Path"}) {
        exitStatus("Access_Error", "can't access \'".$Descriptor{2}."\'");
    }
    
    printMsg("INFO", "reading packages ...");
    
    if(-d $Descriptor{1}{"Path"})
    {
        $Descriptor{1}{"Distr"} = get_filename($Descriptor{1}{"Path"});
        registerDir($Descriptor{1}{"Path"}, 1);
    }
    else
    {
        if($Descriptor{1}{"Path"}=~/\.(\w+)\Z/)
        {
            if($1!~/\A(xml|desc)\Z/) {
                exitStatus("Error", "unknown format \"$1\"");
            }
        }
        readDescriptor($Descriptor{1}{"Path"}, 1);
    }
    
    if(-d $Descriptor{2}{"Path"})
    {
        $Descriptor{2}{"Distr"} = get_filename($Descriptor{2}{"Path"});
        registerDir($Descriptor{2}{"Path"}, 2);
    }
    else
    {
        if($Descriptor{2}{"Path"}=~/\.(\w+)\Z/)
        {
            if($1!~/\A(xml|desc)\Z/) {
                exitStatus("Error", "unknown format \"$1\"");
            }
        }
        readDescriptor($Descriptor{2}{"Path"}, 2);
    }
    
    if($OutputReportPath)
    { # user-defined path
        $REPORT_PATH = $OutputReportPath;
        $REPORT_DIR = get_dirname($REPORT_PATH);
        if(not $REPORT_DIR) {
            $REPORT_DIR = ".";
        }
    }
    else
    {
        $REPORT_DIR = "distdiff_reports/".$Descriptor{1}{"Distr"}."_to_".$Descriptor{2}{"Distr"};
        $REPORT_PATH = $REPORT_DIR."/changes_report.html";
    }
    
    comparePackages();
    createReport($REPORT_PATH);
    
    exit($ERROR_CODE{"Success"});
}

scenario();
