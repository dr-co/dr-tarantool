package DR::Tarantool;

use 5.010001;
use strict;
use warnings;
use Carp;

require Exporter;
use AutoLoader;

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw( ) ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw();
our $VERSION = '0.01';

require XSLoader;
XSLoader::load('DR::Tarantool', $VERSION);


1;

__END__

=head1 NAME

DR::Tarantool - Perl extension for blah blah blah

=head1 SYNOPSIS

  use DR::Tarantool;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for DR::Tarantool, created by h2xs. It looks like the
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

Dmitry E. Oboukhov, E<lt>dimka@E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Dmitry E. Oboukhov

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
