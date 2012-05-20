use utf8;
use strict;
use warnings;

package DR::Tarantool::AsyncClient;
use DR::Tarantool::LLClient;
use DR::Tarantool::Spaces;
use DR::Tarantool::Tuple;
use Carp;
$Carp::Internal{ (__PACKAGE__) }++;
use Data::Dumper;
use Scalar::Util 'blessed';
use base qw(Exporter);

our @EXPORT_OK = qw(tarantool);

=head1 NAME

DR::Tarantool::AsyncClient - async client for L<tarantool|http://tarantool.org>

=head1 SYNOPSIS

    use DR::Tarantool::AsyncClient 'tarantool';

    DR::Tarantool::AsyncClient->connect(
        host    => '127.0.0.1',
        port    => 12345,
        spaces  => {
            0   => {
                name    => 'users',
                fields  => [
                    qw(login password role),
                    {
                        name    => 'counter',
                        type    => 'NUM'
                    }
                ],
                indexes => {
                    0   => 'login',
                    1   => [ qw(login password) ],
                }
            },
            2   => {
                name    => 'roles',
                fields  => [ qw(name title) ],
                indexes => {
                    0   => 'name',
                    1   => {
                        name    => 'myindex',
                        fields  => [ 'name', 'title' ],
                    }
                }
            }
        }
        sub {
            my ($client) = @_;
            ...
        }
    );

    $client->ping(sub { ... });

    $client->insert('space', [ 'user', 10, 'password' ], sub { ... });

    $client->call_lua(foo => ['arg1', 'arg2'], sub {  });

    client->select('space', 1, sub { ... });

    $client->delete('space', 1, sub { ... });

    $client->update('space', 1, [ passwd => set => 'abc' ], sub { .. });


=head1 Class methods


=cut

sub _split_args {

    if (@_ % 2) {
        my ($self, %opts) = @_;
        my $cb = delete $opts{cb};
        return ($self, $cb, %opts);
    }

    my $cb = pop;
    splice @_, 1, 0, $cb;
    return @_;
}


=head2 connect

Connects to L<tarantool:http://tarantool.org>, returns (by callback)
object that can be used to make requests.

    DR::Tarantool::AsyncClient->connect(
        host                => $host,
        port                => $port,
        spaces              => $spaces,
        reconnect_period    => 0.5,
        reconnect_always    => 1,
        sub {
            my ($obj) = @_;
            if (ref $obj) {
                ... # handle errors
            }
            ...
        }
    );

=head3 Arguments

=over

=item host & port

Address where tarantool is started.

=item spaces

A hash with spaces description or L<DR::Tarantool::Spaces> reference.

=item reconnect_period & reconnect_always

See L<DR::Tarantool::LLClient> for more details.

=back

=cut

sub connect {
    my $class = shift;
    my ($cb, %opts);
    if ( @_ % 2 ) {
        $cb = pop;
        %opts = @_;
    } else {
        %opts = @_;
        $cb = delete $opts{cb};
    }

    $class->_llc->_check_cb( $cb );

    my $host = $opts{host} || 'localhost';
    my $port = $opts{port} or croak "port isn't defined";

    my $spaces = blessed($opts{spaces}) ?
        $opts{spaces} : DR::Tarantool::Spaces->new($opts{spaces});
    my $reconnect_period    = $opts{reconnect_period} || 0;
    my $reconnect_always    = $opts{reconnect_always} || 0;

    DR::Tarantool::LLClient->connect(
        host                => $host,
        port                => $port,
        reconnect_period    => $reconnect_period,
        reconnect_always    => $reconnect_always,
        sub {
            my ($client) = @_;
            my $self;
            if (ref $client) {
                $self = bless {
                    llc     => $client,
                    spaces  => $spaces,
                } => ref($class) || $class;
            } else {
                $self = $client;
            }

            $cb->( $self );
        }
    );

    return;

}

=head1 Attributes

=head2 space

Returns space object by name (or by number). See perldoc
L<DR::Tarantool::Spaces> for more details.

=cut

sub space {
    my ($self, $name) = @_;
    return $self->{spaces}->space($name);
}


sub disconnect {
    my ($self, $cb) = @_;
    $self->_llc->disconnect( $cb );
}


sub _llc { return $_[0]{llc} if ref $_[0]; return 'DR::Tarantool::LLClient' }

sub _cb_default {
    my ($res, $s, $cb) = @_;
    if ($res->{status} ne 'ok') {
        $cb->($res->{status} => $res->{code}, $res->{errstr});
        return;
    }

    if ($s) {
        $cb->( ok => DR::Tarantool::Tuple->unpack( $res->{tuples}, $s ) );
    } else {
        $cb->( 'ok' );
    }
    return;
}


=head1 Worker methods

All methods receive callbacks that will receive the following arguments:

=over

=item status

If success the field will have value 'B<ok>'.

=item tuple(s) or code of error

If success, the second argument will contain tuple(s) that extracted by
request.

=item errorstr

Error string if error was happened.

=back


    sub {
        if ($_[0] eq 'ok') {
            my ($status, $tuples) = @_;
            ...
        } else {
            my ($status, $code, $errstr) = @_;
        }
    }


=head2 ping

Pings server.

    $client->ping(sub { ... });

=head3 Arguments

=over

=item cb

=back

=cut

sub ping {
    my ($self, $cb, %opts) = &_split_args;
    $self->_llc->ping(sub { _cb_default($_[0], undef, $cb) });
}



=head2 insert

Inserts tuple into database.

    $client->insert('space', [ 'user', 10, 'password' ], sub { ... });
    $client->insert('space', \@tuple, $flags, sub { ... });


