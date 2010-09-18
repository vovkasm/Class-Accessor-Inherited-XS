package AccessorInstaller;
use strict;
use warnings;

use Carp ();
use Scalar::Util ();
use Sub::Name ();

use mro 'c3';
use base 'Class::Accessor::Grouped';
use Class::Accessor::Inherited::XS;

{
    no strict 'refs';
    no warnings 'redefine';

    sub make_group_accessor {
        my($class, $group, $field, $name) = @_;

        if ( $group eq 'inherited' ) {
            Class::Accessor::Inherited::XS::install_inherited_accessor($class, $field, $name);
#            my $full_name = join('::', $class, $name);
#            my $accessor = eval "sub { Class::Accessor::Inherited::XS::inherited_accessor(shift, '$field', \@_); }";
#            *$full_name = Sub::Name::subname($full_name, $accessor);
            return;
        }

        return $class->next::method($group, $field, $name);
    }
}

1;
