package DR::Tarantool;

=head1 NAME

DR::Tarantool - a Perl driver for L<Tarantool/Box|http://tarantool.org>


=head1 SYNOPSIS

    use DR::Tarantool ':constant', 'tarantool';
    use DR::Tarantool ':all';

    my $tnt = tarantool
        host    => '127.0.0.1',
        port    => 123,
        spaces  => {
            ...
        }
    ;

    $tnt->update( ... );

    my $tnt = coro_tarantool
        host    => '127.0.0.1',
        port    => 123,
        spaces  => {
            ...
        }
    ;

    use DR::Tarantool ':constant', 'async_tarantool';

    async_tarantool
        host    => '127.0.0.1',
        port    => 123,
        spaces  => {
            ...
        },
        sub {
            ...
        }
    ;

    $tnt->update(...);

=head1 DESCRIPTION

This module provides a synchronous and asynchronous driver for
L<Tarantool/Box|http://tarantool.org>.

The driver does not have external dependencies, but includes the
official leight-weight Tarantool/Box C client (a single C header which
implements all protocol formatting) for packing requests and unpacking
server resposnes.

=cut

use 5.008008;
use strict;
use warnings;
use Carp;
$Carp::Internal{ (__PACKAGE__) }++;

use base qw(Exporter);


our %EXPORT_TAGS = (
    client      => [ qw( tarantool async_tarantool coro_tarantool) ],
    constant    => [
        qw(
            TNT_INSERT TNT_SELECT TNT_UPDATE TNT_DELETE TNT_CALL TNT_PING
            TNT_FLAG_RETURN TNT_FLAG_ADD TNT_FLAG_REPLACE TNT_FLAG_BOX_QUIET
        )
    ],
);

our @EXPORT_OK = ( map { @$_ } values %EXPORT_TAGS );
$EXPORT_TAGS{all} = \@EXPORT_OK;
our @EXPORT = @{ $EXPORT_TAGS{client} };
our $VERSION = '0.35';


=head1 EXPORT

=head2 tarantool

connects to L<Tarantool/Box|http://tarantool.org> in synchronous mode
using L<DR::Tarantool::SyncClient>.


=cut

sub tarantool {
    require DR::Tarantool::SyncClient;
    no warnings 'redefine';
    *tarantool = sub {
        DR::Tarantool::SyncClient->connect(@_);
    };
    goto \&tarantool;
}


=head2 async_tarantool

connects to L<tarantool|http://tarantool.org> in async mode using
L<DR::Tarantool::AsyncClient>.

=cut

sub async_tarantool {
    require DR::Tarantool::AsyncClient;
    no warnings 'redefine';
    *async_tarantool = sub {
        DR::Tarantool::AsyncClient->connect(@_);
    };
    goto \&async_tarantool;
}


=head2 coro_tarantol

connects to L<tarantool|http://tarantool.org> in async mode using
L<DR::Tarantool::CoroClient>.


=cut

sub coro_tarantool {
    require DR::Tarantool::CoroClient;
    no warnings 'redefine';
    *coro_tarantool = sub {
        DR::Tarantool::CoroClient->connect(@_);
    };
    goto \&coro_tarantool;
}


=head2 :constant

Exports constants to use in a client request as flags:

=over

=item TNT_FLAG_RETURN

With this flag on, each INSERT/UPDATE request
returns the new value of the tuple. DELETE returns the deleted
tuple, if it is found.

=item TNT_FLAG_ADD

With this flag on, INSERT returns an error if an old tuple
with the same primary key already exists. No tuple is inserted
in this case.

=item TNT_FLAG_REPLACE

With this flag on, INSERT returns an error if an old
tuple for the primary key does not exist.
Without either of the flags, INSERT replaces the old
tuple if it doesn't exist.

=back

=cut

require XSLoader;
XSLoader::load('DR::Tarantool', $VERSION);



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

The project is hosted on github in the following git repository:
L<https://github.com/dr-co/dr-tarantool/>.

=cut

1;
