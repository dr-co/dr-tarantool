package DR::Tarantool;

use 5.010001;
use strict;
use warnings;
use Carp;

use base qw(Exporter);


our %EXPORT_TAGS = (
    all         => [ qw(  ) ],
    constant    => [
        qw(
            TNT_INSERT TNT_SELECT TNT_UPDATE TNT_DELETE TNT_CALL TNT_PING
            TNT_FLAG_RETURN TNT_FLAG_ADD TNT_FLAG_REPLACE TNT_FLAG_BOX_QUIET
            TNT_FLAG_NOT_STORE
        )
    ],
);
our @EXPORT_OK = ( map { @$_ } values %EXPORT_TAGS );
our @EXPORT = qw(insert);
our $VERSION = '0.01';

require XSLoader;
XSLoader::load('DR::Tarantool', $VERSION);


*TNT_PING           = \&DR::Tarantool::_op_ping;
*TNT_CALL           = \&DR::Tarantool::_op_call;
*TNT_INSERT         = \&DR::Tarantool::_op_insert;
*TNT_UPDATE         = \&DR::Tarantool::_op_update;
*TNT_DELETE         = \&DR::Tarantool::_op_delete;
*TNT_SELECT         = \&DR::Tarantool::_op_select;

*TNT_FLAG_RETURN    = \&DR::Tarantool::_flag_return;
*TNT_FLAG_ADD       = \&DR::Tarantool::_flag_add;
*TNT_FLAG_REPLACE   = \&DR::Tarantool::_flag_replace;
*TNT_FLAG_BOX_QUIET = \&DR::Tarantool::_flag_box_quiet;
*TNT_FLAG_NOT_STORE = \&DR::Tarantool::_flag_not_store;

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

 Copyright (C) 2011 Dmitry E. Oboukhov <unera@debian.org>
 Copyright (C) 2011 Roman V. Nikolaev <rshadow@rambler.ru>

 This program is free software, you can redistribute it and/or
 modify it under the terms of the Artistic License.

=head1 VCS

The project is placed git repo on github:
L<https://github.com/unera/dr-tarantool/>.


=cut
