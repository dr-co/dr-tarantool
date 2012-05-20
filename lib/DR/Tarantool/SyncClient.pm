use utf8;
use strict;
use warnings;

package DR::Tarantool::SyncClient;
use base 'DR::Tarantool::AsyncClient';
use AnyEvent;
use Devel::GlobalDestruction;
use Carp;
$Carp::Internal{ (__PACKAGE__) }++;

=head1 NAME

DR::Tarantool::SyncClient - sync driver for L<tarantool|http://tarantool.org>

=head1 SYNOPSIS

    my $client = DR::Tarantool::SyncClient->connect(
        port    => $tnt->primary_port,
        spaces  => $spaces
    );

    if ($client->ping) { .. };

    my $t = $client->insert(
        first_space => [ 1, 'val', 2, 'test' ], TNT_FLAG_RETURN
    );

    $t = $client->call_lua('luafunc' =>  [ 0, 0, 1 ], 'space_name');

    $t = $client->select(space_name => $key);

    $t = $client->update(space_name => 2 => [ name => set => 'new' ]);

    $client->delete(space_name => $key);


=head1 METHODS

=head2 connect

Connects to tarantool.

=head3 Arguments

The same L<DR::Tarantool::AsyncClient/connect> exclude callback.

Returns a connector or croaks error.

=cut

sub connect {
    my ($class, %opts) = @_;
    my $cv = condvar AnyEvent;
    my $self;

    $class->SUPER::connect(%opts, sub {
        ($self) = @_;
        $cv->send;
    });

    $cv->recv;

    croak $self unless ref $self;
    $self;
}

=head2 ping

The same L<DR::Tarantool::AsyncClient/ping> exclude callback.

Returns 'B<ok>' or B<FALSE> if an error.

=head2 insert

The same L<DR::Tarantool::AsyncClient/insert> exclude callback.

Returns 'B<ok>' or tuples that were extracted from database.

=head2 select

The same L<DR::Tarantool::AsyncClient/select> exclude callback.

Returns 'B<ok>' or tuples that were extracted from database.

=head2 update

The same L<DR::Tarantool::AsyncClient/update> exclude callback.

Returns 'B<ok>' or tuples that were extracted from database.

=head2 delete

The same L<DR::Tarantool::AsyncClient/delete> exclude callback.

Returns 'B<ok>' or tuples that were extracted from database.

=head2 call_lua

The same L<DR::Tarantool::AsyncClient/call_lua> exclude callback.

Returns 'B<ok>' or tuples that were extracted from database.

=cut


for my $method (qw(ping insert select update delete call_lua)) {
    no strict 'refs';
    *{ __PACKAGE__ . "::$method" } = sub {
        my ($self, @args) = @_;
        my @res;
        my $cv = condvar AnyEvent;
        my $m = "SUPER::$method";
        $self->$m(@args, sub { @res = @_; $cv->send });
        $cv->recv;

        if ($res[0] ~~ 'ok') {
            return $res[1] // $res[0];
        }
        return if $method eq 'ping';
        croak  "$res[1]: $res[2]";
    };
}

sub DESTROY {
    my ($self) = @_;
    return if in_global_destruction;

    my $cv = condvar AnyEvent;
    $self->disconnect(sub { $cv->send });
    $cv->recv;
}

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
