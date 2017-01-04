package SVNPlus::TagProtect;

use 5.010000;
use strict;
use warnings;

our @ISA = qw();

our $VERSION = '3.18.0';

# Preloaded methods go here.
use autodie;                              # automatic die if file fails to open
use Sysadm::Install qw(tap);              # to shell out for svnlook/svn

# "glob" strings without hitting the file system
use Text::Glob qw(match_glob glob_to_regex glob_to_regex_string);
use POSIX qw(strftime);                   # time stamps
use Cwd 'abs_path';                       # to be able to get full path to this file

# FATAL ERROR
my $exitFatalErr = 1;

# USER ASKED FOR HELP, PARSE, etc, from command line
my $exitSuccess = 0;

################################################################################
# ENTER: HARD DEFAULTS FOR CONFIG FILE, VARIABLES SET IN THE CONFIG FILE, etc.
# hard default                        actual variable      variable looked for
# if not in config                  init w/useless value   in configuration file
# CLI (currently 11 variables for command line parse - some can't be set (auto set)

#  1
#  --debug/-d/--debug=N/-dN
#     $CLIC_DEBUG                         # CLI command line debug level
#     $CLIF_DEBUG                         # debug level from config file parse, if any
my $VAR_H_DEBUG = "DEBUG";                # looked for in config file
my $DEF_H_DEBUG = 0;                      # default - some low level debug can only be seen by
                                          # changing the default, here, to a high level!
#  2
#  not cli setable, but config setable, or default=/usr/bin/svnlook
#      $CLISVNLOOK                        # CLI, path to svnlook program
my $VAR_SVNLOOK = "SVNLOOK";              # variable looked for in config file
my $DEF_SVNLOOK = "/usr/bin/svnlook";     # default value if not in config;

#  3
#  not cli setable, but config setable, or default=/usr/bin/svn
#      $CLISVNPATH                        # CLI, path to svn program
my $VAR_SVNPATH = "SVNPATH";              # variable looked for in config file
my $DEF_SVNPATH = "/usr/bin/svn";         # default value if not in config

#  4
# command line can set, or default=0
#  --build/-b
#      $CLIBLDPREC                        # CLI, output PERL pre-build config from config file

#  5
# command line can set, or default
#  --parse/-p
#      $CLIJUSTCFG                        # CLI, just parse the config and exit

#  6
# command line can set, or default is STDOUT
#  --input=<file>/-i<file>
#      $CLI_INFILE                        # CLI, name of input file overrides default config files

#  7
# command line can set, or default is STDOUT
#  --output=<file>/-o<file>
#      $CLIOUTFILE                        # CLI, name of output file, receives config output

#  8
# command line can set, or default from PERL library name
#  --revert/-r
#      $CLIDUMP_PL                        # CLI, reverse the above, PERL prebuild to config file

#  9
#  not cli setable, this is auto detected
#      $CLIRUNNING                        # CLI, flag running from command line?

# 10
#  not cli setable, set by subversion when in PRODUCTION, or "useless" default for debug
#      $CLISVN_TID                        # CLI, subversion transaction key

# 11
#  not cli setable, set by subversion when in PRODUCTION, or sensible default for debug
#      $CLISVNREPO                        # CLI, path to svn repository

# CFG (currently 5 keys)
#  1
my $VAR_TAGDIRE = "PROTECTED_PARENT";     # variable looked for in config file
my $DEF_TAGDIRE = "/tags";                # default value if not in config
my $TAGpKEY     = "$VAR_TAGDIRE";         # CFG key, key for this N-Tuple, must be a real path

#  2
# these (missing lines)
# not needed for line number
my $LINEKEY = "ProtectLineNo";            # CFG key, line number in the config file of this tag directory

#  3
my $VAR_SUBDIRE = "PROTECTED_PRJDIRS";    # variable looked for in config file
my $DEF_SUBDIRE = "${DEF_TAGDIRE}/*";     # default value if not in config
my $SUBfKEY     = "$VAR_SUBDIRE";         # CFG key, subdirectories will be "globbed"

#  4
my $VAR_MAKESUB = "PRJDIR_CREATORS";      # variable looked for in config file
my $DEF_MAKESUB = "*";                    # default value if not in config
my $MAKEKEY     = "$VAR_MAKESUB";         # CFG key, those who can create sub directories

#  5
my $VAR_NAME_AF = "ARCHIVE_DIRECTORY";    # variable looked for in config file
my $DEF_NAME_AF = "Archive";              # default value if not in config
my $NAMEKEY     = "$VAR_NAME_AF";         # CFG key, directory name of the archive directory(s)

# LEAVE: HARD DEFAULTS FOR CONFIG FILE, VARIABLES SET IN THE CONFIG FILE, etc
################################################################################

################################################################################
# ENTER: VARIABLES WITH FILE SCOPE all with sensible defaults
my $Tuple_CNT  = 0;                       # count of keys, for building a N-Tuple key
my $Tuple_STR  = "Config_Tuple";          # string part of a N-Tuple key
my $CLIBLD_DEF = 0;                       # 1 if --generate on command line
my $CLIBLDPREC = 0;                       # 1 if --build on command line
my $CLIRUNNING = 0;                       # 1 if we know we are running CLI
my $CLICONFIGF = "";                      # name of config file, defaulted below - but it can be changed
my $CLIDUMP_PL = 0;                       # 1 if --dump on command line => revert precompiled config file
my $CLIC_DEBUG = $DEF_H_DEBUG;            # N if --debug
my $CLIF_DEBUG = -1;                      # -1 => no debug level gotten from configuration file parse
my $CLIJUSTCFG = 0;                       # 1 if --parse on command line
my $CLI_INFILE = "";                      # file to read input from (depending on command line options)
my $CLIOUTFILE = "";                      # file to write output to (depending on command line options)
my $CLIPRECONF = "";                      # name of precompiled config file, defaulted below, it can be changed
my $CLISVNREPO = "";                      # path to repo -- this from subversion or dummied up
my $CLISVN_TID = "";                      # transaction id -- this from subversion or dummied up
my $CLISVNLOOK = $DEF_SVNLOOK;            # path to svnlook, can be changed in config file
my $CLISVNPATH = $DEF_SVNPATH;            # path to svn, can be changed in config file

my $PROGNAME;                             # program name
my $PROGDIRE;                             # program directory, usually ends with "hooks"

# this _must_ be "our" (not "my") because of reading from pre-compiled file
our %cfgHofH = ();                        # hash of hashes - holds all configs
my @CommitData;                           # svnlook output split into an array of files/directories
                                          # unless in command line mode

# LEAVE: VARIABLES WITH FILE SCOPE all with sensible defaults
################################################################################

#{ ENTER #######################################################################
############################## PROTECTED/PRIVATE ###############################
############################# SUPPORT SUBROUTINES ##############################
###############################################################################{
my $returnTF = sub {                      # returnTF
    my $zeroOne = shift;
    if ( $zeroOne ) { return 'TRUE'; }
    return 'FALSE';
};    # returnTF

my $IsUnderProtection = sub {             # IsUnderProtection
    my $pDir     = shift;                 # protected (parent) directories
    my $artifact = shift;                 # to be added
    my $leftside;                         # left side of $artifact, length of $pDir
    my $r;                                # returned value
    local $_;

    if ( $pDir eq "/" )
    {
        # THIS IS CODED THIS WAY, HERE INSTEAD OF BELOW, IN CASE "/" IS DISALLOWED IN FUTURE (perhaps it should be?)
        $r = 1;                  # this will always match everything!
        print STDERR "IsUnderProtection: protected directories is \"/\" it always matches everything\n" if ( $CLIC_DEBUG > 7 );
    }
    else
    {
        # the protected (parent) directory is given literally like: "/tags"
        # but can contain who knows what (even meta chars to be taken as is)
        $_ = int( length( $pDir ) );
        $leftside = substr( $artifact, 0, $_ );
        if ( $CLIC_DEBUG > 7 )
        {
            print STDERR 'IsUnderProtection: $artifact:  ' . $artifact . "\n" if ( $CLIC_DEBUG > 7 );
            print STDERR 'IsUnderProtection: checking exact match (' . $leftside . ' eq ' . $pDir . ") ";
        }
        if ( $leftside eq $pDir )
        {
            print STDERR "YES\n" if ( $CLIC_DEBUG > 7 );
            $r = 1;
        }
        else
        {
            print STDERR "NO\n" if ( $CLIC_DEBUG > 7 );
            $r = 0;
        }
    }
    print STDERR "IsUnderProtection: return $r\n" if ( $CLIC_DEBUG > 7 );
    return $r;
};    # IsUnderProtection

my $AddingArchiveDir = sub {    # AddingArchiveDir
    my $parent   = shift;       # this does NOT end with SLASH, protected "parent" directory
    my $allsub   = shift;       # this does NOT end with SLASH, subdirectories (as a path containing all the "parts" of the path)
    my $archive  = shift;       # name of the archive directory(s) for this configuration N-Tuple
    my $artifact = shift;       # may or may not end with SLASH - indicates files or directory
    my $r        = 0;           # assume failure
    my $sstr;                   # subdirectory string - used for parsing $allsub into the @suball array
    my @suball;                 # hold the parts of $allsub, $allsub can be a glob
    my $glob;                   # build up from the $allsub string split apart into @suball
    my $dir = 0;                # assume artifact is a file
    local $_;

    $_ = $artifact;
    $dir = 1 if ( m@/$@ );

    if ( $dir )
    {
        $sstr = $allsub;            # start with the subdirectory config value
        print STDERR "AddingArchiveDir: \$sstr=$sstr\n" if ( $CLIC_DEBUG > 7 );
        $sstr =~ s@^${parent}@@;    # remove the parent with FIRST SLASH
        @suball = split( '/', $sstr );

        # walk the longest path to the shortest path
        while ( @suball > 0 )
        {
            $glob = $parent . join( "/", @suball );
            $glob .= "/" if ( !( $glob =~ '/$' ) );
            $glob .= $archive . "/";
            if ( match_glob( $glob, $artifact ) )
            {
                print STDERR "AddingArchiveDir: match_glob( $glob, $artifact ) = YES\n" if ( $CLIC_DEBUG > 7 );
                $r = 1;             # we have a match
                last;
            }
            elsif ( $CLIC_DEBUG > 7 )
            {
                print STDERR "AddingArchiveDir: match_glob( $glob, $artifact ) = NO\n" if ( $CLIC_DEBUG > 7 );
            }
            pop @suball;
        }
    }
    elsif ( $CLIC_DEBUG > 7 )
    {
        print STDERR "AddingArchiveDir: $artifact is a FILE\n";
    }

    print STDERR "AddingArchiveDir: return $r\t\$artifact=$artifact\n" if ( $CLIC_DEBUG > 7 );
    return $r;
};    # AddingArchiveDir

my $AddingToArchiveDir = sub {    # AddingToArchiveDir
    my $parent   = shift;         # this does NOT end with SLASH, protected "parent" directory
    my $allsub   = shift;         # this does NOT end with SLASH, subdirectories (as a path containing all the "parts" of the path)
    my $archive  = shift;         # name of the archive directory(s) for this configuration N-Tuple
    my $artifact = shift;         # may or may not end with SLASH - indicates files or directory
    my $r        = 0;             # assume failure
    my $sstr;                     # subdirectory string - used for parsing $allsub into the @suball array
    my @suball;                   # hold the parts of $allsub, $allsub can be a glob
    my $glob;                     # build up from the $allsub string split apart into @suball
    my $dir = 0;                  # assume artifact is a file
    local $_;

    $_ = $artifact;
    $dir = 1 if ( m@/$@ );

    if ( $dir )
    {
        $sstr = $allsub;          # start with the subdirectory config value
        print STDERR "AddingToArchiveDir: \$sstr=$sstr\n" if ( $CLIC_DEBUG > 5 );
        $sstr =~ s@^${parent}@@;    # remove the parent with FIRST SLASH
        @suball = split( '/', $sstr );

        # walk the longest path to the shortest path
        while ( @suball > 0 )
        {
            $glob = $parent . join( "/", @suball );
            $glob .= "/" if ( !( $glob =~ '/$' ) );
            $glob .= $archive . "/?*/";
            if ( match_glob( $glob, $artifact ) )
            {
                print STDERR "AddingToArchiveDir: ( match_glob( $glob, $artifact ) = YES\n" if ( $CLIC_DEBUG > 5 );
                $r = 1;             # we have a match
                last;
            }
            elsif ( $CLIC_DEBUG > 5 )
            {
                print STDERR "AddingToArchiveDir: ( match_glob( $glob, $artifact ) = NO\n" if ( $CLIC_DEBUG > 5 );
            }
            pop @suball;
        }
    }
    elsif ( $CLIC_DEBUG > 5 )
    {
        print STDERR "AddingToArchiveDir: $artifact is a FILE\n";
    }

    print STDERR "AddingToArchiveDir: return $r\t\$artifact=$artifact\n" if ( $CLIC_DEBUG > 5 );
    return $r;
};    # AddingToArchiveDir

