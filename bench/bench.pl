#!perl

use Class::Accessor::Inherited::XS;
use Class::Accessor::Grouped;
use Class::XSAccessor;
use strict;
use Benchmark qw/timethis timethese/;

my $o = CCC->new;
$o->a(3);
my $o2 = CCC2->new;
$o2->a(4);
$o2->simple(5);

AAA->a(7);
AAA2->a(8);

timethese(
    -2,
    {
        ic1xs => sub { AAA->a },
        ic1pp => sub { AAA2->a },
        ic2xs => sub { BBB->a },
        ic2pp => sub { BBB2->a },
        ic3xs => sub { CCC->a },
        ic3pp => sub { CCC2->a },
        io_xs => sub { $o->a },
        io_pp => sub { $o2->a },
        so => sub { $o2->simple },
    }
);

BEGIN {

    package IaInstaller;
    use base qw/Class::Accessor::Inherited::XS Class::Accessor::Grouped/;

    package AAA;
    use base qw/IaInstaller/;
    use strict;

    sub new { return bless {}, shift }

    AAA->mk_group_accessors( inherited => qw/a/ );

    package BBB;
    use base 'AAA';

    package CCC;
    use base 'BBB';

    package AAA2;
    use base qw/Class::Accessor::Grouped/;
    use strict;

    sub new { return bless {}, shift }

    AAA2->mk_group_accessors( inherited => qw/a/ );
    AAA2->mk_group_accessors( simple => qw/simple/ );

    package BBB2;
    use base 'AAA2';

    package CCC2;
    use base 'BBB2';

    1;

}
