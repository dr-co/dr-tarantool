use utf8;
use strict;
use warnings;

=head1 NAME

DR::Tarantool::LLClient - low level async client
for L<tarantool | http://tarantool.org>

=head1 SYNOPSIS

    DR::Tarantool::LLClient->connect(
        host => '127.0.0.1',
        port => '33033',
        cb   => {
            my ($tnt) = @_;
            ...
        }
    );

    $tnt->ping( sub { .. } );
    $tnt->insert(0, [ 1, 2, 3 ], sub { ... });
    $tnt->select(1, 0, [ [ 1, 2 ], [ 3, 4 ] ], sub { ... });
    $tnt->update(0, [ 1 ], [ [ 1 => add 1 ] ], sub { ... });
    $tnt->call_lua( 'box.select', [ 0, 1, 2 ], sub { ... });


=head1 DESCRIPTION

The module provides low-level interface to L<tarantool | http://tarantool.org>

=head1 METHODS

All methods receives B<callback> as the last argument. The callback receives
B<HASHREF> value with the following fields:

=over

=item status

Done status:

=over

=item fatal

Fatal error was happenned. Server closed connection or returned broken package.

=item buffer

Internal driver error.

=item error

Request wasn't done: database returned error.

=item ok

Request was done.

=back

=item errstr

If an error was happenned contains error description.

=item code

Contains reply code.

=item req_id

Contains request id.
(see L<protocol documentation|
https://github.com/mailru/tarantool/blob/master/doc/box-protocol.txt
>)

=item type

Contains request type
(see L<protocol documentation|
https://github.com/mailru/tarantool/blob/master/doc/box-protocol.txt
>)

=item count

Contains count of returned tuples.

=item tuples

Contains returned tuples (B<ARRAYREF> of B<ARRAYREF>).

=back

If You use B<NUM> or B<NUM64> values in database You have to pack them before
requests and unpack them after response by hand. This is low-level driver :).

=cut


package DR::Tarantool::LLClient;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Carp;
$Carp::Internal{ (__PACKAGE__) }++;

use Scalar::Util 'weaken';
require DR::Tarantool;
use Data::Dumper;

our $req_id;
our %requests;



=head2 connect

Creates a connection to L<tarantool | http://tarantool.org>

    DR::Tarantool::LLClient->connect(
        host => '127.0.0.1',
        port => '33033',
        cb   => {
            my ($tnt) = @_;
            ...
        }
    );

=head3 Arguments

=over

=item host & port

Host and port to connect.

=item reconnect_period

Interval to reconnect after fatal errors or unsuccessful connects.
If the field is defined and more than zero driver will try to
reconnect server using this interval.

B<Important>: driver wont reconnect after B<the first> unsuccessful connection.
It will call B<callback> instead.

=item reconnect_always

Constantly trying to reconnect even after the first unsuccessful connection.

=item cb

Done callback. The callback will receive a client instance that
is already connected with server or error string.

=back

=cut

sub connect {
    my $class = shift;

    my (%opts, $cb);

    if (@_ % 2) {
        $cb = pop;
        %opts = @_;
    } else {
        %opts = @_;
        $cb = delete $opts{cb};
    }

    $class->_check_cb( $cb || sub {  });

    my $host = $opts{host} || 'localhost';
    my $port = $opts{port} or croak "port is undefined";

    my $reconnect_period    = $opts{reconnect_period} || 0;
    my $reconnect_always    = $opts{reconnect_always} || 0;

    my $self = bless {
        host                => $host,
        port                => $port,
        reconnect_period    => $reconnect_period,
        reconnect_always    => $reconnect_always,
        first_connect       => 1,
        connection_status   => 'not_connected',
    } => ref($class) || $class;

    $self->_connect_reconnect( $cb );

    return $self;
}

