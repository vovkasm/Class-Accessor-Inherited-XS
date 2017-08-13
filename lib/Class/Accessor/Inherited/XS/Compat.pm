package Class::Accessor::Inherited::XS::Compat;
use 5.010001;
use strict;
use warnings;

use Class::Accessor::Inherited::XS;

sub mk_type_accessors {
    my ($class, $type) = (shift, shift);

    {
        require mro;
        state $seen = {};
        state $message = <<EOF;
Inheriting from 'Class::Accessor::Inherited::XS' is deprecated, this behavior will be removed in the next version! To use __PACKAGE__->mk_${type}_accessors form inherit from 'Class::Accessor::Inherited::XS::Compat' instead.
EOF
        warn $message if !$seen->{$class}++ && scalar grep { $_ eq 'Class::Accessor::Inherited::XS' } @{ mro::get_linear_isa($class) };
    }

    my ($installer, $clone_arg) = Class::Accessor::Inherited::XS->_type_installer($type);

    for my $entry (@_) {
        if (ref($entry) eq 'ARRAY') {
            $installer->($class, @$entry);

        } else {
            $installer->($class, $entry, $clone_arg && $entry);
        }
    }
}

sub mk_inherited_accessors {
    shift->mk_type_accessors('inherited', @_);
}

sub mk_class_accessors {
    shift->mk_type_accessors('class', @_);
}

sub mk_varclass_accessors {
    shift->mk_type_accessors('varclass', @_);
}

sub mk_object_accessors {
    shift->mk_type_accessors('object', @_);
}

1;
