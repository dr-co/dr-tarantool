use utf8;
use strict;
use warnings;


package DR::Tarantool::LLClient;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Carp;

use Scalar::Util 'weaken';
require DR::Tarantool;
use Data::Dumper;

our $req_id;
our %requests;

=head2 tnt_connect

Creates a connection to L<tarantool | http://tarantool.org>

=head3 arguments

=over

=item host & port

Host and port to connect.

=item cb

Done callback.

=back

=cut

sub tnt_connect {
    my ($class, %opts) = @_;

    my $cb = $opts{cb};
    croak "done callback is undefined" unless 'CODE' eq ref $cb;

    my $host = $opts{host} || 'localhost';
    my $port = $opts{port} or croak "port is undefined";

    tcp_connect $host, $port, sub {
        my ($fh) = @_;
        unless ( $fh ) {
            $cb->( $! );
            return;
        }

        my $driver = bless {
            host        => $host,
            port        => $port,
        } => ref($class) || $class;

        my $self = $driver;
        weaken $self;

        $self->{handle} = AnyEvent::Handle->new(
            fh          => $fh,
            on_error    => $self->socket_error,
        );

        $cb->( $self );

        $self->{handle}->push_read( chunk => 12, $self->_read_header );
        return;

    };
    return;
}




sub socket_error {
    my ($self) = @_;
    return sub {

    }
}




sub ping :method {
    my ($self, $cb) = @_;
    my $id = $self->_req_id;
    my $pkt = DR::Tarantool::_pkt_ping( $id );
    $self->_request( $id, $pkt, $cb );
    return;
}

sub insert :method {
    my ($self, $space, $flags, $tuple, $cb) = @_;
    croak "insert: tuple must be ARRAYREF" unless ref $tuple eq 'ARRAY';
    croak "insert: callback isn't defined" unless ref $cb eq 'CODE';
    $flags ||= 0;

    my $id = $self->_req_id;
    my $pkt = DR::Tarantool::_pkt_insert( $id, $space, $flags, $tuple );
    $self->_request( $id, $pkt, $cb );
    return;
}

sub select :method {
    my ($self, $ns, $idx, $offset, $limit, $keys, $cb ) = @_;

    my $id = $self->_req_id;
    my $pkt =
        DR::Tarantool::_pkt_select($id, $ns, $idx, $offset, $limit, $keys);
    $self->_request( $id, $pkt, $cb );
    return;
}

sub update :method {
    my ($self, $ns, $flags, $tuple, $ops, $cb) = @_;

    my $id = $self->_req_id;
    my $pkt = DR::Tarantool::_pkt_update($id, $ns, $flags, $tuple, $ops);
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
    $self->{ wait }{ $id } = $cb;
    $self->{handle}->push_write( $pkt );
}

sub _req_id {
    return $req_id = 0 unless defined $req_id;
    return ++$req_id;
}

1;
