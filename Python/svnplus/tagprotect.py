#
#  Copyright 2015,2016,2017 Joseph C. Pietras
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

################################################################################
# This subversion hook originated in PERL and was later rewritten in Python
################################################################################
from __future__ import print_function
import sys
import os
import re
import fnmatch
import subprocess
import time

VERSION = '3.19.1'

# FATAL ERROR
exitFatalErr = 1

# USER ASKED FOR HELP, PARSE, etc, from command line
exitSuccess = 0

###############################################################################[
# ENTER: HARD DEFAULTS FOR CONFIG FILE, VARIABLES SET IN THE CONFIG FILE, etc.
# hard default                        actual variable      variable looked for
# if not in config                  init w/useless value   in configuration file
# CLI (currently 11 variables for command line parse - some can't be set (auto set)
#  1
#  --debug/-d/--debug=N/-dN
#     CLIC_DEBUG                          # CLI command line debug level
#     CLIF_DEBUG                          # debug level from config file parse, if any
VAR_H_DEBUG = "DEBUG"                     # looked for in config file
DEF_H_DEBUG = 0                           # default - some low level debug can only be seen by
                                          # changing the default, here, to a high level!
#  2
#  not cli setable, but config setable, or default=/usr/bin/svnlook
#      CLISVNLOOK                         # CLI, path to svnlook program
VAR_SVNLOOK = "SVNLOOK"                   # variable looked for in config file
DEF_SVNLOOK = "/usr/bin/svnlook"          # default value if not in config;
#  3
#  not cli setable, but config setable, or default=/usr/bin/svn
#      CLISVNPATH                         # CLI, path to svn program
VAR_SVNPATH = "SVNPATH"                   # variable looked for in config file
DEF_SVNPATH = "/usr/bin/svn"              # default value if not in config
#  4
# command line can set, or default=0
#  --build/-b
#      CLIBLDPREC                         # CLI, output PERL pre-build config from config file
#  5
# command line can set, or default
#  --parse/-p
#      CLIJUSTCFG                         # CLI, just parse the config and exit
#  6
# command line can set, or default is STDOUT
#  --input=<file>/-i<file>
#      CLI_INFILE                         # CLI, name of input file overrides default config files
#  7
# command line can set, or default is STDOUT
#  --output=<file>/-o<file>
#      CLIOUTFILE                         # CLI, name of output file, receives config output
#  8
# command line can set, or default from PERL library name
#  --revert/-r
#      CLIDUMP_PL                         # CLI, reverse the above, PERL prebuild to config file
#  9
#  not cli setable, this is auto detected
#      CLIRUNNING                         # CLI, flag running from command line?
# 10
#  not cli setable, set by subversion when in PRODUCTION, or "useless" default for debug
#      CLISVN_TID                        # CLI, subversion transaction key
# 11
#  not cli setable, set by subversion when in PRODUCTION, or sensible default for debug
#      CLISVNREPO                         # CLI, path to svn repository
# CFG (currently 5 keys)
#  1
VAR_TAGDIRE = "PROTECTED_PARENT"          # variable looked for in config file
DEF_TAGDIRE = "/tags"                     # default value if not in config
TAGpKEY     = VAR_TAGDIRE                 # CFG key, key for this N-Tuple, must be a real path
#  2
# these (missing lines)
# not needed for line number
LINEKEY = "ProtectLineNo"                 # CFG key, line number in the config file of this tag directory
#  3
VAR_SUBDIRE = "PROTECTED_PRJDIRS"         # variable looked for in config file
DEF_SUBDIRE = DEF_TAGDIRE + "/*"          # default value if not in config
SUBfKEY     = VAR_SUBDIRE                 # CFG key, subdirectories will be "globbed"
#  4
VAR_MAKESUB = "PRJDIR_CREATORS"           # variable looked for in config file
DEF_MAKESUB = "*"                         # default value if not in config
MAKEKEY     = VAR_MAKESUB                 # CFG key, those who can create sub directories
#  5
VAR_NAME_AF = "ARCHIVE_DIRECTORY"         # variable looked for in config file
DEF_NAME_AF = "Archive"                   # default value if not in config
NAMEKEY     = VAR_NAME_AF                 # CFG key, directory name of the archive directory(s)
# LEAVE: HARD DEFAULTS FOR CONFIG FILE, VARIABLES SET IN THE CONFIG FILE, etc ]
################################################################################

###############################################################################[
# ENTER: VARIABLES WITH FILE SCOPE all with sensible defaults
Tuple_CNT  = 0                           # count of keys, for building a N-Tuple key
Tuple_STR  = "Config_Tuple"              # string part of a N-Tuple key
CLIBLD_DEF = 0                           # 1 if --generate on command line
CLIBLDPREC = 0                           # 1 if --build on command line
CLIRUNNING = 0                           # 1 if we know we are running CLI
CLICONFIGF = ""                          # name of config file, defaulted below - but it can be changed
CLIDUMP_PL = 0                           # 1 if --dump on command line => revert precompiled config file
CLIC_DEBUG = DEF_H_DEBUG                 # N if --debug
CLIF_DEBUG = -1                          # -1 => no debug level gotten from configuration file parse
CLIJUSTCFG = 0                           # 1 if --parse on command line
CLI_INFILE = ""                          # file to read input from (depending on command line options)
CLIOUTFILE = ""                          # file to write output to (depending on command line options)
CLIPRECONF = ""                          # name of precompiled config file, defaulted below, it can be changed
CLISVNREPO = ""                          # path to repo -- this from subversion or dummied up
CLISVN_TID = ""                          # transaction id -- this from subversion or dummied up
CLISVNLOOK = DEF_SVNLOOK                 # path to svnlook, can be changed in config file
CLISVNPATH = DEF_SVNPATH                 # path to svn, can be changed in config file
PROGNAME = ""                            # program name
PROGDIRE = ""                            # program directory, usually ends with "hooks"
cfgDofD = dict()                         # dict of dicts - holds all configs
CommitData = []                          # svnlook output split into an array of files/directories
                                         # unless in command line mode
# LEAVE: VARIABLES WITH FILE SCOPE all with sensible defaults
###############################################################################]

## ENTER: #####################################################################[
######### regular expressions used parsing the config file #####################
pat = '^{0}$'.format(VAR_H_DEBUG)
regvar_H_DEBUG = re.compile(pat, re.IGNORECASE)
pat = '^{0}$'.format(VAR_MAKESUB)
regvar_MAKESUB = re.compile(pat, re.IGNORECASE)
pat = '^{0}$'.format(VAR_NAME_AF)
regvar_NAME_AF = re.compile(pat, re.IGNORECASE)
pat = '^{0}$'.format(VAR_SUBDIRE)
regvar_SUBDIRE = re.compile(pat, re.IGNORECASE)
pat = '^{0}$'.format(VAR_SVNLOOK)
regvar_SVNLOOK = re.compile(pat, re.IGNORECASE)
pat = '^{0}$'.format(VAR_SVNPATH)
regvar_SVNPATH = re.compile(pat, re.IGNORECASE)
pat = '^{0}$'.format(VAR_TAGDIRE)
regvar_TAGDIRE = re.compile(pat, re.IGNORECASE)
pat = '^(.)(.*)(.)$'
reg_1ST_N_LAST = re.compile(pat)
pat = '^(\s*)([^\s]+)(\s*)=(\s*)([^\s]+)(\s*)$'
reg_EQUAL_SIGN = re.compile(pat)
######### regular expressions used parsing the config file ######################
## LEAVE: ######################################################################]

## ENTER: ######################################################################[
########################### PROTECTED/PRIVATE METHODS ###########################
#################################################################################
def _is_under_protection(pDir, artifact): # {
                                          # pDir     -> protected (parent) directory
                                          # artifact -> to be added
    global CLIF_DEBUG
    leftside = ''                   # left side of artifact, length of pDir
    r = False                       # returned value
    tmp = ''
    if CLIF_DEBUG > 7:
        print('_is_under_protection: enter pDir: "{0}"'.format(pDir), file=sys.stderr)
        print('_is_under_protection: enter artifact: "{0}"'.format(artifact), file=sys.stderr)
    if pDir == "/":
        # THIS IS CODED THIS WAY, HERE INSTEAD OF BELOW, IN CASE "/" IS DISALLOWED IN FUTURE (perhaps it should be?)
        r = True                   # this will always match everything!
        if CLIF_DEBUG > 7:
            print('_is_under_protection: protected directories is "/" it always matches everything', file=sys.stderr)
    else:
        # the protected (parent) directory is given literally like: "/tags"
        # but can contain who knows what (even meta chars to be taken as is)
        tmp = len(pDir)
        leftside = artifact[0:tmp]
        if CLIF_DEBUG > 7:
            print('_is_under_protection: artifact="{0}"'.format(artifact), file=sys.stderr)
            print('_is_under_protection: checking exact match ({0} == {1}) '.format(leftside, pDir), file=sys.stderr, end='')
        if leftside == pDir:
            if CLIF_DEBUG > 7:
                print("YES", file=sys.stderr)
            r = True
        else:
            if CLIF_DEBUG > 7:
                print("NO", file=sys.stderr)
            r = False
    if CLIF_DEBUG > 7:
        print("_is_under_protection: return {0}".format(r), file=sys.stderr)
    return r         # _is_under_protection }

def _adding_archive_dir(parent, allsub, archive, artifact):  # {
                                                             # parent   -> this does NOT end with SLASH, protected "parent" directory
                                                             # allsub   -> this does NOT end with SLASH, subdirectories (as a path containing all the "parts" of the path)
                                                             # archive  -> name of the archive directory(s) for this configuration N-Tuple
                                                             # artifact -> may or may not end with SLASH - indicates files or directory
    global CLIF_DEBUG
    r       = False   # assume failure
    sstr    = ''      # subdirectory string - used for parsing allsub into the suball list
    suball  = [ ]     # hold the parts of allsub, allsub can be a glob
    glob    = ''      # build up from the allsub string split apart into suball
    isDir   = False;  # assume artifact is a file
    tmp     = ''
    if artifact[-1] == '/':
        isDir   = True
    if isDir:
        sstr = allsub;            # start with the subdirectory config value
        if CLIF_DEBUG > 7:
            print('_adding_archive_dir: sstr={0}'.format(sstr), file=sys.stderr)
        tmp = '^' + parent
        sstr = re.sub(tmp, "", sstr)    # remove the parent with FIRST SLASH
        suball = sstr.split('/')
        # walk the longest path to the shortest path
        while len(suball) > 0:
            glob = parent
            glob += "/".join(suball)
            if not re.match(r'/$', glob):
                glob += '/'
            glob += archive
            glob += '/'
            if re.match(glob, artifact):
                if CLIF_DEBUG > 7:
                    print('_adding_archive_dir: re.match({0}, {1}) = YES'.format(glob, artifact), file=sys.stderr)
                r = True             # we have a match
                break
            elif CLIF_DEBUG > 7:
                print('_adding_archive_dir: re.match({0}, {1}) = NO'.format(glob, artifact), file=sys.stderr)
            del suball[-1]
    elif CLIF_DEBUG > 7:
        print('_adding_archive_dir: "{0}" is a FILE'.format(artifact), file=sys.stderr)
    if CLIF_DEBUG > 7:
        print('_adding_archive_dir: return {0}\tartifact={1}'.format(r, artifact), file=sys.stderr)
    return r                             # _adding_archive_dir }

def _adding_sub_dir(parent, allsub, artifact): # {
                                               # parent   -> parent to be protected
                                               # allsub   -> list of all subdirectories of parent that are to be protected
                                               # artifact -> what is being added
    global CLIF_DEBUG
    r    = False             # assume failure
    glob = ''                # build up from the allsub string split apart into suball
    if artifact[-1] == '/':
        sstr = allsub             # subdirectory string - used for parsing allsub into the suball - start with the subdirectory config value
        if CLIF_DEBUG > 7:
            print('_adding_sub_dir: sstr={0}'.format(sstr), file=sys.stderr)
        tmp = '^'
        tmp += parent
        sstr = re.sub(tmp, "", sstr)    # remove the parent with FIRST SLASH
        suball = sstr.split('/')        # hold the parts of allsub, allsub can be a glob
        while len(suball) > 0:          # walk the longest path to the shortest path
            glob = parent
            glob += "/".join(suball)
            if not re.match('/$', glob):
                glob += '/'
            if re.match(glob, artifact):
                if CLIF_DEBUG > 7:
                    print('_adding_sub_dir: re.match({0}, {1}) = YES'.format(glob, artifact), file=sys.stderr)
                r = True             # we have a match
                break
            elif CLIF_DEBUG > 7:
                print('_adding_sub_dir: re.match({0}, {1}) = NO'.format(glob, artifact), file=sys.stderr)
            del suball[-1] # remove last element
    elif CLIF_DEBUG > 5:
        print('_adding_sub_dir: {0} is a FILE'.format(artifact), file=sys.stderr)
    if CLIF_DEBUG > 5:
        print('_adding_sub_dir: return {0}\tartifact={1}'.format(r, artifact), file=sys.stderr)
    return r                   # _adding_sub_dir }

