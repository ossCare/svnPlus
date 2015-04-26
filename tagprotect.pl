#! /usr/bin/perl -w
################################################################################
#  Author:      Joseph C. Pietras - Joseph.Pietras@gmail.com
#  License:     GNU GENERAL PUBLIC LICENSE Version 2
#  GitHub:      https://github.com/ossCare/svnPlus.git
#  SourceForge: TBD
################################################################################
my $VERSION_FILE = 'tagprotect.version.txt';

# IF YOU RUN WITHOUT A CONFIGUATION FILE all COMMITS ARE ALLOWED ALL
# TAG PROTECTION IS DISABLED.  IF THIS VARIABLE IS SET TO 0, THEN THE
# PROGRAM WILL NOT RUN WITHOUT A CONFIGURATION FILE.  YOU CAN export
# A DEFAULT CONFIGURATION FILE WITH THE --generate OPTION.
my $ALLOW_NO_CONFIG_FILE = 0;

################################################################################
#### The script parses both the command line and the configuration file     ####
#### (or if no configuration file is found it uses all default values).     ####
####                                                                        ####
#### The data gotten from the command line (in production this is the path  ####
#### to the repository and transaction ID) is put into a hash along with    ####
#### other data values.  These other data values either default or are      ####
#### parsed from the configuration file.  Despite this they are kept in the ####
#### "CLI" hash and not the configuration CFG hash of hashes.  The hash of  ####
#### hashes contains only data regarding which subversion "root" folders    ####
#### are protected tag folders and the associated configuration for that    ####
#### "tag" folder.                                                          ####
################################################################################
# this file does not, normally, exit ever, unless:
# FATAL ERROR
my $exitFatalErr = 1; # when

# USER ASKED FOR HELP, PARSE, etc, from command line
my $exitUserHelp = 0; # when

################################################################################
# ENTER: INITIALIZE
use warnings;
use strict;
use autodie; # automatic die called if file fails to open

# this is for subversion, if you can't get this is installed
# you must convert to using perl system() calls instead
use Sysadm::Install qw(tap);
use Text::Glob qw( match_glob glob_to_regex glob_to_regex_string);
use POSIX qw(strftime);
#use Time::Format qw(time_format time_strftime time_manip);
# The following might be easier but ...
# use SVN::SVNLook; # not there for CentOS6
# LEAVE: INITIALIZE
################################################################################

################################################################################
# ENTER: HARD DEFAULTS FOR CONFIG FILE, VARIABLES SET IN THE CONFIG FILE, etc.
# hard default                        actual variable      variable looked for
# if not in config                  init w/useless value   in configuration file
# CLI



#  --debug/-d/--debug=/-dN
my $VAR_H_DEBUG = "DEBUG";              # looked for in config file
my $DEF_H_DEBUG =  0;
my     $HDBGKEY = 'h_debug';            # CLI key, debug level

#  not setable on the command line
my $VAR_SVNLOOK = "SVNLOOK";            # variable looked for in config file
my $DEF_SVNLOOK = "/usr/bin/svnlook";   # default value if not in config;
my     $LOOKKEY = 'svnlook';            # CLI key, path to svnlook program

#  not setable on the command line
my $VAR_SVNPATH = "SVNPATH";            # variable looked for in config file
my $DEF_SVNPATH = "/usr/bin/svn";       # default value if not in config
my     $PATHKEY = 'svnpath';            # CLI key, path to svn program

#  --build/-b
my     $BCFGKEY = 'buildpl';            # CLI key, output PERL pre-build config from config file
#  not setable on the command line
my     $CLIDKEY = 'cli_dbg';            # CLI key, was debug gotten from command line
#  --parse=<file>/-p<file> changes this
my     $CONFKEY = 'configf';            # CLI key, name of config file, can change when debugging
#  --revert/-r
my     $DUMPKEY = 'dump_pl';            # CLI key, reverse the above, PERL prebuild to config file
#  --parse/-p
my     $PARSKEY = 'justcfg';            # CLI key, just parse the config and exit
#  not setable on the command line, it it exists it is read in
my     $PREFKEY = 'preconf';            # CLI key, name of precompiled config file
#  not setable on the command line, this is auto detected
my     $RCLIKEY = 'cli_run';            # CLI key, running from command line
#  set by subversion when in PRODUCTION
my     $SVNIDEN = 'svn_tID';            # CLI key, subversion transaction key
#  set by subversion when in PRODUCTION
my     $SVNREPO = 'svnRepo';            # CLI key, path to svn repository

# CFG
my $VAR_TAGFOLD = "PROTECTED_PARENT";   # variable looked for in config file
my $DEF_TAGFOLD = "/tags";              # default value if not in config
my     $TAGpKEY = "$VAR_TAGFOLD";       # CFG key, key for this N-Tuple, must be a real path

# these        (missing 3 lines)
#       not
#           needed for line no
my     $LINEKEY = "ProtectLineNo";      # CFG key, line number in the config file of this tag folder

my $VAR_SUBFOLD = "PROTECTED_PRJDIRS";  # variable looked for in config file
my $DEF_SUBFOLD = "${DEF_TAGFOLD}/*";   # default value if not in config
my     $SUBfKEY = "$VAR_SUBFOLD";       # CFG key, subfolders will be "globbed"

my $VAR_MAKESUB = "PRJDIR_CREATORS";    # variable looked for in config file
my $DEF_MAKESUB =  "*";                 # default value if not in config
my     $MAKEKEY = "$VAR_MAKESUB";       # CFG key, those who can create sub folders

my $VAR_NAME_AF = "ARCHIVE_DIRECTORY";  # variable looked for in config file
my $DEF_NAME_AF =  "Archive";           # default value if not in config
my     $NAMEKEY = "$VAR_NAME_AF";       # CFG key, directory name of the archive folder(s)
# LEAVE: HARD DEFAULTS FOR CONFIG FILE, VARIABLES SET IN THE CONFIG FILE, etc
################################################################################

################################################################################
my $TCNT = 0;               # count of N-Tuple keys
my $TSTR = "Config_Tuple";  # string part of a N-Tuple key
################################################################################

################################################################################
################################################################################
############################# SUPPORT SUBROUTINES ##############################
################################################################################
###############################################################################{

sub AddingArchiveFolder
{
    my $parent   = shift; # this does NOT end with SLASH, protected "parent" folder
    my $allsub   = shift; # this does NOT end with SLASH, subfolders (as a path containing all the "parts" of the path)
    my $archive  = shift; # name of the archive folder(s) for this configuration N-Tuple
    my $artifact = shift; # may or may not end with SLASH - indicates files or folder
    my $dbglvl   = shift; # passed in instead of passing $CLIref
    my $r = 0;            # assume failure
    my $sstr;             # subfolder string - used for parsing $allsub into the @suball array
    my @suball;           # hold the parts of $allsub, $allsub can be a glob
    my $glob;             # build up from the $allsub string split apart into @suball
    my $dir = 0;          # assume artifact is a file
    local $_;

    $_ = $artifact;
    $dir = 1 if ( m@/$@ );

    if ( $dir )
    {
        $sstr = $allsub;           # start with the subfolder config value
        print STDERR "AddingArchiveFolder: \$sstr=$sstr\n" if ( $dbglvl > 5 );
        $sstr =~ s@^${parent}/@@;   # remove the parent and FIRST SLASH
        @suball = split( '/', $sstr);
        # walk the longest path to the shortest path
        while ( @suball > 0 )
        {
            $glob  = $parent . "/" . join("/", @suball);
            $glob .= "/" if ( !( $glob =~ '/$' ) );
            $glob .= $archive . "/";
            if ( match_glob( $glob, $artifact ) )
            {
                print STDERR "AddingArchiveFolder: \$glob=$glob matches $artifact\n" if ( $dbglvl > 4 );
                $r = 1; # we have a match
                last;
            }
            elsif ( $dbglvl > 2)
            {
                print STDERR "AddingArchiveFolder: \$glob=$glob DOES NOT match $artifact\n" if ( $dbglvl > 4 );
            }
            pop @suball;
        }
    }
    elsif ( $dbglvl > 4 )
    {
        print STDERR "AddingArchiveFolder: $artifact is a FILE\n";
    }

    print STDERR "AddingArchiveFolder: RETURNED $r\t\$artifact=$artifact\n" if ( $dbglvl > 3 );
    return $r;
} # AddingArchiveFolder
            
sub AddingTooArchiveFolder
{
    my $parent   = shift; # this does NOT end with SLASH, protected "parent" folder
    my $allsub   = shift; # this does NOT end with SLASH, subfolders (as a path containing all the "parts" of the path)
    my $archive  = shift; # name of the archive folder(s) for this configuration N-Tuple
    my $artifact = shift; # may or may not end with SLASH - indicates files or folder
    my $dbglvl   = shift; # passed in instead of passing $CLIref
    my $r = 0;            # assume failure
    my $sstr;             # subfolder string - used for parsing $allsub into the @suball array
    my @suball;           # hold the parts of $allsub, $allsub can be a glob
    my $glob;             # build up from the $allsub string split apart into @suball
    my $dir = 0;          # assume artifact is a file
    local $_;

    $_ = $artifact;
    $dir = 1 if ( m@/$@ );

    if ( $dir )
    {
        $sstr = $allsub;           # start with the subfolder config value
        print STDERR "AddingTooArchiveFolder: \$sstr=$sstr\n" if ( $dbglvl > 5 );
        $sstr =~ s@^${parent}/@@;   # remove the parent and FIRST SLASH
        @suball = split( '/', $sstr);
        # walk the longest path to the shortest path
        while ( @suball > 0 )
        {
            $glob  = $parent . "/" . join("/", @suball);
            $glob .= "/" if ( !( $glob =~ '/$' ) );
            $glob .= $archive . "/?*/";
            if ( match_glob( $glob, $artifact ) )
            {
                print STDERR "AddingTooArchiveFolder: \$glob=$glob matches $artifact\n" if ( $dbglvl > 4 );
                $r = 1; # we have a match
                last;
            }
            elsif ( $dbglvl > 2)
            {
                print STDERR "AddingTooArchiveFolder: \$glob=$glob DOES NOT match $artifact\n" if ( $dbglvl > 4 );
            }
            pop @suball;
        }
    }
    elsif ( $dbglvl > 4 )
    {
        print STDERR "AddingTooArchiveFolder: $artifact is a FILE\n";
    }

    print STDERR "AddingTooArchiveFolder: RETURNED $r\t\$artifact=$artifact\n" if ( $dbglvl > 3 );
    return $r;
} # AddingTooArchiveFolder

sub AddingSubFolder
{
    my $parent   = shift; # this does NOT end with SLASH, protected "parent" folder
    my $allsub   = shift; # this does NOT end with SLASH, subfolders (as a path containing all the "parts" of the path)
    my $artifact = shift; # may or may not end with SLASH - indicates files or folder
    my $dbglvl   = shift; # passed in instead of passing $CLIref
    my $r = 0;            # assume failure
    my $sstr;             # subfolder string - used for parsing $allsub into the @suball array
    my @suball;           # hold the parts of $allsub, $allsub can be a glob
    my $glob;             # build up from the $allsub string split apart into @suball
    my $dir = 0;          # assume artifact is a file
    local $_;

    $_ = $artifact;
    $dir = 1 if ( m@/$@ );

    if ( $dir )
    {
        $sstr = $allsub;           # start with the subfolder config value
        print STDERR "AddingSubFolder: \$sstr=$sstr\n" if ( $dbglvl > 5 );
        $sstr =~ s@^${parent}/@@;   # remove the parent and FIRST SLASH
        @suball = split( '/', $sstr);
        # walk the longest path to the shortest path
        while ( @suball > 0 )
        {
            $glob  = $parent . "/" . join("/", @suball);
            $glob .= "/" if ( !( $glob =~ '/$' ) );
            if ( match_glob( $glob, $artifact ) )
            {
                print STDERR "AddingSubFolder: \$glob=$glob matches $artifact\n" if ( $dbglvl > 4 );
                $r = 1; # we have a match
                last;
            }
            elsif ( $dbglvl > 2)
            {
                print STDERR "AddingSubFolder: \$glob=$glob DOES NOT match $artifact\n" if ( $dbglvl > 4 );
            }
            pop @suball;
        }
    }
    elsif ( $dbglvl > 4 )
    {
        print STDERR "AddingSubFolder: $artifact is a FILE\n";
    }

    print STDERR "AddingSubFolder: RETURNED $r\t\$artifact=$artifact\n" if ( $dbglvl > 3 );
    return $r;
} # AddingSubFolder

