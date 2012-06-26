use utf8;
use strict;
use warnings;

package DR::Tarantool::CoroClient;
use base 'DR::Tarantool::AsyncClient';
use Coro;
use Carp;
use AnyEvent;

=head1 NAME

DR::Tarantool::CoroClient - async coro driver for
L<tarantool|http://tarantool.org>

=head1 SYNOPSIS

    use DR::Tarantool::CoroClient;
    use Coro;
    my $client = DR::Tarantool::CoroClient->connect(
        port    => $port,
        spaces  => $spaces;
    );

    my @res;
    for (1 .. 100) {
        async {
            push @res => $client->select(space_name => $_);
        }
    }
    cede while @res < 100;


=head1 METHODS

=head2 connect

Connects to tarantool.

=head3 Arguments

The same as L<DR::Tarantool::AsyncClient/connect> exclude callback.

Returns a connector or croaks error.

=cut

sub connect {
    my ($class, %opts) = @_;
    my $cv = condvar AnyEvent;

    my $cb = Coro::rouse_cb;
    $class->SUPER::connect(%opts, $cb);

    my ($self) = Coro::rouse_wait;
    croak $self unless ref $self;
    $self;
}

=head2 ping

The same as L<DR::Tarantool::AsyncClient/ping> exclude callback.

Returns B<TRUE> or B<FALSE> if an error.

=head2 insert

The same as L<DR::Tarantool::AsyncClient/insert> exclude callback.

Returns tuples that were extracted from database or undef.
Croaks error if an error was happened.

=head2 select

The same as L<DR::Tarantool::AsyncClient/select> exclude callback.

Returns tuples that were extracted from database or undef.
Croaks error if an error was happened.

=head2 update

The same as L<DR::Tarantool::AsyncClient/update> exclude callback.

Returns tuples that were extracted from database or undef.
Croaks error if an error was happened.

=head2 delete

The same as L<DR::Tarantool::AsyncClient/delete> exclude callback.

Returns tuples that were extracted from database or undef.
Croaks error if an error was happened.

=head2 call_lua

The same as L<DR::Tarantool::AsyncClient/call_lua> exclude callback.

Returns tuples that were extracted from database or undef.
Croaks error if an error was happened.

=cut


for my $method (qw(ping insert select update delete call_lua)) {
    no strict 'refs';
    *{ __PACKAGE__ . "::$method" } = sub {
        my ($self, @args) = @_;

        my $cb = Coro::rouse_cb;
        my $m = "SUPER::$method";
        $self->$m(@args, $cb);

        my @res = Coro::rouse_wait;

        if ($res[0] eq 'ok') {
            return 1 if $method eq 'ping';
            return $res[1];
        }
        return 0 if $method eq 'ping';
        croak  "$res[1]: $res[2]";
    };
}

1;