# EACH ARTIFACT HAS TO BE TESTED TO SEE IF IT IS UNDER PROTECTION
# WHICH MEANS LOOPING THROUGH ALL CONFIGURATIONS
def _artifact_under_protected_dir(artifact): # {
                                             # artifact -> a file or directory being added
    global CLIF_DEBUG
    global TAGpKEY
    global cfgDofD
    parent      = ''       # protected directory
    tupleKey    = ''
    returnKey   = ''
    isProtected = False    # assume not protected
    for tupleKey in cfgDofD:
        parent = cfgDofD[tupleKey][TAGpKEY]
        if CLIF_DEBUG > 8:
            print('_artifact_under_protected_dir: tupleKey=>>{0}<<, parent=>>{1}<<'.format(tupleKey, parent), file=sys.stderr)
        if _is_under_protection(parent, artifact) == True:
            returnKey   = tupleKey;
            isProtected = True
            break
    if CLIF_DEBUG > 8:
        print('_artifact_under_protected_dir: return: isProtected>>{0}<<, returnKey>>{1}<<'.format(isProtected, returnKey), file=sys.stderr)
    return [ isProtected, returnKey ] # _artifact_under_protected_dir }

def _authorized(author, authOK, artifact, msgwords): # {
                                                     # author   -> committer of this change
                                                     # authOK   -> those allowed to commit
                                                     # artifact -> what requires authorization
                                                     # msgwords -> description of what is being added
    global CLIF_DEBUG
    global PROGNAME
    global exitFatalErr
    isauth   = False        # assume failure
    auth = dict()
    user = ''
    if authOK == '*':
        if CLIF_DEBUG > 5:
            print('_authorized: allow because authorization is the "*" character', file=sys.stderr)
        isauth = True
    elif author == '':
        print('{0}: commit failed due to being unable to authenticate.'.format(PROGNAME), file=sys.stderr)
        print('{0}: the author of this commit is BLANK, apparently there is'.format(PROGNAME), file=sys.stderr)
        print('{0}: no authentication required by subversion (apache or html server).'.format(PROGNAME), file=sys.stderr)
        print('{0}: ABORTING - tell the subversion administrator.'.format(PROGNAME), file=sys.stderr)
        sys.exit(exitFatalErr)
    else:
        auth = authOK.split(',')
        for user in auth:
            user = re.sub('\s+', '', user)
            if user == author:
                if CLIF_DEBUG > 5:
                    print( '_authorized: allow because author matches: "{0}"'.format(user), file=sys.stderr)
                isauth = True
                break
            elif user == '*':
                if CLIF_DEBUG > 5:
                    print('_authorized: allow because one of users is the '*' character', file=sys.stderr)
                isauth = True
                break
    if isauth == False:
        print( '{0}: failed on: {1}'.format(PROGNAME, artifact), file=sys.stderr)
        print( '{0}: authorization failed, you cannot "{1}"'.format(PROGNAME, msgwords), file=sys.stderr)
        print( '{0}: commiter "{1}" does not have authorization'.format(PROGNAME, author), file=sys.stderr)
    return isauth                        # _authorized }

def _fix_path(pathstr, no1stSlash, addLastSlash): # {
                                                  # pathstr      -> path string to be fixed up (modified)
                                                  # no1stSlash   -> if true remove any initial slash
                                                  # addListSlash -> if true returned path will end with slash
    if pathstr != "" and pathstr != "/":
        pathstr = re.sub(r'/+$', '', pathstr)
        if pathstr == "":
            pathstr = "/"
        elif no1stSlash:
            pathstr = re.sub(r'^/', '', pathstr)
        if addLastSlash > 0:
            pathstr += "/"
    return pathstr                      # _fix_path }

# CREATE A FORMAT STRING USED WHEN GENERATING A CONFIG FILE
def _fmt_str(): # {
    global VAR_H_DEBUG
    global VAR_MAKESUB
    global VAR_NAME_AF
    global VAR_SUBDIRE
    global VAR_SVNLOOK
    global VAR_SVNPATH
    global VAR_TAGDIRE
    a =  [
           len( VAR_H_DEBUG ),
           len( VAR_SVNLOOK ),
           len( VAR_SVNPATH ),
           len( VAR_TAGDIRE ),
           len( VAR_SUBDIRE ),
           len( VAR_MAKESUB ),
           len( VAR_NAME_AF )
         ]
    r = int(max(a))
    f = '%-'
    f += str(r)
    f += 's'
    return f    # }

# INPUT STRING 's' IS RETURNED FORMATTED WHEN GENERATING A CONFIG FILE
def _get_fmt_str(s): # {
    f = _fmt_str()
    r = f % ( s )
    return r         # }

# BUILD A KEY FOR THE OUTER DICTIONARY
def _gen_tuple_key(keyStr, keyCnt): # {
                                  # keyStr -> initial part of key, same as the global Tuple_Str
                                  # keyCnt -> integer count
    key = "%s_%03d" % ( keyStr, keyCnt )
    return key                      # }

# THIS IS CALLED DURING CONFIGUATION PARSE - NOT OTHERWISE
# the subdirectory given, if not the empty string, must be
# a subdirectory of the associated tag directory (the one
# to protect).  E.g:
#     if   "/tags" is the directory to be protected then
#     then "/tags/<whatever>" is acceptable, but
#          "/foobar/<whatever>" is NOT
# The subdirectory specification must truly be a subdirectory
# of the associated directory to be protected.
def _validate_sub_dir_or_die(pDire, globc, lline): # {
                                                   # pDire -> directory name of tag to protect
                                                   # globc -> the subdirectory "glob" string/path
                                                   # lline -> current config file line
    global CLICONFIGF
    global CLIF_DEBUG
    global PROGNAME
    global SUBfKEY
    global TAGpKEY
    global exitFatalErr
    # a BLANK regex means that the tag directory does not allow _any_
    # project names, hey that's ok!  if so there is no need to test
    if CLIF_DEBUG > 6:
        print('_validate_sub_dir_or_die: enter: pDire="{0}"'.format(pDire), file=sys.stderr)
        print('_validate_sub_dir_or_die: enter: globc="{0}"'.format(globc), file=sys.stderr)
        print('_validate_sub_dir_or_die: enter: lline="{0}"'.format(lline), file=sys.stderr)
    if globc != "":
        tmp = '('+pDire+')(.+)'
        leftP = re.sub(tmp, r'\1', globc)
        right = re.sub(tmp, r'\2', globc)
        if pDire != leftP:
            print('{0}: configuration file:'.format(PROGNAME), file=sys.stderr)
            print('        "{0}"'.format(CLICONFIGF), file=sys.stderr)
            print('{0}: is misconfigured at approximately line {1}.'.format(PROGNAME, lline), file=sys.stderr)
            print('{0}: the variable=value pair:'.format(PROGNAME), file=sys.stderr)
            print('        {0}="{1}"'.format(TAGpKEY, pDire), file=sys.stderr)
            print('{0}: the variable=value pair:'.format(PROGNAME), file=sys.stderr)
            print('        {0}="{1}"'.format(SUBfKEY, globc), file=sys.stderr)
            print('{0}: are out of synchronization.'.format(PROGNAME), file=sys.stderr)
            print('{0}: a correct variable=value pair would be, for example:'.format(PROGNAME), file=sys.stderr)
            print('        {0}="{1}/*"'.format(SUBfKEY, pDire), file=sys.stderr)
            print('{0}: the {1} value (path) MUST be the'.format(PROGNAME, TAGpKEY), file=sys.stderr)
            print('{0}: the first path in {1} (it must start with that path)'.format(PROGNAME, SUBfKEY), file=sys.stderr)
            print('{0}: unless {1} is the empty string (path).'.format(PROGNAME,SUBfKEY ), file=sys.stderr)
            print('{0}: ABORTING - tell the subversion administrator.'.format(PROGNAME), file=sys.stderr)
            sys.exit(exitFatalErr)
        # clean up the subdirectory "glob" (or it could be a literal path, we still clean it up)
        if CLIF_DEBUG > 6:
            print('_validate_sub_dir_or_die: initial       right="{0}"'.format(right), file=sys.stderr)
        tmp = right    # the "backslash" is not allowed, it can only lead to problems!
        tmp = re.sub(r'\\', r'', right)
        if CLIF_DEBUG > 6:
            print('_validate_sub_dir_or_die: rm backslash  tmp="{0}"'.format(tmp), file=sys.stderr)
        tmp = re.sub(r'/+', r'/', tmp)
        if CLIF_DEBUG > 6:
            print('_validate_sub_dir_or_die: rm single sep tmp="{0}"'.format(tmp), file=sys.stderr)
        while re.match(r'/\.\./', tmp) is not None:  # /../ changed to / in a loop
            tmp = re.sub(r'/\.\./', r'', tmp)
            tmp = re.sub(r'/+', r'/', tmp)        # don't see how this could happen, but safety first
            if CLIF_DEBUG > 6:
                print('_validate_sub_dir_or_die: in clean loop tmp="{0}"'.format(tmp), file=sys.stderr)
        if CLIF_DEBUG > 5:
            print('_validate_sub_dir_or_die: done          tmp={0}'.format(tmp), file=sys.stderr)
        globc = leftP
        globc += tmp
    else:
        if CLIF_DEBUG > 6:
            print('_validate_sub_dir_or_die: globc="{0}", no modifications'.format(globc), file=sys.stderr)
    if CLIF_DEBUG > 6:
        print('_validate_sub_dir_or_die: return        globc="{0}"'.format(globc), file=sys.stderr)
    return globc # possible modified (cleaned up) _validate_sub_dir_or_die }

# PUT AN N-Tuple INTO THE DICT OF DICT
# THIS IS WHAT THIS METHOD "instantiates":
#   currently an N-Tuple has 4 elements
#   the the 1st is required (and must be already contained in cfgDict)
#   and the next 3 default if they are not in cfgDict
def _load_cfg_tuple(cfgDict = dict): # {
                                     # cfgDict -> just parsed configuration to be loaded into cfgDofD
    global CLICONFIGF
    global LINEKEY
    global MAKEKEY
    global NAMEKEY
    global PROGNAME
    global SUBfKEY
    global TAGpKEY
    global Tuple_CNT
    global Tuple_STR
    global VAR_MAKESUB
    global VAR_NAME_AF
    global VAR_SUBDIRE
    global VAR_TAGDIRE
    global cfgDofD
    global exitFatalErr
    key = ""                   # used to build the key from the string and the number
    # the outer most dictionary, named cfgDofD, will load (copy) the above dictionary (not the reference)
    # along with the information needed to construct the key needed to push the above dictionary into
    # it.  Got that?
    # check that incoming (inner) dictionary has a directory in it to be protected
    if not NAMEKEY in cfgDict or not MAKEKEY in cfgDict or not TAGpKEY in cfgDict or not LINEKEY in cfgDict or not SUBfKEY in cfgDict:
        # give the line number a bogus value if it has no value
        if not LINEKEY in cfgDict:
            cfgDict[LINEKEY] = 0
        print("{0}: See configuration file: {1}".format(PROGNAME, CLICONFIGF), file=sys.stderr)
        if not TAGpKEY in cfgDict:
            print("{0}: The value of {1} does not exist for the configuration set!".format(PROGNAME, VAR_TAGDIRE), file=sys.stderr)
        if not SUBfKEY in cfgDict:
            print("{0}: The value of {1} does not exist for the configuration set!".format(PROGNAME, VAR_SUBDIRE), file=sys.stderr)
        if not NAMEKEY in cfgDict:
            print("{0}: The value of {1} does not exist for the configuration set!".format(PROGNAME, VAR_NAME_AF), file=sys.stderr)
        if not MAKEKEY in cfgDict:
            print("{0}: The value of {1} does not exist for the configuration set!".format(PROGNAME, VAR_MAKESUB), file=sys.stderr)
        print("{0}: Around line number: {1}".format(PROGNAME, cfgDict[LINEKEY]), file=sys.stderr)
        print("{0}: Failure in subroutine _load_cfg_tuple.".format(PROGNAME), file=sys.stderr)
        print("{0}: ABORTING - tell the subversion administrator.".format(PROGNAME), file=sys.stderr)
        sys.exit(exitFatalErr)
    elif not TAGpKEY in cfgDict:
        # give the line number a bogus value if it has no value
        if not LINEKEY in cfgDict:
            cfgDict[LINEKEY] = 0
        print("{0}: See configuration file: {1}".format(PROGNAME, CLICONFIGF), file=sys.stderr)
        print("{0}: The value of {1} is blank.".format(PROGNAME, VAR_TAGDIRE), file=sys.stderr)
        print("{0}: Around line number: {1}".format(PROGNAME, cfgDict[LINEKEY]), file=sys.stderr)
        print("{0}: Failure in subroutine _load_cfg_tuple.".format(PROGNAME), file=sys.stderr)
        print("{0}: ABORTING - tell the subversion administrator.".format(PROGNAME), file=sys.stderr)
        sys.exit(exitFatalErr)
    # get new key for outer dictionary
    key = _gen_tuple_key(Tuple_STR, Tuple_CNT);
    Tuple_CNT += 1
    # insist that this new configuration plays by the rules
    cfgDict[SUBfKEY] = _validate_sub_dir_or_die(cfgDict[TAGpKEY], cfgDict[SUBfKEY], cfgDict[LINEKEY])
    cfgDofD[key] = cfgDict      # this allocates (copies) inner dictionary
    return # _load_cfg_tuple -- return no value }

