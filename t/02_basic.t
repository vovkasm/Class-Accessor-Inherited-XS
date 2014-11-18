use Test::More;
use Class::Accessor::Inherited::XS;
use strict;

{
    package Jopa;
    use base qw/Class::Accessor::Inherited::XS/; 
    use strict;

    sub new { return bless {}, shift }

    Jopa->mk_group_accessors( inherited => qw/a b c/ );

    1;
}

my $o = new Jopa;
$o->a(1);
is( $o->a, 1, 'get after set' );

done_testing(1);
