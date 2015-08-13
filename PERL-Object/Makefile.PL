use 5.008004;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'SVNPlus::TagProtect',
    VERSION_FROM      => 'lib/SVNPlus/TagProtect.pm', # finds $VERSION
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/SVNPlus/TagProtect.pm', # retrieve abstract from module
       AUTHOR         => 'Joseph C. Pietras <joseph.pietras@gmail.com>') : ()),
);
