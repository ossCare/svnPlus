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

use 5.010000;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'SVNPlus::TagProtect',
    VERSION_FROM      => 'lib/SVNPlus/TagProtect.pm', # finds $VERSION
    PREREQ_PM         => {
                           #'autodie' => 0.1,             CORE no need
                           #'Cwd' => 0.1,                 CORE no need
                           #'ExtUtils::MakeMaker' => 0.1, CORE no need
                           #'POSIX' => 0.1,
                           'Sysadm::Install' => 0.1,
                           #'Test::More' => 0.1,          CORE no need
                           'Text::Glob' => 0.01,
                         },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/SVNPlus/TagProtect.pm', # retrieve abstract from module
       AUTHOR         => 'Joseph C. Pietras <joseph.pietras@gmail.com>') : ()),
);
