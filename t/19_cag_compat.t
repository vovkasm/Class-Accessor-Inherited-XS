use strict;
use Test::More;

use Class::Accessor::Inherited::XS inherited => [qw/foo/];
@main1::ISA = qw/main/;
@main2::ISA = qw/main1/;

is(main->foo(5), 5);
is(main2->foo, 5);

$main::__cag_foo = 42;
is(main2->foo, 42);

$main1::__cag_foo = 17;
is(main2->foo, 17);
is(main1->foo, 17);
is(main->foo, 42);

$main1::__cag_foo = 25;
is(main1->foo, 25);
is(main2->foo, 25);
is(main->foo, 42);

$main::__cag_foo = 88;
is(main2->foo, 25);
is(main->foo, 88);

$main1::__cag_foo = undef;
is(main1->foo, 88);

done_testing;
