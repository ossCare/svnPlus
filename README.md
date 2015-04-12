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
