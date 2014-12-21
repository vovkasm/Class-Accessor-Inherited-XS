use Test::More;
use Class::Accessor::Inherited::XS;
use strict;

Class::Accessor::Inherited::XS::install_inherited_accessor("Jopa::foo", "foo", "__cag_foo");
my $obj = bless {}, 'Jopa';

my $bar = \($obj->foo(24));
is($obj->foo, 24);
is($$bar, 24);

$$bar++;
is($obj->foo, 25);

done_testing;