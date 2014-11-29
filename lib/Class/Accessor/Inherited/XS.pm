package Class::Accessor::Inherited::XS;
use 5.010001;
use strict;
use warnings;

our $VERSION = '0.02';

require XSLoader;
XSLoader::load('Class::Accessor::Inherited::XS', $VERSION);

{
    no strict 'refs';
    
    sub import {
        my $pkg = shift;
        return unless scalar @_;

        my $class = caller;
        my %opts = ref($_[0]) eq 'HASH' ? %{ $_[0] } : @_;

        if (my $inherited = $opts{inherited}) {
            if (ref($inherited) eq 'HASH') {
                mk_inherited_accessor($class, $_, $inherited->{$_}) for keys %$inherited;

            } elsif (ref($inherited) eq 'ARRAY') {
                mk_inherited_accessor($class, $_, $_) for @$inherited;

            } else {
                warn "Can't understand format for inherited accessors initializer for class $class";
            }
        }
    }

    sub mk_inherited_accessors {
        my $class = shift;

        for my $entry (@_) {
            if (ref($entry) eq 'ARRAY') {
                mk_inherited_accessor($class, @$entry);
            } else {
                mk_inherited_accessor($class, $entry, $entry);
            }
        }
    }

    sub mk_inherited_accessor {
        my($class, $name, $field) = @_;

        Class::Accessor::Inherited::XS::install_inherited_accessor("${class}::${name}", $field);
    }
}

1;
__END__

=head1 NAME

Class::Accessor::Inherited::XS - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Class::Accessor::Inherited::XS;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Class::Accessor::Inherited::XS, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Vladimir Timofeev, E<lt>vovkasm@homeE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Vladimir Timofeev
Copyright (C) 2014 by Sergey Aleynikov

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
