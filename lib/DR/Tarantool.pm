package DR::Tarantool;

=head1 NAME

DR::Tarantool - perl driver for L<tarantool|http://tarantool.org>


=head1 SYNOPSIS

    use DR::Tarantool ':constant', 'tarantool';
    use DR::Tarantool ':all';

    my $tnt = tarantool
        host    => '127.0.0.1',
        port    => 123
    ;

    $tnt->update( ... );

    use DR::Tarantool ':constant', 'async_tarantool';

    async_tarantool
        host    => '127.0.0.1',
        port    => 123,
        sub {
            ...
        }
    ;

    $tnt->update(...);

=head1 DESCRIPTION

The module provides sync and async drivers for
L<tarantool|http://tarantool.org>.

The driver uses libtarantool* libraries for making requests and
parsing responses.

=cut

use 5.010001;
use strict;
use warnings;
use Carp;
$Carp::Internal{ (__PACKAGE__) }++;

use base qw(Exporter);


our %EXPORT_TAGS = (
    client      => [ qw( tarantool async_tarantool ) ],
    constant    => [
        qw(
            TNT_INSERT TNT_SELECT TNT_UPDATE TNT_DELETE TNT_CALL TNT_PING
            TNT_FLAG_RETURN TNT_FLAG_ADD TNT_FLAG_REPLACE TNT_FLAG_BOX_QUIET
            TNT_FLAG_NOT_STORE
        )
    ],
);

our @EXPORT_OK = ( map { @$_ } values %EXPORT_TAGS );
$EXPORT_TAGS{all} = \@EXPORT_OK;
our @EXPORT = @{ $EXPORT_TAGS{client} };
our $VERSION = '0.03';


=head1 EXPORT

=head2 tarantool

connects to L<tarantool|http://tarantool.org> in sync mode using
L<DR::Tarantool::SyncClient>.


=cut

sub tarantool       {
    require DR::Tarantool::SyncClient;
    no warnings 'redefine';
    *tarantool = sub {
        DR::Tarantool::SyncClient->connect(@_);
    };
    &tarantool;
}


=head2 async_tarantool

connects to L<tarantool|http://tarantool.org> in sync mode using
L<DR::Tarantool::SyncClient>.

=cut

sub async_tarantool {
    require DR::Tarantool::AsyncClient;
    no warnings 'redefine';
    *async_tarantool = sub {
        DR::Tarantool::AsyncClient->connect(@_);
    };
    &async_tarantool;
}



=head2 :constant

Exports constants to use in request as flags:

=over

=item TNT_FLAG_RETURN

If You use the flag, driver will return tuple that were
inserted/deleted/updated.

=item TNT_FLAG_ADD

Try to add tuple. Return error if tuple is already exists.

=item TNT_FLAG_REPLACE

Try to replace tuple. Return error if tuple isn't exists.

=back

=cut

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


=head2 :all

Exports all functions and constants.


=head1 SEE ALSO

The module uses L<DR::Tarantool::SyncClient> and (or)
L<DR::Tarantool::AsyncClient>.

=head1 COPYRIGHT AND LICENSE

 Copyright (C) 2011 Dmitry E. Oboukhov <unera@debian.org>
 Copyright (C) 2011 Roman V. Nikolaev <rshadow@rambler.ru>

 This program is free software, you can redistribute it and/or
 modify it under the terms of the Artistic License.

=head1 VCS

The project is placed git repo on github:
L<https://github.com/unera/dr-tarantool/>.

=cut

1;
