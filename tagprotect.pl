#! /usr/bin/perl -w
################################################################################
#  Author:      Joseph C. Pietras - Joseph.Pietras@gmail.com
#  License:     GNU GENERAL PUBLIC LICENSE Version 2
#  GitHub:      svn co https://github.com/ossCare/svnPlus
#               git https://github.com/ossCare/svnPlus.git
#  SourceForge: git clone git://git.code.sf.net/p/svnplus/code svnplus-code
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
#### hashes contains only data regarding which subversion "root" direct-    ####
#### ories are protected tag directories and the associated configuration   ####
#### for that "tag" directory.                                              ####
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
# CLI (currently 12 variables for command line parse - some can't be set (auto set)

#  1
#  --debug/-d/--debug=N/-dN
#     $CLIC_DEBUG                       # CLI command line debug level 
#     $CLIF_DEBUG                       # debug level from config file parse, if any
my $CLIF_DEBUG = -1;                    # -1 => no debug level gotten from configuration file parse
my $VAR_H_DEBUG = "DEBUG";              # looked for in config file
my $DEF_H_DEBUG =  0;                   # default - some low level debug can only be seen by
                                        # changing the default, here, to a high level!
#  2
#  not cli setable, but config setable, or default=/usr/bin/svnlook
#      $CLISVNLOOK                      # CLI, path to svnlook program 
my $VAR_SVNLOOK = "SVNLOOK";            # variable looked for in config file
my $DEF_SVNLOOK = "/usr/bin/svnlook";   # default value if not in config;

#  3
#  not cli setable, but config setable, or default=/usr/bin/svn
#      $CLISVNPATH                      # CLI, path to svn program
my $VAR_SVNPATH = "SVNPATH";            # variable looked for in config file
my $DEF_SVNPATH = "/usr/bin/svn";       # default value if not in config

#  4
# command line can set, or default=0
#  --build/-b
#      $CLIBLDPREC                      # CLI, output PERL pre-build config from config file

#  5 & 6
# command line can set, or default from PERL library name
#  --parse[=<file>]/-p[<file>]
#      $CLICONFIGF                      # CLI, name of config file, can change when debugging
#      $CLIJUSTCFG                      # CLI, just parse the config and exit

#  7
# command line can set, or default is STDOUT
#  --output=<file>/-o<file>
#      $CLIOUTFILE                      # CLI, name of output file, receives config output

#  8 & 9
# command line can set, or default from PERL library name
#  --revert[=<file>]/-r[<file>]
#      $CLIPRECONF                      # CLI, name of precompiled config file, can change when debugging
#      $CLIDUMP_PL                      # CLI, reverse the above, PERL prebuild to config file

# 10
#  not cli setable, this is auto detected
#      $CLIRUNNING                      # CLI, flag running from command line?

# 11
#  not cli setable, set by subversion when in PRODUCTION, or "useless" default for debug
#      $CLISVN_TID                      # CLI, subversion transaction key

# 12
#  not cli setable, set by subversion when in PRODUCTION, or sensible default for debug
#      $CLISVNREPO                      # CLI, path to svn repository


# CFG (currently 5 keys)
# 1
my $VAR_TAGDIRE = "PROTECTED_PARENT";   # variable looked for in config file
my $DEF_TAGDIRE = "/tags";              # default value if not in config
my     $TAGpKEY = "$VAR_TAGDIRE";       # CFG key, key for this N-Tuple, must be a real path

# 2
# these (missing lines)
# not needed for line number
my     $LINEKEY = "ProtectLineNo";      # CFG key, line number in the config file of this tag directory

# 3
my $VAR_SUBDIRE = "PROTECTED_PRJDIRS";  # variable looked for in config file
my $DEF_SUBDIRE = "${DEF_TAGDIRE}/*";   # default value if not in config
my     $SUBfKEY = "$VAR_SUBDIRE";       # CFG key, subdirectories will be "globbed"

# 4
my $VAR_MAKESUB = "PRJDIR_CREATORS";    # variable looked for in config file
my $DEF_MAKESUB =  "*";                 # default value if not in config
my     $MAKEKEY = "$VAR_MAKESUB";       # CFG key, those who can create sub directories

# 5
my $VAR_NAME_AF = "ARCHIVE_DIRECTORY";  # variable looked for in config file
my $DEF_NAME_AF =  "Archive";           # default value if not in config
my     $NAMEKEY = "$VAR_NAME_AF";       # CFG key, directory name of the archive directory(s)
# LEAVE: HARD DEFAULTS FOR CONFIG FILE, VARIABLES SET IN THE CONFIG FILE, etc
################################################################################

################################################################################
my $TupleCNT = 0;               # count of N-Tuple keys, for building a N-Tuple key
my $TupleSTR = "Config_Tuple";  # string part of a N-Tuple key
################################################################################

################################################################################
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
my $CLIBLDPREC = 0;             # 1 if --build on command line
my $CLIRUNNING = 0;             # 1 if we know we are running CLI
my $CLICONFIGF = "";            # name of config file, defaulted below - but it can be changed
my $CLIDUMP_PL = 0;             # 1 if --dump on command line => revert precompiled config file
my $CLIC_DEBUG = $DEF_H_DEBUG;  # N if --debug
my $CLIF_DEBUG = -1;            # -1 => no debug level gotten from configuration file parse
my $CLIJUSTCFG = 0;             # 1 if --parse on command line
my $CLIOUTFILE = "";            # file to send output to (depending on command line options)
my $CLIPRECONF = "";            # name of precompiled config file, defaulted below, it can be changed
my $CLISVNREPO = "";            # path to repo -- this from subversion or dummied up
my $CLISVN_TID = "";            # transaction id -- this from subversion or dummied up
my $CLISVNLOOK = $DEF_SVNLOOK;  # path to svnlook, can be changed in config file
my $CLISVNPATH = $DEF_SVNPATH;  # path to svn, can be changed in config file

my $PROGNAME;                   # program name
my $PROGDIRE;                   # program directory, usually ends with "hooks"
# this _must_ be "our" (not "my") because of reading from pre-compiled file
our %cfgHofH = ();              # hash of hashes - holds all configs
my @CommitData;                 # svnlook output split into an array of files/directories
my $dbgOffset = 5;              # set the default high so this function does not output
                                # unless in command line mode
################################################################################

# ENTER ########################################################################
################################################################################
############################# "PUBLIC" SUBROUTINES #############################
################################################################################
###############################################################################{
sub ParseCLI # ENTER: parse command line OR DIE
{
       $PROGNAME = shift; # program name
       $PROGDIRE = shift; # program directory, usually ends with "hooks"
    my $argsRef  = shift; # array reference of command line args
    my $ohandle  = *STDOUT;

    $CLICONFIGF = "$PROGDIRE/tagprotect.conf";     # the name of the config file itself
    $CLIPRECONF = "$PROGDIRE/tagprotect.conf.pl";  # the name of the "pre-compiled" file

    $dbgOffset = 0 if ( scalar( @{ $argsRef } ) != 2 );

    while ( scalar( @{ $argsRef } ) > 0 )
    {
        print STDERR "ParseCLI: " . scalar( @{ $argsRef } ) . "\t$argsRef->[0]\n" if ( $CLIC_DEBUG > 20 );

        # ENTER: options that cause an immediate exit after doing their job
        if    ( $argsRef->[0] eq '--help'          or $argsRef->[0] eq '-h'  )
        {
            &PrintUsageAndExit();
        }
        elsif ( $argsRef->[0] eq '--generate'      or $argsRef->[0] eq '-g'  )
        {
            &PrintDefaultConfigOptionallyExit(0, $ohandle);
        }
        elsif ( $argsRef->[0] eq '--version'       or $argsRef->[0] eq '-v'  )
        {
            &PrintVersionAndExit();
        }
        # LEAVE: options that cause an immediate exit after doing their job

        # ENTER: options that mean we are not running under subversion
        #    ENTER: options that cause a printout then exit
        elsif ( $argsRef->[0] eq '--build'         or $argsRef->[0] eq '-b'  )
        {
            $CLIBLDPREC = 1;
            $CLIRUNNING = 1; # running on comamnd line
            $dbgOffset = 0;
        }
        elsif ( $argsRef->[0] eq '--revert'        or $argsRef->[0] eq '-r'  )
        {
            $CLIDUMP_PL = 1;
            $CLIRUNNING = 1; # running on comamnd line
            $dbgOffset = 0;
        }
        elsif ( $argsRef->[0] =~ '--revert=?+'                          )
        {
            $CLIDUMP_PL = 1;
            $CLIPRECONF = $argsRef->[0]; $CLIPRECONF =~ s@--revert=@@;
            $CLIRUNNING = 1; # running on comamnd line
            $dbgOffset = 0;
        }
        elsif ( $argsRef->[0] =~ '-r..*'                                )
        {
            $CLIDUMP_PL = 1;
            $CLIPRECONF = $argsRef->[0]; $CLIPRECONF =~ s@-r@@;
            $CLIRUNNING = 1; # running on comamnd line
            $dbgOffset = 0;
        }
        elsif ( $argsRef->[0] eq '--parse'         or $argsRef->[0] eq '-p'  )
        {
            $CLIJUSTCFG = 1;
            $CLIRUNNING = 1; # running on comamnd line
            $dbgOffset = 0;
        }
        elsif ( $argsRef->[0] =~ '--parse=?+'                          )
        {
            $CLIJUSTCFG = 1;
            $CLICONFIGF = $argsRef->[0]; $CLICONFIGF =~ s@--parse=@@;
            $CLIRUNNING = 1; # running on command line
            $dbgOffset = 0;
        }
        elsif ( $argsRef->[0] =~ '-p..*'                                )
        {
            $CLIJUSTCFG = 1;
            $CLICONFIGF = $argsRef->[0]; $CLICONFIGF =~ s@-p@@;
            $CLIRUNNING = 1; # running on command line
            $dbgOffset = 0;
        }
        elsif ( $argsRef->[0] =~ '--output=?+'                          )
        {
            $CLIOUTFILE = $argsRef->[0]; $CLIOUTFILE =~ s@--output=@@;
            $CLIRUNNING = 1; # running on comamnd line
            $dbgOffset = 0;
            print STDERR "ParseCLI: write open $CLIOUTFILE\n" if ( $CLIC_DEBUG > 20 );
            open $ohandle, ">", $CLIOUTFILE;
        }
        elsif ( $argsRef->[0] =~ '-o..*'                                )
        {
            $CLIOUTFILE = $argsRef->[0]; $CLIOUTFILE =~ s@-o@@;
            $CLIRUNNING = 1; # running on comamnd line
            $dbgOffset = 0;
            print STDERR "ParseCLI: write open $CLIOUTFILE\n" if ( $CLIC_DEBUG > 20 );
            open $ohandle, ">", $CLIOUTFILE;
        }
        #    LEAVE: options that cause a printout then exit

        elsif ( $argsRef->[0] eq '--nodebug'       or $argsRef->[0] eq '-D'  )
        {
            $CLIC_DEBUG = 0;
            $CLIRUNNING = 1; # running on command line
            $dbgOffset = 0;
        }
        elsif ( $argsRef->[0] eq '--debug'         or $argsRef->[0] eq '-d'  )
        {
            if ( $CLIC_DEBUG <= 0 ) { $CLIC_DEBUG = 1; } else { $CLIC_DEBUG ++; }
            $CLIRUNNING = 1; # running on command line
            $dbgOffset = 0;
        }
        elsif ( $argsRef->[0] =~ '--debug=[0-9]+'                       )
        {
            $CLIC_DEBUG = $argsRef->[0]; $CLIC_DEBUG =~ s@--debug=@@;
            $CLIRUNNING = 1; # running on command line
            $dbgOffset = 0;
        }
        elsif ( $argsRef->[0] =~ '-d[0-9]+'                             )
        {
            $CLIC_DEBUG = $argsRef->[0]; $CLIC_DEBUG =~ s@-d@@;
            $CLIRUNNING = 1; # running on command line
            $dbgOffset = 0;
        }
        elsif ( $argsRef->[0] =~ '-d=[0-9]+'                             )
        {
            $CLIC_DEBUG = $argsRef->[0]; $CLIC_DEBUG =~ s@-d=@@;
            $CLIRUNNING = 1; # running on command line
            $dbgOffset = 0;
        }
        # LEAVE: options that mean we are not running under subversion

        # ENTER: fatal errors
        elsif ( $argsRef->[0] =~ '^-.*'                                 )
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
        else # two command line arguments left
        {
            $CLISVNREPO = $argsRef->[0];
            shift @{ $argsRef };
            $CLISVN_TID = $argsRef->[0];
        }
        # LEAVE: in PRODUCTION, under Subversion, only this block is ever invoked

        shift @{ $argsRef };
    }
    # force debug on if not given on command line
    if ( $CLIJUSTCFG > 0)
    {
        $CLIC_DEBUG = 1 if ( $CLIC_DEBUG <= 0);
    }

    # if debugging from the command line (because that is the only way
    # this could happen) and the command line did not give the expected
    # subversion command line arguments then give them here so the
    # program can continue, usually just to parse the config file.
    if ( $CLISVNREPO eq "" or $CLISVN_TID eq "" )
    {
        $CLISVNREPO =  $PROGDIRE; # this should now be the path to the repo, unless in development
        $CLISVNREPO =~ s@/hooks$@@;
        $CLISVN_TID = "HEAD";  # this will be useless talking to subversion with svnlook
    }

    # svnRepo path must end with slash
    $_ = $CLISVNREPO;
    $CLISVNREPO .= "/" if ( ! m@/$@ );

    print STDERR "ParseCLI: return with no value after successful command line parse\n" if ( $CLIC_DEBUG > 2 );
    return; # nothing useful can be returned
} # LEAVE: parse command line

