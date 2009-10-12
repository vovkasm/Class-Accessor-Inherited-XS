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

    *get_inherited = *Class::Accessor::Inherited::XS::get_inherited;
    *set_inherited = *Class::Accessor::Inherited::XS::set_inherited;
    *get_super_paths = *Class::Accessor::Inherited::XS::get_super_paths;

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
            
            my $alias = "_${name}_accessor";
            my $full_name = join('::', $class, $name);
            my $full_alias = join('::', $class, $alias);
            
            my $accessor = $self->make_inherited_accessor($field);
            my $alias_accessor = $self->make_inherited_accessor($field);
                
            *$full_name = Sub::Name::subname($full_name, $accessor);
            *$full_alias = Sub::Name::subname($full_alias, $alias_accessor);
        }

        return;
    }
}

sub make_inherited_accessor {
    my ($class, $field) = @_;
    return eval "sub {
        if(\@_ > 1) {
            return shift->set_inherited('$field', \@_);
        }
        else {
            return shift->get_inherited('$field');
        }
    };"
}

1;