def _print_default_config_optionally_exit(print_exit, filename, where): # {
                                                                        # print_exit -> if True call sys.exit()
                                                                        # filename   -> filename of where to send the default config
                                                                        # where      -> file handle to be printed to

    global CLIF_DEBUG
    global DEF_H_DEBUG
    global DEF_MAKESUB
    global DEF_NAME_AF
    global DEF_SUBDIRE
    global DEF_SVNLOOK
    global DEF_SVNPATH
    global DEF_TAGDIRE
    global VAR_H_DEBUG
    global VAR_MAKESUB
    global VAR_NAME_AF
    global VAR_SUBDIRE
    global VAR_SVNLOOK
    global VAR_SVNPATH
    global VAR_TAGDIRE
    global exitSuccess
    ##############################################################
    q = '"';
    str = ''
    if filename == "":
        output   = sys.stdout
        filename = "STDOUT"
    else:
        output   = where    # caller already opened it
    if CLIF_DEBUG > 0:
        if print_exit == True:
            print("_print_default_config_optionally_exit: output default header.", file=sys.stderr)
        else:
            print("_print_default_config_optionally_exit: output default configuration file to: {0}".format(filename))
    print("#", file=output)
    print("#  The parsing script will build an 'N-Tuple' from each", file=output)
    print("#  {0} variable/value pair.  If the other".format(VAR_TAGDIRE), file=output)
    print("#  variable/value pairs do not follow one of the", file=output)
    print("#  {0} variable/value pairs, they will".format(VAR_TAGDIRE), file=output)
    print("#  default.", file=output)
    print("#", file=output)
    print("# Recognized variable/value pairs are:", file=output)
    print("#   These are for debugging and subversion", file=output)
    print("#          {0}\t\t= N".format(VAR_H_DEBUG), file=output)
    print("#          {0}\t\t= path to svn".format(VAR_SVNPATH), file=output)
    print("#          {0}\t\t= path to svnlook".format(VAR_SVNLOOK), file=output)
    print("#   These make up an N-Tuple", file=output)
    print("#          {0}\t= /<path>".format(VAR_TAGDIRE), file=output)
    print("#    e.g.: {0}\t= /<path>/*".format(VAR_SUBDIRE), file=output)
    print("# or e.g.: {0}\t= /<path>/*/*".format(VAR_SUBDIRE), file=output)
    print("#          {0}\t= '*' or '<user>, <user>, ...'".format(VAR_MAKESUB), file=output)
    print("#          {0}\t= <name>".format(VAR_NAME_AF), file=output)
    print("", file=output)
    print("### These should be first", file=output)
    str = _get_fmt_str(VAR_H_DEBUG)
    print("{0} = {1}".format(str, DEF_H_DEBUG), file=output)
    str = _get_fmt_str(VAR_SVNPATH)
    print("{0} = {1}{2}{3}".format(str, q, DEF_SVNPATH, q), file=output)
    str = _get_fmt_str(VAR_SVNLOOK)
    print("{0} = {1}{2}{3}".format(str, q, DEF_SVNLOOK, q), file=output)
    print("", file=output)
    print("### These comprise an N-Tuple, can be repeated as many times as wanted,", file=output)
    print("### but each {0} value must be unique.   It is not allowed to".format(VAR_TAGDIRE), file=output)
    print("### try to configure the same directory twice (or more)!", file=output)
    if print_exit == True:
        str = _get_fmt_str(VAR_TAGDIRE)
        print("{0} = {1}{2}{3}".format(str, q, DEF_TAGDIRE, q), file=output)
        str = _get_fmt_str(VAR_SUBDIRE)
        print("{0} = {1}{2}{3}".format(str, q, DEF_SUBDIRE, q), file=output)
        str = _get_fmt_str(VAR_MAKESUB)
        print("{0} = {1}{2}{3}".format(str, q, DEF_MAKESUB, q), file=output)
        str = _get_fmt_str(VAR_NAME_AF)
        print("{0} = {1}{2}{3}".format(str, q, DEF_NAME_AF, q), file=output)
        if CLIF_DEBUG > 0:
            print("_print_default_config_optionally_exit: exit successful after generate default config file." , file=sys.stderr)
        sys.exit(exitSuccess)    # only exit if doing the whole thing
    return                        # _print_default_config_optionally_exit }

# PRINT USAGE TO STANDARD OUTPUT AND THEN EXIT SUCCESS(0)
def _print_usage_and_exit(): # {
    global CLICONFIGF
    global CLIPRECONF
    global CLISVNLOOK
    global CLISVNPATH
    global PROGNAME
    global VERSION
    global exitSuccess
    ####################################
    look = os.path.basename(CLISVNLOOK)
    svn = os.path.basename(CLISVNPATH)
    ####################################
    print("", file=sys.stdout)
    print("usage: {0} repo-name transaction-id  - Normal usage under Subversion.".format(PROGNAME), file=sys.stdout)
    print("OR:    {0} --help                    - Get this printout.".format(PROGNAME), file=sys.stdout)
    print("OR:    {0} [--debug=N] [options]     - configuration testing and debugging.".format(PROGNAME), file=sys.stdout)
    print("", file=sys.stdout)
    print("    THIS SCRIPT IS A HOOK FOR SUBVERSION AND IS NOT RUN FROM THE COMMAND", file=sys.stdout)
    print("    LINE DURING PRODUCTION USAGE.", file=sys.stdout)
    print("", file=sys.stdout)
    print("    The required arguments, repo-name and transaction-id, are", file=sys.stdout)
    print("    provided by subversion.  This subversion hook uses:", file=sys.stdout)
    print("        {0}".format(look), file=sys.stdout)
    print('    the path of which can be configured and defaults to: {0}'.format(CLISVNLOOK), file=sys.stdout)
    print("    and {0}".format(svn), file=sys.stdout)
    print('    the path of which can be configured and defaults to: {0}'.format(CLISVNPATH), file=sys.stdout)
    print("", file=sys.stdout)
    print("    It uses the configuration file:", file=sys.stdout)
    print("        {0}".format(CLICONFIGF), file=sys.stdout)
    print("    If it exists, this \"precompiled\" file will take precedence:", file=sys.stdout)
    print("        {0}".format(CLIPRECONF), file=sys.stdout)
    print("    and the configuration file will not be read.", file=sys.stdout)
    print("", file=sys.stdout)
    print("    When invoked from the command line it will accept these additional", file=sys.stdout)
    print("    options, there is no way you can give these in PRODUCTION while running", file=sys.stdout)
    print("    under subversion.", file=sys.stdout)
    print("    --help            | -h      Show usage information and exit.", file=sys.stdout)
    print("", file=sys.stdout)
    print("    --debug[=n]       | -d[n]   Increment or set the debug value.  If given this", file=sys.stdout)
    print("                                command line option should be first.", file=sys.stdout)
    print("", file=sys.stdout)
    print("    --generate        | -g      Generate a default configuration file with", file=sys.stdout)
    print("                                comments and  write it to standard output.", file=sys.stdout)
    print("", file=sys.stdout)
    print("    --parse           | -p      Parse  the  configuration file then exit.", file=sys.stdout)
    print("                                Errors found in the configuration will be printed", file=sys.stdout)
    print("                                to standard error.  If there are no errors you will", file=sys.stdout)
    print("                                get no output unless debug is greater than zero(0).", file=sys.stdout)
    print("", file=sys.stdout)
    print("    --build           | -b      Build a \"precompiled\" configuration file with", file=sys.stdout)
    print("                                comments from the configuration file and write", file=sys.stdout)
    print("                                it to standard output. This speeds up reading", file=sys.stdout)
    print("                                the configuration in PRODUCTION but is only needed", file=sys.stdout)
    print("                                by sites with a large large number of configurations,", file=sys.stdout)
    print("                                say 20 or more, your mileage may vary - and only if", file=sys.stdout)
    print("                                the server is old and slow. If a precompiled", file=sys.stdout)
    print("                                configuration exists it will be read and the regular", file=sys.stdout)
    print("                                regular configuration file will be ignored.", file=sys.stdout)
    print("", file=sys.stdout)
    print("    --revert        | -r        Opposite of, --build, write to standard output a", file=sys.stdout)
    print("                                configuration file from a previously built", file=sys.stdout)
    print("                                \"precompiled\" configuration file.", file=sys.stdout)
    print("", file=sys.stdout)
    print("    --input=file    | -ifile    Input from \"file\", or output to \"file\", these options", file=sys.stdout)
    print("    --output=file   | -ofile    are used to name an alternate configuration file or an", file=sys.stdout)
    print("                                alternate pre-compiled configuration file.", file=sys.stdout)
    print("", file=sys.stdout)
    print("    --version       | -v        Output the version and exit.", file=sys.stdout)
    print("", file=sys.stdout)
    print("", file=sys.stdout)
    print("NOTE: a typical command line usage for debugging purposes would look", file=sys.stdout)
    print("      like this", file=sys.stdout)
    print("        ./{} --debug=N [options] < /dev/null".format(PROGNAME), file=sys.stdout)
    print("", file=sys.stdout)
    print("{0}: {1}".format(PROGNAME, VERSION), file=sys.stdout)
    print("", file=sys.stdout)
    sys.exit(exitSuccess) # _print_usage_and_exit }

def _print_version_and_exit(): # {
    global VERSION
    global exitSuccess
    print("{0}".format(VERSION), file=sys.stdout)
    sys.exit(exitSuccess)      # }

# CANNOT DETERMINE WHAT THE CURRENT REQUESTED COMMIT DOES:
#  - one or more artifacts cannot be correctly parsed
#  - this is called when everything else fails, increase debug for more information
def _say_impossible(): # {
    global PROGNAME
    print('{0}: it appears this commit does not modify, add, or delete anything!'.format(PROGNAME), file=sys.stderr)
    print('{0}: commited failed, re: UNKNOWN!'.format(PROGNAME), file=sys.stderr)
    return False       # }

def _say_no_delete(what): # {
                          # what -> a specific artifact to commit that caused the failure
    global PROGNAME
    print('{0}: commit failed, delete of protected directories is not allowed!'.format(PROGNAME), file=sys.stderr)
    print('{0}: commit failed on: {1}'.format(PROGNAME, what), file=sys.stderr)
    return False         # }

def _svn_get_author(): # {
    global CLIF_DEBUG
    global CLISVNLOOK
    global CLISVNREPO
    global CLISVN_TID
    global PROGNAME
    global exitFatalErr
    what = "author"
    cmd       = [ CLISVNLOOK, "--transaction", CLISVN_TID, what, CLISVNREPO ] # command to run
    svnErrors = ''          # STDERR of command SVNLOOK - any errors
    svnAuthor = ''          # STDOUT of command SVNLOOK - creator
    svnExit = 0             # exit value of command SVNLOOK
    child = ''              # object created by subprocess
    if CLIF_DEBUG > 5:
        print('_svn_get_author: cmd = {0}'.format(' '.join(cmd)), file=sys.stderr)
    child = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    svnAuthor, svnErrors = child.communicate()
    svnExit = child.returncode
    if CLIF_DEBUG > 5:
        if CLIF_DEBUG > 6:
            print('_svn_get_author: svnExit=  "{0}"'.format(svnExit), file=sys.stderr)
            print('_svn_get_author: svnErrors="{0}"'.format(svnErrors), file=sys.stderr)
        print('_svn_get_author: svnAuthor="{0}"'.format(svnAuthor), file=sys.stderr)
    # svnAuthor always contains a trailing newline, removed it
    svnAuthor = svnAuthor.rstrip()
    if svnExit:
        print('{0}: "{1}" failed to get "{2}" (exit={3}), re: {4}\n'.format(PROGNAME, CLISVNLOOK, what, svnExit, svnErrors), file=sys.stderr)
        print('{0}: command: "{1}"'.format(PROGNAME, ' '.join(cmd)), file=sys.stderr)
        print('{0}: ABORTING - tell the subversion administrator.\n'.format(PROGNAME), file=sys.stderr)
        sys.exit(exitFatalErr)
    if CLIF_DEBUG > 5:
        print('_svn_get_author: return "{0}"'.format(svnAuthor), file=sys.stderr)
    return svnAuthor # _svn_get_author }

def _svn_get_commit(): # {
    global CLIF_DEBUG
    global CLISVNLOOK
    global CLISVNREPO
    global CLISVN_TID
    global CommitData
    global PROGNAME
    global exitFatalErr
    what = "changed"
    cmd       = [ CLISVNLOOK, "--transaction", CLISVN_TID, what, CLISVNREPO ] # command to run
    svnErrors = ''          # STDERR of command SVNLOOK - any errors
    svnOutput = ''          # STDOUT of command SVNLOOK - creator
    svnExit = 0             # exit value of command SVNLOOK
    child = ''              # object created by subprocess
    if CLIF_DEBUG > 5:
        print('_svn_get_commit: cmd = {0}'.format(' '.join(cmd)), file=sys.stderr)
    child = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    svnOutput, svnErrors = child.communicate()
    svnExit = child.returncode
    if CLIF_DEBUG > 5:
        print('_svn_get_commit: svnExit=  >>{0}<<'.format(svnExit), file=sys.stderr)
        print('_svn_get_commit: svnErrors=>>{0}<<'.format(svnErrors), file=sys.stderr)
        print('_svn_get_commit: svnOutput=>>\n{0}<<'.format(svnOutput), file=sys.stderr)
    if svnExit:
        print('{0}: "{1}" failed to get "{2}" (exit={3}), re: {4}\n'.format(PROGNAME, CLISVNLOOK, what, svnExit, svnErrors), file=sys.stderr)
        print('{0}: command: "{1}"'.format(PROGNAME, ' '.join(cmd)), file=sys.stderr)
        print('{0}: ABORTING - tell the subversion administrator.\n'.format(PROGNAME), file=sys.stderr)
        sys.exit(exitFatalErr)
    # svnOutput always contains a trailing newline that add an unwanted blank line via splitlines(), remove it
    svnOutput = svnOutput.rstrip()
    if CLIF_DEBUG > 6:
        print('_svn_get_commit: svnOutput=>>\n{0}<< with last newline stripped'.format(svnOutput), file=sys.stderr)
    CommitData = svnOutput.splitlines() # create a list to return
    if CLIF_DEBUG > 5:
        print('_svn_get_commit: BEFORE SORT: "{0}"'.format(CommitData), file=sys.stderr)
    CommitData = sorted(CommitData) # sorted returns a list
    if CLIF_DEBUG > 5:
        print('_svn_get_commit: AFTER  SORT: "{0}"'.format(CommitData), file=sys.stderr)
    return CommitData # _svn_get_commit - output split into an array of files/directories }

