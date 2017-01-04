# svnPlus
svn tag based protection mechanism

What this software does is to allow subversion admin to control "tagged" subversion folders so that they can no longer be modified.
This insures, for example, that the source code for a deployment, say release 1.3.7, is not changed after its release.


SVNPlus-TagProtect version 3.18.1
=================================
The PERL code has been updated with minor bug fixes found while porting the code to Python.
This is the last updates to the PERL code and all futher updates will be with in the Python line.




SVNPlus-TagProtect version 3.17.0
=================================

The README is used to introduce the module and provide instructions on
how to install the module, any machine dependencies it may have (for
example C compilers and installed libraries) and any other information
that should be provided before the module is installed.

A README file is required for CPAN modules since CPAN extracts the
README file from a module distribution so that people browsing the
archive can use it get an idea of the modules uses. It is usually a
good idea to provide version information here so that people can
decide whether fixes for the module are worth downloading.

INSTALLATION

To install this module type the following:

   perl Makefile.PL
   make
   make test
   make install

DEPENDENCIES

This module requires these other modules and libraries:

   autodie
   Sysadm::Install.pm
   Text::Glob
   POSIX
   Cwd

COPYRIGHT AND LICENCE

Put the correct copyright and licence information here.

Copyright (C) 2015 by Joseph C. Pietras

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.16.2 or,
at your option, any later version of Perl 5 you may have available.