#### FROM: http://svnbook.red-bean.com/nightly/en/svn.ref.svnlook.c.changed.html
####
####   Name
####
####    svnlook changed — Print the paths that were changed.
####
####   Synopsis
####
####    svnlook changed REPOS_PATH
####
####   Description
####
####    Print the paths that were changed in a particular revision or transaction, as well as “svn update-style” status letters in the first two columns:
####
####    'A ' Item added to repository
####
####    'D ' Item deleted from repository
####
####    'U ' File contents changed
####
####    '_U' Properties of item changed; note the leading underscore
####
####    'UU' File contents and properties changed
####
####    Files and directories can be distinguished, as directory paths are displayed with a trailing “/” character.

sub AllowCommit
{
    my $Pname  = shift;   # name of calling program
    my $CLIref = shift;   # reference to command line hash
    my $CFGref = shift;   # reference to configuration hash
    my $CMdata = shift;   # reference to committed files/folders data array
    my $author = shift;   # committer of this change
    my $artifact;         # the thing being commmitted
    my $change;           # a D or an A
    my $check1st;         # to avoid duplicates
    my $commit = 1;       # assume OK to commit
    my $count;            # of array elements
    my $isProt;           # is it protected?
    my $itmp   = -1;      # init to allow for empty CMdata
    my $ok2add;           # push to the add array?
    my $ref;              # to Nth array element
    my $stmp;             # tmp string
    my $tupleKey;         # key into configuration HoH
    my @add    = ();      # things adding
    my @del    = ();      # things deleting
    my @tmp;              # used to push an array into @add or @del

    while( $itmp < $#$CMdata )
    {
        # get the next array element, $CMdata->[$itmp],
        # use a regexp "split" into 3 parts, the middle part is thrown away (it is just 2 spaces)
        # 1st part is 2 chars loaded to $change
        # 2nd part is 2 spaces, ignored
        # 3rd part is the $artifact
        ($change, $artifact) = $CMdata->[$itmp] =~ m@^(..)  (.+)@; # two space chars ignored
        $change =~ s@\s@@g; # remove spaces
        if ( $CLIref->{$HDBGKEY} > 3 )
        {
            print STDERR "AllowCommit: >>$CMdata->[$itmp]<<\n" if ( $CLIref->{$HDBGKEY} > 4 );
            print STDERR "AllowCommit: \$change=>>$change<<\n";
            print STDERR 'AllowCommit: $artifact=' . "$artifact\n";
        }

        ($isProt, $tupleKey) = &ArtifactUnderProtectedFolder($CFGref, $artifact, $CLIref->{$HDBGKEY});
        if ( $CLIref->{$HDBGKEY} > 1 )
        {
            print STDERR 'AllowCommit: $tupleKey=' . "$tupleKey\n" if ( $CLIref->{$HDBGKEY} > 2 );
            print STDERR 'AllowCommit: $isProt=' . "$isProt\n";
        }

        if ( $isProt == 1 )
        {
            if ( $change eq 'U' or $change eq '_U' or $change eq 'UU'  )
            {
                print STDERR "$Pname: commit failed, modifications to protected folders or folders is not allowed!\n";
                print STDERR "$Pname: commit failed on: $CMdata->[$itmp]\n";
                $commit = 0;
                last;
            }
            else
            {
                    $ok2add = 1; # assume so
                    if ( $change eq 'D' )
                    {
                        $count = int(@del);
                        if ( $count > 0 )
                        {
                            $ref = $del[$count - 1];
                            ($stmp, $check1st) = @{ $ref };
                            if (length($artifact) >= length($check1st))
                            {
                                $ok2add = 0 if ( $artifact =~ $check1st );
                            }
                        }
                    }
                    elsif ( $change eq 'A' ) # hey that is all it can be
                    {
                        $count = int(@add);
                        if ( $count > 0 )
                        {
                            $ref = $add[$count - 1];
                            ($stmp, $check1st) = @{ $ref };
                            if (length($artifact) >= length($check1st))
                            {
                                $ok2add = 0 if ( $artifact =~ $check1st );
                            }
                        }
                    }
                    else
                    {   # THIS SHOULD NEVER HAPPEN AND IS HERE IN CASE SUBVERSION CHANGES
                        # this is a safety check - just comment it out to keep on trunking
                        print STDERR "$Pname: commit failed, unknown value for \$change=\"$change\"\n";
                        print STDERR "$Pname: commit failed on: $CMdata->[$itmp]\n";
                        $commit = 0;
                        last;
                    }
                    if ( $ok2add )
                    {
                        @tmp = ($tupleKey, $artifact);
                        if ( $change eq 'D' )
                        {
                            print STDERR "AllowCommit: $artifact pushed to 'del'\n" if ( $CLIref->{$HDBGKEY} > 2 );
                            push @del, [ @tmp ];
                        }
                        else
                        {
                            print STDERR "AllowCommit: $artifact pushed to 'add'\n" if ( $CLIref->{$HDBGKEY} > 2 );
                            push @add, [ @tmp ];
                        }
                    }
                    else
                    {
                        print STDERR "AllowCommit: $artifact not needed it is a duplicate\n" if ( $CLIref->{$HDBGKEY} > 3 );
                    }
            }
        }
        $itmp ++;
    }
    if ( $commit == 1 )
    {
        # See if attempting a delete only
        if    ( int(@add) == 0 && int(@del) != 0 )
        {
            print STDERR "AllowCommit: DELETE ONLY\n" if ( $CLIref->{$HDBGKEY} > 1 );
            $commit = &SayNoDelete($Pname, $CMdata->[$itmp]); # always returns 0
        }

        # See if attempting an add only
        elsif ( int(@add) != 0 && int(@del) == 0 )
        {
            print STDERR "AllowCommit: ADD ONLY\n" if ( $CLIref->{$HDBGKEY} > 1 );
            $commit = &TheAddIsAllowed($Pname, $CLIref, $CFGref, $author, \@add); # returns 0 or 1
        }

        # See if attempting an add and a delete, only do this if moving a tag to an archive folder
        elsif ( int(@add) != 0 && int(@del) != 0 )
        {
            print STDERR "AllowCommit: ADD AND DELETE\n" if ( $CLIref->{$HDBGKEY} > 1 );
            $commit = &TheMoveIsAllowed($Pname, $CLIref, $CFGref, $CMdata, $author, \@add, \@del); # returns 0 or 1
        }

        # Not attempting anything! What? That's impossible, something is wrong.
        elsif ( int(@add) == 0 && int(@del) == 0 )
        {
            print STDERR "AllowCommit: IMPOSSIPLE\n" if ( $CLIref->{$HDBGKEY} > 1 );
            $commit = &SayImpossible($Pname); # always returns 0
        }
    }
    return $commit;
} # AllowCommit

# each artifact has to be tested to see if it is under protection
# which means looping through all configurations
sub ArtifactUnderProtectedFolder
{
    my $CFGref   = shift;
    my $artifact = shift;
    my $dbglvl   = shift; # passed in instead of passing $CLIref
    my $parent;           # protected folder
    my $tupleKey;
    my $returnKey = "";
    my $isProtected = 0; # assume not protected

    for $tupleKey ( keys %{ $CFGref } )
    {
        $parent = $CFGref->{$tupleKey}{$TAGpKEY};
        if ( &IsUnderProtectection($parent, $artifact, $dbglvl) == 1 )
        {
            $returnKey = $tupleKey;
            $isProtected = 1;
            last;
        }
    }
    return ($isProtected, $returnKey);
} # ArtifactUnderProtectedFolder

sub Authorized
{
    my $name     = shift;   # name of calling program
    my $author   = shift;   # committer of this change
    my $authOK   = shift;   # those allowed to commit
    my $artifact = shift;   # what is requires authorization
    my $adding   = shift;   # what is being added
    my $dbglvl   = shift;   # passed in instead of passing $CLIref
    my $isauth   = 0;       # assume failure
    my @auth;
    my $user;

    if ( $authOK eq '*')
    {
        print STDERR "Authorized: allow because authorization is the '*' character\n" if ( $dbglvl > 3 );
        $isauth = 1;
    }
    elsif ( $author eq '' )
    {
        print STDERR "$name: commit failed due to being unable to authenticate.\n";
        print STDERR "$name: the author of this commit is BLANK, apparently there is\n";
        print STDERR "$name: no authentication required by subversion (apache or html server).\n";
        print STDERR "$name: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }
    else
    {
        @auth = split( ",", $authOK);
        for $user ( @auth )
        {
            $user =~ s@\s+@@g; # remove all spaces, user names can not have spaces in them
            if ( $user eq $author )
            {
                print STDERR "Authorized: allow because author matches: $user\n" if ( $dbglvl > 3 );
                $isauth = 1;
                last;
            }
            elsif ( $user eq '*' )
            {
                print STDERR "Authorized: allow because one of users is the '*' character\n" if ( $dbglvl > 3 );
                $isauth = 1;
                last;
            }
        }
    }
    if ( $isauth == 0 )
    {
        print STDERR "$name: failed on: $artifact\n";
        print STDERR "$name: authorization failed, you cannot \"$adding\"\n";
        print STDERR "$name: commiter \"$author\" does not have authorization\n";
    }
    return $isauth;
} # Authorized

sub DebugLevel
{
    my $CLIref = shift;  # reference to command line arguments hash
    my $level = $CLIref->{$HDBGKEY};
    return $level;
} # DebugLevel

sub FixPath # trim trailing / chars as need be from the config file
{
    local $_ = shift; # path to be "fixed"
    if ( $_ ne "" and $_ ne "/" )
    {

        #$_ =~
        s/\/+$//; # strip any trailing "/" chars
        $_ = "/" if ( $_ eq "" );
    }
    return $_;
} # FixPath

sub FmtStr # create a format string used when generating a config file
{
    my $l = 0;
    my $r = 0;
    my $f = "";
    $l = length($VAR_H_DEBUG); $r = $l if ( $l > $r);
    $l = length($VAR_SVNLOOK); $r = $l if ( $l > $r);
    $l = length($VAR_SVNPATH); $r = $l if ( $l > $r);
    $l = length($VAR_TAGFOLD); $r = $l if ( $l > $r);
    $l = length($VAR_SUBFOLD); $r = $l if ( $l > $r);
    $l = length($VAR_MAKESUB); $r = $l if ( $l > $r);
    $l = length($VAR_NAME_AF); $r = $l if ( $l > $r);
    $f = '%-' . $r . "s";
    return $f;
} # FmtStr

sub GenTupleKey
{
    my $keyStr = shift;
    my $keyCnt = shift;
    my $key;
    $key = $keyStr . sprintf("_%03d", $keyCnt); # build the key for the outer hash
    return $key;
} # GenTupleKey

sub GetSvnAuthor
{
    my $Pname  = shift; # name of calling program
    my $CLIref = shift; # reference to command line arguments hash
    my @tapCmd;         # array to hold output
    my $svnErrors;      # STDERR of command SVNLOOK - any errors
    my $svnAuthor;      # STDOUT of command SVNLOOK - creator
    my $svnExit;        # exit value of command SVNLOOK
    my $what = "author";

    @tapCmd = (
        $CLIref->{$LOOKKEY},
        "--transaction",
        $CLIref->{$SVNIDEN},
        $what,
        $CLIref->{$SVNREPO},
      );
    print STDERR          'GetSvnAuthor: tap' . " " . join(" ", @tapCmd) . "\n" if ( $CLIref->{$HDBGKEY} > 4 );
    ($svnAuthor, $svnErrors, $svnExit) = tap                    @tapCmd;
    chop($svnAuthor);
    if ( $CLIref->{$HDBGKEY} > 4 )
    {
        if ( $CLIref->{$HDBGKEY} > 4 )
        {
            print STDERR "GetSvnAuthor: \$svnExit=  >>$svnExit<<\n";
            print STDERR "GetSvnAuthor: \$svnErrors=>>$svnErrors<<\n";
        }
        print STDERR "GetSvnAuthor: \$svnAuthor=>>$svnAuthor<<\n";
    }
    if ( $svnExit )
    {
        print STDERR "$Pname: \"$CLIref->{$LOOKKEY}\" failed to get \"$what\" (exit=$svnExit), re: $svnErrors\n";
        print STDERR "$Pname: command: >>tap " . join(" ", @tapCmd) . "\n";
        print STDERR "$Pname: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }
    print STDERR "GetSvnAuthor: return \"$svnAuthor\"\n" if ( $CLIref->{$HDBGKEY} > 3 );
    return $svnAuthor;
} # GetSvnAuthor

sub GetSvnCommit
{
    my $Pname  = shift; # name of calling program
    my $CLIref = shift; # reference to command line arguments hash
    my @tapCmd;         # array to hold output
    my $svnErrors;      # STDERR of command SVNLOOK - any errors
    my $svnChanged;     # STDOUT of command SVNLOOK - commit data
    my $svnExit;        # exit value of command SVNLOOK
    my @Changed;        # $svnChanged split into an array of files/folders
    my $itmp = 0;       # index into @Changed
    local $_;           # regex'ing
    my $what = "changed";

    @tapCmd = (
        $CLIref->{$LOOKKEY},
        "--transaction",
        $CLIref->{$SVNIDEN},
        $what,
        $CLIref->{$SVNREPO},
      );
    print STDERR           'GetSvnCommit: tap' . " " . join(" ", @tapCmd) . "\n" if ( $CLIref->{$HDBGKEY} > 4 );
    ($svnChanged, $svnErrors, $svnExit) = tap                    @tapCmd;
    if ( $CLIref->{$HDBGKEY} > 4 ) # "2", not "0" because the array is printed below
    {
        print STDERR "GetSvnCommit: \$svnExit=  >>$svnExit<<\n";
        print STDERR "GetSvnCommit: \$svnErrors=>>$svnErrors<<\n";
        print STDERR "GetSvnCommit: \$svnChanged=>>$svnChanged<<\n";
    }
    if ( $svnExit )
    {
        print STDERR "$Pname: \"$CLIref->{$LOOKKEY}\" failed to get \"$what\" (exit=$svnExit), re: $svnErrors\n";
        print STDERR "$Pname: command: >>tap " . join(" ", @tapCmd) . "\n";
        print STDERR "$Pname: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }
    @Changed = split("\n", $svnChanged);

    # now put insert a "/" character as the 5th character on each of the array
    # elements.  svnlook does not do that and it is needed for subsequent
    # regexp matches.
    print STDERR "GetSvnCommit: ENTER: list of $what folders and files\n" if ( $CLIref->{$HDBGKEY} > 3 );
    while ( $itmp < int(@Changed) )
    {
        print STDERR "GetSvnCommit: BEFORE $Changed[$itmp]\n" if ( $CLIref->{$HDBGKEY} > 4 );
        $_ = $Changed[$itmp];

        # push a "/" infront of the path if it not there, it can be there if "/" properties are being changed
        s@^(....)@$1/@ if ( ! m,^..../, );
        $Changed[$itmp] = $_;
        print STDERR "GetSvnCommit: AFTER  $Changed[$itmp]\n" if ( $CLIref->{$HDBGKEY} > 3 );
        $itmp ++;
    }
    print STDERR "GetSvnCommit: LEAVE: list of $what folders and files\n" if ( $CLIref->{$HDBGKEY} > 3 );
    return @Changed; # $svnChanged split into an array of files/folders
} # GetSvnCommit

sub GetVersion
{
    my $ver = shift;
    my $back = "";
    local $_;

    open my $vHandle, "<", $VERSION_FILE;
    while (<$vHandle>)
    {
       chop();
       last;
    }
    close($vHandle);
    $back  = 'Version ' if ( $ver );
    $back .= $_;
    return $back;
} # GetVersion

sub IsUnderProtectection
{
    my $pfolder  = shift; # protected (parent) folder
    my $artifact = shift; # to be added
    my $dbglvl   = shift; # passed in instead of passing $CLIref
    my $leftside;         # left side of $artifact, length of $pfolder
    my $r;                # returned value
    local $_;

    if ( $pfolder eq "/" )
    {
        # THIS IS CODED THIS WAY IN CASE "/" IS DISALLOWED IN FUTURE (perhaps it should be?)
        $r  = 1;   # this will always match everything!
        print STDERR "IsUnderProtection: protected folder is \"/\" it always matches everyting\n" if ( $dbglvl > 5 );
    }
    else
    {
        # the protected (parent) folder is given literally like: "/tags"
        # but can contain who knows what (even meta chars to be taken as is)
        $_ = int(length($pfolder));
        $leftside = substr($artifact, 0, $_);
        if ( $dbglvl > 5 )
        {
            print STDERR 'IsUnderProtection: $artifact:  ' . $artifact . ")\n" if ( $dbglvl > 6 );
            print STDERR 'IsUnderProtection: checking regexp match (' . $leftside . ' eq ' . $pfolder . ")\t";
        }
        if ( $leftside eq $pfolder )
        {
            print STDERR "MATCH\n" if ( $dbglvl > 5 );
            $r = 1;
        }
        else
        {
            print STDERR "miss\n" if ( $dbglvl > 5 );
            $r = 0;
        }
    }
    print STDERR "IsUnderProtection: RETURNED $r\n" if ( $dbglvl > 4 );
    return $r;
} # IsUnderProtectection

sub JustCFGParse
{
    my $CLIref = shift;  # reference to command line arguments hash
    my $justParse = $CLIref->{$PARSKEY};
    return $justParse;
} # JustCFGParse

sub LoadCFGTuple # put an N-Tuple into the Hash of hashes
{
    my $progName    = shift;
    my $cfg_File    = shift;

    # this is what this subroutine "loads", i.e. the 1st is given and
    # we default the next 3 from the 3 above if they are not there
    my $inHashRef   = shift; # a reference to the "inner" hash
    my $folderKey = shift; # key into above hash to see if we got it or must default
    my $linenoKey = shift; # key into above hash to see if we got it or must default
    my $subdirKey = shift; # key into above hash to see if we got it or must default
    my $creatsKey = shift; # key into above hash to see if we got it or must default
    my $archnmKey = shift; # key into above hash to see if we got it or must default

    # the outer most hash that we will load the above hash into, along with the information
    # needed to construt the key needed to push the above hash into this hash.  Got that?
    my $ouHashRef   = shift; # a reference to the "outer" hash this one will get the above one
    my $keyStr    = shift; # the string part of the key into the outer hash (key will be constructed)
    my $keyCnt    = shift; # the integer part of the key into the outer hash (key will be constructed)
    my $dbglvl    = shift;

    my $key;                 # used to build the key from the string and the number

    # check that incoming (inner) hash has a folder in it to be protected
    if (    ( ! exists $inHashRef->{$archnmKey} )
        ||  ( ! exists $inHashRef->{$creatsKey} )
        ||  ( ! exists $inHashRef->{$folderKey} )
        ||  ( ! exists $inHashRef->{$linenoKey} )
        ||  ( ! exists $inHashRef->{$subdirKey} ) )
    {

        # give it bogus value if it has no value
        $inHashRef->{$linenoKey}  = 0 if ( ! exists $inHashRef->{$linenoKey} );

        print STDERR "$progName: See configuration file: $cfg_File\n";
        print STDERR "$progName: The value of $VAR_TAGFOLD does not exist for the configuration set.\n"
          if ( ! exists $inHashRef->{$folderKey} );
        print STDERR "$progName: The value of $VAR_SUBFOLD does not exist for the configuration set!\n"
          if ( ! exists $inHashRef->{$subdirKey} );
        print STDERR "$progName: The value of $VAR_NAME_AF does not exist for the configuration set!\n"
          if ( ! exists $inHashRef->{$archnmKey} );
        print STDERR "$progName: The value of $VAR_MAKESUB does not exist for the configuration set!\n"
          if ( ! exists $inHashRef->{$creatsKey} );
        print STDERR "$progName: Around line number: $inHashRef->{$linenoKey}\n";
        print STDERR "$progName: Failure in subroutine LoadCFGTuple.\n";
        print STDERR "$progName: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }
    elsif ( $inHashRef->{$folderKey} eq "" )
    {

        # give it bogus value if it has no value
        $inHashRef->{$linenoKey}  = 0 if ( ! exists $inHashRef->{$linenoKey} );
        print STDERR "$progName: See configuration file: $cfg_File\n";
        print STDERR "$progName: The value of $VAR_TAGFOLD is blank.\n";
        print STDERR "$progName: Around line number: $inHashRef->{$linenoKey}\n";
        print STDERR "$progName: Failure in subroutine LoadCFGTuple.\n";
        print STDERR "$progName: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }

    # get new key for outer hash
    $key =  &GenTupleKey($keyStr, $keyCnt);
    $ouHashRef->{ $key } =  { %$inHashRef }; # this allocates (copies) inner hash

    # the validator will return the input if it is ok, else it will silently clean it up
    $inHashRef->{$subdirKey} = &ValidateSubFolderOrDie($progName, $inHashRef->{$folderKey},
                                                       $inHashRef->{$subdirKey},
                                                       $cfg_File,
                                                       $inHashRef->{$linenoKey},
                                                       $folderKey, $subdirKey, $dbglvl);
    $keyCnt++;
    return $keyCnt; # return one more than input
} # put an N-Tuple into the Hash of hashes

sub ParseCFG # ENTER: parse config file
{
    my $Pname   = shift;   # name of calling program
    # this _must_ be "our" (not "my") because of reading from pre-compiled file
    our $CLIref = shift;   # reference to command line arguments hash
    my $var     = "";
    my $val     = "";
    my $ch_1st  = "";
    my $chLast  = "";
    my $errors  =  0;
    my $unknown =  0;
    my $itmp    =  0;
    my %cfg     = ();     # "one config" for a protected folder
    # this _must_ be "our" (not "my") because of reading from pre-compiled file
    our %HoH    = ();     # hash of hashes - holds all configs
    my $cfgh;             # open config handle
    my $tKey;             # N-Tuple key
    my $cKey;             # configuration key
    my $spch;             # string of space characters
    my $readPreComp = 0;  # read the precompiled config file

    my $dbgInc = 5;       # set the default high so this function does not output unless in command line mode
    $dbgInc = 0 if ( $CLIref->{$RCLIKEY} || $CLIref->{$PARSKEY} || $CLIref->{$BCFGKEY} || $CLIref->{$DUMPKEY} );

    # do not read the pre-compiled file if we have to build it
    # and do not read the pre-compiled file it we have been asked to parse the configuation file
    if ( $CLIref->{$BCFGKEY} == 0 && $CLIref->{$PARSKEY} == 0 )
    {
        $readPreComp = 1 if ( -f $CLIref->{$PREFKEY} ); # if the precompiled file exists it will be read in
    }

    if ( $readPreComp ) # if precompiled file, and not command line options to the contrary, just require it and done!
    {
        my $dbgBefore = $CLIref->{$HDBGKEY};
        print STDERR "ParseCFG: read precompiled configuration file \"$CLIref->{$PREFKEY}\"\n" if ( $CLIref->{$HDBGKEY} > ($dbgInc + 0) );
        require "$CLIref->{$PREFKEY}";
        # if the command line set the debug higher than what it now is set back to the command line value
        $CLIref->{$HDBGKEY} = $dbgBefore if ($CLIref->{$HDBGKEY} < $dbgBefore);
    }
    # read the regular config file
    else
    {
        if ( ! -f $CLIref->{$CONFKEY} )
        {
            print STDERR "ParseCFG: No configuration file \"$CLIref->{$CONFKEY}\"\n" if ( $CLIref->{$HDBGKEY} > ($dbgInc + 0) );
            if ($ALLOW_NO_CONFIG_FILE == 1)
            {
                print STDERR "ParseCFG: NO CONFIG FILE -- ALL COMMITS ALLOWED\n" if ( $CLIref->{$HDBGKEY} > ($dbgInc + 0) );
            }
            else
            {
                print STDERR "$Pname: configuration file \"$CLIref->{$CONFKEY}\" does not exist, aborting.\n";
                print STDERR "$Pname: tell the subversion administrator.\n";
                exit $exitFatalErr;
            }
        }
        else
        {
            print STDERR "ParseCFG: read open $CLIref->{$CONFKEY}\n" if ( $CLIref->{$HDBGKEY} > ($dbgInc + 0) );
            open $cfgh, "<", $CLIref->{$CONFKEY};
            while (<$cfgh>)
            {
                ###############################################
                # ENTER: fix and split up the line just read in
                chop;
                s/#.*//;  # remove comments
                s/\s*$//; # remove trailing white space
                next if $_ eq "";
                print STDERR "ParseCFG: RAW: $_\n" if ( $CLIref->{$HDBGKEY} > ($dbgInc + 4) );

                if ( ! m/=/ )
                {
                    print STDERR "$Pname: configuration file \"$CLIref->{$CONFKEY}\" is misconfigured.\n" if ( $errors == 0 );
                    print STDERR "$Pname: line $. >>$_<< is not a comment and does not contain an equal sign(=) character!\n";
                    $errors ++;
                    next;
                }
                $var =  $_;                                     # init to input
                $var =~ s/^\s*//;                               # remove initial white space
                $var =~ s/^([A-Za-z0-9_]+)\s*=.*/$1/;           # remove optional white space and equal sign
                $val =  $_;                                     # init to input
                $val =~ s/\s*$var\s*=\s*//;                     # remove VAR= with optional white space
                $val =~ s/\s*;\s*//;                            # remove trailing ';' and white space, if any
                $ch_1st = $val; $ch_1st =~ s/^(.)(.*)(.)\Z/$1/; # first char
                $chLast = $val; $chLast =~ s/^(.)(.*)(.)\Z/$3/; # last char
                if ( $CLIref->{$HDBGKEY} > ($dbgInc + 4) )
                {
                    print STDERR "ParseCFG: \$var=\"$var\"\n";
                    print STDERR "ParseCFG: \$val=\"$val\"\n";
                    print STDERR "ParseCFG: \$ch_1st=\"$ch_1st\"\n";
                    print STDERR "ParseCFG: \$chLast=\"$chLast\"\n";
                }
                if    ( $ch_1st eq $chLast and $ch_1st eq '"' )
                {   # extact dq string
                    $val =~ s/^(.)(.*)(.)\Z/$2/;
                }
                elsif ( $ch_1st eq $chLast and $ch_1st eq "'" )
                {   # extact sq string
                    $val =~ s/^(.)(.*)(.)\Z/$2/;
                }
                elsif ($ch_1st eq '"' or $ch_1st eq "'" )
                {
                    print STDERR "$Pname: configuration file \"$CLIref->{$CONFKEY}\" is misconfigured.\n" if ( $errors == 0 );
                    print STDERR "$Pname: line $. >>$_<< badly quoted!\n";
                    $errors ++;
                    next;
                }
                #else                                  { $val is good as it is }

                if ( $CLIref->{$HDBGKEY} > ($dbgInc + 3) )
                {
                    print STDERR 'ParseCFG: $var="' . "$var" . '"' . "\n";
                    print STDERR 'ParseCFG: $val="' . "$val" . '"' . "\n";
                }
                # LEAVE: fix and split up the line just read in
                ###############################################

                ############################################################
                # ENTER: find the variable and store the value for "GLOBALS"
                if    ( $var =~ m/^${VAR_H_DEBUG}\Z/i       )
                {
                    if ( $CLIref->{$CLIDKEY} == 0 )
                    {
                        $itmp = &ZeroOneOrN($val);
                        $CLIref->{$HDBGKEY} = $itmp if ( $itmp > $CLIref->{$HDBGKEY} );
                    }
                }
                elsif ( $var =~ m/^${VAR_SVNPATH}\Z/i       )
                {
                    $ch_1st = $val; $ch_1st =~ s/(.)(.+)/$1/; # first char
                    if ( $ch_1st ne "/" )
                    {
                        print STDERR "$Pname: configuration file \"$CLIref->{$CONFKEY}\" is misconfigured.\n" if ( $errors == 0 );
                        print STDERR "$Pname: line $. >>$_<< svn path does not start with slash(/)!\n";
                        $errors ++;
                        next;
                    }
                    $CLIref->{$PATHKEY}=$val;
                    print STDERR 'ParseCFG: $CLIref->{' . "$PATHKEY" . '} = "' . $CLIref->{$PATHKEY} . '"' . "\n" if ( $CLIref->{$HDBGKEY} > ($dbgInc + 2) );
                }
                elsif ( $var =~ m/^${VAR_SVNLOOK}\Z/i       )
                {
                    $ch_1st = $val; $ch_1st =~ s/(.)(.+)/$1/; # first char
                    if ( $ch_1st ne "/" )
                    {
                        print STDERR "$Pname: configuration file \"$CLIref->{$CONFKEY}\" is misconfigured.\n" if ( $errors == 0 );
                        print STDERR "$Pname: line $. >>$_<< svnlook path does not start with slash(/)!\n";
                        $errors ++;
                        next;
                    }
                    $CLIref->{$LOOKKEY}=$val;
                    print STDERR 'ParseCFG: $CLIref->{' . "$LOOKKEY" . '} = "' . $CLIref->{$LOOKKEY} . '"' . "\n" if ( $CLIref->{$HDBGKEY} > ($dbgInc + 2) );
                }
                # LEAVE: find the variable and store the value for "GLOBALS"
                ############################################################

                ###########################################################
                # ENTER: find the variable and store the value for "N-Tuple"
                # can be given in _any_ order
                # 1) tag folder - cannot be BLANK
                # 2) subfolder - can be BLANK means NOT ALLOWED
                # 3) subfolder creators - can be BLANK means NO ONE
                # 4) archive name - can be BLANK means NOT ALLOWED

                # 1)
                elsif ( $var =~ m/^${VAR_TAGFOLD}\Z/i )
                {

                    # before processing this "$var" (a "protected tag folder" from the config file)
                    # if there is a "protected tag folder" outstanding, load it and its corresponding
                    # configuration values
                    if ( keys %cfg )
                    {
                        $cfg{$LINEKEY} = $. if ( ! exists $cfg{$LINEKEY} );

                        # we need to load this protected folder and all the
                        # members of the "tuple" into the configuration hash
                        print STDERR "ParseCFG: $TAGpKEY = $cfg{$TAGpKEY}    in the while loop\n" if ( $CLIref->{$HDBGKEY} > ($dbgInc + 1) );
                        $TCNT = &LoadCFGTuple($Pname, $CLIref->{$CONFKEY},
                            \%cfg, $TAGpKEY, $LINEKEY, $SUBfKEY, $MAKEKEY, $NAMEKEY,
                            \%HoH, $TSTR, $TCNT, $CLIref->{$HDBGKEY});
                        %cfg = (); # clear it to hold next parse
                    }

                    # now process the just read in "protected tag folder"
                    $ch_1st = $val; $ch_1st =~ s/(.)(.+)/$1/; # first char
                    if ( $ch_1st ne "/" )
                    {
                        print STDERR "$Pname: configuration file \"$CLIref->{$CONFKEY}\" is misconfigured.\n" if ( $errors == 0 );
                        print STDERR "$Pname: line $. >>$_<< tag folder to protect does not start with slash(/)!\n";
                        $errors ++;
                        next;
                    }
                    $cfg{$TAGpKEY} = &FixPath($val);
                    $cfg{$LINEKEY} = $.; # keep the line this was read in on
                    # safety/security check
                    if ( $cfg{$TAGpKEY}    eq ""  )
                    {
                        print STDERR "$Pname: configuration file \"$CLIref->{$CONFKEY}\" is misconfigured.\n" if ( $errors == 0 );
                        print STDERR "$Pname: line $. >>$_<<";
                        print STDERR " (which becomes \"$cfg{$TAGpKEY}\")" if ( $_ ne $cfg{$TAGpKEY} );
                        print STDERR " cannot be blank!\n";
                        $errors ++;
                        next;
                    }
                }

                # 2)
                elsif ( $var =~ m/^${VAR_SUBFOLD}\Z/i   )
                {
                    $val = &FixPath($val); # can end up being BLANK, that's ok
                    # if $val is BLANK it means the next tags folder to be protected
                    # will have NO subfolders
                    $cfg{$SUBfKEY} = $val;
                    if ( $CLIref->{$HDBGKEY} > ($dbgInc + 2) )
                    {
                        if ( $val eq "" )
                        {
                            print STDERR "ParseCFG: $SUBfKEY = has been cleared, configuation to have no subfolders.\n";
                        }
                        else
                        {
                            print STDERR "ParseCFG: $SUBfKEY = $cfg{$SUBfKEY}\n";
                        }
                    }
                    $cfg{$LINEKEY} = $. if ( ! exists $cfg{$LINEKEY} );
                }

                # 3)
                elsif ( $var =~ m/^${VAR_MAKESUB}\Z/i       )
                {
                    $cfg{$MAKEKEY} = "$val"; # can be BLANK
                    print STDERR "ParseCFG: $MAKEKEY = $cfg{$MAKEKEY}\n" if ( $CLIref->{$HDBGKEY} > ($dbgInc + 2) );
                    $cfg{$LINEKEY} = $. if ( ! exists $cfg{$LINEKEY} );
                }

                # 4)
                elsif ( $var =~ m/^${VAR_NAME_AF}\Z/i       )
                {
                    $val = &FixPath($val); # can end up being BLANK, that's ok
                    $val = $DEF_NAME_AF if  ( $val eq ""    ); # asked for a reset
                    $val = &FixPath($val); # won't be BLANK any longer
                    if ( $val =~ m@/@ )
                    {
                        print STDERR "$Pname: configuration file \"$CLIref->{$CONFKEY}\" is misconfigured.\n" if ( $errors == 0 );
                        print STDERR "$Pname: line $. >>$_<< archive folder name contains a slash(/) character, that is not allowed!\n";
                        $errors ++;
                        next;
                    }
                    $cfg{$NAMEKEY} = $val;
                    print STDERR "ParseCFG: $NAMEKEY = $cfg{$NAMEKEY}\n" if ( $CLIref->{$HDBGKEY} > ($dbgInc + 2) );
                    $cfg{$LINEKEY} = $. if ( ! exists $cfg{$LINEKEY} );
                }

                # the "variable = value" pair is unrecognized
                else
                {

                    # useless to output error message unless debug is enabled, or
                    # we are running from the command line, because otherwise
                    # subversion will just throw them away!
                    if ( $CLIref->{$HDBGKEY} > ($dbgInc + 0) || $CLIref->{$RCLIKEY} > 0 )
                    {
                        if ( $unknown == 0 )
                        {
                            print STDERR "$Pname: useless configuration variables found while parsing\n";
                            print STDERR "$Pname: configuration file: \"$CLIref->{$CONFKEY}\"\n";
                            print STDERR "$Pname: tell the subversion administrator.\n";
                        }
                        print STDERR "$Pname: unrecognized \"variable = value\" on line $.\n";
                        print STDERR "$Pname: variable: \"$var\"\n";
                        print STDERR "$Pname: value:    \"$val\"\n";
                        print STDERR "$Pname: line:     >>$_<<\n";
                        $unknown ++;
                    }
                }
                # LEAVE: find the variable and store the value for "N-Tuple"
                # can be given in _any_ order
                # 1) tag folder - cannot be BLANK
                # 2) subfolder - can be BLANK means NOT ALLOWED
                # 3) subfolder creators - can be BLANK means NO ONE
                # 4) archive name - can be BLANK means NOT ALLOWED
                ############################################################
            }
            if ( $errors > 0 ) { exit $exitFatalErr; }

            # there can be one left in the "cache"
            if ( keys %cfg )
            {
                print STDERR "ParseCFG: $TAGpKEY = $cfg{$TAGpKEY}    AT END OF WHILE LOOP\n" if ( $CLIref->{$HDBGKEY} > ($dbgInc + 1) );
                $TCNT = &LoadCFGTuple($Pname, $CLIref->{$CONFKEY},
                    \%cfg, $TAGpKEY, $LINEKEY, $SUBfKEY, $MAKEKEY, $NAMEKEY,
                    \%HoH, $TSTR, $TCNT, $CLIref->{$HDBGKEY});
            }
            close $cfgh;
        }
        &ValidateCFGorDie($Pname, $CLIref->{$CONFKEY}, $TSTR, $TCNT, \%HoH, $TAGpKEY, $LINEKEY);
    }
    # DUMP (revert) THE PRECOMPILED FILE BACK TO A REGULAR CONFIGURATION FILE
    if ( $CLIref->{$DUMPKEY} > 0 )
    {
        if ( $readPreComp == 0 )
        {
            print STDERR "$Pname: precompiled configuration file is:\n";
            print STDERR "$Pname:     \"$CLIref->{$PREFKEY}\"\n";
            print STDERR "$Pname: precompiled configuration file was not read in.  Unable to\n";
            print STDERR "$Pname: revert the precompiled configuration file to a (regular) configuration file.\n";
            if ( ! -f "$CLIref->{$PREFKEY}" )
            {
                print STDERR "$Pname: it does not exist.\n";
            }
            print STDERR "$Pname: ABORTING!\n";
            exit 1;
        }
        &PrintDefaultConfigAndExit(1, $CLIref->{$HDBGKEY}); # get the header part of the "revert", will not exit!!
        $_ = 0;
        for $tKey ( sort keys %HoH )
        {
            my $q = "'";
            print STDOUT "\n\n" if ( $_ > 0 );
            $_ = 1;
            %cfg = %{ $HoH{$tKey} };
            print STDOUT &PrtStr($VAR_TAGFOLD) . " = ${q}$cfg{$TAGpKEY}${q}\n";
            print STDOUT &PrtStr($VAR_SUBFOLD) . " = ${q}$cfg{$SUBfKEY}${q}\n";
            print STDOUT &PrtStr($VAR_MAKESUB) . " = ${q}$cfg{$MAKEKEY}${q}\n";
            print STDOUT &PrtStr($VAR_NAME_AF) . " = ${q}$cfg{$NAMEKEY}${q}\n";
        }
        exit 0;
    }
    # OUTPUT (build) THE PRECOMPILED CONFIGURATION FILE FROM THE CONFIGURATION FILE JUST READ IN
    elsif ( $CLIref->{$BCFGKEY} > 0 )
    {
        my $Oline  = '%HoH = ('; # open the HASH of HASH lines
        my $Sline  = '        '; # spaces
        my $Cline  = '       );'; # open the HASH of HASH lines
        my $tStamp = strftime('%d %B %Y %T', localtime);
        my $user   = $ENV{'USER'}; $user = "UNKNOWN" if ($user eq "");

        # output the header
        print STDOUT "#\n";
        print STDOUT "# Pre-compiled configuation file created:\n";
        print STDOUT "#   Date: $tStamp\n";
        print STDOUT "#   From: $CLIref->{$CONFKEY}\n";
        print STDOUT "#   User: $user\n";
        print STDOUT "#\n";
        print STDOUT "\n";

        # output configuration for the 3
        print STDOUT '$CLIref->{' . "'" . $HDBGKEY . "'" . '} = ' . "0; # always set to zero by default\n";
        print STDOUT '$CLIref->{' . "'" . $LOOKKEY . "'" . '} = ' . "'$CLIref->{$LOOKKEY}';\n";
        print STDOUT '$CLIref->{' . "'" . $PATHKEY . "'" . '} = ' . "'$CLIref->{$PATHKEY}';\n";
        print STDOUT "\n";

        # output all the N-Tuples
        print STDOUT "$Oline\n"; # open HoH declaration line
        $spch = '        ';
        for $tKey ( sort keys %HoH )
        {
            %cfg = %{ $HoH{$tKey} };
            print STDOUT $Sline . "'$tKey' => {   # started on line " . $cfg{$LINEKEY} . "\n";
            $spch = $tKey;
            $spch =~ s@.@ @g; # $spch is now just spaces
            print STDOUT $Sline . "$spch       '$TAGpKEY' => " . '"' . $cfg{$TAGpKEY} . '",' . "\n";
            print STDOUT $Sline . "$spch       '$SUBfKEY' => " . '"' . $cfg{$SUBfKEY} . '",' . "\n";
            print STDOUT $Sline . "$spch       '$MAKEKEY' => " . '"' . $cfg{$MAKEKEY} . '",' . "\n";
            print STDOUT $Sline . "$spch       '$NAMEKEY' => " . '"' . $cfg{$NAMEKEY} . '",' . "\n";
            print STDOUT $Sline . "$spch      },\n";
        }
        print STDOUT "$Cline\n"; # close HoH declaration line
        exit 0; # yes, this exits right here, we are done with building the precompiled configuration file
    }
    # OUTPUT THE INTERNAL HASH OF HASHES if debug is high enough
    if ( $CLIref->{$HDBGKEY} > ($dbgInc + 0) )
    {
        print STDERR "$VAR_H_DEBUG=" . $CLIref->{$HDBGKEY} . "\n";
        print STDERR "$VAR_SVNLOOK=" . $CLIref->{$LOOKKEY} . "\n";
        print STDERR "$VAR_SVNPATH=" . $CLIref->{$PATHKEY} . "\n";
        print STDERR "\n";
        for $tKey ( sort keys %HoH )
        {
            $spch = $tKey;
            $spch =~ s@.@ @g;        # make a string of spaces
            %cfg = %{ $HoH{$tKey} }; # load the config hash
            print STDERR "$tKey = {";
            print STDERR "   # started on line $cfg{$LINEKEY}" if ( exists $cfg{$LINEKEY} );
            print STDERR "\n";
            print STDERR "$spch       $VAR_TAGFOLD=" . '"' . $HoH{$tKey}{$TAGpKEY} . '"' . " # literal only\n";
            print STDERR "$spch       $VAR_SUBFOLD=" . '"' . $HoH{$tKey}{$SUBfKEY} . '"' . " # literal, a glob, or blank\n";
            print STDERR "$spch       $VAR_MAKESUB=" . '"' . $HoH{$tKey}{$MAKEKEY} . '"' . " # authorized committers - can create subfolders/subprojects\n";
            print STDERR "$spch       $VAR_NAME_AF=" . '"' . $HoH{$tKey}{$NAMEKEY} . '"' . " # authorised committers only - name of folder for archiving\n";
            print STDERR "$spch   }\n";
        }
    }
    return ( %HoH );
} # LEAVE: parse config file

sub ParseCLI # ENTER: parse command line
{
    my $Pname = shift;   # program name
    my $Pdire = shift;   # program directory, usually ends with "hooks"
    my $Conff = shift;   # name of configuation file
    my $PreCf = shift;   # name of "pre-compiled" configuration file
    my %cli = ();        # the hash to load with values gotten from the
    ###################### command line, in production there will always
    ###################### only be 2 command line options, the path to
    ###################### the subversion repository and the subversion
    ###################### transaction ID, but the hash is filled out
    ###################### with other data that _could_ come from command
    ###################### line arguments when invoking the script from the
    ###################### command line for debugging/testing purposes.
    ######################
    ###################### everthing neeed as initial default in case one of the
    ###################### Print...AndExit functions is called.
    $cli{$BCFGKEY} = 0;             # 1 if --build on command line
    $cli{$CLIDKEY} = 0;             # 1 if --debug on command line
    $cli{$CONFKEY} = $Conff;        # name of config file - it can be changed
    $cli{$DUMPKEY} = 0;             # revert a precompiled config file
    $cli{$HDBGKEY} = $DEF_H_DEBUG;  # hook debug level
    $cli{$PARSKEY} = 0;             # 1 if --parse on command line
    $cli{$LOOKKEY} = $DEF_SVNLOOK;  # default path to svnlook
    $cli{$PATHKEY} = $DEF_SVNPATH;  # default path to svn
    $cli{$PREFKEY} = $PreCf;        # name of precompiled config file
    $cli{$RCLIKEY} = 0;             # 1 if we know we are running CLI
    $cli{$SVNIDEN} = "";            # transaction id -- this from subversion or dummied up
    $cli{$SVNREPO} = "";            # path to repo -- this from subversion or dummied up

    $ARGV[0] = '--help' if ( $#ARGV < 0 );
    while ( $#ARGV >= 0 )
    {
        print STDERR "ParseCLI: $#ARGV\t$ARGV[0]\n" if ( $cli{$HDBGKEY} > 6 );

        # ENTER: options that cause an immediate exit after doing their job
        if    ( $ARGV[0] eq '--help'          or $ARGV[0] eq '-h'  )
        {
            &PrintUsageAndExit($Pname, $Conff, $PreCf, $cli{$LOOKKEY}, $cli{$PATHKEY});
        }
        elsif ( $ARGV[0] eq '--generate'      or $ARGV[0] eq '-g'  )
        {
            &PrintDefaultConfigAndExit(0, $cli{$HDBGKEY});
        }
        elsif ( $ARGV[0] eq '--version'       or $ARGV[0] eq '-v'  )
        {
            &PrintVersionAndExit();
        }
        # LEAVE: options that cause an immediate exit after doing their job

        # ENTER: options that mean we are not running under subversion
        #    ENTER: options that cause a printout then exit
        elsif ( $ARGV[0] eq '--build'         or $ARGV[0] eq '-b'  )
        {
            $cli{$BCFGKEY} = 1;
            $cli{$RCLIKEY} = 1; # running on comamnd line
        }
        elsif ( $ARGV[0] eq '--revert'        or $ARGV[0] eq '-r'  )
        {
            $cli{$DUMPKEY} = 1;
            $cli{$RCLIKEY} = 1; # running on comamnd line
        }
        elsif ( $ARGV[0] =~ '--revert=?+'                          )
        {
            $cli{$DUMPKEY} = 1;
            $cli{$PREFKEY} = $ARGV[0]; $cli{$PREFKEY} =~ s@--revert=@@;
            $cli{$RCLIKEY} = 1; # running on comamnd line
        }
        elsif ( $ARGV[0] =~ '-r..*'                                )
        {
            $cli{$DUMPKEY} = 1;
            $cli{$PREFKEY} = $ARGV[0]; $cli{$PREFKEY} =~ s@-r@@;
            $cli{$RCLIKEY} = 1; # running on comamnd line
        }
        elsif ( $ARGV[0] eq '--parse'         or $ARGV[0] eq '-p'  )
        {
            $cli{$PARSKEY} = 1;
            $cli{$RCLIKEY} = 1; # running on comamnd line
        }
        elsif ( $ARGV[0] =~ '--parse=?+'                          )
        {
            $cli{$PARSKEY} = 1;
            $cli{$CONFKEY} = $ARGV[0]; $cli{$CONFKEY} =~ s@--parse=@@;
            $cli{$RCLIKEY} = 1; # running on command line
        }
        elsif ( $ARGV[0] =~ '-p..*'                                )
        {
            $cli{$PARSKEY} = 1;
            $cli{$CONFKEY} = $ARGV[0]; $cli{$CONFKEY} =~ s@-p@@;
            $cli{$RCLIKEY} = 1; # running on command line
        }
        #    LEAVE: options that cause a printout then exit

        elsif ( $ARGV[0] eq '--nodebug'       or $ARGV[0] eq '-D'  )
        {
            $cli{$CLIDKEY} = 1; # debug on command line, use it only
            $cli{$HDBGKEY} = 0;
            $cli{$RCLIKEY} = 1; # running on command line
        }
        elsif ( $ARGV[0] eq '--debug'         or $ARGV[0] eq '-d'  )
        {
            $cli{$CLIDKEY} = 1; # debug on command line, use it only
            if ( $cli{$HDBGKEY} <= 0 ) { $cli{$HDBGKEY} = 1; } else { $cli{$HDBGKEY} ++; }
            $cli{$RCLIKEY} = 1; # running on command line
        }
        elsif ( $ARGV[0] =~ '--debug=[0-9]+'                       )
        {
            $cli{$CLIDKEY} = 1; # debug on command line, use it only
            $cli{$HDBGKEY} = $ARGV[0]; $cli{$HDBGKEY} =~ s@--debug=@@;
            $cli{$RCLIKEY} = 1; # running on command line
        }
        elsif ( $ARGV[0] =~ '-d[0-9]+'                             )
        {
            $cli{$CLIDKEY} = 1; # debug on command line, use it only
            $cli{$HDBGKEY} = $ARGV[0]; $cli{$HDBGKEY} =~ s@-d@@;
            $cli{$RCLIKEY} = 1; # running on command line
        }
        elsif ( $ARGV[0] =~ '-d=[0-9]+'                             )
        {
            $cli{$CLIDKEY} = 1; # debug on command line, use it only
            $cli{$HDBGKEY} = $ARGV[0]; $cli{$HDBGKEY} =~ s@-d=@@;
            $cli{$RCLIKEY} = 1; # running on command line
        }
        # LEAVE: options that mean we are not running under subversion

        # ENTER: fatal errors
        elsif ( $ARGV[0] =~ '^-.*'                                 )
        {
            print STDERR "$Pname: unrecognized command line option: \"$ARGV[0]\"!\n";
            print STDERR "$Pname: ABORTING!\n";
            exit $exitFatalErr;
        }
        elsif ( $#ARGV != 1 )
        {
            my $aHave = int($#ARGV) + 1;
            my $aNeed = 2;
            print STDERR "$Pname: incorrect command line argument count is: $aHave (it should be $aNeed).\n";
            print STDERR "$Pname: perhaps you are not running under subversion?  if so give two dummy command line options.\n";
            print STDERR "$Pname: ABORTING!\n";
            exit $exitFatalErr;
        }
        # LEAVE: fatal errors

        # ENTER: in PRODUCTION, under Subversion, only this block is ever invoked
        else # two command line arguments left
        {
            $cli{$SVNREPO} = $ARGV[0];
            shift @ARGV;
            $cli{$SVNIDEN} = $ARGV[0];
        }
        # LEAVE: in PRODUCTION, under Subversion, only this block is ever invoked

        shift @ARGV;
    }

    # if debugging and the command line did not give the expected subversion
    # command line arguments then give them here so the program can continue,
    # usually just to parse the config file.
    if ( $cli{$HDBGKEY} > 0)
    {
        if ( $cli{$SVNREPO} eq "" or $cli{$SVNIDEN} eq "" )
        {
            $cli{$SVNREPO} =  $Pdire; # this should now be the path to the repo, unless in development
            $cli{$SVNREPO} =~ s@/hooks$@@;
            $cli{$SVNIDEN} = "HEAD";  # this will be useless talking to subversion with svnlook
        }
    }
    return ( %cli );
} # LEAVE: parse command line

sub PrintDefaultConfigAndExit
{
    my $headerOnly = shift;
    my $dbglvl     = shift; # passed in instead of passing $CLIref
    my $q = '"';

    if ($dbglvl > 0)
    {
        if ( $headerOnly )
        {
            print STDERR "PrintDefaultConfigAndExit: output default header.\n";
        }
        else
        {
            print STDERR "PrintDefaultConfigAndExit: output default configuration file.\n";
        }
    }
    print STDOUT "#\n";
    print STDOUT "#  The parsing script will build an 'N-Tuple' from each\n";
    print STDOUT "#  '${VAR_TAGFOLD}' variable.\n";
    print STDOUT "#\n";
    print STDOUT "# Recognized variable/value pairs are:\n";
    print STDOUT "#   These are for debugging and the svnlook path\n";
    print STDOUT "#          ${VAR_H_DEBUG}\t\t= N\n";
    print STDOUT "#          ${VAR_SVNPATH}\t\t= path to svn\n";
    print STDOUT "#          ${VAR_SVNLOOK}\t\t= path to svnlook\n";
    print STDOUT "#   These make up an N-Tuple\n";
    print STDOUT "#          ${VAR_TAGFOLD}\t\t= /<path>\n";
    print STDOUT "# e.g.:    ${VAR_SUBFOLD}\t= /<path>/*\n";
    print STDOUT "# or e.g.: ${VAR_SUBFOLD}\t= /<path>/*/*\n";
    print STDOUT "#          ${VAR_MAKESUB}\t= '*' or '<user>, <user>, ...'\n";
    print STDOUT "#          ${VAR_NAME_AF}\t= <name>\n";
    print STDOUT "\n";
    print STDOUT "### These should be first\n";
    print STDOUT &PrtStr($VAR_H_DEBUG) . " = $DEF_H_DEBUG\n";
    print STDOUT &PrtStr($VAR_SVNPATH) . " = ${q}$DEF_SVNPATH${q}\n";
    print STDOUT &PrtStr($VAR_SVNLOOK) . " = ${q}$DEF_SVNLOOK${q}\n";
    print STDOUT "\n";
    print STDOUT "### These comprise an N-Tuple, can be repeated as many times as wanted,\n";
    print STDOUT "### but each ${VAR_TAGFOLD} value must be unique.   It is not allowed to\n";
    print STDOUT "### try to configure the same folder twice (or more)!\n";
    if ( $headerOnly == 0 )
    {
        print STDOUT &PrtStr($VAR_TAGFOLD) . " = ${q}$DEF_TAGFOLD${q}\n";
        print STDOUT &PrtStr($VAR_SUBFOLD) . " = ${q}$DEF_SUBFOLD${q}\n";
        print STDOUT &PrtStr($VAR_MAKESUB) . " = ${q}$DEF_MAKESUB${q}\n";
        print STDOUT &PrtStr($VAR_NAME_AF) . " = ${q}$DEF_NAME_AF${q}\n";
        exit $exitUserHelp; # only exit if doing the whole thing
    }
} # PrintDefaultConfigAndExit

sub PrintUsageAndExit # output and exit
{
    my $name    = shift;
    my $inif    = shift;
    my $pref    = shift;
    my $deflook = shift;
    my $defsvn  = shift;

    my $look = $deflook;
    $look =~ s@.*/@@;
    $look =~ s@.*\\@@;

    my $svn  = $defsvn;
    $svn =~ s@.*/@@;
    $svn =~ s@.*\\@@;

    print STDOUT "\n";
    print STDOUT "usage: $name repo-name transaction-id  - Normal usage under Subversion.\n";
    print STDOUT "OR:    $name --help                    - Get this printout.\n";
    print STDOUT "OR:    $name [options]                 - CLI testing and debugging.\n";
    print STDOUT "\n";
    print STDOUT "    THIS SCRIPT IS A HOOK FOR SUBVERSION AND IS NOT MEANT TO BE\n";
    print STDOUT "    RUN FROM THE COMMAND LINE UNDER NORMAL USAGE.\n";
    print STDOUT "\n";
    print STDOUT "    The required arguments, repo-name and transaction-id, are\n";
    print STDOUT "    provided by subversion.  This subversion hook uses:\n";
    print STDOUT "        '$look'\n";
    print STDOUT "    the path of which can be configured and defaults to: '$deflook'\n";
    print STDOUT "    and '$svn'\n";
    print STDOUT "    the path of which can be configured and defaults to: '$defsvn'\n";
    print STDOUT "\n";
    print STDOUT "    It uses the configuration file:\n";
    print STDOUT "        $inif\n";
    print STDOUT "    If it exists, this \"precompiled\" file will take precedence:\n";
    print STDOUT "        $pref\n";
    print STDOUT "    and the configuation file will not be read.\n";
    print STDOUT "\n";
    print STDOUT "    When invoked from the command line it will accept these additional\n";
    print STDOUT "    options, there is no way you can give these in production while running\n";
    print STDOUT "    under subversion.\n";

    print STDOUT "    --help            | -h      Show usage information and exit.\n";
    print STDOUT "\n";
    print STDOUT "    --debug[=n]       | -d[n]   Increment or set the debug value, If given this\n";
    print STDOUT "                                command line option should be first, otherwise\n";
    print STDOUT "                                you might get debug output at all, depending\n";
    print STDOUT "                                upon other command line options.  Typically used\n";
    print STDOUT "                                with the --parse option to explicitly see what\n";
    print STDOUT "                                is happening when reading the configuration\n";
    print STDOUT "                                file.\n";
    print STDOUT "\n";
    print STDOUT "    --parse[=file]  | -c[file]  Parse  the  configuration file, default is\n";
    print STDOUT "                                tagprotect.conf, then exit.  Errors found in the\n";
    print STDOUT "                                configuration will be printed to standard error.\n";
    print STDOUT "                                If there are no errors you will get no output\n";
    print STDOUT "                                unless debug is greater than zero(0).  Typically\n";
    print STDOUT "                                used for testing/debugging an  alternate\n";
    print STDOUT "                                configuration file before moving it into\n";
    print STDOUT "                                production.  NOTE: in production  the\n";
    print STDOUT "                                configuration  file cannot be changed, you can\n";
    print STDOUT "                                only do this on the command line.\n";
    print STDOUT "\n";
    print STDOUT "    --generate        | -g      Generate a default configuration file, with\n";
    print STDOUT "                                comments, and  write it to standard output.\n";
    print STDOUT "                                Typically used for testing/debugging a\n";
    print STDOUT "                                configuration file before moving into\n";
    print STDOUT "                                production.\n";
    print STDOUT "\n";
    print STDOUT "    --build           | -b      Build (i.e. generate) a \"precompiled\" file from\n";
    print STDOUT "                                the configuration file, with comments, and write\n";
    print STDOUT "                                it to standard output. This speeds up reading\n";
    print STDOUT "                                the configuration but is only needed by sites\n";
    print STDOUT "                                with a large large number of configuations - say\n";
    print STDOUT "                                20 or more, your mileage may vary - and only if\n";
    print STDOUT "                                the server is old and slow. If a precompiled\n";
    print STDOUT "                                configuation exists pre-commit will read it and\n";
    print STDOUT "                                ignore the configuration file.\n";
    print STDOUT "\n";
    print STDOUT "    --revert[=file] | -r[file]  Opposite of, --build, write to standard output a\n";
    print STDOUT "                                configuation file from a previously built\n";
    print STDOUT "                                \"precompiled\" configuration file.\n";

    print STDOUT "\n";
    print STDOUT "\n";
    print STDOUT "NOTE: a typical command line usage for debugging purposes would look\n";
    print STDOUT "      like this\n";
    print STDOUT "        ./$name [options] --debug=N < /dev/null\n";
    print STDOUT "\n";
    print STDOUT "$name: " . &GetVersion(1) . "\n";
    print STDOUT "\n";
    exit $exitUserHelp;
} # PrintUsageAndExit

sub PrintVersionAndExit
{
    print STDOUT &GetVersion(1) . "\n";
    exit $exitUserHelp;
} # PrintVersionAndExit

sub PrtStr # string '$s' returned formatted when generating a config file
{
    my $s = shift;
    my $f = &FmtStr();
    my $r = sprintf($f, $s);
    return $r;
} # PrtStr

# cannot determine what the commit does - one or more artifacts cannot be correctly parsed
# this is called when everything else fails, increase debug for more information
sub SayImpossible
{
    my $name = shift;
    print STDERR "$name: commit failed, re: UNKNOWN!\n";
    print STDERR "$name: it appears this commit does not modify, add, or delete anything!\n";
    return 0;
} # SayImpossible

sub SayNoDelete
{
    my $name = shift;
    my $what = shift;
    print STDERR "$name: commit failed, delete of protected folders is not allowed!\n";
    print STDERR "$name: commit failed on: $what\n";
    return 0;
} # SayNoDelete

sub SimplyAllow # ENTER: determine if we can simply allow this commit or of a protected folder is part of the commit
{
    my $CLIref = shift;   # reference to command line hash
    my $CFGref = shift;   # reference to configuration hash
    my $CMdata = shift;   # reference to changed directories array
    my $justAllow = 1;    # assume most commits are not tags
    my $itmp = -1;        # iterate the incoming array of commits
    my $pfolder;          # protected folder
    my $tupleKey;         # N-Tuple keys found in the configuation ref
    local $_;             # artifact to be committed, changed or whatever

    while( $itmp < $#$CMdata )
    {
        $_ = $CMdata->[$itmp];
        print STDERR "SimplyAllow: >>$_<<\n" if ( $CLIref->{$HDBGKEY} > 3 );

        s/^[A-Z_]+\s+//;               # trim first two char(s) and two spaces

        print STDERR "SimplyAllow: >>$_<<\n" if ( $CLIref->{$HDBGKEY} > 2 );

        for $tupleKey ( keys %{ $CFGref } )
        {
            $pfolder = $CFGref->{$tupleKey}{$TAGpKEY};  # protected folder
            # if the artifact is under a protected folder we cannot simply allow
            if ( &IsUnderProtectection($pfolder, $_, $CLIref->{$HDBGKEY}) == 1 )
            {
                print STDERR "SimplyAllow: artifact under protection is: $_\n" if ( $CLIref->{$HDBGKEY} > 1 );
                $justAllow = 0; # nope, we gotta work!
                last;
            }
        }
        $itmp ++;
    }
    print STDERR "SimplyAllow: \$justAllow=$justAllow RETURNED\n" if ( $CLIref->{$HDBGKEY} > 1 );
    return $justAllow;
} # SimplyAllow: LEAVE: determine if we can simply allow this commit or of a protected folder is part of the commit

sub TheAddIsAllowed
{
    my $Pname  = shift;   # name of calling program
    my $CLIref = shift;   # reference to command line hash
    my $CFGref = shift;   # reference to configuration hash
    my $author = shift;   # committer of this change
    my $ADDref = shift;   # array reference to the "array of stuff to add"
    my $afold;            # archive folder name
    my $amake;            # users that can create new project folders
    my $artifact;         # user wants to add
    my $commit = 1;       # assume OK to commit
    my $arrayRef;         # pointer to the inner array
    my $pfold;            # protected (parent) folder
    my $sfold;            # subfolder under $pfold, can be BLANK
    my $tupKey;           # N-Tuple key used to find data in $CFGref
    my $glob;             # a "glob" pattern to check for matches

    if ( $CLIref->{$HDBGKEY} > 3 )
    {
        for $arrayRef ( @{ $ADDref } )
        {
            ($tupKey, $artifact) = ( @{ $arrayRef } );
            print STDERR "TheAddIsAllowed: FROM CFG $tupKey TEST $artifact\n";
        }
    }
    for $arrayRef ( @{ $ADDref } ) # we know all these are protected and to be added
    {
        ($tupKey, $artifact) = ( @{ $arrayRef } );
        $pfold = $CFGref->{$tupKey}{$TAGpKEY}; # protected folder
        $amake = $CFGref->{$tupKey}{$MAKEKEY}; # authorised to make subfolders
        $afold = $CFGref->{$tupKey}{$NAMEKEY}; # archive folder name
        $sfold = $CFGref->{$tupKey}{$SUBfKEY}; # subfolder name - glob is allowed here

        if ( $CLIref->{$HDBGKEY} > 4 )
        {
            print STDERR 'TheAddIsAllowed: $tupKey'   . "\t= $tupKey\n";
            print STDERR 'TheAddIsAllowed: $artifact' . "\t= $artifact\n";
            print STDERR 'TheAddIsAllowed: $pfold'    . "\t\t= $pfold\n";
            print STDERR 'TheAddIsAllowed: $afold'    . "\t\t= $afold\n";
            print STDERR 'TheAddIsAllowed: $amake'    . "\t\t= $amake\n";
            print STDERR 'TheAddIsAllowed: $sfold'    . "\t\t= $sfold\n";
        }

        # IN ORDER TO ENSURE CORRECTLY FIGURING OUT WHAT THE USER IS DOING TEST IN THIS ORDER:
        # 1) attempting to add to the Achive folder?
        # 2) attempting to add to a tag?
        # 3) attempting to add _the_ Achive folder itself?
        # 4) attempting to add a project folder?
        # 5) attempting to add the protected folder _itself_ ?
        # 6) attempting to add a folder? <= this should never happen, above takes care of it
        # 7) attempting to add a file that is not part of a tag?

        # 1) attempting to add to the Achive?
        if    ( $sfold eq "" and $afold eq "" ) { $glob = "";                              } # no subfolder, no archive folder name
        elsif ( $sfold eq "" and $afold ne "" ) { $glob = $pfold . '/' . $afold . "/?*";   } # no subfolder, yes archive folder name
        elsif ( $sfold ne "" and $afold eq "" ) { $glob = "";                              } # yes subfolder, not arhive folder name
        elsif ( $sfold ne "" and $afold ne "" ) { $glob = $sfold . '/' . $afold . "/?*";   } # yes subfolder, yes archive folder name
        if ( $glob ne "" )
        {
            print STDERR "TheAddIsAllowed: if (AddingTooArchiveFolder($pfold, $sfold, $afold, $artifact, $CLIref->{$HDBGKEY})) is the test to see if adding to an archive folder\n" if ( $CLIref->{$HDBGKEY} > 5 );
            if ( &AddingTooArchiveFolder($pfold, $sfold, $afold, $artifact, $CLIref->{$HDBGKEY}) == 1 )
            {
                print STDERR 'TheAddIsAllowed: $artifact=' . "$artifact IS UNDER AN ARCHIVE FOLDER\n" if ( $CLIref->{$HDBGKEY} > 4 );
                print STDERR "$Pname: you can only move existing tags to an archive folder\n";
                print STDERR "$Pname: commit failed, you cannot add anything to an archive folder is not allowed!\n";
                print STDERR "$Pname: commit failed on: $artifact\n";
                $commit = 0;
                last;
            }
        }
        print STDERR "TheAddIsAllowed: KEEP TESTING -> NOT ADDING TO AN ARCHIVE FOLDER $artifact\n" if ( $CLIref->{$HDBGKEY} > 2 );

        # 2) attempting to add to a tag?
        if    ( $sfold eq ""                    ) { $glob = $pfold . "/?*"; } # no subfolder
        else                                      { $glob = $sfold . "/?*"; }
        print STDERR "TheAddIsAllowed: if ( match_glob( $glob, $artifact ) ) is the test to see if adding a new tag\n" if ( $CLIref->{$HDBGKEY} > 5 );
        if ( match_glob( $glob, $artifact ) )
        {
            # no problem - adding a tag
            # no work but this match prevents the next one, and that is why it is here
            print STDERR "TheAddIsAllowed: stop TESTING -> THIS IS PART OF A NEW TAG $artifact\n" if ( $CLIref->{$HDBGKEY} > 2 );
        }
        else
        {
            print STDERR "TheAddIsAllowed: KEEP TESTING -> THIS IS NOT PART OF A NEW TAG $artifact\n" if ( $CLIref->{$HDBGKEY} > 2 );
            # 3) attempting to add the _Achive folder_ itself?
            if ( $afold ne "" )
            {
                print STDERR "TheAddIsAllowed: AddingArchiveFolder($pfold, $sfold, $afold, $artifact, $CLIref->{$HDBGKEY}) is the test to see if adding an archive folder\n" if ( $CLIref->{$HDBGKEY} > 5 );
                if ( &AddingArchiveFolder($pfold, $sfold, $afold, $artifact, $CLIref->{$HDBGKEY}) == 1 )
                {
                    print STDERR 'TheAddIsAllowed: $artifact=' . "$artifact IS AN ARCHIVE FOLDER\n" if ( $CLIref->{$HDBGKEY} > 2 );
                    $commit = &Authorized($Pname, $author, $amake, $artifact, 'add an archive folder', $CLIref->{$HDBGKEY});
                    last if ( $commit == 0 );
                    next;
                }
            }
            print STDERR "TheAddIsAllowed: KEEP TESTING -> NOT ADDING AN ARCHIVE FOLDER $artifact\n" if ( $CLIref->{$HDBGKEY} > 2 );

            # 4) attempting to add a project folder?
            if ( &AddingSubFolder($pfold, $sfold, $artifact, $CLIref->{$HDBGKEY}) == 1 )
            {
                print STDERR "TheAddIsAllowed: stop TESTING -> THIS IS A NEW PROJECT SUB FOLDER $artifact\n" if ( $CLIref->{$HDBGKEY} > 2 );
                $commit = &Authorized($Pname, $author, $amake, $artifact, 'add a project (or sub) folder', $CLIref->{$HDBGKEY});
                last if ( $commit == 0 );
                next;
            }
            print STDERR "TheAddIsAllowed: KEEP TESTING -> NOT ADDING A PROJECT FOLDER $artifact\n" if ( $CLIref->{$HDBGKEY} > 2 );

            # 5) attempting to add the protected folder _itself_ ?
            if ( "$pfold/" eq $artifact ) # trying to add the parent folder itself
            {
                print STDERR 'TheAddIsAllowed: $artifact=' . "$artifact IS THE PROTECTED FOLDER\n" if ( $CLIref->{$HDBGKEY} > 2 );
                $commit = &Authorized($Pname, $author, $amake, $artifact, 'create the protected folder', $CLIref->{$HDBGKEY});
                last if ( $commit == 0 );
                next;
            }
            else # attempting to add a file instead of a tag
            {
                print STDERR "TheAddIsAllowed: stop TESTING -> CANNOT ADD ARBITRARY FOLDER OR FILE TO A PROTECTED FOLDER artifact=$artifact\n" if ( $CLIref->{$HDBGKEY} > 4 );
                print STDERR "$Pname: you can only only add new tags\n";
                if ( $artifact =~ m@/$@ )
                {
                    # 6) attempting to add a folder? <= this should never happen, above takes care of it
                    print STDERR "$Pname: commit failed, you cannot add a folder!\n";
                }
                else
                {
                    # 7) attempting to add a file that is not part of a tag?
                    print STDERR "$Pname: commit failed, you cannot add a file to a protected folder!\n";
                }
                print STDERR "$Pname: commit failed on: $artifact\n";
                $commit = 0;
                last;
            }
        }
    }
    print STDERR "TheAddIsAllowed: RETURNED $commit\n" if ( $CLIref->{$HDBGKEY} > 2 );
    return $commit;
} # TheAddIsAllowed

sub TheMoveIsAllowed
{
    my $Pname  = shift;   # name of calling program
    my $CLIref = shift;   # reference to command line hash
    my $CFGref = shift;   # reference to configuration hash
    my $CMdata = shift;   # reference to committed files/folders data array
    my $author = shift;   # committer of this change
    my $ADDref = shift;   # reference to the array of stuff to add
    my $DELref = shift;   # reference to the array of stuff to delete
    my $addKey;           # N-Tuple key from the "add" array
    my $addPath;          # path from the "add" array
    my $addPathNoArch;    # path from the "add" array with next to last folder with "Arhive name" removed
    my $addRef;           # reference for add array
    my $archive;          # name of an archive folder for this N-Tuple
    my $check1st;         # path to check before putting a path into @pureAdd
    my $commit = 1;       # assume OK to commit
    my $count;            # of elements in @pureAdd
    my $delNdx;           # found the thing in the del array this is in the add array?
    my $delKey;           # N-Tuple key from the "del" array
    my $delPath;          # path from the "del" array
    my $delRef;           # reference for the del array
    my $justAdd;          # true if the path in the add array has no matching path in the del array
    my $ok2add;           # ok to put a path into @pureAdd because it is not there already
    my $ref;              # reference into @pureAdd
    my $stmp;             # tmp string
    my @pureAdd;          # array of additions found that do not have matching delete/move
    my @tmp;              # used to load the @pureAdd array with data

    # walk each of the artifacts to be added
    for $addRef ( @{ $ADDref } )
    {
        ($addKey, $addPath) = ( @{ $addRef } );
        print STDERR "TheMoveIsAllowed: ADD cfgkey $addKey path $addPath\n" if ( $CLIref->{$HDBGKEY} > 2 );
        $archive = $CFGref->{$addKey}{$NAMEKEY};
        if ( $archive eq "" )
        {
            $justAdd = 1;
            print STDERR "TheMoveIsAllowed: NO ARCHIVE FOLDER - just add\n" if ( $CLIref->{$HDBGKEY} > 2 );
        }
        else
        {
            $justAdd = 0;
            if ( $addPath =~ m@^(/.+)/${archive}/([^/]+/)$@ ) # does path have "archive folder name" in it as next to last folder
            {
                print STDERR "TheMoveIsAllowed: ADD cfgkey $addKey PATH does have archive $addPath\n" if ( $CLIref->{$HDBGKEY} > 3 );
                $addPathNoArch = "$1/$2";
                print STDERR "TheMoveIsAllowed: ADD cfgkey $addKey PATH with archive removed $addPathNoArch\n" if ( $CLIref->{$HDBGKEY} > 2 );
                $delNdx = -1; # impossible value
                $count = 0;
                # walk each of the artifacts to be deleted and look to see if the thing added is related to the artifact being deleted by an archive folder name
                for $delRef ( @{ $DELref } )
                {
                    ($delKey, $delPath) = ( @{ $delRef } );
                    print STDERR "TheMoveIsAllowed: DEL cfgkey $delKey path with Archive $delPath\n" if ( $CLIref->{$HDBGKEY} > 2 );
                    if ( $addKey eq $delKey and $addPathNoArch eq $delPath )
                    {
                        $delNdx = $count;
                        if ( $CLIref->{$HDBGKEY} > 5 )
                        {
                            print STDERR "TheMoveIsAllowed: DEL is moving to Arhive, that's OK\n";
                            print STDERR "TheMoveIsAllowed: ADD KEY  >>$addKey<<\n";
                            print STDERR "TheMoveIsAllowed: DEL KEY  >>$delKey<<\n";
                            print STDERR "TheMoveIsAllowed: ADD PATH >>$addPathNoArch<<\n";
                            print STDERR "TheMoveIsAllowed: DEL PATH >>$delPath<<\n";
                        }
                        last;
                    }
                    $count ++;
                }
                if ( $delNdx != -1 ) # was the index into the del array found?
                {
                    print STDERR "TheMoveIsAllowed:        splice delNdx is: $delNdx\n" if ( $CLIref->{$HDBGKEY} > 4 );
                    splice @{ $DELref }, $delNdx, 1; # ignore any returned value, not needed
                }
                else
                {
                    print STDERR "TheMoveIsAllowed: delNdx is nagative: $delNdx, will not SPLICE it out of the delete array\n" if ( $CLIref->{$HDBGKEY} > 4 );
                }
            }
            else # found a path to add but it does not have "archive folder name" as next to last folder
            {
                $justAdd = 1;
                print STDERR "TheMoveIsAllowed: NO ARCHIVE MATCH - just add\n" if ( $CLIref->{$HDBGKEY} > 4 );
            }
        }
        if ( $justAdd )
        {
            $ok2add = 1; # assume so
            $count = int(@pureAdd);
            if ( $count > 0 )
            {
                $ref = $pureAdd[$count - 1];
                ($stmp, $check1st) = @{ $ref };
                if (length($addPath) >= length($check1st))
                {
                    $ok2add = 0 if ( $addPath =~ $check1st );
                }
            }
            if ( $ok2add )
            {
                @tmp = ($addKey, $addPath);
                print STDERR "TheMoveIsAllowed: $addPath pushed to 'pureAdd'\n" if ( $CLIref->{$HDBGKEY} > 3 );
                push @pureAdd, [ @tmp ];
            }
            else
            {
                print STDERR "TheMoveIsAllowed: $addPath not needed it is a duplicate\n" if ( $CLIref->{$HDBGKEY} > 3 );
            }
        }
    }
    if ( $CLIref->{$HDBGKEY} > 2 )
    {
        print STDERR "TheMoveIsAllowed: LOOP IS DONE\n";
        print STDERR "TheMoveIsAllowed: left over delete count is: $#$DELref  (0 or more means there are some deletes not part of moves)\n";
        print STDERR "TheMoveIsAllowed: pure add array   count is: " . int( @pureAdd ) . "\n";
    }
    if ( ! ( $#$DELref < 0 ) ) # if there is something left over to be deleted then it is not a "move"
    {
        for $delRef ( @{ $DELref } )
        {
            ($delKey, $delPath) = ( @{ $delRef } );
            $commit = &SayNoDelete($Pname, "D   $delPath");   # always returns 0
            last; # just do one
        }
    }
    elsif ( int( @pureAdd ) > 0 ) # there is something left over to be added and must check that on its own
    {
        $commit = &TheAddIsAllowed($Pname, $CLIref, $CFGref, $author, \@pureAdd);
    }
    print STDERR "ALlowMove: RETURNED $commit\n" if ( $CLIref->{$HDBGKEY} > 2 );
    return $commit;
} # TheMoveIsAllowed

# if the (now parsed into PERL hash of hash) configuration file has the _identical_
# tag folder to protect repeated (i.e. given more that once) error out and die.
# a tag folder to protect can only be given once.
sub ValidateCFGorDie
{
    my $Pname   = shift;   # name of calling program
    my $Iname   = shift;   # configuation file name
    my $HoHstr  = shift;   # hash of has key string
    my $HoHcnt  = shift;   # hash of has key count
    my $HoHref  = shift;   # ref to hash of hash
    my $folderKey = shift; # key to find protected folder in the innner hash
    my $linenoKey = shift; # key to find line number contained in the inner has
    #
    my $count_1 = 0;       # index for outer count
    my $count_2 = 0;       # index for inner count
    my $key_1;             # to loop through keys
    my $key_2;             # to loop through keys
    my $protected_1;       # 1st protected folder to compare with
    my $protected_2;       # 2nd protected folder to compare with
    my $error = 0;         # error count

    while ( $count_1 < $HoHcnt )
    {
        $key_1 = &GenTupleKey($HoHstr, $count_1);
        $protected_1 = $HoHref->{$key_1}{$folderKey};  # data to compare
        $count_2 = $count_1 + 1;
        while ( $count_2 < $HoHcnt )
        {
            $key_2 = &GenTupleKey($HoHstr, $count_2);
            $protected_2 = $HoHref->{$key_2}{$folderKey};  # data to compare
            if ( $protected_2 eq $protected_1 )
            {
                if ( $error == 0 )
                {
                    print STDERR "$Pname: error with configuration file: \"$Iname\"\n";
                }
                else
                {
                    print STDERR "\n";
                }
                print STDERR "$Pname: the protected path \"$protected_1\" is duplicated\n";
                print STDERR "$Pname: lines with duplications are:";
                print STDERR " $HoHref->{$key_1}{$linenoKey}";
                print STDERR " and";
                print STDERR " $HoHref->{$key_2}{$linenoKey}\n";
                $error = 1;
            }
            $count_2 ++;
        }
        $count_1 ++;
    }
    if ( $error > 0 ) # die if errors
    {
        print STDERR "$Pname: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }
    return;
} # ValidateCFGorDie

# THIS IS CALLED DURING CONFIGUATION PARSE - NOT OTHERWISE
# the subfolder given, if not the empty string, must be
# a subfolder of the associated tag folder (the one to
# protect).  E.g:
#     if   "/tags" is the folder to be protected then
#     then "/tags/<whatever>" is acceptable, but
#          "/foobar/<whatever>" is NOT
# The subfolder specification must truly be a subfolder
# of the associated folder to be protected.
sub ValidateSubFolderOrDie
{
    my $progn = shift;   # name of this script
    my $pFold = shift;   # folder name of tag to protect
    my $globc = shift;   # the subfolder "glob" string/path
    my $cfile = shift;   # config file
    my $lline = shift;   # current config file line
    my $p_Var = shift;   # config variable for the tag
    my $s_Var = shift;   # config variable for the sub folder
    my $dbglvl = shift;
    my $leftP; # left part
    my $right; # right part
    local $_;

    # a BLANK regex means that the tag folder does not allow _any_
    # project names, hey that's ok!  if so there is no need to test
    if ( $globc ne "" )
    {
        $leftP = $globc; $leftP =~ s@(${pFold})(.+)@$1@;
        $right = $globc; $right =~ s@(${pFold})(.+)@$2@;
        if ( $pFold ne $leftP )
        {
            print STDERR "$progn: configuration file:\n";
            print STDERR "        \"$cfile\"\n";
            print STDERR "$progn: is misconfigured at approximately line $lline.\n";
            print STDERR "$progn: the variable=value pair:\n";
            print STDERR "        $p_Var=\"$pFold\"\n";
            print STDERR "$progn: the variable=value pair:\n";
            print STDERR "        $s_Var=\"$globc\"\n";
            print STDERR "$progn: are out of synchronization.\n";
            print STDERR "$progn: a correct variable=value pair would be, for example:\n";
            print STDERR "        $s_Var=\"$pFold/*\"\n";
            print STDERR "$progn: the $p_Var value (path) MUST be the\n";
            print STDERR "$progn: the first path in $s_Var (it must start with that path)\n";
            print STDERR "$progn: unless $s_Var is the empty string (path).\n";
            print STDERR "$progn: ABORTING - tell the subversion administrator.\n";
            exit $exitFatalErr;
        }

        # clean up the subfolder "glob" (or it could be a literal path, we still clean it up)
        $_ = $right;         # the "backslash" is not allowed, it can only lead to problems!
        print STDERR "ValidateSubFolderOrDie: initial       \$_=$_\n" if ( $dbglvl > 8 );
        s@\\@@g;             # remove all backslash chars - not allowed
        print STDERR "ValidateSubFolderOrDie: rm backslash  \$_=$_\n" if ( $dbglvl > 8 );
        s@/+@/@g;            # change multiple //* chars into just one /
        print STDERR "ValidateSubFolderOrDie: rm single sep \$_=$_\n" if ( $dbglvl > 8 );
        while ( m@/\.\//@ )  # /../ changed to / in a loop
        {
            s@/\.\./@/@g;    # remove it
            s@/+@/@g;        # don't see how this could happen, but safety first
        print STDERR "ValidateSubFolderOrDie: in clean loop \$_=$_\n" if ( $dbglvl > 8 );
        }
        print STDERR "ValidateSubFolderOrDie: done          \$_=$_\n" if ( $dbglvl > 8 );
        $globc = $leftP . $_;         # the "backslash" is not allowed, it can only lead to problems!
    }
    print STDERR "ValidateSubFolderOrDie: returning $globc\n" if ( $dbglvl > 7 );
    return $globc; # possible modified (cleaned up)
} # ValidateSubFolderOrDie

sub ZeroOneOrN # return 0, 1, or any N
{
    local $_ = shift;
    my $rvalue;
    if ( m/^[0-9]+$/ )
    {
        s@^0*@@;
        s@^$@0@;
        $rvalue = int($_);
    }
    elsif ( m/^on$/i     ) { $rvalue = 1; }
    elsif ( m/^yes$/i    ) { $rvalue = 1; }
    elsif ( m/^true$/i   ) { $rvalue = 1; }
    elsif ( m/^enable$/i ) { $rvalue = 1; }
    else                   { $rvalue = 0; } # default to zero
    return $rvalue;
} # ZeroOneOrN

# this last line is need by perl
1;