sub ParseCFG # ENTER: parse config file
{
    my $var     = "";
    my $val     = "";
    my $ch_1st  = "";
    my $chLast  = "";
    my $errors  =  0;
    my $unknown =  0;
    my $itmp    =  0;
    my %cfg     = ();     # "one config" for a protected directory
    my $cfgh;             # open config handle
    my $tKey;             # N-Tuple key
    my $cKey;             # configuration key
    my $spch;             # string of space characters
    my $readPreComp = 0;  # read the precompiled config file
    my $ohandle = *STDOUT;

    # do not read the pre-compiled file if we have to build it
    # and do not read the pre-compiled file it we have been asked to parse the configuation file
    if ( $CLIBLDPREC == 0 && $CLIJUSTCFG == 0 )
    {
        $readPreComp = 1 if ( -f $CLIPRECONF ); # if the precompiled file exists it will be read in
    }

    if ( $readPreComp ) # if precompiled file, and not command line options to the contrary, just require it and done!
    {
        $itmp = $CLIC_DEBUG; # hold
        print STDERR "ParseCFG: read precompiled configuration file \"$CLIPRECONF\"\n" if ( $CLIC_DEBUG > 2 );
        require "$CLIPRECONF";
        # if the command line has set the debug higher than what it now is then it set back to the command line value
        $CLIF_DEBUG = $CLIC_DEBUG; # f_debug is now the actual value gotten from the parse
        $CLIC_DEBUG = &GetMax( $CLIF_DEBUG, $CLIF_DEBUG ); # use the max value to work with, usually c_debug
    }
    # read the regular config file
    else
    {
        if ( ! -f $CLICONFIGF )
        {
            print STDERR "ParseCFG: No configuration file \"$CLICONFIGF\"\n" if ( $CLIC_DEBUG > ($dbgOffset + 20) );
            if ($ALLOW_NO_CONFIG_FILE == 1)
            {
                print STDERR "ParseCFG: NO CONFIG FILE -- ALL COMMITS ALLOWED\n" if ( $CLIC_DEBUG > 0);
            }
            else
            {
                print STDERR "$PROGNAME: configuration file \"$CLICONFIGF\" does not exist, aborting.\n";
                print STDERR "$PROGNAME: tell the subversion administrator.\n";
                exit $exitFatalErr;
            }
        }
        else
        {
            print STDERR "ParseCFG: read $CLICONFIGF\n" if ( $CLIC_DEBUG > 2 );
            open $cfgh, "<", $CLICONFIGF;
            while (<$cfgh>)
            {
                ###############################################
                # ENTER: fix and split up the line just read in
                chop;
                s/#.*//;  # remove comments
                s/\s*$//; # remove trailing white space
                next if $_ eq "";
                print STDERR "ParseCFG: RAW: $_\n" if ( $CLIC_DEBUG > ($dbgOffset + 20) );

                if ( ! m/=/ )
                {
                    print STDERR "$PROGNAME: configuration file \"$CLICONFIGF\" is misconfigured.\n" if ( $errors == 0 );
                    print STDERR "$PROGNAME: line $. >>$_<< is not a comment and does not contain an equal sign(=) character!\n";
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
                if ( $CLIC_DEBUG > ($dbgOffset + 20) )
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
                    print STDERR "$PROGNAME: configuration file \"$CLICONFIGF\" is misconfigured.\n" if ( $errors == 0 );
                    print STDERR "$PROGNAME: line $. >>$_<< badly quoted!\n";
                    $errors ++;
                    next;
                }
                #else                                  { $val is good as it is }

                if ( $CLIC_DEBUG > ($dbgOffset + 20) )
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
                    $CLIF_DEBUG = &ZeroOneOrN($val);
                    $CLIC_DEBUG = &GetMax( $CLIC_DEBUG, $CLIF_DEBUG ); # use the max value to work with, usually c_debug
                }
                elsif ( $var =~ m/^${VAR_SVNPATH}\Z/i       )
                {
                    $ch_1st = $val; $ch_1st =~ s/(.)(.+)/$1/; # first char
                    if ( $ch_1st ne "/" )
                    {
                        print STDERR "$PROGNAME: configuration file \"$CLICONFIGF\" is misconfigured.\n" if ( $errors == 0 );
                        print STDERR "$PROGNAME: line $. >>$_<< svn path does not start with slash(/)!\n";
                        $errors ++;
                        next;
                    }
                    $CLISVNPATH=$val;
                    print STDERR 'ParseCFG: $CLISVNPATH="' . $CLISVNPATH . '"' . "\n" if ( $CLIC_DEBUG > ($dbgOffset + 20) );
                }
                elsif ( $var =~ m/^${VAR_SVNLOOK}\Z/i       )
                {
                    $ch_1st = $val; $ch_1st =~ s/(.)(.+)/$1/; # first char
                    if ( $ch_1st ne "/" )
                    {
                        print STDERR "$PROGNAME: configuration file \"$CLICONFIGF\" is misconfigured.\n" if ( $errors == 0 );
                        print STDERR "$PROGNAME: line $. >>$_<< svnlook path does not start with slash(/)!\n";
                        $errors ++;
                        next;
                    }
                    $CLISVNLOOK=$val;
                    print STDERR 'ParseCFG: $CLISVNLOOK = "' . $CLISVNLOOK . '"' . "\n" if ( $CLIC_DEBUG > ($dbgOffset + 20) );
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
                        $cfg{$LINEKEY} = $. if ( ! exists $cfg{$LINEKEY} );

                        # we need to load this protected directory and all the
                        # members of the "tuple" into the configuration hash
                        print STDERR "ParseCFG: $TAGpKEY = $cfg{$TAGpKEY}    in the while loop\n" if ( $CLIC_DEBUG > ($dbgOffset + 20) );
                        &LoadCFGTuple(\%cfg, \%cfgHofH);
                        %cfg = (); # clear it to hold next parse
                    }

                    # now process the just read in "protected tag directory"
                    $ch_1st = $val; $ch_1st =~ s/(.)(.+)/$1/; # first char
                    if ( $ch_1st ne "/" )
                    {
                        print STDERR "$PROGNAME: configuration file \"$CLICONFIGF\" is misconfigured.\n" if ( $errors == 0 );
                        print STDERR "$PROGNAME: line $. >>$_<< tag directory to protect does not start with slash(/)!\n";
                        $errors ++;
                        next;
                    }
                    $cfg{$TAGpKEY} = &FixPath($val, 1, 1); # strip first slash, add last slash
                    $cfg{$LINEKEY} = $.; # keep the line this was read in on
                    # safety/security check
                    if ( $cfg{$TAGpKEY}    eq ""  )
                    {
                        print STDERR "$PROGNAME: configuration file \"$CLICONFIGF\" is misconfigured.\n" if ( $errors == 0 );
                        print STDERR "$PROGNAME: line $. >>$_<<";
                        print STDERR " (which becomes \"$cfg{$TAGpKEY}\")" if ( $_ ne $cfg{$TAGpKEY} );
                        print STDERR " cannot be blank!\n";
                        $errors ++;
                        next;
                    }
                }

                # 2) subdirectories
                elsif ( $var =~ m/^${VAR_SUBDIRE}\Z/i   )
                {
                    $val = &FixPath($val, 1, 0); # strip 1st slash, can end up being BLANK, that's ok, add last slash
                    # if $val is BLANK it means the next tags directory to be protected
                    # will have NO subdirectories
                    $cfg{$SUBfKEY} = $val;
                    if ( $CLIC_DEBUG > ($dbgOffset + 20) )
                    {
                        if ( $val eq "" )
                        {
                            print STDERR "ParseCFG: $SUBfKEY = has been cleared, configuation to have no subdirectories.\n";
                        }
                        else
                        {
                            print STDERR "ParseCFG: $SUBfKEY = $cfg{$SUBfKEY}\n";
                        }
                    }
                    $cfg{$LINEKEY} = $. if ( ! exists $cfg{$LINEKEY} );
                }

                # 3) creators
                elsif ( $var =~ m/^${VAR_MAKESUB}\Z/i       )
                {
                    $cfg{$MAKEKEY} = "$val"; # can be BLANK
                    print STDERR "ParseCFG: $MAKEKEY = $cfg{$MAKEKEY}\n" if ( $CLIC_DEBUG > ($dbgOffset + 20) );
                    $cfg{$LINEKEY} = $. if ( ! exists $cfg{$LINEKEY} );
                }

                # 4) archive name
                elsif ( $var =~ m/^${VAR_NAME_AF}\Z/i       )
                {
                    $val = &FixPath($val, 0, 0); # do not strip 1st slash, can end up being BLANK, that's ok, no last slash
                    $val = $DEF_NAME_AF if  ( $val eq "" ); # asked for a reset
                    $val = &FixPath($val, 0, 0); # won't be BLANK any longer, no last slash
                    if ( $val =~ m@/@ )
                    {
                        print STDERR "$PROGNAME: configuration file \"$CLICONFIGF\" is misconfigured.\n" if ( $errors == 0 );
                        print STDERR "$PROGNAME: line $. >>$_<< archive directory name contains a slash(/) character, that is not allowed!\n";
                        $errors ++;
                        next;
                    }
                    $cfg{$NAMEKEY} = $val;
                    print STDERR "ParseCFG: $NAMEKEY = $cfg{$NAMEKEY}\n" if ( $CLIC_DEBUG > ($dbgOffset + 20) );
                    $cfg{$LINEKEY} = $. if ( ! exists $cfg{$LINEKEY} );
                }

                # the "variable = value" pair is unrecognized
                else
                {

                    # useless to output error message unless debug is enabled, or
                    # we are running from the command line, because otherwise
                    # subversion will just throw them away!
                    if ( $CLIC_DEBUG > ($dbgOffset + 20) || $CLIRUNNING > 0 )
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
                        $unknown ++;
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
                print STDERR "ParseCFG: $TAGpKEY = $cfg{$TAGpKEY}    AT END OF WHILE LOOP\n" if ( $CLIC_DEBUG > ($dbgOffset + 20) );
                &LoadCFGTuple(\%cfg, \%cfgHofH);
            }
            close $cfgh;
        }
        &ValidateCFGorDie();
    }
    # DUMP (revert) THE PRECOMPILED FILE BACK TO A REGULAR CONFIGURATION FILE
    if ( $CLIDUMP_PL > 0 )
    {
        if ( $readPreComp == 0 )
        {
            print STDERR "$PROGNAME: precompiled configuration file is:\n";
            print STDERR "$PROGNAME:     \"$CLIPRECONF\"\n";
            print STDERR "$PROGNAME: precompiled configuration file was not read in.  Unable to\n";
            print STDERR "$PROGNAME: revert the precompiled configuration file to a (regular) configuration file.\n";
            if ( ! -f "$CLIPRECONF" )
            {
                print STDERR "$PROGNAME: it does not exist.\n";
            }
            print STDERR "$PROGNAME: ABORTING!\n";
            exit $exitFatalErr;
        }
        if ( $CLIOUTFILE ne "" )
        {
            print STDERR "ParseCFG: write open $CLIOUTFILE\n" if ( $CLIC_DEBUG > 20 );
            open $ohandle, ">", $CLIOUTFILE;
        }
        &PrintDefaultConfigOptionallyExit(1, $ohandle); # get the header part of the "revert", will not exit!!
        $_ = 0;
        for $tKey ( sort keys %cfgHofH )
        {
            my $q = "'";
            print $ohandle "\n\n" if ( $_ > 0 );
            $_ = 1;
            %cfg = %{ $cfgHofH{$tKey} };
            print $ohandle &PrtStr($VAR_TAGDIRE) . " = ${q}$cfg{$TAGpKEY}${q}\n";
            print $ohandle &PrtStr($VAR_SUBDIRE) . " = ${q}$cfg{$SUBfKEY}${q}\n";
            print $ohandle &PrtStr($VAR_MAKESUB) . " = ${q}$cfg{$MAKEKEY}${q}\n";
            print $ohandle &PrtStr($VAR_NAME_AF) . " = ${q}$cfg{$NAMEKEY}${q}\n";
        }
        exit $exitUserHelp;
    }
    # OUTPUT (build) THE PRECOMPILED CONFIGURATION FILE FROM THE CONFIGURATION FILE JUST READ IN
    elsif ( $CLIBLDPREC > 0 )
    {
        if ( $CLIOUTFILE ne "" )
        {
            print STDERR "ParseCFG: write open $CLIOUTFILE\n" if ( $CLIC_DEBUG > 20 );
            open $ohandle, ">", $CLIOUTFILE;
        }
        my $Oline  = '%cfgHofH = ('; # open the HASH of HASH lines
        my $Sline  = '             '; # spaces
        my $Cline  = '           );'; # close the HASH of HASH lines
        my $tStamp = strftime('%d %B %Y %T', localtime);
        my $user   = $ENV{'USER'}; $user = "UNKNOWN" if ($user eq "");

        # output the header
        print $ohandle "#\n";
        print $ohandle "# Pre-compiled configuation file created:\n";
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
        print $ohandle "$Oline\n"; # open cfgHofH declaration line
        $spch = '        ';
        for $tKey ( sort keys %cfgHofH )
        {
            %cfg = %{ $cfgHofH{$tKey} };
            print $ohandle $Sline . "'$tKey' => { # started on line " . $cfg{$LINEKEY} . "\n"; # INITIAL SLASHES PUT BACK
            $spch = $tKey;
            $spch =~ s@.@ @g; # $spch is now just spaces
            print $ohandle $Sline . "$spch        '$TAGpKEY' => " . '"/' . $cfg{$TAGpKEY} . '",' . "\n";
            print $ohandle $Sline . "$spch        '$SUBfKEY' => " . '"/' . $cfg{$SUBfKEY} . '",' . "\n";
            print $ohandle $Sline . "$spch        '$MAKEKEY' => " . '"' . $cfg{$MAKEKEY} . '",' . "\n";
            print $ohandle $Sline . "$spch        '$NAMEKEY' => " . '"' . $cfg{$NAMEKEY} . '",' . "\n";
            print $ohandle $Sline . "$spch      },\n";
        }
        print $ohandle "$Cline\n"; # close cfgHofH declaration line
        exit $exitUserHelp; # yes, this exits right here, we are done with building the precompiled configuration file
    }
    # OUTPUT THE INTERNAL HASH OF HASHES if debug is high enough
    if ( $CLIC_DEBUG > ($dbgOffset + 20) )
    {
        print STDERR "$VAR_H_DEBUG=" . $CLIC_DEBUG . "\n";
        print STDERR "$VAR_SVNLOOK=" . $CLISVNLOOK . "\n";
        print STDERR "$VAR_SVNPATH=" . $CLISVNPATH . "\n";
        print STDERR "\n";
        for $tKey ( sort keys %cfgHofH )
        {
            $spch = $tKey;
            $spch =~ s@.@ @g;        # make a string of spaces
            %cfg = %{ $cfgHofH{$tKey} }; # load the config hash
            print STDERR "$tKey = {";
            print STDERR "   # started on line $cfg{$LINEKEY} INITIAL SLASHES REMOVED" if ( exists $cfg{$LINEKEY} );
            print STDERR "\n";
            print STDERR "$spch       $VAR_TAGDIRE=" . '"' . $cfgHofH{$tKey}{$TAGpKEY} . '"' . " # literal only\n";
            print STDERR "$spch       $VAR_SUBDIRE=" . '"' . $cfgHofH{$tKey}{$SUBfKEY} . '"' . " # literal, a glob, or blank\n";
            print STDERR "$spch       $VAR_MAKESUB=" . '"' . $cfgHofH{$tKey}{$MAKEKEY} . '"' . " # authorized committers - can create subdirectories/subprojects\n";
            print STDERR "$spch       $VAR_NAME_AF=" . '"' . $cfgHofH{$tKey}{$NAMEKEY} . '"' . " # authorised committers only - name of directory for archiving\n";
            print STDERR "$spch   }\n";
        }
    }
    if ( $CLIJUSTCFG )
    {
        print STDERR "$PROGNAME: exit because just parse configuration file is in effect\n" if ( $CLIC_DEBUG > 20 );
        exit $exitUserHelp;
    }
    if ( $CLIC_DEBUG > 2 )
    {
        print STDERR "ParseCFG: successful configuration file parse returning debug level=$CLIC_DEBUG\n";
    }
    return $CLIC_DEBUG;
} # ParseCFG # LEAVE: parse config file

