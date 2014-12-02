use Test::More;
use Class::Accessor::Inherited::XS;
use strict;

{
    package Jopa;
    use base qw/Class::Accessor::Inherited::XS/;
    use strict;

    Jopa->mk_inherited_accessors(qw/a b/);
}

$Jopa::__cag_a = 1;
is(Jopa->a, 1);

Jopa->b(2);
is(Jopa->b, 2);
is($Jopa::__cag_b, 2);

done_testing;
