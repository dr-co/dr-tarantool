use utf8;
use strict;
use warnings;

package DR::Tarantool::MsgPack::LLClient;
use Carp;
use base qw(DR::Tarantool::LLClient);
use DR::Tarantool::MsgPack::Proto;
use Data::Dumper;

sub connect {
    my ($class, %opts) = @_;

    $class->_check_cb( my $cb = $opts{cb} || sub {  } );
    my $user        = delete $opts{user};
    my $password    = delete $opts{password};

    $class->SUPER::connect(
        %opts,

        cb => sub {
            my ($tnt) = @_;
            if (ref $tnt) {
                if (defined $user and defined $password) {
                    $tnt->{user}        = $user;
                    $tnt->{password}    = $password;
                }
                $tnt->{handshake}   = 1;
                $tnt->{_connect_cb} = $cb;
                return;
            }

            $cb->( $tnt );
        }
    );
}


sub _check_rbuf {
    my ($self) = @_;
    if ($self->{handshake}) {
        return unless length $self->{rbuf} >= 128;
        my $handshake = substr $self->{rbuf}, 0, 128, '';

        eval {
            ($self->{tnt_version}, $self->{tnt_salt}) =
                DR::Tarantool::MsgPack::Proto::handshake($handshake)
        };
        if ($@) {
            if (my $cb = delete $self->{_connect_cb}) {
                $cb->('Broken handshake');
            } else {
                $self->_fatal_error('Broken handshake');
            }
            return;
        }
        $self->{handshake} = 0;

        if (my $cb = delete $self->{_connect_cb}) {{
            unless (defined $self->{user} and defined $self->{password}) {
                $cb->($self);
                last;
            }
            $self->auth(sub {
                my ($r) = @_;
                if ('HASH' eq ref $r) {
                    warn $r->{ERROR} unless $r->{CODE} == 0;
                    $cb->($self);
                } else {
                    $cb->($r);
                }
            });
        }}
    }

    # usual receive
    while(1) {
        my ($resp, $tail) = eval {
            DR::Tarantool::MsgPack::Proto::response $self->{rbuf};

        };
        if ($@) {
            $self->_fatal_error('Broken response');
            return;
        }

        return unless $resp;
        $self->{rbuf} = $tail;

        my $id = $resp->{SYNC};
        my $cb = delete $self->{ wait }{ $id };
        if ('CODE' eq ref $cb) {
            $cb->( $resp );
        } else {
            warn "Unexpected reply from tarantool with id = $id";
        }

    }
}


sub _fatal_error {
    my ($self, @args) = @_;
    $self->{handshake} = 1;
    delete $self->{tnt_salt};
    return $self->SUPER::_fatal_error(@args);
}

sub ping {
    my ($self, $cb) = @_;
    $self->_check_cb( $cb );

    my $id = $self->_req_id;
    my $pkt = DR::Tarantool::MsgPack::Proto::ping($id);

    $self->_request($id, $pkt, $cb);
    return;
}


sub call_lua {
    my $self = shift;
    my $proc = shift;
    $self->_check_cb( my $cb = pop );
    my $tuple;
    if (@_) {
        $self->_check_tuple($tuple = shift);
    } else {
        $tuple = [];
    }

    my $id = $self->_req_id;
    my $pkt = DR::Tarantool::MsgPack::Proto::call_lua($id, $proc, $tuple);
    $self->_request($id, $pkt, $cb);
    return;
}


sub auth {
    my $self = shift;
    my $cb = pop;
    ($self->{user}, $self->{password}) = @_ if @_ == 2;
    $self->_check_cb($cb);
    
    croak "user and password must be defined"
        unless defined $self->{user} and defined $self->{password};

    croak "salt is not received yet" unless $self->{tnt_salt};
    
    my $id = $self->_req_id;
    my $pkt = DR::Tarantool::MsgPack::Proto::auth(
        $id, $self->{user}, $self->{password}, $self->{tnt_salt});
    $self->_request($id, $pkt, $cb);
    return;
}


sub _request {
    my ($self, $id, $pkt, $cb) = @_;
    return $self->SUPER::_request($id, $pkt, $cb);
}





1;