def _svn_get_list(path): # {
                         # path -> path with in the repository to list
    global CLIF_DEBUG
    global CLISVNPATH
    global CLISVNREPO
    global PROGNAME
    global exitFatalErr
    # build the full protocol / repository / path string
    full = "file://"+CLISVNREPO+path
    what = "list"
    cmd       = [ CLISVNPATH, what, full ] # command to run
    svnErrors = ''          # STDERR of command SVN - any errors
    svnList = ''            # STDOUT of command SVN - creator
    svnExit = 0             # exit value of command SVN
    child = ''              # object created by subprocess
    if CLIF_DEBUG > 5:
        print('_svn_get_list: cmd = {0}'.format(' '.join(cmd)), file=sys.stderr)
    child = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    svnList, svnErrors = child.communicate()
    svnExit = child.returncode
    if CLIF_DEBUG > 5:
        if CLIF_DEBUG > 6:
            print('_svn_get_list: svnExit=  "{0}"'.format(svnExit), file=sys.stderr)
            print('_svn_get_list: svnErrors="{0}"'.format(svnErrors), file=sys.stderr)
        print('_svn_get_list: svnList="{0}"'.format(svnList), file=sys.stderr)
    if svnExit:
        if not re.match(r'non-existent in that revision', svnErrors):
            print('{0}: "{1}" "{2}" failed to list "{3}" (exit={4}), re: {5}\n'.format(PROGNAME, CLISVNPATH, path, svnExit, svnErrors), file=sys.stderr)
            print('{0}: command: "{1}"'.format(PROGNAME, ' '.join(cmd)), file=sys.stderr)
            print('{0}: ABORTING - tell the subversion administrator.\n'.format(PROGNAME), file=sys.stderr)
            sys.exit(exitFatalErr)
    svnList = svnList.rstrip()
    svnList = svnList.splitlines() # create a list to return
    svnList = sorted(svnList) # sorted returns a list
    if CLIF_DEBUG > 5:
        print('_svn_get_list:        svn list of "{0}"'.format(full), file=sys.stderr)
        print('_svn_get_list: LEAVE: svn list is "{0}"'.format(svnList), file=sys.stderr)
    return svnList     # _svn_get_list }

def _tag_is_in_archive(aTag, arch): # {
                                    # aTag -> new artifact, tag that is being created
                                    # arch -> name of archive directory
    rvalue = False  # assume not in archive
    head = re.sub(r'/$', '', aTag)
    tail = head
    head = re.sub(r'(.*)/(.*)', '\1', head)
    tail = re.sub(r'(.*)/(.*)', '\2', head)
    path = head
    path += '/'
    path += arch
    path += '/'
    path += tail
    aList = _svn_get_list(path)
    if len(aList) > 0:
        rvalue = False
    return rvalue # _tag_is_in_archive }

def _the_add_is_allowed(author, ADDlist): # {
                                          # author  -> committer of this change
                                          # ADDlist -> array reference to the "array of stuff to add"
    global CLIF_DEBUG
    global MAKEKEY
    global NAMEKEY
    global PROGNAME
    global SUBfKEY
    global TAGpKEY
    global cfgDofD
    aDire = ""                 # archive directory name
    aMake = ""                 # users that can create new project directories
    artifact = ""              # user wants to add
    commit = True              # assume OK to commit
    pDire = ""                 # protected (parent) directory
    sDire = ""                 # subdirectory under pDire, can be BLANK
    tupKey = ""                # N-Tuple key used to find data in cfgDofD
    glob = ""                  # a "glob" pattern to check for matches
    if CLIF_DEBUG > 6:
        print('_the_add_is_allowed: ENTER: listing array of N-Tuple keys and the artifact to test with the key', file=sys.stderr)
        for i in range(0, len(ADDlist)):
            print('_the_add_is_allowed: with ADDlist[{0}]=>>{1}<<'.format(i, ADDlist[i]), file=sys.stderr);
           #for j in range(0, len(ADDlist[i])):
           #    print('_the_add_is_allowed: with ADDlist[{0}][{1}]=>>{2}<<'.format(i, j, ADDlist[i][j]), file=sys.stderr);
        print('_the_add_is_allowed: LEAVE: listing array of N-Tuple keys and the artifact to test with the key', file=sys.stderr)
    for i in range(0, len(ADDlist)): #  we know all these are protected and to be added [
        tupKey = ADDlist[i][0]
        artifact = ADDlist[i][1]
        pDire = cfgDofD[tupKey][TAGpKEY]    # protected directory
        aMake = cfgDofD[tupKey][MAKEKEY]    # authorised to make subdirectories
        aDire = cfgDofD[tupKey][NAMEKEY]    # archive directory name
        sDire = cfgDofD[tupKey][SUBfKEY]    # subdirectory name - glob is allowed here
        if CLIF_DEBUG > 6:
            print('_the_add_is_allowed: N-TupleKey:     tupKey\t= {0}'.format(tupKey), file=sys.stderr)
            print('_the_add_is_allowed: Commited:       artifact\t= {0}'.format(artifact), file=sys.stderr)
            print('_the_add_is_allowed: Parent Dir:     pDire\t\t= {0}'.format(pDire), file=sys.stderr)
            print('_the_add_is_allowed: Sub "glob" Dir: sDire\t\t= {0}'.format(sDire), file=sys.stderr)
            print('_the_add_is_allowed: Archive Dir:    aDire\t\t= {0}'.format(aDire), file=sys.stderr)
            print('_the_add_is_allowed: authorized:     aMake\t\t= {0}'.format(aMake), file=sys.stderr)
        # IN ORDER TO ENSURE CORRECTLY FIGURING OUT WHAT THE USER IS DOING TEST IN THIS ORDER:
        # 1) attempting to add to the Archive directory?
        # 2) attempting to add to a tag?
        # 3) attempting to add _the_ Archive directory itself?
        # 4) attempting to add a project directory?
        # 5) attempting to add the protected directory _itself_ ?
        # 6) attempting to add a directory? <= this should never happen, above takes care of it
        # 7) attempting to add a file that is not part of a tag?
        ###########################################################################################[
        # 1) ENTER: attempting to add to the Archive? {
        if CLIF_DEBUG > 3:
            print('_the_add_is_allowed: TESTING -> ATTEMPT TO ADD TO AN ARCHIVE DIRECTORY? artifact="{0}"'.format(artifact), file=sys.stderr)
        if   sDire == "" and aDire == "":
            glob = ""                                  # no subdirectory, no archive directory name
        elif sDire == "" and aDire != "":                    # no subdirectory, yes archive directory name
            glob = pDire + '/' + aDire + '/?*'
        elif sDire != "" and aDire == "":                     # yes subdirectory, no arhive directory name
            glob = ""
        elif sDire != "" and aDire != "":                     # yes subdirectory, yes archive directory name
            glob = sDire + '/' + aDire + '/?*'
        if glob != "":
            if CLIF_DEBUG > 6:
                print('_the_add_is_allowed: if _adding_archive_dir({0}, {1}, {2}, {3}) is the test to see if adding to an archive directory'.format(pDire, sDire, aDire, artifact), file=sys.stderr)
            if _adding_archive_dir(pDire, sDire, aDire, artifact) == True: #
                if CLIF_DEBUG > 3:
                    print('_the_add_is_allowed: artifact="{0}" IS UNDER AN ARCHIVE DIRECTORY'.format(artifact), file=sys.stderr)
                print('{0}: you can only move existing tags to an archive directory'.format(PROGNAME), file=sys.stderr)
                print('{0}: commit failed, you cannot add anything to an existing archive directory!'.format(PROGNAME), file=sys.stderr)
                print('{0}: commit failed on: {1}'.format(PROGNAME, artifact), file=sys.stderr)
                commit = False
            # otherwise contine testing
        # 1) LEAVE: attempting to add to the Archive? }
        if commit == True:
            if CLIF_DEBUG > 4:
                print('_the_add_is_allowed: KEEP TESTING -> NOT ADDING TO AN ARCHIVE DIRECTORY WITH: artifact="{0}"'.format(artifact), file=sys.stderr)
        # 2) ENTER: attempting to add to a tag?
            if CLIF_DEBUG > 3:
                print('_the_add_is_allowed: TESTING -> ATTEMPT TO ADD A TAG? artifact="{0}"'.format(artifact), file=sys.stderr)
            if sDire == "":
                glob = pDire+"/?*/"       # no subdirectory
            else:
                glob = sDire+"/?*/"
            if CLIF_DEBUG > 6:
                print('_the_add_is_allowed: if fnmatch.fnmatch({0}, {1}) == True is the test to see if adding a new tag'.format(artifact, glob), file=sys.stderr)
            if fnmatch.fnmatch(artifact, glob) == True:  # [
                if CLIF_DEBUG > 6:
                    print('_the_add_is_allowed: if _tag_is_in_archive({0}, {1}) == True is the test to see if adding to an archive directory'.format(artifact, glob), file=sys.stderr)
                if _tag_is_in_archive(artifact, aDire) == True:
                    if CLIF_DEBUG > 3:
                        print('_the_add_is_allowed: stop TESTING -> CANNOT ADD tag that already exists in the archive directory: artifact="{0}"'.format(artifact), file=sys.stderr)
                    print('{0}: you cannot add this tag because it already exists in an archive directory!'.format(PROGNAME), file=sys.stderr)
                    print('{0}: commit failed on: {1}'.format(PROGNAME, artifact), file=sys.stderr)
                    commit = False
                    break
                # no problem - we are simply adding a tag
                if CLIF_DEBUG > 3:
                    print('_the_add_is_allowed: stop TESTING -> THIS IS OK AND IS A NEW TAG artifact="{0}"'.format(artifact), file=sys.stderr)
        # 2) LEAVE: attempting to add to a tag?
            else: # if fnmatch.fnmatch(artifact, glob) == True: ][
                if CLIF_DEBUG > 4:
                    print('_the_add_is_allowed: KEEP TESTING -> THIS IS NOT A NEW TAG artifact="{0}"'.format(artifact), file=sys.stderr)
        # 3) ENTER: attempting to add the _Archive directory_ itself?
                if CLIF_DEBUG > 3:
                    print('_the_add_is_allowed: TESTING -> ATTEMPT TO ADD THE ARCHIVE DIRECTORY ITSELF? artifact="{0}"'.format(artifact), file=sys.stderr)
                if aDire != "":
                    if CLIF_DEBUG > 6:
                        print('_the_add_is_allowed: if _adding_archive_dir({0}, {1}, {2}, {3}) == True '.format(pDire, sDire, aDire, artifact), end='', file=sys.stderr)
                        print('is the test to see if adding an archive directory', file=sys.stderr)
                    if _adding_archive_dir(pDire, sDire, aDire, artifact) == True:
                        if CLIF_DEBUG > 3:
                            print('_the_add_is_allowed: stop TESTING -> artifact="{0}" IS AN ARCHIVE DIRECTORY'.format(artifact), file=sys.stderr)
                        commit = _authorized(author, aMake, artifact, 'add an archive directory')
                        if commit == True:
                            break  # no need to continue
                        continue   # no need to futher test
        # 3) LEAVE: attempting to add the _Archive directory_ itself?
                if CLIF_DEBUG > 4:
                    print('_the_add_is_allowed: KEEP TESTING -> NOT ADDING THE ARCHIVE DIRECTORY ITSELF WITH artifact="{0}"'.format(artifact), file=sys.stderr)
        # 4) ENTER: attempting to add a project directory?
                if CLIF_DEBUG > 3:
                    print('_the_add_is_allowed: TESTING -> ATTEMPT TO ADD A SUB DIRECTORY? artifact="{0}"'.format(artifact), file=sys.stderr)
                if CLIF_DEBUG > 6:
                    print('_the_add_is_allowed: if _adding_sub_dir({0}, {1}, {2}) == True '.format(pDire, sDire, artifact), end='', file=sys.stderr)
                    print('is the test to see if adding a sub directory', file=sys.stderr)
                if _adding_sub_dir(pDire, sDire, artifact) == True:
                    if CLIF_DEBUG > 3:
                        print('_the_add_is_allowed: stop TESTING -> THIS IS A NEW PROJECT SUB DIRECTORY, calling _authorized(author="{0}", {1}="{2}", artifact="{3}")'.format(author, MAKEKEY, aMake, artifact),
                              file=sys.stderr)
                    commit = _authorized(author, aMake, artifact, 'add a project (or sub) directory')
                    if commit == True:
                        break
                    continue   # no need to futher test
        # 4) LEAVE: attempting to add a project directory?
                if CLIF_DEBUG > 4:
                    print('_the_add_is_allowed: KEEP TESTING -> NOT ATTEMPT TO ADD A SUB DIRECTORY WITH artifact="{0}"'.format(artifact), file=sys.stderr)
        # 5) ENTER: attempting to add the protected directory _itself_ ?
                if CLIF_DEBUG > 3:
                    print('_the_add_is_allowed: TESTING -> ATTEMPT TO ADD THE PROTECTED DIRECTORY ITSELF? artifact="{0}"'.format(artifact), file=sys.stderr)
                if CLIF_DEBUG > 6:
                    print('_the_add_is_allowed: if {0} == {1} is the test to see if adding a sub directory'.format(pDire+"/", artifact),  file=sys.stderr)
                if pDire+"/" == artifact:     # trying to add the parent directory itself
                    if CLIF_DEBUG > 3:
                        print('_the_add_is_allowed: stop TESTING -> THIS IS A THE PROTECTED DIRECTORY, calling _authorized(author="{0}", {1}="{2}", artifact="{3}")'.format(author, MAKEKEY, aMake, artifact), file=sys.stderr)
                    commit = _authorized(author, aMake, artifact, 'create the protected directory')
                    if commit == True:
                        break
                    continue   # no need to futher test
        # 5) LEAVE: attempting to add the protected directory _itself_ ?
                if CLIF_DEBUG > 3:
                    print('_the_add_is_allowed: stop TESTING -> CANNOT ADD ARBITRARY DIRECTORY OR FILE TO A PROTECTED DIRECTORY artifact="{0}"'.format(artifact), file=sys.stderr)
                print('{0}: you can only only add new tags'.format(PROGNAME), file=sys.stderr)
                if artifact.endswith('$') == True:
        # 6) attempting to add a directory? <= this should never happen, above takes care of it
                    print('{0}: commit failed, you cannot add a directory to a protected directory!'.format(PROGNAME), file=sys.stderr)
                else:
        # 7) attempting to add a file that is not part of a tag?
                    print('{0}: commit failed, you cannot add a file to a protected directory!'.format(PROGNAME), file=sys.stderr)
                print('{0}: commit failed on: {1}'.format(PROGNAME, artifact), file=sys.stderr)
                commit = False
                break
        # if fnmatch.fnmatch(artifact, glob) == True:  # ]
        ###########################################################################################]
    # for ]
    if CLIF_DEBUG > 2:
        print('_the_add_is_allowed: return {0}'.format(commit), file=sys.stderr)
    return commit     # _the_add_is_allowed }

