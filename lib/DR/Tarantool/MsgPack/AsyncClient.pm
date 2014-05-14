use utf8;
use strict;
use warnings;

package DR::Tarantool::MsgPack::AsyncClient;
use DR::Tarantool::MsgPack::LLClient;
use DR::Tarantool::Spaces;
use DR::Tarantool::Tuple;
use Carp;
$Carp::Internal{ (__PACKAGE__) }++;
use Scalar::Util ();
use Data::Dumper;

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

    my $user        = delete $opts{user};
    my $password    = delete $opts{password};

    my $spaces = Scalar::Util::blessed($opts{spaces}) ?
        $opts{spaces} : DR::Tarantool::Spaces->new($opts{spaces});
    $spaces->family(2);

    my $reconnect_period    = $opts{reconnect_period} || 0;
    my $reconnect_always    = $opts{reconnect_always} || 0;

    DR::Tarantool::MsgPack::LLClient->connect(
        host                => $host,
        port                => $port,
        user                => $user,
        password            => $password,
        reconnect_period    => $reconnect_period,
        reconnect_always    => $reconnect_always,
        sub {
            my ($client) = @_;
            my $self;
            if (ref $client) {
                $self = bless {
                    llc         => $client,
                    spaces      => $spaces,
                } => ref($class) || $class;
            } else {
                $self = $client;
            }

            $cb->( $self );
        }
    );

    return;
}

sub _llc { return $_[0]{llc} if ref $_[0]; 'DR::Tarantool::MsgPack::LLClient' }


sub _cb_default {
    my ($res, $s, $cb) = @_;
    if ($res->{status} ne 'ok') {
        $cb->($res->{status} => $res->{CODE}, $res->{ERROR});
        return;
    }

    if ($s) {
        $cb->(ok => $s->tuple_class->unpack( $res->{DATA}, $s ), $res->{CODE});
        return;
    }

    unless ('ARRAY' eq ref $res->{DATA}) {
        $cb->(ok => $res->{DATA}, $res->{CODE});
        return;
    }

    unless (@{ $res->{DATA} }) {
        $cb->(ok => undef, $res->{CODE});
        return;
    }
    $cb->(ok => DR::Tarantool::Tuple->new($res->{DATA}), $res->{CODE});
    return;
}

sub ping {
    my $self = shift;
    my $cb = pop;

    $self->_llc->_check_cb( $cb );
    $self->_llc->ping(sub { _cb_default($_[0], undef, $cb) });
}

sub insert {
    my $self = shift;
    my $cb = pop;
    $self->_llc->_check_cb( $cb );
    my $space = shift;
    my $tuple = shift;
    $self->_llc->_check_tuple( $tuple );


    my $sno;
    my $s;

    if (Scalar::Util::looks_like_number $space) {
        $sno = $space;
    } else {
        $s = $self->{spaces}->space($space);
        $sno = $s->number,
        $tuple = $s->pack_tuple( $tuple );
    }

    $self->_llc->insert(
        $sno,
        $tuple,
        sub {
            my ($res) = @_;
            _cb_default($res, $s, $cb);
        }
    );
    return;
}

sub replace {
    my $self = shift;
    my $cb = pop;
    $self->_llc->_check_cb( $cb );
    my $space = shift;
    my $tuple = shift;
    $self->_llc->_check_tuple( $tuple );


    my $sno;
    my $s;

    if (Scalar::Util::looks_like_number $space) {
        $sno = $space;
    } else {
        $s = $self->{spaces}->space($space);
        $sno = $s->number,
        $tuple = $s->pack_tuple( $tuple );
    }

    $self->_llc->replace(
        $sno,
        $tuple,
        sub {
            my ($res) = @_;
            _cb_default($res, $s, $cb);
        }
    );
    return;
}

sub delete :method {
    my $self = shift;
    my $cb = pop;
    $self->_llc->_check_cb( $cb );
    
    my $space = shift;
    my $key = shift;


    my $sno;
    my $s;

    if (Scalar::Util::looks_like_number $space) {
        $sno = $space;
    } else {
        $s = $self->{spaces}->space($space);
        $sno = $s->number;
    }

    $self->_llc->delete(
        $sno,
        $key,
        sub {
            my ($res) = @_;
            _cb_default($res, $s, $cb);
        }
    );
    return;
}

sub select :method {
    my $self = shift;
    my $cb = pop;
    $self->_llc->_check_cb( $cb );
    my $space = shift;
    my $index = shift;
    my $key = shift;
    my %opts = @_;

    my $sno;
    my $ino;
    my $s;
    if (Scalar::Util::looks_like_number $space) {
        $sno = $space;
        croak 'If space is number, index must be number too'
            unless Scalar::Util::looks_like_number $index;
        $ino = $index;
    } else {
        $s = $self->{spaces}->space($space);
        $sno = $s->number;
        $ino = $s->_index( $index )->{no};
    }
    $self->_llc->select(
        $sno,
        $ino,
        $key,
        $opts{limit},
        $opts{offset},
        $opts{iterator},
        sub {
            my ($res) = @_;
            _cb_default($res, $s, $cb);
        }
    );
}

sub update :method {
    my $self = shift;
    my $cb = pop;
    $self->_llc->_check_cb( $cb );
    my $space = shift;
    my $key = shift;
    my $ops = shift;

    my $sno;
    my $s;
    if (Scalar::Util::looks_like_number $space) {
        $sno = $space;
    } else {
        $s = $self->{spaces}->space($space);
        $sno = $s->number;
        $ops = $s->pack_operations($ops);
    }
    $self->_llc->update(
        $sno,
        $key,
        $ops,
        sub {
            my ($res) = @_;
            _cb_default($res, $s, $cb);
        }
    );
}

1;
