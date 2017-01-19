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

from __future__ import print_function
import os
import sys
import re
from setuptools import setup

def read(fname):
    return open(os.path.join(os.path.dirname(__file__), fname)).read()

def theVersion():
    vfile = "svnplus/tagprotect.py" # relative path , file with version string
    verStr = ""
    f = open(os.path.join(os.path.dirname(__file__), vfile))
    if f:
        regex = re.compile(r'^VERSION\s*=\s*')
        for line in f:
            if regex.match(line) is not None:
                #print('line:  {0}'.format(line), file=sys.stderr)
                verStr = re.sub(r'\s*$', r'', line)
                #print('verStr: {0}'.format(verStr), file=sys.stderr)
                verStr = re.sub(r'^VERSION\s*=\s*', r'', verStr)
                #print('verStr: {0}'.format(verStr), file=sys.stderr)
                verStr = re.sub(r'^"(.+)"$', r'\1', verStr)
                #print('verStr: {0}'.format(verStr), file=sys.stderr)
                verStr = re.sub(r"^'(.+)'$", r'\1', verStr)
                #print('verStr: {0}'.format(verStr), file=sys.stderr)
                break
    else:
        print('failed to open will NOT read', file=sys.stderr)
    if verStr != "":
       print('version is: {0} from file "{1}"'.format(verStr, vfile), file=sys.stderr)
       return verStr
    exit(1)

setup(name='svnplus',
      author_email='joseph.pietras@gmail.com',
      author='Joseph C. Pietras',
      classifiers=['Intended Audience :: Information Technology', 'License :: OSI Approved :: Apache Software License', 'Natural Language :: English'],
      data_files=[ ("/root/svnplus", ['LICENSE', 'pre-commit', 'pre-commit.conf']) ],
      description='''This is a subversion hook.  It provides a protection mechanism for subversion repositories so that previously committed "tags" are immutable.''',
      include_package_data=True,
      keywords='subversion hook tagprotect immutable',
      license='Apache Software License 2.0',
      long_description=read('README'),
      packages=['svnplus'],
      url='https://github.com/ossCare/svnPlus',
      version=theVersion(),
      zip_safe=False)
