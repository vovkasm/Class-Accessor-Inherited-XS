use strict;
use Test::More;
use Class::Accessor::Inherited::XS;

sub on_read  { $_[0] + 1 }
sub on_write { $_[1] + 2 }

BEGIN {
    Class::Accessor::Inherited::XS::register_type(
        component => {read_cb => \&on_read, write_cb => \&on_write}
    );
    Class::Accessor::Inherited::XS::register_type(
        die       => {read_cb => \&die, write_cb => \&die},
    );
}

use Class::Accessor::Inherited::XS
    component => ['foo'],
    die       => ['fire'],
;

is(main->foo, 1);
is(main->foo, 1);
is(main->foo, 1) for (1..3);

#is(main->foo(1), 3);
#is(main->foo(1), 3);
#is(main->foo(1), 3) for (1..3);

main->foo(3);

is(main->foo, 4);
is(main->foo, 4);
is(main->foo, 4) for (1..3);

eval {
    main->fire;
    ok 0;
} for (1..3);

my $obj = bless {};

#is($obj->foo(4), 6) for (1..4);

$obj->foo(6);
is($obj->foo, 7);
is($obj->foo, 7);
is($obj->foo, 7) for (1..4);

done_testing;