=head3 Arguments

=over

=item space_name

=item tuple

=item flags (optional)

Flag list described in perldoc L<DR::Tarantool/:constant>.

=item callback

=back

=cut

sub insert {
    my $self = shift;
    $self->_llc->_check_cb( my $cb = pop );
    my $space = shift;
    $self->_llc->_check_tuple( my $tuple = shift );
    my $flags = pop || 0;

    my $s = $self->{spaces}->space($space);

    $self->_llc->insert(
        $s->number,
        $s->pack_tuple( $tuple ),
        $flags,
        sub {
            my ($res) = @_;
            _cb_default($res, $s, $cb);
        }
    );
    return;
}


=head2 call_lua

Calls lua function. All arguments translates to lua as strings (As is).
Returned tuples can be unpacked by space or by format.


    $client->call_lua(foo => ['arg1', 'arg2'], sub {  });
    $client->call_lua(foo => [], 'space_name', sub { ... });
    $client->call_lua(foo => \@args,
        flags => $f,
        space => $space_name,
        sub { ... }
    );
    $client->call_lua(foo => \@args,
        fields => [ qw(a b c) ],
        sub { ... }
    );
    $client->call_lua(foo => \@args,
        fields => [ qw(a b c), { type => 'NUM', name => 'abc'} ... ],
        sub { ... }
    );

=head3 Arguments

=over

=item function name

=item function arguments

=item space name or the other optional arguments

=item callback

=back

=head4 Optional arguments

=over

=item space

Space name. Use the argument if Your function returns tuple(s) from a
described in L<connect> space.

=item fields

Output fields format (like 'B<fields>' in L<connect> method).

=item flags

Reserved option.

=item args

Argument fields format.

=back

=cut

sub call_lua {
    my $self = shift;
    my $lua_name = shift;
    my $args = shift;
    $self->_llc->_check_cb( my $cb = pop );

    unshift @_ => 'space' if @_ == 1;
    my %opts = @_;

    my $flags = $opts{flags} || 0;
    my $space_name = $opts{space};
    my $fields = $opts{fields};

    my $s;
    croak "You can't use 'fields' and 'space' at the same time"
        if $fields and $space_name;

    if ($space_name) {
        $s = $self->space( $space_name );
    } elsif ( $fields ) {
        $s = DR::Tarantool::Space->new(
            0 =>
            {
                name    => 'temp_space',
                fields  => $fields,
                indexes => {}
            },
        );
    }

    if ($opts{args}) {
        my $sa = DR::Tarantool::Space->new(
            0 =>
            {
                name    => 'temp_space_args',
                fields  => $opts{args},
                indexes => {}
            },
        );
        $args = $sa->pack_tuple( $args );
    }

    $self->_llc->call_lua(
        $lua_name,
        $args,
        $flags,
        sub { _cb_default($_[0], $s, $cb) }
    );
}


=head2 select

Selects tuple(s) from database.

    $tuples = $client->select('space', 1, sub { ... });
    $tuples = $client->select('space', [1, 2], sub { ... });

    $tuples = $client->select('space_name',
            [1,2,3] => 'index_name', sub { ... });

=head3 Arguments

=over

=item space name

=item key(s)

=item optional arguments

=item callback

=back

=head3 optional arguments

The section can contain only one element: index name, or hash with the
following fields:

=over

=item index

index name or number

=item limit

=item offset

=back

=cut

sub select {
    my $self = shift;
    my $space = shift;
    my $keys = shift;

    my $cb = pop;

    my ($index, $limit, $offset);

    if (@_ == 1) {
        $index = shift;
    } elsif (@_ == 3) {
        ($index, $limit, $offset) = @_;
    } elsif (@_) {
        my %opts = @_;
        $index = $opts{index};
        $limit = $opts{limit};
        $offset = $opts{offset};
    }

    $index ||= 0;

    my $s = $self->space($space);

    $self->_llc->select(
        $s->number,
        $s->_index( $index )->{no},
        $s->pack_keys( $keys, $index ),
        $limit,
        $offset,

        sub { _cb_default($_[0], $s, $cb) }
    );
}


=head2 delete

Deletes tuple.

    $client->delete('space', 1, sub { ... });
    $client->delete('space', $key, $flags, sub { ... });

=head3 Arguments

=over

=item space name

=item key

=item flags (optional)

Flag list described in perldoc L<DR::Tarantool/:constant>.

=item callback

=back

=cut

sub delete :method {
    my $self = shift;
    my $space = shift;
    my $key = shift;
    $self->_llc->_check_cb( my $cb = pop );
    my $flags = shift || 0;

    my $s = $self->space($space);

    $self->_llc->delete(
        $s->number,
        $s->pack_key( $key ),
        $flags,
        sub { _cb_default($_[0], $s, $cb) }
    );
}


=head2 update

Updates tuple.

    $client->update('space', 1, [ passwd => set => 'abc' ], sub { .. });
    $client->update(
        'space',
        1,
        [ [ passwd => set => 'abc' ], [ login => 'delete' ] ],
        sub { ... }
    );

=head3 Arguments

=over

=item space name

=item key

=item operations list

=item flags (optional)

Flag list described in perldoc L<DR::Tarantool/:constant>.

=item callback

=back

=cut

sub update {
    my $self = shift;
    my $space = shift;
    my $key = shift;
    my $op = shift;
    $self->_llc->_check_cb( my $cb = pop );
    my $flags = shift || 0;

    my $s = $self->space($space);

    $self->_llc->update(
        $s->number,
        $s->pack_key( $key ),
        $s->pack_operations( $op ),
        $flags,
        sub { _cb_default($_[0], $s, $cb) }
    );
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