sub SimplyAllow # ENTER: determine if we can simply allow this commit or of a protected directory is part of the commit
{
    my $justAllow = 1;    # assume most commits are not tags
    my $pDir;             # protected directory
    my $tupleKey;         # N-Tuple keys found in the configuation ref
    my $artifact;         # N-Tuple keys found in the configuation ref
    my $isProtected;      # returned by IsUnderProtection
    local $_;             # artifact to be committed, changed or whatever

    print STDERR "SimplyAllow: call SvnGetCommit\n" if ( $CLIC_DEBUG > 9);
    &SvnGetCommit;

    foreach $_ ( @CommitData )
    {
        print STDERR "SimplyAllow: >>$_<<\n" if ( $CLIC_DEBUG > 8);
        $artifact = $_;

        $artifact =~ s/^[A-Z_]+\s+//;  # trim first two char(s) and two spaces

        print STDERR "SimplyAllow: >>$artifact<<\n" if ( $CLIC_DEBUG > 7);

        for $tupleKey ( keys %cfgHofH )
        {
            $pDir = $cfgHofH{$tupleKey}{$TAGpKEY};  # protected directory
            $isProtected = &IsUnderProtection($pDir, $artifact);
            print STDERR "SimplyAllow: \$isProtected=" . &returnTF($isProtected) . " artifact=$artifact\n" if ( $CLIC_DEBUG > 2);
            # if the artifact is under a protected directory we cannot simply allow
            if ( &IsUnderProtection($pDir, $artifact) == 1 )
            {
                $justAllow = 0; # nope, we gotta work!
                last;
            }
        }
    }
    if ( $CLIC_DEBUG > 1 )
    {
        print STDERR "SimplyAllow: return " . &returnTF($justAllow) . "\n";
    }
    return $justAllow;
} # SimplyAllow: LEAVE: determine if we can simply allow this commit or of a protected directory is part of the commit

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
    my $author;           # person making commit
    my $artifact;         # the thing being commmitted
    my $change;           # a D or an A
    my $check1st;         # to avoid duplicates
    my $commit = 1;       # assume OK to commit
    my $count;            # of array elements
    my $isProtected;           # is it protected?
    my $ok2add;           # push to the add array?
    my $ref;              # to Nth array element
    my $stmp;             # tmp string
    my $tupleKey;         # key into configuration HoH
    my @add    = ();      # things adding
    my @del    = ();      # things deleting
    my @tmp;              # used to push an array into @add or @del
    my $element;          # artifact to be committed, changed or whatever
    local $_;             # artifact to be committed, changed or whatever

    if ($CLIC_DEBUG > 8)
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
        print STDERR "AllowCommit: >>$element<<\n" if ( $CLIC_DEBUG > 7);
        # get the next array element, $element
        # use a regexp "split" into 3 parts, the middle part is thrown away (it is just 2 spaces)
        # 1st part is 2 chars loaded to $change
        # 2nd part is 2 spaces, ignored
        # 3rd part is the $artifact
        ($change, $artifact) = $element =~ m@^(..)  (.+)@; # two space chars ignored
        $change =~ s@\s@@g; # remove trailing space, sometimes there is one
        if ( $CLIC_DEBUG > 7)
        {
            print STDERR 'AllowCommit: $change="' . $change . '"' . "\n";
            print STDERR 'AllowCommit: $artifact="' . $artifact . '"' . "\n";
        }

        ($isProtected, $tupleKey) = &ArtifactUnderProtectedDir($artifact);
        if ( $CLIC_DEBUG > 3)
        {
            print STDERR 'AllowCommit: $isProtected  = ' . &returnTF($isProtected) . " \$artifact=$artifact\n";
            print STDERR 'AllowCommit: $tupleKey     = ' . "$tupleKey\n" if ( $CLIC_DEBUG > 4);
        }

        if ( $isProtected == 1 )
        {
            if ( $change eq 'U' or $change eq '_U' or $change eq 'UU'  )
            {
                print STDERR "$PROGNAME: commit failed, modifications to protected directories or files is not allowed!\n";
                print STDERR "$PROGNAME: commit failed on: $_\n";
                $commit = 0;
                last;
            }
            else
            {
                $ok2add = 1; # assume this path has not been added
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
                    print STDERR "$PROGNAME: commit failed, unknown value for \$change=\"$change\"\n";
                    print STDERR "$PROGNAME: commit failed on: $element\n";
                    $commit = 0;
                    last;
                }
                if ( $ok2add )
                {
                    @tmp = ($tupleKey, $artifact);
                    if ( $change eq 'D' )
                    {
                        print STDERR "AllowCommit: push to array of artifacts being deleted: artifact=$artifact\n" if ( $CLIC_DEBUG > 3);
                        push @del, [ @tmp ];
                    }
                    else
                    {
                        print STDERR "AllowCommit: push to array of artifacts being added: artifact=$artifact\n" if ( $CLIC_DEBUG > 3 );
                        push @add, [ @tmp ];
                    }
                }
                elsif ( $CLIC_DEBUG > 4)
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
        if    ( int(@add) == 0 && int(@del) != 0 )
        {
            print STDERR "AllowCommit: this commit is a DELETE ONLY\n" if ( $CLIC_DEBUG > 3);
            $commit = &SayNoDelete($artifact); # always returns 0
        }

        # See if attempting an add only
        elsif ( int(@add) != 0 && int(@del) == 0 )
        {
            $author = &SvnGetAuthor();
            print STDERR "AllowCommit: this commit is an ADD ONLY\n" if ( $CLIC_DEBUG > 3);
            $commit = &TheAddIsAllowed($author, \@add); # returns 0 or 1
        }

        # See if attempting an add and a delete, only do this if moving a tag to an archive directory
        elsif ( int(@add) != 0 && int(@del) != 0 )
        {
            $author = &SvnGetAuthor();
            print STDERR "AllowCommit: this commit has both ADD AND DELETE\n" if ( $CLIC_DEBUG > 3);
            $commit = &TheMoveIsAllowed($element, $author, \@add, \@del); # returns 0 or 1
        }

        # Not attempting anything! What? That's impossible, something is wrong.
        elsif ( int(@add) == 0 && int(@del) == 0 )
        {
            print STDERR "AllowCommit: this commit is IMPOSSIPLE\n" if ( $CLIC_DEBUG > 3);
            $commit = &SayImpossible(); # always returns 0
        }
    }
    if ( $CLIC_DEBUG > 1 )
    {
        print STDERR "AllowCommit: return " . &returnTF($commit) . "\n";
    }
    return $commit;
} # AllowCommit
################################################################################
################################################################################
############################# "PUBLIC" SUBROUTINES #############################
################################################################################
# LEAVE #######################################################################}



