package AccessorInstaller;
use strict;
use warnings;

use Carp ();
use Scalar::Util ();
use Sub::Name ();

use Class::Accessor::Inherited::XS;

{
    no strict 'refs';
    no warnings 'redefine';

    sub mk_inherited_accessors {
        my($self, @fields) = @_;
        my $class = Scalar::Util::blessed $self || $self;

        foreach my $field (@fields) {
            if( $field eq 'DESTROY' ) {
                Carp::carp("Having a data accessor named DESTROY  in ".
                             "'$class' is unwise.");
            }

            my $name = $field;
            ($name, $field) = @$field if ref $field;
            
            my $full_name = join('::', $class, $name);
            my $accessor = $self->make_inherited_accessor($field);
            *$full_name = Sub::Name::subname($full_name, $accessor);
        }

        return;
    }
}

sub make_inherited_accessor {
    my ($class, $field) = @_;
    return eval "sub { Class::Accessor::Inherited::XS::inherited_accessor(shift, '$field', \@_); }";
}

1;
