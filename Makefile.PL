use 5.010001;
use ExtUtils::MakeMaker;

#system 'pod2text lib/Class/Accessor/Inherited/XS.pm > README';
my $CCFLAGS = join(' ',$Config{ccflags},'-x c++');

WriteMakefile(
    NAME            => 'Class::Accessor::Inherited::XS',
    VERSION_FROM    => 'lib/Class/Accessor/Inherited/XS.pm',
    AUTHOR          => ['Vladimir Timofeev <vovkasm@crazypanda.ru>', 'Sergey Aleynikov <randir@cpan.org>'],
    PREREQ_PM       => {
        'XSLoader'                  => 0,
    },
    TEST_REQUIRES   => {
        'Test::Fatal' => 0,
        'Test::More'  => 0,
    },
    META_MERGE => {
        resources => {
            repository => 'http://github.com/vovkasm/Class-Accessor-Inherited-XS',
        },
    },
    ABSTRACT_FROM   => 'lib/Class/Accessor/Inherited/XS.pm',
    CCFLAGS         => $CCFLAGS,
    LICENSE         => 'perl',
    MIN_PERL_VERSION=> 5.010001,
);