# ENTER ########################################################################
################################################################################
############################# SUPPORT SUBROUTINES ##############################
################################################################################
###############################################################################{
sub AddingArchiveDir
{
    my $parent   = shift; # this does NOT end with SLASH, protected "parent" directory
    my $allsub   = shift; # this does NOT end with SLASH, subdirectories (as a path containing all the "parts" of the path)
    my $archive  = shift; # name of the archive directory(s) for this configuration N-Tuple
    my $artifact = shift; # may or may not end with SLASH - indicates files or directory
    my $r = 0;            # assume failure
    my $sstr;             # subdirectory string - used for parsing $allsub into the @suball array
    my @suball;           # hold the parts of $allsub, $allsub can be a glob
    my $glob;             # build up from the $allsub string split apart into @suball
    my $dir = 0;          # assume artifact is a file
    local $_;

    $_ = $artifact;
    $dir = 1 if ( m@/$@ );

    if ( $dir )
    {
        $sstr = $allsub;           # start with the subdirectory config value
        print STDERR "AddingArchiveDir: \$sstr=$sstr\n" if ( $CLIC_DEBUG > 20);
        $sstr =~ s@^${parent}@@;   # remove the parent with FIRST SLASH
        @suball = split( '/', $sstr);
        # walk the longest path to the shortest path
        while ( @suball > 0 )
        {
            $glob  = $parent . join("/", @suball);
            $glob .= "/" if ( !( $glob =~ '/$' ) );
            $glob .= $archive . "/";
            if ( match_glob( $glob, $artifact ) )
            {
                print STDERR "AddingArchiveDir: match_glob( $glob, $artifact ) = YES\n" if ( $CLIC_DEBUG > 20);
                $r = 1; # we have a match
                last;
            }
            elsif ( $CLIC_DEBUG > 20 )
            {
                print STDERR "AddingArchiveDir: match_glob( $glob, $artifact ) = NO\n" if ( $CLIC_DEBUG > 20);
            }
            pop @suball;
        }
    }
    elsif ( $CLIC_DEBUG > 20)
    {
        print STDERR "AddingArchiveDir: $artifact is a FILE\n";
    }

    print STDERR "AddingArchiveDir: return $r\t\$artifact=$artifact\n" if ( $CLIC_DEBUG > 20);
    return $r;
} # AddingArchiveDir

sub AddingToArchiveDir
{
    my $parent   = shift; # this does NOT end with SLASH, protected "parent" directory
    my $allsub   = shift; # this does NOT end with SLASH, subdirectories (as a path containing all the "parts" of the path)
    my $archive  = shift; # name of the archive directory(s) for this configuration N-Tuple
    my $artifact = shift; # may or may not end with SLASH - indicates files or directory
    my $r = 0;            # assume failure
    my $sstr;             # subdirectory string - used for parsing $allsub into the @suball array
    my @suball;           # hold the parts of $allsub, $allsub can be a glob
    my $glob;             # build up from the $allsub string split apart into @suball
    my $dir = 0;          # assume artifact is a file
    local $_;

    $_ = $artifact;
    $dir = 1 if ( m@/$@ );

    if ( $dir )
    {
        $sstr = $allsub;           # start with the subdirectory config value
        print STDERR "AddingToArchiveDir: \$sstr=$sstr\n" if ( $CLIC_DEBUG > 20);
        $sstr =~ s@^${parent}@@;   # remove the parent with FIRST SLASH
        @suball = split( '/', $sstr);
        # walk the longest path to the shortest path
        while ( @suball > 0 )
        {
            $glob  = $parent . join("/", @suball);
            $glob .= "/" if ( !( $glob =~ '/$' ) );
            $glob .= $archive . "/?*/";
            if ( match_glob( $glob, $artifact ) )
            {
                print STDERR "AddingToArchiveDir: ( match_glob( $glob, $artifact ) = YES\n" if ( $CLIC_DEBUG > 20);
                $r = 1; # we have a match
                last;
            }
            elsif ( $CLIC_DEBUG > 20)
            {
                print STDERR "AddingToArchiveDir: ( match_glob( $glob, $artifact ) = NO\n" if ( $CLIC_DEBUG > 20);
            }
            pop @suball;
        }
    }
    elsif ( $CLIC_DEBUG > 20)
    {
        print STDERR "AddingToArchiveDir: $artifact is a FILE\n";
    }

    print STDERR "AddingToArchiveDir: return $r\t\$artifact=$artifact\n" if ( $CLIC_DEBUG > 20);
    return $r;
} # AddingToArchiveDir

