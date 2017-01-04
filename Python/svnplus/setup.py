#
#  Copyright 2015,2016 Joseph C. Pietras
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

from setuptools import setup

setup(name='svnplus',
      version='0.8',
      description='''
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

will not be allowed.''',
      url='http://github.com/storborg/svnplus',
      author='Flying Circus',
      author_email='flyingcircus@example.com',
      license='MIT',
      packages=['svnplus'],
      zip_safe=False)
