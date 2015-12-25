use strict;
use Test::More;

{
    package Jopa;
    use Class::Accessor::Inherited::XS inherited => [qw/a b/];
}

$Jopa::__cag_a = 1;
is(Jopa->a, 1);

Jopa->b(2);
is(Jopa->b, 2);
is($Jopa::__cag_b, 2);

done_testing;
