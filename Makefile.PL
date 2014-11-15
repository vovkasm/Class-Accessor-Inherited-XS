use strict;
use Panda::Install;

write_makefile(
    NAME      => 'Class::Accessor::Inherited::XS',
    BIN_DEPS  => ['Panda::LIb', 'Panda::XS'],
);
