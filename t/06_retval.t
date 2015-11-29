package Jopa;
use Test::More;
use parent 'Class::Accessor::Inherited::XS';

__PACKAGE__->mk_inherited_accessors('foo');
__PACKAGE__->mk_class_accessors('cfoo');

my $obj = bless {}, 'Jopa';
my $bar = \($obj->foo(24));
is($obj->foo, 24);
is($$bar, 24);

$$bar++;
is($obj->foo, 25);

my $baz = \($obj->foo);
$$baz++;
is($obj->foo, 26);

my $cbar = \(__PACKAGE__->cfoo(24));
$$cbar++;
is(__PACKAGE__->cfoo, 25);

my $cbaz = \(__PACKAGE__->cfoo);
$$cbaz++;
is(__PACKAGE__->cfoo, 26);

done_testing;