def _the_move_is_allowed(what, author, ADDlist, DELlist): # {
                                                          # what    -> svnlook output, what is to be committed ('A', or 'D' and the path)
                                                          # author  -> committer of this change
                                                          # ADDlist -> list of stuff to add
                                                          # DELlist -> list of stuff to delete
    global CLIF_DEBUG
    global NAMEKEY
    global cfgDofD
    addKey = ""                 # N-Tuple key from the "add" array
    artifact = ""               # path from the "add" array
    artifactNoArch = ""         # path from the "add" array with next to last directory with "Arhive name" removed
    archive = ""                # name of an archive directory for this N-Tuple
    check1st = ""               # path to check before putting a path into @justAdditions
    commit = True               # assume OK to commit
    delNdx = -1                 # found the thing in the del array this is in the add array?
    delKey = ""                 # N-Tuple key from the "del" array
    delPath = ""                # path from the "del" array
    justAdd = False             # true if the path in the add array has no matching path in the del array
    ok2add = False              # ok to put a path into @justAdditions because it is not there already
    justAdditions = []          # list of additions found that do not have matching delete/move
    ################################################################################################
    for i in range(0, len(ADDlist)): #    # walk each of the artifacts to be added [
        addKey = ADDlist[i][0]
        artifact = ADDlist[i][1]
        if CLIF_DEBUG > 6:
            print('_the_move_is_allowed: add cfgkey is: {0}, add artifact is: {1}'.format(addKey, artifact), file=sys.stderr)
        archive = cfgDofD[addKey][NAMEKEY];
        if archive == "":
            if CLIF_DEBUG > 4:
                print('_the_move_is_allowed: KEEP TESTING -> no archive directory so this must be a just add condition with artifact="{0}"'.format(artifact, file=sys.stderr))
            justAdd = True
        else:
            justAdd = False # clear (possible true from a previous loop) and assume False for this block
            regex = '^(.+)/' + archive + '/([^/]+/)'
            if CLIF_DEBUG > 6:
                print('_the_move_is_allowed: if re.match({0}, {1}) == True '.format(regex, archive), end='', file=sys.stderr)
                print('is the test to see if adding to an archive directory\n',  file=sys.stderr)
            if re.match(regex, artifact) == True:    # does path have "archive directory name" in it as next to last directory
                artifactNoArch = re.sub(regex, r'\1/\2');
                if CLIF_DEBUG > 4:
                    print('_the_move_is_allowed: KEEP TESTING -> does the archive artifact to add have a corresponding tag being deleted, ', end='', file=sys.stderr)
                    print('artifact: {0}, corresponding: {1}'.format(artifact, artifactNoArch), file=sys.stderr)
                delNdx = -1                                     # impossible value
                for j in range(0, len(DELlist)): # walk each of the artifacts to be deleted and look to see if the thing added is related to the [
                                                 # artifact being deleted by an archive directory name
                    delKey = DELlist[j][0]
                    delPath = DELlist[j][1]
                    if CLIF_DEBUG > 5:
                        print( '_the_move_is_allowed: delete cfgkey is: {0}, add artifact is: {1}'.format(delKey, delPath), file=sys.stderr)
                    if addKey == delKey and artifactNoArch == delPath:
                        delNdx = i
                        if CLIF_DEBUG > 6:
                            print('_the_move_is_allowed: DEL is moving to Arhive, that is OK', file=sys.stderr)
                            print('_the_move_is_allowed: ADD KEY  >>{0}<<\n'.format(addKey), file=sys.stderr)
                            print('_the_move_is_allowed: DEL KEY  >>{0}<<\n'.format(delKey), file=sys.stderr)
                            print('_the_move_is_allowed: ADD PATH >>{0}<<\n'.format(artifact), file=sys.stderr)
                            print('_the_move_is_allowed: DEL PATH >>{0}<<\n'.format(delPath), file=sys.stderr)
                        break
                # for ]
                if delNdx != -1:     # was the index into the del array found?
                    if CLIF_DEBUG > 4:
                        print('_the_move_is_allowed: KEEP TESTING -> ', end='', file=sys.stderr)
                        print('remove this artifact from delete array because it is moving to archive directory artifact="{0}"'.format(artifact), file=sys.stderr)
                        del DELlist[delNdx]
                else:
                    if CLIF_DEBUG > 4:
                        print('_the_move_is_allowed: KEEP TESTING -> the artifact to be added has no corresponding delete from a tag, artifact="{0}"'.format(artifact), file=sys.stderr)
            else:                                       # found a path to add but it does not have "archive directory name" as next to last directory
                if CLIF_DEBUG > 4:
                    print('_the_move_is_allowed: KEEP TESTING -> no archive directory match so this is an add condition with artifact="{0}"'.format(artifact), file=sys.stderr)
                justAdd = True
        if justAdd == True:
            if CLIF_DEBUG > 3:
                print('_the_move_is_allowed: KEEP TESTING -> ADDING TO THE ARRAY OF justAdditions, artifact="{0}"'.format(artifact), file=sys.stderr)
            ok2add = True                                # assume so
            if len(justAdditions) > 0:
                ref = justAdditions[-1]
                check1st = ref[1]
                if len(artifact) >= len(check1st):
                    if check1st.find(artifact, 0, len(artifact)) == 0:
                        ok2add = False
            if ok2add == True:
                if CLIF_DEBUG > 4:
                    print('_the_move_is_allowed: KEEP TESTING - pushing path to array for futher testing, artifact="{0}"'.format(artifact), file=sys.stderr)
                justAdditions.append([addKey, artifact])
            else:
                if CLIF_DEBUG > 4:
                    print('_the_move_is_allowed: duplicate pathing, not pushing path to array for futher testing, artifact: {0}'.format(artifact), file=sys.stderr)
    # for ]
    if CLIF_DEBUG > 5:
        print('_the_move_is_allowed: LOOP IS DONE', file=sys.stderr)
        print('_the_move_is_allowed: left over delete count is:  {0}  (0 or more means there are some deletes not part of moves)'.format(len(DELlist)), file=sys.stderr)
        print('_the_move_is_allowed: count of just additions is: {0}'.format(len(justAdditions)), file=sys.stderr)
    if len(DELlist) > 0:       # if there is something left over to be deleted then it is not a 'move'
        for j in range(0, len(DELlist)):
            #delKey = DELlist[j][0]
            delPath = 'D   '+DELlist[j][1]  # Prepend the path to be delete with 'D   ' (3 spaces) to emulate what svnlook does
            commit = _say_no_delete(delPath);  # always returns False
            break                           # just do one
    elif len(justAdditions) > 0:                     # there is something left over to be added and must check that on its own
        if CLIF_DEBUG > 3:
            print('_the_move_is_allowed: KEEP TESTING - call _the_add_is_allowed({0}, {1}) to test addtions not matched with deletions'.format(author, justAdditions), file=sys.stderr)
        commit = _the_add_is_allowed(author, justAdditions)
    if CLIF_DEBUG > 1:
        print('_the_move_is_allowed: return {0}'.format(commit), file=sys.stderr)
    return commit                    # _the_move_is_allowed }

# A TAG DIRECTORY TO PROTECT CAN ONLY BE GIVEN ONCE.
# IF THE (now parsed into a dictionary of dictionary) CONFIGURATION FILE HAS THE _IDENTICAL_
# TAG DIRECTORY TO PROTECT REPEATED (i.e. given more that once) ERROR OUT AND EXIT.
def _validate_cfg_or_die(): # {
    global CLICONFIGF
    global LINEKEY
    global PROGNAME
    global TAGpKEY
    global Tuple_CNT
    global Tuple_STR
    global cfgDofD
    global exitFatalErr
    return
    count_1 = 0             # index for outer count
    count_2 = 0             # index for inner count
    key_1 = ""              # to loop through keys
    key_2 = ""              # to loop through keys
    protected_1 = ""        # 1st protected directory to compare with
    protected_2 = ""        # 2nd protected directory to compare with
    error = False           # error count
    while count_1 < Tuple_CNT: # [
        key_1       = _gen_tuple_key(Tuple_STR, count_1)
        protected_1 = cfgDofD[key_1][TAGpKEY]           # data to compare
        count_2     = count_1 + 1
        while count_2 < Tuple_CNT: # [
            key_2 = _gen_tuple_key(Tuple_STR, count_2)
            protected_2 = cfgDofD[key_2][TAGpKEY]      # data to compare
            if protected_2 == protected_1:
                if error == False:
                    print('{0}: error with configuration file: "{1}"'.format(PROGNAME, CLICONFIGF), file=sys.stderr)
                else:
                    print('\n', file=sys.stderr)
                print('{0}: the protected path "{1}" is duplicated'.format(PROGNAME, protected_1), file=sys.stderr)
                print('{0}: lines with duplications are:'.format(PROGNAME), file=sys.stderr)
                print(' {0}'.format(cfgDofD[key_1][LINEKEY]), end='', file=sys.stderr)
                print(' and', end='', file=sys.stderr)
                print(' {0}'.format(cfgDofD[key_2][LINEKEY]), file=sys.stderr)
                error = True
            count_2 += 1
        # while count_2 < Tuple_CNT: # ]
        count_1 += 1
    # while count_1 < Tuple_CNT: ]
    if error == True:     # exit if errors
        print('{0}: ABORTING - tell the subversion administrator.'.format(PROGNMAE), file=sys.stderr)
        sys.exit(exitFatalErr)
    return  # _validate_cfg_or_die }

# LET THE CONFIG FILE USE N, yes, off, ETC. FOR DEBUG VALUE
def _zero_one_or_n(invalue): # {
                             # invalue -> string parsed from config file
    rvalue = 0
    if re.match(r'^[0-9]+$', invalue):
        invalue = re.sub(r'^0*', '', invalue)
        if len(invalue) == 0:
            rvalue = 0
        else:
            rvalue = int(invalue)
    elif re.match(r'^on$', invalue, re.IGNORECASE):
        rvalue = 1
    elif re.match(r'^yes$', invalue, re.IGNORECASE):
        rvalue = 1
    elif re.match(r'^true$', invalue, re.IGNORECASE):
        rvalue = 1
    elif re.match(r'^enabled$', invalue, re.IGNORECASE):
        rvalue = 1
    else:            # default to zero
        rvalue = 0
    return rvalue            # }

