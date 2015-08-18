use 5.008004;
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
