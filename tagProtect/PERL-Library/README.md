# svnPlus
svn tag based protection mechanism

version 0.3: initial commit, not really working well

version 1.0: working!

version 1.1: nothing added, just fixed default configuration values

version 2.0: changed the names of most of the configuration variables
	     to be more "administrator" centric, not developer
	     centric. Added man page and make file for installing
	     it.

version 2.1: added the logic to dump backslash `\' from subdirectories
	     (or project directories).  Ok, *nix does allow `\' in
	     a directory or file name but do you really want this?
	     Test have to be applied to the subdirectory (project
	     directory) values to remove attempts to do things like
                 PROTECTED_PRJDIR=/tags/../messing-with-you
	     If this is not a good thing let us know and we can
	     implement something different.

version 2.2: fixed the issue of allowing each protected directory
             to have its own Archive directory (or whatevery you
             name it).
             modified AllowCommit to check all Archive directories
             instead of just the primary Archive directory or the
             first fix would not work correctly.

version 2.3: tech debt changes only (changed the use of "folder"
             to "directory").

version 2.4: lots of code changes to get ready for making tagprotect.pl
             into a PERL object. Debugging working more consistently
             but not done.

version 2.5: removed no longer accurate comments, added more comments
             and other minor changes to i/o.

TBD
version 3.0: NOTE: an attempt to del/add (i.e. move) a directory
             or file to a protected folder has not been tested
             or "thought of".  It needs testing.