# IN PRODUCTION PARSING THE COMMAND LINE IS EXTREMELY TRIVIAL
#     you get 2 command line options:
#        1 - path to svn repository on disk
#        2 - svn transaction id to use with svnlook
# IN COMMAND LINE MODE (for debugging or testing, help, etc.) DEBUGGING SHOULD
# NOT BE NEEDED BY THE SUBVERION ADMINISTRATOR.
# Even so, this function can be debugged by the calling program by passing in
# a debug value.
def _parse_cli(debugCLIParse, argv = []): # {
                                          # debugCLIParse -> debug value for this function
                                          # argv          -> command line arguments
    global CLIBLDPREC
    global CLIBLD_DEF
    global CLICONFIGF
    global CLIF_DEBUG
    global CLIDUMP_PL
    global CLIJUSTCFG
    global CLIOUTFILE
    global CLIPRECONF
    global CLIRUNNING
    global CLISVNREPO
    global CLISVN_TID
    global CLI_INFILE
    global PROGDIRE
    global PROGNAME
    global exitFatalErr
    ######################################
    # in production the PROGDIR directory is "</svndir>/hooks",
    # where /svndir is the absolute path to a subversion repository.
    CLICONFIGF = '{0}/{1}.conf'.format(PROGDIRE, PROGNAME)    # "PROGDIRE/PROGNAME.conf";       # the name of the config file itself
    CLIPRECONF = '{0}/{1}.conf.py'.format(PROGDIRE, PROGNAME) # "PROGDIRE/PROGNAME.conf.py";    # the name of the "pre-compiled" file
    ######################################
    total = 0                      # count number of requested actions
    ######################################
    cnt = len(argv)
    ndx = 1 # start from 1, skipping argv[0] which is the program name
    ######################################
    while ndx < cnt:
        if debugCLIParse > 3:
            print('_parse_cli: argc={0}  argv[{1}] => "{2}"'.format(cnt, ndx, argv[ndx]), file=sys.stderr)
        ######################################
        ######################################
        ## ENTER: options that cause an immediate exit after doing their job
        if argv[ndx] in ['--help', '-h']:
            _print_usage_and_exit()
        elif argv[ndx] in ['--version', '-v']:
            _print_version_and_exit()
        ## LEAVE: options that cause an immediate exit after doing their job
        ##
        ##
        ## ENTER: options that mean we are not running under subversion
        elif argv[ndx] in ['--generate', '-g']:
            CLIBLD_DEF = 1
            CLIRUNNING = 1    # running on command line
        elif argv[ndx] in ['--parse', '-p']:
            CLIJUSTCFG = 1
            CLIRUNNING = 1    # running on command line
        elif argv[ndx] in ['--build', '-b']:
            CLIBLDPREC = 1
            CLIRUNNING = 1    # running on command line
        elif argv[ndx] in ['--revert', '-r']:
            CLIDUMP_PL = 1
            CLIRUNNING = 1    # running on command line
        elif re.match(r'--input=.+', argv[ndx]) is not None:
            CLI_INFILE = re.sub(r'--input=', '', argv[ndx])
            CLIRUNNING = 1     # running on command line
        elif re.match(r'-i.+', argv[ndx]) is not None:
            CLI_INFILE = re.sub(r'-i', '', argv[ndx])
            CLIRUNNING = 1     # running on command line
        elif re.match(r'--output=.+', argv[ndx]) is not None:
            CLIOUTFILE = re.sub(r'--output=', '', argv[ndx])
            CLIRUNNING = 1     # running on command line
        elif re.match(r'-o.+', argv[ndx]) is not None:
            CLIOUTFILE = re.sub(r'-o', '', argv[ndx])
            CLIRUNNING = 1     # running on command line
        elif argv[ndx] in ['--nodebug', '-D']:
            CLIF_DEBUG = int(0)
            CLIRUNNING = 1             # running on command line
        elif argv[ndx] in ['--debug', '-d']:
            if CLIF_DEBUG <= 0:
                CLIF_DEBUG = int(1)
            else:
                CLIF_DEBUG += 1
            CLIRUNNING = 1             # running on command line
        elif re.match(r'--debug=[0-9]+', argv[ndx]) is not None:
            CLIF_DEBUG = int(re.sub(r'--debug=', '', argv[ndx]))
            CLIRUNNING = 1             # running on command line
        elif re.match(r'-d[0-9]+', argv[ndx]) is not None:
            CLIF_DEBUG = int(re.sub(r'-d', '', argv[ndx]))
            CLIRUNNING = 1             # running on command line
        elif re.match(r'-d=[0-9]+', argv[ndx]) is not None:
            CLIF_DEBUG = int(re.sub(r'-d=', '', argv[ndx]))
            CLIRUNNING = 1             # running on command line
        ## LEAVE: options that mean we are not running under subversion
        ##
        ##
        ## ENTER: fatal errors
        elif re.match(r'-.*', argv[ndx]) is not None:
            print('{0}: unrecognized command line option: "{1}"'.format(PROGNAME, argv[ndx]))
            print("{0}: ABORTING!".format(PROGNAME))
            sys.exit(exitFatalErr)
        elif ((cnt-ndx) != 2):
            print("{0}: incorrect command line argument count is: {1} (it should be {2}).".format(PROGNAME, (cnt-ndx), 2), file=sys.stderr)
            print("{0}: perhaps you are not running under subversion?  if so give {1} dummy command line options.".format(PROGNAME, 2))
            print("{0}: ABORTING!".format(PROGNAME))
            sys.exit(exitFatalErr)
        ## LEAVE: fatal errors
        ##
        ##
        ## ENTER: in PRODUCTION, under Subversion, only this block is ever invoked
        else:    # there are now 2 command line arguments left - see the test above
            if debugCLIParse > 2:
                print('_parse_cli: PRODUCTION MODE consume two args:  argc={0}  repo == argv[{1}] == "{2}" and transaction id == argv[{3}] == "{4}"'.format(cnt, ndx, argv[ndx], ndx+1, argv[ndx+1]), file=sys.stderr)
            CLISVNREPO = argv[ndx]
            if debugCLIParse > 1:
                print('_parse_cli: CLISVNREPO="{0}"'.format(CLISVNREPO), file=sys.stderr)
            ndx += 1
            CLISVN_TID = argv[ndx]
            if debugCLIParse > 1:
                print('_parse_cli: CLISVN_TID="{0}"'.format(CLISVN_TID), file=sys.stderr)
        ## LEAVE: in PRODUCTION, under Subversion, only this block is ever invoked
        ##
        ##
        ndx += 1 # # END: while ( ndx < cnt ):
    # if debugging from the command line (because that is the only way
    # this could happen) and the command line did not give the expected
    # subversion command line arguments then give them here so the
    # program can continue, usually just to parse the config file.
    if CLISVNREPO == "" or CLISVN_TID == "":
        CLISVNREPO = re.sub(r'/hooks$', '', PROGDIRE)
        if CLISVNREPO == '':
            CLISVNREPO = PROGDIRE    # this should now be the path to the repo, unless in development
        CLISVN_TID = "HEAD"       # this will be useless talking to subversion with svnlook
    ##
    ##
    # svnRepo path must end with slash
    if re.match(r'/$', CLISVNREPO) is None:
        CLISVNREPO += "/"
    ##
    ##
    total = CLIBLD_DEF + CLIJUSTCFG + CLIBLDPREC + CLIDUMP_PL
    if total > 1:
        print("{0}: too many actions requested!".format(PROGNAME), file=sys.stderr)
        print("{0}: only one of --generate/--parse/--build/--revert can be given.".format(PROGNAME), file=sys.stderr)
        print("{0}: ABORTING".format(PROGNAME), file=sys.stderr)
        sys.exit(exitFatalErr)
    ##
    ##
    # produce a default file and exit, if command line requested
    if CLIBLD_DEF > 0:
        _print_default_config_optionally_exit(True, CLIOUTFILE, sys.stdout)
    ##
    ##
    if debugCLIParse > 0:
        print('_parse_cli: returning successful (with no value) after command line parse', file=sys.stderr)
    return # nothing useful can be returned }

# IN PRODUCTION PARSING THE CONFIG FILE IS CRITICAL
# without a proper config file there is no way to know
# what to protect from changes.
#
# SUBVERSION ADMINSTRATORS can send in a debug value
#
def _parse_cfg(debugCFGParse): # {
                               # debugCFGParse -> debug value for this function
    global CLIBLDPREC
    global CLICONFIGF
    global CLIC_DEBUG
    global CLIDUMP_PL
    global CLIF_DEBUG
    global CLIJUSTCFG
    global CLIOUTFILE
    global CLIPRECONF
    global CLIRUNNING
    global CLISVNLOOK
    global CLISVNPATH
    global CLI_INFILE
    global CLI_INFILE
    global DEF_NAME_AF
    global LINEKEY
    global MAKEKEY
    global NAMEKEY
    global PROGNAME
    global SUBfKEY
    global TAGpKEY
    global Tuple_STR
    global VAR_H_DEBUG
    global VAR_MAKESUB
    global VAR_NAME_AF
    global VAR_SUBDIRE
    global VAR_SVNLOOK
    global VAR_SVNPATH
    global VAR_TAGDIRE
    global cfgDofD
    global exitFatalErr
    global exitSuccess
    global regvar_H_DEBUG
    global regvar_MAKESUB
    global regvar_NAME_AF
    global regvar_SUBDIRE
    global regvar_SVNLOOK
    global regvar_SVNPATH
    global regvar_TAGDIRE
    global reg_1ST_N_LAST
    global reg_EQUAL_SIGN
#
    var     = ""
    val     = ""
    ch_1st  = ""
    chLast  = ""
    errors  = 0
    unknown = 0
    itmp    = 0
    cfg     = dict()  # "one config" for a protected directory
    tKey    = ''      # N-Tuple key
    cKey    = ''      # configuration key
    spch    = ''      # string of space characters
    readPreComp = False # read the precompiled config file
    ohandle = sys.stdout
    tstr    = ''
    # do not read the pre-compiled file if we have to build it
    # and do not read the pre-compiled file it we have been asked to parse
    # the configuration file
    if CLIBLDPREC == 0 and CLIJUSTCFG == 0:
        if CLI_INFILE != "":
            CLIPRECONF = CLI_INFILE
        if os.path.isfile(CLIPRECONF):    # if the precompiled file exists it will be read in
            readPreComp = True
    if readPreComp:    # if precompiled file, and no command line options to the contrary, just "source" it and done!
        if debugCFGParse > 1:
            print('_parse_cfg: execfile(configfile, globals()) with precompiled configuration file "{0}"'.format(CLIPRECONF), file=sys.stderr)
        execfile(CLIPRECONF, globals()) # this will instantiate CLIF_DEBUG as
        # if the command line has set the debug higher than what it now is then it set back to the command line value
        CLIF_DEBUG = max(CLIF_DEBUG, CLIC_DEBUG)            # allow command line to override precompiled config file value
    else:   # read the regular config file
        if CLI_INFILE != "":
            CLIPRECONF = CLI_INFILE               # command line parse overrides default
        if os.path.exists(CLICONFIGF) == False:    # if the precompiled file exists it will be read in
            print('{0}: configuration file "{1}" does not exist, aborting.'.format(PROGNAME, CLICONFIGF), file=sys.stderr)
            print('{0}: tell the subversion administrator.'.format(PROGNAME), file=sys.stderr)
            sys.exit(exitFatalErr)
        else: # read the regular config file ENTER
            if debugCFGParse > 2:
                print('_parse_cfg: open for read "{0}"'.format(CLICONFIGF), file=sys.stderr)
            cfgh = open(CLICONFIGF, 'rb')
            if debugCFGParse > 1:
                print('_parse_cfg: read configuration file "{0}"'.format(CLICONFIGF), file=sys.stderr)
            cnt = 0
            for line in cfgh:
                ###############################################
                # ENTER: fix and split up the line just read in
                cnt += 1
                line = line.strip()             # strip initial and trailing whitespace
                line = re.sub(r'#.*', '', line) # remove comments, leaving, optionally, initial whitespace
                line = line.rstrip()            # remove trailing whitespace in case of comment on after assignment
                if len(line) == 0:
                    continue
                if debugCFGParse > 4:
                    print("_parse_cfg: RAW: {0}".format(line), file=sys.stderr)
                if reg_EQUAL_SIGN.match(line) is None:
                    if errors == 0:
                        print('{0}: configuration file "{1}" is misconfigured.'.format(PROGNAME, CLICONFIGF), file=sys.stderr)
                    print("{0}: line {1} >>{2}<< is not a comment and does not contain an equal sign(=) character!".format(PROGNAME, cnt, line), file=sys.stderr)
                    errors += 1
                    continue
                var = reg_EQUAL_SIGN.sub(r'\2', line)
                val = reg_EQUAL_SIGN.sub(r'\5', line)
                ch_1st = reg_1ST_N_LAST.sub(r'\1', val) # first char
                chLast = reg_1ST_N_LAST.sub(r'\3', val) # last char
                if debugCFGParse > 5:
                    print('_parse_cfg: var="{0}"'.format(var), file=sys.stderr)
                    print('_parse_cfg: val="{0}"'.format(val), file=sys.stderr)
                    print('_parse_cfg: ch_1st="{0}"'.format(ch_1st), file=sys.stderr)
                    print('_parse_cfg: chLast="{0}"'.format(chLast), file=sys.stderr)
                if ch_1st == chLast and ch_1st == '"':
                    if debugCFGParse > 5:
                        print('_parse_cfg: val=>>{0}<<  stripping first and last double quotes (")'.format(val), file=sys.stderr)
                    val = reg_1ST_N_LAST.sub(r'\2', val)
                elif ch_1st == chLast and ch_1st == "'":
                    if debugCFGParse > 5:
                        print("_parse_cfg: val=>>{0}<<  stripping first and last single quotes (')".format(val), file=sys.stderr)
                    val = reg_1ST_N_LAST.sub(r'\2', val)
                elif ch_1st == '"' or ch_1st == "'":
                    if errors == 0:
                        print('{0}: configuration file "{1}" is misconfigured.'.format(PROGNAME, CLICONFIGF), file=sys.stderr)
                    print("{0}: line {1} >>{2}<< is badly quoted!".format(PROGNAME, cnt, line), file=sys.stderr)
                    errors += 1
                    continue
                else:
                    if debugCFGParse > 5:
                        print('_parse_cfg: val=>>{0}<< is good as it is, no quote stripping needed'.format(val), file=sys.stderr)
                if debugCFGParse > 5:
                    print('_parse_cfg: var="{0}"'.format(var), file=sys.stderr)
                    print('_parse_cfg: val="{0}"'.format(val), file=sys.stderr)
                # LEAVE: fix and split up the line just read in
                ###############################################