my $AddingSubDir = sub {    # AddingSubDir
    my $parent   = shift;    # this does NOT end with SLASH, protected "parent" directory
    my $allsub   = shift;    # this does NOT end with SLASH, subdirectory(s) (as a path containing all the "parts" of the path)
    my $artifact = shift;    # may or may not end with SLASH - indicates files or directory
    my $r        = 0;        # assume failure
    my $sstr;                # subdirectory string - used for parsing $allsub into the @suball array
    my @suball;              # hold the parts of $allsub, $allsub can be a glob
    my $glob;                # build up from the $allsub string split apart into @suball
    my $dir = 0;             # assume artifact is a file
    local $_;

    $_ = $artifact;
    $dir = 1 if ( m@/$@ );

    if ( $dir )
    {
        $sstr = $allsub;     # start with the subdirectory config value
        print STDERR "AddingSubDir: \$sstr=$sstr\n" if ( $CLIC_DEBUG > 5 );
        $sstr =~ s@^${parent}@@;    # remove the parent with FIRST SLASH
        @suball = split( '/', $sstr );

        # walk the longest path to the shortest path
        while ( @suball > 0 )
        {
            $glob = $parent . join( "/", @suball );
            $glob .= "/" if ( !( $glob =~ '/$' ) );
            if ( match_glob( $glob, $artifact ) )
            {
                print STDERR "AddingSubDir: ( match_glob( $glob, $artifact ) = YES\n" if ( $CLIC_DEBUG > 5 );
                $r = 1;             # we have a match
                last;
            }
            elsif ( $CLIC_DEBUG > 5 )
            {
                print STDERR "AddingSubDir: ( match_glob( $glob, $artifact ) = NO\n" if ( $CLIC_DEBUG > 5 );
            }
            pop @suball;
        }
    }
    elsif ( $CLIC_DEBUG > 5 )
    {
        print STDERR "AddingSubDir: $artifact is a FILE\n";
    }

    print STDERR "AddingSubDir: return $r\t\$artifact=$artifact\n" if ( $CLIC_DEBUG > 5 );
    return $r;
};    # AddingSubDir

# each artifact has to be tested to see if it is under protection
# which means looping through all configurations
my $ArtifactUnderProtectedDir = sub {    # ArtifactUnderProtectedDir
    my $artifact = shift;
    my $parent;                          # protected directory
    my $tupleKey;
    my $returnKey   = "";
    my $isProtected = 0;                 # assume not protected

    for $tupleKey ( keys %{ cfgHofH } )
    {
        $parent = $cfgHofH{ $tupleKey }{ $TAGpKEY };
        if ( &$IsUnderProtection( $parent, $artifact ) == 1 )
        {
            $returnKey   = $tupleKey;
            $isProtected = 1;
            last;
        }
    }
    return ( $isProtected, $returnKey );
};    # ArtifactUnderProtectedDir