sub AddingSubDir
{
    my $parent   = shift; # this does NOT end with SLASH, protected "parent" directory
    my $allsub   = shift; # this does NOT end with SLASH, subdirectory(s) (as a path containing all the "parts" of the path)
    my $artifact = shift; # may or may not end with SLASH - indicates files or directory
    my $r = 0;            # assume failure
    my $sstr;             # subdirectory string - used for parsing $allsub into the @suball array
    my @suball;           # hold the parts of $allsub, $allsub can be a glob
    my $glob;             # build up from the $allsub string split apart into @suball
    my $dir = 0;          # assume artifact is a file
    local $_;

    $_ = $artifact;
    $dir = 1 if ( m@/$@ );

    if ( $dir )
    {
        $sstr = $allsub;           # start with the subdirectory config value
        print STDERR "AddingSubDir: \$sstr=$sstr\n" if ( $CLIC_DEBUG > 20);
        $sstr =~ s@^${parent}@@;   # remove the parent with FIRST SLASH
        @suball = split( '/', $sstr);
        # walk the longest path to the shortest path
        while ( @suball > 20 )
        {
            $glob  = $parent . join("/", @suball);
            $glob .= "/" if ( !( $glob =~ '/$' ) );
            if ( match_glob( $glob, $artifact ) )
            {
                print STDERR "AddingSubDir: ( match_glob( $glob, $artifact ) = YES\n" if ( $CLIC_DEBUG > 20);
                $r = 1; # we have a match
                last;
            }
            elsif ( $CLIC_DEBUG > 20)
            {
                print STDERR "AddingSubDir: ( match_glob( $glob, $artifact ) = NO\n" if ( $CLIC_DEBUG > 20);
            }
            pop @suball;
        }
    }
    elsif ( $CLIC_DEBUG > 20)
    {
        print STDERR "AddingSubDir: $artifact is a FILE\n";
    }

    print STDERR "AddingSubDir: return $r\t\$artifact=$artifact\n" if ( $CLIC_DEBUG > 20);
    return $r;
} # AddingSubDir

# each artifact has to be tested to see if it is under protection
# which means looping through all configurations
sub ArtifactUnderProtectedDir
{
    my $artifact = shift;
    my $parent;           # protected directory
    my $tupleKey;
    my $returnKey = "";
    my $isProtected = 0; # assume not protected

    for $tupleKey ( keys %{cfgHofH} )
    {
        $parent = $cfgHofH{$tupleKey}{$TAGpKEY};
        if ( &IsUnderProtection($parent, $artifact) == 1 )
        {
            $returnKey = $tupleKey;
            $isProtected = 1;
            last;
        }
    }
    return ($isProtected, $returnKey);
} # ArtifactUnderProtectedDir