#
                ############################################################
                # ENTER: find the variable and store the value for "GLOBALS"
                if regvar_H_DEBUG.match(var) is not None:
                    CLIF_DEBUG = _zero_one_or_n(val)
                    CLIF_DEBUG = max(CLIC_DEBUG, CLIF_DEBUG)     # use the max value to work with, usually c_debug
                    if debugCFGParse > 3:
                       print('_parse_cfg: CLIF_DEBUG={0}'.format(CLIF_DEBUG), file=sys.stderr)
                elif regvar_SVNPATH.match(var) is not None:
                    ch_1st = reg_1ST_N_LAST.sub(r'\1', val) # first char
                    if ch_1st != "/":
                        if errors == 0:
                            print('{0}: configuration file "{1}" is misconfigured.'.format(PROGNAME, CLICONFIGF), file=sys.stderr)
                        print("{0}: line {1} >>{2}<< svn path does not start with slash(/)!".format(PROGNAME, cnt, line), file=sys.stderr)
                        errors += 1
                        continue
                    CLISVNPATH = val
                    if debugCFGParse > 3:
                       print('_parse_cfg: CLISVNPATH="{0}"'.format(CLISVNPATH), file=sys.stderr)
                elif regvar_SVNLOOK.match(var) is not None:
                    ch_1st = reg_1ST_N_LAST.sub(r'\1', val) # first char
                    if ch_1st != "/":
                        if errors == 0:
                            print('{0}: configuration file "{1}" is misconfigured.'.format(PROGNAME, CLICONFIGF), file=sys.stderr)
                        print("{0}: line {1} >>{2}<< svnlook does not start with slash(/)!".format(PROGNAME, cnt, line), file=sys.stderr)
                        errors += 1
                        continue
                    CLISVNLOOK = val
                    if debugCFGParse > 3:
                        print('_parse_cfg: CLISVNLOOK="{0}"'.format(CLISVNLOOK), file=sys.stderr)
                # LEAVE: find the variable and store the value for "GLOBALS"
                ############################################################
#
                ###########################################################
                # ENTER: find the variable and store the value for "N-Tuple"
                # can be given in _any_ order
                # 1) tag directory - cannot be BLANK
                # 2) subdirectories - can be BLANK means NOT ALLOWED
                # 3) subdirectory creators - can be BLANK means NO ONE -- they have made'm all and no more are allowed
                # 4) archive name - can be BLANK means NOT ALLOWED
                # 1) tag directory -- the parent
                elif regvar_TAGDIRE.match(var) is not None:
                    # before processing this "var" (a "protected tag directory" from the config file)
                    # if there is a "protected tag directory" outstanding, load it and its corresponding
                    # configuration values
                    if len(cfg) > 0:
                        if not LINEKEY in cfg:
                            cfg[LINEKEY] = cnt
                        # we need to load this protected directory and all the
                        # members of the "tuple" into the configuration dictionary
                        if debugCFGParse > 3:
                            print('_parse_cfg: {0} = "{1}" in loop read   LOAD'.format(TAGpKEY, cfg[TAGpKEY]), file=sys.stderr)
                        _load_cfg_tuple(cfg)
                        cfg = dict()    # clear it to hold next parse
                    # now process the just read in "protected tag directory"
                    ch_1st = reg_1ST_N_LAST.sub(r'\1', val) # first char
                    if ch_1st != "/":
                        if errors == 0:
                            print('{0}: configuration file "{1}" is misconfigured.'.format(PROGNAME, CLICONFIGF), file=sys.stderr)
                        print("{0}: line {1} >>{2}<< tag directory to protect does not start with slash(/)!".format(PROGNAME, cnt, line), file=sys.stderr)
                        errors += 1
                        continue
                    cfg[TAGpKEY] = _fix_path( val, 1, 1 )     # strip first slash, add last slash
                    cfg[LINEKEY] = cnt                      # keep the line this was read in on
                                                            # safety/security check
                    if cfg[TAGpKEY] == "":
                        if errors == 0:
                            print('{0}: configuration file "{1}" is misconfigured.'.format(PROGNAME, CLICONFIGF), file=sys.stderr)
                        print("{0}: line {1} >>{2}<<".format(PROGNAME, cnt, line), file=sys.stderr)
                        if line != cfg[TAGpKEY]:
                            print(' (which becomes "{0}")'.format('cfg[TAGpKEY]'), file=sys.stderr)
                        print(" cannot be blank!", file=sys.stderr)
                        errors += 1
                        continue
                    if debugCFGParse > 3:
                        print('_parse_cfg: {0} = "{1}"'.format(TAGpKEY, cfg[TAGpKEY]), file=sys.stderr)
                # 2) subdirectories
                elif regvar_SUBDIRE.match(var) is not None:
                    val = _fix_path(val, 1, 0)    # strip 1st slash, can end up being BLANK, that's ok, add last slash
                                                # if val is BLANK it means the next tags directory to be protected
                                                # will have NO subdirectories
                    cfg[SUBfKEY] = val
                    if debugCFGParse > 3:
                        print('_parse_cfg: {0} = "{1}"'.format(SUBfKEY, cfg[SUBfKEY]), file=sys.stderr)
                        if cfg[SUBfKEY] == "" and debugCFGParse > 3:
                            print("_parse_cfg: {0} = has been cleared, protected parent will have no subdirectories.".format(SUBfKEY), file=sys.stderr)
                    if not LINEKEY in cfg:
                       cfg[LINEKEY] = cnt
                # 3) creators
                elif regvar_MAKESUB.match(var) is not None:
                    cfg[MAKEKEY] = val      # can be BLANK
                    if debugCFGParse > 3:
                        print('_parse_cfg: {0} = "{1}"'.format(MAKEKEY, cfg[MAKEKEY]), file=sys.stderr)
                    if not LINEKEY in cfg:
                       cfg[LINEKEY] = cnt
                # 4) archive name
                elif regvar_NAME_AF.match(var) is not None:
                    val = _fix_path(val, 0, 0)                    # do not strip 1st slash, can end up being BLANK, that's ok, no last slash
                    if val == "":                               # asked for a reset
                        val = DEF_NAME_AF
                    val = _fix_path(val, 0, 0)                     # won't be BLANK any longer, no last slash
                    if re.match(r'.*/.*', val):
                        if errors == 0:
                            print('{0}: configuration file "{1}" is misconfigured.'.format(PROGNAME, CLICONFIGF), file=sys.stderr)
                        print("{0}: line {1} >>{2}<< archive directory name contains a slash(/) character, this is not allowed!".format(PROGNAME, cnt, line), file=sys.stderr)
                        errors += 1
                        continue
                    cfg[NAMEKEY] = val
                    if debugCFGParse > 3:
                        print('_parse_cfg: {0} = "{1}"'.format(NAMEKEY, cfg[NAMEKEY]), file=sys.stderr)
                    if not LINEKEY in cfg:
                       cfg[LINEKEY] = cnt
                # the "variable = value" pair is unrecognized
                else:
                    # useless to output error message unless debug is enabled, or
                    # we are running from the command line, because otherwise
                    # subversion will just throw them away!
                    if debugCFGParse > 0 or CLIRUNNING > 0:    # insure STDERR is not useless
                       if unknown == 0:
                           print('{0}: useless configuration variables found while parsing'.format(PROGNAME), file=sys.stderr)
                           print('{0}: configuration file: "{1}"'.format(PROGNAME, CLICONFIGF), file=sys.stderr)
                           print('{0}: tell the subversion administrator.'.format(PROGNAME), file=sys.stderr)
                    print('{0}: unrecognized "variable = value" on line {1}'.format(PROGNAME, cnt), file=sys.stderr)
                    print('{0}: variable: "{1}"'.format(PROGNAME, var), file=sys.stderr)
                    print('{0}: value:    "{1}"'.format(PROGNAME, var), file=sys.stderr)
                    print('{0}: line:      {1}'.format(PROGNAME, cnt), file=sys.stderr)
                    unknown += 1
               # LEAVE: find the variable and store the value for "N-Tuple"
               # can be given in _any_ order
               # 1) tag directory - cannot be BLANK
               # 2) subdirectory - can be BLANK means NOT ALLOWED
               # 3) subdirectory creators - can be BLANK means NO ONE
               # 4) archive name - can be BLANK means NOT ALLOWED
               ############################################################
            # END: for line in cfgh:
            cfgh.close()
            if errors > 0:
                sys.exit(exitFatalErr)
            # there can be one left in the "cache"
            if len(cfg):
                if debugCFGParse > 3:
                    print('_parse_cfg: {0} = "{1}" LAST (OR ONLY) LOAD'.format(TAGpKEY, cfg[TAGpKEY]), file=sys.stderr)
                _load_cfg_tuple(cfg)
            _validate_cfg_or_die()
        ####### read the regular config file LEAVE
    # DUMP (revert) THE PRECOMPILED FILE BACK TO A REGULAR CONFIGURATION FILE
    if CLIDUMP_PL > 0:
        if CLIOUTFILE != "":
           CLIPRECONF = CLIOUTFILE
        if readPreComp == False:
            print("{0}: precompiled configuration file is:".format(PROGNAME), file=sys.stderr)
            print('{0}:     "{1}"'.format(PROGNAME, CLIPRECONF), file=sys.stderr)
            print("{0}: precompiled configuration file was not read in.  Unable to".format(PROGNAME), file=sys.stderr)
            print("{0}: revert the precompiled configuration file to a (regular) configuration file".format(PROGNAME), file=sys.stderr)
            if not os.path.exists(CLIPRECONF):
                print("{0}: it does not exist".format(PROGNAME), file=sys.stderr)
            print("{0}: ABORTING".format(PROGNAME), file=sys.stderr)
            sys.exit(exitFatalErr)
        if CLIOUTFILE != "":
            if debugCFGParse > 1:
                print('_parse_cfg: open for write "{0}"'.format(CLIOUTFILE), file=sys.stderr)
            ohandle = open(CLIOUTFILE, 'wb')
        if debugCFGParse > 1:
            where = "STDOUT"
            if CLIOUTFILE != "":
                where = CLIOUTFILE
            print('_parse_cfg: output default pre-compiled configuration file to: "{0}"'.format(where))
        # OUTPUT THE HEADER PART, next function will not exit
        _print_default_config_optionally_exit(False, "CLIOUTFILE", ohandle );
        addBlank = False
        for okey, oval in sorted(cfgDofD.iteritems()):
            if addBlank == True:
                print('', file=ohandle)
                print('', file=ohandle)
            var = VAR_TAGDIRE
            val = cfgDofD[okey][var]
            fmt = _get_fmt_str(var)
            print("{0} = '{1}'".format(fmt, val), file=ohandle)
            var = VAR_SUBDIRE
            val = cfgDofD[okey][var]
            fmt = _get_fmt_str(var)
            print("{0} = '{1}'".format(fmt, val), file=ohandle)
            var = VAR_MAKESUB
            val = cfgDofD[okey][var]
            fmt = _get_fmt_str(var)
            print("{0} = '{1}'".format(fmt, val), file=ohandle)
            var = VAR_NAME_AF
            val = cfgDofD[okey][var]
            fmt = _get_fmt_str(var)
            print("{0} = '{1}'".format(fmt, val), file=ohandle)
            addBlank = True
        sys.exit(exitSuccess) # output of "reverted" precompiled file is done
    # OUTPUT (build) THE PRECOMPILED CONFIGURATION FILE FROM THE CONFIGURATION FILE JUST READ IN
    elif CLIBLDPREC > 0:
        if CLIOUTFILE == "":
            if debugCFGParse > 0:
                print('_parse_cfg: write precompile configuration to standard output', file=sys.stderr)
            cfgh = sys.stdout
        else:
            if debugCFGParse > 0:
                print('_parse_cfg: open for write {0}, for precompile configuration output'.format(CLIOUTFILE), file=sys.stderr)
            cfgh = open(CLIOUTFILE, 'wb')
        tStamp = time.strftime('%d %B %Y %T', time.localtime())
        user   = os.environ['USER']
        if user == "":
            user   = 'UNKNOWN'
        # create string of spaces
        spch = ""
        for i in range(0, len(_gen_tuple_key(Tuple_STR, 0))):
            spch += " "
        # output the header
        print('#', file=cfgh)
        print('# Pre-compiled configuration file created:', file=cfgh)
        print('#   Date: {0}'.format(tStamp), file=cfgh)
        print('#   From: {0}'.format(CLICONFIGF), file=cfgh)
        print('#   User: {0}'.format(user), file=cfgh)
        print('#', file=cfgh)
        # output configuration for the 3
        # use "c_debug" here, not "f_debug"
        print('CLIF_DEBUG = 0 # always set to zero by default', file=cfgh)
        print('CLISVNLOOK = "{0}"'.format(CLISVNLOOK), file=cfgh)
        print('CLISVNPATH = "{0}"'.format(CLISVNPATH), file=cfgh)
        print('', file=cfgh)
        print('cfgDofD = {  # instantiate dictionary of dictionaries', file=cfgh)
        # output all the N-Tuples
        for okey, oval in sorted(cfgDofD.iteritems()):
            print("              '{0}':{{ # instantiate inner dictionary".format(okey), file=cfgh)
            for ikey, ival in sorted(oval.iteritems()):
                print("                   {0}'{1}':".format(spch, ikey), end="", file=cfgh)
                print('"{0}",'.format(ival), file=cfgh)
            print("               {0}  }}, # close inner dictionary".format(spch), file=cfgh)
        print('          } # close dictionary of dictionaries', file=cfgh)
        sys.exit(exitSuccess)  # yes, this exits right here, we are done with building the precompiled configuration file
    # OUTPUT THE INTERNAL DICTIONARY OF DICTIONARIES if debug is high enough
    if debugCFGParse > 2:
        print('{0}={1}'.format(VAR_H_DEBUG, CLIF_DEBUG), file=sys.stderr)
        print('{0}="{1}"'.format(VAR_SVNLOOK, CLISVNLOOK), file=sys.stderr)
        print('{0}="{1}"'.format(VAR_SVNPATH, CLISVNPATH), file=sys.stderr)
        for dKey, subdict in sorted(cfgDofD.iteritems()):
            spch = dKey
            spch = re.sub(r'.', r' ', spch)
            print('{0}:{{'.format(dKey), end='', file=sys.stderr)
            if LINEKEY in subdict:
                print("   # started on line {0} INITIAL SLASHES REMOVED".format(subdict[LINEKEY]), end='', file=sys.stderr)
            print('', file=sys.stderr)
            print("{0}    '{1}:'{2}' # literal only".format(spch, VAR_TAGDIRE, cfgDofD[dKey][TAGpKEY]), file=sys.stderr)
            print("{0}    '{1}:'{2}' # literal, a glob, or blank".format(spch, VAR_SUBDIRE, cfgDofD[dKey][SUBfKEY]), file=sys.stderr)
            print("{0}    '{1}:'{2}' # authorized committers - they can create subdirectories/subprojects".format(spch, VAR_MAKESUB, cfgDofD[dKey][MAKEKEY]), file=sys.stderr)
            print("{0}    '{1}:'{2}' # literal only - name of directory for archiving".format(spch, VAR_NAME_AF, cfgDofD[dKey][NAMEKEY]), file=sys.stderr)
            print('{0} }}'.format(spch), file=sys.stderr)
    if CLIJUSTCFG:
        if debugCFGParse > 0:
            print("_parse_cfg: exit {0} because just parse configuration file is in effect".format(exitSuccess), file=sys.stderr)
        sys.exit(exitSuccess)
    if debugCFGParse > 0:
        print("_parse_cfg: return successful (with no value) after configuration file parse", file=sys.stderr)
    return # nothing useful can be returned }

