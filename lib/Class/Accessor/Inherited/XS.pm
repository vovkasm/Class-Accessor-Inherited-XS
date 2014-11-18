package Class::Accessor::Inherited::XS;
use 5.010001;
use strict;
use warnings;
use mro 'c3';
use parent 'Class::Accessor::Grouped';

our $VERSION = '0.02';

require XSLoader;
XSLoader::load('Class::Accessor::Inherited::XS', $VERSION);

{
    no strict 'refs';
    no warnings 'redefine';
    
    # for Class::Accessor::Grouped (should be in base classes)
    sub make_group_accessor {
        my($class, $group, $field, $name) = @_;

        if ($group eq 'inherited') {
            Class::Accessor::Inherited::XS::install_inherited_accessor("${class}::${name}", $field);
            return;
        }

        return $class->next::method($group, $field, $name);
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

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
