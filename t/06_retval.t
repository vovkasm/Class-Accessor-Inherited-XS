package Jopa;
use Test::More;
use parent 'Class::Accessor::Inherited::XS';

__PACKAGE__->mk_inherited_accessors('foo');

my $obj = bless {}, 'Jopa';
my $bar = \($obj->foo(24));
is($obj->foo, 24);
is($$bar, 24);

$$bar++;
is($obj->foo, 25);

done_testing;