#################################################################################
########################### PROTECTED/PRIVATE METHODS ###########################
## LEAVE: ######################################################################]

## ENTER: ######################################################################[
################################# PUBLIC METHODS ################################
#################################################################################
# THIS IS THE tag protect CONSTRUCTOR
# o) it instantiates some runtime globals
# o) calls the command line parser, which in PRODUCTION is extreamly fast, no worries
# o) calls the configuration file parser - this can be slow for a very large configuation
#                                          so you can pre-compile the configuration file
#                                          see documentation and/or command line help
# o) returns the greatest debug value it knows about:
#    i.e: largest of:
#                     - two passed in
#                     - config file value
#                     - command line value (if not in PRODUCTION mode)
def tag_protect(debugCLIParse, debugCFGParse, argv = []): # {
    global CLIF_DEBUG
    global PROGDIRE
    global PROGNAME
    #########################################################
    PROGNAME = os.path.abspath(argv[0])
    PROGDIRE = os.path.dirname(PROGNAME)
    PROGNAME = os.path.basename(PROGNAME)
    #########################################################
    if (len(argv) == 1):
        argv.append("--help")
    _parse_cli(debugCLIParse, argv) # exits on failure - errors to stderr
    _parse_cfg(debugCFGParse)       # exits on failure - errors to stderr
    return max(debugCLIParse, debugCFGParse, CLIF_DEBUG) # }

# Determine if we can simply allow this commit or if a protected directory is part of the commit
def simply_allow(): # {
    global CLIF_DEBUG
    global CommitData
    global TAGpKEY
    global cfgDofD
    justAllow = True                     # assume most commits are not tags
    pDir = ""                            # protected directory
    tupleKey = ""                        # N-Tuple keys found in the configuration ref
    arti_Key = ""                        # N-Tuple keys found in the configuration ref
    isProtected = False                  # returned by _is_under_protection
    artifact = ""                        # artifact to be committed, changed or whatever
    _svn_get_commit() # in PRODUCTION, uses previously parsed command line options
    for artifact in CommitData:
        if CLIF_DEBUG > 8:
            print('simply_allow: >>{0}<<'.format(artifact), file=sys.stderr)
        artifact = re.sub(r'^[A-Z_]+\s+', r'', artifact)    # trim first two char(s) and two spaces
        if CLIF_DEBUG > 7:
            print('simply_allow: >>{0}<<'.format(artifact), file=sys.stderr)
        for tupleKey, subdict in sorted(cfgDofD.iteritems()):
            pDir = cfgDofD[tupleKey][TAGpKEY]              # protected directory
            # if the artifact is under a protected directory we cannot simply allow
            isProtected = _is_under_protection(pDir, artifact)
            if CLIF_DEBUG > 2:
                print('simply_allow: tupleKey={0}, isProtected={1} artifact={2}'.format(tupleKey, isProtected, artifact), file=sys.stderr)
            if isProtected == True:
                justAllow = False                                       # nope, we gotta work!
                break
    if CLIF_DEBUG > 1:
        print('simply_allow: return {0}'.format(justAllow), file=sys.stderr)
    return justAllow # }

# THIS COMMIT IS NOT SIMPLE, WHICH MEANS THIS COMMIT IS ATTEMPTING
# TO DO SOMETHING UNDER A PROTECTED PARENT DIRECTORY.  USUALLY THAT
# IS FORBIDDEN, BUT DEPENDING ON EXACTLY WHAT IS BEING ATTEMPTED,
# such as adding a new sub project or moving an existing project
# into a archive folder, IT MIGHT BE ALLOWED
def allow_commit(): # {
    global CLIF_DEBUG
    global CommitData
    global PROGNAME
    global VERSION
    author = ""        # person making commit
    artifact = ""      # the thing being commmitted
    change = ""        # a D or an A
    last_ele = ""      # to avoid duplicates
    check1st = ""      # to avoid duplicates
    commit = True      # assume OK to commit
    dbgcnt = 0         # used during debug
    isProtected = True # is it protected?
    ok2add = False     # push to the add array?
    tupleKey = ""      # key into configuration HoH
    addarts = []       # list of artifacts being added
    delarts = []       # list of artifacts being deleted
    tmp1 = ""          # used to push an array into @add or @del
    element = ""       # artifact to be committed, changed or whatever
    tmp2 = ""          # artifact to be committed, changed or whatever
    if CLIF_DEBUG > 7:
        print("allow_commit: ENTER: listing array of commits", file=sys.stderr)
        dbgcnt = 0
        for element in CommitData:
            print("allow_commit: CommitData[{0}] = {1}".format(dbgcnt, element), file=sys.stderr)
            dbgcnt = dbgcnt + 1
        print("allow_commit: LEAVE: listing array of commits", file=sys.stderr)
    dbgcnt = 0
    for element in CommitData:
        if CLIF_DEBUG > 6:
            print("allow_commit: CommitData[{0}] = {1}".format(dbgcnt, element), file=sys.stderr)
            dbgcnt = dbgcnt + 1
        # get the next array element
        # use a regexp "split" into 3 parts, the middle part is thrown away (it is just 2 spaces)
        # 1st part is 2 chars loaded to change
        # 2nd part is 2 spaces, ignored
        # 3rd part is the artifact
        change = re.sub(r'^(..)(  )(.+)$', r'\1', element)
        artifact = re.sub(r'^(..)(  )(.+)$', r'\3', element)
        change = re.sub(r' *$', r'', change)                          # remove trailing space, sometimes there is one
        if CLIF_DEBUG > 6:
            print('allow_commit: change = "{0}"'.format(change), file=sys.stderr)
            print('allow_commit: artifact = "{0}"'.format(artifact), file=sys.stderr)
        [isProtected, tupleKey] = _artifact_under_protected_dir(artifact)
        if CLIF_DEBUG > 2:
            print('allow_commit: tupleKey = "{0}" isProtected = {1} artifact="{2}"'.format(tupleKey, isProtected, artifact), file=sys.stderr)
        if isProtected == True:
            if change == 'U' or change == '_U' or change == 'UU':
                print('{0}: commit failed, modifications to protected directories or files is not allowed!'.format(PROGNAME), file=sys.stderr)
                print('{0}: commit failed on: "{1}"'.format(PROGNAME, artifact), file=sys.stderr)
                commit = False;
                break
            else:
                ok2add = True    # assume this path has not been added
                if change == 'D':
                    if len(delarts) > 0:
                        last_ele = delarts[-1]
                        check1st = last_ele[-1]
                        if len(artifact) >= len(check1st):
                             if check1st.find(artifact, 0, len(artifact)) == 0:
                                 ok2add = False
                elif change == 'A':     # hey that is all it can be
                    if len(addarts) > 0:
                        last_ele = addarts[-1]
                        check1st = last_ele[-1]
                        if len(artifact) >= len(check1st):
                             if check1st.find(artifact, 0, len(artifact)) == 0:
                                 ok2add = False
                else:    # THIS SHOULD NEVER HAPPEN AND IS HERE IN CASE SUBVERSION CHANGES
                        ## this is a safety check - just comment it out to keep on trunking
                    print('{0}: commit failed, unknown value for change="{1}"'.format(PROGNAME, change), file=sys.stderr)
                    print('{0}: commit failed on: {1}'.format(PROGNAME, element), file=sys.stderr)
                    commit = False
                    break
                if ok2add:
                    if change == 'D':
                        if CLIF_DEBUG > 3:
                            print('allow_commit: append this list to list of artifacts being deleted: ["{0}", "{1}"]'.format(tupleKey, artifact), file=sys.stderr)
                        delarts.append([tupleKey, artifact])
                    else:
                        if CLIF_DEBUG > 3:
                            print('allow_commit: append this list to list of artifacts being added:   ["{0}", "{1}"]'.format(tupleKey, artifact), file=sys.stderr)
                        addarts.append([tupleKey, artifact])
                elif CLIF_DEBUG > 4:
                    if change == 'D':
                        print('allow_commit: duplicate, do NOT push to array of artifacts being deleted: {0}'.format(artifact), file=sys.stderr)
                    else:
                        print('allow_commit: duplicate, do NOT push to array of artifacts being added: {1}'.format(artifact), file=sys.stderr)
    if commit == True:
        # See if attempting a delete only
        if len(addarts) == 0 and len(delarts) != 0:
            if CLIF_DEBUG > 2:
                print("allow_commit: the protected commit is a DELETE ONLY", file=sys.stderr)
            commit = _say_no_delete(artifact)    # always returns False
        # See if attempting an add only
        elif len(addarts) != 0 and len(delarts) == 0:
            author = _svn_get_author()
            if CLIF_DEBUG > 2:
                print("allow_commit: the protected commit is an ADD ONLY", file=sys.stderr)
            commit = _the_add_is_allowed(author, addarts)     # returns True or False
        # See if attempting an add and a delete, only do this if moving a tag to an archive directory
        elif len(addarts) != 0 and len(delarts) != 0:
            author = _svn_get_author();
            if CLIF_DEBUG > 2:
                print("allow_commit: the protected commit has both ADD AND DELETE", file=sys.stderr)
            commit = _the_move_is_allowed(element, author, addarts, delarts)     # returns True or False
        # Not attempting anything! What? That's impossible, something is wrong.
        elif len(addarts) == 0 and len(delarts) == 0:
            if CLIF_DEBUG > 2:
                print("allow_commit: the protected commit is IMPOSSIBLE", file=sys.stderr)
            commit = _say_impossible() # always returns False
    if CLIF_DEBUG > 0:
        print("allow_commit: return {0}".format(commit), file=sys.stderr)
    return commit # allow_commit }

#################################################################################
################################# PUBLIC METHODS ################################
## LEAVE: ######################################################################]