sub disconnect {
    my ($self, $cb) = @_;
    $self->_check_cb( $cb || sub {  });

    delete $self->{reconnect_timer};
    delete $self->{connecting};
    if ($self->is_connected) {
        $self->{handle}->on_error( sub {  } );
        $self->{handle}->on_error( sub {  } );
        $self->{handle}->destroy;
        delete $self->{handle};
    }
    $cb->( 'ok' );
}

sub DESTROY {
    my ($self) = @_;
    if ($self->is_connected) {
        $self->{handle}->destroy;
        $self->{handle}->on_error( sub {  });
        $self->{handle}->on_eof( sub {  });
        delete $self->{handle};
    }
}

=head2 is_connected

Returns B<TRUE> if driver and server are connected with.

=cut

sub is_connected {
    my ($self) = @_;
    return $self->{handle} ? 1 : 0;
}

=head2 connection_status

Returns string that informs You about status of connection. Return value can be:

=over

=item ok

Connection is established

=item not_connected

Connection isn't established yet, or was disconnected.

=item connecting

Driver tries connecting server

=item fatal

Driver tried connecting but receives an error. Driver can repeat connecting
processes (see B<reconnect_period> option).

=back

=cut

sub connection_status {
    my ($self) = @_;
    $self->{connection_status} || 'unknown';
}


=head2 ping

Pings tarantool.

    $tnt->ping( sub { .. } );

=head3 Arguments

=over

=item callback for results

=back

=cut

sub ping :method {
    my ($self, $cb) = @_;
    $self->_check_cb( $cb );
    my $id = $self->_req_id;
    my $pkt = DR::Tarantool::_pkt_ping( $id );
    $self->_request( $id, $pkt, $cb );
    return;
}


=head2 insert

Inserts tuple.

    $tnt->insert(0, [ 1, 2, 3 ], sub { ... });
    $tnt->insert(0, [ 4, 5, 6 ], $flags, sub { .. });

=head3 Arguments

=over

=item space

=item tuple

=item flags (optional)

=item callback for results

=back


=cut

sub insert :method {

    my $self = shift;
    $self->_check_number(   my $space = shift       );
    $self->_check_tuple(    my $tuple = shift       );
    $self->_check_cb(       my $cb = pop            );
    $self->_check_number(   my $flags = pop || 0    );
    croak "insert: tuple must be ARRAYREF" unless ref $tuple eq 'ARRAY';
    $flags ||= 0;

    my $id = $self->_req_id;
    my $pkt = DR::Tarantool::_pkt_insert( $id, $space, $flags, $tuple );
    $self->_request( $id, $pkt, $cb );
    return;
}

=head2 select

Selects tuple(s).

    $tnt->select(1, 0, [ [ 1, 2 ], [ 3, 4 ] ], sub { ... });
    $tnt->select(1, 0, [ [ 1, 2 ], [ 3, 4 ] ], 1, sub { ... });
    $tnt->select(1, 0, [ [ 1, 2 ], [ 3, 4 ] ], 1, 2, sub { ... });

=head3 Arguments

=over

=item space

=item index

=item tuple_keys

=item limit (optional)

If limit isn't defined or zero select will extract all records without limit.

=item offset (optional)

Default value is B<0>.

=item callback for results

=back

=cut

sub select :method {

    my $self = shift;
    $self->_check_number(       my $ns = shift                  );
    $self->_check_number(       my $idx = shift                 );
    $self->_check_tuple_list(   my $keys = shift                );
    $self->_check_cb(           my $cb = pop                    );
    $self->_check_number(       my $limit = shift || 0x7FFFFFFF );
    $self->_check_number(       my $offset = shift || 0         );

    my $id = $self->_req_id;
    my $pkt =
        DR::Tarantool::_pkt_select($id, $ns, $idx, $offset, $limit, $keys);
    $self->_request( $id, $pkt, $cb );
    return;
}

=head2 update