sub Authorized
{
    my $author   = shift;   # committer of this change
    my $authOK   = shift;   # those allowed to commit
    my $artifact = shift;   # what requires authorization
    my $msgwords = shift;   # description of what is being added
    my $isauth   = 0;       # assume failure
    my @auth;
    my $user;

    if ( $authOK eq '*')
    {
        print STDERR "Authorized: allow because authorization is the '*' character\n" if ( $CLIC_DEBUG > 20);
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
        @auth = split( ",", $authOK);
        for $user ( @auth )
        {
            $user =~ s@\s+@@g; # remove all spaces, user names can not have spaces in them
            if ( $user eq $author )
            {
                print STDERR "Authorized: allow because author matches: $user\n" if ( $CLIC_DEBUG > 20);
                $isauth = 1;
                last;
            }
            elsif ( $user eq '*' )
            {
                print STDERR "Authorized: allow because one of users is the '*' character\n" if ( $CLIC_DEBUG > 20);
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
} # Authorized

sub FixPath # trim trailing / chars as need be from the config file
{
    local $_ = shift; # path to be "fixed"
    my $no1stSlash = shift;
    my $addLastSlash = shift;
    if ( $_ ne "" and $_ ne "/" )
    {
        s/\/+$//; # strip any trailing "/" chars
        if ( $_ eq "" )
        {
            $_ = "/"
        }
        elsif ( $no1stSlash )
        {
           s@^/@@;
        }
        $_ .= "/" if ( $addLastSlash );
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
    $l = length($VAR_TAGDIRE); $r = $l if ( $l > $r);
    $l = length($VAR_SUBDIRE); $r = $l if ( $l > $r);
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

sub GetMax
{
    my $l = shift; # left
    my $r = shift; # right
    return $l if ($l > $r);
    return $r;
} # GetMax

sub GetVersion
{
    my $ver = shift;
    my $back = "";
    local $_;

    open my $vHandle, "<", "$PROGDIRE/$VERSION_FILE";
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

sub IsUnderProtection
{
    my $pDir     = shift; # protected (parent) directories
    my $artifact = shift; # to be added
    my $leftside;         # left side of $artifact, length of $pDir
    my $r;                # returned value
    local $_;

    if ( $pDir eq "/" )
    {
        # THIS IS CODED THIS WAY IN CASE "/" IS DISALLOWED IN FUTURE (perhaps it should be?)
        $r  = 1;   # this will always match everything!
        print STDERR "IsUnderProtection: protected directories is \"/\" it always matches everything\n" if ( $CLIC_DEBUG > 20);
    }
    else
    {
        # the protected (parent) directory is given literally like: "/tags"
        # but can contain who knows what (even meta chars to be taken as is)
        $_ = int(length($pDir));
        $leftside = substr($artifact, 0, $_);
        if ( $CLIC_DEBUG > 20)
        {
            print STDERR 'IsUnderProtection: $artifact:  ' . $artifact . "\n" if ( $CLIC_DEBUG > 20);
            print STDERR 'IsUnderProtection: checking exact match (' . $leftside . ' eq ' . $pDir . ") ";
        }
        if ( $leftside eq $pDir )
        {
            print STDERR "YES\n" if ( $CLIC_DEBUG > 20);
            $r = 1;
        }
        else
        {
            print STDERR "NO\n" if ( $CLIC_DEBUG > 20);
            $r = 0;
        }
    }
    print STDERR "IsUnderProtection: return $r\n" if ( $CLIC_DEBUG > 20);
    return $r;
} # IsUnderProtection

sub LoadCFGTuple # put an N-Tuple into the Hash of hashes
{
    # this is what this subroutine "loads", i.e. the 1st is given and
    # we default the next 3 from the 3 above if they are not there
    my $inHashRef = shift; # a reference to the "inner" hash
    my $key;                 # used to build the key from the string and the number

    # the outer most hash, named %cfgHofH, will load (copy) the above hash (not the reference)
    # along with the information needed to construct the key needed to push the above hash into
    # it.  Got that?

    # check that incoming (inner) hash has a directory in it to be protected
    if (    ( ! exists $inHashRef->{$NAMEKEY} )
        ||  ( ! exists $inHashRef->{$MAKEKEY} )
        ||  ( ! exists $inHashRef->{$TAGpKEY} )
        ||  ( ! exists $inHashRef->{$LINEKEY} )
        ||  ( ! exists $inHashRef->{$SUBfKEY} ) )
    {
        # give it bogus value if it has no value
        $inHashRef->{$LINEKEY}  = 0 if ( ! exists $inHashRef->{$LINEKEY} );

        print STDERR "$PROGNAME: See configuration file: $CLICONFIGF\n";
        print STDERR "$PROGNAME: The value of $VAR_TAGDIRE does not exist for the configuration set.\n"
          if ( ! exists $inHashRef->{$TAGpKEY} );
        print STDERR "$PROGNAME: The value of $VAR_SUBDIRE does not exist for the configuration set!\n"
          if ( ! exists $inHashRef->{$SUBfKEY} );
        print STDERR "$PROGNAME: The value of $VAR_NAME_AF does not exist for the configuration set!\n"
          if ( ! exists $inHashRef->{$NAMEKEY} );
        print STDERR "$PROGNAME: The value of $VAR_MAKESUB does not exist for the configuration set!\n"
          if ( ! exists $inHashRef->{$MAKEKEY} );
        print STDERR "$PROGNAME: Around line number: $inHashRef->{$LINEKEY}\n";
        print STDERR "$PROGNAME: Failure in subroutine LoadCFGTuple.\n";
        print STDERR "$PROGNAME: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }
    elsif ( $inHashRef->{$TAGpKEY} eq "" )
    {
        # give it bogus value if it has no value
        $inHashRef->{$LINEKEY}  = 0 if ( ! exists $inHashRef->{$LINEKEY} );
        print STDERR "$PROGNAME: See configuration file: $CLICONFIGF\n";
        print STDERR "$PROGNAME: The value of $VAR_TAGDIRE is blank.\n";
        print STDERR "$PROGNAME: Around line number: $inHashRef->{$LINEKEY}\n";
        print STDERR "$PROGNAME: Failure in subroutine LoadCFGTuple.\n";
        print STDERR "$PROGNAME: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }

    # get new key for outer hash
    $key =  &GenTupleKey($TupleSTR, $TupleCNT);
    $TupleCNT++;

    # insist that this new configuation plays by the rules
    $inHashRef->{$SUBfKEY} = &ValidateSubDirOrDie($inHashRef->{$TAGpKEY},
                                                  $inHashRef->{$SUBfKEY},
                                                  $inHashRef->{$LINEKEY});

    $cfgHofH{ $key } = { %$inHashRef }; # this allocates (copies) inner hash

    return; # return no value
} # LoadCFGTuple # put an N-Tuple into the Hash of hashes

sub PrintDefaultConfigOptionallyExit
{
    my $headerOnly = shift;
    my $output     = shift;
    my $q = '"';

    if ($CLIC_DEBUG > 20)
    {
        if ( $headerOnly )
        {
            print STDERR "PrintDefaultConfigOptionallyExit: output default header.\n";
        }
        else
        {
            print STDERR "PrintDefaultConfigOptionallyExit: output default configuration file.\n";
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
    print $output &PrtStr($VAR_H_DEBUG) . " = $DEF_H_DEBUG\n";
    print $output &PrtStr($VAR_SVNPATH) . " = ${q}$DEF_SVNPATH${q}\n";
    print $output &PrtStr($VAR_SVNLOOK) . " = ${q}$DEF_SVNLOOK${q}\n";
    print $output "\n";
    print $output "### These comprise an N-Tuple, can be repeated as many times as wanted,\n";
    print $output "### but each ${VAR_TAGDIRE} value must be unique.   It is not allowed to\n";
    print $output "### try to configure the same directory twice (or more)!\n";
    if ( $headerOnly == 0 )
    {
        print $output &PrtStr($VAR_TAGDIRE) . " = ${q}$DEF_TAGDIRE${q}\n";
        print $output &PrtStr($VAR_SUBDIRE) . " = ${q}$DEF_SUBDIRE${q}\n";
        print $output &PrtStr($VAR_MAKESUB) . " = ${q}$DEF_MAKESUB${q}\n";
        print $output &PrtStr($VAR_NAME_AF) . " = ${q}$DEF_NAME_AF${q}\n";
        exit $exitUserHelp; # only exit if doing the whole thing
    }
} # PrintDefaultConfigOptionallyExit

sub PrintUsageAndExit # output and exit
{
    my $look = $CLISVNLOOK;
    $look =~ s@.*/@@;
    $look =~ s@.*\\@@;

    my $svn  = $CLISVNPATH;
    $svn =~ s@.*/@@;
    $svn =~ s@.*\\@@;

    print STDOUT "\n";
    print STDOUT "usage: $PROGNAME repo-name transaction-id  - Normal usage under Subversion.\n";
    print STDOUT "OR:    $PROGNAME --help                    - Get this printout.\n";
    print STDOUT "OR:    $PROGNAME [options]                 - configuration testing and debugging.\n";
    print STDOUT "\n";
    print STDOUT "    THIS SCRIPT IS A HOOK FOR SUBVERSION AND IS NOT MEANT TO BE\n";
    print STDOUT "    RUN FROM THE COMMAND LINE UNDER NORMAL USAGE.\n";
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
    print STDOUT "    --generate        | -g      Generate a default configuration file, with\n";
    print STDOUT "                                comments, and  write it to standard output.\n";
    print STDOUT "                                Typically used for testing/debugging a\n";
    print STDOUT "                                configuration file before moving into\n";
    print STDOUT "                                production.\n";
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
    print STDOUT "    --output=file   | -ofile    Output to \"file\", this option is used in conjunct-\n";
    print STDOUT "                                ion with --generate and --build.  If --output=file is\n";
    print STDOUT "                                given with one of --generate or --build the output will\n";
    print STDOUT "                                be written to the named \"file\" instead.\n";

    print STDOUT "\n";
    print STDOUT "\n";
    print STDOUT "NOTE: a typical command line usage for debugging purposes would look\n";
    print STDOUT "      like this\n";
    print STDOUT "        ./$PROGNAME [options] --debug=N < /dev/null\n";
    print STDOUT "\n";
    print STDOUT "$PROGNAME: " . &GetVersion(1) . "\n";
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
    print STDERR "$PROGNAME: commit failed, re: UNKNOWN!\n";
    print STDERR "$PROGNAME: it appears this commit does not modify, add, or delete anything!\n";
    return 0;
} # SayImpossible

sub SayNoDelete
{
    my $what = shift;
    print STDERR "$PROGNAME: commit failed, delete of protected directories is not allowed!\n";
    print STDERR "$PROGNAME: commit failed on: $what\n";
    return 0;
} # SayNoDelete

sub SvnGetAuthor
{
    my @tapCmd;         # array to hold output
    my $svnErrors;      # STDERR of command SVNLOOK - any errors
    my $svnAuthor;      # STDOUT of command SVNLOOK - creator
    my $svnExit;        # exit value of command SVNLOOK
    my $what = "author";

    @tapCmd = (
        $CLISVNLOOK,
        "--transaction",
        $CLISVN_TID,
        $what,
        $CLISVNREPO,
      );
    print STDERR          'SvnGetAuthor: tap' . " " . join(" ", @tapCmd) . "\n" if ( $CLIC_DEBUG > 20);
    ($svnAuthor, $svnErrors, $svnExit) = tap                    @tapCmd;
    chop($svnAuthor);
    if ( $CLIC_DEBUG > 20)
    {
        if ( $CLIC_DEBUG > 20)
        {
            print STDERR "SvnGetAuthor: \$svnExit=  >>$svnExit<<\n";
            print STDERR "SvnGetAuthor: \$svnErrors=>>$svnErrors<<\n";
        }
        print STDERR "SvnGetAuthor: \$svnAuthor=>>$svnAuthor<<\n";
    }
    if ( $svnExit )
    {
        print STDERR "$PROGNAME: \"$CLISVNLOOK\" failed to get \"$what\" (exit=$svnExit), re: $svnErrors\n";
        print STDERR "$PROGNAME: command: >>tap " . join(" ", @tapCmd) . "\n";
        print STDERR "$PROGNAME: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }
    print STDERR "SvnGetAuthor: return \"$svnAuthor\"\n" if ( $CLIC_DEBUG > 20);
    return $svnAuthor;
} # SvnGetAuthor

sub SvnGetCommit
{
    my @tapCmd;         # array to hold output
    my $svnErrors;      # STDERR of command SVNLOOK - any errors
    my $svnOutput;      # STDOUT of command SVNLOOK - commit data
    my $svnExit;        # exit value of command SVNLOOK
    my $itmp = 0;       # index into @Changed
    local $_;           # regex'ing
    my $what = "changed";

    @tapCmd = (
        $CLISVNLOOK,
        "--transaction",
        $CLISVN_TID,
        $what,
        $CLISVNREPO,
      );
    print STDERR           'SvnGetCommit: tap' . " " . join(" ", @tapCmd) . "\n" if ( $CLIC_DEBUG > 20);
    ($svnOutput, $svnErrors, $svnExit) = tap                    @tapCmd;
    if ( $CLIC_DEBUG > 20) # "2", not "0" because the array is printed below
    {
        print STDERR "SvnGetCommit: \$svnExit=  >>$svnExit<<\n";
        print STDERR "SvnGetCommit: \$svnErrors=>>$svnErrors<<\n";
        print STDERR "SvnGetCommit: \$svnOutput=>>\n$svnOutput<<\n";
    }
    if ( $svnExit )
    {
        print STDERR "$PROGNAME: \"$CLISVNLOOK\" failed to get \"$what\" (exit=$svnExit), re: $svnErrors\n";
        print STDERR "$PROGNAME: command: >>tap " . join(" ", @tapCmd) . "\n";
        print STDERR "$PROGNAME: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }
    @CommitData = split("\n", $svnOutput);
    if ( $CLIC_DEBUG > 20)
    {
        foreach $_ ( @CommitData )
        {
            print STDERR "SvnGetCommit BEFORE: CommitData>>$_\n";
        }
    }
    @CommitData = sort @CommitData; # needed?
    if ( $CLIC_DEBUG >  20)
    {
        foreach $_ ( @CommitData )
        {
            print STDERR "SvnGetCommit  AFTER: CommitData>>$_\n";
        }
    }
    return @CommitData # $svnOutput split into an array of files/directories;
} # SvnGetCommit

sub SvnGetList
{
    my $path   = shift; # path to list
    my $full   = shift; # protocol, repo, path
    my @tapCmd;         # array to hold output
    my $svnErrors;      # STDERR of command SVNPATH list - any errors
    my $svnList;        # STDOUT of command SVNPATH list - data
    my $svnExit;        # exit value of command SVNPATH
    my @List;           # $svnList split into an array of files/directories
    local $_;           # regex'ing

   # build the full protocol / repository / path string
   $full = "file://" . $CLISVNREPO . $path;

    @tapCmd = (
        $CLISVNPATH,
        "list",
        $full
      );
    print STDERR           'SvnGetList: tap' . " " . join(" ", @tapCmd) . "\n" if ( $CLIC_DEBUG > 20);
    ($svnList, $svnErrors, $svnExit) = tap                    @tapCmd;
    if ( $CLIC_DEBUG > 20) # "2", not "0" because the array is printed below
    {
        print STDERR "SvnGetList: \$svnExit=  >>$svnExit<<\n";
        print STDERR "SvnGetList: \$svnErrors=>>$svnErrors<<\n";
        print STDERR "SvnGetList: \$svnList=  >>$svnList<<\n";
    }
    if ( $svnExit )
    {
        # is this a true error or simply that the path listed does not exist?
        $_ = $svnErrors;
        if ( ! m/non-existent in that revision/ )
        {
            print STDERR "$PROGNAME: \"$CLISVNPATH\" failed to list \"$path\" (exit=$svnExit), re: $svnErrors";
            print STDERR "$PROGNAME: command: >>tap " . join(" ", @tapCmd) . "\n";
            print STDERR "$PROGNAME: ABORTING - tell the subversion administrator.\n";
            exit $exitFatalErr;
        }
    }
    @List = split("\n", $svnList);
    print STDERR "SvnGetList: LEAVE: svn list of $full\n" if ( $CLIC_DEBUG > 20);
    return @List; # $svnList split into an array of files/directories
} # SvnGetList

sub TagIsInArchive
{
    my $aTag  = shift;   # new artifact, tag that is being created
    my $arch  = shift;   # name of archive directory
    my @list;
    my $rvalue = 0;       # returned value, assume not in archive
    my $head;
    my $tail;
    my $path;

    $head = $aTag;
    $head =~ s@/$@@;
    $tail = $head;

    $head =~ s@(.*)/(.*)@$1@;
    $tail =~ s@(.*)/(.*)@$2@;

    $path = $head . "/" . $arch . "/" . $tail;

    @list = &SvnGetList($path);
    if ( ( scalar @list ) > 0 ) { $rvalue = 1; }
    return $rvalue;
} # TagIsInArchive

sub TheAddIsAllowed
{
    my $author = shift;   # committer of this change
    my $ADDref = shift;   # array reference to the "array of stuff to add"
    my $aDire;            # archive directory name
    my $aMake;            # users that can create new project directories
    my $artifact;         # user wants to add
    my $commit = 1;       # assume OK to commit
    my $arrayRef;         # pointer to the inner array
    my $pDire;            # protected (parent) directory
    my $sDire;            # subdirectory under $pDire, can be BLANK
    my $tupKey;           # N-Tuple key used to find data in $CFGref
    my $glob;             # a "glob" pattern to check for matches

    if ( $CLIC_DEBUG > 7)
    {
        print STDERR "TheAddIsAllowed: ENTER: listing array of N-Tuple keys and the artifact to test with the key\n";
        for $arrayRef ( @{ $ADDref } )
        {
            ($tupKey, $artifact) = ( @{ $arrayRef } );
            print STDERR "TheAddIsAllowed: with Configuration key=$tupKey test artifact=$artifact\n";
        }
        print STDERR "TheAddIsAllowed: LEAVE: listing array of N-Tuple keys and the artifact to test with the key\n";
    }
    for $arrayRef ( @{ $ADDref } ) # we know all these are protected and to be added
    {
        ($tupKey, $artifact) = ( @{ $arrayRef } );
        $pDire = $cfgHofH{$tupKey}{$TAGpKEY}; # protected directory
        $aMake = $cfgHofH{$tupKey}{$MAKEKEY}; # authorised to make subdirectories
        $aDire = $cfgHofH{$tupKey}{$NAMEKEY}; # archive directory name
        $sDire = $cfgHofH{$tupKey}{$SUBfKEY}; # subdirectory name - glob is allowed here

        if ( $CLIC_DEBUG > 6)
        {
            print STDERR 'TheAddIsAllowed: N-TupleKey:     $tupKey'   . "\t= $tupKey\n";
            print STDERR 'TheAddIsAllowed: Commited:       $artifact' . "\t= $artifact\n";
            print STDERR 'TheAddIsAllowed: Parent Dir:     $pDire'    . "\t\t= $pDire\n";
            print STDERR 'TheAddIsAllowed: Sub "glob" Dir: $sDire'    . "\t\t= $sDire\n";
            print STDERR 'TheAddIsAllowed: Archive Dir:    $aDire'    . "\t\t= $aDire\n";
            print STDERR 'TheAddIsAllowed: Authorized:     $aMake'    . "\t\t= $aMake\n";
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
        print STDERR "TheAddIsAllowed: TESTING -> ATTEMPT TO ADD TO AN ARCHIVE DIRECTORY? $artifact\n" if ( $CLIC_DEBUG > 4);
        if    ( $sDire eq "" and $aDire eq "" ) { $glob = "";                              } # no subdirectory, no archive directory name
        elsif ( $sDire eq "" and $aDire ne "" ) { $glob = $pDire . '/' . $aDire . "/?*";   } # no subdirectory, yes archive directory name
        elsif ( $sDire ne "" and $aDire eq "" ) { $glob = "";                              } # yes subdirectory, not arhive directory name
        elsif ( $sDire ne "" and $aDire ne "" ) { $glob = $sDire . '/' . $aDire . "/?*";   } # yes subdirectory, yes archive directory name
        if ( $glob ne "" )
        {
            print STDERR 'TheAddIsAllowed: if (&' . "AddingToArchiveDir($pDire, $sDire, $aDire, $artifact) is the test to see if adding to an archive directory\n" if ( $CLIC_DEBUG > 6);
            if ( &AddingToArchiveDir($pDire, $sDire, $aDire, $artifact) == 1 )
            {
                print STDERR 'TheAddIsAllowed: $artifact=' . "$artifact IS UNDER AN ARCHIVE DIRECTORY\n" if ( $CLIC_DEBUG > 4);
                print STDERR "$PROGNAME: you can only move existing tags to an archive directory\n";
                print STDERR "$PROGNAME: commit failed, you cannot add anything to an existing archive directory!\n";
                print STDERR "$PROGNAME: commit failed on: $artifact\n";
                $commit = 0;
                last;
            }
        }
        print STDERR "TheAddIsAllowed: KEEP TESTING -> NOT ADDING TO AN ARCHIVE DIRECTORY WITH: $artifact\n" if ( $CLIC_DEBUG > 5);

        # 2) attempting to add to a tag?
        print STDERR "TheAddIsAllowed: TESTING -> ATTEMPT TO ADD A TAG? $artifact\n" if ( $CLIC_DEBUG > 4);
        if    ( $sDire eq ""                    ) { $glob = $pDire . "/?*/"; } # no subdirectory
        else                                      { $glob = $sDire . "/?*/"; }
        print STDERR "TheAddIsAllowed: if ( match_glob( $glob, $artifact ) ) is the test to see if adding a new tag\n" if ( $CLIC_DEBUG > 6);
        if ( match_glob( $glob, $artifact ) )
        {
            print STDERR 'TheAddIsAllowed: if ( &' . "TagIsInArchive($artifact, $aDire) == 1 ) is the test to see if adding to an archive directory\n" if ( $CLIC_DEBUG > 6);
            if ( &TagIsInArchive($artifact, $aDire) == 1 )
            {
                print STDERR "TheAddIsAllowed: stop TESTING -> CANNOT ADD tag that already exists in the archive directory: artifact=$artifact\n" if ( $CLIC_DEBUG > 4);
                print STDERR "$PROGNAME: you cannot add this tag because it already exists in an archive directory!\n";
                print STDERR "$PROGNAME: commit failed on: $artifact\n";
                $commit = 0;
                last;
            }
            # no problem - we are simply adding a tag
            print STDERR "TheAddIsAllowed: stop TESTING -> THIS IS OK AND IS A NEW TAG artifact=$artifact\n" if ( $CLIC_DEBUG > 4);
        }
        else
        {
            print STDERR "TheAddIsAllowed: KEEP TESTING -> THIS IS NOT A NEW TAG $artifact\n" if ( $CLIC_DEBUG > 5);
            # 3) attempting to add the _Archive directory_ itself?
            print STDERR "TheAddIsAllowed: TESTING -> ATTEMPT TO ADD THE ARCHIVE DIRECTORY ITSELF? artifact=$artifact\n" if ( $CLIC_DEBUG > 4);
            if ( $aDire ne "" )
            {
                print STDERR 'TheAddIsAllowed: if ( &' . " AddingArchiveDir($pDire, $sDire, $aDire, $artifact) == 1 ) is the test to see if adding an archive directory\n" if ( $CLIC_DEBUG > 6);
                if ( &AddingArchiveDir($pDire, $sDire, $aDire, $artifact) == 1 )
                {
                    print STDERR 'TheAddIsAllowed: $artifact=' . "$artifact IS AN ARCHIVE DIRECTORY\n" if ( $CLIC_DEBUG > 4);
                    $commit = &Authorized($author, $aMake, $artifact, 'add an archive directory');
                    last if ( $commit == 0 );
                    next;
                }
            }
            print STDERR "TheAddIsAllowed: KEEP TESTING -> NOT ADDING THE ARCHIVE DIRECTORY ITSELF WITH artifact=$artifact\n" if ( $CLIC_DEBUG > 5);

            # 4) attempting to add a project directory?
            print STDERR "TheAddIsAllowed: TESTING -> ATTEMPT TO ADD A SUB DIRECTORY? artifact=$artifact\n" if ( $CLIC_DEBUG > 4);
            print STDERR 'TheAddIsAllowed: if ( &' . "AddingSubDir($pDire, $sDire, $artifact) == 1 ) is the test to see if adding a sub directory\n" if ( $CLIC_DEBUG > 6);
            if ( &AddingSubDir($pDire, $sDire, $artifact) == 1 )
            {
                print STDERR "TheAddIsAllowed: stop TESTING -> THIS IS A NEW PROJECT SUB DIRECTORY, calling Authorized artifact=$artifact\n" if ( $CLIC_DEBUG > 4);
                $commit = &Authorized($author, $aMake, $artifact, 'add a project (or sub) directory');
                last if ( $commit == 0 );
                next;
            }
            print STDERR "TheAddIsAllowed: KEEP TESTING -> NOT ATTEMPT TO ADD A SUB DIRECTORY WITH artifact=$artifact\n" if ( $CLIC_DEBUG > 5);

            # 5) attempting to add the protected directory _itself_ ?
            print STDERR "TheAddIsAllowed: TESTING -> ATTEMPT TO ADD THE PROTECTED DIRECTORY ITSELF? artifact=$artifact\n" if ( $CLIC_DEBUG > 4);
            print STDERR 'TheAddIsAllowed: if ( ' . "\"$pDire/\" eq $artifact ) is the test to see if adding a sub directory\n" if ( $CLIC_DEBUG > 6);
            if ( "$pDire/" eq $artifact ) # trying to add the parent directory itself
            {
                print STDERR "TheAddIsAllowed: stop TESTING -> THIS IS A THE PROTECTED DIRECTORY, calling Authorized artifact=$artifact\n" if ( $CLIC_DEBUG > 4);
                $commit = &Authorized($author, $aMake, $artifact, 'create the protected directory');
                last if ( $commit == 0 );
                next;
            }
            else # attempting to add a file instead of a tag
            {
                print STDERR "TheAddIsAllowed: stop TESTING -> CANNOT ADD ARBITRARY DIRECTORY OR FILE TO A PROTECTED DIRECTORY artifact=$artifact\n" if ( $CLIC_DEBUG > 4);
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
    print STDERR "TheAddIsAllowed: return " . &returnTF($commit) . "\n" if ( $CLIC_DEBUG > 3);
    return $commit;
} # TheAddIsAllowed

sub TheMoveIsAllowed
{
    my $what = shift;     # committer of this change
    my $author = shift;   # committer of this change
    my $ADDref = shift;   # reference to the array of stuff to add
    my $DELref = shift;   # reference to the array of stuff to delete
    my $addKey;           # N-Tuple key from the "add" array
    my $artifact;         # path from the "add" array
    my $artifactNoArch;   # path from the "add" array with next to last directory with "Arhive name" removed
    my $addRef;           # reference for add array
    my $archive;          # name of an archive directory for this N-Tuple
    my $check1st;         # path to check before putting a path into @justAdditions
    my $commit = 1;       # assume OK to commit
    my $count;            # of elements in @justAdditions
    my $delNdx;           # found the thing in the del array this is in the add array?
    my $delKey;           # N-Tuple key from the "del" array
    my $delPath;          # path from the "del" array
    my $delRef;           # reference for the del array
    my $justAdd;          # true if the path in the add array has no matching path in the del array
    my $ok2add;           # ok to put a path into @justAdditions because it is not there already
    my $ref;              # reference into @justAdditions
    my $stmp;             # tmp string
    my @justAdditions;    # array of additions found that do not have matching delete/move
    my @tmp;              # used to load the @justAdditions array with data

    # walk each of the artifacts to be added
    for $addRef ( @{ $ADDref } )
    {
        ($addKey, $artifact) = ( @{ $addRef } );
        print STDERR "TheMoveIsAllowed: add cfgkey is: $addKey, add artifact is: $artifact\n" if ( $CLIC_DEBUG > 5);
        $archive = $cfgHofH{$addKey}{$NAMEKEY};
        if ( $archive eq "" )
        {
            print STDERR "TheMoveIsAllowed: KEEP TESTING -> no archive directory so this must be a just add condition with artifact: $artifact\n" if ( $CLIC_DEBUG > 4 );
            $justAdd = 1;
        }
        else
        {
            $justAdd = 0;
            print STDERR "TheMoveIsAllowed: if ( $artifact " . '=~ m@^(.+)/' . "${archive}" . '/([^/]+/)$@' . " ) is the test to see if adding to an archive directory\n" if ( $CLIC_DEBUG > 6);
            if ( $artifact =~ m@^(.+)/${archive}/([^/]+/)$@ ) # does path have "archive directory name" in it as next to last directory
            {
                $artifactNoArch = "$1/$2";
                print STDERR "TheMoveIsAllowed: KEEP TESTING -> does the archive artifact to add have a corresponding tag being deleted, artifact: $artifact, corresponding: $artifactNoArch\n" if ( $CLIC_DEBUG > 4 );
                $delNdx = -1; # impossible value
                $count = 0;
                # walk each of the artifacts to be deleted and look to see if the thing added is related to the artifact being deleted by an archive directory name
                for $delRef ( @{ $DELref } )
                {
                    ($delKey, $delPath) = ( @{ $delRef } );
                    print STDERR "TheMoveIsAllowed: delete cfgkey is: $delKey, add artifact is: $delPath\n" if ( $CLIC_DEBUG > 5);
                    if ( $addKey eq $delKey and $artifactNoArch eq $delPath )
                    {
                        $delNdx = $count;
                        if ( $CLIC_DEBUG > 6)
                        {
                            print STDERR "TheMoveIsAllowed: DEL is moving to Arhive, that's OK\n";
                            print STDERR "TheMoveIsAllowed: ADD KEY  >>$addKey<<\n";
                            print STDERR "TheMoveIsAllowed: DEL KEY  >>$delKey<<\n";
                            print STDERR "TheMoveIsAllowed: ADD PATH >>$artifact<<\n";
                            print STDERR "TheMoveIsAllowed: DEL PATH >>$delPath<<\n";
                        }
                        last;
                    }
                    $count ++;
                }
                if ( $delNdx != -1 ) # was the index into the del array found?
                {
                    print STDERR "TheMoveIsAllowed: KEEP TESTING -> remove this artifact from delete array because it is moving to archive directory: $artifact\n" if ( $CLIC_DEBUG > 4 );
                    splice @{ $DELref }, $delNdx, 1; # ignore any returned value, not needed
                }
                else
                {
                    print STDERR "TheMoveIsAllowed: KEEP TESTING -> the artifact to be added has no corresponding delete from a tag: $artifact\n" if ( $CLIC_DEBUG > 4 );
                }
            }
            else # found a path to add but it does not have "archive directory name" as next to last directory
            {
                print STDERR "TheMoveIsAllowed: KEEP TESTING -> no archive directory match so this is an add condition with artifact: $artifact\n" if ( $CLIC_DEBUG > 4 );
                $justAdd = 1;
            }
        }
        if ( $justAdd )
        {
            print STDERR "TheMoveIsAllowed: KEEP TESTING -> ADDING TO THE ARRAY OF justAdditions: $artifact\n" if ( $CLIC_DEBUG > 3 );
            $ok2add = 1; # assume so
            $count = int(@justAdditions);
            if ( $count > 0 )
            {
                $ref = $justAdditions[$count - 1];
                ($stmp, $check1st) = @{ $ref };
                if (length($artifact) >= length($check1st))
                {
                    $ok2add = 0 if ( $artifact =~ $check1st );
                }
            }
            if ( $ok2add )
            {
                @tmp = ($addKey, $artifact);
                print STDERR "TheMoveIsAllowed: KEEP TESTING - pushing path to array for futher testing, artifact: $artifact\n" if ( $CLIC_DEBUG > 4);
                push @justAdditions, [ @tmp ];
            }
            else
            {
                print STDERR "TheMoveIsAllowed: duplicate pathing, not pushing path to array for futher testing, artifact: $artifact\n" if ( $CLIC_DEBUG > 4);
            }
        }
    }
    if ( $CLIC_DEBUG > 5)
    {
        print STDERR "TheMoveIsAllowed: LOOP IS DONE\n";
        print STDERR "TheMoveIsAllowed: left over delete count is:  $#$DELref  (0 or more means there are some deletes not part of moves)\n";
        print STDERR "TheMoveIsAllowed: count of just additions is: " . int( @justAdditions ) . "\n";
    }
    if ( ! ( $#$DELref < 0 ) ) # if there is something left over to be deleted then it is not a "move"
    {
        for $delRef ( @{ $DELref } )
        {
            ($delKey, $delPath) = ( @{ $delRef } );
            $commit = &SayNoDelete("D   $delPath");   # always returns 0
            last; # just do one
        }
    }
    elsif ( int( @justAdditions ) > 0 ) # there is something left over to be added and must check that on its own
    {
        print STDERR "TheMoveIsAllowed: KEEP TESTING - call " . '&TheAddIsAllowed' . " to test addtions not matched with deletions\n" if ( $CLIC_DEBUG > 3);
        $commit = &TheAddIsAllowed($author, \@justAdditions);
    }
    if ( $CLIC_DEBUG > 1)
    {
        print STDERR "TheMoveIsAllowed: return " . &returnTF($commit) . "\n";
    }
    return $commit;
} # TheMoveIsAllowed

# if the (now parsed into PERL hash of hash) configuration file has the _identical_
# tag directory to protect repeated (i.e. given more that once) error out and die.
# a tag directory to protect can only be given once.
sub ValidateCFGorDie
{
    my $count_1 = 0;       # index for outer count
    my $count_2 = 0;       # index for inner count
    my $key_1;             # to loop through keys
    my $key_2;             # to loop through keys
    my $protected_1;       # 1st protected directory to compare with
    my $protected_2;       # 2nd protected directory to compare with
    my $error = 0;         # error count

    while ( $count_1 < $TupleCNT )
    {
        $key_1 = &GenTupleKey($TupleSTR, $count_1);
        $protected_1 = $cfgHofH{$key_1}{$TAGpKEY};  # data to compare
        $count_2 = $count_1 + 1;
        while ( $count_2 < $TupleCNT )
        {
            $key_2 = &GenTupleKey($TupleSTR, $count_2);
            $protected_2 = $cfgHofH{$key_2}{$TAGpKEY};  # data to compare
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
            $count_2 ++;
        }
        $count_1 ++;
    }
    if ( $error > 0 ) # die if errors
    {
        print STDERR "$PROGNAME: ABORTING - tell the subversion administrator.\n";
        exit $exitFatalErr;
    }
    return;
} # ValidateCFGorDie

# THIS IS CALLED DURING CONFIGUATION PARSE - NOT OTHERWISE
# the subdirectory given, if not the empty string, must be
# a subdirectory of the associated tag directory (the one
# to protect).  E.g:
#     if   "/tags" is the directory to be protected then
#     then "/tags/<whatever>" is acceptable, but
#          "/foobar/<whatever>" is NOT
# The subdirectory specification must truly be a subdirectory
# of the associated directory to be protected.
sub ValidateSubDirOrDie
{
    my $pDire = shift;   # directory name of tag to protect
    my $globc = shift;   # the subdirectory "glob" string/path
    my $lline = shift;   # current config file line

    my $leftP; # left part
    my $right; # right part
    local $_;

    # a BLANK regex means that the tag directory does not allow _any_
    # project names, hey that's ok!  if so there is no need to test
    if ( $globc ne "" )
    {
        $leftP = $globc; $leftP =~ s@(${pDire})(.+)@$1@;
        $right = $globc; $right =~ s@(${pDire})(.+)@$2@;
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
        $_ = $right;         # the "backslash" is not allowed, it can only lead to problems!
        print STDERR "ValidateSubDirOrDie: initial       \$_=$_\n" if ( $CLIC_DEBUG > 20);
        s@\\@@g;             # remove all backslash chars - not allowed
        print STDERR "ValidateSubDirOrDie: rm backslash  \$_=$_\n" if ( $CLIC_DEBUG > 20);
        s@/+@/@g;            # change multiple //* chars into just one /
        print STDERR "ValidateSubDirOrDie: rm single sep \$_=$_\n" if ( $CLIC_DEBUG > 20);
        while ( m@/\.\//@ )  # /../ changed to / in a loop
        {
            s@/\.\./@/@g;    # remove it
            s@/+@/@g;        # don't see how this could happen, but safety first
        print STDERR "ValidateSubDirOrDie: in clean loop \$_=$_\n" if ( $CLIC_DEBUG > 20);
        }
        print STDERR "ValidateSubDirOrDie: done          \$_=$_\n" if ( $CLIC_DEBUG > 20);
        $globc = $leftP . $_;         # the "backslash" is not allowed, it can only lead to problems!
    }
    print STDERR "ValidateSubDirOrDie: return $globc\n" if ( $CLIC_DEBUG > 20);
    return $globc; # possible modified (cleaned up)
} # ValidateSubDirOrDie

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

sub returnTF {
  local $_ = shift;
  if ( $_ ) { return 'TRUE'; }
  return 'FALSE';
} # returnTF
################################################################################
################################################################################
############################# SUPPORT SUBROUTINES ##############################
################################################################################
# LEAVE #######################################################################}

# this last line is need by perl
1;
