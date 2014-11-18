use 5.010001;
use ExtUtils::MakeMaker;

my $CCFLAGS = join(' ',$Config{ccflags},'-x c++');

WriteMakefile(
    NAME            => 'Class::Accessor::Inherited::XS',
    VERSION_FROM    => 'lib/Class/Accessor/Inherited/XS.pm',
    AUTHOR          => ['Vladimir Timofeev <vovkasm@crazypanda.ru>', 'Sergey Aleynikov <sergey.aleynikov@gmail.com>'],
    PREREQ_PM       => {
        'Class::Accessor::Grouped'  => 0,
        'XSLoader'                  => 0,
    },
    META_MERGE => {
        resources => {
            repository => 'http://github.com/vovkasm/Class-Accessor-Inherited-XS',
        },
    },
    ABSTRACT_FROM   => 'lib/Class/Accessor/Inherited/XS.pm',
    LIBS            => ['-lstdc++'],
    INC             => '-I.',
    CCFLAGS         => $CCFLAGS,
    LICENSE         => 'perl',
    MIN_PERL_VERSION=> 5.010001,
);