Updates tuple.

    $tnt->update(0, [ 1 ], [ [ 1 => add 1 ] ], sub { ... });
    $tnt->update(
        0,                                      # space
        [ 1 ],                                  # key
        [ [ 1 => add 1 ], [ 2 => add => 1 ],    # operations
        $flags,                                 # flags
        sub { ... }                             # callback
    );
    $tnt->update(0, [ 1 ], [ [ 1 => add 1 ] ], $flags, sub { ... });

=head3 Arguments

=over

=item space

=item tuple_key

=item operations list

=item flags (optional)

=item callback for results

=back


=cut

sub update :method {

    my $self = shift;
    $self->_check_number(           my $ns = shift          );
    $self->_check_tuple(            my $key = shift         );
    $self->_check_operations(       my $operations = shift  );
    $self->_check_cb(               my $cb = pop            );
    $self->_check_number(           my $flags = pop || 0    );

    my $id = $self->_req_id;
    my $pkt = DR::Tarantool::_pkt_update($id, $ns, $flags, $key, $operations);
    $self->_request( $id, $pkt, $cb );
    return;

}

=head2 delete

Deletes tuple.

    $tnt->delete( 0, [ 1 ], sub { ... });
    $tnt->delete( 0, [ 1 ], $flags, sub { ... });

=head3 Arguments

=over

=item space

=item tuple_key

=item flags (optional)

=item callback for results

=back

=cut

sub delete :method {
    my $self = shift;
    my $ns = shift;
    my $key = shift;
    $self->_check_tuple( $key );
    my $cb = pop;
    $self->_check_cb( $cb );
    my $flags = pop || 0;

    my $id = $self->_req_id;
    my $pkt = DR::Tarantool::_pkt_delete($id, $ns, $flags, $key);
    $self->_request( $id, $pkt, $cb );
    return;
}


=head2 call_lua

calls lua function.

    $tnt->call_lua( 'box.select', [ 0, 1, 2 ], sub { ... });
    $tnt->call_lua( 'box.select', [ 0, 1, 2 ], $flags, sub { ... });

=head3 Arguments

=over

=item name of function

=item tuple_key

=item flags (optional)

=item callback for results

=back

=cut

sub call_lua :method {

    my $self = shift;
    my $proc = shift;
    my $tuple = shift;
    $self->_check_tuple( $tuple );
    my $cb = pop;
    $self->_check_cb( $cb );
    my $flags = pop || 0;

    my $id = $self->_req_id;
    my $pkt = DR::Tarantool::_pkt_call_lua($id, $flags, $proc, $tuple);
    $self->_request( $id, $pkt, $cb );
    return;
}


sub _read_header {
    my ($self) = @_;
    return sub {
        my (undef, $data) = @_;
        croak "Unexpected data length" unless $data and length $data == 12;
        my (undef, $blen ) = unpack 'L< L<', $data;

        $self->{handle}->push_read( chunk => $blen, $self->_read_reply($data) );
    }
}

sub _read_reply {
    my ($self, $hdr) = @_;

    return sub {
        my (undef, $data) = @_;
        my $res = DR::Tarantool::_pkt_parse_response( $hdr . $data );


        if ($res->{status} =~ /^(fatal|buffer)$/) {
            $self->_fatal_error( $res->{errstr} );
            return;
        }

#       write responses as binfile for tests
#         {
#             my $sname = sprintf 't/test-data/%05d-%03d-%s.bin',
#                 $res->{type} || 0, $res->{code}, $res->{status};
#             open my $fh, '>:raw', $sname;
#             print $fh $hdr;
#             print $fh $data;
#         }


        my $id = $res->{req_id};
        my $cb = delete $self->{ wait }{ $id };
        if ('CODE' eq ref $cb) {
            $cb->( $res );
        } else {
            warn "Unexpected reply from tarantool with id = $id";
        }

        $self->{handle}->push_read(chunk => 12, $self->_read_header);
    }
}


sub _request {
    my ($self, $id, $pkt, $cb ) = @_;

    unless($self->{handle}) {
        $cb->({
            status  => 'fatal',
            errstr  => "Connection isn't established"
        });
        return;
    }
    $self->{ wait }{ $id } = $cb;
    $self->{handle}->push_write( $pkt );
}

sub _req_id {
    return $req_id = 0 unless defined $req_id;
    return ++$req_id;
}

sub _fatal_error {
    my ($self, $msg) = @_;
    for (keys %{ $self->{ wait } }) {
        my $cb = delete $self->{ wait }{ $_ };
        $cb->({ status  => 'fatal',  errstr  => $msg, req_id => $_ });
    }

    undef $self->{handle};
    $self->{connection_status} = 'not_connected',
    $self->_connect_reconnect;
}

sub _connect_reconnect {

    my ($self, $cb) = @_;

    $self->_check_cb( $cb ) if $cb;
    return if $self->{reconnect_timer};
    return if $self->{connecting};
    return unless $self->{first_connect} or $self->{reconnect_period};

    $self->{reconnect_timer} = AE::timer
        $self->{first_connect} ? 0 : $self->{reconnect_period},
        $self->{reconnect_period} || 0,
        sub {
            return if $self->{connecting};
            $self->{connecting} = 1;

            $self->{connection_status} = 'connecting';

            tcp_connect $self->{host}, $self->{port}, sub {
                my ($fh) = @_;
                delete $self->{connecting};
                if ($fh) {
                    $self->{handle} = AnyEvent::Handle->new(
                        fh          => $fh,
                        on_error    => $self->_socket_error,
                        on_eof      => $self->_socket_eof,
                    );
                    $self->{handle}->push_read(
                        chunk => 12, $self->_read_header
                    );

                    delete $self->{reconnect_timer};
                    delete $self->{first_connect};
                    $self->{connection_status} = 'ok';

                    $cb->( $self ) if $cb;
                    return;
                }

                my $emsg = $!;
                if ($self->{first_connect} and not $self->{reconnect_always}) {
                    $cb->( $! ) if $cb;
                    delete $self->{reconnect_timer};
                    delete $self->{connecting};
                }
                $self->{connection_status} = "Couldn't connect to server: $!";
            };
        }
    ;
}


sub _socket_error {
    my ($self) = @_;
    return sub {
        my (undef, $fatal, $msg) = @_;
        $self->_fatal_error("Socket error: $msg");

    }
}

sub _socket_eof {
    my ($self) = @_;
    return sub {
        $self->_fatal_error("Socket error: Server closed connection");
    }
}


sub _check_cb {
    my ($self, $cb) = @_;
    croak 'Callback must be CODEREF' unless 'CODE' eq ref $cb;
}

sub _check_tuple {
    my ($self, $tuple) = @_;
    croak 'Tuple must be ARRAYREF' unless 'ARRAY' eq ref $tuple;
}

sub _check_tuple_list {
    my ($self, $list) = @_;
    croak 'Tuplelist must be ARRAYREF of ARRAYREF' unless 'ARRAY' eq ref $list;
    croak 'Tuplelist is empty' unless @$list;
    $self->_check_tuple($_) for @$list;
}

sub _check_number {
    my ($self, $number) = @_;
    croak "argument must be number" unless $number ~~ /^\d+$/;
}


sub _check_operation {
    my ($self, $op) = @_;
    croak 'Operation must be ARRAYREF' unless 'ARRAY' eq ref $op;
    croak 'Wrong update operation: too short arglist' unless @$op >= 2;
    croak "Wrong operation: $op->[1]"
        unless $op->[1] ~~ /^(delete|set|insert|add|and|or|xor|substr)$/;
    $self->_check_number($op->[0]);
}

sub _check_operations {
    my ($self, $list) = @_;
    croak 'Operations list must be ARRAYREF of ARRAYREF'
        unless 'ARRAY' eq ref $list;
    croak 'Operations list is empty' unless @$list;
    $self->_check_operation( $_ ) for @$list;
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
