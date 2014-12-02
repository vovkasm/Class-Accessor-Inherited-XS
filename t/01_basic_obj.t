use Test::More;
use Class::Accessor::Inherited::XS;
use strict;

{
    package Jopa;
    use base qw/Class::Accessor::Inherited::XS/;
    use strict;

    sub new { return bless {}, shift }

    Jopa->mk_inherited_accessors(qw/a b c/);
    Jopa->mk_inherited_accessors(qw/d/);

    1;
}

my $o = new Jopa;
$o->{a} = 1;
is( $o->a, 1, 'get after set' );

$o->{b} = 5;
is( $o->b, 5, 'get after set' );

is( $o->a, 1, 'a is stil the same' );

is $o->d(12), 12;

done_testing;
