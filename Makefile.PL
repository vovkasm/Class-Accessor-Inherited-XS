use 5.010001;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'Class::Accessor::Inherited::XS',
    VERSION_FROM      => 'lib/Class/Accessor/Inherited/XS.pm', # finds $VERSION
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Class/Accessor/Inherited/XS.pm', # retrieve abstract from module
       AUTHOR         => 'Vladimir Timofeev <vovkasm@gmail.com>') : ()),
    LIBS              => [''], # e.g., '-lm'
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => '-I.', # e.g., '-I. -I/usr/include/other'
	#OPTIMIZE		  => '-g3',
	# Un-comment this if you add C files to link with later:
    # OBJECT            => '$(O_FILES)', # link all the C files too
);