my $Authorized = sub {    # Authorized
    my $author   = shift;    # committer of this change
    my $authOK   = shift;    # those allowed to commit
    my $artifact = shift;    # what requires authorization
    my $msgwords = shift;    # description of what is being added
    my $isauth   = 0;        # assume failure
    my @auth;
    my $user;

    if ( $authOK eq '*' )
    {
        print STDERR "Authorized: allow because authorization is the '*' character\n" if ( $CLIC_DEBUG > 5 );
        $isauth = 1;
    }
    elsif ( $author eq '' )
    {
        print STDERR "$PROGNAME: commit failed due to being unable to authenticate.\n";
        print STDERR "$PROGNAME: the author of this commit is BLANK, apparently there is\n";
        print STDERR "$PROGNAME: no authentication required by subversion (apache or html server).\n";
        print STDERR "$PROGNAME: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }
    else
    {
        @auth = split( ",", $authOK );
        for $user ( @auth )
        {
            $user =~ s@\s+@@g;    # remove all spaces, user names can not have spaces in them
            if ( $user eq $author )
            {
                print STDERR "Authorized: allow because author matches: $user\n" if ( $CLIC_DEBUG > 5 );
                $isauth = 1;
                last;
            }
            elsif ( $user eq '*' )
            {
                print STDERR "Authorized: allow because one of users is the '*' character\n" if ( $CLIC_DEBUG > 5 );
                $isauth = 1;
                last;
            }
        }
    }
    if ( $isauth == 0 )
    {
        print STDERR "$PROGNAME: failed on: $artifact\n";
        print STDERR "$PROGNAME: authorization failed, you cannot \"$msgwords\"\n";
        print STDERR "$PROGNAME: commiter \"$author\" does not have authorization\n";
    }
    return $isauth;
};    # Authorized

my $FixPath = sub {    # FixPath  # trim trailing / chars as need be from the config file
    local $_ = shift;    # path to be "fixed"
    my $no1stSlash   = shift;
    my $addLastSlash = shift;
    if ( $_ ne "" and $_ ne "/" )
    {
        s/\/+$//;        # strip any trailing "/" chars
        if ( $_ eq "" )
        {
            $_ = "/";
        }
        elsif ( $no1stSlash )
        {
            s@^/@@;
        }
        $_ .= "/" if ( $addLastSlash );
    }
    return $_;
};    # FixPath

my $FmtStr = sub {    # FmtStr # create a format string used when generating a config file
    my $l = 0;
    my $r = 0;
    my $f = "";
    $l = length( $VAR_H_DEBUG );
    $r = $l if ( $l > $r );
    $l = length( $VAR_SVNLOOK );
    $r = $l if ( $l > $r );
    $l = length( $VAR_SVNPATH );
    $r = $l if ( $l > $r );
    $l = length( $VAR_TAGDIRE );
    $r = $l if ( $l > $r );
    $l = length( $VAR_SUBDIRE );
    $r = $l if ( $l > $r );
    $l = length( $VAR_MAKESUB );
    $r = $l if ( $l > $r );
    $l = length( $VAR_NAME_AF );
    $r = $l if ( $l > $r );
    $f = '%-' . $r . "s";
    return $f;
};    # FmtStr

my $PrtStr = sub {    # PrtStr # string '$s' returned formatted when generating a config file
    my $s = shift;
    my $f = &$FmtStr();
    my $r = sprintf( $f, $s );
    return $r;
};    # PrtStr

my $GenTupleKey = sub {    # GenTupleKey
    my $keyStr = shift;
    my $keyCnt = shift;
    my $key;
    $key = $keyStr . sprintf( "_%03d", $keyCnt );    # build the key for the outer hash
    return $key;
};    # GenTupleKey

my $GetMax = sub {
    my $l = shift;    # left
    my $r = shift;    # right
    return $l if ( $l > $r );
    return $r;
};    # GetMax

# THIS IS CALLED DURING CONFIGUATION PARSE - NOT OTHERWISE
# the subdirectory given, if not the empty string, must be
# a subdirectory of the associated tag directory (the one
# to protect).  E.g:
#     if   "/tags" is the directory to be protected then
#     then "/tags/<whatever>" is acceptable, but
#          "/foobar/<whatever>" is NOT
# The subdirectory specification must truly be a subdirectory
# of the associated directory to be protected.
my $ValidateSubDirOrDie = sub {    #  ValidateSubDirOrDie
    my $pDire = shift;             # directory name of tag to protect
    my $globc = shift;             # the subdirectory "glob" string/path
    my $lline = shift;             # current config file line

    my $leftP;                     # left part
    my $right;                     # right part
    local $_;

    # a BLANK regex means that the tag directory does not allow _any_
    # project names, hey that's ok!  if so there is no need to test
    if ( $globc ne "" )
    {
        $leftP = $globc;
        $leftP =~ s@(${pDire})(.+)@$1@;
        $right = $globc;
        $right =~ s@(${pDire})(.+)@$2@;
        if ( $pDire ne $leftP )
        {
            print STDERR "$PROGNAME: configuration file:\n";
            print STDERR "        \"$CLICONFIGF\"\n";
            print STDERR "$PROGNAME: is misconfigured at approximately line $lline.\n";
            print STDERR "$PROGNAME: the variable=value pair:\n";
            print STDERR "        $TAGpKEY=\"$pDire\"\n";
            print STDERR "$PROGNAME: the variable=value pair:\n";
            print STDERR "        $SUBfKEY=\"$globc\"\n";
            print STDERR "$PROGNAME: are out of synchronization.\n";
            print STDERR "$PROGNAME: a correct variable=value pair would be, for example:\n";
            print STDERR "        $SUBfKEY=\"$pDire/*\"\n";
            print STDERR "$PROGNAME: the $TAGpKEY value (path) MUST be the\n";
            print STDERR "$PROGNAME: the first path in $SUBfKEY (it must start with that path)\n";
            print STDERR "$PROGNAME: unless $SUBfKEY is the empty string (path).\n";
            print STDERR "$PROGNAME: ABORTING - tell the subversion administrator.\n";
            exit $exitFatalErr;
        }

        # clean up the subdirectory "glob" (or it could be a literal path, we still clean it up)
        $_ = $right;    # the "backslash" is not allowed, it can only lead to problems!
        print STDERR "ValidateSubDirOrDie: initial       \$_=$_\n" if ( $CLIC_DEBUG > 5 );
        s@\\@@g;        # remove all backslash chars - not allowed
        print STDERR "ValidateSubDirOrDie: rm backslash  \$_=$_\n" if ( $CLIC_DEBUG > 5 );
        s@/+@/@g;       # change multiple //* chars into just one /
        print STDERR "ValidateSubDirOrDie: rm single sep \$_=$_\n" if ( $CLIC_DEBUG > 5 );
        while ( m@/\.\//@ )    # /../ changed to / in a loop
        {
            s@/\.\./@/@g;      # remove it
            s@/+@/@g;          # don't see how this could happen, but safety first
            print STDERR "ValidateSubDirOrDie: in clean loop \$_=$_\n" if ( $CLIC_DEBUG > 5 );
        }
        print STDERR "ValidateSubDirOrDie: done          \$_=$_\n" if ( $CLIC_DEBUG > 5 );
        $globc = $leftP . $_;    # the "backslash" is not allowed, it can only lead to problems!
    }
    print STDERR "ValidateSubDirOrDie: return $globc\n" if ( $CLIC_DEBUG > 5 );
    return $globc;               # possible modified (cleaned up)
};    # ValidateSubDirOrDie

my $LoadCFGTuple = sub {    # LoadCFGTuple  # put an N-Tuple into the Hash of hashes
                            # this is what this subroutine "loads", i.e. the 1st is given and
                            # we default the next 3 from the 3 above if they are not there
    my $inHashRef = shift;  # a reference to the "inner" hash
    my $key;                # used to build the key from the string and the number

    # the outer most hash, named %cfgHofH, will load (copy) the above hash (not the reference)
    # along with the information needed to construct the key needed to push the above hash into
    # it.  Got that?

    # check that incoming (inner) hash has a directory in it to be protected
    if (    ( !exists $inHashRef->{ $NAMEKEY } )
         || ( !exists $inHashRef->{ $MAKEKEY } )
         || ( !exists $inHashRef->{ $TAGpKEY } )
         || ( !exists $inHashRef->{ $LINEKEY } )
         || ( !exists $inHashRef->{ $SUBfKEY } ) )
    {
        # give it bogus value if it has no value
        $inHashRef->{ $LINEKEY } = 0 if ( !exists $inHashRef->{ $LINEKEY } );

        print STDERR "$PROGNAME: See configuration file: $CLICONFIGF\n";
        print STDERR "$PROGNAME: The value of $VAR_TAGDIRE does not exist for the configuration set.\n"
          if ( !exists $inHashRef->{ $TAGpKEY } );
        print STDERR "$PROGNAME: The value of $VAR_SUBDIRE does not exist for the configuration set!\n"
          if ( !exists $inHashRef->{ $SUBfKEY } );
        print STDERR "$PROGNAME: The value of $VAR_NAME_AF does not exist for the configuration set!\n"
          if ( !exists $inHashRef->{ $NAMEKEY } );
        print STDERR "$PROGNAME: The value of $VAR_MAKESUB does not exist for the configuration set!\n"
          if ( !exists $inHashRef->{ $MAKEKEY } );
        print STDERR "$PROGNAME: Around line number: $inHashRef->{$LINEKEY}\n";
        print STDERR "$PROGNAME: Failure in subroutine LoadCFGTuple.\n";
        print STDERR "$PROGNAME: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }
    elsif ( $inHashRef->{ $TAGpKEY } eq "" )
    {
        # give it bogus value if it has no value
        $inHashRef->{ $LINEKEY } = 0 if ( !exists $inHashRef->{ $LINEKEY } );
        print STDERR "$PROGNAME: See configuration file: $CLICONFIGF\n";
        print STDERR "$PROGNAME: The value of $VAR_TAGDIRE is blank.\n";
        print STDERR "$PROGNAME: Around line number: $inHashRef->{$LINEKEY}\n";
        print STDERR "$PROGNAME: Failure in subroutine LoadCFGTuple.\n";
        print STDERR "$PROGNAME: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }

    # get new key for outer hash
    $key = &$GenTupleKey( $Tuple_STR, $Tuple_CNT );
    $Tuple_CNT++;

    # insist that this new configuration plays by the rules
    $inHashRef->{ $SUBfKEY } = &$ValidateSubDirOrDie( $inHashRef->{ $TAGpKEY }, $inHashRef->{ $SUBfKEY }, $inHashRef->{ $LINEKEY } );

    $cfgHofH{ $key } = { %$inHashRef };    # this allocates (copies) inner hash

    return;                                # return no value
};    # LoadCFGTuple # put an N-Tuple into the Hash of hashes

my $PrintDefaultConfigOptionallyExit = sub {    # PrintDefaultConfigOptionallyExit
    my $print_exit = shift;
    my $filename   = shift;
    my $ohandle    = shift;
    my $output;
    my $q = '"';
    my $str;

    if ( $filename eq "" )
    {
        $output   = *STDOUT;
        $filename = "STDOUT";
    }
    else
    {
        $output = $ohandle;    # caller already opened it
    }
    if ( $CLIC_DEBUG > 0 )
    {
        if ( $print_exit )
        {
            print STDERR "PrintDefaultConfigOptionallyExit: output default header.\n";
        }
        else
        {
            print STDERR "PrintDefaultConfigOptionallyExit: output default configuration file to: $filename\n";
        }
    }
    print $output "#\n";
    print $output "#  The parsing script will build an 'N-Tuple' from each\n";
    print $output "#  ${VAR_TAGDIRE} variable.\n";
    print $output "#\n";
    print $output "# Recognized variable/value pairs are:\n";
    print $output "#   These are for debugging and subversion\n";
    print $output "#          ${VAR_H_DEBUG}\t\t= N\n";
    print $output "#          ${VAR_SVNPATH}\t\t= path to svn\n";
    print $output "#          ${VAR_SVNLOOK}\t\t= path to svnlook\n";
    print $output "#   These make up an N-Tuple\n";
    print $output "#          ${VAR_TAGDIRE}\t\t= /<path>\n";
    print $output "#    e.g.: ${VAR_SUBDIRE}\t= /<path>/*\n";
    print $output "# or e.g.: ${VAR_SUBDIRE}\t= /<path>/*/*\n";
    print $output "#          ${VAR_MAKESUB}\t= '*' or '<user>, <user>, ...'\n";
    print $output "#          ${VAR_NAME_AF}\t= <name>\n";
    print $output "\n";
    print $output "### These should be first\n";
    $str = &$PrtStr( $VAR_H_DEBUG );
    print $output $str . " = $DEF_H_DEBUG\n";
    $str = &$PrtStr( $VAR_SVNPATH );
    print $output $str . " = ${q}$DEF_SVNPATH${q}\n";
    $str = &$PrtStr( $VAR_SVNLOOK );
    print $output $str . " = ${q}$DEF_SVNLOOK${q}\n";
    print $output "\n";
    print $output "### These comprise an N-Tuple, can be repeated as many times as wanted,\n";
    print $output "### but each ${VAR_TAGDIRE} value must be unique.   It is not allowed to\n";
    print $output "### try to configure the same directory twice (or more)!\n";

    if ( $print_exit == 1 )
    {
        $str = &$PrtStr( $VAR_TAGDIRE );
        print $output $str . " = ${q}$DEF_TAGDIRE${q}\n";
        $str = &$PrtStr( $VAR_SUBDIRE );
        print $output $str . " = ${q}$DEF_SUBDIRE${q}\n";
        $str = &$PrtStr( $VAR_MAKESUB );
        print $output $str . " = ${q}$DEF_MAKESUB${q}\n";
        $str = &$PrtStr( $VAR_NAME_AF );
        print $output $str . " = ${q}$DEF_NAME_AF${q}\n";
        print STDERR "PrintDefaultConfigOptionallyExit: exit successful after generate default config file.\n" if ( $CLIC_DEBUG > 0 );
        exit $exitSuccess;    # only exit if doing the whole thing
    }
};    # PrintDefaultConfigOptionallyExit

my $PrintUsageAndExit = sub {    # PrintUsageAndExit # output and exit
    my $look = $CLISVNLOOK;
    $look =~ s@.*/@@;
    $look =~ s@.*\\@@;

    my $svn = $CLISVNPATH;
    $svn =~ s@.*/@@;
    $svn =~ s@.*\\@@;

    print STDOUT "\n";
    print STDOUT "usage: $PROGNAME repo-name transaction-id  - Normal usage under Subversion.\n";
    print STDOUT "OR:    $PROGNAME --help                    - Get this printout.\n";
    print STDOUT "OR:    $PROGNAME [--debug=N] [options]     - configuration testing and debugging.\n";
    print STDOUT "\n";
    print STDOUT "    THIS SCRIPT IS A HOOK FOR SUBVERSION AND IS NOT RUN FROM THE COMMAND\n";
    print STDOUT "    LINE DURING PRODUCTION USAGE.\n";
    print STDOUT "\n";
    print STDOUT "    The required arguments, repo-name and transaction-id, are\n";
    print STDOUT "    provided by subversion.  This subversion hook uses:\n";
    print STDOUT "        '$look'\n";
    print STDOUT '    the path of which can be configured and defaults to: ' . "'" . $CLISVNLOOK . "'\n";
    print STDOUT "    and '$svn'\n";
    print STDOUT '    the path of which can be configured and defaults to: ' . "'" . $CLISVNPATH . "'\n";
    print STDOUT "\n";
    print STDOUT "    It uses the configuration file:\n";
    print STDOUT "        $CLICONFIGF\n";
    print STDOUT "    If it exists, this \"precompiled\" file will take precedence:\n";
    print STDOUT "        $CLIPRECONF\n";
    print STDOUT "    and the configuration file will not be read.\n";
    print STDOUT "\n";
    print STDOUT "    When invoked from the command line it will accept these additional\n";
    print STDOUT "    options, there is no way you can give these in PRODUCTION while running\n";
    print STDOUT "    under subversion.\n";
    print STDOUT "    --help            | -h      Show usage information and exit.\n";
    print STDOUT "\n";
    print STDOUT "    --debug[=n]       | -d[n]   Increment or set the debug value.  If given this\n";
    print STDOUT "                                command line option should be first.\n";
    print STDOUT "\n";
    print STDOUT "    --generate        | -g      Generate a default configuration file with\n";
    print STDOUT "                                comments and  write it to standard output.\n";
    print STDOUT "\n";
    print STDOUT "    --parse           | -p      Parse  the  configuration file then exit.\n";
    print STDOUT "                                Errors found in the configuration will be printed\n";
    print STDOUT "                                to standard error.  If there are no errors you will\n";
    print STDOUT "                                get no output unless debug is greater than zero(0).\n";
    print STDOUT "\n";
    print STDOUT "    --build           | -b      Build a \"precompiled\" configuration file with\n";
    print STDOUT "                                comments from the configuration file and write\n";
    print STDOUT "                                it to standard output. This speeds up reading\n";
    print STDOUT "                                the configuration in PRODUCTION but is only needed\n";
    print STDOUT "                                by sites with a large large number of configurations,\n";
    print STDOUT "                                say 20 or more, your mileage may vary - and only if\n";
    print STDOUT "                                the server is old and slow. If a precompiled\n";
    print STDOUT "                                configuration exists it will be read and the regular\n";
    print STDOUT "                                regular configuration file will be ignored.\n";
    print STDOUT "\n";
    print STDOUT "    --revert        | -r        Opposite of, --build, write to standard output a\n";
    print STDOUT "                                configuration file from a previously built\n";
    print STDOUT "                                \"precompiled\" configuration file.\n";
    print STDOUT "\n";
    print STDOUT "    --input=file    | -ifile    Input from \"file\", or output to \"file\", these options\n";
    print STDOUT "    --output=file   | -ofile    are used to name an alternate configuration file or an\n";
    print STDOUT "                                alternate pre-compiled configuration file.\n";
    print STDOUT "\n";
    print STDOUT "    --version       | -v        Output the version and exit.\n";
    print STDOUT "\n";
    print STDOUT "\n";
    print STDOUT "NOTE: a typical command line usage for debugging purposes would look\n";
    print STDOUT "      like this\n";
    print STDOUT "        ./$PROGNAME --debug=N [options] < /dev/null\n";
    print STDOUT "\n";
    print STDOUT "$PROGNAME: " . $VERSION . "\n";
    print STDOUT "\n";
    exit $exitSuccess;
};    # PrintUsageAndExit

my $PrintVersionAndExit = sub {    # PrintVersionAndExit
    print STDOUT $VERSION . "\n";
    exit $exitSuccess;
};    # PrintVersionAndExit

# cannot determine what the commit does - one or more artifacts cannot be correctly parsed
# this is called when everything else fails, increase debug for more information
my $SayImpossible = sub {    # SayImpossible
    print STDERR "$PROGNAME: commit failed, re: UNKNOWN!\n";
    print STDERR "$PROGNAME: it appears this commit does not modify, add, or delete anything!\n";
    return 0;
};    # SayImpossible

my $SayNoDelete = sub {    # SayNoDelete
    my $what = shift;
    print STDERR "$PROGNAME: commit failed, delete of protected directories is not allowed!\n";
    print STDERR "$PROGNAME: commit failed on: $what\n";
    return 0;
};    # SayNoDelete

my $SvnGetAuthor = sub {    # SvnGetAuthor
    my @tapCmd;             # array to hold output
    my $svnErrors;          # STDERR of command SVNLOOK - any errors
    my $svnAuthor;          # STDOUT of command SVNLOOK - creator
    my $svnExit;            # exit value of command SVNLOOK
    my $what = "author";

    @tapCmd = ( $CLISVNLOOK, "--transaction", $CLISVN_TID, $what, $CLISVNREPO, );
    print STDERR 'SvnGetAuthor: tap' . " " . join( " ", @tapCmd ) . "\n" if ( $CLIC_DEBUG > 5 );
    ( $svnAuthor, $svnErrors, $svnExit ) = tap @tapCmd;
    chop( $svnAuthor );
    if ( $CLIC_DEBUG > 5 )
    {
        if ( $CLIC_DEBUG > 5 )
        {
            print STDERR "SvnGetAuthor: \$svnExit=  >>$svnExit<<\n";
            print STDERR "SvnGetAuthor: \$svnErrors=>>$svnErrors<<\n";
        }
        print STDERR "SvnGetAuthor: \$svnAuthor=>>$svnAuthor<<\n";
    }
    if ( $svnExit )
    {
        print STDERR "$PROGNAME: \"$CLISVNLOOK\" failed to get \"$what\" (exit=$svnExit), re: $svnErrors\n";
        print STDERR "$PROGNAME: command: >>tap " . join( " ", @tapCmd ) . "\n";
        print STDERR "$PROGNAME: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }
    print STDERR "SvnGetAuthor: return \"$svnAuthor\"\n" if ( $CLIC_DEBUG > 5 );
    return $svnAuthor;
};    # SvnGetAuthor

my $SvnGetCommit = sub {    # SvnGetCommit
    my @tapCmd;             # array to hold output
    my $svnErrors;          # STDERR of command SVNLOOK - any errors
    my $svnOutput;          # STDOUT of command SVNLOOK - commit data
    my $svnExit;            # exit value of command SVNLOOK
    my $itmp = 0;           # index into @Changed
    local $_;               # regex'ing
    my $what = "changed";

    @tapCmd = ( $CLISVNLOOK, "--transaction", $CLISVN_TID, $what, $CLISVNREPO, );
    print STDERR 'SvnGetCommit: tap' . " " . join( " ", @tapCmd ) . "\n" if ( $CLIC_DEBUG > 5 );
    ( $svnOutput, $svnErrors, $svnExit ) = tap @tapCmd;
    if ( $CLIC_DEBUG > 5 )
    {
        print STDERR "SvnGetCommit: \$svnExit=  >>$svnExit<<\n";
        print STDERR "SvnGetCommit: \$svnErrors=>>$svnErrors<<\n";
        print STDERR "SvnGetCommit: \$svnOutput=>>\n$svnOutput<<\n";
    }
    if ( $svnExit )
    {
        print STDERR "$PROGNAME: \"$CLISVNLOOK\" failed to get \"$what\" (exit=$svnExit), re: $svnErrors\n";
        print STDERR "$PROGNAME: command: >>tap " . join( " ", @tapCmd ) . "\n";
        print STDERR "$PROGNAME: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }
    @CommitData = split( "\n", $svnOutput );
    if ( $CLIC_DEBUG > 5 )
    {
        foreach $_ ( @CommitData )
        {
            print STDERR "SvnGetCommit BEFORE: CommitData>>$_\n";
        }
    }
    @CommitData = sort @CommitData;    # needed?
    if ( $CLIC_DEBUG > 5 )
    {
        foreach $_ ( @CommitData )
        {
            print STDERR "SvnGetCommit  AFTER: CommitData>>$_\n";
        }
    }
    return @CommitData                 # $svnOutput split into an array of files/directories;
};    # SvnGetCommit

my $SvnGetList = sub {    # SvnGetList
    my $path = shift;     # path to list
    my $full = shift;     # protocol, repo, path
    my @tapCmd;           # array to hold output
    my $svnErrors;        # STDERR of command SVNPATH list - any errors
    my $svnList;          # STDOUT of command SVNPATH list - data
    my $svnExit;          # exit value of command SVNPATH
    my @List;             # $svnList split into an array of files/directories
    local $_;             # regex'ing

    # build the full protocol / repository / path string
    $full = "file://" . $CLISVNREPO . $path;

    @tapCmd = ( $CLISVNPATH, "list", $full );
    print STDERR 'SvnGetList: tap' . " " . join( " ", @tapCmd ) . "\n" if ( $CLIC_DEBUG > 5 );
    ( $svnList, $svnErrors, $svnExit ) = tap @tapCmd;
    if ( $CLIC_DEBUG > 5 )    # "2", not "0" because the array is printed below
    {
        print STDERR "SvnGetList: \$svnExit=  >>$svnExit<<\n";
        print STDERR "SvnGetList: \$svnErrors=>>$svnErrors<<\n";
        print STDERR "SvnGetList: \$svnList=  >>$svnList<<\n";
    }
    if ( $svnExit )
    {
        # is this a true error or simply that the path listed does not exist?
        $_ = $svnErrors;
        if ( !m/non-existent in that revision/ )
        {
            print STDERR "$PROGNAME: \"$CLISVNPATH\" failed to list \"$path\" (exit=$svnExit), re: $svnErrors";
            print STDERR "$PROGNAME: command: >>tap " . join( " ", @tapCmd ) . "\n";
            print STDERR "$PROGNAME: ABORTING - tell the subversion administrator.\n";
            exit $exitFatalErr;
        }
    }
    @List = split( "\n", $svnList );
    print STDERR "SvnGetList: LEAVE: svn list of $full\n" if ( $CLIC_DEBUG > 5 );
    return @List;    # $svnList split into an array of files/directories
};    # SvnGetList

my $TagIsInArchive = sub {    # TagIsInArchive
    my $aTag = shift;         # new artifact, tag that is being created
    my $arch = shift;         # name of archive directory
    my @list;
    my $rvalue = 0;           # returned value, assume not in archive
    my $head;
    my $tail;
    my $path;

    $head = $aTag;
    $head =~ s@/$@@;
    $tail = $head;

    $head =~ s@(.*)/(.*)@$1@;
    $tail =~ s@(.*)/(.*)@$2@;

    $path = $head . "/" . $arch . "/" . $tail;

    @list = &$SvnGetList( $path );
    if ( ( scalar @list ) > 0 ) { $rvalue = 1; }
    return $rvalue;
};    # TagIsInArchive

my $TheAddIsAllowed = sub {    # TheAddIsAllowed
    my $author = shift;        # committer of this change
    my $ADDref = shift;        # array reference to the "array of stuff to add"
    my $aDire;                 # archive directory name
    my $aMake;                 # users that can create new project directories
    my $artifact;              # user wants to add
    my $commit = 1;            # assume OK to commit
    my $arrayRef;              # pointer to the inner array
    my $pDire;                 # protected (parent) directory
    my $sDire;                 # subdirectory under $pDire, can be BLANK
    my $tupKey;                # N-Tuple key used to find data in $CFGref
    my $glob;                  # a "glob" pattern to check for matches

    if ( $CLIC_DEBUG > 7 )
    {
        print STDERR "TheAddIsAllowed: ENTER: listing array of N-Tuple keys and the artifact to test with the key\n";
        for $arrayRef ( @{ $ADDref } )
        {
            ( $tupKey, $artifact ) = ( @{ $arrayRef } );
            print STDERR "TheAddIsAllowed: with Configuration key=$tupKey test artifact=$artifact\n";
        }
        print STDERR "TheAddIsAllowed: LEAVE: listing array of N-Tuple keys and the artifact to test with the key\n";
    }
    for $arrayRef ( @{ $ADDref } )    # we know all these are protected and to be added
    {
        ( $tupKey, $artifact ) = ( @{ $arrayRef } );
        $pDire = $cfgHofH{ $tupKey }{ $TAGpKEY };    # protected directory
        $aMake = $cfgHofH{ $tupKey }{ $MAKEKEY };    # authorised to make subdirectories
        $aDire = $cfgHofH{ $tupKey }{ $NAMEKEY };    # archive directory name
        $sDire = $cfgHofH{ $tupKey }{ $SUBfKEY };    # subdirectory name - glob is allowed here

        if ( $CLIC_DEBUG > 6 )
        {
            print STDERR 'TheAddIsAllowed: N-TupleKey:     $tupKey' . "\t= $tupKey\n";
            print STDERR 'TheAddIsAllowed: Commited:       $artifact' . "\t= $artifact\n";
            print STDERR 'TheAddIsAllowed: Parent Dir:     $pDire' . "\t\t= $pDire\n";
            print STDERR 'TheAddIsAllowed: Sub "glob" Dir: $sDire' . "\t\t= $sDire\n";
            print STDERR 'TheAddIsAllowed: Archive Dir:    $aDire' . "\t\t= $aDire\n";
            print STDERR 'TheAddIsAllowed: Authorized:     $aMake' . "\t\t= $aMake\n";
        }

        # IN ORDER TO ENSURE CORRECTLY FIGURING OUT WHAT THE USER IS DOING TEST IN THIS ORDER:
        # 1) attempting to add to the Archive directory?
        # 2) attempting to add to a tag?
        # 3) attempting to add _the_ Archive directory itself?
        # 4) attempting to add a project directory?
        # 5) attempting to add the protected directory _itself_ ?
        # 6) attempting to add a directory? <= this should never happen, above takes care of it
        # 7) attempting to add a file that is not part of a tag?

        # 1) attempting to add to the Archive?
        print STDERR "TheAddIsAllowed: TESTING -> ATTEMPT TO ADD TO AN ARCHIVE DIRECTORY? $artifact\n" if ( $CLIC_DEBUG > 4 );
        if    ( $sDire eq "" and $aDire eq "" ) { $glob = ""; }                               # no subdirectory, no archive directory name
        elsif ( $sDire eq "" and $aDire ne "" ) { $glob = $pDire . '/' . $aDire . "/?*"; }    # no subdirectory, yes archive directory name
        elsif ( $sDire ne "" and $aDire eq "" ) { $glob = ""; }                               # yes subdirectory, not arhive directory name
        elsif ( $sDire ne "" and $aDire ne "" ) { $glob = $sDire . '/' . $aDire . "/?*"; }    # yes subdirectory, yes archive directory name
        if ( $glob ne "" )
        {
            print STDERR 
                'TheAddIsAllowed: if (&$AddingArchiveDir(' . "$pDire, $sDire, $aDire, $artifact) is the test to see if adding to an archive directory\n"
                if ( $CLIC_DEBUG > 6 );
            if ( &$AddingArchiveDir( $pDire, $sDire, $aDire, $artifact ) == 1 )
            {
                print STDERR 'TheAddIsAllowed: $artifact=' . "$artifact IS UNDER AN ARCHIVE DIRECTORY\n" if ( $CLIC_DEBUG > 4 );
                print STDERR "$PROGNAME: you can only move existing tags to an archive directory\n";
                print STDERR "$PROGNAME: commit failed, you cannot add anything to an existing archive directory!\n";
                print STDERR "$PROGNAME: commit failed on: $artifact\n";
                $commit = 0;
                last;
            }
        }
        print STDERR "TheAddIsAllowed: KEEP TESTING -> NOT ADDING TO AN ARCHIVE DIRECTORY WITH: $artifact\n" if ( $CLIC_DEBUG > 5 );

        # 2) attempting to add to a tag?
        print STDERR "TheAddIsAllowed: TESTING -> ATTEMPT TO ADD A TAG? $artifact\n" if ( $CLIC_DEBUG > 4 );
        if   ( $sDire eq "" ) { $glob = $pDire . "/?*/"; }    # no subdirectory
        else                  { $glob = $sDire . "/?*/"; }
        print STDERR "TheAddIsAllowed: if ( match_glob( $glob, $artifact ) ) is the test to see if adding a new tag\n" if ( $CLIC_DEBUG > 6 );
        if ( match_glob( $glob, $artifact ) )
        {
            print STDERR
              'TheAddIsAllowed: if ( &$TagIsInArchive(' . "$artifact, $aDire) == 1 ) is the test to see if adding to an archive directory\n"
              if ( $CLIC_DEBUG > 6 );
            if ( &$TagIsInArchive( $artifact, $aDire ) == 1 )
            {
                print STDERR
                  "TheAddIsAllowed: stop TESTING -> CANNOT ADD tag that already exists in the archive directory: artifact=$artifact\n"
                  if ( $CLIC_DEBUG > 4 );
                print STDERR "$PROGNAME: you cannot add this tag because it already exists in an archive directory!\n";
                print STDERR "$PROGNAME: commit failed on: $artifact\n";
                $commit = 0;
                last;
            }

            # no problem - we are simply adding a tag
            print STDERR "TheAddIsAllowed: stop TESTING -> THIS IS OK AND IS A NEW TAG artifact=$artifact\n" if ( $CLIC_DEBUG > 4 );
        }
        else
        {
            print STDERR "TheAddIsAllowed: KEEP TESTING -> THIS IS NOT A NEW TAG $artifact\n" if ( $CLIC_DEBUG > 5 );

            # 3) attempting to add the _Archive directory_ itself?
            print STDERR "TheAddIsAllowed: TESTING -> ATTEMPT TO ADD THE ARCHIVE DIRECTORY ITSELF? artifact=$artifact\n" if ( $CLIC_DEBUG > 4 );
            if ( $aDire ne "" )
            {
                print STDERR
                  'TheAddIsAllowed: if ( &$AddingArchiveDir(' . "$pDire, $sDire, $aDire, $artifact) == 1 ) is the test to see if adding an archive directory\n"
                  if ( $CLIC_DEBUG > 6 );
                if ( &$AddingArchiveDir( $pDire, $sDire, $aDire, $artifact ) == 1 )
                {
                    print STDERR 'TheAddIsAllowed: $artifact=' . "$artifact IS AN ARCHIVE DIRECTORY\n" if ( $CLIC_DEBUG > 4 );
                    $commit = &$Authorized( $author, $aMake, $artifact, 'add an archive directory' );
                    last if ( $commit == 0 );
                    next;
                }
            }
            print STDERR "TheAddIsAllowed: KEEP TESTING -> NOT ADDING THE ARCHIVE DIRECTORY ITSELF WITH artifact=$artifact\n" if ( $CLIC_DEBUG > 5 );

            # 4) attempting to add a project directory?
            print STDERR "TheAddIsAllowed: TESTING -> ATTEMPT TO ADD A SUB DIRECTORY? artifact=$artifact\n" if ( $CLIC_DEBUG > 4 );
            print STDERR
              'TheAddIsAllowed: if ( &$AddingSubDir( ' . "$pDire, $sDire, $artifact) == 1 ) is the test to see if adding a sub directory\n"
              if ( $CLIC_DEBUG > 6 );
            if ( &$AddingSubDir( $pDire, $sDire, $artifact ) == 1 )
            {
                print STDERR
                  "TheAddIsAllowed: stop TESTING -> THIS IS A NEW PROJECT SUB DIRECTORY, calling Authorized artifact=$artifact\n"
                  if ( $CLIC_DEBUG > 4 );
                $commit = &$Authorized( $author, $aMake, $artifact, 'add a project (or sub) directory' );
                last if ( $commit == 0 );
                next;
            }
            print STDERR "TheAddIsAllowed: KEEP TESTING -> NOT ATTEMPT TO ADD A SUB DIRECTORY WITH artifact=$artifact\n" if ( $CLIC_DEBUG > 5 );

            # 5) attempting to add the protected directory _itself_ ?
            print STDERR "TheAddIsAllowed: TESTING -> ATTEMPT TO ADD THE PROTECTED DIRECTORY ITSELF? artifact=$artifact\n" if ( $CLIC_DEBUG > 4 );
            print STDERR 'TheAddIsAllowed: if ( ' . "\"$pDire/\" eq $artifact ) is the test to see if adding a sub directory\n" if ( $CLIC_DEBUG > 6 );
            if ( "$pDire/" eq $artifact )    # trying to add the parent directory itself
            {
                print STDERR
                  "TheAddIsAllowed: stop TESTING -> THIS IS A THE PROTECTED DIRECTORY, calling Authorized artifact=$artifact\n"
                  if ( $CLIC_DEBUG > 4 );
                $commit = &$Authorized( $author, $aMake, $artifact, 'create the protected directory' );
                last if ( $commit == 0 );
                next;
            }
            else                             # attempting to add a file instead of a tag
            {
                print STDERR
                  "TheAddIsAllowed: stop TESTING -> CANNOT ADD ARBITRARY DIRECTORY OR FILE TO A PROTECTED DIRECTORY artifact=$artifact\n"
                  if ( $CLIC_DEBUG > 4 );
                print STDERR "$PROGNAME: you can only only add new tags\n";
                if ( $artifact =~ m@/$@ )
                {
                    # 6) attempting to add a directory? <= this should never happen, above takes care of it
                    print STDERR "$PROGNAME: commit failed, you cannot add a directory to a protected directory!\n";
                }
                else
                {
                    # 7) attempting to add a file that is not part of a tag?
                    print STDERR "$PROGNAME: commit failed, you cannot add a file to a protected directory!\n";
                }
                print STDERR "$PROGNAME: commit failed on: $artifact\n";
                $commit = 0;
                last;
            }
        }
    }
    print STDERR "TheAddIsAllowed: return " . &$returnTF( $commit ) . "\n" if ( $CLIC_DEBUG > 3 );
    return $commit;
};    # TheAddIsAllowed

my $TheMoveIsAllowed = sub {    # TheMoveIsAllowed
    my $what   = shift;         # committer of this change
    my $author = shift;         # committer of this change
    my $ADDref = shift;         # reference to the array of stuff to add
    my $DELref = shift;         # reference to the array of stuff to delete
    my $addKey;                 # N-Tuple key from the "add" array
    my $artifact;               # path from the "add" array
    my $artifactNoArch;         # path from the "add" array with next to last directory with "Arhive name" removed
    my $addRef;                 # reference for add array
    my $archive;                # name of an archive directory for this N-Tuple
    my $check1st;               # path to check before putting a path into @justAdditions
    my $commit = 1;             # assume OK to commit
    my $count;                  # of elements in @justAdditions
    my $delNdx;                 # found the thing in the del array this is in the add array?
    my $delKey;                 # N-Tuple key from the "del" array
    my $delPath;                # path from the "del" array
    my $delRef;                 # reference for the del array
    my $justAdd;                # true if the path in the add array has no matching path in the del array
    my $ok2add;                 # ok to put a path into @justAdditions because it is not there already
    my $ref;                    # reference into @justAdditions
    my $stmp;                   # tmp string
    my @justAdditions;          # array of additions found that do not have matching delete/move
    my @tmp;                    # used to load the @justAdditions array with data

    # walk each of the artifacts to be added
    for $addRef ( @{ $ADDref } )
    {
        ( $addKey, $artifact ) = ( @{ $addRef } );
        print STDERR "TheMoveIsAllowed: add cfgkey is: $addKey, add artifact is: $artifact\n" if ( $CLIC_DEBUG > 5 );
        $archive = $cfgHofH{ $addKey }{ $NAMEKEY };
        if ( $archive eq "" )
        {
            print STDERR
              "TheMoveIsAllowed: KEEP TESTING -> no archive directory so this must be a just add condition with artifact: $artifact\n"
              if ( $CLIC_DEBUG > 4 );
            $justAdd = 1;
        }
        else
        {
            $justAdd = 0;
            print STDERR
              "TheMoveIsAllowed: if ( $artifact " . '=~ m@^(.+)/' . "${archive}" . '/([^/]+/)$@' . " ) is the test to see if adding to an archive directory\n"
              if ( $CLIC_DEBUG > 6 );
            if ( $artifact =~ m@^(.+)/${archive}/([^/]+/)$@ )    # does path have "archive directory name" in it as next to last directory
            {
                $artifactNoArch = "$1/$2";
                print STDERR
                  'TheMoveIsAllowed: KEEP TESTING -> does the archive artifact to add have a corresponding tag being deleted, artifact: ' .
                  "$artifact, corresponding: $artifactNoArch\n"
                  if ( $CLIC_DEBUG > 4 );
                $delNdx = -1;                                    # impossible value
                $count  = 0;

                # walk each of the artifacts to be deleted and look to see if the thing added is related to the
                # artifact being deleted by an archive directory name
                for $delRef ( @{ $DELref } )
                {
                    ( $delKey, $delPath ) = ( @{ $delRef } );
                    print STDERR "TheMoveIsAllowed: delete cfgkey is: $delKey, add artifact is: $delPath\n" if ( $CLIC_DEBUG > 5 );
                    if ( $addKey eq $delKey and $artifactNoArch eq $delPath )
                    {
                        $delNdx = $count;
                        if ( $CLIC_DEBUG > 6 )
                        {
                            print STDERR "TheMoveIsAllowed: DEL is moving to Arhive, that's OK\n";
                            print STDERR "TheMoveIsAllowed: ADD KEY  >>$addKey<<\n";
                            print STDERR "TheMoveIsAllowed: DEL KEY  >>$delKey<<\n";
                            print STDERR "TheMoveIsAllowed: ADD PATH >>$artifact<<\n";
                            print STDERR "TheMoveIsAllowed: DEL PATH >>$delPath<<\n";
                        }
                        last;
                    }
                    $count++;
                }
                if ( $delNdx != -1 )    # was the index into the del array found?
                {
                    print STDERR
                      "TheMoveIsAllowed: KEEP TESTING -> remove this artifact from delete array because it is moving to archive directory: $artifact\n"
                      if ( $CLIC_DEBUG > 4 );
                    splice @{ $DELref }, $delNdx, 1;    # ignore any returned value, not needed
                }
                else
                {
                    print STDERR
                      "TheMoveIsAllowed: KEEP TESTING -> the artifact to be added has no corresponding delete from a tag: $artifact\n"
                      if ( $CLIC_DEBUG > 4 );
                }
            }
            else                                        # found a path to add but it does not have "archive directory name" as next to last directory
            {
                print STDERR
                  "TheMoveIsAllowed: KEEP TESTING -> no archive directory match so this is an add condition with artifact: $artifact\n"
                  if ( $CLIC_DEBUG > 4 );
                $justAdd = 1;
            }
        }
        if ( $justAdd )
        {
            print STDERR "TheMoveIsAllowed: KEEP TESTING -> ADDING TO THE ARRAY OF justAdditions: $artifact\n" if ( $CLIC_DEBUG > 3 );
            $ok2add = 1;                                # assume so
            $count  = int( @justAdditions );
            if ( $count > 0 )
            {
                $ref = $justAdditions[$count - 1];
                ( $stmp, $check1st ) = @{ $ref };
                if ( length( $artifact ) >= length( $check1st ) )
                {
                    $ok2add = 0 if ( $artifact =~ $check1st );
                }
            }
            if ( $ok2add )
            {
                @tmp = ( $addKey, $artifact );
                print STDERR "TheMoveIsAllowed: KEEP TESTING - pushing path to array for futher testing, artifact: $artifact\n" if ( $CLIC_DEBUG > 4 );
                push @justAdditions, [@tmp];
            }
            else
            {
                print STDERR "TheMoveIsAllowed: duplicate pathing, not pushing path to array for futher testing, artifact: $artifact\n" if ( $CLIC_DEBUG > 4 );
            }
        }
    }
    if ( $CLIC_DEBUG > 5 )
    {
        print STDERR "TheMoveIsAllowed: LOOP IS DONE\n";
        print STDERR "TheMoveIsAllowed: left over delete count is:  $#$DELref  (0 or more means there are some deletes not part of moves)\n";
        print STDERR "TheMoveIsAllowed: count of just additions is: " . int( @justAdditions ) . "\n";
    }
    if ( !( $#$DELref < 0 ) )    # if there is something left over to be deleted then it is not a "move"
    {
        for $delRef ( @{ $DELref } )
        {
            ( $delKey, $delPath ) = ( @{ $delRef } );
            $commit = &$SayNoDelete( "D   $delPath" );    # always returns 0
            last;                                         # just do one
        }
    }
    elsif ( int( @justAdditions ) > 0 )                   # there is something left over to be added and must check that on its own
    {
        print STDERR "TheMoveIsAllowed: KEEP TESTING - call " . '&TheAddIsAllowed' . " to test addtions not matched with deletions\n" if ( $CLIC_DEBUG > 3 );
        $commit = &$TheAddIsAllowed( $author, \@justAdditions );
    }
    if ( $CLIC_DEBUG > 1 )
    {
        print STDERR "TheMoveIsAllowed: return " . &$returnTF( $commit ) . "\n";
    }
    return $commit;
};    # TheMoveIsAllowed

# if the (now parsed into PERL hash of hash) configuration file has the _identical_
# tag directory to protect repeated (i.e. given more that once) error out and die.
# a tag directory to protect can only be given once.
my $ValidateCFGorDie = sub {    # ValidateCFGorDie
    my $count_1 = 0;            # index for outer count
    my $count_2 = 0;            # index for inner count
    my $key_1;                  # to loop through keys
    my $key_2;                  # to loop through keys
    my $protected_1;            # 1st protected directory to compare with
    my $protected_2;            # 2nd protected directory to compare with
    my $error = 0;              # error count

    while ( $count_1 < $Tuple_CNT )
    {
        $key_1       = &$GenTupleKey( $Tuple_STR, $count_1 );
        $protected_1 = $cfgHofH{ $key_1 }{ $TAGpKEY };          # data to compare
        $count_2     = $count_1 + 1;
        while ( $count_2 < $Tuple_CNT )
        {
            $key_2 = &$GenTupleKey( $Tuple_STR, $count_2 );
            $protected_2 = $cfgHofH{ $key_2 }{ $TAGpKEY };    # data to compare
            if ( $protected_2 eq $protected_1 )
            {
                if ( $error == 0 )
                {
                    print STDERR "$PROGNAME: error with configuration file: \"$CLICONFIGF\"\n";
                }
                else
                {
                    print STDERR "\n";
                }
                print STDERR "$PROGNAME: the protected path \"$protected_1\" is duplicated\n";
                print STDERR "$PROGNAME: lines with duplications are:";
                print STDERR " $cfgHofH{$key_1}{$LINEKEY}";
                print STDERR " and";
                print STDERR " $cfgHofH{$key_2}{$LINEKEY}\n";
                $error = 1;
            }
            $count_2++;
        }
        $count_1++;
    }
    if ( $error > 0 )    # die if errors
    {
        print STDERR "$PROGNAME: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }
    return;
};    # ValidateCFGorDie

my $ZeroOneOrN = sub {    # ZeroOneOrN # return 0, 1, or any N
    local $_ = shift;
    my $rvalue;
    if ( m/^[0-9]+$/ )
    {
        s@^0*@@;
        s@^$@0@;
        $rvalue = int( $_ );
    }
    elsif ( m/^on$/i )     { $rvalue = 1; }
    elsif ( m/^yes$/i )    { $rvalue = 1; }
    elsif ( m/^true$/i )   { $rvalue = 1; }
    elsif ( m/^enable$/i ) { $rvalue = 1; }
    else                   { $rvalue = 0; }    # default to zero
    return $rvalue;
};    # ZeroOneOrN

# THERE IS NO NEED TO OFFSET THE DEBUG LEVEL IN THE COMMAND LINE
# PARSE ROUTINE.  IF IN PRODUCTION YOU DO NOT WANT TO PARSE THE
# COMMAND LINE - IT IS TRIVIAL AND RATHER USELESS.  IN DEBUG AND/OR
# TEST MODE THE DEBUG LEVEL SHOULD BE "low" THRESHOLD NOT OFFSET.
my $ParseCLI = sub {    # ParseCLI # ENTER: parse command line OR DIE
    my $argsRef = shift;     # array reference of command line args
    my $ohandle = *STDOUT;
    my $total;               # count number of requested actions
    my $debugLVL = $CLIC_DEBUG;    # parsing changes, --debug should be first on command line

    # in production the $PROGDIR directory is "</svndir>/hooks",
    # where /svndir is the absolute path to a subversion repository.
    $CLICONFIGF = "$PROGDIRE/$PROGNAME.conf";       # the name of the config file itself
    $CLIPRECONF = "$PROGDIRE/$PROGNAME.conf.pl";    # the name of the "pre-compiled" file

    while ( scalar( @{ $argsRef } ) > 0 )
    {
        print STDERR "ParseCLI: " . scalar( @{ $argsRef } ) . "\t$argsRef->[0]\n" if ( $debugLVL > 4 );

        # ENTER: options that cause an immediate exit after doing their job
        if ( $argsRef->[0] eq '--help' or $argsRef->[0] eq '-h' )
        {
            &$PrintUsageAndExit();
        }
        elsif ( $argsRef->[0] eq '--version' or $argsRef->[0] eq '-v' )
        {
            &$PrintVersionAndExit();
        }

        # LEAVE: options that cause an immediate exit after doing their job

        # ENTER: options that mean we are not running under subversion
        elsif ( $argsRef->[0] eq '--generate' or $argsRef->[0] eq '-g' )
        {
            $CLIBLD_DEF = 1;
            $CLIRUNNING = 1;    # running on comamnd line
        }
        elsif ( $argsRef->[0] eq '--parse' or $argsRef->[0] eq '-p' )
        {
            $CLIJUSTCFG = 1;
            $CLIRUNNING = 1;    # running on comamnd line
        }
        elsif ( $argsRef->[0] eq '--build' or $argsRef->[0] eq '-b' )
        {
            $CLIBLDPREC = 1;
            $CLIRUNNING = 1;    # running on comamnd line
        }
        elsif ( $argsRef->[0] eq '--revert' or $argsRef->[0] eq '-r' )
        {
            $CLIDUMP_PL = 1;
            $CLIRUNNING = 1;    # running on comamnd line
        }
        elsif ( $argsRef->[0] =~ '--input=?+' )
        {
            $CLI_INFILE = $argsRef->[0];
            $CLI_INFILE =~ s@--input=@@;
            $CLIRUNNING = 1;    # running on comamnd line
        }
        elsif ( $argsRef->[0] =~ '-i..*' )
        {
            $CLI_INFILE = $argsRef->[0];
            $CLI_INFILE =~ s@-i@@;
            $CLIRUNNING = 1;    # running on comamnd line
        }
        elsif ( $argsRef->[0] =~ '--output=?+' )
        {
            $CLIOUTFILE = $argsRef->[0];
            $CLIOUTFILE =~ s@--output=@@;
            $CLIRUNNING = 1;    # running on comamnd line
        }
        elsif ( $argsRef->[0] =~ '-o..*' )
        {
            $CLIOUTFILE = $argsRef->[0];
            $CLIOUTFILE =~ s@-o@@;
            $CLIRUNNING = 1;    # running on comamnd line
        }

        elsif ( $argsRef->[0] eq '--nodebug' or $argsRef->[0] eq '-D' )
        {
            $CLIC_DEBUG = 0;
            $debugLVL   = $CLIC_DEBUG;
            $CLIRUNNING = 1;             # running on command line
        }
        elsif ( $argsRef->[0] eq '--debug' or $argsRef->[0] eq '-d' )
        {
            if ( $CLIC_DEBUG <= 0 ) { $CLIC_DEBUG = 1; }
            else                    { $CLIC_DEBUG++; }
            $debugLVL   = $CLIC_DEBUG;
            $CLIRUNNING = 1;             # running on command line
        }
        elsif ( $argsRef->[0] =~ '--debug=[0-9]+' )
        {
            $CLIC_DEBUG = $argsRef->[0];
            $CLIC_DEBUG =~ s@--debug=@@;
            $debugLVL   = $CLIC_DEBUG;
            $CLIRUNNING = 1;             # running on command line
        }
        elsif ( $argsRef->[0] =~ '-d[0-9]+' )
        {
            $CLIC_DEBUG = $argsRef->[0];
            $CLIC_DEBUG =~ s@-d@@;
            $debugLVL   = $CLIC_DEBUG;
            $CLIRUNNING = 1;             # running on command line
        }
        elsif ( $argsRef->[0] =~ '-d=[0-9]+' )
        {
            $CLIC_DEBUG = $argsRef->[0];
            $CLIC_DEBUG =~ s@-d=@@;
            $debugLVL   = $CLIC_DEBUG;
            $CLIRUNNING = 1;             # running on command line
        }

        # LEAVE: options that mean we are not running under subversion

        # ENTER: fatal errors
        elsif ( $argsRef->[0] =~ '^-.*' )
        {
            print STDERR "$PROGNAME: unrecognized command line option: \"$argsRef->[0]\"!\n";
            print STDERR "$PROGNAME: ABORTING!\n";
            exit $exitFatalErr;
        }
        elsif ( scalar( @{ $argsRef } ) != 2 )
        {
            my $aHave = scalar( @{ $argsRef } );
            my $aNeed = 2;
            print STDERR "$PROGNAME: incorrect command line argument count is: $aHave (it should be $aNeed).\n";
            print STDERR "$PROGNAME: perhaps you are not running under subversion?  if so give two dummy command line options.\n";
            print STDERR "$PROGNAME: ABORTING!\n";
            exit $exitFatalErr;
        }

        # LEAVE: fatal errors

        # ENTER: in PRODUCTION, under Subversion, only this block is ever invoked
        else    # two command line arguments left
        {
            $CLISVNREPO = $argsRef->[0];
            shift @{ $argsRef };
            $CLISVN_TID = $argsRef->[0];
        }

        # LEAVE: in PRODUCTION, under Subversion, only this block is ever invoked

        shift @{ $argsRef };
    }

    # if debugging from the command line (because that is the only way
    # this could happen) and the command line did not give the expected
    # subversion command line arguments then give them here so the
    # program can continue, usually just to parse the config file.
    if ( $CLISVNREPO eq "" or $CLISVN_TID eq "" )
    {
        $CLISVNREPO = $PROGDIRE;    # this should now be the path to the repo, unless in development
        $CLISVNREPO =~ s@/hooks$@@;
        $CLISVN_TID = "HEAD";       # this will be useless talking to subversion with svnlook
    }

    # svnRepo path must end with slash
    $_ = $CLISVNREPO;
    $CLISVNREPO .= "/" if ( !m@/$@ );

    $total = $CLIBLD_DEF + $CLIJUSTCFG + $CLIBLDPREC + $CLIDUMP_PL;
    if ( $total > 1 )
    {
        print STDERR "$PROGNAME: too many actions requested!\n";
        print STDERR "$PROGNAME: only one of --generate/--parse/--build/--revert can be given.\n";
        print STDERR "$PROGNAME: ABORTING\n";
        exit $exitFatalErr;
    }

    # produce a default file and exit, if command line requested
    if ( $CLIBLD_DEF )
    {
        &$PrintDefaultConfigOptionallyExit( 1, $CLIOUTFILE, $ohandle );
    }

    print STDERR "ParseCLI: return successful (with no value) after command line parse\n" if ( $debugLVL > 0 );
    return;    # nothing useful can be returned
};    # ParseCLI # LEAVE: parse command line OR DIE

my $ParseCFG = sub {    # ParseCFG # ENTER: parse config file
    my $var     = "";
    my $val     = "";
    my $ch_1st  = "";
    my $chLast  = "";
    my $errors  = 0;
    my $unknown = 0;
    my $itmp    = 0;
    my %cfg     = ();    # "one config" for a protected directory
    my $cfgh;            # open config handle
    my $tKey;            # N-Tuple key
    my $cKey;            # configuration key
    my $spch;            # string of space characters
    my $readPreComp = 0;         # read the precompiled config file
    my $ohandle     = *STDOUT;
    my $str;
    my $localDEBUG = 0;          # offset if in PRODUCTION since config parse is not wanted at low debug levels
    $localDEBUG = -1 if ( $CLIRUNNING == 0 );    # invoke the offset - we are in PRODUCTION

    # do not read the pre-compiled file if we have to build it
    # and do not read the pre-compiled file it we have been asked to parse the configuration file
    if ( $CLIBLDPREC == 0 && $CLIJUSTCFG == 0 )
    {
        $CLIPRECONF = $CLI_INFILE if ( $CLI_INFILE ne "" );
        $readPreComp = 1 if ( -f $CLIPRECONF );    # if the precompiled file exists it will be read in
    }

    if ( $readPreComp )    # if precompiled file, and no command line options to the contrary, just require it and done!
    {
        $itmp = $CLIC_DEBUG;    # hold
        print STDERR "ParseCFG: read precompiled configuration file \"$CLIPRECONF\"\n" if ( $localDEBUG > 1 );
        require "$CLIPRECONF";

        # if the command line has set the debug higher than what it now is then it set back to the command line value
        $CLIF_DEBUG = $CLIC_DEBUG;                             # f_debug is now the actual value gotten from the parse
        $CLIC_DEBUG = &$GetMax( $CLIF_DEBUG, $CLIF_DEBUG );    # use the max value to work with, usually c_debug
    }

    # read the regular config file
    else
    {
        $CLIPRECONF = $CLI_INFILE if ( $CLI_INFILE ne "" );
        if ( !-f $CLICONFIGF )
        {
            print STDERR "ParseCFG: No configuration file \"$CLICONFIGF\"\n" if ( $localDEBUG > 0 );
            print STDERR "$PROGNAME: configuration file \"$CLICONFIGF\" does not exist, aborting.\n";
            print STDERR "$PROGNAME: tell the subversion administrator.\n";
            exit $exitFatalErr;
        }
        else
        {
            print STDERR "ParseCFG: open for read $CLICONFIGF\n" if ( $localDEBUG > 2 );
            open $cfgh, "<", $CLICONFIGF;
            print STDERR "ParseCFG: read $CLICONFIGF\n" if ( $localDEBUG > 1 );
            while ( <$cfgh> )
            {
                ###############################################
                # ENTER: fix and split up the line just read in
                chop;
                s/#.*//;     # remove comments
                s/\s*$//;    # remove trailing white space
                next if $_ eq "";
                print STDERR "ParseCFG: RAW: $_\n" if ( $localDEBUG > 5 );

                if ( !m/=/ )
                {
                    print STDERR "$PROGNAME: configuration file \"$CLICONFIGF\" is misconfigured.\n" if ( $errors == 0 );
                    print STDERR "$PROGNAME: line $. >>$_<< is not a comment and does not contain an equal sign(=) character!\n";
                    $errors++;
                    next;
                }
                $var = $_;    # init to input
                $var =~ s/^\s*//;                        # remove initial white space
                $var =~ s/^([A-Za-z0-9_]+)\s*=.*/$1/;    # remove optional white space and equal sign
                $val = $_;                               # init to input
                $val =~ s/\s*$var\s*=\s*//;              # remove VAR= with optional white space
                $val =~ s/\s*;\s*//;                     # remove trailing ';' and white space, if any
                $ch_1st = $val;
                $ch_1st =~ s/^(.)(.*)(.)\Z/$1/;          # first char
                $chLast = $val;
                $chLast =~ s/^(.)(.*)(.)\Z/$3/;          # last char

                if ( $localDEBUG > 4 )
                {
                    print STDERR "ParseCFG: \$var=\"$var\"\n";
                    print STDERR "ParseCFG: \$val=\"$val\"\n";
                    print STDERR "ParseCFG: \$ch_1st=\"$ch_1st\"\n";
                    print STDERR "ParseCFG: \$chLast=\"$chLast\"\n";
                }
                if ( $ch_1st eq $chLast and $ch_1st eq '"' )
                {                                        # extact dq string
                    $val =~ s/^(.)(.*)(.)\Z/$2/;
                }
                elsif ( $ch_1st eq $chLast and $ch_1st eq "'" )
                {                                        # extact sq string
                    $val =~ s/^(.)(.*)(.)\Z/$2/;
                }
                elsif ( $ch_1st eq '"' or $ch_1st eq "'" )
                {
                    print STDERR "$PROGNAME: configuration file \"$CLICONFIGF\" is misconfigured.\n" if ( $errors == 0 );
                    print STDERR "$PROGNAME: line $. >>$_<< badly quoted!\n";
                    $errors++;
                    next;
                }

                #else                                  { $val is good as it is }

                if ( $localDEBUG > 4 )
                {
                    print STDERR 'ParseCFG: $var="' . "$var" . '"' . "\n";
                    print STDERR 'ParseCFG: $val="' . "$val" . '"' . "\n";
                }

                # LEAVE: fix and split up the line just read in
                ###############################################

                ############################################################
                # ENTER: find the variable and store the value for "GLOBALS"
                if ( $var =~ m/^${VAR_H_DEBUG}\Z/i )
                {
                    $CLIF_DEBUG = &$ZeroOneOrN( $val );
                    $CLIC_DEBUG = &$GetMax( $CLIC_DEBUG, $CLIF_DEBUG );    # use the max value to work with, usually c_debug
                }
                elsif ( $var =~ m/^${VAR_SVNPATH}\Z/i )
                {
                    $ch_1st = $val;
                    $ch_1st =~ s/(.)(.+)/$1/;    # first char
                    if ( $ch_1st ne "/" )
                    {
                        print STDERR "$PROGNAME: configuration file \"$CLICONFIGF\" is misconfigured.\n" if ( $errors == 0 );
                        print STDERR "$PROGNAME: line $. >>$_<< svn path does not start with slash(/)!\n";
                        $errors++;
                        next;
                    }
                    $CLISVNPATH = $val;
                    print STDERR 'ParseCFG: $CLISVNPATH="' . $CLISVNPATH . '"' . "\n" if ( $localDEBUG > 4 );
                }
                elsif ( $var =~ m/^${VAR_SVNLOOK}\Z/i )
                {
                    $ch_1st = $val;
                    $ch_1st =~ s/(.)(.+)/$1/;    # first char
                    if ( $ch_1st ne "/" )
                    {
                        print STDERR "$PROGNAME: configuration file \"$CLICONFIGF\" is misconfigured.\n" if ( $errors == 0 );
                        print STDERR "$PROGNAME: line $. >>$_<< svnlook path does not start with slash(/)!\n";
                        $errors++;
                        next;
                    }
                    $CLISVNLOOK = $val;
                    print STDERR 'ParseCFG: $CLISVNLOOK = "' . $CLISVNLOOK . '"' . "\n" if ( $localDEBUG > 4 );
                }

                # LEAVE: find the variable and store the value for "GLOBALS"
                ############################################################

                ###########################################################
                # ENTER: find the variable and store the value for "N-Tuple"
                # can be given in _any_ order
                # 1) tag directory - cannot be BLANK
                # 2) subdirectories - can be BLANK means NOT ALLOWED
                # 3) subdirectory creators - can be BLANK means NO ONE -- they have made'm all and no more are allowed
                # 4) archive name - can be BLANK means NOT ALLOWED

                # 1) tag directory
                elsif ( $var =~ m/^${VAR_TAGDIRE}\Z/i )
                {
                    # before processing this "$var" (a "protected tag directory" from the config file)
                    # if there is a "protected tag directory" outstanding, load it and its corresponding
                    # configuration values
                    if ( keys %cfg )
                    {
                        $cfg{ $LINEKEY } = $. if ( !exists $cfg{ $LINEKEY } );

                        # we need to load this protected directory and all the
                        # members of the "tuple" into the configuration hash
                        print STDERR "ParseCFG: $TAGpKEY = $cfg{$TAGpKEY}    in the while loop\n" if ( $localDEBUG > 4 );
                        &$LoadCFGTuple( \%cfg, \%cfgHofH );
                        %cfg = ();    # clear it to hold next parse
                    }

                    # now process the just read in "protected tag directory"
                    $ch_1st = $val;
                    $ch_1st =~ s/(.)(.+)/$1/;    # first char
                    if ( $ch_1st ne "/" )
                    {
                        print STDERR "$PROGNAME: configuration file \"$CLICONFIGF\" is misconfigured.\n" if ( $errors == 0 );
                        print STDERR "$PROGNAME: line $. >>$_<< tag directory to protect does not start with slash(/)!\n";
                        $errors++;
                        next;
                    }
                    $cfg{ $TAGpKEY } = &$FixPath( $val, 1, 1 );    # strip first slash, add last slash
                    $cfg{ $LINEKEY } = $.;                         # keep the line this was read in on
                                                                   # safety/security check
                    if ( $cfg{ $TAGpKEY } eq "" )
                    {
                        print STDERR "$PROGNAME: configuration file \"$CLICONFIGF\" is misconfigured.\n" if ( $errors == 0 );
                        print STDERR "$PROGNAME: line $. >>$_<<";
                        print STDERR " (which becomes \"$cfg{$TAGpKEY}\")" if ( $_ ne $cfg{ $TAGpKEY } );
                        print STDERR " cannot be blank!\n";
                        $errors++;
                        next;
                    }
                }

                # 2) subdirectories
                elsif ( $var =~ m/^${VAR_SUBDIRE}\Z/i )
                {
                    $val = &$FixPath( $val, 1, 0 );    # strip 1st slash, can end up being BLANK, that's ok, add last slash
                                                       # if $val is BLANK it means the next tags directory to be protected
                                                       # will have NO subdirectories
                    $cfg{ $SUBfKEY } = $val;
                    if ( $localDEBUG > 4 )
                    {
                        if ( $val eq "" )
                        {
                            print STDERR "ParseCFG: $SUBfKEY = has been cleared, configuration to have no subdirectories.\n";
                        }
                        else
                        {
                            print STDERR "ParseCFG: $SUBfKEY = $cfg{$SUBfKEY}\n";
                        }
                    }
                    $cfg{ $LINEKEY } = $. if ( !exists $cfg{ $LINEKEY } );
                }

                # 3) creators
                elsif ( $var =~ m/^${VAR_MAKESUB}\Z/i )
                {
                    $cfg{ $MAKEKEY } = "$val";    # can be BLANK
                    print STDERR "ParseCFG: $MAKEKEY = $cfg{$MAKEKEY}\n" if ( $localDEBUG > 4 );
                    $cfg{ $LINEKEY } = $. if ( !exists $cfg{ $LINEKEY } );
                }

                # 4) archive name
                elsif ( $var =~ m/^${VAR_NAME_AF}\Z/i )
                {
                    $val = &$FixPath( $val, 0, 0 );    # do not strip 1st slash, can end up being BLANK, that's ok, no last slash
                    $val = $DEF_NAME_AF if ( $val eq "" );    # asked for a reset
                    $val = &$FixPath( $val, 0, 0 );           # won't be BLANK any longer, no last slash
                    if ( $val =~ m@/@ )
                    {
                        print STDERR "$PROGNAME: configuration file \"$CLICONFIGF\" is misconfigured.\n" if ( $errors == 0 );
                        print STDERR "$PROGNAME: line $. >>$_<< archive directory name contains a slash(/) character, that is not allowed!\n";
                        $errors++;
                        next;
                    }
                    $cfg{ $NAMEKEY } = $val;
                    print STDERR "ParseCFG: $NAMEKEY = $cfg{$NAMEKEY}\n" if ( $localDEBUG > 4 );
                    $cfg{ $LINEKEY } = $. if ( !exists $cfg{ $LINEKEY } );
                }

                # the "variable = value" pair is unrecognized
                else
                {
                    # useless to output error message unless debug is enabled, or
                    # we are running from the command line, because otherwise
                    # subversion will just throw them away!
                    if ( $localDEBUG > 0 || $CLIRUNNING > 0 )    # insure STDERR is not useless
                    {
                        if ( $unknown == 0 )
                        {
                            print STDERR "$PROGNAME: useless configuration variables found while parsing\n";
                            print STDERR "$PROGNAME: configuration file: \"$CLICONFIGF\"\n";
                            print STDERR "$PROGNAME: tell the subversion administrator.\n";
                        }
                        print STDERR "$PROGNAME: unrecognized \"variable = value\" on line $.\n";
                        print STDERR "$PROGNAME: variable: \"$var\"\n";
                        print STDERR "$PROGNAME: value:    \"$val\"\n";
                        print STDERR "$PROGNAME: line:     >>$_<<\n";
                        $unknown++;
                    }
                }

                # LEAVE: find the variable and store the value for "N-Tuple"
                # can be given in _any_ order
                # 1) tag directory - cannot be BLANK
                # 2) subdirectory - can be BLANK means NOT ALLOWED
                # 3) subdirectory creators - can be BLANK means NO ONE
                # 4) archive name - can be BLANK means NOT ALLOWED
                ############################################################
            }
            if ( $errors > 0 ) { exit $exitFatalErr; }

            # there can be one left in the "cache"
            if ( keys %cfg )
            {
                print STDERR "ParseCFG: $TAGpKEY = $cfg{$TAGpKEY}    AT END OF WHILE LOOP\n" if ( $localDEBUG > 4 );
                &$LoadCFGTuple( \%cfg, \%cfgHofH );
            }
            close $cfgh;
        }
        &$ValidateCFGorDie();
    }

    # DUMP (revert) THE PRECOMPILED FILE BACK TO A REGULAR CONFIGURATION FILE
    if ( $CLIDUMP_PL > 0 )
    {
        $CLIPRECONF = $CLIOUTFILE if ( $CLIOUTFILE ne "" );
        if ( $readPreComp == 0 )
        {
            print STDERR "$PROGNAME: precompiled configuration file is:\n";
            print STDERR "$PROGNAME:     \"$CLIPRECONF\"\n";
            print STDERR "$PROGNAME: precompiled configuration file was not read in.  Unable to\n";
            print STDERR "$PROGNAME: revert the precompiled configuration file to a (regular) configuration file.\n";
            if ( !-f "$CLIPRECONF" )
            {
                print STDERR "$PROGNAME: it does not exist.\n";
            }
            print STDERR "$PROGNAME: ABORTING!\n";
            exit $exitFatalErr;
        }
        if ( $CLIOUTFILE ne "" )
        {
            print STDERR "ParseCFG: open for write $CLIOUTFILE\n" if ( $localDEBUG > 2 );
            open $ohandle, ">", $CLIOUTFILE;
        }
        if ( $localDEBUG > 1 )
        {
            my $where = "STDOUT";
            $where = $CLIOUTFILE if ( $CLIOUTFILE ne "" );
            print STDERR "ParseCFG: output default pre-compiled configuration file to: $where\n";
        }

        # OUTPUT THE HEADER PART, next function will not exit
        &$PrintDefaultConfigOptionallyExit( 0, $CLIOUTFILE, $ohandle );
        $_ = 0;
        for $tKey ( sort keys %cfgHofH )
        {
            my $q = "'";
            print $ohandle "\n\n" if ( $_ > 0 );
            $_   = 1;
            %cfg = %{ $cfgHofH{ $tKey } };
            $str = &$PrtStr( $VAR_TAGDIRE );
            print $ohandle $str . " = ${q}$cfg{$TAGpKEY}${q}\n";
            $str = &$PrtStr( $VAR_SUBDIRE );
            print $ohandle $str . " = ${q}$cfg{$SUBfKEY}${q}\n";
            $str = &$PrtStr( $VAR_MAKESUB );
            print $ohandle $str . " = ${q}$cfg{$MAKEKEY}${q}\n";
            $str = &$PrtStr( $VAR_NAME_AF );
            print $ohandle $str . " = ${q}$cfg{$NAMEKEY}${q}\n";
        }
        exit $exitSuccess;
    }

    # OUTPUT (build) THE PRECOMPILED CONFIGURATION FILE FROM THE CONFIGURATION FILE JUST READ IN
    elsif ( $CLIBLDPREC > 0 )
    {
        my $where = "STDOUT";
        if ( $CLIOUTFILE ne "" )
        {
            print STDERR "ParseCFG: open for write $CLIOUTFILE\n" if ( $localDEBUG > 2 );
            open $ohandle, ">", $CLIOUTFILE;
        }
        if ( $localDEBUG > 1 )
        {
            $where = $CLIOUTFILE if ( $CLIOUTFILE ne "" );
            print STDERR "ParseCFG: output default pre-compiled configuration file to: $where\n";
        }
        my $Oline  = '%cfgHofH = (';                         # open the HASH of HASH lines
        my $Sline  = '             ';                        # spaces
        my $Cline  = '           );';                        # close the HASH of HASH lines
        my $tStamp = strftime( '%d %B %Y %T', localtime );
        my $user   = $ENV{ 'USER' };
        $user = "UNKNOWN" if ( $user eq "" );

        # output the header
        print $ohandle "#\n";
        print $ohandle "# Pre-compiled configuration file created:\n";
        print $ohandle "#   Date: $tStamp\n";
        print $ohandle "#   From: $CLICONFIGF\n";
        print $ohandle "#   User: $user\n";
        print $ohandle "#\n";
        print $ohandle "\n";

        # output configuration for the 3
        # use "c_debug" here, not "f_debug"
        print $ohandle '$CLIC_DEBUG = 0; # always set to zero by default' . "\n";
        print $ohandle '$CLISVNLOOK = "' . $CLISVNLOOK . '";' . "\n";
        print $ohandle '$CLISVNPATH = "' . $CLISVNPATH . '";' . "\n";
        print $ohandle "\n";

        # output all the N-Tuples
        print $ohandle "$Oline\n";    # open cfgHofH declaration line
        $spch = '        ';
        for $tKey ( sort keys %cfgHofH )
        {
            %cfg = %{ $cfgHofH{ $tKey } };
            print $ohandle $Sline . "'$tKey' => { # started on line " . $cfg{ $LINEKEY } . "\n";    # INITIAL SLASHES PUT BACK
            $spch = $tKey;
            $spch =~ s@.@ @g;                                                                       # $spch is now just spaces
            print $ohandle $Sline . "$spch        '$TAGpKEY' => " . '"/' . $cfg{ $TAGpKEY } . '",' . "\n";
            print $ohandle $Sline . "$spch        '$SUBfKEY' => " . '"/' . $cfg{ $SUBfKEY } . '",' . "\n";
            print $ohandle $Sline . "$spch        '$MAKEKEY' => " . '"' . $cfg{ $MAKEKEY } . '",' . "\n";
            print $ohandle $Sline . "$spch        '$NAMEKEY' => " . '"' . $cfg{ $NAMEKEY } . '",' . "\n";
            print $ohandle $Sline . "$spch      },\n";
        }
        print $ohandle "$Cline\n";   # close cfgHofH declaration line
        print STDERR "ParseCFG: exit $exitSuccess because building of precompiled configuration file is done\n" if ( $localDEBUG > 0 );
        exit $exitSuccess;  # yes, this exits right here, we are done with building the precompiled configuration file
    }

    # OUTPUT THE INTERNAL HASH OF HASHES if debug is high enough
    if ( $localDEBUG > 2 )
    {
        print STDERR "$VAR_H_DEBUG=" . $CLIC_DEBUG . "\n";
        print STDERR "$VAR_SVNLOOK=" . $CLISVNLOOK . "\n";
        print STDERR "$VAR_SVNPATH=" . $CLISVNPATH . "\n";
        print STDERR "\n";
        for $tKey ( sort keys %cfgHofH )
        {
            $spch = $tKey;
            $spch =~ s@.@ @g;    # make a string of spaces
            %cfg = %{ $cfgHofH{ $tKey } };    # load the config hash
            print STDERR "$tKey = {";
            print STDERR "   # started on line $cfg{$LINEKEY} INITIAL SLASHES REMOVED" if ( exists $cfg{ $LINEKEY } );
            print STDERR "\n";
            print STDERR "$spch       $VAR_TAGDIRE=" . '"' . $cfgHofH{ $tKey }{ $TAGpKEY } . '"' . " # literal only\n";
            print STDERR "$spch       $VAR_SUBDIRE=" . '"' . $cfgHofH{ $tKey }{ $SUBfKEY } . '"' . " # literal, a glob, or blank\n";
            print STDERR "$spch       $VAR_MAKESUB=" . '"' . $cfgHofH{ $tKey }{ $MAKEKEY } . '"' . " # authorized committers
                                                                                                     #  - they can create subdirectories/subprojects\n";
            print STDERR "$spch       $VAR_NAME_AF=" . '"' . $cfgHofH{ $tKey }{ $NAMEKEY } . '"' . " # authorised committers only
                                                                                                     #  - name of directory for archiving\n";
            print STDERR "$spch   }\n";
        }
    }
    if ( $CLIJUSTCFG )
    {
        print STDERR "ParseCFG: exit $exitSuccess because just parse configuration file is in effect\n" if ( $localDEBUG > 0 );
        exit $exitSuccess;
    }
    print STDERR "ParseCFG: return successful (with no value) after configuration file parse\n" if ( $localDEBUG > 0 );
    return;    # nothing useful can be returned
};    # ParseCFG # LEAVE: parse config file
################################################################################
############################## PROTECTED/PRIVATE ###############################
############################# SUPPORT SUBROUTINES ##############################
# } LEAVE #####################################################################}

# { ENTER ######################################################################
############################# "PUBLIC" SUBROUTINES #############################
###############################################################################{
sub new
{
    my $class    = shift;
    my $fullname = shift;    # but it might not be!
    my $argsRef  = shift;    # array reference of command line args
    my $self     = {};

    $PROGNAME = &abs_path( $fullname );    # print STDERR "NAME=$NAME\n";
    $PROGDIRE = $PROGNAME;                 # init to finding directory we live in
    $PROGNAME =~ s@.*\\@@;                 # print STDERR "NAME=$NAME\n";
    $PROGNAME =~ s@.*/@@;                  # print STDERR "NAME=$NAME\n";
    $PROGDIRE =~ s@\\[^\\][^\\]*$@@;       # print STDERR "DIRE=$DIRE\n";
    $PROGDIRE =~ s@/[^/][^/]*$@@;          # print STDERR "DIRE=$DIRE\n";

    $argsRef->[0] = "--help" if ( scalar( @{ $argsRef } ) == 0 );

    &$ParseCLI( $argsRef );                # ParseCLI dies if it fails
    &$ParseCFG();                          # ParseCFG dies if it fails
    return bless $self, $class;
}

sub GetDebugLevel { return $CLIC_DEBUG; }

sub SimplyAllow                            # ENTER: determine if we can simply allow this commit or of a protected directory is part of the commit
{
    my $justAllow = 1;                     # assume most commits are not tags
    my $pDir;                              # protected directory
    my $tupleKey;                          # N-Tuple keys found in the configuration ref
    my $artifact;                          # N-Tuple keys found in the configuration ref
    my $isProtected;                       # returned by IsUnderProtection
    local $_;                              # artifact to be committed, changed or whatever

    print STDERR "SimplyAllow: call SvnGetCommit\n" if ( $CLIC_DEBUG > 9 );
    &$SvnGetCommit;

    foreach $_ ( @CommitData )
    {
        print STDERR "SimplyAllow: >>$_<<\n" if ( $CLIC_DEBUG > 8 );
        $artifact = $_;

        $artifact =~ s/^[A-Z_]+\s+//;      # trim first two char(s) and two spaces

        print STDERR "SimplyAllow: >>$artifact<<\n" if ( $CLIC_DEBUG > 7 );

        for $tupleKey ( keys %cfgHofH )
        {
            $pDir = $cfgHofH{ $tupleKey }{ $TAGpKEY };                # protected directory
            $isProtected = &$IsUnderProtection( $pDir, $artifact );
            print STDERR "SimplyAllow: \$isProtected=" . &$returnTF( $isProtected ) . " artifact=$artifact\n" if ( $CLIC_DEBUG > 2 );

            # if the artifact is under a protected directory we cannot simply allow
            if ( &$IsUnderProtection( $pDir, $artifact ) == 1 )
            {
                $justAllow = 0;                                       # nope, we gotta work!
                last;
            }
        }
    }
    if ( $CLIC_DEBUG > 1 )
    {
        print STDERR "SimplyAllow: return " . &$returnTF( $justAllow ) . "\n";
    }
    return $justAllow;
}    # SimplyAllow: LEAVE: determine if we can simply allow this commit or of a protected directory is part of the commit

#### FROM: http://svnbook.red-bean.com/nightly/en/svn.ref.svnlook.c.changed.html
####
####   Name
####    svnlook changed — Print the paths that were changed.
####   Synopsis
####    svnlook changed REPOS_PATH
####   Description
####    Print the paths that were changed in a particular revision or transaction, as well as “svn update-style” status letters in the first two columns:
####    'A ' Item added to repository
####    'D ' Item deleted from repository
####    'U ' File contents changed
####    '_U' Properties of item changed; note the leading underscore
####    'UU' File contents and properties changed
####    Files and directories can be distinguished, as directory paths are displayed with a trailing “/” character.
sub AllowCommit
{
    my $author;      # person making commit
    my $artifact;    # the thing being commmitted
    my $change;      # a D or an A
    my $check1st;    # to avoid duplicates
    my $commit = 1;  # assume OK to commit
    my $count;       # of array elements
    my $isProtected; # is it protected?
    my $ok2add;      # push to the add array?
    my $ref;         # to Nth array element
    my $stmp;        # tmp string
    my $tupleKey;    # key into configuration HoH
    my @add = ();    # things adding
    my @del = ();    # things deleting
    my @tmp;         # used to push an array into @add or @del
    my $element;     # artifact to be committed, changed or whatever
    local $_;        # artifact to be committed, changed or whatever

    if ( $CLIC_DEBUG > 8 )
    {
        print STDERR "AllowCommit: ENTER: listing array of commits\n";
        foreach $_ ( @CommitData )
        {
            print STDERR "AllowCommit: CommitData>>$_\n";
        }
        print STDERR "AllowCommit: LEAVE: listing array of commits\n";
    }
    foreach $element ( @CommitData )
    {
        print STDERR "AllowCommit: >>$element<<\n" if ( $CLIC_DEBUG > 7 );

        # get the next array element, $element
        # use a regexp "split" into 3 parts, the middle part is thrown away (it is just 2 spaces)
        # 1st part is 2 chars loaded to $change
        # 2nd part is 2 spaces, ignored
        # 3rd part is the $artifact
        ( $change, $artifact ) = $element =~ m@^(..)  (.+)@;    # two space chars ignored
        $change =~ s@\s@@g;                                     # remove trailing space, sometimes there is one
        if ( $CLIC_DEBUG > 7 )
        {
            print STDERR 'AllowCommit: $change="' . $change . '"' . "\n";
            print STDERR 'AllowCommit: $artifact="' . $artifact . '"' . "\n";
        }

        ( $isProtected, $tupleKey ) = &$ArtifactUnderProtectedDir( $artifact );
        if ( $CLIC_DEBUG > 3 )
        {
            print STDERR 'AllowCommit: $isProtected  = ' . &$returnTF( $isProtected ) . " \$artifact=$artifact\n";
            print STDERR 'AllowCommit: $tupleKey     = ' . "$tupleKey\n" if ( $CLIC_DEBUG > 4 );
        }

        if ( $isProtected == 1 )
        {
            if ( $change eq 'U' or $change eq '_U' or $change eq 'UU' )
            {
                print STDERR "$PROGNAME: commit failed, modifications to protected directories or files is not allowed!\n";
                print STDERR "$PROGNAME: commit failed on: $_\n";
                $commit = 0;
                last;
            }
            else
            {
                $ok2add = 1;    # assume this path has not been added
                if ( $change eq 'D' )
                {
                    $count = int( @del );
                    if ( $count > 0 )
                    {
                        $ref = $del[$count - 1];
                        ( $stmp, $check1st ) = @{ $ref };
                        if ( length( $artifact ) >= length( $check1st ) )
                        {
                            $ok2add = 0 if ( $artifact =~ $check1st );
                        }
                    }
                }
                elsif ( $change eq 'A' )    # hey that is all it can be
                {
                    $count = int( @add );
                    if ( $count > 0 )
                    {
                        $ref = $add[$count - 1];
                        ( $stmp, $check1st ) = @{ $ref };
                        if ( length( $artifact ) >= length( $check1st ) )
                        {
                            $ok2add = 0 if ( $artifact =~ $check1st );
                        }
                    }
                }
                else
                {    # THIS SHOULD NEVER HAPPEN AND IS HERE IN CASE SUBVERSION CHANGES
                        # this is a safety check - just comment it out to keep on trunking
                    print STDERR "$PROGNAME: commit failed, unknown value for \$change=\"$change\"\n";
                    print STDERR "$PROGNAME: commit failed on: $element\n";
                    $commit = 0;
                    last;
                }
                if ( $ok2add )
                {
                    @tmp = ( $tupleKey, $artifact );
                    if ( $change eq 'D' )
                    {
                        print STDERR "AllowCommit: push to array of artifacts being deleted: artifact=$artifact\n" if ( $CLIC_DEBUG > 3 );
                        push @del, [@tmp];
                    }
                    else
                    {
                        print STDERR "AllowCommit: push to array of artifacts being added: artifact=$artifact\n" if ( $CLIC_DEBUG > 3 );
                        push @add, [@tmp];
                    }
                }
                elsif ( $CLIC_DEBUG > 4 )
                {
                    if ( $change eq 'D' )
                    {
                        print STDERR "AllowCommit: duplicate, do NOT push to array of artifacts being deleted: artifact=$artifact\n";
                    }
                    else
                    {
                        print STDERR "AllowCommit: duplicate, do NOT push to array of artifacts being added: artifact=$artifact\n";
                    }
                }
            }
        }
    }
    if ( $commit == 1 )
    {
        # See if attempting a delete only
        if ( int( @add ) == 0 && int( @del ) != 0 )
        {
            print STDERR "AllowCommit: the protected commit is a DELETE ONLY\n" if ( $CLIC_DEBUG > 3 );
            $commit = &$SayNoDelete( $artifact );    # always returns 0
        }

        # See if attempting an add only
        elsif ( int( @add ) != 0 && int( @del ) == 0 )
        {
            $author = &$SvnGetAuthor();
            print STDERR "AllowCommit: the protected commit is an ADD ONLY\n" if ( $CLIC_DEBUG > 3 );
            $commit = &$TheAddIsAllowed( $author, \@add );    # returns 0 or 1
        }

        # See if attempting an add and a delete, only do this if moving a tag to an archive directory
        elsif ( int( @add ) != 0 && int( @del ) != 0 )
        {
            $author = &$SvnGetAuthor();
            print STDERR "AllowCommit: the protected commit has both ADD AND DELETE\n" if ( $CLIC_DEBUG > 3 );
            $commit = &$TheMoveIsAllowed( $element, $author, \@add, \@del );    # returns 0 or 1
        }

        # Not attempting anything! What? That's impossible, something is wrong.
        elsif ( int( @add ) == 0 && int( @del ) == 0 )
        {
            print STDERR "AllowCommit: the protected commit is IMPOSSIPLE\n" if ( $CLIC_DEBUG > 3 );
            $commit = &$SayImpossible();                                        # always returns 0
        }
    }
    if ( $CLIC_DEBUG > 1 )
    {
        print STDERR "AllowCommit: return " . &$returnTF( $commit ) . "\n";
    }
    return $commit;
}    # AllowCommit
################################################################################
############################# "PUBLIC" SUBROUTINES #############################
# } LEAVE #####################################################################}

1;
__END__

=head1 NAME

SVNPlus::TagProtect - Perl extension for Subversion tag protection

=head1 SYNOPSIS

This is a fully functional Subversion "pre-commit" file for deploying this
object.  After installing this module copy/paste this perl code, make the file
executable, then run it with the --generate option to get an initial, default
configuration file.  If you are working with source code this file, "pre-commit",
and the default configuration file "pre-commit.conf" are contained in the
tarball.

  #! /usr/bin/perl -w
  use warnings;
  use strict;
  use SVNPlus::TagProtect;
  
  $_ = $0;
  s@.*/@@;
  my $NAME = $_;
  
  # build the object: it exits if args are invalid
  my $tagprotect = SVNPlus::TagProtect->new( $0, \@ARGV );
  
  if ( $tagprotect->SimplyAllow() )
  {
      # if the commit is ok, because it does impact protected directories,
      # but debug is wanted then this script must exit NON-zero, which
      # causes the commit to fail but the client gets the standard error.
      # A zero exit causes the STDERR to be squashed.  If any "True"
      # errors occured, "SimplyAllow" will have printed them to standard
      # error and would have returned 0.
      if ( $tagprotect->GetDebugLevel > 0 )
      {
          print STDERR
              "$NAME: SimplyAllow succeeded but script exiting 1 (FAIL) because debug is enabled.\n";
          exit 1;
      }
      exit 0;
  }
  
  if ( $tagprotect->AllowCommit() )
  {
      # if the commit is ok, i.e.: it is allowed, but debug is wanted
      # then this script must exit NON-zero, which causes the commit to
      # fail but the client gets the standard error.  A zero exit causes
      # the STDERR to be squashed.    If any "True" errors occurred,
      # "AllowCommit" will have printed them to standard error and would
      # have returned 0.
      if ( $tagprotect->GetDebugLevel > 0 )
      {
          print STDERR
              "$NAME: AllowCommit succeeded but script exiting 1 (FAIL) because debug is enabled.\n";
          exit 1;
      }
      exit 0;
  }
  
  # commit is not allowed, sub "AllowCommit" has already output the reason
  print STDERR "$NAME: exit 1 (FAIL) this is a true prevent commit condition.\n"
    if ( $tagprotect->GetDebugLevel > 0 );
  exit 1;

=head1 DESCRIPTION

THIS SCRIPT IS A hook FOR Subversion AND IS NOT MEANT TO BE RUN FROM
THE COMMAND LINE UNDER NORMAL USAGE.

It would be run from the command line for configuration
testing and configuration debugging. TagProtect provides
immutablity (write once) protection for the /tags directory
of a subversion repository. This is the default protected
directory and everything is configurable.

Subversion requires that this software be invoked with the
name pre-commit.  Installation of this subversion hook is
trivial, simply put pre-commit into the directory named
hooks found under the directory where you have built the
subversion repostitory. Make sure pre-commit is executable
by the owner of the httpd process.

The subversion admistrator - or anyone with write permission
on the subversion installation directory - can change the
configurtion. Below is a complete configuration set with
default values: Debug value and where subversion looks for
programs it needs:

  DEBUG = 0
  SVNPATH = "/usr/bin/svn"
  SVNLOOK = "/usr/bin/svnlook"

The remaining configuration variables comprise an N-Tuple
and this set can be repeated as many times as wanted.

  PROTECTED_PARENT = "/tags"    # a literal path
  PROTECTED_PRJDIRS = "/tags/*" # literal, glob, or blank
  PRJDIR_CREATORS = "*"         # or comma list, or blank
  ARCHIVE_DIRECTORY = "Archive" # directory name

Do not configure directories with trailing slash characters,
if you do they will simply be discarded anyway but to
avoid confusion don't add them. The configuration of the
protected project directories variable, PROTECTED_PRJDIRS,
must start with the exact same path as its associated
protected parent configuration, namely PROTECTED_PARENT. This
is for security. Also for security any instances of /../
(or the like) found in the PROTECTED_PRJDIRS variable will
be discared.

Each TAG_FOLDER value must be unique and two(2) or more of
them cannot be subdirectories of each other. For example:

  PROTECTED_PARENT = "/tags"
  PROTECTED_PARENT = "/tags/foobar"

will not be allowed.

=head1 SEE ALSO

svn(1), svnlook(1), "Version Control with Subversion" at http://svnbook.red-bean.com/

=head1 AUTHOR

Joseph C. Pietras, E<lt>joseph.pietras@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2015 by Joseph C. Pietras

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.16.3 or,
at your option, any later version of Perl 5 you may have available.

=cut
