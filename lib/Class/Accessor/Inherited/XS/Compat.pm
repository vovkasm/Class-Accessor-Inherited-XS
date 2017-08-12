package Class::Accessor::Inherited::XS::Compat;
use 5.010001;
use strict;
use warnings;

sub mk_type_accessors {
    my ($class, $type) = (shift, shift);

    my ($installer, $clone_arg) = $class->_type_installer($type);

    for my $entry (@_) {
        if (ref($entry) eq 'ARRAY') {
            $installer->($class, @$entry);

        } else {
            $installer->($class, $entry, $clone_arg && $entry);
        }
    }
}

sub mk_inherited_accessors {
    my $class = shift;
    mk_type_accessors($class, 'inherited', @_);
}

sub mk_class_accessors {
    my $class = shift;
    mk_type_accessors($class, 'class', @_);
}

sub mk_varclass_accessors {
    my $class = shift;
    mk_type_accessors($class, 'varclass', @_);
}

sub mk_object_accessors {
    my $class = shift;
    mk_type_accessors($class, 'object', @_);
}

1;
